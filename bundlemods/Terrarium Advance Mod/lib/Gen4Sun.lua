-- Gen4Sun: cast shadows on Platinum's own 3D world.
--
-- WHY THIS EXISTS
--
-- On Gen 1-3 lib/VoxelScene owns the frame: it fills lib/ShadowMap from the sun
-- every frame and the Voxel3D shader samples it. On Gen 4 VoxelScene never runs
-- (the `voxel` pipeline stands down, see Gen4Bridge), and neither Gen4Bridge
-- nor Gen4WorldHost ever touched ShadowMap or Shadows -- so the map was never
-- filled, `ShadowMap.active()` stayed false, and every Terrarium mesh on a
-- Gen 4 map drew with sunDark = 0: no shadows at all, and the SHADOWS rows did
-- nothing. This module is the Gen 4 half of that pipeline.
--
-- THREE PIECES
--
--  1. CASTERS. Voxel3D.draw is wrapped once. While `Sun.capturing` is on (the
--     Bridge sets it around trees / rocks / fences / bumps / HD Pokemon, the
--     Host around the field actors) every non-swaying mesh drawn is recorded:
--     mesh, texture and a COPY of its model matrix. Grass and flowers sway and
--     are skipped on purpose: thousands of tufts would cost more than they show.
--
--  2. THE SUN PASS. Sun.cast(ground) runs from Gen4WorldHost's drawFree wrapper,
--     BEFORE the engine opens its free canvas (the sun pass switches canvases,
--     and the engine's colour+depth target must not be disturbed). It fills
--     ShadowMap from last frame's casters -- one frame behind, which at walking
--     speed is a fraction of a pixel -- fitted to a box around the player
--     instead of the voxel camera's frustum (ShadowMap.begin's `box`).
--
--  3. THE RECEIVER. Platinum's terrain is drawn by the engine with its own
--     shader, which cannot read our map. So Sun.receive(scene) lays a thin,
--     transparent sheet of ground-height quads over the terrain and darkens
--     the texels the map says the sun cannot reach. It is depth-tested against
--     the real scene (buildings and characters stay in front) and never writes
--     depth. Meshes Terrarium draws itself (trees, rocks, NPC bodies...) take
--     the map through the ordinary Voxel3D shader and need nothing extra.
--
-- Everything is pcall-guarded by the callers: a failure here costs shadows,
-- never the frame.

local V = ...

local ShadowMap = V.require("ShadowMap")   -- the sun's depth pass
local Shadows = V.require("Shadows")       -- the SHADOWS on/off row
local Voxel3D = V.require("Voxel3D")
local Quality = V.require("Quality")
local DayNight = V.require("DayNight")     -- the clock: where the sun/moon is

local Sun = {
  capturing = false,
  pending = {},          -- casters recorded THIS frame
  casters = {},          -- last frame's, what the sun pass draws
  stats = { casts = 0, casters = 0, quads = 0 },
  live = false,          -- a map this module filled is standing
  center = nil,          -- {x, z} world, the box the last cast covered
}

Sun.MAX_CASTERS = 1200
Sun.MARGIN = 48          -- caster cull margin around the box, world px
Sun.LIFT = 0.35          -- the receiver's float above the ground, world px
Sun.CELL = 8             -- receiver quad edge, map px
Sun.RADIUS_LOW = 224     -- how far from the player shadows are made, world px
Sun.RADIUS_HIGH = 320

-- Whether the MOON throws shadows at night. true follows the mod's own rig on
-- Gen 1-3 (a softer press, 0.26 against the sun's 0.40, from the moon's own
-- bearing). false means a night is simply dark -- the hour's tint from DayTint
-- and nothing cast at all -- which is the "full dark map" look.
Sun.NIGHT_SHADOWS = true

-- ------------------------------------------------------------ gating --

