-- BLACK AND WHITE'S POKEMON BATTLE PICTURES (/a/0/0/4, the pokegra archive).
--
-- Twenty members a species, from species 0 (the "?" picture) at member 0:
--
--   +0  front, 96 x 96 (LZ11 RGCN, 144 tiles)     +1  female front (or empty)
--   +2  front animation parts (128 x 256)          +3  female parts (or empty)
--   +4  RECN cells   +5 RNAN   +6 RCMN   +7 RAMN   +8 the animation script
--   +9  back, 96 x 96                              +10 female back (or empty)
--   +11 back parts   +12 female back parts         +13..+17 the back's cells
--   +18 normal palette (RLCN)                      +19 shiny palette
--
-- The 96 x 96 still is 1D-mapped for four OAM blocks -- 64x64 at (0, 0),
-- 32x64 at (64, 0), 64x32 at (0, 64), 32x32 at (64, 64) -- 64 + 32 + 32 + 16
-- = 144 tiles, which is what every member decodes to. Read row-major instead
-- the picture comes out as the four blocks laid in a strip.
--
-- Written under the same keys Platinum's species stage stamps on a species
-- row (spriteFront, spriteBack, spriteShiny, spriteShinyBack, plus the female
-- pair), so the battle screen and every other reader of Sprites.path draw a
-- Unova Pokemon without knowing which cartridge it came from.

local B = {}

B.PATH = "/a/0/0/4"
B.STRIDE = 20
B.SPECIES = 649
B.SIZE = 96
B.BLOCKS = { { 0, 0, 8, 8 }, { 8, 0, 4, 8 }, { 0, 8, 8, 4 }, { 8, 8, 4, 4 } }

local function cellsFor()
  local grid, t = {}, 0
  for _, bl in ipairs(B.BLOCKS) do
    for ty = 0, bl[4] - 1 do
      for tx = 0, bl[3] - 1 do
        grid[(bl[2] + ty) * 12 + bl[1] + tx + 1] = { tile = t, palette = 0 }
        t = t + 1
      end
    end
  end
  return { width = B.SIZE, height = B.SIZE, cells = grid }
end

-- build(x) -> report; stamps x._pokemon and writes gen4_species_sprites
function B.build(x)
  local G = require("src.import.Gen4Graphics")
  local Lz = require("src.import.Gen5Lz")
  local raw = x.rom:read(B.PATH)
  local arc = raw and require("src.import.NarcArchive").parse(raw)
  if not arc then return { error = "no " .. B.PATH } end
  local function member(i)
    local b = arc:get(i)
    if not b or #b == 0 then return nil end
    if Lz.isCompressed(b) then b = Lz.decompress(b) end
    return b
  end
  local map = cellsFor()
  local mons = x._pokemon or {}
  local index = { species = {}, counts = { images = 0, missing = 0, female = 0, animations=0, animationErrors=0 } }
  local Anim=require("src.import.Gen5MonAnim")
  local function slug(id)
    local def = mons[id]
    local name = def and def.name or ("species_%03d"):format(id)
    return ("%03d_%s"):format(id, tostring(name):lower():gsub("[^%w]+", "_"))
  end
  local function save(rel, sheetBytes, palette)
    local sheet = sheetBytes and G.tiles(sheetBytes)
    if not (sheet and palette) then return nil end
    local image = G.compose(map, sheet, palette)
    local entry = image and x:saveImage("battle/" .. rel, image)
    if entry then index.counts.images = index.counts.images + 1 end
    -- the lowest row with a pixel in it: where the Pokemon's feet are, which
    -- is the point the battle stands on its platform in the 3D field
    local feet
    if image then
      for y = B.SIZE - 1, 0, -1 do
        local row = image.rgba:sub(y * B.SIZE * 4 + 1, (y + 1) * B.SIZE * 4)
        for px = 4, #row, 4 do
          if row:byte(px) > 0 then feet = y + 1 break end
        end
        if feet then break end
      end
    end
    return entry and entry.path, feet
  end
  for id = 1, B.SPECIES do
    local base = id * B.STRIDE
    local normal = G.palette(member(base + 18))
    local shiny = G.palette(member(base + 19))
    local name = slug(id)
    local rec = { feet = {} }
    rec.front, rec.feet.front = save("front/" .. name, member(base + 0), normal)
    rec.back, rec.feet.back = save("back/" .. name, member(base + 9), normal)
    local more = {
      shiny_front = save("shiny_front/" .. name, member(base + 0), shiny),
      shiny_back = save("shiny_back/" .. name, member(base + 9), shiny),
    }
    for k, v in pairs(more) do rec[k] = v end
    local femaleFront = member(base + 1)
    if femaleFront then
      rec.female_front = save("female_front/" .. name, femaleFront, normal)
      rec.female_back = save("female_back/" .. name, member(base + 10), normal)
      rec.female_shiny_front = save("female_shiny_front/" .. name, femaleFront, shiny)
      rec.female_shiny_back = save("female_shiny_back/" .. name, member(base + 10), shiny)
      index.counts.female = index.counts.female + 1
    end
    if not rec.front then index.counts.missing = index.counts.missing + 1 end
    index.species[id] = rec
    local def = mons[id]
    if def then
      def.spriteFront, def.spriteBack = rec.front, rec.back
      def.spriteShiny, def.spriteShinyBack = rec.shiny_front, rec.shiny_back
      def.spriteFemaleFront, def.spriteFemaleBack = rec.female_front, rec.female_back
      def.battleSpriteSize = B.SIZE
      local front,frontError=Anim.load(arc,id,"front")
      local back,backError=Anim.load(arc,id,"back")
      if front and back then
        local path=x:saveBinary(("battle/mcss/%03d.bin"):format(id),Anim.pack(arc,id))
        def.gen5Animation={path=path,species=id}
        rec.animation=def.gen5Animation
        index.counts.animations=index.counts.animations+2
      else
        index.counts.animationErrors=index.counts.animationErrors+1
        rec.animationError=frontError or backError
      end
    end
    if x.tick then x:tick("battle_sprites", id, B.SPECIES) end
  end
  index.size = B.SIZE
  index.source = ("ROM:%s (%d a species; front +0, back +9, palettes +18 / +19)"):format(B.PATH, B.STRIDE)
  return index
end

return B
