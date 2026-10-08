local codec = require("ducknet.codec")

local IP = {}
IP.__index = IP

local function ipv4(address)
  assert(type(address) == "string", "address must be a string")
  local value, count = 0, 0
  for part in address:gmatch("[^.]+") do
    local byte = tonumber(part)
    assert(byte and byte >= 0 and byte <= 255 and byte % 1 == 0, "invalid IPv4 address")
    value, count = value * 256 + byte, count + 1
  end
  assert(count == 4, "invalid IPv4 address")
  return value
end

local function parseNetwork(cidr)
  local address, prefixText = cidr:match("^([^/]+)/(%d+)$")
  assert(address, "route must use address/prefix notation")
  local prefix = tonumber(prefixText)
  assert(prefix >= 0 and prefix <= 32, "invalid route prefix")
  local block = 2 ^ (32 - prefix)
  return math.floor(ipv4(address) / block) * block, prefix, block
end

local function defaultClock()
  local ok, computer = pcall(require, "computer")
  return ok and computer.uptime() or os.clock()
end

function IP.new(link, options)
  options = options or {}
  assert(link and type(link.send) == "function" and type(link.receive) == "function",
    "link must implement send and receive")
  ipv4(options.address)
  return setmetatable({
    link = link,
    address = options.address,
    forwarding = options.forwarding == true,
    defaultTTL = options.ttl or 16,
    clock = options.clock or defaultClock,
    routes = {},
    inbox = {},
    counter = 0,
    handlers = {},
    dropHandlers = options.onDrop and { options.onDrop } or {}
  }, IP)
end

-- Register a protocol handler. Returning true consumes the packet; otherwise it
-- remains available through receive(). This lets services such as ICMP respond
-- while an application is blocked waiting for TCP traffic.
function IP:on(protocol, handler)
  assert(type(protocol) == "number", "protocol must be a number")
  assert(type(handler) == "function", "handler must be a function")
  local handlers = self.handlers[protocol] or {}
  self.handlers[protocol] = handlers
  handlers[#handlers + 1] = handler
  return handler
end

function IP:onDrop(handler)
  assert(type(handler) == "function", "drop handler must be a function")
  self.dropHandlers[#self.dropHandlers + 1] = handler
  return handler
end

function IP:addRoute(cidr, nextHop, metric)
  local network, prefix, block = parseNetwork(cidr)
  if nextHop then ipv4(nextHop) end
  self.routes[#self.routes + 1] = {
    cidr = cidr, network = network, prefix = prefix, block = block,
    nextHop = nextHop, metric = metric or 100
  }
  table.sort(self.routes, function(a, b)
    return a.prefix > b.prefix or (a.prefix == b.prefix and a.metric < b.metric)
  end)
end

function IP:route(destination)
  local value = ipv4(destination)
  for _, route in ipairs(self.routes) do
    if math.floor(value / route.block) * route.block == route.network then
      return route.nextHop or destination, route
    end
  end
  return nil, "no route to " .. destination
end

function IP:_transmit(packet)
  local nextHop, routeOrError = self:route(packet.dst)
  if not nextHop then return nil, routeOrError end
  return self.link:send(nextHop, codec.encode(packet))
end

function IP:send(destination, protocol, payload, options)
  ipv4(destination)
  assert(type(protocol) == "number", "protocol must be a number")
  assert(type(payload) == "string", "payload must be a string")
  options = options or {}
  self.counter = self.counter + 1
  local packet = {
    v = 1, id = self.address .. ":" .. self.counter,
    src = self.address, dst = destination, protocol = protocol,
    ttl = options.ttl or self.defaultTTL, payload = payload,
    hops = { self.address }
  }
  local sent, err = self:_transmit(packet)
  if not sent then return nil, err end
  return true, packet
end

function IP:_drop(reason, packet)
  for _, handler in ipairs(self.dropHandlers) do pcall(handler, reason, packet) end
  return nil, reason
end

function IP:pump(timeout)
  local _, frame = self.link:receive(timeout)
  if not frame then return nil, "timeout" end
  local ok, packet = pcall(codec.decode, frame)
  if not ok or type(packet) ~= "table" or packet.v ~= 1 or
      type(packet.src) ~= "string" or type(packet.dst) ~= "string" or
      type(packet.protocol) ~= "number" or type(packet.payload) ~= "string" or
      type(packet.ttl) ~= "number" then
    return self:_drop("invalid packet")
  end
  local addressesValid = pcall(function() ipv4(packet.src) ipv4(packet.dst) end)
  if not addressesValid then return self:_drop("invalid packet") end
  if packet.dst == self.address then
    for _, handler in ipairs(self.handlers[packet.protocol] or {}) do
      local handled, consumed = pcall(handler, packet)
      if handled and consumed then return packet, "consumed" end
    end
    local queue = self.inbox[packet.protocol] or {}
    self.inbox[packet.protocol] = queue
    queue[#queue + 1] = packet
    return packet
  end
  if not self.forwarding then return self:_drop("forwarding disabled", packet) end
  packet.ttl = (tonumber(packet.ttl) or 0) - 1
  if packet.ttl <= 0 then return self:_drop("ttl exceeded", packet) end
  packet.hops = type(packet.hops) == "table" and packet.hops or {}
  packet.hops[#packet.hops + 1] = self.address
  local sent, err = self:_transmit(packet)
  if not sent then return self:_drop(err, packet) end
  return packet, "forwarded"
end

function IP:receive(protocol, timeout)
  local queue = self.inbox[protocol]
  if queue and #queue > 0 then return table.remove(queue, 1) end
  local deadline = self.clock() + (timeout or math.huge)
  while self.clock() < deadline do
    local remaining = deadline - self.clock()
    self:pump(remaining)
    queue = self.inbox[protocol]
    if queue and #queue > 0 then return table.remove(queue, 1) end
  end
  return nil, "timeout"
end

return IP
