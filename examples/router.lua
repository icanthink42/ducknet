local config = require("ducknet.config")
local ducknet = require("ducknet")

local settings = assert(config.load())
settings.ip.forwarding = true
local stack = ducknet.stack(settings)
local addresses = {}
for _, interface in ipairs(stack.ip.interfaces) do
  addresses[#addresses + 1] = interface.name .. "=" .. interface.address
end
io.write("Routing on " .. table.concat(addresses, ", ") .. "\n")
while true do stack.ip:pump(math.huge) end
