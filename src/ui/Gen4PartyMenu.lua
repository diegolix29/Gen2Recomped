-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Platinum's PARTY SCREEN -- the last of the four that were falling back to
-- Kanto's art.
--
-- WHERE THE SIX PANELS ARE, measured off `party/menu` rather than guessed.
-- The panels are drawn in one teal, striped every other row, so the stripes
-- give the bands away: on the left half they run 5..47, 53..95 and 101..143,
-- and on the right half 13..57, 61..107 and 109..151.  Two columns of three,
-- a pitch of 48 both sides, the right one starting eight pixels lower -- which
-- is the stagger Platinum's screen has.  The cursor art is 128 wide, which is
-- the third independent way of saying a column is half the screen.
--
-- WHAT THIS SCREEN DOES AND DOES NOT DO, said plainly because the alias in
-- `Screens.lua` is where it matters:
--
--   * THE FIELD PARTY MENU is this screen: the list, the cursor, SUMMARY and
--     SWITCH.
--   * EVERYTHING IN A BATTLE still goes to the Gen 3 screen, which already
--     answers SHIFT, forced switches and an item's target.  The alias does not
--     list `battle`, so those pushes are declined here and served there.
--   * SO DOES TM TEACHING and the Frontier's team order, for the same reason:
--     each needs words this cartridge's cache does not carry yet.
--   * GIVE/TAKE AN ITEM is not offered.  `BagMenu.giveItem` is published and
--     would serve it; what is missing is Platinum's own word for it, and a
--     menu entry in the engine's English on a screen that is otherwise the
--     cartridge's is the kind of seam this port does not leave.

local Font = require("src.render.Font")
local Logger = require("src.core.Logger")
local Strings = require("src.core.Strings")
local Theme = require("src.ui.Theme")

local Gen4PartyMenu = {}
Gen4PartyMenu.__index = Gen4PartyMenu
Gen4PartyMenu.isOpaque = true

local W, H = 256, 192

-- The six slots, in reading order, from the bands above.
local SLOT_W, SLOT_H = 128, 44
local SLOTS = {
  { x = 0,   y = 5 },   { x = 128, y = 13 },
  { x = 0,   y = 53 },  { x = 128, y = 61 },
  { x = 0,   y = 101 }, { x = 128, y = 109 },
}
-- The panels stop at 151, so CANCEL gets the strip under them.
local CANCEL = { x = 8, y = 160, w = 240, h = 24 }

local ICON_PERIOD = 0.32

function Gen4PartyMenu:uiSize() return W, H end
function Gen4PartyMenu:wantsFillScale() return true end
function Gen4PartyMenu:wantsEdgeBleed() return false end

function Gen4PartyMenu:sgbPalettes()
  local P = require("src.render.PaletteFX")
  return { P.trueColorZone(0, 0, math.ceil(W / 8) - 1, math.ceil(H / 8) - 1) }
end

function Gen4PartyMenu.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, Gen4PartyMenu)
  self.game = game
  self.onCancel = opts.onCancel
  self.onSwitch = opts.onSwitch
  self.pickOnly = opts.pickOnly
  self.forceSwitch = opts.forceSwitch
  self.keepOpen = opts.keepOpen
  self.index = 1
  self.t = 0
  self.cache = {}
  self.icons = {}
  self.art = ((game.data or {}).gen4_graphics or {}).screens or {}
  if not self.art["party/menu"] then
    Logger.warn("gen4 party: this cache carries no party screen art -- "
                .. "the panels will be drawn in the engine's own frame")
  end
  return self
end

function Gen4PartyMenu:img(key)
  local rec = self.art[key]
  local path = (type(rec) == "table" and rec.path) or rec
  if type(path) ~= "string" then return nil end
  if self.cache[path] == nil then
    local ok, img = pcall(require("src.render.Assets").image, path)
    self.cache[path] = ok and img or false
    if self.cache[path] then self.cache[path]:setFilter("nearest", "nearest") end
  end
  return self.cache[path] or nil
end

function Gen4PartyMenu:party() return self.game.save.party or {} end

-- Slots 1..#party, then CANCEL.
function Gen4PartyMenu:count() return #self:party() + 1 end

function Gen4PartyMenu:close()
  self.game.stack:pop()
  if self.onCancel then self.onCancel() end
end

