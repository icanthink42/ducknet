local config = require("ducknet.config")

local arguments = { ... }
local family, action = arguments[1], arguments[2]
local defaultPath = "/etc/ducknet/config.lua"

local function usage()
  io.stderr:write([[
usage:
  ip address set <address/prefix> [config.lua]
  ip gateway set <ip|none> [config.lua]
  ip channel set <channel> [config.lua]
  ip ttl set <ttl> [config.lua]
  ip forwarding set <on|off> [config.lua]
  ip dltp-port set <port> [config.lua]
  ip interface list [config.lua]
  ip interface add <name> <modem> <address/prefix> [channel] [config.lua]
  ip interface set <name> <modem> <address/prefix> [channel] [config.lua]
  ip interface remove <name> [config.lua]
  ip route list [config.lua]
  ip route add <network> <interface> <next-hop|direct> [metric] [config.lua]
  ip route remove <network> [interface] [config.lua]
]])
end

local function parseCIDR(cidr)
  assert(type(cidr) == "string", "address must use valid IPv4 CIDR notation")
  local a, b, c, d, prefix = cidr:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)/(%d+)$")
  a, b, c, d, prefix = tonumber(a), tonumber(b), tonumber(c), tonumber(d), tonumber(prefix)
  assert(a and a <= 255 and b <= 255 and c <= 255 and d <= 255 and
    prefix >= 0 and prefix <= 32, "address must use valid IPv4 CIDR notation")
  local value = ((a * 256 + b) * 256 + c) * 256 + d
  local block = 2 ^ (32 - prefix)
  local networkValue = math.floor(value / block) * block
  local network = networkValue
  local n4 = network % 256
  network = math.floor(network / 256)
  local n3 = network % 256
  network = math.floor(network / 256)
  local n2 = network % 256
  local n1 = math.floor(network / 256)
  return string.format("%d.%d.%d.%d", a, b, c, d),
    string.format("%d.%d.%d.%d/%d", n1, n2, n3, n4, prefix),
    value, networkValue, block
end

local function parseAddress(address)
  local normalized, _, value = parseCIDR(tostring(address) .. "/32")
  return normalized, value
end

local function integer(value, name, minimum, maximum)
  local result = tonumber(value)
  assert(result and result % 1 == 0 and result >= minimum and result <= maximum,
    name .. " must be between " .. minimum .. " and " .. maximum)
  return result
end

local function load(path)
  path = path or defaultPath
  local settings, loadError = config.load(path)
  if not settings then error("could not load DuckNet config: " .. tostring(loadError), 0) end
  return settings, path
end

local function save(settings, path, message)
  local saved, saveError = config.save(settings, path)
  if not saved then error("could not save DuckNet config: " .. tostring(saveError), 0) end
  io.write(message .. "\nRestart the DuckNet service or reboot to apply it.\n")
end

local function requireLegacy(settings, command)
  assert(not settings.interfaces or #settings.interfaces == 0,
    command .. " manages a single-interface host; use 'ip interface' on a router")
  settings.link = settings.link or {}
  settings.ip = settings.ip or {}
  settings.routes = settings.routes or {}
end

local function findInterface(settings, name)
  for index, interface in ipairs(settings.interfaces or {}) do
    if interface.name == name then return interface, index end
  end
end

local function contains(cidr, address)
  local _, addressValue = parseAddress(address)
  local _, _, _, networkValue, block = parseCIDR(cidr)
  return math.floor(addressValue / block) * block == networkValue
end

if not family or not action then usage() return end

