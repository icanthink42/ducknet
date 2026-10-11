local root = (... and ... ~= "" and ...) or "."
local originalFs, originalParallel = _G.fs, _G.parallel
local originalQueueEvent, originalPullEvent, originalStartTimer =
  os.queueEvent, os.pullEvent, os.startTimer
local originalRun = os.run
local originalConfig = package.loaded["ducknet.config"]
local records, events = {}, {}

local function copy(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for key, child in pairs(value) do result[copy(key)] = copy(child) end
  return result
end

records["/etc/systemdck/demo.lua"] = {
  description = "Test service", program = "/test.lua", arguments = { "one" },
  enabled = true, restart = "always"
}
records["/var/run/systemdck/demo.lua"] = { state = "running", worker = 1, restarts = 2 }
package.loaded["ducknet.config"] = {
  load = function(path)
    if type(records[path]) ~= "table" then return nil, "missing" end
    return copy(records[path])
  end,
  save = function(value, path) records[path] = copy(value) return true end
}
_G.fs = {
  makeDir = function() end,
  exists = function(path)
    if records[path] ~= nil then return true end
    local prefix = path:gsub("/+$", "") .. "/"
    for candidate in pairs(records) do
      if candidate:sub(1, #prefix) == prefix then return true end
    end
    return false
  end,
  list = function(path)
    local result, prefix = {}, path:gsub("/+$", "") .. "/"
    for candidate in pairs(records) do
      if candidate:sub(1, #prefix) == prefix then
        local child = candidate:sub(#prefix + 1)
        if not child:find("/", 1, true) then result[#result + 1] = child end
      end
    end
    return result
  end,
  open = function(path, mode)
    local chunks = mode == "a" and { records[path] or "" } or {}
    return {
      write = function(value) chunks[#chunks + 1] = value end,
      readAll = function() return records[path] or "" end,
      close = function() if mode ~= "r" then records[path] = table.concat(chunks) end end
    }
  end,
  delete = function(path) records[path] = nil end
}
_G.parallel = {}
os.queueEvent = function(event, token, requested, name)
  if event == "systemdck_request" then
    events[#events + 1] = { "systemdck_response", token, true,
      requested .. " accepted for " .. name }
  end
end
os.pullEvent = function()
  local event = table.remove(events, 1)
  if not event then return coroutine.yield() end
  return table.unpack(event)
end
os.startTimer = function() return 99 end

-- CraftOS program environments contain package, while their _G base may not.
-- Keep those tables distinct so inheriting the wrong one fails this test.
local craftGlobal = {}
for key, value in pairs(_G) do
  if key ~= "package" then craftGlobal[key] = value end
end
craftGlobal._G = craftGlobal
local programEnvironment = setmetatable({ package = package }, { __index = craftGlobal })
programEnvironment._G = craftGlobal
local program = assert(loadfile(root .. "/ducknet/bin/systemdck.lua", "t", programEnvironment))
program("status", "demo")
program("start", "demo")
program("restart", "demo")
program("disable", "demo")
assert(not records["/etc/systemdck/demo.lua"].enabled)
program("enable", "demo")
assert(records["/etc/systemdck/demo.lua"].enabled)
assert(records["/startup/zz-systemdck.lua"]:find('"boot"', 1, true))
program("create", "worker", "/worker.lua", "hello")
assert(records["/etc/systemdck/worker.lua"].arguments[1] == "hello")
records["/var/log/systemdck/demo.log"] = "test log\n"
program("logs", "demo")
records["/var/run/systemdck/worker.lua"] = { state = "inactive" }
program("remove", "worker")
assert(not records["/etc/systemdck/worker.lua"])

-- Boot builds one manager, one interactive shell, and sixteen parallel workers.
local bootTasks, serviceEnvironment
records["/etc/systemdck/demo.lua"].restart = "no"
_G.parallel.waitForAll = function(...)
  assert(select("#", ...) == 18, "unexpected systemdck task count")
  bootTasks = { ... }
end
program("boot")
assert(records["/var/run/systemdck/demo.lua"].state == "starting")
assert(records["/var/run/systemdck/demo.lua"].worker == 1)
_G.parallel.waitForAny = function(run) run() return 1 end
os.run = function(environment, path, argument)
  serviceEnvironment = environment
  assert(path == "/test.lua" and argument == "one")
  return true
end
local worker = coroutine.create(bootTasks[3])
assert(coroutine.resume(worker))
assert(coroutine.status(worker) == "suspended")
assert(serviceEnvironment.package == package,
  "service environment did not inherit the global package library")
assert(serviceEnvironment._G == serviceEnvironment)
assert(records["/var/run/systemdck/demo.lua"].state == "inactive")

local source = assert(io.open(root .. "/ducknet/bin/systemdck.lua", "r")):read("*a")
assert(source:find("parallel.waitForAll", 1, true))
assert(not source:find("multishell", 1, true))

_G.fs, _G.parallel = originalFs, originalParallel
os.queueEvent, os.pullEvent, os.startTimer =
  originalQueueEvent, originalPullEvent, originalStartTimer
os.run = originalRun
package.loaded["ducknet.config"] = originalConfig
io.write("all systemdck tests passed\n")
