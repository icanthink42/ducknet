local codec = require("ducknet.codec")
local config = require("ducknet.config")

local DHCP = { SERVER_PORT = 67, CLIENT_PORT = 68, BROADCAST = "255.255.255.255" }

local function ipv4(address)
  local a, b, c, d = tostring(address):match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
  a, b, c, d = tonumber(a), tonumber(b), tonumber(c), tonumber(d)
  assert(a and a <= 255 and b <= 255 and c <= 255 and d <= 255, "invalid IPv4 address")
  return ((a * 256 + b) * 256 + c) * 256 + d
end

local function address(value)
  local d = value % 256
  value = math.floor(value / 256)
  local c = value % 256
  value = math.floor(value / 256)
  local b = value % 256
  local a = math.floor(value / 256)
  return string.format("%d.%d.%d.%d", a, b, c, d)
end

local function now()
  if os.epoch then return math.floor(os.epoch("utc") / 1000) end
  if os.time then return os.time() end
  return os.clock()
end

local function decode(payload)
  local ok, message = pcall(codec.decode, payload)
  if ok and type(message) == "table" and message.v == 1 then return message end
end

local function encode(message)
  message.v = 1
  return codec.encode(message)
end

local Server = {}
Server.__index = Server

function DHCP.server(udp, ip, options)
  options = options or {}
  local stored = config.load(options.leasePath or "/etc/ducknet/dhcp-leases.lua")
  local self = setmetatable({
    udp = udp, ip = ip, pools = {}, offers = {},
    leases = stored and stored.leases or {},
    leasePath = options.leasePath or "/etc/ducknet/dhcp-leases.lua",
    clock = options.clock or now
  }, Server)
  for _, pool in ipairs(options.pools or {}) do self:addPool(pool) end
  udp:on(DHCP.SERVER_PORT, function(datagram)
    return self:_handle(datagram)
  end)
  return self
end

function Server:addPool(pool)
  assert(type(pool.interface) == "string", "DHCP pool requires an interface")
  local interface = self.ip.interfaceByName[pool.interface]
  assert(interface, "unknown DHCP interface " .. pool.interface)
  local first, last = ipv4(pool.first or pool.start), ipv4(pool.last or pool.finish)
  assert(first <= last, "DHCP pool start must not exceed its end")
  local network = assert(pool.network or pool.subnet, "DHCP pool requires a subnet")
  local baseAddress, prefix = network:match("^([^/]+)/(%d+)$")
  prefix = tonumber(prefix)
  assert(prefix and prefix >= 0 and prefix <= 32, "invalid DHCP pool subnet")
  local block = 2 ^ (32 - prefix)
  local base = math.floor(ipv4(baseAddress) / block) * block
  assert(math.floor(first / block) * block == base and
    math.floor(last / block) * block == base, "DHCP pool must be inside its subnet")
  if prefix <= 30 then
    assert(first > base and last < base + block - 1,
      "DHCP pool cannot include the network or broadcast address")
  end
  local gateway = pool.gateway or interface.address
  local gatewayValue = ipv4(gateway)
  assert(gatewayValue < first or gatewayValue > last,
    "DHCP pool cannot include the gateway address")
  self.pools[pool.interface] = {
    interface = pool.interface, first = first, last = last,
    network = network, prefix = prefix,
    gateway = gateway,
    lease = pool.lease or 3600
  }
end

function Server:_save()
  return config.save({ leases = self.leases }, self.leasePath)
end

function Server:_pool(interfaceName)
  return interfaceName and self.pools[interfaceName]
end

function Server:_allocate(pool, clientId)
  local current = self.clock()
  for xid, offer in pairs(self.offers) do
    if offer.expires <= current then self.offers[xid] = nil end
  end
  for leasedAddress, lease in pairs(self.leases) do
    if lease.clientId == clientId and lease.interface == pool.interface and
        (lease.expires or 0) > current then return leasedAddress end
  end
  for value = pool.first, pool.last do
    local candidate = address(value)
    local lease = self.leases[candidate]
    local offered = false
    for _, offer in pairs(self.offers) do
      if offer.address == candidate and offer.expires > current then offered = true break end
    end
    if not offered and (not lease or (lease.expires or 0) <= current) then return candidate end
  end
end

function Server:_reply(interfaceName, message)
  return self.udp:send(DHCP.BROADCAST, DHCP.CLIENT_PORT, encode(message), {
    sourcePort = DHCP.SERVER_PORT, interface = interfaceName
  })
