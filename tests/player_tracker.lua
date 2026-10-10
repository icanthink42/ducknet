local root = (... and ... ~= "" and ...) or "."
package.path = root .. "/niobium/lib/?.lua;" ..
  root .. "/niobium/lib/?/init.lua;" .. package.path

local Sandbox = require("niobium.sandbox")
local originalPeripheral = _G.peripheral
local detector = {
  getOnlinePlayers = function() return { "Alex", "Steve" } end,
  getPlayer = function(username)
    if username ~= "Steve" then return nil end
    return {
      name = "Steve", uuid = "player-uuid", dimension = "minecraft:overworld",
      x = 12.5, y = 64, z = -8.25, yaw = 90, pitch = 10,
      health = 18, maxHealth = 20, airSupply = 300
    }
  end
}
_G.peripheral = {
  find = function(kind)
    if kind == "player_detector" then return detector end
  end
}

local routes = {}
local app = {
  get = function(_, pattern, handler) routes[pattern] = handler end
}
local configure = assert(loadfile(root .. "/sites/player-tracker.lua"))()
configure(app)

local home = routes["/"]({ params = {} })
assert(home.status == 200)
assert(home.headers["content-type"] == "application/x-ducknet-lua")
assert(home.body:find("ui.input", 1, true))

local online = routes["/api/online"]({ params = {} })
assert(online.status == 200)
assert(online.body == "Online players: Alex, Steve")

local found = routes["/api/player/:username"]({ params = { username = "Steve" } })
assert(found.status == 200)
assert(found.body:find("x: 12.5", 1, true))
assert(found.body:find("dimension: minecraft:overworld", 1, true))
assert(found.body:find("health: 18", 1, true))

local missing = routes["/api/player/:username"]({ params = { username = "Nobody" } })
assert(missing.status == 404)

-- Older Advanced Peripherals releases expose getPlayerPos instead.
detector = {
  getOnlinePlayers = function() return {} end,
  getPlayerPos = function() return { x = 1, y = 2, z = 3 } end
}
local legacy = routes["/api/player/:username"]({ params = { username = "Alex" } })
assert(legacy.status == 200 and legacy.body:find("z: 3", 1, true))

local inputs, output, requests = { "Steve", "" }, {}, {}
local ok, runtimeError = Sandbox.new():run(home.body, {
  ui = {
    clear = function() end,
    write = function(value) output[#output + 1] = tostring(value) end,
    input = function() return table.remove(inputs, 1) end
  },
  net = {
    request = function(method, path)
      requests[#requests + 1] = method .. " " .. path
      if path == "/api/online" then return { status = 200, body = "Online players: Steve" } end
      return { status = 200, body = "Player: Steve\nx: 12.5\ny: 64\nz: -8.25" }
    end
  }
}, "=player-tracker-page")
assert(ok, runtimeError)
assert(requests[2] == "GET /api/player/Steve")
assert(table.concat(output, "\n"):find("x: 12.5", 1, true))

_G.peripheral = originalPeripheral
io.write("all player tracker tests passed\n")
