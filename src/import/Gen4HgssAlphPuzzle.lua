-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- HEARTGOLD / SOULSILVER'S RUINS OF ALPH PUZZLES: the art, out of
-- NARC_application_annon_puzzle_gra (/a/1/7/2 -- found by its shape, the only
-- 16-member archive with palettes at 0 / 10, cell banks at 2 / 8 and screens
-- at 12..15), pokeheartgold src/alph_puzzle.c:
--
--   0       NCLR, the sprites (main OBJ)
--   1..3    NCGR / NCER / NANR, the QUIT button and the held tile's origin
--           cursor (resdat 8..10, set 0)
--   4..7    NCGR, the four puzzles' tiles (Kabuto, Aerodactyl, Omanyte, Ho-Oh),
--           cut by 8 / 9 -- animation sequence i is tile i
--   10      NCLR, both screens' backgrounds
--   11      NCGR, the backgrounds' tiles
--   12      NSCR, the board (bottom BG3)
--   13      NSCR, the hover marks, three 4 x 4-tile blocks side by side
--           (AlphPuzzle_ClearOrSetBgTilesAtCoords: block a3 - 1)
--   14 / 15 NSCR, the top screen (sub BG3 under sub BG2)

local Gen4Graphics = require("src.import.Gen4Graphics")
local Gen4Cells = require("src.import.Gen4Cells")
local Gen4CellAnim = require("src.import.Gen4CellAnim")

local A = { PATH = "/a/1/7/2", PUZZLES = 4 }

local function member(arc, i)
  local b = arc and arc:get(i)
  if b and Gen4Graphics.isCompressed(b) then b = Gen4Graphics.decompress(b) end
  return b
end

