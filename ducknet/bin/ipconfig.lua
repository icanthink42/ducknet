local cli = require("ducknet.cli")

local arguments = { ... }
local settings, _, ip, _, stack = cli.load(arguments[1], false)

io.write("DuckNet adapter\n")
for index, interface in ipairs(ip.interfaces) do
  local link = interface.link
  io.write(string.format("  Interface %s%s\n", interface.name,
    index == 1 and " (primary)" or ""))
  io.write("    IP address . . . . : " .. interface.address .. "\n")
  io.write("    Platform . . . . . : " .. tostring(link.platform) .. "\n")
  io.write("    Modem address  . . : " ..
    tostring(link.modem.address or link.modemName or "wireless") .. "\n")
  io.write("    Modem port . . . . : " .. tostring(link.port) .. "\n")
end
io.write("  Forwarding . . . . . : " .. (ip.forwarding and "enabled" or "disabled") .. "\n")
io.write("  Default TTL . . . . . : " .. tostring(ip.defaultTTL) .. "\n")
local routeCount, peerCount = #ip.routes, 0
for _, link in ipairs(stack.links) do
  for _ in pairs(link.peers) do peerCount = peerCount + 1 end
end
io.write("  Routes / neighbors  . : " .. routeCount .. " / " .. peerCount .. "\n")
