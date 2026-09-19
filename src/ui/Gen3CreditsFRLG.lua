-- FIRERED'S CREDITS, run from the cartridge's own script (credits.c
-- sCreditsScript, read into constants.gen3Credits.frlg):
--
--   PRINT     a heading and its names fade in on the darkened map, hold for
--             the command's duration, fade out
--   MAPNEXT   the next map fly-over: the map loads at the scene's start tile
--             and the camera drifts (one pixel every other frame), dimmed
--             (BLDY 10), with only the band y 36..124 showing
--   MAP       the same, and the player or rival runs on the spot in front of
--             it on a ground strip (sPlayerRivalSpriteParams)
--   MON       the white circle shrinks onto a POKe BALL and one of the three
--             starters (or PIKACHU) is shown with its cry
--   THEENDGFX the copyright card, then THE END
--   WAITBUTTON until A, or 600 frames
--
-- The map scenes, sprite params and timings are pokefirered's; the pictures
-- are the ones extractFireRedExtraArt read out of the ROM.

local Assets = require("src.render.Assets")
local Font = require("src.render.Font")
local Music = require("src.core.Music")
local Sound = require("src.core.Sound")

local W, H = 240, 160
local C = {}
C.__index = C
C.isOpaque = true
function C:uiSize() return W, H end
function C:wantsFillScale() return true end
-- full colour throughout: without the zone, the SGB shade pass had the map
-- scenes to itself
function C:sgbPalettes()
  local P = require("src.render.PaletteFX")
  return { P.trueColorZone(0, 0, math.ceil(W / 8) - 1, math.ceil(H / 8) - 1) }
end

-- sOverworldMapScenes: map, start tile, scroll step (credits.c)
local SCENES = {
  [0] = { "MAP_G03_N42", 11, 107, 0, 1 },   -- ROUTE23
  { "MAP_G03_N01", 30, 34, 0, -1 },         -- VIRIDIAN_CITY
  { "MAP_G03_N02", 20, 26, 0, -1 },         -- PEWTER_CITY
  { "MAP_G03_N03", 8, 6, 1, 1 },            -- CERULEAN_CITY
  { "MAP_G03_N44", 25, 6, 1, 0 },           -- ROUTE25
  { "MAP_G03_N05", 9, 7, 1, 1 },            -- VERMILION_CITY
  { "MAP_G03_N28", 11, 68, 0, 1 },          -- ROUTE10
  { "MAP_G03_N06", 48, 16, -1, 0 },         -- CELADON_CITY
  { "MAP_G03_N10", 39, 5, 0, 1 },           -- SAFFRON_CITY
  { "MAP_G03_N35", 7, 43, 0, 1 },           -- ROUTE17
  { "MAP_G03_N07", 28, 5, 0, 1 },           -- FUCHSIA_CITY
  { "MAP_G03_N08", 13, 17, 0, -1 },         -- CINNABAR_ISLAND
  { "MAP_G03_N39", 8, 20, 0, -1 },          -- ROUTE21_NORTH
}
local MON_SPECIES = { [0] = "CHARIZARD", "VENUSAUR", "BLASTOISE", "PIKACHU" }
local SPRITE_SCENE = { [3] = 2, [6] = 3, [9] = 4, [12] = 5 }   -- 1-based sprite params rows
-- DoCreditsMonScene: the 16-frame fade-in runs *inside* the initial 40-frame
-- hold.  After that hold it waits 8 frames, puts window 1 up for 4 frames,
-- puts window 2 up for 4, scales the circle for 16, then waits 32 before
-- revealing BG1 and playing the cry.  Keep those waits explicit here rather
-- than serialising the fade and hold (the old approximation made the scene
-- twelve frames too long before the reveal).
local MON_POSE1, MON_POSE2 = 48, 52
local MON_CIRCLE_SHRINK, MON_REVEAL = 56, 104
local MON_FADE_OUT, MON_DONE = MON_REVEAL + 128, MON_REVEAL + 128 + 16

local function image(path)
  if type(path) ~= "string" then return nil end
  local ok, img = pcall(Assets.image, path)
  return ok and img or nil
end

