-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially.  Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- NSBTX: the overworld sprites, which turn out not to need 3D at all.
--
-- /data/mmodel/mmodel.narc is 470 members and the obvious reading of it is
-- discouraging: Gen 4's overworld is 3D, so the NPCs must be models, and
-- models mean NSBMD, a mesh pipeline and a long detour.
--
-- THEY ARE NOT MODELS.  421 of the 470 are BTX0 -- Nitro TEXTURE archives --
-- and only 24 are BMD0.  A Gen 4 NPC is a flat quad wearing a texture, the
-- geometry is shared, and the per-character art is a TEXTURE SET: 32x32,
-- 16 colours, colour 0 transparent, nine to sixteen frames covering the walk
-- cycle in four directions.  The member names say so outright --
-- `youngster.nsbtx`, `lass.nsbtx`, `guitarist.nsbtx` -- and the map defs
-- already carry a `graphicsId` that indexes this archive.
--
-- So the overworld sprite question is answered by reading textures, and the
-- mesh pipeline is not on the path to it.
--
-- WHAT A TEXTURE ENTRY SAYS.  Eight bytes, of which the SECOND word is the
-- one that matters -- the hardware's texImageParam:
--
--   bits  0-15  texture offset, in units of 8 bytes
--   bits 20-22  width  exponent, width  = 8 << value
--   bits 23-25  height exponent, height = 8 << value
--   bits 26-28  format
--   bit  29     colour 0 is transparent
--
-- The record is { u32 texImageParam, u32 extraParam }, so the parameter is
-- the FIRST word.  This file used to read the second, and said so; that was
-- wrong, and it survived because the dictionary reader below was ALSO four
-- bytes short, and on a two-texture member the two errors cancel exactly.
-- 208 of mmodel's 421 texture members have two textures, which was enough to
-- make the pair look correct.
--
-- FORMATS, recounted over all 3,567 entries once both were fixed: 3,564 are
-- format 3 (16 colours) and 3 are format 2 (4 colours).  That is the whole
-- list.  The earlier count here -- 621 empty slots, 181 A3I5, 82
-- 4x4-compressed, 16 A5I3 -- was misread bytes, not cartridge content: this
-- archive holds nothing but paletted sprite frames.  The other formats are
-- still REPORTED rather than silently skipped, in case a mod adds one.

local Gen4Models = {}

local byte, char, concat, floor = string.byte, string.char, table.concat, math.floor

local function u8(s, at) return byte(s, at + 1) end

local function u16(s, at)
  local a, b = byte(s, at + 1, at + 2)
  if not b then return nil end
  return a + b * 256
end

local function u32(s, at)
  local a, b, c, d = byte(s, at + 1, at + 4)
  if not d then return nil end
  return a + b * 256 + c * 65536 + d * 16777216
end

local function bits(value, low, count)
  return floor(value / 2 ^ low) % 2 ^ count
end

Gen4Models.FORMATS = {
  [0] = "none", "a3i5", "palette4", "palette16", "palette256",
  "compressed4x4", "a5i3", "direct",
}

-- The formats this reads.  The rest are counted and left alone: a sprite drawn
-- from a format nobody decoded would be wrong rather than missing, and missing
-- is the honest answer.
Gen4Models.DECODABLE = { [2] = 4, [3] = 16, [4] = 256 }

-- The largest a character sprite is taken to be.  Every NPC in the archive
-- is 32x32 or 16x32; this only has to sit above those and below the 512-and-
-- up slots that are not sprites at all.
Gen4Models.MAX_SPRITE = 128

-- A Nitro 3D dictionary: a count, a tree nobody needs, then fixed-size records
-- followed by sixteen-byte names.
local function dictionary(data, base)
  local count = u8(data, base + 1)
  if not count or count == 0 then return {} end
  -- 4 bytes of header, then an 8-byte block, then one 4-byte tree node each.
  local at = base + 4 + 8 + count * 4
  local unit = u16(data, at)
  local dataOffset = u16(data, at + 2)
  if not (unit and dataOffset) then return {} end

  -- `dataOffset` is measured from `at`, not from `base`, and it points at the
  -- NAMES -- the fixed-size records sit immediately after this 4-byte
  -- sub-header.  Deriving the records from `dataOffset` is right only when
  -- count*(unit-4) == 12, which for unit 8 means exactly two records; that is
  -- 208 of mmodel's 421 members, enough for the mistake to look correct.
  local records = at + 4
  local nameBase = records + count * unit
  local out = {}
  for i = 0, count - 1 do
    local name = data:sub(nameBase + i * 16 + 1, nameBase + i * 16 + 16)
    out[i + 1] = {
      at = records + i * unit,
      name = (name:gsub("%z.*", "")),
    }
  end
  return out
end

local function bgr555(value)
  local r = value % 32
  local g = floor(value / 32) % 32
  local b = floor(value / 1024) % 32
  return floor(r * 255 / 31 + 0.5), floor(g * 255 / 31 + 0.5), floor(b * 255 / 31 + 0.5)
end