-- Hand the pick back, popping first, which is the order every other picker in
-- this port uses: a caller that opens a message box would otherwise draw it
-- underneath this screen.
function Gen4PartyMenu:handOff(mon)
  if not self.keepOpen then self.game.stack:pop() end
  if self.onSwitch then self.onSwitch(mon, self) end
end

function Gen4PartyMenu:swapWith(slot)
  local party = self:party()
  local from = self.switchFrom
  self.switchFrom = nil
  if not from or from == slot then return end
  party[from], party[slot] = party[slot], party[from]
end

function Gen4PartyMenu:choose()
  if self.index > #self:party() then
    if self.switchFrom then self.switchFrom = nil return end
    if self.onSwitch and not (self.pickOnly or self.forceSwitch) then
      return self:handOff(nil)
    end
    return self:close()
  end
  local mon = self:party()[self.index]
  if not mon then return end

  -- A screen opened to PICK a member hands it back at once, the way the
  -- cartridge does when the previous Pokemon has fainted or an item is
  -- waiting on a target: there is nothing to choose between.
  if self.onSwitch and (self.pickOnly or self.forceSwitch) then
    return self:handOff(mon)
  end
  -- A second press while a slot is marked completes the swap.
  if self.switchFrom then return self:swapWith(self.index) end
  self.submenu = 1
end

function Gen4PartyMenu:runAction(action)
  local mon = self:party()[self.index]
  self.submenu = nil
  if action == "summary" and mon then
    require("src.ui.Screens").push(self.game, "SummaryMenu", mon)
  elseif action == "switch" then
    self.switchFrom = self.index
  end
end

Gen4PartyMenu.ACTIONS = { "summary", "switch", "cancel" }

function Gen4PartyMenu:actionLabel(action)
  if action == "summary" then return Strings("SUMMARY") end
  if action == "switch" then return Strings("SWITCH") end
  return Strings("CANCEL")
end

function Gen4PartyMenu:update(dt)
  self.t = (self.t or 0) + (dt or 1 / 60)
  local input = self.game.input
  if not input then return end

  if self.submenu then
    local n = #Gen4PartyMenu.ACTIONS
    if input:wasPressed("up") then
      self.submenu = (self.submenu - 2) % n + 1
    elseif input:wasPressed("down") then
      self.submenu = self.submenu % n + 1
    elseif input:wasPressed("a") then
      self:runAction(Gen4PartyMenu.ACTIONS[self.submenu])
    elseif input:wasPressed("b") then
      self.submenu = nil
    end
    return
  end

  local n = self:count()
  -- Two columns, so left and right step by one and up/down step by two --
  -- which is what the staggered panels read as.
  if input:wasPressed("up") then
    self.index = ((self.index - 3) % n) + 1
  elseif input:wasPressed("down") then
    self.index = ((self.index + 1) % n) + 1
  elseif input:wasPressed("left") or input:wasPressed("right") then
    self.index = (self.index % n) + 1
  elseif input:wasPressed("a") then
    self:choose()
  elseif input:wasPressed("b") or input:wasPressed("start") then
    if self.switchFrom then self.switchFrom = nil
    elseif self.onSwitch and not (self.pickOnly or self.forceSwitch) then
      self:handOff(nil)
    else
      self:close()
    end
  end
end

-- ------------------------------------------------------------------- draw --

function Gen4PartyMenu:iconFor(mon)
  local data = self.game and self.game.data
  if not (data and mon and mon.species) then return nil end
  local icons = data.icons
  local def = data.pokemon and data.pokemon[mon.species]
  local entry = (icons and icons.bySpecies and icons.bySpecies[mon.species])
                or (def and def.icon)
  local path, frameH
  if type(entry) == "table" then
    path, frameH = entry.image, tonumber(entry.frameHeight)
  elseif type(entry) == "string" then
    path = entry
  end
  if not path then return nil end
  frameH = frameH or tonumber(icons and icons.frameHeight) or 32
  if self.icons[path] == nil then
    local ok, img = pcall(require("src.render.Assets").image, path)
    self.icons[path] = ok and img or false
    if self.icons[path] then self.icons[path]:setFilter("nearest", "nearest") end
  end
  local img = self.icons[path] or nil
  if not img then return nil end
  return img, frameH
end

