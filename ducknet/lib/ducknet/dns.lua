local codec = require("ducknet.codec")

local DNS = {
  PORT = 53,
  TYPES = { A = true, NS = true, CNAME = true, SOA = true, TXT = true, ANY = true }
}

local function now()
  if os.epoch then return math.floor(os.epoch("utc") / 1000) end
  if os.time then return os.time() end
  return os.clock()
end

local function copy(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for key, child in pairs(value) do result[copy(key)] = copy(child) end
  return result
end

local function isIPv4(value)
  local a, b, c, d = tostring(value):match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
  a, b, c, d = tonumber(a), tonumber(b), tonumber(c), tonumber(d)
  return a ~= nil and a <= 255 and b <= 255 and c <= 255 and d <= 255
end

function DNS.normalize(name)
  assert(type(name) == "string", "DNS name must be a string")
  name = name:lower():gsub("%.$", "")
  if name == "" then return "" end
  assert(name:sub(1, 1) ~= "." and name:sub(-1) ~= ".", "invalid DNS name")
  assert(#name <= 253, "DNS name is too long")
  for label in name:gmatch("[^.]+") do
    assert(#label <= 63 and label:match("^[a-z0-9_-]+$") and
      not label:match("^-") and not label:match("-$"), "invalid DNS name")
  end
  assert(not name:find("..", 1, true), "invalid DNS name")
  return name
end

function DNS.type(value)
  value = tostring(value or "A"):upper()
  assert(DNS.TYPES[value], "unsupported DNS record type: " .. value)
  return value
end

local function beneath(name, zone)
  return zone == "" or name == zone or name:sub(-#zone - 1) == "." .. zone
end

local function encode(message)
  message.v = 1
  return codec.encode(message)
end

local function decode(payload)
  local ok, message = pcall(codec.decode, payload)
  if not ok or type(message) ~= "table" or message.v ~= 1 or
      type(message.id) ~= "string" then return nil, "invalid DNS message" end
  return message
end

local Authority = {}
Authority.__index = Authority

function DNS.authority(zones)
  local self = setmetatable({ zones = {} }, Authority)
  for _, source in ipairs(zones or {}) do
    local zone = { name = DNS.normalize(source.name), records = {} }
    for _, sourceRecord in ipairs(source.records or {}) do
      local record = copy(sourceRecord)
      record.name = DNS.normalize(record.name)
      record.type = DNS.type(record.type)
      assert(record.type ~= "ANY", "ANY cannot be stored as a DNS record")
      assert(type(record.value) == "string", "DNS record value must be a string")
      if record.type == "A" then assert(isIPv4(record.value), "invalid DNS A record") end
      if record.type == "NS" or record.type == "CNAME" then
        record.value = DNS.normalize(record.value)
      end
      record.ttl = tonumber(record.ttl) or 300
      assert(record.ttl >= 0 and record.ttl % 1 == 0, "invalid DNS TTL")
      assert(beneath(record.name, zone.name), "DNS record is outside its zone")
      zone.records[#zone.records + 1] = record
    end
    self.zones[#self.zones + 1] = zone
  end
  table.sort(self.zones, function(left, right) return #left.name > #right.name end)
  return self
end

function Authority:_zone(name)
  for _, zone in ipairs(self.zones) do
    if beneath(name, zone.name) then return zone end
  end
end

local function recordsAt(zone, name, wanted)
  local result = {}
  for _, record in ipairs(zone.records) do
    if record.name == name and (wanted == "ANY" or record.type == wanted) then
      result[#result + 1] = copy(record)
    end
  end
  return result
end

function Authority:answer(name, recordType)
  name, recordType = DNS.normalize(name), DNS.type(recordType)
  local zone = self:_zone(name)
  if not zone then return nil, "not authoritative" end

  local delegation
  for _, record in ipairs(zone.records) do
    if record.type == "NS" and record.name ~= zone.name and beneath(name, record.name) and
        (not delegation or #record.name > #delegation) then delegation = record.name end
  end
  if delegation then
    local authority, additional = recordsAt(zone, delegation, "NS"), {}
    for _, nameserver in ipairs(authority) do
      local glue = recordsAt(zone, nameserver.value, "A")
      for _, record in ipairs(glue) do additional[#additional + 1] = record end
    end
    return { rcode = "NOERROR", aa = false, answers = {},
      authority = authority, additional = additional }
  end

  local answers = recordsAt(zone, name, recordType)
  if #answers == 0 and recordType ~= "CNAME" and recordType ~= "ANY" then
    answers = recordsAt(zone, name, "CNAME")
  end
  local exists = false
  for _, record in ipairs(zone.records) do
    if record.name == name then exists = true break end
  end
  local authority = {}
  if #answers == 0 then authority = recordsAt(zone, zone.name, "SOA") end
  return {
    rcode = exists and "NOERROR" or "NXDOMAIN", aa = true,
    answers = answers, authority = authority, additional = {}
  }
end

local Resolver = {}
Resolver.__index = Resolver

function DNS.resolver(udp, options)
  options = options or {}
  return setmetatable({
    udp = udp, servers = copy(options.servers or {}), roots = copy(options.roots or {}),
    search = copy(options.search or {}),
    timeout = options.timeout or 2, retries = options.retries or 2,
    maxReferrals = options.maxReferrals or 16, clock = options.clock or now,
    random = options.random or math.random, cache = {}, counter = 0
  }, Resolver)
end

function Resolver:_exchange(server, name, recordType, recursive)
  for _ = 1, self.retries do
    self.counter = self.counter + 1
    local id = tostring(self.clock()) .. ":" .. tostring(self.counter) .. ":" ..
      tostring(self.random(1, 2147483647))
    local sourcePort = self.random(49152, 65535)
    local sent, sendError = self.udp:send(server, DNS.PORT, encode({
      kind = "query", id = id, name = name, type = recordType, rd = recursive == true
    }), { sourcePort = sourcePort })
    if sent then
      local datagram, receiveError = self.udp:receive(sourcePort, self.timeout,
        function(candidate)
          local response = decode(candidate.payload)
          return candidate.src == server and response and response.kind == "response" and
            response.id == id
        end)
      if datagram then return decode(datagram.payload) end
      sendError = receiveError
    end
    if sendError and self.retries == 1 then return nil, sendError end
  end
  return nil, "DNS query timed out"
end

local function minimumTTL(response)
  local ttl
  for _, section in ipairs({ response.answers or {}, response.authority or {} }) do
    for _, record in ipairs(section) do
      local value = tonumber(record.ttl)
      if value then ttl = ttl and math.min(ttl, value) or value end
    end
  end
  return ttl or 30
end

function Resolver:_cached(key)
  local cached = self.cache[key]
  if not cached then return end
  if cached.expires <= self.clock() then self.cache[key] = nil return end
  return copy(cached.response)
end

function Resolver:_store(key, response)
  self.cache[key] = {
    expires = self.clock() + minimumTTL(response), response = copy(response)
  }
end

function Resolver:query(name, recordType, options)
  options = options or {}
  name, recordType = DNS.normalize(name), DNS.type(recordType)
  local key = name .. "|" .. recordType
  if not options.noCache then
    local cached = self:_cached(key)
    if cached then cached.cached = true return cached end
  end

  local servers = copy(options.servers or
    (#self.servers > 0 and self.servers or self.roots))
  if #servers == 0 then return nil, "no DNS servers configured" end
  local response, lastError
  for _ = 1, self.maxReferrals do
    response = nil
    for _, server in ipairs(servers) do
      response, lastError = self:_exchange(server, name, recordType, true)
      if response then break end
    end
    if not response then return nil, lastError or "all DNS servers failed" end
    response.answers = response.answers or {}
    response.authority = response.authority or {}
    response.additional = response.additional or {}
    if response.rcode ~= "NOERROR" or #response.answers > 0 then
      self:_store(key, response)
      return response
    end

    local nameservers, glue = {}, {}
    for _, record in ipairs(response.authority) do
      if record.type == "NS" then nameservers[#nameservers + 1] = record.value end
    end
    for _, record in ipairs(response.additional) do
      if record.type == "A" then glue[record.name] = record.value end
    end
    local nextServers = {}
    for _, nameserver in ipairs(nameservers) do
      if glue[nameserver] then nextServers[#nextServers + 1] = glue[nameserver] end
    end
    if #nextServers == 0 then
      for _, nameserver in ipairs(nameservers) do
        local nameserverResponse = self:query(nameserver, "A")
        if nameserverResponse then
          for _, record in ipairs(nameserverResponse.answers or {}) do
            if record.type == "A" then nextServers[#nextServers + 1] = record.value end
          end
        end
      end
    end
    if #nextServers == 0 then
      self:_store(key, response)
      return response
    end
    servers = nextServers
  end
  return nil, "too many DNS referrals"
end

function Resolver:_resolve(name, depth)
  if isIPv4(name) then return name end
  if depth > 8 then return nil, "too many DNS aliases" end
  local response, err = self:query(name, "A")
  if not response then return nil, err end
  if response.rcode ~= "NOERROR" then return nil, response.rcode end
  for _, record in ipairs(response.answers or {}) do
    if record.type == "A" then return record.value, response end
  end
  for _, record in ipairs(response.answers or {}) do
    if record.type == "CNAME" then return self:_resolve(record.value, depth + 1) end
  end
  return nil, "DNS name has no A record"
end

function Resolver:resolve(name)
  if isIPv4(name) then return name end
  local normalized = DNS.normalize(name)
  if not normalized:find(".", 1, true) then
    for _, suffix in ipairs(self.search) do
      local address = self:_resolve(normalized .. "." .. DNS.normalize(suffix), 0)
      if address then return address end
    end
  end
  return self:_resolve(normalized, 0)
end

local Server = {}
Server.__index = Server

function DNS.server(udp, options)
  options = options or {}
  local roots = options.roots or {}
  return setmetatable({
    udp = udp, authority = DNS.authority(options.zones), recursive = options.recursive == true,
    resolver = DNS.resolver(udp, {
      roots = roots, timeout = options.timeout, retries = options.retries,
      clock = options.clock, random = options.random
    })
  }, Server)
end

function Server:_response(query)
  if query.kind ~= "query" or type(query.name) ~= "string" then
    return { kind = "response", id = query.id, rcode = "FORMERR" }
  end
  local ok, response = pcall(self.authority.answer, self.authority,
    query.name, query.type or "A")
  if not ok then return { kind = "response", id = query.id, rcode = "FORMERR" } end
  if not response then
    if not self.recursive or not query.rd then
      return { kind = "response", id = query.id, rcode = "REFUSED", ra = self.recursive }
    end
    local recursive, err = self.resolver:query(query.name, query.type or "A")
    if not recursive then
      return { kind = "response", id = query.id, rcode = "SERVFAIL", error = err, ra = true }
    end
    response = recursive
    response.aa, response.ra = false, true
  end
  response.kind, response.id = "response", query.id
  return response
end

function Server:serveOnce(timeout)
  local datagram, err = self.udp:receive(DNS.PORT, timeout or math.huge)
  if not datagram then return nil, err end
  local query = decode(datagram.payload)
  if not query then return true end
  local response = self:_response(query)
  return self.udp:send(datagram.src, datagram.srcPort, encode(response), {
    -- Preserve the queried destination as the source address, but let IP choose
    -- the return route. Forcing the incoming interface treats remote clients as
    -- directly attached and bypasses the server's configured gateway.
    sourcePort = DNS.PORT, source = datagram.dst
  })
end

function Server:run()
  while true do self:serveOnce(math.huge) end
end

DNS.Authority = Authority
DNS.Resolver = Resolver
DNS.Server = Server
DNS._encode = encode
DNS._decode = decode
DNS._isIPv4 = isIPv4

return DNS
