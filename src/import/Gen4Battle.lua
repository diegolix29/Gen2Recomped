-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Gen 4 (Platinum) battle presentation: which cartridge members make up a
-- battle scene, and in what combination.
--
-- A Gen 1-3 battle background is one picture at one address.  A Gen 4 one is
-- assembled at run time from three archive members that are nowhere near each
-- other, chosen by two independent values -- the map's BACKGROUND and the
-- TIME OF DAY -- and drawn under a fourth, the TERRAIN platform, chosen by a
-- third value that is derived from the tile the player is standing on rather
-- than from the map at all.
--
-- None of that is guessable from the archive.  pl_batt_bg has no .order file,
-- its 342 members are an irregular run of compressed tile sheets, palettes and
-- tilemaps, and nothing in it says which member belongs to which background.
-- The indices below are the arithmetic the game itself performs, and they are
-- checked against the cartridge rather than copied on faith:
--
--   * member 2 really is an NSCR and members 3..25 really are NCGR, which is
--     what `tilemap = 2` and `tiles = 3 + background` require.
--   * members 172..240 really are NCLR, which is what
--     `palette = 172 + background * 3 + time` requires for 23 backgrounds at
--     three times of day.
--   * all 23 backgrounds compose to plausible pictures in plausible colours,
--     and the count 23 is confirmed a second way by sFadeTargets, a per
--     background table with exactly 23 entries.
--
-- THE TILEMAP IS SHARED.  Every background reuses member 2.  A background is
-- therefore a palette swap over a common tile arrangement plus its own tile
-- sheet, which is why the archive holds one tilemap and sixty-nine palettes.
-- Composing a background against a per-background tilemap that does not exist
-- is the obvious wrong turn here, and it fails by producing nothing rather
-- than by producing something wrong, so it is at least loud.

local Gen4Battle = {}

Gen4Battle.ARCHIVE_BG = "/battle/graphic/pl_batt_bg.narc"
Gen4Battle.ARCHIVE_OBJ = "/battle/graphic/pl_batt_obj.narc"

-- ---------------------------------------------------------------------------
-- Backgrounds
-- ---------------------------------------------------------------------------

-- The map header's battleBG field indexes this.  Order comes from
-- sTerrainForBackground, written as designated initialisers in enum order, and
-- is confirmed by sFadeTargets: entries 9, 10 and 11 -- the three caves -- are
-- the only ones that fade to black instead of white, which is exactly where
-- the caves fall in this order.
Gen4Battle.BACKGROUNDS = {
  "plain", "water", "city", "forest", "mountain", "snow",
  "indoors_1", "indoors_2", "indoors_3",
  "cave_1", "cave_2", "cave_3",
  "aaron", "bertha", "flint", "lucian", "cynthia",
  "distortion_world",
  "battle_tower", "battle_factory", "battle_arcade",
  "battle_castle", "battle_hall",
}
Gen4Battle.BACKGROUND_COUNT = #Gen4Battle.BACKGROUNDS

-- Times of day as the background palettes are grouped -- three per background,
-- in this order.  The game's own clock has more states than this (morning and
-- late night among them); they collapse onto these three for battle purposes.
Gen4Battle.TIMES = { "day", "evening", "night" }

-- Where the shared tilemap lives.  Not a formula, just a constant the game
-- hard-codes.
Gen4Battle.BG_TILEMAP_MEMBER = 2

-- tiles = 3 + background
Gen4Battle.BG_TILES_BASE = 3

-- palette = 172 + background * 3 + time
Gen4Battle.BG_PALETTE_BASE = 172
Gen4Battle.BG_PALETTE_STRIDE = 3

-- The colour each background fades TO on a whiteout or blackout: white for
-- everything outdoors, black inside the three caves.  Stored as BGR555, which
-- is what the hardware register takes; 0x7FFF is white, 0 is black.
Gen4Battle.FADE_TARGETS = {
  0x7FFF, 0x7FFF, 0x7FFF, 0x7FFF, 0x7FFF, 0x7FFF, 0x7FFF, 0x7FFF, 0x7FFF,
  0x0000, 0x0000, 0x0000,
  0x7FFF, 0x7FFF, 0x7FFF, 0x7FFF, 0x7FFF, 0x7FFF, 0x7FFF, 0x7FFF, 0x7FFF,
  0x7FFF, 0x7FFF,
}

