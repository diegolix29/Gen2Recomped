-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Emerald's attract movie: the wet leaves, then the bike ride.
--
-- WHY THIS IS NOT IntroMovie.  Gen 3 was booting straight to the title --
-- `boot.screens.splash = false` -- which silently dropped the STUDIO CARD,
-- and that card is not a Gen 1 asset: it is this port's own.  Sending Gen 3
-- to IntroMovie instead would have been the other mistake: everything after
-- the card in it is Kanto -- the shooting star, the Gengar and Nidorino
-- fight -- built out of a `field.intro` manifest a Gen 3 cache does not have
-- and should not inherit.  So the card is kept and the movie behind it is
-- Emerald's.
--
-- THE CLOCK IS THE CARTRIDGE'S, and that is the thing that changed this from
-- a slideshow into a film.  Emerald's intro is one task chain counting frames
-- from zero, and every beat in it is a comparison against that counter.  A
-- scanner walked the chain tracking registers and recorded every immediate
-- the counter is compared against -- some as `cmp rD,#imm`, the larger ones
-- built with `movs`+`lsls` and compared register to register -- and what came
-- back was: 76, 128, 251, 256, 368, 384, 560 in the first scene's handler;
-- 832 and 1007 in the one after it; 1026 where it hands over; and 1088, 1109,
-- 1168, 1214, 1224, 1394, 1398, 1576, 1856, 1946 in the ride.  Those are the
-- beats below, and they are why the film is 1946 frames rather than however
-- long a made-up per-scene timer said.
--
-- WHICH LAYERS COEXIST IS ALSO IN THE DATA.  Every layer records the VRAM
-- address it is decompressed to.  Layers that share one are the SAME
-- background at different moments -- the cartridge overwrites the slot -- so
-- they are a sequence; a layer with an address of its own is a background of
-- its own and is on screen the whole time.  Drawing all of them one at a
-- time, which is what this did, showed the standing layer as a scene in its
-- own right and then took it away again: the flashes.
--
-- THE OPENING SHOT is one sheet with FOUR tilemaps -- four backgrounds
-- stacked, which is how the leaves sit in front of the plants in front of the
-- hills -- and the scene pass, which pairs one sheet with one tilemap, could
-- not see it at all.  The import composes each layer on its own, index 0 left
-- transparent except on the backdrop.
--
-- AND THE CAST IS THE CARTRIDGE'S.  Four compressed sprite sheets carry the
-- ride -- the two riders' seven-frame pedal cycles, the bicycle, the Pokemon
-- -- and three more carry the opening shot: the water drops and their ripple
-- rings, the sparkles, and the winged silhouette the scene puts in the sky at
-- frame 832.  Their OAM shapes are a judgement (a sprite's shape lives in a
-- template no loader touches) corroborated by the composed picture: at any
-- other size those sheets are noise.
--
-- WHAT IS STILL RECONSTRUCTED is the geometry -- where a drop's leaf runs,
-- where the rider stands, how far the sparkles are apart.  The cartridge's
-- own answers to those live in sprite callbacks and coordinate tables this
-- pass does not read.  Every beat is derived; every position is not, and the
-- constants below say which is which.
--
-- ONE DELIBERATE DIFFERENCE.  At frame 128 the cartridge fades its own studio
-- logo in over the leaves and blends it out again at 272.  This port shows
-- ITS card in that slot, on the cartridge's own beats, over the cartridge's
-- own shot -- so the lettering frames in the drops sheet are extracted and
-- never drawn.
--
-- START, A or B skips it the way CheckForUserInterruption always has.

local Assets = require("src.render.Assets")
local Font = require("src.render.Font")
local Gen3Scene = require("src.render.Gen3Scene")
local Gen3Wide = require("src.ui.Gen3Wide")
local Music = require("src.core.Music")
local Strings = require("src.core.Strings")

local Gen3Intro = {}
Gen3Intro.__index = Gen3Intro
Gen3Intro.isOpaque = true

local GBA_W, GBA_H = 240, 160

-- DERIVED: the immediates the intro's own task chain compares its frame
-- counter against.  See the note at the top for how they were found.
local T_BIG_DROP       = 76      -- the first drop starts down the leaf
local T_LOGO_APPEAR    = 128     -- the studio card fades in over the shot
local T_LOGO_LETTERS   = 144     -- ...and is fully up
local T_BIG_DROP_FALLS = 251     -- it lets go
local T_LOGO_BLEND_OUT = 256     -- the card starts to go
local T_LOGO_GONE      = 272
local T_SMALL_DROP_1   = 368
local T_SMALL_DROP_2   = 384
local T_SPARKLES       = 560     -- sparkles, and the camera starts climbing
local T_FLYGON         = 832     -- the silhouette crosses the sky
-- 904 is the one beat the scan did not come back with -- it is built some
-- other way than the immediates around it.  It is where the climb stops.
local T_PAN_UP_END     = 904
local T_SCENE_1_END    = 1007
local T_SCENE_2        = 1026    -- the ride begins
local T_MANECTRIC      = 1088
local T_DRIFT_BACK     = 1109
local T_RUN_CIRCULAR   = 1168
local T_MOVE_FORWARD   = 1214
local T_TORCHIC        = 1224
local T_FLYGON_ENTER   = 1394
local T_MOVE_BACKWARD  = 1398
local T_HOLD_POSITION  = 1576
local T_TORCHIC_EXIT   = 1856
-- THE RIDE DOES NOT END AT 1946, AND THE PORT USED TO CUT THERE.
--
-- Reported from play: "Before the post cycle intro the player is supposed to
-- drive off screen and then the torchic is supposed to come back and run
-- across and then the post cycle intro begins".  It is all there, and the
-- task chain says so: 016D650 owns frames 1029..1946 and then hands over to
-- 016D7E8, which owns 122 MORE before 016DBAC -- the Poke Ball, the first
-- beat of act three -- is armed at 2069.  The port armed act three at 1946,
-- so those 122 frames were the tail it never played.
--
-- WHAT IS IN THEM, off the ride's own sprites (tools/gen3_intro_act3.py runs
-- the chain with the sprite engine on and records every live object):
--
--   1829..1862  Torchic turns and sprints RIGHT at four pixels a frame, from
--               x 205, and is off the right-hand edge by about 1842
--   1863..2069  it comes back on at x 335 and runs LEFT at two a frame --
--               the whole width of the screen, clearing the left edge around
--               2038
--
-- and the rider is long gone by then: his sprite travels left at one pixel a
-- frame and does not come back.  So the order the report gives is the
-- cartridge's order.
local T_TORCHIC_SPRINT = 1829    -- Torchic turns and runs out to the right
local T_TORCHIC_RETURN = 1863    -- ...and comes back on at the right
local TORCHIC_RETURN_X = 335     -- from here
local TORCHIC_RETURN_DX = -2     -- at this, a pixel every other frame doubled
local TORCHIC_SPRINT_DX = 4      -- and out at this
local T_RIDE_TAIL      = 1946    -- 016D650 hands over to 016D7E8
local RIDER_EXIT_DX    = -1      -- the rider's own pixels a frame, leftwards
local RIDER_EXIT_X     = -64     -- off the left edge, a rider's width past it
local T_SCENE_2_END    = 2068

-- ACT THREE, AND IT IS THE CARTRIDGE'S, MOTION INCLUDED.
--
-- The ride's handler (016D7E8) arms 016DBAC and the chain runs on for 893 more
-- frames before the title takes over: a Poke Ball, Groudon, Kyogre, a cloud
-- field closing over the screen and the same field parting again.  None of it
-- was played, and the scene pass could not have found it -- three of those are
-- AFFINE backgrounds, a map of one byte per cell over 256-colour tiles.
--
-- The movement is not reconstructed.  tools/gen3_intro_act3.py runs the
-- cartridge's own task code with a THUMB interpreter, stubbing everything but
-- SetBgAffine, SetGpuReg, the decompressors and Div, and records what the
-- hardware is handed every frame: an affine placement (a texture point pinned
-- to a screen point, one uniform scale, one angle) on the first three beats
-- and two scroll offsets on the last two.  893 frames compress to 269 runs of
-- constant step, and that table travels in the dataset.
--
-- So the ball really does turn once every 64 frames while its scale runs
-- 65536/n, Groudon really does slide in sixteen pixels a frame and then shake
-- by three every other frame, and the clouds really do close from +80 and -80.
-- and the Poke Ball is armed on the frame AFTER the ride's last, which is
-- 2069 -- 016D7E8 hands over to 016DBAC there
local T_ACT3 = T_SCENE_2_END + 1

local FADE_FRAMES = 20

-- RECONSTRUCTED geometry.  None of this is in the cartridge's tables; it is
-- built to sit on the beats above.
local RIDER_Y = 100             -- pret creates the rider at y=100
local RIDER_ENTER_X = GBA_W + 32 -- ...at DISPLAY_WIDTH + 32
local PEDAL_FRAMES = 5          -- frames per pedal pose
-- where the bicycle sits under the rider: the rider sheet's ink ends on row
-- 52 of 64 and the bicycle's on row 30 of 32, so they share a ground line at
-- this offset (see the note in drawRide)
local BIKE_DROP = 22
local RIDE_SPEED = 2.0          -- pixels of world per frame

