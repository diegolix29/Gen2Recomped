-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Gen 4 (Platinum) graphics: Nitro containers, palettes, tiles, tilemaps and
-- the LZ77 the cartridge wraps most of them in.
--
-- Every later stage needs this, which is why it comes before maps and items.
-- A DS graphic is not a blob at an address the way a Gen 1-3 one is; it is a
-- small tagged container, and there are four of them that matter:
--
--   NCLR  "RLCN"  palette   -- section TTLP, BGR555 colours
--   NCGR  "RGCN"  tiles     -- section RAHC, 8x8 tiles, 4bpp or 8bpp
--   NSCR  "RCSN"  tilemap   -- section NRCS, u16 per cell
--   NCER  "RECN"  cells     -- section CEBK, sprite assembly (not parsed here)
--
-- THE MAGICS ARE STORED REVERSED, exactly as NarcArchive's chunk tags are:
-- the file tagged NCLR begins with the bytes "RLCN".  Both spellings appear
-- in circulation, so this compares the four bytes that are actually there.
--
-- WHAT WAS MEASURED RATHER THAN ASSUMED.
--
--   * Section layout is found by WALKING from headerSize for sectionCount
--     chunks, never by fixed offset -- both fields exist because they vary.
--   * The bit depth is confirmed by ARITHMETIC, not by trusting the enum:
--     a 4bpp tile is 32 bytes, so tilesX * tilesY * 32 == dataSize settles
--     it.  pokegra's sprite sheets are 20x10 tiles and 6400 bytes, which is
--     4bpp exactly.
--   * The colour count is dataSize / 2 rather than read from the depth
--     field, which is the one field here whose meaning did not survive
--     inspection: a 16-colour Platinum palette carries 4 where the published
--     tables say 3.  Since the byte count is unambiguous and self-checking,
--     nothing needs the enum to be right.
--   * tilesX / tilesY are 0xFFFF on an UNSIZED graphic -- every party icon
--     is one.  Those get their shape from the NCER cell bank, or from the
--     caller; `tiles` is always correct because it comes from the byte
--     count.  Reading 0xFFFF as a width produces a 65535-tile-wide image and
--     an out-of-memory rather than a wrong picture, which at least fails
--     loudly, but it still has to be handled.
--
-- VALIDATION.  The parser was run against the cartridge and the result
-- looked at, not just counted: all 540 party icons in
-- /poketool/icongra/pl_poke_icon.narc render as recognisable Pokemon in the
-- right colours.  The LZ was checked on every compressed member of four
-- graphics archives -- 125 of 125 decompress to exactly their declared size
-- and every one of them turns out to be a valid Nitro container (48 NCGR,
-- 27 NSCR, 23 NCER, 23 NANR).
--
-- THE BATTLE SPRITES NEED TWO MORE THINGS, and both of them look like the
-- other one when you only have one.  pokegra and otherpoke are ENCRYPTED
-- (see decryptSprite) and they are also stored as LINEAR BITMAPS rather than
-- as 8x8 tiles (see `bitmap`).  Decrypt without un-tiling and you get real
-- Pokemon colours smeared into horizontal bands, which reads as "the cipher
-- is nearly right"; un-tile without decrypting and you get noise, which reads
-- as "the layout is fine, the cipher is wrong".  Neither is a clue about the
-- other, and chasing either one alone goes nowhere.

local Gen4Graphics = {}

local byte, sub, floor = string.byte, string.sub, math.floor
local char, concat = string.char, table.concat

local function u16(s, at)
  local a, b = byte(s, at, at + 1)
  if not b then return nil end
  return a + b * 256
end

local function u32(s, at)
  local a, b, c, d = byte(s, at, at + 3)
  if not d then return nil end
  return a + b * 256 + c * 65536 + d * 16777216
end

-- The archives whose NCGR tile data is encrypted.  Measured, not guessed:
-- these four sit at byte entropy ~7.98 raw and drop to ~0.9 once decrypted,
-- while the trainer sprites in trfgra/trbgra are already 4.8-5.3 raw and are
-- NOT encrypted -- they are merely linear, which is a separate thing.
Gen4Graphics.ENCRYPTED = {
  ["/poketool/pokegra/pl_pokegra.narc"] = true,
  ["/poketool/pokegra/pokegra.narc"] = true,
  ["/poketool/pokegra/otherpoke.narc"] = true,
  ["/poketool/pokegra/pl_otherpoke.narc"] = true,
}

-- pokegra's stride: six members per species -- four NCGR (back female, back
-- male, front female, front male) then two NCLR (normal, shiny).
Gen4Graphics.POKEGRA_STRIDE = 6
Gen4Graphics.POKEGRA_FRONT = 3
Gen4Graphics.POKEGRA_PALETTE = 4
Gen4Graphics.POKEGRA_SHINY = 5

