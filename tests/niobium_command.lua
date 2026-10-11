local root = (... and ... ~= "" and ...) or "."
package.path = root .. "/ducknet/lib/?.lua;" .. root .. "/ducknet/lib/?/init.lua;" ..
  root .. "/niobium/lib/?.lua;" .. root .. "/niobium/lib/?/init.lua;" .. package.path

local names = { "ducknet.config", "ducknet", "niobium.sandbox", "niobium.ui" }
local saved = {}
for _, name in ipairs(names) do saved[name] = package.loaded[name] end

local requests, configPaths, rendered = {}, {}, {}
package.loaded["ducknet.config"] = {
  load = function(path)
    configPaths[#configPaths + 1] = path or false
    return {}
  end
}
package.loaded["ducknet"] = {
  stack = function()
    return { resolve = function(_, host) return host end,
      dltp = { request = function(_, host, method, path, options)
      requests[#requests + 1] = {
        host = host, method = method, path = path, options = options
      }
      return { status = 200, body = "return true" }
    end } }
  end
}
package.loaded["niobium.sandbox"] = {
  new = function()
    return { run = function(_, body, capabilities, chunkName)
      rendered[#rendered + 1] = { body, capabilities, chunkName }
      return true
    end }
  end
}
package.loaded["niobium.ui"] = {
  new = function()
    return { capability = function() return {} end }
  end
}

local output, reads = {}, 0
local environment = setmetatable({
  peripheral = {},
  term = {},
  io = {
    write = function(value) output[#output + 1] = value end,
    read = function() reads = reads + 1 return "dltp://10.0.0.2" end
  }
}, { __index = _G })
environment._G = environment

local function run(...)
  local program = assert(loadfile(root .. "/niobium/bin/niobium.lua", "t", environment))
  return program(...)
end

run()
assert(reads == 1)
assert(table.concat(output) == "DuckNet URL: ")
assert(requests[1].host == "10.0.0.2" and requests[1].path == "/")
assert(requests[1].options.headers.host == "10.0.0.2")
assert(rendered[1][3] == "=dltp://10.0.0.2")

run("10.0.0.3/site", "/custom.lua")
assert(reads == 1, "URL argument unexpectedly prompted for input")
assert(requests[2].host == "10.0.0.3" and requests[2].path == "/site")
assert(configPaths[2] == "/custom.lua")

for _, name in ipairs(names) do package.loaded[name] = saved[name] end
io.write("all Niobium command tests passed\n")