function C.new(game, record, onDone)
  local art = (game.data.constants or {}).gen3FRLGArt or {}
  local self = setmetatable({ game = game, rec = record.frlg, art = art.credits or {},
                              onDone = onDone, frame = 0, idx = 1, timer = 0,
                              textAlpha = 0, fade = 1 }, C)
  self:loadScene({ "MAP_G03_N09", 11, 6, 0, 0 })          -- the Indigo Plateau you arrived at
  self:loadSprite(1)
  self.phase = "open"
  self.bandTop, self.bandBottom = 79, 81
  self.titleText = { title = record.frlg.title, names = "" }
  return self
end

function C:enter()
  local ok = pcall(Music.play, self.game.data, "Music_Credits")
  if not ok then pcall(Music.play, self.game.data, "Music_HallOfFame") end
end

function C:loadScene(scene)
  local id = scene[1]
  local okL, MapLoader = pcall(require, "src.world.MapLoader")
  local okM, map = false, nil
  if okL and self.game.data.maps[id] then okM, map = pcall(MapLoader.load, self.game.data, id) end
  self.map = (okM and type(map) == "table") and map or nil
  if not self.map then
    require("src.core.Logger").warn("gen3 frlg credits: %s did not load (%s)", tostring(id), tostring(map))
  elseif not self.map.renderer then
    require("src.core.Logger").warn("gen3 frlg credits: %s has no renderer", tostring(id))
  end
  self.camX = scene[2] * 16 + 8 - W / 2
  self.camY = scene[3] * 16 + 8 - H / 2
  self.stepX, self.stepY = scene[4], scene[5]
end

function C:loadSprite(row)
  local params = (self.art.spriteParams or {})[row]
  if not params then self.sprite = nil return end
  local who, groundKind, move = params[1], params[2], params[3]
  local save = self.game.save or {}
  local female = (save.player or {}).gender == "girl" or (save.player or {}).female
  local charRec = who == 1 and self.art.rival or (female and self.art.playerFemale or self.art.playerMale)
  local groundRec = ({ [0] = self.art.groundGrass, self.art.groundGrass, self.art.groundDirt,
                       self.art.groundCity })[groundKind]
  local x, y = W - 32, H / 2
  if move == 1 then x = W + 32 elseif move == 2 then y = H end
  self.sprite = { char = charRec and image(charRec.image), charFrames = charRec and charRec.frames or 1,
                  ground = groundRec and image(groundRec.image), groundFrames = groundRec and groundRec.frames or 1,
                  running = groundKind ~= 1, move = move, x = x, y = y }
end

function C:nextCommand()
  local cmd = self.rec.script[self.idx]
  if not cmd then self.phase = "done" return end
  self.idx = self.idx + 1
  self.cmd = cmd
  if cmd.cmd == 0 then
    self.phase, self.timer = "printIn", 16
    self.titleText = self.rec.texts[cmd.param] or self.rec.texts[tostring(cmd.param)] or { title = "", names = "" }
  elseif cmd.cmd == 1 or cmd.cmd == 2 then
    self.phase, self.timer = "mapOut", 16
  elseif cmd.cmd == 3 then
    self.phase, self.timer = "monOut", 16
  elseif cmd.cmd == 4 then
    self.phase, self.timer = "endOut", 16
  elseif cmd.cmd == 5 then
    self.phase, self.timer = "wait", cmd.duration
  end
end

