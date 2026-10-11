local UI = {}
UI.__index = UI

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

function UI.new(gpu, term, options)
  options = options or {}
  return setmetatable({
    gpu = gpu,
    term = term,
    reader = options.reader,
    pullEvent = options.pullEvent,
    lines = {},
    top = 1
  }, UI)
end

function UI:_canRender()
  return self.term and self.term.getSize and self.term.setCursorPos and
    self.term.clearLine and self.term.write
end

function UI:size()
  if self.gpu and self.gpu.getResolution then return self.gpu.getResolution() end
  if self.term and self.term.getSize then return self.term.getSize() end
  return 80, 25
end

function UI:_viewportHeight()
  local _, height = self:size()
  return math.max(1, height - 1)
end

function UI:_maximumTop()
  return math.max(1, #self.lines - self:_viewportHeight() + 1)
end

function UI:_render()
  if not self:_canRender() then return end
  local width, height = self:size()
  local viewport = self:_viewportHeight()
  self.top = clamp(self.top, 1, self:_maximumTop())
  for row = 1, viewport do
    self.term.setCursorPos(1, row)
    self.term.clearLine()
    local line = self.lines[self.top + row - 1]
    if line then self.term.write(line:sub(1, width)) end
  end
  self.term.setCursorPos(1, height)
  self.term.clearLine()
  self.term.write(("Niobium  Wheel/Arrows/PgUp/PgDn  Q quit"):sub(1, width))
  if self.term.setCursorBlink then self.term.setCursorBlink(false) end
end

function UI:clear()
  self.lines, self.top = {}, 1
  if self.term and self.term.clear then self.term.clear() end
  self:_render()
end

function UI:write(value)
  local text = tostring(value)
  for line in (text .. "\n"):gmatch("(.-)\n") do
    self.lines[#self.lines + 1] = line
  end
  self.top = self:_maximumTop()
  if self:_canRender() then self:_render() else io.write(text .. "\n") end
end

function UI:scroll(amount)
  self.top = clamp(self.top + amount, 1, self:_maximumTop())
  self:_render()
end

function UI:input(prompt)
  prompt = prompt and tostring(prompt) or ""
  local reader = self.reader or (type(read) == "function" and read) or io.read
  if not self:_canRender() then
    if prompt ~= "" then io.write(prompt) end
    local value = reader()
    return value == nil and "" or tostring(value)
  end

  self.lines[#self.lines + 1] = prompt
  self.top = self:_maximumTop()
  self:_render()
  local row = #self.lines - self.top + 1
  self.term.setCursorPos(math.min(#prompt + 1, select(1, self:size())), row)
  if self.term.setCursorBlink then self.term.setCursorBlink(true) end
  local value = reader()
  value = value == nil and "" or tostring(value)
  self.lines[#self.lines] = prompt .. value
  self.top = self:_maximumTop()
  self:_render()
  return value
end

function UI:browse()
  if not self:_canRender() then return end
  local pullEvent = self.pullEvent or (os and os.pullEvent)
  if type(pullEvent) ~= "function" then return end
  self:_render()
  while true do
    local event, first = pullEvent()
    if event == "mouse_scroll" then
      self:scroll(first)
    elseif event == "term_resize" then
      self:_render()
    elseif event == "char" and tostring(first):lower() == "q" then
      local _, height = self:size()
      self.term.setCursorPos(1, height)
      self.term.clearLine()
      if self.term.setCursorBlink then self.term.setCursorBlink(true) end
      return
    elseif event == "key" and type(keys) == "table" then
      if first == keys.up then self:scroll(-1)
      elseif first == keys.down then self:scroll(1)
      elseif first == keys.pageUp then self:scroll(-self:_viewportHeight())
      elseif first == keys.pageDown then self:scroll(self:_viewportHeight())
      elseif first == keys.home then self.top = 1 self:_render()
      elseif first == keys["end"] then self.top = self:_maximumTop() self:_render()
      end
    end
  end
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
