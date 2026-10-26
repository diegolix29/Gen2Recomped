-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE MAHOGANY HIDEOUT'S TWO PICTURES (HeartGold / SoulSilver, D35R0102):
-- the floor trap going off under the player (ScrCmd_708) and the Persian
-- statues' alarm (ScrCmd_709).  The sounds always played; these are what the
-- cartridge draws while they do.
--
-- READ FROM CODE (pokeheartgold):
--   ScrCmd_708 <n>   src/field/scrcmd_pokemon_misc.c -> ov02_022460AC
--                    (asm/overlay_02_02245B80.s): TaskManager_Call, so the
--                    script waits for the task.  Its table ov02_02253264, 12
--                    bytes a row { u16 narc 0xAE, u8 model, u8 animCount,
--                    anim list, u16 SE }:
--                      0  model 10 asito_thunder  anims {11}     DENKI_TRAP
--                      1  model  3 asito_poison   anims {4, 5}   DOKU_TRAP
--                      2  model  6 asito_rock     anims {7, 8, 9} IWA_TRAP
--                    State 0: the model at the player's position
--                    (PlayerAvatar_CopyPositionVector), the SE; state 1:
--                    every animation advanced FX32_ONE a frame until all
--                    have ended (ov02_02245FD0); state 2: removed, done.
--   ScrCmd_709       -> ov02_022462E8, task ov02_02246330, also called:
--                    state 0 (ov02_02246398): NARC 0xAE palette 12, char 13,
--                    screen 14 onto main BG1, BG1 priority 0 / BG0 1, BG1 on,
--                    G2 blend alpha BG1 over BG0|BG2 at (d, 31 - d), d = 0;
--                    SEQ_SE_GS_AJITO_SIREN.  State 1: two pulses of
--                    ov02_02246490 -- each a reset frame, then 25 frames
--                    writing the blend with d = 0,1..12,11..0, then a frame
--                    that reports the pulse done.  State 2: waits until the
--                    siren is no longer playing, restores priorities, clears
--                    BG1, blend off, done.
--   The art is /a/1/7/4 (Gen4HgssLegendArt: trapThunder / trapPoison /
--   trapRock, hideoutAlarm -- a 256x192 field of RGB(214,16,0)).
--
-- TIMING: in FIELD FRAMES, two engine ticks each (the field runs at 30 Hz;
-- Gen4PropClock.TICKS_PER_FRAME).  The trap's model advances one animation
-- frame per field frame; the alarm's blend steps one d per field frame.
--
-- BLEND: the hardware computes min(31, (ev1 * BG1 + ev2 * field) / 16) with
-- ev2 = 31 - d clamped to 16 -- the field at full strength plus d/16 of the
-- red, which is LOVE's additive mode with alpha d/16.
--
-- STAND-INS (said, not hidden):
--   * the siren wait is capped at 600 field frames: the cartridge waits on
--     IsSEPlaying alone, and a sound bank that loops the siren (or a harness
--     with audio off, which answers "not playing" at once) must not hold the
--     script for ever;
--   * the alarm is drawn over the finished field picture and under the text
--     box, which is where BG1 at priority 0 sits on the cartridge too -- but
--     the field's own BG2/BG3 windows are not separated out.

local M = {}

M.TRAPS = {
  [0] = { part = "trapThunder", se = 2174 },   -- SEQ_SE_GS_DENKI_TRAP
  [1] = { part = "trapPoison", se = 2175 },    -- SEQ_SE_GS_DOKU_TRAP
  [2] = { part = "trapRock", se = 2177 },      -- SEQ_SE_GS_IWA_TRAP
}
M.SE_SIREN = 2173                              -- SEQ_SE_GS_AJITO_SIREN
M.ALARM_RGB = { 214 / 255, 16 / 255, 0 }       -- the screen's one colour
M.TICKS_PER_FRAME = 2
M.PULSES = 2
M.SIREN_CAP = 600

M.trap = nil
M.alarm = nil

local function Game() return package.loaded["src.core.Game"] end
local function art()
  local G = Game()
  return G and G.data and G.data.gen4_legend_art or nil
end
local function partOf(name)
  local a = art()
  return a and a.parts and a.parts[name] or nil
end
local function overworld()
  local G = Game()
  return G and G.overworld
end

local function playSe(id)
  local okS, Sound = pcall(require, "src.core.Sound")
  local G = Game()
  if okS and Sound and Sound.play then pcall(Sound.play, G and G.data, id) end
end

local function sePlaying(id)
  local okS, Sound = pcall(require, "src.core.Sound")
  if not (okS and Sound and Sound.isPlaying) then return false end
  local ok, playing = pcall(Sound.isPlaying, id)
  return ok and playing or false
end

-- where the player's feet are, in the ground's world space
local function anchor(ow)
  local p = ow and ow.player
  if not p then return 0, 0, 0 end
  local ground = ow.map and ow.map.renderer and ow.map.renderer.gen4Ground
  local gx, gz = (p.px or 0) + 8, (p.py or 0) + 8
  local y = ground and ground.groundY and ground:groundY(gx, gz) or 0
  return gx, y, gz
end

function M.active() return (M.trap or M.alarm) and true or false end

-- ------------------------------------------------------------- the trap --
-- startTrap(n) -> true when a picture is playing (and the script must wait)
function M.startTrap(variant)
  local row = M.TRAPS[math.floor(tonumber(variant) or 0)]
  if not row then return false end
  playSe(row.se)
  local part = partOf(row.part)
  if not part then return false end
  local x, y, z = anchor(overworld())
  M.trap = { part = row.part, frame = 0, state = 1, x = x, y = y, z = z, tick = 0,
             mapId = overworld() and overworld().map and overworld().map.id }
  return true
