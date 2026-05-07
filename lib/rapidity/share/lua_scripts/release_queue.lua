-------------------------------------------------------------------------------
-- СПЕЦИФИКАЦИЯ ФАЙЛА
-------------------------------------------------------------------------------
-- Этот файл отвечает за освобождение (возврат) мест обратно в семафор/очередь
-- после того, как задача была завершена.
-- 
-- Этот механизм является частью Feedback-Driven Flow Control:
-- продюсер захватывает места перед выполнением задачи (acquire_queue), 
-- а после выполнения SENDER возвращает их (release_queue), чтобы другие продюсеры 
-- могли отправить новые задачи.
--
-- Описание функционала файла release_queue.lua
-- 1. Скрипт принимает ключи лимитов (списком) и количество возвращаемых мест.
-- 2. Считывает текущее значение семафора и максимальный размер очереди (max_queue) одним запросом.
-- 3. Если хоть одного из ключей нет, возвращает ошибку key_not_found.
-- 4. Рассчитывает новое значение для каждого семафора, прибавляя возвращенные места к текущему значению.
--    ВАЖНО: результат ограничивается сверху значением max_queue (защита от переполнения).
-- 5. Обновляет значение семафоров в Redis и продлевает время жизни ключа (TTL).
-------------------------------------------------------------------------------

-- Указываем Redis реплицировать сами эффекты от скрипта, а не сам скрипт.
redis.replicate_commands()

-- Входящие аргументы:
-- KEYS : список ключей лимитов в Redis
-- ARGV[1] : количество возвращаемых мест (released)
-- ARGV[2] : время жизни ключа в секундах (key_ttl)
local keys = KEYS
local released = tonumber(ARGV[1]) or 0
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

  -- Получаем текущие настройки семафора одним запросом.
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

-- Возврат мест в семафор с защитой от переполнения (в памяти)
function QueueLimit:release(amount)
  if self:is_enabled() then
    self.semaphore = math.min(self.max_queue, self.semaphore + amount)
  end
end

-- Сохранение обновленного значения семафора в Redis
function QueueLimit:save()
  if self.exists and self:is_enabled() then
    redis.call("HSET", self.key, "semaphore", self.semaphore)
  end
end

-------------------------------------------------------------------------------
-- Основная логика: возврат мест в список лимитов
-------------------------------------------------------------------------------
local function process_all_queues(limit_keys, released_tokens, ttl)
  -- Базовая валидация: нельзя вернуть <= 0 мест
  if released_tokens <= 0 then
    return {"result", "false", "error", "tokens not released"}
  end

  if #limit_keys == 0 then
    return {"result", "false", "error", "no keys passed"}
  end

  local limits = {}

  -- Фаза 1: Проверка всех лимитов (Validation)
  for i = 1, #limit_keys do
    local key = limit_keys[i]
    local limit = QueueLimit:new(key)
    
    if not limit.exists then
      return {"result", "false", "error", "key_not_found", "key", key}
    end

    table.insert(limits, limit)
  end

  -- Переменная для хранения минимального значения семафора среди всех лимитов (для обратной совместимости вывода)
  local min_new_semaphore = nil

  -- Фаза 2: Фиксация состояния (Возврат)
  for i = 1, #limits do
    local limit = limits[i]
    
    limit:release(released_tokens)
    limit:save()
    
    -- Обновляем min_new_semaphore, но только для лимитов с включенной очередью
    if limit:is_enabled() then
      if not min_new_semaphore or limit.semaphore < min_new_semaphore then
        min_new_semaphore = limit.semaphore
      end
    end

    -- Продлеваем жизнь ключу 
    -- раньше был GT, но он только с версии 7 (GT - только если новый TTL больше текущего остатка)
    redis.call("EXPIRE", limit.key, ttl)
  end

  -- Если ни у одного лимита очередь не включена, вернем 0
  min_new_semaphore = min_new_semaphore or 0

  -- Возвращаем успешный результат
  return {
    "result", "true", 
    "semaphore", min_new_semaphore,
    "keys", limit_keys
  }
end

return process_all_queues(keys, released, key_ttl)