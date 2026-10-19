-- src/ui/Gen5MusicalStage.lua -- the Musical's stage and its results
-- (overlays 131 / 132, sta_acting.c and kin).
--
-- Four performers in the lineup the event drew, the show's own song
-- (SEQ_BGM_MSL_01 .. 04 by show), and the appeals: a prop held in a hand is
-- shown off once (ov132 0x021F99F4 -- the prop's worth again, the louder
-- cheer, SE 0x62B, when it is worth 7 or more). The player appeals with A;
-- the others show theirs off on their own. When the song's time is up the
-- curtain falls and the ranking is read out with each one's points
-- (src/script/Gen5Musical.lua scores them).
--
-- Not the cartridge's: the choreography (each show's script, member 2 of
-- /a/1/1/x, which moves the performers and times the NPCs' appeals), the
-- 3D stage, the lights and the audience. The show runs a fixed 40 seconds.

local Font = require("src.render.Font")
local Art = require("src.ui.Gen5MusicalArt")

local Screen = {}
Screen.__index = Screen
Screen.isOpaque = true

local W, H = 256, 192
local SHOW_FRAMES = 40 * 60
local lg = love and love.graphics

function Screen:uiSize() return W, H end
function Screen:wantsFillScale() return true end
function Screen:wantsEdgeBleed() return false end

local function se(self, name) pcall(function() require("src.core.Sound").play(self.game.data, name) end) end

function Screen.new(game, opts)
  local self = setmetatable({}, Screen)
  self.game, self.prog, self.performers, self.onDone = game, opts.prog, opts.performers, opts.onDone
  self.t, self.state, self.pops = 0, "curtain", {}
  self.M = require("src.script.Gen5Musical")
  -- the NPCs' appeals, one per held prop, at random moments of the song
  self.plan = {}
  for i, pf in ipairs(self.performers or {}) do
    if not pf.player then
      for _, slot in ipairs({ 7, 8 }) do
        if pf.props[slot] then
          self.plan[#self.plan + 1] = { who = i, slot = slot,
            at = 300 + ((love and love.math and love.math.random(0, SHOW_FRAMES - 600)) or math.random(0, SHOW_FRAMES - 600)) }
        end
      end
    end
  end
  local song = opts.prog and opts.prog.show and opts.prog.show.song
  if song then pcall(function() require("src.core.Music").play(game.data, song) end) end
  return self
end

-- the saved Musical Photo: the player's Pokemon on the stage, still
function Screen.photo(game, photo)
  local self = setmetatable({}, Screen)
  self.game, self.state, self.t, self.pops = game, "photo", 0, {}
  local outfit = {}
  for slot, id in pairs(photo.outfit or {}) do outfit[slot] = { id = id } end
  self.performers = { { player = true, species = photo.species, props = outfit, used = {} } }
  self.photoRec = photo
  return self
end

function Screen:pressed(key)
  local input = self.game.input
  return input and input.wasPressed and input:wasPressed(key)
end

function Screen:finish()
  if self.state ~= "photo" then pcall(function() require("src.core.Music").restoreMap(self.game.data) end) end
  self.game.stack:pop()
  if self.onDone then self.onDone() end
end

