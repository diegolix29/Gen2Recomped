-- EMERALD'S SCRIPTED SCREEN EFFECTS, and the `waitstate` that waits for them.
--
-- On the cartridge `waitstate` stops the script until some task calls
-- ScriptContext_Enable -- the FIRST one to finish, whichever it is. This port's
-- waitstate only ever restored the fade, so a script that shook the camera and
-- waited ran straight on through its own shake. Here each effect that ends in
-- ScriptContext_Enable is counted while it runs, and waitstate parks the runner
-- until one of them reports (Gen3ScreenFx.wait / M.enable).
--
--   ShakeCamera (special 312, field_specials.c): VAR_0x8004 vertical pan,
--     0x8005 horizontal, 0x8006 number of shakes, 0x8007 frames between; the
--     camera itself pans (map AND sprites), the sign flipping each shake.
--   DoOrbEffect / FadeOutOrbEffect (284 / 285, field_screen_effect.c): BG0
--     filled with RGB_RED or RGB_BLUE, shown only inside a circular window that
--     grows from radius 1 to 160 by 2 every second frame around (x, 80) --
--     VAR_RESULT 0 red at 104, 1 blue at 136, 2 red at 120, else blue at 120 --
--     and blended over the scene at BLDALPHA (12, 7). Grown, the script is let
--     go and the camera rocks 4 px every 4 frames until FadeOutOrbEffect, which
--     steps the blend out (EVA down / EVB up, alternately, every 8 frames) and
--     lets the script go again when it reaches (0, 16).
--
-- The cartridge's camera holds the player at screen (112, 72), so screen
-- coordinates are placed relative to the player here, and a circle that has
-- finished growing tints the whole of this port's (wider) view.

local M = {}

-- Is anything running that will call ScriptContext_Enable? Read off the live
-- effects rather than counted, so an effect dropped by a map change can never
-- leave a waitstate parked for good.
function M.pending(ow)
  if not ow then return false end
  if ow.g3Shake and ow.g3Shake.counted then return true end
  local o = ow.g3Orb
  return o ~= nil and (o.state == "grow" or o.state == "fade")
end

-- ScriptContext_Enable: an effect is done; a parked waitstate resumes.
function M.enable(ow)
  local resume = ow.g3FxWaiter
  if resume then
    ow.g3FxWaiter = nil
    resume()
  end
end

-- `waitstate`: true when the runner should park (resume is called later).
function M.wait(ow, resume)
  if not M.pending(ow) then return false end
  ow.g3FxWaiter = resume
  return true
end

-- ---------------------------------------------------------------- shake --
-- `uncounted` for a shake no script waits on (the Mirage Tower's crumble
-- shake reports to its own task, not to the script).
function M.shakeCamera(ow, vertical, horizontal, shakes, delay, uncounted)
  shakes = math.floor(tonumber(shakes) or 0)
  delay = math.floor(tonumber(delay) or 0)
  if shakes <= 0 or delay <= 0 then return false end
  ow.g3Shake = { h = tonumber(horizontal) or 0, v = tonumber(vertical) or 0,
                 shakes = shakes, delay = delay, counter = 0, counted = not uncounted }
  return true
end

-- ------------------------------------------------------------------ orb --
M.ORB = {
  [0] = { blue = false, x = 104 }, [1] = { blue = true, x = 136 },
  [2] = { blue = false, x = 120 },
}

function M.orb(ow, result)
  local row = M.ORB[tonumber(result) or 3] or { blue = true, x = 120 }
  ow.g3Orb = { blue = row.blue, cx = row.x, cy = 80, radius = 1, phase = 0,
               state = "grow", eva = 12, evb = 7, dir = 0, delay = 0, pan = 0 }
end

function M.fadeOutOrb(ow)
  local o = ow.g3Orb
  if not o then return end
  o.state = "fade"
  o.delay = 8
  o.pan = 0
end

