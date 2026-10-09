local codec = require("ducknet.codec")

local DLTP = {}
DLTP.__index = DLTP

local Server = {}
Server.__index = Server

local function pack(value)
  return codec.encode({ v = 1, body = codec.encode(value) })
end

local function unpackMessage(wire)
  local ok, outer = pcall(codec.decode, wire)
  if not ok or type(outer) ~= "table" or outer.v ~= 1 then return nil, "invalid DLTP message" end
  local decoded, value = pcall(codec.decode, outer.body)
  if not decoded or type(value) ~= "table" then return nil, "invalid DLTP body" end
  return value
end

function DLTP.new(tcp, options)
  options = options or {}
  return setmetatable({ tcp = tcp, port = options.port or 80,
    timeout = options.timeout or 10 }, DLTP)
end

function DLTP:request(host, method, path, options)
  options = options or {}
  local connection, err = self.tcp:connect(host, options.port or self.port)
  if not connection then return nil, err end
  local request = { v = 1, method = method or "GET", path = path or "/",
    headers = options.headers or {}, body = options.body or "" }
  local sent
  sent, err = connection:send(pack(request))
  if not sent then connection:close() return nil, err end
  local wire
  wire, err = connection:receive(options.timeout or self.timeout)
  connection:close()
  if not wire then return nil, err end
  return unpackMessage(wire)
end

function DLTP:server(options)
  options = options or {}
  return setmetatable({
    dltp = self, listener = self.tcp:listen(options.port or self.port),
    routes = {}, middleware = {}, notFound = options.notFound
  }, Server)
end

function Server:use(handler)
  self.middleware[#self.middleware + 1] = handler
  return self
end

function Server:route(method, pattern, handler)
  self.routes[#self.routes + 1] = { method = method, pattern = pattern, handler = handler }
  return self
end

function Server:get(pattern, handler) return self:route("GET", pattern, handler) end
function Server:post(pattern, handler) return self:route("POST", pattern, handler) end

local function matchPath(pattern, path)
  local wanted, actual = {}, {}
  for part in pattern:gmatch("[^/]+") do wanted[#wanted + 1] = part end
  for part in path:gmatch("[^/]+") do actual[#actual + 1] = part end
  if #wanted ~= #actual then return nil end
  local params = {}
  for index, part in ipairs(wanted) do
    if part:sub(1, 1) == ":" then params[part:sub(2)] = actual[index]
    elseif part ~= actual[index] then return nil end
  end
  return params
end

function Server:_dispatch(request)
  for _, middleware in ipairs(self.middleware) do
    local response = middleware(request)
    if response then return response end
  end
  for _, route in ipairs(self.routes) do
    local params = route.method == request.method and matchPath(route.pattern, request.path)
    if params then
      request.params = params
      return route.handler(request)
    end
  end
  if self.notFound then return self.notFound(request) end
  return { status = 404, headers = {}, body = "Not Found" }
end

function Server:serveOnce(timeout)
  local connection, err = self.listener:accept(timeout)
  if not connection then return nil, err end
  local wire
  wire, err = connection:receive(self.dltp.timeout)
  if not wire then connection:close() return nil, err end
  local request
  request, err = unpackMessage(wire)
  local response
  if request then
    local ok, result = pcall(function() return self:_dispatch(request) end)
    response = ok and result or { status = 500, headers = {}, body = "Application error" }
  else
    response = { status = 400, headers = {}, body = err }
  end
  response = response or { status = 204, headers = {}, body = "" }
  response.v = 1
  local sent, sendError = connection:send(pack(response))
  connection:close()
  if not sent then return nil, sendError end
  return true
end

function Server:run()
  while true do self:serveOnce(math.huge) end
end

return DLTP
