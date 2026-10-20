-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- BLACK / WHITE'S XTRANSCEIVER CALLS, out of the ROM.
--
-- Script 0x155 <call> (ov10 0x0215CAB4) starts overlay 174, the story-call
-- app (local_tvt_sys.c / local_tvt_chara.c; the online one is ov172), with
-- the call number. The app reads /a/1/3/1 (arc 131, opened at its start):
--
--   members 63..68   the six calls, call n = member 62 + n:
--                      +0  four participant ids (0xFF none) -- 0 the
--                          player, 1 Cheren, 2 Bianca, 3 the Professor,
--                          4 Mom (system bank 198 holds their names)
--                      +4  four bytes, one per panel
--                      +8  4-byte steps: 01 <panel> <line> 00 says a line
--                          of system text bank 191 + n; 00 ends the call
--   24..35 / 18..23  the callers' pictures: 128 x 192, 8bpp (16 x 24 tiles),
--                    two frames each (the mouth shut and open), one palette
--                    per person -- Juniper, Hilda, Hilbert, Cheren, Bianca,
--                    Mom
--   6..17 / 1..5     the backgrounds behind them, the same size, two frames
--                    each -- three of hills (6, 8, 10) and three of dunes
--                    (12, 14, 16) -- and the five palettes are the time of
--                    day: 1 morning and evening, 2 night, 4 the hills' day,
--                    3 the dunes' day
--   37 / 38          the panel layouts (placeholder art numbering 1..4): two
--                    callers stand in 128-pixel halves, three or four in
--                    128 x 96 quarters
--
-- build(x) -> { calls, people, backgrounds } or nil

local M = {}

M.PATH = "/a/1/3/1"
M.CALL_BASE = 62
M.TEXT_BASE = 191
M.NAMES_BANK = 198
M.PEOPLE = { "juniper", "hilda", "hilbert", "cheren", "bianca", "mom" }
M.PORTRAIT = { first = 24, palette = 18 }
M.BACKGROUND = { first = 6, palettes = { 1, 2, 3, 4, 5 } }
M.W, M.H = 128, 192

local function u16(s, o) return s:byte(o + 1) + s:byte(o + 2) * 256 end

local function section(data, tag, skip)
  local at = data and data:find(tag, 1, true)
  return at and (at - 1 + skip) or nil
end

-- an 8bpp 16 x 24-tile sheet in its own palette, as RGBA
local function picture(sheet, pal)
  local chr, plt = section(sheet, "RAHC", 0x20), section(pal, "TTLP", 0x18)
  if not (chr and plt) then return nil end
  local colours = {}
  local function colour(i)
    local c = colours[i]
    if c then return c end
    local v = u16(pal, plt + i * 2)
    local function ch(n) n = n % 32 return string.char(n * 8 + math.floor(n / 4)) end
    c = ch(v) .. ch(math.floor(v / 32)) .. ch(math.floor(v / 1024)) .. "\255"
    colours[i] = c
    return c
  end
  local rows = {}
  for py = 0, M.H - 1 do
    local row = {}
    local ty, y = math.floor(py / 8), py % 8
    for px = 0, M.W - 1 do
      local t = ty * 16 + math.floor(px / 8)
      local ci = sheet:byte(chr + t * 64 + y * 8 + px % 8 + 1) or 0
      row[#row + 1] = ci == 0 and "\0\0\0\0" or colour(ci)
    end
    rows[#rows + 1] = table.concat(row)
  end
  return { width = M.W, height = M.H, rgba = table.concat(rows) }
end

function M.calls(arc)
  local out = {}
  for n = 1, arc.count - 1 - M.CALL_BASE do
    local d = arc:get(M.CALL_BASE + n)
    if not d or #d < 12 then break end
    local call = { textBank = M.TEXT_BASE + n, people = {}, panels = {}, steps = {} }
    for k = 0, 3 do
      local p = d:byte(k + 1)
      if p ~= 0xFF then call.people[#call.people + 1] = p end
      call.panels[k + 1] = d:byte(k + 5)
    end
    for o = 8, #d - 4, 4 do
      local op = d:byte(o + 1)
      if op == 0 then break end
      call.steps[#call.steps + 1] = { op = op, panel = d:byte(o + 2), line = d:byte(o + 3) }
    end
    out[n] = call
  end
  return out
end

function M.build(x)
  local arc = require("src.import.NarcArchive").parse(x.rom:read(M.PATH))
  if not arc then return nil, "no " .. M.PATH end
  local out = { calls = M.calls(arc), people = {}, backgrounds = {}, namesBank = M.NAMES_BANK,
                source = "ROM:" .. M.PATH .. " (ov174)" }
  for k, name in ipairs(M.PEOPLE) do
    local frames = {}
    for f = 0, 1 do
      local img = picture(arc:get(M.PORTRAIT.first + (k - 1) * 2 + f), arc:get(M.PORTRAIT.palette + k - 1))
      local e = img and x:saveImage(("xtransceiver/%s_%d"):format(name, f), img)
      if e then frames[#frames + 1] = e.path end
    end
    out.people[k] = { name = name, frames = frames }
    local bg = {}
    for _, p in ipairs(M.BACKGROUND.palettes) do
      local img = picture(arc:get(M.BACKGROUND.first + (k - 1) * 2), arc:get(p))
      local e = img and x:saveImage(("xtransceiver/bg%d_p%d"):format(k - 1, p), img)
      if e then bg[p] = e.path end
    end
    out.backgrounds[k] = bg
  end
  return out
end

return M
