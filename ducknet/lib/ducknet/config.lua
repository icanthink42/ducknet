local config = {}

function config.load(path)
  path = path or "/etc/ducknet/config.lua"
  local chunk, err = loadfile(path)
  if not chunk then return nil, err end
  local ok, value = pcall(chunk)
  if not ok then return nil, value end
  if type(value) ~= "table" then return nil, "config must return a table" end
  return value
end

return config

