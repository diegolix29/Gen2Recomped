-- Gen4Glass: window glass on Platinum's own buildings -- the Gen 4 half of
-- lib/GlassMask.
--
-- WHY GLASSMASK ITSELF DOES NOT APPLY HERE
--
-- On Gen 1-3 the glass is a MASK the size of the tileset atlas, and the scene
-- shader samples it with the same UVs as the terrain mesh. Gen 4 has no tileset
-- atlas: the engine draws the cartridge's own NSBMD buildings with its own
-- shader, one texture per material. So the mask has to be per TEXTURE, and the
-- glass has to be drawn by us, on top of the engine's building, through the
-- Voxel3D shader that already knows what to do with a mask (lit panes after
-- dark, the movement-fed glint by day).
--
-- WHAT GEN 4 SAYS ABOUT ITS WINDOWS (there is no id list -- read this)
--
-- Gen 3 has a hand-made catalog (src/world/Gen3WindowMetatiles.lua). Gen 4 has
-- no counterpart: nothing in the engine lists window ids. What it DOES carry,
-- on every building shape, is the material name, the texture name and the
-- texture's own picture (`shape.image`, `shape.material`, `shape.texture`).
-- Two facts about Platinum's art are already established in the engine and are
-- used here instead of inventing a rule:
--
--   1. A glass MATERIAL is named for it: `wtk_kabe_garasu3` (garasu = glass,
--      stated translucent) -- Gen4Terrain.lua. Such a texture is glass whole.
--   2. A window PAINTED INTO A WALL TEXTURE is drawn at the palette's pure
--      white, and nothing else in a house wall is -- Gen4Model.splitWallBand
--      measured t1_s01 (glass 1.000 against siding 0.756..0.871).
--
-- So a texture's mask is "pure white texels" (or every texel, for a garasu
-- material). A texture whose white is most of the picture is not a window
-- texture (a white wall, a sign board) and is left alone -- MAX_FRACTION.
--
-- HOW IT DRAWS
--
-- For each land near the camera the placed buildings (Gen4Ground:objectsFor)
-- are walked; every shape that wears a glass texture is copied, PLACED, into one
-- mesh per texture. The mesh is drawn over the engine's building with the
-- texture's glass-only copy as both the texture and the mask: non-glass texels
-- are alpha 0 and the scene shader discards them, so only the panes are drawn.
-- `pull` nudges the overlay toward the eye so it never z-fights the surface it
-- sits on. Outdoors only, exactly like the Gen 1-3 glass.
--
-- By default only the NIGHT lamps are drawn (the overlay's lit colour does not
-- depend on how the engine shaded the wall, so nothing can mismatch). The day
-- glint is DAY_GLINT: it lifts the overlay's own base colour, which is not
-- guaranteed to match the engine's shading of the same wall, so it is off until
-- it has been looked at in play.
--
-- TUNING: with LOG on, every texture analysed writes one line (grep
-- "Gen4Glass:") giving its names, size, glass texel count and verdict. A white
-- wall that lights up like a lamp is a texture to add to DENY_NAMES; a window
-- that never lights is a texture to add to ALLOW.
--
-- NOT VERIFIED: written without a ROM or a LOVE runtime to hand. It is isolated
-- the way the other Gen 4 passes are (Bridge disables an effect that throws).
-- Bridge.setEffect("glass", false) turns it off.

local V = ...
local Voxel3D = V.require("Voxel3D")
local Assets = require("src.render.Assets")

local function optional(name)
  local ok, mod = pcall(V.require, name)
  return ok and mod or nil
end

local DayNight = optional("DayNight")
local Budget = optional("Gen4Budget") or { allow = function() return true end, charge = function() end }
local clock = (love and love.timer and love.timer.getTime) or os.clock