-- ---------------------------------------------------------------------------
-- LZ77, Nitro type 0x10
-- ---------------------------------------------------------------------------

-- A member whose first byte is 0x10 is compressed and the next three bytes
-- are the DECOMPRESSED size, little-endian.  Then flag bytes, each covering
-- eight slots from the high bit down: a clear bit copies one literal byte, a
-- set bit is a two-byte back-reference of (hi >> 4) + 3 bytes from
-- ((hi & 0xF) << 8 | lo) + 1 back.
--
-- The back-reference may overlap what it is still writing -- a run of one
-- byte repeated is spelled as a distance of 1 -- so this copies one byte at a
-- time rather than slicing, which would read the pre-copy state and quietly
-- produce the wrong bytes on exactly the runs that compress best.
function Gen4Graphics.isCompressed(data)
  if type(data) ~= "string" or #data <= 4 or byte(data, 1) ~= 0x10 then return false end
  -- THE SIZE MUST BE NON-ZERO, and the check is not pedantry.  Platinum's four
  -- NFGR fonts begin `10 00 00 00` -- 0x10 is the font's own data offset, not a
  -- compression tag -- so a test on the first byte alone accepts them, reads a
  -- declared output size of ZERO, and returns an empty string.  Not an error and
  -- not garbage: the file simply vanishes, and the caller sees a zero-length
  -- member rather than a misread one.  A real LZ member never declares zero,
  -- because there would be nothing to decompress.
  local a, b, c = byte(data, 2, 4)
  return (a + b * 256 + c * 65536) > 0
end

function Gen4Graphics.decompress(data)
  if not Gen4Graphics.isCompressed(data) then return data end
  local a, b, c = byte(data, 2, 4)
  local size = a + b * 256 + c * 65536
  local out, n, p = {}, 0, 5
  local len = #data
  while n < size and p <= len do
    local flags = byte(data, p); p = p + 1
    for bit = 7, 0, -1 do
      if n >= size then break end
      if floor(flags / 2 ^ bit) % 2 == 1 then
        local hi, lo = byte(data, p, p + 1)
        if not lo then return nil, "LZ stream ends inside a back-reference" end
        p = p + 2
        local count = floor(hi / 16) + 3
        local dist = (hi % 16) * 256 + lo + 1
        if dist > n then return nil, "LZ back-reference points before the start" end
        for _ = 1, count do
          n = n + 1
          out[n] = out[n - dist]
          if n >= size then break end
        end
      else
        local v = byte(data, p)
        if not v then return nil, "LZ stream ends inside a literal" end
        p = p + 1
        n = n + 1
        out[n] = string.char(v)
      end
    end
  end
  if n < size then return nil, ("LZ produced %d of %d bytes"):format(n, size) end
  return table.concat(out, "", 1, size)
end

-- ---------------------------------------------------------------------------
-- The battle-sprite cipher
-- ---------------------------------------------------------------------------

-- pokegra and otherpoke XOR their tile data with a keystream from the same
-- linear congruential generator the series uses everywhere else:
--
--   key = the FIRST halfword of the data
--   for each halfword:  plain = cipher ~ key;  key = (key * 0x41C64E6D + 0x6073) % 2^16
--
-- Only the low 16 bits of the state ever matter, because the output is the
-- low 16 bits and an LCG's low bits depend on nothing above them -- so this
-- keeps the state in 16 bits and never needs 32-bit arithmetic Lua 5.1 would
-- make awkward.
--
-- The first halfword being the key is the same statement as "the first
-- halfword of the picture is transparent", since anything XORed with itself
-- is zero.  Every sprite in the cartridge begins with blank pixels, so this
-- is self-seeding and there is no table of keys anywhere.
--
-- HOW THIS WAS FOUND, because the wrong way round wasted real time.  The
-- published constants were tried first and appeared to fail, then all eight
-- combinations of seed/direction/key-half failed, then a brute force over all
-- 65,536 seeds failed.  Every one of those was scored against MEMBER 0 of
-- pl_pokegra -- which is a placeholder that decrypts to noise no matter what
-- you do to it.  The algorithm had been right the whole time and the test
-- subject was the problem.
--
-- What settled it was not another guess: assume the leading plaintext is
-- zero, read the leading ciphertext AS the keystream, and solve the
-- recurrence k[i+1] = (k[i]*A + C) mod 2^16 for A and C from the values
-- themselves.  34 of 38 sprites gave A = 0x4E6D and C = 0x6073 -- which is
-- exactly the published LCG -- and the four that disagreed are the ones whose
-- first tile is not blank, so the "keystream" read from them included
-- picture.  Solving beats searching when the unknown is small.
function Gen4Graphics.decryptSprite(pixels)
  if type(pixels) ~= "string" or #pixels < 2 then return pixels end
  local key = byte(pixels, 1) + byte(pixels, 2) * 256
  local out, n = {}, 0
  for i = 1, #pixels - 1, 2 do
    local lo, hi = byte(pixels, i, i + 1)
    local v = lo + hi * 256
    -- XOR of two 16-bit values, arithmetically: see Gen4Text.xor16 for why
    -- this is not the `bit` library.
    local r, place, a, b = 0, 1, v, key
    for _ = 1, 16 do
      local x, y = a % 2, b % 2
      if x ~= y then r = r + place end
      a, b, place = floor(a / 2), floor(b / 2), place * 2
    end
    n = n + 1
    out[n] = string.char(r % 256, floor(r / 256))
    key = (key * 0x41C64E6D + 0x6073) % 65536
  end
  return table.concat(out)
