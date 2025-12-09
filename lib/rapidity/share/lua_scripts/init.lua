redis.replicate_commands()

local key = KEYS[1]
local limit = tonumber(ARGV[1])
local interval = tonumber(ARGV[2])
local queue = tonumber(ARGV[3])
local key_ttl = tonumber(ARGV[4])
local current_time = redis.call("TIME")

local exists = redis.call("EXISTS", key)

if exists == 1 then
  redis.call("HSET", key,
    "max_tokens", limit,
    "interval", interval,
    "max_queue", queue,
    "rate", limit / interval
  )
  redis.call("EXPIRE", key, key_ttl, "GT")
else
  redis.call("HSET", key, 
    "max_tokens", limit, 
    "tokens", limit, 
    "interval", interval, 
    "max_queue", queue,
    "queue", 0,
    "last_used", current_time[1],
    "rate", limit / interval
  )
  redis.call("EXPIRE", key, key_ttl, "EX")
end
return {"ОК"}
