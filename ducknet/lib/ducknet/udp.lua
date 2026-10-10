local codec = require("ducknet.codec")

local UDP = {}
UDP.__index = UDP
UDP.PROTOCOL = 17

function UDP.new(ip)
  local self = setmetatable({
    ip = ip, queues = {}, handlers = {}, bound = {}, nextPort = 49152
  }, UDP)
  ip:on(self.PROTOCOL, function(packet)
    local ok, datagram = pcall(codec.decode, packet.payload)
    if not ok or type(datagram) ~= "table" or datagram.v ~= 1 or
        type(datagram.srcPort) ~= "number" or type(datagram.dstPort) ~= "number" or
        type(datagram.payload) ~= "string" then return true end
    datagram.src, datagram.dst, datagram.interface = packet.src, packet.dst, packet.interface
    local handlers = self.handlers[datagram.dstPort] or {}
    for _, handler in ipairs(handlers) do
      local handled, consumed = pcall(handler, datagram, packet)
      if handled and consumed then return true end
    end
    if not self.bound[datagram.dstPort] then return true end
    local queue = self.queues[datagram.dstPort] or {}
    self.queues[datagram.dstPort] = queue
    queue[#queue + 1] = datagram
    return true
  end)
  return self
end

function UDP:on(port, handler)
  assert(type(port) == "number" and port >= 0 and port <= 65535, "invalid UDP port")
  assert(type(handler) == "function", "UDP handler must be a function")
  local handlers = self.handlers[port] or {}
  self.handlers[port] = handlers
  handlers[#handlers + 1] = handler
  return handler
end

function UDP:send(destination, destinationPort, payload, options)
  options = options or {}
  local sourcePort = options.sourcePort
  if not sourcePort then
    sourcePort = self.nextPort
    self.nextPort = self.nextPort >= 65535 and 49152 or self.nextPort + 1
  end
  assert(type(destinationPort) == "number" and destinationPort >= 0 and
    destinationPort <= 65535, "invalid destination UDP port")
  assert(type(payload) == "string", "UDP payload must be a string")
  return self.ip:send(destination, self.PROTOCOL, codec.encode({
    v = 1, srcPort = sourcePort, dstPort = destinationPort, payload = payload
  }), options)
end

function UDP:receive(port, timeout, predicate)
  self.bound[port] = true
  local deadline = self.ip.clock() + (timeout or math.huge)
  while self.ip.clock() < deadline do
    local queue = self.queues[port] or {}
    self.queues[port] = queue
    for index, datagram in ipairs(queue) do
      if not predicate or predicate(datagram) then return table.remove(queue, index) end
    end
    self.ip:pump(deadline - self.ip.clock())
  end
  return nil, "timeout"
end

return UDP
