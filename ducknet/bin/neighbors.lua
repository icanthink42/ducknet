local cli = require("ducknet.cli")

local arguments = { ... }
local _, _, ip = cli.load(arguments[1], false)
io.write("Interface       Logical IP        Modem address\n")
for _, interface in ipairs(ip.interfaces) do
  local addresses = {}
  for address in pairs(interface.link.peers) do addresses[#addresses + 1] = address end
  table.sort(addresses)
  for _, address in ipairs(addresses) do
    io.write(string.format("%-15s %-17s %s\n", interface.name, address,
      tostring(interface.link.peers[address])))
  end
end
