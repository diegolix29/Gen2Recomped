-- Trainer class pictures: trfgra.narc, the front faces.
--
-- WHAT THE ARCHIVE IS.  525 members = 105 trainer classes of FIVE, in the
-- order the packer writes them (res/trainers/classes/meson.build feeds
-- `trainer_front_NCGR, trainer_front_NCER, trainer_front_NANR,
-- trainer_front_NCLR, trainer_front_scan_NCGR` through an `.order` file that
-- interleaves them per class):
--
--   +0 NCGR   the cell-based sprite      +1 NCLR   the class palette
--   +2 NCER   its cell bank              +3 NANR   its animation
--   +4 NCGR   the LINEAR sheet
--
-- Confirmed by reading the cartridge rather than by trusting the build file:
-- every member's magic was counted (105 RLCN, 105 RECN, 105 RNAN, 210 RGCN)
-- and the cycle is the same for all 105.
--
-- 105 IS THE TRAINER CLASS COUNT, not the trainer count -- `generated/
-- trainer_classes.txt` has exactly 105 rows, and
-- `SpriteSystem_SetTrainerClassGraphicsIndex(trainerClass, FACE_FRONT, ...)`
-- is what indexes this archive.  So the picture belongs to the CLASS: every
-- Youngster in Sinnoh shares one, which is why a trainer row carries `class`
-- and the extractor stamps the same path on all of them.
-- Verified by rendering: class 0 is the male player, 1 the female player,
-- 2 a Youngster, 12 a male Cyclist on a bicycle and 61 a female School Kid --
-- which is `trainer_classes.txt` line for line.
--
-- WHICH NCGR TO READ, and the two differ in kind rather than in quality.
-- Member +0 carries NO DIMENSIONS -- `tilesX`/`tilesY` come back nil, which is
-- what `-vram -clobbersize` produces: its size lives in the NCER beside it and
-- the hardware assembles it from cells.  Member +4 declares 20x10 tiles.  So
-- +4 is the one a reader can use without a cell walk, and it is the same
-- artwork.
--
-- 20x10 tiles is 160x80: TWO 80x80 FRAMES SIDE BY SIDE, the same shape
-- `pl_pokegra` uses.  But the proportions are the OPPOSITE way round, and that
-- decides how this is emitted.  Measured across all 105 classes:
--
--   two genuinely different frames   25
--   second frame EMPTY               80
--   identical frames                  0
--
-- A species sheet is 475-of-477 two-frame, so the strip is emitted whole and
-- `picAnim` cuts it.  Here four classes in five have a blank right half, so a
-- whole strip would draw every one of those trainers in the left half of a
-- double-width picture.  FRAME 1 IS THE PICTURE; the second frame is recorded
-- as a fact (`frames`) for an animation stage that does not exist yet, and not
-- emitted.
--
-- THE DATA IS ENCRYPTED, LIKE THE SPECIES SHEETS, and this is the one that
-- looks like something else when you get it wrong.  Read raw, member +4 is
-- 81% zero bytes and renders as coloured static -- which reads as a palette or
-- layout fault rather than an encryption one.  `Gen4Graphics.decryptSprite`
-- first, then `Gen4Graphics.indices`, and the figures appear.
--
-- THE PALETTE IS 256 ENTRIES AND THE SHEET IS 4BPP.  Only the first sixteen
-- are non-zero and the decrypted indices span exactly 0..15, so sub-palette 0
-- is the whole of it -- stated rather than searched for, because a 4bpp sheet
-- whose palette bank is picked wrong still renders a recognisable figure in
-- the wrong colours, which is a far harder fault to notice than static.

local Gen4Trgra = {}

local floor = math.floor
local char, concat = string.char, table.concat

Gen4Trgra.PATH = "/poketool/trgra/trfgra.narc"
Gen4Trgra.BACK_PATH = "/poketool/trgra/trbgra.narc"
Gen4Trgra.MEMBERS_PER_CLASS = 5

Gen4Trgra.SLOT = {
  sprite = 0, palette = 1, cells = 2, anim = 3, sheet = 4,
}

