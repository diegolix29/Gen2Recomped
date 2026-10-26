-- BLACK AND WHITE'S MESH WIPES: the into-battle effects that draw the captured
-- field on geometry they build themselves, under overlay 75's runner (the two
-- white flashes, the capture, then the effect's own init and step).
--
-- RIPPLE, overlay 78 (effects 2 and 36). The screen as a 33 x 25 grid of
-- vertices, one every 8 pixels, each with a height and a velocity (s16,
-- 1/4096). A step (0x021F5950): the neighbours' average (zero past the edge)
-- less the height is added to the velocity, the velocity to the height,
-- clamped to +-1, and the border pinned at 0 -- a wave with no damping. A
-- counter drops `amp` on the centre vertex (16, 12) every `period` + 1 ticks,
-- `drops` times. Drawn (0x021F5800) as quad strips at
-- MTX_TRANS(-16, 12, 0) MTX_SCALE(16, 16, 64): a 32 x 24 plane, its height
-- 64 times over, seen from (0, 0, 33) at the 19.96-degree half-FOV -- which is
-- exactly the screen while it is flat.
--   effect 2   amp 0x400, period 8, 7 drops, then done;  the fade (both
--              screens to white) starts after 50 ticks
--   effect 36  amp 0x555, period 2, 7 drops, then 45 ticks; to black after 55
--
-- PANELS, overlay 77 with 79 / 80 / 81 (effects 7, 9, 8). The screen cut into
-- tiles of tw x th 8-pixel cells, each a quad of its own picture at its own
-- place (MTX_TRANS(x, y, 0) MTX_SCALE(w / 8, h / 8, 1), a +-4 quad, turned
-- about Y), front faces only, over a cleared screen, seen from (0, 0, 264) --
-- one unit a pixel. A scheduler starts panels; each runs until it says it is
-- done; then both screens fade (to white over a white clear, to black over a
-- black one).
--   effect 7  (ov79) 32 x 32 panels, one started a tick in reading order;
--             each turns a full turn and a half, 1/16 turn a tick; black
--   effect 9  (ov80) 16 x 16 panels, a column started every other tick;
--             each turns half a turn over 64 ticks; white
--   effect 8  (ov81) 16 x 16 panels started by a flood from panels 51, 149
--             and 91, a ring every other tick; each flies right, 1, 2, 3 ...
--             pixels a tick, turning 1/128 turn a tick, until x = 256; white

local W = {}

local floor, max, min, sin, cos, pi = math.floor, math.max, math.min, math.sin, math.cos, math.pi

W.TAN_Y = 1398 / 3850
W.ASPECT = 0x1555 / 4096

local function trunc(x) if x >= 0 then return floor(x) end return -floor(-x) end
local function s16(v) v = v % 65536 if v >= 32768 then v = v - 65536 end return v end

W.RIPPLE = {
  [2] = { amp = 0x400, period = 8, drops = 7, after = 0, delay = 50, white = true },
  [36] = { amp = 0x555, period = 2, drops = 7, after = 45, delay = 55, white = false },
}
W.PANELS = {
  [7] = { tw = 4, th = 4, sched = "one", panel = "spin", white = false },
  [9] = { tw = 2, th = 2, sched = "column", panel = "turn", white = true },
  [8] = { tw = 2, th = 2, sched = "flood", panel = "blow", white = true, seeds = { 51, 149, 91 } },
}

function W.handles(id) return W.RIPPLE[id] ~= nil or W.PANELS[id] ~= nil end

-- ---------------------------------------------------------------------------
-- The ripple
-- ---------------------------------------------------------------------------

local COLS, ROWS = 33, 25

local function rippleNew(p)
  local R = { kind = "ripple", p = p, h = {}, v = {}, delay = p.delay, fading = false,
              left = p.drops, wait = 0, post = nil, done = false }
  for i = 0, COLS * ROWS - 1 do R.h[i] = 0; R.v[i] = 0 end
  return R
end

-- 0x021F5950: true when the drops are over
local function rippleSim(R)
  local p = R.p
  if R.left > 0 then
    if R.wait == 0 then
      R.h[12 * COLS + 16] = s16(p.amp)
      R.wait = p.period
      R.left = R.left - 1
    else
      R.wait = R.wait - 1
    end
    if R.left <= 0 then
      if p.after == 0 then R.wait = 6 return true end
      R.wait = p.after
    end
  else
    R.wait = R.wait - 1
    if R.wait <= 0 then R.wait = 6 return true end
  end
  local h, v = R.h, R.v
  local old = {}
  for i = 0, COLS * ROWS - 1 do old[i] = h[i] end
  for i = 0, COLS * ROWS - 1 do
    local x, y = i % COLS, floor(i / COLS)
    local sum = (x > 0 and old[i - 1] or 0) + (x < COLS - 1 and old[i + 1] or 0)
              + (y > 0 and old[i - COLS] or 0) + (y < ROWS - 1 and old[i + COLS] or 0)
    local dv = s16(trunc(sum / 4) - h[i])
    v[i] = s16(v[i] + dv)
    local nh = s16(h[i] + v[i])
    if nh > 4096 then nh = 4096 elseif nh < -4096 then nh = -4096 end
    if x == 0 or x == COLS - 1 or y == 0 or y == ROWS - 1 then nh = 0 end
    h[i] = nh
  end
  return false
