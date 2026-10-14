-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE DISTORTION WORLD'S SKY, from /data/tw_arc_etc.narc.
--
-- Reported from play: "The sky doesn't darken during Giratina's arrival."  It
-- could not: the Distortion World drew the overworld's panorama, and the
-- cartridge's sky is something else -- a 2D background on main BG2 behind the
-- 3D plane (pokeplatinum overlay009 InitSkyBackground) and nine cloud sprites
-- turning about the screen (InitSkyCloudAnimators):
--
--   member 0/1/2   the background's NCGR / NCLR / NSCR, one 256x192 screen
--   4,7,..,0x16    the seven cloud kinds' NCGR  (sSkyCloudsCharNARCIndexes)
--   3,6,..,0x15    their NCER                    (sSkyCloudsCellNARCIndexes)
--   5,8,..,0x17    their NANR                    (sSkyCloudsAnimNARCIndexes)
--   0x18           the clouds' five palettes     (sSkyCloudsPlttNARCIndexes)
--
-- Both are darkened at run time by RecalculateSkyBackgroundDarkness, toward
-- GX_RGB(4,4,8) (background) and GX_RGB(6,6,8) (clouds) by level/16; the
-- import keeps the undarkened pictures and the runtime (Gen4DistSkyView) mixes.

local Gen4Graphics = require("src.import.Gen4Graphics")
local Gen4Cells = require("src.import.Gen4Cells")
local Gen4CellAnim = require("src.import.Gen4CellAnim")

local K = {}

K.PATH = "/data/tw_arc_etc.narc"
K.CHAR = { 0x4, 0x7, 0xA, 0xD, 0x10, 0x13, 0x16 }
K.CELL = { 0x3, 0x6, 0x9, 0xC, 0xF, 0x12, 0x15 }
K.ANIM = { 0x5, 0x8, 0xB, 0xE, 0x11, 0x14, 0x17 }
K.PLTT = 0x18

local function member(arc, i)
  local b = arc and arc:get(i)
  if b and Gen4Graphics.isCompressed(b) then b = Gen4Graphics.decompress(b) end
  return b
end

-- extract(ex) -> the record for gen4_distortion_world.sky, or nil, why.
-- `ex` is the RomExtractorGen4 (archiveAt, saveImage).
function K.extract(ex)
  local arc = ex:archiveAt(K.PATH)
  if not arc then return nil, K.PATH .. " missing" end
  local out = { source = "ROM:tw_arc_etc.narc (overlay 9 InitSkyBackground / InitSkyCloudAnimators)", clouds = {} }

  local palette = Gen4Graphics.palette(member(arc, 1))
  local bg = palette and Gen4Graphics.compose(Gen4Graphics.tilemap(member(arc, 2)),
                                             Gen4Graphics.tiles(member(arc, 0)), palette)
  if bg then
    out.background = ex:saveImage("distortion/sky_bg", bg)
    -- colour 0 is the backdrop under the transparent pixels
    local c = palette[1]
    if c then out.backdrop = { c[1], c[2], c[3] } end
  else
    out.refusedBackground = "member 0/1/2 did not compose"
  end

  local colours = Gen4Graphics.palette(member(arc, K.PLTT))
  for kind = 1, #K.CHAR do
    local sheet = Gen4Graphics.tiles(member(arc, K.CHAR[kind]))
    local cellBytes = member(arc, K.CELL[kind])
    local bank = cellBytes and Gen4Cells.parse(cellBytes, Gen4Graphics)
    local animBytes = member(arc, K.ANIM[kind])
    local anim = animBytes and Gen4CellAnim.parse(animBytes, Gen4Graphics)
    local rec = { cells = {} }
    if sheet and bank and colours then
      for i, cell in ipairs(bank.cells) do
        local image = Gen4Cells.assemble(cell, sheet, colours, bank, Gen4Graphics)
        local minX, minY = Gen4Cells.extent(cell)
        rec.cells[i] = false
        if image then
          local entry = ex:saveImage(("distortion/sky_cloud_%d_%d"):format(kind - 1, i - 1), image)
          -- where the sprite's centre falls in the picture
          if entry then entry.ox, entry.oy = -(minX or 0), -(minY or 0) end
          rec.cells[i] = entry or false   -- 1-based: cell n is cells[n + 1]
        end
      end
      local frames = anim and Gen4CellAnim.frames(anim, 0)
      if frames then
        rec.frames = {}
        for _, f in ipairs(frames) do rec.frames[#rec.frames + 1] = { cell = f.cell, duration = f.duration } end
      end
    else
      rec.refused = "char, cell or palette did not decode"
    end
    out.clouds[kind] = rec   -- 1-based: resIDsIndex n is clouds[n + 1]
  end
  return out
end

return K
