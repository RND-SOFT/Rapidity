redis.replicate_commands()

local key = KEYS[1]
local key_ttl = tonumber(ARGV[1]) or 0

local exists = redis.call("EXISTS", key)

if exists ~= 1 then
  return {"result", "false", "error", "key_not_found"}
end

local queue = tonumber(redis.call("HGET", key, "queue")) or 0

redis.call("EXPIRE", key, key_ttl, "GT")
return {"result", "true", "queue", queue}
