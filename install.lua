local component = require("component")
local filesystem = require("filesystem")
local internet = require("internet")

assert(component.isAvailable("internet"), "an internet card is required")

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
local function download(source, destination, preserve)
  if preserve and filesystem.exists(destination) then
    io.write("keep " .. destination .. "\n")
    return
  end
  filesystem.makeDirectory(parent(destination))
  local url = base .. "/" .. branch .. "/" .. source
  io.write("get  " .. source .. "\n")
  local handle, reason = internet.request(url)
  assert(handle, reason or ("request failed: " .. url))
  local temporary = destination .. ".ducknet-new"
  local file = assert(io.open(temporary, "wb"))
  local ok, failure = pcall(function()
    for chunk in handle do file:write(chunk) end
  end)
  file:close()
  if not ok then filesystem.remove(temporary) error(failure, 0) end
  if filesystem.exists(destination) then filesystem.remove(destination) end
  assert(filesystem.rename(temporary, destination))
end

local order = { "core", "tcp", "dltp", "server", "tools", "niobium" }
for _, name in ipairs(order) do
  if selected[name] then
    for _, file in ipairs(packages[name]) do download(file[1], file[2], file[3]) end
  end
end
io.write("DuckNet installed from branch " .. branch .. ". Edit /etc/ducknet/config.lua next.\n")