if family == "address" and action == "set" then
  if not arguments[3] then usage() return end
  local settings, path = load(arguments[4])
  requireLegacy(settings, "ip address")
  local address, network = parseCIDR(arguments[3])
  settings.ip.address = address
  local direct
  for _, route in ipairs(settings.routes) do
    if not route.via then direct = route break end
  end
  if direct then direct.network = network else
    table.insert(settings.routes, 1, { network = network, metric = 10 })
  end
  local removedGateway = false
  for index = #settings.routes, 1, -1 do
    local route = settings.routes[index]
    if route.network == "0.0.0.0/0" and route.via and not contains(network, route.via) then
      table.remove(settings.routes, index)
      removedGateway = true
    end
  end
  save(settings, path, "set address " .. address .. " on " .. network ..
    (removedGateway and " and removed the incompatible default gateway" or ""))
  return
end

if family == "gateway" and action == "set" then
  if not arguments[3] then usage() return end
  local settings, path = load(arguments[4])
  requireLegacy(settings, "ip gateway")
  local gateway = arguments[3]:lower()
  if gateway ~= "none" then
    gateway = parseAddress(gateway)
    local reachable = false
    for _, route in ipairs(settings.routes) do
      if not route.via and contains(route.network, gateway) then reachable = true break end
    end
    assert(reachable, "default gateway must be inside the host's directly connected subnet")
  end
  for index = #settings.routes, 1, -1 do
    if settings.routes[index].network == "0.0.0.0/0" then table.remove(settings.routes, index) end
  end
  if gateway ~= "none" then
    settings.routes[#settings.routes + 1] = {
      network = "0.0.0.0/0", via = gateway, metric = 100
    }
  end
  save(settings, path, gateway == "none" and "removed default gateway" or
    ("set default gateway " .. gateway))
  return
end

if family == "channel" and action == "set" then
  local settings, path = load(arguments[4])
  requireLegacy(settings, "ip channel")
  local channel = integer(arguments[3], "channel", 0, 65535)
  settings.link.port = channel
  save(settings, path, "set modem channel " .. channel)
  return
end

if family == "ttl" and action == "set" then
  local settings, path = load(arguments[4])
  settings.ip = settings.ip or {}
  local ttl = integer(arguments[3], "TTL", 1, 255)
  settings.ip.ttl = ttl
  save(settings, path, "set default TTL " .. ttl)
  return
end

if family == "forwarding" and action == "set" then
  local settings, path = load(arguments[4])
  settings.ip = settings.ip or {}
  local state = arguments[3] and arguments[3]:lower()
  assert(state == "on" or state == "off", "forwarding must be 'on' or 'off'")
  settings.ip.forwarding = state == "on"
  save(settings, path, "set forwarding " .. state)
  return
end

if family == "dltp-port" and action == "set" then
  local settings, path = load(arguments[4])
  settings.dltp = settings.dltp or {}
  local port = integer(arguments[3], "DLTP port", 1, 65535)
  settings.dltp.port = port
  save(settings, path, "set DLTP port " .. port)
  return
end

if family == "interface" and action == "list" then
  local settings = load(arguments[3])
  io.write("Name            Modem            Address            Subnet              Channel\n")
  if settings.interfaces and #settings.interfaces > 0 then
    for _, interface in ipairs(settings.interfaces) do
      io.write(string.format("%-15s %-16s %-18s %-19s %d\n", interface.name,
        interface.modem or "auto", interface.address,
        interface.network or interface.subnet, interface.port or 4660))
    end
  else
    io.write(string.format("%-15s %-16s %-18s %-19s %d\n", "default", "auto",
      settings.ip.address, ((settings.routes or {})[1] or {}).network or "unknown",
      (settings.link or {}).port or 4660))
  end
  return
end

