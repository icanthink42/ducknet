local root = (... and ... ~= "" and ...) or "."
local originalFs, originalMultishell, originalQueueEvent = _G.fs, _G.multishell, os.queueEvent
local originalParallel, originalShell, originalPullEvent, originalSleep =
  _G.parallel, _G.shell, os.pullEvent, _G.sleep
local originalConfig = package.loaded["ducknet.config"]
local records, tabs, events, nextPid = {}, {}, {}, 1

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
package.loaded["ducknet.config"] = {
  load = function(path)
    if not records[path] then return nil, "missing" end
    return copy(records[path])
  end,
  save = function(value, path) records[path] = copy(value) return true end
}
_G.fs = {
  makeDir = function() end,
  exists = function(path)
    if records[path] then return true end
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
  open = function(path)
    local chunks = {}
    return {
      write = function(value) chunks[#chunks + 1] = value end,
      close = function() records[path] = table.concat(chunks) end
    }
  end,
  delete = function(path) records[path] = nil end
}
_G.multishell = {
  launch = function(_, program, name)
    nextPid = nextPid + 1
    tabs[nextPid] = { program = program, service = name }
    return nextPid
  end,
  setTitle = function(pid, title) tabs[pid].title = title end,
  getTitle = function(pid) assert(tabs[pid], "no tab") return tabs[pid].title end
}
os.queueEvent = function(...) events[#events + 1] = { ... } end

local program = assert(loadfile(root .. "/ducknet/bin/systemdck.lua"))
program("start", "demo")
local state = records["/var/run/systemdck/demo.lua"]
assert(state.state == "running" and state.pid == 2)
assert(tabs[2].program == "/ducknet/bin/systemdck-run.lua")
program("restart", "demo")
state = records["/var/run/systemdck/demo.lua"]
assert(state.state == "restarting" and state.pid == 2)
assert(events[#events][1] == "systemdck_control" and events[#events][3] == "restart")
program("disable", "demo")
assert(not records["/etc/systemdck/demo.lua"].enabled)
program("enable", "demo")
assert(records["/etc/systemdck/demo.lua"].enabled)
program("create", "worker", "/worker.lua", "hello")
assert(records["/etc/systemdck/worker.lua"].arguments[1] == "hello")
program("start-enabled")
assert(records["/var/run/systemdck/worker.lua"].state == "running")
program("remove", "worker")
assert(not records["/etc/systemdck/worker.lua"])

-- A control event cleanly stops the runner and its managed coroutine.
records["/var/run/systemdck/demo.lua"] = { state = "running", pid = 2 }
_G.parallel = { waitForAny = function(_, control) control() return 2 end }
_G.shell = { run = function() error("service should have been cancelled") end }
os.pullEvent = function() return "systemdck_control", "demo", "stop" end
_G.sleep = function() end
assert(loadfile(root .. "/ducknet/bin/systemdck-run.lua"))("demo")
assert(records["/var/run/systemdck/demo.lua"].state == "inactive")

_G.fs, _G.multishell, os.queueEvent = originalFs, originalMultishell, originalQueueEvent
_G.parallel, _G.shell, os.pullEvent, _G.sleep =
  originalParallel, originalShell, originalPullEvent, originalSleep
package.loaded["ducknet.config"] = originalConfig
io.write("all systemdck tests passed\n")
