local cli = require("ducknet.cli")

local arguments = { ... }
local _, link = cli.load(arguments[1], false)
io.write("Logical IP        Modem address\n")
local addresses = {}
for address in pairs(link.peers) do addresses[#addresses + 1] = address end
table.sort(addresses)
for _, address in ipairs(addresses) do
  io.write(string.format("%-17s %s\n", address, tostring(link.peers[address])))
end