local Glass = {
  enabled = true,

  -- substrings of a shape's TEXTURE or MATERIAL name that make the whole
  -- texture glass (Gen4Terrain: `wtk_kabe_garasu3`)
  GLASS_NAMES = { "garasu", "glass" },
  -- substrings that are never scanned: shadows, water, sky, snow
  DENY_NAMES = { "kage", "shadow", "shade", "water", "sea", "kumo", "cloud",
                 "snow", "yuki" },
  -- exact lower-case texture names forced to glass whole (tuning)
  -- c1_lamp01 / c1_lamp02: city building lights (not street posts).
  ALLOW = { c1_lamp01 = true, c1_lamp02 = true },

  WHITE = 0.5,        -- every channel at least this: the palette's white
  MIN_TEXELS = 4,       -- fewer glass texels than this is noise, not a pane
  MAX_FRACTION = 0.45,  -- more of the picture than this and it is not a window

  WINDOW = 2,           -- lands each way around the camera
  PULL = 0.6,           -- toward the eye, world units: the overlay's depth bias
  SHADE = 0.9,          -- the overlay's own vertex shade (day glint's base only)

  NIGHT_MIN = 0.02,     -- below this the lamps are out and nothing is drawn
  DAY_GLINT = false,    -- see the header
  GLINT_RATE = 0.05,    -- radians of sweep per world unit travelled
  GLINT_IN = 0.12,      -- strength gained per moving frame
  GLINT_OUT = 0.08,     -- ...and lost per resting frame
  GLINT_MIN = 0.02,

  BUILDS_PER_FRAME = 3,
  MAX_RESIDENT = 24,
  MAX_VERTS = 60000,    -- split a mesh before it needs 32-bit indices
  LOG = true,

  -- Point lights from the glass MASK itself (pane centroids, not the land
  -- centre). The shader only has eight lamp slots, shared with street lamps.
  LIGHT_RADIUS = 48,
  LIGHT_LIMIT = 8,
  LIGHT_CLUSTER = 20,   -- merge pane samples this close (one window, one flame)

  stats = { textures = 0, glassTextures = 0, lands = 0, shapes = 0 },
  version = 2,
}

local FX16, UV_UNITS = 4096, 16

local warned = {}
local function note(key, fmt, ...)
  if warned[key] then return end
  warned[key] = true
  if V.mod and V.mod.log then
    -- already formatted: a leftover "%" (e.g. "17%") must not be re-parsed
    V.mod.log:info("%s", "Gen4Glass: " .. fmt:format(...))
  end
end

local function lowered(s) return tostring(s or ""):lower() end

local function hasAny(name, list)
  for _, sub in ipairs(list) do
    if name:find(sub, 1, true) then return true end
  end
  return false
end

-- ------------------------------------------------------- the texture masks --

-- image path -> { image, w, h, texels } for a texture with glass in it, or
-- false for one without (or unreadable: a verdict for the session, no retry loop)
local textures = {}

local function analyse(path, textureName, materialName)
  local hit = textures[path]
  if hit ~= nil then return hit or nil end
  textures[path] = false
  Glass.stats.textures = Glass.stats.textures + 1

  local tex, mat = lowered(textureName), lowered(materialName)
  if hasAny(tex, Glass.DENY_NAMES) or hasAny(mat, Glass.DENY_NAMES) then
    if Glass.LOG then note("deny:" .. path, "%s (%s): skipped, name is denied", tex, mat) end
    return nil
  end

  -- `Assets.image` hands back a placeholder for a path that is not there, so
  -- the pixels are read with the call that RAISES (as Gen4Model.splitWallBand)
  local okData, data = pcall(function()
    return love.image.newImageData(Assets.resolve(path))
  end)
  if not (okData and data) then
    note("read:" .. path, "%s: could not read the texture", tostring(path))
    return nil
  end
  local w, h = data:getDimensions()
  if w < 1 or h < 1 then return nil end

  local whole = Glass.ALLOW[tex] == true
                or hasAny(tex, Glass.GLASS_NAMES) or hasAny(mat, Glass.GLASS_NAMES)
  local white = Glass.WHITE
  local out = love.image.newImageData(w, h)
  local count = 0
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local r, g, b, a = data:getPixel(x, y)
      if a >= 0.5 and (whole or (r >= white and g >= white and b >= white)) then
        out:setPixel(x, y, r, g, b, 1)
        count = count + 1
      else
        out:setPixel(x, y, 0, 0, 0, 0)
      end
    end
  end

  local fraction = count / (w * h)
  local keep = count >= Glass.MIN_TEXELS and (whole or fraction <= Glass.MAX_FRACTION)
  if Glass.LOG then
    note("tex:" .. path, "%s (%s) %dx%d: %d glass texels (%.0f%%)%s -> %s",
         tex, mat, w, h, count, fraction * 100, whole and ", whole pane" or "",
         keep and "GLASS" or "no glass")
  end
  if not keep then return nil end

  local okImg, image = pcall(love.graphics.newImage, out)
  if not (okImg and image) then
    note("img:" .. path, "%s: could not make the glass image", tostring(path))
    return nil
  end
  image:setFilter("nearest", "nearest")
  image:setWrap("repeat", "repeat")       -- Gen 4 UVs run far past 0..1
  local entry = { image = image, mask = out, w = w, h = h, texels = count, whole = whole }
  textures[path] = entry
  Glass.stats.glassTextures = Glass.stats.glassTextures + 1
  return entry
