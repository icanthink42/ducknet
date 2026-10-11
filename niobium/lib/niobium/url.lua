local URL = {}

function URL.parse(value)
  assert(type(value) == "string", "invalid DuckNet URL")
  value = value:match("^%s*(.-)%s*$")
  assert(value ~= "", "invalid DuckNet URL")

  local scheme, remainder = value:match("^([%a][%w+.-]*)://(.+)$")
  if scheme then
    assert(scheme:lower() == "dltp", "unsupported URL scheme: " .. scheme)
    value = remainder
  end

  local host, path = value:match("^([^/]+)(/.*)$")
  if not host then host, path = value, "/" end
  assert(host ~= "" and not host:find(":", 1, true), "invalid DuckNet URL")
  return host, path
end

return URL