-- parse(data) -> { textures = {...}, palettes = {...}, texBase, palBase }
--
-- `sectionAt` is for a TEX0 that is NOT the whole file: a model file carries
-- its textures in a second section beside MDL0, and `u32(data, 16)` there is
-- the MODEL section, not this one.  Reading a BMD0 with that assumption gives
-- a texture table built out of geometry -- a parse that succeeds and is
-- entirely wrong, which is this format's recurring hazard.
function Gen4Models.parse(data, sectionAt)
  local section = sectionAt
  if not section then
    if type(data) ~= "string" or data:sub(1, 4) ~= "BTX0" then
      return nil, "not an NSBTX"
    end
    section = u32(data, 16)
  end
  if not section or data:sub(section + 1, section + 4) ~= "TEX0" then
    return nil, "no TEX0 section here"
  end

  local texInfo = u16(data, section + 0x0E)
  local texData = u32(data, section + 0x14)
  local palSize = u32(data, section + 0x30)
  local palInfo = u32(data, section + 0x34)
  local palData = u32(data, section + 0x38)
  if not (texInfo and texData and palData) then return nil, "TEX0 header is truncated" end

  local texBase = section + texData
  local palBase = section + palData

  local textures = {}
  for _, entry in ipairs(dictionary(data, section + texInfo)) do
    -- The texture record is { u32 texImageParam, u32 extraParam }, so the
    -- parameter is the FIRST word.  Reading the second cancelled the record
    -- error above on two-texture members and on nothing else.
    local param = u32(data, entry.at)
    if param then
      textures[#textures + 1] = {
        name = entry.name,
        offset = bits(param, 0, 16) * 8,
        -- floor()ed, because 2^n in Lua is a FLOAT: without it every size
        -- reports as "32.0x32.0" and a key built from it will not match the
        -- integer one any caller would write.
        width = floor(8 * 2 ^ bits(param, 20, 3)),
        height = floor(8 * 2 ^ bits(param, 23, 3)),
        format = bits(param, 26, 3),
        transparent0 = bits(param, 29, 1) == 1,
      }
    end
  end

  -- A CORRECTION.  This block used to say the palette dictionary's offsets
  -- read implausibly -- one claiming 3,064 bytes into a 32-byte region -- and
  -- fell back to dividing the region by its own palette size.  The offsets
  -- were fine; the dictionary reader above was reading four bytes short of
  -- the records.  With that fixed, all 618 palette entries in the 421 texture
  -- members land inside their own region.  The range check is kept as a cheap
  -- guard -- it now never fires -- rather than as the thing doing the work.
  local palBytes = (palSize or 0) * 8
  local palettes = {}
  local dict = dictionary(data, section + (palInfo or 0))
  for i, entry in ipairs(dict) do
    local offset = u16(data, entry.at)
    offset = offset and bits(offset, 0, 16) * 8 or nil
    if not offset or offset >= palBytes then offset = (i - 1) * 32 end
    palettes[i] = { name = entry.name, offset = offset }
  end
  if #palettes == 0 then palettes[1] = { name = "", offset = 0 } end

  return {
    textures = textures,
    palettes = palettes,
    texBase = texBase,
    palBase = palBase,
    paletteBytes = palBytes,
    section = section,
  }
end

-- colours(parsed, data, paletteIndex, count) -> array of { r, g, b }, 0-based.
function Gen4Models.colours(parsed, data, paletteIndex, count)
  local palette = parsed.palettes[paletteIndex or 1] or parsed.palettes[1]
  local at = parsed.palBase + (palette and palette.offset or 0)
  local out = {}
  for i = 0, (count or 16) - 1 do
    local value = u16(data, at + i * 2)
    if not value then break end
    local r, g, b = bgr555(value)
    out[i] = { r, g, b }
  end
  return out
end

-- decode(parsed, data, index, paletteIndex) -> { width, height, rgba }, or nil
-- plus the format name when the texture is one this does not read.
function Gen4Models.decode(parsed, data, index, paletteIndex)
  local texture = parsed and parsed.textures[index]
  if not texture then return nil, "no such texture" end

  local colourCount = Gen4Models.DECODABLE[texture.format]
  if not colourCount then
    return nil, Gen4Models.FORMATS[texture.format] or "unknown format"
  end

  local colours = Gen4Models.colours(parsed, data, paletteIndex, colourCount)
  local width, height = texture.width, texture.height
  local base = parsed.texBase + texture.offset
  local out = {}
  local blank = char(0, 0, 0, 0)

  -- Pixels are packed low-bits-first within a byte, the same way every other
  -- indexed graphic in this cartridge is.
  local perByte = (texture.format == 2) and 4
                  or (texture.format == 3) and 2 or 1
  local mask = (texture.format == 2) and 4
               or (texture.format == 3) and 16 or 256

  for y = 0, height - 1 do
    for x = 0, width - 1 do
      local linear = y * width + x
      local value = u8(data, base + floor(linear / perByte))
      local index_
      if value then
        index_ = floor(value / mask ^ (linear % perByte)) % mask
      else
        index_ = 0
      end
      local colour = colours[index_]
      if index_ == 0 and texture.transparent0 then
        out[linear + 1] = blank
      elseif colour then
        out[linear + 1] = char(colour[1], colour[2], colour[3], 255)
      else
        out[linear + 1] = blank
      end
    end
  end

  return { width = width, height = height, rgba = concat(out), name = texture.name }