-- a sprite set: every cell saved with its centre offset, every sequence's
-- frames (cell, duration)
local function sprites(x, arc, colours, sheetIndex, cellIndex, animIndex, prefix)
  local sheet = Gen4Graphics.tiles(member(arc, sheetIndex))
  local cellBytes = member(arc, cellIndex)
  local bank = cellBytes and Gen4Cells.parse(cellBytes, Gen4Graphics)
  local animBytes = member(arc, animIndex)
  local anim = animBytes and Gen4CellAnim.parse(animBytes, Gen4Graphics)
  if not (sheet and bank and anim) then return nil end
  local rec = { cells = {}, anims = {} }
  for i, cell in ipairs(bank.cells) do
    local image = Gen4Cells.assemble(cell, sheet, colours, bank, Gen4Graphics)
    if image then
      local minX, minY = Gen4Cells.extent(cell)
      local entry = x:saveImage(("alph_puzzle/%s_cell_%d"):format(prefix, i - 1), image)
      if entry then entry.ox, entry.oy = -(minX or 0), -(minY or 0) end
      rec.cells[i] = entry or false
    else
      rec.cells[i] = false
    end
  end
  for s, seq in ipairs(anim.sequences or {}) do
    local frames = {}
    for _, f in ipairs(Gen4CellAnim.frames(anim, s - 1) or {}) do
      frames[#frames + 1] = { cell = f.cell, duration = f.duration }
    end
    rec.anims[s] = { frames = frames, mode = seq.playbackMode }
  end
  return rec
end

-- THE FOUR STARTING LAYOUTS (sAlphKabutoPuzzle .. sAlphHoOhPuzzle, overlay
-- 110): 6 x 6 cells each, one byte per cell -- index:5 (tile 1..16, 0 empty),
-- rotation:2, isImmovable:1. Found by shape, not by content: four 36-byte
-- boards in a row, each holding every tile 1..16 and nothing in its four
-- corners (sCornerCoords: no tile may sit there). NOT "exactly once": the
-- Ho-Oh board names tile 5 twice (a fixed one, then a movable one), and
-- AlphPuzzle_InitTileData simply lets the later cell win.
local function isBoard(s, at)
  local seen, n = {}, 0
  for i = 0, 35 do
    local v = s:byte(at + i)
    local idx = v % 32
    if idx > 16 then return false end
    if idx > 0 then
      local cx, cy = i % 6, math.floor(i / 6)
      if (cx == 0 or cx == 5) and (cy == 0 or cy == 5) then return false end
      if not seen[idx] then seen[idx], n = true, n + 1 end
    elseif v ~= 0 then
      return false
    end
  end
  return n == 16
end

function A.layouts(rom)
  local order = { 110 }
  for i = 0, 140 do if i ~= 110 then order[#order + 1] = i end end
  for _, i in ipairs(order) do
    local ok, ov = pcall(function() return rom:overlay(i) end)
    if ok and type(ov) == "string" then
      for at = 1, #ov - 143, 4 do
        if isBoard(ov, at) and isBoard(ov, at + 36) and isBoard(ov, at + 72) and isBoard(ov, at + 108) then
          local out = {}
          for p = 0, 3 do
            local cells = {}
            for c = 0, 35 do
              local v = ov:byte(at + p * 36 + c)
              cells[c + 1] = { index = v % 32, rotation = math.floor(v / 32) % 4, fixed = v >= 128 }
            end
            out[p + 1] = cells
          end
          return out, i, at - 1
        end
      end
    end
  end
  return nil
end

function A.build(x)
  local Narc = require("src.import.NarcArchive")
  local arc = assert(Narc.parse(assert(x.rom:read(A.PATH))))
  local objPal = Gen4Graphics.palette(member(arc, 0))
  local bgPal = Gen4Graphics.palette(member(arc, 10))
  local bgTiles = Gen4Graphics.tiles(member(arc, 11))
  assert(objPal and bgPal and bgTiles, "palettes 0 / 10 or tiles 11 did not decode")
  local out = { source = "ROM:" .. A.PATH .. " (NARC_application_annon_puzzle_gra)" }
  local function screen(n, name)
    local map = Gen4Graphics.tilemap(member(arc, n))
    local img = map and Gen4Graphics.compose(map, bgTiles, bgPal)
    return img and x:saveImage("alph_puzzle/" .. name, img) or nil
  end
  out.board = screen(12, "board")
  out.marks = screen(13, "marks")
  out.topBack = screen(14, "top_bg3")
  out.topFront = screen(15, "top_bg2")
  local c0 = bgPal[1]
  if c0 then out.backdrop = { c0[1], c0[2], c0[3] } end
  out.cursors = sprites(x, arc, objPal, 1, 2, 3, "cursor")
  -- THE SOLVED GLOW (AlphPuzzleMainSeq_Clear_impl): PaletteData_BlendPalette
  -- on main OBJ colours 0x2B..0x2F toward white, 0..15 sixteenths and back.
  -- A blend is a lerp, so the same picture is the tile with a white mask of
  -- exactly those texels laid over it at that alpha -- the mask is the tile
  -- composed through a palette holding only those five entries, white.
  local glow = {}
  for i = 0x2B, 0x2F do glow[i + 1] = { 255, 255, 255 } end
  out.puzzles = {}
  for p = 0, A.PUZZLES - 1 do
    out.puzzles[p + 1] = sprites(x, arc, objPal, 4 + p, 8, 9, ("tiles%d"):format(p))
    local mask = sprites(x, arc, glow, 4 + p, 8, 9, ("glow%d"):format(p))
    if out.puzzles[p + 1] and mask then out.puzzles[p + 1].glow = mask.cells end
  end
  -- THE INKS: both windows sit on BG palette line 3 (sWindowTemplates); the
  -- hint prints in MAKE_TEXT_COLOR(2, 1, 0), QUIT in (1, 2, 0) / (3, 4, 0) /
  -- (5, 6, 0) (sQuitButtonTextColors) -- letter, then shadow
  local function ink(i)
    local c = bgPal[3 * 16 + i + 1]
    return c and { c[1], c[2], c[3] } or nil
  end
  local layouts, ovl, off = A.layouts(x.rom)
  out.layouts = layouts
  if layouts then out.layoutSource = ("overlay %d +0x%X"):format(ovl, off) end
  out.inks = {
    hint = { ink(2), ink(1) },
    quit = { { ink(1), ink(2) }, { ink(3), ink(4) }, { ink(5), ink(6) } },
  }
  return out
end

return A
