local config = require("ducknet.config")
local ducknet = require("ducknet")

local arguments = { ... }
local settings, configError = config.load(arguments[1])
if not settings then error("could not load config: " .. tostring(configError), 0) end
settings.ip.forwarding = true
local stack = ducknet.stack(settings)
io.write("DuckNet router " .. settings.ip.address .. " is forwarding packets\n")
while true do stack.ip:pump(math.huge) end

