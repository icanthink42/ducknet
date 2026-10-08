local event = require("event")
local computer = require("computer")

local Link = {}
Link.__index = Link

function Link.new(modem, options)
  options = options or {}
  assert(modem, "a modem component is required")
  local self = setmetatable({
    modem = modem,
    port = options.port or 4660,
    peers = options.peers or {},
    broadcastUnknown = options.broadcastUnknown == true
  }, Link)
  modem.open(self.port)
  return self
end

function Link:addPeer(logicalAddress, modemAddress)
  self.peers[logicalAddress] = modemAddress
end

function Link:send(nextHop, frame)
  local hardwareAddress = self.peers[nextHop]
  if hardwareAddress then
    return self.modem.send(hardwareAddress, self.port, "ducknet:1", frame)
  end
  if self.broadcastUnknown then
    return self.modem.broadcast(self.port, "ducknet:1", frame)
  end
  return nil, "no modem peer for next hop " .. tostring(nextHop)
end

function Link:receive(timeout)
  local deadline = computer.uptime() + (timeout or math.huge)
  while true do
    local remaining = timeout
    remaining = deadline - computer.uptime()
    if remaining <= 0 then return nil, "timeout" end
    local name, _, from, port, _, marker, frame = event.pull(remaining, "modem_message")
    if not name then return nil, "timeout" end
    if port == self.port and marker == "ducknet:1" and type(frame) == "string" then
      return from, frame
    end
  end
end

function Link:close()
  self.modem.close(self.port)
end

return Link
