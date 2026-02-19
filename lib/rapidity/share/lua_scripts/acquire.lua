redis.replicate_commands()

local keys = KEYS
local requested = tonumber(ARGV[1]) or 0
local key_ttl = tonumber(ARGV[2]) or 0

local current_time = redis.call("TIME")[1]

local Limit = {}
Limit.__index = Limit

function Limit:new(key)
  local obj = {
    key = key,
    exists = false
  }
    
  setmetatable(obj, self)

  if redis.call("EXISTS", key) ~= 1 then
    return obj
  end
  
  local values = redis.call("HMGET", key,
    "max_tokens",
    "tokens",
    "interval",
    "last_used",
    "rate"
  )
    
  obj.max_tokens = tonumber(values[1]) or 0
  obj.tokens = tonumber(values[2]) or 0
  obj.interval = tonumber(values[3]) or 0
  obj.last_used = tonumber(values[4]) or 0
  obj.rate = tonumber(values[5]) or 0

  obj.exists = obj.max_tokens > 0 and obj.interval > 0
  
  return obj
end

function Limit:update(current_time)
  if not self.exists then
    return self
  end  
  
  local time_passed = current_time - self.last_used
  if time_passed <= 0 then
    return self
  end
  
  local tokens_to_add = math.floor(time_passed * self.rate)
  self.tokens = math.min(self.tokens + tokens_to_add, self.max_tokens)
  self.last_used = current_time
  return self
end

function Limit:save()
  if not self.exists then return end
  
  redis.call("HMSET", self.key,
      "tokens", self.tokens, 
      "last_used", self.last_used
  )
end

function Limit:can_acquire(requested)
  return self.exists and self.tokens >= requested
end

function Limit:acquire(requested)
  if not self:can_acquire(requested) then
    return false
  end
    
  self.tokens = self.tokens - requested
  return true
end

local function process_all_limits(keys, requested, current_time)
  if requested <= 0 then
    return {
        "result", "false",
        "retryable", "false",
        "error", "limits not requested"
      }
  end

  if #keys == 0 then
    return {
        "result", "false",
        "retryable", "false",
        "error", "no keys passed"
      }
  end
  
  local limits = {}
  
  for i = 1, #keys do
    local key = keys[i]
    local limit = Limit:new(key)
    if not limit.exists then
      return {
        "result", "false",
        "retryable", "false",
        "error", "key_not_found",
        "key", key
      }
    end

    limit:update(current_time)

    if not limit:can_acquire(requested) then
      return {
        "result", "false",
        "retryable", "true",
        "error", "not_limits",
        "tokens_available", limit.tokens,
        "key", key
      }
    end
    
    table.insert(limits, limit)
  end
  
  for i=1, #limits do
    local limit = limits[i]
    limit:acquire(requested)
    limit:save()
    redis.call("EXPIRE", limit.key, key_ttl, "GT")
  end
  
  return {
    "result", "true",
    "key", "key"
  }
end


return process_all_limits(keys, requested, current_time)