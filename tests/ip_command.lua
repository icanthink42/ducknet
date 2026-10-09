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

command("interface", "list", path)
command("interface", "remove", "net12", path)
updated = assert(config.load(path))
assert(#updated.interfaces == 2)
assert(not path:match("^/etc/"))
os.remove(path)
os.remove(path .. ".ducknet-new")
os.remove(path .. ".ducknet-old")
io.write("all ip command tests passed\n")