function C:update()
  self.frame = self.frame + 1
  local input = self.game.input
  if input:wasPressed("start") and self.phase ~= "wait" then self:finish() return end
  -- the overworld under the credits runs every other frame
  if self.map and self.frame % 2 == 0 and (self.phase ~= "mon" and self.phase ~= "end") then
    self.camX = self.camX + (self.stepX or 0)
    self.camY = self.camY + (self.stepY or 0)
  end
  local s = self.sprite
  if s then
    if s.move == 1 and s.x > 208 then s.x = s.x - 1
    elseif s.move == 2 and s.y > 80 and self.frame % 2 == 0 then s.y = s.y - 1
    elseif s.move == 3 and self.phase == "endOut" then s.x = s.x - 1 end
  end
  local p = self.phase
  if p == "open" then
    if self.bandTop > 36 then self.bandTop, self.bandBottom = self.bandTop - 1, self.bandBottom + 1
    else self.phase, self.timer = "titleWait", 100 end
  elseif p == "titleWait" then
    self.timer = self.timer - 1
    if self.timer <= 0 then self.phase, self.timer, self.textAlpha = "title", 360, 1 end
  elseif p == "title" then
    self.timer = self.timer - 1
    if self.timer <= 0 then self.textAlpha = 0 self:nextCommand() end
  elseif p == "printIn" then
    self.timer = self.timer - 1
    self.textAlpha = 1 - self.timer / 16
    if self.timer <= 0 then self.phase, self.timer = "printHold", self.cmd.duration end
  elseif p == "printHold" then
    self.timer = self.timer - 1
    if self.timer <= 0 then self.phase, self.timer = "printOut", 16 end
  elseif p == "printOut" then
    self.timer = self.timer - 1
    self.textAlpha = self.timer / 16
    if self.timer <= 0 then self:nextCommand() end
  elseif p == "mapOut" then
    self.timer = self.timer - 1
    self.fade = self.timer / 16
    if self.timer <= 0 then
      self:loadScene(SCENES[self.cmd.param] or SCENES[0])
      if self.cmd.cmd == 2 then self:loadSprite(SPRITE_SCENE[self.cmd.param] or 2) end
      self.phase, self.timer = "mapIn", 16
    end
  elseif p == "mapIn" then
    self.timer = self.timer - 1
    self.fade = 1 - self.timer / 16
    if self.timer <= 0 then self.phase, self.timer = "hold", self.cmd.duration end
  elseif p == "hold" then
    self.timer = self.timer - 1
    if self.timer <= 0 then self:nextCommand() end
  elseif p == "monOut" then
    self.timer = self.timer - 1
    self.fade = self.timer / 16
    if self.timer <= 0 then
      self.sprite = nil
      local species = MON_SPECIES[self.cmd.param]
      local okS, Sprites = pcall(require, "src.pokemon.Sprites")
      local okP, path = false, nil
      if okS then okP, path = pcall(Sprites.path, self.game.data, species, "front", { kind = "pokepic" }) end
      if not (okP and path) then
        require("src.core.Logger").warn("gen3 frlg credits: no pic for %s (%s)", tostring(species), tostring(path))
      end
      local poses = {}
      for i, rec in ipairs((self.art.monPoses or {})[self.cmd.param + 1] or {}) do
        poses[i] = { img = image(rec.image), x = rec.x, y = rec.y }
      end
      self.mon = { species = species, img = okP and image(path) or nil,
                   poses = poses,
                   ball = image((self.art.pokeball or {})[self.cmd.param + 1]), t = 0 }
      self.phase = "mon"
    end
  elseif p == "mon" then
    local m = self.mon
    m.t = m.t + 1
    -- credits.c starts the 16-frame fade-in and its 40-frame hold together.
    -- The drawing constants above then account for 8/4/4, circle 16, wait 32.
    self.fade = math.min(1, m.t / 16)
    if m.t == MON_REVEAL then pcall(Sound.playCry, self.game.data, m.species) end
    if m.t >= MON_FADE_OUT then self.fade = math.max(0, 1 - (m.t - MON_FADE_OUT) / 16) end
    if m.t >= MON_DONE then self.mon = nil self.map = nil self:nextCommand() end
  elseif p == "endOut" then
    self.timer = self.timer - 1
    self.fade = self.timer / 16
    if self.timer <= 0 then
      self.sprite = nil
      self.endImg = image(self.cmd.param == 0 and self.art.copyright or self.art.the_end)
      self.phase, self.timer = "end", self.cmd.duration
      self.fade = self.cmd.param == 0 and 0 or 1
    end
  elseif p == "end" then
    if self.fade < 1 then self.fade = math.min(1, self.fade + 1 / 16) end
    self.timer = self.timer - 1
    if self.timer <= 0 then self:nextCommand() end
  elseif p == "wait" then
    self.timer = self.timer - 1
    if input:wasPressed("a") or self.timer <= 0 then self.phase, self.timer = "white", 16 end
  elseif p == "white" then
    self.timer = self.timer - 1
    if self.timer <= 0 then self:finish() end
  elseif p == "done" then
    self:finish()
  end
end

function C:finish()
  if self.finished then return end
  self.finished = true
  self.game.stack:pop()
  if self.onDone then self.onDone() end
end

