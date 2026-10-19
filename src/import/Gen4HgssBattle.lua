-- HEARTGOLD AND SOULSILVER'S BATTLE BACKDROPS (/a/0/0/7).
--
-- The same 23 backdrops as Platinum in the same order (pokeheartgold
-- include/constants/battle.h enum BattleBg: GENERAL, OCEAN, CITY, FOREST ...
-- with Johto's Elite Four -- WILL, KOGA, BRUNO, KAREN, LANCE -- where
-- Platinum's sit), in the same archive shape as pl_batt_bg.narc, at the same
-- member arithmetic but one base: overlay 12's background load
-- (asm/overlay_12_022378C0.s) reads
--
--   GfGfxLoader_LoadCharData(NARC 7, bg + 3)               -- tiles, as Platinum
--   PaletteData_LoadNarc(NARC 7, bg * 3 + 0xB0 + time)     -- 176, not 172
--   ... the tilemap at member 2                            -- as Platinum
--
-- (the archive has four more members before its palettes than Platinum's,
-- 91 palettes from 175 against 91 from 171). The names are Gen4Battle's, by
-- index, because the battle screen looks a backdrop up by that name.

local Battle = require("src.import.Gen4Battle")

local B = {}

B.PATH = "/a/0/0/7"
B.PALETTE_BASE = 0xB0

-- the HGSS spec for backdrop `index` at `time` (0 day, 1 evening, 2 night)
function B.background(index, time)
  local spec = Battle.background(index, time)
  if not spec then return nil end
  spec.palette = B.PALETTE_BASE + index * Battle.BG_PALETTE_STRIDE + time
  return spec
end

-- backgrounds(x) -> { [name] = entry }, written, skipped
function B.backgrounds(x)
  local arc = x:archiveAt(B.PATH)
  local out, written, skipped = {}, 0, {}
  if not arc then return out, 0, { B.PATH } end
  for i = 0, Battle.BACKGROUND_COUNT - 1 do
    for t = 0, #Battle.TIMES - 1 do
      local spec = B.background(i, t)
      local name = ("%s_%s"):format(spec.name, spec.time)
      for _, gray in ipairs({ false, true }) do
        local image = x:composeJob(arc, { tiles = spec.tiles, palette = spec.palette,
                                          tilemap = spec.tilemap, grayscale = gray or nil })
        local key = gray and (name .. "_gray") or name
        local entry = image and x:saveImage("battle/background/" .. key, image, {
          background = i, time = spec.time, fadeTo = spec.fadeTo, grayscale = gray or nil,
        })
        if entry then out[key] = entry; written = written + 1 else skipped[#skipped + 1] = key end
      end
    end
  end
  return out, written, skipped
end

return B
