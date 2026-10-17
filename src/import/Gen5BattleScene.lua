-- BLACK AND WHITE'S BATTLE SCENE: the backdrops and the platforms are 3D.
--
-- /a/0/1/1 members 0-87 (bw_ui_map.md; the names are the models' own):
--   0-33   batt_stageNN[a-d]  the platforms, one shape each
--   34-83  batt_bgNN[a-d]     the backdrops -- a sky cylinder, the field and
--                             its brush -- each followed by its BCA0 (the
--                             clouds' and the water's movement)
--   84-87  batt_fd_vs3 / batt_st_vs3, the link-battle stage
-- a-d are the seasons (spring .. winter) of the outdoor ones. Every texture
-- sits in the model file's own TEX0, beside MDL0.
--
-- Packed with Gen4ModelPack the way the field's models are, each texture
-- written out as a PNG and named on its shape, so src/render/Gen4Model draws
-- them unchanged.

local S = {}

S.PATH = "/a/0/1/1"
S.LAST_MODEL = 87

function S.build(x)
  local Narc = require("src.import.NarcArchive")
  local Nsbmd = require("src.import.Gen4Nsbmd")
  local Pack = require("src.import.Gen4ModelPack")
  local Models = require("src.import.Gen4Models")
  local raw = x.rom:read(S.PATH)
  local arc = raw and Narc.parse(raw)
  if not arc then return nil end
  local out = { models = {}, order = {}, source = "ROM:" .. S.PATH .. " 0-87 (BMD0 with TEX0)" }
  for member = 0, S.LAST_MODEL do
    local bytes = arc:get(member)
    if bytes and bytes:sub(1, 4) == "BMD0" then
      local parsed = Nsbmd.parse(bytes)
      local model = parsed and parsed.models and parsed.models[1]
      local packed = model and Pack.pack(model)
      if packed then
        local name = model.name or ("model_%02d"):format(member)
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
              local saved = image and x:saveImage(("battle5/scene/%s_%s"):format(name, tname:gsub("[^%w_%-]", "_")),
                                                  image, { texture = tname })
              written[tname] = saved and saved.path or false
            end
            shape.image = written[tname] or nil
          end
        end
        packed.member = member
        packed.name = name
        out.models[name] = packed
        out.order[#out.order + 1] = name
      end
    end
  end
  return out
end

return S