-- background(index, time) -> { tiles = n, palette = n, tilemap = n }
--
-- `index` is zero-based, matching the map header field.  `time` is 0 day,
-- 1 evening, 2 night.
function Gen4Battle.background(index, time)
  index = index or 0
  time = time or 0
  if index < 0 or index >= Gen4Battle.BACKGROUND_COUNT then return nil end
  if time < 0 or time > 2 then return nil end
  return {
    name = Gen4Battle.BACKGROUNDS[index + 1],
    time = Gen4Battle.TIMES[time + 1],
    tiles = Gen4Battle.BG_TILES_BASE + index,
    palette = Gen4Battle.BG_PALETTE_BASE + index * Gen4Battle.BG_PALETTE_STRIDE + time,
    tilemap = Gen4Battle.BG_TILEMAP_MEMBER,
    fadeTo = Gen4Battle.FADE_TARGETS[index + 1],
  }
end

-- ---------------------------------------------------------------------------
-- The MOVE ANIMATION background layer
-- ---------------------------------------------------------------------------

-- `switchbg` names one of fifty-eight backgrounds and the game assembles it out
-- of FIVE members of the same archive the backdrops live in: a tile sheet, one
-- sixteen-colour palette, and THREE tilemaps over that one sheet.
--
-- WHY THREE. `BattleBgSwitch_SetBg` picks between them by situation and nothing
-- else: the first in a normal battle, the SECOND when the animation is to be
-- mirrored -- which is what happens when the defender is the player -- and the
-- THIRD in a contest. So a background is one picture with a left-facing, a
-- right-facing and a contest arrangement, and a port that only ever loaded the
-- first would play every enemy attack's background the wrong way round.
--
-- WHERE THE TABLE COMES FROM. It is `sBgNarcIndices`, and it is READ OUT OF THE
-- CARTRIDGE rather than transcribed on faith: the 1,160 bytes below sit at file
-- offset 0x1C0308, inside overlay 12, and `tools/gen4_moveanim_check.lua`
-- searches the overlays for the encoding of this very table and asserts it is
-- found exactly once. Change one number here and the search finds nothing.
--
-- It is not derivable. Rows 0-4 are the same five members repeated, row 47 sits
-- in a different part of the archive from its neighbours, and rows 28 and 30 are
-- identical while 29 differs only in its palette. There is no formula; this is
-- the list.
Gen4Battle.EFFECT_BG_COUNT = 58

-- The five columns, in `BgNarcMemberType` order.
Gen4Battle.EFFECT_BG_TILES = 1
Gen4Battle.EFFECT_BG_PALETTE = 2
Gen4Battle.EFFECT_BG_MAP_NORMAL = 3
Gen4Battle.EFFECT_BG_MAP_REVERSED = 4
Gen4Battle.EFFECT_BG_MAP_CONTEST = 5

