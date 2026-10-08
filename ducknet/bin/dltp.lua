local config = require("ducknet.config")
local ducknet = require("ducknet")

local arguments = { ... }
local method, destination, path = arguments[1], arguments[2], arguments[3]
if not path then
  io.stderr:write("usage: dltp <METHOD> <ip> <path> [body] [config.lua]\n")
  return
end
local settings = assert(config.load(arguments[5]))
local stack = ducknet.stack(settings)
local response, err = stack.dltp:request(destination, method:upper(), path, { body = arguments[4] or "" })
if not response then error("request failed: " .. tostring(err), 0) end
io.write("DLTP " .. tostring(response.status) .. "\n")
local names = {}
for name in pairs(response.headers or {}) do names[#names + 1] = name end
table.sort(names)
for _, name in ipairs(names) do io.write(name .. ": " .. tostring(response.headers[name]) .. "\n") end
io.write("\n" .. tostring(response.body or "") .. "\n")

