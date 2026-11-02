-- The parts of an ORAS move timeline that move the battle itself, not its
-- particles: where each Pokemon stands and how big it is, how dark the stage
-- is, and where the camera looks.  Baked by lib/ORASEffects.lua (entry.stage,
-- see stageRecord there), evaluated here at any frame, drawn by the 3D-BTL
-- scene (lib/ORASEffectsScene.lua, lib/Stadium.lua, lib/BattleScene.lua).
--
-- Pure functions, no state: everything is worked out again from the frame,
-- so it does not matter how often or from where it is asked.
--
-- Units: positions in ORAS centimetres in a side's own frame (x right, y up,
-- z toward the other side); the scene turns them into world units.
--
-- Afterimages: Double Team / Agility hop the Pokemon between places every
-- frame (Double Team: centre, +50, -50 cm, frames 45-70), which on the 3DS
-- reads as several see-through copies.  Played literally at 60 Hz that is a
-- jitter, so when the last three frames zig-zag the model stands at their
-- middle and the other places get a translucent ghost each.

local St = {}

St.GHOST_SPREAD = 20       -- cm the last three frames must span to count as a hop
St.GHOST_ALPHA = 0.45
St.FADE_OUT = 10           -- frames the camera / tint take to go back after the timeline

local function clamp(x, a, b) if x < a then return a elseif x > b then return b end return x end

local function progress(op, f)
  local span = math.max(1, op[2] - op[1] + 1)
  local u = clamp((f - op[1] + 1) / span, 0, 1)
  if op.ease == 2 then u = u * u * (3 - 2 * u) end
  return u
end

-- does this entry have anything for the scene to do
function St.has(entry)
  return type(entry) == "table" and type(entry.stage) == "table" and #entry.stage > 0
end

-- last frame anything in the stage list happens (plus the fade back)
function St.length(entry)
  local last = tonumber(entry and entry.frames) or 0
  for _, op in ipairs(St.has(entry) and entry.stage or {}) do
    if op[2] > last then last = op[2] end
  end
  return last + St.FADE_OUT
end

-- offset {x, y, z} (cm) and scale {x, y, z} of side `who` (0 / 1) at frame f
function St.pose(entry, who, f)
  local o, s = { 0, 0, 0 }, { 1, 1, 1 }
  if not St.has(entry) then return o, s end
  for _, op in ipairs(entry.stage) do
    if op[1] > f then break end
    if op.w == who then
      local u = progress(op, f)
      if op.k == "move" then
        for i = 1, 3 do o[i] = o[i] + op.v[i] * u end
      elseif op.k == "home" then
        for i = 1, 3 do o[i] = o[i] * (1 - u); s[i] = s[i] + (1 - s[i]) * u end
      elseif op.k == "scale" then
        for i = 1, 3 do s[i] = s[i] + (op.v[i] - s[i]) * u end
      end
    end
  end
  return o, s
end

local function dist(a, b)
  local x, y, z = a[1] - b[1], a[2] - b[2], a[3] - b[3]
  return math.sqrt(x * x + y * y + z * z)
end

-- { offset, scale, ghosts = { {x, y, z, alpha} ... } } of side `who`
-- at frame f (fractional)
function St.actor(entry, who, f)
  local off, sc = St.pose(entry, who, f)
  local out = { offset = off, scale = sc, ghosts = {} }
  if not St.has(entry) then return out end
  -- the last five frames: a hop phase turns back at least twice in them
  -- (Double Team: 0, +50, -50, 0, +50); a sway (frames 15-44, 5-7 frames
  -- a leg) or a dash (Fly, Quick Attack) at most once
  local fi = math.floor(f)
  if fi < 4 then return out end
  local p = {}
  for k = 0, 4 do p[k + 1] = St.pose(entry, who, fi - k) end
  local turns = 0
  for k = 1, 3 do
    local a, b, c = p[k], p[k + 1], p[k + 2]
    local dot = (a[1] - b[1]) * (b[1] - c[1]) + (a[2] - b[2]) * (b[2] - c[2]) + (a[3] - b[3]) * (b[3] - c[3])
    if dot < 0 and dist(a, b) > St.GHOST_SPREAD * 0.5 and dist(b, c) > St.GHOST_SPREAD * 0.5 then
      turns = turns + 1
    end
  end
  if turns < 2 then return out end
  -- its distinct places: the model stands at their middle, a ghost on each
  local places = {}
  for _, q in ipairs(p) do
    local same = false
    for _, s in ipairs(places) do if dist(q, s) < 5 then same = true; break end end
    if not same then places[#places + 1] = q end
  end
  local mid = { 0, 0, 0 }
  for _, q in ipairs(places) do for i = 1, 3 do mid[i] = mid[i] + q[i] / #places end end
  out.offset = mid
  for _, q in ipairs(places) do
    if dist(q, mid) > St.GHOST_SPREAD * 0.5 then
      out.ghosts[#out.ghosts + 1] = { q[1] - mid[1], q[2] - mid[2], q[3] - mid[3], St.GHOST_ALPHA }
    end
  end
  return out
end

-- stage colour {r, g, b, a} at frame f, or nil when clear
function St.tint(entry, f)
  if not St.has(entry) then return nil end
  local c, any = { 0, 0, 0, 0 }, false
  for _, op in ipairs(entry.stage) do
    if op[1] > f then break end
    if op.k == "tint" then
      any = true
      local u = progress(op, f)
      for i = 1, 4 do c[i] = c[i] + (op.v[i] - c[i]) * u end
    end
  end
  if not any then return nil end
  local endAt = tonumber(entry.frames) or 0
  if f > endAt then c[4] = c[4] * clamp(1 - (f - endAt) / St.FADE_OUT, 0, 1) end
  if c[4] <= 0.004 then return nil end
  return c
end

-- camera at frame f: { eye, look } built by place(op) -> eye, look (world),
-- blended from `default` ({eye, look}); nil when the move has no camera.
function St.camera(entry, f, default, place)
  if not St.has(entry) then return nil end
  local eye = { default.eye[1], default.eye[2], default.eye[3] }
  local look = { default.look[1], default.look[2], default.look[3] }
  local any = false
  for _, op in ipairs(entry.stage) do
    if op[1] > f then break end
    if op.k == "cam" then
      local ok, e, l = pcall(place, op)
      if ok and e and l then
        any = true
        local u = progress(op, f)
        u = u * u * (3 - 2 * u)
        for i = 1, 3 do
          eye[i] = eye[i] + (e[i] - eye[i]) * u
          look[i] = look[i] + (l[i] - look[i]) * u
        end
      end
    end
  end
  if not any then return nil end
  local endAt = tonumber(entry.frames) or 0
  local w = 1
  if f > endAt then
    w = clamp(1 - (f - endAt) / St.FADE_OUT, 0, 1)
    w = w * w * (3 - 2 * w)
  end
  for i = 1, 3 do
    eye[i] = default.eye[i] + (eye[i] - default.eye[i]) * w
    look[i] = default.look[i] + (look[i] - default.look[i]) * w
  end
  return { eye = eye, look = look, weight = w }
end

return St
