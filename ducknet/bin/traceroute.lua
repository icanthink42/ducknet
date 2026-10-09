local cli = require("ducknet.cli")

local arguments = { ... }
local destination = arguments[1]
if not destination then
  io.stderr:write("usage: traceroute <ip> [max-hops] [timeout] [config.lua]\n")
  return
end
local maximum = arguments[2] and cli.number(arguments[2], "max hops", 1, 64) or 16
local timeout = arguments[3] and tonumber(arguments[3]) or 2
assert(timeout and timeout > 0, "timeout must be positive")
local _, _, _, icmp = cli.load(arguments[4], true)

io.write("traceroute to " .. destination .. ", " .. maximum .. " hops max\n")
for ttl = 1, maximum do
  local result = icmp:probe(destination, { ttl = ttl, timeout = timeout, sequence = ttl })
  if not result then
    io.write(string.format("%2d  *\n", ttl))
  else
    io.write(string.format("%2d  %-15s %.1fms\n", ttl, result.from, result.elapsed * 1000))
    if result.kind == "reply" then break end
  end
end