end

-- ---------------------------------------------------------------------------
-- The container
-- ---------------------------------------------------------------------------

-- Decompresses first when needed, so callers never have to ask.
function Gen4Graphics.container(data)
  data = Gen4Graphics.decompress(data)
  if type(data) ~= "string" or #data < 16 then
    return nil, "not a Nitro container: too short"
  end
  local magic = sub(data, 1, 4)
  local headerSize, count = u16(data, 13), u16(data, 15)
  if not (headerSize and count) or headerSize < 16 or count == 0 then
    return nil, ("not a Nitro container: magic %q"):format(magic)
  end
  local sections, at = {}, headerSize + 1
  for _ = 1, count do
    if at + 8 > #data + 1 then break end
    local tag = sub(data, at, at + 3)
    local size = u32(data, at + 4)
    if not size or size < 8 then break end
    -- `at` is the tag; `body` is where this section's own fields start.
    sections[tag] = { at = at, size = size, body = at + 8 }
    at = at + size
  end
  return { magic = magic, data = data, sections = sections }
end

-- ---------------------------------------------------------------------------
-- NCLR: palettes
-- ---------------------------------------------------------------------------

-- BGR555 -> three 0-255 INTEGER channels.  The 5-bit value is scaled by
-- *255/31 rather than shifted left by three, so that 31 comes out as a true
-- 255 and the brightest colour in the cartridge is the brightest colour on
-- screen; shifting leaves white at 248 and every image slightly dim.
--
-- Rounded to integers rather than left as the division's float: these are
-- channel values, callers format them with %d and hand them to image writers
-- that want bytes, and under Lua 5.3+ a float silently fails an integer
-- conversion instead of quietly truncating.
local function ch(x) return floor(x * 255 / 31 + 0.5) end
local function bgr555(v)
  return ch(v % 32), ch(floor(v / 32) % 32), ch(floor(v / 1024) % 32)
end
Gen4Graphics.bgr555 = bgr555

-- Returns a flat array of { r, g, b } and the colours-per-palette the file
-- declares, so a caller can slice it into sub-palettes.
function Gen4Graphics.palette(data)
  local c = Gen4Graphics.container(data)
  if not c then return nil, "not a palette" end
  local s = c.sections.TTLP
  if not s then return nil, "NCLR has no TTLP section" end
  local size = u32(c.data, s.body + 8)
  local perPalette = u32(c.data, s.body + 12)
  local at = s.body + 16
  local out = {}
  for i = 0, floor((size or 0) / 2) - 1 do
    local v = u16(c.data, at + i * 2)
    if not v then break end
    local r, g, b = bgr555(v)
    out[i + 1] = { r, g, b }
  end
  return out, perPalette
end

-- ---------------------------------------------------------------------------
-- NCGR: tiles
-- ---------------------------------------------------------------------------

local UNSIZED = 0xFFFF

