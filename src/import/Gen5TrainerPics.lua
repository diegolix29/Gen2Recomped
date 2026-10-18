-- BLACK AND WHITE'S TRAINER BATTLE PICTURES (/a/0/7/2, the trfgra archive).
--
-- Eight members a picture, picture 0 at member 0:
--
--   +0  front, 80 x 80 (LZ11 RGCN, 100 tiles)     +1  animation parts
--   +2  RECN   +3 RNAN   +4 RCMN   +5 RAMN   +6 the animation script
--   +7  palette (RLCN)
--
-- The 80 x 80 still is 1D-mapped for five OAM blocks -- 64x64 at (0, 0),
-- 16x64 at (64, 0), 32x16 at (0, 64), 32x16 at (32, 64), 16x16 at (64, 64)
-- = 64 + 16 + 8 + 8 + 4 = 100 tiles, the size of every member.
--
-- WHICH PICTURE A CLASS WEARS is not its number: there are 95 pictures and
-- classes up to 102. `classPics` (filled by RomExtractorGen5 from the ARM9
-- table, see M.findClassTable) maps one to the other; without it a class
-- falls back to its own number when that is in range.

local M = {}

M.PATH = "/a/0/7/2"
-- the player characters' backs, the same eight-member layout (6 pictures)
M.BACK_PATH = "/a/0/7/3"
M.STRIDE = 8
M.SIZE = 80
M.BLOCKS = { { 0, 0, 8, 8 }, { 8, 0, 2, 8 }, { 0, 8, 4, 2 }, { 4, 8, 4, 2 }, { 8, 8, 2, 2 } }

local function cellsFor()
  local grid, t, wide = {}, 0, M.SIZE / 8
  for _, bl in ipairs(M.BLOCKS) do
    for ty = 0, bl[4] - 1 do
      for tx = 0, bl[3] - 1 do
        grid[(bl[2] + ty) * wide + bl[1] + tx + 1] = { tile = t, palette = 0 }
        t = t + 1
      end
    end
  end
  return { width = M.SIZE, height = M.SIZE, cells = grid }
end

