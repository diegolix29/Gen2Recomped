-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- BLACK / WHITE'S POKE MART COUNTER ART, written as `gen4_shop_art` -- the
-- record src/ui/Gen4ShopMenu.lua already draws Platinum's counter from.
--
-- The counter is a field event of scrcmd_shop.c (overlay 21): it opens
-- arc 54 (/a/0/5/4, ov21 0x021B3BE8 / 0x021B3C82) and loads
--
--   0 / 1      the BG tiles (4bpp, 128) and their palette
--   2          the counter's screen (256 x 192): the money box at the top
--              left, the light-blue list window on the right, the slate bar
--              along the foot with the item icon's box -- the field shows
--              through the rest
--   3          the screen's other half (not drawn here)
--   4 / 5 / 6  OBJ: the list's scroll arrows (cells 0 up, 1 down)
--   7 / 8 / 9  OBJ: the selection bar
--   10         the OBJ palette
--
-- The screen is decoded here directly, each entry's top four bits its
-- palette row (through the shared compose path it came out in scattered
-- pieces).
--
-- build(x) -> { counter, cursor_0, cursor_1, scroll_up, scroll_down, ink } or nil

local M = {}

M.PATH = "/a/0/5/4"

local function u16(s, o) return s:byte(o + 1) + s:byte(o + 2) * 256 end
local function section(data, tag, skip)
  local at = data and data:find(tag, 1, true)
  return at and (at - 1 + skip) or nil
end

local function colour(pal, plt, i)
  local v = u16(pal, plt + i * 2)
  local function ch(n) n = n % 32 return string.char(n * 8 + math.floor(n / 4)) end
  return ch(v) .. ch(math.floor(v / 32)) .. ch(math.floor(v / 1024)) .. "\255"
end

-- a 4bpp text-BG screen over its sheet and palette rows, 256 x 192 RGBA
local function screen(scr, sheet, pal)
  local so, chr, plt = section(scr, "NRCS", 0x14), section(sheet, "RAHC", 0x20), section(pal, "TTLP", 0x18)
  if not (so and chr and plt) then return nil end
  local px = {}
  for ty = 0, 23 do
    for tx = 0, 31 do
      local v = u16(scr, so + (ty * 32 + tx) * 2)
      local t, row = v % 1024, math.floor(v / 4096)
      local hf, vf = math.floor(v / 1024) % 2 == 1, math.floor(v / 2048) % 2 == 1
      for y = 0, 7 do
        for x = 0, 7 do
          local sx, sy = hf and 7 - x or x, vf and 7 - y or y
          local b = sheet:byte(chr + t * 32 + sy * 4 + math.floor(sx / 2) + 1) or 0
          local ci = sx % 2 == 0 and b % 16 or math.floor(b / 16)
          if ci ~= 0 then px[(ty * 8 + y) * 256 + tx * 8 + x] = colour(pal, plt, row * 16 + ci) end
        end
      end
    end
  end
  local out = {}
  for i = 0, 256 * 192 - 1 do out[#out + 1] = px[i] or "\0\0\0\0" end
  return { width = 256, height = 192, rgba = table.concat(out) }
end

function M.build(x)
  local G = require("src.import.Gen4Graphics")
  local Cells = require("src.import.Gen4Cells")
  local Lz = require("src.import.Gen5Lz")
  local raw = x.rom:read(M.PATH)
  local arc = raw and require("src.import.NarcArchive").parse(raw)
  if not arc then return nil, "no " .. M.PATH end
  local function m(i)
    local b = arc:get(i)
    if b and Lz.isCompressed(b) then b = Lz.decompress(b) elseif b and G.isCompressed(b) then b = G.decompress(b) end
    return b
  end
  local out = { _source = "ROM:" .. M.PATH .. " (screen 2 on 0 pal 1; OBJ 4/5 and 7/8 pal 10)", family = "bw",
                -- dark words on the light-blue list, light ones on the slate
                ink = { list = { text = { 0.25, 0.25, 0.29 }, shadow = { 0.70, 0.80, 0.86 } },
                        money = { text = { 1, 1, 1 }, shadow = { 0.25, 0.25, 0.32 } } },
                money = { labelX = 8, labelY = 6, amountRight = 80, amountY = 22 } }
  local counter = screen(m(2), m(0), m(1))
  local e = counter and x:saveImage("bw_shop/counter", counter)
  if not e then return nil, "no counter" end
  out.counter = e
  local pal = G.palette(m(10))
  local function cells(charIndex, cellIndex, names)
    local sheet, bank = G.tiles(m(charIndex)), Cells.parse(m(cellIndex), G)
    if not (sheet and bank and pal) then return end
    for i, name in pairs(names) do
      local cell = bank.cells[i + 1]
      local pic = cell and Cells.assemble(cell, sheet, pal, bank, G)
      if pic then
        local ox, oy = Cells.extent(cell)
        out[name] = x:saveImage("bw_shop/" .. name, pic, { originX = ox, originY = oy })
      end
    end
  end
  cells(4, 5, { [0] = "scroll_up", [1] = "scroll_down" })
  cells(7, 8, { [0] = "cursor_0" })
  out.cursor_1 = out.cursor_0
  return out
end

return M
