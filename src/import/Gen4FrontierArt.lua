-- THE BATTLE FRONTIER SCENES' BACKDROPS (/resource/eng/frontier_graphic/
-- frontier_bg.narc, sFrontierScenes in overlay104/frontier_scenes.c).
--
-- Each scene names a tilemap, its tiles and its palette (and some a second
-- layer drawn over it). The member numbers are the line numbers, less one,
-- of res/graphics/frontier/backgrounds/frontier_backgrounds.order. Composed
-- whole -- the screen scrolls over them -- and written to
-- assets/generated/gen4/frontier/<scene>.png, indexed in the cache module
-- `gen4_frontier_art`.

local Gen4FrontierArt = {}

Gen4FrontierArt.PATH = "/resource/eng/frontier_graphic/frontier_bg.narc"

-- [scene key] = { tilemap, tiles, palette [, overlay = { tilemap, tiles, palette }] }
Gen4FrontierArt.SCENES = {
  factory_corridor = { 2, 0, 129, overlay = { 3, 0, 129 } },
  factory_battle_room = { 1, 0, 129 },
  hall_corridor = { 17, 16, 132 },
  hall_battle_room = { 20, 14, 131, overlay = { 22, 19, 133 } },
  castle_corridor = { 26, 25, 135 },
  castle_passage = { 28, 27, 136 },
  castle_battle_room = { 30, 29, 140, overlay = { 33, 29, 140 } },
  arcade_corridor = { 55, 56, 143 },
  arcade_battle_room = { 52, 54, 142 },
}

function Gen4FrontierArt.compose(narc, spec)
  local G = require("src.import.Gen4Graphics")
  local function member(i)
    local b = narc:get(i)
    if b and G.isCompressed(b) then b = G.decompress(b) end
    return b
  end
  local map, sheet, pal = G.tilemap(member(spec[1])), G.tiles(member(spec[2])), G.palette(member(spec[3]))
  if not (map and sheet and pal) then return nil end
  -- GX_BGMODE_5: the scene's backgrounds are extended affine BGs, whose maps
  -- run straight across rather than in 256-pixel blocks
  map.linear = true
  return G.compose(map, sheet, pal), map
end

function Gen4FrontierArt.images(rom)
  local N = require("src.import.NarcArchive")
  local bytes = rom:read(Gen4FrontierArt.PATH)
  if not bytes then return nil, "frontier_bg missing" end
  local narc = N.parse(bytes)
  local out = {}
  for key, spec in pairs(Gen4FrontierArt.SCENES) do
    local ok, img = pcall(Gen4FrontierArt.compose, narc, spec)
    if ok and img then out[key] = img end
    if spec.overlay then
      local ok2, over = pcall(Gen4FrontierArt.compose, narc, spec.overlay)
      if ok2 and over then out[key .. "_overlay"] = over end
    end
  end
  return out
end

return Gen4FrontierArt
