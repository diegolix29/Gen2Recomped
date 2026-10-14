-- Morty's gym in Ecruteak City (HeartGold / SoulSilver).
--
-- pokeheartgold src/field/gymmick/ecruteak.c and gymmick_init.c:
--
--   * InitEcruteakGym (the gym's init script): four candles, all lit.
--   * GymmickInit_Ecruteak: the room is fogged to black -- fog offset 0, every
--     density step 127, colour 0 -- with map objects left out of the fog, so
--     the people show and the floor does not. Each of the four mediums
--     (objects 2..5) has build model 128 placed on her (`gym04spot`, material
--     `dun_spot`, out of the fog). Its texture, `g04_light`, is black with a
--     soft transparent hole -- a darkness mask, not a glow -- so under the
--     black fog it adds nothing visible; it is placed all the same, and an
--     extinguished candle's is culled.
--   * ExtinguishEcruteakGymCandle: 30 frames, then the light shrinks over 4
--     and goes out, the save remembers, and the medium becomes SPRITE_ITAKO_
--     (250), the one with no candle.
--
-- The light sits on the medium's position vector, which is where the
-- cartridge's SysTask puts it while she walks up to the player.

local G = {}

G.CANDLES = 4
G.FIRST_OBJECT = 2          -- obj_T27GYM0101_itako .. _4 are local ids 2..5
G.LIGHT_MODEL = 128
G.FOG = { 0, 0, 0 }
G.OUT_SPRITE = 250          -- SPRITE_ITAKO_

function G.initialState() return { kind = "ecruteak", candles = { false, false, false, false } } end

function G.candleOf(localId)
  local i = (tonumber(localId) or -1) - G.FIRST_OBJECT + 1
  if i >= 1 and i <= G.CANDLES then return i end
  return nil
end

-- the lights, one per lit candle, on its medium; `scale` shrinks one going out
-- `heightAt(x, z)` is the ground's height there (the medium's position
-- vector stands on it; at 0 the light would sit under the raised path)
function G.props(state, npcs, dying, heightAt)
  local out = {}
  for _, npc in ipairs(npcs or {}) do
    local i = npc.def and G.candleOf(npc.def.localId)
    if i and not state.candles[i] and not npc.hidden then
      local x, z = npc.px + 8, npc.py + 8
      local p = { model = G.LIGHT_MODEL, x = x, y = heightAt and heightAt(x, z) or 0, z = z }
      if dying and dying.index == i then p.scale = 1 / dying.factor end
      out[#out + 1] = p
    end
  end
  return out
end

return G
