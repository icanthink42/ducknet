local config = require("ducknet.config")
local Link = require("ducknet.modem")
local IP = require("ducknet.ip")
local UDP = require("ducknet.udp")
local DHCP = require("ducknet.dhcp")

local arguments = { ... }
local action = arguments[1] or "status"

local function load(path)
  path = path or "/etc/ducknet/config.lua"
  local settings, err = config.load(path)
  if not settings then error("could not load DuckNet config: " .. tostring(err), 0) end
  assert(not settings.interfaces, "DHCP client mode is for single-interface hosts")
  return settings, path
end

local function clientId(settings)
  if settings.dhcp and settings.dhcp.client and settings.dhcp.client.id then
    return settings.dhcp.client.id
  end
  if os.getComputerID then return "cc:" .. tostring(os.getComputerID()) end
  local ok, computer = pcall(require, "computer")
  if ok and computer.address then return "oc:" .. tostring(computer.address()) end
  return "ducknet:" .. tostring(math.random(1, 2147483647))
end

local function resolveModem(name)
  if type(peripheral) == "table" and type(peripheral.wrap) == "function" then
    local modem = name and peripheral.wrap(name) or peripheral.find("modem")
    assert(modem, "no modem found" .. (name and (" on " .. name) or ""))
    return modem
  end
  local component = require("component")
  return name and assert(component.proxy(name)) or component.modem
end

local function temporaryStack(modemName, channel)
  local link = Link.new(resolveModem(modemName), {
    modemName = modemName, address = "0.0.0.0", port = channel,
    broadcastUnknown = true
  })
  local ip = IP.new(link, { address = "0.0.0.0", ttl = 16 })
  return link, ip, UDP.new(ip)
end

local function networkFor(address, prefix)
  local a, b, c, d = address:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
  local value = ((tonumber(a) * 256 + tonumber(b)) * 256 + tonumber(c)) * 256 + tonumber(d)
  local block = 2 ^ (32 - prefix)
  value = math.floor(value / block) * block
  local bytes = {}
  for index = 4, 1, -1 do bytes[index], value = value % 256, math.floor(value / 256) end
  return string.format("%d.%d.%d.%d/%d", bytes[1], bytes[2], bytes[3], bytes[4], prefix)
end

local function installStartup(configPath)
  configPath = configPath or "/etc/ducknet/config.lua"
  if type(fs) == "table" then
    if not fs.exists("/startup") then fs.makeDir("/startup") end
    local file = assert(fs.open("/startup/10-ducknet-dhcp.lua", "w"))
    file.write("if multishell then\n" ..
      "  multishell.launch({}, \"/ducknet/bin/dhclient.lua\", \"daemon\", " ..
        string.format("%q", configPath) .. ")\n" ..
      "else\n" ..
      "  print(\"Renewing DuckNet DHCP lease...\")\n" ..
      "  shell.run(\"/ducknet/bin/dhclient.lua\", \"renew\", " ..
        string.format("%q", configPath) .. ")\n" ..
      "end\n")
    file.close()
    return
  end
  local servicePath = "/etc/rc.d/ducknet-dhcp.lua"
  local file = assert(io.open(servicePath, "w"))
  file:write("local worker\n" ..
    "function start()\n" ..
    "  if worker and worker:status() == \"running\" then return end\n" ..
    "  worker = require(\"thread\").create(function()\n" ..
    "    assert(loadfile(\"/usr/bin/dhclient.lua\"))(\"daemon\", " ..
      string.format("%q", configPath) .. ")\n" ..
    "  end):detach()\n" ..
    "end\n" ..
    "function stop() if worker then worker:kill(); worker = nil end end\n")
  file:close()
  local ok, shell = pcall(require, "shell")
  if ok then pcall(shell.execute, "rc ducknet-dhcp enable") end
end

