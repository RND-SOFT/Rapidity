-- this is required to be able to use TIME and writes; basically it lifts the script into IO
redis.replicate_commands()


-- args: key, requested, key_ttl
-- returns: tokens - obtained queue size
-- returns: semaphore - amount queue size

local key = KEYS[1]
local requested = tonumber(ARGV[1]) or 0
local key_ttl = tonumber(ARGV[2]) or 0


local function acquire_queue(key, requested, key_ttl)
  local exists = redis.call("EXISTS", key)
  local tokens = 0

  if exists ~= 1 then
    return {"result", "false", "error", "key_not_found"}
  end

  local semaphore = tonumber(redis.call("HGET", key, "semaphore")) or 0

  if semaphore > 0 then
    if semaphore >= requested then
      semaphore = semaphore - requested
      tokens = requested
    else
      tokens = semaphore
      semaphore = 0
    end
  else
    semaphore = 0
    tokens = 0
  end

  redis.call("HSET", key, "semaphore", semaphore)
  redis.call("EXPIRE", key, key_ttl, "GT")

  return {"result", "true", "tokens", tokens, "semaphore", semaphore}
end


return acquire_queue(key, requested, key_ttl)