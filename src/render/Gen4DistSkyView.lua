-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE DISTORTION WORLD'S SKY, drawn the way overlay 9 draws it.
--
-- Reported from play: "The sky doesn't darken during Giratina's arrival."
-- The pictures are Gen4DistSky's (tw_arc_etc); this is the behaviour:
--
--   * BACKGROUND: one 256x192 screen on main BG2, behind the 3D plane
--     (BG0 priority 2, BG2 priority 3).  It does not scroll.
--   * CLOUDS: nine sprites (sSkyCloudsTemplates) on OBJ priority 3 -- over the
--     background, under the 3D -- each turning about its template's centre at
--     distToCenter pixels, its own rotation the orbit angle plus
--     rotAngleOffset.  The orbit speed is the template's base plus a per-group
--     extra for the sky kind (sSkyCloudsRotAngleDeltas), eased toward a new
--     kind by 0x200 (1/8 degree) a frame.
--   * DARKNESS (RecalculateSkyBackgroundDarkness): level 0..12 from the
--     player's height between y 65 and 289 tiles, unless an event holds it
--     (Giratina's arrival, and the Giratina room once he has arrived); both
--     pictures are tinted, background toward GX_RGB(4,4,8) and clouds toward
--     GX_RGB(6,6,8), by level/16 (CalculateTintedColor).
-- All per cartridge field frame, 30 a second.

local Assets = require("src.render.Assets")

local V = {}

V.MIN_Y, V.MAX_Y, V.MAX_DARKNESS = 65, 289, 12
V.BG_TINT = { 4 / 31, 4 / 31, 8 / 31 }
V.CLOUD_TINT = { 6 / 31, 6 / 31, 8 / 31 }

V.NORMAL, V.GIRATINA_ROOM, V.GIRATINA_ROOM_DARK = 0, 1, 2
-- sSkyCloudsRotAngleDeltas[skyKind][group], degrees a frame
V.KIND_DELTAS = {
  [0] = { [0] = 0, 0, 0, 0 },
  [1] = { [0] = 0.5, 1.5, 3, 5 },
  [2] = { [0] = -2, -4.5, -7, -12.5 },
}
-- sSkyCloudsTemplates: res, group, initial angle, angle offset, distance,
-- base speed, centre x, y, scale
V.CLOUDS = {
  { res = 6, group = 3, angle = 0,   offset = 135, dist = 0x68, speed = 1.25, x = 128, y = 108, scale = 2 },
  { res = 6, group = 3, angle = 180, offset = 135, dist = 0x68, speed = 1.25, x = 128, y = 108, scale = 2 },
  { res = 6, group = 3, angle = 90,  offset = 135, dist = 0x68, speed = 1.25, x = 128, y = 108, scale = 2 },
  { res = 6, group = 3, angle = 270, offset = 135, dist = 0x68, speed = 1.25, x = 128, y = 108, scale = 2 },
  { res = 1, group = 2, angle = 0,   offset = 90,  dist = 0x3C, speed = 1,    x = 128, y = 128, scale = 1 },
  { res = 2, group = 2, angle = 180, offset = 90,  dist = 0x3C, speed = 1,    x = 128, y = 128, scale = 1 },
  { res = 3, group = 1, angle = 315, offset = 90,  dist = 0x2A, speed = 0.75, x = 128, y = 128, scale = 1 },
  { res = 4, group = 1, angle = 135, offset = 90,  dist = 0x2A, speed = 0.75, x = 128, y = 128, scale = 1 },
  { res = 5, group = 0, angle = 0,   offset = 90,  dist = 0,    speed = 0.5,  x = 128, y = 128, scale = 1 },
}

local function Game() return package.loaded["src.core.Game"] end

local function skyData()
  local G = Game()
  local dw = G and G.data and G.data.gen4_distortion_world
  return dw and dw.sky
end

local images = {}
local function image(entry)
  if not (entry and entry.path) then return nil end
  if images[entry.path] == nil then
    local ok, img = pcall(Assets.image, entry.path)
    images[entry.path] = (ok and img) or false
    if ok and img then img:setFilter("nearest", "nearest") end
  end
  return images[entry.path] or nil
end

-- CalculateTintedColor as a mix, for the sprites (the background is covered
-- by one rectangle, which is the same arithmetic)
local shader
local function tintShader()
  if shader == nil then
    local ok, s = pcall(love.graphics.newShader, [[
      extern vec3 tint;
      extern number amount;
      vec4 effect(vec4 colour, Image tex, vec2 tc, vec2 sc) {
        vec4 p = Texel(tex, tc);
        return vec4(mix(p.rgb, tint, amount), p.a * colour.a);
      }
    ]])
    shader = ok and s or false
  end
  return shader or nil
end

-- the state of one visit: per-cloud angles and eased speeds, the kind, the
-- darkness and whether an event holds it
V.state = nil

function V.reset(kind)
  local st = { kind = kind or V.NORMAL, clouds = {}, darkness = 0, held = false, tick = 0 }
  for i, c in ipairs(V.CLOUDS) do
    st.clouds[i] = { angle = c.angle, extra = V.KIND_DELTAS[st.kind][c.group] }
  end
  V.state = st
  return st
end

-- InitSkyCloudAnimators / InitSkyBackgroundDarkness for a floor
function V.enter(def, progress)
  local kind = V.NORMAL
  progress = tonumber(progress) or 0
  if def and def.gen4DistWorld == "giratina" and progress >= 10 then
    kind = (progress <= 12) and V.GIRATINA_ROOM or ((progress <= 13) and V.GIRATINA_ROOM_DARK or V.NORMAL)
  end
  local st = V.reset(kind)
  if def and def.gen4DistWorld == "giratina" and progress == 13 then
    st.held, st.darkness = true, V.MAX_DARKNESS
  end
  st.def = def
  return st
end

function V.setKind(kind) if V.state then V.state.kind = kind end end
-- SetSkyBackgroundDarknessCalculationDisabled + SetSkyBackgroundDarknessLevel
function V.hold(level)
  if not V.state then return end
  V.state.held = true
  V.state.darkness = math.max(0, math.min(V.MAX_DARKNESS, math.floor(level or 0)))
end
function V.release() if V.state then V.state.held = false end end

local function wrap(a) a = a % 360; if a < 0 then a = a + 360 end; return a end

-- one cartridge frame; `worldY` is the player's height in world units (a tile
-- is 16), or nil to leave the darkness where it is
function V.frame(worldY)
  local st = V.state
  if not st then return end
  st.tick = st.tick + 1
  for i, c in ipairs(V.CLOUDS) do
    local cs = st.clouds[i]
    local want = V.KIND_DELTAS[st.kind][c.group]
    if want < cs.extra then cs.extra = math.max(want, cs.extra - 0.125)
    elseif want > cs.extra then cs.extra = math.min(want, cs.extra + 0.125) end
    cs.angle = wrap(cs.angle + c.speed + cs.extra)
  end
  if not st.held and worldY then
    -- the overlay's own integer division
    local level = math.floor((worldY - V.MIN_Y * 16) / (((V.MAX_Y - V.MIN_Y) * 16) / V.MAX_DARKNESS))
    st.darkness = math.max(0, math.min(V.MAX_DARKNESS, level))
  end
