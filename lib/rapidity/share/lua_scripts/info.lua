redis.replicate_commands()

local key = KEYS[1]
local key_ttl = tonumber(ARGV[1]) or 0

local function info(key, key_ttl)
  local exists = redis.call("EXISTS", key)

  if exists ~= 1 then
    return {"result", "false", "error", "key_not_found"}
  end

  redis.call("EXPIRE", key, key_ttl, "GT")
  return {"result", "true", "info", {key, redis.call("HGETALL", key)}}
end

return info(key, key_ttl)