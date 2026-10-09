local config = require("ducknet.config")
local ducknet = require("ducknet")

local arguments = { ... }
local appPath = arguments[1]
if not appPath then
  io.stderr:write("usage: serve <application.lua> [config.lua]\n")
  return
end

local settings, configError = config.load(arguments[2])
if not settings then error("could not load config: " .. tostring(configError), 0) end
local stack = ducknet.stack(settings)
local application, appError = loadfile(appPath)
if not application then error("could not load application: " .. tostring(appError), 0) end
local ok, configure = pcall(application)
if not ok then error("application failed to load: " .. tostring(configure), 0) end
if type(configure) ~= "function" then error("application must return a function", 0) end

local server = stack.dltp:server()
configure(server)
io.write("DuckNet server listening on " .. settings.ip.address .. ":" .. stack.dltp.port .. "\n")
server:run()
