redis.replicate_commands()

local key = KEYS[1]
local exists = redis.call("EXISTS", key)

if exists ~= 1 then
  return {"result", "false", "error", "key_not_found"}
end

redis.call("DEL", key)
return {"result", "true"}
