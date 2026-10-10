local config = require("ducknet.config")

local arguments = { ... }
local family, action = arguments[1], arguments[2]

local function usage()
  io.stderr:write([[
usage:
  dhcpd pool list [config.lua]
  dhcpd pool add <interface> <first-ip> <last-ip> [lease-seconds] [config.lua]
  dhcpd pool remove <interface> [config.lua]
  dhcpd lease list [config.lua]
]])
end

local function ipv4(address)
  local a, b, c, d = tostring(address):match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
  a, b, c, d = tonumber(a), tonumber(b), tonumber(c), tonumber(d)
  assert(a and a <= 255 and b <= 255 and c <= 255 and d <= 255, "invalid IPv4 address")
  return ((a * 256 + b) * 256 + c) * 256 + d
end

local function contains(cidr, address)
  local base, prefix = cidr:match("^([^/]+)/(%d+)$")
  prefix = tonumber(prefix)
  assert(base and prefix and prefix <= 32, "invalid interface subnet")
  local block = 2 ^ (32 - prefix)
  return math.floor(ipv4(base) / block) == math.floor(ipv4(address) / block)
end

local function usableHost(cidr, address)
  local base, prefix = cidr:match("^([^/]+)/(%d+)$")
  prefix = tonumber(prefix)
  assert(base and prefix and prefix <= 32, "invalid interface subnet")
  if prefix > 30 then return true end
  local block = 2 ^ (32 - prefix)
  local network = math.floor(ipv4(base) / block) * block
  local value = ipv4(address)
  return value > network and value < network + block - 1
end

local function load(path)
  path = path or "/etc/ducknet/config.lua"
  local settings, err = config.load(path)
  if not settings then error("could not load DuckNet config: " .. tostring(err), 0) end
  settings.dhcp = settings.dhcp or { pools = {} }
  settings.dhcp.pools = settings.dhcp.pools or {}
  return settings, path
end

local function save(settings, path, message)
  assert(config.save(settings, path))
  io.write(message .. "\nReboot the router to apply it.\n")
end

local function findInterface(settings, name)
  for _, interface in ipairs(settings.interfaces or {}) do
    if interface.name == name then return interface end
  end
end

if family == "pool" and action == "list" then
  local settings = load(arguments[3])
  io.write("Interface       First             Last              Lease\n")
  for _, pool in ipairs(settings.dhcp.pools) do
    io.write(string.format("%-15s %-17s %-17s %ds\n", pool.interface,
      pool.first, pool.last, pool.lease or 3600))
  end
  return
end

if family == "pool" and action == "add" then
  local interfaceName, first, last = arguments[3], arguments[4], arguments[5]
  if not interfaceName or not first or not last then usage() return end
  local settings, path = load(arguments[7])
  local interface = findInterface(settings, interfaceName)
  assert(interface, "unknown interface: " .. interfaceName)
  first, last = tostring(first), tostring(last)
  assert(ipv4(first) <= ipv4(last), "pool start must not exceed pool end")
  local network = interface.network or interface.subnet
  assert(contains(network, first) and contains(network, last),
    "DHCP pool must be inside the interface subnet")
  assert(usableHost(network, first) and usableHost(network, last),
    "DHCP pool cannot include the network or broadcast address")
  local routerAddress = ipv4(interface.address)
  assert(routerAddress < ipv4(first) or routerAddress > ipv4(last),
    "DHCP pool cannot include the router address")
  local lease = tonumber(arguments[6] or "3600")
  assert(lease and lease % 1 == 0 and lease >= 60, "lease must be at least 60 seconds")
  for _, pool in ipairs(settings.dhcp.pools) do
    assert(pool.interface ~= interfaceName, "interface already has a DHCP pool")
  end
  settings.dhcp.pools[#settings.dhcp.pools + 1] = {
    interface = interfaceName, first = first, last = last,
    network = network, gateway = interface.address, lease = lease
  }
  save(settings, path, "added DHCP pool on " .. interfaceName)
  return
end

if family == "pool" and action == "remove" then
  local interfaceName = arguments[3]
  if not interfaceName then usage() return end
  local settings, path = load(arguments[4])
  local found = false
  for index = #settings.dhcp.pools, 1, -1 do
    if settings.dhcp.pools[index].interface == interfaceName then
      table.remove(settings.dhcp.pools, index)
      found = true
    end
  end
  assert(found, "no DHCP pool on interface " .. interfaceName)
  save(settings, path, "removed DHCP pool from " .. interfaceName)
  return
end

if family == "lease" and action == "list" then
  local settings = load(arguments[3])
  local leases = config.load(settings.dhcp.leasePath or "/etc/ducknet/dhcp-leases.lua")
  io.write("Address           Client ID                       Interface       Expires\n")
  local addresses = {}
  for leasedAddress in pairs(leases and leases.leases or {}) do
    addresses[#addresses + 1] = leasedAddress
  end
  table.sort(addresses)
  for _, leasedAddress in ipairs(addresses) do
    local lease = leases.leases[leasedAddress]
    io.write(string.format("%-17s %-31s %-15s %s\n", leasedAddress,
      lease.clientId, lease.interface, tostring(lease.expires)))
  end
  return
end

usage()
