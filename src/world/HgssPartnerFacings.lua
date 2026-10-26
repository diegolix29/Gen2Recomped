-- WHICH WAY HEARTGOLD / SOULSILVER'S POKEMON SHEETS FACE.
--
-- /a/0/8/1 members 297 .. 862 (Gen4HgssFollowMon.FIRST_MEMBER, .COUNT) are
-- the walking partners' sheets, and they are ALSO the art of every Pokemon a
-- map places as an object -- the `tsure_poke_static_*` sprites: Ilex Forest's
-- two Farfetch'd (member 381), the Spiky-eared Pichu, Marill, the Kimono
-- Girls' Eevees. Each is eight 32x32 frames, two per side, up / down / left /
-- right (Gen4HgssFollowMon.FACINGS, which the partner itself already draws by).
--
-- No sequence table in the archive names them (Gen4HgssFacings reads 280..296
-- and none has eight textures), so the import left `facings` off all 566 and
-- SpriteRenderer read them with the Game Boy's slots: frame 0 -- a BACK view --
-- for "standing south", the front view mirrored for east, and a side view for
-- a step north. Reported from the Ilex Forest chase: the Farfetch'd ran south
-- showing its back and turned to the player with its face when it should
-- have shown its side.
--
-- `covers` is for the import (RomExtractorGen4's sprite table); `stamp` puts
-- the same answer on a cache imported before it, once per dataset, so no
-- re-import is needed. Neither touches a sheet that already says how it faces.

local Partner = {}

local Follow = require("src.import.Gen4HgssFollowMon")

Partner.FACINGS = Follow.FACINGS
Partner.FIRST = Follow.FIRST_MEMBER
Partner.LAST = Follow.FIRST_MEMBER + Follow.COUNT - 1
Partner.SOURCE = ("ROM:/a/0/8/1 walking-partner layout (members %d..%d)")
  :format(Partner.FIRST, Partner.LAST)

function Partner.covers(member, frames)
  member = tonumber(member)
  return member ~= nil and member >= Partner.FIRST and member <= Partner.LAST
         and tonumber(frames) == 8
end

-- data.sprites keys are SPRITE_G4_<member> (RomExtractorGen4.spriteKey);
-- remembered per sprites TABLE, so a reloaded cache is stamped again
local stamped = setmetatable({}, { __mode = "k" })
function Partner.stamp(data)
  local sprites = data and data.sprites
  if type(sprites) ~= "table" or stamped[sprites] then return 0 end
  stamped[sprites] = true
  local n = 0
  for member = Partner.FIRST, Partner.LAST do
    local def = sprites[("SPRITE_G4_%03d"):format(member)]
    if type(def) == "table" and def.facings == nil and Partner.covers(member, def.frames) then
      def.facings = Partner.FACINGS
      def.facingSource = def.facingSource or Partner.SOURCE
      n = n + 1
    end
  end
  return n
end

return Partner
