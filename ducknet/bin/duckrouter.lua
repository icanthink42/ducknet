local config = require("ducknet.config")
local ducknet = require("ducknet")

local arguments = { ... }
local settings, configError = config.load(arguments[1])
if not settings then error("could not load config: " .. tostring(configError), 0) end
settings.ip.forwarding = true
local stack = ducknet.stack(settings)
local dhcpServer
if settings.dhcp and settings.dhcp.pools and #settings.dhcp.pools > 0 then
  local ok, serverOrError = pcall(ducknet.DHCP.server, stack.udp, stack.ip, settings.dhcp)
  if ok then
    dhcpServer = serverOrError
  else
    io.stderr:write("DuckNet DHCP is disabled: " .. tostring(serverOrError) .. "\n")
  end
end
local addresses = {}
for _, interface in ipairs(stack.ip.interfaces) do
  addresses[#addresses + 1] = interface.name .. "=" .. interface.address
end
io.write("DuckNet router is forwarding packets (" .. table.concat(addresses, ", ") .. ")\n")
if dhcpServer then io.write("DuckNet DHCP is serving configured interface pools\n") end
while true do stack.ip:pump(math.huge) end
