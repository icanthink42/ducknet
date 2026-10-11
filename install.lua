local isComputerCraft = type(fs) == "table" and type(http) == "table" and
  type(os) == "table" and type(os.pullEvent) == "function"
-- The release builder replaces these two declarations. Keeping them nil makes
-- this source installer fetch the selected development branch as before.
local BUNDLED_FILES = nil
local BUNDLED_VERSION = nil
local component, filesystem, internet
if not isComputerCraft then
  component = require("component")
  filesystem = require("filesystem")
  internet = require("internet")
  assert(component.isAvailable("internet"), "an internet card is required")
else
  assert(http.get, "CC:Tweaked HTTP access must be enabled")
end

local packages = {
  core = {
    { "ducknet/lib/ducknet/codec.lua", "/usr/lib/ducknet/codec.lua" },
    { "ducknet/lib/ducknet/modem.lua", "/usr/lib/ducknet/modem.lua" },
    { "ducknet/lib/ducknet/ip.lua", "/usr/lib/ducknet/ip.lua" },
    { "ducknet/lib/ducknet/icmp.lua", "/usr/lib/ducknet/icmp.lua" },
    { "ducknet/lib/ducknet/udp.lua", "/usr/lib/ducknet/udp.lua" },
    { "ducknet/lib/ducknet/dhcp.lua", "/usr/lib/ducknet/dhcp.lua" },
    { "ducknet/lib/ducknet/dns.lua", "/usr/lib/ducknet/dns.lua" },
    { "ducknet/lib/ducknet/config.lua", "/usr/lib/ducknet/config.lua" },
    { "ducknet/lib/ducknet/scrollterm.lua", "/usr/lib/ducknet/scrollterm.lua" },
    { "ducknet/etc/ducknet/config.lua", "/etc/ducknet/config.lua", true },
    { "uninstall.lua", "/usr/bin/uninstall-ducknet.lua" }
  },
  tcp = {
    { "ducknet/lib/ducknet/tcp.lua", "/usr/lib/ducknet/tcp.lua" }
  },
  dltp = {
    { "ducknet/lib/ducknet/dltp.lua", "/usr/lib/ducknet/dltp.lua" },
    { "ducknet/lib/ducknet/init.lua", "/usr/lib/ducknet.lua" }
  },
  server = {
    { "ducknet/bin/duckserve.lua", "/usr/bin/serve.lua" },
    { "examples/server.lua", "/usr/share/ducknet/server.lua" },
    { "sites/foo-bar.lua", "/usr/share/ducknet/sites/foo-bar.lua" },
    { "sites/player-tracker.lua", "/usr/share/ducknet/sites/player-tracker.lua" },
    { "examples/server.lua", "/usr/share/ducknet/sites/hello-world.lua" }
  },
  router = {
    { "ducknet/bin/duckrouter.lua", "/usr/bin/router.lua" },
    { "examples/router.lua", "/usr/share/ducknet/router.lua" }
  },
  tools = {
    { "ducknet/lib/ducknet/cli.lua", "/usr/lib/ducknet/cli.lua" },
    { "ducknet/bin/systemdck.lua", "/usr/bin/systemdck.lua" },
    { "ducknet/bin/networkd.lua", "/usr/bin/networkd.lua" },
    { "ducknet/bin/ip.lua", "/usr/bin/ip.lua" },
    { "ducknet/bin/dhclient.lua", "/usr/bin/dhclient.lua" },
    { "ducknet/bin/dhcpd.lua", "/usr/bin/dhcpd.lua" },
    { "ducknet/bin/dnsd.lua", "/usr/bin/dnsd.lua" },
    { "ducknet/bin/dnsctl.lua", "/usr/bin/dnsctl.lua" },
    { "ducknet/bin/dig.lua", "/usr/bin/dig.lua" },
    { "ducknet/bin/nslookup.lua", "/usr/bin/nslookup.lua" },
    { "ducknet/bin/host.lua", "/usr/bin/host.lua" },
    { "ducknet/bin/ipconfig.lua", "/usr/bin/ipconfig.lua" },
    { "ducknet/bin/route.lua", "/usr/bin/route.lua" },
    { "ducknet/bin/neighbors.lua", "/usr/bin/arp.lua" },
    { "ducknet/bin/ping.lua", "/usr/bin/ping.lua" },
    { "ducknet/bin/traceroute.lua", "/usr/bin/traceroute.lua" },
    { "ducknet/bin/dltp.lua", "/usr/bin/dltp.lua" }
  },
  niobium = {
    { "niobium/lib/niobium/sandbox.lua", "/usr/lib/niobium/sandbox.lua" },
    { "niobium/lib/niobium/ui.lua", "/usr/lib/niobium/ui.lua" },
    { "niobium/lib/niobium/url.lua", "/usr/lib/niobium/url.lua" },
    { "niobium/bin/niobium.lua", "/usr/bin/niobium.lua" }
  }
}

