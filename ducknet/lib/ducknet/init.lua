local ducknet = {}

ducknet.codec = require("ducknet.codec")
ducknet.Link = require("ducknet.modem")
ducknet.IP = require("ducknet.ip")
ducknet.ICMP = require("ducknet.icmp")
ducknet.UDP = require("ducknet.udp")
ducknet.DHCP = require("ducknet.dhcp")
ducknet.TCP = require("ducknet.tcp")
ducknet.DLTP = require("ducknet.dltp")

local function copy(source)
  local target = {}
  for key, value in pairs(source or {}) do target[key] = value end
  return target
end

local function resolveModem(name)
  if not name or name == "" then return nil end
  if type(peripheral) == "table" and type(peripheral.wrap) == "function" then
    local wrapped = peripheral.wrap(name)
    assert(wrapped, "no modem found on " .. name)
    return wrapped
  end
  local component = require("component")
  assert(type(component.proxy) == "function", "component.proxy is unavailable")
  return component.proxy(name)
end

-- Build a complete stack. Legacy link/ip configs remain supported; routers can
-- instead declare several interfaces, each with its own address and modem.
function ducknet.stack(configuration, modem)
  local links, ip = {}, nil
  if configuration.interfaces and #configuration.interfaces > 0 then
    for index, interface in ipairs(configuration.interfaces) do
      local linkOptions = copy(configuration.link)
      for key, value in pairs(interface) do linkOptions[key] = value end
      linkOptions.address = interface.address
      linkOptions.modemName = interface.modem
      local resolved = index == 1 and modem or nil
      resolved = resolved or resolveModem(interface.modem)
      links[index] = ducknet.Link.new(resolved, linkOptions)
    end
    local ipOptions = copy(configuration.ip)
    ipOptions.address = configuration.interfaces[1].address
    ipOptions.interface = configuration.interfaces[1].name
    ip = ducknet.IP.new(links[1], ipOptions)
    for index = 2, #configuration.interfaces do
      local interface = configuration.interfaces[index]
      ip:addInterface(links[index], interface)
    end
    for index, interface in ipairs(configuration.interfaces) do
      ip:addRoute(interface.network or interface.subnet, nil,
        interface.metric or 10, ip.interfaces[index].name)
    end
  else
    local linkOptions = copy(configuration.link)
    linkOptions.address = configuration.ip.address
    linkOptions.modemName = linkOptions.modem
    links[1] = ducknet.Link.new(modem or resolveModem(linkOptions.modem), linkOptions)
    ip = ducknet.IP.new(links[1], configuration.ip)
  end

  for _, route in ipairs(configuration.routes or {}) do
    ip:addRoute(route.network, route.via, route.metric, route.interface)
  end
  local tcp = ducknet.TCP.new(ip, configuration.tcp)
  local udp = ducknet.UDP.new(ip)
  local icmp = ducknet.ICMP.new(ip)
  local dltpOptions = configuration.dltp or {}
  local dltp = ducknet.DLTP.new(tcp, dltpOptions)
  return { link = links[1], links = links, ip = ip, icmp = icmp,
    udp = udp, tcp = tcp, dltp = dltp }
end

return ducknet
