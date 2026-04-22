-------------------------------------------------------------------------------
-- СПЕЦИФИКАЦИЯ ФАЙЛА
-------------------------------------------------------------------------------
-- Этот скрипт отвечает за реализацию алгоритма Token Bucket (маркерная корзина) для Rate Limiter'а,
-- выполняемую прямо внутри Redis с помощью Lua.
-- Выполнение внутри Redis гарантирует атомарность операций (никто не сможет изменить
-- данные между чтением и записью) и высокую производительность.
--
-- Описание функционала файла acquire.lua
-- 1. Атомарный захват по нескольким лимитам ("Всё или ничего"):
--   Скрипт принимает список ключей (лимитов) и запрошенное количество токенов.
--   Он проверяет, есть ли нужное количество токенов во всех переданных лимитах одновременно.
-- 2. Ленивое пополнение (Lazy Refill): Токены не пополняются каким-то фоновым процессом.
--   Вместо этого при каждом обращении (в функции Limit:update) вычисляется разница во времени
--   с момента последнего обращения (current_time - self.last_used) и добавляется количество токенов, пропорциональное скорости rate.
-- 3. Проверка условий (Validation):
--    - Если запрашивается <= 0 токенов или передан пустой список ключей — сразу возвращается ошибка.
--    - Если хотя бы одного ключа не существует в Redis, возвращается key_not_found.
--    - Если хотя бы в одном лимите не хватает токенов, скрипт возвращает ошибку not_limits и ничего не списывает из других лимитов (откат транзакции).
-- 4. Фиксация состояния: Только если проверены и удовлетворены все лимиты, происходит
--   фактическое списание токенов (tokens - requested), сохранение новых значений
--   в Redis (HMSET) и обновление времени жизни ключей (EXPIRE). Возвращается успешный результат.
-------------------------------------------------------------------------------

-- Указываем Redis реплицировать сами эффекты от скрипта (HMSET), а не сам скрипт.
-- Это необходимо для использования команды TIME внутри скрипта в версиях Redis 3.2 - 5.0.
redis.replicate_commands()

-- Входящие аргументы
-- KEYS: список ключей (имен лимитов)
-- ARGV[1]: запрашиваемое количество токенов (requested) !ЧИСЛО!
-- ARGV[2]: время жизни ключей в секундах (key_ttl)
local limit_keys = KEYS
local requested = tonumber(ARGV[1]) or 0
local key_ttl = tonumber(ARGV[2]) or 0

-- Получаем текущее время сервера (в секундах)
local current_time = redis.call("TIME")[1]

-------------------------------------------------------------------------------
-- ООП обертка для работы с лимитом (Token Bucket)
-------------------------------------------------------------------------------
local Limit = {}
Limit.__index = Limit

-- Инициализация объекта Limit из Redis
function Limit:new(limit_key)
  local obj = { key = limit_key, exists = false }
  setmetatable(obj, self)

  -- Оптимизация: вместо EXISTS + HMGET делаем только HMGET.
  -- Если ключа нет, values[1] будет nil.
  local values = redis.call("HMGET", limit_key,
    "max_tokens",
    "tokens",
    "interval",
    "last_used",
    "rate"
  )

  if not values[1] then
    return obj -- Ключ не существует
  end

  obj.max_tokens = tonumber(values[1]) or 0
  obj.tokens     = tonumber(values[2]) or 0
  obj.interval   = tonumber(values[3]) or 0
  obj.last_used  = tonumber(values[4]) or 0
  obj.rate       = tonumber(values[5]) or 0

  obj.exists     = (obj.max_tokens > 0) and (obj.interval > 0)

  return obj
end

-- "Ленивое" пополнение корзины токенов на основе прошедшего времени
function Limit:update(current_time)
  if not self.exists then return self end

  local time_passed = current_time - self.last_used
  if time_passed <= 0 then return self end

  local tokens_to_add = math.floor(time_passed * self.rate)
  self.tokens = math.min(self.tokens + tokens_to_add, self.max_tokens)

  if tokens_to_add > 0 then
    if self.tokens == self.max_tokens then
      self.last_used = current_time
    else
      local time_consumed = tokens_to_add / self.rate
      self.last_used = math.min(self.last_used + time_consumed, current_time)
    end
  end

  return self
end

-- Сохранение обновленного стейта лимита в Redis
function Limit:save()
  if not self.exists then return end

  redis.call("HMSET", self.key,
    "tokens", self.tokens,
    "last_used", self.last_used
  )
end

-- Проверка, достаточно ли токенов
-- requested - это количество (ЧИСЛО) запрошенных токенов
function Limit:can_acquire(requested)
  return self.exists and self.tokens >= requested
end

-- Списание токенов из памяти объекта (без сохранения в БД)
-- requested - это количество (ЧИСЛО) запрошенных токенов
function Limit:acquire(requested)
  if not self:can_acquire(requested) then return false end
  self.tokens = self.tokens - requested
  return true
end

-------------------------------------------------------------------------------
-- Основная логика обработки всех лимитов
-------------------------------------------------------------------------------
-- requested - это количество (ЧИСЛО) запрошенных токенов
local function process_all_limits(limit_keys, requested, current_time)
  -- Базовые валидации
  if requested <= 0 then
    return { "result", "false", "retryable", "false", "error", "limits not requested" }
  end

  if #limit_keys == 0 then
    return { "result", "false", "retryable", "false", "error", "no keys passed" }
  end

  local limits = {}

  -- Фаза 1: Проверка всех лимитов (Read & Validate)
  for i = 1, #limit_keys do
    local key = limit_keys[i]
    local limit = Limit:new(key)

    if not limit.exists then
      return { "result", "false", "retryable", "false", "error", "key_not_found", "key", key }
    end

    -- Пересчитываем количество токенов на текущий момент
    limit:update(current_time)

    -- Если хотя бы в одном лимите не хватает токенов - прерываем операцию для всех
    if not limit:can_acquire(requested) then
      return {
        "result", "false",
        "retryable", "true",
        "error", "not_limits",
        "tokens_available", limit.tokens,
        "key", key
      }
    end

    table.insert(limits, limit)
  end

  -- Фаза 2: Применение изменений (Write)
  -- Выполняется только если всем лимитам хватило токенов
  for i = 1, #limits do
    local limit = limits[i]
    limit:acquire(requested)
    limit:save()

    -- Продлеваем жизнь ключу, чтобы он не удалился, если к нему активно обращаются.
    -- "GT" обновляет TTL только если новый TTL больше текущего.
    redis.call("EXPIRE", limit.key, key_ttl, "GT")
  end

  return { "result", "true", "keys", limit_keys }
end

return process_all_limits(limit_keys, requested, current_time)
