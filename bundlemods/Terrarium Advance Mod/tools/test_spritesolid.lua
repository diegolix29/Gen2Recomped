-- Run from the mod root with: texlua tools/test_spritesolid.lua
-- Pure Lua, no LOVE, no ROM: drives the REAL lib/SpriteSolid.lua on a
-- synthetic four-sided sheet (tools/spritesolid_fixture.lua).
local fails, passes = 0, 0
local function check(c, m) if c then passes = passes + 1 else fails = fails + 1; print("FAIL: " .. m) end end

local S = assert(loadfile("lib/SpriteSolid.lua"))()
local Fx = assert(loadfile("tools/spritesolid_fixture.lua"))()
local rgba, imgW, imgH = Fx.makeSheet()
local padded = S.padRGBA(rgba, imgW, imgH, Fx.W, Fx.H, 3)

local function alphaAt(sheet, x, y) return sheet:byte((y * imgW + x) * 4 + 4) end

-- ------------------------------------------------------------ masks / pad --
local m = S.maskFromRGBA(rgba, imgW, imgH, 0, Fx.facings.down[1] * Fx.H, Fx.W, Fx.H)
check(m.w == 32 and m.h == 32, "mask carries its cell size")
check(m[(9 * 32) + 16 + 1] == true, "a head pixel is opaque")
check(m[(0 * 32) + 0 + 1] == false, "the corner is clear")
check(S.maskFromRGBA(rgba, imgW, imgH, 0, imgH + 64, 32, 32)[1] == false, "off the sheet reads as clear")

