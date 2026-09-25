-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Gen 4 (Platinum) user interface: which archive members make up each screen.
--
-- The title sequence, the start menu, the summary pages, the bag, the trainer
-- card and the Poketch are all built the same way -- tiles, a palette and a
-- tilemap -- but the three parts are NOT stored together and NOT in a fixed
-- order.  In pl_winframe, message_box_00's tiles are member 3 and its palette
-- is member 26; taking members in threes puts the wrong palette on every
-- frame, which produces a picture rather than an error, in the wrong colours.
--
-- What pairs them is the NAME.  Gen4Archives recovers the names, and this
-- module says what to do with them:
--
--   * A group with tiles, a palette and a tilemap is a SCREEN -- compose all
--     three and you have the picture as the game draws it.
--   * A group with only a tilemap borrows the tiles and palette from the
--     archive's main sheet.  This is how the ten summary pages work: one
--     shared 480-tile sheet, ten tilemaps over it.
--   * A group with tiles and a palette but no tilemap is a SHEET -- a set of
--     pieces the game assembles through OAM, not a screen.  It is laid out at
--     a stated width so it can be looked at, and that layout is provisional.
--
-- The point of the table below is that it is nearly all derivable.  Only the
-- shared-sheet choice and the sheet widths are stated, and each is stated
-- because the archive genuinely does not record it.

local Gen4Archives = require("src.import.Gen4Archives")

local Gen4Screens = {}

-- The archives that make up the parts of the game the player actually looks
-- at.  `label` is what the progress line says; `shared` names the group that
-- supplies tiles and palette to tilemap-only groups; `tilesWide` is the
-- fallback layout width for sheets that carry no size.
Gen4Screens.ARCHIVES = {
  {
    path = "/demo/title/titledemo.narc", label = "title screen",
    out = "title", tilesWide = 8,
  },
  {
    path = "/graphic/menu_gra.narc", label = "menus",
    out = "menu", tilesWide = 8,
  },
  {
    path = "/graphic/pl_winframe.narc", label = "window frames",
    out = "windows", tilesWide = 8,
  },
  {
    path = "/graphic/touch_subwindow.narc", label = "touch sub-windows",
    out = "touch", tilesWide = 8,
  },
  {
    path = "/graphic/config_gra.narc", label = "options screen",
    out = "options", tilesWide = 8,
  },
  {
    path = "/graphic/pl_pst_gra.narc", label = "summary screen",
    out = "summary", shared = "tiles_main", tilesWide = 8,
  },
  {
    path = "/graphic/pl_plist_gra.narc", label = "party screen",
    out = "party", tilesWide = 8,
  },
  {
    path = "/graphic/pl_bag_gra.narc", label = "bag",
    out = "bag", tilesWide = 8,
  },
  {
    path = "/graphic/trainer_case.narc", label = "trainer card",
    out = "trainer_card", tilesWide = 8,
    -- The card's two faces share one sheet, and so do the two trainers and
    -- the two Diamond/Pearl trainers.  See `tilesFrom` in `plan`.
    tilesFrom = {
      trainer_card_front = "trainer_card",
      trainer_card_back = "trainer_card",
      lucas = "player", dawn = "player",
      lucas_dp = "player_dp", dawn_dp = "player_dp",
    },
  },
  {
    path = "/graphic/poketch.narc", label = "Poketch",
    out = "poketch", tilesWide = 8,
    -- Both watches draw on one background, and the digit strip has its own.
    tilesFrom = {
      digital_watch = "watch", analog_watch = "watch",
      digital_watch_digits = "digits",
    },
  },
  {
    path = "/graphic/shop_gra.narc", label = "shop",
    out = "shop", tilesWide = 8,
  },
  {
    path = "/graphic/tmap_gra.narc", label = "town map",
    out = "town_map", tilesWide = 8,
  },
  {
    path = "/resource/eng/zukan/zukan.narc", label = "Pokedex",
    out = "pokedex", tilesWide = 8,
  },
  {
    path = "/graphic/mail_gra.narc", label = "mail",
    out = "mail", tilesWide = 8,
  },
  {
    path = "/graphic/ntag_gra.narc", label = "berry tag",
    out = "berry_tag", tilesWide = 8,
  },
  {
    path = "/graphic/pl_font.narc", label = "fonts",
    out = "font", tilesWide = 16,
  },
}

Gen4Screens.SCREEN = "screen"
Gen4Screens.SHEET = "sheet"