end

local function stepTrap(t)
  -- state 1: FrameAdvanceAndCheck on every animation; the model's longest
  -- animation decides (`frames` is the longest of the set)
  if t.state == 1 then
    local part = partOf(t.part)
    local frames = math.max(1, math.floor(tonumber(part and part.frames) or 1))
    if t.frame < frames - 1 then t.frame = t.frame + 1 end
    if t.frame >= frames - 1 then t.state = 2 end
  elseif t.state == 2 then
    -- ov02_02245E68: the object goes, the task returns TRUE
    M.trap = nil
  end
end

-- ------------------------------------------------------------ the alarm --
function M.startAlarm()
  playSe(M.SE_SIREN)
  M.alarm = { state = 1, sub = 0, a = 0, d = 0, ev = 0, pulses = 0, wait = 0, tick = 0 }
  return true
end

-- ov02_02246490: one pulse; true on the frame it reports done
local function pulse(al)
  if al.sub == 0 then
    al.a, al.d = 0, 0
    al.sub = 1
    return false
  elseif al.sub == 1 then
    al.ev = math.max(0, al.d)
    local was = al.a
    al.a = al.a + 1
    if was < 12 then al.d = al.d + 1 else al.d = al.d - 1 end
    if al.a > 24 then al.sub = 2 end
    return false
  end
  al.a, al.sub = 0, 0
  return true
end

local function stepAlarm(al)
  if al.state == 1 then
    if pulse(al) then
      local was = al.pulses
      al.pulses = al.pulses + 1
      if was >= M.PULSES - 1 then al.state = 2 end
    end
  elseif al.state == 2 then
    al.wait = al.wait + 1
    if not sePlaying(M.SE_SIREN) or al.wait >= M.SIREN_CAP then
      al.ev = 0
      M.alarm = nil
    end
  end
end

-- ------------------------------------------------------------- one tick --
-- once per engine tick from the overworld's update; the effects step once
-- per FIELD frame (every second tick)
function M.tick(ow)
  local t = M.trap
  if t then
    if ow and ow.map and t.mapId and ow.map.id ~= t.mapId then M.trap = nil
    else
      t.tick = t.tick + 1
      if t.tick % M.TICKS_PER_FRAME == 0 then stepTrap(t) end
    end
  end
  local al = M.alarm
  if al then
    al.tick = al.tick + 1
    if al.tick % M.TICKS_PER_FRAME == 0 then stepAlarm(al) end
  end
end

function M.reset()
  M.trap, M.alarm = nil, nil
end

-- ------------------------------------------------------------- drawing --
local models = {}
local function modelFor(name)
  if models[name] ~= nil then return models[name] or nil end
  local part = partOf(name)
  local ok, m = false, nil
  if part then ok, m = pcall(require("src.render.Gen4Model").new, part.model) end
  models[name] = ok and m or false
  return ok and m or nil
end

local function poseAndMaterials(mdl, part, frame)
  local Anim = require("src.import.Gen4Anim")
  local motion = part.motion
  local pose = motion and mdl:posed(function(node)
    local track = motion.tracks[node]
    return track and Anim.unpackFrame(track, math.min(frame, (motion.frames or 1) - 1)) or nil
  end) or nil
  local mats = require("src.render.Gen4TexAnim").materials(part.records, frame, part.model.patternImages)
  return pose, mats
end

-- the field camera's live pass (Gen4Ground, beside the legendary wing)
function M.drawLive(ground, left, top, vw, vh)
  local t = M.trap
  if not t then return end
  local mdl, part = modelFor(t.part), partOf(t.part)
  if not (mdl and part) then return end
  local Gen4Ground = require("src.render.Gen4Ground")
  local pose, mats = poseAndMaterials(mdl, part, t.frame)
  local half = ground.half or 0
  local base = ground:screenMatrix(t.x + (ground.offsetX or 0) - left - half,
                                   t.z + (ground.offsetY or 0) - top - half, vw, vh)
  local m = Gen4Ground.liftMatrix(base, t.y)
  local spread = Gen4Ground.liftedSpread and Gen4Ground.liftedSpread(ground.spread, t.y) or ground.spread
  mdl:draw(m, pose, mats, nil, spread)
end

-- the 3D view's pass (Gen4Ground:drawFree), with the world's depth
function M.drawFree(ground, vp)
  local t = M.trap
  if not t then return end
  local mdl, part = modelFor(t.part), partOf(t.part)
  if not (mdl and part) then return end
  local Gen4Model = require("src.render.Gen4Model")
  local pose, mats = poseAndMaterials(mdl, part, t.frame)
  local m = Gen4Model.multiply(vp, { 1, 0, 0, t.x + (ground.offsetX or 0),
                                     0, 1, 0, t.y,
                                     0, 0, 1, t.z + (ground.offsetY or 0),
                                     0, 0, 0, 1 })
  mdl:draw(m, pose, mats)
end

-- the alarm: Renderer.screenWeather's callback (UI pixels)
function M.alarmActive() return M.alarm ~= nil end

function M.drawAlarm(w, h)
  local al = M.alarm
  if not (al and al.ev and al.ev > 0) then return true end
  local g = love.graphics
  local mode, alphaMode = g.getBlendMode()
  g.setBlendMode("add", "alphamultiply")
  g.setColor(M.ALARM_RGB[1], M.ALARM_RGB[2], M.ALARM_RGB[3], math.min(16, al.ev) / 16)
  g.rectangle("fill", 0, 0, w, h)
  g.setBlendMode(mode, alphaMode)
  g.setColor(1, 1, 1, 1)
  return true
end

return M