-- Shadows run when the row says so AND the sun pass can exist at all (shaders,
-- a canvas, and Quality's own SHADOWS row not OFF).
function Sun.enabled()
  local okS, on = pcall(Shadows.enabled)
  if not (okS and on) then return false end
  local okA, avail = pcall(ShadowMap.available)
  return okA and avail and true or false
end

-- Drop the map and the baked receiver (graphics reset, mod reload, battle).
function Sun.invalidate()
  Sun.pending, Sun.casters = {}, {}
  Sun.live = false
  Sun.center = nil
  Sun._mesh, Sun._key, Sun._indexCount = nil, nil, 0
  Sun._heights = setmetatable({}, { __mode = "k" })
  pcall(ShadowMap.invalidate)
end

-- Called when something else (a battle, the arena pose) is about to use the
-- map or the Voxel3D shader: a frozen overworld map would shadow it wrongly.
function Sun.suspend()
  if Sun.live then
    Sun.live = false
    pcall(ShadowMap.invalidate)
  end
  Sun.pending, Sun.casters = {}, {}
end

Sun._heights = setmetatable({}, { __mode = "k" })

-- ------------------------------------------------------------ capture --

local function copyModel(m)
  if not m then return nil end
  return { m[1], m[2], m[3], m[4], m[5], m[6], m[7], m[8],
           m[9], m[10], m[11], m[12], m[13], m[14], m[15], m[16] }
end

-- Wrap Voxel3D.draw once. A wrapper left by an earlier run of this file (mod
-- reload) sees a different token and passes straight through.
function Sun.hook()
  if Sun.hooked then return true end
  local original = Voxel3D.draw
  if type(original) ~= "function" then return false end
  local token = {}
  Voxel3D.__sunToken = token
  Voxel3D.draw = function(mesh, texture, model, pull, sunModel, sway, waterBody)
    if Voxel3D.__sunToken == token and Sun.capturing and mesh
       and not (sway and sway > 0) then
      local list = Sun.pending
      local n = #list
      if n < Sun.MAX_CASTERS then
        list[n + 1] = { mesh, texture, copyModel(model) }
      end
    end
    return original(mesh, texture, model, pull, sunModel, sway, waterBody)
  end
  Sun.hooked = true
  return true
end

-- Effects of Gen4Bridge that cast (by registered name).
Sun.CASTING = { trees = true, rocks = true, fence = true, bump = true,
                hd_pokemon = true }

-- ------------------------------------------------------------ the pass --

local function playerCentre(ground)
  local okG, Game = pcall(require, "src.core.Game")
  local ow = okG and type(Game) == "table" and Game.overworld or nil
  local p = ow and ow.player
  local ox, oz = ground.offsetX or 0, ground.offsetY or 0
  if p and p.px and p.py then return p.px + 8 + ox, p.py + 8 + oz end
  local view = ground.view3d
  if view and view.x and view.z then return view.x, view.z end
  return nil
end

local function radius()
  return Quality.softShadows() and Sun.RADIUS_HIGH or Sun.RADIUS_LOW
end

-- Is this map under the open sky? Gen4Spawn.isOutdoor is the real answer on
-- Platinum. Map.isOutdoor (what DayTint and VoxelScene use) reads Gen 1/2 header
-- fields and says "indoors" for a Gen 4 map, which left the rig on its noon
-- setting -- full sun shadows all night -- so it is only the fallback here.
local function outdoorNow()
  local okG, Game = pcall(require, "src.core.Game")
  local ow = okG and type(Game) == "table" and Game.overworld or nil
  local map = ow and ow.map
  if not map then return false end
  local okS, Spawn = pcall(V.require, "Gen4Spawn")
  if okS and type(Spawn) == "table" and Spawn.isOutdoor then
    local ok, r = pcall(Spawn.isOutdoor, map)
    if ok then return r and true or false end
  end
  local okM, Map = pcall(require, "src.world.Map")
  if okM and Map and Map.isOutdoor and map.def then
    local ok, r = pcall(Map.isOutdoor, map.def)
    return ok and r and true or false
  end
  return false
end

-- Point the shared light rig at the hour, as VoxelScene does on Gen 1-3:
-- ShadowMap.KX/KZ get the body's bearing and Voxel3D.SHADOW_ALPHA the hour's
-- weight. Gen 4 never ran this, so the sun sat at noon, full strength, all
-- night. Two clocks are consulted: the mod's DayNight (sun/moon position) and the
-- ENGINE's own `ground.nightness` (the cartridge's light keyframes, 0 day .. 1
-- night, off the wall clock) so shadows die with the world's own dusk even when
-- the DAYTIME row is pinned to DAY. Returns false when this hour casts nothing.
local function pointRig(ground)
  local outdoor = outdoorNow()
  pcall(DayNight.applyRig, outdoor)
  if not outdoor then return (Voxel3D.SHADOW_ALPHA or 0) > 0.004 end
  if not Sun.NIGHT_SHADOWS then
    local okB, _, _, moon = pcall(DayNight.bodyAt, DayNight.rigTime())
    if okB and moon then return false end
    local n = tonumber(ground and ground.nightness)
    if n then
      if n >= 0.5 then return false end
      -- a fade, not a switch: the dusk keyframes move nightness continuously
      Voxel3D.SHADOW_ALPHA = (Voxel3D.SHADOW_ALPHA or 0) * (1 - n * 2)
    end
  end
  return (Voxel3D.SHADOW_ALPHA or 0) > 0.004