function Gen4Graphics.tiles(data)
  local c = Gen4Graphics.container(data)
  if not c then return nil, "not a tile sheet" end
  local s = c.sections.RAHC
  if not s then return nil, "NCGR has no RAHC section" end
  local tilesY, tilesX = u16(c.data, s.body), u16(c.data, s.body + 2)
  local depth = u32(c.data, s.body + 4)
  local size = u32(c.data, s.body + 16)
  local offset = u32(c.data, s.body + 20)
  if not (size and offset) then return nil, "NCGR header is truncated" end

  -- Believe the arithmetic over the enum.  32 bytes per 4bpp tile, 64 per
  -- 8bpp; when the sheet declares a size, that settles it outright.
  -- THE LAYOUT FLAG, at the field's low byte.  0 means the data is 8x8 tiles
  -- in reading order; 1 means it is a LINEAR BITMAP, row after row, with no
  -- tiling at all.  Measured across every NCGR in the cartridge: 3,872 tiled
  -- against 4,160 linear, and the split is not arbitrary -- every sprite
  -- archive (pokegra, otherpoke, and the trainer sheets trfgra/trbgra) is
  -- linear, while fonts, icons and backgrounds are tiled.
  local layout = u16(c.data, s.body + 12) or 0
  local bitmap = (layout % 256) == 1

  local bpp = (depth == 4) and 8 or 4
  if tilesX and tilesY and tilesX ~= UNSIZED and tilesY ~= UNSIZED then
    if tilesX * tilesY * 32 == size then bpp = 4
    elseif tilesX * tilesY * 64 == size then bpp = 8 end
  end
  local perTile = (bpp == 8) and 64 or 32

  return {
    tilesX = (tilesX ~= UNSIZED) and tilesX or nil,
    tilesY = (tilesY ~= UNSIZED) and tilesY or nil,
    bitmap = bitmap,
    bpp = bpp,
    count = floor(size / perTile),
    perTile = perTile,
    -- `offset` is relative to the START OF THE SECTION'S FIELDS, which is
    -- what `body` already is -- adding the 8-byte tag/size header a second
    -- time shifts every sheet eight bytes into itself.  That produces a
    -- picture, not a crash: recognisable shapes displaced by a quarter tile,
    -- which is exactly the kind of wrong that survives a glance.
    pixels = sub(c.data, s.body + offset, s.body + offset + size - 1),
  }
end

-- ---------------------------------------------------------------------------
-- NSCR: tilemaps
-- ---------------------------------------------------------------------------

-- Each cell is one u16: tile index in the low 10 bits, then horizontal flip,
-- vertical flip, and a 4-bit sub-palette.
function Gen4Graphics.tilemap(data)
  local c = Gen4Graphics.container(data)
  if not c then return nil, "not a tilemap" end
  local s = c.sections.NRCS
  if not s then return nil, "NSCR has no NRCS section" end
  local w, h = u16(c.data, s.body), u16(c.data, s.body + 2)
  local size = u32(c.data, s.body + 8)
  local cells, at = {}, s.body + 12
  for i = 0, floor((size or 0) / 2) - 1 do
    local v = u16(c.data, at + i * 2)
    if not v then break end
    cells[i + 1] = {
      tile = v % 1024,
      flipX = floor(v / 1024) % 2 == 1,
      flipY = floor(v / 2048) % 2 == 1,
      palette = floor(v / 4096) % 16,
    }
  end
  return { width = w, height = h, cells = cells }
end

-- ---------------------------------------------------------------------------
-- Pixels
-- ---------------------------------------------------------------------------