end

-- sheet(data, opts) -> the CHARACTER's frames, laid out in a row.
--
-- A CORRECTION, kept because the wrong version was published.  This block
-- used to say every member held nine 32x32 frames plus a handful of huge
-- empty slots -- 512x32, 1024x512, 1024x8 -- and that 120 of 120 of those
-- large slots decoded to a fully transparent image.  None of that is in the
-- cartridge.  The nine frames were sixteen, the huge slots were the
-- dictionary misread pointing at the middle of a name, and the transparency
-- was what you get when you decode a region that is not texture data.
--
-- What is actually here: 421 texture members, every texture paletted, frame
-- sizes 32x32 (3,158), 16x32 (385) and a handful of 64x64, 16x16, 64x32,
-- 128x64 and 128x32.  A member holds 1, 2, 3, 4, 7, 12, 13, 16, 17, 24 or 32
-- frames -- 16 for a standard NPC, 32 for the player, 1 for an item ball.
--
-- The strip is still built from the MODAL frame size: whichever size the most
-- decodable textures in this member share.  That is the character in every
-- member checked, it needs no list of which entries to trust, and the frames
-- it leaves out are counted and returned rather than dropped quietly.
--
-- It is also what makes this fast enough to run: decoding one member's
-- 1024x512 slot costs more than every 32x32 frame in the archive put together.
function Gen4Models.sheet(data, opts)
  opts = opts or {}
  local parsed = Gen4Models.parse(data)
  if not parsed then return nil end

  -- Which size the most decodable textures agree on.
  local tally, best, bestCount = {}, nil, 0
  for _, texture in ipairs(parsed.textures) do
    if Gen4Models.DECODABLE[texture.format] then
      local key = texture.width .. "x" .. texture.height
      tally[key] = (tally[key] or 0) + 1
      if tally[key] > bestCount then best, bestCount = key, tally[key] end
    end
  end
  if not best then return nil, { none = #parsed.textures } end

  -- A CHARACTER SPRITE IS SMALL.  This guard was written when eleven members
  -- appeared to have a modal size of 1024x512 or 512x512; that was the
  -- dictionary misread, and with it fixed the largest modal frame in the
  -- whole archive is 128x64.  The guard stays because an oversize modal
  -- really would mean this member is not a character, and decoding one
  -- 1024x512 slot costs more than every 32x32 frame here put together -- but
  -- it is a guard against a misread, not a description of the cartridge.
  local modalWidth = tonumber(best:match("^(%d+)")) or 0
  local modalHeight = tonumber(best:match("x(%d+)$")) or 0
  if modalWidth > Gen4Models.MAX_SPRITE or modalHeight > Gen4Models.MAX_SPRITE then
    return nil, { modal = best, oversize = true }
  end

  local report = { modal = best, kept = 0, otherSize = 0, undecodable = 0 }
  local frames = {}
  for i, texture in ipairs(parsed.textures) do
    if not Gen4Models.DECODABLE[texture.format] then
      if texture.format ~= 0 then report.undecodable = report.undecodable + 1 end
    elseif (texture.width .. "x" .. texture.height) ~= best then
      report.otherSize = report.otherSize + 1
    else
      local image = Gen4Models.decode(parsed, data, i, opts.palette)
      if image then
        frames[#frames + 1] = image
        report.kept = report.kept + 1
      end
    end
  end
  if #frames == 0 then return nil, report end

  -- FRAMES STACK DOWNWARD, NOT ACROSS.
  --
  -- src/render/SpriteRenderer.lua cuts frame f with
  -- `newQuad(0, f * frameHeight, frameWidth, frameHeight, ...)`, so a sheet is
  -- a COLUMN.  A horizontal strip is the obvious thing to build and it loads
  -- without complaint -- every quad lands inside the image -- but every frame
  -- after the first is then cut out of empty space below the strip, so an NPC
  -- stands correctly and vanishes the moment it takes a step.  Gen 3's own
  -- sheets are 16 wide and 288 tall for exactly this reason.
  local width, height = frames[1].width, 0
  for _, frame in ipairs(frames) do height = height + frame.height end

  local out = {}
  local blank = char(0, 0, 0, 0)
  for i = 1, width * height do out[i] = blank end
  local penY = 0
  for _, frame in ipairs(frames) do
    for y = 0, frame.height - 1 do
      for x = 0, frame.width - 1 do
        if x < width then
          local from = (y * frame.width + x) * 4
          out[(penY + y) * width + x + 1] = frame.rgba:sub(from + 1, from + 4)
        end
      end
    end
    penY = penY + frame.height
  end

  return { width = width, height = height, rgba = concat(out),
           frames = #frames, frameWidth = frames[1].width,
           frameHeight = frames[1].height }, report
end

return Gen4Models
