-- BLACK AND WHITE'S CUT-INS, DRAWN (src/import/Gen5EncounterCutIns.lua has the
-- scenes). A frame of a scene is every model's shapes at that frame, each
-- shape:
--
--   * hidden when its node is switched off by the BVA (frame-major bits);
--   * at its material's alpha (the BMA's 0..31, else the material's own) and
--     diffuse colour (the BMA's, else the material's when its vertex colour is
--     its diffuse);
--   * its texture moved by the BTA's translation, in whole textures;
--   * wearing the face / name pictures the trainer brings (`pictures`).
--
-- Drawn farthest first through the scene view (+-64 x +-48 units at z = 0).

local C = {}

local floor, max, min = math.floor, math.max, math.min

local meshFormat = { { "VertexPosition", "float", 2 }, { "VertexTexCoord", "float", 2 },
                     { "VertexColor", "byte", 4 } }

local function at(list, f)
  if not list then return nil end
  if #list == 1 then return list[1] end
  return list[max(1, min(#list, f))]
end

local function rgb555(v)
  return (v % 32) / 31, (floor(v / 32) % 32) / 31, (floor(v / 1024) % 32) / 31
end

local function visible(vis, node, frame)
  if not (vis and node) then return true end
  if node >= vis.targets then return true end
  local fr = min(frame - 1, vis.frames - 1)
  local index = fr * vis.targets + node
  local byte = tonumber(vis.bits:sub(floor(index / 8) * 2 + 1, floor(index / 8) * 2 + 2), 16)
  if not byte then return true end
  return floor(byte / 2 ^ (index % 8)) % 2 == 1
end

local function clipNear(poly, near)
  local out = {}
  for i = 1, #poly do
    local a, b = poly[i], poly[i % #poly + 1]
    local ina, inb = a[3] >= near, b[3] >= near
    if ina then out[#out + 1] = a end
    if ina ~= inb then
      local t = (near - a[3]) / (b[3] - a[3])
      out[#out + 1] = { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, near,
                        a[4] + (b[4] - a[4]) * t, a[5] + (b[5] - a[5]) * t }
    end
  end
  return out
end

-- draw(scene, frame, imageFor, ox, oy, k, view)
-- imageFor(model, shape) -> an Image (or nil: drawn in its colour alone)
function C.draw(scene, frame, imageFor, ox, oy, k, view)
  local E = require("src.import.Gen5EncounterEffects")
  view = view or E.SCENE_VIEW
  local ty = 1398 / 3850
  local tx = ty * view.aspect
  local eye = view.halfY / ty
  local items = {}
  for mi, model in ipairs(scene.models or {}) do
    E.unpack(model)
    -- a model held back (the scene's +96 / +98) stands on its first frame
    local delay = scene.modelDelays and scene.modelDelays[mi] or 0
    local mframe = max(1, frame - delay)
    local pos = model.pos[max(1, min(#model.pos, mframe))]
    for _, sh in ipairs(model.shapes) do
      local frame = mframe
      if visible(model.visibility, sh.node, frame) then
        local ma = model.materialAnim and model.materialAnim[sh.material]
        local alpha = (ma and at(ma.alpha, frame)) or sh.alpha or 31
        if alpha > 0 then
          local r, g, b = 1, 1, 1
          local dif = (ma and at(ma.diffuse, frame)) or sh.diffuse
          if dif then r, g, b = rgb555(dif) end
          local ta = model.textureAnim and model.textureAnim[sh.material]
          local du, dv = (ta and at(ta.translateS, frame)) or 0, (ta and at(ta.translateT, frame)) or 0
          local su, sv = (ta and at(ta.scaleS, frame)) or 1, (ta and at(ta.scaleT, frame)) or 1
          local polys, depth = {}, 0
          for t = sh.first, sh.first + sh.count - 1 do
            local poly = {}
            for c = 0, 2 do
              local vi = model.tris[t * 3 + c + 1] - 1
              local p = vi * 3
              poly[c + 1] = { pos[p + 1], pos[p + 2], eye - pos[p + 3],
                              model.uv[vi * 2 + 1] * su - du, model.uv[vi * 2 + 2] * sv + dv }
              depth = depth + poly[c + 1][3]
            end
            polys[#polys + 1] = poly
          end
          items[#items + 1] = { model = model, shape = sh, polys = polys,
                                depth = depth / max(1, sh.count * 3),
                                colour = { r * 255, g * 255, b * 255, alpha / 31 * 255 } }
        end
      end
    end
  end
  table.sort(items, function(a, b) return a.depth > b.depth end)
  for _, it in ipairs(items) do
    local verts = {}
    local col = it.colour
    for _, poly in ipairs(it.polys) do
      if poly[1][3] < 1 or poly[2][3] < 1 or poly[3][3] < 1 then poly = clipNear(poly, 1) end
      local scr = {}
      for j, q in ipairs(poly) do
        scr[j] = { ox + (128 + 128 * q[1] / (q[3] * tx)) * k, oy + (96 - 96 * q[2] / (q[3] * ty)) * k,
                   q[4], q[5], col[1], col[2], col[3], col[4] }
      end
      for j = 2, #scr - 1 do
        verts[#verts + 1] = scr[1]; verts[#verts + 1] = scr[j]; verts[#verts + 1] = scr[j + 1]
      end
    end
    if #verts > 0 then
      local mesh = love.graphics.newMesh(meshFormat, verts, "triangles", "stream")
      local img = imageFor and imageFor(it.model, it.shape)
      if img then mesh:setTexture(img) end
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(mesh)
      mesh:release()
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- THE PARTICLES (src/render/Gen5Particles.lua): emitter i starts once the
-- scene has run its delay, at (0, 0, z) in the scene's units, and steps once a
-- tick from then.
function C.particlesNew(scene, seed)
  local sp = scene and scene.particles
  if not sp then return nil end
  local P = require("src.render.Gen5Particles")
  -- the ROM starts emitter 1 only when the file holds two (0x021C2400)
  local count = math.min(2, #(sp.emitters or {}))
  return { sp = sp, R = P.newRandom(seed or 0x1234), emitters = {}, count = count }
end

function C.particlesStep(state, frame)
  if not state then return end
  local P = require("src.render.Gen5Particles")
  for i = 1, state.count do
    if not state.emitters[i] and frame >= (state.sp.delays[i] or 0) then
      state.emitters[i] = P.new(state.sp.emitters[i], { 0, 0, state.sp.z or 64 }, state.R)
    end
  end
  for i = 1, state.count do
    local e = state.emitters[i]
    if e and not e:done() then e:step() end
  end
end

function C.particlesDraw(state, imageFor, ox, oy, k, view)
  if not state then return end
  local E = require("src.import.Gen5EncounterEffects")
  view = view or E.SCENE_VIEW
  local ty = 1398 / 3850
  local tx = ty * view.aspect
  local eye = view.halfY / ty
  local function project(x, y, z)
    local d = eye - z
    if d < 1 then return nil end
    -- one unit at that depth, in window pixels
    return ox + (128 + 128 * x / (d * tx)) * k, oy + (96 - 96 * y / (d * ty)) * k, 96 / (d * ty) * k
  end
  local images = setmetatable({}, { __index = function(_, key) return imageFor(key) end })
  for i = 1, state.count do
    local e = state.emitters[i]
    if e then e:draw(images, project) end
  end
end

-- a name, as 0x021C2F84 writes it into its 128 x 16 texture: at x = 60 -
-- width (so a short name sits right of the slot's middle), white
function C.nameCanvas(text)
  local Font = require("src.render.Font")
  local c = love.graphics.newCanvas(128, 16)
  c:setFilter("nearest", "nearest")
  love.graphics.push("all")
  love.graphics.setCanvas(c)
  love.graphics.origin()
  love.graphics.clear(0, 0, 0, 0)
  local ok, w = pcall(Font.width, text)
  w = ok and tonumber(w) or (#text * 8)
  local x = max(0, 60 - w)
  love.graphics.setColor(1, 1, 1, 1)
  pcall(Font.draw, text, x, 0)
  love.graphics.pop()
  return c
end

return C
