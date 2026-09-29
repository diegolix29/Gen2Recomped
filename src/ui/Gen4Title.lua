-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Platinum's title screen.
--
-- Four pictures out of `/demo/title/titledemo.narc`, each composed by the
-- graphics stage and named by role in `gen4_menus.title`:
--
--   top_screen_border     the ragged white field the logo sits in
--   logo                  POKéMON PLATINUM VERSION
--   copyright             the four (c) lines, on black
--   bottom_screen_border  the dark field those lines sit on
--
-- ONE SCREEN OUT OF TWO, and deliberately.  A DS title is two panels: the logo
-- above, the copyright below.  This engine draws one surface, and the dual
-- screen work (the Poketch toggle and the corner overlay) is designed and not
-- built -- so the two are composed into one 256x192 screen here rather than the
-- copyright being dropped.  When the second screen exists, this file splits
-- along the seam the two borders already mark.
--
-- WHAT IS MISSING IS NAMED RATHER THAN FAKED.  The centrepiece of the real
-- title is Giratina, an NSBMD model turning behind the logo, and there is no 3D
-- path yet.  So the logo sits on the border field alone.  Nothing here draws a
-- substitute for it.

local Assets = require("src.render.Assets")
local Font = require("src.render.Font")
local Music = require("src.core.Music")
local Screens = require("src.ui.Screens")
local Strings = require("src.core.Strings")
local Gen4Anim = require("src.import.Gen4Anim")
local Gen4Model = require("src.render.Gen4Model")
local Logger = require("src.core.Logger")

local Gen4Title = {}
Gen4Title.__index = Gen4Title
Gen4Title.isOpaque = true

local W, H = 256, 192

-- WHERE THE TWO PANELS MEET IS MEASURED, NOT PICKED.
--
-- Every sheet in this archive is 256x192 or 256x256 and most of it is empty:
-- the logo's artwork occupies rows 27 to 148 of its own sheet and the
-- copyright's four lines rows 64 to 119.  Drawn at 0,0 on the sheet size the
-- logo lands forty rows low and "VERSION" is cut off at the seam -- which looks
-- like a layout choice rather than a measurement nobody took.
--
-- So the menus stage measures each picture's content box and this splits the
-- screen by what has to fit in each half: the logo's height above, the
-- copyright block's below, and the slack shared between them.  A cache with no
-- boxes falls back to the sheet drawn as it stands, which is the old behaviour
-- rather than a crash.
local FALLBACK_SPLIT = 129

-- THE BAND PRESS START GETS, and it has to be taken out of the screen before
-- the two panels are measured rather than found afterwards.
--
-- The comment below used to say PRESS START is drawn "in the copyright strip
-- where nothing else is", and that was true of the strip and false of the
-- copyright: the four (c) lines are 56 rows and they are centred in that
-- strip, so `H - 20` lands on the third of them.  On screen the words sat
-- across "(c)1995-2009 GAME FREAK inc.", which is what was reported.
--
-- Fourteen rows, because that is exactly what the screen has spare: the
-- logo's content is 122 rows and the copyright's 56, and 122 + 56 + 14 is
-- 192.  The two panels therefore keep every row they need and PRESS START
-- gets the slack instead of borrowing a panel's.
local PRESS_BAND = 14

-- Frames, engine step.  The cartridge fades the logo up out of the border
-- field; the beats here are that fade and nothing invented around it.
local T_FADE = 24
local T_READY = 40

