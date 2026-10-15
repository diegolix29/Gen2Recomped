-- Gen4Light: the night's lamps and windows light Platinum's own SURFACES.
--
-- WHY THIS EXISTS
--
-- Platinum's roads and walls are drawn by the ENGINE's shader, which never
-- reads Voxel3D.lampLights. Until now the only "light" they got was Gen4Tint's
-- screen-space glow: a flat additive disc painted over the finished frame. It
-- has no depth, so it
--   * sits on top of Mewtwo and the player instead of behind them,
--   * lights a window as a yellow speck rather than the wall around it,
--   * puts a second disc on the lantern ("light on top and bottom"),
--   * never touches the street, so the world still reads as opaque dark.
--
-- WHAT IT DOES INSTEAD
--
-- Same trick as Gen4Sun's shadow receiver, run the other way round: lay
-- additive geometry over the real surfaces, depth-tested against the engine's
-- own depth buffer (never written), and let a pixel shader work out how much
-- light each fragment receives from each source in WORLD space.
--
--   ground  a small sheet of ground-height quads around every light
--   walls   the glass-bearing building meshes Gen4Glass already holds
--
-- Because it is geometry in the scene, a character or a building in front of a
-- lit patch hides it, and a lamp lights the wall beside it harder than the road
-- at its feet, from the flame's real height.
--
-- THE TINT PROBLEM
--
-- Gen4Tint multiplies the whole frame by the hour's colour AFTER the scene. A
-- light added inside the scene is multiplied down with everything else (deep
-- night is 0.14 / 0.17 / 0.31), which both dims it and turns it blue. So the
-- shader divides by that tint first, then normalises so the hottest channel
-- stops at 1: after the multiply the result is the lamp's own warm hue.
-- Brightness is capped by the tint itself (what fits in 0..1 before the
-- multiply); raise DayNight.TINTS_DEEP if deep night is too dark to light.
--
-- Everything is pcall-guarded. If the shader does not compile, `ok` stays
-- false and Gen4Tint keeps painting its old screen-space discs.

local V = ...
local Voxel3D = V.require("Voxel3D")

local function optional(name)
  local ok, mod = pcall(V.require, name)
  return ok and mod or nil
end

local DayNight = optional("DayNight")
local Budget = optional("Gen4Budget") or { allow = function() return true end, charge = function() end }
local clock = (love and love.timer and love.timer.getTime) or os.clock

local Light = {
  enabled = true,
  LOG = true,
  ok = false,              -- set by draw every frame it ran; Gen4Tint reads and clears it

  GROUND = true,           -- light the roads
  WALLS = true,            -- light the building walls

  POST_LIMIT = 8,          -- street posts lit per frame (nearest first)
  PANE_LIMIT = 8,          -- lit windows (nearest first)
  WALL_LIGHTS = 8,         -- the shader's array size: sources a wall may take
  POST_STRENGTH = 1.0,
  PANE_STRENGTH = 0.8,

  CELL = 12,               -- ground sheet quad edge, map px
  LIFT = 0.6,              -- sheet float above the ground (z-fight guard)
  MAX_STEP = 8,            -- a quad whose corners differ more is a cliff: skipped
  SHEETS_PER_FRAME = 3,
  MAX_SHEETS = 48,
  WALL_PULL = 0.8,         -- toward the eye, so a wall overlay never z-fights its wall

  PANE_SOFT = 20,          -- a window's own height for the falloff (units)
  FLOOR_TINT = 0.05,       -- never divide by less than this
  NEUTRAL = 0.999,
  version = 1,
}

local MAXL = 8

local warned = {}
local function note(key, fmt, ...)
  if warned[key] then return end
  warned[key] = true
  if V.mod and V.mod.log then
    V.mod.log:info("%s", "Gen4Light: " .. fmt:format(...))
  end
end

-- --------------------------------------------------------------- shader --

