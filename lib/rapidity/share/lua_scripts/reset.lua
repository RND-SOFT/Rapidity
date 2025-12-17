redis.replicate_commands()

local key = KEYS[1]
local key_ttl = tonumber(ARGV[1])

local exists = redis.call("EXISTS", key)
local current_time = redis.call("TIME")[1]

if exists ~= 1 then
  return {"result", "false", "error", "key_not_found"}
end

local limit = redis.call("HMGET", key,
  "max_tokens",
  "interval",
  "max_queue"
)
local max_tokens = tonumber(limit[1]) or 0
local interval = tonumber(limit[1]) or 0
local max_queue = tonumber(limit[1]) or 0

redis.call("HSET", key,
  "tokens", max_tokens,
  "queue", max_queue,
  "rate", max_tokens / interval,
  "last_used", current_time
)

redis.call("EXPIRE", key, key_ttl, "GT")
return {"result", "true", "info", {key, redis.call("HGETALL", key)}}
