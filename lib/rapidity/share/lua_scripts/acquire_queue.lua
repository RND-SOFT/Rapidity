redis.replicate_commands()

local key = KEYS[1]
local requested = tonumber(ARGV[1])
local exists = redis.call("EXISTS", key)
local tokens = 0

if exists ~= 1 then
  return {"result", "false", "error", "key_not_found"}
end

local queue = tonumber(redis.call("HGET", key, "queue")) or 0

if queue > 0 then
  if queue >= requested then
    queue = queue - requested
    tokens = requested
  else
    tokens = queue
    queue = 0
  end
else
  queue = 0
  tokens = 0
end

redis.call("HSET", key, "queue", queue)

return {"result", "true", "tokens", tokens, "queue", queue}