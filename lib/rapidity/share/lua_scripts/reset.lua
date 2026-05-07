-------------------------------------------------------------------------------
-- СПЕЦИФИКАЦИЯ ФАЙЛА
-------------------------------------------------------------------------------
-- Этот файл отвечает за полный сброс состояния лимита к исходным значениям.
-- 
-- Описание логики работы:
-- 1. Скрипт принимает ключ лимита и время его жизни (TTL).
-- 2. Читает базовые (конфигурационные) параметры лимита (max_tokens, interval, max_queue).
-- 3. Если ключ отсутствует, возвращает ошибку key_not_found.
-- 4. Перезаписывает текущее состояние лимита:
--    - tokens = max_tokens (корзина полностью заполняется)
--    - semaphore = max_queue (очередь полностью освобождается)
--    - last_used = текущее время сервера
--    - rate = max_tokens / interval (пересчитывается на случай, если была ошибка деления)
-- 5. Обновляет время жизни ключа (TTL) и возвращает обновленное состояние (HGETALL).
-------------------------------------------------------------------------------

-- Указываем Redis реплицировать сами эффекты от скрипта, а не сам скрипт.
redis.replicate_commands()

-- Входящие аргументы:
-- KEYS[1] : ключ лимита в Redis
-- ARGV[1] : время жизни ключа в секундах (key_ttl)
local limit_key = KEYS[1]
local key_ttl = tonumber(ARGV[1]) or 0

local function reset()
  -- Получаем текущие базовые настройки лимита
  local limit_params = redis.call("HMGET", limit_key,
    "max_tokens",
    "interval",
    "max_queue"
  )
  
  -- Если первого поля (max_tokens) нет, значит ключа не существует
  if not limit_params[1] then
    return {"result", "false", "error", "key_not_found"}
  end

  local max_tokens = tonumber(limit_params[1]) or 0
  local interval = tonumber(limit_params[2]) or 1 -- защита от деления на 0
  local max_queue = tonumber(limit_params[3]) or 0
  
  local current_time = redis.call("TIME")[1]

  -- Сбрасываем динамические параметры (наполняем корзину, очищаем семафор)
  redis.call("HMSET", limit_key,
    "tokens", max_tokens,
    "semaphore", max_queue,
    "rate", max_tokens / interval,
    "last_used", current_time
  )

  -- Продлеваем жизнь ключу
  -- раньше был GT, но он только с версии 7 (GT - только если новый TTL больше текущего остатка)
  redis.call("EXPIRE", limit_key, key_ttl)
  
  -- Возвращаем успешный результат и обновленные данные
  return {"result", "true", "info", {limit_key, redis.call("HGETALL", limit_key)}}
end

return reset()