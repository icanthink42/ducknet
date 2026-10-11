local config = require("ducknet.config")
local DNS = require("ducknet.dns")

local arguments = { ... }
local family, action = arguments[1], arguments[2]
local networkPath, dnsPath = "/etc/ducknet/config.lua", "/etc/ducknet/dns.lua"

local function usage()
  io.stderr:write([[
usage:
  dnsctl resolver list
  dnsctl resolver add <ip>
  dnsctl resolver remove <ip>
  dnsctl search list
  dnsctl search add <domain>
  dnsctl search remove <domain>
  dnsctl root list
  dnsctl root add <ip>
  dnsctl root remove <ip>
  dnsctl zone list
  dnsctl zone add <domain>
  dnsctl zone remove <domain>
  dnsctl record list <zone>
  dnsctl record add <zone> <name|@> <A|NS|CNAME|SOA|TXT> <value> [ttl]
  dnsctl record remove <zone> <name|@> <type> [value]
  dnsctl server enable <authoritative|recursive|both>
  dnsctl server disable
]])
end

local function ipv4(value)
  assert(DNS._isIPv4(value), "invalid IPv4 address: " .. tostring(value))
  return value
end

local function network()
  local value, err = config.load(networkPath)
  if not value then error("could not load DuckNet config: " .. tostring(err), 0) end
  value.dns = value.dns or { servers = {}, search = {} }
  value.dns.servers = value.dns.servers or {}
  return value
end

local function dnsConfig()
  local value = config.load(dnsPath)
  if not value then value = { recursive = false, roots = {}, zones = {} } end
  value.roots, value.zones = value.roots or {}, value.zones or {}
  return value
end

local function save(value, path, message)
  local ok, err = config.save(value, path)
  if not ok then error("could not save DNS configuration: " .. tostring(err), 0) end
  io.write(message .. "\n")
end

