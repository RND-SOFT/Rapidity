redis.replicate_commands()

local key = KEYS[1]
local exists = redis.call("EXISTS", key)

if exists ~= 1 then
  return {"error", "key_not_found"}
end

return redis.call("HGETALL", key)
