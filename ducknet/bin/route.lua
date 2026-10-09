local cli = require("ducknet.cli")

local arguments = { ... }
local _, _, ip = cli.load(arguments[2], false)
if arguments[1] then
  local nextHop, route = ip:route(arguments[1])
  if not nextHop then error(route, 0) end
  io.write(arguments[1] .. " via " .. nextHop .. " (" .. route.cidr ..
    ", interface " .. route.interface.name .. ", metric " .. route.metric .. ")\n")
  return
end

io.write("Network             Gateway          Interface       Metric\n")
for _, route in ipairs(ip.routes) do
  io.write(string.format("%-19s %-16s %-15s %d\n", route.cidr,
    route.nextHop or "direct", route.interface.name, route.metric))
end
