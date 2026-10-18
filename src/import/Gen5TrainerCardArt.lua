-- BLACK AND WHITE'S TRAINER CARD (/a/0/4/0, the same in both games), in the
-- shape Gen4TrainerCardArt writes Platinum's so the card screen reads either;
-- `bw = true` in the index tells it which layout. (bw_ui_map.md's "/a/0/6/3"
-- is another app's; this archive is the one with TRAINER CARD in its header.)
--
-- No symbols: the pairings were found by composing every map on every tileset
-- and palette (scratch_claude/bw040*), and are the ones that come out clean.
--
--   palettes 0-24     5-10 Black's six card levels, 15-20 White's -- Normal,
--                     Purple, Red, Silver, Gold, Black / White, the order
--                     Bulbapedia's level table gives and the colours agree;
--                     21 / 22 / 23 the badges clean / dulled / dirty
--   41 on tileset 28  the front (TRAINER CARD header, photo box, rows)
--   36 on tileset 28  the back (a records box over the signature box)
--   43 / 44 on 31     Hilbert / Hilda, full-screen maps over the photo box
--   33 on 25          the badge board: eight sockets in a strip, y 88..168
--   27 / 45           the badges, cells 0-7 (32 x 64, anchored at the centre)
--
-- BY EYE, and the record says so: the board's palette (2, the gold one -- the
-- palette the archive leaves unassigned to any card), and that 38 / 39 / 42 on
-- tileset 32 -- the same faces with a decorated rim -- are not used.

local C = {}

C.PATH = "/a/0/4/0"
C.LEVELS = { "normal", "cobalt", "bronze", "silver", "gold", "black" } -- Gen4TrainerCard's key names
C.FIRST_LEVEL = { black = 5, white = 15 }
C.FRONT, C.BACK, C.CARD_TILES = 41, 36, 28
C.TRAINERS, C.TRAINER_TILES = { hilbert = 43, hilda = 44 }, 31
C.BOARD, C.BOARD_TILES, C.BOARD_PALETTE = 33, 25, 2
C.BADGE_TILES, C.BADGE_CELLS, C.BADGE_PALETTES = 27, 45, { 21, 22, 23 }
-- the sockets' centres, measured on the composed board
C.BADGE_AT = {}
for i = 0, 7 do C.BADGE_AT[i + 1] = { 16 + 32 * i, 128 } end

function C.build(x)
  local G = require("src.import.Gen4Graphics")
  local Cells = require("src.import.Gen4Cells")
  local raw = x.rom:read(C.PATH)
  local arc = raw and require("src.import.NarcArchive").parse(raw)
  if not arc then return nil end
  local function pal(i) local p = G.palette(arc:get(i)); return p end
  local index = { bw = true, badgeAt = C.BADGE_AT,
                  _source = "ROM:/a/0/4/0 (front 41 / back 36 on 28, trainers 43/44 on 31, board 33 on 25, badges 27/45)" }
  local function save(key, image, extra)
    local entry = image and x:saveImage("trainer_card_art/" .. key, image, extra)
    if entry then index[key] = entry end
  end
  local first = C.FIRST_LEVEL[x.version] or C.FIRST_LEVEL.black
  local sheet, front, back = G.tiles(arc:get(C.CARD_TILES)), G.tilemap(arc:get(C.FRONT)), G.tilemap(arc:get(C.BACK))
  local trainerSheet = G.tiles(arc:get(C.TRAINER_TILES))
  for i, name in ipairs(C.LEVELS) do
    local p = pal(first + i - 1)
    if p and sheet then
      save("front_" .. name, G.compose(front, sheet, p))
      save("back_" .. name, G.compose(back, sheet, p))
    end
  end
  -- the no-dex face is the normal one: BW's card shows no POKeDEX band to hide
  index.front_no_dex, index.back_no_dex = index.front_normal, index.back_normal
  local p0 = pal(first)
  for who, m in pairs(C.TRAINERS) do
    local map = G.tilemap(arc:get(m))
    if map and trainerSheet and p0 then save(who, G.compose(map, trainerSheet, p0)) end
  end
  local boardPal = pal(C.BOARD_PALETTE)
  local board = G.tilemap(arc:get(C.BOARD))
  local boardSheet = G.tiles(arc:get(C.BOARD_TILES))
  if board and boardSheet and boardPal then save("badge_board", G.compose(board, boardSheet, boardPal)) end
  local bs, bank = G.tiles(arc:get(C.BADGE_TILES)), Cells.parse(arc:get(C.BADGE_CELLS), G)
  if bs and bank then
    for dirt, pi in ipairs(C.BADGE_PALETTES) do
      local p = pal(pi)
      for i = 0, 7 do
        local cell = bank.cells[i + 1]
        local pic = cell and p and Cells.assemble(cell, bs, p, bank, G)
        if pic then
          local ox, oy = Cells.extent(cell)
          save(("badge_%d_%d"):format(i, dirt - 1), pic, { originX = ox, originY = oy })
        end
      end
    end
    for i = 0, 7 do index["badge_" .. i] = index[("badge_%d_0"):format(i)] end
  end
  return index
end

return C
