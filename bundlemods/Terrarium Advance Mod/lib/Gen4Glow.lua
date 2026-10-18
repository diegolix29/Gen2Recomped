-- Gen4Glow: firefly glows that respect the scene's DEPTH.
--
-- THE PROBLEM
--
-- Two things drew fireflies with no idea what was in front of them:
--   * AmbientLife paints its critters as flat 2D rectangles (Host.project turns
--     a world point into a screen point and a rectangle goes there), so a firefly
--     behind a tree or a building was painted over the tree or the building;
--   * the night glow (Gen4Tint.addGlow) is repainted AFTER the frame has been
--     blitted, to keep Gen4Tint's night multiply from turning it into a dim
--     speck, and by then there is no depth at all.
-- (Flora's 3D firefly billboards are depth-tested and were never the problem; it
-- is their glow that goes through the same sink.)
--
-- THE FIX
--
-- Each glow now carries its WORLD position. While the finished scene's colour +
-- depth are still on the engine's canvas (Gen4Bridge.after), every glow is drawn
-- into a transparent LAYER canvas by a shader that reads the scene depth under each
-- of its pixels, rebuilds that point's distance from the eye (the same
-- invVP * (uv, depth) maths Gen4Haze and RayFX use) and hides the glow wherever
-- the scene is nearer than the glow by more than a small margin. The layer is
-- handed to Gen4Tint, which paints it additive after the night multiply, exactly
-- where the old unoccluded glows went.
--
-- A glow is a soft halo plus a small hot core (the core replaces the flat
-- rectangle AmbientLife used to draw). The margin grows with the glow's size: a
-- halo hanging over the grass would otherwise be clipped by the ground just
-- below it, which is nearer the camera than the firefly.
--
-- FALLBACK. No readable depth (see Gen4Haze / Gen4Reflect), no shader, the
-- cartridge camera (no Bridge.after): the layer is not produced, Gen4Tint keeps
-- its old unoccluded glow list, and nothing breaks; fireflies simply show through
-- again. One log line says why.

local V = ...

local Glow = {
  enabled = true,
  BIAS = 6,            -- units of slack before a nearer surface hides a glow
  BIAS_PER_RADIUS = 0.5,   -- plus this many units per pixel of glow radius
  MAX = 96,
  status = "idle",
}

local pending = {}        -- this frame's glows, filled by the host's sink
local layer, layerW, layerH
local shader, shaderFailed, haloImg

local warned = {}
local function once(key, fmt, ...)
  if warned[key] then return end
  warned[key] = true
  if V.mod and V.mod.log then V.mod.log:info("Gen4Glow: " .. fmt:format(...)) end
end

local function optional(name)
  local ok, mod = pcall(V.require, name)
  return ok and mod or nil
end

local SHADER = [[
  uniform Image depthTex;
  uniform highp mat4 invVP;
  uniform highp vec3 eye;
  uniform highp vec2 centre;      // the glow's centre, in canvas uv
  uniform highp vec2 halfSize;    // half the glow quad, in canvas uv
  uniform highp float dist;       // the glow's distance from the eye (0 = always show)
  uniform highp float bias;

  vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
    vec4 px = Texel(tex, uv) * color;
    if (px.a <= 0.001) return vec4(0.0);
    if (dist > 0.0) {
      vec2 suv = centre + (uv - 0.5) * 2.0 * halfSize;
      float d = Texel(depthTex, suv).r;
      if (d < 0.9999) {                       // 1.0 is the cleared depth: sky
        vec4 c = invVP * vec4(suv * 2.0 - 1.0, d * 2.0 - 1.0, 1.0);
        vec3 P = c.xyz / c.w;
        if (length(P - eye) + bias < dist) return vec4(0.0);   // something is in front
      }
    }
    return px;
  }
]]

local function getShader()
  if shader then return shader end
  if shaderFailed then return nil end
  local ok, sh = pcall(love.graphics.newShader, SHADER)
  if not (ok and sh) then
    shaderFailed = true
    once("shader", "the glow shader would not compile: %s", tostring(sh))
    return nil
  end
  shader = sh
  return shader
end

-- a white disc with a quadratic alpha falloff
local function halo()
  if haloImg then return haloImg end
  local ok, img = pcall(function()
    local n = 64
    local data = love.image.newImageData(n, n)
    for y = 0, n - 1 do
      for x = 0, n - 1 do
        local dx, dy = (x + 0.5) / n * 2 - 1, (y + 0.5) / n * 2 - 1
        local r = math.sqrt(dx * dx + dy * dy)
        local a = r < 1 and (1 - r) * (1 - r) or 0
        data:setPixel(x, y, 1, 1, 1, a)
      end
    end
    local i = love.graphics.newImage(data)
    i:setFilter("linear", "linear")
    return i
  end)
  if ok then haloImg = img end
  return haloImg
end

local function ensureLayer(w, h)
  if layer and layerW == w and layerH == h then return layer end
  local ok, c = pcall(love.graphics.newCanvas, w, h)
  if not (ok and c) then return nil end
  c:setFilter("linear", "linear")
  if layer and layer.release then pcall(layer.release, layer) end
  layer, layerW, layerH = c, w, h
  return layer
end

-- ----------------------------------------------------------- host-facing API --

-- Start of a frame's glows (Gen4WorldHost.overlayFx).
function Glow.begin()
  pending = {}
end

