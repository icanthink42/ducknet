local config = require("ducknet.config")
local ducknet = require("ducknet")

local arguments = { ... }
local server, name, recordType
if arguments[1] and arguments[1]:sub(1, 1) == "@" then
  server, name, recordType = arguments[1]:sub(2), arguments[2], arguments[3]
else
  name, recordType = arguments[1], arguments[2]
end
if not name then
  io.stderr:write("usage: dig [@dns-server] <name> [type]\n")
  return
end

local settings, err = config.load()
if not settings then error("could not load DuckNet config: " .. tostring(err), 0) end
local stack = ducknet.stack(settings)
local options = server and { servers = { server }, noCache = true } or nil
local response, queryError = stack.dns:query(name, recordType or "A", options)
if not response then error("DNS query failed: " .. tostring(queryError), 0) end
io.write(";; status: " .. tostring(response.rcode) ..
  ", authoritative: " .. (response.aa and "yes" or "no") ..
  ", cached: " .. (response.cached and "yes" or "no") .. "\n")

local function section(title, records)
  if #(records or {}) == 0 then return end
  io.write("\n;; " .. title .. ":\n")
  for _, record in ipairs(records) do
    io.write(string.format("%-32s %-6d %-6s %s\n",
      record.name == "" and "." or record.name, record.ttl or 0,
      record.type, record.value))
  end
end

section("ANSWER", response.answers)
section("AUTHORITY", response.authority)
section("ADDITIONAL", response.additional)