-- ---------------------------------------------------------------------------
-- THE INTRO, ON THE CARTRIDGE'S OWN FRAME COUNTS
-- ---------------------------------------------------------------------------
--
-- `TitleScreen_ShowIntro` is eleven states and every number below is one of
-- its delays, read out of applications/title_screen.c rather than timed off a
-- video.  In order: fade in from black, hold nine seconds while the portal
-- turns, two white flashes, a fade out to white, the logo's layer on and
-- Giratina's animation started, a beat of black, the slow reveal, and the
-- camera moving in -- and the logo and the copyright are the LAST things to
-- appear, which is why the title is a sequence and not a picture.
local TIMELINE = {
  { name = "fadeIn",    frames = 15 },   -- FADE_FROM_BLACK, step 3
  { name = "portal",    frames = 267 },  -- the delay in that same state
  { name = "flashUp1",  frames = 10 },   -- two white flashes, 10 frames each
  { name = "flashDown1", frames = 10 },
  { name = "flashUp2",  frames = 10 },
  { name = "flashDown2", frames = 10 },
  { name = "toWhite",   frames = 5 },    -- WAIT_AND_FADE_TO_WHITE_2, step 2
  { name = "fromWhite", frames = 16 },   -- logo BG2 on, the animation starts
  { name = "hold",      frames = 10 },   -- main to black
  { name = "reveal",    frames = 48 },   -- FADE_MAIN_FROM_BLACK, step 1
  { name = "camera",    frames = 60 },   -- TITLE_CAM_MOVE_IN_FRAMES
}

local INTRO_FRAMES = 0
for _, step in ipairs(TIMELINE) do INTRO_FRAMES = INTRO_FRAMES + step.frames end

-- How long the inputs stay dead after arriving with no intro, so a button
-- held through the menu cannot fall straight back through the title.
local INPUT_DISABLE_FRAMES = 30

-- Idle frames before the title goes back to the opening.  On the cartridge
-- that is `TITLE_SCREEN_REPLAY_OPENING_FRAMES`: the title is an ATTRACT LOOP,
-- not a still, and a player who walks away gets the cutscene again.  This port
-- has no cutscene yet, so it replays the part it does have -- the title's own
-- intro -- which is the same loop with one shot missing rather than a loop
-- that does not exist.
local REPLAY_FRAMES = 900

-- THE TITLE CAMERA, both ends of it.  Interpolated linearly over the sixty
-- frames of the move -- `TitleScreen_UpdateTitleCam` adds (end - start) / 60
-- every frame, which is a straight line -- with the target fixed throughout.
local CAM_START_EYE = { 0, 192, 600 }
local CAM_END_EYE = { -64, 192, 484 }
local CAM_TARGET = { 0, 100, -18 }
-- THE CARTRIDGE'S FOV IS A HALF-ANGLE, and reading it as the whole one drew
-- Giratina at twice his size -- a close-up of one gold stripe filling the
-- screen, which is what was reported.
--
-- `Camera_Init` keeps `sinFovY` and `cosFovY` of the value passed in, and
-- `Camera_ComputeProjectionMatrix`'s orthographic branch is what settles it:
-- `top = tan(fovY) * distance`, and `top` is the HALF height of the frustum.
-- So the full vertical angle is twice the 15.996 degrees the title screen
-- hands `Camera_InitWithTargetAndPosition`.
local CAM_FOV = math.rad(15.996 * 2)

-- CLIP Y POINTS THE OTHER WAY INTO A CANVAS.
--
-- Reported: "Giratina is showing ... upside down". A custom `position()` in a
-- LOVE shader returns clip coordinates directly, which bypasses the projection
-- LOVE would otherwise set up for the target -- and a canvas's framebuffer
-- counts its rows the opposite way round from the screen. `Gen4Model.orbit`
-- does not hit this because the starter select composes it with a Z-up-to-Y-up
-- rotation that inverts the axis on the way past; a plain `lookAt` has nothing
-- to hide it.
--
-- Negating clip Y rather than the up vector on purpose: flipping `up` would
-- also swap the handedness of the side vector and mirror him left to right,
-- which trades one wrong picture for another.
local FLIP_Y = {
  1, 0, 0, 0,
  0, -1, 0, 0,
  0, 0, 1, 0,
  0, 0, 0, 1,
}

