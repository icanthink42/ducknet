local config = require("ducknet.config")
local ducknet = require("ducknet")

local cli = {}

function cli.load(path, enableICMP)
  local settings, err = config.load(path)
  if not settings then error("could not load DuckNet config: " .. tostring(err), 0) end
  local stack = ducknet.stack(settings)
  return settings, stack.link, stack.ip, enableICMP and stack.icmp or nil, stack
end

function cli.number(value, name, minimum, maximum)
  local number = tonumber(value)
  if not number or number % 1 ~= 0 or number < minimum or number > maximum then
    error((name or "value") .. " must be between " .. minimum .. " and " .. maximum, 0)
  end
  return number
end

return cli
