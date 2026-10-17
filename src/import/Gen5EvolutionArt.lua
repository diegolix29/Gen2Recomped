-- BLACK AND WHITE'S EVOLUTION SCENE (overlay 195, shinka_demo*.c; the map is
-- scratch_claude/evolution_map.md): /a/1/8/2, the same in both games.
--
--   10  SPA "12_1": 9 emitters, 5 textures -- read by Gen4Particle unchanged
--       (the header arithmetic and version are Platinum's), fired on the
--       scene's frame table _02208ED0: 0-4 at 0, 5-6 at 500, 7 at 755, 8 at 783
--    8  BMD0 demo_sinka01: the cylinder of white light streaks round the
--       Pokemon (its own TEX0); 9 is the streaks' texture scroll
--  3-5  the letterbox: black bars 24 px deep top and bottom of main BG2
--
-- Written as `gen5_evolution` (emitters, texture bits, the model packed the
-- way the battle field's are) with the particle and model textures as PNGs.

local E = {}

E.PATH = "/a/1/8/2"
E.PARTICLES = 10
E.MODEL = 8
E.SCHEDULE = { { 0, { 0, 1, 2, 3, 4 } }, { 500, { 5, 6 } }, { 755, { 7 } }, { 783, { 8 } } }

function E.build(x)
  local Narc = require("src.import.NarcArchive")
  local raw = x.rom:read(E.PATH)
  local arc = raw and Narc.parse(raw)
  if not arc then return nil end
  local P = require("src.import.Gen4Particle")
  local out = { images = {}, schedule = E.SCHEDULE, letterbox = 24,
                source = "ROM:/a/1/8/2 (10 particles, 8 cylinder model)" }
  local spa = arc:get(E.PARTICLES)
  if spa then
    out.emitters = P.emitters(spa)
    for i, texture in ipairs(P.textures(spa) or {}) do
      local entry = x:saveImage(("evolution5/particle_%d"):format(i - 1), P.rgba(texture))
      if entry then out.images[("particle_%d"):format(i - 1)] = entry end
    end
    -- each texture's repeat / flip bits, as Gen4EvolutionArt reads them
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
  -- the cylinder
  local bytes = arc:get(E.MODEL)
  if bytes and bytes:sub(1, 4) == "BMD0" then
    local Nsbmd = require("src.import.Gen4Nsbmd")
    local Pack = require("src.import.Gen4ModelPack")
    local Models = require("src.import.Gen4Models")
    local parsed = Nsbmd.parse(bytes)
    local model = parsed and parsed.models and parsed.models[1]
    local packed = model and Pack.pack(model)
    if packed then
      local at = bytes:find("TEX0", 1, true)
      local tex = at and Models.parse(bytes, at - 1)
      local written = {}
      for _, shape in ipairs(packed.shapes) do
        local tname = shape.texture
        if tname and tex then
          if written[tname] == nil then
            written[tname] = false
            local index, palette
            for k, t in ipairs(tex.textures) do if t.name == tname then index = k end end
            for k, pl in ipairs(tex.palettes or {}) do if pl.name == shape.palette then palette = k end end
            local image = index and Models.decode(tex, bytes, index, palette or 1)
            local saved = image and x:saveImage("evolution5/" .. tname:gsub("[^%w_%-]", "_"), image)
            written[tname] = saved and saved.path or false
          end
          shape.image = written[tname] or nil
        end
      end
      out.model = packed
    end
  end
  return out
end

return E