-- TWO NAMING CONVENTIONS LIVE IN THESE ARCHIVES, and a planner that knows only
-- one silently drops half the game's screens.
--
--   SUBJECT-NAMED.  The base name is the thing and the extension is the role:
--   "message_box_00.NCGR" with "message_box_00.NCLR", "logo.NCGR" with
--   "logo.NCLR" and "logo.NSCR".  Grouping by base name is exactly right.
--
--   ROLE-NAMED.  The NAME is the role and the archive is the thing:
--   shop_gra is "tiles.NCGR", "default.NCLR", "tilemap.NSCR",
--   "tilemap_no_item.NSCR".  Here every base name differs, so grouping by
--   base name produces four groups of one and not a single composable screen.
--
-- A third case sits between them: pl_plist_gra names its sheet
-- "subscreen_tiles.NCGR" and its tilemap "subscreen.NSCR", so the two belong
-- together but their bases differ by a suffix.
--
-- So: normalise away the role suffixes, then let a group that is missing a
-- part fall back to the archive's own sheet and palette.  Falling back is
-- recorded on the job rather than hidden, because a borrowed palette is a
-- guess and a guess that is not marked is indistinguishable from a fact.
-- `_bg_tiles` is FIRST because the list is tried in order and `_tiles` would
-- otherwise match it and leave a stray `_bg`.  Its absence was the whole
-- reason the Pokétch drew as tile soup: every app names its background
-- `<app>_bg_tiles.NCGR` beside `<app>.NSCR`, and without this suffix the two
-- never grouped, so each app's tilemap fell back to the archive's shared
-- sheet -- the device border -- and composed the border's tiles through the
-- app's map.
local ROLE_SUFFIXES = { "_bg_tiles", "_tileset", "_tiles", "_tilemap",
                        "_gra", "_graphics" }