-- HOW DARK GIRATINA IS.
--
-- On the cartridge he is a shape in a portal, not a lit model: the title runs
-- its own light through `light1State`, which starts at DEFAULT, goes BRIGHTEN
-- on each white flash of the intro and DARKEN after it. None of that lighting
-- model is ported, and drawing the textures at full strength is why he came
-- out "in full color" instead.
--
-- So this is a TINT standing in for a light, and it is one number rather than
-- a pretence at the real thing. It follows the same beats the cartridge's
-- light does, which is the part that is actually the cartridge's.
-- HE IS A SILHOUETTE, and that is the reported correction rather than a
-- preference: "hes usually a sillouette compare the rom". A third of full
-- strength still reads as a brown and gold Giratina; the cartridge's is a dark
-- shape in the portal with the light behind him, and the flashes are what
-- briefly show his colours.
local GIRA_DARK = 0.12
local GIRA_LIT = 1.0

-- WHETHER THE NEXT TITLE PLAYS ITS INTRO.  `gSystem.showTitleScreenIntro` on
-- the cartridge: set when the opening cutscene has just run (or the attract
-- timer fired), cleared when the player skipped it.  Module state rather than
-- an option, because it is a fact about this boot and not a preference.
Gen4Title.showIntro = true

function Gen4Title:uiSize() return W, H end
function Gen4Title:wantsFillScale() return true end
function Gen4Title:wantsEdgeBleed() return false end

function Gen4Title:sgbPalettes()
  local P = require("src.render.PaletteFX")
  return { P.trueColorZone(0, 0, math.ceil(W / 8) - 1, math.ceil(H / 8) - 1) }
end

function Gen4Title.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, Gen4Title)
  self.game = game
  self.onNewGame, self.onContinue = opts.onNewGame, opts.onContinue
  local menus = game.data and game.data.gen4_menus
  self.art = (menus and menus.title) or {}
  self.cache = {}
  self.frame = 0
  self.blink = 0
  self.opened = false

  -- GIRATINA, WHICH IS THE CENTREPIECE AND WAS THE ONE THING NAMED AS ABSENT.
  --
  -- `titledemo.narc` member 1 is `title_gira`: four shapes, 996 triangles,
  -- carrying its own textures, with a 121-frame joint animation beside it in
  -- member 2.  Both are paired BY NAME rather than by position, because they
  -- sit in different members and nothing else says they belong together --
  -- the same rule the starter case is loaded under.
  local set = ((game.data or {}).gen4_models or {}).sets
  set = set and set.title
  if set then
    for _, record in ipairs(set.models or {}) do
      if record.name == "title_gira" then
        self.gira = Gen4Model.new(record)
      end
    end
    for _, anim in ipairs(set.animations or {}) do
      if anim.name == "title_gira" and anim.tracks then
        self.giraTracks = {}
        for _, track in ipairs(anim.tracks) do
          self.giraTracks[track.index] = track
        end
        self.giraFrames = anim.frames or 1
      end
    end
  end
  if not self.gira then
    -- Named, not silent: a cache from before the title archive was extracted
    -- still shows the logo, and the difference has to be visible in the log
    -- rather than looking like a render that failed.
    Logger.warn("gen4 title: this cache carries no `title_gira` model -- the "
                .. "logo will be shown with nothing behind it")
  end

  -- A title reached from the menu is not a title reached from the opening.
  self.intro = Gen4Title.showIntro and self.gira ~= nil
  Gen4Title.showIntro = false
  self.lockout = self.intro and 0 or INPUT_DISABLE_FRAMES

  return self
end

-- Which beat of the intro this frame is, and how far through it.
-- Returns nil once the intro is over, which is what every `if self.intro`
-- below tests.
function Gen4Title:beat()
  if not self.intro then return nil end
  local at = self.frame
  for _, step in ipairs(TIMELINE) do
    if at < step.frames then
      return step.name, (step.frames > 0) and (at / step.frames) or 1
    end
    at = at - step.frames
  end
  return nil
end

-- How far into the intro the logo and the copyright are allowed to be drawn:
-- the cartridge turns their layers on at the END of the camera move.
function Gen4Title:panelsVisible()
  return (not self.intro) or self.frame >= INTRO_FRAMES
end