function C:drawMap()
  local g = love.graphics
  local map = self.map
  if not (map and map.renderer) then return end
  local cx, cy = math.floor(self.camX), math.floor(self.camY)
  g.setColor(1, 1, 1, 1)
  local ok, err = pcall(function()
    if map.renderer.drawBorderFill then map.renderer:drawBorderFill(cx, cy, W, H) end
    map.renderer:draw(cx, cy, W, H)
    if map.renderer.drawAbove then map.renderer:drawAbove(cx, cy, W, H) end
  end)
  if not ok and not self.mapErrLogged then
    self.mapErrLogged = true
    require("src.core.Logger").warn("gen3 frlg credits: map draw failed: %s", tostring(err))
  end
  -- BLDY 10: the backgrounds darkened ten sixteenths toward black
  g.setColor(0, 0, 0, 10 / 16)
  g.rectangle("fill", 0, 0, W, H)
end

function C:drawSprite()
  local s = self.sprite
  if not s then return end
  local g = love.graphics
  g.setColor(1, 1, 1, 1)
  if s.ground then
    local f = s.running and (math.floor(self.frame / 8) % s.groundFrames) or 0
    local q = g.newQuad(f * 64, 0, 64, 32, s.ground:getDimensions())
    g.draw(s.ground, q, math.floor(s.x - 32), math.floor(s.y + 38 - 16))
  end
  if s.char then
    local f = math.floor(self.frame / 8) % s.charFrames
    local q = g.newQuad(f * 64, 0, 64, 64, s.char:getDimensions())
    g.draw(s.char, q, math.floor(s.x - 32), math.floor(s.y - 32))
  end
end

function C:drawText()
  if self.textAlpha <= 0 then return end
  local g = love.graphics
  local t = self.titleText or {}
  g.setColor(1, 1, 1, self.textAlpha)
  local faced = Font.pushFace and Font.pushFace("small")
  Font.pushStyle({ text = { 0.97, 0.75, 0.33 }, shadow = { 0.3, 0.2, 0.1 } })
  local y = 32 + 6
  for piece in ((t.title or "") .. "\n"):gmatch("([^\n]*)\n") do
    if piece ~= "" then Font.draw(piece, 2, y) end
    y = y + 16
  end
  Font.popStyle()
  Font.pushStyle({ text = { 1, 1, 1 }, shadow = { 0.35, 0.35, 0.35 } })
  y = 32 + 6
  for piece in ((t.names or "") .. "\n"):gmatch("([^\n]*)\n") do
    if piece ~= "" then Font.draw(piece, 8, y) end
    y = y + 16
  end
  Font.popStyle()
  if faced and Font.popFace then Font.popFace() end
  g.setColor(1, 1, 1, 1)
end

function C:draw()
  local g = love.graphics
  g.setColor(0, 0, 0, 1)
  g.rectangle("fill", 0, 0, W, H)
  if self.phase == "mon" and self.mon then
    local m = self.mon
    g.setColor(1, 1, 1, 1)
    if m.t < MON_REVEAL then
      -- the white circle closing in on the ball
      local k = math.max(0, math.min(1, (m.t - MON_CIRCLE_SHRINK) / 16))
      local r = 40 + (1 - k) * 200
      g.setColor(1, 1, 1, 1)
      g.circle("fill", 120, 80, r)
    else
      if m.ball then g.draw(m.ball, 0, 0) end
    end

    -- Each PutWindowTilemap call replaces the previous rectangular window;
    -- draw only the active pose rather than compositing all three pictures.
    local pose
    if m.t >= MON_POSE2 then pose = m.poses[2]
    elseif m.t >= MON_POSE1 then pose = m.poses[1] end
    if pose and pose.img then
      g.draw(pose.img, pose.x, pose.y)
    elseif m.img then
      local w, h = m.img:getDimensions()
      g.draw(m.img, math.floor(120 - w / 2), math.floor(80 - h / 2))
    end
  elseif (self.phase == "end") and self.endImg then
    g.setColor(1, 1, 1, 1)
    g.draw(self.endImg, 0, 0)
  else
    self:drawMap()
    self:drawSprite()
    -- WIN0: only the band shows the scene
    g.setColor(0, 0, 0, 1)
    g.rectangle("fill", 0, 0, W, self.bandTop or 36)
    g.rectangle("fill", 0, self.bandBottom or 124, W, H - (self.bandBottom or 124))
    self:drawText()
  end
  if self.fade < 1 then
    g.setColor(0, 0, 0, 1 - self.fade)
    g.rectangle("fill", 0, 0, W, H)
  end
  if self.phase == "white" then
    g.setColor(1, 1, 1, 1 - self.timer / 16)
    g.rectangle("fill", 0, 0, W, H)
  end
  g.setColor(1, 1, 1, 1)
end

function C:keypressed() end

return C