end

local function cloudCell(rec, tick)
  local frames = rec.frames
  local index = 0
  if frames and #frames > 1 then
    local total = 0
    for _, f in ipairs(frames) do total = total + (f.duration or 0) end
    if total > 0 then
      local t = tick % total
      for _, f in ipairs(frames) do
        t = t - (f.duration or 0)
        if t < 0 then index = f.cell or 0; break end
      end
    end
  elseif frames and frames[1] then
    index = frames[1].cell or 0
  end
  return rec.cells and rec.cells[index + 1]
end

-- draws over a cleared target of w x h pixels; true when it drew
function V.draw(w, h)
  local sky = skyData()
  local st = V.state
  if not (sky and st) or (os.getenv and os.getenv("DWNOSKY")) then return false end
  local g = love.graphics
  local s = h / 192
  local left = (w - 256 * s) / 2
  local amount = st.darkness / 16
  g.push("all")
  -- the backdrop colour, then the background repeated across a wide view (a
  -- BG screen wraps at 256)
  local bd = sky.backdrop or { 0, 0, 0 }
  g.setColor(bd[1] / 255, bd[2] / 255, bd[3] / 255, 1)   -- Gen4Graphics.palette's bytes
  g.rectangle("fill", 0, 0, w, h)
  local bg = image(sky.background)
  if bg then
    g.setColor(1, 1, 1, 1)
    local quad = g.newQuad(0, 0, 256, 192, bg:getDimensions())
    local x0 = left - math.ceil(left / (256 * s)) * 256 * s
    local x = x0
    while x < w do
      g.draw(bg, quad, x, 0, 0, s, s)
      x = x + 256 * s
    end
  end
  if amount > 0 then
    g.setColor(V.BG_TINT[1], V.BG_TINT[2], V.BG_TINT[3], amount)
    g.rectangle("fill", 0, 0, w, h)
  end
  -- the clouds
  local sh = tintShader()
  if sh then
    g.setShader(sh)
    sh:send("tint", V.CLOUD_TINT)
    sh:send("amount", amount)
  end
  g.setColor(1, 1, 1, 1)
  for i, c in ipairs(V.CLOUDS) do
    local rec = sky.clouds and sky.clouds[c.res + 1]
    local entry = rec and cloudCell(rec, st.tick)
    local img = entry and image(entry)
    if img then
      local a = st.clouds[i].angle
      local r = math.rad(a)
      local cx = c.x + math.cos(r) * c.dist
      local cy = c.y + math.sin(r) * c.dist
      g.draw(img, left + cx * s, cy * s, math.rad(wrap(a + c.offset)), c.scale * s, c.scale * s,
             entry.ox or 0, entry.oy or 0)
    end
  end
  g.pop()
  return true
end

return V
