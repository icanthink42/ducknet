local uninstallerPath = (...) or "uninstall.lua"
local originalFs, originalShell, originalRead, originalPull = _G.fs, _G.shell, io.read, os.pullEvent
local files = {
  ["/ducknet/lib/ducknet/codec.lua"] = "library",
  ["/ducknet/lib/ducknet.lua"] = "library",
  ["/ducknet/bin/ping.lua"] = "program",
  ["/ducknet/bin/serve.lua"] = "program",
  ["/ducknet/bin/uninstall-ducknet.lua"] = "program",
  ["/startup/00-ducknet-path.lua"] = "path startup",
  ["/startup/ducknet-server.lua"] = "startup",
  ["/etc/ducknet/config.lua"] = "config"
}
local shellPath = ".:/rom/programs:/ducknet/bin"

_G.fs = {
  exists = function(path)
    if files[path] then return true end
    local prefix = path:gsub("/+$", "") .. "/"
    for candidate in pairs(files) do
      if candidate:sub(1, #prefix) == prefix then return true end
    end
    return false
  end,
  delete = function(path)
    local prefix = path:gsub("/+$", "") .. "/"
    for candidate in pairs(files) do
      if candidate == path or candidate:sub(1, #prefix) == prefix then files[candidate] = nil end
    end
  end
}
_G.shell = {
  path = function() return shellPath end,
  setPath = function(value) shellPath = value end
}
os.pullEvent = function() end
io.read = function() return "n" end

assert(loadfile(uninstallerPath))()
assert(not files["/ducknet/lib/ducknet/codec.lua"] and not files["/ducknet/bin/ping.lua"])
assert(not files["/startup/ducknet-server.lua"])
assert(not files["/startup/00-ducknet-path.lua"])
assert(not shellPath:find("/ducknet/bin", 1, true))
assert(files["/etc/ducknet/config.lua"], "configuration should be preserved after 'no'")

_G.fs, _G.shell, io.read, os.pullEvent = originalFs, originalShell, originalRead, originalPull
io.write("all uninstaller tests passed\n")
