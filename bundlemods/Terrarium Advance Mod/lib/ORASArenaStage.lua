-- ORAS ARENA: a fight staged in an Omega Ruby / Alpha Sapphire battle stage
-- (baked by lib/ORASArenas.lua) instead of on the map or the B-rung discs.
--
-- The arena is the same synthetic WIDE arena the discs use (StadiumStage), so
-- the pins, HUDs, move effects and depth of field all work unchanged; it just
-- carries `_oras` (the stage) and its own camera rig, and BattleScene asks this
-- file to draw the ground instead of the discs. On whenever the ORAS ARENA row
-- is, whatever the 3D-BTL row says (that row still picks what stands there).
--
-- Placement: ORAS cm to world pixels at K (the 430 cm between the two
-- Pokemon = the arena's 48 px), turned half round, because ORAS shoots from
-- -Z with the player's side at -Z, and this mode's camera sits at +Z behind
-- the player. The two bases sit on the two cells, tops flush with the ground.
--
-- Drawn with a shader of its own into the scene canvas, inside Voxel3D's pass
-- (its vp, its depth buffer): tex0 x vertex colour x the material's constant,
-- alpha tested; opaque and cut-out meshes write depth, blended ones do not and
-- go after them. The Voxel3D shader and depth mode are restored afterwards.

local V = ...

local Mat4 = V.require("Mat4")

local S = {}

S.ORAS_GAP = 430                 -- cm between the two Pokemon in ORAS
S.CELL_GAP = 48                  -- world px between the arena's two cells
S.K = S.CELL_GAP / S.ORAS_GAP

-- The camera. Inside every stage's ring of trees / buildings (~9-11 m out),
-- behind and right of the player's Pokemon like ORAS's own singles shot.
-- World px from the arena's middle; see BattleCam.RIGS.
S.RIG = {
  side = 30, back = 74, height = 24,
  lookX = -1.5, lookY = 4.5, frameH = 44,
}
pcall(function()
  local BattleCam = V.require("BattleCam")
  if BattleCam.RIGS then BattleCam.RIGS.orasArena = S.RIG end
end)

local function Arenas() return V.require("ORASArenas") end

-- ------------------------------------------------------------------ arena

-- the arena for this fight, or nil (row OFF, nothing built)
function S.arena(state, battle)
  local okA, A = pcall(Arenas)
  if not (okA and A and A.active()) then return nil end
  local map = state and state.map
  local env = A.pick(map, battle)
  if not env then return nil end
  local stage = A.index().stages[env]
  if not stage then return nil end
  local BattleArena = V.require("BattleArena")
  local StadiumStage = V.require("StadiumStage")
  local arena = BattleArena.at(StadiumStage.ORIGIN[1], StadiumStage.ORIGIN[2], "wide")
  if not arena then return nil end
  arena.map = map
  arena.discs = true          -- no map terrain; BattleScene asks us for the ground
  arena._oras = env
  arena._orasStage = stage
  arena.cam = "orasArena"
  return arena
end

-- the row is on and something is built (OverworldBattle: stage every fight)
function S.wanted()
  local okA, A = pcall(Arenas)
  return okA and A and A.active() or false
end

-- ------------------------------------------------------------- resources

local models, images, meshes = {}, {}, {}

function S.invalidate()
  for _, list in pairs(meshes) do
    for _, m in ipairs(list or {}) do if m.mesh and m.mesh.release then pcall(m.mesh.release, m.mesh) end end
  end
  for _, img in pairs(images) do if img and img.release then pcall(img.release, img) end end
  models, images, meshes = {}, {}, {}
end

local function model(name)
  local m = models[name]
  if m == nil then
    m = Arenas().readLua(("%s/models/%s.lua"):format(Arenas().ROOT, name)) or false
    models[name] = m
  end
  return m or nil
end

local WRAP = { [0] = "clamp", [1] = "clampzero", [2] = "repeat", [3] = "mirroredrepeat" }

local function image(key, wu, wv)
  local id = ("%s|%s|%s"):format(key, tostring(wu), tostring(wv))
  local img = images[id]
  if img ~= nil then return img or nil end
  img = false
  local bytes = Arenas().readFile(Arenas().ROOT .. "/tex/" .. key .. ".png")
  if bytes and love and love.graphics then
    local okI, data = pcall(function()
      return love.image.newImageData(love.filesystem.newFileData(bytes, key .. ".png"))
    end)
    if okI and data then
      local okG, gi = pcall(love.graphics.newImage, data)
      if okG and gi then
        gi:setFilter("linear", "linear")
        pcall(gi.setWrap, gi, WRAP[wu] or "repeat", WRAP[wv] or "repeat")
        img = gi
      end
    end
  end
  images[id] = img
  return img or nil
end

local FORMAT = {
  { "VertexPosition", "float", 3 },
  { "VertexTexCoord", "float", 2 },
  { "VertexColor", "float", 4 },
}

-- one stage piece as LOVE meshes: { mesh, blend, cutout, kc, pass } in draw order
local function piece(name)
  local list = meshes[name]
  if list ~= nil then return list or nil end
  list = false
  local m = model(name)
  if m and love and love.graphics then
    list = {}
    for _, ms in ipairs(m.meshes) do
      local verts = {}
      for i = 0, #ms.v / 9 - 1 do
        local o = i * 9
        verts[#verts + 1] = { ms.v[o + 1], ms.v[o + 2], ms.v[o + 3], ms.v[o + 4], ms.v[o + 5],
                              ms.v[o + 6], ms.v[o + 7], ms.v[o + 8], ms.v[o + 9] }
      end
      local tex = ms.tex and image(ms.tex, ms.wrapU, ms.wrapV)
      if #verts >= 3 and tex then
        local ok, mesh = pcall(love.graphics.newMesh, FORMAT, verts, "triangles", "static")
        if ok and mesh then
          pcall(mesh.setVertexMap, mesh, ms.idx)
          mesh:setTexture(tex)
          local blend = ms.blend or "alpha"
          list[#list + 1] = {
            mesh = mesh, blend = blend, cutout = ms.cutout or 0, kc = ms.kc or { 1, 1, 1, 1 },
            -- opaque first, then blended ones, additive last
            pass = blend == "opaque" and 1 or (blend == "add" and 3 or 2),
          }
        end
      end
    end
  end
  meshes[name] = list
  return list or nil
end

-- --------------------------------------------------------------- shader

local SHADER = [[
uniform mat4 vp;
uniform mat4 model;
uniform vec4 kc;
uniform float cutout;
#ifdef VERTEX
vec4 position(mat4 t, vec4 p) { return vp * model * p; }
#endif
#ifdef PIXEL
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
  vec4 c = Texel(tex, uv) * color * kc;
  if (c.a <= cutout + 0.004) discard;
  return c;
}
#endif
]]