-- WHICH WAY THE RIDE IS GOING, and it is not a choice: every sheet in this
-- scene faces LEFT.  The rider's four frames (tag 03EA) are drawn head-left
-- and leaning left, and so are Torchic's four running frames -- and nothing
-- here draws any of them mirrored, because the cartridge does not either.
-- So the bicycle travels left, the scenery travels right past it, and
-- anything lying still on that scenery travels right with it.
--
-- Written down once and read by all three places that need it, because the
-- three had disagreed: the backdrop panned as though the rider were going
-- right, Volbeat flew in from behind (which is right), and the two on the
-- ground came in from in front and drifted backwards to their stations.
--
-- Reported from play: "Torchic is also moving in the wrong direction after he
-- falls should be moving beind the player driving the bike".  Behind a rider
-- going left is to the RIGHT, and it was sliding left -- travelling with him
-- rather than being left behind.
local RIDE_DIR = -1             -- +1 travels right, -1 travels left
local POKEMON_ENTER_X = -64     -- pret creates the Pokemon at (-64, 60)
local POKEMON_Y = 60
local POKEMON_SPEED = 0.9
local POKEMON_ARC = 48          -- Sin(t >> 2 & 0x7F, 48), one arc over 512
local POKEMON_ARC_FRAMES = 512
-- HOW THE OPENING SHOT IS STAGED.
--
-- THERE IS NO POND ASSET, and that is the thing that took longest to accept.
-- The scene decompresses ONE sheet and four tilemaps and nothing else, so the
-- water is not a picture to go and find -- it is composed out of the four
-- layers, and getting it on screen is a staging problem rather than an
-- extraction one.
--
-- What each layer holds, read off the composed tilemaps:
--   0  the big leaves across the top, a transparent middle, a dark bank of
--      grass along the bottom -- the nearest thing to the lens
--   1  a hedge along its top, solid dark green below it
--   2  grass tufts and a leaf bed along its top, solid dark green below
--   3  the backdrop: sky, mountains, a green field, and then a pale flat
--      band across its bottom third.  That band is the water.
--
-- Stacked at a common offset -- which is what this did -- layers 1 and 2 lay
-- their dark green over the whole lower screen and the water is buried under
-- it.  That was the missing pond: not absent, covered.
--
-- So the three near layers are STAGED rather than stacked: the leaves at the
-- top of the frame, the two banks pushed down until only their top strips
-- show along the bottom, and the backdrop framed so its pale band sits in the
-- gap between them.  A drop then runs down a leaf, falls through open air and
-- lands in water, which is the shot.  Every number here is reconstruction --
-- the cartridge scrolls its four backgrounds independently and none of those
-- offsets is a table anyone can read.
-- ...AND THE POND IS BLACK, which is the part the staging above got wrong.
--
-- Reported from play: "the intro with the leaves and the droplets is missing
-- the water that the puddle drops into -- in the original game it appears as
-- black with ripples where drops fall".
--
-- The note below calls the backdrop's "pale flat band across its bottom third"
-- the water.  It is not water: the backdrop is 256 rows because a GBA
-- background is, the picture stops at 160, and that band is the EMPTY part of
-- the tilemap painted in the backdrop colour.  Framing the shot to show it put
-- a beige floor under the leaves.
--
-- There is no pond asset and there was never going to be one -- the pool is
-- the shade under the leaves, and on the cartridge it is very nearly black.
-- Both numbers are measured off a capture of the cartridge and snapped to the
-- GBA's five bits per channel: the surface starts three fifths of the way down
-- the screen, and the water is a dark green that reads as black until a ripple
-- lands in it.
local POOL = { 8 / 255, 24 / 255, 8 / 255 }
local POOL_TOP = 96

local SHOT_BACKDROP_TOP = 78    -- the backdrop's window: water in the lower half
local SHOT_BANKS = { 0, 124, 138 }  -- screen y of each near layer, front first
local WATER_Y = 110             -- the middle of the band the banks leave open
local RIPPLE_Y = WATER_Y        -- so a drop lands in it and rings
local RIPPLE_FRAMES = 24
local DANGLE_FRAMES = 24        -- it hangs off the leaf before letting go
local SPARKLE_COUNT = 11        -- pret spawns eleven, twelve frames apart
local SPARKLE_GAP = 12
local SPARKLE_LIFE = 48

-- The three drops the cartridge creates, with the arguments it passes:
-- CreateWaterDrop(x, y, speed, delay, gravity, small).  Speed and gravity are
-- 8.8 fixed point, so they divide by 256 to get pixels per frame.
-- `tipX`/`tipY` are RECONSTRUCTION: the cartridge's drop follows the leaf it
-- is on, and where that leaf runs is in the sprite callback, not in any table.
-- What is the cartridge's is where each drop STARTS, how fast it moves, how
-- hard it falls, and -- for the first one -- the frame it lets go on.
local DROPS = {
  { at = T_BIG_DROP,     x = 236, y = -14, tipX = 150, tipY = 58,
    gravity = 0x78, falls = T_BIG_DROP_FALLS, small = false },
  { at = T_SMALL_DROP_1, x = 48,  y = 0,   tipX = 86,  tipY = 52,
    gravity = 0x70, small = true },
  -- y = 60, not 30.  The three drops are created by one constructor and the
  -- arguments are in the code: (236, -14, ..., speed 120) in the scene's load,
  -- then (48, 0, 1024, 5, speed 112) at frame 368 and (200, 60, 1024, 9,
  -- speed 128) at 384.  Every other number in this table already matched;
  -- this one was half what the cartridge passes.
  { at = T_SMALL_DROP_2, x = 200, y = 60,  tipX = 186, tipY = 56,
    gravity = 0x80, small = true },
}
-- the big drop's slide is the cartridge's: spawned at 76, it lets go at 251.
-- The small ones carry no recorded beat, so they slide for the same span --
-- which puts both of them down just before the camera starts to climb.
local SLIDE_FRAMES = T_BIG_DROP_FALLS - T_BIG_DROP

-- Reported from play: "the ... main menu intro music/sounds arent playing".
-- The intro had a `Music.stop` on its way out and nothing on its way in, so
-- Emerald's opening demo ran in silence and handed a silent title screen on.
function Gen3Intro:enter()
  local data = self.game and self.game.data
  local song = data and Music.special(data, "intro")
  if song and data.audio and data.audio.songs and data.audio.songs[song] then
    pcall(Music.play, data, song)
  end
end

function Gen3Intro:wantsFillScale() return true end

-- NOT A PANEL, so its edge is not a frame to continue.
--
-- Renderer:bleedEdges paints the letterbox with the surface's outermost row
-- and column so a menu's border appears to run to the window edge.  Here the
-- outermost column is the attract movie's scenes, which are pictures -- pulling it
-- outward stretches that sideways instead of extending a border.  Reported
-- from play: "fix the stretching of borders on the start menu, main menu,
-- main menu intro and the continue, new game, options, exit menus ... instead
-- make them full screen/fit the screen without stretching".  wantsFillScale
-- above is what makes it fill; this is what stops it smearing.
function Gen3Intro:wantsEdgeBleed() return false end
-- The same surface the title asks for, so the film and the screen it hands to
-- are the same shape and a wide window is filled rather than framed in black.
-- Everything inside draw() still lays out against the cartridge's own 240
-- columns; draw() translates them into the middle of it.
function Gen3Intro:uiSize() return Gen3Wide.uiSize() end

-- colour, not four shades: see the note on Gen3Title:sgbPalettes
function Gen3Intro:sgbPalettes()
  local P = require("src.render.PaletteFX")
  local w = select(1, Gen3Wide.uiSize())
  return { P.trueColorZone(0, 0, math.ceil(w / 8) - 1,
                           math.ceil(GBA_H / 8) - 1) }
end

