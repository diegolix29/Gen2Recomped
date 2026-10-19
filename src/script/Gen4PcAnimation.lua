-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE PC'S SCREEN LIGHTING UP AND GOING DARK -- Platinum and HGSS.
--
-- Platinum's CommonScript_PC (res/field/scripts/scripts_common.s):
--
--     CommonScript_PCBootUpAnimation:  LoadPCAnimation ANIMATION_TAG_PC
--                                      PlayPCBootUpAnimation ANIMATION_TAG_PC
--                                      WaitForAnimation ANIMATION_TAG_PC
--     CommonScript_PCShutDownAnimation: PlayPCShutDownAnimation ANIMATION_TAG_PC
--                                      WaitForAnimation ANIMATION_TAG_PC
--                                      UnloadAnimation ANIMATION_TAG_PC
--
-- `FieldSystem_LoadPCAnimation` (overlay006/pc_animation.c) finds the loaded
-- map prop whose model is one of four PC models (`pokecenter_pc` and the three
-- desk laptops) and hands that prop's animations to the one-shot manager under
-- the tag; boot-up plays animation 0 of the tag, shutdown animation 1.
--
-- WHICH ANIMATIONS: the prop's bm_anime_list record.  Platinum's PC models
-- (`pc01` 119, `table_l01`/`_l02`/`_l03` 112/115/248) are claimed by exactly
-- two bm_anime members, 41 `pc_moni_on` and 42 `pc_moni_off` -- 20-frame BTP0
-- flipbooks over `pc_moni.1`..`.4` (grey -> bright cyan).  `pc_moni_on` ends
-- on `pc_moni.4` (lit) and `pc_moni_off` on `pc_moni.1` (dark); a one-shot
-- holds its last frame (Gen4PropOneShot), so the screen stays lit while the
-- menu is up.  31/32 (`pc_mb`, `moniter_mb`) are the HEALING MACHINE's, not
-- the PC's.
--
-- HGSS has the same script shape under unnamed commands (std PC, scr_seq 3
-- `S09FD`: `ScrCmd_500 90; ScrCmd_501 90; WaitForAnimation 90` for boot-up and
-- `ScrCmd_502 90; WaitForAnimation 90; UnloadAnimation 90` for shutdown), and
-- its room list (/a/1/0/8) gives `pc01` (33) and `pc05` (138) the members 102
-- `pc_moni_on` / 103 `pc_moni_off` -- as script-owned claims (`scriptProps`).
--
-- So the animations are found BY THE PROP'S OWN CLAIM: the two script-owned
-- flipbooks named `pc_moni_on` / `pc_moni_off` in whichever set this map's
-- renderer loaded, with Platinum's member numbers as the fallback.  The PC is
-- the first loaded prop those animations claim, as on the cartridge.
--
-- The slot is an ordinary Gen4PropOneShot slot, so `waitforanimation` and
-- `unloadanimation` (lowered for the doors) already wait on and release it.
--
-- Loaded by Gen4ScriptVM (`install` with the lowering table).

local okCommands, Commands = pcall(require, "src.script.Commands")
if not okCommands then Commands = {} end

local M = {}

-- Platinum's bm_anime members, when the cache's records carry no name
M.PLATINUM_ON, M.PLATINUM_OFF = 41, 42
M.ON_NAME, M.OFF_NAME = "pc_moni_on", "pc_moni_off"

local function groundOf(ow)
  return ow and ow.map and ow.map.renderer and ow.map.renderer.gen4Ground
end

-- records(ground) -> on, off (animation records) | nil
function M.records(ground)
  local byMember = ground and ground.animsByMember
  if type(byMember) ~= "table" then return nil end
  local on, off
  for _, record in pairs(byMember) do
    if record.name == M.ON_NAME then on = record
    elseif record.name == M.OFF_NAME then off = record end
  end
  on = on or byMember[M.PLATINUM_ON]
  off = off or byMember[M.PLATINUM_OFF]
  return on, off
end

-- owners(record) -> { [model index] = true }
function M.owners(record)
  local set = {}
  for _, key in ipairs({ "props", "scriptProps" }) do
    for _, index in ipairs((record and record[key]) or {}) do set[index] = true end
  end
  return set
end

-- findPc(ground) -> object (the terrain's own table, by identity) | nil
function M.findPc(ground)
  local on = M.records(ground)
  if not on then return nil end
  local owners = M.owners(on)
  if not next(owners) then return nil end
  local grid, terrain = ground.grid, ground.terrain
  local chunks = terrain and terrain.chunks
  if not (grid and grid.land and chunks) then return nil end
  for _, land in ipairs(grid.land) do
    local record = chunks[land]
    for _, object in ipairs((record and record.objects) or {}) do
      if object.archive ~= "fldeff" and owners[object.model] then return object end
    end
  end
  return nil
end

-- g4_pc_animation(which, tag): "load" finds the PC, "on" / "off" play its
-- boot-up / shutdown flipbook on the tag.  A PC that cannot be found starts
-- nothing, so the `waitforanimation` after it steps over (cartridge: assert).
function Commands.g4_pc_animation(ctx, which, tag)
  local ow = ctx and ctx.overworld
  if not ow then return end
  tag = math.floor(tonumber(tag) or 0)
  local ground = groundOf(ow)
  ow.gen4PcProps = ow.gen4PcProps or {}
  if which == "load" then
    ow.gen4PcProps[tag] = (ground and M.findPc(ground)) or false
    return
  end
  local object = ow.gen4PcProps[tag]
  if object == nil and ground then
    -- a play without a load on this map: find it now rather than stay dark
    object = M.findPc(ground) or false
    ow.gen4PcProps[tag] = object
  end
  local on, off = M.records(ground)
  local record = (which == "on" and on) or (which == "off" and off) or nil
  local OneShot = require("src.world.Gen4PropOneShot")
  local slots = OneShot.all(ow)
  local frames = record and tonumber(record.frames) or 0
  if not (object and record and frames > 0 and slots) then
    if slots then slots[tag] = nil end
    return
  end
  slots[tag] = {
    tag = tag, model = "pc", action = which, object = object,
    animation = record.member, frames = frames, frame = 0,
  }
end

function M.install(L)
  local function emit(s, row) s.out[#s.out + 1] = row end
  local function load(ins, s) emit(s, { "g4_pc_animation", "load", ins.args[1] }) end
  local function on(ins, s) emit(s, { "g4_pc_animation", "on", ins.args[1] }) end
  local function off(ins, s) emit(s, { "g4_pc_animation", "off", ins.args[1] }) end
  -- Platinum's names (0x24B-0x24D)
  L.loadpcanimation, L.playpcbootupanimation, L.playpcshutdownanimation = load, on, off
  -- HGSS's ScrCmd_500/501/502 (u8 tag each), unnamed in the import
  L.scrcmd_500, L.scrcmd_501, L.scrcmd_502 = load, on, off
end

return M
