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
    modemName = options.modemName or modemName,
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

function Link:_decodeEvent(eventData)
  if self.platform == "computercraft" then
    local side, channel, message = eventData[2], eventData[3], eventData[5]
    if (not self.modemName or side == self.modemName) and channel == self.port and
        type(message) == "table" and message.marker == "ducknet:1" and
        type(message.frame) == "string" and
        (not message.target or message.target == self.address) then
      return message.source or side, message.frame
    end
    return nil
  end

  local localAddress, from, port, marker, frame =
    eventData[2], eventData[3], eventData[4], eventData[6], eventData[7]
  local modemAddress = self.modem.address
  if (not modemAddress or localAddress == modemAddress) and port == self.port and
      marker == "ducknet:1" and type(frame) == "string" then
    return from, frame
  end
end

-- Wait on several interfaces through one event loop. Calling receive() on each
-- modem in sequence would discard events belonging to the other modems.
function Link:receiveAny(links, timeout)
  assert(type(links) == "table" and #links > 0, "at least one link is required")
  if self.platform == "computercraft" then
    local timer
    if timeout and timeout < math.huge then timer = os.startTimer(math.max(0, timeout)) end
    while true do
      local eventData = { os.pullEvent() }
      if eventData[1] == "timer" and eventData[2] == timer then return nil, "timeout" end
      if eventData[1] == "modem_message" then
        for _, link in ipairs(links) do
          local from, frame = link:_decodeEvent(eventData)
          if frame then
            if timer then os.cancelTimer(timer) end
            return from, frame, link
          end
        end
      end
    end
  end

  local deadline = self.computer.uptime() + (timeout or math.huge)
  while true do
    local remaining = deadline - self.computer.uptime()
    if remaining <= 0 then return nil, "timeout" end
    local eventData = { self.event.pull(remaining, "modem_message") }
    if not eventData[1] then return nil, "timeout" end
    for _, link in ipairs(links) do
      local from, frame = link:_decodeEvent(eventData)
      if frame then return from, frame, link end
    end
  end
end

function Link:addPeer(logicalAddress, modemAddress)
  self.peers[logicalAddress] = modemAddress
end

function Link:send(nextHop, frame)
  if self.platform == "computercraft" then
    local target = nextHop
    if nextHop == "255.255.255.255" then target = nil end
    self.modem.transmit(self.port, self.port, {
      marker = "ducknet:1", source = self.address,
      target = target, frame = frame
    })
    return true
  end
  if nextHop == "255.255.255.255" then
    return self.modem.broadcast(self.port, "ducknet:1", frame)
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
  return self:receiveAny({ self }, timeout)
end

function Link:close()
  self.modem.close(self.port)
end

return Link
