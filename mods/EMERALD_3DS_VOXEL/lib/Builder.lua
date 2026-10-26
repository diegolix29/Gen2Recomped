-- A map instance's geometry, built the way Emerald 3DS builds a chunk
-- (voxel_mesh_builder.c, voxel_relief.c, voxel_building.c, voxel_tree.c,
-- voxel_sign.c): the ground pass cell by cell, then the trees, then the
-- buildings.  Units are cells (16 px); X east, Y up, Z south; coordinates are
-- MAP-LOCAL (the renderer translates an instance by its origin).
--
-- Three meshes come out, one per texture: the ground on the pair's atlas,
-- the trees on the tree sheet, and the buildings on the layout's page.
-- Shading is baked per vertex exactly as the 3DS bakes it: the drawn face
-- constants, the sun's facing term, and outdoors a cast-shadow ray marched
-- toward a fixed north-west sun against the trees' crowns, the models'
-- heights and the drawn relief.

local V = ...
local Data = V.require("Data")
local Atlas = V.require("Atlas")
local Generic = V.require("Generic")
local Trees = V.require("Trees")
local Bin = V.require("Bin")

local Builder = {}

local floor, max, min, sqrt = math.floor, math.max, math.min, math.sqrt

local FORMAT = {
  { "VertexPosition", "float", 3 },
  { "VertexTexCoord", "float", 2 },
  { "VertexColor", "byte", 4 },
}
Builder.FORMAT = FORMAT

-- face shades (voxel_mesh_builder.h)
local SHADE_TOP, SHADE_SOUTH, SHADE_NORTH, SHADE_WEST, SHADE_EAST = 1.00, 0.60, 0.50, 0.65, 0.55

-- the default sun (gVoxelSun) and the light model (voxel_lighting.c)
local SUN_DX, SUN_DZ, AMBIENT = 0.85, 0.55, 0.70

-- Emerald metatile behaviours the ground pass asks about
local WATER = { [0x10] = true, [0x11] = true, [0x12] = true, [0x14] = true, [0x15] = true,
                [0x16] = true, [0x17] = true, [0x18] = true, [0x19] = true, [0x1A] = true,
                [0x22] = true, [0x28] = true, [0x2A] = true, [0x2B] = true, [0x50] = true,
                [0x51] = true, [0x52] = true, [0x53] = true }
local MB_COUNTER = 0x80
-- the behaviours Emerald 3DS stands up as a television (BehaviorShape):
-- PC, cable box, television, secret base PC
local FURNITURE = { [0x83] = true, [0x84] = true, [0x86] = true, [0xB0] = true }

-- ------------------------------------------------------------ buffers --

local function newBuf() return { n = 0 } end

local function vert(buf, x, y, z, u, v, s)
  local c = s > 1 and 1 or (s < 0 and 0 or s)
  buf.n = buf.n + 1
  buf[buf.n] = { x, y, z, u, v, c, c, c, 1 }
end

local function tri(buf, a, b, c)
  vert(buf, a[1], a[2], a[3], a[4], a[5], a[6])
  vert(buf, b[1], b[2], b[3], b[4], b[5], b[6])
  vert(buf, c[1], c[2], c[3], c[4], c[5], c[6])
end

local function quad(buf, a, b, c, d)
  tri(buf, a, b, c)
  tri(buf, a, c, d)
end

-- Where a map's points are drawn north-south (voxel_relief.c, dev): as far
-- south as they stand high in the world, so the map's base counts as well
-- as its relief, and through its south seam's ease.  Set for one build.
local zMap = nil

local function toMesh(buf)
  if buf.n == 0 then return nil end
  buf.n = nil
  if zMap then
    for i = 1, #buf do buf[i][3] = zMap(buf[i][3]) end
  end
  local ok, mesh = pcall(love.graphics.newMesh, FORMAT, buf, "triangles", "static")
  return ok and mesh or nil
end

-- --------------------------------------------------------------- light --

local function faceTerm(nx, ny, nz)
  local len = sqrt(nx * nx + ny * ny + nz * nz)
  if len < 1e-9 then return 1 end
  local f = (ny - SUN_DX * nx - SUN_DZ * nz) / len
  if f <= 0 then return AMBIENT end
  if f >= 1 then return 1 end
  return AMBIENT + (1 - AMBIENT) * f
end
Builder.faceTerm = faceTerm

-- The model shade (VoxelLighting_ModelShade): the stored drawn shade says
-- which side of an inconsistently wound triangle is the outside.
local function modelShade(ax, ay, az, bx, by, bz, cx, cy, cz, drawn)
  local ux, uy, uz = bx - ax, by - ay, bz - az
  local vx, vy, vz = cx - ax, cy - ay, cz - az
  local nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
  local flip
  if math.abs(drawn - 0.90) < 0.02 then flip = false
  elseif math.abs(drawn - 0.80) < 0.02 then flip = nx > 0
  elseif math.abs(drawn - 0.72) < 0.02 then flip = nx < 0
  elseif math.abs(drawn - 0.66) < 0.02 then flip = ny + nz > 0
  else flip = ny + nz < 0 end
  if flip then nx, ny, nz = -nx, -ny, -nz end
  return faceTerm(nx, ny, nz)
end

-- ---------------------------------------------------------------- trees --

-- VoxelTree_Part: -1 none, 0..3 large-tree quadrant (row*2+col), 4 small
local LARGE = { [0x1D4] = 0, [0x1D6] = 0, [0x1D5] = 1, [0x1D7] = 1,
                [0x1DC] = 2, [0x1DE] = 2, [0x1E4] = 2, [0x1E6] = 2,
                [0x1DD] = 3, [0x1DF] = 3, [0x1E5] = 3, [0x1E7] = 3,
                [0x1EC] = 2, [0x1ED] = 3, [0x1F3] = 2, [0x1F2] = 3, [0x1FC] = 0, [0x1FD] = 1,
                [0x016] = 4, [0x017] = 4, [0x0C6] = 4, [0x0C7] = 4, [0x1F4] = 4, [0x1F5] = 4 }
local function treePart(dewford, id)
  if id >= 0x200 then
    if dewford and (id == 0x23A or id == 0x243) then return 4 end
    return -1
  end
  local p = LARGE[id]
  return p == nil and -1 or p
end

local GROUND = { [0x1C6] = 0x00D, [0x1C7] = 0x00D, [0x1CE] = 0x001, [0x1CF] = 0x001,
                 [0x00E] = 0x001, [0x00F] = 0x001, [0x040] = 0x001, [0x01D] = 0x002,
                 [0x025] = 0x00D, [0x02D] = 0x0A1, [0x035] = 0x170, [0x193] = 0x170, [0x0CE] = 0x091 }
