local config = require("ducknet.config")

local UNIT_DIR = "/etc/systemdck"
local STATE_DIR = "/var/run/systemdck"
local LOG_DIR = "/var/log/systemdck"
local WORKERS = 16
local arguments = { ... }
local action = arguments[1] or "list"
local unpack = table.unpack or unpack

assert(type(fs) == "table" and type(parallel) == "table",
  "systemdck requires CC:Tweaked")

local function timestamp()
  if os.epoch then return os.epoch("utc") end
  return math.floor(os.clock() * 1000)
end

local function serviceName(name)
  assert(type(name) == "string" and name:match("^[%w][%w_.-]*$"),
    "invalid service name")
  return name
end

local function unitPath(name) return UNIT_DIR .. "/" .. serviceName(name) .. ".lua" end
local function statePath(name) return STATE_DIR .. "/" .. serviceName(name) .. ".lua" end
local function logPath(name) return LOG_DIR .. "/" .. serviceName(name) .. ".log" end

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

local function ensureBoot()
  fs.makeDir("/startup")
  local file = assert(fs.open("/startup/zz-systemdck.lua", "w"))
  file.write([[shell.run("/ducknet/bin/systemdck.lua", "boot")
]])
  file.close()
  if fs.exists("/startup/10-systemdck.lua") then fs.delete("/startup/10-systemdck.lua") end
end

local function request(requested, name)
  local token = tostring(os.getComputerID and os.getComputerID() or 0) .. ":" ..
    tostring(timestamp()) .. ":" .. tostring(math.random(1, 2147483647))
  os.queueEvent("systemdck_request", token, requested, name)
  local timer = os.startTimer(2)
  while true do
    local event = { os.pullEvent() }
    if event[1] == "systemdck_response" and event[2] == token then
      if os.cancelTimer then os.cancelTimer(timer) end
      if not event[3] then error(event[4] or "service request failed", 0) end
      return event[4]
    end
    if event[1] == "timer" and event[2] == timer then
      error("systemdck supervisor is not running; reboot the computer", 0)
    end
  end
end

local function appendLog(name, text)
  fs.makeDir(LOG_DIR)
  local file = fs.open(logPath(name), "a")
  if not file then return end
  file.write(text)
  file.close()
end

local function serviceEnvironment(name)
  local function values(...)
    local result = {}
    for index = 1, select("#", ...) do result[index] = tostring(select(index, ...)) end
    return table.concat(result, "\t")
  end
  local function line(...) appendLog(name, values(...) .. "\n") end
  local serviceIO = setmetatable({}, { __index = io })
  serviceIO.write = function(...) appendLog(name, values(...)) end
  serviceIO.stdout = { write = function(_, ...) appendLog(name, values(...)) end }
  serviceIO.stderr = { write = function(_, ...) appendLog(name, values(...)) end }
  return {
    print = line,
    printError = function(...) appendLog(name, "ERROR: " .. values(...) .. "\n") end,
    write = function(value) appendLog(name, tostring(value)) end,
    io = serviceIO
  }
end

