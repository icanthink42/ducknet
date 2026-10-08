local installerPath = (...) or "dist/ducknet-installer.lua"

local original = {
  fs = _G.fs, http = _G.http, peripheral = _G.peripheral,
  read = io.read, pullEvent = os.pullEvent
}

local function runProfile(profile, answers)
  local files, requests = {}, 0
  _G.fs = {
    exists = function(path) return files[path] ~= nil end,
    makeDir = function() end,
    delete = function(path) files[path] = nil end,
    move = function(source, destination)
      files[destination], files[source] = files[source], nil
    end,
    open = function(path, mode)
      if mode == "rb" then
        assert(files[path], "missing mocked file " .. path)
        return { readAll = function() return files[path] end, close = function() end }
      end
      local chunks = {}
      return {
        write = function(value) chunks[#chunks + 1] = value end,
        close = function() files[path] = table.concat(chunks) end
      }
    end
  }
  _G.http = {
    get = function()
      requests = requests + 1
      return nil, "unexpected HTTP request"
    end
  }
  os.pullEvent = function() end
  io.read = function()
    local answer = table.remove(answers, 1)
    assert(answer ~= nil, "installer asked an unexpected question for " .. profile)
    return answer
  end

  assert(loadfile(installerPath))()
  assert(#answers == 0, "installer did not ask every expected question for " .. profile)
  assert(requests == 0, "bundled " .. profile .. " install made an HTTP request")
  assert(files["/etc/ducknet/config.lua"], profile .. " did not write a config")
  return files
end

local client = runProfile("client", { "", "client", "", "", "", "", "", "" })
assert(client["/niobium.lua"], "client did not install Niobium")
assert(not client["/duckserve.lua"], "client unexpectedly installed server")

local router = runProfile("router", { "", "router", "", "", "", "", "", "" })
assert(router["/duck-router.lua"], "router runtime was not installed")
assert(router["/etc/ducknet/config.lua"]:find("forwarding = true", 1, true))

local server = runProfile("server", { "", "server", "", "", "", "", "", "", "1" })
assert(server["/duckserve.lua"], "server runtime was not installed")
assert(server["/etc/ducknet/site.lua"]:find("DuckNet Foo Bar Test", 1, true))

_G.fs, _G.http, _G.peripheral = original.fs, original.http, original.peripheral
io.read, os.pullEvent = original.read, original.pullEvent
io.write("all installer profile tests passed\n")