-- A frame is square and half the sheet, stated rather than derived so a member
-- with an unexpected width is caught instead of silently halved.
Gen4Trgra.FRAME = 80
Gen4Trgra.FRAMES = 2

-- Colour 0 is the transparent one, as everywhere else in this cartridge.
Gen4Trgra.TRANSPARENT = 0

function Gen4Trgra.classCount(narc)
  if not narc or not narc.count then return 0 end
  return floor(narc.count / Gen4Trgra.MEMBERS_PER_CLASS)
end

-- sheet(narc, Gen4Graphics, class) -> { pixels, width, height, bpp }
-- `pixels` is DECRYPTED and linear, one nibble per pixel, low nibble first.
function Gen4Trgra.sheet(narc, Gen4Graphics, class)
  if not narc then return nil end
  local member = narc:get(class * Gen4Trgra.MEMBERS_PER_CLASS + Gen4Trgra.SLOT.sheet)
  if not (member and #member > 0) then return nil end
  local info = Gen4Graphics.tiles(member)
  if not (info and info.tilesX and info.tilesY) then return nil end
  return {
    pixels = Gen4Graphics.decryptSprite(info.pixels),
    width = info.tilesX * 8,
    height = info.tilesY * 8,
    bitmap = info.bitmap,
    bpp = info.bpp,
  }
end

function Gen4Trgra.palette(narc, Gen4Graphics, class)
  if not narc then return nil end
  local member = narc:get(class * Gen4Trgra.MEMBERS_PER_CLASS + Gen4Trgra.SLOT.palette)
  if not (member and #member > 0) then return nil end
  return Gen4Graphics.palette(member)
end

local function indexAt(sheet, x, y)
  local linear = y * sheet.width + x
  local b = sheet.pixels:byte(floor(linear / 2) + 1)
  if not b then return 0 end
  if linear % 2 == 0 then return b % 16 end
  return floor(b / 16)
end

local function paint(sheet, colours, x0, x1)
  local h = sheet.height
  local out, n = {}, 0
  local blank = char(0, 0, 0, 0)
  for y = 0, h - 1 do
    for x = x0, x1 do
      local index = indexAt(sheet, x, y)
      local colour = colours and colours[index + 1]
      n = n + 1
      if index == Gen4Trgra.TRANSPARENT or not colour then
        out[n] = blank
      else
        out[n] = char(colour[1], colour[2], colour[3], 255)
      end
    end
  end
  return { width = x1 - x0 + 1, height = h, rgba = concat(out) }
end

-- One 80x80 frame, 1-based.
function Gen4Trgra.frame(sheet, colours, index)
  if not sheet then return nil end
  local frameWidth = floor(sheet.width / Gen4Trgra.FRAMES)
  local x0 = ((index or 1) - 1) * frameWidth
  if x0 < 0 or x0 + frameWidth > sheet.width then return nil end
  return paint(sheet, colours, x0, x0 + frameWidth - 1)
end

-- Does the second frame carry anything?  Answered rather than assumed, because
-- four classes in five leave it blank and a caller that emits the strip
-- regardless would give those trainers a double-width picture with a hole in
-- it.
function Gen4Trgra.framesUsed(sheet)
  if not sheet then return 0 end
  local half = floor(sheet.width / Gen4Trgra.FRAMES)
  for y = 0, sheet.height - 1 do
    for x = half, sheet.width - 1 do
      if indexAt(sheet, x, y) ~= Gen4Trgra.TRANSPARENT then return 2 end
    end
  end
  return 1
end

-- A filename that says who it is, on the same pattern as the species slugs.
function Gen4Trgra.slug(class, name)
  if type(name) ~= "string" or name == "" then
    return ("%03d"):format(class)
  end
  local slug = name:lower():gsub("[^a-z0-9]+", "_"):gsub("^_+", ""):gsub("_+$", "")
  if slug == "" then return ("%03d"):format(class) end
  return ("%03d_%s"):format(class, slug)
end

return Gen4Trgra
