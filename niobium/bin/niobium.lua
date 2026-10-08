local config = require("ducknet.config")
local ducknet = require("ducknet")
local Sandbox = require("niobium.sandbox")
local UI = require("niobium.ui")

local arguments = { ... }
local url = arguments[1]
if not url then
  io.stderr:write("usage: niobium dltp://10.0.0.2/path [config.lua]\n")
  return
end
local host, path = url:match("^dltps?://([^/]+)(/.*)$")
if not host then host, path = url:match("^([^/]+)(/.*)$") end
if not host then error("invalid DuckNet URL", 0) end

local settings = assert(config.load(arguments[2]))
local stack = ducknet.stack(settings)
local response, requestError = stack.dltp:request(host, "GET", path)
if not response then error("request failed: " .. tostring(requestError), 0) end
if response.status ~= 200 then error("site returned status " .. tostring(response.status), 0) end

local terminal, gpu
if type(peripheral) == "table" then
  terminal = term
else
  local component = require("component")
  terminal = require("term")
  gpu = component.isAvailable("gpu") and component.gpu or nil
end
local ui = UI.new(gpu, terminal)
local origin = host
local network = {
  request = function(method, requestedPath, options)
    assert(type(requestedPath) == "string" and requestedPath:sub(1, 1) == "/",
      "sandbox requests must use an absolute same-origin path")
    return stack.dltp:request(origin, method, requestedPath, options)
  end
}
local sandbox = Sandbox.new()
local ok, runtimeError = sandbox:run(response.body, {
  ui = ui:capability(), net = network
}, "=" .. url)
if not ok then error("site crashed: " .. tostring(runtimeError), 0) end