Gen4Battle.EFFECT_BG_MEMBERS = {
  [0] = { 0x41, 0x123, 0x3E, 0x3F, 0x40 },
  [1] = { 0x41, 0x123, 0x3E, 0x3F, 0x40 },
  [2] = { 0x41, 0x123, 0x3E, 0x3F, 0x40 },
  [3] = { 0x41, 0x123, 0x3E, 0x3F, 0x40 },
  [4] = { 0x41, 0x123, 0x3E, 0x3F, 0x40 },
  [5] = { 0x41, 0x141, 0x3E, 0x3F, 0x40 },
  [6] = { 0x45, 0x124, 0x42, 0x43, 0x44 },
  [7] = { 0x45, 0x145, 0x42, 0x43, 0x44 },
  [8] = { 0x45, 0x148, 0x42, 0x43, 0x44 },
  [9] = { 0x46, 0x125, 0x47, 0x47, 0x47 },
  [10] = { 0x46, 0x125, 0x47, 0x47, 0x47 },
  [11] = { 0x46, 0x13F, 0x47, 0x47, 0x47 },
  [12] = { 0x46, 0x140, 0x47, 0x47, 0x47 },
  [13] = { 0x46, 0x147, 0x47, 0x47, 0x47 },
  [14] = { 0x4C, 0x126, 0x48, 0x48, 0x48 },
  [15] = { 0x4C, 0x128, 0x48, 0x48, 0x48 },
  [16] = { 0x4C, 0x130, 0x48, 0x48, 0x48 },
  [17] = { 0x4C, 0x138, 0x48, 0x48, 0x48 },
  [18] = { 0x4C, 0x130, 0x48, 0x48, 0x48 },
  [19] = { 0x51, 0x129, 0x52, 0x52, 0x50 },
  [20] = { 0x59, 0x12B, 0x56, 0x57, 0x58 },
  [21] = { 0x5F, 0x12D, 0x5C, 0x5D, 0x5E },
  [22] = { 0x63, 0x12E, 0x60, 0x61, 0x62 },
  [23] = { 0x64, 0x12F, 0x65, 0x65, 0x65 },
  [24] = { 0x66, 0x131, 0x67, 0x67, 0x67 },
  [25] = { 0x69, 0x132, 0x6A, 0x6A, 0x68 },
  [26] = { 0x6F, 0x133, 0x6E, 0x6E, 0x6E },
  [27] = { 0x6F, 0x153, 0x6E, 0x6E, 0x6E },
  [28] = { 0x70, 0x134, 0x71, 0x71, 0x71 },
  [29] = { 0x70, 0x135, 0x71, 0x71, 0x71 },
  [30] = { 0x70, 0x134, 0x71, 0x71, 0x71 },
  [31] = { 0x77, 0x137, 0x74, 0x75, 0x76 },
  [32] = { 0x77, 0x137, 0x74, 0x75, 0x76 },
  [33] = { 0x77, 0x137, 0x74, 0x75, 0x76 },
  [34] = { 0x7C, 0x13B, 0x7D, 0x7D, 0x7D },
  [35] = { 0x81, 0x13D, 0x82, 0x82, 0x80 },
  [36] = { 0x83, 0x13E, 0x84, 0x84, 0x85 },
  [37] = { 0x8A, 0x143, 0x88, 0x89, 0x89 },
  [38] = { 0x8B, 0x144, 0x8C, 0x8C, 0x8C },
  [39] = { 0x8D, 0x146, 0x8E, 0x8E, 0x8E },
  [40] = { 0x92, 0x149, 0x8F, 0x90, 0x91 },
  [41] = { 0x96, 0x14A, 0x93, 0x94, 0x95 },
  [42] = { 0x97, 0x14B, 0x98, 0x98, 0x98 },
  [43] = { 0x99, 0x14C, 0x9A, 0x9A, 0x9A },
  [44] = { 0x9B, 0x14D, 0x9C, 0x9C, 0x9C },
  [45] = { 0xA0, 0x14E, 0x9D, 0x9E, 0x9F },
  [46] = { 0xA1, 0x14F, 0xA2, 0xA2, 0xA2 },
  [47] = { 0x34, 0x11E, 0x35, 0x35, 0x35 },
  [48] = { 0xA3, 0x150, 0xA4, 0xA5, 0xA4 },
  [49] = { 0xA3, 0x152, 0xA4, 0xA5, 0xA4 },
  [50] = { 0xA6, 0x151, 0xA8, 0xA7, 0xA7 },
  [51] = { 0x4E, 0x127, 0x4F, 0x4F, 0x4F },
  [52] = { 0x5A, 0x12C, 0x5B, 0x5B, 0x5B },
  [53] = { 0x55, 0x12A, 0x53, 0x53, 0x53 },
  [54] = { 0x72, 0x136, 0x73, 0x73, 0x73 },
  [55] = { 0x7A, 0x13A, 0x7B, 0x7B, 0x7B },
  [56] = { 0x78, 0x139, 0x79, 0x79, 0x79 },
  [57] = { 0x86, 0x142, 0x87, 0x87, 0x87 },
}

