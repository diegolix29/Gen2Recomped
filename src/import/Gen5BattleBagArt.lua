-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- BLACK AND WHITE'S BATTLE BAG (/a/0/9/9), written as `gen5_battle_bag` for
-- src/ui/Gen5BattleBag.lua. The battle's own touch-screen family: like the
-- command screen (/a/0/1/1 91-111) it is one tileset and one palette under
-- a 512 x 512 map whose four 256-pixel quarters are the screens the
-- cartridge scrolls between. Decoded and looked at (scratch_claude/
-- bw_ui_map.md section 2, bw_battle3/bagq*.png); the file table has no
-- names:
--
--   0 / 1      the tileset (512 tiles, LZ10) and its palette
--   2          the backdrop: a Poke Ball under the buttons (256 x 256)
--   3          the screens, by quarter:
--                (0, 0)     the four pockets -- HP/PP RESTORE (top left),
--                           POKe BALLS (top right), STATUS RESTORE (bottom
--                           left), BATTLE ITEMS (bottom right) -- the LAST
--                           USED ITEM bar and the back button
--                (256, 0)   a pocket: six item buttons, the page arrows, the
--                           page box, back
--                (0, 256)   one item: the panel, the USE bar, back
--   4..7       a pocket button PRESSED (the top 30 lines of it; the rest of
--              the 128 x 64 patch is empty): HP/PP, Status, Balls, Battle
--   8          an item button pressed; 9 / 10 the page arrows; 11 back;
--              12 the long bar
--   13..16     the page numbers (OBJ, not used: the port prints them)
--
-- Every button's rectangle below was measured off the composed quarters
-- (the opaque runs of each), in the screen's own pixels.

local A = {}

A.PATH = "/a/0/9/9"

A.QUARTERS = { menu = { 0, 0 }, pocket = { 256, 0 }, use = { 0, 256 } }
A.PRESS = { pocket_hp = 4, pocket_status = 5, pocket_balls = 6, pocket_battle = 7,
            item = 8, prev = 9, next = 10, back = 11, bar = 12 }

-- { x, y, w, h } per button, and where its pressed patch goes (the button's
-- tile origin)
A.RECTS = {
  menu = {
    { 1, 10, 126, 61 }, { 129, 10, 126, 61 }, { 1, 82, 126, 61 }, { 129, 82, 126, 61 },
    { 11, 160, 194, 30 }, { 217, 153, 39, 39 },
  },
  pocket = {
    { 1, 9, 126, 46 }, { 129, 9, 126, 46 }, { 1, 57, 126, 46 }, { 129, 57, 126, 46 },
    { 1, 105, 126, 46 }, { 129, 105, 126, 46 },
    { 1, 157, 38, 35 }, { 41, 157, 38, 35 }, { 217, 153, 39, 39 },
  },
  use = { { 11, 160, 194, 30 }, { 217, 153, 39, 39 } },
  panel = { 3, 22, 250, 99 },
  pageBox = { 84, 154, 128, 36 },
}

function A.build(x)
  local G = require("src.import.Gen4Graphics")
  local raw = x.rom:read(A.PATH)
  local arc = raw and require("src.import.NarcArchive").parse(raw)
  if not arc then return nil end
  local function m(i)
    local b = arc:get(i)
    if b and G.isCompressed(b) then b = G.decompress(b) end
    return b
  end
  local sheet, pal = G.tiles(m(0)), G.palette(m(1))
  if not (sheet and pal) then return nil end
  local out = { images = {}, rects = A.RECTS }
  local function save(name, image, extra)
    local entry = image and x:saveImage("battle5/bag_" .. name, image, extra)
    if entry then out.images[name] = entry end
    return entry
  end
  local function crop(full, qx, qy, w, h)
    local rgba = {}
    for y = 0, h - 1 do
      local from = ((qy + y) * full.width + qx) * 4
      rgba[#rgba + 1] = full.rgba:sub(from + 1, from + w * 4)
    end
    return { width = w, height = h, rgba = table.concat(rgba) }
  end
  local back = G.compose(G.tilemap(m(2)), sheet, pal)
  if back then save("base", crop(back, 0, 0, 256, 192)) end
  local screens = G.compose(G.tilemap(m(3)), sheet, pal)
  if screens then
    for name, q in pairs(A.QUARTERS) do save(name, crop(screens, q[1], q[2], 256, 192)) end
  end
  for name, member in pairs(A.PRESS) do
    local pic = G.compose(G.tilemap(m(member)), sheet, pal)
    if pic then save("press_" .. name, pic) end
  end
  -- the text colours the screens print in: the palette's white and its
  -- darkest grey (the buttons' faces are dark)
  out.source = "ROM:/a/0/9/9 (tiles 0, palette 1, backdrop 2, screens 3, pressed 4-12)"
  return out
end

return A
