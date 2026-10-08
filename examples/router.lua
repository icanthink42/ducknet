local config = require("ducknet.config")
local ducknet = require("ducknet")

local settings = assert(config.load())
settings.ip.forwarding = true
local stack = ducknet.stack(settings)
io.write("Routing as " .. settings.ip.address .. "\n")
while true do stack.ip:pump(math.huge) end

