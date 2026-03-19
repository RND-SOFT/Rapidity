-------------------------------------------------------------------------------
-- СПЕЦИФИКАЦИЯ ФАЙЛА
-------------------------------------------------------------------------------
-- Этот файл отвечает за поиск и получение списка лимитов по паттерну.
-- 
-- Описание логики работы:
-- 1. Использует неблокирующую команду SCAN для итерации по ключам в Redis
--    в соответствии с переданным паттерном (например "my_app:limits:*").
-- 2. Для каждого найденного ключа проверяет, является ли он хэшом (hash).
-- 3. Если это хэш (то есть валидный лимит), читает все его данные (HGETALL).
-- 4. Итерация останавливается, если найдено максимальное количество ключей (max_keys)
--    или если SCAN обошел всю базу.
-- 5. Возвращает количество обработанных ключей и массив найденных лимитов.
-------------------------------------------------------------------------------

-- Входящие аргументы:
-- ARGV[1] : паттерн для поиска ключей (по умолчанию '*')
-- ARGV[2] : максимальное количество возвращаемых лимитов
local namespace_pattern = ARGV[1] or '*'
local max_keys = tonumber(ARGV[2]) or 1000

local function list()
  local cursor = "0"
  local found = {}
  local processed_count = 0

  repeat
    -- Ищем ключи пачками по 100 штук
    local scan_result = redis.call("SCAN", cursor, "MATCH", namespace_pattern, "COUNT", 100)
    cursor = scan_result[1]
    local keys = scan_result[2]
    
    for _, key in ipairs(keys) do
      -- Проверяем тип ключа (лимиты хранятся только в Hash)
      if redis.call("TYPE", key)["ok"] == "hash" then
        local values = redis.call("HGETALL", key)
        table.insert(found, {key, values})
        processed_count = processed_count + 1
      end
      
      -- Прерываем внутренний цикл, если достигли лимита
      if processed_count >= max_keys then
        break
      end
    end
    
    -- Если достигли лимита, принудительно обнуляем курсор, чтобы выйти из repeat
    if processed_count >= max_keys then
      cursor = "0"
    end
  until cursor == "0"

  return {
      "count", processed_count,
      "limits", found
  }
end

return list()