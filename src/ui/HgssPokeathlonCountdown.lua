-- HEARTGOLD / SOULSILVER POKeATHLON: the 3-2-1 and the FINISH every event
-- shares (pokeheartgold asm/overlay_96.s ov96_021E61D8 / 021E637C /
-- 021E667C), drawn from `gen4_hgss_athlon_common`
-- (src/import/Gen4HgssPokeathlonCommonArt.lua).
--
-- READ FROM CODE (30 ticks a second, one `tick()` per logic tick):
--   * the sprite sits at x 128, y = the event's offset + 0x60 (021E61D8)
--   * the countdown (021E637C): SE 0x89A, then "3" at tick 0, "2" at 21, "1"
--     at 42 (SE 0x89D each), and at tick 64 SE 0x892 and the sprite hides --
--     the event starts
--   * the finish (021E667C): SE 0x899 and "FINISH" (seq 3) at offset + 0x48,
--     held 61 ticks; one tick for the record check (SE 0x898 and NEW RECORD!
--     at offset + 0x82 when the event's record was beaten -- `finish(true)`),
--     then 121 more ticks (0x78 + 1), record or not: about 183 in all
-- STAND-IN, said so: the event's own intro sprites the countdown waits for
-- first (021E62AC / 021E65D8, up to three) are not drawn; 667C's second
-- sprite (0x714) and its plane toggle / callback are not ported.
--
-- Use: local CD = require("src.ui.HgssPokeathlonCountdown")
--   self.cd = CD.new(game, yOffset)           -- yOffset as the event passes it
--   in the logic tick:   if not self.cd:countdown() then return end
--   at the end:          self.cd:startFinish(newRecord); then each tick
--                        if self.cd:finishing() then return end
--   in draw (the screen whose sprite-space y the offset is in): self.cd:draw(top)

local Assets = require("src.render.Assets")

local M = {}
M.__index = M

local function se(game, id)
  local ok, Sound = pcall(require, "src.core.Sound")
  if ok and Sound.playSe then pcall(Sound.playSe, game.data, id) end
end

function M.available(game)
  local d = game and game.data and game.data.gen4_hgss_athlon_common
  return type(d) == "table" and d.count_0_0 ~= nil
end

function M.new(game, yOffset)
  return setmetatable({ game = game, y0 = yOffset or 0, state = "count", t = 0, images = {}, started = false }, M)
end

-- one logic tick of the countdown; true once the event may start
function M:countdown()
  if self.state ~= "count" then return true end
  if not self.started then
    self.started = true
    se(self.game, 0x89A)
  end
  if self.t == 0 or self.t == 21 or self.t == 42 then se(self.game, 0x89D) end
  self.t = self.t + 1
  if self.t > 0x3F then
    se(self.game, 0x892)
    self.state, self.t = "play", 0
    return true
  end
  return false
end

function M:startFinish(newRecord)
  self.state, self.t, self.newRecord = "finish", 0, newRecord and true or false
  se(self.game, 0x899)
end

-- one logic tick of the finish; true while it is still on screen
function M:finishing()
  if self.state ~= "finish" then return false end
  self.t = self.t + 1
  if self.t == 61 and self.newRecord then se(self.game, 0x898) end
  if self.t > 182 then
    self.state = "done"
    return false
  end
  return true
end

function M:img(key)
  local rec = (self.game.data.gen4_hgss_athlon_common or {})[key]
  if type(rec) ~= "table" then return nil end
  if rec.image and not rec.path then
    if self.images[rec] == nil then
      self.images[rec] = love.graphics.newImage(rec.image)
      self.images[rec]:setFilter("nearest", "nearest")
    end
    return self.images[rec], rec
  end
  if self.images[rec.path] == nil then
    local ok, img = pcall(Assets.image, rec.path)
    self.images[rec.path] = ok and img or false
    if self.images[rec.path] then self.images[rec.path]:setFilter("nearest", "nearest") end
  end
  return self.images[rec.path] or nil, rec
end

function M:sprite(key, x, y)
  local img, rec = self:img(key)
  if not img then return false end
  love.graphics.draw(img, x + (tonumber(rec.originX) or 0), y + (tonumber(rec.originY) or 0))
  return true
end

-- the frame of set / seq `ticks` ticks in (the NANR's durations, held on
-- the last frame)
function M:frameAt(set, seq, ticks)
  local seqs = (((self.game.data.gen4_hgss_athlon_common or {}).objSeq or {})[set] or {})[seq] or {}
  local acc = 0
  for f, d in ipairs(seqs) do
    acc = acc + (tonumber(d) or 1)
    if ticks < acc then return f - 1 end
  end
  return math.max(0, #seqs - 1)
end

-- `top`: the sprite-space y the drawn screen starts at (0 for the screen the
-- event's offset is measured on)
function M:draw(top)
  top = top or 0
  love.graphics.setColor(1, 1, 1, 1)
  if self.state == "count" and self.started then
    local seq = self.t < 21 and 0 or (self.t < 42 and 1 or 2)
    local f = self:frameAt("count", seq, self.t - seq * 21)
    self:sprite(("count_%d_%d"):format(seq, f), 128, self.y0 + 0x60 - top)
  elseif self.state == "finish" then
    self:sprite(("count_3_%d"):format(self:frameAt("count", 3, self.t)), 128, self.y0 + 0x48 - top)
    if self.newRecord and self.t > 60 then
      self:sprite(("record_0_%d"):format(self:frameAt("record", 0, self.t - 61)), 128, self.y0 + 0x82 - top)
    end
  end
end

-- whether anything is on screen (an event can skip its own overlay)
function M:showing()
  return (self.state == "count" and self.started) or self.state == "finish"
end

return M
