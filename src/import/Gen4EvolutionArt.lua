-- PLATINUM'S EVOLUTION SCENE PARTICLES (src/evolution.c, src/unk_0207C63C.c).
--
-- sub_0207C894 loads member 0 of NARC 124 --
-- /demo/shinka/data/particle/shinka_demo_particle.narc -- as the scene's one
-- particle resource, and the scene fires its emitters by id (0 at the start
-- fade; 1, 2, 7, 8, 9, 11 when the clamp closes; 3, 4, 5, 6, 10 when the two
-- forms stop alternating; 12 on the final white-out), each placed by
-- sub_0207C854 at (0, 8 * 172, 0) in fx32 units.
--
-- Pictures: `particle_<i>`, the SPA file's textures in file order. Data
-- (`gen4_evolution_ink`): `emitters`, Gen4Particle's decode of the same file,
-- which Gen4ParticleSystem.fromEmitters / .resource simulate.

local Gen4EvolutionArt = {}

Gen4EvolutionArt.PATH = "/demo/shinka/data/particle/shinka_demo_particle.narc"
Gen4EvolutionArt.MEMBER = 0

Gen4EvolutionArt.HGSS = { particles="/a/1/1/9", background="/a/1/1/5", bottom="/a/2/3/7", bank=197 }
local function file(rom, config)
  local bytes = rom:read(config and config.particles or Gen4EvolutionArt.PATH)
  if not bytes then return nil end
  local narc = require("src.import.NarcArchive").parse(bytes)
  return narc and narc:get(Gen4EvolutionArt.MEMBER)
end

function Gen4EvolutionArt.images(rom, config)
  local P = require("src.import.Gen4Particle")
  local data = file(rom, config)
  local list = data and P.textures(data)
  if not list then return nil, "shinka particle file missing" end
  local out = {}
  for i, texture in ipairs(list) do out[("particle_%d"):format(i - 1)] = P.rgba(texture) end
  -- BG3: egg_data.narc members 0 (tiles), 1 (tilemap) and 8 (two palettes to
  -- rows 0-1) -- the diploma naix order the decomp's names come from:
  -- sinnoh_document_NCGR, national_dex_document_NCGR, sinnoh_document_NSCR
  local G = require("src.import.Gen4Graphics")
  local egg = Gen4EvolutionArt.egg(rom, config)
  if egg then
    local sheet, map, pal = G.tiles(egg(0)), G.tilemap(egg(1)), G.palette(egg(8))
    if sheet and map and pal then out.background = G.compose(map, sheet, pal) end
  end
  if config and config.bottom then
    local bytes=rom:read(config.bottom)
    local arc=bytes and require("src.import.NarcArchive").parse(bytes)
    if arc then
      local pal=G.palette(arc:get(0));local extra=G.palette(arc:get(15))
      -- Member 15's PMCP already places its colours in BG palette slot 9.
      if pal and extra then for i=1,16 do pal[144+i]=extra[144+i] or extra[i]end end
      local tiles,map=G.tiles(arc:get(16)),G.tilemap(arc:get(17))
      if pal and tiles and map then
        out.bottom=G.compose(map,tiles,pal)
        -- BG palette colour zero is the screen's opaque backdrop, not a
        -- transparent OBJ texel. The other images stay layered/translucent.
        local backdrop=string.char(pal[1][1],pal[1][2],pal[1][3],255)
        out.bottom.rgba=out.bottom.rgba:gsub("....",function(pixel)
          return pixel:byte(4)==0 and backdrop or pixel
        end)
      end
      local buttons,buttonMap=G.tiles(arc:get(1)),G.tilemap(arc:get(10))
      if pal and buttons and buttonMap then out.moveButtons=G.compose(buttonMap,buttons,pal)end
    end
  end
  return out
end

Gen4EvolutionArt.EGG_PATH = "/demo/egg/data/egg_data.narc"

function Gen4EvolutionArt.egg(rom, config)
  local G = require("src.import.Gen4Graphics")
  local bytes = rom:read(config and config.background or Gen4EvolutionArt.EGG_PATH)
  local narc = bytes and require("src.import.NarcArchive").parse(bytes)
  if not narc then return nil end
  return function(i)
    local b = narc:get(i)
    if b and G.isCompressed(b) then b = G.decompress(b) end
    return b
  end
end

function Gen4EvolutionArt.data(rom, config)
  local data = file(rom, config)
  if not data then return nil end
  local emitters = require("src.import.Gen4Particle").emitters(data)
  local out = { emitters = emitters, count = emitters and #emitters or 0, bank=config and config.bank or 368 }
  -- each texture's repeat/flip bits (SPLTextureParam: format 0-3, s 4-7,
  -- t 8-11, repeat 12-13, flip 14-15): a flipped repeat mirrors alternate
  -- copies, which is how a quarter-circle texture tiled 2x2 draws a ring
  local head = require("src.import.Gen4Particle").header(data)
  if head then
    out.textures = {}
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
  -- the backdrop: main BG palette colour 0 (row 0 of member 8) shows outside
  -- window 0 while the scene letterboxes
  local egg = Gen4EvolutionArt.egg(rom, config)
  local pal = egg and require("src.import.Gen4Graphics").palette(egg(8))
  if pal and pal[1] then out.backdrop = { pal[1][1], pal[1][2], pal[1][3] } end
  return out
end

return Gen4EvolutionArt
