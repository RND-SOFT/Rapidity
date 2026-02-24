-- this is required to be able to use TIME and writes; basically it lifts the script into IO
redis.replicate_commands()

-- args: key, key_ttl
-- returns: info - limit hash (key-value pairs), with the limit name as the first element

local key = KEYS[1]
local key_ttl = tonumber(ARGV[1])

local function reset(key, key_ttl)
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
  local interval = tonumber(limit[2]) or 0
  local max_queue = tonumber(limit[3]) or 0

  redis.call("HSET", key,
    "tokens", max_tokens,
    "semaphore", max_queue,
    "rate", max_tokens / interval,
    "last_used", current_time
  )

  redis.call("EXPIRE", key, key_ttl, "GT")
  return {"result", "true", "info", {key, redis.call("HGETALL", key)}}
end

return reset(key, key_ttl)

