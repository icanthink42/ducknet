-- Interactive Niobium site backed by an Advanced Peripherals Player Detector.
local function response(status, body, contentType)
  return {
    status = status,
    headers = { ["content-type"] = contentType or "text/plain" },
    body = body or ""
  }
end

local function findDetector()
  if type(peripheral) ~= "table" or type(peripheral.find) ~= "function" then return nil end
  return peripheral.find("player_detector") or peripheral.find("playerDetector")
end

local function appendValue(lines, label, value, depth, seen)
  local kind = type(value)
  if kind == "string" or kind == "number" or kind == "boolean" then
    lines[#lines + 1] = label .. ": " .. tostring(value)
    return
  end
  if kind ~= "table" or depth >= 4 or seen[value] then return end
  seen[value] = true
  local keys = {}
  for key in pairs(value) do keys[#keys + 1] = key end
  table.sort(keys, function(left, right) return tostring(left) < tostring(right) end)
  for _, key in ipairs(keys) do
    local child = label == "" and tostring(key) or (label .. "." .. tostring(key))
    appendValue(lines, child, value[key], depth + 1, seen)
  end
  seen[value] = nil
end

local page = [=[
local ui = require("ui")
local net = require("net")

ui.clear()
ui.write("DuckNet Player Tracker")
ui.write("----------------------")
local online = net.request("GET", "/api/online")
if online then ui.write(online.body) end
ui.write("")

while true do
  local username = ui.input("Player username (blank to exit): ")
  if username == "" then break end
  if #username > 16 or not username:match("^[%w_]+$") then
    ui.write("Minecraft usernames may only contain letters, numbers, and underscores.")
  else
    local result, reason = net.request("GET", "/api/player/" .. username)
    ui.write("")
    if result then
      ui.write(result.body)
    else
      ui.write("Request failed: " .. tostring(reason))
    end
    ui.write("")
  end
end
]=]

return function(app)
  app:get("/", function()
    return response(200, page, "application/x-ducknet-lua")
  end)

  app:get("/api/online", function()
    local detector = findDetector()
    if not detector then return response(503, "Player Detector is not attached") end
    if type(detector.getOnlinePlayers) ~= "function" then
      return response(501, "This Player Detector cannot list online players")
    end
    local ok, players = pcall(detector.getOnlinePlayers)
    if not ok then return response(500, "Player Detector error: " .. tostring(players)) end
    if type(players) ~= "table" or #players == 0 then
      return response(200, "Online players: none")
    end
    local names = {}
    for _, player in ipairs(players) do
      names[#names + 1] = type(player) == "table" and
        tostring(player.name or player.username or player.uuid or "unknown") or tostring(player)
    end
    table.sort(names)
    return response(200, "Online players: " .. table.concat(names, ", "))
  end)

  app:get("/api/player/:username", function(request)
    local username = request.params.username or ""
    if #username == 0 or #username > 16 or not username:match("^[%w_]+$") then
      return response(400, "Invalid Minecraft username")
    end
    local detector = findDetector()
    if not detector then return response(503, "Player Detector is not attached") end
    local lookup = detector.getPlayer or detector.getPlayerPos
    if type(lookup) ~= "function" then
      return response(501, "Attached Player Detector has no player lookup method")
    end
    local ok, player = pcall(lookup, username)
    if not ok then return response(500, "Player Detector error: " .. tostring(player)) end
    if type(player) ~= "table" then
      return response(404, "Player not found: " .. username)
    end
    local lines = { "Player: " .. tostring(player.name or username) }
    appendValue(lines, "", player, 0, {})
    return response(200, table.concat(lines, "\n"))
  end)
end