local dependencies = {
  core = {}, tcp = { "core" }, dltp = { "core", "tcp" },
  server = { "dltp" }, router = { "dltp" }, tools = { "dltp" },
  niobium = { "dltp" }
}

local DEFAULT_REPOSITORY = "https://raw.githubusercontent.com/icanthink42/ducknet"

local function ask(prompt, fallback)
  io.write(prompt .. (fallback and " [" .. fallback .. "]" or "") .. ": ")
  local answer = io.read()
  if not answer or answer == "" then return fallback end
  return answer
end

local arguments = { ... }
local base = arguments[1] or DEFAULT_REPOSITORY
assert(base and base:match("^https?://"), "a http(s) repository URL is required")
base = base:gsub("/+$", "")
local branch = ask(BUNDLED_VERSION and "Branch or bundled release" or "Branch",
  BUNDLED_VERSION or "main")
assert(branch:match("^[%w%._/-]+$") and not branch:find("%.%."), "invalid branch")
local useBundle = BUNDLED_FILES ~= nil and branch == BUNDLED_VERSION

local selected = {}
io.write("Profiles: client, router, server, dns, developer, custom\n")
local profile = ask("Profile", "client"):lower()
local profiles = {
  client = { "niobium", "tools" },
  router = { "router", "tools" },
  server = { "server", "tools" },
  dns = { "tools" },
  developer = { "core", "tcp", "dltp", "server", "router", "tools", "niobium" }
}
assert(profiles[profile] or profile == "custom", "unknown profile: " .. profile)
if profile == "custom" then
  io.write("Packages: core, tcp, dltp, server, router, tools, niobium, or all\n")
  local selection = ask("Install", "all")
  if selection == "all" then
    for name in pairs(packages) do selected[name] = true end
  else
    for name in selection:gmatch("[%w_-]+") do
      assert(packages[name], "unknown package: " .. name)
      selected[name] = true
    end
  end
else
  for _, name in ipairs(profiles[profile]) do selected[name] = true end
end
if profile == "developer" then
  for name in pairs(packages) do selected[name] = true end
end

local function includeDependencies(name)
  for _, dependency in ipairs(dependencies[name]) do
    if not selected[dependency] then selected[dependency] = true includeDependencies(dependency) end
  end
end
for name in pairs(selected) do includeDependencies(name) end

local function parent(path) return path:match("^(.*)/[^/]+$") end

local function destinationForPlatform(destination)
  if not isComputerCraft then return destination end
  if destination == "/usr/lib/ducknet.lua" then return "/ducknet/lib/ducknet.lua" end
  destination = destination:gsub("^/usr/lib/ducknet/", "/ducknet/lib/ducknet/")
  destination = destination:gsub("^/usr/lib/niobium/", "/ducknet/lib/niobium/")
  destination = destination:gsub("^/usr/bin/", "/ducknet/bin/")
  destination = destination:gsub("^/usr/share/ducknet/", "/ducknet/share/")
  return destination
end

local function exists(path)
  if isComputerCraft then return fs.exists(path) end
  return filesystem.exists(path)
end

local function makeDirectory(path)
  if isComputerCraft then fs.makeDir(path) else filesystem.makeDirectory(path) end
end

local function remove(path)
  if isComputerCraft then fs.delete(path) else filesystem.remove(path) end
end

local function rename(source, destination)
  if isComputerCraft then fs.move(source, destination) return true end
  return filesystem.rename(source, destination)
end

