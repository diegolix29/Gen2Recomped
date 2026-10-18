-- src/import/Gen5StarterArt.lua -- BLACK AND WHITE'S GIFT BOX (the starter
-- choice), written as `gen5_starter_art`.
--
-- WHICH APP. Script command 0x153 <var> (ov10 0x0215CBF0, table slot 0x162 --
-- Gen5ScriptOps' offset 15) starts process 0x021BC8C4 of OVERLAY 223 with the
-- answer var in its work. Overlay 223 loads one archive of its own, 0xCD =
-- /a/2/0/5 ("psel", poke select), 40 members, the same in both games:
--
--    0-11  RLCN  256-colour palettes. 0 / 2 / 4 the three Pokemon's OBJ
--                (Snivy, Tepig, Oshawott; 1 / 3 / 5 their silhouettes),
--                11 the white hand; 6 the gift
--                box screen's grey, 7 the stage's white -- and 9 / 8 / 10
--                the stage tinted green / orange / blue for the one under the
--                hand (ov223 0x021BC70C: 09 08 0A 07, the starters' order,
--                then none)
--    12-14 RGCN  the three Pokemon (96 x 96 cells 21-23, anims 25-27)
--    15/16 RGCN  8bpp: 15 the box screen (screen 18), 16 the stage (19) and
--                its pedestal (20) -- ov223 0x021BAC14 / 0x021BAD88 load
--                (pal 6, char 15, screen 18) and (pal 7, char 16, screens
--                19 and 20)
--    17    RGCN  the hand (cell 24, anim 28)
--    29-32 psel_s01  the gift box opening on the table: model, BCA, BMA, BTA
--                (130 frames; ov223 0x021BC81C)
--    33    the s01 camera, baked: u32 130, u32 0x10101 (?), then 130 x six
--          floats -- a rotation (x, y, z degrees) and the eye (x, y, z)
--    34/35 psel_s02  the box open, its cushion: model, BCA (250 frames)
--    36    the s02 camera, the same shape (250 frames): it sweeps in, then
--          from the left ball (x -12.5) to the right (12.5)
--    37-39 psel_mb   a Poke Ball: model, BMA, BCA (160 frames: it opens)
--          (ov223 0x021BC884 loads 34, 35, 37, 38, 39)
--
-- THE BALLS stand at ov223 0x021BC7CC, three fx32 vectors: (-12.5, 29, 3.6),
-- (0, 29, -7), (12.5, 29, 3.6) -- Snivy, Tepig, Oshawott, left to right.
-- THE TOUCH TABLE (ov223 0x021BC7F0, 14 bytes each): the balls' points on the
-- touch screen (53, 73), (128, 68), (202, 73), then each one's label point
-- (90, 83), (128, 94), (165, 83).
--
-- THE TEXT is the bedroom's own bank 430 (see src/ui/Gen5StarterSelect).

local A = {}

A.PATH = "/a/2/0/5"
A.SCENE1 = { model = 29, anims = { 30, 31, 32 }, camera = 33 }
A.SCENE2 = { model = 34, anims = { 35 }, camera = 36 }
A.BALL = { model = 37, anims = { 38, 39 } }
A.BALLS = { { -12.5, 29, 3.6 }, { 0, 29, -7.0 }, { 12.5, 29, 3.6 } }
A.TOUCH = { { 53, 73 }, { 128, 68 }, { 202, 73 } }
A.LABEL = { { 90, 83 }, { 128, 94 }, { 165, 83 } }
-- the stage's palette for each starter, then for none (ov223 0x021BC70C)
A.STAGE_PALETTES = { 9, 8, 10, 7 }
A.BOX_SCREEN = { palette = 6, char = 15, screen = 18 }
A.STAGE = { char = 16, screen = 19, pedestal = 20 }
-- each Pokemon's palette is the even one; the odd one after it is the same
-- picture darkened to a silhouette
A.MONS = { { cell = 21, char = 12, palette = 0 }, { cell = 22, char = 13, palette = 2 },
           { cell = 23, char = 14, palette = 4 } }
A.HAND = { cell = 24, char = 17, palette = 11 }

local function f32(s, at)
  local a, b, c, d = s:byte(at + 1, at + 4)
  if not d then return 0 end
  local bits = a + b * 256 + c * 65536 + d * 16777216
  local sign = bits >= 2 ^ 31 and -1 or 1
  local e = math.floor(bits / 2 ^ 23) % 256
  local m = bits % 2 ^ 23
  if e == 0 then return sign * m * 2 ^ -149 end
  return sign * (1 + m / 2 ^ 23) * 2 ^ (e - 127)
end

-- members 33 / 36: { frames, data = { rx, ry, rz, x, y, z, ... } }
function A.camera(bytes)
  if type(bytes) ~= "string" or #bytes < 8 then return nil end
  local n = bytes:byte(1) + bytes:byte(2) * 256
  if #bytes < 8 + n * 24 then return nil end
  local data = {}
  for i = 0, n * 6 - 1 do data[#data + 1] = f32(bytes, 8 + i * 4) end
  return { frames = n, data = data }
end

function A.build(x)
  local Narc = require("src.import.NarcArchive")
  local G = require("src.import.Gen4Graphics")
  local Lz = require("src.import.Gen5Lz")
  local Cells = require("src.import.Gen4Cells")
  local Models = require("src.import.Gen4Models")
  local Anim = require("src.import.Gen4Anim")
  local Pack = require("src.import.Gen4ModelPack")
  local Nsbmd = require("src.import.Gen4Nsbmd")
  local raw = x.rom:read(A.PATH)
  local arc = raw and Narc.parse(raw)
  if not arc then return nil end
  local function member(i)
    local b = arc:get(i)
    if b and Lz.isCompressed(b) then b = Lz.decompress(b)
    elseif b and G.isCompressed(b) then b = G.decompress(b) end
    return b
  end
  local out = {
    _source = "ROM:" .. A.PATH .. " (overlay 223, script command 0x153)",
    balls = A.BALLS, touch = A.TOUCH, label = A.LABEL, stagePalettes = A.STAGE_PALETTES,
    images = {},
  }
  local function save(key, image, extra)
    local entry = image and x:saveImage("bw_starter/" .. key, image, extra)
    if entry then out.images[key] = entry end
    return entry
  end

  -- the 3D parts, packed with their textures and animations
  local written = {}
  local function textureImage(prefix, tex, bytes, name, paletteName)
    local key = prefix .. name .. "/" .. tostring(paletteName)
    if written[key] ~= nil then return written[key] end
    local ti, pi
    for k, t in ipairs(tex.textures) do if t.name == name then ti = k end end
    for k, p in ipairs(tex.palettes or {}) do if p.name == paletteName then pi = k end end
    if not ti then written[key] = false return false end
    local image = Models.decode(tex, bytes, ti, pi or 1)
    local saved = image and x:saveImage(("bw_starter/%s%s_%d"):format(prefix, name:gsub("[^%w_%-]", "_"), pi or 1), image)
    written[key] = saved and (type(saved) == "table" and saved.path or saved) or false
    return written[key]
  end
  local function part(spec)
    local bytes = member(spec.model)
    local parsed = bytes and Nsbmd.parse(bytes)
    local model = parsed and parsed.models and parsed.models[1]
    if not model then return nil end
    local packed = Pack.pack(model)
    local texAt = bytes:find("TEX0", 1, true)
    local tex = texAt and Models.parse(bytes, texAt - 1)
    local prefix = ("m%d_"):format(spec.model)
    for _, shape in ipairs(packed.shapes) do
      if shape.texture and tex then shape.image = textureImage(prefix, tex, bytes, shape.texture, shape.palette) or nil end
    end
    local p = { model = packed, records = {}, frames = 0, name = model.name }
    for _, m in ipairs(spec.anims or {}) do
      local data = member(m)
      local parsed2 = data and Anim.parse(data)
      local animation = parsed2 and parsed2.animations and parsed2.animations[1]
      if animation then
        local frames = tonumber(animation.frames) or 0
        if frames > p.frames then p.frames = frames end
        local kind = parsed2.kind
        if kind == "BCA0" then
          local motion = { frames = frames, tracks = {} }
          for _, joint in ipairs(Anim.jointMatrices(data, animation) or {}) do
            motion.tracks[joint.index] = Anim.packTrack(joint.track)
          end
          p.motion = motion
        elseif kind == "BTA0" then
          p.records[#p.records + 1] = { kind = "BTA0", frames = frames, srt = Anim.textureSrt(data, animation) }
        elseif kind == "BMA0" then
          p.records[#p.records + 1] = { kind = "BMA0", frames = frames, colour = Anim.materialColour(data, animation) }
        end
      end
    end
    if spec.camera then p.camera = A.camera(member(spec.camera)) end
    return p
  end
  for key, spec in pairs({ scene1 = A.SCENE1, scene2 = A.SCENE2, ball = A.BALL }) do
    local ok, p = pcall(part, spec)
    if ok then out[key] = p else out[key .. "Error"] = tostring(p) end
  end

  -- the backgrounds: the box screen, and the stage in each of its tints
  local okB, errB = pcall(function()
    local b = A.BOX_SCREEN
    save("box_screen", assert(G.compose(assert(G.tilemap(member(b.screen))), assert(G.tiles(member(b.char))),
                                        assert(G.palette(member(b.palette))))))
    local sheet = assert(G.tiles(member(A.STAGE.char)))
    local stage, pedestal = assert(G.tilemap(member(A.STAGE.screen))), assert(G.tilemap(member(A.STAGE.pedestal)))
    for i, p in ipairs(A.STAGE_PALETTES) do
      local pal = assert(G.palette(member(p)))
      save(("stage_%d"):format(i - 1), assert(G.compose(stage, sheet, pal)))
      save(("pedestal_%d"):format(i - 1), assert(G.compose(pedestal, sheet, pal)))
    end
  end)
  if not okB then out.backgroundError = tostring(errB) end

  -- the three Pokemon and the hand (OBJ cells)
  local function cell(key, spec)
    local bank = Cells.parse(member(spec.cell), G)
    local sheet, pal = G.tiles(member(spec.char)), G.palette(member(spec.palette))
    local c = bank and bank.cells and bank.cells[1]
    local pic = c and sheet and pal and Cells.assemble(c, sheet, pal, bank, G)
    if pic then
      local ox, oy = Cells.extent(c)
      save(key, pic, { originX = ox, originY = oy })
    end
  end
  for i, spec in ipairs(A.MONS) do pcall(cell, ("mon_%d"):format(i - 1), spec) end
  pcall(cell, "hand", A.HAND)
  return out
end

return A
