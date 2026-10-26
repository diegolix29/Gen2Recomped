-- BLACK AND WHITE'S EGG HATCH (overlay 215, egg_demo_graphic.c /
-- egg_demo_view.c; launched by script 0x106 from M0858 through the ov10
-- event at 0x02166B58). Read out of the overlay's tables:
--
--   /a/1/8/9 -- the egg variant of the evolution scene's /a/1/8/2:
--      3-5  the letterbox (black bars 24 px deep, main BG)
--     10    SPA, 5 emitters, 4 textures (_021F7300: arc 0xBD member 10),
--           fired on the frame tables at _021F7314 / _021F7340 -- the
--           burst at the end of the egg's phase, which the view module
--           (0x021F67E0) runs 380 frames for an Egg and 300 for Manaphy's
--           (0x1EA - 0x6E / - 0xBE): the Egg 0, 1 and 2 at 380; the Manaphy
--           Egg 3 and 4 at 0, then 0, 1 and 2 at 300
--      6-9  the light model demo_sinka02 and its BCA / BMA / BTA
--           (_021F7354) -- NOT drawn here yet
--   /a/0/0/4 -- the egg itself is a Pokemon picture: entry 650 (the Egg)
--     and 651 (the Manaphy Egg), MCSS with two NMAR sequences -- 0 the idle
--     wobble, 1 the hatch (381 frames for the Egg).
--
-- Written as `gen5_egg_hatch`.

local E = {}

E.PATH = "/a/1/8/9"
E.PARTICLES = 10
E.SPRITES = "/a/0/0/4"
E.EGG, E.MANAPHY_EGG = 650, 651
E.SCHEDULE = { egg = { { 380, { 0, 1, 2 } } },
               manaphy = { { 0, { 3, 4 } }, { 300, { 0, 1, 2 } } } }

function E.build(x)
  local Narc = require("src.import.NarcArchive")
  local raw = x.rom:read(E.PATH)
  local arc = raw and Narc.parse(raw)
  if not arc then return nil end
  local P = require("src.import.Gen4Particle")
  local out = { images = {}, schedule = E.SCHEDULE, letterbox = 24,
                source = "ROM:/a/1/8/9 (10 particles) + /a/0/0/4 650/651" }
  local spa = arc:get(E.PARTICLES)
  if spa then
    out.emitters = P.emitters(spa)
    for i, texture in ipairs(P.textures(spa) or {}) do
      local entry = x:saveImage(("egg_hatch5/particle_%d"):format(i - 1), P.rgba(texture))
      if entry then out.images[("particle_%d"):format(i - 1)] = entry end
    end
    local head = P.header(spa)
    if head then
      out.textures = {}
      local at = head.textureAt
      local function u32(o) local a, b, c, d = spa:byte(o + 1, o + 4); return d and a + b * 256 + c * 65536 + d * 16777216 end
      for i = 1, head.textures do
        local param, total = u32(at + 4), u32(at + 28)
        if not (param and total and total > 0) then break end
        local bits = math.floor(param / 4096) % 16
        out.textures[i] = { repeatS = bits % 2 == 1, repeatT = math.floor(bits / 2) % 2 == 1,
          flipS = math.floor(bits / 4) % 2 == 1, flipT = math.floor(bits / 8) % 2 == 1 }
        at = at + total
      end
    end
  end
  -- the two eggs' MCSS, packed the way the battle pictures' are
  local sprites = x.rom:read(E.SPRITES)
  local sarc = sprites and Narc.parse(sprites)
  if sarc then
    local Anim = require("src.import.Gen5MonAnim")
    for key, id in pairs({ egg = E.EGG, manaphy = E.MANAPHY_EGG }) do
      local okL, set = pcall(Anim.load, sarc, id, "front")
      if okL and set then
        local okP, packed = pcall(Anim.pack, sarc, id)
        local path = okP and packed and x:saveBinary(("egg_hatch5/mcss_%03d.bin"):format(id), packed)
        if path then out[key] = { path = path, species = id } end
      end
    end
  end
  return out
end

return E
