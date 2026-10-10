local root = (... and ... ~= "" and ...) or "."
package.path = root .. "/ducknet/lib/?.lua;" ..
  root .. "/ducknet/lib/?/init.lua;" .. package.path

local DHCP = require("ducknet.dhcp")
local config = require("ducknet.config")
local leasePath = os.tmpname()
os.remove(leasePath)

local sent, handler = {}, nil
local udp = {
  on = function(_, port, callback)
    assert(port == DHCP.SERVER_PORT)
    handler = callback
  end,
  send = function(_, destination, port, payload, options)
    sent[#sent + 1] = {
      destination = destination, port = port, payload = payload, options = options
    }
    return true
  end
}
local ip = {
  interfaceByName = {
    lan = { name = "lan", address = "11.0.0.1" }
  }
}
local clock = 1000
local server = DHCP.server(udp, ip, {
  leasePath = leasePath, clock = function() return clock end,
  pools = {
    { interface = "lan", first = "11.0.0.100", last = "11.0.0.101",
      network = "11.0.0.0/24", gateway = "11.0.0.1", lease = 3600 }
  }
})
assert(server and handler)

handler({ interface = "lan", payload = DHCP._encode({
  type = "discover", xid = "x1", clientId = "cc:2"
}) })
local offer = DHCP._decode(sent[#sent].payload)
assert(offer.type == "offer" and offer.address == "11.0.0.100")
assert(offer.gateway == "11.0.0.1" and offer.prefix == 24)

handler({ interface = "lan", payload = DHCP._encode({
  type = "request", xid = "x1", clientId = "cc:2", address = offer.address
}) })
local ack = DHCP._decode(sent[#sent].payload)
assert(ack.type == "ack" and ack.address == "11.0.0.100")
assert(server.leases["11.0.0.100"].clientId == "cc:2")

-- Exercise the client DORA state machine with a deterministic fake transport.
local pending, phase
local clientUDP = {}
function clientUDP:send(_, _, payload)
  local message = DHCP._decode(payload)
  if message.type == "discover" then
    phase = "offer"
    pending = { type = "offer", xid = message.xid, clientId = message.clientId,
      address = "11.0.0.101", prefix = 24, gateway = "11.0.0.1",
      server = "11.0.0.1", lease = 600 }
  elseif message.type == "request" then
    phase = "ack"
    pending = { type = "ack", xid = message.xid, clientId = message.clientId,
      address = message.address, prefix = 24, gateway = "11.0.0.1",
      server = "11.0.0.1", lease = 600, obtained = 1000 }
  end
  return true
end
function clientUDP:receive(_, _, predicate)
  local datagram = { payload = DHCP._encode(pending) }
  assert(predicate(datagram))
  pending = nil
  return datagram
end
local lease = assert(DHCP.Client.acquire(clientUDP, "cc:3", { retries = 1 }))
assert(phase == "ack" and lease.address == "11.0.0.101")

local routerPath = os.tmpname()
os.remove(routerPath)
assert(config.save({
  link = { peers = {} },
  interfaces = {
    { name = "lan", modem = "left", address = "11.0.0.1",
      network = "11.0.0.0/24", port = 4660 }
  },
  ip = { forwarding = true, ttl = 16 }, routes = {}, tcp = {}, dltp = {}
}, routerPath))
local dhcpd = assert(loadfile(root .. "/ducknet/bin/dhcpd.lua"))
dhcpd("pool", "add", "lan", "11.0.0.100", "11.0.0.200", "600", routerPath)
local routerConfig = assert(config.load(routerPath))
assert(routerConfig.dhcp.pools[1].interface == "lan")
assert(routerConfig.dhcp.pools[1].gateway == "11.0.0.1")
assert(routerConfig.dhcp.pools[1].lease == 600)
dhcpd("pool", "list", routerPath)
dhcpd("pool", "remove", "lan", routerPath)
routerConfig = assert(config.load(routerPath))
assert(#routerConfig.dhcp.pools == 0)
local invalidPool = pcall(dhcpd, "pool", "add", "lan", "11.0.0.0",
  "11.0.0.200", "600", routerPath)
assert(not invalidPool, "DHCP command accepted the subnet's network address")
routerConfig = assert(config.load(routerPath))
assert(#routerConfig.dhcp.pools == 0)

os.remove(leasePath)
os.remove(leasePath .. ".ducknet-new")
os.remove(leasePath .. ".ducknet-old")
os.remove(routerPath)
os.remove(routerPath .. ".ducknet-new")
os.remove(routerPath .. ".ducknet-old")
io.write("all DHCP tests passed\n")
