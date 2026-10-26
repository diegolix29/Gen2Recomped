-- THE POKEMON MOTION PROGRAMS (pokeplatinum src/pokemon_anim.c,
-- res/pokemon_anims/*.s): /pokeanime/pl_poke_anm.narc, 143 members, each a
-- script of 32-bit words -- a command index (0 End .. 33 WaitFade) and its
-- operands. HeartGold / SoulSilver carry the same archive byte for byte as
-- /a/0/9/0.
--
-- Which program a species plays, and after how long, is its SpeciesSpriteData
-- (src/import/Gen4PokeAnimScript.lua: faces[1].animation / startDelay, kept
-- as def.picAnim.motion / startDelay). src/pokemon/Gen4MonMotion.lua runs
-- them.
--
-- Written to the cache module `gen4_poke_motion` as { [n] = { words } }, the
-- words signed.

local M = {}

M.PATHS = { "/pokeanime/pl_poke_anm.narc", "/a/0/9/0" }

function M.parse(bytes)
  local out = {}
  for o = 1, #bytes - 3, 4 do
    local a, b, c, d = bytes:byte(o, o + 3)
    local v = a + b * 256 + c * 65536 + d * 16777216
    if v >= 2147483648 then v = v - 4294967296 end
    out[#out + 1] = v
  end
  return out
end

function M.extract(rom)
  for _, path in ipairs(M.PATHS) do
    local bytes = rom and rom:read(path)
    local ok, narc = pcall(function() return bytes and require("src.import.NarcArchive").parse(bytes) end)
    if ok and narc and narc.count >= 100 then
      local out = {}
      for i = 0, narc.count - 1 do
        local m = narc:get(i)
        if m and #m >= 4 then out[i] = M.parse(m) end
      end
      return out
    end
  end
  return nil
end

return M
