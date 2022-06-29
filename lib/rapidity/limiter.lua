-- args: key, treshold, interval, count
-- returns: obtained count.

-- this is required to be able to use TIME and writes; basically it lifts the script into IO
redis.replicate_commands()

-- make some nicer looking variable names:
local retval = nil

-- Redis documentation recommends passing the keys separately so that Redis
-- can - in the future - verify that they live on the same shard of a cluster, and
-- raise an error if they are not. As far as can be understood this functionality is not
-- yet present, but if we can make a little effort to make ourselves more future proof
-- we should.
local key = KEYS[1]
local treshold = tonumber(ARGV[1])
local interval = tonumber(ARGV[2])
local count = tonumber(ARGV[3])

local current = 0
local to_return = 0

local redis_time = redis.call("TIME") -- Array of [seconds, microseconds]
redis.call("SET", key, treshold, "EX", interval, "NX")
current = redis.call("DECRBY", key, count)

-- If we became below zero we must return some value back
if current < 0 then
  to_return = math.min(count, math.abs(current))

  -- set 0 to current counter value
  redis.call("SET", key, 0, 'KEEPTTL')

  -- return obtained part of requested count
  retval = count - to_return
else
  -- return full of requested count
  retval = count
end

return {retval, redis_time}
