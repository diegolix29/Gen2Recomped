-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE SOOTOPOLIS CUTSCENE.
--
-- Reported from play: "Make sure the cutscene for groudon, kyogre and
-- rayquaza appears after going to the tower and making rayquaza flee and
-- returning to sootopolis ... It shows kyogre and groudon and then rayquaza
-- comes down from the sky".
--
-- WHAT WAS MISSING WAS ONE SPECIAL.  Sootopolis City's two scene scripts were
-- decoded end to end and every command in them lowers and every special they
-- call is implemented except gSpecials[470] = gSpecials[508],
-- Script_DoRayquazaScene -- which is not a script at all.  It takes over the
-- main callback and plays a full-screen cinematic, and this is that
-- cinematic.
--
-- WHAT COMES OFF THE CARTRIDGE (see RomExtractorGen3:extractRayquazaScene):
--
--   * the art.  Five screens' worth of background layers and sprite sheets,
--     composed from the tiles, tilemaps and palettes the scene's own five
--     loader functions bring in.  Groudon comes out 64x64 and Kyogre 32x16
--     because each sheet's frame size is read from the OAM of the sprite
--     template that names its tag.
--   * the ORDER.  The scene's advance step installs the next screen out of a
--     table at $62A6A0, and that table reads
--
--         clouds -> clouds -> storm -> chase -> descent -> light -> end
--
--     which is Groudon and Kyogre first and Rayquaza afterwards, exactly as
--     the report describes it.
--   * WHERE IT STARTS AND WHETHER IT STOPS.  Script_DoRayquazaScene passes
--     two arguments off gSpecialVar_0x8004: the index into that table, and
--     whether the advance exits instead of stepping.  The half the script
--     runs before the Sky Pillar opens on the first screen and stops there;
--     the half after it walks the whole table.
--
-- WHAT DOES NOT: HOW LONG EACH SCREEN HOLDS, and how the Pokemon move across
-- it.  Each step is its own C function counting its own frames, and none of
-- that is data.  So the hold below is this port's, one number for every
-- screen.  The scene plays the cartridge's pictures in the cartridge's order
-- for the cartridge's two halves; it does not claim to be frame-accurate
-- inside a screen.
--
-- WHERE THE PIECES SIT IS NOT A GUESS ANY MORE.  It was -- "the biggest sheet
-- in the middle" -- and that is not a layout, it is a coin toss that Groudon
-- won and Kyogre lost.  See COMPOSITION below: the duo fight and the descent
-- are now laid out at the cartridge's own CreateSprite coordinates.  The
-- take-off smoke and the chase-away finale are not, because their C functions
-- spread sprites from tables this port has not read yet, and those two
-- screens still fall back to the old single sheet.
local Assets = require("src.render.Assets")

local Gen3Cutscene = {}
Gen3Cutscene.__index = Gen3Cutscene

local GBA_W, GBA_H = 240, 160

-- the port's own numbers, and the only ones here that are
local HOLD = 150               -- frames a screen is up for
local FADE = 20                -- ...of which the first and last are a fade
local SPRITE_HOLD = 8          -- frames per frame of a Pokemon's animation