end

-- one tick of the effect's task (0x021F5748); `fade(white)` starts the
-- two-screen fade, `fadeDone()` asks after it. True when finished.
local function rippleStep(R, fade, fadeDone)
  if not R.post then
    if R.delay > 0 then
      R.delay = R.delay - 1
    elseif not R.fading then
      fade(R.p.white)
      R.fading = true
    end
    if rippleSim(R) then R.post = 6 end
    return false
  end
  if R.post > 0 then R.post = R.post - 1 return false end
  return fadeDone()
end

-- ---------------------------------------------------------------------------
-- The panels
-- ---------------------------------------------------------------------------

local function panelsNew(p)
  local pw, ph = p.tw * 8, p.th * 8
  local cols, rows = floor(32 / p.tw), floor(24 / p.th)
  local P = { kind = "panels", p = p, pw = pw, ph = ph, cols = cols, rows = rows, list = {},
              idx = 0, wait = 0, activated = 0, finished = false, current = {}, pending = {} }
  local ox = pw * floor(cols / 2) - floor(pw / 2)
  local oy = ph * floor(rows / 2) - floor(ph / 2)
  for i = 0, cols * rows - 1 do
    P.list[i] = { x = (i % cols) * pw - ox, y = oy - floor(i / cols) * ph, z = 0,
                  rot = 0, phase = 0, vel = 0, active = false, done = false }
  end
  if p.seeds then for _, s in ipairs(p.seeds) do P.pending[#P.pending + 1] = s end end
  return P
end

local PANEL = {}
-- ov79 0x021F5B24
function PANEL.spin(e)
  if e.phase == 0 then
    e.rot = e.rot + 0x1000
    if e.rot >= 0x10000 then e.rot = e.rot - 0x10000; e.phase = 1 end
  elseif e.phase == 1 then
    e.rot = e.rot + 0x1000
    if e.rot >= 0x8000 then e.rot = 0x8000; e.phase = 2 end
  else
    e.done = true
  end
  return e.done
end
-- ov80 0x021F5B44
function PANEL.turn(e)
  if e.phase < 64 then e.rot = e.rot + 0x200; e.phase = e.phase + 1 else e.done = true end
  return e.done
end
-- ov81 0x021F5B94
function PANEL.blow(e)
  if e.x < 256 then
    e.z = 1
    e.x = e.x + e.vel
    e.vel = e.vel + 1
    if e.rot < 0x8000 then e.rot = e.rot + 0x200 end
  else
    e.done = true
  end
  return e.done
end

local SCHED = {}
-- ov79 0x021F5AE4
function SCHED.one(P)
  if P.idx < P.cols * P.rows then
    if P.wait == 0 then
      P.list[P.idx].active = true
      P.idx = P.idx + 1
      P.wait = 0
    else
      P.wait = P.wait - 1
    end
  end
end
-- ov80 0x021F5AE8
function SCHED.column(P)
  if P.idx < P.cols then
    if P.wait == 0 then
      for r = 0, P.rows - 1 do P.list[P.idx + P.cols * r].active = true end
      P.idx = P.idx + 1
      P.wait = 1
    else
      P.wait = P.wait - 1
    end
  end
end
-- ov81 0x021F5B30 / 0x021F5C3C / 0x021F5CA0
function SCHED.flood(P)
  if P.activated >= P.cols * P.rows then return end
  if P.wait ~= 0 then P.wait = P.wait - 1 return end
  local queued = {}
  for _, i in ipairs(P.pending) do queued[i] = true end
  local function add(x, y)
    local i = y * P.cols + x
    if not P.list[i].active and not queued[i] then
      queued[i] = true
      P.pending[#P.pending + 1] = i
    end
  end
  for _, i in ipairs(P.current) do
    local x, y = i % P.cols, floor(i / P.cols)
    if y - 1 >= 0 then add(x, y - 1) end
    if x + 1 < P.cols then add(x + 1, y) end
    if y + 1 < P.rows then add(x, y + 1) end
    if x - 1 >= 0 then add(x - 1, y) end
  end
  local now = {}
  for _, i in ipairs(P.pending) do
    local e = P.list[i]
    if not e.active then
      e.active = true
      e.vel = 1
      P.activated = P.activated + 1
    end
    now[#now + 1] = i
  end
  P.current, P.pending = now, {}
  P.wait = 1
end

-- 0x021F5798: the scheduler, then every live panel; true when all are done
local function panelsRun(P)
  SCHED[P.p.sched](P)
  local done, fn = 0, PANEL[P.p.panel]
  for i = 0, P.cols * P.rows - 1 do
    local e = P.list[i]
    if e.done then done = done + 1
    elseif e.active and fn(e) then done = done + 1 end
  end
  return done >= P.cols * P.rows
end

-- 0x021F5744
local function panelsStep(P, fade, fadeDone)
  if not P.finished then
    if panelsRun(P) then P.finished = true; fade(P.p.white) end
    return false
  end
  return fadeDone()
end

-- ---------------------------------------------------------------------------
-- The shared surface
-- ---------------------------------------------------------------------------

function W.new(id)
  if W.RIPPLE[id] then return rippleNew(W.RIPPLE[id]) end
  if W.PANELS[id] then return panelsNew(W.PANELS[id]) end
  return nil
end

function W.step(S, fade, fadeDone)
  if S.kind == "ripple" then return rippleStep(S, fade, fadeDone) end
  return panelsStep(S, fade, fadeDone)
end

-- the screen behind the geometry
function W.clearWhite(S) return S.kind == "panels" and S.p.white or false end

local meshFormat = { { "VertexPosition", "float", 2 }, { "VertexTexCoord", "float", 2 } }

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

-- polys: lists of camera-space points {x, y, depth, u, v}; drawn far first,
-- `cull` dropping the ones that turn their back on the camera
local function drawPolys(polys, texture, ox, oy, k, cull)
  local tx, ty = W.TAN_Y * W.ASPECT, W.TAN_Y
  local items = {}
  for _, poly in ipairs(polys) do
    local d = 0
    for _, q in ipairs(poly) do d = d + q[3] end
    d = d / #poly
    local clipped = poly
    for _, q in ipairs(poly) do if q[3] < 1 then clipped = clipNear(poly, 1) break end end
    if #clipped >= 3 then items[#items + 1] = { clipped, d } end
  end
  table.sort(items, function(a, b) return a[2] > b[2] end)
  local verts = {}
  for _, it in ipairs(items) do
    local P = it[1]
    local scr = {}
    for j, q in ipairs(P) do
      scr[j] = { ox + (128 + 128 * q[1] / (q[3] * tx)) * k, oy + (96 - 96 * q[2] / (q[3] * ty)) * k, q[4], q[5] }
    end
    local keep = true
    if cull then
      local area = 0
      for j = 1, #scr do
        local a, b = scr[j], scr[j % #scr + 1]
        area = area + a[1] * b[2] - b[1] * a[2]
      end
      -- the quads are wound top-left, bottom-left, bottom-right, top-right:
      -- clockwise on a y-down screen while they face the camera
      keep = area < 0
    end
    if keep then
      for j = 2, #scr - 1 do
        verts[#verts + 1] = scr[1]; verts[#verts + 1] = scr[j]; verts[#verts + 1] = scr[j + 1]
      end
    end
  end
  if #verts == 0 then return end
  local mesh = love.graphics.newMesh(meshFormat, verts, "triangles", "stream")
  mesh:setTexture(texture)
  love.graphics.draw(mesh)
  mesh:release()
end

-- draw(S, texture, ox, oy, k, uvRect): the effect's picture of the screen at
-- (ox, oy), k pixels to the DS pixel; uvRect is the part of `texture` that is
-- the screen
function W.draw(S, texture, ox, oy, k, uv)
  local u0, v0, u1, v1 = 0, 0, 1, 1
  if uv then u0, v0, u1, v1 = uv[1], uv[2], uv[3], uv[4] end
  local function U(px) return u0 + px / 256 * (u1 - u0) end
  local function V(py) return v0 + py / 192 * (v1 - v0) end
  local polys = {}
  if S.kind == "ripple" then
    local eye = 33
    local function pt(c, r)
      local hz = S.h[r * COLS + c] / 4096 * 64
      return { c - 16, 12 - r, eye - hz, U(c * 8), V(r * 8) }
    end
    for r = 0, ROWS - 2 do
      for c = 0, COLS - 2 do
        polys[#polys + 1] = { pt(c, r), pt(c, r + 1), pt(c + 1, r + 1), pt(c + 1, r) }
      end
    end
    drawPolys(polys, texture, ox, oy, k, false)
    return
  end
  local eye = 264
  local hw, hh = S.pw / 2, S.ph / 2
  for i = 0, S.cols * S.rows - 1 do
    local e = S.list[i]
    local a = e.rot / 65536 * 2 * pi
    local c, s = cos(a), sin(a)
    local s0, t0 = (i % S.cols) * S.pw, floor(i / S.cols) * S.ph
    local function corner(lx, ly, su, tv)
      -- MTX_RotY33 as a row vector: x' = x cos, z' = -x sin
      local wx, wz = e.x + lx * c, e.z + (-lx * s)
      return { wx, e.y + ly, eye - wz, U(su), V(tv) }
    end
    polys[#polys + 1] = { corner(-hw, hh, s0, t0), corner(-hw, -hh, s0, t0 + S.ph),
                          corner(hw, -hh, s0 + S.pw, t0 + S.ph), corner(hw, hh, s0 + S.pw, t0) }
  end
  drawPolys(polys, texture, ox, oy, k, true)
end

return W
