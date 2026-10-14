-- SpriteSolid: a smooth 3D body built from a sprite's front and back.
--
-- WHY THIS EXISTS
--
-- Platinum's overworld people are billboards: a flat card showing one of four
-- REAL pictures (south, north, west, east -- nothing is mirrored, see the
-- engine's Gen4Facings) plus two step frames per side. A free camera orbits
-- that card, so every NPC is a paper cut-out in a 3D world.
--
-- This module turns the front and back pictures of one pose into a closed,
-- smooth, textured mesh (optional side pictures can still drive depth). It
-- owns NO engine state and touches no LOVE API, so it runs (and is tested)
-- under plain Lua; lib/Gen4NpcModels.lua does the engine side.
--
-- THE SHAPE
--
-- 1. The front/back alpha masks give, for every pixel row, which stretches of
--    the body are occupied (x runs). Depth (z runs) is invented from each
--    run's width so the body is volumetric without a side picture fighting
--    the front silhouette. `useSides` opts back into reading east/west masks
--    for z. A row's cross-section is one ellipse per (x run, z run): a leg
--    4 px wide with invented depth 3 is a 4 x 3 ellipse, not a box.
--    Runs pair by order when both views see the same count (two legs that
--    are also two legs in profile), and as a product otherwise. Pairing by
--    order is what stops a walking pose growing four legs.
-- 2. Every ellipse becomes a soft density (a one-pixel ramp), the rows are
--    stacked into a 3D field and blurred, which rounds the pixel staircase.
-- 3. Naive SURFACE NETS pulls the iso-surface out of that field (no lookup
--    tables, and smoother than marching cubes at this resolution). Normals
--    come from the field's gradient, so shading is smooth across triangles.
-- 4. The soles are flattened onto y = 0 (virtual rows are added under the feet
--    first, so the blur cannot round them off the ground).
--
-- THE LOOK
--
-- Each triangle takes its colour from the front or back picture (the +z /
-- -z half of the body). Side pictures are not mapped on: at a 3/4 camera
-- they show a different pose of the same person and fight the front art.
-- The vertex UV is the planar projection of the vertex into that picture.
-- Vertices are duplicated per picture, so the mid-body seam is a colour
-- change, never a crack. Texels just outside a silhouette are expected to
-- be colour-padded by `padRGBA`, because the mesh is rounder than the pixels.
--
-- COORDINATES (model space, one unit = one sprite pixel)
--   y up, 0 at the soles. x east when the body faces south, z forward (south).
--   A sprite cell is W x H; its centre column is x = 0 / z = 0.
--   front (south sprite):  col = x + W/2        back (north):  col = -x + W/2
--   right (east sprite):   col = z + W/2        left (west):   col = -z + W/2
--   row = base + 1 - y, where `base` is the lowest occupied row.

local S = {}

S.ALPHA = 128           -- alpha (0..255) at or above which a texel is body

S.DEFAULT = {
  ss = 1,               -- field samples per pixel per axis (2 = 8x the nodes)
  blur = 2,             -- passes of [1 2 1]/4 along each axis
  iso = 0.45,           -- density level of the surface (0.5 = exact edge)
  ramp = 1.0,           -- px over which a section's density falls from 1 to 0
  minDepth = 3,         -- px: the thinnest any part may be front to back
  margin = 3,           -- empty px kept around the body for the blur
  below = 3,            -- virtual rows under the soles
  frontBias = 1.2,      -- front/back win a triangle over a side by this factor
  useSides = false,     -- true: east/west masks for depth AND side pictures
  light = { 0.15, 0.85, 0.5 },   -- body-attached key light (model space)
  floor = 0.66,         -- darkest shade; the shader wants a floor well above 0
}

local floor, ceil, sqrt, abs = math.floor, math.ceil, math.sqrt, math.abs
local min, max = math.min, math.max
local byte, char = string.byte, string.char

-- --------------------------------------------------------------- masks --

-- maskFromRGBA(rgba, imgW, imgH, x0, y0, cw, ch [, thr]) -> mask
-- One cell of a sheet as a flat boolean array, row-major from the top.
function S.maskFromRGBA(rgba, imgW, imgH, x0, y0, cw, ch, thr)
  thr = thr or S.ALPHA
  local m = { w = cw, h = ch }
  for y = 0, ch - 1 do
    local at = ((y0 + y) * imgW + x0) * 4 + 4
    local o = y * cw
    for x = 0, cw - 1 do
      local a = byte(rgba, at + x * 4)
      m[o + x + 1] = (a ~= nil and a >= thr) and true or false
    end
  end
  return m
end

-- ------------------------------------------------------------- padding --

-- padRGBA(rgba, imgW, imgH, cw, ch [, radius [, thr]]) -> rgba
--
-- The mesh is rounder than the pixels, so a triangle near the edge of a
-- silhouette can land on a texel that was transparent. The shader discards
-- those, which would cut holes in the body. This grows each opaque texel's
-- colour outward `radius` px (inside its own cell, so one frame never bleeds
-- into the next) and makes the grown texels opaque. Original opaque texels
-- are untouched; anything further than `radius` from the art stays clear.
function S.padRGBA(rgba, imgW, imgH, cw, ch, radius, thr)
  radius = radius or 3
  thr = thr or S.ALPHA
  local n = imgW * imgH
  local R, G, B, solid = {}, {}, {}, {}
  for i = 0, n - 1 do
    local r, g, b, a = byte(rgba, i * 4 + 1, i * 4 + 4)
    if a and a >= thr then
      R[i], G[i], B[i], solid[i] = r, g, b, true
    end
  end
  for _ = 1, radius do
    local fill = {}
    for y = 0, imgH - 1 do
      local cy0 = floor(y / ch) * ch
      local cy1 = cy0 + ch - 1
      for x = 0, imgW - 1 do
        local i = y * imgW + x
        if not solid[i] then
          local sr, sg, sb, c = 0, 0, 0, 0
          for dy = -1, 1 do
            local yy = y + dy
            if yy >= cy0 and yy <= cy1 then
              for dx = -1, 1 do
                local xx = x + dx
                if (dx ~= 0 or dy ~= 0) and xx >= 0 and xx < imgW then
                  local j = yy * imgW + xx
                  if solid[j] then
                    sr, sg, sb, c = sr + R[j], sg + G[j], sb + B[j], c + 1
                  end
                end
              end
            end
          end
          if c > 0 then
            fill[#fill + 1] = { i, floor(sr / c + 0.5), floor(sg / c + 0.5),
                                floor(sb / c + 0.5) }
          end
        end
      end
    end
    if #fill == 0 then break end
    for _, f in ipairs(fill) do
      R[f[1]], G[f[1]], B[f[1]], solid[f[1]] = f[2], f[3], f[4], true
    end
  end
  local out = {}
  for i = 0, n - 1 do
    if solid[i] then
      out[i + 1] = char(R[i], G[i], B[i], 255)
    else
      out[i + 1] = "\0\0\0\0"
    end
  end
  return table.concat(out)
end

-- --------------------------------------------------------------- rows --

local function runsOf(w, test)
  local runs, start = {}, nil
  for i = 0, w - 1 do
    if test(i) then
      if not start then start = i end
    elseif start then
      runs[#runs + 1] = { start, i }
      start = nil
    end
  end
  if start then runs[#runs + 1] = { start, w } end
  return runs
end

-- Per row: the x runs (front/back seen together: the back picture is the
-- front's mirror) and, when useSides, the z runs (east/west seen together).
local function analyse(views, W, H, useSides)
  local F, Bk, L, R = views.front, views.back, views.left, views.right
  local wr, dr = {}, {}
  local top, base
  for r = 0, H - 1 do
    local o = r * W
    wr[r] = runsOf(W, function(i)
      return F[o + i + 1] or Bk[o + (W - 1 - i) + 1]
    end)
    if useSides and L and R then
      dr[r] = runsOf(W, function(k)
        return R[o + k + 1] or L[o + (W - 1 - k) + 1]
      end)
    else
      dr[r] = {}
    end
    if #wr[r] > 0 then
      top = top or r
      base = r
    end
  end
  return wr, dr, top, base
end

-- One row's cross-section: a list of ellipses { cx, cz, a, b } in model units.
local function sections(wRuns, dRuns, W, minDepth)
  local half = W / 2
  local halfMin = minDepth / 2
  local out = {}
  local function add(w, d)
    out[#out + 1] = {
      cx = (w[1] + w[2]) / 2 - half,
      a = max((w[2] - w[1]) / 2, 0.5),
      cz = (d[1] + d[2]) / 2 - half,
      b = max((d[2] - d[1]) / 2, halfMin),
    }
  end
  local nW, nD = #wRuns, #dRuns
  if nW == nD then
    for i = 1, nW do add(wRuns[i], dRuns[i]) end
  elseif nW == 1 or nD == 1 then
    for i = 1, nW do
      for j = 1, nD do add(wRuns[i], dRuns[j]) end
    end
  else
    -- both see several, and a different number: take the side view as one
    -- stretch rather than guess a pairing
    local lo, hi = dRuns[1][1], dRuns[nD][2]
    for i = 1, nW do add(wRuns[i], { lo, hi }) end
  end
  return out
end

-- ----------------------------------------------------------- the field --

local function blurAxis(f, nx, ny, nz, axis, passes, tick)
  local len = (axis == 1 and nx) or (axis == 2 and ny) or nz
  local stride = (axis == 1 and 1) or (axis == 2 and nx) or (nx * ny)
  local t = {}
  local function line(base)
    for _ = 1, passes do
      for i = 1, len do t[i] = f[base + (i - 1) * stride] end
      local prev, cur = 0, t[1]
      for i = 1, len do
        local nxt = (i < len) and t[i + 1] or 0
        f[base + (i - 1) * stride] = (prev + 2 * cur + nxt) * 0.25
        prev, cur = cur, nxt
      end
    end
  end
  if axis == 1 then
    for k = 0, nz - 1 do
      for j = 0, ny - 1 do line((k * ny + j) * nx + 1) end
      tick()
    end
  elseif axis == 2 then
    for k = 0, nz - 1 do
      for i = 0, nx - 1 do line(k * ny * nx + i + 1) end
      tick()
    end
  else
    for j = 0, ny - 1 do
      for i = 0, nx - 1 do line(j * nx + i + 1) end
      tick()
    end
  end
end

-- ------------------------------------------------------------ the build --

local function noop() end

-- shade(nx, ny, nz, o) -> signed shade for Voxel3D's VertexShade. The sign is
-- the shader's "this face points at the sky" flag.
local function shadeOf(nx, ny, nz, o)
  local L = o.light
  local d = nx * L[1] + ny * L[2] + nz * L[3]
  local s = o.floor + (1 - o.floor) * (d * 0.5 + 0.5)
  if s > 1 then s = 1 end
  if ny > 0.55 then s = -s end
  return s
end

-- build(views, layout [, opts [, tick]]) -> result | nil, reason
--
--   views   { front, back [, left, right] } masks (S.maskFromRGBA), one pose
--   layout  { imgW, imgH, cellW, cellH, cellX,
--             cellY = { front =, back = [, left =, right =] } }   (pixels)
--   opts    S.DEFAULT overrides
--   tick    called now and then; a job uses it to yield (see S.newJob)
--
-- result  { verts, map, vertexCount, triangleCount, height, halfW, halfD }
-- verts are { x, y, z, u, v, shade, 0 } (Voxel3D.FORMAT); map is 1-based.
function S.build(views, layout, opts, tick)
  tick = tick or noop
  local o = {}
  for k, v in pairs(S.DEFAULT) do o[k] = v end
  for k, v in pairs(opts or {}) do o[k] = v end
  local W, H = layout.cellW, layout.cellH
  local need = { "front", "back" }
  if o.useSides then need[3], need[4] = "left", "right" end
  for _, key in ipairs(need) do
    local m = views[key]
    if not (m and m.w == W and m.h == H) then
      return nil, "missing or mismatched " .. key .. " mask"
    end
  end

  local wr, dr, top, base = analyse(views, W, H, o.useSides)
  if not top then return nil, "no body in the front/back views" end
  local bodyH = base - top + 1
  if bodyH < 4 then return nil, "body only " .. bodyH .. " rows tall" end

  -- Rows with no side view borrow the nearest row that has one.
  local rows = {}
  local anyD = false
  for r = top, base do if #dr[r] > 0 then anyD = true break end end
  local function depthRunsFor(r)
    if #dr[r] > 0 then return dr[r] end
    for d = 1, 8 do
      if r - d >= top and #dr[r - d] > 0 then return dr[r - d] end
      if r + d <= base and #dr[r + d] > 0 then return dr[r + d] end
    end
    return nil
  end
  for r = top, base do
    local d = depthRunsFor(r)
    if not d then
      -- No side picture: each front/back run becomes its own ellipse, depth
      -- from that run's width, centred so the volume matches the art we paint.
      d = {}
      for i = 1, #wr[r] do
        local wrun = wr[r][i]
        local depth = max(o.minDepth, (wrun[2] - wrun[1]) * 0.85)
        d[i] = { W / 2 - depth / 2, W / 2 + depth / 2 }
      end
    end
    rows[r] = sections(wr[r], d, W, o.minDepth)
  end
  tick()

  -- extents of the body in model space
  local xmin, xmax, zmin, zmax = math.huge, -math.huge, math.huge, -math.huge
  for r = top, base do
    for _, e in ipairs(rows[r]) do
      xmin, xmax = min(xmin, e.cx - e.a), max(xmax, e.cx + e.a)
      zmin, zmax = min(zmin, e.cz - e.b), max(zmax, e.cz + e.b)
    end
  end

  local ss = max(1, floor(o.ss))
  local h = 1 / ss
  local m = o.margin
  local x0, x1 = floor(xmin) - m, ceil(xmax) + m
  local z0, z1 = floor(zmin) - m, ceil(zmax) + m
  local yBot, yTop = -o.below, bodyH + m
  local nx, ny, nz = (x1 - x0) * ss, (yTop - yBot) * ss, (z1 - z0) * ss

  -- density per node
  local f = {}
  local ramp = o.ramp
  for k = 0, nz - 1 do
    local z = z0 + (k + 0.5) * h
    for j = 0, ny - 1 do
      local y = yBot + (j + 0.5) * h
      local r = floor(base + 1 - y)
      if r > base then r = base end
      local es = (r >= top) and rows[r] or nil
      local at = (k * ny + j) * nx
      for i = 0, nx - 1 do
        local rho = 0
        if es then
          local x = x0 + (i + 0.5) * h
          for n = 1, #es do
            local e = es[n]
            local dx, dz = x - e.cx, z - e.cz
            if abs(dx) <= e.a + ramp and abs(dz) <= e.b + ramp then
              local ia2, ib2 = 1 / (e.a * e.a), 1 / (e.b * e.b)
              local q2 = dx * dx * ia2 + dz * dz * ib2
              local v
              if q2 < 1e-9 then
                v = 1
              else
                local q = sqrt(q2)
                local gx, gz = dx * ia2, dz * ib2
                local gl = sqrt(gx * gx + gz * gz) / q
                v = 0.5 - ((q - 1) / gl) / ramp
                if v < 0 then v = 0 elseif v > 1 then v = 1 end
              end
              if v > rho then rho = v end
            end
          end
        end
        f[at + i + 1] = rho
      end
    end
    tick()
  end

  local passes = max(1, floor(o.blur * ss))
  for axis = 1, 3 do blurAxis(f, nx, ny, nz, axis, passes, tick) end

  -- signed field: positive inside
  local iso = o.iso
  for i = 1, #f do f[i] = f[i] - iso end
  tick()

  local function F(i, j, k)
    if i < 0 or j < 0 or k < 0 or i >= nx or j >= ny or k >= nz then return -iso end
    return f[(k * ny + j) * nx + i + 1]
  end
  local function grad(i, j, k)
    return (F(i + 1, j, k) - F(i - 1, j, k)) * 0.5,
           (F(i, j + 1, k) - F(i, j - 1, k)) * 0.5,
           (F(i, j, k + 1) - F(i, j, k - 1)) * 0.5
  end

  -- ---- surface nets: one vertex per cell the surface crosses
  local cx_, cy_, cz_ = nx - 1, ny - 1, nz - 1
  local cellVert = {}
  local P, N = {}, {}            -- vertex positions / normals (flat arrays)
  local nv = 0
  local EDGES = {
    { 0, 1 }, { 2, 3 }, { 4, 5 }, { 6, 7 },
    { 0, 2 }, { 1, 3 }, { 4, 6 }, { 5, 7 },
    { 0, 4 }, { 1, 5 }, { 2, 6 }, { 3, 7 },
  }
  local cv = {}
  for k = 0, cz_ - 1 do
    for j = 0, cy_ - 1 do
      for i = 0, cx_ - 1 do
        local mask = 0
        for c = 0, 7 do
          local dx, dy, dz = c % 2, floor(c / 2) % 2, floor(c / 4)
          local val = F(i + dx, j + dy, k + dz)
          cv[c] = val
          if val > 0 then mask = mask + 2 ^ c end
        end
        if mask ~= 0 and mask ~= 255 then
          local sx, sy, sz, cnt = 0, 0, 0, 0
          for e = 1, 12 do
            local a, b = EDGES[e][1], EDGES[e][2]
            local fa, fb = cv[a], cv[b]
            if (fa > 0) ~= (fb > 0) then
              local t = fa / (fa - fb)
              local ax, ay, az = a % 2, floor(a / 2) % 2, floor(a / 4)
              local bx, by, bz = b % 2, floor(b / 2) % 2, floor(b / 4)
              sx = sx + ax + t * (bx - ax)
              sy = sy + ay + t * (by - ay)
              sz = sz + az + t * (bz - az)
              cnt = cnt + 1
            end
          end
          local px = x0 + (i + sx / cnt + 0.5) * h
          local py = yBot + (j + sy / cnt + 0.5) * h
          local pz = z0 + (k + sz / cnt + 0.5) * h
          -- normal: the field's gradient over the cell's corners, pointing out
          local gx, gy, gz = 0, 0, 0
          for c = 0, 7 do
            local dx, dy, dz = c % 2, floor(c / 2) % 2, floor(c / 4)
            local a, b, d = grad(i + dx, j + dy, k + dz)
            gx, gy, gz = gx + a, gy + b, gz + d
          end
          local gl = sqrt(gx * gx + gy * gy + gz * gz)
          if gl < 1e-9 then gx, gy, gz, gl = 0, 1, 0, 1 end
          nv = nv + 1
          P[nv * 3 - 2], P[nv * 3 - 1], P[nv * 3] = px, py, pz
          N[nv * 3 - 2], N[nv * 3 - 1], N[nv * 3] = -gx / gl, -gy / gl, -gz / gl
          cellVert[(k * cy_ + j) * cx_ + i + 1] = nv
        end
      end
    end
    tick()
  end
  if nv == 0 then return nil, "the field produced no surface" end

  -- flatten the soles
  for v = 1, nv do
    if P[v * 3 - 1] < 0 then P[v * 3 - 1] = 0 end
  end

  local function cellAt(i, j, k)
    if i < 0 or j < 0 or k < 0 or i >= cx_ or j >= cy_ or k >= cz_ then return nil end
    return cellVert[(k * cy_ + j) * cx_ + i + 1]
  end

  -- ---- quads: one per grid edge the surface crosses
  local tris = {}      -- flat: a, b, c per triangle (vertex ids)
  local function quad(a, b, c, d)
    if not (a and b and c and d) then return end
    -- outward orientation from the vertex normals
    local ux, uy, uz = P[b * 3 - 2] - P[a * 3 - 2], P[b * 3 - 1] - P[a * 3 - 1], P[b * 3] - P[a * 3]
    local vx, vy, vz = P[c * 3 - 2] - P[a * 3 - 2], P[c * 3 - 1] - P[a * 3 - 1], P[c * 3] - P[a * 3]
    local cxn, cyn, czn = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
    local nxs = N[a * 3 - 2] + N[b * 3 - 2] + N[c * 3 - 2] + N[d * 3 - 2]
    local nys = N[a * 3 - 1] + N[b * 3 - 1] + N[c * 3 - 1] + N[d * 3 - 1]
    local nzs = N[a * 3] + N[b * 3] + N[c * 3] + N[d * 3]
    if cxn * nxs + cyn * nys + czn * nzs < 0 then b, d = d, b end
    -- split along the shorter diagonal
    local function dist2(p, q2)
      local dx, dy, dz = P[p * 3 - 2] - P[q2 * 3 - 2], P[p * 3 - 1] - P[q2 * 3 - 1], P[p * 3] - P[q2 * 3]
      return dx * dx + dy * dy + dz * dz
    end
    local n = #tris
    if dist2(a, c) <= dist2(b, d) then
      tris[n + 1], tris[n + 2], tris[n + 3] = a, b, c
      tris[n + 4], tris[n + 5], tris[n + 6] = a, c, d
    else
      tris[n + 1], tris[n + 2], tris[n + 3] = a, b, d
      tris[n + 4], tris[n + 5], tris[n + 6] = b, c, d
    end
  end

  for k = 1, nz - 2 do
    for j = 1, ny - 2 do
      for i = 1, nx - 2 do
        local inside = F(i, j, k) > 0
        if i < nx - 1 and (F(i + 1, j, k) > 0) ~= inside then
          quad(cellAt(i, j - 1, k - 1), cellAt(i, j, k - 1),
               cellAt(i, j, k), cellAt(i, j - 1, k))
        end
        if j < ny - 1 and (F(i, j + 1, k) > 0) ~= inside then
          quad(cellAt(i - 1, j, k - 1), cellAt(i, j, k - 1),
               cellAt(i, j, k), cellAt(i - 1, j, k))
        end
        if k < nz - 1 and (F(i, j, k + 1) > 0) ~= inside then
          quad(cellAt(i - 1, j - 1, k), cellAt(i, j - 1, k),
               cellAt(i, j, k), cellAt(i - 1, j, k))
        end
      end
    end
    tick()
  end

  -- ---- pictures: pick one per triangle, duplicate vertices per picture
  local VIEWS = { "front", "back", "right", "left" }
  local VN = { { 0, 0, 1 }, { 0, 0, -1 }, { -1, 0, 0 }, { 1, 0, 0 } }
  local BIAS = { o.frontBias, o.frontBias, 1, 1 }
  local colX = {
    function(x, z) return x + W / 2 end,       -- front
    function(x, z) return -x + W / 2 end,      -- back
    function(x, z) return z + W / 2 end,       -- right (east sprite)
    function(x, z) return -z + W / 2 end,      -- left  (west sprite)
  }
  local nPic = o.useSides and 4 or 2
  local verts, map = {}, {}
  local made = {}
  local imgW, imgH = layout.imgW, layout.imgH
  local cellX = layout.cellX or 0

  for t = 1, #tris, 3 do
    local a, b, c = tris[t], tris[t + 1], tris[t + 2]
    -- drop triangles that collapsed onto the ground
    if not (P[a * 3 - 1] == 0 and P[b * 3 - 1] == 0 and P[c * 3 - 1] == 0) then
      local best
      if nPic == 2 then
        -- Front hemisphere wears south, back wears north. Using centroid z
        -- (not the normal) so a flank still shows the front/back art instead
        -- of a side picture of a different pose.
        best = (P[a * 3] + P[b * 3] + P[c * 3] >= 0) and 1 or 2
      else
        local nxs = N[a * 3 - 2] + N[b * 3 - 2] + N[c * 3 - 2]
        local nzs = N[a * 3] + N[b * 3] + N[c * 3]
        local bestScore = -math.huge
        best = 1
        for vi = 1, 4 do
          local s = (nxs * VN[vi][1] + nzs * VN[vi][3]) * BIAS[vi]
          if s > bestScore then best, bestScore = vi, s end
        end
      end
      for _, vid in ipairs({ a, b, c }) do
        local key = vid * 4 + best
        local idx = made[key]
        if not idx then
          local x, y, z = P[vid * 3 - 2], P[vid * 3 - 1], P[vid * 3]
          local col = colX[best](x, z)
          local row = base + 1 - y
          if col < 0.5 then col = 0.5 elseif col > W - 0.5 then col = W - 0.5 end
          if row < 0.5 then row = 0.5 elseif row > H - 0.5 then row = H - 0.5 end
          local cellY = layout.cellY[VIEWS[best]]
          verts[#verts + 1] = {
            x, y, z,
            (cellX + col) / imgW, (cellY + row) / imgH,
            shadeOf(N[vid * 3 - 2], N[vid * 3 - 1], N[vid * 3], o), 0,
          }
          idx = #verts
          made[key] = idx
        end
        map[#map + 1] = idx
      end
    end
  end
  if #map == 0 then return nil, "no triangles" end

  return {
    verts = verts, map = map,
    vertexCount = #verts, triangleCount = #map / 3,
    height = bodyH, halfW = max(abs(xmin), abs(xmax)), halfD = max(abs(zmin), abs(zmax)),
    base = base, top = top,
  }
end

-- ---------------------------------------------------------------- jobs --

-- newJob(views, layout [, opts [, clock]]) -> job
-- The same build, as a coroutine that gives control back once a time slice is
-- spent, so a frame budget (Gen4Budget) can pay for it a few ms at a time.
--   job:step(seconds) -> done        job.result / job.reason / job.failed
function S.newJob(views, layout, opts, clock)
  clock = clock or os.clock
  local job = { done = false }
  local function tick()
    if job.deadline and clock() > job.deadline then coroutine.yield() end
  end
  local co = coroutine.create(function()
    job.result, job.reason = S.build(views, layout, opts, tick)
  end)
  function job:step(seconds)
    if self.done then return true end
    self.deadline = clock() + (seconds or 0.004)
    local ok, err = coroutine.resume(co)
    if not ok then
      self.done, self.failed = true, tostring(err)
    elseif coroutine.status(co) == "dead" then
      self.done = true
    end
    return self.done
  end
  return job
end

return S
