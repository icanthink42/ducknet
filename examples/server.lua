-- Run with: duckserve /usr/share/ducknet/server.lua
return function(app)
  app:use(function(request)
    io.write(request.method .. " " .. request.path .. "\n")
  end)

  app:get("/", function()
    return {
      status = 200,
      headers = { ["content-type"] = "application/x-ducknet-lua" },
      body = [[
local ui = require("ui")
ui.clear()
ui.write("Hello from DuckNet!")
ui.write("This Lua came from a DLTP server and is running in Niobium.")
]]
    }
  end)

  app:get("/hello/:name", function(request)
    return { status = 200, headers = {}, body = "Hello, " .. request.params.name }
  end)
end

