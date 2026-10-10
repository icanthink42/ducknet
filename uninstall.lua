local isComputerCraft = type(fs) == "table" and type(os) == "table" and
  type(os.pullEvent) == "function"
local filesystem
if not isComputerCraft then filesystem = require("filesystem") end

local function exists(path)
  if isComputerCraft then return fs.exists(path) end
  return filesystem.exists(path)
end

local function removeTree(path)
  if not exists(path) then return end
  if isComputerCraft then
    fs.delete(path)
    return
  end
  if filesystem.isDirectory(path) then
    for child in filesystem.list(path) do
      removeTree(filesystem.concat(path, child))
    end
  end
  filesystem.remove(path)
end

local function askYes(prompt)
  io.write(prompt .. " (y/N): ")
  local answer = io.read()
  return answer and answer:lower():sub(1, 1) == "y"
end

if not isComputerCraft then
  local ok, shell = pcall(require, "shell")
  if ok then
    pcall(shell.execute, "rc ducknet-router disable")
    pcall(shell.execute, "rc ducknet-server disable")
    pcall(shell.execute, "rc ducknet-dhcp disable")
  end
end

local common = isComputerCraft and {
  "/ducknet.lua", "/ducknet", "/niobium",
  "/ipconfig.lua", "/route.lua", "/arp.lua", "/ping.lua",
  "/traceroute.lua", "/dltp.lua", "/router.lua", "/serve.lua",
  "/niobium.lua", "/uninstall-ducknet.lua",
  "/duck-ipconfig.lua", "/duck-route.lua", "/duck-neighbors.lua",
  "/duck-ping.lua", "/duck-traceroute.lua", "/duck-router.lua",
  "/duckserve.lua", "/startup/ducknet-router.lua",
  "/startup/ducknet-server.lua", "/startup/00-ducknet-path.lua",
  "/startup/10-ducknet-dhcp.lua"
} or {
  "/usr/lib/ducknet.lua", "/usr/lib/ducknet", "/usr/lib/niobium",
  "/usr/share/ducknet", "/usr/bin/ip.lua", "/usr/bin/ipconfig.lua", "/usr/bin/route.lua",
  "/usr/bin/arp.lua", "/usr/bin/ping.lua", "/usr/bin/traceroute.lua",
  "/usr/bin/dltp.lua", "/usr/bin/dhclient.lua", "/usr/bin/dhcpd.lua",
  "/usr/bin/router.lua", "/usr/bin/serve.lua",
  "/usr/bin/niobium.lua", "/usr/bin/uninstall-ducknet.lua",
  "/usr/bin/duck-ipconfig.lua", "/usr/bin/duck-route.lua",
  "/usr/bin/duck-neighbors.lua", "/usr/bin/duck-ping.lua",
  "/usr/bin/duck-traceroute.lua", "/usr/bin/duck-router.lua",
  "/usr/bin/duckserve.lua", "/etc/rc.d/ducknet-router.lua",
  "/etc/rc.d/ducknet-server.lua", "/etc/rc.d/ducknet-dhcp.lua"
}

for _, path in ipairs(common) do
  if exists(path) then
    io.write("remove " .. path .. "\n")
    removeTree(path)
  end
end

if isComputerCraft and shell and shell.path and shell.setPath then
  local kept = {}
  for entry in shell.path():gmatch("[^:]+") do
    if entry ~= "/ducknet/bin" then kept[#kept + 1] = entry end
  end
  shell.setPath(table.concat(kept, ":"))
end

if exists("/etc/ducknet") and askYes("Remove DuckNet configuration and active website") then
  removeTree("/etc/ducknet")
end

io.write("DuckNet has been uninstalled.\n")
