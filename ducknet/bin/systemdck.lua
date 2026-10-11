local config = require("ducknet.config")

local UNIT_DIR = "/etc/systemdck"
local STATE_DIR = "/var/run/systemdck"
local RUNNER = "/ducknet/bin/systemdck-run.lua"
local arguments = { ... }
local action = arguments[1] or "list"
local unpack = table.unpack or unpack

assert(type(fs) == "table" and type(multishell) == "table",
  "systemdck requires an advanced CC:Tweaked computer")

local function serviceName(name)
  assert(type(name) == "string" and name:match("^[%w][%w_.-]*$"),
    "invalid service name")
  return name
end

local function unitPath(name) return UNIT_DIR .. "/" .. serviceName(name) .. ".lua" end
local function statePath(name) return STATE_DIR .. "/" .. serviceName(name) .. ".lua" end

local function loadUnit(name)
  local unit, reason = config.load(unitPath(name))
  assert(unit, "could not load service " .. name .. ": " .. tostring(reason))
  assert(type(unit.program) == "string", "service " .. name .. " has no program")
  unit.arguments = unit.arguments or {}
  return unit
end

local function loadState(name)
  return config.load(statePath(name)) or { state = "inactive" }
end

local function saveState(name, state)
  fs.makeDir(STATE_DIR)
  assert(config.save(state, statePath(name)))
end

local function ensureBoot()
  fs.makeDir("/startup")
  local file = assert(fs.open("/startup/10-systemdck.lua", "w"))
  file.write([[if multishell then
  shell.run("/ducknet/bin/systemdck.lua", "start-enabled")
else
  printError("systemdck requires an advanced computer")
end
]])
  file.close()
end

local function tabIsRunning(name, state)
  if not state.pid then return false end
  local ok, title = pcall(multishell.getTitle, state.pid)
  return ok and title == "[systemdck] " .. name
end

local function start(name, quiet)
  local unit = loadUnit(name)
  local state = loadState(name)
  if tabIsRunning(name, state) then
    if not quiet then io.write(name .. " is already running\n") end
    return true
  end
  saveState(name, { state = "starting", since = os.epoch and os.epoch("utc") or os.clock() })
  local environment = setmetatable({}, { __index = _ENV })
  environment._ENV = environment
  local pid = multishell.launch(environment, RUNNER, name)
  assert(pid, "could not launch service " .. name)
  multishell.setTitle(pid, "[systemdck] " .. name)
  state = loadState(name)
  state.pid, state.state = pid, "running"
  state.description = unit.description
  saveState(name, state)
  if not quiet then io.write("started " .. name .. "\n") end
  return true
end

local function stop(name, quiet)
  loadUnit(name)
  local state = loadState(name)
  if tabIsRunning(name, state) then
    os.queueEvent("systemdck_control", name, "stop")
    state.state = "stopping"
    saveState(name, state)
    if type(sleep) == "function" then sleep(0) end
  else
    saveState(name, {
      state = "inactive", description = state.description,
      stopped = os.epoch and os.epoch("utc") or os.clock()
    })
  end
  if not quiet then io.write("stopped " .. name .. "\n") end
  return true
end

local function unitNames()
  if not fs.exists(UNIT_DIR) then return {} end
  local names = {}
  for _, file in ipairs(fs.list(UNIT_DIR)) do
    local name = file:match("^(.-)%.lua$")
    if name then names[#names + 1] = name end
  end
  table.sort(names)
  return names
end

local function setEnabled(name, enabled)
  local unit = loadUnit(name)
  unit.enabled = enabled
  assert(config.save(unit, unitPath(name)))
  if enabled then ensureBoot() end
  io.write((enabled and "enabled " or "disabled ") .. name .. "\n")
end

if action == "start-enabled" then
  for _, name in ipairs(unitNames()) do
    local unit = loadUnit(name)
    if unit.enabled then
      local ok, reason = pcall(start, name, true)
      if not ok then printError("systemdck: " .. tostring(reason)) end
    end
  end
  return
end

if action == "list" then
  io.write(string.format("%-24s %-10s %-8s %s\n", "SERVICE", "STATE", "ENABLED", "DESCRIPTION"))
  for _, name in ipairs(unitNames()) do
    local unit, state = loadUnit(name), loadState(name)
    if state.state == "running" and not tabIsRunning(name, state) then state.state = "failed" end
    io.write(string.format("%-24s %-10s %-8s %s\n", name, state.state or "inactive",
      unit.enabled and "yes" or "no", unit.description or ""))
  end
  return
end

local name = serviceName(arguments[2])
if action == "start" then return start(name) end
if action == "stop" then return stop(name) end
if action == "restart" then
  local state = loadState(name)
  if tabIsRunning(name, state) then
    os.queueEvent("systemdck_control", name, "restart")
    state.state = "restarting"
    saveState(name, state)
    io.write("restarting " .. name .. "\n")
    return
  end
  return start(name)
end
if action == "status" then
  local unit, state = loadUnit(name), loadState(name)
  if state.state == "running" and not tabIsRunning(name, state) then state.state = "failed" end
  io.write(name .. " - " .. (unit.description or name) .. "\n")
  io.write("  State:   " .. tostring(state.state or "inactive") .. "\n")
  io.write("  Enabled: " .. (unit.enabled and "yes" or "no") .. "\n")
  if state.pid then io.write("  Task:    " .. tostring(state.pid) .. "\n") end
  if state.message then io.write("  Detail:  " .. tostring(state.message) .. "\n") end
  if state.restarts then io.write("  Restarts: " .. tostring(state.restarts) .. "\n") end
  return
end
if action == "enable" then setEnabled(name, true) return end
if action == "disable" then setEnabled(name, false) return end
if action == "create" then
  local program = arguments[3]
  assert(program, "usage: systemdck create <name> <program> [arguments...]")
  fs.makeDir(UNIT_DIR)
  local programArguments = {}
  for index = 4, #arguments do programArguments[#programArguments + 1] = arguments[index] end
  assert(config.save({ description = name, program = program, arguments = programArguments,
    enabled = true, restart = "always", restartDelay = 2 }, unitPath(name)))
  ensureBoot()
  io.write("created and enabled " .. name .. "\n")
  return
end
if action == "remove" then
  stop(name, true)
  if type(sleep) == "function" then sleep(0) end
  fs.delete(unitPath(name))
  if fs.exists(statePath(name)) then fs.delete(statePath(name)) end
  io.write("removed " .. name .. "\n")
  return
end

error("usage: systemdck list|status|start|stop|restart|enable|disable|create|remove [service]", 0)
