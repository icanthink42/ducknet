local Link = {}
Link.__index = Link

function Link.new(modem, options)
  options = options or {}
  local platform, event, computer, modemName
  if type(peripheral) == "table" and type(peripheral.find) == "function" then
    platform = "computercraft"
    if not modem then
      modem = peripheral.find("modem", function(name)
        modemName = name
        return true
      end)
    end
  else
    platform = "opencomputers"
    event = require("event")
    computer = require("computer")
    if not modem then modem = require("component").modem end
  end
  assert(modem, "a modem is required")
  local self = setmetatable({
    modem = modem,
    modemName = modemName,
    platform = platform,
    address = options.address,
    port = options.port or 4660,
    peers = options.peers or {},
    broadcastUnknown = options.broadcastUnknown == true
  }, Link)
  self.event, self.computer = event, computer
  modem.open(self.port)
  return self
end

function Link:addPeer(logicalAddress, modemAddress)
  self.peers[logicalAddress] = modemAddress
end

function Link:send(nextHop, frame)
  if self.platform == "computercraft" then
    self.modem.transmit(self.port, self.port, {
      marker = "ducknet:1", source = self.address,
      target = nextHop, frame = frame
    })
    return true
  end
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
  if self.platform == "computercraft" then
    local timer
    if timeout and timeout < math.huge then timer = os.startTimer(math.max(0, timeout)) end
    while true do
      local eventData = { os.pullEvent() }
      if eventData[1] == "timer" and eventData[2] == timer then return nil, "timeout" end
      if eventData[1] == "modem_message" then
        local channel, message = eventData[3], eventData[5]
        if channel == self.port and type(message) == "table" and
            message.marker == "ducknet:1" and type(message.frame) == "string" and
            (not message.target or message.target == self.address) then
          if timer then os.cancelTimer(timer) end
          return message.source or eventData[2], message.frame
        end
      end
    end
  end
  local deadline = self.computer.uptime() + (timeout or math.huge)
  while true do
    local remaining = timeout
    remaining = deadline - self.computer.uptime()
    if remaining <= 0 then return nil, "timeout" end
    local name, _, from, port, _, marker, frame = self.event.pull(remaining, "modem_message")
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