check(#padded == #rgba, "padding keeps the sheet size")
local same = true
for y = 0, imgH - 1 do
  for x = 0, imgW - 1 do
    if alphaAt(rgba, x, y) == 255 then
      local i = (y * imgW + x) * 4
      if rgba:sub(i + 1, i + 4) ~= padded:sub(i + 1, i + 4) then same = false end
    end
  end
end
check(same, "padding never changes an opaque texel")
-- cell 0 (south stand): head disc centre (16,9) r5 -> (16,3) is the hair row top
local function opaque(sheet, f, x, y) return alphaAt(sheet, x, f * Fx.H + y) >= 128 end
check(not opaque(rgba, 0, 16, 1) and opaque(padded, 0, 16, 1), "a texel just outside the art is grown")
check(not opaque(padded, 0, 0, 0), "a texel far from the art stays clear")
-- no bleed between stacked cells: a lone opaque texel on the last row of one cell
do
  local px = {}
  for i = 1, 8 * 16 do px[i] = "\0\0\0\0" end
  px[(7 * 8) + 4 + 1] = "\200\10\10\255"            -- cell 0, last row
  local sheet = table.concat(px)
  local p2 = S.padRGBA(sheet, 8, 16, 8, 8, 3)
  check(p2:byte((8 * 8 + 4) * 4 + 4) == 0, "padding does not bleed into the next cell's first row")
  check(p2:byte((6 * 8 + 4) * 4 + 4) == 255, "padding does grow within its own cell")
end

-- ------------------------------------------------------------------ build --
local results = {}
for slot = 1, 3 do
  local views, layout = Fx.viewsFor(S, rgba, imgW, imgH, slot)
  local r, why = S.build(views, layout)
  check(r ~= nil, "slot " .. slot .. " builds (" .. tostring(why) .. ")")
  results[slot] = r
end
local r1 = results[1]
check(r1.triangleCount > 1500 and r1.triangleCount < 6000, "stand body is a sane size: " .. r1.triangleCount)
check(#r1.map == r1.triangleCount * 3, "index list matches the triangle count")

local minY, maxY, sumX, nanBad, uvBad = math.huge, -math.huge, 0, false, false
for _, v in ipairs(r1.verts) do
  for i = 1, 7 do if v[i] ~= v[i] or v[i] == math.huge or v[i] == -math.huge then nanBad = true end end
  minY, maxY, sumX = math.min(minY, v[2]), math.max(maxY, v[2]), sumX + v[1]
  if v[4] < 0 or v[4] > 1 or v[5] < 0 or v[5] > 1 then uvBad = true end
  if math.abs(v[6]) < 0.5 or math.abs(v[6]) > 1.0001 then nanBad = true end
end
check(not nanBad, "no NaN/inf, and every |shade| is in the shader's safe range")
check(not uvBad, "every UV is inside the sheet")
check(minY == 0, "the soles are exactly on the ground (min y = " .. minY .. ")")
check(math.abs(maxY - r1.height) <= 1.5, ("the head is as tall as the art (%.2f vs %d)"):format(maxY, r1.height))
check(math.abs(sumX / #r1.verts) < 0.6, "a symmetric sprite gives a centred body")
local okMap = true
for _, i in ipairs(r1.map) do if i < 1 or i > #r1.verts then okMap = false end end
check(okMap, "every index points at a vertex")

-- the surface is closed: every edge borders two triangles, except on the ground
do
  local function key(v) return string.format("%.3f,%.3f,%.3f", v[1], v[2], v[3]) end
  local uses, ends = {}, {}
  for i = 1, #r1.map, 3 do
    local k = { key(r1.verts[r1.map[i]]), key(r1.verts[r1.map[i + 1]]), key(r1.verts[r1.map[i + 2]]) }
    for e = 1, 3 do
      local a, b = k[e], k[e % 3 + 1]
      if a ~= b then
        local ek = a < b and (a .. "|" .. b) or (b .. "|" .. a)
        uses[ek] = (uses[ek] or 0) + 1
        ends[ek] = { r1.verts[r1.map[i + e - 1]][2], r1.verts[r1.map[i + e % 3]][2] }
      end
    end
  end
  local open, openOffGround = 0, 0
  for ek, n in pairs(uses) do
    if n ~= 2 then
      open = open + 1
      if not (ends[ek][1] == 0 and ends[ek][2] == 0) then openOffGround = openOffGround + 1 end
    end
  end
  check(openOffGround == 0, "the body is closed above the ground (" .. openOffGround .. " open edges off the ground)")
end

-- the baked atlas: four picture cells + a top cell, every vertex on real colour
local K = S.DEFAULT.texScale                  -- atlas texels per sprite pixel
local SRC_W, SRC_H = 32, 4 * 32 + 32            -- the atlas in sprite pixels
local ATLAS_W, ATLAS_H = SRC_W * K, SRC_H * K
local ORIGIN = { 0, 32, 64, 96, 128 }       -- front, back, east, west, top (sprite px)
local function cellOfRow(ay) ay = ay / K; return ay >= 128 and 5 or math.floor(ay / 32) + 1 end  -- ay in texels
local function texel(r, v) -- colour under a vertex's UV
  local x = math.min(math.floor(v[4] * r.atlasW), r.atlasW - 1)
  local y = math.min(math.floor(v[5] * r.atlasH), r.atlasH - 1)
  local at = (y * r.atlasW + x) * 4
  local R, G, B, A = r.atlas:byte(at + 1, at + 4)
  return R, G, B, A
end
do
  check(r1.atlasW == ATLAS_W and r1.atlasH == ATLAS_H and #r1.atlas == ATLAS_W * ATLAS_H * 4,
    "the atlas is four picture cells and a top cell")
  local onClear, perCell = 0, {}
  for _, v in ipairs(r1.verts) do
    local _, _, _, A = texel(r1, v)
    if A < 128 then onClear = onClear + 1 end
    local c = cellOfRow(v[5] * r1.atlasH)
    perCell[c] = (perCell[c] or 0) + 1
  end
  check(onClear == 0, "no vertex samples a transparent texel (" .. onClear .. ")")
  local used = 0
  for c = 1, 5 do if (perCell[c] or 0) > 20 then used = used + 1 end end
  check(used == 5, "all five cells are used (front, back, east, west, top)")

  -- the crown of the head is projected from above, not smeared by a side view
  local top = r1.verts[1]
  for _, v in ipairs(r1.verts) do if v[2] > top[2] then top = v end end
  check(cellOfRow(top[5] * r1.atlasH) == 5, "the highest point wears the TOP cell")

  -- colour comes ONLY from the front and back pictures. The fixture paints
  -- its two side pictures in colours nothing else uses (green / yellow shirts
  -- and their darker arms), so any leak into the texture is findable.
  local function near(R, G, B, c, d)
    return math.abs(R - c[1]) + math.abs(G - c[2]) + math.abs(B - c[3]) <= d
  end
  local sideColours = { { 40, 170, 60 }, { 220, 190, 40 }, { 20, 85, 30 }, { 110, 95, 20 } }
  local leaked, red, blue = 0, 0, 0
  for y = 0, r1.atlasH - 1 do
    for x = 0, r1.atlasW - 1 do
      local at = (y * r1.atlasW + x) * 4
      local R, G, B, A = r1.atlas:byte(at + 1, at + 4)
      if A >= 128 then
        for _, c in ipairs(sideColours) do if near(R, G, B, c, 30) then leaked = leaked + 1 end end
        if near(R, G, B, Fx.COLORS.front, 30) then red = red + 1 end
        if near(R, G, B, Fx.COLORS.back, 30) then blue = blue + 1 end
      end
    end
  end
  check(leaked == 0, "no side-picture colour reaches the texture (" .. leaked .. " texels)")
  check(red > 40 and blue > 40, "the front's red and the back's blue are both there (" .. red .. ", " .. blue .. ")")

  -- facing south the surface is the front picture, facing north the back one
  local front, back
  for _, v in ipairs(r1.verts) do
    if v[2] >= 9 and v[2] <= 17 then
      if not front or v[3] > front[3] then front = v end
      if not back or v[3] < back[3] then back = v end
    end
  end
  local fr, fg, fb = texel(r1, front)
  check(fr > fg + 40 and fr > fb + 40, "the most forward torso point is the front picture's red")
  local br, bg, bb = texel(r1, back)
  check(bb > br + 40 and bb > bg + 20, "the most rearward torso point is the back picture's blue")
end

-- the chibi: its side picture has a MAGENTA eye. A second face on the cheek is
-- exactly what that would look like, so it must not appear anywhere.
do
  local crgba, cw, ch = Fx.makeChibi()
  for slot = 1, 3 do
    local views, layout = Fx.viewsFor(S, crgba, cw, ch, slot)
    local r = assert(S.build(views, layout))
    local magenta, eyes = 0, 0
    for y = 0, r.atlasH - 1 do
      for x = 0, r.atlasW - 1 do
        local at = (y * r.atlasW + x) * 4
        local R, G, B, A = r.atlas:byte(at + 1, at + 4)
        if A >= 128 then
          if math.abs(R - 255) + G + math.abs(B - 255) <= 90 then magenta = magenta + 1 end
          -- the front picture's eyes: dark texels in the face band of the front cell
          if y >= 14 * K and y < 17 * K and x >= 11 * K and x < 21 * K and R < 70 and G < 70 and B < 80 then
            eyes = eyes + 1
          end
        end
      end
    end
    check(magenta == 0, "chibi pose " .. slot .. ": the side picture's eye never reaches the texture (" .. magenta .. ")")
    if slot == 1 then check(eyes >= 4, "...while the front picture's own eyes do (" .. eyes .. " eye texels)") end
  end
end

-- the flank is the picture stretched over the depth, not its dark outline
-- carried round. Platinum sprites have a 1px outline; plain projection paints
-- that over the whole side (the chibi fixture has one too, like the real ones).
do
  local crgba, cw, ch = Fx.makeChibi()
  local function build(opts)
    local views, layout = Fx.viewsFor(S, crgba, cw, ch, 1)
    return assert(S.build(views, layout, opts))
  end
  -- share of opaque texels in the given cells that are outline-coloured
  local function outlineShare(r, cells)
    local tot, hit = 0, 0
    for _, c in ipairs(cells) do
      for y = ORIGIN[c] * K, (ORIGIN[c] + 32) * K - 1 do
        for x = 0, 32 * K - 1 do
          local at = (y * r.atlasW + x) * 4
          local R, G, B, A = r.atlas:byte(at + 1, at + 4)
          if A >= 128 then
            tot = tot + 1
            if math.abs(R - Fx.OUTLINE[1]) + math.abs(G - Fx.OUTLINE[2]) + math.abs(B - Fx.OUTLINE[3]) <= 14 then hit = hit + 1 end
          end
        end
      end
    end
    return hit / math.max(tot, 1), tot
  end
  local plain, wrapped = build({ wrap = 0 }), build()
  local flank0, n = outlineShare(plain, { 3, 4 })
  local flank1 = outlineShare(wrapped, { 3, 4 })
  local crown0 = outlineShare(plain, { 5 })
  local crown1 = outlineShare(wrapped, { 5 })
  check(n > 300, "there is a flank to measure (" .. n .. " texels)")
  check(flank0 > 0.4, ("without the stretch the flank IS the outline (%.0f%%)"):format(flank0 * 100))
  check(flank1 < 0.15, ("with it the flank is %.0f%% outline"):format(flank1 * 100))
  check(crown0 > 0.15, ("without it the crown is outline-black too (%.0f%%)"):format(crown0 * 100))
  check(crown1 < 0.05, ("with it the crown is %.0f%% outline"):format(crown1 * 100))
  -- the face is not distorted: the middle of the front picture stays planar
  local same, tot = 0, 0
  for y = 8 * K, 19 * K - 1 do          -- the fringe and the face (the shoulders below
    for x = 10 * K, 22 * K - 1 do       -- face up, so they rightly use the outline-free copy)
      local at = (y * plain.atlasW + x) * 4
      local a1, a2, a3, a4 = plain.atlas:byte(at + 1, at + 4)
      local b1, b2, b3 = wrapped.atlas:byte(at + 1, at + 3)
      if a4 >= 128 then
        tot = tot + 1
        if math.abs(a1 - b1) + math.abs(a2 - b2) + math.abs(a3 - b3) <= 6 then same = same + 1 end
      end
    end
  end
  check(tot > 300 and same / tot > 0.99, ("the face is untouched by the stretch (%d of %d texels)"):format(same, tot))
  -- and it is still only front/back colour
  local mag = 0
  for y = 0, wrapped.atlasH - 1 do
    for x = 0, 32 * K - 1 do
      local at = (y * wrapped.atlasW + x) * 4
      local R, G, B, A = wrapped.atlas:byte(at + 1, at + 4)
      if A >= 128 and math.abs(R - 255) + G + math.abs(B - 255) <= 90 then mag = mag + 1 end
    end
  end
  check(mag == 0, "the stretch still uses no side-picture colour")
end

-- the UV is exactly the documented planar projection into its cell
do
  local worst = 0
  for _, v in ipairs(r1.verts) do
    local ay = v[5] * SRC_H
    local c = cellOfRow(ay * K)
    local x, y, z = v[1], v[2], v[3]
    local col, row
    if c == 1 then col, row = x + 16, r1.base + 1 - y
    elseif c == 2 then col, row = -x + 16, r1.base + 1 - y
    elseif c == 3 then col, row = z + 16, r1.base + 1 - y
    elseif c == 4 then col, row = -z + 16, r1.base + 1 - y
    else col, row = x + 16, z + 16 end
    col = math.max(0.5, math.min(31.5, col))
    row = math.max(0.5, math.min(31.5, row))
    worst = math.max(worst, math.abs(v[4] * SRC_W - col), math.abs(ay - ORIGIN[c] - row))
  end
  check(worst < 1e-3, "every UV is the planar projection into its cell (worst error " .. worst .. ")")
end

-- no triangle is stretched into streaks (the crown used to be edge-on to every picture)
do
  local bad, n = 0, 0
  for i = 1, #r1.map, 3 do
    local a, b, c = r1.verts[r1.map[i]], r1.verts[r1.map[i + 1]], r1.verts[r1.map[i + 2]]
    local ux, uy, uz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
    local vx, vy, vz = c[1] - a[1], c[2] - a[2], c[3] - a[3]
    local cx, cy, cz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
    local area3 = math.sqrt(cx * cx + cy * cy + cz * cz) / 2
    local du1, dv1 = (b[4] - a[4]) * SRC_W, (b[5] - a[5]) * SRC_H
    local du2, dv2 = (c[4] - a[4]) * SRC_W, (c[5] - a[5]) * SRC_H
    local areaUV = math.abs(du1 * dv2 - du2 * dv1) / 2
    if area3 > 0.02 then
      n = n + 1
      if areaUV < 0.45 * area3 then bad = bad + 1 end
    end
  end
  check(bad / n < 0.06, ("under 6%% of triangles are stretched past ~60 degrees (%.1f%%)"):format(100 * bad / n))
end

-- the point of baking: the colour is the same on both sides of a cell edge.
-- (With four pictures painted on, the mean jump across an edge was 58; with
-- colour from the front/back only it is the pixel-quantisation floor, ~13.)
do
  local views, layout = Fx.viewsFor(S, rgba, imgW, imgH, 1)
  local r = assert(S.build(views, layout))
  local byPos, sum, count = {}, 0, 0
  for _, v in ipairs(r.verts) do
    local k = string.format("%.3f,%.3f,%.3f", v[1], v[2], v[3])
    byPos[k] = byPos[k] or {}
    table.insert(byPos[k], v)
  end
  for _, group in pairs(byPos) do
    for i = 1, #group do
      for j = i + 1, #group do
        if cellOfRow(group[i][5] * r.atlasH) ~= cellOfRow(group[j][5] * r.atlasH) then
          local r1_, g1, b1 = texel(r, group[i])
          local r2, g2, b2 = texel(r, group[j])
          sum = sum + (math.abs(r1_ - r2) + math.abs(g1 - g2) + math.abs(b1 - b2)) / 3
          count = count + 1
        end
      end
    end
  end
  check(count > 50, "there are cell edges to measure (" .. count .. " vertex pairs)")
  local jump = sum / math.max(count, 1)
  check(jump < 20, ("colour is continuous across cell edges (mean jump %.1f)"):format(jump))
end

-- a walking pose has two legs, not four
check(results[2].triangleCount < r1.triangleCount * 1.5, "the stride pose does not grow ghost legs")

-- ------------------------------------------------------------------- opts --
do
  local views, layout = Fx.viewsFor(S, rgba, imgW, imgH, 1)
  local hi = S.build(views, layout, { ss = 2 })
  check(hi and hi.triangleCount > r1.triangleCount * 2.5, "ss=2 gives a finer mesh")
  local bad = {}
  for k, v in pairs(views) do bad[k] = v end
  bad.left = { w = 16, h = 16 }
  local r, why = S.build(bad, layout)
  check(r == nil and why:find("left"), "a mismatched mask is refused with a reason")
  local nosrc = {}
  for k, v in pairs(layout) do nosrc[k] = v end
  nosrc.src = nil
  local r0, why0 = S.build(views, nosrc)
  check(r0 == nil and why0:find("src"), "a build without the padded sheet is refused with a reason")
  local empty = {}
  for k, v in pairs(views) do
    local e = { w = v.w, h = v.h }
    for i = 1, v.w * v.h do e[i] = false end
    empty[k] = e
  end
  r, why = S.build(empty, layout)
  check(r == nil and why, "an empty sprite is refused, not crashed on")
end

-- ---------------------------------------------------------------- smoothness --
-- A 32 px sprite on a body that is big on screen shows squares unless the atlas
-- is baked from a smooth reconstruction of it.
do
  local function imgOf(w, h, f)               -- f(x, y) -> {r,g,b} | nil
    local R, G, B, SO = {}, {}, {}, {}
    for y = 0, h - 1 do
      for x = 0, w - 1 do
        local c = f(x, y)
        if c then local i = y * w + x; R[i], G[i], B[i], SO[i] = c[1], c[2], c[3], true end
      end
    end
    return { w = w, h = h, R = R, G = G, B = B, solid = SO }
  end
  local RED, BLUE = { 200, 0, 0 }, { 0, 0, 200 }
  local function key(i, t) return t.R[i] * 65536 + t.G[i] * 256 + t.B[i] end

  -- K = 1 changes nothing
  local plain = imgOf(6, 6, function(x, y) return ((x + y) % 2 == 0) and RED or BLUE end)
  local same = S.smooth(plain, 1, 0)
  local identical = same.w == 6 and same.h == 6
  for i = 0, 35 do if key(i, same) ~= key(i, plain) then identical = false end end
  check(identical and same.scale == 1, "smoothing at scale 1 is the identity")
  check(S.smooth(plain, 3, 0).scale == 2 and S.smooth(plain, 8, 0).scale == 8,
    "the scale is the power of two at or below the request")

  -- a diagonal staircase: where the red turns blue, row by row
  local diag = imgOf(8, 8, function(x, y) return (x + y < 8) and RED or BLUE end)
  local function flips(t)
    local out = {}
    for y = 0, t.h - 1 do
      local first
      for x = 0, t.w - 1 do
        if key(y * t.w + x, t) ~= key(0, t) then first = x break end
      end
      out[y] = first
    end
    return out
  end
  local function maxStep(t)
    local f, worst = flips(t), 0
    for y = 1, t.h - 1 do
      if f[y] and f[y - 1] then worst = math.max(worst, math.abs(f[y] - f[y - 1])) end
    end
    return worst
  end
  local hard = imgOf(32, 32, function(x, y) return ((math.floor(x / 4) + math.floor(y / 4)) < 8) and RED or BLUE end)
  local sm = S.smooth(diag, 4, 0)
  check(sm.w == 32 and sm.h == 32, "a picture comes out K times larger")
  check(maxStep(hard) >= 4, "(the plain 4x enlargement steps 4 texels at a time: " .. maxStep(hard) .. ")")
  check(maxStep(sm) <= 2, "the reconstruction turns the staircase into a slope (largest step " .. maxStep(sm) .. ")")

  -- all four corner rules are mirror images of each other: smoothing a mirrored
  -- picture must equal mirroring the smoothed one (a single broken rule fails this)
  do
    local seed = 12345
    local function rnd(n) seed = (seed * 1103515245 + 12345) % 2147483648; return seed % n end
    local pal = { { 200, 0, 0 }, { 0, 0, 200 }, { 0, 200, 0 } }
    local pat = {}
    for i = 0, 63 do pat[i] = pal[rnd(3) + 1] end
    local base = imgOf(8, 8, function(x, y) return pat[y * 8 + x] end)
    local flipX = imgOf(8, 8, function(x, y) return pat[y * 8 + (7 - x)] end)
    local flipY = imgOf(8, 8, function(x, y) return pat[(7 - y) * 8 + x] end)
    local sb, sx, sy = S.smooth(base, 4, 0), S.smooth(flipX, 4, 0), S.smooth(flipY, 4, 0)
    local okX, okY = true, true
    for y = 0, 31 do
      for x = 0, 31 do
        if key(y * 32 + x, sx) ~= key(y * 32 + (31 - x), sb) then okX = false end
        if key(y * 32 + x, sy) ~= key((31 - y) * 32 + x, sb) then okY = false end
      end
    end
    check(okX and okY, "the reconstruction is mirror-symmetric (every EPX rule works)")
  end

  -- anti-alias: a hard vertical edge gets intermediate colours only with blur
  local edge = imgOf(8, 4, function(x, y) return (x < 4) and RED or BLUE end)
  local function distinctInRow(t)
    local seen, n = {}, 0
    for x = 0, t.w - 1 do local k = key(x, t); if not seen[k] then seen[k] = true; n = n + 1 end end
    return n
  end
  check(distinctInRow(S.smooth(edge, 4, 0)) == 2, "without blur a hard edge stays two colours")
  check(distinctInRow(S.smooth(edge, 4, 1)) >= 3, "with blur it is anti-aliased")

  -- not-art never colours the art: a lone red pixel in empty space
  local lone = imgOf(6, 6, function(x, y) return (x == 3 and y == 3) and RED or nil end)
  local sl = S.smooth(lone, 4, 1)
  local nSolid, offColour = 0, 0
  for i = 0, sl.w * sl.h - 1 do
    if sl.solid[i] then
      nSolid = nSolid + 1
      if key(i, sl) ~= 200 * 65536 then offColour = offColour + 1 end
    end
  end
  -- (EPX rounds the corners of an isolated block, so 12 of the 16 texels, not all 16)
  check(nSolid >= 8 and nSolid <= 16 and offColour == 0,
    "empty texels never bleed into the art (" .. nSolid .. " texels, " .. offColour .. " off-colour)")

  -- the baked atlas is smoother than a plain bake, and the scale is honoured
  local crgba, cw, ch = Fx.makeChibi()
  local function distinct(opts)
    local views, layout = Fx.viewsFor(S, crgba, cw, ch, 1)
    local r = assert(S.build(views, layout, opts))
    local seen, n = {}, 0
    for y = 0, 32 * r.scale - 1 do
      for x = 0, 32 * r.scale - 1 do
        local at = (y * r.atlasW + x) * 4
        local R, G, B, A = r.atlas:byte(at + 1, at + 4)
        if A >= 128 then
          local k = R * 65536 + G * 256 + B
          if not seen[k] then seen[k] = true; n = n + 1 end
        end
      end
    end
    return n, r
  end
  local nPlain, rPlain = distinct({ texScale = 1, texBlur = 0 })
  local nSmooth, rSmooth = distinct(nil)
  check(rPlain.scale == 1 and rPlain.atlasW == 32 and rPlain.atlasH == 160, "texScale = 1 is the old 32 x 160 atlas")
  check(rSmooth.scale == K and rSmooth.atlasW == 32 * K and rSmooth.atlasH == 160 * K, "the default atlas is " .. K .. "x the sprite")
  check(nSmooth > nPlain * 1.5, ("the smooth bake has far more tones along edges (%d vs %d)"):format(nSmooth, nPlain))
end

-- ------------------------------------------------------------------- jobs --
do
  local views, layout = Fx.viewsFor(S, rgba, imgW, imgH, 1)
  local now, resumes = 0, 0
  local job = S.newJob(views, layout, nil, function() now = now + 1; return now end)
  local done = false
  while not done and resumes < 100000 do
    done = job:step(5)          -- each clock read advances 1, so a slice is ~5 reads
    resumes = resumes + 1
  end
  check(done and job.result ~= nil, "a sliced job finishes with a result")
  check(resumes > 5, "and really was spread over many slices (" .. resumes .. ")")
  check(job.result.triangleCount == r1.triangleCount, "slicing does not change the mesh")
  check(job:step(1) == true, "stepping a finished job is harmless")
end

print(string.format("%d passed, %d failed", passes, fails))
os.exit(fails == 0 and 0 or 1)
