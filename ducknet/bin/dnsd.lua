local config = require("ducknet.config")
local ducknet = require("ducknet")

local arguments = { ... }
local networkPath = arguments[1] or "/etc/ducknet/config.lua"
local dnsPath = arguments[2] or "/etc/ducknet/dns.lua"
local settings, networkError = config.load(networkPath)
if not settings then error("could not load DuckNet config: " .. tostring(networkError), 0) end
local dnsSettings, dnsError = config.load(dnsPath)
if not dnsSettings then error("could not load DNS config: " .. tostring(dnsError), 0) end

local stack = ducknet.stack(settings)
local server = ducknet.DNS.server(stack.udp, dnsSettings)
local modes = {}
if #(dnsSettings.zones or {}) > 0 then modes[#modes + 1] = "authoritative" end
if dnsSettings.recursive then modes[#modes + 1] = "recursive" end
assert(#modes > 0, "DNS server has no zones and recursion is disabled")
io.write("DuckNet DNS server listening on UDP/53 (" .. table.concat(modes, ", ") .. ")\n")
server:run()