local function fetch(url)
  if isComputerCraft then
    local handle, reason, failure = http.get(url, nil, true)
    if not handle then
      if failure and failure.close then failure.close() end
      return nil, reason
    end
    local body = handle.readAll()
    handle.close()
    return body
  end
  local handle, reason = internet.request(url)
  if not handle then return nil, reason end
  local chunks = {}
  local ok, failure = pcall(function()
    for chunk in handle do chunks[#chunks + 1] = chunk end
  end)
  if not ok then return nil, failure end
  return table.concat(chunks)
end

local function writeFile(path, body)
  if isComputerCraft then
    local file = assert(fs.open(path, "wb"))
    file.write(body)
    file.close()
  else
    local file = assert(io.open(path, "wb"))
    file:write(body)
    file:close()
  end
end

local function readFile(path)
  if isComputerCraft then
    local file = assert(fs.open(path, "rb"))
    local body = file.readAll()
    file.close()
    return body
  end
  local file = assert(io.open(path, "rb"))
  local body = file:read("*a")
  file:close()
  return body
end

local function writeAtomic(path, body)
  makeDirectory(parent(path))
  local temporary = path .. ".ducknet-new"
  writeFile(temporary, body)
  if exists(path) then remove(path) end
  assert(rename(temporary, path))
end

local function download(source, destination, preserve)
  destination = destinationForPlatform(destination)
  if preserve and exists(destination) then
    io.write("keep " .. destination .. "\n")
    return
  end
  makeDirectory(parent(destination))
  local url = base .. "/" .. branch .. "/" .. source
  io.write("get  " .. source .. "\n")
  local body, reason
  if useBundle then body = BUNDLED_FILES[source] else body, reason = fetch(url) end
  assert(body, reason or ("request failed: " .. url))
  if isComputerCraft and destination:match("^/ducknet/bin/") then
    body = "package.path = \"/ducknet/lib/?.lua;/ducknet/lib/?/init.lua;\" .. package.path\n" .. body
  end
  local temporary = destination .. ".ducknet-new"
  writeFile(temporary, body)
  if exists(destination) then remove(destination) end
  assert(rename(temporary, destination))
end

local function removeLegacyCommands()
  local paths = isComputerCraft and {
    "/ducknet/lib/ducknet/crypto.lua",
    "/ipconfig.lua", "/route.lua", "/arp.lua", "/ping.lua",
    "/traceroute.lua", "/dltp.lua", "/router.lua", "/serve.lua",
    "/niobium.lua", "/uninstall-ducknet.lua", "/ducknet.lua", "/niobium",
    "/duck-ipconfig.lua", "/duck-route.lua", "/duck-neighbors.lua",
    "/duck-ping.lua", "/duck-traceroute.lua", "/duck-router.lua",
    "/duckserve.lua", "/ducknet/bin/systemdck-run.lua",
    "/startup/10-systemdck.lua"
  } or {
    "/usr/lib/ducknet/crypto.lua",
    "/usr/bin/duck-ipconfig.lua", "/usr/bin/duck-route.lua",
    "/usr/bin/duck-neighbors.lua", "/usr/bin/duck-ping.lua",
    "/usr/bin/duck-traceroute.lua", "/usr/bin/duck-router.lua",
    "/usr/bin/duckserve.lua", "/usr/bin/systemdck-run.lua"
  }
  for _, path in ipairs(paths) do
    if exists(path) then remove(path) end
  end
end

local function configureCommandPath()
  if not isComputerCraft then return end
  local bin = "/ducknet/bin"
  local function add(path)
    if path:find(bin, 1, true) then return path end
    return path .. ":" .. bin
  end
  shell.setPath(add(shell.path()))
  local body = [[local bin = "/ducknet/bin"
local path = shell.path()
if not path:find(bin, 1, true) then shell.setPath(path .. ":" .. bin) end
]]
  writeAtomic("/startup/00-ducknet-path.lua", body)
end

local configPath = "/etc/ducknet/config.lua"
local hadConfig = exists(configPath)
local order = { "core", "tcp", "dltp", "server", "router", "tools", "niobium" }
for _, name in ipairs(order) do
  if selected[name] then
    for _, file in ipairs(packages[name]) do download(file[1], file[2], file[3]) end
  end
end
removeLegacyCommands()
configureCommandPath()

local function yes(prompt, fallback)
  local marker = fallback and "Y/n" or "y/N"
  local answer = ask(prompt .. " (" .. marker .. ")", fallback and "y" or "n")
  return answer:lower():sub(1, 1) == "y"
end

local function number(prompt, fallback, minimum, maximum)
  local value = tonumber(ask(prompt, tostring(fallback)))
  assert(value and value % 1 == 0 and value >= minimum and value <= maximum,
    prompt .. " must be between " .. minimum .. " and " .. maximum)
  return value
end

local function quote(value)
  return string.format("%q", value)
end

local function defaultSubnet(address)
  local first, second, third, fourth =
    address:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
  if first and tonumber(first) <= 255 and tonumber(second) <= 255 and
      tonumber(third) <= 255 and tonumber(fourth) <= 255 then
    return first .. "." .. second .. "." .. third .. ".0/24"
  end
  return "10.0.0.0/24"
end

local function ipv4(value)
  local first, second, third, fourth =
    tostring(value):match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
  first, second, third, fourth = tonumber(first), tonumber(second),
    tonumber(third), tonumber(fourth)
  assert(first and first <= 255 and second <= 255 and third <= 255 and fourth <= 255,
    "invalid IPv4 address: " .. tostring(value))
  return ((first * 256 + second) * 256 + third) * 256 + fourth
end

local function formatIPv4(value)
  local fourth = value % 256
  value = math.floor(value / 256)
  local third = value % 256
  value = math.floor(value / 256)
  local second = value % 256
  local first = math.floor(value / 256)
  return string.format("%d.%d.%d.%d", first, second, third, fourth)
end

local function subnetInfo(cidr, minimumHosts)
  local value, prefix = tostring(cidr):match("^([^/]+)/(%d+)$")
  prefix = tonumber(prefix)
  assert(value and prefix and prefix >= 0 and prefix <= 32,
    "subnet must use IPv4 CIDR notation")
  local block = 2 ^ (32 - prefix)
  if minimumHosts then
    assert(prefix <= 30 and block - 2 >= minimumHosts,
      "subnet does not have enough usable addresses")
  end
  local base = math.floor(ipv4(value) / block) * block
  return {
    cidr = formatIPv4(base) .. "/" .. prefix,
    prefix = prefix, base = base, block = block,
    first = minimumHosts and formatIPv4(base + 1) or nil,
    second = minimumHosts and formatIPv4(base + 2) or nil,
    last = minimumHosts and formatIPv4(base + block - 2) or nil
  }
end

local function overlaps(left, right)
  return left.base < right.base + right.block and right.base < left.base + left.block
end

local function transitSubnet(index)
  return formatIPv4(ipv4("10.255.0.0") + ((index - 1) * 4)) .. "/30"
end

local function configureNetwork(role)
  if hadConfig and not yes("Replace the existing DuckNet configuration", false) then
    io.write("keep " .. configPath .. "\n")
    return false
  end
  io.write("\nConfigure the " .. role .. "\n")
  local address, channel, subnet
  local routes, interfaces, dhcpPools = {}, nil, {}
  local ttl, dltpPort
  local routerPreset, clientDHCP

  if role == "client" then
    local modem = ask("Modem side or component address", "left")
    channel = number("Modem channel", 4660, 0, 65535)
    ttl = number("Default TTL", 16, 1, 255)
    dltpPort = number("DLTP port", 80, 1, 65535)
    address = "0.0.0.0"
    clientDHCP = { modem = modem, channel = channel }
  elseif role ~= "router" then
    local defaultHost = role == "server" and 10 or role == "dns" and 53 or 2
    address = ask("DuckNet IP address", "10.0.0." .. defaultHost)
    channel = number("Modem channel", 4660, 0, 65535)
    ttl = number("Default TTL", 16, 1, 255)
    subnet = ask("Subnet", defaultSubnet(address))
    dltpPort = number("DLTP port", 80, 1, 65535)
    routes[1] = { network = subnet, metric = 10 }
    local gateway = ask("Default gateway (blank for none)", "")
    if gateway ~= "" then
      routes[#routes + 1] = { network = "0.0.0.0/0", via = gateway, metric = 100 }
    end
  else
    routerPreset = ask("Router preset (home/transit)", "home"):lower()
    assert(routerPreset == "home" or routerPreset == "transit",
      "router preset must be home or transit")
    ttl = number("Default TTL", 16, 1, 255)
    dltpPort = number("DLTP port", 80, 1, 65535)
    interfaces = {}
    local lanCount, transitCount = 0, 0

    local function checkInterfaceSubnet(info)
      for _, existing in ipairs(interfaces) do
        assert(not overlaps(info, subnetInfo(existing.network, 2)),
          "router interface subnets must not overlap")
      end
    end

    local function addLAN(defaultModem, defaultNetwork)
      lanCount = lanCount + 1
      local name = lanCount == 1 and "lan" or ("lan" .. lanCount)
      local modem = ask("LAN " .. lanCount .. " modem side or component address", defaultModem)
      local lan = subnetInfo(ask("LAN " .. lanCount .. " subnet", defaultNetwork), 2)
      checkInterfaceSubnet(lan)
      interfaces[#interfaces + 1] = {
        name = name, role = "lan", modem = modem, address = lan.first,
        port = number("LAN " .. lanCount .. " modem channel", 4660, 0, 65535),
        network = lan.cidr
      }
      if yes("Enable DHCP on LAN " .. lanCount, true) then
        local firstOffset = lan.block - 2 >= 100 and 100 or 2
        local lastOffset = lan.block - 2 >= 200 and 200 or lan.block - 2
        dhcpPools[#dhcpPools + 1] = {
          interface = name, first = formatIPv4(lan.base + firstOffset),
          last = formatIPv4(lan.base + lastOffset), network = lan.cidr,
          gateway = lan.first, lease = 3600
        }
      end
      io.write("LAN " .. lanCount .. ": gateway " .. lan.first ..
        " on " .. lan.cidr .. "\n")
    end

    local function addTransit(defaultModem, defaultPosition, askRemote, offerDefault)
      transitCount = transitCount + 1
      local name = "transit" .. transitCount
      local modem = ask("Transit " .. transitCount .. " modem side or component address",
        defaultModem)
      local link = subnetInfo(ask("Transit " .. transitCount .. " link subnet",
        transitSubnet(transitCount)), 2)
      checkInterfaceSubnet(link)
      local position = ask("This router uses the first or second address",
        defaultPosition):lower()
      assert(position == "first" or position == "second",
        "address position must be first or second")
      local localAddress = position == "first" and link.first or link.second
      local peerAddress = position == "first" and link.second or link.first
      interfaces[#interfaces + 1] = {
        name = name, role = "transit", modem = modem, address = localAddress,
        port = number("Transit " .. transitCount .. " modem channel", 4660, 0, 65535),
        network = link.cidr
      }
      if offerDefault and yes("Use this as the default transit link", transitCount == 1) then
        routes[#routes + 1] = {
          network = "0.0.0.0/0", via = peerAddress,
          interface = name, metric = 100
        }
      end
      if askRemote then
        local remote = ask("Subnet routed through the other router (blank for none)", "")
        if remote ~= "" then
          routes[#routes + 1] = {
            network = subnetInfo(remote).cidr, via = peerAddress,
            interface = name, metric = 100
          }
        end
      end
      io.write("Transit " .. transitCount .. ": this router " .. localAddress ..
        ", neighbor " .. peerAddress .. "\n")
    end

    if routerPreset == "home" then
      addLAN("left", "11.0.0.0/24")
      addTransit("right", "second", false, true)
      while yes("Add another transit link", false) do
        addTransit("back", "second", false, true)
      end
    else
      repeat
        addTransit(transitCount == 0 and "left" or "right", "first", true, false)
      until not yes("Add another transit link", transitCount < 2)
      while yes("Add a LAN to this router", false) do
        addLAN("back", "11.0.0.0/24")
      end
    end
    channel = interfaces[1].port
  end

  local peers = {}
  if not isComputerCraft then
    io.write("OpenComputers requires logical neighbor to modem-address mappings.\n")
    while yes("Add a modem neighbor", #peers == 0) do
      peers[#peers + 1] = {
        address = ask("Neighbor DuckNet IP"),
        modem = ask("Neighbor modem component address")
      }
    end
  end

  local lines = {
    "-- Generated by the DuckNet " .. role .. " profile.",
    "return {",
    "  link = {",
    "    port = " .. channel .. ",",
    "    broadcastUnknown = false,",
    "    peers = {"
  }
  if clientDHCP then
    table.insert(lines, 5, "    modem = " .. quote(clientDHCP.modem) .. ",")
  end
  for _, peer in ipairs(peers) do
    lines[#lines + 1] = "      [" .. quote(peer.address) .. "] = " .. quote(peer.modem) .. ","
  end
  lines[#lines + 1] = "    }"
  lines[#lines + 1] = "  },"
  if interfaces then
    lines[#lines + 1] = "  router = { preset = " .. quote(routerPreset) .. " },"
    lines[#lines + 1] = "  interfaces = {"
    for _, interface in ipairs(interfaces) do
      lines[#lines + 1] = "    { name = " .. quote(interface.name) ..
        ", role = " .. quote(interface.role) ..
        ", modem = " .. quote(interface.modem) ..
        ", address = " .. quote(interface.address) ..
        ", network = " .. quote(interface.network) ..
        ", port = " .. interface.port .. " },"
    end
    lines[#lines + 1] = "  },"
    lines[#lines + 1] = "  ip = { forwarding = true, ttl = " .. ttl .. " },"
  else
    lines[#lines + 1] = "  ip = { address = " .. quote(address) ..
      ", forwarding = false, ttl = " .. ttl .. " },"
  end
  lines[#lines + 1] = "  routes = {"
  for _, route in ipairs(routes) do
    local via = route.via and (", via = " .. quote(route.via)) or ""
    local interface = route.interface and (", interface = " .. quote(route.interface)) or ""
    lines[#lines + 1] = "    { network = " .. quote(route.network) .. via .. interface ..
      ", metric = " .. route.metric .. " },"
  end
  lines[#lines + 1] = "  },"
  if #dhcpPools > 0 then
    lines[#lines + 1] = "  dhcp = { pools = {"
    for _, pool in ipairs(dhcpPools) do
      lines[#lines + 1] = "    { interface = " .. quote(pool.interface) ..
        ", first = " .. quote(pool.first) .. ", last = " .. quote(pool.last) ..
        ", network = " .. quote(pool.network) .. ", gateway = " ..
        quote(pool.gateway) .. ", lease = " .. pool.lease .. " },"
    end
    lines[#lines + 1] = "  } },"
  elseif clientDHCP then
    lines[#lines + 1] = "  dhcp = { client = { enabled = true, modem = " ..
      quote(clientDHCP.modem) .. ", channel = " .. clientDHCP.channel .. " } },"
  end
  lines[#lines + 1] = "  tcp = { mtu = 4096, timeout = 2, retries = 4 },"
  lines[#lines + 1] = "  dns = { servers = {}, search = {} },"
  lines[#lines + 1] = "  dltp = { port = " .. dltpPort .. " }"
  lines[#lines + 1] = "}"
  writeAtomic(configPath, table.concat(lines, "\n") .. "\n")
  io.write("configured " .. configPath .. "\n")
  return { clientDHCP = clientDHCP, address = address }
end

local function dnsName(value)
  value = tostring(value):lower():gsub("%.$", "")
  if value == "" then return "" end
  assert(value:sub(1, 1) ~= "." and value:sub(-1) ~= "." and #value <= 253,
    "invalid DNS name")
  for label in value:gmatch("[^.]+") do
    assert(#label <= 63 and label:match("^[a-z0-9_-]+$") and
      not label:match("^-") and not label:match("-$"), "invalid DNS name")
  end
  assert(not value:find("..", 1, true), "invalid DNS name")
  return value
end

local function configureDNS(address)
  io.write("\nConfigure the DNS server\n")
  local mode = ask("DNS mode (authoritative/recursive/both)", "authoritative"):lower()
  assert(mode == "authoritative" or mode == "recursive" or mode == "both",
    "DNS mode must be authoritative, recursive, or both")
  local settings = { recursive = mode ~= "authoritative", roots = {}, zones = {} }

  if settings.recursive then
    local roots = ask("Root DNS server IPs (comma separated)")
    assert(roots and roots ~= "", "a recursive DNS server needs at least one root hint")
    for root in roots:gmatch("[^,%s]+") do
      ipv4(root)
      settings.roots[#settings.roots + 1] = root
    end
    assert(#settings.roots > 0, "a recursive DNS server needs at least one root hint")
  end

  if mode ~= "recursive" then
    local enteredZone = ask("Authoritative zone (. for the DNS root)", "duck")
    local zone = enteredZone == "." and "" or dnsName(enteredZone)
    local suffix = zone == "" and "root" or zone
    local nameserver = dnsName(ask("Primary nameserver", "ns." .. suffix))
    local administrator = dnsName(ask("Administrator DNS name", "hostmaster." .. suffix))
    assert(zone == "" or nameserver == zone or
      nameserver:sub(-#zone - 1) == "." .. zone,
      "the primary nameserver must be inside the authoritative zone")
    local ttl = number("Default DNS TTL", 300, 0, 2147483647)
    settings.zones[1] = { name = zone, records = {
      { name = zone, type = "SOA", value = nameserver .. " " .. administrator, ttl = ttl },
      { name = zone, type = "NS", value = nameserver, ttl = ttl },
      { name = nameserver, type = "A", value = address, ttl = ttl }
    } }
  end

  local function serializeList(values, indent)
    local lines = { "{" }
    for _, value in ipairs(values) do
      if type(value) == "string" then
        lines[#lines + 1] = indent .. "  " .. quote(value) .. ","
      else
        lines[#lines + 1] = indent .. "  { name = " .. quote(value.name) ..
          ", records = {"
        for _, record in ipairs(value.records) do
          lines[#lines + 1] = indent .. "    { name = " .. quote(record.name) ..
            ", type = " .. quote(record.type) .. ", value = " .. quote(record.value) ..
            ", ttl = " .. record.ttl .. " },"
        end
        lines[#lines + 1] = indent .. "  } },"
      end
    end
    lines[#lines + 1] = indent .. "}"
    return table.concat(lines, "\n")
  end

  local body = "-- Generated by the DuckNet DNS profile.\nreturn {\n" ..
    "  recursive = " .. tostring(settings.recursive) .. ",\n" ..
    "  roots = " .. serializeList(settings.roots, "  ") .. ",\n" ..
    "  zones = " .. serializeList(settings.zones, "  ") .. "\n}\n"
  assert(load(body, "=ducknet-dns-config"))
  writeAtomic("/etc/ducknet/dns.lua", body)
  io.write("configured /etc/ducknet/dns.lua\n")
end

local function githubRawUrl(url)
  local owner, repository, ref, path = url:match(
    "^https://github%.com/([^/]+)/([^/]+)/blob/([^/]+)/(.+)$")
  if owner then
    return "https://raw.githubusercontent.com/" .. owner .. "/" .. repository ..
      "/" .. ref .. "/" .. path:gsub("%?.*$", "")
  end
  return url
end

local function configureSite()
  io.write("\nWebsites:\n")
  io.write("  1. Foo Bar network test\n")
  io.write("  2. Hello World\n")
  io.write("  3. Player Tracker (Advanced Peripherals)\n")
  io.write("  4. GitHub URL\n")
  local choice = ask("Website", "1")
  local body
  if choice == "1" or choice:lower() == "foo-bar" then
    body = readFile(destinationForPlatform("/usr/share/ducknet/sites/foo-bar.lua"))
  elseif choice == "2" or choice:lower() == "hello-world" then
    body = readFile(destinationForPlatform("/usr/share/ducknet/sites/hello-world.lua"))
  elseif choice == "3" or choice:lower() == "player-tracker" then
    body = readFile(destinationForPlatform("/usr/share/ducknet/sites/player-tracker.lua"))
  elseif choice == "4" or choice:lower() == "github" then
    local url = githubRawUrl(ask("GitHub raw or blob URL"))
    assert(url:match("^https://"), "website URL must use HTTPS")
    local reason
    body, reason = fetch(url)
    assert(body, reason or "could not download website")
  else
    error("unknown website selection: " .. choice, 0)
  end
  local chunk, syntaxError = load(body, "=ducknet-site")
  assert(chunk, "website is not valid Lua: " .. tostring(syntaxError))
  writeAtomic("/etc/ducknet/site.lua", body)
  io.write("activated /etc/ducknet/site.lua\n")
end

local function configureStartup(role)
  assert(role == "router" or role == "server" or role == "dns", "invalid startup role")
  if isComputerCraft then
    makeDirectory("/startup")
    makeDirectory("/etc/systemdck")
    local oppositeRole = role == "router" and "server" or role == "server" and "router"
    if oppositeRole then
      local opposite = "/etc/systemdck/ducknet-" .. oppositeRole .. ".lua"
      if exists(opposite) then remove(opposite) end
      local legacyOpposite = "/startup/ducknet-" .. oppositeRole .. ".lua"
      if exists(legacyOpposite) then remove(legacyOpposite) end
    end
    local legacy = "/startup/ducknet-" .. role .. ".lua"
    if exists(legacy) then remove(legacy) end
    local program = role == "router" and "/ducknet/bin/router.lua" or
      role == "server" and "/ducknet/bin/serve.lua" or "/ducknet/bin/dnsd.lua"
    local arguments = role == "server" and "{ \"/etc/ducknet/site.lua\" }" or
      role == "dns" and "{ \"/etc/ducknet/config.lua\", \"/etc/ducknet/dns.lua\" }" or "{}"
    local body = "return {\n" ..
      "  description = " .. quote("DuckNet " .. (role == "dns" and "DNS" or role)) .. ",\n" ..
      "  program = " .. quote(program) .. ",\n" ..
      "  arguments = " .. arguments .. ",\n" ..
      "  enabled = true, restart = \"always\", restartDelay = 2,\n" ..
      "}\n"
    assert(load(body, "=systemdck-unit"))
    writeAtomic("/etc/systemdck/ducknet-" .. role .. ".lua", body)
    local boot = [[shell.run("/ducknet/bin/systemdck.lua", "boot")
]]
    writeAtomic("/startup/zz-systemdck.lua", boot)
    if exists("/startup/10-systemdck.lua") then remove("/startup/10-systemdck.lua") end
  else
    local shell = require("shell")
    local opposite = role == "router" and "ducknet-server" or
      role == "server" and "ducknet-router"
    if opposite then
      local oppositePath = "/etc/rc.d/" .. opposite .. ".lua"
      if exists(oppositePath) then
        pcall(shell.execute, "rc " .. opposite .. " disable")
        remove(oppositePath)
      end
    end
    local program = role == "router" and "/usr/bin/router.lua" or
      role == "server" and "/usr/bin/serve.lua" or "/usr/bin/dnsd.lua"
    local programArguments = role == "server" and { "/etc/ducknet/site.lua" } or
      role == "dns" and { "/etc/ducknet/config.lua", "/etc/ducknet/dns.lua" } or {}
    local lines = {
      "local worker",
      "function start()",
      "  if worker and worker:status() == \"running\" then return end",
      "  worker = require(\"thread\").create(function()",
      "    local program = assert(loadfile(" .. quote(program) .. "))"
    }
    local serializedArguments = {}
    for _, argument in ipairs(programArguments) do
      serializedArguments[#serializedArguments + 1] = quote(argument)
    end
    lines[#lines + 1] = "    program(" .. table.concat(serializedArguments, ", ") .. ")"
    lines[#lines + 1] = "  end):detach()"
    lines[#lines + 1] = "end"
    lines[#lines + 1] = "function stop()"
    lines[#lines + 1] = "  if worker then worker:kill(); worker = nil end"
    lines[#lines + 1] = "end"
    local body = table.concat(lines, "\n") .. "\n"
    assert(load(body, "=ducknet-rc-service"))
    local service = "ducknet-" .. role
    writeAtomic("/etc/rc.d/" .. service .. ".lua", body)
    pcall(shell.execute, "rc " .. service .. " disable")
    local enabled, reason = shell.execute("rc " .. service .. " enable")
    assert(enabled, "could not enable startup service: " .. tostring(reason))
  end
  io.write("enabled DuckNet " .. (role == "dns" and "DNS" or role) .. " at startup\n")
end

local function configureClientDHCPStartup()
  if isComputerCraft then
    makeDirectory("/startup")
    makeDirectory("/etc/systemdck")
    local unit = [[return {
  description = "DuckNet network configuration and DHCP renewal",
  program = "/ducknet/bin/networkd.lua",
  arguments = { "/etc/ducknet/config.lua" },
  enabled = true, restart = "always", restartDelay = 5,
}
]]
    writeAtomic("/etc/systemdck/ducknet-network.lua", unit)
    local body = [[shell.run("/ducknet/bin/systemdck.lua", "boot")
]]
    writeAtomic("/startup/zz-systemdck.lua", body)
    if exists("/startup/10-ducknet-dhcp.lua") then remove("/startup/10-ducknet-dhcp.lua") end
    if exists("/startup/10-systemdck.lua") then remove("/startup/10-systemdck.lua") end
    return
  end
  local body = [[local worker
function start()
  if worker and worker:status() == "running" then return end
  worker = require("thread").create(function()
    assert(loadfile("/usr/bin/dhclient.lua"))("daemon", "/etc/ducknet/config.lua")
  end):detach()
end
function stop() if worker then worker:kill(); worker = nil end end
]]
  writeAtomic("/etc/rc.d/ducknet-dhcp.lua", body)
  local shell = require("shell")
  pcall(shell.execute, "rc ducknet-dhcp disable")
  local enabled, reason = shell.execute("rc ducknet-dhcp enable")
  assert(enabled, "could not enable DHCP startup service: " .. tostring(reason))
end

local networkSetup
if profile == "client" or profile == "router" or profile == "server" or profile == "dns" then
  networkSetup = configureNetwork(profile)
end
if profile == "client" and networkSetup and networkSetup.clientDHCP then
  configureClientDHCPStartup()
  io.write("enabled DuckNet DHCP at startup\n")
end
if profile == "server" then configureSite() end
if profile == "dns" then
  local dnsAddress = networkSetup and networkSetup.address
  if not dnsAddress then
    local existing = assert(load(readFile(configPath), "=" .. configPath))()
    dnsAddress = assert(existing.ip and existing.ip.address,
      "the retained network configuration has no host IP address")
  end
  configureDNS(dnsAddress)
end
if profile == "router" or profile == "server" or profile == "dns" then
  configureStartup(profile)
end

io.write("\nDuckNet installed for " .. (isComputerCraft and "CC:Tweaked" or "OpenComputers") ..
  " from " .. (useBundle and "release " or "branch ") .. branch .. ".\n")
if profile == "router" then
  io.write("Reboot to start routing, or run: systemdck start ducknet-router\n")
elseif profile == "server" then
  io.write("Reboot to start the server, or run: systemdck start ducknet-server\n")
elseif profile == "client" then
  io.write("Reboot to acquire a DHCP address, then open a site with Niobium.\n")
elseif profile == "dns" then
  io.write("Reboot to start DNS, or run: systemdck start ducknet-dns\n")
end