end

-- ------------------------------------------------------------ the geometry --

local function s16(data, at)                 -- `at` is 0-based
  local a, b = data:byte(at + 1, at + 2)
  if not b then return 0 end
  local value = a + b * 256
  if value >= 32768 then value = value - 65536 end
  return value
end

-- Gen4Ground's `placement`, as a row-major 3x4: scale, then an optional turn
-- about the vertical, then translate. (Gen4Ground keeps its own copy local.)
local function placementOf(object)
  local sx = (object.scaleX and object.scaleX ~= 0) and object.scaleX or 1
  local sy = (object.scaleY and object.scaleY ~= 0) and object.scaleY or 1
  local sz = (object.scaleZ and object.scaleZ ~= 0) and object.scaleZ or 1
  local yaw = object.rotY and object.rotY ~= 0 and math.rad(object.rotY) or nil
  if yaw then
    local c, s = math.cos(yaw), math.sin(yaw)
    return { c * sx, 0, s * sz, object.x or 0,
             0, sy, 0, object.y or 0,
             -s * sx, 0, c * sz, object.z or 0 }
  end
  return { sx, 0, 0, object.x or 0,
           0, sy, 0, object.y or 0,
           0, 0, sz, object.z or 0 }
end

local function newBucket(entry)
  return { entry = entry, verts = {}, map = {}, meshes = {}, lightPts = {} }
end

-- True when this UV lands on a glass texel of the mask (repeat wrap).
local function glassAt(entry, u, v)
  if not entry then return false end
  if entry.whole or not entry.mask then return true end
  u = u - math.floor(u)
  v = v - math.floor(v)
  if u < 0 then u = u + 1 end
  if v < 0 then v = v + 1 end
  local w, h = entry.w, entry.h
  local x = math.min(w - 1, math.max(0, math.floor(u * w)))
  local y = math.min(h - 1, math.max(0, math.floor(v * h)))
  local ok, _, _, _, a = pcall(entry.mask.getPixel, entry.mask, x, y)
  return ok and (a or 0) >= 0.5
end