-- Expand a tile sheet into a width x height grid of palette INDICES (0 is
-- the transparent one by convention and is left as 0 rather than resolved,
-- because only the caller knows whether it wants a hole or a colour).
--
-- `widthTiles` is required for an unsized sheet and ignored otherwise.
function Gen4Graphics.indices(sheet, widthTiles)
  if not sheet then return nil end
  local tx = sheet.tilesX or widthTiles
  if not tx or tx < 1 then return nil, "tile sheet has no width; pass one" end
  local w = tx * 8
  local px, data, four = {}, sheet.pixels, sheet.bpp == 4

  -- A linear sheet is simply pixels in reading order, so there is no tile
  -- walk at all -- and running the tile walk over one produces a picture in
  -- the right colours sheared into horizontal bands, which looks far more
  -- like a broken decrypt than like a layout mistake.
  if sheet.bitmap then
    local per = four and 2 or 1
    local h = floor(#data * per / w)
    for i = 1, w * h do px[i] = 0 end
    for i = 0, #data - 1 do
      local v = byte(data, i + 1)
      if four then
        px[i * 2 + 1] = v % 16
        px[i * 2 + 2] = floor(v / 16)
      else
        px[i + 1] = v
      end
    end
    return px, w, h
  end

  local ty = math.ceil(sheet.count / tx)
  local h = ty * 8
  for i = 1, w * h do px[i] = 0 end
  for t = 0, sheet.count - 1 do
    local bx, by = (t % tx) * 8, floor(t / tx) * 8
    local base = t * sheet.perTile
    for i = 0, sheet.perTile - 1 do
      local v = byte(data, base + i + 1)
      if not v then break end
      if four then
        -- Two pixels per byte, LOW nibble first -- the other way round
        -- mirrors every tile horizontally, which looks like a flip-flag bug.
        local p = i * 2
        local x1, y1 = bx + p % 8, by + floor(p / 8)
        px[y1 * w + x1 + 1] = v % 16
        local x2, y2 = bx + (p + 1) % 8, by + floor((p + 1) / 8)
        px[y2 * w + x2 + 1] = floor(v / 16)
      else
        local x1, y1 = bx + i % 8, by + floor(i / 8)
        px[y1 * w + x1 + 1] = v
      end
    end
  end
  return px, w, h
end

-- ---------------------------------------------------------------------------
-- Composition: NSCR + NCGR + NCLR -> one finished screen
-- ---------------------------------------------------------------------------

-- A background is never one file.  The tilemap says which tile goes where and
-- with which sub-palette, the tile sheet holds the 8x8 pieces, and the palette
-- holds the colours.  Composing them is what turns three archive members into
-- a picture, and it is the step that was missing while Gen 4 assets could be
-- decoded but not looked at.
--
-- Returns { width, height, rgba }, rgba being width * height * 4 bytes.
-- Palette entry 0 is transparent, as everywhere else on the hardware.
function Gen4Graphics.compose(map, sheet, palette)
  if not (map and sheet and palette) then return nil, "compose needs a tilemap, tiles and a palette" end

  local w, h = map.width, map.height
  -- NSCR records its size in pixels, but a few members leave it at zero and
  -- let the cell count speak instead.  Fall back rather than return nothing.
  if not w or w == 0 or not h or h == 0 then
    local cells = #map.cells
    w = 256
    h = floor(cells / (w / 8)) * 8
    if h == 0 then return nil, "tilemap has no size and no cells" end
  end

  local cols = floor(w / 8)
  local four = sheet.bpp == 4
  local perTile = sheet.perTile or (four and 32 or 64)
  local data = sheet.pixels
  -- `palette` is the flat array Gen4Graphics.palette returns: one { r, g, b }
  -- per entry, sub-palettes laid end to end in sixteens.
  local colours = palette
  if type(colours) ~= "table" or #colours == 0 then return nil, "palette has no colours" end

  local out = {}
  local blank = char(0, 0, 0, 0)
  for i = 1, w * h do out[i] = blank end

  for index = 1, #map.cells do
    local cell = map.cells[index]
    local cx = ((index - 1) % cols) * 8
    local cy = floor((index - 1) / cols) * 8
    if cy < h then
      local base = cell.tile * perTile
      -- A cell may point past the end of a sheet that was cut short; leave
      -- those transparent instead of reading whatever follows.
      if base + perTile <= #data then
        local shift = four and (cell.palette * 16) or 0
        for y = 0, 7 do
          local sy = cell.flipY and (7 - y) or y
          for x = 0, 7 do
            local sx = cell.flipX and (7 - x) or x
            local value
            if four then
              local at = base + sy * 4 + floor(sx / 2)
              local pair = byte(data, at + 1) or 0
              if sx % 2 == 0 then value = pair % 16 else value = floor(pair / 16) end
            else
              value = byte(data, base + sy * 8 + sx + 1) or 0
            end
            if value ~= 0 then
              local colour = colours[shift + value + 1]
              if colour then
                out[(cy + y) * w + cx + x + 1] =
                  char(colour[1], colour[2], colour[3], 255)
              end
            end
          end
        end
      end
    end
  end

  return { width = w, height = h, rgba = concat(out) }
end

-- Compose straight from an archive group (see Gen4Archives.groups): the group
-- names the members, this fetches and decodes them.  `fallbackMap` supplies a
-- tilemap for groups that share one rather than carrying their own -- battle
-- backgrounds all reuse member 2, for instance.
function Gen4Graphics.composeGroup(narc, group, fallbackMap)
  if not group then return nil, "no group" end
  local function fetch(member)
    if member == nil then return nil end
    local raw = narc:get(member)
    if not raw then return nil end
    if Gen4Graphics.isCompressed(raw) then raw = Gen4Graphics.decompress(raw) end
    return raw
  end

  local tileData = fetch(group.NCGR)
  local palData = fetch(group.NCLR)
  local mapData = fetch(group.NSCR) or fallbackMap
  if not tileData then return nil, "group has no tile sheet" end
  if not palData then return nil, "group has no palette" end
  if not mapData then return nil, "group has no tilemap" end

  local sheet = Gen4Graphics.tiles(tileData)
  local palette = Gen4Graphics.palette(palData)
  local map = Gen4Graphics.tilemap(mapData)
  return Gen4Graphics.compose(map, sheet, palette)
end

return Gen4Graphics
