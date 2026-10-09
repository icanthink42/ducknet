local uninstallerPath = (...) or "uninstall.lua"
local originalFs, originalRead, originalPull = _G.fs, io.read, os.pullEvent
local files = {
  ["/ducknet/codec.lua"] = "library",
  ["/ducknet.lua"] = "library",
  ["/ping.lua"] = "program",
  ["/serve.lua"] = "program",
  ["/uninstall-ducknet.lua"] = "program",
  ["/startup/ducknet-server.lua"] = "startup",
  ["/etc/ducknet/config.lua"] = "config"
}

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
os.pullEvent = function() end
io.read = function() return "n" end

assert(loadfile(uninstallerPath))()
assert(not files["/ducknet/codec.lua"] and not files["/ping.lua"])
assert(not files["/startup/ducknet-server.lua"])
assert(files["/etc/ducknet/config.lua"], "configuration should be preserved after 'no'")

_G.fs, io.read, os.pullEvent = originalFs, originalRead, originalPull
io.write("all uninstaller tests passed\n")