-- The window spans, as SetOrbFlashScanlineEffectWindowBoundaries writes them:
-- spans[y] = { left, right } in screen pixels, without the GBA's clamps.
function M.spans(cx, cy, radius)
  local out = {}
  local function set(y, l, r) out[y] = { l, r } end
  local r, v2, v3 = radius, radius, 0
  while r >= v3 do
    set(cy - v3, cx - r, cx + r)
    set(cy + v3, cx - r, cx + r)
    set(cy - r, cx - v3, cx + v3)
    set(cy + r, cx - v3, cx + v3)
    v2 = v2 - (v3 * 2 - 1)
    v3 = v3 + 1
    if v2 < 0 then
      v2 = v2 + 2 * (r - 1)
      r = r - 1
    end
  end
  return out
end

-- ---------------------------------------------------------------- frames --
function M.tick(ow)
  local s = ow.g3Shake
  if s then
    s.counter = s.counter + 1
    if s.counter % s.delay == 0 then
      s.counter = 0
      s.shakes = s.shakes - 1
      s.h, s.v = -s.h, -s.v
      ow.g3Pan = { x = s.h, y = s.v }
      if s.shakes <= 0 then
        ow.g3Shake = nil
        ow.g3Pan = nil
        if s.counted then M.enable(ow) end
      end
    end
  end
  local o = ow.g3Orb
  if o then
    if o.state == "grow" then
      -- UpdateOrbFlashEffect: draw, draw, then grow by 2 -- every second frame
      o.phase = 1 - o.phase
      if o.phase == 0 then
        o.radius = o.radius + 2
        if o.radius > 160 then
          o.state = "shake"; o.dir = 0; o.delay = 4
          M.enable(ow)
        end
      end
    elseif o.state == "shake" then
      o.delay = o.delay - 1
      if o.delay == 0 then
        o.delay = 4
        o.dir = 1 - o.dir
        o.pan = (o.dir == 1) and 4 or -4
      end
    elseif o.state == "fade" then
      o.delay = o.delay - 1
      if o.delay == 0 then
        o.delay = 8
        o.dir = 1 - o.dir
        if o.dir ~= 0 then
          if o.eva > 0 then o.eva = o.eva - 1 end
        elseif o.evb < 16 then
          o.evb = o.evb + 1
        end
        if o.eva == 0 and o.evb == 16 then
          ow.g3Orb = nil
          M.enable(ow)
        end
      end
    end
  end
end

-- The camera offset this frame: ShakeCamera's pan, plus the orb's rocking.
function M.pan(ow)
  local x, y = 0, 0
  if ow.g3Pan then x, y = x + ow.g3Pan.x, y + ow.g3Pan.y end
  if ow.g3Orb then y = y + (ow.g3Orb.pan or 0) end
  if x == 0 and y == 0 then return nil end
  return x, y
end

-- Over the whole view, under the text: the orb's tint inside its window.
-- GBA blending is A*EVA/16 + B*EVB/16, clamped: the scene is scaled down to
-- EVB/16 by a black wash, then the colour is ADDED at EVA/16.
function M.draw(ow, cam, vw, vh)
  local o = ow.g3Orb
  local p = ow.player
  if not (o and p) then return end
  local ox, oy = p.px - 112 - cam.x, p.py - 72 - cam.y   -- screen (0, 0) in view pixels
  local r, g, b = o.blue and 0 or 1, 0, o.blue and 1 or 0
  local function region(fn)
    if o.state ~= "grow" then
      fn(0, 0, vw, vh)
    else
      for y, span in pairs(M.spans(o.cx, o.cy, o.radius)) do
        if span[2] > span[1] then fn(ox + span[1], oy + y, span[2] - span[1], 1) end
      end
    end
  end
  love.graphics.setColor(0, 0, 0, 1 - math.min(16, o.evb) / 16)
  region(function(x, y, w, h) love.graphics.rectangle("fill", x, y, w, h) end)
  love.graphics.setBlendMode("add")
  love.graphics.setColor(r, g, b, o.eva / 16)
  region(function(x, y, w, h) love.graphics.rectangle("fill", x, y, w, h) end)
  love.graphics.setBlendMode("alpha")
  love.graphics.setColor(1, 1, 1, 1)
end

return M
