local isComputerCraft = type(fs) == "table" and type(http) == "table" and
  type(os) == "table" and type(os.pullEvent) == "function"
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
    { "ducknet/etc/ducknet/config.lua", "/etc/ducknet/config.lua", true }
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
    { "ducknet/bin/duckserve.lua", "/usr/bin/duckserve.lua" },
    { "examples/server.lua", "/usr/share/ducknet/server.lua" },
    { "examples/router.lua", "/usr/share/ducknet/router.lua" }
  },
  tools = {
    { "ducknet/lib/ducknet/cli.lua", "/usr/lib/ducknet/cli.lua" },
    { "ducknet/bin/ipconfig.lua", "/usr/bin/duck-ipconfig.lua" },
    { "ducknet/bin/route.lua", "/usr/bin/duck-route.lua" },
    { "ducknet/bin/neighbors.lua", "/usr/bin/duck-neighbors.lua" },
    { "ducknet/bin/ping.lua", "/usr/bin/duck-ping.lua" },
    { "ducknet/bin/traceroute.lua", "/usr/bin/duck-traceroute.lua" },
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
  server = { "dltp" }, tools = { "dltp" }, niobium = { "dltp" }
}

local function ask(prompt, fallback)
  io.write(prompt .. (fallback and " [" .. fallback .. "]" or "") .. ": ")
  local answer = io.read()
  if not answer or answer == "" then return fallback end
  return answer
end

local arguments = { ... }
local base = arguments[1] or ask("Raw repository URL (without branch)")
assert(base and base:match("^https?://"), "a http(s) repository URL is required")
base = base:gsub("/+$", "")
local branch = ask("Branch", "main")
assert(branch:match("^[%w%._/-]+$") and not branch:find("%.%."), "invalid branch")

io.write("Packages: core, tcp, dltp, server, tools, niobium, or all\n")
local selection = ask("Install", "all")
local selected = {}
if selection == "all" then
  for name in pairs(packages) do selected[name] = true end
else
  for name in selection:gmatch("[%w_-]+") do
    assert(packages[name], "unknown package: " .. name)
    selected[name] = true
  end
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
  if destination == "/usr/lib/ducknet.lua" then return "/ducknet.lua" end
  destination = destination:gsub("^/usr/lib/ducknet/", "/ducknet/")
  destination = destination:gsub("^/usr/lib/niobium/", "/niobium/")
  destination = destination:gsub("^/usr/bin/", "/")
  destination = destination:gsub("^/usr/share/ducknet/", "/ducknet/examples/")
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

local function download(source, destination, preserve)
  destination = destinationForPlatform(destination)
  if preserve and exists(destination) then
    io.write("keep " .. destination .. "\n")
    return
  end
  makeDirectory(parent(destination))
  local url = base .. "/" .. branch .. "/" .. source
  io.write("get  " .. source .. "\n")
  local body, reason = fetch(url)
  assert(body, reason or ("request failed: " .. url))
  local temporary = destination .. ".ducknet-new"
  writeFile(temporary, body)
  if exists(destination) then remove(destination) end
  assert(rename(temporary, destination))
end

local order = { "core", "tcp", "dltp", "server", "tools", "niobium" }
for _, name in ipairs(order) do
  if selected[name] then
    for _, file in ipairs(packages[name]) do download(file[1], file[2], file[3]) end
  end
end
io.write("DuckNet installed for " .. (isComputerCraft and "CC:Tweaked" or "OpenComputers") ..
  " from branch " .. branch .. ". Edit /etc/ducknet/config.lua next.\n")