local function runSupervisor()
  fs.makeDir(STATE_DIR)
  fs.makeDir(LOG_DIR)
  local assignments, controls = {}, {}

  local function findWorker(name)
    for index = 1, WORKERS do
      if assignments[index] == name then return index end
    end
  end

  local function assign(name)
    if findWorker(name) then return true, name .. " is already running" end
    local ok, unit = pcall(loadUnit, name)
    if not ok then return false, unit end
    for index = 1, WORKERS do
      if not assignments[index] then
        assignments[index] = name
        controls[index] = nil
        saveState(name, { state = "starting", worker = index,
          description = unit.description, since = timestamp(), restarts = 0 })
        os.queueEvent("systemdck_dispatch", index)
        return true, "started " .. name
      end
    end
    return false, "no free systemdck workers"
  end

  for _, name in ipairs(unitNames()) do
    local unit = loadUnit(name)
    if unit.enabled then
      local ok, reason = assign(name)
      if not ok then appendLog("systemdck", tostring(reason) .. "\n") end
    else
      saveState(name, { state = "inactive", description = unit.description,
        message = "disabled", stopped = timestamp(), restarts = 0 })
    end
  end

  local function manager()
    while true do
      local _, token, requested, name = os.pullEvent("systemdck_request")
      local ok, message
      if type(name) ~= "string" or not name:match("^[%w][%w_.-]*$") then
        ok, message = false, "invalid service name"
      elseif requested == "start" then
        ok, message = assign(name)
      elseif requested == "stop" or requested == "restart" then
        local workerIndex = findWorker(name)
        if workerIndex then
          controls[workerIndex] = requested
          local state = loadState(name)
          state.state = requested == "stop" and "stopping" or "restarting"
          saveState(name, state)
          os.queueEvent("systemdck_control", workerIndex)
          ok, message = true, requested == "stop" and ("stopping " .. name) or
            ("restarting " .. name)
        elseif requested == "restart" then
          ok, message = assign(name)
        else
          ok, message = true, name .. " is already stopped"
        end
      else
        ok, message = false, "unknown supervisor request"
      end
      os.queueEvent("systemdck_response", token, ok, message)
    end
  end

  local function worker(index)
    while true do
      while not assignments[index] do
        local _, target = os.pullEvent("systemdck_dispatch")
        if target == index then break end
      end
      local name = assignments[index]
      if name then
        local restarts = loadState(name).restarts or 0
        while assignments[index] == name do
          local unit, unitError = config.load(unitPath(name))
          if not unit then
            saveState(name, { state = "failed", worker = index,
              message = tostring(unitError), stopped = timestamp(), restarts = restarts })
            break
          end
          local pending = controls[index]
          controls[index] = nil
          if pending == "stop" then
            saveState(name, { state = "inactive", description = unit.description,
              message = "stopped by user", stopped = timestamp(), restarts = restarts })
            break
          end
          saveState(name, { state = "running", worker = index,
            description = unit.description, since = timestamp(), restarts = restarts })
          appendLog(name, "[systemdck] starting at " .. tostring(timestamp()) .. "\n")
          local success, message, controlled
          parallel.waitForAny(function()
            local ok, result = pcall(os.run, serviceEnvironment(name), unit.program,
              unpack(unit.arguments or {}))
            success = ok and result ~= false
            message = success and "program exited" or tostring(ok and "program failed" or result)
          end, function()
            while true do
              local _, target = os.pullEvent("systemdck_control")
              if target == index then controlled = controls[index] controls[index] = nil return end
            end
          end)
          if controlled == "stop" then
            saveState(name, { state = "inactive", description = unit.description,
              message = "stopped by user", stopped = timestamp(), restarts = restarts })
            break
          end
          local restart = controlled == "restart" or unit.restart == "always" or
            (unit.restart == "on-failure" and not success)
          if not restart then
            saveState(name, { state = success and "inactive" or "failed",
              description = unit.description, message = message,
              stopped = timestamp(), restarts = restarts })
            break
          end
          restarts = restarts + 1
          saveState(name, { state = "restarting", worker = index,
            description = unit.description,
            message = controlled == "restart" and "restart requested" or message,
            stopped = timestamp(), restarts = restarts })
          if controlled ~= "restart" then
            local delay = tonumber(unit.restartDelay) or 2
            parallel.waitForAny(function() sleep(delay) end, function()
              while true do
                local _, target = os.pullEvent("systemdck_control")
                if target == index then return end
              end
            end)
          end
        end
        assignments[index], controls[index] = nil, nil
      end
    end
  end

  local function interactiveShell()
    while true do
      shell.run("shell")
      sleep(0)
    end
  end

  local tasks = { manager, interactiveShell }
  for index = 1, WORKERS do
    local workerIndex = index
    tasks[#tasks + 1] = function() worker(workerIndex) end
  end
  parallel.waitForAll(unpack(tasks))
end

if action == "boot" or action == "start-enabled" then return runSupervisor() end

if action == "list" then
  io.write(string.format("%-24s %-10s %-8s %s\n", "SERVICE", "STATE", "ENABLED", "DESCRIPTION"))
  for _, name in ipairs(unitNames()) do
    local unit, state = loadUnit(name), loadState(name)
    io.write(string.format("%-24s %-10s %-8s %s\n", name, state.state or "inactive",
      unit.enabled and "yes" or "no", unit.description or ""))
  end
  return
end

local name = serviceName(arguments[2])
if action == "start" or action == "stop" or action == "restart" then
  io.write(tostring(request(action, name)) .. "\n")
  return
end
if action == "status" then
  local unit, state = loadUnit(name), loadState(name)
  io.write(name .. " - " .. (unit.description or name) .. "\n")
  io.write("  State:    " .. tostring(state.state or "inactive") .. "\n")
  io.write("  Enabled:  " .. (unit.enabled and "yes" or "no") .. "\n")
  if state.worker then io.write("  Worker:   " .. tostring(state.worker) .. "\n") end
  if state.message then io.write("  Detail:   " .. tostring(state.message) .. "\n") end
  if state.restarts then io.write("  Restarts: " .. tostring(state.restarts) .. "\n") end
  io.write("  Log:      " .. logPath(name) .. "\n")
  return
end
if action == "logs" then
  local path = logPath(name)
  if not fs.exists(path) then io.write("No logs for " .. name .. "\n") return end
  local file = assert(fs.open(path, "r"))
  local body = file.readAll()
  file.close()
  io.write(body)
  return
end
if action == "enable" or action == "disable" then
  local unit = loadUnit(name)
  unit.enabled = action == "enable"
  assert(config.save(unit, unitPath(name)))
  if unit.enabled then ensureBoot() end
  io.write(action .. "d " .. name .. "\n")
  return
end
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
  local state = loadState(name)
  if state.state == "running" or state.state == "restarting" then request("stop", name) end
  fs.delete(unitPath(name))
  if fs.exists(statePath(name)) then fs.delete(statePath(name)) end
  io.write("removed " .. name .. "\n")
  return
end

error("usage: systemdck list|status|logs|start|stop|restart|enable|disable|create|remove [service]", 0)
