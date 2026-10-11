local root = (... and ... ~= "" and ...) or "."
package.path = root .. "/ducknet/lib/?.lua;" ..
  root .. "/ducknet/lib/?/init.lua;" .. package.path

local DHCP = require("ducknet.dhcp")
local config = require("ducknet.config")
local IP = require("ducknet.ip")
local UDP = require("ducknet.udp")
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

-- Exercise DORA through real UDP and IP layers on a multi-interface router.
local endpoints = {}
local function networkLink(name, segment, address)
  local result = { name = name, segment = segment, address = address, queue = {} }
  endpoints[#endpoints + 1] = result
  function result:send(nextHop, frame)
    for _, endpoint in ipairs(endpoints) do
      if endpoint ~= self and endpoint.segment == self.segment and
          (nextHop == DHCP.BROADCAST or nextHop == endpoint.address) then
        endpoint.queue[#endpoint.queue + 1] = { from = self.name, frame = frame }
      end
    end
    return true
  end
  function result:receive()
    local item = table.remove(self.queue, 1)
    if item then return item.from, item.frame end
    return nil, "timeout"
  end
  function result:receiveAny(links)
    for _, link in ipairs(links) do
      local item = table.remove(link.queue, 1)
      if item then return item.from, item.frame, link end
    end
    return nil, "timeout"
  end
  return result
end

local clientIP = IP.new(networkLink("client", "lan", "0.0.0.0"), {
  address = "0.0.0.0", clock = os.clock
})
local routerIP = IP.new(networkLink("router-lan", "lan", "10.0.0.1"), {
  address = "10.0.0.1", interface = "lan", forwarding = true, clock = os.clock
})
routerIP:addInterface(networkLink("router-transit", "transit", "10.255.0.2"), {
  name = "transit1", address = "10.255.0.2"
})
routerIP:addRoute("10.0.0.0/16", nil, 10, "lan")
routerIP:addRoute("10.255.0.0/30", nil, 10, "transit1")
routerIP:addRoute("0.0.0.0/0", "10.255.0.1", 100, "transit1")
local clientDatagrams, routerDatagrams = UDP.new(clientIP), UDP.new(routerIP)
local integrationLeasePath = os.tmpname()
os.remove(integrationLeasePath)
DHCP.server(routerDatagrams, routerIP, {
  leasePath = integrationLeasePath, clock = function() return 2000 end,
  pools = {{ interface = "lan", first = "10.0.0.100", last = "10.0.0.200",
    network = "10.0.0.0/16", gateway = "10.0.0.1", lease = 3600 }}
})
local integrationXid = "integration-xid"
assert(clientDatagrams:send(DHCP.BROADCAST, DHCP.SERVER_PORT, DHCP._encode({
  type = "discover", xid = integrationXid, clientId = "cc:4"
}), { sourcePort = DHCP.CLIENT_PORT, source = "0.0.0.0", interface = "default" }))
assert(routerIP:pump(0))
local offeredDatagram = assert(clientDatagrams:receive(DHCP.CLIENT_PORT, 0.01))
local integrationOffer = DHCP._decode(offeredDatagram.payload)
assert(integrationOffer.type == "offer" and integrationOffer.address == "10.0.0.100")
assert(clientDatagrams:send(DHCP.BROADCAST, DHCP.SERVER_PORT, DHCP._encode({
  type = "request", xid = integrationXid, clientId = "cc:4",
  address = integrationOffer.address, server = integrationOffer.server
}), { sourcePort = DHCP.CLIENT_PORT, source = "0.0.0.0", interface = "default" }))
assert(routerIP:pump(0))
local ackDatagram = assert(clientDatagrams:receive(DHCP.CLIENT_PORT, 0.01))
assert(DHCP._decode(ackDatagram.payload).type == "ack")

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
os.remove(integrationLeasePath)
os.remove(integrationLeasePath .. ".ducknet-new")
os.remove(integrationLeasePath .. ".ducknet-old")
io.write("all DHCP tests passed\n")