end

-- Fill the shadow map for this frame. Must run with NO engine canvas open.
function Sun.cast(ground, vw, vh)
  -- this frame's recording becomes next frame's casters
  Sun.casters, Sun.pending = Sun.pending, {}
  Sun.capturing = false
  if not ground then return false end
  if not Sun.enabled() then
    if Sun.live then Sun.suspend() end
    return false
  end
  -- the hour first: it moves the sun the frustum is fitted to
  if not pointRig(ground) then
    -- night (or the horizon's shadowless gap): nothing is cast, and a map left
    -- standing from the afternoon must not keep shading the dark world
    if Sun.live then Sun.suspend() end
    return false
  end
  local list = Sun.casters
  if #list == 0 then return false end
  local cx, cz = playerCentre(ground)
  if not cx then return false end

  local R = radius()
  local reach = ShadowMap.HEIGHT
                * math.max(math.abs(ShadowMap.KX), math.abs(ShadowMap.KZ)) + 24
  -- ground heights around the player decide the box's vertical span
  local ox, oz = ground.offsetX or 0, ground.offsetY or 0
  local lo, hi = 0, 0
  if ground.groundY then
    lo, hi = math.huge, -math.huge
    for _, d in ipairs({ { 0, 0 }, { -R, -R }, { R, -R }, { -R, R }, { R, R } }) do
      local y = ground:groundY(cx - ox + d[1], cz - oz + d[2])
      if tonumber(y) then lo, hi = math.min(lo, y), math.max(hi, y) end
    end
    if lo > hi then lo, hi = 0, 0 end
  end
  -- the sun hangs southeast, so casters for this ground stand south and east
  -- of it: the margin goes on those two sides only
  local box = { cx - R, cz - R, cx + R + reach, cz + R + reach,
                lo - 32, hi + ShadowMap.HEIGHT }
  Sun.center = { cx, cz }

  if not ShadowMap.stale(true) then return true end

  local g = love.graphics
  local m = Sun.MARGIN
  local x0, z0, x1, z1 = box[1] - m, box[2] - m, box[3] + m, box[4] + m
  local drawn = 0
  g.push("all")
  g.origin()
  g.setScissor()
  local ok, err = pcall(function()
    if not ShadowMap.begin(cx, cz, vw or 1, vh or 1, box) then return end
    for i = 1, #list do
      local c = list[i]
      local model = c[3]
      -- the model's translation column: cull what stands outside the box
      local x, z = 0, 0
      if model then x, z = model[4], model[12] end
      if x >= x0 and x <= x1 and z >= z0 and z <= z1 then
        ShadowMap.draw(c[1], c[2], model)
        drawn = drawn + 1
      end
    end
    ShadowMap.finish()
    Sun.live = true
  end)
  if not ok then
    pcall(ShadowMap.finish)       -- never leave the pass open
    Sun.live = false
    g.pop()
    error(err, 0)
  end
  g.pop()
  Sun.stats.casts = Sun.stats.casts + 1
  Sun.stats.casters = drawn
  return true
end

-- ------------------------------------------------------------ receiver --

local SHADER = [[
  varying highp vec3 vWorld;
#ifdef VERTEX
  uniform highp mat4 vp;
  vec4 position(mat4 transform_projection, vec4 vertex_position) {
    vWorld = vertex_position.xyz;
    return vp * vertex_position;
  }
#endif
#ifdef PIXEL
  uniform highp mat4 sunVP;
  uniform Image sunMap;
  uniform highp float dark;
  uniform highp float sunBias;
  uniform highp vec2 sunTexel;
  uniform highp float oneTap;

  float sunDepth(vec2 uv) {
    vec4 c = Texel(sunMap, uv);
    return c.r + c.g * (1.0 / 255.0);
  }

  vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    vec3 p = (sunVP * vec4(vWorld, 1.0)).xyz;
    if (p.x < 0.0 || p.x > 1.0 || p.y < 0.0 || p.y > 1.0 || p.z > 1.0) discard;
    // ease out at the map's rim, same as the scene shader's sunlight()
    vec2 e = min(p.xy, 1.0 - p.xy);
    float edge = smoothstep(0.0, 0.06, min(e.x, e.y));
    if (edge <= 0.0) discard;
    float z = p.z - sunBias;
    float lit;
    if (oneTap > 0.5) {
      lit = step(z, sunDepth(p.xy));
    } else {
      lit = (step(z, sunDepth(p.xy + sunTexel * vec2(-0.5, -0.5)))
           + step(z, sunDepth(p.xy + sunTexel * vec2( 0.5, -0.5)))
           + step(z, sunDepth(p.xy + sunTexel * vec2(-0.5,  0.5)))
           + step(z, sunDepth(p.xy + sunTexel * vec2( 0.5,  0.5)))) * 0.25;
    }
    float a = edge * (1.0 - lit) * dark;
    if (a <= 0.004) discard;
    return vec4(0.0, 0.0, 0.0, a);
  }
#endif
]]

