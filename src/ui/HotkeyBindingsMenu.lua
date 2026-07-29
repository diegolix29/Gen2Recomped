-- Rebinding over the "display hotkey" actions (COLORS/TILT/ZOOM/GBC FX +
-- zoom step): one row per action, A arms a "PRESS A BUTTON" capture and
-- the captured key or pad button lands in save.options.hotkeyBindings,
-- which Input:applyHotkeyBindings layers over its fixed default map (see
-- src/core/Input.lua and Game:applyOptions).
--
-- These are one-shot actions, not Game Boy buttons, so they get their own
-- save key and their own capture screen rather than sharing
-- BindingsMenu/save.options.bindings -- a rebind here can never shadow a
-- d-pad/A/B/Start/Select rebind, or vice versa. See Game:fireHotkey,
-- Game:keypressed and Game:gamepadpressed.

local Font = require("src.render.Font")
local ListMenu = require("src.ui.ListMenu")
local Input = require("src.core.Input")
local Strings = require("src.core.Strings")
local Theme = require("src.ui.Theme")

local HotkeyBindingsMenu = setmetatable({}, { __index = ListMenu })
HotkeyBindingsMenu.__index = HotkeyBindingsMenu

-- Mirrors Input.lua's DEFAULT_HOTKEY_KEY_BINDINGS, default key first;
-- no action ships with a default pad button (see DEFAULT_HOTKEY_PAD_BINDINGS),
-- so the pad column starts blank until the player captures one here.
local ACTIONS = {
  { id = "colors", label = "COLORS", key = "2" },
  { id = "tilt", label = "TILT", key = "3" },
  { id = "fastForward", label = "FAST FORWARD", key = "4" },
  { id = "gbcfx", label = "GBC FX", key = "5" },
  { id = "vortex", label = "VORTEX", key = "6" },
  { id = "zoomOut", label = "ZOOM OUT", key = "-" },
  { id = "zoomIn", label = "ZOOM IN", key = "=" },
  { id = "cameraRotateLeft", label = "CAM LEFT", key = "[" },
  { id = "cameraRotateRight", label = "CAM RIGHT", key = "]" },
  { id = "quit", label = "QUIT", key = "9" },
  { id = "softReset", label = "SOFT RESET", key = "0" },
  { id = "saveGame", label = "SAVE GAME", key = "f1" },
  { id = "loadGame", label = "LOAD GAME", key = "f2" },
  { id = "toggleModMenu", label = "TOGGLE MOD MENU", key = "f10" },
  { id = "reloadMods", label = "RELOAD MODS", key = "f5" },
}

-- a binding is a plain key string or { key, pad }; absent = the fixed
-- default above, so a vanilla save renders today's keys byte-identical
local function boundKey(overlay, def)
  local b = overlay and overlay[def.id]
  if type(b) == "table" then return b.key or def.key end
  if type(b) == "string" then return b end
  return def.key
end

local function boundPad(overlay, def)
  local b = overlay and overlay[def.id]
  if type(b) == "table" then return b.pad end
  return nil
end

-- Map internal button names to readable labels
local function padLabel(pad)
  if not pad then return nil end
  local labels = {
    stickup = "L-STICK UP",
    stickdown = "L-STICK DOWN",
    stickleft = "L-STICK LEFT",
    stickright = "L-STICK RIGHT",
    rightstickup = "R-STICK UP",
    rightstickdown = "R-STICK DOWN",
    rightstickleft = "R-STICK LEFT",
    rightstickright = "R-STICK RIGHT",
    lefttrigger = "L2",
    righttrigger = "R2",
  }
  return labels[pad] or pad
end

local function boundRight(overlay, def)
  local key = boundKey(overlay, def):upper()
  local pad = boundPad(overlay, def)
  if pad then return key .. "/" .. (padLabel(pad) or pad):upper() end
  return key
end

function HotkeyBindingsMenu.new(game)
  local overlay = game.save and game.save.options
                  and game.save.options.hotkeyBindings
  local items = {}
  for i, def in ipairs(ACTIONS) do
    items[i] = { label = Strings(def.label),
                 right = boundRight(overlay, def), action = def }
  end
  local self
  self = setmetatable(ListMenu.new(game, "HOTKEYS", items, {
    -- SELECT on a row is the only way to walk back a bad capture (there's
    -- no separate delete control on this screen) -- same opt-in ListMenu
    -- already uses for the fight-menu move reorder / bag item reorder.
    onSelectKey = function(item) self:resetItem(item) end,
    footer = Strings("SELECT: RESET TO DEFAULT"),
    rows = 4, -- Fewer rows since each item takes 2 lines
  }), HotkeyBindingsMenu)
  self.onChoose = function(item) self:beginCapture(item) end
  self.scroll = 0
  self.index = 1
  return self