function Screen:appeal(i, slot)
  local pf = self.performers[i]
  local v = self.M.appeal(self.game.data, self.prog, pf, slot)
  if v and v > 0 then
    self.pops[#self.pops + 1] = { who = i, text = "+" .. v, t = 0 }
    se(self, v >= 7 and "SEQ_SE_MSCL_10" or "SEQ_SE_MSCL_11")   -- 0x62B / 0x62C
  end
end

function Screen:update()
  self.t = self.t + 1
  for k = #self.pops, 1, -1 do
    local p = self.pops[k]
    p.t = p.t + 1
    if p.t > 60 then table.remove(self.pops, k) end
  end
  if self.state == "photo" then
    if self:pressed("a") or self:pressed("b") then self:finish() end
    return
  end
  if self.state == "curtain" then
    if self.t >= 90 then self.state, self.t = "show", 0 end
    return
  end
  if self.state == "show" then
    for _, a in ipairs(self.plan) do
      if not a.done and self.t >= a.at then a.done = true self:appeal(a.who, a.slot) end
    end
    if self:pressed("a") then
      for i, pf in ipairs(self.performers) do
        if pf.player then
          for _, slot in ipairs({ 7, 8 }) do
            if pf.props[slot] and not pf.used[slot] then self:appeal(i, slot) break end
          end
        end
      end
    end
    if self.t >= SHOW_FRAMES then
      self.state, self.t = "results", 0
      self.order = self.M.rank(self.performers)
      pcall(function() require("src.core.Music").stop() end)
    end
    return
  end
  if self.state == "results" then
    if self.t > 60 and (self:pressed("a") or self:pressed("b")) then self:finish() end
  end
end

local function title(self)
  local index = self.prog and self.prog.index or (self.photoRec and self.photoRec.show) or 0
  local s = self.game.data.text and self.game.data.text[("TEXT_B%04d_%05d"):format(286, 29 + index)]
  return s or "Musical"
end

local function speciesName(data, sp)
  local def = data.pokemon and data.pokemon[sp]
  return def and def.name or ("#" .. tostring(sp))
end

function Screen:drawStage()
  -- the hall, the curtains, the boards
  lg.setColor(0.12, 0.05, 0.12)
  lg.rectangle("fill", 0, 0, W, H)
  lg.setColor(0.55, 0.08, 0.15)
  local open = (self.state == "curtain") and math.min(1, self.t / 90) or 1
  local cw = 128 * (1 - open) + 18
  lg.rectangle("fill", 0, 0, cw, 150)
  lg.rectangle("fill", W - cw, 0, cw, 150)
  lg.setColor(0.45, 0.28, 0.16)
  lg.rectangle("fill", 0, 140, W, 52)
  lg.setColor(1, 1, 0.8, 0.12)
  lg.polygon("fill", 128, 0, 40, 150, 216, 150)
end

function Screen:draw()
  if not lg then return end
  local data = self.game.data
  lg.push("all")
  self:drawStage()
  local n = #self.performers
  for i, pf in ipairs(self.performers) do
    local x = (n == 1) and 128 or (32 + (i - 1) * 64)
    local bob = (self.state == "show") and math.floor(math.sin((self.t + i * 13) / 9) * 2) or 0
    lg.setColor(1, 1, 1)
    Art.drawMon(data, pf.species, pf.props, x, 146 + bob, n == 1 and 1 or 0.62)
    for _, p in ipairs(self.pops) do
      if p.who == i then
        lg.setColor(1, 0.9, 0.3)
        Font.draw(p.text, x - 8, 60 - p.t / 3)
      end
    end
  end
  lg.setColor(1, 1, 1)
  Font.draw(title(self), 6, 4)
  if self.state == "show" then
    local left = math.max(0, math.ceil((SHOW_FRAMES - self.t) / 60))
    Font.draw(tostring(left), W - 22, 4)
  elseif self.state == "results" then
    lg.setColor(0, 0, 0, 0.7)
    lg.rectangle("fill", 24, 30, 208, 108, 6, 6)
    lg.setColor(1, 1, 1)
    for k, i in ipairs(self.order or {}) do
      local pf = self.performers[i]
      local mark = pf.player and "*" or " "
      Font.draw(("%d %s%s"):format(k, mark, speciesName(data, pf.species)), 34, 38 + (k - 1) * 22)
      Font.draw(tostring(self.M.total(pf)), 196, 38 + (k - 1) * 22)
    end
  elseif self.state == "photo" then
    lg.setColor(1, 1, 1)
    Font.draw(tostring(self.photoRec and self.photoRec.score or ""), W - 30, 4)
  end
  lg.pop()
end

return Screen