local function normalise(base)
  for _, suffix in ipairs(ROLE_SUFFIXES) do
    if #base > #suffix and base:sub(-#suffix) == suffix then
      return base:sub(1, #base - #suffix)
    end
  end
  return base
end

-- A group is only worth drawing if it can be given pixels.  A lone animation,
-- a lone cell bank, a 3D model -- all real members, none of them a picture.
local function kindOf(group)
  if group.NSCR then return Gen4Screens.SCREEN end
  if group.NCGR then return Gen4Screens.SHEET end
  return nil
end

-- plan(path, options) -> array of jobs, or nil when the archive has no names.
--
-- Each job is { name, kind, tiles, palette, tilemap, tilesWide }, with member
-- indices already resolved.  Nothing is read from the cartridge here; this is
-- only the plan.
function Gen4Screens.plan(path, options)
  options = options or {}
  local raw = Gen4Archives.groups(path)
  if not raw then return nil, "no name table for " .. tostring(path) end

  -- Re-group on the normalised base, so subscreen_tiles.NCGR and
  -- subscreen.NSCR land together.
  local byBase, groups = {}, {}
  for _, group in ipairs(raw) do
    local base = normalise(group.base)
    local merged = byBase[base]
    if not merged then
      -- Keep the name AS WRITTEN as well as the normalised one: cell banks are
      -- found by the spelling the cartridge uses ("bag_sprite_male"), not by
      -- the shortened form this table groups on.
      merged = { base = base, raw = group.base }
      byBase[base] = merged
      groups[#groups + 1] = merged
    end
    if group.NCGR and not merged.sheetName then merged.sheetName = group.base end
    -- A BASE CAN OWN TWO SHEETS, and only one of them is the background.
    -- `stopwatch_bg_tiles.NCGR` and `stopwatch.NCGR` normalise to the same
    -- name; the first is the app's background and the second is its sprite
    -- sheet, and taking whichever came first in the archive picked the sprites
    -- about half the time.  A sheet whose own name carries a role suffix is
    -- the background, and it wins.
    if group.NCGR and group.base ~= merged.base then
      merged.bgNCGR = merged.bgNCGR or group.NCGR
    end
    for _, role in ipairs({ "NCGR", "NCLR", "NSCR" }) do
      if group[role] and not merged[role] then merged[role] = group[role] end
    end
  end

  -- The archive's fallback sheet and palette.  Named outright where the
  -- caller knows better; otherwise the first of each, which in every archive
  -- here is the main one.
  local sharedTiles, sharedPalette, sharedFrom
  for _, group in ipairs(groups) do
    if options.shared and normalise(options.shared) == group.base then
      sharedTiles, sharedPalette, sharedFrom = group.NCGR, group.NCLR, group.base
      break
    end
  end
  -- Otherwise: prefer the sheet that a tilemap already points at, because a
  -- tilemap with no sheet of its own is far likelier to belong to a screen
  -- than to the first sprite in the archive.  In pl_bag_gra the first NCGR is
  -- the player's bag sprite and the screen sheet is the twelfth member; taking
  -- the first one puts the bag sprite's pixels behind the bag's own UI.
  if not sharedTiles then
    for _, group in ipairs(groups) do
      if group.NCGR and group.NSCR and group.NCLR then
        sharedTiles, sharedPalette, sharedFrom = group.NCGR, group.NCLR, group.base
        break
      end
    end
  end
  if not sharedTiles then
    for _, group in ipairs(groups) do
      if group.NCGR and group.NCLR then
        sharedTiles, sharedPalette, sharedFrom = group.NCGR, group.NCLR, group.base
        break
      end
    end
  end
  if not sharedTiles then
    for _, group in ipairs(groups) do
      if group.NCGR and not sharedTiles then
        sharedTiles, sharedFrom = group.NCGR, group.base
      end
      if group.NCLR and not sharedPalette then sharedPalette = group.NCLR end
    end
  end

  -- WHERE A SCREEN BORROWS ITS SHEET FROM, when the names do not pair it.
  --
  -- Normalising the role suffixes pairs most of them, and the shared sheet is
  -- a reasonable last resort -- but between those two sit the screens that
  -- name their sheet after something else entirely.  Both watches draw on
  -- `watch_bg_tiles`; the card's front and back both draw on
  -- `trainer_card_tiles`; Lucas and Dawn both draw on `player_tiles`.  No rule
  -- over the names finds those, and the shared sheet is WRONG rather than
  -- merely worse, so they are written down per archive and the rest is left to
  -- the suffixes.
  local byBaseGroup = {}
  for _, group in ipairs(groups) do byBaseGroup[group.base] = group end

  local jobs = {}
  for _, group in ipairs(groups) do
    local kind = kindOf(group)
    if kind then
      local lent = options.tilesFrom and options.tilesFrom[group.base]
      local donor = lent and byBaseGroup[lent] or nil
      -- A DONOR OUTRANKS THE GROUP'S OWN SHEET, because it is written down
      -- for the cases where the group's own sheet is the wrong one: the analog
      -- watch has an `analog_watch.NCGR`, and it is the hands, not the face.
      local tiles = (donor and donor.NCGR) or group.bgNCGR or group.NCGR
                    or sharedTiles
      local palette = group.NCLR or (donor and donor.NCLR) or sharedPalette
      -- A tilemap with no sheet of its own takes the shared sheet AND the
      -- shared palette together.  Pairing the shared sheet with this group's
      -- own palette is the precise mistake the name table exists to stop.
      if group.NSCR and not (group.bgNCGR or group.NCGR) then
        tiles = (donor and donor.NCGR) or sharedTiles
        palette = group.NCLR or (donor and donor.NCLR) or sharedPalette
      end
      if tiles and palette then
        local job = {
          name = group.base,
          kind = kind,
          tiles = tiles,
          palette = palette,
          tilemap = group.NSCR,
          tilesWide = options.tilesWide or 8,
          borrowedTiles = (group.NCGR == nil) or false,
          borrowedPalette = (group.NCLR == nil) or false,
        }
        -- A sheet with a cell bank is not a guess any more: the bank says how
        -- many pieces it has, how big each one is and where it sits.  Only a
        -- sheet with no bank anywhere in its archive still needs a width.
        if kind == Gen4Screens.SHEET then
          local at, via, how =
            Gen4Archives.cellBank(path, group.sheetName or group.raw or group.base)
          if at then
            job.cell = at
            job.cellFrom = via
            job.cellMatch = how
          end
        end
        jobs[#jobs + 1] = job
      end
    end
  end
  return jobs, sharedFrom
end

-- planAll() -> { { archive = <entry>, jobs = {...} }, ... }
function Gen4Screens.planAll()
  local out = {}
  for _, entry in ipairs(Gen4Screens.ARCHIVES) do
    local jobs = Gen4Screens.plan(entry.path, entry)
    if jobs and #jobs > 0 then
      out[#out + 1] = { archive = entry, jobs = jobs }
    end
  end
  return out
end

return Gen4Screens
