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
-- Native panels are separate in dual-screen mode; single-screen mode overlays
-- the logo on the animated Giratina panel.

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
  { name = "fadeIn",    frames = 45 },   -- 15 fade steps, three frames per step
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
  { name = "settle",    frames = 90 },
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

function Gen4Title:uiSize()
  local mode=require('src.ui.SecondScreen').mode(self.game)
  return (mode=='display' or mode=='inset') and W or W*2,
         (mode=='display' or mode=='inset') and H or H*2
end
function Gen4Title:wantsFillScale() return true end
function Gen4Title:wantsEdgeBleed() return false end

function Gen4Title:sgbPalettes()
  local P = require("src.render.PaletteFX")
  local w,h=self:uiSize()
  return { P.trueColorZone(0, 0, math.ceil(w / 8) - 1, math.ceil(h / 8) - 1) }
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
    self.openingModels = {}
    self.giraMaterials = {}
    for _, record in ipairs(set.models or {}) do
      if record.name == "title_gira" then
        self.gira = Gen4Model.new(record)
      elseif record.name == 'op_ana' or record.name == 'op_kao' then
        self.openingModels[record.name] = {model=Gen4Model.new(record),materials={}}
      end
    end
    for _, anim in ipairs(set.animations or {}) do
      local opening=self.openingModels[anim.name]
      if opening then
        if anim.tracks then
          opening.tracks={};opening.frames=anim.frames or 1
          for _,track in ipairs(anim.tracks) do opening.tracks[track.index]=track end
        else opening.materials[#opening.materials+1]=anim end
      end
      if anim.name == "title_gira" and anim.srt then
        self.giraMaterials[#self.giraMaterials + 1] = anim
      end
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
  return (not self.intro) or self:beat() == 'settle'
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

-- Average all four source pixels at half size instead of dropping three.
-- Remove bright outer-edge pixels before averaging; the white lettering's
-- interior remains intact. Work in premultiplied colour to avoid alpha halos.
function Gen4Title:drawSmallLogo(logo)
  local g=love.graphics
  if not self.logoShader then
    self.logoShader=g.newShader([[
      extern vec2 pixel;
      extern number sampleSpan;
      vec4 clean(Image image, vec2 uv) {
        vec4 p=Texel(image,uv);
        float edge=min(min(Texel(image,uv+vec2(pixel.x,0.0)).a,
                          Texel(image,uv-vec2(pixel.x,0.0)).a),
                       min(Texel(image,uv+vec2(0.0,pixel.y)).a,
                          Texel(image,uv-vec2(0.0,pixel.y)).a));
        if (min(p.r,min(p.g,p.b))>0.8 && edge<0.01) p.a=0.0;
        return vec4(p.rgb*p.a,p.a);
      }
      vec4 effect(vec4 color, Image image, vec2 uv, vec2 position) {
        vec4 p=(clean(image,uv+pixel*vec2(-sampleSpan,-sampleSpan))+
                clean(image,uv+pixel*vec2(sampleSpan,-sampleSpan))+
                clean(image,uv+pixel*vec2(-sampleSpan,sampleSpan))+
                clean(image,uv+pixel*vec2(sampleSpan,sampleSpan)))*0.25;
        return vec4(p.a>0.0 ? p.rgb/p.a : vec3(0.0),p.a)*color;
      }
    ]])
  end
  local previous=g.getShader();local w,h=logo:getDimensions()
  self.logoShader:send('pixel',{1/w,1/h});g.setShader(self.logoShader)
  self.logoShader:send('sampleSpan',self.highResolution and 0 or 0.5)
  g.draw(logo,W/4,0,0,0.5,0.5);g.setShader(previous)
end

function Gen4Title:enter()
  self.frame, self.opened = 0, false
  local data = self.game.data
  local songs = data and data.audio and data.audio.songs
  local id = data and data.gen4_menus and data.gen4_menus.titleSong
  id = id or (data.audio and data.audio.special and data.audio.special.title)
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

function Gen4Title:update(dt)
  -- updated again with the flag still set means the menu was backed out of
  if self.opened then self:resume() end
  -- Platinum advances its application/animation clock at 30 Hz.
  local speed=self.game.logicSpeed and self.game:logicSpeed() or 1
  self.frameRemainder=(self.frameRemainder or 0)+(dt or 1/60)*30/math.max(1,speed)
  local ticks=math.floor(self.frameRemainder+1e-9)
  self.frameRemainder=self.frameRemainder-ticks
  self.frame = self.frame + ticks
  self.blink = (self.blink + ticks) % 90
  if self.lockout > 0 then self.lockout = math.max(0,self.lockout - ticks) end
  -- The intro is over when its last beat is, and the frame counter restarts so
  -- the logo's own fade and the prompt's timing read from there.
  if self.intro and self.frame >= INTRO_FRAMES then
    self.giraPhaseOffset=self:giraTime()
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
  elseif name == nil or name == 'settle' then k = 1 end
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
function Gen4Title:giraTime()
  if not self.intro then return self.frame+(self.giraPhaseOffset or 0) end
  local before=0
  for _,step in ipairs(TIMELINE) do
    if step.name=='fromWhite' then break end
    before=before+step.frames
  end
  return math.max(0,self.frame-before)
end

function Gen4Title:giraFrame()
  if not self.giraFrames or self.giraFrames<1 then return 0 end
  return self:giraTime()%self.giraFrames
end

-- The model, into a canvas of its own with a depth buffer -- the UI surface
-- has none, and a 996-triangle model drawn without one comes out inside out.
function Gen4Title:drawGiratina()
  if not self.gira or self.noDepth then return nil end
  local resolution=self.highResolution and 2 or 1
  if not self.colour or self.modelResolution~=resolution then
    self.colour, self.depth = Gen4Model.newTarget(W*resolution, H*resolution)
    self.modelResolution=resolution
    if not self.colour then self.noDepth = true return nil end
  end

  local g = love.graphics
  local previous = { g.getCanvas() }
  g.setCanvas({ self.colour, depthstencil = self.depth })
  g.clear(0, 0, 0, 0, true, true)

  local beat=self:beat()
  if self.intro and (beat=='fadeIn' or beat=='portal' or beat=='flashUp1' or beat=='flashDown1'
      or beat=='flashUp2' or beat=='flashDown2' or beat=='toWhite') and next(self.openingModels or {}) then
    local frame=self.frame
    local pitch=math.rad(319.94)
    local z=math.max(0,37.5-frame*0.625)
    local target={0,0,z}
    local eye={0,-math.sin(pitch)*160,math.cos(pitch)*160+z}
    local vp=Gen4Model.multiply(FLIP_Y,Gen4Model.multiply(
      Gen4Model.perspective(math.rad(43.988),W/H,1,4000),Gen4Model.lookAt(eye,target)))
    for _,name in ipairs({'op_ana','op_kao'}) do
      local record=self.openingModels[name]
      local at=name=='op_kao' and frame-75 or frame
      if record and at>=0 and (name~='op_kao' or at<(record.frames or 174)) then
        at=at%(record.frames or 240)
        local pose=record.model:posed(function(node)
          local track=record.tracks and record.tracks[node]
          return track and Gen4Anim.unpackFrame(track.matrices,at) or nil
        end)
        record.model:draw(vp,pose,require('src.render.Gen4TexAnim').materials(record.materials,at))
      end
    end
    g.setCanvas(previous[1] and previous or nil)
    return self.colour
  end

  local frame = self:giraFrame()
  local tracks = self.giraTracks
  local pose = self.gira:posed(function(node)
    local track = tracks and tracks[node]
    return track and Gen4Anim.unpackFrame(track.matrices, frame) or nil
  end)

  local projection = Gen4Model.perspective(CAM_FOV, W / H, 1, 4000)
  local view = Gen4Model.lookAt(self:cameraEye(), CAM_TARGET)
  self.gira:draw(Gen4Model.multiply(FLIP_Y,
                                    Gen4Model.multiply(projection, view)), pose,
      require("src.render.Gen4TexAnim").materials(self.giraMaterials, self:giraTime()))

  g.setCanvas(previous[1] and previous or nil)
  return self.colour
end

-- The white and black the intro fades through, as one number.
--
-- Positive is white over the scene and negative is black, which lets the whole
-- eleven-state sequence be one lookup instead of two flags: every one of its
-- beats is a ramp between the picture and one of those two colours.
-- The light on Giratina, following `light1State`: DEFAULT while the portal
-- turns, BRIGHTEN through each white flash, DARKEN after it.
function Gen4Title:giraLight()
  if not self.intro then return GIRA_LIT end
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

function Gen4Title:drawPanel(bottom, merged)
  local g = love.graphics
  g.setColor(0, 0, 0, 1)
  g.rectangle("fill", 0, 0, W, H)
  local panels = self:panelsVisible()
  local backdrop = self:img(bottom and "bottomBorder" or "topBorder")
  g.setColor(1, 1, 1, 1)
  if backdrop then g.draw(backdrop, 0, 0) end
  if bottom then
    local scene = self:drawGiratina()
    if scene then
      local lit = self:giraLight()
      g.setColor(lit, lit, lit, 1)
      local scale=1/(self.modelResolution or 1)
      g.draw(scene, 0, 0,0,scale,scale)
    end
    if panels and not merged then
      local copyright = self:img("copyright")
      g.setColor(1, 1, 1, 1)
      if copyright then
        -- Older imports flattened this layer onto black. On the DS palette
        -- index zero is transparent, so that field must not cover Giratina.
        self.copyShader = self.copyShader or g.newShader([[
          vec4 effect(vec4 colour, Image tex, vec2 uv, vec2 screen) {
            vec4 pixel = Texel(tex, uv);
            if (max(pixel.r, max(pixel.g, pixel.b)) < 0.01) discard;
            return pixel * colour;
          }
        ]])
        local previous = g.getShader()
        g.setShader(self.copyShader)
        g.draw(copyright, 0, 0)
        g.setShader(previous)
      end
    end
  end
  if panels and (not bottom or merged) then
    local logo = self:img("logo")
    g.setColor(1, 1, 1, 1)
    if logo then
      if merged then self:drawSmallLogo(logo)
      else g.draw(logo, 0, 0) end
    end
    if self.frame >= T_READY and self.frame % 32 < 16 then
      local text = Strings("PRESS START")
      g.setColor(21 / 31, 0, 0, 1)
      Font.draw(text, math.floor((W - Font.width(text)) / 2), 152)
    end
  end
  local veil = self:veil()
  if veil ~= 0 then
    if veil > 0 then g.setColor(1, 1, 1, veil) else g.setColor(0, 0, 0, -veil) end
    g.rectangle("fill", 0, 0, W, H)
  end
  g.setColor(1, 1, 1, 1)
end

function Gen4Title:draw()
  local SecondScreen = require("src.ui.SecondScreen")
  local mode = SecondScreen.mode(self.game)
  local dual = mode == "display" or mode == "inset"
  self.highResolution=not dual
  if not dual then love.graphics.push();love.graphics.scale(2,2) end
  self:drawPanel(not dual, not dual)
  if not dual then love.graphics.pop() end
  if dual then SecondScreen.draw(self.game, function() self:drawPanel(true, false) end) end
end

return Gen4Title
