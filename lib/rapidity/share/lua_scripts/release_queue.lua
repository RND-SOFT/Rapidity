redis.replicate_commands()

local key = KEYS[1]
local released = tonumber(ARGV[1])
local exists = redis.call("EXISTS", key)

if exists ~= 1 then
  return {"result", "false", "error", "key_not_found"}
end

local queue = tonumber(redis.call("HGET", key, "queue")) or 0
local max_queue = tonumber(redis.call("HGET", key, "max_queue")) or 0

local new_queue = math.min(max_queue, queue + released)

redis.call("HSET", key, "queue", new_queue)

return {"result", "true", "queue", new_queue}