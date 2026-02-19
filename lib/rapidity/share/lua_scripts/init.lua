redis.replicate_commands()

local key = KEYS[1]
local max_tokens = tonumber(ARGV[1])
local interval = tonumber(ARGV[2])
local max_queue = tonumber(ARGV[3])
local key_ttl = tonumber(ARGV[4])


local function init(key, max_tokens, interval, max_queue, key_ttl)
  local current_time = redis.call("TIME")[1]
  local exists = redis.call("EXISTS", key)

  if exists == 1 then
    redis.call("HSET", key,
      "max_tokens", max_tokens,
      "interval", interval,
      "max_queue", max_queue,
      "semaphore", max_queue,
      "rate", max_tokens / interval
    )
    redis.call("EXPIRE", key, key_ttl, "GT")
  else
    redis.call("HSET", key, 
      "max_tokens", max_tokens, 
      "tokens", max_tokens, 
      "interval", interval, 
      "max_queue", max_queue,
      "semaphore", max_queue,
      "last_used", current_time,
      "rate", max_tokens / interval
    )
    redis.call("EXPIRE", key, key_ttl, "NX")
  end
  return { key, redis.call("HGETALL", key)}
end

return init(key, max_tokens, interval, max_queue, key_ttl)
