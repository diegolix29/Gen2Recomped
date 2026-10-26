-- PLATINUM'S EGG HATCH CUTSCENE ART (src/cutscenes/egg_hatch/graphics.c).
--
-- /demo/egg/data/egg_data.narc, in res/graphics/egg_hatch/egg_graphics.order:
--   0 background NCGR, 1 its NSCR, 8 its NCLR (BG3; the evolution scene
--     borrows the same three, Gen4EvolutionArt)
--   2 egg NANR, 3 egg NCER, 4 egg NCGR, 9 egg NCLR -- six 32x32 cells, the
--     whole egg to "ready to shatter" (EggAnimFrame), drawn at (128, 120)
--   5 bar NANR, 6 bar NCER, 7 bar NCGR, 10 bar NCLR -- the black letterbox
--     bars, at y = -16 and y = 192 - 48, sliding off 4 px a frame
-- /demo/egg/data/particle/egg_demo_particle.narc: member 0 normal.spa (the
-- emitters FIRST_EGG_SHARDS 0, MORE_EGG_SHARDS 1, EGG_EXPLODES 2, SPARKLES
-- 3), member 1 manaphy.spa.
--
-- HeartGold / SoulSilver carry both archives byte for byte as /a/1/1/5 and
-- /a/1/1/6.
--
-- Pictures: `background`, `egg_0`..`egg_5`, `bar`, `normal_<i>` and
-- `manaphy_<i>` (each SPA file's textures in file order). Data
-- (`gen4_egg_hatch_ink`): `normal` / `manaphy` = { emitters, textures }
-- in Gen4EvolutionArt.data's shape, and the cells' origins.

local Gen4EggHatchArt = {}

Gen4EggHatchArt.PLATINUM = { graphics = "/demo/egg/data/egg_data.narc",
  particles = "/demo/egg/data/particle/egg_demo_particle.narc" }
Gen4EggHatchArt.HGSS = { graphics = "/a/1/1/5", particles = "/a/1/1/6" }

local function opener(rom, path)
  local G = require("src.import.Gen4Graphics")
  local bytes = path and rom:read(path)
  local narc = bytes and require("src.import.NarcArchive").parse(bytes)
  if not narc then return nil end
  return function(i)
    local b = narc:get(i)
    if b and G.isCompressed(b) then b = G.decompress(b) end
    return b
  end
end

local function row(colours, r)
  local out = {}
  for i = 1, 16 do out[i] = colours[r * 16 + i] or { 0, 0, 0 } end
  return out
end

-- every cell of a bank, each OAM entry on palette row 0
local function cells(member, char, cell, pal)
  local G = require("src.import.Gen4Graphics")
  local Cells = require("src.import.Gen4Cells")
  local sheet, bank, colours = G.tiles(member(char)), Cells.parse(member(cell), G), G.palette(member(pal))
  if not (sheet and bank and colours) then return {} end
  local out = {}
  for i, c in ipairs(bank.cells) do
    local flat = {}
    for k, v in pairs(c) do flat[k] = v end
    flat.oam = {}
    for j, o in ipairs(c.oam) do
      local copy = {}
      for k, v in pairs(o) do copy[k] = v end
      copy.palette = 0
      flat.oam[j] = copy
    end
    local pic = Cells.assemble(flat, sheet, row(colours, 0), bank, G)
    if pic then pic.originX, pic.originY = Cells.extent(flat) end
    out[i] = pic
  end
  return out
end

local function config(hgss) return hgss and Gen4EggHatchArt.HGSS or Gen4EggHatchArt.PLATINUM end

function Gen4EggHatchArt.images(rom, hgss)
  local cfg = config(hgss)
  local member = opener(rom, cfg.graphics)
  if not member then return nil, "egg_data missing" end
  local G = require("src.import.Gen4Graphics")
  local out = {}
  local sheet, map, pal = G.tiles(member(0)), G.tilemap(member(1)), G.palette(member(8))
  if sheet and map and pal then out.background = G.compose(map, sheet, pal) end
  for i, pic in ipairs(cells(member, 4, 3, 9)) do out[("egg_%d"):format(i - 1)] = pic end
  out.bar = cells(member, 7, 6, 10)[1]
  local particles = opener(rom, cfg.particles)
  local P = require("src.import.Gen4Particle")
  for i, name in ipairs({ "normal", "manaphy" }) do
    local list = particles and P.textures(particles(i - 1))
    for t, texture in ipairs(list or {}) do out[("%s_%d"):format(name, t - 1)] = P.rgba(texture) end
  end
  return out
end

-- an SPA file's emitters and each texture's repeat / flip bits (the same
-- reading Gen4EvolutionArt.data does)
local function spa(data)
  if not data then return nil end
  local P = require("src.import.Gen4Particle")
  local emitters = P.emitters(data)
  local out = { emitters = emitters, count = emitters and #emitters or 0, textures = {} }
  local head = P.header(data)
  if head then
    local at = head.textureAt
    for i = 1, head.textures do
      local function u32(o) local a, b, c, d = data:byte(o + 1, o + 4); return d and a + b * 256 + c * 65536 + d * 16777216 end
      local param, total = u32(at + 4), u32(at + 28)
      if not (param and total and total > 0) then break end
      local bits = math.floor(param / 4096) % 16
      out.textures[i] = { repeatS = bits % 2 == 1, repeatT = math.floor(bits / 2) % 2 == 1,
        flipS = math.floor(bits / 4) % 2 == 1, flipT = math.floor(bits / 8) % 2 == 1 }
      at = at + total
    end
  end
  return out
end

function Gen4EggHatchArt.data(rom, hgss)
  local cfg = config(hgss)
  local particles = opener(rom, cfg.particles)
  if not particles then return nil end
  return { normal = spa(particles(0)), manaphy = spa(particles(1)) }
end

return Gen4EggHatchArt
