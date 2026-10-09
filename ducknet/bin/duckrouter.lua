local config = require("ducknet.config")
local ducknet = require("ducknet")

local arguments = { ... }
local settings, configError = config.load(arguments[1])
if not settings then error("could not load config: " .. tostring(configError), 0) end
settings.ip.forwarding = true
local stack = ducknet.stack(settings)
local addresses = {}
for _, interface in ipairs(stack.ip.interfaces) do
  addresses[#addresses + 1] = interface.name .. "=" .. interface.address
end
io.write("DuckNet router is forwarding packets (" .. table.concat(addresses, ", ") .. ")\n")
while true do stack.ip:pump(math.huge) end