local function clusterPoints(pts, radius)
  local out, used = {}, {}
  local r2 = radius * radius
  for i, p in ipairs(pts) do
    if not used[i] then
      local sx, sy, sz, n = p[1], p[2], p[3], 1
      used[i] = true
      for j = i + 1, #pts do
        if not used[j] then
          local q = pts[j]
          local dx, dz = q[1] - p[1], q[3] - p[3]
          if dx * dx + dz * dz <= r2 then
            used[j] = true
            sx, sy, sz, n = sx + q[1], sy + q[2], sz + q[3], n + 1
          end
        end
      end
      out[#out + 1] = { x = sx / n, y = sy / n, z = sz / n }
    end
  end
  return out
end

local function seal(bk)
  if #bk.verts == 0 then return end
  local mesh = Voxel3D.newMesh(bk.verts, bk.map)
  if mesh then bk.meshes[#bk.meshes + 1] = mesh end
  bk.verts, bk.map = {}, {}
end

-- One packed shape, placed, into its texture's bucket. Layout (Gen4ModelPack):
-- 16 bytes a vertex -- x y z u v as s16, then colour and normal -- and u16
-- indices into the shape's OWN vertex array.
local function buildingLightNames()
  local names = { c1_lamp01 = true, c1_lamp02 = true }
  local Lawn = optional("Gen4Lawn")
  if Lawn and Lawn.buildingLightIds then
    local ok, got = pcall(Lawn.buildingLightIds)
    if ok and type(got) == "table" then
      for k, v in pairs(got) do
        if v then names[tostring(k):lower()] = true end
      end
    end
  end
  return names
end

local function readTerrainPos(ground, s, posScale)
  local vdata = s.vertices
  if type(vdata) ~= "string" then
    vdata = ground:slice(s.vertexAt, s.vertexBytes)
  end
  local count = s.vertexCount or 0
  if not vdata or count < 3 then return nil end
  local stride = math.floor(#vdata / count)
  if stride < 10 then return nil end
  local pos = {}
  for i = 1, count do
    local at = (i - 1) * stride
    pos[i] = {
      s16(vdata, at) / FX16 * posScale,
      s16(vdata, at + 2) / FX16 * posScale,
      s16(vdata, at + 4) / FX16 * posScale,
    }
  end
  return pos
end

local function addShape(bk, s, posScale, m)
  local vdata, idata = s.vertices, s.indices
  if type(vdata) ~= "string" or type(idata) ~= "string" then return false end
  local count, tris = s.vertexCount or 0, s.triangleCount or 0
  if count < 3 or tris < 1 then return false end
  local stride = math.floor(#vdata / count)
  if stride ~= 14 and stride ~= 16 then return false end
  local tw, th = bk.entry.w, bk.entry.h
  local base = #bk.verts
  for i = 0, count - 1 do
    local at = i * stride
    local x = s16(vdata, at) / FX16 * posScale
    local y = s16(vdata, at + 2) / FX16 * posScale
    local z = s16(vdata, at + 4) / FX16 * posScale
    bk.verts[base + i + 1] = {
      m[1] * x + m[2] * y + m[3] * z + m[4],
      m[5] * x + m[6] * y + m[7] * z + m[8],
      m[9] * x + m[10] * y + m[11] * z + m[12],
      s16(vdata, at + 6) / UV_UNITS / tw,     -- texel -> 0..1 of THIS picture
      s16(vdata, at + 8) / UV_UNITS / th,     -- (no V flip: Gen4Model does none)
      Glass.SHADE, 0,
    }
  end
  for t = 0, tris * 3 - 1 do
    local a, b = idata:byte(t * 2 + 1, t * 2 + 2)
    if not b then break end
    bk.map[#bk.map + 1] = base + a + b * 256 + 1
  end
  -- One sample per triangle that actually hits the mask: the overlay's
  -- own verts, so the flame sits on the pane rather than on the land.
  for t = 0, tris - 1 do
    local a1, a2 = idata:byte(t * 6 + 1, t * 6 + 2)
    local b1, b2 = idata:byte(t * 6 + 3, t * 6 + 4)
    local c1, c2 = idata:byte(t * 6 + 5, t * 6 + 6)
    if not c2 then break end
    local va = bk.verts[base + a1 + a2 * 256 + 1]
    local vb = bk.verts[base + b1 + b2 * 256 + 1]
    local vc = bk.verts[base + c1 + c2 * 256 + 1]
    if va and vb and vc then
      local ua, va2 = va[4], va[5]
      local ub, vb2 = vb[4], vb[5]
      local uc, vc2 = vc[4], vc[5]
      if glassAt(bk.entry, ua, va2) or glassAt(bk.entry, ub, vb2)
         or glassAt(bk.entry, uc, vc2)
         or glassAt(bk.entry, (ua + ub + uc) / 3, (va2 + vb2 + vc2) / 3) then
        bk.lightPts[#bk.lightPts + 1] = {
          (va[1] + vb[1] + vc[1]) / 3,
          (va[2] + vb[2] + vc[2]) / 3,
          (va[3] + vb[3] + vc[3]) / 3,
        }
      end
    end
  end
  Glass.stats.shapes = Glass.stats.shapes + 1
  if #bk.verts > Glass.MAX_VERTS then seal(bk) end
  return true
end

-- Everything on one land that wears glass: { pieces = { {mesh, entry}, ... } }
local function harvestBuildingTerrain(ground, record, pts)
  local building = buildingLightNames()
  if not (record and record.shapes) then return end
  for _, s in ipairs(record.shapes) do
    local tex = lowered(s.texture or s.srcTexture)
    if building[tex] then
      local pos = readTerrainPos(ground, s, record.posScale or 1)
      if pos and #pos > 0 then
        local sx, sy, sz, n = 0, 0, 0, 0
        for _, p in ipairs(pos) do
          sx, sy, sz, n = sx + p[1], sy + p[2], sz + p[3], n + 1
        end
        -- lowest vertex as the wash origin so the pool sits on the wall, not in the sky
        local ymin = pos[1][2]
        for _, p in ipairs(pos) do
          if p[2] < ymin then ymin = p[2] end
        end
        pts[#pts + 1] = { sx / n, ymin + (sy / n - ymin) * 0.35, sz / n }
      end
    end
  end
end

local function buildLand(ground, land)
  local out = { pieces = {}, lights = {} }
  local record = ground.terrain and ground.terrain.chunks and ground.terrain.chunks[land]
  if not record then return out end
  local set = ground.buildingSet
  local objects
  if set and set.models then
    if type(ground.objectsFor) == "function" then
      local ok, list = pcall(ground.objectsFor, ground, land, record)
      objects = ok and list or nil
    end
    objects = objects or record.objects
  end

  local buckets, order = {}, {}
  for _, object in ipairs(objects or {}) do
    -- a fldeff prop is a sign or a mailbox; a live one is a moving platform
    if object.archive ~= "fldeff" and not object.live then
      local packed = set.models[(tonumber(object.model) or -1) + 1]
      if packed and packed.shapes then
        local m, posScale = nil, packed.posScale or 1
        for _, s in ipairs(packed.shapes) do
          if s.image then
            local entry = analyse(s.image, s.texture, s.material)
            if entry then
              m = m or placementOf(object)
              local bk = buckets[s.image]
              if not bk then
                bk = newBucket(entry)
                buckets[s.image] = bk
                order[#order + 1] = bk
              end
              addShape(bk, s, posScale, m)
            end
          end
        end
      end
    end
  end
  local pts, buildingPts = {}, {}
  for _, bk in ipairs(order) do
    seal(bk)
    for _, mesh in ipairs(bk.meshes) do
      out.pieces[#out.pieces + 1] = { mesh = mesh, entry = bk.entry }
    end
    for _, p in ipairs(bk.lightPts or {}) do
      pts[#pts + 1] = p
    end
  end
  harvestBuildingTerrain(ground, record, buildingPts)
  out.lights = clusterPoints(pts, Glass.LIGHT_CLUSTER)
  out.buildingLights = clusterPoints(buildingPts, 36)
  Glass.stats.lands = Glass.stats.lands + 1
  if Glass.LOG and #out.lights > 0 then
    note("lights:" .. tostring(land),
         "land %s: %d glass flame(s) from %d pane triangle(s)",
         tostring(land), #out.lights, #pts)
  end
  return out
end

-- ------------------------------------------------------- the land window --

-- ground -> { lands = { [land] = entry }, resident = n }. Per ground because
-- a map can edit a chunk's props (def.gen4ModelEdits), so two maps drawing the
-- same chunk can disagree about what stands on it.
local perGround = setmetatable({}, { __mode = "k" })
local window = {}
local tick = 0

local function release(entry)
  for _, p in ipairs(entry.pieces or {}) do
    if p.mesh and p.mesh.release then pcall(p.mesh.release, p.mesh) end
  end
end

local function prepare(ground, view)
  local grid, px, half = ground.grid, ground.chunkPx, ground.half
  if not (grid and px and half and ground.terrain) then window = {} return end
  local cache = perGround[ground]
  if not cache then cache = { lands = {}, resident = 0 } perGround[ground] = cache end

  local camCx, camCy = math.floor(view.x / px), math.floor(view.z / px)
  local qx, qy = math.floor(view.x * 4 / px), math.floor(view.z * 4 / px)
  if window.done and window.ground == ground and window.qx == qx and window.qy == qy
     and window.version == Glass.version then
    return
  end
  tick = tick + 1

  local want = {}
  local W = Glass.WINDOW
  for cy = camCy - W, camCy + W do
    for cx = camCx - W, camCx + W do
      if cx >= 0 and cy >= 0 and cx < grid.width and cy < grid.height then
        local land = grid.land[cy * grid.width + cx + 1]
        if land then
          local dx, dz = cx - camCx, cy - camCy
          want[#want + 1] = { dx * dx + dz * dz, cx, cy, land }
        end
      end
    end
  end
  table.sort(want, function(a, b) return a[1] < b[1] end)

  local builds, pending, list = 0, 0, {}
  for _, w in ipairs(want) do
    local land = w[4]
    local entry = cache.lands[land]
    if not entry then
      if builds < Glass.BUILDS_PER_FRAME and Budget.allow(false) then
        builds = builds + 1
        local t0 = clock()
        local ok, built = pcall(buildLand, ground, land)
        Budget.charge(t0, "glass")
        if not ok then
          note("build", "a land failed to build and was skipped: %s", tostring(built))
          built = { pieces = {} }
        end
        cache.lands[land] = built
        cache.resident = cache.resident + 1
        entry = built
      else
        pending = pending + 1
      end
    end
    if entry then
      entry.used = tick
      if #entry.pieces > 0 or #(entry.lights or {}) > 0 then
        list[#list + 1] = { entry = entry, x = w[2] * px + half, z = w[3] * px + half }
      end
    end
  end

  -- evict the oldest lands past the cap
  if cache.resident > Glass.MAX_RESIDENT then
    local old = {}
    for land, e in pairs(cache.lands) do
      if e.used ~= tick then old[#old + 1] = { e.used or 0, land, e } end
    end
    table.sort(old, function(a, b) return a[1] < b[1] end)
    local i = 1
    while cache.resident > Glass.MAX_RESIDENT and old[i] do
      release(old[i][3])
      cache.lands[old[i][2]] = nil
      cache.resident = cache.resident - 1
      i = i + 1
    end
  end

  window = { ground = ground, qx = qx, qy = qy, list = list,
             done = (pending == 0), version = Glass.version }
end

-- ------------------------------------------------------------ the lighting --

local glint = { x = nil, z = nil, phase = 0, amp = 0 }

-- A reflection is something the viewpoint does (VoxelScene.glintStep): the
-- phase is fed by the camera's own travel, the strength dies when it stops.
local function glintStep(x, z)
  local dist = 0
  if glint.x then dist = math.abs(x - glint.x) + math.abs(z - glint.z) end
  glint.x, glint.z = x, z
  if dist > 64 then dist = 0 end            -- a warp is not travel
  glint.phase = (glint.phase + dist * Glass.GLINT_RATE) % (2 * math.pi)
  if dist > 0.05 then
    glint.amp = math.min(1, glint.amp + Glass.GLINT_IN)
  else
    glint.amp = math.max(0, glint.amp - Glass.GLINT_OUT)
  end
end

-- Under the open sky? Gen4Spawn.isOutdoor is the real answer on Platinum
-- (Map.isOutdoor reads Gen 1/2 header fields); `ground.outdoors` is the
-- engine's own reading of the same fact.
local function outdoorNow(ground)
  if ground.outdoors == false then return false end
  local map = ground.terrariumMap
  local Spawn = optional("Gen4Spawn")
  if map and Spawn and Spawn.isOutdoor then
    local ok, r = pcall(Spawn.isOutdoor, map)
    if ok then return r and true or false end
  end
  return ground.outdoors == true
end

-- -------------------------------------------------------------------- draw --

function Glass.draw(scene)
  if not (Glass.enabled and DayNight and scene and scene.ground and scene.view) then return end
  local ground, view = scene.ground, scene.view
  if not outdoorNow(ground) then return end

  glintStep(scene.eye[1], scene.eye[3])

  -- built whatever the hour, so the first dusk does not hitch the frame
  prepare(ground, view)
  local list = window.list
  if not list or #list == 0 then return end

  local okN, night = pcall(DayNight.windowLight)
  night = okN and tonumber(night) or 0
  local wantNight = night > Glass.NIGHT_MIN
  local wantGlint = Glass.DAY_GLINT and glint.amp > Glass.GLINT_MIN
  if not (wantNight or wantGlint) then return end     -- by day: nothing drawn

  local lamp
  do
    local okL, c = pcall(DayNight.lampColor)
    lamp = okL and c or nil
  end

  local Mat4 = V.require("Mat4")
  local visible = scene.sphereVisible
  local radius = (ground.chunkPx or 512) * 0.72 + 80

  Voxel3D.seams(false)
  Voxel3D.glass(true)
  scene.blend()
  if wantNight and lamp then
    Voxel3D.flatten(lamp, math.min(1, 0.50 + 0.50 * night))
  end
  local drawn = 0
  for _, item in ipairs(list) do
    if (not visible) or visible(item.x, 0, item.z, radius) then
      local model = item.model
      if not model then
        model = Mat4.translate(item.x, 0, item.z)
        item.model = model
      end
      for _, piece in ipairs(item.entry.pieces) do
        -- the glass-only copy is both the texture (non-glass texels are alpha 0
        -- and discarded) and the mask (alpha 1 on every pane texel)
        Voxel3D.glassPass(piece.entry.image, wantNight and night or 0, lamp,
                          glint.phase, wantGlint and glint.amp or 0)
        Voxel3D.draw(piece.mesh, piece.entry.image, model, Glass.PULL, nil, 0, false)
        drawn = drawn + 1
      end
    end
  end
  if wantNight and lamp then Voxel3D.flatten(nil) end
  scene.opaque()
  Voxel3D.glassPass(nil)                  -- the blank mask and the scene's own light
  Voxel3D.seams(true)
  Voxel3D.glass(true)
  
  -- Log once per frame when glass is drawn
  if drawn > 0 and Glass.LOG then
    note("draw", "drew %d glass piece(s) at night=%.2f", drawn, night)
  end
end

-- Point lights from the glass MASK: each clustered pane, in the same format
-- as StreetLamps.lights(). The shader hangs the flame `lampHeight` above
-- lamp.y, so y is the pane height minus that offset -- otherwise a window
-- would light the sky 19 units above the glass.
function Glass.lights(wx, wz, limit)
  if not (Glass.enabled and DayNight) then return {} end

  local okN, night = pcall(DayNight.windowLight)
  night = okN and tonumber(night) or 0
  if night <= Glass.NIGHT_MIN then return {} end

  local list = window.list
  if not list or #list == 0 then return {} end

  wx, wz = tonumber(wx) or 0, tonumber(wz) or 0
  limit = math.max(1, math.min(Glass.LIGHT_LIMIT, limit or Glass.LIGHT_LIMIT))
  local flame = Voxel3D.lampHeight or Voxel3D.LAMP_HEIGHT or 19

  local out = {}
  for _, item in ipairs(list) do
    for _, p in ipairs(item.entry.lights or {}) do
      local x, z = p.x + item.x, p.z + item.z
      local dx, dz = x - wx, z - wz
      out[#out + 1] = {
        x = x,
        y = (p.y or 0) - flame,
        z = z,
        radius = Glass.LIGHT_RADIUS,
        power = night * 0.75,
        d2 = dx * dx + dz * dz,
      }
    end
  end

  table.sort(out, function(a, b) return a.d2 < b.d2 end)
  for i = #out, limit + 1, -1 do out[i] = nil end
  return out
end

-- Building-wall washes for Gen4Tint. Not glass panes (those are overlay
-- flatten) and not street-lamp orbs -- a wide dim pool on the facade.
function Glass.screenLights(wx, wz)
  if not (Glass.enabled and DayNight) then return {} end
  local okN, night = pcall(DayNight.windowLight)
  night = okN and tonumber(night) or 0
  if night <= Glass.NIGHT_MIN then return {} end
  local list = window.list
  if not list or #list == 0 then return {} end
  wx, wz = tonumber(wx) or 0, tonumber(wz) or 0
  local out = {}
  for _, item in ipairs(list) do
    for _, p in ipairs(item.entry.buildingLights or {}) do
      local x, z = p.x + item.x, p.z + item.z
      local dx, dz = x - wx, z - wz
      out[#out + 1] = {
        x = x, y = p.y or 0, z = z,
        radius = 140,
        power = night * 0.55,
        kind = "building",
        d2 = dx * dx + dz * dz,
      }
    end
  end
  table.sort(out, function(a, b) return a.d2 < b.d2 end)
  for i = #out, 16, -1 do out[i] = nil end
  return out
end

-- Called from Gen4Bridge before the scene opens, so the first night frame
-- already has pane lights (draw's prepare would otherwise run too late).
function Glass.collectLights(scene)
  if not (scene and scene.ground and scene.view) then return {} end
  if not outdoorNow(scene.ground) then return {} end
  prepare(scene.ground, scene.view)
  return Glass.lights(scene.view.x, scene.view.z)
end

-- Drop every GPU object (graphics reset, mod reload). The decisions about which
-- textures hold glass are facts about the art and survive; the images and the
-- meshes are rebuilt on demand.
function Glass.invalidate()
  for _, cache in pairs(perGround) do
    for _, e in pairs(cache.lands) do release(e) end
  end
  perGround = setmetatable({}, { __mode = "k" })
  for path, entry in pairs(textures) do
    if entry and entry.image and entry.image.release then
      pcall(entry.image.release, entry.image)
    end
    textures[path] = nil
  end
  window = {}
  Glass.version = Glass.version + 1
end

-- Read-only, for the console / a test: the glass texture verdicts so far.
function Glass.report()
  local out = {}
  for path, entry in pairs(textures) do
    if entry then out[#out + 1] = { path = path, w = entry.w, h = entry.h, texels = entry.texels } end
  end
  table.sort(out, function(a, b) return a.path < b.path end)
  return out
end

return Glass
