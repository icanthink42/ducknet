local installerPath = (...) or "dist/ducknet-installer.lua"

local original = {
  fs = _G.fs, http = _G.http, peripheral = _G.peripheral,
  shell = _G.shell, read = io.read, pullEvent = os.pullEvent
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
  local shellPath = ".:/rom/programs"
  _G.shell = {
    path = function() return shellPath end,
    setPath = function(value) shellPath = value end
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
  assert(files["/startup/00-ducknet-path.lua"], profile .. " did not install path setup")
  assert(shellPath:find("/ducknet/bin", 1, true), profile .. " did not update the current path")
  return files
end

local client = runProfile("client", { "", "client", "", "", "", "" })
assert(client["/ducknet/bin/niobium.lua"], "client did not install Niobium")
assert(client["/ducknet/bin/ip.lua"], "client did not install the ip command")
assert(client["/ducknet/bin/dhclient.lua"], "client did not install the DHCP client")
assert(client["/ducknet/bin/dhcpd.lua"], "client did not install DHCP administration")
assert(client["/ducknet/bin/ping.lua"], "client did not install normal command names")
assert(client["/ducknet/bin/ping.lua"]:find("/ducknet/lib/?.lua", 1, true),
  "CC command did not receive the DuckNet library path")
assert(not client["/duck-ping.lua"], "client retained a legacy command name")
assert(not client["/ducknet/bin/serve.lua"], "client unexpectedly installed server")
local clientConfig = assert(load(client["/etc/ducknet/config.lua"], "=client-config"))()
assert(clientConfig.ip.address == "0.0.0.0")
assert(clientConfig.link.modem == "left")
assert(clientConfig.dhcp.client.enabled)
assert(client["/startup/10-ducknet-dhcp.lua"], "client did not enable DHCP startup")

local router = runProfile("router", {
  "", "router", "home", "", "", "left", "11.0.0.0/24", "", "",
  "right", "10.255.0.0/30", ""
})
assert(router["/ducknet/bin/router.lua"], "router runtime was not installed")
assert(router["/etc/ducknet/config.lua"]:find("forwarding = true", 1, true))
local routerConfig = assert(load(router["/etc/ducknet/config.lua"], "=router-config"))()
assert(#routerConfig.interfaces == 2, "router did not configure two interfaces")
assert(routerConfig.router.kind == "home")
assert(routerConfig.interfaces[1].name == "lan")
assert(routerConfig.interfaces[1].address == "11.0.0.1")
assert(routerConfig.interfaces[1].network == "11.0.0.0/24")
assert(routerConfig.interfaces[1].modem == "left")
assert(routerConfig.interfaces[2].name == "global")
assert(routerConfig.interfaces[2].address == "10.255.0.2")
assert(routerConfig.interfaces[2].network == "10.255.0.0/30")
assert(routerConfig.interfaces[2].modem == "right")
assert(routerConfig.routes[1].network == "0.0.0.0/0")
assert(routerConfig.routes[1].via == "10.255.0.1")
assert(routerConfig.routes[1].interface == "global")
assert(routerConfig.dhcp.pools[1].interface == "lan")
assert(routerConfig.dhcp.pools[1].first == "11.0.0.100")
assert(routerConfig.dhcp.pools[1].last == "11.0.0.200")
assert(router["/startup/ducknet-router.lua"], "router startup was not installed")
assert(load(router["/startup/ducknet-router.lua"], "=router-startup"))
assert(router["/startup/ducknet-router.lua"]:find("/ducknet/bin/router.lua", 1, true))

local core = runProfile("router", {
  "", "router", "core", "", "", "left", "10.255.0.0/30", "first", "",
  "", "", "right", "10.255.0.4/30", "second", "", "11.0.0.0/24", "n"
})
local coreConfig = assert(load(core["/etc/ducknet/config.lua"], "=core-config"))()
assert(coreConfig.router.kind == "core")
assert(coreConfig.interfaces[1].address == "10.255.0.1")
assert(coreConfig.interfaces[2].address == "10.255.0.6")
assert(coreConfig.routes[1].network == "11.0.0.0/24")
assert(coreConfig.routes[1].via == "10.255.0.5")
assert(coreConfig.routes[1].interface == "link2")

local server = runProfile("server", { "", "server", "", "", "", "", "", "", "3" })
assert(server["/ducknet/bin/serve.lua"], "server runtime was not installed")
assert(server["/etc/ducknet/site.lua"]:find("DuckNet Player Tracker", 1, true))
assert(server["/ducknet/share/sites/foo-bar.lua"], "Foo Bar site was not bundled")
assert(server["/ducknet/share/sites/player-tracker.lua"], "Player Tracker site was not bundled")
assert(server["/startup/ducknet-server.lua"], "server startup was not installed")
assert(load(server["/startup/ducknet-server.lua"], "=server-startup"))
assert(server["/startup/ducknet-server.lua"]:find("/ducknet/bin/serve.lua", 1, true))

_G.fs, _G.http, _G.peripheral, _G.shell = original.fs, original.http,
  original.peripheral, original.shell
io.read, os.pullEvent = original.read, original.pullEvent
io.write("all installer profile tests passed\n")