-- WHICH SUB-PALETTE THE SIXTEEN COLOURS GO IN, and it is not zero: the loader
-- writes them to `PLTT_DEST(BATTLE_BG_PALETTE_EFFECT)` and the tilemaps' cells
-- name slot 9 to match. See Gen4Graphics.paletteAtSlot for what composing at the
-- wrong slot produces (nothing at all).
Gen4Battle.EFFECT_BG_PALETTE_SLOT = 9

-- The three arrangements, in the order of the three tilemap columns. The names
-- are the port's; the ORDER is the cartridge's.
Gen4Battle.EFFECT_VARIANTS = { "normal", "reversed", "contest" }

-- ...and which column each one is, by name rather than by arithmetic on the first.
-- THE ARITHMETIC IS WHY THIS EXISTS: `row[MAP_NORMAL + which - 1]` gives the right
-- answer and leaves MAP_REVERSED and MAP_CONTEST declared, unused and looking
-- load-bearing -- so a reader who swapped those two constants to fix an imagined
-- bug would change nothing and learn nothing. Measured against the plant: with the
-- arithmetic, swapping them failed no check in the suite; with this table it fails
-- 116 column comparisons.
Gen4Battle.EFFECT_BG_MAP_COLUMN = {
  normal = Gen4Battle.EFFECT_BG_MAP_NORMAL,
  reversed = Gen4Battle.EFFECT_BG_MAP_REVERSED,
  contest = Gen4Battle.EFFECT_BG_MAP_CONTEST,
}

-- effectBackground(id, variant) -> { tiles, palette, tilemap, slot, art }
--
-- `id` is zero-based, matching the `switchbg` operand. `variant` is one of
-- EFFECT_VARIANTS or its 1-based index.
--
-- `art` is the name the composed picture is stored under, and it is spelled from
-- the THREE MEMBERS rather than from the id, because the members are what decide
-- the picture: 58 backgrounds x 3 arrangements is 174 combinations but only 81
-- distinct triples, so naming by id would write the same image up to five times.
function Gen4Battle.effectBackground(id, variant)
  id = tonumber(id)
  if not id or id < 0 or id >= Gen4Battle.EFFECT_BG_COUNT then return nil end
  local row = Gen4Battle.EFFECT_BG_MEMBERS[id]
  if not row then return nil end
  local which
  if type(variant) == "number" then
    which = variant
  else
    for i, name in ipairs(Gen4Battle.EFFECT_VARIANTS) do
      if name == variant then which = i end
    end
  end
  if not which or which < 1 or which > #Gen4Battle.EFFECT_VARIANTS then return nil end
  local name = Gen4Battle.EFFECT_VARIANTS[which]
  local column = Gen4Battle.EFFECT_BG_MAP_COLUMN[name]
  if not column then return nil end
  local tiles = row[Gen4Battle.EFFECT_BG_TILES]
  local palette = row[Gen4Battle.EFFECT_BG_PALETTE]
  local tilemap = row[column]
  return {
    tiles = tiles, palette = palette, tilemap = tilemap,
    slot = Gen4Battle.EFFECT_BG_PALETTE_SLOT,
    variant = name,
    art = ("%d_%d_%d"):format(tiles, palette, tilemap),
  }
end

-- effectKey(id, variant) -> the key the graphics index stores the entry under
function Gen4Battle.effectKey(id, variant)
  local spec = Gen4Battle.effectBackground(id, variant)
  if not spec then return nil end
  return ("%d_%s"):format(tonumber(id), spec.variant)
end

-- ---------------------------------------------------------------------------
-- The touch screen during battle
-- ---------------------------------------------------------------------------