local function acquire(settings, path, modemName, channel)
  local id = clientId(settings)
  local _, _, udp = temporaryStack(modemName, channel)
  local lease, err = DHCP.Client.acquire(udp, id)
  if not lease then error("DHCP failed: " .. tostring(err), 0) end
  local network = networkFor(lease.address, lease.prefix)
  settings.link = settings.link or {}
  settings.ip = settings.ip or {}
  settings.routes = settings.routes or {}
  settings.link.port = channel
  settings.link.modem = modemName
  settings.ip.address = lease.address
  for index = #settings.routes, 1, -1 do
    local route = settings.routes[index]
    if not route.via or route.network == "0.0.0.0/0" then table.remove(settings.routes, index) end
  end
  table.insert(settings.routes, 1, { network = network, metric = 10 })
  settings.routes[#settings.routes + 1] = {
    network = "0.0.0.0/0", via = lease.gateway, metric = 100
  }
  settings.dhcp = settings.dhcp or {}
  settings.dhcp.client = {
    enabled = true, id = id, modem = modemName, channel = channel,
    address = lease.address, server = lease.server,
    obtained = lease.obtained, expires = (lease.obtained or 0) + lease.lease
  }
  assert(config.save(settings, path))
  installStartup(path)
  io.write("leased " .. lease.address .. "/" .. lease.prefix ..
    " via " .. lease.gateway .. " for " .. lease.lease .. " seconds\n")
end

if action == "enable" then
  local modemName = arguments[2]
  if not modemName then error("usage: dhclient enable <modem-side> [channel] [config.lua]", 0) end
  local channel = tonumber(arguments[3] or "4660")
  assert(channel and channel % 1 == 0 and channel >= 0 and channel <= 65535,
    "channel must be between 0 and 65535")
  local settings, path = load(arguments[4])
  acquire(settings, path, modemName, channel)
  return
end

if action == "renew" then
  local settings, path = load(arguments[2])
  local client = settings.dhcp and settings.dhcp.client
  assert(client and client.enabled, "DHCP client is not enabled")
  acquire(settings, path, client.modem, client.channel or 4660)
  return
end

if action == "daemon" then
  while true do
    local settings = load(arguments[2])
    local client = settings.dhcp and settings.dhcp.client
    if not client or not client.enabled then return end
    local ok, err = pcall(acquire, settings, arguments[2] or "/etc/ducknet/config.lua",
      client.modem, client.channel or 4660)
    if not ok then io.stderr:write("DHCP renewal failed: " .. tostring(err) .. "\n") end
    local refreshed = config.load(arguments[2] or "/etc/ducknet/config.lua")
    local active = refreshed and refreshed.dhcp and refreshed.dhcp.client
    local delay = active and active.obtained and active.expires and
      math.max(30, math.floor((active.expires - active.obtained) / 2)) or 60
    if type(sleep) == "function" then sleep(delay)
    else require("event").pull(delay) end
  end
end

if action == "status" then
  local settings = load(arguments[2])
  local client = settings.dhcp and settings.dhcp.client
  if not client or not client.enabled then io.write("DHCP client is disabled\n") return end
  io.write("DHCP client " .. client.id .. "\n")
  io.write("  Address: " .. tostring(client.address) .. "\n")
  io.write("  Server:  " .. tostring(client.server) .. "\n")
  io.write("  Expires: " .. tostring(client.expires) .. "\n")
  return
end

if action == "release" then
  local settings, path = load(arguments[2])
  local client = settings.dhcp and settings.dhcp.client
  assert(client and client.enabled, "DHCP client is not enabled")
  local _, _, udp = temporaryStack(client.modem, client.channel or 4660)
  DHCP.Client.release(udp, client.id, client.address)
  client.enabled = false
  settings.ip.address = "0.0.0.0"
  for index = #(settings.routes or {}), 1, -1 do
    local route = settings.routes[index]
    if not route.via or route.network == "0.0.0.0/0" then
      table.remove(settings.routes, index)
    end
  end
  assert(config.save(settings, path))
  if type(fs) == "table" and fs.exists("/startup/10-ducknet-dhcp.lua") then
    fs.delete("/startup/10-ducknet-dhcp.lua")
  elseif type(fs) ~= "table" then
    local ok, filesystem = pcall(require, "filesystem")
    if ok and filesystem.exists("/etc/rc.d/ducknet-dhcp.lua") then
      local shellOk, shell = pcall(require, "shell")
      if shellOk then pcall(shell.execute, "rc ducknet-dhcp disable") end
      filesystem.remove("/etc/rc.d/ducknet-dhcp.lua")
    end
  end
  io.write("released " .. tostring(client.address) .. "\n")
  return
end

error("usage: dhclient enable|renew|status|release", 0)