local function treeGround(dewford, id)
  if id >= 0x200 then
    if dewford and id == 0x239 then return 0x124 end
    return id
  end
  return GROUND[id] or id
end
Builder.treePart, Builder.treeGround = treePart, treeGround

-- ------------------------------------------------------------ the build --

-- `map` is the engine's Map (blockAt, def, renderer); returns the instance
-- record the renderer draws, or nil when the map cannot be built.
function Builder.build(map)
  local def = map and map.def
  local layout = def and def.layoutId
  if not layout then return nil end
  local atlas = Atlas.forMap(map)
  if not atlas then return nil end
  local L = Data.layouts and Data.layouts[layout] or {}
  local W, H = def.width or 0, def.height or 0
  local outdoor = def.outdoor ~= false and def.mapType ~= "MAP_TYPE_INDOOR"
  if def.outdoor == false then outdoor = false end
  local trees = outdoor and L.primary == "gTileset_General"
  local dewford = L.secondary == "gTileset_Dewford"
  Generic.checkOverride(layout)
  local RL = Data.reliefLayout(layout)
  local base = RL and RL.base or 0
  local record = atlas.record

  local function block(x, y)
    if x < 0 or y < 0 or x >= W or y >= H then return nil end
    local ok, id = pcall(map.blockAt, map, x, y)
    return ok and id or nil
  end
  local function behaviour(id)
    local t = record.tiles
    if not (t and t.attributes) then return 0 end
    local ok, b = pcall(t.attributes, t, id)
    return ok and b or 0
  end
  local function variantFits(var) return Atlas.variantFits(var, layout) end

  -- a map Emerald 3DS has not modelled: stood up here (lib/Generic.lua)
  local fortree = outdoor and L.secondary == "gTileset_Fortree"
  Data.generic[layout] = nil
  local cave = def.mapType == "UNDERGROUND" or def.mapType == "MAP_TYPE_UNDERGROUND"
  if Generic.applies(layout, fortree, cave) then
    local okG, cells = pcall(Generic.build, layout, W, H, {
      block = block, behaviour = behaviour,
      walkable = function(x, y)
        local ok, w = pcall(map.isWalkableCell, map, x, y)
        return ok and w or false
      end,
      owned = function(x, y, id) return Data.buildingCell(layout, x, y, id, variantFits) ~= nil end,
      fortree = fortree,
      roleAt = Generic.pyramidRoles(map, W, H),
      inPlaceWalls = def.id == "MAP_G26_N26",
      elevation = def.elevationCells and function(x, y)
        if x < 0 or y < 0 or x >= W or y >= H then return 0 end
        return def.elevationCells[y * W + x + 1] or 0
      end or nil,
    })
    if okG then Data.generic[layout] = cells else V.log("generic relief failed: %s", tostring(cells)) end
  end

  local function cellLift(x, y)
    local g, d = Data.reliefCell(layout, x, y)
    if not g then return 0, 0 end
    return g[12] / 16, d[12] / 16
  end

  -- ---------------------------------------------- casters (outdoor sun) --
  local caster = {}         -- y*1024+x -> function(px, py, pz) occludes
  local function addCaster(x, y, f) caster[y * 1024 + x] = f end
  local buildingTop = {}

  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local id = block(x, y)
      if id then
        local ground, top = Data.buildingCell(layout, x, y, id, variantFits)
        if ground then
          local lift = cellLift(x, y)
          buildingTop[y * 1024 + x] = true
          local roof = base + lift + top
          addCaster(x, y, function(_, py) return py < roof end)
        elseif trees then
          local p = treePart(dewford, id)
          if p >= 0 then
            local lift = cellLift(x, y)
            local cx, cy, cz, rx, ry, rz
            if p == 4 then
              cx, cy, cz, rx, ry, rz = x + 0.5, 0.80, y + 0.35, 0.48, 0.62, 0.55
            else
              cx, cy, cz, rx, ry, rz = x - (p % 2) + 1, 0.95, y - floor(p / 2) + 0.65, 0.95, 0.67, 0.65
            end
            cy = cy + base + lift
            addCaster(x, y, function(px, py, pz)
              local a, b, c = (px - cx) / rx, (py - cy) / ry, (pz - cz) / rz
              return a * a + b * b + c * c < 1
            end)
          end
        end
      end
    end
  end
  if RL and RL.drawn then
    for y = 0, H - 1 do
      for x = 0, W - 1 do
        if not caster[y * 1024 + x] then
          local g = Data.reliefCell(layout, x, y)
          if g then
            addCaster(x, y, function(px, py, pz)
              local fx, fy = (px - x) * 4, (pz - y) * 4
              local i, j = min(3, floor(fx)), min(3, floor(fy))
              fx, fy = fx - i, fy - j
              local a = g[j * 5 + i] * (1 - fx) + g[j * 5 + i + 1] * fx
              local b = g[(j + 1) * 5 + i] * (1 - fx) + g[(j + 1) * 5 + i + 1] * fx
              return py < base + (a * (1 - fy) + b * fy) / 16
            end)
          end
        end
      end
    end
  end

  local function occluded(px, py, pz)
    local f = caster[floor(pz) * 1024 + floor(px)]
    return f ~= nil and px >= 0 and pz >= 0 and px < W and pz < H and f(px, py, pz)
  end
  local function lit(px, py, pz)
    for s = 1, 32 do
      local t = s / 4
      if occluded(px - SUN_DX * t, py + t + 0.08, pz - SUN_DZ * t) then return false end
    end
    return true
  end
  -- VoxelLighting_Sample: sun or ambient, times the contact darkening
  local function sample(px, py, pz)
    if not outdoor then return 1 end
    local contact = 1
    if py - base <= 0.41 then
      local n = 0
      if occluded(px + 0.28, py + 0.3, pz) then n = n + 1 end
      if occluded(px - 0.28, py + 0.3, pz) then n = n + 1 end
      if occluded(px, py + 0.3, pz + 0.28) then n = n + 1 end
      if occluded(px, py + 0.3, pz - 0.28) then n = n + 1 end
      contact = 1 - 0.035 * n
    end
    return (lit(px, py, pz) and 1 or AMBIENT) * contact
  end

  local ground, treeBuf, buildBuf = newBuf(), newBuf(), newBuf()

  -- A flat top, each corner lit by its own sample: the soft-edged shadow.
  local function top(buf, x, z, y, u0, v0, u1, v1, inset, shift)
    inset, shift = inset or 0, shift or 0
    local x0, x1, z0, z1 = x + inset, x + 1 - inset, z + inset + shift, z + 1 - inset + shift
    local function c(px, pz, u, v)
      return { px, y, pz, u, v, outdoor and sample(px, y, pz) or SHADE_TOP }
    end
    quad(buf, c(x0, z0, u0, v0), c(x1, z0, u1, v0), c(x1, z1, u1, v1), c(x0, z1, u0, v1))
  end

  -- an upright face, lit by the sun's facing term only
  local function wall(buf, p, shadeConst, nx, nz)
    local s = outdoor and (faceTerm(nx, 0, nz) * (lit(
      (p[1][1] + p[3][1]) / 2 + nx * 0.05, (p[1][2] + p[3][2]) / 2, (p[1][3] + p[3][3]) / 2 + nz * 0.05)
      and 1 or AMBIENT)) or shadeConst
    for i = 1, 4 do p[i][6] = s end
    quad(buf, p[1], p[2], p[3], p[4])
  end

  local function uvOf(id) return Atlas.uv(atlas, id) end

  -- ------------------------------------------------------- voxel signs --
  -- VoxelSign_EmitSign: the opaque pixels of the mask as a 2 px board, each
  -- pixel row merged into runs, faces only where the neighbour pixel is empty.
  local function emitSign(rec, x, y, lift, shift)
    local u0, v0, u1, v1 = uvOf(block(x, y) or 0)
    if not u0 then return end
    local rows, uvRow = {}, {}
    local du, dv = (u1 - u0) / 16, (v1 - v0) / 16
    local wz = y
    if rec.hasHead and y > 0 then
      local hu0, hv0 = uvOf(block(x, y - 1) or 0)
      if hu0 then
        for r = 0, 15 do rows[r] = rec.head[r]; uvRow[r] = { hu0, hv0 + r * dv } end
        for r = 0, 15 do rows[r + 16] = rec.rows[r]; uvRow[r + 16] = { u0, v0 + r * dv } end
        wz = y - 1
      end
    end
    if not rows[0] then
      for r = 0, 15 do rows[r] = rec.rows[r]; uvRow[r] = { u0, v0 + r * dv } end
    end
    local n = #rows + 1
    local maxY = 0
    for r = 0, n - 1 do if rows[r] ~= 0 then maxY = r end end
    local depth = 2 / 16
    local za = wz + floor(maxY / 8) * 0.5 + 0.25 - depth * 0.5 + shift
    local zb = za + depth
    local light = outdoor and sample(x + 0.5, base + lift + 0.5, wz + 0.5 + shift) or 1
    local function bit(r, c)
      if r < 0 or r >= n or c < 0 or c > 15 then return false end
      return floor(rows[r] / 2 ^ c) % 2 == 1
    end
    for r = 0, n - 1 do
      local c = 0
      while c <= 15 do
        if bit(r, c) then
          local c1 = c
          while c1 + 1 <= 15 and bit(r, c1 + 1) do c1 = c1 + 1 end
          local ya = base + lift + (maxY - r) / 16
          local yb = ya + 1 / 16
          local xa, xb = x + c / 16, x + (c1 + 1) / 16
          local ru, rv = uvRow[r][1], uvRow[r][2]
          local ua, ub, va, vb = ru + c * du, ru + (c1 + 1) * du, rv, rv + dv
          local function s(k) return light > AMBIENT and light * k or light * min(k, 1) end
          -- front (south) and back (north)
          quad(ground, { xa, ya, zb, ua, vb, s(1) }, { xb, ya, zb, ub, vb, s(1) },
                       { xb, yb, zb, ub, va, s(1) }, { xa, yb, zb, ua, va, s(1) })
          quad(ground, { xb, ya, za, ua, vb, s(0.68) }, { xa, ya, za, ub, vb, s(0.68) },
                       { xa, yb, za, ub, va, s(0.68) }, { xb, yb, za, ua, va, s(0.68) })
          -- the run's two ends
          quad(ground, { xa, ya, za, ua, vb, s(0.78) }, { xa, ya, zb, ua, vb, s(0.78) },
                       { xa, yb, zb, ua, va, s(0.78) }, { xa, yb, za, ua, va, s(0.78) })
          quad(ground, { xb, ya, zb, ub, vb, s(0.78) }, { xb, ya, za, ub, vb, s(0.78) },
                       { xb, yb, za, ub, va, s(0.78) }, { xb, yb, zb, ub, va, s(0.78) })
          -- top and bottom, pixel by pixel where the row above / below is empty
          for k = c, c1 do
            local pu, pu1 = ru + k * du, ru + (k + 1) * du
            local px0, px1 = x + k / 16, x + (k + 1) / 16
            if not bit(r - 1, k) then
              quad(ground, { px0, yb, za, pu, va, s(1) }, { px1, yb, za, pu1, va, s(1) },
                           { px1, yb, zb, pu1, vb, s(1) }, { px0, yb, zb, pu, vb, s(1) })
            end
            if not bit(r + 1, k) then
              quad(ground, { px0, ya, zb, pu, vb, s(0.55) }, { px1, ya, zb, pu1, vb, s(0.55) },
                           { px1, ya, za, pu1, va, s(0.55) }, { px0, ya, za, pu, va, s(0.55) })
            end
          end
          c = c1 + 1
        else
          c = c + 1
        end
      end
    end
  end

  -- ------------------------------------------------------------ relief --
  local function emitRelief(x, y, g, d, id, dl)
    local u0, v0, u1, v1 = uvOf(id)
    if not u0 then return end
    local base = base + (dl or 0)
    local slope = false
    for i = 1, 24 do if g[i] ~= g[0] or d[i] ~= d[0] then slope = true break end end
    if not slope then
      local h, dz = base + g[0] / 16, d[0] / 16
      top(ground, x, y, h, u0, v0, u1, v1, 0, dz)
      return
    end
    -- per-lattice-point light: the slope's own facing over +-2 points
    local shade = {}
    for c = 0, 4 do
      for a = 0, 4 do
        local i = c * 5 + a
        local px, py, pz = x + a / 4, base + g[i] / 16, y + c / 4 + d[i] / 16
        if outdoor then
          local aL, aR = max(0, a - 2), min(4, a + 2)
          local cU, cD = max(0, c - 2), min(4, c + 2)
          local hu = (g[c * 5 + aR] - g[c * 5 + aL]) / 16 / ((aR - aL) / 4)
          local hv = (g[cD * 5 + a] - g[cU * 5 + a]) / 16 / ((cD - cU) / 4)
          local f = faceTerm(-hu, 1 + hv, -hv)
          shade[i] = (lit(px, py, pz) and f or AMBIENT)
        else
          shade[i] = 1
        end
      end
    end
    local DI, DJ = { 0, 1, 1, 0 }, { 0, 0, 1, 1 }
    for j = 0, 3 do
      for i = 0, 3 do
        local p = {}
        for k = 1, 4 do
          local a, c = i + DI[k], j + DJ[k]
          local idx = c * 5 + a
          p[k] = { x + a / 4, base + g[idx] / 16, y + c / 4 + d[idx] / 16,
                   u0 + (u1 - u0) * a / 4, v0 + (v1 - v0) * c / 4, shade[idx] }
        end
        if g[j * 5 + i] == g[(j + 1) * 5 + i + 1] and g[j * 5 + i + 1] ~= g[(j + 1) * 5 + i] then
          quad(ground, p[2], p[3], p[4], p[1])
        else
          quad(ground, p[1], p[2], p[3], p[4])
        end
      end
    end
  end

  -- Cliff walls on the south, west and east edges where this cell's lattice
  -- edge stands above the neighbour's (EmitCliffWalls, first version: the
  -- face metatile on the south, the cell's own art down the sides).
  local function emitCliffs(x, y, g, d, id)
    local cut = Data.cutAt(layout, x, y)
    local faceId = (cut and cut.wall < 0xFFFE) and cut.wall or id
    local fu0, fv0, fu1, fv1 = uvOf(faceId)
    local u0, v0, u1, v1 = uvOf(id)
    if not (fu0 and u0) then return end
    -- south
    local gs, ds = Data.reliefCell(layout, x, y + 1)
    for a = 0, 3 do
      local i0, i1 = 20 + a, 21 + a
      local n0 = gs and gs[a] or 0
      local n1 = gs and gs[a + 1] or 0
      local drop = max(g[i0] - n0, g[i1] - n1) / 16
      -- (a stood-up map closes its last row too: nothing south covers it)
      if drop > 0.01 and (y + 1 < H or Data.generic[layout]) then
        local nd0, nd1 = ds and ds[a] or 0, ds and ds[a + 1] or 0
        local xa, xb = x + a / 4, x + (a + 1) / 4
        local vSpan = (fv1 - fv0) * min(1, drop)
        local ua, ub = fu0 + (fu1 - fu0) * a / 4, fu0 + (fu1 - fu0) * (a + 1) / 4
        wall(ground, {
          { xa, base + n0 / 16, y + 1 + nd0 / 16, ua, fv0 + vSpan, 0 },
          { xb, base + n1 / 16, y + 1 + nd1 / 16, ub, fv0 + vSpan, 0 },
          { xb, base + g[i1] / 16, y + 1 + d[i1] / 16, ub, fv0, 0 },
          { xa, base + g[i0] / 16, y + 1 + d[i0] / 16, ua, fv0, 0 } }, SHADE_SOUTH, 0, 1)
      end
    end
    -- west and east: the drawing's edge column hung down
    for side = 0, 1 do
      local nx = side == 0 and x - 1 or x + 1
      local gn, dn = Data.reliefCell(layout, nx, y)
      local col, ncol = side == 0 and 0 or 4, side == 0 and 4 or 0
      local eu = side == 0 and (u0 + (u1 - u0) / 32) or (u1 - (u1 - u0) / 32)
      for c = 0, 3 do
        local i0, i1 = c * 5 + col, (c + 1) * 5 + col
        local n0 = gn and gn[c * 5 + ncol] or 0
        local n1 = gn and gn[(c + 1) * 5 + ncol] or 0
        if max(g[i0] - n0, g[i1] - n1) > 1 and nx >= 0 and nx < W then
          local px = side == 0 and x or x + 1
          local va, vb = v0 + (v1 - v0) * c / 4, v0 + (v1 - v0) * (c + 1) / 4
          local nd0, nd1 = dn and dn[c * 5 + ncol] or 0, dn and dn[(c + 1) * 5 + ncol] or 0
          wall(ground, {
            { px, base + n0 / 16, y + c / 4 + nd0 / 16, eu, va, 0 },
            { px, base + n1 / 16, y + (c + 1) / 4 + nd1 / 16, eu, vb, 0 },
            { px, base + g[i1] / 16, y + (c + 1) / 4 + d[i1] / 16, eu, vb, 0 },
            { px, base + g[i0] / 16, y + c / 4 + d[i0] / 16, eu, va, 0 } },
            side == 0 and SHADE_WEST or SHADE_EAST, side == 0 and -1 or 1, 0)
        end
      end
    end
  end

  -- ------------------------------------------------------------- trees --
  local TU = Trees.U
  local function treeTop(x, y, lift, shift, tx, ty)
    local yy = base + lift
    top(treeBuf, x, y, yy, TU(tx), TU(ty), TU(tx + 16), TU(ty + 16), 0, shift)
  end
  local function crownCard(x, y, col, row, lift, shift)
    local u0, u1 = TU(col * 16), TU(col * 16 + 16)
    local v0, v1 = TU(row * 18), TU(row * 18 + 18)
    local rise, run, baseH = 1.723600, 1.446272, -0.10
    local baseZ = y - row + 1.35 + shift
    local t, b = 1.0 - row * 0.5, 0.5 - row * 0.5
    local y0 = base + lift + baseH
    local light = outdoor and sample(x + 0.5, y0 + 1.2, baseZ - 0.6) or 1
    local s = light > AMBIENT and light * faceTerm(0, 1 + 0.64, 0.77) or light
    quad(treeBuf, { x, y0 + t * rise, baseZ - t * run, u0, v0, s },
                  { x + 1, y0 + t * rise, baseZ - t * run, u1, v0, s },
                  { x + 1, y0 + b * rise, baseZ - b * run, u1, v1, s },
                  { x, y0 + b * rise, baseZ - b * run, u0, v1, s })
  end
  local function emitTree(x, y, part, lift, shift, inside)
    if part == 4 then
      local cx, cy = dewford and 64 or 32, dewford and 0 or 32
      treeTop(x, y, lift, shift, cx + 16, cy)
      local role = Data.roleAt(layout, x, y - 2)
      local rock = role == Data.ROLE.CLIFF or role == Data.ROLE.SHELF
      local rise, run, baseH = 1.532089, rock and 0.8 or 1.285575, -0.10
      local baseZ = y + (dewford and 0.975 or 0.825) + shift
      local y0 = base + lift + baseH
      local light = outdoor and sample(x + 0.5, y0 + 1.0, baseZ - 0.5) or 1
      local s = light > AMBIENT and light * faceTerm(0, 1.77, 0.64) or light
      quad(treeBuf, { x, y0 + rise, baseZ - run, TU(cx), TU(cy), s },
                    { x + 1, y0 + rise, baseZ - run, TU(cx + 16), TU(cy), s },
                    { x + 1, y0, baseZ, TU(cx + 16), TU(cy + 32), s },
                    { x, y0, baseZ, TU(cx), TU(cy + 32), s })
      return
    end
    local col, row = part % 2, floor(part / 2)
    treeTop(x, y, lift, shift, 32 + col * 16, row * 16)
    crownCard(x, y, col, row, lift, shift)
    -- the tree's other row drawn over by the secondary tileset (a hedge, a
    -- roof): this row adds that row's card so the crown is not cut in two
    if inside then
      local oy = row == 0 and y + 1 or y - 1
      local other = block(x, oy)
      if other and treePart(dewford, other) < 0 and oy >= 0 and oy < H then
        crownCard(x, oy, col, 1 - row, lift, shift)
      end
    end
  end

  local genericWalls
  -- the floors laid on under a stood-up map's rock (lib/Generic.lua)
  local G = Data.generic[layout]
  for _, f in ipairs(G and G.fills or {}) do
    local fid = block(f.fromX, f.fromY)
    local fu0, fv0, fu1, fv1
    if fid then fu0, fv0, fu1, fv1 = uvOf(fid) end
    if fu0 then top(ground, f.x, f.y, base + f.level - 1 / 64, fu0, fv0, fu1, fv1, 0, f.level) end
  end
  -- posts under Fortree's decks: square, straight down in the drawn picture
  -- from the planks to the ground the GBA shows below them
  for _, p in ipairs(G and G.posts or {}) do
    local pu0, pv0, pu1, pv1
    if p.art then pu0, pv0, pu1, pv1 = uvOf(p.art) end
    if pu0 then
      local r0 = 0.07
      local zc = p.y + p.high          -- drawn: as far south as the deck is high
      local y0, y1 = base, base + p.high - 0.1
      local x0, x1, z0, z1 = p.x - r0, p.x + r0, zc - r0, zc + r0
      local um = (pu0 + pu1) / 2
      local function side(ax, az, bx, bz, sh)
        quad(ground, { ax, y0, az, um, pv1, sh }, { bx, y0, bz, um + 0.0001, pv1, sh },
                     { bx, y1, bz, um + 0.0001, pv0, sh }, { ax, y1, az, um, pv0, sh })
      end
      side(x0, z1, x1, z1, SHADE_SOUTH)
      side(x1, z1, x1, z0, SHADE_EAST)
      side(x0, z0, x0, z1, SHADE_WEST)
    end
  end

  -- ---------------------------------------- walls of a stood-up map --
  -- The sheared vertical walls of lib/Generic.lua's maps: wherever a cell's
  -- edge stands over its neighbour's, a wall from the neighbour's height up
  -- to its own (each point moved south by its height, as the relief is),
  -- textured with the map's own cliff face one tile a level, so a tall drop
  -- is a stack of rock rather than one tile pulled long.
  local G0 = Data.generic[layout]
  local function edgeOf(nx, ny, idx)
    if nx < 0 or ny < 0 or nx >= W or ny >= H then return nil end
    local gn = Data.reliefCell(layout, nx, ny)
    return gn and gn[idx] or 0
  end
  local EDGES = {
    -- own lattice index, neighbour, its facing index, point position, normal
    { dx = 0, dy = 1, own = function(i) return 20 + i end, their = function(i) return i end,
      at = function(x, y, i) return x + i / 4, y + 1 end, nx = 0, nz = 1, shade = SHADE_SOUTH },
    { dx = 0, dy = -1, own = function(i) return i end, their = function(i) return 20 + i end,
      at = function(x, y, i) return x + i / 4, y end, nx = 0, nz = -1, shade = SHADE_NORTH },
    { dx = -1, dy = 0, own = function(i) return i * 5 end, their = function(i) return i * 5 + 4 end,
      at = function(x, y, i) return x, y + i / 4 end, nx = -1, nz = 0, shade = SHADE_WEST },
    { dx = 1, dy = 0, own = function(i) return i * 5 + 4 end, their = function(i) return i * 5 end,
      at = function(x, y, i) return x + 1, y + i / 4 end, nx = 1, nz = 0, shade = SHADE_EAST },
  }
  genericWalls = function(x, y, g, gid, gc)
    local art = G0 and G0.faceArt or gid
    local u0, v0, u1, v1 = uvOf(art)
    if not u0 then u0, v0, u1, v1 = uvOf(gid) end
    if not u0 then return end
    local function artUV(id)
      local a0, b0, a1, b1 = nil, nil, nil, nil
      if id then a0, b0, a1, b1 = uvOf(id) end
      if a0 then return a0, b0, a1, b1 end
      return u0, v0, u1, v1
    end
    for _, e in ipairs(EDGES) do
      for i = 0, 3 do
        local a0, a1 = g[e.own(i)], g[e.own(i + 1)]
        local b0 = edgeOf(x + e.dx, y + e.dy, e.their(i))
        local b1 = edgeOf(x + e.dx, y + e.dy, e.their(i + 1))
        if b0 == nil then b0, b1 = (e.dy == 1) and 0 or nil, (e.dy == 1) and 0 or nil end
        -- a plank deck's edge is the planks' thickness, not a wall
        if b0 and gc and gc.thin then
          b0, b1 = max(b0, a0 - 2), max(b1, a1 - 2)
        elseif b0 then
          -- (a wall stands on the ground, the neighbour's lowest point)
          b0, b1 = min(b0, b1), min(b0, b1)
        end
        if b0 and max(a0 - b0, a1 - b1) > 0.5 then
          local px0, pz0 = e.at(x, y, i)
          local px1, pz1 = e.at(x, y, i + 1)
          local n = math.max(1, math.ceil(max(a0 - b0, a1 - b1) / 16 - 0.01))
          for j = 0, n - 1 do
            local t0, t1 = j / n, (j + 1) / n
            local lo0, lo1 = b0 + (a0 - b0) * t0, b1 + (a1 - b1) * t0
            local hi0, hi1 = b0 + (a0 - b0) * t1, b1 + (a1 - b1) * t1
            local wu0, wv0, wu1, wv1 = u0, v0, u1, v1
            if gc and gc.thin then wu0, wv0, wu1, wv1 = artUV(gid) end
            local ua, ub = wu0 + (wu1 - wu0) * i / 4, wu0 + (wu1 - wu0) * (i + 1) / 4
            -- On the 45-degree rule every point is drawn as far south as it
            -- is high.  The faces are the face cells themselves (a level a
            -- row, vertical on the rule); every other wall drops straight
            -- down in the drawn picture, its foot as far south as its top, so
            -- nothing is a slant -- the floor laid under the rock (the fills)
            -- is what shows round its foot.
            local dd = gc and gc[2] or g
            local zl0, zl1 = pz0 + dd[e.own(i)] / 16, pz1 + dd[e.own(i + 1)] / 16
            local zh0, zh1 = zl0, zl1
            wall(ground, {
              { px0, base + lo0 / 16, zl0, ua, wv1, 0 },
              { px1, base + lo1 / 16, zl1, ub, wv1, 0 },
              { px1, base + hi1 / 16, zh1, ub, wv0, 0 },
              { px0, base + hi0 / 16, zh0, ua, wv0, 0 } }, e.shade, e.nx, e.nz)
          end
        end
      end
    end
  end

  -- ------------------------------------------------------- furniture --
  local function solidBox(x, y, k, x0, z0, x1, z1, y0, y1)
    local u0, v0, u1, v1 = Atlas.solidUV(atlas, k)
    local X0, X1, Z0, Z1, Y0, Y1 = x + x0, x + x1, y + z0, y + z1, base + y0, base + y1
    quad(ground, { X0, Y1, Z0, u0, v0, SHADE_TOP }, { X1, Y1, Z0, u1, v0, SHADE_TOP },
                 { X1, Y1, Z1, u1, v1, SHADE_TOP }, { X0, Y1, Z1, u0, v1, SHADE_TOP })
    quad(ground, { X0, Y0, Z1, u0, v1, SHADE_SOUTH }, { X1, Y0, Z1, u1, v1, SHADE_SOUTH },
                 { X1, Y1, Z1, u1, v0, SHADE_SOUTH }, { X0, Y1, Z1, u0, v0, SHADE_SOUTH })
    quad(ground, { X1, Y0, Z0, u0, v1, SHADE_NORTH }, { X0, Y0, Z0, u1, v1, SHADE_NORTH },
                 { X0, Y1, Z0, u1, v0, SHADE_NORTH }, { X1, Y1, Z0, u0, v0, SHADE_NORTH })
    quad(ground, { X0, Y0, Z0, u0, v1, SHADE_WEST }, { X0, Y0, Z1, u1, v1, SHADE_WEST },
                 { X0, Y1, Z1, u1, v0, SHADE_WEST }, { X0, Y1, Z0, u0, v0, SHADE_WEST })
    quad(ground, { X1, Y0, Z1, u0, v1, SHADE_EAST }, { X1, Y0, Z0, u1, v1, SHADE_EAST },
                 { X1, Y1, Z0, u1, v0, SHADE_EAST }, { X1, Y1, Z1, u0, v0, SHADE_EAST })
  end
  local function emitFurniture(x, y, u0, v0, u1, v1)
    local stand, topH = 0.3, 1.0
    solidBox(x, y, Atlas.SOLID.GREY, 0, 0, 1, 1, 0, stand)
    solidBox(x, y, Atlas.SOLID.BLACK, 0, 0.3, 1, 0.8, stand, topH)
    quad(ground, { x, base + stand, y + 0.79, u0, v1, SHADE_SOUTH }, { x + 1, base + stand, y + 0.79, u1, v1, SHADE_SOUTH },
                 { x + 1, base + topH, y + 0.79, u1, v0, SHADE_SOUTH }, { x, base + topH, y + 0.79, u0, v0, SHADE_SOUTH })
  end

  -- ------------------------------------------------------ ground pass --
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local id = block(x, y)
      if id then
        local part = trees and treePart(dewford, id) or -1
        local lift, shift = cellLift(x, y)
        if part >= 0 then
          emitTree(x, y, part, lift, shift, true)
        else
          local gid = trees and treeGround(dewford, id) or id
          local g, d = Data.reliefCell(layout, x, y)
          local bground, modelTop = Data.buildingCell(layout, x, y, id, variantFits)
          local sign = Data.signAt(layout, x, y)
          -- a model lower than a level standing on a one-level slope
          -- (Lavaridge's benches) keeps the slope under it (dev)
          local keepRelief = false
          if g and bground then
            local lo, hi = g[0], g[0]
            for i = 1, 24 do lo, hi = min(lo, g[i]), max(hi, g[i]) end
            keepRelief = modelTop and modelTop > 0 and modelTop < 1 and hi - lo == 16
          end
          if g and (not bground or keepRelief) then
            -- A CUT cell (voxel_relief.c, first version): the rock's drawing
            -- with its background cleared, over the ground that runs on
            -- behind it laid flat at the rock's foot.  Without it a rock in
            -- the sea lifts its own patch of sea up the mountainside.
            local cut = not sign and Data.cutAt(layout, x, y)
            local reliefId = gid
            local flags = cut and cut.flags or 0
            -- a canopy cleared (VOXEL_RELIEF_CANOPY, dev): its variant drawn
            -- whole on the relief over a plate of `wall` a pixel under it;
            -- the rest as a cell with no variant
            if cut and math.floor(flags / 128) % 2 == 1 and cut.variant ~= 0xFFFF and uvOf(1152 + cut.variant) then
              if cut.wall < 0xFFFE and uvOf(cut.wall) then emitRelief(x, y, g, d, cut.wall, -1 / 16) end
              reliefId = 1152 + cut.variant
              cut = { variant = 0xFFFF, foot = cut.foot, ground = cut.ground, wall = 0xFFFF, flags = flags }
            end
            -- a tree's cell on the rock (VOXEL_RELIEF_FACE_TOP, dev): the
            -- rock's face, not the leaves
            if cut and math.floor(flags / 16) % 2 == 1 and not uvOf(gid) and cut.wall < 0xFFFE and uvOf(cut.wall) then
              reliefId = cut.wall
            end
            if cut then
              local foot = base + cut.foot
              local fshift = (RL and not RL.level) and cut.foot or 0
              local cutId = cut.variant ~= 0xFFFF and 1152 + cut.variant or nil
              if cutId and uvOf(cutId) then
                reliefId = cutId
                local behind = cut.ground ~= 0xFFFF and cut.ground or gid
                local bu0, bv0, bu1, bv1 = uvOf(behind)
                if bu0 then top(ground, x, y, foot - 1 / 16, bu0, bv0, bu1, bv1, -2 / 16, fshift) end
              elseif cut.ground ~= 0xFFFF then
                local bu0, bv0, bu1, bv1 = uvOf(cut.ground)
                if bu0 then
                  top(ground, x, y, foot - (2 + 0.125 * ((x + y) % 2)) / 16, bu0, bv0, bu1, bv1, -2 / 16, fshift)
                end
              end
            end
            local gc = G0 and G0[y * 256 + x]
            if gc then
              emitRelief(x, y, g, d, reliefId)
              genericWalls(x, y, g, gid, gc)
            else
              emitRelief(x, y, g, d, reliefId)
              emitCliffs(x, y, g, d, gid)
            end
            if sign then emitSign(sign, x, y, lift, shift) end
          elseif bground then
            local u0, v0, u1, v1 = uvOf(bground)
            if not u0 then u0, v0, u1, v1 = uvOf(gid) end
            if u0 then top(ground, x, y, base + lift, u0, v0, u1, v1, 0, shift) end
          elseif sign then
            local gu0, gv0, gu1, gv1 = uvOf(sign.ground)
            if not gu0 then gu0, gv0, gu1, gv1 = uvOf(block(x, y + 1) or gid) end
            if gu0 then top(ground, x, y, base + lift, gu0, gv0, gu1, gv1, 0, shift) end
            emitSign(sign, x, y, lift, shift)
          else
            local head = Data.signHeadAt(layout, x, y)
            local hid = head and head.headGround or gid
            local u0, v0, u1, v1 = uvOf(hid)
            if not u0 then u0, v0, u1, v1 = uvOf(gid) end
            if u0 then
              local beh = behaviour(id)
              if not outdoor and beh == MB_COUNTER then
                local hgt = base + 0.70
                top(ground, x, y, hgt, u0, v0, u1, v1)
                local function side(dx, dy) local n = block(x + dx, y + dy); return n and behaviour(n) ~= MB_COUNTER end
                if side(0, 1) then quad(ground, { x, base, y + 1, u0, v1, SHADE_SOUTH }, { x + 1, base, y + 1, u1, v1, SHADE_SOUTH },
                  { x + 1, hgt, y + 1, u1, v0, SHADE_SOUTH }, { x, hgt, y + 1, u0, v0, SHADE_SOUTH }) end
                if side(-1, 0) then quad(ground, { x, base, y, u0, v1, SHADE_WEST }, { x, base, y + 1, u1, v1, SHADE_WEST },
                  { x, hgt, y + 1, u1, v0, SHADE_WEST }, { x, hgt, y, u0, v0, SHADE_WEST }) end
                if side(1, 0) then quad(ground, { x + 1, base, y + 1, u0, v1, SHADE_EAST }, { x + 1, base, y, u1, v1, SHADE_EAST },
                  { x + 1, hgt, y, u1, v0, SHADE_EAST }, { x + 1, hgt, y + 1, u0, v0, SHADE_EAST }) end
              elseif not outdoor and FURNITURE[beh] then
                -- EmitFurniture: a grey stand, a black body, the metatile's
                -- own art as the screen facing south
                emitFurniture(x, y, u0, v0, u1, v1)
              elseif Data.roleAt(layout, x, y) == Data.ROLE.SIGNPOST then
                -- a sign with no record: its metatile stood upright mid-cell
                local su0, sv0, su1, sv1 = uvOf(block(x, y + 1) or gid)
                if su0 then top(ground, x, y, base + lift, su0, sv0, su1, sv1) end
                quad(ground, { x, base, y + 0.5, u0, v1, 1 }, { x + 1, base, y + 0.5, u1, v1, 1 },
                             { x + 1, base + 1, y + 0.5, u1, v0, 1 }, { x, base + 1, y + 0.5, u0, v0, 1 })
              else
                top(ground, x, y, base + lift, u0, v0, u1, v1, 0, shift)
              end
            end
          end
        end
      end
    end
  end

  -- ---------------------------------------------------------- buildings --
  local page
  local B = Data.buildings
  for _, p in ipairs(Data.placements(layout) or {}) do
    local pm = B.pageModels[p.pageModel]
    local m = B.models[pm.model]
    local P = B.pages[pm.page]
    page = page or pm.page
    local lift, shift = cellLift(p.x, p.y + m.h - 1)
    local yb = base + lift
    local su, sv = 1 / P.w, 1 / P.h
    local verts = B.verts
    local F = Bin.float
    -- the model's triangles
    for t = 0, floor(m.count / 3) - 1 do
      local pts = {}
      for k = 0, 2 do
        local o = (m.first + t * 3 + k) * 6
        pts[k + 1] = { F(verts, o) + p.x, F(verts, o + 1) + yb, F(verts, o + 2) + p.y + shift,
                       (pm.ox + F(verts, o + 3)) * su, (pm.oy + F(verts, o + 4)) * sv, F(verts, o + 5) }
      end
      if outdoor then
        local a, b, c = pts[1], pts[2], pts[3]
        local s = modelShade(a[1], a[2], a[3], b[1], b[2], b[3], c[1], c[2], c[3], a[6])
        a[6], b[6], c[6] = s, s, s
      end
      tri(buildBuf, pts[1], pts[2], pts[3])
    end
    -- its ground patches: quads of 6, page pixels, lit like ground
    for q = 0, floor(p.extraCount / 6) - 1 do
      local t = {}
      for k = 0, 5 do
        local o = (p.extraFirst + q * 6 + k) * 6
        local px, py, pz = F(verts, o) + p.x, F(verts, o + 1) + yb, F(verts, o + 2) + p.y + shift
        t[k] = { px, py, pz, F(verts, o + 3) * su, F(verts, o + 4) * sv,
                 outdoor and sample(px, py, pz) or 1 }
      end
      quad(buildBuf, t[0], t[1], t[2], t[5])
    end
  end

  zMap = function(z) return Data.stretchZ(layout, z) + base end
  local okM, groundMesh, treeMesh, buildMesh = pcall(function()
    return toMesh(ground), toMesh(treeBuf), toMesh(buildBuf)
  end)
  zMap = nil
  if not okM then error(groundMesh, 0) end
  local inst = {
    map = map, layout = layout, width = W, height = H, base = base, outdoor = outdoor,
    atlas = atlas, ground = groundMesh, trees = treeMesh,
    buildings = buildMesh, page = page and Data.pageImage(page) or nil,
    usesTrees = trees, dewford = dewford, relief = RL,
  }
  return inst
end

-- ------------------------------------------------------------- the belt --

-- VoxelMesh_EmitBorder: the ring of cells no instance covers, around the
-- current map, laid with that map's 2x2 border block -- two courses high,
-- water flat, trees as trees.  `covered(wx, wy)` says whether some instance
-- owns a world cell; `reach` is how far out the ring goes.
function Builder.belt(inst, covered, reach)
  local map, atlas = inst.map, inst.atlas
  local border = map.def and map.def.border
  if not (inst.outdoor and type(border) == "string" and #border >= 8) then return nil end
  local function borderAt(x, y)
    local i = (x % 2) + 2 * (y % 2)
    return (border:byte(i * 2 + 1) + border:byte(i * 2 + 2) * 256) % 1024
  end
  local record = atlas.record
  local function isWater(id)
    local t = record.tiles
    if not (t and t.attributes) then return false end
    local ok, b = pcall(t.attributes, t, id)
    return ok and WATER[b] or false
  end
  local W, H, base = inst.width, inst.height, inst.base
  local belt = inst.relief and inst.relief.belt or 0
  local courses = belt > 0 and belt or 2
  local ground, treeBuf = newBuf(), newBuf()
  local TU = Trees.U
  local function isBelt(x, y)
    return not (x >= 0 and y >= 0 and x < W and y < H) and not covered(x, y)
  end
  for y = -reach, H + reach - 1 do
    for x = -reach, W + reach - 1 do
      if isBelt(x, y) then
        local id = borderAt(x, y)
        local part = inst.usesTrees and treePart(inst.dewford, id) or -1
        if part >= 0 then
          if part == 4 then
            local cx, cy = inst.dewford and 64 or 32, inst.dewford and 0 or 32
            local y0 = base - 0.10
            quad(treeBuf, { x, base, y, TU(cx + 16), TU(cy), 1 }, { x + 1, base, y, TU(cx + 32), TU(cy), 1 },
                          { x + 1, base, y + 1, TU(cx + 32), TU(cy + 16), 1 }, { x, base, y + 1, TU(cx + 16), TU(cy + 16), 1 })
            local bz = y + (inst.dewford and 0.975 or 0.825)
            quad(treeBuf, { x, y0 + 1.532089, bz - 1.285575, TU(cx), TU(cy), 0.95 },
                          { x + 1, y0 + 1.532089, bz - 1.285575, TU(cx + 16), TU(cy), 0.95 },
                          { x + 1, y0, bz, TU(cx + 16), TU(cy + 32), 0.95 },
                          { x, y0, bz, TU(cx), TU(cy + 32), 0.95 })
          else
            local col, row = part % 2, floor(part / 2)
            local tx, ty = 32 + col * 16, row * 16
            quad(treeBuf, { x, base, y, TU(tx), TU(ty), 1 }, { x + 1, base, y, TU(tx + 16), TU(ty), 1 },
                          { x + 1, base, y + 1, TU(tx + 16), TU(ty + 16), 1 }, { x, base, y + 1, TU(tx), TU(ty + 16), 1 })
            local u0, u1 = TU(col * 16), TU(col * 16 + 16)
            local v0, v1 = TU(row * 18), TU(row * 18 + 18)
            local bz = y - row + 1.35
            local t, b = 1.0 - row * 0.5, 0.5 - row * 0.5
            local y0 = base - 0.10
            quad(treeBuf, { x, y0 + t * 1.7236, bz - t * 1.446272, u0, v0, 0.95 },
                          { x + 1, y0 + t * 1.7236, bz - t * 1.446272, u1, v0, 0.95 },
                          { x + 1, y0 + b * 1.7236, bz - b * 1.446272, u1, v1, 0.95 },
                          { x, y0 + b * 1.7236, bz - b * 1.446272, u0, v1, 0.95 })
          end
        else
          local u0, v0, u1, v1 = Atlas.uv(atlas, id)
          if u0 then
            if isWater(id) then
              quad(ground, { x, base, y, u0, v0, 1 }, { x + 1, base, y, u1, v0, 1 },
                           { x + 1, base, y + 1, u1, v1, 1 }, { x, base, y + 1, u0, v1, 1 })
            elseif belt > 0 then
              local hy, sz = base + courses, belt
              quad(ground, { x, hy, y + sz, u0, v0, 1 }, { x + 1, hy, y + sz, u1, v0, 1 },
                           { x + 1, hy, y + 1 + sz, u1, v1, 1 }, { x, hy, y + 1 + sz, u0, v1, 1 })
            else
              local hy = base + courses
              local tu0, tv0, tu1, tv1 = Atlas.uv(atlas, borderAt(x, y - 1))
              tu0 = tu0 or u0; tv0 = tv0 or v0; tu1 = tu1 or u1; tv1 = tv1 or v1
              quad(ground, { x, hy, y, tu0, tv0, 1 }, { x + 1, hy, y, tu1, tv0, 1 },
                           { x + 1, hy, y + 1, tu1, tv1, 1 }, { x, hy, y + 1, tu0, tv1, 1 })
              local function open(dx, dy)
                if not isBelt(x + dx, y + dy) then return true end
                local n = borderAt(x + dx, y + dy)
                return isWater(n)
              end
              for h = 0, courses - 1 do
                local fu0, fv0, fu1, fv1 = Atlas.uv(atlas, borderAt(x, y - h))
                if fu0 then
                  local y0, y1 = base + h, base + h + 1
                  if open(0, 1) then
                    quad(ground, { x, y0, y + 1, fu0, fv1, SHADE_SOUTH }, { x + 1, y0, y + 1, fu1, fv1, SHADE_SOUTH },
                                 { x + 1, y1, y + 1, fu1, fv0, SHADE_SOUTH }, { x, y1, y + 1, fu0, fv0, SHADE_SOUTH })
                  end
                  if open(-1, 0) then
                    quad(ground, { x, y0, y, fu0, fv1, 0.85 }, { x, y0, y + 1, fu1, fv1, 0.85 },
                                 { x, y1, y + 1, fu1, fv0, 0.85 }, { x, y1, y, fu0, fv0, 0.85 })
                  end
                  if open(1, 0) then
                    quad(ground, { x + 1, y0, y + 1, fu0, fv1, AMBIENT }, { x + 1, y0, y, fu1, fv1, AMBIENT },
                                 { x + 1, y1, y, fu1, fv0, AMBIENT }, { x + 1, y1, y + 1, fu0, fv0, AMBIENT })
                  end
                end
              end
            end
          end
        end
      end
    end
  end
  -- the belt stands round the map on its base: as far south as that is high
  local base = inst.base or 0
  zMap = function(z) return z + base end
  local okM, g, t = pcall(function() return toMesh(ground), toMesh(treeBuf) end)
  zMap = nil
  if not okM then error(g, 0) end
  return { ground = g, trees = t }
end

return Builder
