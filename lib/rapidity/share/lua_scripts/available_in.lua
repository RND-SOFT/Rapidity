-------------------------------------------------------------------------------
-- СПЕЦИФИКАЦИЯ ФАЙЛА
-------------------------------------------------------------------------------
-- Этот файл содержит логику для вычисления времени ожидания (available_in). 
-- Он используется, когда приложение хочет узнать, через сколько секунд в наличии будет нужное количество токенов для выполнения запроса.
--
-- Описание функционала файла available_in.lua
--   1. Проверка всех лимитов сразу: Скрипт принимает список ключей (имен лимитов) и
--     количество запрашиваемых токенов. Он вычисляет, когда это количество токенов станет доступно в каждом из лимитов.
--   2. "Ленивое" вычисление (Lazy Evaluation): Как и в скрипте acquire.lua,
--     сначала симулируется прошедшее с момента последнего использования время (Limit:update),
--     чтобы посчитать актуальное количество токенов в корзине на текущую секунду.
--   3. Расчет дефицита (Deficit Calculation): Для каждого лимита скрипт проверяет, хватает ли сейчас токенов.
--     Если их меньше, чем нужно, вычисляется дефицит (needed - self.tokens). 
--     Затем этот дефицит делится на скорость пополнения корзины (rate), чтобы узнать необходимое
--     время ожидания в секундах (с округлением вверх math.ceil, чтобы дождаться целого токена).
--   4. Поиск "узкого горлышка" (Bottleneck): Поскольку для успешной операции (в acquire.lua) нужны
--     токены из всех переданных лимитов одновременно, общим временем ожидания будет являться
--     максимальное время ожидания среди всех проверенных корзин (math.max(unpack(wait_times))).
--   5. Поддержка TTL: В процессе проверки скрипт продлевает время жизни ключей (EXPIRE ...),
--     чтобы корзины не удалялись из Redis, пока за ними наблюдают ожидающие
--     процессы.
-- Обратите внимание: скрипт не изменяет количество токенов (не списывает их), а лишь "смотрит" на состояние.
-------------------------------------------------------------------------------

-- Указываем Redis реплицировать сами эффекты от скрипта, а не сам скрипт.
-- Это необходимо для использования команды TIME внутри скрипта в версиях Redis 3.2 - 5.0.
redis.replicate_commands()

-- Входящие аргументы
-- KEYS: список ключей (имен лимитов)
-- ARGV[1]: требуемое количество токенов (tokens_needed)
-- ARGV[2]: время жизни ключей в секундах (key_ttl)
local limit_keys = KEYS
local tokens_needed = tonumber(ARGV[1]) or 0
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

  obj.exists = (obj.max_tokens > 0) and (obj.interval > 0)
  
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
    local time_consumed = tokens_to_add / self.rate
    self.last_used = math.min(self.last_used + time_consumed, current_time)
  end

  return self
end

-- Расчет времени, через которое накопится нужное количество токенов
function Limit:available_in(needed)
  -- Если токенов уже хватает, ждать не нужно
  if needed <= self.tokens then
    return 0
  end
  
  local deficit_tokens = needed - self.tokens
  local time_passed = current_time - self.last_used
  -- Округляем вверх (math.ceil), так как нам нужно дождаться появления ЦЕЛОГО токена
  return math.ceil(deficit_tokens / self.rate) - time_passed
end

-------------------------------------------------------------------------------
-- Основная логика: расчет максимального времени ожидания
-------------------------------------------------------------------------------
local function process_all_limits(limit_keys, needed, time_now)
  -- Валидация входных данных
  if needed <= 0 then 
    return { "result", "false", "error", "tokens not requested", "keys", limit_keys } 
  end
  
  if #limit_keys == 0 then 
    return { "result", "false", "error", "no keys passed", "keys", limit_keys } 
  end
  
  local wait_times = {}
  
  for i = 1, #limit_keys do
    local key = limit_keys[i]
    local limit = Limit:new(key)
    
    if not limit.exists then
      return { "result", "false", "error", "key_not_found", "key", key }
    end  
    
    -- Пересчитываем текущее количество токенов
    limit:update(time_now)
    
    -- Продлеваем жизнь ключу, так как идет активная проверка лимита
    -- раньше был GT, но он только с версии 7 (GT - только если новый TTL больше текущего остатка)
    redis.call("EXPIRE", limit.key, key_ttl)
    
    -- Сохраняем время ожидания для текущего лимита
    table.insert(wait_times, limit:available_in(needed))
  end
  
  -- Возвращаем максимальное время ожидания среди всех лимитов (bottleneck)
  return {
    "result", "true",
    "available_in", math.max(unpack(wait_times))
  }
end

return process_all_limits(limit_keys, tokens_needed, current_time)