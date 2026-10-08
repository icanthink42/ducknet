-- A small end-to-end test site for DuckNet, DLTP, and Niobium.
return function(app)
  app:get("/", function()
    return {
      status = 200,
      headers = { ["content-type"] = "application/x-ducknet-lua" },
      body = [[
local ui = require("ui")
local net = require("net")

ui.clear()
ui.write("DuckNet Foo Bar Test")
ui.write("foo")

local response, reason = net.request("GET", "/bar")
if response then
  ui.write(response.body)
else
  ui.write("bar request failed: " .. tostring(reason))
end
]]
    }
  end)

  app:get("/bar", function()
    return {
      status = 200,
      headers = { ["content-type"] = "text/plain" },
      body = "bar"
    }
  end)

  app:get("/health", function()
    return {
      status = 200,
      headers = { ["content-type"] = "text/plain" },
      body = "foo bar ok"
    }
  end)
end