function Gen4PartyMenu:drawIcon(mon, x, y)
  local img, frameH = self:iconFor(mon)
  if not img then
    local ball = self:img("party/member_ball_00")
    if ball then love.graphics.draw(ball, x, y) end
    return
  end
  local iw, ih = img:getDimensions()
  frameH = math.min(frameH or ih, ih)
  local frames = math.max(1, math.floor(ih / frameH))
  local frame = frames > 1
    and (math.floor((self.t % (ICON_PERIOD * frames)) / ICON_PERIOD) % frames)
    or 0
  local quad = love.graphics.newQuad(0, frame * frameH, iw, frameH, iw, ih)
  love.graphics.draw(img, quad, x, y)
end

function Gen4PartyMenu:drawSlot(i, mon)
  local g = love.graphics
  local at = SLOTS[i]
  if not at then return end

  if i == self.index then
    local cursor = self:img("party/cursor_00")
    if cursor then
      g.setColor(1, 1, 1, 1)
      g.draw(cursor, at.x, at.y - 2)
    else
      Font.drawCode(Theme.cursor, at.x + 2, at.y + 14)
    end
  end
  if self.switchFrom == i then
    g.setColor(1, 0.9, 0.3, 0.35)
    g.rectangle("fill", at.x + 2, at.y, SLOT_W - 4, SLOT_H)
    g.setColor(1, 1, 1, 1)
  end

  self:drawIcon(mon, at.x + 4, at.y + 4)

  local name = tostring(mon.nickname or mon.name or "")
  if name == "" then
    local def = self.game.data.pokemon and self.game.data.pokemon[mon.species]
    name = (def and def.name) or tostring(mon.species)
  end
  Font.draw(Font.fit(name, SLOT_W - 44), at.x + 38, at.y + 4)
  Font.draw(("Lv%d"):format(tonumber(mon.level) or 1), at.x + 38, at.y + 18)

  local hp = tonumber(mon.hp) or 0
  local max = tonumber(mon.maxHp) or tonumber(mon.maxhp) or 0
  if max > 0 then
    local text = ("%d/%d"):format(hp, max)
    Font.draw(text, at.x + SLOT_W - Font.width(text) - 6, at.y + 18)
    local full = SLOT_W - 48
    local share = math.max(0, math.min(1, hp / max))
    g.setColor(0.10, 0.12, 0.16, 1)
    g.rectangle("fill", at.x + 38, at.y + 32, full, 4)
    if share > 0.5 then g.setColor(0.36, 0.85, 0.36, 1)
    elseif share > 0.2 then g.setColor(0.95, 0.82, 0.28, 1)
    else g.setColor(0.92, 0.32, 0.30, 1) end
    g.rectangle("fill", at.x + 38, at.y + 32, math.floor(full * share), 4)
    g.setColor(1, 1, 1, 1)
  end
end

function Gen4PartyMenu:draw()
  local g = love.graphics
  g.setColor(0.08, 0.09, 0.14, 1)
  g.rectangle("fill", 0, 0, W, H)
  g.setColor(1, 1, 1, 1)

  local back = self:img("party/menu")
  if back then g.draw(back, 0, 0) else Font.drawBox(0, 0, 32, 20) end

  local party = self:party()
  for i = 1, math.min(#party, #SLOTS) do
    self:drawSlot(i, party[i])
  end

  -- CANCEL, under the panels.
  Font.drawBox(math.floor(CANCEL.x / 8), math.floor(CANCEL.y / 8),
               math.floor(CANCEL.w / 8), math.floor(CANCEL.h / 8))
  local word = Strings("CANCEL")
  Font.draw(word, CANCEL.x + 12, CANCEL.y + 6)
  if self.index > #party then
    Font.drawCode(Theme.cursor, CANCEL.x + 2, CANCEL.y + 6)
  end

  if self.submenu then
    local n = #Gen4PartyMenu.ACTIONS
    local boxW, rowH = 80, 16
    local x, y = W - boxW - 8, H - (n * rowH) - 20
    Font.drawBox(math.floor(x / 8), math.floor(y / 8),
                 math.floor(boxW / 8), math.floor((n * rowH + 12) / 8))
    for i, action in ipairs(Gen4PartyMenu.ACTIONS) do
      local ry = y + 6 + (i - 1) * rowH
      if i == self.submenu then Font.drawCode(Theme.cursor, x + 4, ry) end
      Font.draw(self:actionLabel(action), x + 16, ry)
    end
  end
  g.setColor(1, 1, 1, 1)
end

return Gen4PartyMenu
