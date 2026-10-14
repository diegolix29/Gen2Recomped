-- PLATINUM'S JOURNAL ART (src/applications/journal_display/journal_controller.c
-- JournalController_LoadGraphics), from /graphic/f_note_gra.narc:
--
--   member 0 / 2 / 4   the boy's notebook: tilemap, tiles, palettes
--   member 1 / 3 / 5   the girl's
--
-- The one 32 x 32 tilemap is every page. JournalController_LoadNewPagePalette
-- repaints the whole map in palette `page`, so each of the ten pages has its
-- own paper; they are composed here as journal_<m|f>_<page>.png (256 x 192).
--
-- Written to assets/generated/gen4/journal/<key>.png, indexed in the cache
-- module `gen4_journal_art`.

local Gen4JournalArt = {}

Gen4JournalArt.PATH = "/graphic/f_note_gra.narc"
Gen4JournalArt.PAGES = 10

function Gen4JournalArt.images(rom)
  local G = require("src.import.Gen4Graphics")
  local N = require("src.import.NarcArchive")
  local bytes = rom:read(Gen4JournalArt.PATH)
  if not bytes then return nil, "f_note_gra missing" end
  local narc = N.parse(bytes)
  local function member(i)
    local b = narc:get(i)
    if b and G.isCompressed(b) then b = G.decompress(b) end
    return b
  end
  local out = {}
  for g, key in ipairs({ "m", "f" }) do
    local k = g - 1
    local map, sheet, pal = G.tilemap(member(k)), G.tiles(member(2 + k)), G.palette(member(4 + k))
    if not (map and sheet and pal) then return nil, "f_note_gra unreadable" end
    local across = math.floor((map.width and map.width > 0 and map.width or 256) / 8)
    for page = 0, Gen4JournalArt.PAGES - 1 do
      local cells = {}
      for row = 0, 23 do
        for col = 0, 31 do
          local c = map.cells[row * across + col + 1]
          cells[#cells + 1] = c and { tile = c.tile, flipX = c.flipX, flipY = c.flipY, palette = page }
            or { tile = 0, palette = page }
        end
      end
      out["journal_" .. key .. "_" .. page] = G.compose({ width = 256, height = 192, cells = cells }, sheet, pal)
    end
  end
  return out
end

return Gen4JournalArt
