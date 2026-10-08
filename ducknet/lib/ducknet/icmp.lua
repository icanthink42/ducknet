local codec = require("ducknet.codec")

local ICMP = {}
ICMP.__index = ICMP
ICMP.PROTOCOL = 1

local function decode(payload)
  local ok, message = pcall(codec.decode, payload)
  if ok and type(message) == "table" and message.v == 1 then return message end
end

function ICMP.new(ip, options)
  options = options or {}
  local self = setmetatable({
    ip = ip,
    clock = options.clock or ip.clock,
    counter = 0
  }, ICMP)

  ip:on(self.PROTOCOL, function(packet)
    local message = decode(packet.payload)
    if message and message.type == "echo_request" then
      ip:send(packet.src, self.PROTOCOL, codec.encode({
        v = 1, type = "echo_reply", id = message.id,
        sequence = message.sequence, data = message.data or ""
      }))
      return true
    end
    return false
  end)

  ip:onDrop(function(reason, packet)
    if reason == "ttl exceeded" and packet and packet.src ~= ip.address then
      local original = packet.protocol == self.PROTOCOL and decode(packet.payload) or nil
      ip:send(packet.src, self.PROTOCOL, codec.encode({
        v = 1, type = "time_exceeded", originalId = packet.id,
        echoId = original and original.id or nil,
        reporter = ip.address
      }))
    end
  end)
  return self
end

function ICMP:_id()
  self.counter = self.counter + 1
  return self.ip.address .. ":icmp:" .. self.counter
end

function ICMP:probe(destination, options)
  options = options or {}
  local identifier = self:_id()
  local started = self.clock()
  local sent, packetOrError = self.ip:send(destination, self.PROTOCOL, codec.encode({
    v = 1, type = "echo_request", id = identifier,
    sequence = options.sequence or self.counter, data = options.data or "ducknet"
  }), { ttl = options.ttl })
  if not sent then return nil, packetOrError end
  local packetId = packetOrError.id
  local deadline = started + (options.timeout or 2)
  repeat
    local packet, err = self.ip:receive(self.PROTOCOL, deadline - self.clock())
    if not packet then return nil, err end
    local message = decode(packet.payload)
    if message and message.type == "echo_reply" and message.id == identifier then
      return {
        kind = "reply", from = packet.src, elapsed = self.clock() - started,
        sequence = message.sequence, hops = packet.hops
      }
    end
    if message and message.type == "time_exceeded" and
        (message.originalId == packetId or message.echoId == identifier) then
      return {
        kind = "ttl", from = packet.src, elapsed = self.clock() - started,
        reporter = message.reporter or packet.src
      }
    end
  until self.clock() >= deadline
  return nil, "timeout"
end

function ICMP:ping(destination, options)
  return self:probe(destination, options)
end

return ICMP

