redis.replicate_commands()

local key = KEYS[1]
local released = tonumber(ARGV[1])
local key_ttl = tonumber(ARGV[2]) or 0

local function release_queue(key, released, key_ttl)
  local exists = redis.call("EXISTS", key)

  if exists ~= 1 then
    return {"result", "false", "error", "key_not_found"}
  end

  local semaphore = tonumber(redis.call("HGET", key, "semaphore")) or 0
  local max_queue = tonumber(redis.call("HGET", key, "max_queue")) or 0

  local new_queue = math.min(max_queue, semaphore + released)

  redis.call("HSET", key, "semaphore", new_queue)
  redis.call("EXPIRE", key, key_ttl, "GT")

  return {"result", "true", "semaphore", new_queue}
end

return release_queue(key, released, key_ttl)
