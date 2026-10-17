-- Gen4Haze: V-HAZE (lib/Aerial) on Platinum's own 3D world, per pixel.
--
-- THE GEN 1-3 HAZE, AND WHY THIS IS THE SAME THING
--
-- In the voxel scene every surface asks its own question in the scene shader:
-- how far is this world point from the eye? It squares the ramp, snaps it to
-- hard rungs dithered in world space, and mixes toward the sky's palest band.
-- There is no geometry in it, so there is nothing to see but the haze.
--
-- Platinum's terrain, buildings and characters are the ENGINE's meshes, so that
-- shader never touches them. This asks the same question after the fact: a
-- full-screen pass over the finished Gen 4 frame that reads each pixel's DEPTH,
-- rebuilds the world point that wrote it (the same invVP * (uv, depth) maths
-- RayFX rests on), measures its distance to the eye and applies the same
-- squared, rung-quantised, dithered mix. (An earlier version drew nested
-- translucent shells instead; their rims showed as horizontal edges across the
-- buildings, which is why this replaced it.)
--
-- WHERE IT STARTS (measured PAST THE PLAYER, like Aerial.NEAR / FAR)
--
-- The haze starts NEAR_CHUNKS beyond the player, not beyond the camera. A
-- third-person camera already sits ~100 units behind the player, so measuring from
-- the eye put the start AT the player and the buildings next to you were
-- stippled with haze. The eye-to-player distance is added to both ends of
-- the ramp. Everything inside the start is untouched (alpha 0, not "dithered
-- to nothing"), and the dither is half a rung wide so a surface only starts to
-- stipple once it is well into the haze.
--
-- WHAT IT NEEDS
--
-- A READABLE depth buffer. The engine makes its depth write-only; Gen4Reflect
-- wraps Gen4Model.newTarget to hand back a readable twin, and this reuses that.
-- If the driver will not give one, the pass logs once and does nothing: no
-- haze, no artefacts.
--
-- THE SEAM
--
-- Gen4Bridge calls Haze.draw(scene) each frame inside its scene. That call draws
-- nothing; it decides whether the haze applies (V-HAZE on, outdoors, a sky) and
-- on first use hangs Haze.run on Gen4Bridge.after, which runs once the scene is
-- finished and before the engine blits the picture. Registered after
-- Gen4Reflect's own hook, so the haze lies over the reflection.
--
-- The haze colour is the sky's palest band, the value Gen4Sky clears the frame
-- to, so the far ground fades into the horizon. Pixels that nothing wrote depth
-- to -- the sky and the painted scenery ring -- are left alone.
--
-- Rows: the existing V-HAZE (Aerial.setting). Distances are in engine chunks
-- (ground.chunkPx, 512 units); the voxel numbers are for a diorama a few tiles
-- wide and would haze a Platinum route to nothing.

local V = ...

local Mat4 = V.require("Mat4")
local Aerial = V.require("Aerial")

local Haze = {
  enabled = true,
  NEAR_CHUNKS = 0.2,     -- where the haze begins, in chunks PAST THE PLAYER (~100 units)
  FAR_CHUNKS = 0.9,      -- where it tops out, past the player (~460 units)
  -- Top-rung strength per V-HAZE option (OFF, 1, 2, 3). Heavier than Aerial.AMOUNTS
  -- (0.34 / 0.56 / 0.78), which were tuned for the voxel diorama. Keep the last
  -- one under 1, or the far edge becomes a hole the colour of the sky.
  AMOUNTS = { 0, 0.5, 0.74, 0.92 },
  -- Size, in world units, of the cells the rung edges are dithered in (the
  -- shader's per-world-pixel grain). 0 = hard bands with no stipple.
  DITHER_CELL = 2,
  -- How wide the stipple between two rungs is, in rungs. 1 = the voxel shader's
  -- full rung (stipple begins the moment the ramp leaves zero); 0.5 keeps the
  -- near edge of the haze clean. Ignored when DITHER_CELL is 0.
  DITHER_WIDTH = 0.5,
  status = "idle",       -- what the last frame did, for probes and the log
}

local warned = {}
local function once(key, fmt, ...)
  if warned[key] then return end
  warned[key] = true
  if V.mod and V.mod.log then V.mod.log:info("Gen4Haze: " .. fmt:format(...)) end
end

local function optional(name)
  local ok, mod = pcall(V.require, name)
  return ok and mod or nil
end

-- ------------------------------------------------------------- the shader --

local SHADER = [[
  uniform Image depthTex;
  uniform highp mat4 invVP;       // clip -> world: the camera matrix run backwards
  uniform highp vec3 eye;
  uniform highp vec4 fog;         // x = near, y = 1/span, z = top strength, w = rungs
  uniform highp vec3 fogColor;    // the sky's palest band
  uniform highp float cell;       // dither cell, world units (0 = none)
  uniform highp float ditherW;    // stipple width, in rungs

  // the cleared depth: nothing was drawn there, so it is sky
#define SKY_DEPTH 0.9999

  vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
    float d = Texel(depthTex, uv).r;
    if (d >= SKY_DEPTH) return vec4(0.0);

    // a canvas pixel and its stored depth back to the world point that wrote
    // them (uv*2-1 with no flip: the camera matrix already carries it)
    vec4 c = invVP * vec4(uv * 2.0 - 1.0, d * 2.0 - 1.0, 1.0);
    vec3 P = c.xyz / c.w;

    // Voxel3D's own ramp: squared, so the near ground stays legible and the
    // cost piles up over the far half of the range
    float t = clamp((length(P - eye) - fog.x) * fog.y, 0.0, 1.0);
    // inside the start of the haze nothing is touched, whatever the dither says
    if (t <= 0.0) return vec4(0.0);
    t *= t;

    // hard rungs, dithered one rung wide in world space so the boundary is a
    // stipple that sits still while the camera pans
    if (cell > 0.0) {
      vec3 g = floor(P / cell);
      float n = fract(52.9829189 * fract(dot(g.xz + g.y * vec2(17.0, 31.0),
                                             vec2(0.06711056, 0.00583715))));
      t = clamp(t + (n - 0.5) * ditherW / fog.w, 0.0, 1.0);
    }
    t = floor(t * fog.w + 0.5) / fog.w;

    float a = t * fog.z;
    if (a <= 0.0) return vec4(0.0);
    return vec4(fogColor, a);
  }
]]

local shader, shaderFailed
local function getShader()
  if shader then return shader end
  if shaderFailed then return nil end
  local ok, sh = pcall(love.graphics.newShader, SHADER)
  if not (ok and sh) then
    shaderFailed = true
    once("shader", "the haze shader would not compile -- no Gen 4 haze: %s", tostring(sh))
    return nil
  end
  shader = sh
  return shader
end

local whiteImg
local function white()
  if whiteImg then return whiteImg end
  local ok, img = pcall(function()
    local data = love.image.newImageData(2, 2)
    for y = 0, 1 do for x = 0, 1 do data:setPixel(x, y, 1, 1, 1, 1) end end
    local i = love.graphics.newImage(data)
    i:setFilter("nearest", "nearest")
    return i
  end)
  if ok then whiteImg = img end
  return whiteImg
end

-- ------------------------------------------------------------ the decision --

-- the sky's palest band, or nil where there is no sky
local function hazeColor()
  local Sky = optional("Sky")
  if not (Sky and type(Sky.bands) == "function") then return nil end
  local okB, bands = pcall(Sky.bands)
  local c = okB and type(bands) == "table" and bands[#bands] or nil
  if c and c[1] and c[2] and c[3] then return c end
  return nil
end

local function outdoors(map)
  local Spawn = optional("Gen4Spawn")
  if not (Spawn and Spawn.isOutdoor) then return map ~= nil end
  local ok, r = pcall(Spawn.isOutdoor, map)
  return ok and r and true or false
end

-- True while Gen4WorldHost.renderPose is drawing the Colosseum arena backdrop
-- world (drawn every frame at arena resolution; the haze is left to the
-- overworld's own pass, as Gen4Reflect does).
local function inArenaPass()
  local Host = optional("Gen4WorldHost")
  return Host ~= nil and type(Host.inPose) == "function" and Host.inPose() or false
end

-- Straight-line distance from the camera to the player (ground point under them):
-- the extra path length the haze is measured PAST. 0 when the player is not known.
local function eyeToPlayer(scene)
  local eye = scene and scene.eye
  if not eye then return 0 end
  local okG, Game = pcall(require, "src.core.Game")
  local p = okG and type(Game) == "table" and Game.overworld and Game.overworld.player or nil
  if not (p and tonumber(p.px) and tonumber(p.py)) then return 0 end
  local mx, mz = p.px + 8, p.py + 8
  local gy = eye[2]
  if scene.groundY then
    local ok, y = pcall(scene.groundY, mx, mz)
    if ok and tonumber(y) then gy = y end
  end
  local dx = mx + (scene.offsetX or 0) - eye[1]
  local dy = gy - eye[2]
  local dz = mz + (scene.offsetZ or 0) - eye[3]
  return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Called by Gen4Bridge every frame from inside its scene. Draws nothing: it
-- hangs the screen pass on first use and says whether THIS frame gets haze.
function Haze.draw(scene)
  if not Haze.hooked then
    local Bridge = optional("Gen4Bridge")
    if Bridge and type(Bridge.after) == "table" then
      Bridge.after[#Bridge.after + 1] = Haze.run
      Haze.hooked, Haze.Bridge = true, Bridge
    end
  end
  Haze.live = nil
  if not Haze.enabled then Haze.status = "disabled"; return end
  local amount = Haze.AMOUNTS[(Aerial.level() or 0) + 1] or Aerial.amount()
  if not (amount and amount > 0) then Haze.status = "off"; return end
  if not outdoors(scene and scene.map) then Haze.status = "indoors"; return end
  local col = hazeColor()
  if not col then Haze.status = "no sky"; return end
  local chunk = tonumber(scene and scene.ground and scene.ground.chunkPx) or 512
  local near = eyeToPlayer(scene) + Haze.NEAR_CHUNKS * chunk
  local span = (Haze.FAR_CHUNKS - Haze.NEAR_CHUNKS) * chunk
  if span <= 0 then Haze.status = "bad range"; return end
  Haze.live = { col = col, near = near, span = span, amount = amount }
  Haze.status = "armed"
end

-- ------------------------------------------------------------------ the pass --

local unreadable = setmetatable({}, { __mode = "k" })   -- depth canvas -> true

-- Gen4Bridge.after hook: (ground, view, vw, vh), the finished scene's canvas
-- still holding colour + depth.
function Haze.run(ground, view, vw, vh)
  local st = Haze.live
  Haze.live = nil
  if not (st and Haze.enabled) then return end
  if inArenaPass() then return end
  if not (ground and view and ground.liveTargetFor and ground.freeW and ground.freeH) then
    return
  end
  local colour, depth = ground:liveTargetFor(ground.freeW, ground.freeH)
  if not (colour and depth) then return end
  if unreadable[depth] then Haze.status = "depth unreadable"; return end
  local sh, img = getShader(), white()
  if not (sh and img) then return end
  local w, h = ground.freeW, ground.freeH
  local vp = view:matrix(w, h)
  local inv = vp and Mat4.invert(vp)
  if not inv then return end

  local g = love.graphics
  g.push("all")                      -- the whole graphics state comes back after
  local ok, err = pcall(function()
    g.setCanvas()                    -- let go of colour + depth so depth can be sampled
    local okD = pcall(sh.send, sh, "depthTex", depth)
    if not okD then
      unreadable[depth] = true
      Haze.status = "depth unreadable"
      once("unreadable", "the Gen 4 depth buffer is not readable -- no haze. "
           .. "(Gen4Reflect makes it readable; it must be installed before the canvas is made.)")
      return
    end
    pcall(sh.send, sh, "invVP", "row", inv)
    pcall(sh.send, sh, "eye", { view.x, view.y, view.z })
    pcall(sh.send, sh, "fog", { st.near, 1 / st.span, st.amount,
                                math.max(1, Aerial.RUNGS or 4) })
    pcall(sh.send, sh, "fogColor", { st.col[1], st.col[2], st.col[3] })
    pcall(sh.send, sh, "cell", Haze.DITHER_CELL or 0)
    pcall(sh.send, sh, "ditherW", Haze.DITHER_WIDTH or 1)

    -- colour only (no depth attached), the shader's own alpha does the mix:
    -- dst = haze * a + dst * (1 - a)
    g.setCanvas(colour)
    g.origin()
    g.setScissor()
    g.setShader(sh)
    g.setBlendMode("alpha", "alphamultiply")
    g.setColor(1, 1, 1, 1)
    g.draw(img, 0, 0, 0, w / 2, h / 2)
    Haze.status = "drawn"
  end)
  g.pop()
  if not ok then
    Haze.enabled = false
    Haze.status = "failed"
    once("run", "the haze pass failed and was switched off: %s", tostring(err))
  end
end

-- drop the GPU objects (graphics reset, mod reload, cache reset)
function Haze.invalidate()
  if whiteImg and whiteImg.release then pcall(whiteImg.release, whiteImg) end
  whiteImg = nil
  if shader and shader.release then pcall(shader.release, shader) end
  shader, shaderFailed = nil, nil
end

function Haze.uninstall()
  if Haze.hooked and Haze.Bridge and Haze.Bridge.after then
    for i, fn in ipairs(Haze.Bridge.after) do
      if fn == Haze.run then table.remove(Haze.Bridge.after, i); break end
    end
  end
  Haze.hooked = false
end

return Haze