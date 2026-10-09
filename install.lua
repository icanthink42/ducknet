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
    { "ducknet/lib/ducknet/config.lua", "/usr/lib/ducknet/config.lua" },
    { "ducknet/etc/ducknet/config.lua", "/etc/ducknet/config.lua", true },
    { "uninstall.lua", "/usr/bin/uninstall-ducknet.lua" }
  },
  tcp = {
    { "ducknet/lib/ducknet/tcp.lua", "/usr/lib/ducknet/tcp.lua" }
  },
  dltp = {
    { "ducknet/lib/ducknet/crypto.lua", "/usr/lib/ducknet/crypto.lua" },
    { "ducknet/lib/ducknet/dltp.lua", "/usr/lib/ducknet/dltp.lua" },
    { "ducknet/lib/ducknet/init.lua", "/usr/lib/ducknet.lua" }
  },
  server = {
    { "ducknet/bin/duckserve.lua", "/usr/bin/serve.lua" },
    { "examples/server.lua", "/usr/share/ducknet/server.lua" },
    { "sites/foo-bar.lua", "/usr/share/ducknet/sites/foo-bar.lua" },
    { "examples/server.lua", "/usr/share/ducknet/sites/hello-world.lua" }
  },
  router = {
    { "ducknet/bin/duckrouter.lua", "/usr/bin/router.lua" },
    { "examples/router.lua", "/usr/share/ducknet/router.lua" }
  },
  tools = {
    { "ducknet/lib/ducknet/cli.lua", "/usr/lib/ducknet/cli.lua" },
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
    { "niobium/bin/niobium.lua", "/usr/bin/niobium.lua" }
  }
}