-- A glow at canvas pixel (sx, sy) with radius `rad` px and strength `a`, at world
-- point (wx, wy, wz). The world point is optional: without it the glow always shows.
function Glow.add(sx, sy, rad, a, wx, wy, wz)
  if #pending >= Glow.MAX then return end
  pending[#pending + 1] = { sx = sx, sy = sy, rad = rad, a = a, wx = wx, wy = wy, wz = wz }
end

-- Hang the layer pass on Gen4Bridge.after (once). Called when the first glow is
-- made, so a session that never sees a firefly never pays for it.
function Glow.hook()
  if Glow.hooked then return end
  local Bridge = optional("Gen4Bridge")
  if Bridge and type(Bridge.after) == "table" then
    Bridge.after[#Bridge.after + 1] = Glow.run
    Glow.hooked, Glow.Bridge = true, Bridge
  end
end

local unreadable = setmetatable({}, { __mode = "k" })

-- Gen4Bridge.after hook: (ground, view, vw, vh), the finished scene's canvas still
-- holding colour + depth.
function Glow.run(ground, view, vw, vh)
  local list = pending
  pending = {}
  local Tint = optional("Gen4Tint")
  if not (Tint and Glow.enabled) then return end
  if #list == 0 then Tint.glowLayer = nil; Glow.status = "none"; return end
  if not (ground and view and ground.liveTargetFor and ground.freeW and ground.freeH) then
    return
  end
  local w, h = ground.freeW, ground.freeH
  local colour, depth = ground:liveTargetFor(w, h)
  if not (colour and depth) then return end
  if unreadable[depth] then Glow.status = "depth unreadable"; return end
  local sh, img = getShader(), halo()
  local out = sh and img and ensureLayer(w, h)
  if not out then return end
  local Mat4 = optional("Mat4")
  local vp = view:matrix(w, h)
  local inv = vp and Mat4 and Mat4.invert(vp)
  if not inv then return end

  local ex, ey, ez = view.x, view.y, view.z
  local g = love.graphics
  local drew = false
  g.push("all")
  local ok, err = pcall(function()
    g.setCanvas()                 -- release colour + depth so depth can be sampled
    local okD = pcall(sh.send, sh, "depthTex", depth)
    if not okD then
      unreadable[depth] = true
      Glow.status = "depth unreadable"
      once("unreadable", "the Gen 4 depth buffer is not readable -- fireflies will show through scenery")
      return
    end
    pcall(sh.send, sh, "invVP", "row", inv)
    pcall(sh.send, sh, "eye", { ex, ey, ez })

    g.setCanvas(out)
    g.origin()
    g.setScissor()
    g.clear(0, 0, 0, 0)
    g.setShader(sh)
    g.setBlendMode("add", "alphamultiply")
    local iw, ih = img:getWidth(), img:getHeight()

    local function stamp(sx, sy, rad, a, dist, bias, cr, cg, cb)
      sh:send("centre", { sx / w, sy / h })
      sh:send("halfSize", { rad / w, rad / h })
      sh:send("dist", dist)
      sh:send("bias", bias)
      g.setColor(cr, cg, cb, math.min(1, a))
      g.draw(img, sx, sy, 0, (rad * 2) / iw, (rad * 2) / ih, iw * 0.5, ih * 0.5)
    end

    for _, gl in ipairs(list) do
      if gl.sx and gl.sy and gl.sx > -60 and gl.sx < w + 60 and gl.sy > -60 and gl.sy < h + 60 then
        local dist = 0
        if gl.wx and gl.wy and gl.wz then
          local dx, dy, dz = gl.wx - ex, gl.wy - ey, gl.wz - ez
          dist = math.sqrt(dx * dx + dy * dy + dz * dz)
        end
        local bias = Glow.BIAS + (Glow.BIAS_PER_RADIUS or 0) * gl.rad
        stamp(gl.sx, gl.sy, gl.rad, gl.a, dist, bias, 1.0, 0.9, 0.45)            -- halo
        -- the hot core stands in for AmbientLife's flat rectangle; its margin is the
        -- bare BIAS, so a firefly half behind a trunk loses its core first
        stamp(gl.sx, gl.sy, math.max(2, gl.rad * 0.3), gl.a * 1.8, dist,
              Glow.BIAS, 1.0, 0.97, 0.7)
        drew = true
      end
    end
  end)
  g.pop()

  if not ok then
    Glow.enabled = false
    Glow.status = "failed"
    once("run", "the glow pass failed and was switched off: %s", tostring(err))
    return
  end
  if drew then
    -- Gen4Tint paints the layer after the night multiply, in place of its own
    -- (unoccluded) list
    Tint.glowLayer = out
    Tint.glowLayerAt = (love.timer and love.timer.getTime()) or 0
    Tint.glows = {}
    Glow.status = "drawn"
  end
end

function Glow.invalidate()
  if haloImg and haloImg.release then pcall(haloImg.release, haloImg) end
  if layer and layer.release then pcall(layer.release, layer) end
  if shader and shader.release then pcall(shader.release, shader) end
  haloImg, layer, shader, shaderFailed, layerW, layerH = nil, nil, nil, nil, nil, nil
end

function Glow.uninstall()
  if Glow.hooked and Glow.Bridge and Glow.Bridge.after then
    for i, fn in ipairs(Glow.Bridge.after) do
      if fn == Glow.run then table.remove(Glow.Bridge.after, i); break end
    end
  end
  Glow.hooked = false
end

return Glow
