local root = (... and ... ~= "" and ...) or "."
package.path = root .. "/ducknet/lib/?.lua;" .. root .. "/ducknet/lib/?/init.lua;" ..
  root .. "/niobium/lib/?.lua;" .. root .. "/niobium/lib/?/init.lua;" .. package.path

local codec = require("ducknet.codec")
local IP = require("ducknet.ip")
local ICMP = require("ducknet.icmp")
local UDP = require("ducknet.udp")
local TCP = require("ducknet.tcp")
local DLTP = require("ducknet.dltp")
local Sandbox = require("niobium.sandbox")
local UI = require("niobium.ui")

local function equal(left, right, message)
  assert(left == right, (message or "values differ") .. ": " .. tostring(left) .. " ~= " .. tostring(right))
end

local encoded = codec.encode({ hello = "world\0!", answer = 42, nested = { true, false } })
local decoded = codec.decode(encoded)
equal(decoded.hello, "world\0!")
equal(decoded.answer, 42)
equal(decoded.nested[1], true)
equal(decoded.nested[2], false)
assert(not pcall(codec.decode, encoded .. "junk"))

local wire = {}
local function link(name)
  local result = {
    send = function(_, nextHop, frame)
      wire[#wire + 1] = { from = name, to = nextHop, frame = frame }
      return true
    end,
    receive = function()
      for index, item in ipairs(wire) do
        if item.to == name then table.remove(wire, index) return item.from, item.frame end
      end
      return nil, "timeout"
    end
  }
  function result:receiveAny(links)
    for index, item in ipairs(wire) do
      for _, candidate in ipairs(links) do
        if item.to == candidate.name then
          table.remove(wire, index)
          return item.from, item.frame, candidate
        end
      end
    end
    return nil, "timeout"
  end
  result.name = name
  return result
end

local left = IP.new(link("10.0.0.1"), { address = "10.0.0.1", clock = os.clock })
local router = IP.new(link("10.0.0.2"), { address = "10.0.0.2", forwarding = true, clock = os.clock })
local right = IP.new(link("10.0.1.1"), { address = "10.0.1.1", clock = os.clock })
left:addRoute("10.0.1.0/24", "10.0.0.2")
router:addRoute("10.0.1.0/24", nil)
router:addRoute("10.0.0.0/24", nil)
right:addRoute("10.0.0.0/24", "10.0.0.2")
assert(left:send("10.0.1.1", 99, "payload"))
local _, state = router:pump(0)
equal(state, "forwarded")
local packet = assert(right:receive(99, 0.01))
equal(packet.payload, "payload")
equal(packet.hops[2], "10.0.0.2")

local leftICMP = ICMP.new(left)
ICMP.new(router)
ICMP.new(right)
-- An echo traverses the router and is answered by the destination's ICMP
-- handler while its IP stack is pumping.
local sent, echoPacket = left:send("10.0.1.1", ICMP.PROTOCOL, codec.encode({
  v = 1, type = "echo_request", id = "test-echo", sequence = 1, data = "x"
}), { ttl = 4 })
assert(sent and echoPacket)
router:pump(0)
right:pump(0)
router:pump(0)
local echoReply = assert(left:receive(ICMP.PROTOCOL, 0.01))
equal(codec.decode(echoReply.payload).type, "echo_reply")

-- TTL one expires at the first router, which returns a control message.
assert(left:send("10.0.1.1", ICMP.PROTOCOL, codec.encode({
  v = 1, type = "echo_request", id = "trace-echo", sequence = 2
}), { ttl = 1 }))
router:pump(0)
local expired = assert(left:receive(ICMP.PROTOCOL, 0.01))
local expiredMessage = codec.decode(expired.payload)
equal(expiredMessage.type, "time_exceeded")
equal(expiredMessage.reporter, "10.0.0.2")

local leftUDP, rightUDP = UDP.new(left), UDP.new(right)
assert(leftUDP:send("10.0.1.1", 9000, "datagram", { sourcePort = 8000 }))
equal(select(2, router:pump(0)), "forwarded")
local datagram = assert(rightUDP:receive(9000, 0.01))
equal(datagram.payload, "datagram")
equal(datagram.srcPort, 8000)

-- A single router can own an address on each of two modem interfaces.
wire = {}
local client = IP.new(link("11.0.0.13"), { address = "11.0.0.13", clock = os.clock })
local multiRouter = IP.new(link("10.0.0.1"), {
  address = "10.0.0.1", interface = "net10", forwarding = true, clock = os.clock
})
multiRouter:addInterface(link("11.0.0.1"), { name = "net11", address = "11.0.0.1" })
local server = IP.new(link("10.0.0.10"), { address = "10.0.0.10", clock = os.clock })
client:addRoute("0.0.0.0/0", "11.0.0.1")
multiRouter:addRoute("10.0.0.0/24", nil, 10, "net10")
multiRouter:addRoute("11.0.0.0/24", nil, 10, "net11")
server:addRoute("0.0.0.0/0", "10.0.0.1")
ICMP.new(client)
ICMP.new(multiRouter)
ICMP.new(server)
assert(client:send("10.0.0.1", ICMP.PROTOCOL, codec.encode({
  v = 1, type = "echo_request", id = "router-echo", sequence = 1
})))
multiRouter:pump(0)
local routerReply = assert(client:receive(ICMP.PROTOCOL, 0.01))
equal(routerReply.src, "10.0.0.1")

assert(client:send("10.0.0.10", ICMP.PROTOCOL, codec.encode({
  v = 1, type = "echo_request", id = "multi-echo", sequence = 1
})))
equal(select(2, multiRouter:pump(0)), "forwarded")
server:pump(0)
equal(select(2, multiRouter:pump(0)), "forwarded")
local multiReply = assert(client:receive(ICMP.PROTOCOL, 0.01))
equal(multiReply.src, "10.0.0.10")
equal(multiReply.dst, "11.0.0.13")

-- Run client and server stacks cooperatively over an in-memory IP transport.
local queues, now = { client = {}, server = {} }, 0
local function fakeIP(name, peer)
  return {
    address = name,
    send = function(_, destination, protocol, payload)
      queues[peer][#queues[peer] + 1] = { src = name, dst = destination,
        protocol = protocol, payload = payload }
      return true
    end,
    receive = function(_, protocol)
      while true do
        for index, item in ipairs(queues[name]) do
          if item.protocol == protocol then table.remove(queues[name], index) return item end
        end
        coroutine.yield()
      end
    end
  }
end
local clientTCP = TCP.new(fakeIP("client", "server"), { clock = function() return now end })
local serverTCP = TCP.new(fakeIP("server", "client"), { clock = function() return now end })
local observed
local serverTask = coroutine.create(function()
  local socket = assert(serverTCP:listen(80):accept(5))
  observed = assert(socket:receive(5))
  assert(socket:send("response:" .. observed))
end)
local clientTask = coroutine.create(function()
  local socket = assert(clientTCP:connect("server", 80))
  assert(socket:send("request"))
  equal(assert(socket:receive(5)), "response:request")
end)
while coroutine.status(serverTask) ~= "dead" or coroutine.status(clientTask) ~= "dead" do
  now = now + 0.01
  if coroutine.status(serverTask) ~= "dead" then assert(coroutine.resume(serverTask)) end
  if coroutine.status(clientTask) ~= "dead" then assert(coroutine.resume(clientTask)) end
end
equal(observed, "request")

queues, now = { client = {}, server = {} }, 0
clientTCP = TCP.new(fakeIP("client", "server"), { clock = function() return now end })
serverTCP = TCP.new(fakeIP("server", "client"), { clock = function() return now end })
local clientDLTP = DLTP.new(clientTCP)
local serverDLTP = DLTP.new(serverTCP)
local app = serverDLTP:server()
app:get("/users/:name", function(request)
  return { status = 200, headers = { test = "yes" }, body = "hello " .. request.params.name }
end)
serverTask = coroutine.create(function() assert(app:serveOnce(5)) end)
clientTask = coroutine.create(function()
  local response = assert(clientDLTP:request("server", "GET", "/users/duck"))
  equal(response.status, 200)
  equal(response.headers.test, "yes")
  equal(response.body, "hello duck")
end)
while coroutine.status(serverTask) ~= "dead" or coroutine.status(clientTask) ~= "dead" do
  now = now + 0.01
  if coroutine.status(serverTask) ~= "dead" then assert(coroutine.resume(serverTask)) end
  if coroutine.status(clientTask) ~= "dead" then assert(coroutine.resume(clientTask)) end
end

local output = {}
local sandbox = Sandbox.new({ instructionLimit = 10000 })
assert(sandbox:run([[local ui=require("ui"); ui.write(string.upper("safe"))]], {
  ui = { write = function(value) output[#output + 1] = value end }
}))
equal(output[1], "SAFE")
local prompted = UI.new(nil, nil, { reader = function() return "Steve" end }):capability()
equal(prompted.input(""), "Steve")
local ok = sandbox:run([[require("component")]])
assert(not ok)
local quotaOk = sandbox:run([[while true do end]])
assert(not quotaOk)

-- The CC:Tweaked adapter targets logical next hops over a shared modem channel.
local savedPeripheral = _G.peripheral
local savedPullEvent, savedStartTimer, savedCancelTimer = os.pullEvent, os.startTimer, os.cancelTimer
local transmission
local ccModem = {
  open = function() end,
  close = function() end,
  transmit = function(channel, replyChannel, payload)
    transmission = { channel, replyChannel, payload }
  end
}
_G.peripheral = {
  find = function(_, filter)
    filter("left", ccModem)
    return ccModem
  end,
  wrap = function() return ccModem end
}
os.startTimer = function() return 7 end
os.cancelTimer = function() end
package.loaded["ducknet.modem"] = nil
local CCLink = require("ducknet.modem")
local ccLink = CCLink.new(nil, { address = "10.0.0.1", port = 4660 })
assert(ccLink:send("10.0.0.2", "frame"))
equal(transmission[1], 4660)
equal(transmission[3].target, "10.0.0.2")
assert(ccLink:send("255.255.255.255", "broadcast"))
equal(transmission[3].target, nil)
os.pullEvent = function()
  return "modem_message", "left", 4660, 4660,
    { marker = "ducknet:1", source = "10.0.0.2", target = "10.0.0.1", frame = "reply" }, 4
end
local from, frame = ccLink:receive(1)
equal(from, "10.0.0.2")
equal(frame, "reply")

local configuredRouter = require("ducknet").stack({
  link = { peers = {} },
  interfaces = {
    { name = "net10", modem = "left", address = "10.0.0.1",
      network = "10.0.0.0/24", port = 4660 },
    { name = "net11", modem = "right", address = "11.0.0.1",
      network = "11.0.0.0/24", port = 4661 }
  },
  ip = { forwarding = true, ttl = 16 }, routes = {}, tcp = {}, dltp = {}
})
equal(#configuredRouter.links, 2)
equal(#configuredRouter.ip.interfaces, 2)
equal(#configuredRouter.ip.routes, 2)
local _, configuredRoute = configuredRouter.ip:route("11.0.0.13")
equal(configuredRoute.interface.name, "net11")
_G.peripheral = savedPeripheral
os.pullEvent, os.startTimer, os.cancelTimer = savedPullEvent, savedStartTimer, savedCancelTimer
package.loaded["ducknet.modem"] = nil

io.write("all DuckNet tests passed\n")