local SHADER = [[
  varying highp vec3 vWorld;
#ifdef VERTEX
  uniform highp mat4 vp;
  uniform highp vec3 offset;     // land origin for a wall mesh; 0 for a ground sheet
  uniform highp vec3 eye;
  uniform highp float pull;      // toward the eye, world units (walls only)
  vec4 position(mat4 transform_projection, vec4 vertex_position) {
    vec3 p = vertex_position.xyz + offset;
    vWorld = p;
    vec3 toEye = eye - p;
    p += toEye * (pull * inversesqrt(max(dot(toEye, toEye), 1.0)));
    return vp * vec4(p, 1.0);
  }
#endif
#ifdef PIXEL
  uniform highp vec4 lp[8];      // xyz = where the light comes FROM, w = reach
  uniform highp vec4 lc[8];      // rgb = colour * power, a = softening (height^2)
  uniform highp float count;
  uniform highp vec3 comp;       // 1 / the hour's tint, so the later multiply cancels

  vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    vec3 acc = vec3(0.0);
    for (int i = 0; i < 8; i++) {
      if (float(i) >= count) break;
      vec4 L = lp[i];
      vec3 d = L.xyz - vWorld;
      float r2 = L.w * L.w;
      vec2 g = d.xz;
      float rad2 = dot(g, g);
      if (rad2 >= r2) continue;               // reach is a ground distance
      float nd2 = rad2 / r2;
      float win = 1.0 - nd2 * nd2;            // zero slope at the rim: no visible ring
      float k = max(lc[i].a, 1.0);
      float atten = win * win * k / (dot(d, d) + k);
      acc += lc[i].rgb * atten;
    }
    // soft ceiling, so overlapping pools climb without blowing out
    acc = acc / (1.0 + acc * 1.2);
    vec3 o = acc * comp;
    float m = max(o.r, max(o.g, o.b));
    if (m > 1.0) o /= m;                      // keep the lamp's hue under the tint
    if (m <= 0.004) discard;
    return vec4(o, 1.0);
  }
#endif
]]

local shader                 -- nil untried, false unavailable
local function getShader()
  if shader == nil then
    local ok, sh = pcall(love.graphics.newShader, SHADER)
    shader = (ok and sh) or false
    if not shader then
      note("shader", "the light shader did not compile (%s) -- Gen4Tint keeps its screen glow", tostring(sh))
    end
  end
  return shader or nil
end

-- ----------------------------------------------------------------- light --

local function nightNow()
  if not DayNight then return 0 end
  local ok, n = pcall(DayNight.windowLight)
  return ok and tonumber(n) or 0
end

-- 1 / the multiply Gen4Tint will apply to this frame, or 1 when it applies none
-- (so a night with the tint switched off is not over-driven).
local function compensation()
  local Tint = optional("Gen4Tint")
  if not (Tint and Tint.enabled and Tint.installed and DayNight) then return { 1, 1, 1 } end
  local ok, t = pcall(DayNight.tint, true)
  if not (ok and t) then return { 1, 1, 1 } end
  local r, g, b = t[1] or 1, t[2] or 1, t[3] or 1
  local neutral = Tint.NEUTRAL or Light.NEUTRAL
  if r > neutral and g > neutral and b > neutral then return { 1, 1, 1 } end
  -- what the frame will REALLY be multiplied by (town lift included)
  if Tint.adjust then r, g, b = Tint.adjust(r, g, b) end
  if r > neutral and g > neutral and b > neutral then return { 1, 1, 1 } end
  local f = Light.FLOOR_TINT
  return { 1 / math.max(r, f), 1 / math.max(g, f), 1 / math.max(b, f) }
end