if family == "interface" and (action == "add" or action == "set") then
  local name, modem, cidr = arguments[3], arguments[4], arguments[5]
  if not name or not modem or not cidr then usage() return end
  local settings, path = load(arguments[7])
  assert(settings.interfaces and #settings.interfaces > 0,
    "this config uses the single-interface format; reinstall the router profile first")
  assert(name:match("^[%a_][%w_-]*$"), "invalid interface name")
  local address, network = parseCIDR(cidr)
  local channel = integer(arguments[6] or "4660", "channel", 0, 65535)
  local existing, existingIndex = findInterface(settings, name)
  if action == "add" then
    assert(not existing, "interface already exists: " .. name)
  else
    assert(existing, "unknown interface: " .. name)
  end
  for index, interface in ipairs(settings.interfaces) do
    assert(index == existingIndex or interface.address ~= address,
      "IP address already exists: " .. address)
  end
  local replacement = {
    name = name, modem = modem, address = address, network = network, port = channel
  }
  if existingIndex then settings.interfaces[existingIndex] = replacement
  else settings.interfaces[#settings.interfaces + 1] = replacement end
  local verb = action == "add" and "added" or "updated"
  save(settings, path, verb .. " interface " .. name .. " on " .. modem .. " as " ..
    address .. " (" .. network .. ", channel " .. channel .. ")")
  return
end

if family == "interface" and action == "remove" then
  local name = arguments[3]
  if not name then usage() return end
  local settings, path = load(arguments[4])
  assert(settings.interfaces and #settings.interfaces > 1,
    "cannot remove the router's only interface")
  local _, found = findInterface(settings, name)
  assert(found, "unknown interface: " .. name)
  for _, route in ipairs(settings.routes or {}) do
    assert(route.interface ~= name, "interface is used by static route " .. route.network)
  end
  table.remove(settings.interfaces, found)
  save(settings, path, "removed interface " .. name)
  return
end

if family == "route" and action == "list" then
  local settings = load(arguments[3])
  io.write("Network             Gateway          Interface       Metric\n")
  for _, interface in ipairs(settings.interfaces or {}) do
    io.write(string.format("%-19s %-16s %-15s %d\n",
      interface.network or interface.subnet, "direct", interface.name,
      interface.metric or 10))
  end
  for _, route in ipairs(settings.routes or {}) do
    io.write(string.format("%-19s %-16s %-15s %d\n", route.network,
      route.via or "direct", route.interface or "default", route.metric or 100))
  end
  return
end

if family == "route" and action == "add" then
  local cidr, interfaceName, nextHop = arguments[3], arguments[4], arguments[5]
  if not cidr or not interfaceName or not nextHop then usage() return end
  local settings, path = load(arguments[7])
  local outgoing = settings.interfaces and findInterface(settings, interfaceName)
  assert(outgoing,
    "unknown interface: " .. tostring(interfaceName))
  local _, network = parseCIDR(cidr)
  nextHop = nextHop:lower()
  if nextHop ~= "direct" then
    nextHop = parseAddress(nextHop)
    assert(contains(outgoing.network or outgoing.subnet, nextHop),
      "next hop must be inside the outgoing interface's subnet")
  end
  settings.routes = settings.routes or {}
  for _, route in ipairs(settings.routes) do
    assert(route.network ~= network or route.interface ~= interfaceName,
      "route already exists for " .. network .. " on " .. interfaceName)
  end
  local route = {
    network = network, interface = interfaceName,
    metric = integer(arguments[6] or "100", "metric", 0, 65535)
  }
  if nextHop ~= "direct" then route.via = nextHop end
  settings.routes[#settings.routes + 1] = route
  save(settings, path, "added route " .. network .. " on " .. interfaceName ..
    " via " .. nextHop)
  return
end

if family == "route" and action == "remove" then
  local cidr = arguments[3]
  if not cidr then usage() return end
  local settings, path = load(arguments[5])
  local _, network = parseCIDR(cidr)
  local interfaceName, found = arguments[4], false
  for index = #(settings.routes or {}), 1, -1 do
    local route = settings.routes[index]
    if route.network == network and (not interfaceName or route.interface == interfaceName) then
      table.remove(settings.routes, index)
      found = true
    end
  end
  assert(found, "no matching route for " .. network)
  save(settings, path, "removed route " .. network ..
    (interfaceName and (" on " .. interfaceName) or ""))
  return
end

usage()
