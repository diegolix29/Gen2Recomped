-- Rebinding over the logical Game Boy buttons (gap C2's file-12 half,
-- 12-ui-extensibility 4.4): one row per button, A arms a "PRESS A BUTTON"
-- capture and the captured key or pad button lands in
-- save.options.bindings, which Input:applyBindings layers over its fixed
-- default map (see src/core/Input.lua and Game:applyOptions).

local Font = require("src.render.Font")
local ListMenu = require("src.ui.ListMenu")
local Input = require("src.core.Input")
local Strings = require("src.core.Strings")
local Theme = require("src.ui.Theme")

local BindingsMenu = setmetatable({}, { __index = ListMenu })
BindingsMenu.__index = BindingsMenu

-- Input.lua's map, primary key first where several keys share a button.
-- `pad` is the default SDL gamecontroller button (see Input.lua); shown
-- on the SELECT row so controller Back/View is discoverable (#73).
local BUTTONS = {
  { id = "up", label = "UP", key = "up", pad = "dpup" },
  { id = "down", label = "DOWN", key = "down", pad = "dpdown" },
  { id = "left", label = "LEFT", key = "left", pad = "dpleft" },
  { id = "right", label = "RIGHT", key = "right", pad = "dpright" },
  { id = "a", label = "A", key = "z", pad = "a" },
  { id = "b", label = "B", key = "x", pad = "b" },
  { id = "start", label = "START", key = "escape", pad = "start" },
  { id = "select", label = "SELECT", key = "tab", pad = "back" },
}

-- a binding is a plain key string or { key, pad }; absent = the fixed
-- map, so a vanilla save renders today's keys byte-identically
local function boundKey(overlay, def)
  local b = overlay and overlay[def.id]
  if type(b) == "table" then return b.key or def.key end
  if type(b) == "string" then return b end
  return def.key
end

local function boundPad(overlay, def)
  local b = overlay and overlay[def.id]
  if type(b) == "table" and b.pad then return b.pad end
  return def.pad
end

-- Key column for every row. Show both keyboard and gamepad bindings
-- separated by "/" so controller bindings are visible for all buttons
local function boundRight(overlay, def)
  local key = boundKey(overlay, def)
  local pad = boundPad(overlay, def)
  if pad then return (key .. "/" .. pad):upper() end
  return key:upper()
end

function BindingsMenu.new(game)
  local overlay = game.save and game.save.options
                  and game.save.options.bindings
  local items = {}
  for i, def in ipairs(BUTTONS) do
    -- translated here, not in ROWS: that table is built at require
    -- time, before Strings.load has a catalog to look in
    items[i] = { label = Strings(def.label),
                 right = boundRight(overlay, def), button = def }
  end
  local self = setmetatable(ListMenu.new(game, "CONTROLS", items, {
    rows = 4, -- Fewer rows since each item takes 2 lines like hotkeys
    footer = Strings("SELECT: RESET TO DEFAULT"),
    onSelectKey = function(item) self:resetItem(item) end,
  }), BindingsMenu)
  self.onChoose = function(item) self:beginCapture(item) end
  self.scroll = 0
  self.index = 1
  return self
end

-- the capture handlers are per-instance slots, so Game's raw-input
-- routing only ever sees this screen while a capture is armed
function BindingsMenu:beginCapture(item)
  self.capture = item
  self.onKeyPressed = BindingsMenu.captureKey
  self.onGamepadPressed = BindingsMenu.capturePad
end

function BindingsMenu:captureKey(key)
  self:storeBinding("key", key)
end

function BindingsMenu:capturePad(button)
  self:storeBinding("pad", button)
end

function BindingsMenu:storeBinding(slot, value)
  local item = self.capture
  self.capture = nil
  self.onKeyPressed = nil
  self.onGamepadPressed = nil
  local game = self.game
  if not (item and value and game.save and game.save.options) then return end
  local opts = game.save.options
  opts.bindings = opts.bindings or {}
  local b = opts.bindings[item.button.id]
  if type(b) ~= "table" then
    -- keep a direct-edited plain key string when only the pad changes
    b = { key = type(b) == "string" and b or nil }
  end
  b[slot] = value
  opts.bindings[item.button.id] = b
  item.right = boundRight(opts.bindings, item.button)
  Input:applyBindings(opts.bindings)
  if game.writeOptions then game:writeOptions() end
end

function BindingsMenu:update(dt)
  if self.capture then return end -- the raw capture owns the input
  ListMenu.update(self, dt)
  
  -- Handle scrolling to keep selected item visible
  local totalItems = #self.items
  local rows = self.rows or 4
  local maxScroll = math.max(0, totalItems - rows)
  
  if self.index < self.scroll + 1 then
    self.scroll = math.max(0, self.index - 1)
  elseif self.index > self.scroll + rows then
    self.scroll = math.min(maxScroll, self.index - rows)
  end
end

function BindingsMenu:resetItem(item)
  local game = self.game
  if not (item and game.save and game.save.options) then return end
  local opts = game.save.options
  opts.bindings = opts.bindings or {}
  opts.bindings[item.button.id] = nil
  item.right = boundRight(opts.bindings, item.button)
  Input:applyBindings(opts.bindings)
  if game.writeOptions then game:writeOptions() end
end

function BindingsMenu:draw()
  Font.draw(self.title, 8, 4)
  local baseY = 20
  local rows = self.rows or 4
  
  for row = 1, rows do
    local i = (self.scroll or 0) + row
    local item = self.items[i]
    local y = baseY + (row - 1) * 24 -- 24 pixels per item (2 lines + blank line)
    if item then
      Font.draw(item.label, 16, y)
      Font.draw(item.right, 80, y + 8) -- Centered position (x=80)
      if i == self.index then
        Font.drawCode(Theme.cursor, 8, y)
      end
    end
  end
  
  if self.footer then
    Font.draw(self.footer, 8, 136)
  end
  
  if self.capture then
    Font.drawBox(1, 6, 18, 4)
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw(Strings("PRESS A BUTTON"), 24, 60)
    love.graphics.setColor(1, 1, 1, 1)
  end
end

return BindingsMenu