local shader                 -- nil untried, false unavailable

local function getShader()
  if shader == nil then
    local ok, sh = pcall(love.graphics.newShader, SHADER)
    shader = (ok and sh) or false
  end
  return shader or nil
end

local MAX_FRESH = 1500       -- new ground samples one build may take
local MAX_STEP = 8           -- a quad whose corners differ more is a cliff: skip

-- (Re)build the sheet of ground-height quads around the player. Heights are
-- sampled once per cell ever (weak-keyed per ground) and the build resumes next
-- frame when it ran out of budget, so a cold map never hitches.
local function ensureMesh(ground, cxPx, czPx)
  local CELL = Sun.CELL
  local half = math.floor(radius() / CELL) - 2
  local snap = CELL * 2
  local ix0 = math.floor(cxPx / snap) * 2
  local iz0 = math.floor(czPx / snap) * 2
  local key = ix0 .. ":" .. iz0 .. ":" .. half
  if Sun._mesh and Sun._key == key and Sun._ground == ground then
    return Sun._mesh
  end
  local cache = Sun._heights[ground]
  if not cache then cache = {}; Sun._heights[ground] = cache end

  local n = half * 2 + 1
  local fresh = MAX_FRESH
  local h = {}
  for j = 0, n - 1 do
    local iz = iz0 - half + j
    for i = 0, n - 1 do
      local ix = ix0 - half + i
      local ck = (ix + 2048) * 8192 + (iz + 2048)
      local y = cache[ck]
      if y == nil then
        if fresh <= 0 then return Sun._mesh end      -- resume next frame
        fresh = fresh - 1
        local v = ground:groundY(ix * CELL, iz * CELL)
        y = tonumber(v) or false
        cache[ck] = y
      end
      h[j * n + i + 1] = y
    end
  end

  local ox, oz = ground.offsetX or 0, ground.offsetY or 0
  local verts = {}
  for j = 0, n - 1 do
    for i = 0, n - 1 do
      local y = h[j * n + i + 1]
      verts[j * n + i + 1] = {
        (ix0 - half + i) * CELL + ox,
        (y or 0) + Sun.LIFT,
        (iz0 - half + j) * CELL + oz,
      }
    end
  end
  local map, c = {}, 0
  for j = 0, n - 2 do
    for i = 0, n - 2 do
      local a = j * n + i + 1
      local b, d, e = a + 1, a + n, a + n + 1
      local ya, yb, yd, ye = h[a], h[b], h[d], h[e]
      if ya and yb and yd and ye then
        local top = math.max(ya, yb, yd, ye)
        local bot = math.min(ya, yb, yd, ye)
        if top - bot <= MAX_STEP then
          map[c + 1], map[c + 2], map[c + 3] = a, b, d
          map[c + 4], map[c + 5], map[c + 6] = b, e, d
          c = c + 6
        end
      end
    end
  end

  local mesh = Sun._mesh
  if not (mesh and Sun._verts == #verts) then
    local ok, m = pcall(love.graphics.newMesh,
                        { { "VertexPosition", "float", 3 } }, verts,
                        "triangles", "dynamic")
    if not ok then return nil end
    mesh, Sun._mesh, Sun._verts = m, m, #verts
  else
    mesh:setVertices(verts)
  end
  mesh:setVertexMap(map)
  Sun._key, Sun._ground, Sun._indexCount = key, ground, c
  Sun.stats.quads = c / 6
  return mesh
end

-- Draw the shadow sheet. Runs inside the Bridge's open Voxel3D scene, last.
function Sun.receive(scene)
  if not (scene and scene.ground and ShadowMap.active()) then return end
  local ground = scene.ground
  local sh = getShader()
  if not (sh and ground.groundY) then return end
  local ox, oz = scene.offsetX or 0, scene.offsetZ or 0
  local cx, cz
  if Sun.center then cx, cz = Sun.center[1], Sun.center[2]
  else cx, cz = playerCentre(ground) end
  if not cx then return end
  local mesh = ensureMesh(ground, cx - ox, cz - oz)
  if not (mesh and Sun._indexCount > 0) then return end

  local g = love.graphics
  local prevShader = g.getShader()
  local prevBlend, prevAlpha = g.getBlendMode()
  g.setShader(sh)
  g.setBlendMode("alpha", "alphamultiply")
  scene.blend()                      -- depth-tested, never written
  pcall(sh.send, sh, "vp", "row", Voxel3D.vp)
  pcall(sh.send, sh, "sunVP", "row", ShadowMap.uvVP)
  local tex = ShadowMap.texture()
  if tex then pcall(sh.send, sh, "sunMap", tex) end
  pcall(sh.send, sh, "dark", Voxel3D.SHADOW_ALPHA or 0.4)
  pcall(sh.send, sh, "sunBias", ShadowMap.bias)
  local texel = 1 / math.max(1, ShadowMap.res)
  pcall(sh.send, sh, "sunTexel", { texel, texel })
  pcall(sh.send, sh, "oneTap", Quality.softShadows() and 0 or 1)
  g.setColor(1, 1, 1, 1)
  local ok, err = pcall(g.draw, mesh)
  g.setBlendMode(prevBlend or "alpha", prevAlpha)
  g.setShader(prevShader)
  scene.opaque()
  if not ok then error(err, 0) end
end

Sun.hook()

return Sun
