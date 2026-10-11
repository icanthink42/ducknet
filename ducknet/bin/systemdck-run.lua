local config = require("ducknet.config")

local name = ...
assert(type(name) == "string" and name:match("^[%w][%w_.-]*$"), "invalid service name")
local unitPath = "/etc/systemdck/" .. name .. ".lua"
local statePath = "/var/run/systemdck/" .. name .. ".lua"
local unpack = table.unpack or unpack
local restarts = 0

local function timestamp() return os.epoch and os.epoch("utc") or os.clock() end
local function save(state)
  fs.makeDir("/var/run/systemdck")
  state.restarts = restarts
  config.save(state, statePath)
end

while true do
  local unit, reason = config.load(unitPath)
  if not unit then save({ state = "failed", message = reason }) return end
  local current = config.load(statePath) or {}
  save({ state = "running", pid = current.pid, description = unit.description,
    since = timestamp() })
  local success, message, control
  parallel.waitForAny(function()
    local ok, result = pcall(shell.run, unit.program, unpack(unit.arguments or {}))
    success = ok and result ~= false
    message = success and "program exited" or tostring(ok and "program failed" or result)
  end, function()
    while true do
      local _, target, requested = os.pullEvent("systemdck_control")
      if target == name and (requested == "stop" or requested == "restart") then
        control = requested
        return
      end
    end
  end)
  if control == "stop" then
    save({ state = "inactive", description = unit.description,
      message = "stopped by user", stopped = timestamp() })
    return
  end
  if control == "restart" then
    restarts = restarts + 1
  else
    local restart = unit.restart == "always" or (unit.restart == "on-failure" and not success)
    if not restart then
      save({ state = success and "inactive" or "failed", description = unit.description,
        message = message, stopped = timestamp() })
      return
    end
    restarts = restarts + 1
  end
  save({ state = "restarting", pid = current.pid, description = unit.description,
    message = control == "restart" and "restart requested" or message, stopped = timestamp() })
  if control ~= "restart" then sleep(tonumber(unit.restartDelay) or 2) end
end