end

-- same per-instance capture-slot pattern as BindingsMenu: while a capture
-- is armed, Game's raw-input routing hands keys/pad buttons straight here
-- instead of feeding them to Input as gameplay input.
function HotkeyBindingsMenu:beginCapture(item)
  self.capture = item
  self.onKeyPressed = HotkeyBindingsMenu.captureKey
  self.onGamepadPressed = HotkeyBindingsMenu.capturePad
  self.onGamepadAxis = HotkeyBindingsMenu.captureAxis
end

function HotkeyBindingsMenu:captureKey(key)
  self:storeBinding("key", key)
end

function HotkeyBindingsMenu:capturePad(button)
  self:storeBinding("pad", button)
end

function HotkeyBindingsMenu:captureAxis(axis, value)
  -- Map axis movements to bindable button names
  if axis == "leftx" then
    if value > 0.5 then
      self:storeBinding("pad", "stickright")
    elseif value < -0.5 then
      self:storeBinding("pad", "stickleft")
    end
  elseif axis == "lefty" then
    if value > 0.5 then
      self:storeBinding("pad", "stickdown")
    elseif value < -0.5 then
      self:storeBinding("pad", "stickup")
    end
  elseif axis == "rightx" then
    if value > 0.5 then
      self:storeBinding("pad", "rightstickright")
    elseif value < -0.5 then
      self:storeBinding("pad", "rightstickleft")
    end
  elseif axis == "righty" then
    if value > 0.5 then
      self:storeBinding("pad", "rightstickdown")
    elseif value < -0.5 then
      self:storeBinding("pad", "rightstickup")
    end
  elseif axis == "triggerleft" and value > 0.5 then
    self:storeBinding("pad", "lefttrigger")
  elseif axis == "triggerright" and value > 0.5 then
    self:storeBinding("pad", "righttrigger")
  end
end

-- Drops this action's whole overlay entry (both key and pad), so the row
-- falls back to DEFAULT_HOTKEY_KEY_BINDINGS / no pad -- the fix for a
-- capture that landed on the wrong button.
function HotkeyBindingsMenu:resetItem(item)
  local game = self.game
  local opts = game.save and game.save.options
  if not (opts and opts.hotkeyBindings) then return end
  opts.hotkeyBindings[item.action.id] = nil
  item.right = boundRight(opts.hotkeyBindings, item.action)
  Input:applyHotkeyBindings(opts.hotkeyBindings)
  if game.writeOptions then game:writeOptions() end
end

function HotkeyBindingsMenu:storeBinding(slot, value)
  local item = self.capture
  self.capture = nil
  self.onKeyPressed = nil
  self.onGamepadPressed = nil
  self.onGamepadAxis = nil
  local game = self.game
  if not (item and value and game.save and game.save.options) then return end
  local opts = game.save.options
  opts.hotkeyBindings = opts.hotkeyBindings or {}
  local b = opts.hotkeyBindings[item.action.id]
  if type(b) ~= "table" then
    -- keep a direct-edited plain key string when only the pad changes
    b = { key = type(b) == "string" and b or nil }
  end
  b[slot] = value
  opts.hotkeyBindings[item.action.id] = b
  item.right = boundRight(opts.hotkeyBindings, item.action)
  Input:applyHotkeyBindings(opts.hotkeyBindings)
  if game.writeOptions then game:writeOptions() end
end

function HotkeyBindingsMenu:update(dt)
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

function HotkeyBindingsMenu:draw()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(self.title, 8, 4)
  
  for row = 1, self.rows do
    local i = self.scroll + row
    local item = self.items[i]
    if not item then break end
    local y = 8 + row * 24 -- 24 pixels per item (2 lines + blank line)
    
    -- Draw label on first line
    Font.draw(item.label, 16, y)
    
    -- Draw key binding on second line, centered
    if item.right then
      Font.draw(item.right, 80, y + 8)
    end
    
    -- Draw cursor
    if i == self.index then
      Font.drawCode(Theme.cursor, 8, y)
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

return HotkeyBindingsMenu