local dependencies = {
  core = {}, tcp = { "core" }, dltp = { "core", "tcp" },
  server = { "dltp" }, router = { "core" }, tools = { "dltp" },
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
io.write("Profiles: client, router, server, developer, custom\n")
local profile = ask("Profile", "client"):lower()
local profiles = {
  client = { "niobium", "tools" },
  router = { "router", "tools" },
  server = { "server", "tools" },
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
    "/ipconfig.lua", "/route.lua", "/arp.lua", "/ping.lua",
    "/traceroute.lua", "/dltp.lua", "/router.lua", "/serve.lua",
    "/niobium.lua", "/uninstall-ducknet.lua", "/ducknet.lua", "/niobium",
    "/duck-ipconfig.lua", "/duck-route.lua", "/duck-neighbors.lua",
    "/duck-ping.lua", "/duck-traceroute.lua", "/duck-router.lua",
    "/duckserve.lua"
  } or {
    "/usr/bin/duck-ipconfig.lua", "/usr/bin/duck-route.lua",
    "/usr/bin/duck-neighbors.lua", "/usr/bin/duck-ping.lua",
    "/usr/bin/duck-traceroute.lua", "/usr/bin/duck-router.lua",
    "/usr/bin/duckserve.lua"
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

local function configureNetwork(role)
  if hadConfig and not yes("Replace the existing DuckNet configuration", false) then
    io.write("keep " .. configPath .. "\n")
    return
  end
  io.write("\nConfigure the " .. role .. "\n")
  local defaultHost = 2
  if role == "router" then defaultHost = 1
  elseif role == "server" then defaultHost = 10
  elseif isComputerCraft and os.getComputerID then defaultHost = os.getComputerID() % 240 + 11 end
  local address = ask("DuckNet IP address", "10.0.0." .. defaultHost)
  local channel = number("Modem channel", 4660, 0, 65535)
  local ttl = number("Default TTL", 16, 1, 255)
  local directNetwork = ask("Directly connected network", "10.0.0.0/24")
  local dltpPort = number("DLTP port", role == "server" and 80 or 80, 1, 65535)
  local routes = { { network = directNetwork, metric = 10 } }

  if role ~= "router" then
    local gateway = ask("Default gateway (blank for none)", "")
    if gateway ~= "" then
      routes[#routes + 1] = { network = "0.0.0.0/0", via = gateway, metric = 100 }
    end
  else
    while yes("Add another route", false) do
      routes[#routes + 1] = {
        network = ask("Destination network (CIDR)"),
        via = ask("Next-hop DuckNet IP"),
        metric = number("Metric", 100, 0, 65535)
      }
    end
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
  for _, peer in ipairs(peers) do
    lines[#lines + 1] = "      [" .. quote(peer.address) .. "] = " .. quote(peer.modem) .. ","
  end
  lines[#lines + 1] = "    }"
  lines[#lines + 1] = "  },"
  lines[#lines + 1] = "  ip = { address = " .. quote(address) ..
    ", forwarding = " .. tostring(role == "router") .. ", ttl = " .. ttl .. " },"
  lines[#lines + 1] = "  routes = {"
  for _, route in ipairs(routes) do
    local via = route.via and (", via = " .. quote(route.via)) or ""
    lines[#lines + 1] = "    { network = " .. quote(route.network) .. via ..
      ", metric = " .. route.metric .. " },"
  end
  lines[#lines + 1] = "  },"
  lines[#lines + 1] = "  tcp = { mtu = 4096, timeout = 2, retries = 4 },"
  lines[#lines + 1] = "  dltp = { port = " .. dltpPort .. " }"
  lines[#lines + 1] = "}"
  writeAtomic(configPath, table.concat(lines, "\n") .. "\n")
  io.write("configured " .. configPath .. "\n")
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
  io.write("  3. GitHub URL\n")
  local choice = ask("Website", "1")
  local body
  if choice == "1" or choice:lower() == "foo-bar" then
    body = readFile(destinationForPlatform("/usr/share/ducknet/sites/foo-bar.lua"))
  elseif choice == "2" or choice:lower() == "hello-world" then
    body = readFile(destinationForPlatform("/usr/share/ducknet/sites/hello-world.lua"))
  elseif choice == "3" or choice:lower() == "github" then
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
  assert(role == "router" or role == "server", "invalid startup role")
  if isComputerCraft then
    makeDirectory("/startup")
    local opposite = role == "router" and "/startup/ducknet-server.lua" or
      "/startup/ducknet-router.lua"
    if exists(opposite) then remove(opposite) end
    local program = role == "router" and "/ducknet/bin/router.lua" or
      "/ducknet/bin/serve.lua"
    local arguments = role == "server" and (", " .. quote("/etc/ducknet/site.lua")) or ""
    local body = "print(" .. quote("Starting DuckNet " .. role .. "...") .. ")\n" ..
      "local ok = shell.run(" .. quote(program) .. arguments .. ")\n" ..
      "if not ok then printError(" .. quote("DuckNet " .. role .. " stopped") .. ") end\n"
    assert(load(body, "=ducknet-startup"))
    writeAtomic("/startup/ducknet-" .. role .. ".lua", body)
  else
    local opposite = role == "router" and "ducknet-server" or "ducknet-router"
    local oppositePath = "/etc/rc.d/" .. opposite .. ".lua"
    local shell = require("shell")
    if exists(oppositePath) then
      pcall(shell.execute, "rc " .. opposite .. " disable")
      remove(oppositePath)
    end
    local program = role == "router" and "/usr/bin/router.lua" or
      "/usr/bin/serve.lua"
    local argument = role == "server" and "/etc/ducknet/site.lua" or nil
    local lines = {
      "local worker",
      "function start()",
      "  if worker and worker:status() == \"running\" then return end",
      "  worker = require(\"thread\").create(function()",
      "    local program = assert(loadfile(" .. quote(program) .. "))"
    }
    if argument then
      lines[#lines + 1] = "    program(" .. quote(argument) .. ")"
    else
      lines[#lines + 1] = "    program()"
    end
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
  io.write("enabled DuckNet " .. role .. " at startup\n")
end

if profile == "client" or profile == "router" or profile == "server" then
  configureNetwork(profile)
end
if profile == "server" then configureSite() end
if profile == "router" or profile == "server" then configureStartup(profile) end

io.write("\nDuckNet installed for " .. (isComputerCraft and "CC:Tweaked" or "OpenComputers") ..
  " from " .. (useBundle and "release " or "branch ") .. branch .. ".\n")
if profile == "router" then
  io.write("Start routing with: router\n")
elseif profile == "server" then
  io.write("Start the server with: serve /etc/ducknet/site.lua\n")
elseif profile == "client" then
  io.write("Open a site with: niobium dltp://<server-ip>/\n")
end
