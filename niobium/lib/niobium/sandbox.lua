local Sandbox = {}
Sandbox.__index = Sandbox

local function copy(source)
  local target = {}
  for key, value in pairs(source) do target[key] = value end
  return target
end

function Sandbox.new(options)
  options = options or {}
  return setmetatable({
    instructionLimit = options.instructionLimit or 200000,
    modules = options.modules or {},
    onError = options.onError
  }, Sandbox)
end

function Sandbox:_environment(capabilities)
  local modules = {}
  for name, value in pairs(self.modules) do modules[name] = value end
  for name, value in pairs(capabilities or {}) do modules[name] = value end

  local environment = {
    assert = assert, error = error, ipairs = ipairs, next = next, pairs = pairs,
    pcall = pcall, select = select, tonumber = tonumber, tostring = tostring,
    type = type, xpcall = xpcall,
    math = copy(math), string = copy(string), table = copy(table),
    _VERSION = _VERSION
  }
  environment.require = function(name)
    assert(type(name) == "string", "module name must be a string")
    local module = modules[name]
    if module == nil then error("site does not have capability '" .. name .. "'", 2) end
    return module
  end
  environment._G = environment
  return environment
end

function Sandbox:run(source, capabilities, chunkName)
  assert(type(source) == "string", "site source must be a string")
  local environment = self:_environment(capabilities)
  local chunk, compileError = load(source, chunkName or "=ducknet-site", "t", environment)
  if not chunk then return nil, compileError end

  local used = 0
  local function meter()
    used = used + 1000
    if used > self.instructionLimit then error("site exceeded instruction limit", 0) end
  end
  debug.sethook(meter, "", 1000)
  local results = { pcall(chunk) }
  debug.sethook()
  if not results[1] then
    if self.onError then self.onError(results[2]) end
    return nil, results[2]
  end
  return true, results[2]
end

return Sandbox