-- WHERE EACH PIECE GOES, AND WHICH PIECE IT IS.  READ OFF THE CARTRIDGE.
--
-- A Pokemon on these screens is not one sprite.  Groudon is two 64x64 halves
-- with a shoulder and a claw over them; Kyogre is NINE 32x16 tiles in a grid
-- plus two fins.  The hardware builds each out of OAM entries at fixed
-- coordinates and animates only some of them.  Drawing "the biggest sheet,
-- centred" -- which is what this did -- drew a chunk of Groudon and nothing
-- else, and Kyogre, whose tiles are eight times smaller, never appeared at
-- all.  On the finale it drew Groudon alone in the middle of the screen with
-- his legs off the bottom of his own frame.
--
-- EVERY NUMBER BELOW IS THE CARTRIDGE'S.  The scene's step table at $62A6A0
-- names six screens and a teardown; each step was disassembled and its
-- `bl CreateSprite` ($006DF4) calls read for the template pointer in r0 and
-- the x, y and subpriority in r1, r2, r3.  Each template's own OAM gives the
-- frame size and its anim table gives the image list -- as TILE offsets,
-- divided here by the frame's tile count, because a tile offset means nothing
-- to a quad.  Forty CreateSprite calls in the scene; they are all here.
--
--   * `x` and `y` are CreateSprite's arguments, which are the sprite's
--     CENTRE, not its corner -- the hardware adds centerToCornerVec itself.
--   * `sub` is the subpriority: LOWER IS NEARER, so the draw runs downward.
--   * `images` is the anim's own image list.  Groudon's body reads
--     FRAME(192), FRAME(256), FRAME(320), FRAME(256), and a 64x64 image is
--     64 tiles, so it is images 3, 4, 5, 4.
--   * `hold` is that anim's own frame count, which differs per part and
--     between the two halves of the duo fight: 30 frames before the Sky
--     Pillar, 20 after.
--   * `to` is NOT the cartridge's.  Three sprites are created off the top of
--     the screen and flown in by a sprite callback -- Rayquaza's descent at
--     (160, 0), and his head and tail in the finale at y -65 and -113.  A
--     callback is code, not data, so `to` is this port's own straight run;
--     without it those three hang off the edge where they were made.
--
-- Keyed by the screen and then by the sprite's TAG, which is what the
-- extractor records and what the cartridge keys its sheets by.
--
-- The duo fight is laid out TWICE because the cartridge lays it out twice:
-- steps 0 and 1 are the same art at coordinates ten pixels apart, holding 30
-- frames against 20.  The early half plays step 0 and stops; the half after
-- the Sky Pillar starts at step 1.
local COMPOSITION = {
  -- step 0: the duo fight, before the Sky Pillar
  cloudsPre = {
    [30505] = {
      { images = { 0, 1, 2, 1 }, hold = 30, x = 88, y = 72,  sub = 3 },
      { images = { 3, 4, 5, 4 }, hold = 30, x = 56, y = 104, sub = 3 },
    },
    [30506] = { { images = { 0 }, x = 75,  y = 101, sub = 0 } },
    [30507] = { { images = { 0 }, x = 109, y = 114, sub = 1 } },
    [30508] = {
      { images = { 0 }, x = 136, y = 96,  sub = 1 },
      { images = { 1 }, x = 168, y = 96,  sub = 1 },
      { images = { 2 }, x = 136, y = 112, sub = 1 },
      { images = { 3 }, x = 168, y = 112, sub = 1 },
      { images = { 4 }, x = 136, y = 128, sub = 1 },
      { images = { 5 }, x = 168, y = 128, sub = 1 },
      { images = { 6, 8, 10, 8 },    hold = 36, x = 104, y = 128, sub = 2 },
      { images = { 7, 9, 11, 9 },    hold = 36, x = 136, y = 128, sub = 2 },
      { images = { 12, 13, 14, 13 }, hold = 36, x = 184, y = 128, sub = 0 },
    },
    [30509] = { { images = { 0, 1, 2, 1 }, hold = 36, x = 208, y = 132, sub = 0 } },
    [30510] = { { images = { 0 }, x = 200, y = 120, sub = 1 } },
  },
  -- step 1: the same fight, after the Sky Pillar
  clouds = {
    [30505] = {
      { images = { 0, 1, 2, 1 }, hold = 20, x = 98, y = 72,  sub = 3 },
      { images = { 3, 4, 5, 4 }, hold = 20, x = 66, y = 104, sub = 3 },
    },
    [30506] = { { images = { 0 }, x = 85,  y = 101, sub = 0 } },
    [30507] = { { images = { 0 }, x = 119, y = 114, sub = 1 } },
    [30508] = {
      { images = { 0 }, x = 126, y = 96,  sub = 1 },
      { images = { 1 }, x = 158, y = 96,  sub = 1 },
      { images = { 2 }, x = 126, y = 112, sub = 1 },
      { images = { 3 }, x = 158, y = 112, sub = 1 },
      { images = { 4 }, x = 126, y = 128, sub = 1 },
      { images = { 5 }, x = 158, y = 128, sub = 1 },
      { images = { 6, 8, 10, 8 },    hold = 24, x = 94,  y = 128, sub = 2 },
      { images = { 7, 9, 11, 9 },    hold = 24, x = 126, y = 128, sub = 2 },
      { images = { 12, 13, 14, 13 }, hold = 24, x = 174, y = 128, sub = 0 },
    },
    [30509] = { { images = { 0, 1, 2, 1 }, hold = 24, x = 198, y = 132, sub = 0 } },
    [30510] = { { images = { 0 }, x = 190, y = 120, sub = 1 } },
  },
  -- step 2: the smoke Rayquaza leaves taking off.  The cartridge spreads
  -- several of these from a coordinate table scaled by four about (120, 80);
  -- that table is the one piece of this scene still unread, so one puff sits
  -- at its origin.
  storm = {
    [30555] = { { images = { 0 }, x = 120, y = 80, sub = 0 } },
  },
  -- step 3: the descent.  Tag 30557 is Rayquaza's TAIL -- the cartridge loads
  -- its sheet (record $0862AB04, 512 bytes) and the extractor's loader walk
  -- does not find it, so the entry below waits on a sheet the record does not
  -- carry yet and draws nothing until it does.
  chase = {
    [30556] = { { images = { 0, 1 }, hold = 32, x = 160, y = 0,
                  sub = 0, to = { x = 110, y = 108 } } },
    [30557] = { { images = { 0, 1 }, hold = 32, x = 184, y = -48,
                  sub = 0, to = { x = 134, y = 60 } } },
  },
  -- step 5: the finale.  Groudon bottom left with his tail, Kyogre in three
  -- tiles along the bottom right, Rayquaza down the middle from off the top,
  -- and a splash under each of the two that are leaving.
  light = {
    [30565] = { { images = { 0 }, x = 64, y = 120, sub = 0 } },
    [30566] = { { images = { 0 }, x = 16, y = 130, sub = 0 } },
    [30568] = {
      { images = { 0 }, x = 160, y = 128, sub = 1 },
      { images = { 1 }, x = 192, y = 128, sub = 1 },
      { images = { 2 }, x = 224, y = 128, sub = 1 },
    },
    [30569] = { { images = { 0 }, x = 120, y = -65,
                  sub = 0, to = { x = 120, y = 60 } } },
    [30570] = { { images = { 0 }, x = 120, y = -113,
                  sub = 0, to = { x = 120, y = 12 } } },
    [30571] = {
      { images = { 0, 1, 2, 3, 4, 5 }, hold = 8, x = 152, y = 132, sub = 0 },
      { images = { 0, 1, 2, 3, 4, 5 }, hold = 8, x = 224, y = 132, sub = 0 },
    },
  },
}

