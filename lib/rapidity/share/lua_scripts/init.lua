redis.replicate_commands()

local key = KEYS[1]
local count = tonumber(ARGV[1])
local interval = tonumber(ARGV[2])
local queue_length = tonumber(ARGV[3])
local key_ttl = tonumber(ARGV[4])
local redis_time = redis.call("TIME") -- Array of [seconds, microseconds]

redis.call("HSET", key, "default", count, "current", count, "interval", interval, "queue_length", queue_length, last_used, redis_time[1])
redis.call("EXPIRE", key, key_ttl, "GT")

return {}
