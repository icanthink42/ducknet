local UI = {}
UI.__index = UI

function UI.new(gpu, term)
  return setmetatable({ gpu = gpu, term = term }, UI)
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

-- Sites receive this restricted facade, never the host objects themselves.
function UI:capability()
  local owner = self
  return {
    clear = function() return owner:clear() end,
    write = function(value) return owner:write(value) end,
    size = function() return owner:size() end
  }
end

return UI
