local codec = {}

local function encodeValue(value, seen)
  local kind = type(value)
  if kind == "nil" then return "z" end
  if kind == "boolean" then return value and "t" or "f" end
  if kind == "number" then
    assert(value == value and value ~= math.huge and value ~= -math.huge,
      "cannot encode non-finite number")
    local valueText = tostring(value)
    return "n" .. #valueText .. ":" .. valueText
  end
  if kind == "string" then return "s" .. #value .. ":" .. value end
  assert(kind == "table", "unsupported value type: " .. kind)
  assert(not seen[value], "cannot encode cyclic table")
  seen[value] = true

  local keys = {}
  for key in pairs(value) do
    assert(type(key) == "string" or type(key) == "number",
      "table keys must be strings or numbers")
    keys[#keys + 1] = key
  end
  table.sort(keys, function(a, b)
    local ta, tb = type(a), type(b)
    if ta == tb then return a < b end
    return ta < tb
  end)

  local out = { "m", tostring(#keys), ":" }
  for _, key in ipairs(keys) do
    out[#out + 1] = encodeValue(key, seen)
    out[#out + 1] = encodeValue(value[key], seen)
  end
  seen[value] = nil
  return table.concat(out)
end

function codec.encode(value)
  return encodeValue(value, {})
end

local function countAt(input, position)
  local colon = input:find(":", position, true)
  assert(colon, "invalid length")
  local text = input:sub(position, colon - 1)
  assert(text:match("^%d+$"), "invalid length")
  return tonumber(text), colon + 1
end

local function decodeValue(input, position, depth)
  assert(depth <= 64, "maximum nesting exceeded")
  local tag = input:sub(position, position)
  position = position + 1
  if tag == "z" then return nil, position end
  if tag == "t" then return true, position end
  if tag == "f" then return false, position end
  if tag == "s" or tag == "n" then
    local length
    length, position = countAt(input, position)
    assert(length <= #input - position + 1, "truncated value")
    local text = input:sub(position, position + length - 1)
    position = position + length
    if tag == "n" then
      local number = tonumber(text)
      assert(number, "invalid number")
      return number, position
    end
    return text, position
  end
  if tag == "m" then
    local count
    count, position = countAt(input, position)
    assert(count <= 65536, "table too large")
    local result = {}
    for _ = 1, count do
      local key, value
      key, position = decodeValue(input, position, depth + 1)
      assert(type(key) == "string" or type(key) == "number", "invalid map key")
      value, position = decodeValue(input, position, depth + 1)
      result[key] = value
    end
    return result, position
  end
  error("unknown codec tag")
end

function codec.decode(input)
  assert(type(input) == "string", "encoded input must be a string")
  local value, position = decodeValue(input, 1, 0)
  assert(position == #input + 1, "trailing encoded data")
  return value
end

return codec