local function mutateList(list, operation, value, label)
  if operation == "add" then
    for _, current in ipairs(list) do assert(current ~= value, label .. " already exists") end
    list[#list + 1] = value
    return "added " .. label .. " " .. value
  end
  local removed = false
  for index = #list, 1, -1 do
    if list[index] == value then table.remove(list, index) removed = true end
  end
  assert(removed, label .. " not found: " .. value)
  return "removed " .. label .. " " .. value
end

local function zoneName(value)
  assert(value, "zone name is required")
  if value == "." then return "" end
  return DNS.normalize(value)
end

local function displayName(value) return value == "" and "." or value end

local function findZone(settings, name)
  for index, zone in ipairs(settings.zones) do
    if DNS.normalize(zone.name) == name then return zone, index end
  end
end

local function recordName(zone, name)
  assert(name, "record name is required")
  if name == "@" then return zone end
  local absolute = name:sub(-1) == "."
  name = DNS.normalize(name)
  if absolute or zone == "" or name == zone or name:sub(-#zone - 1) == "." .. zone then
    return name
  end
  return DNS.normalize(name .. "." .. zone)
end

if family == "resolver" and action == "list" then
  for _, server in ipairs(network().dns.servers) do io.write(server .. "\n") end
  return
end

if family == "resolver" and (action == "add" or action == "remove") then
  local settings, server = network(), ipv4(arguments[3])
  local message = mutateList(settings.dns.servers, action, server, "DNS resolver")
  save(settings, networkPath, message)
  return
end

if family == "search" and action == "list" then
  local settings = network()
  for _, suffix in ipairs(settings.dns.search or {}) do io.write(suffix .. "\n") end
  return
end

if family == "search" and (action == "add" or action == "remove") then
  local settings, suffix = network(), DNS.normalize(arguments[3])
  assert(suffix ~= "", "search domain cannot be the DNS root")
  settings.dns.search = settings.dns.search or {}
  local message = mutateList(settings.dns.search, action, suffix, "DNS search domain")
  save(settings, networkPath, message)
  return
end

if family == "root" and action == "list" then
  for _, server in ipairs(dnsConfig().roots) do io.write(server .. "\n") end
  return
end

if family == "root" and (action == "add" or action == "remove") then
  local settings, server = dnsConfig(), ipv4(arguments[3])
  local message = mutateList(settings.roots, action, server, "root hint")
  save(settings, dnsPath, message)
  return
end

if family == "zone" and action == "list" then
  local settings = dnsConfig()
  table.sort(settings.zones, function(left, right) return left.name < right.name end)
  for _, zone in ipairs(settings.zones) do
    io.write(displayName(DNS.normalize(zone.name)) .. "\n")
  end
  return
end

if family == "zone" and action == "add" then
  local settings, name = dnsConfig(), zoneName(arguments[3])
  assert(not findZone(settings, name), "zone already exists: " .. displayName(name))
  settings.zones[#settings.zones + 1] = { name = name, records = {} }
  save(settings, dnsPath, "added authoritative zone " .. displayName(name))
  return
end

if family == "zone" and action == "remove" then
  local settings, name = dnsConfig(), zoneName(arguments[3])
  local _, index = findZone(settings, name)
  assert(index, "zone not found: " .. displayName(name))
  table.remove(settings.zones, index)
  save(settings, dnsPath, "removed authoritative zone " .. displayName(name))
  return
end

if family == "record" and action == "list" then
  local settings, name = dnsConfig(), zoneName(arguments[3])
  local zone = assert(findZone(settings, name), "zone not found: " .. displayName(name))
  table.sort(zone.records, function(left, right)
    return left.name == right.name and left.type < right.type or left.name < right.name
  end)
  for _, record in ipairs(zone.records) do
    io.write(string.format("%-32s %-6s %-6d %s\n", displayName(record.name),
      record.type, record.ttl or 300, record.value))
  end
  return
end

if family == "record" and action == "add" then
  local settings, name = dnsConfig(), zoneName(arguments[3])
  local zone = assert(findZone(settings, name), "zone not found: " .. displayName(name))
  local record = {
    name = recordName(name, arguments[4]), type = DNS.type(arguments[5]),
    value = assert(arguments[6], "record value is required"),
    ttl = tonumber(arguments[7] or "300")
  }
  assert(record.type ~= "ANY", "ANY cannot be stored as a record")
  assert(record.ttl and record.ttl >= 0 and record.ttl % 1 == 0, "invalid DNS TTL")
  if record.type == "A" then ipv4(record.value) end
  if record.type == "NS" or record.type == "CNAME" then
    record.value = DNS.normalize(record.value)
  end
  for _, current in ipairs(zone.records) do
    assert(current.name ~= record.name or current.type ~= record.type or
      current.value ~= record.value, "DNS record already exists")
  end
  zone.records[#zone.records + 1] = record
  DNS.authority(settings.zones)
  save(settings, dnsPath, "added " .. record.type .. " record for " ..
    displayName(record.name))
  return
end

if family == "record" and action == "remove" then
  local settings, name = dnsConfig(), zoneName(arguments[3])
  local zone = assert(findZone(settings, name), "zone not found: " .. displayName(name))
  local wantedName, wantedType, wantedValue = recordName(name, arguments[4]),
    DNS.type(arguments[5]), arguments[6]
  local removed = false
  for index = #zone.records, 1, -1 do
    local record = zone.records[index]
    if record.name == wantedName and record.type == wantedType and
        (not wantedValue or record.value == wantedValue) then
      table.remove(zone.records, index)
      removed = true
    end
  end
  assert(removed, "matching DNS record not found")
  save(settings, dnsPath, "removed " .. wantedType .. " record for " ..
    displayName(wantedName))
  return
end

local function enableServer(mode)
  assert(mode == "authoritative" or mode == "recursive" or mode == "both",
    "DNS server mode must be authoritative, recursive, or both")
  local settings = dnsConfig()
  settings.recursive = mode ~= "authoritative"
  if settings.recursive then assert(#settings.roots > 0, "add at least one root hint first") end
  if mode ~= "recursive" then assert(#settings.zones > 0, "add an authoritative zone first") end
  save(settings, dnsPath, "configured " .. mode .. " DNS server")
  if type(fs) == "table" then
    fs.makeDir("/etc/systemdck")
    assert(config.save({
      description = "DuckNet DNS server", program = "/ducknet/bin/dnsd.lua",
      arguments = { networkPath, dnsPath }, enabled = true,
      restart = "always", restartDelay = 2
    }, "/etc/systemdck/ducknet-dns.lua"))
    io.write("enabled DuckNet DNS at startup; reboot or run: systemdck start ducknet-dns\n")
    return
  end
  local filesystem, shell = require("filesystem"), require("shell")
  filesystem.makeDirectory("/etc/rc.d")
  local file = assert(io.open("/etc/rc.d/ducknet-dns.lua", "w"))
  file:write([[local worker
function start()
  if worker and worker:status() == "running" then return end
  worker = require("thread").create(function()
    assert(loadfile("/usr/bin/dnsd.lua"))(
      "/etc/ducknet/config.lua", "/etc/ducknet/dns.lua")
  end):detach()
end
function stop() if worker then worker:kill(); worker = nil end end
]])
  file:close()
  pcall(shell.execute, "rc ducknet-dns disable")
  local enabled, reason = shell.execute("rc ducknet-dns enable")
  assert(enabled, "could not enable DNS startup: " .. tostring(reason))
  io.write("enabled DuckNet DNS at startup; run: rc ducknet-dns start\n")
end

if family == "server" and action == "enable" then
  enableServer((arguments[3] or "authoritative"):lower())
  return
end

if family == "server" and action == "disable" then
  if type(fs) == "table" and fs.exists("/etc/systemdck/ducknet-dns.lua") then
    local unit = assert(config.load("/etc/systemdck/ducknet-dns.lua"))
    unit.enabled = false
    assert(config.save(unit, "/etc/systemdck/ducknet-dns.lua"))
    io.write("disabled DuckNet DNS at startup; run: systemdck stop ducknet-dns\n")
    return
  end
  if type(fs) ~= "table" then
    local filesystem, shell = require("filesystem"), require("shell")
    if filesystem.exists("/etc/rc.d/ducknet-dns.lua") then
      pcall(shell.execute, "rc ducknet-dns stop")
      pcall(shell.execute, "rc ducknet-dns disable")
      io.write("disabled DuckNet DNS at startup\n")
      return
    end
  end
  error("DuckNet DNS is not installed as a service", 0)
end

usage()