-- THE CLASS -> PICTURE TABLE: one byte per class in the ARM9 (0x9C23C in
-- Black), found by content -- the pictures run 0..46 in class order, and
-- class 47 (Team Plasma's N) borrows picture 40. Read for `classes` bytes.
M.CLASSES = 105
function M.findClassTable(arm9, pictures)
  if type(arm9) ~= "string" then return nil end
  local sig = {}
  for i = 0, 46 do sig[#sig + 1] = string.char(i) end
  sig[#sig + 1] = string.char(40)
  local at = arm9:find(table.concat(sig), 1, true)
  if not at then return nil end
  local map = {}
  for c = 0, M.CLASSES - 1 do
    local p = arm9:byte(at + c)
    if not p or (pictures and p >= pictures) then break end
    map[c] = p
  end
  return map
end

function M.count(arc)
  return math.floor((arc and arc.count or 0) / M.STRIDE)
end

-- picture(arc, n) -> image (rgba) or nil
function M.picture(arc, n)
  local G = require("src.import.Gen4Graphics")
  local Lz = require("src.import.Gen5Lz")
  local function member(i)
    local b = arc:get(i)
    if not b or #b == 0 then return nil end
    if Lz.isCompressed(b) then b = Lz.decompress(b) end
    return b
  end
  local sheetBytes = member(n * M.STRIDE)
  local palBytes = member(n * M.STRIDE + 7)
  local sheet = sheetBytes and G.tiles(sheetBytes)
  local pal = palBytes and G.palette(palBytes)
  if not (sheet and pal) then return nil end
  return G.compose(cellsFor(), sheet, pal)
end

-- THE BACKS ARE NOT THE STILL. The +0 sheet of /a/0/7/3 does not hold a
-- standing back; the battle draws cell 0 of the RECN (+2) over the parts
-- sheet (+1), a LINEAR 256 x 128 bitmap read as a 32-tile-wide grid (an OAM's
-- tile t starts at pixel (8 (t % 32), 8 floor(t / 32))). Cell 0 is the
-- standing pose: 56 x 128, the whole figure, cut off by the screen's foot.
function M.back(arc, n)
  local G = require("src.import.Gen4Graphics")
  local Cells = require("src.import.Gen4Cells")
  local Lz = require("src.import.Gen5Lz")
  local function member(i)
    local b = arc:get(i)
    if not b or #b == 0 then return nil end
    if Lz.isCompressed(b) then b = Lz.decompress(b) end
    return b
  end
  local sheet = member(n * M.STRIDE + 1)
  sheet = sheet and G.tiles(sheet)
  local bank = Cells.parse(member(n * M.STRIDE + 2), G)
  local pal = G.palette(member(n * M.STRIDE + 7))
  local cell = bank and bank.cells and bank.cells[1]
  if not (sheet and sheet.pixels and cell and pal) then return nil end
  local minX, minY, w, h = Cells.extent(cell)
  if not w then return nil end
  local px, sheetW = sheet.pixels, 256
  local function index(x, y)
    local p = y * sheetW + x
    local b = px:byte(math.floor(p / 2) + 1) or 0
    return (p % 2 == 1) and math.floor(b / 16) or (b % 16)
  end
  local out = {}
  for i = 1, w * h do out[i] = "\0\0\0\0" end
  for k = #cell.oam, 1, -1 do
    local o = cell.oam[k]
    local sx, sy = (o.tile % 32) * 8, math.floor(o.tile / 32) * 8
    for y = 0, o.height - 1 do
      for x = 0, o.width - 1 do
        local c = index(sx + (o.flipX and o.width - 1 - x or x), sy + (o.flipY and o.height - 1 - y or y))
        local rgb = c > 0 and pal[c + 1]
        if rgb then
          out[(o.y - minY + y) * w + (o.x - minX + x) + 1] =
            string.char(rgb[1], rgb[2], rgb[3], 255)
        end
      end
    end
  end
  return { width = w, height = h, rgba = table.concat(out) }
end

-- build(x, trainers) -> index; saves battle/trainer/NNN.png and stamps
-- `pic` on every trainer row whose class has a picture
function M.build(x, trainers, classPics)
  local raw = x.rom:read(M.PATH)
  local arc = raw and require("src.import.NarcArchive").parse(raw)
  if not arc then return nil end
  local index = { pictures = {}, classes = {}, counts = { pictures = 0, stamped = 0 } }
  local n = M.count(arc)
  classPics = classPics or M.findClassTable(x.rom:arm9(), n)
  index.classPics = classPics
  for i = 0, n - 1 do
    local image = M.picture(arc, i)
    local entry = image and x:saveImage(("battle/trainer/%03d"):format(i), image)
    if entry then
      index.pictures[i] = entry
      index.counts.pictures = index.counts.pictures + 1
    end
  end
  -- the player characters' backs (0 Hilbert, 1 Hilda, ...)
  index.backs = {}
  local backRaw = x.rom:read(M.BACK_PATH)
  local backs = backRaw and require("src.import.NarcArchive").parse(backRaw)
  for i = 0, M.count(backs) - 1 do
    local image = M.back(backs, i)
    local entry = image and x:saveImage(("battle/trainer_back/%03d"):format(i), image)
    if entry then index.backs[i] = entry end
  end
  local function picFor(class)
    local p = classPics and classPics[class]
    if p == nil and class and class < n then p = class end
    return p and index.pictures[p]
  end
  for _, t in pairs(trainers or {}) do
    local entry = t.class and picFor(t.class)
    if entry then
      t.pic = entry.path
      t.trueColor = true
      index.classes[t.class] = entry
      index.counts.stamped = index.counts.stamped + 1
    end
  end
  return index
end

return M
