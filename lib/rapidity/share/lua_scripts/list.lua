local namespace_pattern = ARGV[1] or '*'
local max_keys = tonumber(ARGV[2]) or 1000

local function list(namespace_pattern, max_keys)
  local cursor = "0"
  local found = {}
  local processed = 0

  repeat
    local scan_result = redis.call("SCAN", cursor, "MATCH", namespace_pattern, "COUNT", 100)
    cursor = scan_result[1]
    local keys = scan_result[2]
    
    for _, key in ipairs(keys) do
      processed = processed + 1
      if redis.call("TYPE", key)["ok"] == "hash" then
        local values = redis.call("HGETALL", key)
        table.insert(found, {key, values})
      end
    end
    
    if processed >= max_keys then
      cursor = "0"
    end
  until cursor == "0"

  return {
      "count", processed,
      "limits", found
  }
end

return list(namespace_pattern, max_keys)