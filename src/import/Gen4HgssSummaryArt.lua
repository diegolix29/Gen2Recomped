-- HEARTGOLD / SOULSILVER'S POKEMON SUMMARY (pokeheartgold asm/unk_02088288.s,
-- asm/unk_0208B1AC.s; scratch_claude/hgss_ui_screens_map.md "Summary"),
-- written as `gen4_hgss_summary_art`. Every background is /a/1/6/2's
-- (`sub_020887C4`): palette 0 for both screens, char 2 under the top pages,
-- char 1 under the touch pages.
--
--   top_<page>      13 info (trainer memo) / 19 skills / 10 ribbons
--   touch_<page>    12 info / 17 moves / 9 ribbons; 77 / 78 the same with two
--                   tabs (no ribbons); 18 moves with a fifth row (learning)
--   ball_<b>        the caught ball, b = BALL_* 0..25: char 25 for none, else
--                   24 + b; palette 49 + `_02104C68`[b]

local A = {}

A.PATH = "/a/1/6/2"
A.TOP = { info = 13, skills = 19, ribbons = 10 }
A.TOUCH = { info = 12, moves = 17, ribbons = 9, info_two = 77, moves_two = 78, moves_learn = 18 }
-- `_02104C68`, BALL_NONE .. BALL_SPORT (BALL_PARK takes the last row too)
A.BALL_PALETTE = { [0] = 2, 0, 2, 2, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 2, 0, 4, 5, 6, 7, 8, 9, 10, 11, 11 }

function A.images(rom)
  local G = require("src.import.Gen4Graphics")
  local raw = rom:read(A.PATH)
  local arc = raw and require("src.import.NarcArchive").parse(raw)
  if not arc then return nil end
  local function m(i) local b = arc:get(i); if b and G.isCompressed(b) then b = G.decompress(b) end return b end
  local pal = G.palette(m(0))
  if not pal then return nil end
  local out = {}
  local function page(key, screen, chars)
    local map = G.tilemap(m(screen))
    local img = map and chars and G.compose(map, chars, pal)
    if img and img.height > 192 then img = { width = img.width, height = 192, rgba = img.rgba:sub(1, img.width * 192 * 4) } end
    out[key] = img
  end
  local top, touch = G.tiles(m(2)), G.tiles(m(1))
  for k, s in pairs(A.TOP) do page("top_" .. k, s, top) end
  for k, s in pairs(A.TOUCH) do page("touch_" .. k, s, touch) end
  for b = 0, 25 do
    local sheet = G.tiles(m(b == 0 and 25 or 24 + b))
    local bp = G.palette(m(49 + (A.BALL_PALETTE[b] or 0)))
    if sheet and bp then
      -- a 32 x 32 OBJ, 1D: its sixteen tiles in reading order
      local side = math.floor(math.sqrt(sheet.count) + 0.5)
      local cells = {}
      for t = 0, side * side - 1 do cells[t + 1] = { tile = t, palette = 0 } end
      local img = G.compose({ width = side * 8, height = side * 8, cells = cells }, sheet, bp)
      if img then img.originX, img.originY = -side * 4, -side * 4; out["ball_" .. b] = img end
    end
  end
  return out
end

return A
