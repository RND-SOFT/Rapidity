-- this is required to be able to use TIME and writes; basically it lifts the script into IO
redis.replicate_commands()

-- args: keys, tokens_needed, key_ttl
-- returns: available_in - time to limits

local keys = KEYS
local tokens_needed = tonumber(ARGV[1]) or 0
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

function Limit:available_in(tokens_needed, current_time)
  if tokens_needed <= self.tokens then
    return 0
  else
    local deficit_tokens = tokens_needed - self.tokens
    local time_needed = math.ceil(deficit_tokens / self.rate)
    return time_needed
  end
end

local function process_all_limits(keys, tokens_needed, current_time)
  if tokens_needed <= 0 then 
    return {
        "result", "false",
        "error", "tokens not requested",
        "keys", keys
      } 
  end
  
  if #keys == 0 then 
    return {
        "result", "false",
        "error", "no keys passed",
        "keys", keys
      } 
  end
  
  local limits = {}
  for i = 1, #keys do
    local key = keys[i]
    local limit = Limit:new(key)
    if not limit.exists then
      return {
        "result", "false",
        "error", "key_not_found",
        "key", key
      }
    end  
    
    limit:update(current_time)
    redis.call("EXPIRE", limit.key, key_ttl, "GT")
    table.insert(limits, limit:available_in(tokens_needed, current_time))
  end
  
  return {
    "result", "true",
    "available_in", math.max(unpack(limits))
  }
end

return process_all_limits(keys, tokens_needed, current_time)