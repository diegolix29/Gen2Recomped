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

-- texture projection: every vertex lands on body colour in the padded atlas,
-- and each picture is used where it faces
do
  local onClear, perFrame = 0, {}
  local bestZ, bestZframe = -math.huge, nil
  local bestNZ, bestNZframe = math.huge, nil
  local bestX, bestXframe = -math.huge, nil
  local bestNX, bestNXframe = math.huge, nil
  for _, v in ipairs(r1.verts) do
    local x, y = math.min(math.floor(v[4] * imgW), imgW - 1), math.min(math.floor(v[5] * imgH), imgH - 1)
    if alphaAt(padded, x, y) < 128 then onClear = onClear + 1 end
    local frame = math.floor(y / Fx.H)
    perFrame[frame] = (perFrame[frame] or 0) + 1
    if v[3] > bestZ then bestZ, bestZframe = v[3], frame end
    if v[3] < bestNZ then bestNZ, bestNZframe = v[3], frame end
    if v[1] > bestX then bestX, bestXframe = v[1], frame end
    if v[1] < bestNX then bestNX, bestNXframe = v[1], frame end
  end
  check(onClear == 0, "no vertex samples a transparent texel (" .. onClear .. ")")
  check(bestZframe == Fx.facings.down[1], "the most forward point wears the SOUTH picture")
  check(bestNZframe == Fx.facings.up[1], "the most rearward point wears the NORTH picture")
  -- +x is the body's LEFT (it faces +z): that is the WEST sprite; -x the EAST one
  check(bestXframe == Fx.facings.left[1], "the +x flank wears the WEST picture")
  check(bestNXframe == Fx.facings.right[1], "the -x flank wears the EAST picture")
  local used = 0
  for _, f in ipairs({ 0, 3, 6, 9 }) do if (perFrame[f] or 0) > 20 then used = used + 1 end end
  check(used == 4, "all four pictures are used")
end

-- the UV is exactly the documented planar projection for the picture a vertex
-- wears (independent of how symmetric the art happens to be)
do
  local viewOf = {}
  for _, f in ipairs(Fx.facings.down) do viewOf[f] = "front" end
  for _, f in ipairs(Fx.facings.up) do viewOf[f] = "back" end
  for _, f in ipairs(Fx.facings.left) do viewOf[f] = "left" end
  for _, f in ipairs(Fx.facings.right) do viewOf[f] = "right" end
  local colFor = {
    front = function(x, z) return x + 16 end, back = function(x, z) return -x + 16 end,
    right = function(x, z) return z + 16 end, left = function(x, z) return -z + 16 end,
  }
  local worst = 0
  for _, v in ipairs(r1.verts) do
    local frame = math.floor(v[5] * imgH / Fx.H)
    local want = colFor[viewOf[frame]](v[1], v[3])
    want = math.max(0.5, math.min(31.5, want))
    local row = math.max(0.5, math.min(31.5, r1.base + 1 - v[2]))
    worst = math.max(worst, math.abs(v[4] * imgW - want), math.abs(v[5] * imgH - frame * Fx.H - row))
  end
  check(worst < 1e-3, "every UV is the planar projection of its vertex (worst error " .. worst .. ")")
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
  local empty = {}
  for k, v in pairs(views) do
    local e = { w = v.w, h = v.h }
    for i = 1, v.w * v.h do e[i] = false end
    empty[k] = e
  end
  r, why = S.build(empty, layout)
  check(r == nil and why, "an empty sprite is refused, not crashed on")
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