-- The bottom screen's seven tilemaps, in the order the game loads them.  At a
-- Frontier facility index 49 is swapped for 170; everything else is fixed.
Gen4Battle.SUBSCREEN_TILEMAPS = { 0x31, 0x2A, 0x2F, 0x2B, 0x2C, 0x30, 0x2D }
Gen4Battle.SUBSCREEN_FRONTIER_SWAP = { from = 49, to = 170 }

-- The base palette for the touch screen, and its Frontier variant.
Gen4Battle.SUBSCREEN_PALETTE = 242
Gen4Battle.SUBSCREEN_PALETTE_FRONTIER = 340

-- Per background, a second palette pair laid over the base one.  0xFFFF means
-- "leave the base palette alone" -- which is how the five Frontier backgrounds
-- at the end are spelled, since they bring their own.
Gen4Battle.SUBSCREEN_BG_PALETTES = {
  { 0xF3, 0x10B }, { 0xF4, 0x10C }, { 0xF5, 0x10D }, { 0xF6, 0x10E },
  { 0xF7, 0x10F }, { 0xF8, 0x110 }, { 0xF9, 0x111 }, { 0xFA, 0x112 },
  { 0xFB, 0x113 }, { 0xFC, 0x114 }, { 0xFD, 0x115 }, { 0xFE, 0x116 },
  { 0xFF, 0x117 }, { 0x100, 0x118 }, { 0x101, 0x119 }, { 0x102, 0x11A },
  { 0x103, 0x11B }, { 0x11C, 0x11D },
  { 0xFFFF, 0xFFFF }, { 0xFFFF, 0xFFFF }, { 0xFFFF, 0xFFFF },
  { 0xFFFF, 0xFFFF }, { 0xFFFF, 0xFFFF },
}
Gen4Battle.NO_PALETTE = 0xFFFF

-- ---------------------------------------------------------------------------
-- Terrain
-- ---------------------------------------------------------------------------

-- The platform each battler stands on.  Chosen from the tile the player is
-- standing on where that says something (grass, sand, ice, snow, mud, cave,
-- surfable water) and otherwise from the map's background.  24 entries, which
-- is TERRAIN_MAX.
Gen4Battle.TERRAINS = {
  "plain", "sand", "grass", "puddle", "mountain", "cave", "snow", "water",
  "ice", "building", "great_marsh", "bridge",
  "aaron", "bertha", "flint", "lucian", "cynthia", "distortion_world",
  "battle_tower", "battle_factory", "battle_arcade", "battle_castle",
  "battle_hall", "giratina",
}
Gen4Battle.TERRAIN_COUNT = #Gen4Battle.TERRAINS

-- Terrain -> the member BASE NAME in pl_batt_obj.  Mostly the terrain's own
-- name, but four terrains borrow another's art rather than having their own,
-- and one borrows a different one per side:
--
--   puddle   -> path_puddles        bridge (player) -> path_puddles
--   plain    -> path                bridge (enemy)  -> mud
--   mountain -> rocky               building        -> indoors
--   great_marsh -> mud
--
-- Those are the game's tables, not a simplification: sTerrainSpriteSource_*
-- really do point two different terrains at one sheet, and BRIDGE really does
-- take its player-side art from one terrain and its enemy-side art from
-- another.  Collapsing them to a single name per terrain would put a puddle
-- under the enemy on every bridge in Sinnoh.
Gen4Battle.TERRAIN_ART = {
  plain = "path", sand = "sand", grass = "grass", puddle = "path_puddles",
  mountain = "rocky", cave = "cave", snow = "snow", water = "water",
  ice = "ice", building = "indoors", great_marsh = "mud",
  bridge = { player = "path_puddles", enemy = "mud" },
  aaron = "league_aaron", bertha = "league_bertha", flint = "league_flint",
  lucian = "league_lucian", cynthia = "league_cynthia",
  distortion_world = "distortion_world",
  battle_tower = "battle_tower", battle_factory = "battle_factory",
  battle_arcade = "battle_arcade", battle_castle = "battle_castle",
  battle_hall = "battle_hall", giratina = "giratina",
}

