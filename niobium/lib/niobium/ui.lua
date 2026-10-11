local UI = {}
UI.__index = UI

function UI.new(gpu, term, options)
  options = options or {}
  return setmetatable({ gpu = gpu, term = term, reader = options.reader }, UI)
end

function UI:clear()
  if self.term and self.term.clear then
    self.term.clear()
    if self.term.setCursorPos then self.term.setCursorPos(1, 1) end
  end
end

function UI:write(value)
  io.write(tostring(value) .. "\n")
end

function UI:size()
  if self.gpu and self.gpu.getResolution then return self.gpu.getResolution() end
  if self.term and self.term.getSize then return self.term.getSize() end
  return 80, 25
end

function UI:input(prompt)
  if prompt and prompt ~= "" then io.write(tostring(prompt)) end
  local reader = self.reader or (type(read) == "function" and read) or io.read
  local value = reader()
  return value == nil and "" or tostring(value)
end

-- Sites receive this restricted facade, never the host objects themselves.
function UI:capability()
  local owner = self
  return {
    clear = function() return owner:clear() end,
    write = function(value) return owner:write(value) end,
    size = function() return owner:size() end,
    input = function(prompt) return owner:input(prompt) end
  }
end

return UI