-- Every source this frame, nearest first within its kind:
-- { x, y (the point it shines FROM), z, floor (ground y under it), radius,
--   power, soft (height^2), kind, d2 }
local function collect(scene)
  local night = nightNow()
  if night <= 0.05 then return {} end
  local view = scene.view
  local vx, vz = view.x or 0, view.z or 0
  local out = {}

  local Lamps = optional("Gen4Lamps")
  if Lamps and Lamps.worldLights then
    local ok, posts = pcall(Lamps.worldLights)
    if ok and type(posts) == "table" then
      local mine = {}
      for _, p in ipairs(posts) do
        local dx, dz = p.x - vx, p.z - vz
        local h = math.max(8, (p.fy or p.y) - p.y)
        mine[#mine + 1] = {
          x = p.x, y = p.fy or (p.y + 34), z = p.z, floor = p.y,
          radius = p.radius or 96, power = (p.power or night) * Light.POST_STRENGTH/3,
          soft = h * h, kind = "post", d2 = dx * dx + dz * dz,
        }
      end
      table.sort(mine, function(a, b) return a.d2 < b.d2 end)
      for i = 1, math.min(#mine, Light.POST_LIMIT) do out[#out + 1] = mine[i] end
    end
  end

  local Glass = optional("Gen4Glass")
  if Glass and Glass.screenLights then
    local ok, panes = pcall(Glass.screenLights, vx, vz)
    if ok and type(panes) == "table" then
      local ground = scene.ground
      local ox, oz = ground.offsetX or 0, ground.offsetY or 0
      for i = 1, math.min(#panes, Light.PANE_LIMIT) do
        local p = panes[i]
        local floor = ground.groundY and ground:groundY(p.x - ox, p.z - oz)
        floor = tonumber(floor) or math.min(p.y, 0)
        out[#out + 1] = {
          x = p.x, y = p.y, z = p.z, floor = floor,
          radius = p.radius or 77, power = (p.power or night) * Light.PANE_STRENGTH,
          soft = Light.PANE_SOFT * Light.PANE_SOFT, kind = "pane", d2 = p.d2 or 0,
        }
      end
    end
  end
  return out
end

-- ---------------------------------------------------------- ground sheets --

-- ground -> { sheets = { [key] = {mesh, count, used} }, n = number, heights = {} }
local perGround = setmetatable({}, { __mode = "k" })
local tick = 0

local function cacheOf(ground)
  local c = perGround[ground]
  if not c then c = { sheets = {}, n = 0, heights = {} }; perGround[ground] = c end
  return c
end

local function release(sheet)
  if sheet.mesh and sheet.mesh.release then pcall(sheet.mesh.release, sheet.mesh) end
end

local function buildSheet(ground, cache, l)
  local CELL = Light.CELL
  local ox, oz = ground.offsetX or 0, ground.offsetY or 0
  local r = l.radius
  local n = math.ceil(2 * r / CELL) + 1
  local x0, z0 = l.x - r, l.z - r
  local heights = cache.heights
  local h = {}
  for j = 0, n - 1 do
    for i = 0, n - 1 do
      local wx, wz = x0 + i * CELL, z0 + j * CELL
      local hk = math.floor(wx / CELL + 0.5) * 100003 + math.floor(wz / CELL + 0.5)
      local y = heights[hk]
      if y == nil then
        local v = ground:groundY(wx - ox, wz - oz)
        y = tonumber(v) or false
        heights[hk] = y
      end
      h[j * n + i + 1] = y
    end
  end
  local verts = {}
  for j = 0, n - 1 do
    for i = 0, n - 1 do
      verts[j * n + i + 1] = { x0 + i * CELL, (h[j * n + i + 1] or 0) + Light.LIFT, z0 + j * CELL }
    end
  end
  local map, c = {}, 0
  local r2 = (r * 1.08) * (r * 1.08)
  for j = 0, n - 2 do
    for i = 0, n - 2 do
      local a = j * n + i + 1
      local b, d, e = a + 1, a + n, a + n + 1
      local ya, yb, yd, ye = h[a], h[b], h[d], h[e]
      if ya and yb and yd and ye then
        local cx, cz = x0 + (i + 0.5) * CELL - l.x, z0 + (j + 0.5) * CELL - l.z
        if cx * cx + cz * cz <= r2
           and math.max(ya, yb, yd, ye) - math.min(ya, yb, yd, ye) <= Light.MAX_STEP then
          map[c + 1], map[c + 2], map[c + 3] = a, b, d
          map[c + 4], map[c + 5], map[c + 6] = b, e, d
          c = c + 6
        end
      end
    end
  end
  if c == 0 then return { count = 0 } end
  local ok, mesh = pcall(love.graphics.newMesh, { { "VertexPosition", "float", 3 } },
                         verts, "triangles", "static")
  if not ok then return { count = 0 } end
  mesh:setVertexMap(map)
  return { mesh = mesh, count = c }
end

local function sheetFor(ground, l, budget)
  local cache = cacheOf(ground)
  local key = string.format("%d:%d:%d", math.floor(l.x + 0.5), math.floor(l.z + 0.5), math.floor(l.radius))
  local sheet = cache.sheets[key]
  if not sheet then
    if budget.left <= 0 or not Budget.allow(false) then return nil end
    budget.left = budget.left - 1
    local t0 = clock()
    local ok, built = pcall(buildSheet, ground, cache, l)
    Budget.charge(t0, "light")
    if not ok then
      note("sheet", "a ground sheet failed to build and was skipped: %s", tostring(built))
      built = { count = 0 }
    end
    sheet = built
    cache.sheets[key] = sheet
    cache.n = cache.n + 1
    if cache.n > Light.MAX_SHEETS then
      local old = {}
      for k, s in pairs(cache.sheets) do
        if s ~= sheet and s.used ~= tick then old[#old + 1] = { s.used or 0, k } end
      end
      table.sort(old, function(a, b) return a[1] < b[1] end)
      local i = 1
      while cache.n > Light.MAX_SHEETS and old[i] do
        release(cache.sheets[old[i][2]])
        cache.sheets[old[i][2]] = nil
        cache.n = cache.n - 1
        i = i + 1
      end
    end
  end
  sheet.used = tick
  return sheet
end

-- ------------------------------------------------------------------- draw --

local function sendLights(sh, list, lamp)
  local lp, lc = {}, {}
  for i = 1, MAXL do
    local l = list[i]
    if l then
      lp[i] = { l.x, l.y, l.z, l.radius }
      local p = l.power or 1
      lc[i] = { lamp[1] * p, lamp[2] * p, lamp[3] * p, l.soft or 400 }
    else
      lp[i] = { 0, 0, 0, 0 }
      lc[i] = { 0, 0, 0, 1 }
    end
  end
  local spread = table.unpack or unpack
  pcall(sh.send, sh, "lp", spread(lp))
  pcall(sh.send, sh, "lc", spread(lc))
  pcall(sh.send, sh, "count", math.min(#list, MAXL))
end

function Light.draw(scene)
  Light.ok = false
  if not (Light.enabled and DayNight and scene and scene.ground and scene.view) then return end
  local ground = scene.ground
  if ground.outdoors == false then return end
  local sh = getShader()
  if not sh then return end
  Light.ok = true                          -- ran (nothing to light by day is still "ran")

  local lights = collect(scene)
  if #lights == 0 then return end

  tick = tick + 1
  local lamp = { 1.0, 0.84, 0.5 }
  do
    local okL, c = pcall(DayNight.lampColor)
    if okL and type(c) == "table" then lamp = c end
  end

  local g = love.graphics
  local prevShader = g.getShader()
  local prevBlend, prevAlpha = g.getBlendMode()
  g.setShader(sh)
  g.setBlendMode("add", "alphamultiply")
  scene.blend()                            -- depth-tested, never written
  pcall(sh.send, sh, "vp", "row", Voxel3D.vp)
  pcall(sh.send, sh, "eye", { scene.eye[1], scene.eye[2], scene.eye[3] })
  pcall(sh.send, sh, "comp", compensation())
  g.setColor(1, 1, 1, 1)

  local ok, err = pcall(function()
    -- ground: one sheet per light, each adding ITS OWN light, so overlapping
    -- sheets sum like real pools instead of double-counting a shared array
    if Light.GROUND and ground.groundY then
      pcall(sh.send, sh, "offset", { 0, 0, 0 })
      pcall(sh.send, sh, "pull", 0)
      local budget = { left = Light.SHEETS_PER_FRAME }
      for _, l in ipairs(lights) do
        local sheet = sheetFor(ground, l, budget)
        if sheet and sheet.mesh and sheet.count > 0 then
          -- the sheet is lit from this light alone, at its real height
          sendLights(sh, { l }, lamp)
          g.draw(sheet.mesh)
        end
      end
    end

    -- walls: the glass-bearing building meshes, lit by the nearest sources
    if Light.WALLS then
      local Glass = optional("Gen4Glass")
      local pieces = Glass and Glass.wallPieces and Glass.wallPieces() or nil
      if pieces and #pieces > 0 then
        local near = {}
        for i = 1, math.min(#lights, Light.WALL_LIGHTS) do near[i] = lights[i] end
        sendLights(sh, near, lamp)
        pcall(sh.send, sh, "pull", Light.WALL_PULL)
        local reach = (ground.chunkPx or 512) * 0.75
        local visible = scene.sphereVisible
        local radius = (ground.chunkPx or 512) * 0.72 + 80
        for _, p in ipairs(pieces) do
          local hit = false
          for _, l in ipairs(near) do
            local dx, dz = p.x - l.x, p.z - l.z
            local rr = l.radius + reach
            if dx * dx + dz * dz <= rr * rr then hit = true; break end
          end
          if hit and ((not visible) or visible(p.x, 0, p.z, radius)) then
            pcall(sh.send, sh, "offset", { p.x, 0, p.z })
            g.draw(p.mesh)
          end
        end
      end
    end
  end)

  g.setBlendMode(prevBlend or "alpha", prevAlpha)
  g.setShader(prevShader)
  scene.opaque()
  if not ok then error(err, 0) end
  if Light.LOG then note("draw", "lighting %d source(s) on roads and walls", #lights) end
end

function Light.invalidate()
  for _, c in pairs(perGround) do
    for _, s in pairs(c.sheets) do release(s) end
  end
  perGround = setmetatable({}, { __mode = "k" })
  shader = nil
  Light.ok = false
  Light.version = Light.version + 1
end

return Light