-- Terrains whose three "times of day" are the same picture three times.  The
-- palette names say so outright: an outdoor terrain has day/evening/night
-- palettes, an indoor or special one has a single `all` palette listed three
-- times over.  Worth knowing so the extractor writes one image rather than
-- three identical ones.
Gen4Battle.TERRAIN_TIMELESS = {
  cave = true, building = true, aaron = true, bertha = true, flint = true,
  lucian = true, cynthia = true, distortion_world = true,
  battle_tower = true, battle_factory = true, battle_arcade = true,
  battle_castle = true, battle_hall = true, giratina = true,
}

-- The platform sheets are unsized -- tilesX and tilesY are 0xFFFF, because on
-- the hardware their shape comes from an NCER cell bank and the platform is
-- drawn as several OAM sprites rather than as one picture.
--
-- THE BANKS SAY IT EXACTLY, and every terrain shares them: one bank for the
-- player side, one for the enemy side, named for the SIDE rather than for any
-- terrain.  That is why all 24 platform sheets are the same 128 tiles.
--
--   terrain/player_cell   4 OAM entries of 64x32  ->  256 x 32
--   terrain/enemy_cell    2 OAM entries of 64x64  ->  128 x 64
--
-- The widths below are only the fallback for a sheet whose bank cannot be
-- found; eight is the width at which the pieces at least come out whole and
-- the right way up, where sixteen cuts every piece in half down the middle.
-- Nothing in the extractor should reach them while the banks parse.
Gen4Battle.PLATFORM_TILES_WIDE = 8
Gen4Battle.PLATFORM_TILES_HIGH = 16
Gen4Battle.PLATFORM_CELL_BANK = { player = "terrain/player_cell", enemy = "terrain/enemy_cell" }

-- terrainArt(index, side) -> base name, for side "player" or "enemy".
function Gen4Battle.terrainArt(index, side)
  local name = Gen4Battle.TERRAINS[(index or 0) + 1]
  if not name then return nil end
  local art = Gen4Battle.TERRAIN_ART[name]
  if type(art) == "table" then art = art[side or "player"] end
  return art, name
end

-- terrain(index, side, time) -> member names inside pl_batt_obj, ready for
-- Gen4Archives.find.  Palettes are `<art>_<time>` outdoors and `<art>_all`
-- for the timeless terrains above.
function Gen4Battle.terrain(index, side, time)
  local art, name = Gen4Battle.terrainArt(index, side)
  if not art then return nil end
  local timeless = Gen4Battle.TERRAIN_TIMELESS[name]
  local suffix = timeless and "all" or Gen4Battle.TIMES[(time or 0) + 1]
  return {
    name = name,
    art = art,
    side = side or "player",
    tiles = ("terrain/%s/%s"):format(art, side or "player"),
    palette = ("terrain/%s/%s"):format(art, suffix),
    timeless = timeless or false,
  }
end

-- ---------------------------------------------------------------------------
-- Everything else on screen
-- ---------------------------------------------------------------------------

-- The families inside pl_batt_obj, and how wide their sheets are in tiles
-- where the sheet itself does not say.  `nil` means the sheet is sized and
-- needs no hint.
Gen4Battle.OBJ_FAMILIES = {
  { prefix = "terrain/", label = "platforms", tilesWide = 8 },
  { prefix = "healthbox/", label = "healthboxes", tilesWide = 16 },
  { prefix = "type_icons/", label = "type icons", tilesWide = 4 },
  { prefix = "interface/", label = "interface", tilesWide = 8 },
  { prefix = "ball_throws/", label = "ball throws", tilesWide = 4 },
  { prefix = "trainer_backs/", label = "trainer backs", tilesWide = 16 },
  { prefix = "misc/", label = "misc", tilesWide = 8 },
}

-- familyFor(name) -> the entry above whose prefix matches, or nil.
function Gen4Battle.familyFor(name)
  for _, family in ipairs(Gen4Battle.OBJ_FAMILIES) do
    if name:sub(1, #family.prefix) == family.prefix then return family end
  end
  return nil
end

return Gen4Battle
