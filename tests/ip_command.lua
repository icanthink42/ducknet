local root = (... and ... ~= "" and ...) or "."
package.path = root .. "/ducknet/lib/?.lua;" ..
  root .. "/ducknet/lib/?/init.lua;" .. package.path

local config = require("ducknet.config")
local path = os.tmpname()
os.remove(path)

local settings = {
  link = { broadcastUnknown = false, peers = {} },
  interfaces = {
    { name = "net10", modem = "left", address = "10.0.0.1",
      network = "10.0.0.0/24", port = 4660 },
    { name = "net11", modem = "right", address = "11.0.0.1",
      network = "11.0.0.0/24", port = 4660 }
  },
  ip = { forwarding = true, ttl = 16 },
  routes = {}, tcp = {}, dltp = { port = 80 }
}
assert(config.save(settings, path))

local command = assert(loadfile(root .. "/ducknet/bin/ip.lua"))
command("interface", "add", "net12", "top", "12.34.56.78/20", "4662", path)
local updated = assert(config.load(path))
assert(#updated.interfaces == 3)
assert(updated.interfaces[3].name == "net12")
assert(updated.interfaces[3].address == "12.34.56.78")
assert(updated.interfaces[3].network == "12.34.48.0/20")
assert(updated.interfaces[3].port == 4662)

command("interface", "set", "net12", "back", "12.1.2.3/16", "4663", path)
updated = assert(config.load(path))
assert(updated.interfaces[3].modem == "back")
assert(updated.interfaces[3].network == "12.1.0.0/16")
assert(updated.interfaces[3].port == 4663)
command("route", "add", "13.2.1.0/16", "net12", "12.1.0.2", "50", path)
updated = assert(config.load(path))
assert(updated.routes[1].network == "13.2.0.0/16")
assert(updated.routes[1].interface == "net12")
assert(updated.routes[1].via == "12.1.0.2")
assert(updated.routes[1].metric == 50)
command("route", "list", path)
command("route", "remove", "13.2.0.0/16", "net12", path)

command("interface", "list", path)
command("interface", "remove", "net12", path)
updated = assert(config.load(path))
assert(#updated.interfaces == 2)

local hostPath = os.tmpname()
os.remove(hostPath)
assert(config.save({
  link = { port = 4660, peers = {} },
  ip = { address = "10.0.0.2", forwarding = false, ttl = 16 },
  routes = {
    { network = "10.0.0.0/24", metric = 10 },
    { network = "0.0.0.0/0", via = "10.0.0.1", metric = 100 }
  },
  tcp = {}, dltp = { port = 80 }
}, hostPath))
command("address", "set", "11.0.0.13/24", hostPath)
assert(not pcall(command, "gateway", "set", "10.0.0.1", hostPath),
  "accepted a default gateway outside the host subnet")
command("gateway", "set", "11.0.0.1", hostPath)
command("channel", "set", "4661", hostPath)
command("ttl", "set", "32", hostPath)
command("forwarding", "set", "off", hostPath)
command("dltp-port", "set", "8080", hostPath)
local host = assert(config.load(hostPath))
assert(host.ip.address == "11.0.0.13")
assert(host.ip.ttl == 32 and host.ip.forwarding == false)
assert(host.link.port == 4661)
assert(host.routes[1].network == "11.0.0.0/24")
assert(host.routes[2].via == "11.0.0.1")
assert(host.dltp.port == 8080)

assert(not path:match("^/etc/"))
os.remove(path)
os.remove(path .. ".ducknet-new")
os.remove(path .. ".ducknet-old")
os.remove(hostPath)
os.remove(hostPath .. ".ducknet-new")
os.remove(hostPath .. ".ducknet-old")
io.write("all ip command tests passed\n")
