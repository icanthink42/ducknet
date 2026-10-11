local ScrollTerm = {}
ScrollTerm.__index = ScrollTerm

local HEX = "0123456789abcdef"

local function colourCode(colour)
  for index = 0, 15 do
    if colour == 2 ^ index then return HEX:sub(index + 1, index + 1) end
  end
  error("invalid colour", 3)
end

local function replace(value, startAt, length, replacement)
  return value:sub(1, startAt - 1) .. replacement .. value:sub(startAt + length)
end

function ScrollTerm.new(parent, options)
  options = options or {}
  local width, height = parent.getSize()
  local self = setmetatable({
    parent = parent,
    width = width,
    height = height,
    limit = options.limit or 1000,
    history = {},
    screen = {},
    offset = 0,
    cursorX = 1,
    cursorY = 1,
    cursorBlink = false,
    textColour = parent.getTextColor and parent.getTextColor() or colors.white,
    backgroundColour = parent.getBackgroundColor and parent.getBackgroundColor() or colors.black
  }, ScrollTerm)
  for row = 1, height do self.screen[row] = self:_blank() end
  self.terminal = self:_terminal()
  return self
end

function ScrollTerm:_blank()
  return {
    text = (" "):rep(self.width),
    foreground = colourCode(self.textColour):rep(self.width),
    background = colourCode(self.backgroundColour):rep(self.width)
  }
end

function ScrollTerm:_remember(line)
  self.history[#self.history + 1] = line
  if #self.history > self.limit then table.remove(self.history, 1) end
end

function ScrollTerm:_redraw()
  local maximum = #self.history
  self.offset = math.max(0, math.min(maximum, self.offset))
  local first = #self.history + 1 - self.offset
  for row = 1, self.height do
    local index = first + row - 1
    local line = index <= #self.history and self.history[index] or
      self.screen[index - #self.history]
    line = line or self:_blank()
    self.parent.setCursorPos(1, row)
    self.parent.blit(line.text, line.foreground, line.background)
  end
  if self.offset == 0 then
    self.parent.setCursorPos(self.cursorX, self.cursorY)
    self.parent.setCursorBlink(self.cursorBlink)
  else
    self.parent.setCursorBlink(false)
  end
end

function ScrollTerm:_write(text, foreground, background)
  text = tostring(text)
  local source = math.max(1, 2 - self.cursorX)
  local target = math.max(1, self.cursorX)
  local length = math.min(#text - source + 1, self.width - target + 1)
  if self.cursorY >= 1 and self.cursorY <= self.height and length > 0 then
    local line = self.screen[self.cursorY]
    line.text = replace(line.text, target, length, text:sub(source, source + length - 1))
    line.foreground = replace(line.foreground, target, length,
      foreground:sub(source, source + length - 1))
    line.background = replace(line.background, target, length,
      background:sub(source, source + length - 1))
  end
  self.cursorX = self.cursorX + #text
  self:_redraw()
end

function ScrollTerm:view(amount)
  self.offset = math.max(0, math.min(#self.history, self.offset + amount))
  self:_redraw()
end

function ScrollTerm:follow()
  if self.offset ~= 0 then self.offset = 0 self:_redraw() end
end

function ScrollTerm:resize()
  local width, height = self.parent.getSize()
  if width == self.width and height == self.height then return end
  self.width = width
  local function fit(line)
    local missing = math.max(0, width - #line.text)
    line.text = line.text:sub(1, width) .. (" "):rep(missing)
    line.foreground = line.foreground:sub(1, width) ..
      colourCode(self.textColour):rep(missing)
    line.background = line.background:sub(1, width) ..
      colourCode(self.backgroundColour):rep(missing)
  end
  for _, line in ipairs(self.history) do fit(line) end
  for _, line in ipairs(self.screen) do fit(line) end
  while #self.screen > height do self:_remember(table.remove(self.screen, 1)) end
  self.height = height
  while #self.screen < height do self.screen[#self.screen + 1] = self:_blank() end
  self.cursorY = math.min(self.cursorY, height)
  self:_redraw()
end

function ScrollTerm:_terminal()
  local owner = self
  local terminal = {}

  terminal.write = function(text)
    text = tostring(text)
    owner:_write(text, colourCode(owner.textColour):rep(#text),
      colourCode(owner.backgroundColour):rep(#text))
  end
  terminal.blit = function(text, foreground, background)
    assert(#text == #foreground and #text == #background, "Arguments must be the same length")
    owner:_write(text, foreground, background)
  end
  terminal.clear = function()
    for row = 1, owner.height do owner:_remember(owner.screen[row]) end
    owner.screen = {}
    for row = 1, owner.height do owner.screen[row] = owner:_blank() end
    owner:_redraw()
  end
  terminal.clearLine = function()
    if owner.cursorY >= 1 and owner.cursorY <= owner.height then
      owner.screen[owner.cursorY] = owner:_blank()
    end
    owner:_redraw()
  end
  terminal.scroll = function(amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount > 0 then
      for _ = 1, math.min(amount, owner.height) do
        owner:_remember(table.remove(owner.screen, 1))
        owner.screen[#owner.screen + 1] = owner:_blank()
      end
    elseif amount < 0 then
      for _ = 1, math.min(-amount, owner.height) do
        table.remove(owner.screen)
        table.insert(owner.screen, 1, owner:_blank())
      end
    end
    owner:_redraw()
  end
  terminal.getCursorPos = function() return owner.cursorX, owner.cursorY end
  terminal.setCursorPos = function(x, y)
    owner.cursorX, owner.cursorY = math.floor(x), math.floor(y)
    owner:_redraw()
  end
  terminal.getCursorBlink = function() return owner.cursorBlink end
  terminal.setCursorBlink = function(value)
    owner.cursorBlink = value == true
    owner:_redraw()
  end
  terminal.getSize = function() return owner.width, owner.height end
  terminal.isColor = function() return owner.parent.isColor() end
  terminal.isColour = terminal.isColor
  terminal.getTextColor = function() return owner.textColour end
  terminal.getTextColour = terminal.getTextColor
  terminal.setTextColor = function(value) colourCode(value) owner.textColour = value end
  terminal.setTextColour = terminal.setTextColor
  terminal.getBackgroundColor = function() return owner.backgroundColour end
  terminal.getBackgroundColour = terminal.getBackgroundColor
  terminal.setBackgroundColor = function(value) colourCode(value) owner.backgroundColour = value end
  terminal.setBackgroundColour = terminal.setBackgroundColor
  terminal.setPaletteColor = function(...) return owner.parent.setPaletteColor(...) end
  terminal.setPaletteColour = terminal.setPaletteColor
  terminal.getPaletteColor = function(...) return owner.parent.getPaletteColor(...) end
  terminal.getPaletteColour = terminal.getPaletteColor
  terminal.nativePaletteColor = function(...) return owner.parent.nativePaletteColor(...) end
  terminal.nativePaletteColour = terminal.nativePaletteColor
  return terminal
end

return ScrollTerm