end

function Server:_handle(datagram)
  local message = decode(datagram.payload)
  if not message or type(message.clientId) ~= "string" or type(message.xid) ~= "string" then
    return true
  end
  local pool = self:_pool(datagram.interface)
  if not pool then return true end

  if message.type == "discover" then
    local offered = self:_allocate(pool, message.clientId)
    if not offered then
      self:_reply(pool.interface, { type = "nak", xid = message.xid,
        clientId = message.clientId, reason = "address pool exhausted" })
      return true
    end
    self.offers[message.xid] = {
      clientId = message.clientId, address = offered,
      interface = pool.interface, expires = self.clock() + 30
    }
    self:_reply(pool.interface, {
      type = "offer", xid = message.xid, clientId = message.clientId,
      address = offered, prefix = pool.prefix, gateway = pool.gateway,
      server = self.ip.interfaceByName[pool.interface].address, lease = pool.lease
    })
    return true
  end

  if message.type == "request" then
    local localServer = self.ip.interfaceByName[pool.interface].address
    if message.server and message.server ~= localServer then return true end
    local offer = self.offers[message.xid]
    if not offer or offer.clientId ~= message.clientId or
        offer.address ~= message.address or offer.interface ~= pool.interface or
        offer.expires < self.clock() then
      self:_reply(pool.interface, { type = "nak", xid = message.xid,
        clientId = message.clientId, reason = "invalid or expired offer" })
      return true
    end
    self.leases[offer.address] = {
      clientId = message.clientId, interface = pool.interface,
      expires = self.clock() + pool.lease
    }
    self.offers[message.xid] = nil
    self:_save()
    self:_reply(pool.interface, {
      type = "ack", xid = message.xid, clientId = message.clientId,
      address = offer.address, prefix = pool.prefix, gateway = pool.gateway,
      server = self.ip.interfaceByName[pool.interface].address,
      lease = pool.lease, obtained = self.clock()
    })
    return true
  end

  if message.type == "release" then
    local lease = self.leases[message.address]
    if lease and lease.clientId == message.clientId then
      self.leases[message.address] = nil
      self:_save()
    end
    return true
  end
  return true
end

local Client = {}

local function transaction(clientId)
  return clientId .. ":" .. tostring(os.clock()) .. ":" .. tostring(math.random(1, 2147483647))
end

function Client.acquire(udp, clientId, options)
  options = options or {}
  local retries, timeout = options.retries or 3, options.timeout or 3
  for _ = 1, retries do
    local xid = transaction(clientId)
    local sendOptions = { sourcePort = DHCP.CLIENT_PORT,
      source = "0.0.0.0", interface = options.interface or "default" }
    local sent, sendError = udp:send(DHCP.BROADCAST, DHCP.SERVER_PORT,
      encode({ type = "discover", xid = xid, clientId = clientId }), sendOptions)
    if not sent then return nil, sendError end
    local offer = udp:receive(DHCP.CLIENT_PORT, timeout, function(datagram)
      local message = decode(datagram.payload)
      return message and message.xid == xid and message.clientId == clientId and
        (message.type == "offer" or message.type == "nak")
    end)
    if offer then
      local offered = decode(offer.payload)
      if offered.type == "nak" then return nil, offered.reason end
      assert(udp:send(DHCP.BROADCAST, DHCP.SERVER_PORT, encode({
        type = "request", xid = xid, clientId = clientId,
        address = offered.address, server = offered.server
      }), sendOptions))
      local reply = udp:receive(DHCP.CLIENT_PORT, timeout, function(datagram)
        local message = decode(datagram.payload)
        return message and message.xid == xid and message.clientId == clientId and
          (message.type == "ack" or message.type == "nak")
      end)
      if reply then
        local acknowledged = decode(reply.payload)
        if acknowledged.type == "ack" then return acknowledged end
        return nil, acknowledged.reason
      end
    end
  end
  return nil, "DHCP request timed out"
end

function Client.release(udp, clientId, leasedAddress, options)
  options = options or {}
  return udp:send(DHCP.BROADCAST, DHCP.SERVER_PORT, encode({
    type = "release", xid = transaction(clientId), clientId = clientId,
    address = leasedAddress
  }), { sourcePort = DHCP.CLIENT_PORT, source = leasedAddress,
    interface = options.interface or "default" })
end

DHCP.Client = Client
DHCP._decode = decode
DHCP._encode = encode
return DHCP