-- Which layout a screen gets.  The duo fight is the only screen that appears
-- twice, and the early half is always its first appearance.
function Gen3Cutscene:layoutFor(scene)
  local key = scene and scene.key
  if key == "clouds" and (tonumber(self.part) or 0) == 0 then key = "cloudsPre" end
  return COMPOSITION[key] or {}
end

function Gen3Cutscene:uiSize() return GBA_W, GBA_H end
function Gen3Cutscene:wantsFillScale() return true end
function Gen3Cutscene:isOpaque() return true end

function Gen3Cutscene.record(game)
  local constants = game and game.data and game.data.constants
  local record = constants and constants.gen3RayquazaScene
  if type(record) ~= "table" or type(record.scenes) ~= "table" then
    return nil
  end
  return record
end

-- The screens this half plays, in order.  `part` is the index the cartridge
-- starts at and `earlyStops` is how many steps the early half gets.
function Gen3Cutscene.steps(record, part)
  if not record then return {} end
  local byKey = {}
  for _, scene in ipairs(record.scenes) do byKey[scene.key] = scene end
  local order = record.order
  local out = {}
  if type(order) == "table" and #order > 0 then
    local from = math.max(1, (tonumber(part) or 0) + 1)
    for i = from, #order do
      local key = order[i]
      if key and byKey[key] then out[#out + 1] = byKey[key] end
    end
  else
    -- no order came off the cartridge: play what there is, once each, rather
    -- than nothing at all
    for _, scene in ipairs(record.scenes) do out[#out + 1] = scene end
  end
  -- ...and the early half stops after its first screen, which is what
  -- endEarly does to the advance
  local early = tonumber(record.earlyStops)
  if early and (tonumber(part) or 0) == 0 and #out > early then
    local cut = {}
    for i = 1, early do cut[i] = out[i] end
    out = cut
  end
  return out
end

function Gen3Cutscene.new(game, opts)
  local self = setmetatable({}, Gen3Cutscene)
  self.game = game
  self.onDone = opts and opts.onDone
  self.part = tonumber(opts and opts.part) or 0
  self.record = Gen3Cutscene.record(game)
  self.list = Gen3Cutscene.steps(self.record, self.part)
  self.index = 1
  self.frame = 0
  return self
end

function Gen3Cutscene:current() return self.list[self.index] end

function Gen3Cutscene:finish()
  if self.done then return end
  self.done = true
  if self.game and self.game.stack then
    pcall(self.game.stack.pop, self.game.stack)
  end
  if self.onDone then pcall(self.onDone) end
end

function Gen3Cutscene:update()
  if self.done then return end
  -- nothing to play is not a reason to sit on a black screen: the script
  -- behind this is waiting on it
  if not self:current() then return self:finish() end
  self.frame = self.frame + 1
  if self.frame >= HOLD then
    self.frame = 0
    self.index = self.index + 1
    if not self:current() then return self:finish() end
  end
  -- ...AND IT CAN ALWAYS BE LEFT.  The cartridge's cinematic is not
  -- skippable, but a cinematic this port got wrong and could not be left
  -- would strand the save at the one point in the story it cannot go round.
  local input = self.game and self.game.input
  if input and (input:wasPressed("b") or input:wasPressed("start")) then
    self:finish()
  end
end

-- How far through the current screen the fade is: nothing at the ends, full
-- in the middle.
function Gen3Cutscene:alpha()
  local f = self.frame
  if f < FADE then return f / FADE end
  if f > HOLD - FADE then return math.max(0, (HOLD - f) / FADE) end
  return 1
end

function Gen3Cutscene:draw()
  local g = love.graphics
  g.setColor(0, 0, 0, 1)
  g.rectangle("fill", 0, 0, GBA_W, GBA_H)
  local scene = self:current()
  if not scene then return end
  local alpha = self:alpha()

  -- the layers, back to front.  A higher BG number is further back on the
  -- hardware's usual ordering, and these scenes are built that way: the
  -- cloud tunnel's BG3 is the sky behind everything else it draws.
  local layers = {}
  for _, layer in ipairs(scene.layers or {}) do layers[#layers + 1] = layer end
  table.sort(layers, function(a, b) return (a.bg or 0) > (b.bg or 0) end)
  -- A LAYER IS A SCREEN BLOCK, AND A SCREEN BLOCK HAS AN ORIGIN.
  --
  -- Every one of these comes off the cartridge 256x256: that is the size of a
  -- GBA text background's tilemap, 32x32 tiles, and it has nothing to do with
  -- where the picture sits.  What the hardware shows is the 240x160 window at
  -- the background's own scroll, and each of these scenes is installed with
  -- that scroll at zero -- so the visible picture is the TOP-LEFT 240x160 of
  -- the block.
  --
  -- Centring it instead put the window at (-8, -48).  Forty-eight rows down
  -- the tilemap is past the end of the art and simply empty, so every screen
  -- came out shifted eight pixels sideways with a black band along the bottom
  -- -- which is exactly what the scene looked like in play: "the graphics
  -- arent correct ... not filling the screen".
  --
  -- Clipped, because a block is 256 wide and the screen is 240: without this
  -- the right-hand 16 columns of the tilemap -- the wrap the hardware never
  -- shows -- spill over whatever the frame draws next.
  g.setScissor(0, 0, GBA_W, GBA_H)
  for _, layer in ipairs(layers) do
    local ok, img = pcall(Assets.image, layer.image)
    if ok and img and img.getWidth then
      g.setColor(1, 1, 1, alpha)
      g.draw(img, 0, 0)
    end
  end
  g.setScissor()

  -- ...and the Pokemon on it, assembled out of their pieces.
  local layout = self:layoutFor(scene)
  local parts = {}
  for _, s in ipairs(scene.sprites or {}) do
    for _, place in ipairs(layout[s.tag] or {}) do
      parts[#parts + 1] = { sprite = s, place = place, seq = #parts }
    end
  end
  if #parts > 0 then
    -- back to front: subpriority counts DOWN towards the viewer, and
    -- table.sort is not stable, so ties fall back on creation order -- which
    -- is the order the cartridge's own CreateSprite calls run in.
    table.sort(parts, function(a, b)
      if a.place.sub ~= b.place.sub then return a.place.sub > b.place.sub end
      return a.seq < b.seq
    end)
    for _, part in ipairs(parts) do
      self:drawPart(part.sprite, part.place, alpha)
    end
  else
    -- A SCREEN WHOSE LAYOUT IS NOT IN THE TABLE still shows something.  The
    -- chase-away finale spreads Groudon, Kyogre and Rayquaza over the screen
    -- from a C function this port has not read, so until it does, that screen
    -- gets what it always got: the biggest sheet, in the middle.
    local biggest
    for _, s in ipairs(scene.sprites or {}) do
      local area = (s.width or 0) * (s.height or 0)
      if not biggest or area > (biggest.width or 0) * (biggest.height or 0) then
        biggest = s
      end
    end
    if biggest then
      self:drawPart(biggest, nil, alpha)
    end
  end
  g.setColor(1, 1, 1, 1)
end

-- One OAM entry's worth of a Pokemon.  `place` nil means the fallback: the
-- sheet's own animation, centred.
function Gen3Cutscene:drawPart(sprite, place, alpha)
  local g = love.graphics
  local ok, img = pcall(Assets.image, sprite.image)
  if not (ok and img and img.getWidth) then return end
  local w = sprite.width or img:getWidth()
  local h = sprite.height or img:getHeight()
  local frames = math.max(1, sprite.frames or 1)

  local index, x, y
  if place then
    local seq = place.images
    local step = math.floor(self.frame / (place.hold or SPRITE_HOLD)) % #seq
    index = seq[step + 1]
    -- a sheet that came out of the cartridge short must not read past its end
    if index >= frames then index = frames - 1 end
    local cx, cy = place.x, place.y
    if place.to then
      -- eased so the arrival settles rather than stopping dead
      local p = math.min(1, math.max(0, self.frame / HOLD))
      p = p * p * (3 - 2 * p)
      cx = cx + (place.to.x - cx) * p
      cy = cy + (place.to.y - cy) * p
    end
    x = math.floor(cx - w / 2)
    y = math.floor(cy - h / 2)
  else
    index = math.floor(self.frame / SPRITE_HOLD) % frames
    x = math.floor((GBA_W - w) / 2)
    y = math.floor((GBA_H - h) / 2)
  end

  self.quads = self.quads or {}
  local key = tostring(sprite.image) .. ":" .. index
  local quad = self.quads[key]
  if not quad then
    quad = g.newQuad(index * w, 0, w, h, img:getWidth(), img:getHeight())
    self.quads[key] = quad
  end
  g.setColor(1, 1, 1, alpha)
  g.draw(img, quad, x, y)
end

return Gen3Cutscene
