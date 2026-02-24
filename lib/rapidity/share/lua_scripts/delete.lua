-- this is required to be able to use TIME and writes; basically it lifts the script into IO
redis.replicate_commands()

-- args: key
-- returns: key - deleted key

local key = KEYS[1]

local function delete(key)
  local exists = redis.call("EXISTS", key)
  
  if exists ~= 1 then
    return {"result", "false", "error", "key_not_found"}
  end

  redis.call("DEL", key)
  return {"result", "true"}
end

return delete(key)
