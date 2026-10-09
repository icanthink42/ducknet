local config = require("ducknet.config")

local arguments = { ... }
local family, action = arguments[1], arguments[2]

local function usage()
  io.stderr:write([[
usage:
  ip interface list [config.lua]
  ip interface add <name> <modem> <address/prefix> [channel] [config.lua]
  ip interface remove <name> [config.lua]
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
  local network = math.floor(value / block) * block
  local n4 = network % 256
  network = math.floor(network / 256)
  local n3 = network % 256
  network = math.floor(network / 256)
  local n2 = network % 256
  local n1 = math.floor(network / 256)
  return string.format("%d.%d.%d.%d", a, b, c, d),
    string.format("%d.%d.%d.%d/%d", n1, n2, n3, n4, prefix)
end

if family ~= "interface" or not action then usage() return end

local configPath
if action == "list" then configPath = arguments[3]
elseif action == "add" then configPath = arguments[7]
elseif action == "remove" then configPath = arguments[4]
else usage() return end
configPath = configPath or "/etc/ducknet/config.lua"

local settings, loadError = config.load(configPath)
if not settings then error("could not load DuckNet config: " .. tostring(loadError), 0) end

if action == "list" then
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

assert(settings.interfaces and #settings.interfaces > 0,
  "this config uses the legacy single-interface format; reinstall the router profile first")

if action == "add" then
  local name, modem, cidr = arguments[3], arguments[4], arguments[5]
  if not name or not modem or not cidr then usage() return end
  assert(name:match("^[%a_][%w_-]*$"), "invalid interface name")
  local address, network = parseCIDR(cidr)
  local channel = tonumber(arguments[6] or "4660")
  assert(channel and channel % 1 == 0 and channel >= 0 and channel <= 65535,
    "channel must be between 0 and 65535")
  for _, interface in ipairs(settings.interfaces) do
    assert(interface.name ~= name, "interface already exists: " .. name)
    assert(interface.address ~= address, "IP address already exists: " .. address)
  end
  settings.interfaces[#settings.interfaces + 1] = {
    name = name, modem = modem, address = address, network = network, port = channel
  }
  assert(config.save(settings, configPath))
  io.write("added " .. name .. " on " .. modem .. " as " .. address ..
    " (" .. network .. ", channel " .. channel .. ")\nRestart the router to apply it.\n")
  return
end

local name = arguments[3]
if not name then usage() return end
assert(#settings.interfaces > 1, "cannot remove the router's only interface")
local found
for index, interface in ipairs(settings.interfaces) do
  if interface.name == name then found = index break end
end
assert(found, "unknown interface: " .. name)
for _, route in ipairs(settings.routes or {}) do
  assert(route.interface ~= name, "interface is used by static route " .. route.network)
end
table.remove(settings.interfaces, found)
assert(config.save(settings, configPath))
io.write("removed " .. name .. "\nRestart the router to apply it.\n")
