local cli = require("ducknet.cli")

local arguments = { ... }
local destination = arguments[1]
if not destination then
  io.stderr:write("usage: duck-ping <ip> [count] [timeout] [config.lua]\n")
  return
end
local count = arguments[2] and cli.number(arguments[2], "count", 1, 1000) or 4
local timeout = arguments[3] and tonumber(arguments[3]) or 2
assert(timeout and timeout > 0, "timeout must be positive")
local _, _, _, icmp = cli.load(arguments[4], true)

io.write("PING " .. destination .. " with DuckNet ICMP:\n")
local received, total = 0, 0
for sequence = 1, count do
  local result, err = icmp:ping(destination, {
    sequence = sequence, timeout = timeout, data = string.rep("d", 32)
  })
  if result and result.kind == "reply" then
    local milliseconds = result.elapsed * 1000
    received, total = received + 1, total + milliseconds
    io.write(string.format("reply from %s: seq=%d time=%.1fms hops=%d\n",
      result.from, sequence, milliseconds, #(result.hops or {})))
  elseif result and result.kind == "ttl" then
    io.write("TTL expired at " .. result.from .. "\n")
  else
    io.write("timeout: seq=" .. sequence .. " (" .. tostring(err) .. ")\n")
  end
end
local lost = count - received
io.write(string.format("%d sent, %d received, %.0f%% loss", count, received, lost / count * 100))
if received > 0 then io.write(string.format(", average %.1fms", total / received)) end
io.write("\n")