-- The picture, and the record that says where its artwork sits inside it.
-- The record is `{ path, width, height, content = { x, y, w, h } }`; an older
-- cache wrote a bare path string, which still resolves and simply has no box.
function Gen4Title:img(key)
  local rec = self.art[key]
  local path = (type(rec) == "table" and rec.path) or rec
  if type(path) ~= "string" then return nil end
  if self.cache[path] == nil then
    local ok, img = pcall(Assets.image, path)
    self.cache[path] = ok and img or false
    if self.cache[path] then self.cache[path]:setFilter("nearest", "nearest") end
  end
  local img = self.cache[path] or nil
  if not img then return nil end
  return img, (type(rec) == "table" and rec.content) or nil
end

-- How tall the logo panel is.  Both halves are sized by what must fit in them,
-- and the rows neither needs are split between them.
-- How tall the logo panel is, and where the copyright panel ends.
--
-- Three bands now, not two: the logo, the copyright, and the row PRESS START
-- is drawn on.  A cache with no content boxes keeps the old fallback and the
-- old behaviour.
function Gen4Title:split()
  local _, logoBox = self:img("logo")
  local _, copyBox = self:img("copyright")
  if not (logoBox and copyBox) then return FALLBACK_SPLIT, H - PRESS_BAND end
  local usable = H - PRESS_BAND
  local slack = usable - logoBox.h - copyBox.h
  if slack < 0 then return FALLBACK_SPLIT, H - PRESS_BAND end
  return logoBox.h + math.floor(slack / 2), usable
end

-- The title theme, if the audio stage has run.  Gen 4 songs are not extracted
-- yet, so this is a no-op on every current cache -- written now so it starts
-- working the day they are, rather than being a thing to remember later.
function Gen4Title:enter()
  self.frame, self.opened = 0, false
  local data = self.game.data
  local songs = data and data.audio and data.audio.songs
  local id = data and data.gen4_menus and data.gen4_menus.titleSong
  if id and songs and songs[id] then pcall(Music.play, data, id) end
end

function Gen4Title:resume()
  self.opened = false
end

function Gen4Title:openMenu()
  if self.opened then return end
  self.opened = true
  Screens.push(self.game, "Gen4MainMenu", {
    onNewGame = self.onNewGame,
    onContinue = self.onContinue,
  })
end

function Gen4Title:update()
  -- updated again with the flag still set means the menu was backed out of
  if self.opened then self:resume() end
  self.frame = self.frame + 1
  self.blink = (self.blink + 1) % 90
  if self.lockout > 0 then self.lockout = self.lockout - 1 end
  -- The intro is over when its last beat is, and the frame counter restarts so
  -- the logo's own fade and the prompt's timing read from there.
  if self.intro and self.frame >= INTRO_FRAMES then
    self.intro = false
    self.frame = 0
  end
  -- The attract loop.
  if not self.intro and self.gira and self.frame >= REPLAY_FRAMES then
    self.intro = true
    self.frame = 0
    self.lockout = 0
  end
  local input = self.game.input
  if not input then return end
  if input:wasPressed("start") or input:wasPressed("a") then
    if self.lockout > 0 then
      -- Deliberately swallowed: the cartridge kills input for thirty frames
      -- after a title it did not introduce.
      return
    end
    if self.intro then
      -- THIS PORT'S, AND SAID SO.  Platinum does not let you out of the title
      -- intro at all -- only the opening cutscene before it is skippable -- but
      -- a window the player just alt-tabbed back into is not an attract mode,
      -- and eight seconds with no way past reads as a hang.
      self.intro = false
      self.frame = T_READY
    elseif self.frame < T_READY then
      -- skip the fade rather than swallowing the press
      self.frame = T_READY
    else
      self:openMenu()
    end
  end
end

-- ------------------------------------------------------------------ giratina

-- Where the camera is this frame.  Fixed at the start of the shot until the
-- move begins, then a straight line to the end over sixty frames.
function Gen4Title:cameraEye()
  local name, progress = self:beat()
  local k = 0
  if name == "camera" then k = progress
  elseif name == nil then k = 1 end
  return {
    CAM_START_EYE[1] + (CAM_END_EYE[1] - CAM_START_EYE[1]) * k,
    CAM_START_EYE[2] + (CAM_END_EYE[2] - CAM_START_EYE[2]) * k,
    CAM_START_EYE[3] + (CAM_END_EYE[3] - CAM_START_EYE[3]) * k,
  }
