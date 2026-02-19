redis.replicate_commands()

local key = KEYS[1]
local key_ttl = tonumber(ARGV[1]) or 0

local function check_queue(key, key_ttl)
  local exists = redis.call("EXISTS", key)

  if exists ~= 1 then
    return {"result", "false", "error", "key_not_found"}
  end

  local semaphore = tonumber(redis.call("HGET", key, "semaphore")) or 0

  redis.call("EXPIRE", key, key_ttl, "GT")
  
  return {"result", "true", "semaphore", semaphore}
end

return check_queue(key, key_ttl)