function Gen3Intro.new(game, onDone)
  local self = setmetatable({}, Gen3Intro)
  self.game = game
  self.onDone = onDone
  self.frame = 0
  self.finished = false
  local intro = (game.data.field and game.data.field.intro) or {}
  self.studio = intro.studio or {}
  self.skipAll = intro.skip and true or false
  self.skies = Gen3Scene.layersOf(game.data, "intro")

  -- Split the role's layers by the VRAM address each is loaded to (see the
  -- note at the top): a shared address means one background taking turns,
  -- a private one means a layer that stands through all of them.
  local scenes = (game.data.scenes) or {}
  local uses = {}
  for _, id in ipairs(self.skies) do
    local dest = scenes[id] and scenes[id].graphicsDest
    if dest then uses[dest] = (uses[dest] or 0) + 1 end
  end
  self.standing, self.sequence = {}, {}
  for _, id in ipairs(self.skies) do
    local dest = scenes[id] and scenes[id].graphicsDest
    if dest and (uses[dest] or 0) > 1 then
      self.sequence[#self.sequence + 1] = id
    else
      self.standing[#self.standing + 1] = id
    end
  end
  -- a dataset whose layers all landed in their own slot has no sequence to
  -- run; then every layer takes a turn, which is what this used to do
  if not self.sequence[1] then
    self.sequence, self.standing = self.skies, {}
  end

  self.cast = (game.data.constants or {}).gen3IntroCast
  self.shot = ((game.data.constants or {}).gen3IntroShots or {}).leaves
  self.rideShot = ((game.data.constants or {}).gen3IntroShots or {}).ride
  self.rideX = 0
  return self
end

-- The opening shot's layers, back to front.  Empty for a dataset without it,
-- and the intro then plays as a card over the skies the way it used to.
function Gen3Intro:shotLayers()
  local record = self.shot
  if type(record) ~= "table" then return nil end
  if self.cachedLayers ~= nil then
    return self.cachedLayers[1] and self.cachedLayers or nil
  end
  local out = {}
  for n, layer in ipairs(record.layers or {}) do
    local ok, image = pcall(Assets.image, layer.image)
    if ok and image then
      out[#out + 1] = { image = image, backdrop = layer.backdrop, order = n,
                        wrap = tonumber(layer.wrap) }
    end
  end
  -- THE LOAD ORDER IS THE PRIORITY ORDER.  The cartridge puts the first map
  -- it loads on BG0 and the last on BG3, and a BG's number IS its priority
  -- here (BG0CNT..BG3CNT are 9000, 9201, 9402, 9603), so layer 1 is the
  -- nearest and layer 4 the backdrop -- which is exactly what `backdrop`
  -- already marked.  The scroll track is indexed by that same order, so the
  -- list is left in it and drawn back to front instead of being sorted.
  table.sort(out, function(a, b)
    local ab, bb = a.backdrop and 1 or 0, b.backdrop and 1 or 0
    if ab ~= bb then return ab > bb end
    return a.order < b.order
  end)
  self.cachedLayers = out
  return out[1] and out or nil
end

-- THE RIDE'S OWN BACKDROP, back to front, cached like the opening shot's.
--
-- Three layers and not a sequence: the cartridge's scene two decompresses
-- exactly four blobs and turns on exactly three backgrounds, so there is
-- nothing here to take turns.  Order is the priority order the control
-- registers give (BG3 the mountains, BG2 the pines, BG1 the grass), which is
-- the order the import writes them in.
function Gen3Intro:rideLayers()
  local record = self.rideShot
  if type(record) ~= "table" then return nil end
  if self.cachedRide ~= nil then
    return self.cachedRide[1] and self.cachedRide or nil
  end
  local out = {}
  for _, layer in ipairs(record.layers or {}) do
    local ok, image = pcall(Assets.image, layer.image)
    if ok and image then out[#out + 1] = image end
  end
  self.cachedRide = out
  return out[1] and out or nil
end

-- One of the shot's sprite sheets, and the quad for a frame of it.  The
-- import lays each sheet out as its frames side by side, so a frame is a
-- straight slice; a sheet the discovery pass could not name a shape for has
-- one frame and is never asked for a second.
function Gen3Intro:shotSprite(role, frame)
  local sprites = self.shot and self.shot.sprites
  local record = type(sprites) == "table" and sprites[role]
  if type(record) ~= "table" or not record.image then return nil end
  local ok, image = pcall(Assets.image, record.image)
  if not ok or not image then return nil end
  local frames = math.max(1, math.floor(tonumber(record.frames) or 1))
  local fw = math.floor(tonumber(record.frameWidth) or 32)
  local fh = math.floor(tonumber(record.frameHeight) or 32)
  local iw, ih = image:getDimensions()
  local at = (math.floor(frame or 0) % frames) * fw
  return image, love.graphics.newQuad(at, 0, fw, fh, iw, ih), fw, fh, record
end

-- One actor's sheet and the quad for a frame of it.
function Gen3Intro:actor(name, frame, which)
  local record = self.cast and self.cast[name]
  if type(record) ~= "table" or not record.image then return nil end
  local ok, image = pcall(Assets.image, record.image)
  if not ok or not image then return nil end
  local frames = math.max(1, math.floor(tonumber(record.frames) or 1))
  local fw = math.floor(tonumber(record.frameWidth) or 64)
  local fh = math.floor(tonumber(record.frameHeight) or 64)
  -- A SHEET IS NOT ALWAYS ONE ANIMATION.  Torchic's six frames are four of it
  -- running and two of it on its side; cycling all six made it fall over once
  -- a second, which is not what it does on the cartridge.  The import works
  -- out how many belong to the first animation from the frames' own shapes.
  local cycle = math.max(1, math.min(frames,
                                     math.floor(tonumber(record.runFrames)
                                                or frames)))
  local iw, ih = image:getDimensions()
  local at
  if which == "tumble" and frames > cycle then
    -- the frames the run cycle stops short of -- Torchic's two on its face
    local extra = frames - cycle
    at = (cycle + (math.floor(frame or 0) % extra)) * fw
  else
    at = (math.floor(frame or 0) % cycle) * fw
  end
  return image, love.graphics.newQuad(at, 0, fw, fh, iw, ih), fw, fh
end

-- A cast sheet drawn WHOLE, for the one member whose "frames" are the pieces
-- of a single picture rather than poses of it (see the Pokemon in drawRide).
-- Returns the image and its dimensions, or nil.
function Gen3Intro:actorWhole(name)
  local record = self.cast and self.cast[name]
  if type(record) ~= "table" or not record.image then return nil end
  local ok, image = pcall(Assets.image, record.image)
  if not ok or not image then return nil end
  local iw, ih = image:getDimensions()
  return image, iw, ih
end

-- Which rider a save carries.  Before the Birch speech has been answered
-- there is no gender on the save, and the boy is the cartridge's own default.
function Gen3Intro:riderName()
  local player = (self.game.save or {}).player or {}
  if player.gender == "girl" and self.cast and self.cast.riderGirl then
    return "riderGirl"
  end
  return (self.cast and self.cast.riderBoy) and "riderBoy" or "riderGirl"
end

function Gen3Intro:finish()
  if self.finished then return end
  self.finished = true
  pcall(Music.stop)
  self.game.stack:pop()
  if self.onDone then self.onDone() end
end

function Gen3Intro:update(dt)
  if self.skipAll then self:finish() return end
  local input = self.game.input
  if input:wasPressed("a") or input:wasPressed("b")
     or input:wasPressed("start") then
    self:finish()
    return
  end
  self.frame = self.frame + 1
  -- the world keeps moving across a cut, so the ride's odometer runs the
  -- whole film rather than restarting with each shot
  self.rideX = self.rideX + RIDE_SPEED
  if self.frame >= self:lastFrame() then self:finish() end
end

-- The film's last frame: the ride's end on a dataset with no third act, and
-- the ride plus the act's own 893 frames on one that has it.
function Gen3Intro:lastFrame()
  local record = self:finaleRecord()
  if not record then return T_SCENE_2_END end
  return T_ACT3 + (tonumber(record.frames) or 0)
end

-- ---------------------------------------------------------------------------
-- SCENE ONE: the leaves.

-- Where the camera is.  It holds on the leaves until the sparkles and then
-- climbs out of them, which is the span the pan-up task runs over.
function Gen3Intro:panProgress()
  local span = T_PAN_UP_END - T_SPARKLES
  return math.min(1, math.max(0, (self.frame - T_SPARKLES) / span))
end

-- WHERE THE FOUR LAYERS SIT ON THIS FRAME, out of the cartridge's own
-- BGxVOFS.  A row of the track is
--   firstFrame lastFrame v0 v1 v2 v3 d0 d1 d2 d3
-- and `order` is the layer's load index, which is its BG number.
function Gen3Intro:shotScroll(order)
  local runs = self.shot and self.shot.scroll
  if type(runs) ~= "table" or not runs[1] then return nil end
  local into = self.frame
  local last = runs[#runs]
  if into < 0 then into = 0 end
  if into > last[2] then into = last[2] end
  for _, row in ipairs(runs) do
    if into >= row[1] and into <= row[2] then
      local step = into - row[1]
      return row[2 + order] + row[6 + order] * step
    end
  end
  return nil
end

function Gen3Intro:drawShot(layers)
  -- THE CARTRIDGE'S OWN CAMERA, when the import has it.  Four maps, four
  -- vertical offsets, nothing else: a GBA background wraps at 256 pixels, so
  -- each one is drawn twice to cover the seam, and the layers go back to
  -- front because a lower BG number is a nearer layer here.
  local scrolled = self:shotScroll(1) ~= nil
  if scrolled then
    -- BY BG NUMBER, HIGHEST FIRST.  The staged list above is sorted backdrop-
    -- first for the fallback path, which is NOT back-to-front (the backdrop is
    -- BG3 and the three cut-outs follow in load order), so the draw walks the
    -- load index itself: BG3, BG2, BG1, BG0.
    local byOrder = self.shotByOrder
    if not byOrder then
      byOrder = {}
      for _, layer in ipairs(layers) do byOrder[layer.order] = layer end
      self.shotByOrder = byOrder
    end
    love.graphics.setColor(1, 1, 1, 1)
    for order = #layers, 1, -1 do
      local layer = byOrder[order]
      if layer then
        local iw, ih = layer.image:getDimensions()
        -- A BACKGROUND WRAPS AT ITS OWN HEIGHT, WHICH IS NOT ITS PICTURE'S.
        --
        -- Reported from play: "when it raises upward from the water droplets
        -- and leaves it shows a black background and missing the field of
        -- leaves still".  These four maps are 256x512 -- the size bits of
        -- BG0CNT..BG3CNT (9000, 9201, 9402, 9603) are 2 -- and the cartridge
        -- fills only the top half of each, so the bottom half is tile 0 and
        -- tile 0 is transparent.  The camera climbs out of the leaves rather
        -- than looping them: BG0VOFS runs 40 down to -217 and BG0 simply
        -- leaves the frame, uncovering the backdrop, which never scrolls.
        --
        -- Wrapping at the picture's 256 instead brought the leaf bank back
        -- around over the sky -- its dark underside where the mountains
        -- belong, which is the "black background", and the field of leaves
        -- that should have arrived from below hidden behind it.
        local wrap = math.floor(tonumber(layer.wrap) or ih)
        if wrap < ih then wrap = ih end
        local v = self:shotScroll(order) or 0
        local y = -(v % wrap)
        local x = math.floor((GBA_W - math.min(GBA_W, iw)) / 2)
        love.graphics.draw(layer.image, x, y)
        if y + wrap < GBA_H then
          love.graphics.draw(layer.image, x, y + wrap)
        end
      end
    end
    return
  end

  local progress = self:panProgress()
  love.graphics.setColor(1, 1, 1, 1)
  local bank = 0
  for _, layer in ipairs(layers) do
    local iw, ih = layer.image:getDimensions()
    local top, y = 0, 0
    if layer.backdrop then
      -- the camera tilts up: the far picture's window climbs toward its sky,
      -- and on the way the water it opened on slides out of the bottom
      top = math.floor(math.min(math.max(0, ih - GBA_H), SHOT_BACKDROP_TOP)
                       * (1 - progress))
    else
      bank = bank + 1
      y = SHOT_BANKS[math.min(bank, #SHOT_BANKS)] or 0
      -- ...and everything near the camera swings DOWN across the frame and
      -- off the bottom of it, which is what a tilt up does to a leaf a foot
      -- from the lens
      y = y + math.floor(progress * progress * (GBA_H + 64))
    end
    local slice = math.min(GBA_H - math.min(y, GBA_H), ih - top)
    if slice > 0 then
      local quad = love.graphics.newQuad(0, top, iw, slice, iw, ih)
      love.graphics.draw(layer.image, quad,
                         math.floor((GBA_W - math.min(GBA_W, iw)) / 2), y)
    end
    if layer.backdrop then
      -- THE POOL, straight after the backdrop and under everything near the
      -- camera.  It swings down out of frame on the same curve the leaf banks
      -- do, because it is the same tilt: what is under the lens leaves the
      -- bottom of the picture as the camera lifts toward the sky.
      local poolTop = POOL_TOP + math.floor(progress * progress * (GBA_H + 64))
      if poolTop < GBA_H then
        love.graphics.setColor(POOL[1], POOL[2], POOL[3], 1)
        love.graphics.rectangle("fill", 0, poolTop, GBA_W, GBA_H - poolTop)
        love.graphics.setColor(1, 1, 1, 1)
      end
    end
  end
end

-- A drop, at whatever point of its life this frame catches it: running down
-- the leaf, hanging off the end of it, falling, or ringing in the water where
-- it landed.  The cartridge's own chain is
-- slide -> reach the leaf end -> dangle -> fall -> ripple, and that is the
-- shape here; the leaf it runs along is the reconstructed part.
-- THE OBJECTS THE SHOT PUTS OVER ITS FOUR BACKGROUNDS, when the import has
-- them: the drops and the silhouette, at the frames and places the cartridge
-- creates them.  A DROP IS THREE SPRITES -- one carrying the pale bead, two
-- carrying the dark ring -- which is why drawing one of them showed the
-- highlight and nothing else.
function Gen3Intro:shotObjects()
  local record = self.shot
  local rows = record and record.objects
  local strips = record and record.objectSprites
  if type(rows) ~= "table" or type(strips) ~= "table" then return false end
  local into = self.frame
  love.graphics.setColor(1, 1, 1, 1)
  for _, row in ipairs(rows) do
    if into >= row[1] and into <= row[2] then
      local strip = strips[row[3]]
      -- Assets directly rather than the finale's own loader: that one is a
      -- file-level local declared further down, and a helper hoisted above
      -- its upvalue reads a global instead
      local okImg, image = false, nil
      if strip then okImg, image = pcall(Assets.image, strip.image) end
      if okImg and image then
        local step = into - row[1]
        local frame = row[6] + row[9] * step
        local quad = self:finaleQuad(strip, frame)
        if quad then
          love.graphics.draw(image, quad, row[4] + row[7] * step,
                             row[5] + row[8] * step)
        end
      end
    end
  end
  return true
end

function Gen3Intro:drawDrops()
  -- the cartridge's own cast, when this cache carries it
  if self:shotObjects() then return true end
  local sheet, _, fw, fh, record = self:shotSprite("drops", 0)
  if not sheet then return end
  local dropFrame = math.floor(tonumber(record.drop) or 0)
  local ripple = type(record.ripple) == "table" and record.ripple or nil
  for _, d in ipairs(DROPS) do
    local age = self.frame - d.at
    if age >= 0 then
      local slide = (d.falls or (d.at + SLIDE_FRAMES)) - d.at
      local scale = d.small and 0.6 or 1
      local frame, x, y, alpha = dropFrame, d.x, d.y, 1
      local alive = true
      if age < slide then
        -- along the leaf, easing to a stop at the tip, then dangling there
        local run = math.min(1, age / math.max(1, slide - DANGLE_FRAMES))
        local eased = run * run * (3 - 2 * run)
        x = d.x + (d.tipX - d.x) * eased
        y = d.y + (d.tipY - d.y) * eased
        if age > slide - DANGLE_FRAMES then
          y = y + math.sin((age - (slide - DANGLE_FRAMES)) * 0.35) * 1.5
        end
      else
        -- and off it: v = g*t, so the distance is g*t*t/2
        local fell = age - slide
        local g = d.gravity / 256
        x = d.tipX
        y = d.tipY + g * fell * fell / 2
        if y >= RIPPLE_Y then
          -- the ring, at the moment and place it landed
          local landed = math.sqrt(math.max(0, 2 * (RIPPLE_Y - d.tipY) / g))
          local since = fell - landed
          if since > RIPPLE_FRAMES or not ripple then
            alive = false
          else
            y = RIPPLE_Y
            local step = 1 + math.floor(since / (RIPPLE_FRAMES / #ripple))
            frame = math.floor(tonumber(ripple[math.min(step, #ripple)])
                               or dropFrame)
            alpha = 1 - since / RIPPLE_FRAMES
            scale = scale * (1 + since / RIPPLE_FRAMES)
          end
        end
      end
      if alive and y > -fh and y < GBA_H + fh then
        local img, quad = self:shotSprite("drops", frame)
        if img and quad then
          love.graphics.setColor(1, 1, 1, alpha)
          love.graphics.draw(img, quad,
                             math.floor(x - fw / 2 * scale),
                             math.floor(y - fh / 2 * scale), 0, scale, scale)
        end
      end
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- Eleven sparkles, twelve frames apart, from the beat the cartridge starts
-- them on.  Where they sit is reconstruction: the cartridge reads them out of
-- a coordinate table this pass does not find, so they are spread across the
-- picture on a fixed pattern rather than at random -- an intro that flickers
-- differently every boot would be worse than one that is merely not theirs.
-- THE SPARKLES SIT WHERE THE CARTRIDGE PUTS THEM.
--
-- This used to scatter them with `16 + (i * 73) % 200`, which is a formula and
-- not a fact.  The scene's second task walks a run of {x, y} byte pairs --
-- eleven of them, ending on a {0, 0} -- spawning one every twelve frames, and
-- it adds its own half-speed counter to the y on the way, so each one sits six
-- pixels below the last as the camera begins to climb.  The importer reads the
-- run (gen3IntroShots.leaves.sparkles); the formula stays as the fallback for
-- a cache from before it did.
function Gen3Intro:sparkleSpots()
  local record = self.shot and self.shot.sparkles
  local spots = type(record) == "table" and record.spots or nil
  if type(spots) == "table" and #spots > 0 then
    return spots, math.max(1, math.floor(tonumber(record.gap) or SPARKLE_GAP))
  end
  return nil, SPARKLE_GAP
end

function Gen3Intro:drawSparkles()
  local sheet = self:shotSprite("sparkle", 0)
  if not sheet or self.frame < T_SPARKLES then return end
  local spots, gap = self:sparkleSpots()
  local count = spots and #spots or SPARKLE_COUNT
  for i = 0, count - 1 do
    local born = T_SPARKLES + i * gap
    local age = self.frame - born
    if age >= 0 and age < SPARKLE_LIFE then
      local img, quad, fw, fh = self:shotSprite("sparkle",
                                                math.floor(age / 8))
      if img and quad then
        local x, y
        if spots then
          local spot = spots[i + 1]
          x = spot.x
          -- the counter is stepped every other frame, so the nth sparkle is
          -- spawned with half its own delay added to its y
          y = spot.y + math.floor(i * gap / 2)
        else
          x = 16 + ((i * 73) % 200)
          y = 20 + ((i * 47) % 110)
        end
        local a = 1 - age / SPARKLE_LIFE
        love.graphics.setColor(1, 1, 1, a)
        love.graphics.draw(img, quad, x - fw / 2, y - fh / 2)
      end
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- The silhouette that crosses the sky once the camera is out of the leaves.
function Gen3Intro:drawSilhouette()
  if self.frame < T_FLYGON then return end
  local img, quad, fw = self:shotSprite("flygon", 0)
  if not img or not quad then return end
  local age = self.frame - T_FLYGON
  local span = math.max(1, T_SCENE_1_END - T_FLYGON)
  local x = GBA_W + fw - (GBA_W + fw * 2) * (age / span)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, quad, math.floor(x),
                     math.floor(24 + math.sin(age / 24) * 6))
end

-- This port's studio card, drawn on the cartridge's own logo beats.
function Gen3Intro:drawCard(alpha)
  local credit = self.studio.credit or Strings("UNDERdecodedHD")
  local author = self.studio.author or "UNDERdecodedHD"
  local year = self.studio.year or "2026"
  love.graphics.setColor(1, 1, 1, alpha or 1)
  local function centre(text, y)
    Font.draw(text, math.floor((GBA_W - Font.width(text)) / 2), y)
  end
  centre(year, 56)
  centre(credit, 76)
  centre(author, 96)
  love.graphics.setColor(1, 1, 1, 1)
end

-- How far up the card is, on the cartridge's beats: in over 128..144, held,
-- out over 256..272.
function Gen3Intro:cardAlpha()
  local f = self.frame
  if f < T_LOGO_APPEAR or f >= T_LOGO_GONE then return 0 end
  if f < T_LOGO_LETTERS then
    return (f - T_LOGO_APPEAR) / (T_LOGO_LETTERS - T_LOGO_APPEAR)
  end
  if f < T_LOGO_BLEND_OUT then return 1 end
  return 1 - (f - T_LOGO_BLEND_OUT) / (T_LOGO_GONE - T_LOGO_BLEND_OUT)
end

-- ---------------------------------------------------------------------------
-- SCENE TWO: the ride.

-- Where the rider is.  The beats are the cartridge's; the stations between
-- them are not, so they are keyframes here and the rider eases between them.
--
-- His last station is 96, and he leaves from it at the cartridge's own rate,
-- so how long the exit takes is not a guess either -- it is the distance
-- divided by that rate.
local RIDER_HOLD_X = 96
local RIDER_EXIT_FRAMES =
  math.floor((RIDER_HOLD_X - RIDER_EXIT_X) / math.abs(RIDER_EXIT_DX))
local RIDER_TRACK = {
  { T_SCENE_2,       RIDER_ENTER_X },
  { T_MANECTRIC,     120 },
  { T_DRIFT_BACK,    120 },
  { T_RUN_CIRCULAR,  88 },
  { T_MOVE_FORWARD,  72 },
  { T_TORCHIC,       96 },
  { T_FLYGON_ENTER,  144 },
  { T_MOVE_BACKWARD, 144 },
  { T_HOLD_POSITION, 96 },
  { T_TORCHIC_EXIT,  96 },
  -- AND THEN HE RIDES OUT.  The station is the last one the beats give him;
  -- the leg after it is the cartridge's own rate and direction (one pixel a
  -- frame, leftwards, which is the way everything in this scene faces) run
  -- until he has cleared the edge.  He starts going when Torchic turns.
  { T_TORCHIC_SPRINT, 96 },
  { T_TORCHIC_SPRINT + RIDER_EXIT_FRAMES, RIDER_EXIT_X },
  { T_SCENE_2_END,   RIDER_EXIT_X },
}

-- THE THREE THAT RUN ALONGSIDE, on the beats the cartridge gives them.
--
-- They were missing from the ride entirely -- the collector that finds the
-- intro's sheets only kept blobs a whole number of 64x64 frames long, and two
-- of these three are smaller than one.  `at` and `until_` are the cartridge's
-- own frame numbers; where each one runs is not.
--
-- They run BESIDE the rider, not through him.  The first cut put Manectric on
-- the same square as the bicycle, which hid the bicycle completely -- the
-- rider looked like he was sitting on a Manectric, and the bike read as
-- missing.  The ground line is the rider's; the stations are apart.
local RUNNERS = {
  -- `from` is BEHIND the rider and `to` is the station beside him, so a
  -- runner catches him up rather than being overtaken: on a ride going left
  -- (RIDE_DIR) behind is off the right-hand edge, which is where Volbeat
  -- already came in from and where these two now do too.  The stations
  -- themselves are unchanged -- they were measured against the rider, who
  -- has not moved.
  { name = "manectric", at = T_MANECTRIC, y = 118, from = GBA_W + 72, to = 8,
    settle = T_RUN_CIRCULAR, cycle = 6 },
  -- no `until_`: Torchic does not simply stop being drawn.  It gets up,
  -- sprints out to the right and comes back on for the ride's last leg,
  -- which drawTorchicTail below takes over from the eased staging.
  { name = "torchic", at = T_TORCHIC, y = 126,
    from = GBA_W + 40, to = 74, settle = T_FLYGON_ENTER, cycle = 5 },
  { name = "volbeat", at = T_RUN_CIRCULAR, y = 44, from = GBA_W + 32,
    to = 196, settle = T_MOVE_FORWARD, cycle = 8, swoops = true },
}

-- TORCHIC TRIPS, and the frames to do it with were extracted and never used.
--
-- Reported from play: "torchic doesnt fall".  Its sheet is six frames and the
-- importer already knows the split -- four of it running and two of it on its
-- face, which is why `runFrames` is 4 and the cycle stops there.  Those last
-- two are a tumble: head down, legs up, in two poses.  Nothing ever played
-- them, so it ran the whole way across and off.
--
-- WHEN it trips is not derived.  The beats around it are (T_TORCHIC 1224 in,
-- T_FLYGON_ENTER 1394, T_MOVE_BACKWARD 1398, T_HOLD_POSITION 1576,
-- T_TORCHIC_EXIT 1856) and the animation table that says which of them the
-- sprite's own callback watches is not read by this pass.  T_HOLD_POSITION is
-- the reading taken here: the rider stops there, and a Pokemon still running
-- alongside one that has stopped is exactly when a trip reads.  It is a
-- number to correct against a capture, like the rest of the geometry.
local TORCHIC_TRIPS = T_HOLD_POSITION
local TUMBLE_FRAMES = 8          -- how long each tumble pose holds

-- TORCHIC'S LAST LEG, which is two straight lines and both of them are the
-- cartridge's.  It leaves the ground it fell on at four pixels a frame to the
-- right, is gone by about 1842, comes back on at x 335 on frame 1863 and runs
-- the whole width at two a frame to the left.  Where it starts from is the
-- port's own staging frozen on the frame it gets up, so there is no jump.
function Gen3Intro:drawTorchicTail(r)
  local frame = self.frame
  local x
  if frame < T_TORCHIC_RETURN then
    local span = math.max(1, r.settle - r.at)
    local t = math.min(1, (math.min(T_TORCHIC_SPRINT, TORCHIC_TRIPS) - r.at)
                          / span)
    t = t * t * (3 - 2 * t)
    x = r.from + (r.to - r.from) * t
             - RIDE_DIR * (T_TORCHIC_SPRINT - TORCHIC_TRIPS) * RIDE_SPEED
             + (frame - T_TORCHIC_SPRINT) * TORCHIC_SPRINT_DX
  else
    x = TORCHIC_RETURN_X + (frame - T_TORCHIC_RETURN) * TORCHIC_RETURN_DX
  end
  local img, quad, fw, fh = self:actor(r.name, math.floor(self.rideX / r.cycle))
  if not (img and quad) then return end
  if x > GBA_W or x < -fw then return end
  local bob = math.sin(frame / 5) * 1.5
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, quad, math.floor(x), math.floor(r.y - fh / 2 + bob))
end

function Gen3Intro:drawRunners()
  for _, r in ipairs(RUNNERS) do
    if r.name == "torchic" and self.frame >= T_TORCHIC_SPRINT then
      self:drawTorchicTail(r)
    elseif self.frame >= r.at and (not r.until_ or self.frame < r.until_) then
      local down = (r.name == "torchic" and self.frame >= TORCHIC_TRIPS)
      local frame
      if down then
        -- the two frames past the run cycle, alternating; `actor` wraps on
        -- runFrames, so the tumble is asked for by absolute index instead
        frame = (math.floor((self.frame - TORCHIC_TRIPS) / TUMBLE_FRAMES) % 2)
      else
        frame = math.floor(self.rideX / r.cycle)
      end
      local img, quad, fw, fh = self:actor(r.name, frame, down and "tumble")
      if img and quad then
        local span = math.max(1, r.settle - r.at)
        -- it stops where it fell: the ease is frozen at the trip
        local at = down and math.min(self.frame, TORCHIC_TRIPS) or self.frame
        local t = math.min(1, (at - r.at) / span)
        t = t * t * (3 - 2 * t)
        local x = r.from + (r.to - r.from) * t
        -- ...AND THEN THE GROUND CARRIES IT AWAY.
        --
        -- Reported from play: "when torchic falls its supposed to fall in
        -- place on the ground and transition off screen at the speed of the
        -- player riding the bike ... currently it falls in place and just sits
        -- there".  Once it is down it is no longer running, so nothing moves
        -- it -- but the WORLD is still moving, at RIDE_SPEED, and a thing
        -- lying on that world goes with it.  The rate is the ground's own: the
        -- nearest standing layer is drawn at parallax 1.0 (see drawRide), so
        -- this is the same pixels per frame those leaves travel.
        if down then
          x = x - RIDE_DIR * (self.frame - TORCHIC_TRIPS) * RIDE_SPEED
        end
        -- a small bob, so a runner reads as running rather than sliding --
        -- and nothing bobs once it is on its face
        local bob = down and 0 or math.sin(self.frame / 5) * 1.5
        -- ...AND THE ONE IN THE AIR NEVER STOPS.
        --
        -- Reported from play: "the illumuise is supposed to be moving around
        -- swooping".  It settles at its station like the two on the ground and
        -- then holds, because drawRunners had one rule for all three.  A thing
        -- with wings does not hold: once it has arrived it keeps swooping
        -- around the spot it arrived at.  The figure it flies is
        -- reconstructed -- the cartridge's is in a sprite callback this pass
        -- does not read -- but a flier that drifts beats a flier nailed to the
        -- sky.
        if r.swoops and t >= 1 then
          local a = (self.frame - r.settle) / 40
          x = x + math.sin(a) * 18
          bob = bob + math.sin(a * 2) * 10
        end
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(img, quad, math.floor(x),
                           math.floor(r.y - fh / 2 + bob))
      end
    end
  end
end

function Gen3Intro:riderX()
  local f = self.frame
  for i = 1, #RIDER_TRACK - 1 do
    local a, b = RIDER_TRACK[i], RIDER_TRACK[i + 1]
    if f < b[1] then
      local span = math.max(1, b[1] - a[1])
      local t = math.min(1, math.max(0, (f - a[1]) / span))
      -- ease in and out, so a station is arrived at rather than snapped to
      t = t * t * (3 - 2 * t)
      return a[2] + (b[2] - a[2]) * t
    end
  end
  return RIDER_TRACK[#RIDER_TRACK][2]
end

-- The three bands of pines that drift between the mountains and the stand of
-- big pines.  `bands` is the cartridge's: where each starts and how far it
-- goes a frame, off the sprites' own 16.16 accumulator at 017B62C.
-- WHERE ONE TREE OF A BAND IS ON THIS FRAME.
--
-- The cartridge's own arithmetic, not a modulo: the sprite callback at
-- 017B62C adds its speed to a 16.16 accumulator and then, if the whole part
-- has gone past 255, drops it to -32 and keeps the fraction.  A tree
-- therefore covers 288 pixels a lap, so the four of a band do not stay 64
-- apart -- one gap in the ring is 96 -- and that unevenness is the
-- cartridge's, not an accident of tiling.
local function sceneryX(start, speed, into, wrapAt, wrapTo)
  local lap = wrapAt - wrapTo + 1
  local pos = start + into * speed
  if lap > 0 and pos > wrapAt then
    pos = (pos - (wrapAt + 1)) % lap + wrapTo
  end
  return math.floor(pos)
end

-- THE THREE BANDS OF DRIFTING PINES, each its own tree off the one sheet.
--
-- Reported from play: "the top layer of trees closest to the player in the
-- cycle scene arent moving".  The near band is a 32x32 pine and the two
-- behind it are 16x32 ones; the import lays all three side by side in the
-- scenery strip and `bands` says which slice each takes, so the band that
-- moves fastest is now a whole tree instead of a slice of all three.
function Gen3Intro:drawScenery(margin)
  local record = self.rideShot and self.rideShot.scenery
  local strip = self:rideSprite("scenery")
  if type(record) ~= "table" or not strip then return false end
  local sheet = self.rideShot.sprites and self.rideShot.sprites.scenery
  local parts = type(sheet) == "table" and sheet.parts or nil
  local sw, sh = strip:getDimensions()
  local spacing = math.max(1, math.floor(tonumber(record.spacing) or 64))
  local count = math.max(1, math.floor(tonumber(record.count) or 4))
  local wrapAt = math.floor(tonumber(record.wrapAt) or 255)
  local wrapTo = math.floor(tonumber(record.wrapTo) or -32)
  -- the cartridge's own clock for these, and its own stop: the scene's
  -- handler freezes the bands on frame 1856 and the rest of the ride plays
  -- against a still forest
  local start = math.floor(tonumber(record.first) or T_SCENE_2)
  local freeze = tonumber(record.freeze)
  local now = self.frame
  if freeze and now > freeze then now = freeze end
  local into = math.max(0, now - start)
  local lap = wrapAt - wrapTo + 1
  self.sceneryQuads = self.sceneryQuads or {}
  love.graphics.setColor(1, 1, 1, 1)
  for n, band in ipairs(record.bands or {}) do
    local part = parts and parts[tonumber(band.part) or 0]
    local bw = math.floor(tonumber(band.width) or (part and part.width) or sw)
    local bh = math.floor(tonumber(band.height) or (part and part.height) or sh)
    local quad = self.sceneryQuads[n]
    if not quad then
      quad = love.graphics.newQuad(part and part.x or 0, part and part.y or 0,
                                   bw, bh, sw, sh)
      self.sceneryQuads[n] = quad
    end
    -- the sprite's x and y are its middle, and a quad is drawn from its top
    local y = math.floor((tonumber(record.y) or 88) - bh / 2)
    for k = 0, count - 1 do
      local at = sceneryX((tonumber(band.x) or 0) + k * spacing,
                          tonumber(band.speed) or 0, into, wrapAt, wrapTo)
      local x = at - bw / 2
      -- a surface wider than the Game Boy's needs the lap either side of it
      local from = math.ceil((-margin - bw - x) / lap)
      local to = math.floor((GBA_W + margin - x) / lap)
      for lapN = math.min(0, from), math.max(0, to) do
        love.graphics.draw(strip, quad, math.floor(x + lapN * lap), y)
      end
    end
  end
  return true
end

-- The ride shot's own sheets, which are a different record to the opening
-- shot's -- same shape, so the lookup is the same one pointed elsewhere.
function Gen3Intro:rideSprite(role)
  local sprites = self.rideShot and self.rideShot.sprites
  local record = type(sprites) == "table" and sprites[role]
  if type(record) ~= "table" or not record.image then return nil end
  local ok, image = pcall(Assets.image, record.image)
  if not ok or not image then return nil end
  return image
end

function Gen3Intro:drawRide()
  local data = self.game.data
  -- how far past the cartridge's own columns this surface runs, each side
  local margin = Gen3Wide.inset(select(1, Gen3Wide.uiSize()))
  -- the sequence takes its turns across the ride rather than on a timer of
  -- its own, so the film is as long as the cartridge's clock says
  local span = T_SCENE_2_END - T_SCENE_2
  local into = math.max(0, self.frame - T_SCENE_2)
  local count = math.max(1, #self.sequence)
  local index = math.min(count, 1 + math.floor(into / (span / count)))

  local function paint(id, opaque, parallax)
    local image = id and Gen3Scene.image(data, id, opaque)
    if not image then return false end
    local iw, ih = image:getDimensions()
    -- THE RIDE PANS SIDEWAYS AND ONLY SIDEWAYS.
    --
    -- Reported from play: "the backdrop is scrolling vertically instead of
    -- horizontally".  It was doing both.  These backgrounds are 256 tall
    -- against a 160 screen because a GBA background IS 256 tall -- the extra
    -- ninety-six rows are the unused part of the map, not more scenery -- and
    -- this walked the window down through them over each segment, which reads
    -- as the camera craning up a wall.  The picture is in the top 160 rows,
    -- which is where the cartridge's own scroll register leaves it.
    local quad = love.graphics.newQuad(0, 0, iw, math.min(GBA_H, ih), iw, ih)
    -- A LAYER SCROLLS SIDEWAYS AND WRAPS, which is what makes it a ride:
    -- these maps are 256 wide against a 240 screen, so panning them without
    -- wrapping moves sixteen pixels and looks like a still.  Tiled across
    -- whatever the surface is, so a wide window keeps the ride going rather
    -- than ending it at the Game Boy's edge.
    -- the scenery goes the OTHER way to the rider, which is what makes it a
  -- ride rather than a treadmill
  local shift = math.floor(-RIDE_DIR * self.rideX * (parallax or 1)) % iw
    local x = shift - iw - margin
    while x < GBA_W + margin do
      love.graphics.draw(image, quad, x, 0)
      x = x + iw
    end
    return true
  end

  -- THE BACKDROP IS THE CARTRIDGE'S WHEN THE DATASET HAS IT.
  --
  -- Reported from play: "in the cycle intro the backdrop is incorrect its
  -- supposed to be mountains in the background and pine trees in layers
  -- moving".  It is, and none of it was guesswork in the end: scene two's
  -- loader decompresses four blobs into two char blocks and three maps, and
  -- the three backgrounds they make are the mountains with their far tree
  -- line, a stand of big pines, and the grass field.  Not one of them moves
  -- -- every scroll register is written to zero once and left there for the
  -- whole ride -- so the panning the port used to do was the wrong idea as
  -- well as the wrong pictures.
  --
  -- What moves is twelve sprites of one 64x32 pine strip, in three bands
  -- drifting RIGHT at 1/8, 1/16 and 1/32 of a pixel a frame, sitting between
  -- the mountains and the big pines.  Four strips 64 apart tile 256 exactly,
  -- so each band is drawn as a wrapped tile rather than as four objects.
  local ride = self:rideLayers()
  local drew = false
  if ride then
    local function still(image)
      if not image then return end
      local iw, ih = image:getDimensions()
      local quad = love.graphics.newQuad(0, 0, iw, math.min(GBA_H, ih), iw, ih)
      local x = -iw - margin
      while x < GBA_W + margin do
        love.graphics.draw(image, quad, x, 0)
        x = x + iw
      end
    end
    love.graphics.setColor(1, 1, 1, 1)
    still(ride[1])
    self:drawScenery(margin)
    still(ride[2])
    still(ride[3])
    drew = true
  else
    drew = paint(self.sequence[index], true, 0.35)
    for i, id in ipairs(self.standing) do
      drew = paint(id, false, 0.8 + i * 0.2) or drew
    end
  end

  -- THE POKEMON crosses behind the rider on its own beat, riding one arc of
  -- the cartridge's own sine: Sin(t >> 2 & 0x7F, 48) is half a period, so it
  -- rises and falls exactly once over the 512 frames the counter runs for.
  --
  -- ...AND IT IS ONE ANIMAL, NOT TWO FRAMES OF ONE.
  --
  -- Reported from play: "flygons tail is cut off".  It was, by exactly half.
  -- The sheet is 128 tiles and the manifest reads them as two 64x64 frames,
  -- which is right about the STORAGE -- a GBA draws a 128-wide sprite as two
  -- 64x64 objects side by side, and that is how the tiles are laid down -- and
  -- wrong about what they are.  They are not an animation: the head and one
  -- wing are in the first, the rest of the body and the whole tail with its
  -- red fin are in the second, and the body runs straight through the join.
  -- Asking for "frame 0" drew the front half and nothing else.
  --
  -- The composed picture is already the whole 128x64 animal, so it is drawn
  -- whole.  The note that used to sit here had the diagnosis right and never
  -- reached the draw.
  love.graphics.setColor(1, 1, 1, 1)
  if self.frame >= T_FLYGON_ENTER then
    local age = self.frame - T_FLYGON_ENTER
    local mon, monW = self:actorWhole("pokemon")
    if mon then
      local x = POKEMON_ENTER_X + age * POKEMON_SPEED
      local arc = math.sin(math.min(age, POKEMON_ARC_FRAMES)
                           / POKEMON_ARC_FRAMES * math.pi) * POKEMON_ARC
      if x < GBA_W + monW then
        love.graphics.draw(mon, math.floor(x), math.floor(POKEMON_Y - arc))
      end
    end
  end

  -- the three that run with him, behind the rider so he stays in front
  self:drawRunners()

  -- THE RIDER'S SHEET ALREADY HAS THE BICYCLE IN IT.
  --
  -- Reported from play: "the bike looks duplicated".  It was, and the note
  -- that used to sit here was simply wrong about the art: it claimed a rider
  -- "whose sheet is the body alone" and put the separate bicycle sheet under
  -- him.  Look at the four frames of tag 03EA and the bicycle is drawn in
  -- every one of them -- handlebars, frame, pedals, the child bent over it --
  -- so the sheet under it was a SECOND bicycle, half a body lower.
  --
  -- The standalone bicycle (tag 03E9, four 64x32 frames of a full side-on
  -- Mach Bike with spoked wheels) is a different object at a different size
  -- and it is not this one: nothing here knows which beat it belongs to yet,
  -- so it is left extracted and undrawn rather than stacked under a rider who
  -- already has one.
  local pedal = math.floor(self.rideX / PEDAL_FRAMES)
  local x = math.floor(self:riderX())
  local rider, riderQuad = self:actor(self:riderName(), pedal)
  local bike, bikeQuad = self:actor("bike", pedal)
  local top = RIDER_Y - 40
  -- THE BICYCLE, BACK, AND LINED UP THIS TIME.
  --
  -- Taking it out was half right and half wrong.  It IS a second bicycle --
  -- the rider's own four frames have a light one drawn into them -- but the
  -- cartridge's is the sheet at tag 03E9, the full side-on Mach Bike with
  -- spoked wheels, and without it the rider pedals a sketch: reported from
  -- play first as "the bike looks duplicated" and then, once it was gone, as
  -- "the bike sprite is missing under the player".
  --
  -- What made it read as two was the OFFSET, not the drawing.  It used to be
  -- placed at the rider frame's full height minus its own, which is eight
  -- pixels below where the wheels belong.  Both sheets are measured instead:
  -- the rider's ink ends on row 52 of its 64 and the bicycle's on row 30 of
  -- its 32, so the bicycle is dropped by the difference and the two sets of
  -- wheels land on one line.
  if bike and bikeQuad then
    love.graphics.draw(bike, bikeQuad, x, top + BIKE_DROP)
  end
  if rider and riderQuad then
    love.graphics.draw(rider, riderQuad, x, top)
  end
  return drew
end

-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- ACT THREE: the ball, the two figures, the clouds.

-- The extracted act, or nil on a dataset that predates it (in which case the
-- film still ends where it always did).
function Gen3Intro:finaleRecord()
  if self.finale ~= nil then return self.finale or nil end
  local record = (self.game.data.constants or {}).gen3IntroFinale
  local ok = type(record) == "table" and type(record.beats) == "table"
             and record.beats[1] and type(record.track) == "table"
             and record.track[1]
  self.finale = ok and record or false
  return self.finale or nil
end
-- kept for the caller that only asks whether the act exists
function Gen3Intro:finaleBeats()
  local record = self:finaleRecord()
  return record and record.beats or nil
end

-- Which beat owns this frame: the last one whose graphics have landed.  `at`
-- is the frame the cartridge decompresses that beat on, so the rule is the
-- hardware's own.
function Gen3Intro:finaleBeat()
  local record = self:finaleRecord()
  if not record then return nil end
  local into = self.frame - T_ACT3
  local found
  for _, beat in ipairs(record.beats) do
    if (tonumber(beat.at) or 0) <= into then found = beat end
  end
  return found, into
end

-- The row of the track that covers a frame, interpolated along its own step.
-- A row is { first, last, affine, x, y, scale, angle, flash, dx, dy, ds, da }.
function Gen3Intro:finaleFrame(into)
  local record = self:finaleRecord()
  if not record then return nil end
  local rows = record.track
  local last = rows[#rows]
  if into < 0 then into = 0 end
  if into > last[2] then into = last[2] end
  -- the track is short (269 rows) and walked once a frame; a scan costs less
  -- than the bookkeeping a cursor would need across a skip
  for _, row in ipairs(rows) do
    if into >= row[1] and into <= row[2] then
      local step = into - row[1]
      return {
        affine = row[3] ~= 0,
        x = row[4] + row[9] * step,
        y = row[5] + row[10] * step,
        scale = row[6] + row[11] * step,
        angle = row[7] + row[12] * step,
        flash = row[8],
      }
    end
  end
  return nil
end

local function finaleImage(path)
  if type(path) ~= "string" then return nil end
  local ok, image = pcall(Assets.image, path)
  return ok and image or nil
end

-- One frame out of an object's strip.  Quads are cut once and kept: the act
-- asks for the same handful every frame.
function Gen3Intro:finaleQuad(strip, frame)
  local image = finaleImage(strip.image)
  if not image then return nil end
  local frames = tonumber(strip.frames) or 1
  frame = math.max(0, math.min(frames - 1, tonumber(frame) or 0))
  self.finaleQuads = self.finaleQuads or {}
  local cache = self.finaleQuads[strip.image]
  if not cache then cache = {} self.finaleQuads[strip.image] = cache end
  if not cache[frame] then
    cache[frame] = love.graphics.newQuad(frame * strip.width, 0, strip.width,
                                         strip.height, image:getDimensions())
  end
  return cache[frame]
end

-- THE SCREEN-WIDE BLEND IN FORCE ON A FRAME.
--
-- BeginNormalPaletteFade walks a coefficient from `from` to `to` one step
-- every (delay + 1) frames and mixes every colour that far towards `color`.
-- A new call replaces the one running, so the fade that owns a frame is
-- simply the last one to have started.
function Gen3Intro:finaleFade(into)
  local record = self:finaleRecord()
  local list = record and record.fades
  if type(list) ~= "table" then return nil end
  local found
  for _, fade in ipairs(list) do
    if (tonumber(fade.at) or 0) <= into then found = fade end
  end
  if not found then return nil end
  local step = math.floor((into - found.at) / ((tonumber(found.delay) or 0) + 1))
  local from, to = tonumber(found.from) or 0, tonumber(found.to) or 0
  local y = from + (to > from and step or -step)
  if to > from then y = math.min(y, to) else y = math.max(y, to) end
  if y <= 0 then return nil end
  return found.color, math.min(1, y / 16), found
end

-- THE OBJECTS ON A FRAME.  The rows are in frame order, so one pass builds an
-- index the first time the act is drawn and every frame after is a lookup.
function Gen3Intro:finaleObjects(into)
  local record = self:finaleRecord()
  if not (record and record.objects) then return nil end
  local index = self.finaleObjectIndex
  if not index then
    index = {}
    for _, row in ipairs(record.objects) do
      local at = row[1]
      index[at] = index[at] or {}
      local list = index[at]
      list[#list + 1] = row
    end
    self.finaleObjectIndex = index
  end
  return index[into]
end

-- The colour the bolt has put in the sky's own palette slot, or the slot's
-- resting colour before it ever strikes.
function Gen3Intro:finaleFlicker(into)
  local record = self:finaleRecord()
  local flicker = record and record.flicker
  if type(flicker) ~= "table" then return nil end
  local found
  for _, row in ipairs(flicker.rows or {}) do
    if (tonumber(row.at) or 0) <= into then found = row end
  end
  return (found and found.color) or flicker.base
end

function Gen3Intro:drawFinale(width, inset)
  local beat, into = self:finaleBeat()
  if not beat then return false end
  local state = self:finaleFrame(into)
  if not state then return false end
  local record = self:finaleRecord()

  -- A FADE IS NOT THE WHOLE SCREEN.  BeginNormalPaletteFade names the
  -- palettes it reaches, so the veil is laid over each picture separately --
  -- once over the picture's own pixels, at the fade's coefficient, in the
  -- fade's colour -- rather than as one rectangle over everything.  Which is
  -- the whole reason the bolts read as lightning: the dark the clouds close
  -- into names no OBJ palette, so they flash at full brightness against it.
  local veilColour, veilAlpha, fade = self:finaleFade(into)
  local function reaches(row)
    if not fade then return false end
    if not fade.rows then return true end
    return fade.rows[(tonumber(row) or 0) + 1] and true or false
  end
  local function veil(draw, lit)
    draw()
    if veilColour and veilAlpha and lit then
      love.graphics.setColor(veilColour[1] / 255, veilColour[2] / 255,
                             veilColour[3] / 255, veilAlpha)
      draw()
      love.graphics.setColor(1, 1, 1, 1)
    end
  end

  -- COLOUR 0 OF THE BEAT'S OWN BANK, which is what the hardware leaves
  -- wherever no layer has drawn -- and what the whole screen was, black,
  -- while every beat after the ball was composed against the ball's palette
  local back = beat.backdrop
  local br = back and (back[1] or 0) / 255 or 0
  local bg = back and (back[2] or 0) / 255 or 0
  local bb = back and (back[3] or 0) / 255 or 0
  local left = -(inset or 0)
  -- the backdrop is palette bank 0's colour 0, so bank 0 is what decides
  -- whether a fade reaches it
  local function paper()
    love.graphics.rectangle("fill", left, 0, width, GBA_H)
  end
  love.graphics.setColor(br, bg, bb, 1)
  paper()
  love.graphics.setColor(1, 1, 1, 1)
  if veilColour and veilAlpha and reaches(0) then
    love.graphics.setColor(veilColour[1] / 255, veilColour[2] / 255,
                           veilColour[3] / 255, veilAlpha)
    paper()
    love.graphics.setColor(1, 1, 1, 1)
  end

  -- the ordinary backgrounds, back to front.  The track's x and y are BG0HOFS
  -- and BG1HOFS and a layer says which of them it rides; a background wraps,
  -- so the copy on either side of the seam is drawn too.
  local offsets = { [0] = 0, state.x, state.y }
  for _, layer in ipairs(beat.layers or {}) do
    local image = finaleImage(layer.image)
    if image then
      -- the scroll is in the CARTRIDGE'S columns, so the copies tile out from
      -- there rather than from the wide surface's edge; enough of them to
      -- reach it either side
      local dx = -(offsets[tonumber(layer.scroll) or 0] or 0)
      local iw = image:getWidth()
      local reach = math.ceil(((inset or 0) + iw) / iw)
      local function paint(img)
        return function()
          for tile = -reach, reach do
            love.graphics.draw(img, dx % iw + tile * iw, 0)
          end
        end
      end
      veil(paint(image), reaches(layer.row))
      -- ...and the one colour the bolt drives, in whatever colour it is on.
      -- It is written straight into the faded palette, so no fade touches it.
      local spark = layer.flickerImage and finaleImage(layer.flickerImage)
      if spark then
        local colour = self:finaleFlicker(into)
        if colour then
          love.graphics.setColor(colour[1] / 255, colour[2] / 255,
                                 colour[3] / 255, 1)
          paint(spark)()
          love.graphics.setColor(1, 1, 1, 1)
        end
      end
    end
  end

  -- ...and the affine figure over them
  local art = beat.affine
  if type(art) == "table" then
    local image = finaleImage(art.image)
    -- BgAffineSet is handed the scale as texels per screen pixel in 8.8, so
    -- the magnification is its reciprocal, and its angle is a whole turn in
    -- 65536.  The texture point it pins is (128,128) -- the helper at 016F2A8
    -- writes that constant into the source struct every time.
    local scale = state.scale > 0 and (256 / state.scale) or 0
    if image and scale > 0 then
      local turn = state.angle * 2 * math.pi / 65536
      veil(function()
        love.graphics.draw(image, state.x, state.y, turn, scale, scale,
                           128, 128)
      end, reaches(art.row))
      -- ...and the markings, in the colour the beat is cycling through
      local glow = art.glow and finaleImage(art.glowImage)
      if glow then
        local colour = record.flash and (record.flash[state.flash]
                                         or record.flash[tostring(state.flash)])
        if colour then
          love.graphics.setColor(colour[1] / 255, colour[2] / 255,
                                 colour[3] / 255, 1)
          love.graphics.draw(glow, state.x, state.y, turn, scale, scale,
                             128, 128)
          love.graphics.setColor(1, 1, 1, 1)
        end
      end
    end
  end

  -- THE OBJECTS, over the backgrounds the way OAM sits over a BG of the same
  -- priority: the bubbles rising through Kyogre's water, and the bolts.
  local objects = self:finaleObjects(into)
  if objects then
    local strips = record.sprites or {}
    for _, row in ipairs(objects) do
      local strip = strips[row[2]]
      local image = strip and finaleImage(strip.image)
      if image then
        local quad = self:finaleQuad(strip, row[5])
        if quad then
          -- OAM x and y are the sprite's top-left corner
          veil(function() love.graphics.draw(image, quad, row[3], row[4]) end,
               fade and fade.objects and true or false)
        end
      end
    end
  end

  -- THE LETTERBOX.  WINOUT is zero for the whole act past the ball, so every
  -- row window 0 does not cover shows the backdrop and nothing else -- and
  -- WIN0V does not snap to the band, it CLOSES into it four rows a frame.
  local box = record.letterbox
  if type(box) == "table" and into >= (tonumber(box.at) or 0) then
    local step = (into - box.at) * (tonumber(box.step) or 0)
    local top = math.min(tonumber(box.top) or 0, step)
    local bottom = math.max(tonumber(box.bottom) or GBA_H,
                            (tonumber(box.height) or GBA_H) - step)
    local function bars()
      if top > 0 then
        love.graphics.rectangle("fill", left, 0, width, top)
      end
      if bottom < GBA_H then
        love.graphics.rectangle("fill", left, bottom, width, GBA_H - bottom)
      end
    end
    love.graphics.setColor(br, bg, bb, 1)
    bars()
    love.graphics.setColor(1, 1, 1, 1)
    if veilColour and veilAlpha and reaches(0) then
      love.graphics.setColor(veilColour[1] / 255, veilColour[2] / 255,
                             veilColour[3] / 255, veilAlpha)
      bars()
      love.graphics.setColor(1, 1, 1, 1)
    end
  end

  return true
end

function Gen3Intro:draw()
  -- THE FILM IS 240 COLUMNS WIDE AND THE WINDOW IS NOT.
  --
  -- Asked for directly: "ensure that the main menu and intro animations extend
  -- to wide screen and fill the screen without black borders".  Every beat,
  -- every sprite position and every staged offset below is measured against
  -- the cartridge's own screen, so rather than rewrite them the frame is
  -- SHIFTED into the middle of whatever surface this is -- and the ride's own
  -- backgrounds, which wrap by design, tile out to the edges from there.
  local W = select(1, Gen3Wide.uiSize())
  local inset = Gen3Wide.inset(W)
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("fill", 0, 0, W, GBA_H)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.push()
  love.graphics.translate(inset, 0)

  local layers = self:shotLayers()

  if self.frame < T_SCENE_2 then
    if layers then
      self:drawShot(layers)
      -- the cast is one list now when the import has it, so the silhouette is
      -- in it too; the reconstructed passes stay for a cache that has not
      -- been re-imported
      local staged = self:drawDrops()
      if not staged then
        self:drawSparkles()
        self:drawSilhouette()
      end
    end
    local alpha = self:cardAlpha()
    if alpha > 0 or not layers then
      -- with no shot to draw the card over, it is the whole scene, and it
      -- stands for as long as the cartridge's logo does
      self:drawCard(layers and alpha or 1)
    end
    love.graphics.pop()
    -- the fades cover the WHOLE surface, not just the cartridge's columns, or
    -- a wide window would keep the margins lit through a fade to black
    if self.frame >= T_SCENE_1_END then
      local into = (self.frame - T_SCENE_1_END) / (T_SCENE_2 - T_SCENE_1_END)
      love.graphics.setColor(0, 0, 0, math.min(1, into))
      love.graphics.rectangle("fill", 0, 0, W, GBA_H)
      love.graphics.setColor(1, 1, 1, 1)
    end
    return
  end

  local drew
  if self.frame >= T_ACT3 and self:finaleRecord() then
    drew = self:drawFinale(W, inset)
  else
    drew = self:drawRide()
  end
  love.graphics.pop()

  local since = self.frame - T_SCENE_2
  if since < FADE_FRAMES then
    love.graphics.setColor(0, 0, 0, 1 - since / FADE_FRAMES)
    love.graphics.rectangle("fill", 0, 0, W, GBA_H)
    love.graphics.setColor(1, 1, 1, 1)
  end
  -- THE CUT INTO THE ACT IS THE ACT'S OWN.  This used to fade through BLACK
  -- for twenty frames either side of it, and the cartridge does not: the
  -- ride's handler arms the act's task and the act's first frame calls
  -- BeginNormalPaletteFade(16 -> 0, white), so the screen goes white and the
  -- ball fades in out of it.  Fading to black first put a black hole where
  -- the white flash belongs.  The ride keeps the fade OUT on its own last
  -- frames so the two meet.
  local cut = self.frame - T_SCENE_2_END
  if self:finaleRecord() and cut >= -FADE_FRAMES and cut < 0 then
    love.graphics.setColor(1, 1, 1, 1 + cut / FADE_FRAMES)
    love.graphics.rectangle("fill", 0, 0, W, GBA_H)
    love.graphics.setColor(1, 1, 1, 1)
  end
  local left = self:lastFrame() - self.frame
  if drew ~= false and left < FADE_FRAMES then
    love.graphics.setColor(0, 0, 0, 1 - left / FADE_FRAMES)
    love.graphics.rectangle("fill", 0, 0, W, GBA_H)
    love.graphics.setColor(1, 1, 1, 1)
  end
end

return Gen3Intro
