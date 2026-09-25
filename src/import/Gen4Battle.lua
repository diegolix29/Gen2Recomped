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
