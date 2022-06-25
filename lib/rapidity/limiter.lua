-- args: key, treshold, interval, count
-- returns: obtained count.

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
