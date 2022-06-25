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

redis.call("SET", key, treshold, "EX", interval, "NX")
current = redis.call("DECRBY", key, count)

-- If we became below zero we must return some value back
if current < 0 then
  to_return = math.min(count, math.abs(current))

  -- put back some value 
  redis.call("INCRBY", key, to_return)

  -- return obtained part of requested count
  retval = count - to_return
else
  -- return full of requested count
  retval = count
end

return retval


-- -- and the config variables
-- local max_bucket_capacity = tonumber(ARGV[1])
-- local leak_rate = tonumber(ARGV[2])
-- local block_duration = tonumber(ARGV[3])
-- local n_tokens = tonumber(ARGV[4]) -- How many tokens this call adds to the bucket. Defaults to 1

-- -- Take the Redis timestamp
-- local redis_time = redis.call("TIME") -- Array of [seconds, microseconds]
-- local now = tonumber(redis_time[1]) + (tonumber(redis_time[2]) / 1000000)
-- local key_lifetime = math.ceil(max_bucket_capacity / leak_rate)

-- local blocked_until = redis.call("GET", block_key)
-- if blocked_until then
--   return {(tonumber(blocked_until) - now), 0}
-- end

-- -- get current bucket level. The throttle key might not exist yet in which
-- -- case we default to 0
-- local bucket_level = tonumber(redis.call("GET", bucket_level_key)) or 0

-- -- ...and then perform the leaky bucket fillup/leak. We need to do this also when the bucket has
-- -- just been created because the initial n_tokens to add might be so high that it will
-- -- immediately overflow the bucket and trigger the throttle, on the first call.
-- local last_updated = tonumber(redis.call("GET", last_updated_key)) or now -- use sensible default of 'now' if the key does not exist
-- local new_bucket_level = math.max(0, bucket_level - (leak_rate * (now - last_updated)))

-- if (new_bucket_level + n_tokens) <= max_bucket_capacity then
--   new_bucket_level = math.max(0, new_bucket_level + n_tokens)
--   retval = {0, math.ceil(new_bucket_level)}
-- else
--   redis.call("SETEX", block_key, block_duration, now + block_duration)
--   retval = {block_duration, 0}
-- end

-- -- Save the new bucket level
-- redis.call("SETEX", bucket_level_key, key_lifetime, new_bucket_level)

-- -- Record when we updated the bucket so that the amount of tokens leaked
-- -- can be correctly determined on the next invocation
-- redis.call("SETEX", last_updated_key, key_lifetime, now)

-- return retval