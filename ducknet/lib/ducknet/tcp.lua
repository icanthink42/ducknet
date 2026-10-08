local codec = require("ducknet.codec")

local TCP = {}
TCP.__index = TCP
TCP.PROTOCOL = 6

local Socket = {}
Socket.__index = Socket

local Listener = {}
Listener.__index = Listener

local function has(flags, flag)
  return type(flags) == "string" and flags:find(flag, 1, true) ~= nil
end

local function defaultClock()
  local ok, computer = pcall(require, "computer")
  return ok and computer.uptime() or os.clock()
end

function TCP.new(ip, options)
  options = options or {}
  return setmetatable({
    ip = ip,
    mtu = options.mtu or 4096,
    timeout = options.timeout or 2,
    retries = options.retries or 4,
    clock = options.clock or defaultClock,
    random = options.random or math.random,
    pending = {}
  }, TCP)
end

function TCP:_send(remote, segment)
  return self.ip:send(remote, self.PROTOCOL, codec.encode(segment))
end

function TCP:_receiveMatching(predicate, timeout)
  local deadline = self.clock() + timeout
  for index, item in ipairs(self.pending) do
    if predicate(item.packet, item.segment) then
      table.remove(self.pending, index)
      return item.packet, item.segment
    end
  end
  repeat
    local packet, err = self.ip:receive(self.PROTOCOL, deadline - self.clock())
    if not packet then return nil, err end
    local ok, segment = pcall(codec.decode, packet.payload)
    if ok and type(segment) == "table" and segment.v == 1 then
      if predicate(packet, segment) then return packet, segment end
      self.pending[#self.pending + 1] = { packet = packet, segment = segment }
    end
  until self.clock() >= deadline
  return nil, "timeout"
end

local function socket(manager, remote, localPort, remotePort, connection, sequence)
  return setmetatable({
    manager = manager, remote = remote, localPort = localPort,
    remotePort = remotePort, connection = connection,
    sendSequence = sequence or 1, receiveSequence = 1, closed = false
  }, Socket)
end

function TCP:connect(remote, port, options)
  options = options or {}
  local localPort = options.localPort or self.random(49152, 65535)
  local connection = tostring(self.random(1, 2147483647)) .. ":" .. localPort
  local syn = { v = 1, conn = connection, srcPort = localPort, dstPort = port,
    seq = 0, ack = 0, flags = "SYN", data = "" }
  for _ = 1, self.retries do
    local sent, sendError = self:_send(remote, syn)
    if not sent then return nil, sendError end
    local _, reply = self:_receiveMatching(function(packet, segment)
      return packet.src == remote and segment.conn == connection and
        segment.dstPort == localPort and has(segment.flags, "SYN") and
        has(segment.flags, "ACK")
    end, self.timeout)
    if reply then
      self:_send(remote, { v = 1, conn = connection, srcPort = localPort,
        dstPort = port, seq = 1, ack = 1, flags = "ACK", data = "" })
      return socket(self, remote, localPort, port, connection, 1)
    end
  end
  return nil, "connection timed out"
end

function TCP:listen(port)
  assert(type(port) == "number" and port >= 1 and port <= 65535, "invalid port")
  return setmetatable({ manager = self, port = port, closed = false }, Listener)
end

function Listener:accept(timeout)
  if self.closed then return nil, "listener closed" end
  local packet, syn = self.manager:_receiveMatching(function(_, segment)
    return segment.dstPort == self.port and has(segment.flags, "SYN") and
      not has(segment.flags, "ACK")
  end, timeout or math.huge)
  if not packet then return nil, syn end
  local reply = { v = 1, conn = syn.conn, srcPort = self.port,
    dstPort = syn.srcPort, seq = 0, ack = 1, flags = "SYN,ACK", data = "" }
  for _ = 1, self.manager.retries do
    self.manager:_send(packet.src, reply)
    local acceptedPacket, ack = self.manager:_receiveMatching(function(candidate, segment)
      return candidate.src == packet.src and segment.conn == syn.conn and
        segment.dstPort == self.port and
        ((has(segment.flags, "ACK") and not has(segment.flags, "SYN")) or
        has(segment.flags, "DATA"))
    end, self.manager.timeout)
    if ack then
      -- The first DATA segment also proves the client received SYN|ACK. Preserve
      -- it for Socket:receive when the final handshake ACK was lost.
      if has(ack.flags, "DATA") then
        self.manager.pending[#self.manager.pending + 1] = {
          packet = acceptedPacket, segment = ack
        }
      end
      return socket(self.manager, packet.src, self.port, syn.srcPort, syn.conn, 1)
    end
  end
  return nil, "handshake timed out"
end

function Listener:close()
  self.closed = true
end

function Socket:_matches(packet, segment)
  return packet.src == self.remote and segment.conn == self.connection and
    segment.srcPort == self.remotePort and segment.dstPort == self.localPort
end

function Socket:_ack(sequence)
  return self.manager:_send(self.remote, {
    v = 1, conn = self.connection, srcPort = self.localPort,
    dstPort = self.remotePort, seq = self.sendSequence,
    ack = sequence, flags = "ACK", data = ""
  })
end

function Socket:send(data)
  assert(not self.closed, "socket closed")
  assert(type(data) == "string", "data must be a string")
  local position = 1
  repeat
    local chunk = data:sub(position, position + self.manager.mtu - 1)
    position = position + #chunk
    local more = position <= #data
    local sequence = self.sendSequence
    local segment = { v = 1, conn = self.connection, srcPort = self.localPort,
      dstPort = self.remotePort, seq = sequence, ack = 0, flags = "DATA",
      data = chunk, more = more }
    local acknowledged = false
    for _ = 1, self.manager.retries do
      local sent, sendError = self.manager:_send(self.remote, segment)
      if not sent then return nil, sendError end
      local _, ack = self.manager:_receiveMatching(function(packet, candidate)
        return self:_matches(packet, candidate) and has(candidate.flags, "ACK") and
          candidate.ack == sequence
      end, self.manager.timeout)
      if ack then acknowledged = true break end
    end
    if not acknowledged then return nil, "acknowledgement timed out" end
    self.sendSequence = self.sendSequence + 1
  until position > #data
  return true
end

function Socket:receive(timeout)
  if self.closed then return nil, "socket closed" end
  local chunks = {}
  repeat
    local packet, segment = self.manager:_receiveMatching(function(candidate, value)
      return self:_matches(candidate, value) and
        (has(value.flags, "DATA") or has(value.flags, "FIN"))
    end, timeout or math.huge)
    if not packet then return nil, segment end
    if has(segment.flags, "FIN") then
      self:_ack(segment.seq)
      self.closed = true
      return nil, "closed"
    end
    if segment.seq == self.receiveSequence then
      chunks[#chunks + 1] = segment.data or ""
      self.receiveSequence = self.receiveSequence + 1
      self:_ack(segment.seq)
      if not segment.more then return table.concat(chunks) end
    elseif segment.seq < self.receiveSequence then
      -- An ACK was lost. ACK the duplicate but don't surface a second message.
      self:_ack(segment.seq)
    else
      -- Stop-and-wait should not arrive out of order. ACK the last contiguous
      -- sequence so the sender can retry the missing one.
      self:_ack(self.receiveSequence - 1)
    end
  until false
end

function Socket:close()
  if self.closed then return true end
  self.manager:_send(self.remote, { v = 1, conn = self.connection,
    srcPort = self.localPort, dstPort = self.remotePort,
    seq = self.sendSequence, ack = 0, flags = "FIN", data = "" })
  self.closed = true
  return true
end

return TCP
