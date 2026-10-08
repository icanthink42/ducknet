local cli = require("ducknet.cli")

local arguments = { ... }
local settings, link, ip = cli.load(arguments[1], false)

io.write("DuckNet adapter\n")
io.write("  IP address . . . . . : " .. ip.address .. "\n")
io.write("  Modem address  . . . : " .. tostring(link.modem.address or "unknown") .. "\n")
io.write("  Modem port . . . . . : " .. tostring(link.port) .. "\n")
io.write("  Forwarding . . . . . : " .. (ip.forwarding and "enabled" or "disabled") .. "\n")
io.write("  Default TTL . . . . . : " .. tostring(ip.defaultTTL) .. "\n")
local routeCount, peerCount = #(settings.routes or {}), 0
for _ in pairs(link.peers) do peerCount = peerCount + 1 end
io.write("  Routes / neighbors  . : " .. routeCount .. " / " .. peerCount .. "\n")

