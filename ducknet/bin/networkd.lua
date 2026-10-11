local arguments = { ... }
local configPath = arguments[1] or "/etc/ducknet/config.lua"
local client = "/ducknet/bin/dhclient.lua"
if type(fs) ~= "table" then client = "/usr/bin/dhclient.lua" end
local program, reason = loadfile(client)
assert(program, reason)
return program("daemon", configPath)
