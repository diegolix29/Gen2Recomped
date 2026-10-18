-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- THE "!" OVER A TRAINER WHO HAS SEEN YOU, and the "!!" of a Vs. Seeker
-- rematch.
--
-- `MovementAction_EmoteExclamationMark` (pokeplatinum src/unk_020655F4.c)
-- starts the emote field effect (src/overlay005/ov5_021F5A10.c), which loads
-- its billboard out of `/data/mmodel/fldeff.narc`: model member 85 for the
-- "!" -- texture `sisen_ef`, "line of sight" -- and 108 for the "!!",
-- `saisen_ef`, "rematch". Each is a 16x16 white speech bubble with the mark
-- in red, and each model carries its own TEX0, so the picture comes straight
-- out of the model as the player's shadow does (see `extractField`).
--
-- Stored as raw RGBA rather than a PNG so a cache can gain it without LOVE:
-- 1 KB each, and the runtime turns them into images when first drawn.

local Gen4Emotes = {}

Gen4Emotes.ARCHIVE = "/data/mmodel/fldeff.narc"
-- HEARTGOLD / SOULSILVER keep the same field-effect models in /a/1/0/3, and
-- the two emotes are members 118 and 125 there -- measured, by texture name,
-- off both ROMs (scratch probe over every 16x16 BMD0). Read by name, so the
-- member numbers are only where the search starts.
Gen4Emotes.ARCHIVES = { "/data/mmodel/fldeff.narc", "/a/1/0/3" }
Gen4Emotes.MEMBERS = { exclamation = 85, double = 108 }
Gen4Emotes.TEXTURES = { exclamation = "sisen_ef", double = "saisen_ef" }

-- Where it hangs and how it moves (ov5_021F5A10.c): the billboard's plane
-- spans 0..16 up from its anchor (measured off model 85), and the anchor is
-- the owner's drawn position + 32 units -- the top of a 32-unit character.
-- It rises 6, 10, 12, 12, 10, 6, 0 over seven frames (velocity 6, less 2 a
-- frame, stopping at 0), then holds 30.
Gen4Emotes.LIFT = 32
Gen4Emotes.BOUNCE = { 6, 10, 12, 12, 10, 6, 0 }
Gen4Emotes.HOLD = 30
Gen4Emotes.FRAMES = #Gen4Emotes.BOUNCE + Gen4Emotes.HOLD

function Gen4Emotes.extract(arc)
  local Nsbmd = require("src.import.Gen4Nsbmd")
  local Models = require("src.import.Gen4Models")
  local out = {}
  local function decodeAt(member)
    local bytes = arc and member >= 0 and member < arc.count and arc:get(member)
    if not (bytes and bytes:sub(1, 4) == "BMD0") then return nil end
    local okS, sections = pcall(Nsbmd.sections, bytes)
    local parsed = okS and sections and sections.TEX0 and Models.parse(bytes, sections.TEX0)
    local okD, image = pcall(function() return parsed and Models.decode(parsed, bytes, 1, 1) end)
    return okD and image or nil, parsed
  end
  local function named(parsed, want)
    local t = parsed and parsed.textures and parsed.textures[1]
    return t and t.name == want
  end
  for key, start in pairs(Gen4Emotes.MEMBERS) do
    -- the cartridge's own member when its texture is the emote's, else the
    -- member whose texture is (HGSS: 118 / 125)
    local want = Gen4Emotes.TEXTURES[key]
    local member = start
    local image, parsed = decodeAt(member)
    if not named(parsed, want) then
      image, parsed = nil, nil
      for m = 0, (arc and arc.count or 0) - 1 do
        local img, p = decodeAt(m)
        if named(p, want) then image, parsed, member = img, p, m break end
      end
    end
    if image then
      out[key] = { width = image.width, height = image.height, rgba = image.rgba,
                   member = member,
                   texture = parsed.textures[1] and parsed.textures[1].name or nil }
    end
  end
  if not out.exclamation then return nil, "fldeff member 85 would not decode" end
  return out
end

-- The bounce offset, in units, `age` frames after the emote appeared.
function Gen4Emotes.bounce(age)
  age = math.floor(tonumber(age) or 0)
  if age < 1 then return 0 end
  return Gen4Emotes.BOUNCE[age] or 0
end

return Gen4Emotes