local shader = nil
local function getShader()
  if shader == nil then
    local ok, sh = pcall(love.graphics.newShader, SHADER)
    shader = ok and sh or false
    if not ok then
      local l = V.mod and V.mod.log
      if l and l.warn then pcall(l.warn, l, "ORAS ARENA: shader failed: %s", tostring(sh)) end
    end
  end
  return shader or nil
end

-- ------------------------------------------------------------------- draw

-- ORAS cm -> world px: half a turn about Y, then K, about the arena middle
local function stageMatrix(arena, groundY, ox, oz, lift)
  local K = S.K
  return Mat4.mul(Mat4.translate(arena.mid[1] + ox, groundY + (lift or 0), arena.mid[2] + oz),
                  Mat4.scale(-K, K, -K))
end

local function drawList(sh, list, matrix, pass)
  local g = love.graphics
  pcall(sh.send, sh, "model", "row", matrix)
  for _, it in ipairs(list) do
    if it.pass == pass then
      pcall(sh.send, sh, "kc", it.kc)
      pcall(sh.send, sh, "cutout", it.cutout)
      if it.blend == "add" then g.setBlendMode("add", "alphamultiply")
      else g.setBlendMode("alpha", "alphamultiply") end
      g.draw(it.mesh)
    end
  end
end

-- The stage, its backdrop and the two bases, into the scene being drawn.
-- Returns true when it drew (BattleScene then skips the discs).
function S.draw(arena, groundY)
  local stage = arena and arena._orasStage
  if not stage then return false end
  local Voxel3D = V.require("Voxel3D")
  local vp = Voxel3D.vp
  local sh = getShader()
  if not (vp and sh) then return false end
  local g = love.graphics
  groundY = groundY or 0
  local G, F = piece(stage.g), stage.f and piece(stage.f)
  local O = stage.o and piece(stage.o)
  if not G then return false end

  local prevShader = g.getShader()
  local ok, err = pcall(function()
    g.setShader(sh)
    sh:send("vp", "row", vp)
    g.setColor(1, 1, 1, 1)
    local mStage = stageMatrix(arena, groundY, 0, 0)
    local bases = {}
    if O then
      local top = (model(stage.o) or {}).top or 0
      for _, side in ipairs({ "player", "enemy" }) do
        local c = arena[side]
        if c then
          bases[#bases + 1] = stageMatrix(arena, groundY, c[1] - arena.mid[1], c[2] - arena.mid[2], -top * S.K)
        end
      end
    end
    for pass = 1, 3 do
      g.setDepthMode("lequal", pass == 1)
      if F then drawList(sh, F, mStage, pass) end
      drawList(sh, G, mStage, pass)
      for _, mb in ipairs(bases) do drawList(sh, O, mb, pass) end
    end
  end)
  g.setBlendMode("alpha", "alphamultiply")
  g.setDepthMode("lequal", true)
  g.setColor(1, 1, 1, 1)
  g.setShader(prevShader)
  if not ok and not S.warned then
    S.warned = true
    local l = V.mod and V.mod.log
    if l and l.warn then pcall(l.warn, l, "ORAS ARENA: draw failed: %s", tostring(err)) end
  end
  return ok
end

return S
