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
  arena.clampEye = S.clampEye
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

-- ------------------------------------------------------------ clearance
--
-- How far out from the arena's middle the stage is open, so the battle
-- camera never sits inside a tree or a wall when the player orbits it.
-- Per stage: for each bearing (BINS) and each height band (BAND cm), the
-- nearest stage geometry (vertices plus points sampled over each triangle,
-- so a big wall quad counts between its corners). ORAS cm, stage frame.

S.CLEAR_BINS = 72
S.CLEAR_BAND = 100        -- cm per height band
S.CLEAR_BANDS = 40        -- 0 .. 40 m
S.CLEAR_MIN_R = 300       -- closer than this is the fight itself (bases at 215)
S.CLEAR_MARGIN = 120      -- cm kept between the eye and the nearest scenery
S.CLEAR_HALF = 150        -- cm above / below the eye that must be clear
S.EYE_MIN = 18            -- world px: the eye never pulls closer than this to the focus
S.CLEAR_THIN = 30         -- cm: triangles thinner than this do not block
S.CLEAR_FLOOR = 50        -- cm: lower than this is ground, not scenery

local clearMemo = {}

local function binOf(x, z)
  local a = math.atan2(z, x)
  return math.floor((a + math.pi) / (2 * math.pi) * S.CLEAR_BINS) % S.CLEAR_BINS + 1
end

local function clearance(name)
  local c = clearMemo[name]
  if c ~= nil then return c or nil end
  c = false
  local m = model(name)
  if m and m.meshes then
    c = {}
    for b = 1, S.CLEAR_BINS do
      local row = {}
      for h = 1, S.CLEAR_BANDS do row[h] = math.huge end
      c[b] = row
    end
    local function add(x, y, z)
      if y < S.CLEAR_FLOOR then return end       -- the ground, flowers, puddles
      local h = math.floor(y / S.CLEAR_BAND) + 1
      if h < 1 or h > S.CLEAR_BANDS then return end
      local r = math.sqrt(x * x + z * z)
      if r < S.CLEAR_MIN_R then return end
      local row = c[binOf(x, z)]
      if r < row[h] then row[h] = r end
    end
    for _, ms in ipairs(m.meshes) do
      -- additive pieces are light shafts and glows, not something to hit
      if ms.blend ~= "add" then
        local v, idx = ms.v, ms.idx
        local function P(i) local o = (i - 1) * 9; return v[o + 1], v[o + 2], v[o + 3] end
        if not idx then for i = 1, #v / 9 do add(P(i)) end end
        for t = 1, (idx and #idx or 0) - 2, 3 do
          local ax, ay, az = P(idx[t])
          local bx, by, bz = P(idx[t + 1])
          local cx, cy, cz = P(idx[t + 2])
          local ux, uy, uz = bx - ax, by - ay, bz - az
          local wx, wy, wz = cx - ax, cy - ay, cz - az
          local nx, ny, nz = uy * wz - uz * wy, uz * wx - ux * wz, ux * wy - uy * wx
          local area2 = math.sqrt(nx * nx + ny * ny + nz * nz)
          local e = math.max(math.sqrt(ux * ux + uy * uy + uz * uz), math.sqrt(wx * wx + wy * wy + wz * wz),
                             math.sqrt((cx - bx) ^ 2 + (cy - by) ^ 2 + (cz - bz) ^ 2))
          -- thin strips (light lines, ropes, ribbons: kusa's 16 cm 'ef2'
          -- lines run from the middle out to 7 m) are nothing to hit
          local thin = e > 1e-6 and area2 / e < S.CLEAR_THIN
          local n = thin and -1 or math.min(24, math.max(1, math.ceil(e / 80)))
          for i = 0, n do
            for j = 0, n - i do
              local u, w = i / n, j / n
              local k = 1 - u - w
              add(ax * k + bx * u + cx * w, ay * k + by * u + cy * w, az * k + bz * u + cz * w)
            end
          end
        end
      end
    end
  end
  clearMemo[name] = c
  return c or nil
end
S._clearance = clearance

-- open radius (cm) at a stage-frame point, over the bearing's neighbours and
-- the bands around height y
local function openAt(c, x, y, z)
  local b = binOf(x, z)
  local lo = math.max(1, math.floor((y - S.CLEAR_HALF) / S.CLEAR_BAND) + 1)
  local hi = math.min(S.CLEAR_BANDS, math.floor((y + S.CLEAR_HALF) / S.CLEAR_BAND) + 1)
  local r = math.huge
  for d = -1, 1 do
    local row = c[(b - 1 + d) % S.CLEAR_BINS + 1]
    for h = lo, hi do if row[h] < r then r = row[h] end end
  end
  return r
end

-- BattleCam.rig hook (arena.clampEye): slide the eye in toward the focus
-- until it is clear of the stage's trees / walls / rocks at its bearing.
S.PULL_TIME = 0.12        -- seconds the pull eases over (the map is in 5 degree steps)
local pullNow, pullClock = 1, nil

local function clock()
  return (love and love.timer and love.timer.getTime and love.timer.getTime()) or os.clock()
end

function S.clampEye(arena, eye, focus, groundY, fixed)
  local stage = arena and arena._orasStage
  local c = stage and clearance(stage.g)
  if not c then return end
  local K, mx, mz = S.K, arena.mid[1], arena.mid[2]
  groundY = groundY or 0
  local function blocked(wx, wy, wz)
    local x, y, z = -(wx - mx) / K, (wy - groundY) / K, -(wz - mz) / K
    return math.sqrt(x * x + z * z) > openAt(c, x, y, z) - S.CLEAR_MARGIN
  end
  local vx, vy, vz = eye[1] - focus[1], eye[2] - focus[2], eye[3] - focus[3]
  local d = math.sqrt(vx * vx + vy * vy + vz * vz)
  if d < 1e-6 then return end
  local t = 1
  if blocked(eye[1], eye[2], eye[3]) then
    local tMin = math.min(1, S.EYE_MIN / d)
    t = tMin
    for i = 1, 32 do
      local tt = 1 - (1 - tMin) * i / 32
      if not blocked(focus[1] + vx * tt, focus[2] + vy * tt, focus[3] + vz * tt) then t = tt; break end
    end
  end
  -- the live shot eases between steps; a fixed / canonical ask gets the answer
  if not fixed then
    local now = clock()
    local dt = pullClock and math.max(0, math.min(0.25, now - pullClock)) or 1
    pullClock = now
    pullNow = pullNow + (t - pullNow) * math.min(1, dt / S.PULL_TIME)
    t = pullNow
  end
  if t >= 1 then return end
  eye[1], eye[2], eye[3] = focus[1] + vx * t, focus[2] + vy * t, focus[3] + vz * t
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
