-- tools/gen4_hgss_overworld_harness/field_rom.lua
--
-- HGSS_FIELD_ROM=<HeartGold/SoulSilver .nds>: what the hgss-water-emotes-v1
-- import adds, read from the ROM into memory as the overworld is pushed, so an
-- install imported before it shows it without being written to:
--
--   gen4_emotes                       the "!" / "!!" (Gen4Emotes, /a/1/0/3)
--   gen4_terrain.texAnims ...         the sea's /a/1/4/0 animation
--                                     (Gen4HgssTexAnim.extractInto)
--
-- HGSS_FIELD_NO_WATER=1 / HGSS_FIELD_NO_EMOTES=1 leave one half out.

local StateStack = require("src.core.StateStack")
local push, injected = StateStack.push, false
StateStack.push = function(self, state, ...)
  local G = package.loaded["src.core.Game"]
  if not injected and G and G.data and G.data.gen4_terrain then
    injected = true
    local path = os.getenv("HGSS_FIELD_ROM")
    local X = assert(require("src.import.RomExtractorGen4").new(path, os.getenv("VERSION") or "heartgold"))
    if not os.getenv("HGSS_FIELD_NO_EMOTES") then
      local Narc = require("src.import.NarcArchive")
      local arc = Narc.parse(X.rom:read("/a/1/0/3"))
      G.data.gen4_emotes = assert(require("src.import.Gen4Emotes").extract(arc))
      print(("[field] gen4_emotes from %s: \"!\" member %s, \"!!\" member %s"):format(path,
        tostring(G.data.gen4_emotes.exclamation.member),
        tostring(G.data.gen4_emotes.double and G.data.gen4_emotes.double.member)))
    end
    if not os.getenv("HGSS_FIELD_NO_WATER") then
      local report = assert(require("src.import.Gen4HgssTexAnim").extractInto(X, G.data.gen4_terrain))
      print(("[field] texture animation from %s: %d animation(s), %d map(s), %d chunk(s)"):format(
        path, report.animations, report.maps, report.chunks))
    end
    X:close()
  end
  return push(self, state, ...)
end
