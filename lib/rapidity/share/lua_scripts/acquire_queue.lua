-------------------------------------------------------------------------------
-- СПЕЦИФИКАЦИЯ ФАЙЛА
-------------------------------------------------------------------------------
-- Этот файл отвечает за захват (списание) мест из семафора/очереди. 
-- Механизм Feedback-Driven Flow Control используется продюсерами (теми, кто генерирует запросы) для понимания, 
-- есть ли свободное "место" в очереди для выполнения задачи, или очередь переполнена, и нужно притормозить (backpressure). 
-- Семафор (в отличие от tokens) не пополняется временем автоматически. Он явно захватывается (acquire)
-- и должен быть так же явно освобожден (release) после завершения задачи (как раз для этого в sender.rb есть метод release_queue).
-- 
-- Описание функционала файла acquire_queue.lua
-- 1. ВАЖНО: Атомарный захват по нескольким лимитам ("Всё или ничего"): 
--   Скрипт принимает список ключей (лимитов) и запрошенное количество мест в семафорах.
--   Он проверяет, есть ли нужное количество мест во всех переданных лимитах одновременно (ЕСЛИ этот механизм вообще включен (max_queue > 0) в лимите!).
--   Проверка существования: Сначала скрипт проверяет, существует ли лимит. Если нет — возвращает ошибку key_not_found.
-- 2. Проверка условий (Validation): 
--    - Пытается взять из ВСЕХ семафоров запрошенное количество мест (requested).
--    - Если в семафорах мест хватает, списывает их полностью.
--    - Если мест меньше, чем запросили (но больше 0) — забирает все оставшиеся, а семафор обнуляет (semaphore = 0).
--    - Если мест вообще нет (semaphore <= 0), возвращает 0 захваченных токенов.
-- 3. Фиксация состояния: Только если проверены и удовлетворены все лимиты, происходит
--   фактическое занятие мест семафоров (semaphore - requested), сохранение новых значений
--   в Redis (HMSET) и обновление времени жизни ключей (EXPIRE). Возвращается успешный результат.
-------------------------------------------------------------------------------

-- Указываем Redis реплицировать сами эффекты от скрипта, а не сам скрипт.
redis.replicate_commands()

-- Входящие аргументы:
-- KEYS : список ключей лимитов в Redis
-- ARGV[1] : запрашиваемое количество токенов из семафора/очереди
-- ARGV[2] : время жизни ключа в секундах (key_ttl)
local keys = KEYS
local requested = tonumber(ARGV[1]) or 0
local key_ttl = tonumber(ARGV[2]) or 0

-------------------------------------------------------------------------------
-- ООП обертка для работы с очередью/семафором лимита
-------------------------------------------------------------------------------
local QueueLimit = {}
QueueLimit.__index = QueueLimit

function QueueLimit:new(key)
  local obj = {
    key = key,
    exists = false,
    max_queue = 0,
    semaphore = 0
  }
  setmetatable(obj, self)

  -- Получаем настройки семафора из Redis одним запросом
  local values = redis.call("HMGET", key, "max_queue", "semaphore")
  if not values[1] then
    return obj -- Ключа не существует
  end

  obj.exists = true
  obj.max_queue = tonumber(values[1]) or 0
  obj.semaphore = tonumber(values[2]) or 0

  return obj
end

-- Проверка, включен ли механизм очереди для этого лимита
function QueueLimit:is_enabled()
  return self.max_queue > 0
end

-- Списание мест из семафора (в памяти, без сохранения)
function QueueLimit:acquire(amount)
  if self:is_enabled() then
    self.semaphore = self.semaphore - amount
  end
end

-- Сохранение обновленного значения семафора в Redis
function QueueLimit:save()
  if self.exists and self:is_enabled() then
    redis.call("HSET", self.key, "semaphore", self.semaphore)
  end
end

-------------------------------------------------------------------------------
-- Основная логика: атомарный захват семафора для списка лимитов ("Всё или ничего")
-------------------------------------------------------------------------------
local function process_all_queues(limit_keys, req_tokens, ttl)
  -- Валидация входных параметров
  if req_tokens <= 0 then
    return {"result", "false", "error", "tokens not requested"}
  end

  if #limit_keys == 0 then
    return {"result", "false", "error", "no keys passed"}
  end

  local limits = {}
  -- bottleneck_tokens - узкое горлышко (максимальное количество мест, которое 
  -- мы сможем безопасно списать из ВСЕХ лимитов одновременно, не уйдя в минус)
  local bottleneck_tokens = req_tokens

  -- Фаза 1: Проверка всех лимитов (Validation)
  for i = 1, #limit_keys do
    local key = limit_keys[i]
    local limit = QueueLimit:new(key)

    if not limit.exists then
      return {"result", "false", "error", "key_not_found", "key", key}
    end

    if limit:is_enabled() then
      if limit.semaphore <= 0 then
        -- Если хотя бы в одном из лимитов мест вообще нет, операция атомарно отклоняется для всех
        return {
          "result", "false", 
          "error", "not_limits", 
          "tokens", 0,
          "key", key
        }
      end
      -- Если мест меньше, чем запросили, то мы сможем выдать только "все оставшиеся" по узкому горлышку
      bottleneck_tokens = math.min(bottleneck_tokens, limit.semaphore)
    end

    table.insert(limits, limit)
  end

  -- Фаза 2: Фиксация состояния (Списание)
  -- Выполняется только если всем лимитам хватило хотя бы 1 места (bottleneck_tokens > 0)
  -- Мы списываем одинаковое количество (bottleneck_tokens) из всех лимитов, 
  -- чтобы не было "потерянных" токенов при возврате (release).
  for i = 1, #limits do
    local limit = limits[i]
    
    limit:acquire(bottleneck_tokens)
    limit:save()
    
    -- Продлеваем жизнь ключу
    -- раньше был GT, но он только с версии 7 (GT - только если новый TTL больше текущего остатка)
    redis.call("EXPIRE", limit.key, ttl)
  end

  -- Возвращаем успешный результат: сколько реально удалось захватить (tokens)
  return {
    "result", "true", 
    "tokens", bottleneck_tokens,
    "keys", limit_keys
  }
end

return process_all_queues(keys, requested, key_ttl)