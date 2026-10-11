local root = (... and ... ~= "" and ...) or "."
package.path = root .. "/ducknet/lib/?.lua;" .. root .. "/ducknet/lib/?/init.lua;" .. package.path
local originalFs, originalParallel, originalTerm, originalColors, originalShell, originalKeys =
  _G.fs, _G.parallel, _G.term, _G.colors, _G.shell, _G.keys
local originalQueueEvent, originalPullEvent, originalStartTimer =
  os.queueEvent, os.pullEvent, os.startTimer
local originalPullEventRaw = os.pullEventRaw
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
_G.colors = { white = 1, black = 32768 }
_G.keys = {
  pageUp = 266, pageDown = 267, home = 268, ["end"] = 269,
  numPad1 = 321, numPad3 = 323, numPad7 = 327, numPad9 = 329
}
local terminalRows, terminalCursor, redirected = {}, { 1, 1 }
local nativeTerminal = {
  getSize = function() return 12, 4 end,
  getTextColor = function() return 1 end,
  getBackgroundColor = function() return 32768 end,
  setCursorPos = function(x, y) terminalCursor = { x, y } end,
  setCursorBlink = function() end,
  blit = function(text) terminalRows[terminalCursor[2]] = text end,
  isColor = function() return true end,
  setPaletteColor = function() end,
  getPaletteColor = function() return 0, 0, 0 end,
  nativePaletteColor = function() return 0, 0, 0 end
}
_G.term = {
  current = function() return redirected or nativeTerminal end,
  redirect = function(target)
    local previous = redirected or nativeTerminal
    redirected = target
    return previous
  end
}
_G.shell = {
  run = function(command)
    assert(command == "shell")
    for index = 1, 8 do
      redirected.setCursorPos(1, 4)
      redirected.write("line " .. index)
      redirected.scroll(1)
    end
    while true do coroutine.yield() end
  end
}
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
os.pullEventRaw = os.pullEvent
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
local hostRequire = require
programEnvironment.require = function(name)
  if name == "cc.require" then
    return { make = function()
      return hostRequire, { path = package.path }
    end }
  end
  return hostRequire(name)
end
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

-- Boot builds one manager, one interactive shell, and sixteen workers.
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
programEnvironment.loadfile = function(path, mode, environment)
  serviceEnvironment = environment
  assert(path == "/test.lua" and mode == nil)
  return function(argument) assert(argument == "one") return true end
end
local worker = coroutine.create(bootTasks[3])
assert(coroutine.resume(worker))
assert(coroutine.status(worker) == "suspended")
assert(serviceEnvironment.package ~= package,
  "service environment did not receive an isolated package library")
assert(serviceEnvironment.package.path == package.path)
assert(type(serviceEnvironment.require) == "function")
assert(serviceEnvironment._G == serviceEnvironment)
assert(records["/var/run/systemdck/demo.lua"].state == "inactive")

-- Keypad navigation is processed inside the foreground shell scheduler before
-- it is forwarded to CraftOS. Some keyboards report their Page Up key as
-- numPad9, including the layout used by the in-game test computer.
local rawEvents = {
  { "key", 329, false },
  { "char", "9" },
}
os.pullEventRaw = function()
  local nextEvent = table.remove(rawEvents, 1)
  if not nextEvent then return coroutine.yield() end
  return table.unpack(nextEvent)
end
local interactive = coroutine.create(bootTasks[2])
assert(coroutine.resume(interactive))
assert(coroutine.status(interactive) == "suspended")
assert(terminalRows[1]:match("line 4"),
  "keypad Page Up character returned the console to live output")

-- Ctrl+T reaches the foreground shell, but background environments and the
-- supervisor ignore the broadcast terminate event.
rawEvents = {
  { "terminate" },
  { "modem_message", "left" },
}
os.pullEventRaw = function()
  local event = table.remove(rawEvents, 1)
  if not event then return coroutine.yield() end
  return table.unpack(event)
end
local event, side = serviceEnvironment.os.pullEventRaw("modem_message")
assert(event == "modem_message" and side == "left")
rawEvents = { { "terminate" } }
local manager = coroutine.create(bootTasks[1])
assert(coroutine.resume(manager))
assert(coroutine.status(manager) == "suspended")

local source = assert(io.open(root .. "/ducknet/bin/systemdck.lua", "r")):read("*a")
assert(source:find("parallel.waitForAll", 1, true))
assert(not source:find("multishell", 1, true))
assert(not source:find("os.run", 1, true))

_G.fs, _G.parallel = originalFs, originalParallel
_G.term, _G.colors, _G.shell, _G.keys = originalTerm, originalColors, originalShell, originalKeys
os.queueEvent, os.pullEvent, os.startTimer =
  originalQueueEvent, originalPullEvent, originalStartTimer
os.pullEventRaw = originalPullEventRaw
package.loaded["ducknet.config"] = originalConfig
io.write("all systemdck tests passed\n")
