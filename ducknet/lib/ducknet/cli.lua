local config = require("ducknet.config")
local Link = require("ducknet.modem")
local IP = require("ducknet.ip")
local ICMP = require("ducknet.icmp")

local cli = {}

function cli.load(path, enableICMP)
  local settings, err = config.load(path)
  if not settings then error("could not load DuckNet config: " .. tostring(err), 0) end
  local component = require("component")
  local link = Link.new(component.modem, settings.link or {})
  local ip = IP.new(link, settings.ip)
  for _, route in ipairs(settings.routes or {}) do
    ip:addRoute(route.network, route.via, route.metric)
  end
  return settings, link, ip, enableICMP and ICMP.new(ip) or nil
end

function cli.number(value, name, minimum, maximum)
  local number = tonumber(value)
  if not number or number % 1 ~= 0 or number < minimum or number > maximum then
    error((name or "value") .. " must be between " .. minimum .. " and " .. maximum, 0)
  end
  return number
end

return cli
