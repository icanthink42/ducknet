local arguments = { ... }
if not arguments[1] then io.stderr:write("usage: nslookup <name> [dns-server]\n") return end
local path = type(fs) == "table" and "/ducknet/bin/dig.lua" or "/usr/bin/dig.lua"
local program = assert(loadfile(path))
if arguments[2] then return program("@" .. arguments[2], arguments[1], "A") end
return program(arguments[1], "A")
