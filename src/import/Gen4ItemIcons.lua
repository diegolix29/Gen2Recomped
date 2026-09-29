-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- src/import/Gen4ItemIcons.lua -- WHICH OF THE 711 MEMBERS IS THIS ITEM'S.
--
-- Reported from play, twice over, and recorded twice without a fix: the bag's
-- item-icon frame is empty. It is empty because nothing extracts
-- /itemtool/itemdata/item_icon.narc, and nothing extracts it because NOTHING
-- ABOUT AN ITEM SAYS WHICH MEMBERS ARE ITS OWN. The item's data record carries
-- pockets, price, fling and hold effects and no graphic at all.
--
-- THE ARCHIVE, measured: 711 members.
--
--   0        NANR -- the shared animation, `Item_IconNANRFile`
--   1        NCER -- the shared cell bank, `Item_IconNCERFile`
--   2..710   NCGR and NCLR, mostly in pairs
--
-- Each icon is 16 tiles at 4bpp laid four tiles wide: 32x32.
--
-- ---------------------------------------------------------------------------
-- !! THE PAIRING IS A TABLE IN THE ARM9, AND A THIRD OF IT IS NOT A PATTERN
--
-- `Item_Load` reads `sItemArchiveIDs[item].iconID` and `.paletteID`, and that
-- array is generated into the binary. Eight bytes a row:
--
--     { u16 dataID, u16 iconID, u16 paletteID, u16 gen3ID }
--
-- The obvious shortcut -- item n's icon is member 2n, its palette 2n + 1 --
-- holds for most of the table and IS WRONG FOR 158 OF THE 468 ROWS. There are
-- 295 distinct sprites against 351 distinct palettes, because a family of
-- items shares one shape and recolours it. Black Flute is the clearest: its
-- row is (68, 65, 69), and pokeplatinum names those members `blue_flute_NCGR`
-- and `black_flute_NCLR`. One flute, four colours.
--
-- That is the failure mode to keep in mind: the shortcut gives EVERY item an
-- icon, and the wrong one for a third of the bag. Nothing errors.
--
-- FOUND BY BOUNDS, not by address, and the bounds alone are enough -- unlike
-- `Gen4Icons`, which needed an entropy tie-break because two runs matched.
-- Requiring 468 consecutive rows whose dataID is below the data archive's
-- count and whose icon and palette are below the icon archive's count matches
-- EXACTLY ONE offset in the whole ARM9. The structural checks below are kept
-- anyway, because "unique in this binary" is a measurement of this binary.
--
-- WHAT THE TABLE SAYS ABOUT ITSELF, every bit of it agreeing with something
-- already known elsewhere in this port:
--
--   * Item 1 points at members 2 and 3 -- exactly where the NCGR/NCLR pairs
--     begin, after the NANR and the NCER.
--   * Item 0 points at 707 and 708. With 711 members the last index is 710,
--     and pokeplatinum names 709 and 710 `unused_709_NCGR`/`unused_710_NCLR`:
--     `none` sits immediately below its own pair of unused slots.
--   * `index - dataID` takes exactly TWO values over the whole table: 0 for
--     112 rows and 22 for 333, with 23 rows pointing at `none` in between.
--     That is the "a member index is the item id only up to 112 and is off by
--     twenty-two after that" already written down in `Gen4BagMenu` from the
--     item-table work, arrived at from a different direction and agreeing to
--     the row.
--
-- The twelve rows in `VERIFIED` were checked BY LOOKING -- decoded through
-- their own palettes and compared against the names the cache gives those ids.
-- A scan that finds a different array fails on them rather than filling the
-- bag with plausible wrong pictures.

local Gen4ItemIcons = {}

Gen4ItemIcons.PATH = "/itemtool/itemdata/item_icon.narc"

Gen4ItemIcons.ANIM_MEMBER = 0
Gen4ItemIcons.CELL_MEMBER = 1
Gen4ItemIcons.FIRST_PAIR = 2
Gen4ItemIcons.SIZE = 32
Gen4ItemIcons.TILES_WIDE = 4
Gen4ItemIcons.ROW_BYTES = 8

-- A Gen 3 item id, the fourth field, never reaches this; the bound is only
-- here to stop a run of unrelated small numbers passing for the table.
Gen4ItemIcons.MAX_GEN3_ID = 400

-- item id -> { iconID, paletteID }, and the name each one rendered as.
Gen4ItemIcons.VERIFIED = {
  [1] = { 2, 3, "Master Ball" },
  [4] = { 8, 9, "Poke Ball" },
  [17] = { 24, 25, "Potion" },
  [30] = { 43, 44, "Fresh Water" },
  -- the reused sprites, which are the whole reason this table has to be read
  [68] = { 65, 69, "Black Flute" },
  [70] = { 51, 75, "Shoal Salt" },
  [79] = { 109, 114, "Repel" },
  [71] = { 76, 77, "Shoal Shell" },
  [78] = { 112, 113, "Escape Rope" },
  [94] = { 470, 471, "Honey" },
  [112] = { 699, 700, "Griseous Orb" },
  [445] = { 353, 354, "Old Rod" },
}

local function u16(bin, at)
  local a, b = bin:byte(at), bin:byte(at + 1)
  if not (a and b) then return nil end
  return a + b * 256
end

-- The four fields of row `i`, counting from zero, at a 1-based table offset.
function Gen4ItemIcons.row(bin, at, i)
  local base = at + Gen4ItemIcons.ROW_BYTES * i
  return u16(bin, base), u16(bin, base + 2), u16(bin, base + 4), u16(bin, base + 6)
end

-- findTable(bin, members, dataCount, items) -> 1-based offset, or nil.
--
-- `members` is the icon archive's member count, `dataCount` the item data
-- archive's, `items` the number of rows to require -- which is the number of
-- item NAMES, not the number of data records, because the table is indexed by
-- item id and the ids outrun the data.
function Gen4ItemIcons.findTable(bin, members, dataCount, items)
  if type(bin) ~= "string" then return nil end
  members = tonumber(members) or 711
  dataCount = tonumber(dataCount) or 446
  items = tonumber(items) or 468
  local need = Gen4ItemIcons.ROW_BYTES * items
  local maxGen3 = Gen4ItemIcons.MAX_GEN3_ID
  local n = #bin
  local found, matches = nil, 0
  local at = 1
  while at <= n - need do
    local k = 0
    while true do
      local base = at + Gen4ItemIcons.ROW_BYTES * k
      local d, icon, pal, gen3 = u16(bin, base), u16(bin, base + 2),
                                 u16(bin, base + 4), u16(bin, base + 6)
      if not gen3 then break end
      if d >= dataCount or icon >= members or pal >= members
         or gen3 >= maxGen3 then break end
      k = k + 1
      if k >= items then break end
    end
    if k >= items then
      matches = matches + 1
      found = found or at
    end
    at = at + 4
  end
  return found, matches
end

-- Does the array this scan found agree with the twelve rows that were checked
-- by looking? A wrong array does not fail -- it fills the bag with the wrong
-- pictures, which reads as "the icons are broken" rather than as "the scan
-- found a different table".
function Gen4ItemIcons.verify(bin, at)
  local wrong = {}
  for item, want in pairs(Gen4ItemIcons.VERIFIED) do
    local _, icon, pal = Gen4ItemIcons.row(bin, at, item)
    if icon ~= want[1] or pal ~= want[2] then
      wrong[#wrong + 1] = ("%s (%d) got %s/%s want %d/%d")
        :format(want[3], item, tostring(icon), tostring(pal), want[1], want[2])
    end
  end
  return #wrong == 0, wrong
end

return Gen4ItemIcons
