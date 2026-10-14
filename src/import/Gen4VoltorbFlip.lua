-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- HEARTGOLD / SOULSILVER'S VOLTORB FLIP: the Game Corner's art, out of
-- NARC_application_voltorb_flip (/a/2/6/4 -- the decomp builds the list from a/2/6/0 for its named entries --, pokeheartgold
-- src/voltorb_flip/voltorb_flip.c VoltorbFlip_LoadBgGfx / _LoadObjectGfx):
--
--   0 / 1   NCLR, bottom (main) BG / top (sub) BG
--   2       NCGR, the board's tiles -- BG0 under NSCR 4, and BG2's numbers
--           and memo marks drawn by tile id
--   3       NCGR, the top screen's tiles; NSCR 6 coins, 7 Hint, 8 How to
--           Play, 9 About Memo; the coin digits are tile ids 0xA0 + 2d
--   10..13  main sprites (NCLR, NCGR, NCER, NANR), 14..17 the sub ones
--
-- Written: the two board backgrounds, the four top pages, both tile sheets as
-- atlases (tile t at (t % 32 * 8, t // 32 * 8)) so the screen can draw any
-- tile id the cartridge writes, every sprite cell with its centre offset, the
-- memo cursor's cells again in palette 4, and every animation sequence.

local Gen4Graphics = require("src.import.Gen4Graphics")
local Gen4Cells = require("src.import.Gen4Cells")
local Gen4CellAnim = require("src.import.Gen4CellAnim")

local V = {}

V.PATH = "/a/2/6/4"

-- the `_lz` members are LZ11 (0x11), not the LZ77 (0x10) most of Gen 4 uses
local function member(arc, i)
  local b = arc and arc:get(i)
  if not b then return nil end
  local Lz = require("src.import.Gen5Lz")
  if Lz.isCompressed(b) then return Lz.decompress(b) end
  if Gen4Graphics.isCompressed(b) then b = Gen4Graphics.decompress(b) end
  return b
end

-- every tile of a sheet in one palette line, 32 to a row
local function atlas(sheet, palette, line)
  if not (sheet and palette) then return nil end
  local count = sheet.count or (sheet.tiles and #sheet.tiles) or 0
  if count <= 0 then return nil end
  local rows = math.ceil(count / 32)
  local cells = {}
  for t = 0, rows * 32 - 1 do
    cells[t + 1] = (t < count) and { tile = t, palette = line or 0 } or { tile = 0, palette = line or 0 }
  end
  return Gen4Graphics.compose({ width = 256, height = rows * 8, cells = cells }, sheet, palette)
end

local function sprites(ex, arc, base, prefix, overrideCells, overrideOnly, overridePal)
  local colours = Gen4Graphics.palette(member(arc, base))
  local sheet = Gen4Graphics.tiles(member(arc, base + 1))
  local cellBytes = member(arc, base + 2)
  local bank = cellBytes and Gen4Cells.parse(cellBytes, Gen4Graphics)
  local animBytes = member(arc, base + 3)
  local anim = animBytes and Gen4CellAnim.parse(animBytes, Gen4Graphics)
  local rec = { cells = {}, anims = {}, override = {} }
  if not (colours and sheet and bank) then
    rec.refused = "sprite member " .. base .. ".." .. (base + 3) .. " did not decode"
    return rec
  end
  local function save(name, cell)
    local image = Gen4Cells.assemble(cell, sheet, colours, bank, Gen4Graphics)
    if not image then return false end
    local minX, minY = Gen4Cells.extent(cell)
    local entry = ex:saveImage(name, image)
    if entry then entry.ox, entry.oy = -(minX or 0), -(minY or 0) end
    return entry or false
  end
  for i, cell in ipairs(bank.cells) do
    if not overrideOnly then rec.cells[i] = save(("%s_cell_%d"):format(prefix, i - 1), cell) end
  end
  -- SetPaletteOverride(sprite, 4): the memo cursor, drawn from the board
  -- cursor's cells in another palette line
  for _, i in ipairs(overrideCells or {}) do
    local cell = bank.cells[i + 1]
    if cell then
      local copy = { oam = {}, transfer = cell.transfer }
      for k, v in pairs(cell) do if k ~= "oam" then copy[k] = v end end
      for j, o in ipairs(cell.oam) do
        local c = {}
        for k, v in pairs(o) do c[k] = v end
        c.palette = overridePal or 4
        copy.oam[j] = c
      end
      rec.override[i + 1] = save(("%s_cell_%d_p%d"):format(prefix, i, overridePal or 4), copy)
    end
  end
  for s, seq in ipairs((anim and anim.sequences) or {}) do
    local frames = {}
    for _, f in ipairs(Gen4CellAnim.frames(anim, s - 1) or {}) do
      frames[#frames + 1] = { cell = f.cell, duration = f.duration }
    end
    rec.anims[s] = { frames = frames, mode = seq.playbackMode, loopStart = seq.loopStart }
  end
  return rec
end

-- extract(ex) -> the gen4_voltorb_flip record, or nil, why
function V.extract(ex)
  local arc = ex:archiveAt(V.PATH)
  if not arc then return nil, V.PATH .. " missing" end
  local out = { source = "ROM:/a/2/6/4 (NARC_application_voltorb_flip)" }
  local mainPal = Gen4Graphics.palette(member(arc, 0))
  local subPal = Gen4Graphics.palette(member(arc, 1))
  local mainTiles = Gen4Graphics.tiles(member(arc, 2))
  local subTiles = Gen4Graphics.tiles(member(arc, 3))
  if not (mainPal and subPal and mainTiles and subTiles) then
    return nil, "palettes / tiles 0..3 did not decode"
  end
  local function page(n, tiles, pal, name)
    local map = Gen4Graphics.tilemap(member(arc, n))
    local img = map and Gen4Graphics.compose(map, tiles, pal)
    return img and ex:saveImage("voltorb_flip/" .. name, img) or nil
  end
  out.board = page(4, mainTiles, mainPal, "board")
  out.top = {
    coins = page(6, subTiles, subPal, "top_coins"),
    hint = page(7, subTiles, subPal, "top_hint"),
    howTo = page(8, subTiles, subPal, "top_how_to_play"),
    memo = page(9, subTiles, subPal, "top_about_memo"),
  }
  local a = atlas(mainTiles, mainPal, 0)
  out.mainAtlas = a and ex:saveImage("voltorb_flip/main_tiles", a) or nil
  local b = atlas(subTiles, subPal, 0)
  out.subAtlas = b and ex:saveImage("voltorb_flip/sub_tiles", b) or nil
  -- the backdrop under transparent BG pixels: colour 0 of line 0
  local c0 = mainPal[1]
  if c0 then out.backdrop = { c0[1], c0[2], c0[3] } end
  -- the main sprites (the board cursor's cells 18's frames also in palette 4)
  out.mainSprites = sprites({ saveImage = function(_, n, i) return ex:saveImage("voltorb_flip/" .. n, i) end },
    arc, 10, "main", nil)
  out.subSprites = sprites({ saveImage = function(_, n, i) return ex:saveImage("voltorb_flip/" .. n, i) end },
    arc, 14, "sub", nil)
  -- THE BOARD CURSOR'S PALETTE OVERRIDES (VoltorbFlipInputHandler_
  -- UpdateBoardCursorAnim): line 2 normally, line 4 while the memo is open --
  -- and the memo cursor is anim 18 in line 4 -- so every cell the cursor's
  -- anims show (4 Quit, 7 Memo, 18 card, 23 / 24 pencil) is drawn in both
  local want, seen = {}, {}
  for _, a in ipairs({ 4, 7, 18, 23, 24 }) do
    local an = out.mainSprites.anims and out.mainSprites.anims[a + 1]
    for _, f in ipairs(an and an.frames or {}) do
      if not seen[f.cell] then seen[f.cell] = true; want[#want + 1] = f.cell end
    end
  end
  out.mainSprites.palette = {}
  for _, line in ipairs({ 2, 4 }) do
    local again = sprites({ saveImage = function(_, n, i) return ex:saveImage("voltorb_flip/" .. n, i) end },
      arc, 10, "main", want, true, line)
    out.mainSprites.palette[line] = again.override
  end
  out.mainSprites.override = nil
  return out
end

return V
