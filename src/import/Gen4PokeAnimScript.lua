-- EACH SPECIES' OWN BATTLE-SPRITE FRAME SCRIPT (Platinum
-- /poketool/poke_edit/pl_poke_data.narc, HeartGold / SoulSilver /a/1/8/0;
-- member 0 in both). One 89-byte SpeciesSpriteData a species (pokeplatinum
-- include/struct_defs/species_sprite_data.h; pokeheartgold
-- UnkStruct_02072914, read by NARC_ReadPokepicAnimScript):
--
--   faceAnims[2] (front, back), each:
--     u8 cryDelay, u8 animation (the motion program), u8 startDelay,
--     10 x { s8 next, u8 duration, s8 xOffset, s8 yOffset }
--   s8 yOffset, s8 xOffsetShadow, u8 shadowSize
--
-- `next` is the sprite frame to show (0 or 1), -1 ends the script, and a
-- value below -1 loops back to entry (-2 - next) `duration` times
-- (Pokepic_RunAnimInternal, pokeheartgold src/pokepic.c 997-1022).

local S = {}

S.SIZE = 89
S.FACE = 43
S.ENTRIES = 10

local function s8(v) return v >= 128 and v - 256 or v end

-- parse(bytes, species) -> the record, or nil
function S.parse(bytes, species)
  local at = species * S.SIZE
  if type(bytes) ~= "string" or #bytes < at + S.SIZE then return nil end
  local function b(i) return bytes:byte(at + i + 1) end
  local out = { faces = {} }
  for f = 0, 1 do
    local o = f * S.FACE
    local face = { cryDelay = b(o), animation = b(o + 1), startDelay = b(o + 2), script = {} }
    for e = 0, S.ENTRIES - 1 do
      local p = o + 3 + e * 4
      face.script[e + 1] = { next = s8(b(p)), duration = b(p + 1), x = s8(b(p + 2)), y = s8(b(p + 3)) }
    end
    out.faces[f + 1] = face
  end
  out.yOffset, out.shadowX, out.shadowSize = s8(b(86)), s8(b(87)), b(88)
  return out
end

-- play(face) -> { { frame = 1-based, dur = frames, x = offset }, ... }: the
-- script run the way the cartridge runs it, flattened (capped, in case a
-- script loops without end)
function S.play(face, cap)
  cap = cap or 600
  local script = face and face.script
  if not script or not script[1] or script[1].next < 0 then return nil end
  local out, total = {}, 0
  local loops = {}
  local i = 0                                   -- 0-based entry
  local function push(e)
    local dur = math.max(1, e.duration)
    out[#out + 1] = { frame = e.next + 1, dur = dur, x = e.x ~= 0 and e.x or nil }
    total = total + dur
  end
  push(script[1])
  while total < cap do
    i = i + 1
    while i < S.ENTRIES and script[i + 1].next < -1 do
      loops[i] = (loops[i] or 0) + 1
      local e = script[i + 1]
      if e.duration == loops[i] or e.duration == 0 then
        loops[i] = 0
        i = i + 1
      else
        i = -2 - e.next
      end
    end
    if i >= S.ENTRIES or script[i + 1].next == -1 then break end
    push(script[i + 1])
  end
  return out
end

return S
