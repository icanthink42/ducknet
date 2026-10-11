local root = (... and ... ~= "" and ...) or "."
package.path = root .. "/ducknet/lib/?.lua;" ..
  root .. "/ducknet/lib/?/init.lua;" .. package.path

local originalConfig, originalFs = package.loaded["ducknet.config"], _G.fs
local records = {
  ["/etc/ducknet/config.lua"] = { dns = { servers = {}, search = {} } }
}

local function copy(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for key, child in pairs(value) do result[copy(key)] = copy(child) end
  return result
end

package.loaded["ducknet.config"] = {
  load = function(path)
    local value = records[path or "/etc/ducknet/config.lua"]
    if not value then return nil, "missing" end
    return copy(value)
  end,
  save = function(value, path)
    records[path or "/etc/ducknet/config.lua"] = copy(value)
    return true
  end
}
_G.fs = {
  makeDir = function() end,
  exists = function(path) return records[path] ~= nil end
}

local function command(...)
  return assert(loadfile(root .. "/ducknet/bin/dnsctl.lua"))(...)
end

command("resolver", "add", "11.0.0.53")
assert(records["/etc/ducknet/config.lua"].dns.servers[1] == "11.0.0.53")
command("search", "add", "duck")
assert(records["/etc/ducknet/config.lua"].dns.search[1] == "duck")
command("root", "add", "1.0.0.53")
command("zone", "add", "duck")
command("record", "add", "duck", "@", "SOA", "ns.duck hostmaster.duck", "300")
command("record", "add", "duck", "@", "NS", "ns.duck", "300")
command("record", "add", "duck", "ns", "A", "10.0.0.53", "300")
command("record", "add", "duck", "tracker", "A", "10.0.0.10", "120")
command("record", "list", "duck")
command("server", "enable", "both")
local dns = records["/etc/ducknet/dns.lua"]
assert(dns.recursive and dns.roots[1] == "1.0.0.53")
assert(dns.zones[1].records[4].name == "tracker.duck")
local unit = records["/etc/systemdck/ducknet-dns.lua"]
assert(unit.enabled and unit.program == "/ducknet/bin/dnsd.lua")
command("record", "remove", "duck", "tracker", "A")
assert(#records["/etc/ducknet/dns.lua"].zones[1].records == 3)
command("server", "disable")
assert(not records["/etc/systemdck/ducknet-dns.lua"].enabled)

package.loaded["ducknet.config"], _G.fs = originalConfig, originalFs
io.write("all DNS command tests passed\n")