end

-- The animation frame Giratina is on.  It does not start until the cartridge
-- starts it -- `GIRATINA_ANIM_STATE_PLAY` is set in the state that fades the
-- main screen back from white -- so before that it holds on frame zero and
-- the portal alone is moving.
function Gen4Title:giraFrame()
  if not self.giraFrames or self.giraFrames < 1 then return 0 end
  if not self.intro then return self.frame % self.giraFrames end
  local before = 0
  for _, step in ipairs(TIMELINE) do
    if step.name == "fromWhite" then break end
    before = before + step.frames
  end
  if self.frame < before then return 0 end
  return (self.frame - before) % self.giraFrames
end

-- The model, into a canvas of its own with a depth buffer -- the UI surface
-- has none, and a 996-triangle model drawn without one comes out inside out.
function Gen4Title:drawGiratina()
  if not self.gira or self.noDepth then return nil end
  if not self.colour then
    self.colour, self.depth = Gen4Model.newTarget(W, H)
    if not self.colour then self.noDepth = true return nil end
  end

  local g = love.graphics
  local previous = { g.getCanvas() }
  g.setCanvas({ self.colour, depthstencil = self.depth })
  g.clear(0, 0, 0, 0, true, true)

  local frame = self:giraFrame()
  local tracks = self.giraTracks
  local pose = self.gira:posed(function(node)
    local track = tracks and tracks[node]
    return track and Gen4Anim.unpackFrame(track.matrices, frame) or nil
  end)

  local projection = Gen4Model.perspective(CAM_FOV, W / H, 1, 4000)
  local view = Gen4Model.lookAt(self:cameraEye(), CAM_TARGET)
  self.gira:draw(Gen4Model.multiply(FLIP_Y,
                                    Gen4Model.multiply(projection, view)), pose)

  g.setCanvas(previous[1] and previous or nil)
  return self.colour
end

-- Draw a picture's content box into a band, centred vertically in it.  Where
-- no box was measured the sheet is drawn as it stands, clipped to the band.
local function drawInBand(img, box, top, height, alpha)
  local g = love.graphics
  g.setColor(1, 1, 1, alpha or 1)
  local iw, ih = img:getDimensions()
  if box then
    local quad = g.newQuad(0, box.y, math.min(W, iw), math.min(box.h, ih - box.y),
                           iw, ih)
    g.draw(img, quad, 0, top + math.floor((height - box.h) / 2))
  else
    local quad = g.newQuad(0, 0, math.min(W, iw), math.min(height, ih), iw, ih)
    g.draw(img, quad, 0, top)
  end
  g.setColor(1, 1, 1, 1)
end

-- The white and black the intro fades through, as one number.
--
-- Positive is white over the scene and negative is black, which lets the whole
-- eleven-state sequence be one lookup instead of two flags: every one of its
-- beats is a ramp between the picture and one of those two colours.
-- The light on Giratina, following `light1State`: DEFAULT while the portal
-- turns, BRIGHTEN through each white flash, DARKEN after it.
function Gen4Title:giraLight()
  local name, k = self:beat()
  if name == "flashUp1" or name == "flashUp2" or name == "toWhite" then
    return GIRA_DARK + (GIRA_LIT - GIRA_DARK) * k
  end
  if name == "flashDown1" or name == "flashDown2" then
    return GIRA_DARK + (GIRA_LIT - GIRA_DARK) * (1 - k)
  end
  return GIRA_DARK
end

function Gen4Title:veil()
  local name, k = self:beat()
  if name == nil then return 0 end
  if name == "fadeIn" then return -(1 - k) end
  if name == "portal" then return 0 end
  if name == "flashUp1" or name == "flashUp2" then return k end
  if name == "flashDown1" or name == "flashDown2" then return 1 - k end
  if name == "toWhite" then return k end
  if name == "fromWhite" then return 1 - k end
  if name == "hold" then return -1 end
  if name == "reveal" then return -(1 - k) end
  return 0
