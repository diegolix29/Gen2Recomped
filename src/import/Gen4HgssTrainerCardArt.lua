-- HEARTGOLD / SOULSILVER'S TRAINER CARD ART (/a/0/4/9, overlay 51
-- `ov51_*`; scratch_claude/hgss_ui_screens_map.md "Trainer card"), written in
-- the shape Gen4TrainerCardArt writes Platinum's so `Gen4TrainerCard` reads
-- either -- plus what HGSS has and Platinum has not.
--
-- THE SCREENS ARE THE OTHER WAY ROUND.  `ov51` ORs 0x8000 into POWCNT: the
-- main engine is on TOP.  The badge board is the top screen and the card is
-- on the touch screen; there is no case, no lid and no polishing by touch.
--
--   top     BG3 50 the blue-diamond backdrop, BG2 43 + 51 (Johto: eight
--           leaders) or 52 (Johto + Kanto: sixteen), the whole main BG
--           palette 28; the emblem patch 53 copied over BG2 (0, 7)
--   touch   BG6 (affine, 8bpp) the card 41 + 47 front / 48 back on palette
--           0 with the level's rows 1-8 and 15 (members 0-5, no-dex 6:
--           `ov51_021E60F4`); BG5 the frame 42 / 49 over it; BG7 the trainer
--           44 + 54 Ethan / 55 Lyra and the text
--
-- PICTURES (keys as Gen4TrainerCardArt's where the role is the same):
--
--   front_<level> / back_<level>   level normal cobalt bronze silver gold
--                                  black no_dex
--   card_frame                     42 / 49, over the card
--   ethan / lyra                   the trainer, a full-screen map
--   badge_backdrop                 50
--   badge_board_johto / _kanto     51 / 52 (the "LEAGUE BADGES" header baked in)
--   badge_<i>                      badge i (0 Zephyr .. 7 Rising, 8 Boulder ..
--                                  15 Earth), animation i of 59 on 58 / 46 / 30;
--                                  anchored at BADGE_AT (`ov51_021E801C`)
--   emblem_johto / _kanto          53's two 7 x 9-tile emblems, over a band's
--                                  empty ring once its eight badges are won
--   button_<a>_<f>                 the two touch buttons, 45 / 29 / 56 / 57:
--                                  animation a, frame f
--
-- Written to assets/generated/gen4/trainer_card_art/<key>.png, cache module
-- `gen4_trainer_card_art`, with `hgss = true` in the index so the screen knows
-- which layout it is reading.

local H = {}

H.PATH = "/a/0/4/9"
H.LEVELS = { "normal", "cobalt", "bronze", "silver", "gold", "black" }
H.NO_DEX = "no_dex"
H.NO_DEX_PALETTE = 6
H.LEVEL_ROWS = { 1, 8 } -- rows 1..8, and row 15

H.CARD_TILES, H.FRONT, H.BACK = 41, 47, 48
H.FRAME_TILES, H.FRAME_MAP = 42, 49
H.TRAINER_TILES, H.TRAINERS = 44, { ethan = 54, lyra = 55 }
H.BOARD_PALETTE, H.BOARD_TILES = 28, 43
H.BOARDS = { badge_board_johto = 51, badge_board_kanto = 52 }
H.BACKDROP = 50
H.EMBLEM, H.EMBLEM_W, H.EMBLEM_H = 53, 56, 72
-- where an emblem covers its band's empty ring, in tiles: the Johto band of
-- 51 at (0, 7) (asm:1262-1300), the Kanto band of 52 at (0, 14) -- MEASURED
-- off the composed board (the ring's centre at y 147), not read from code
H.EMBLEM_AT = { johto = { 0, 7 }, kanto = { 0, 14 } }
H.BADGE_TILES, H.BADGE_PALETTE, H.BADGE_CELLS, H.BADGE_ANIMS = 46, 30, 58, 59
H.BUTTON_TILES, H.BUTTON_PALETTE, H.BUTTON_CELLS, H.BUTTON_ANIMS = 45, 29, 56, 57

-- `ov51_021E801C`: four columns, four rows; without Kanto the eight sit 40
-- lower and 8..15 are not drawn
H.BADGE_AT = {}
for i = 0, 15 do
  H.BADGE_AT[i + 1] = { ({ 96, 144, 192, 240 })[i % 4 + 1], ({ 48, 88, 136, 176 })[math.floor(i / 4) + 1] }
end
H.JOHTO_ONLY_DROP = 40

-- the buttons' sprites (asm:4063-4078): anim 0 at (192, 168), anim 4 at (0, 168)
H.BUTTONS = { back = { anim = 0, x = 192, y = 168 }, flip = { anim = 4, x = 0, y = 168 } }

local opener

function H.crop(img, x, y, w, h)
  local rows = {}
  for r = 0, h - 1 do
    local from = ((y + r) * img.width + x) * 4
    rows[#rows + 1] = img.rgba:sub(from + 1, from + w * 4)
  end
  return { width = w, height = h, rgba = table.concat(rows) }
end

-- the card's letter and shadow, TEXT_COLOR(1, 2, 0) on row 15 -- a row each
-- level palette rewrites -- as { [face] = { letter, shadow } }, 0..1
function H.ink(rom)
  local G = require("src.import.Gen4Graphics")
  local member = opener(rom)
  if not member then return nil end
  local normal = G.palette(member(0))
  if not normal then return nil end
  local out = {}
  local faces = {}
  for i, name in ipairs(H.LEVELS) do faces[name] = i - 1 end
  faces[H.NO_DEX] = H.NO_DEX_PALETTE
  for name, i in pairs(faces) do
    local pal = H.cardPalette(normal, G.palette(member(i)))
    local function c(k) local v = pal[15 * 16 + k + 1] or { 0, 0, 0 }; return { v[1] / 255, v[2] / 255, v[3] / 255 } end
    out[name] = { c(1), c(2) }
  end
  return out
end

function opener(rom)
  local G = require("src.import.Gen4Graphics")
  local bytes = rom:read(H.PATH)
  local narc = bytes and require("src.import.NarcArchive").parse(bytes)
  if not narc then return nil end
  return function(i)
    local b = narc:get(i)
    if b and G.isCompressed(b) then b = G.decompress(b) end
    if b and #b == 0 then return nil end
    return b
  end
end

local function copy(colours)
  local out = {}
  for i = 1, 256 do out[i] = colours and colours[i] or { 0, 0, 0 } end
  return out
end

local function putRows(into, from, first, count)
  for i = first * 16 + 1, (first + count) * 16 do
    if from[i] then into[i] = from[i] end
  end
end

function H.cardPalette(normal, level)
  local pal = copy(normal)
  if level then
    putRows(pal, level, H.LEVEL_ROWS[1], H.LEVEL_ROWS[2])
    putRows(pal, level, 15, 1)
  end
  return pal
end

function H.images(rom)
  local G = require("src.import.Gen4Graphics")
  local Cells = require("src.import.Gen4Cells")
  local Anim = require("src.import.Gen4CellAnim")
  local member = opener(rom)
  if not member then return nil, "/a/0/4/9 missing" end
  local out = {}

  local normal = G.palette(member(0))
  if not normal then return nil, "/a/0/4/9 card palette unreadable" end
  local sheet = G.tiles(member(H.CARD_TILES))
  local front, back = G.tilemap(member(H.FRONT)), G.tilemap(member(H.BACK))
  local faces = {}
  for i, name in ipairs(H.LEVELS) do faces[#faces + 1] = { name, i - 1 } end
  faces[#faces + 1] = { H.NO_DEX, H.NO_DEX_PALETTE }
  for _, f in ipairs(faces) do
    local pal = H.cardPalette(normal, G.palette(member(f[2])))
    if sheet and front then out["front_" .. f[1]] = G.compose(front, sheet, pal) end
    if sheet and back then out["back_" .. f[1]] = G.compose(back, sheet, pal) end
  end

  local s, m = G.tiles(member(H.FRAME_TILES)), G.tilemap(member(H.FRAME_MAP))
  if s and m then out.card_frame = G.compose(m, s, normal) end
  s = G.tiles(member(H.TRAINER_TILES))
  for who, i in pairs(H.TRAINERS) do
    m = G.tilemap(member(i))
    if s and m then out[who] = G.compose(m, s, normal) end
  end

  local board = G.palette(member(H.BOARD_PALETTE))
  if board then
    s = G.tiles(member(H.BOARD_TILES))
    for key, i in pairs(H.BOARDS) do
      m = G.tilemap(member(i))
      if s and m then out[key] = G.compose(m, s, board) end
    end
    m = G.tilemap(member(H.BACKDROP))
    if s and m then out.badge_backdrop = G.compose(m, s, board) end
    -- the emblem patch: two 7 x 9-tile emblems side by side, the Johto one
    -- (teal ground) and the Kanto one (cream)
    m = G.tilemap(member(H.EMBLEM))
    local patch = s and m and G.compose(m, s, board)
    if patch then
      for k, key in ipairs({ "emblem_johto", "emblem_kanto" }) do
        out[key] = H.crop(patch, (k - 1) * H.EMBLEM_W, 0, H.EMBLEM_W, H.EMBLEM_H)
      end
    end
  end

  local function sprites(tiles, palette, cells, anims, each)
    local sh, pal = G.tiles(member(tiles)), G.palette(member(palette))
    local bank = Cells.parse(member(cells), G)
    local anim = Anim.parse(member(anims), G)
    if not (sh and pal and bank) then return end
    local full = copy(pal)
    each(function(seq)
      return anim and Anim.frames(anim, seq) or {}
    end, function(key, cellIndex)
      local cell = bank.cells[cellIndex + 1]
      local pic = cell and #cell.oam > 0 and Cells.assemble(cell, sh, full, bank, G)
      if pic then
        pic.originX, pic.originY = Cells.extent(cell)
        out[key] = pic
      end
    end)
  end
  sprites(H.BADGE_TILES, H.BADGE_PALETTE, H.BADGE_CELLS, H.BADGE_ANIMS, function(frames, put)
    for i = 0, 15 do
      local f = frames(i)
      put("badge_" .. i, f[1] and f[1].cell or i)
    end
  end)
  sprites(H.BUTTON_TILES, H.BUTTON_PALETTE, H.BUTTON_CELLS, H.BUTTON_ANIMS, function(frames, put)
    for a = 0, 5 do
      for k, fr in ipairs(frames(a)) do put(("button_%d_%d"):format(a, k - 1), fr.cell) end
    end
  end)

  for k, v in pairs(out) do if not v then out[k] = nil end end
  return out
end

return H
