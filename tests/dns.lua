local root = (... and ... ~= "" and ...) or "."
package.path = root .. "/ducknet/lib/?.lua;" ..
  root .. "/ducknet/lib/?/init.lua;" .. package.path

local DNS = require("ducknet.dns")

local rootAuthority = DNS.authority({{
  name = ".",
  records = {
    { name = "duck", type = "NS", value = "ns.duck", ttl = 600 },
    { name = "ns.duck", type = "A", value = "10.0.0.53", ttl = 600 }
  }
}})
local duckAuthority = DNS.authority({{
  name = "duck",
  records = {
    { name = "duck", type = "SOA", value = "ns.duck hostmaster.duck", ttl = 300 },
    { name = "duck", type = "NS", value = "ns.duck", ttl = 300 },
    { name = "ns.duck", type = "A", value = "10.0.0.53", ttl = 300 },
    { name = "tracker.duck", type = "A", value = "10.0.0.10", ttl = 120 },
    { name = "www.duck", type = "CNAME", value = "tracker.duck", ttl = 120 },
    { name = "_verify.tracker.duck", type = "TXT", value = "challenge", ttl = 30 }
  }
}})

local referral = assert(rootAuthority:answer("tracker.duck", "A"))
assert(not referral.aa and referral.authority[1].value == "ns.duck")
assert(referral.additional[1].value == "10.0.0.53")
local authoritative = assert(duckAuthority:answer("tracker.duck", "A"))
assert(authoritative.aa and authoritative.answers[1].value == "10.0.0.10")
assert(duckAuthority:answer("missing.duck", "A").rcode == "NXDOMAIN")

local pending, queries = {}, {}
local udp = {}
function udp:send(destination, port, payload, options)
  assert(port == DNS.PORT)
  local query = assert(DNS._decode(payload))
  local authority = destination == "1.0.0.1" and rootAuthority or
    destination == "10.0.0.53" and duckAuthority
  assert(authority, "query sent to unexpected DNS server " .. tostring(destination))
  local response = assert(authority:answer(query.name, query.type))
  response.kind, response.id = "response", query.id
  pending[options.sourcePort] = {
    src = destination, dstPort = options.sourcePort, payload = DNS._encode(response)
  }
  queries[#queries + 1] = destination .. ":" .. query.name
  return true
end
function udp:receive(port, _, predicate)
  local datagram = pending[port]
  pending[port] = nil
  if datagram and predicate(datagram) then return datagram end
  return nil, "timeout"
end

local time = 1000
local resolver = DNS.resolver(udp, {
  roots = { "1.0.0.1" }, search = { "duck" }, retries = 1,
  clock = function() return time end,
  random = function(minimum) return minimum end
})
local address = assert(resolver:resolve("tracker.duck"))
assert(address == "10.0.0.10")
assert(queries[1] == "1.0.0.1:tracker.duck")
assert(queries[2] == "10.0.0.53:tracker.duck")
local beforeCache = #queries
assert(resolver:resolve("tracker.duck") == "10.0.0.10")
assert(#queries == beforeCache, "cached DNS response made another network query")
time = time + 121
assert(resolver:resolve("tracker.duck") == "10.0.0.10")
assert(#queries > beforeCache, "expired DNS response remained cached")
assert(resolver:resolve("www.duck") == "10.0.0.10")
assert(resolver:resolve("tracker") == "10.0.0.10")

-- A DNS server returns its authoritative data on UDP/53.
local sent
local serverUDP = {
  receive = function(_, port)
    assert(port == DNS.PORT)
    return {
      src = "10.0.0.2", dst = "10.0.0.53", srcPort = 53000,
      interface = "lan", payload = DNS._encode({
        kind = "query", id = "query-1", name = "tracker.duck", type = "A", rd = true
      })
    }
  end,
  send = function(_, destination, port, payload, options)
    sent = { destination = destination, port = port,
      response = assert(DNS._decode(payload)), options = options }
    return true
  end
}
local server = DNS.server(serverUDP, {
  zones = duckAuthority.zones, recursive = false
})
assert(server:serveOnce(1))
assert(sent.destination == "10.0.0.2" and sent.port == 53000)
assert(sent.options.sourcePort == DNS.PORT and sent.response.answers[1].value == "10.0.0.10")
assert(sent.options.source == "10.0.0.53")
assert(sent.options.interface == nil, "DNS reply bypassed IP return-route selection")

io.write("all DNS tests passed\n")