end

function Gen4Title:draw()
  local g = love.graphics
  g.setColor(0, 0, 0, 1)
  g.rectangle("fill", 0, 0, W, H)

  local split, footer = self:split()
  local panels = self:panelsVisible()

  -- THE LAYER ORDER IS THE CARTRIDGE'S: the field is the backdrop, Giratina is
  -- drawn into it, and the logo goes on top of both.  `ToggleGiratinaBgLayer`
  -- comes on before the camera move and `ToggleLogoLayer` only at the end of
  -- it, which is the order below.
  --
  -- The field is clipped at the seam during the title proper and covers the
  -- whole screen during the intro, when there is no copyright panel yet.
  local border = self:img("topBorder")
  if border then
    g.setColor(1, 1, 1, 1)
    local cut = panels and split or H
    g.setScissor()
    local sx, sy = g.transformPoint(0, 0)
    local ex, ey = g.transformPoint(W, cut)
    g.setScissor(math.floor(sx), math.floor(sy),
                 math.max(0, math.ceil(ex - sx)), math.max(0, math.ceil(ey - sy)))
    g.draw(border, 0, 0)
    g.setScissor()
  end

  local scene = self:drawGiratina()
  if scene then
    local lit = self:giraLight()
    g.setColor(lit, lit, lit, 1)
    g.draw(scene, 0, 0)
    g.setColor(1, 1, 1, 1)
  end

  local logo, logoBox = self:img("logo")
  if logo and panels then
    drawInBand(logo, logoBox, 0, split, math.min(1, self.frame / T_FADE))
  end

  -- the copyright strip
  -- The dark field runs to the bottom of the screen -- PRESS START sits ON it
  -- -- but the copyright is confined to its own band above the footer.
  -- `and ... or nil` AROUND A TWO-VALUE CALL KEEPS ONLY THE FIRST, and that
  -- is what put a black bar across the bottom of the title.
  --
  -- `img` returns the picture AND its measured content box. Wrapping the call
  -- in `panels and ... or nil` truncates the expression to one value, so
  -- `copyBox` came back nil, `drawInBand` fell to its no-box branch and drew
  -- the sheet from row 0 -- and the copyright's four lines live at rows 64 to
  -- 119 of a 256-row sheet, so what landed in the band was the empty top of
  -- it. The picture was there and the wrong 56 rows of it were shown.
  local bottom = self:img("bottomBorder")
  if panels and bottom then
    g.setColor(1, 1, 1, 1)
    local iw, ih = bottom:getDimensions()
    local quad = g.newQuad(0, 0, math.min(W, iw), math.min(H - split, ih), iw, ih)
    g.draw(bottom, quad, 0, split)
  end
  local copyright, copyBox = self:img("copyright")
  if panels and copyright then
    drawInBand(copyright, copyBox, split, math.max(0, footer - split), 1)
  end

  -- PRESS START is this port's, not the cartridge's -- Platinum simply waits.
  -- A window with no hardware START button needs to say which key opens the
  -- menu, and it gets the footer band of its own rather than the copyright's
  -- rows.
  if panels and self.frame >= T_READY and self.blink < 60 then
    g.setColor(1, 1, 1, 1)
    local text = Strings("PRESS START")
    local width = Font.width(text)
    local y = footer + math.floor((H - footer - Font.glyphHeight()) / 2)
    Font.draw(text, math.floor((W - width) / 2), math.max(footer, y))
  end
  g.setColor(1, 1, 1, 1)

  -- ...and the intro's fade over the lot of it.
  local veil = self:veil()
  if veil ~= 0 then
    if veil > 0 then g.setColor(1, 1, 1, veil) else g.setColor(0, 0, 0, -veil) end
    g.rectangle("fill", 0, 0, W, H)
    g.setColor(1, 1, 1, 1)
  end
end

return Gen4Title
