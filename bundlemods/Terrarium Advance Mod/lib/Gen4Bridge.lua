-- Gen4Bridge: Terrarium's effects, drawn INTO the engine's own Gen 4 world.
--
-- WHY THIS EXISTS
--
-- On Gen 1/2/3 this mod builds the 3D world itself: it extrudes the tilemap
-- into voxels and owns the frame through the `voxel` render pipeline. Gen 4
-- (Platinum) already has a real 3D world -- src/render/Gen4Ground.lua draws
-- terrain and buildings from the cartridge's own models through a real camera
-- (src/render/Gen4View.lua) -- so there is nothing to extrude, and letting the
-- voxel pipeline take the world pass would REPLACE that world with a voxelised
-- tilemap. So on Gen 4 the `voxel` pipeline stands down (see main.lua:
-- `available`) and this module runs instead. It adds effects on top of the
-- engine's world and never replaces any of it.
--
-- HOW IT HOOKS IN (engine untouched)
--
-- In a free camera (third / first person, and every numeric CAM TILT rung)
-- Gen4Ground:drawFree() leaves its canvas OPEN -- colour + depth -- while the
-- overworld draws characters into it, and Gen4Ground:endFree() closes it. This
-- module wraps endFree(): just before the original runs, the canvas still holds
-- terrain + buildings + characters with a live depth buffer, so anything drawn
-- now is depth-tested against the real scene. That is the whole seam.
--
-- The mod's own shader renderer (Voxel3D) already has an "external target"
-- mode (beginScene with slot "current") that draws into whatever canvas is
-- bound, and an explicit-camera mode (Voxel3D.camera with view/proj). We feed
-- it Gen4View's own view-projection matrix, so a mesh placed at a Gen 4 world
-- position lands exactly where the engine would put it, and every uniform the
-- shader takes (wind, water, tint, glass mask, lamps, fog) keeps working.
--
-- Coordinates are shared: +x east, +y up, +z south, one unit per map pixel,
-- sixteen per tile -- the voxel scene's convention too. A Gen 4 map adds its
-- matrix origin (ground.offsetX / offsetY) to a map-pixel position.
--
-- SHADOWS. The same seam hosts the sun pass (Bridge.castShadows): the map is
-- filled from the mod's own casters (trees, rocks, fences, flowers, HD cards,
-- the 3D actors Gen4WorldHost records) plus the engine's own buildings
-- (lib/Gen4Sun), and read back by everything Voxel3D draws plus a thin
-- receiver laid on the ground (lib/Gen4Sun.drawReceiver).
--
-- NOT COVERED YET: the CARTRIDGE (oblique) rung, where Gen4Ground bakes chunks
-- with its own depth units. Effects only draw when the camera is a free one.
-- See GEN4_PORT_NOTES.md.

local V = ...
local Voxel3D = V.require("Voxel3D")
local Mat4 = V.require("Mat4")
-- THE SUN. Neither of these was reachable from the Gen 4 path before, which
-- is why Platinum had no cast shadows at all: ShadowMap is the sun's depth
-- pass and Shadows is the player's ON / OFF row for it, and the only code
-- that ever filled the map was VoxelScene / BattleScene -- neither of which
-- runs on Platinum. See Bridge.castShadows below.
local ShadowMap = V.require("ShadowMap")
local Shadows = V.require("Shadows")

local Bridge = {
  effects = {},      -- name -> draw(scene)
  order = {},        -- registration order == draw order
  casters = {},      -- name -> cast(ShadowMap, scene, box): what throws shadows
  casterOrder = {},
  shadows = true,    -- master switch for the sun pass on Gen 4
  actorCasts = {},   -- this frame's recorded actor draws (see captureDraws)
  actorCount = 0,
  pre = {},          -- name -> draw(scene): effects drawn BEFORE the terrain (the sky),
  preOrder = {},     -- into the same open Voxel3D scene, see Bridge.runPre
  stats = { runs = 0, pres = 0 },   -- passes actually run; ArenaOverworldSnapshot reports them
  after = {},        -- fn(ground, view, vw, vh): screen passes run once the effects
                     -- are drawn and BEFORE the engine blits the frame (Gen4Reflect)
  disabled = {},     -- name -> true when switched off
  enabled = true,    -- master switch
  installed = false,
  reported = {},
}

-- The shared per-frame build budget (lib/Gen4Budget.lua). Resolved once.
local budgetMod
local function budget()
  if not budgetMod then
    local ok, B = pcall(V.require, "Gen4Budget")
    if ok and type(B) == "table" then budgetMod = B end
  end
  return budgetMod
end

-- True while a warp fade hides the world: nothing on screen to hitch, so the
-- budget may spend much more building meshes. Only `transitioning` is read (the
-- same flag main.lua's own COVERED test uses for warps); the stack-top test is
-- left out on purpose, because a Gen 4 world can run with an empty stack and
-- that would read as "covered" for the whole game.
local function worldCovered()
  local okG, Game = pcall(require, "src.core.Game")
  local ow = okG and type(Game) == "table" and Game.overworld or nil
  return (ow and ow.transitioning) and true or false
end

local function frameEnd()
  local B = budget()
  if not B then return end
  B.covered = worldCovered()      -- read by the NEXT frame's builds
  B.nextFrame()
end

local function report(key, fmt, ...)
  if Bridge.reported[key] then return end
  Bridge.reported[key] = true
  if V.mod and V.mod.log then
    V.mod.log:warn("Gen4Bridge: " .. fmt:format(...))
  end
end

-- ------------------------------------------------------------ detection --

local function generation()
  local ok, GameVersion = pcall(require, "src.core.GameVersion")
  if not (ok and GameVersion and GameVersion.generation) then return nil end
  local okGen, value = pcall(GameVersion.generation)
  return okGen and tonumber(value) or nil
end

function Bridge.isGen4()
  return generation() == 4
end

-- True when this module owns Terrarium's world-side effects: a Gen 4 game AND
-- the hook is in. main.lua's `voxel` pipeline asks this to stand down.
function Bridge.active()
  return Bridge.installed and Bridge.isGen4()
end

-- ------------------------------------------------------------- registry --

-- register(name, drawFn [, opts]). drawFn(scene) runs inside an open Voxel3D
-- scene (shader bound, depth test on, depth write on). Effects that blend
-- (glass, water) should call scene.blend() first and scene.opaque() after.
function Bridge.register(name, fn)
  if type(fn) ~= "function" then return false end
  if not Bridge.effects[name] then Bridge.order[#Bridge.order + 1] = name end
  Bridge.effects[name] = fn
  return true
end

-- registerPre(name, drawFn): like register, but the effect runs BEFORE the first
-- terrain shape of the frame (Gen4Sky's hook calls Bridge.runPre then), with the
-- depth buffer still clear. Nothing is drawn over yet, so the effect is the
-- backdrop: everything the engine draws afterwards covers it. Same scene, same
-- error isolation as register.
function Bridge.registerPre(name, fn)
  if type(fn) ~= "function" then return false end
  if not Bridge.pre[name] then Bridge.preOrder[#Bridge.preOrder + 1] = name end
  Bridge.pre[name] = fn
  return true
end

function Bridge.setEffect(name, on)
  Bridge.disabled[name] = (on == false) or nil
end


-- --------------------------------------------------------------- shadows --
--
-- ONE SUN PASS PER FRAME, run from runScene just before the effects scene
-- opens. Order inside a Gen 4 frame (see Gen4WorldHost.install):
--
--   1. the engine draws sky, terrain and buildings into its free canvas, and
--      leaves it OPEN (colour + depth);
--   2. Gen4WorldHost draws the 3D actors into it, RECORDING each of their
--      Voxel3D.draw calls as shadow casters (Bridge.captureDraws);
--   3. the engine draws the remaining sprites; endFree runs Bridge.run:
--        a. castShadows fills ShadowMap from every caster, restoring the open
--           canvas afterwards;
--        b. the effects scene opens and every Voxel3D mesh reads the map.
--
-- So an actor casts the same frame it moves, and receives from the map built
-- the frame before -- the one frame of lag ShadowMap's own LOW rung already
-- accepts, and not a thing anyone can see at 60 fps.

Bridge.SHADOW_RADIUS = 224      -- world units around the player that get shadows
Bridge.SHADOW_SNAP = 16         -- the box centre snaps to a tile, so it holds
                                -- still between steps and the receiver grid
                                -- is not rebuilt every pixel
Bridge.MAX_ACTOR_CASTS = 256
Bridge.shadowStats = { passes = 0, reused = 0, failed = 0, actors = 0, casters = 0 }

-- Whether a sun pass should run at all this frame. Both rows are read: the
-- ON / OFF row in lib/Shadows and (inside ShadowMap.wanted) the LOW / OFF /
-- HIGH / SOFT quality row. Either one saying no is a no, which is what
-- "OFF means OFF" in Shadows.lua asks for.
function Bridge.shadowsWanted()
  if not Bridge.shadows then return false end
  local ok, on = pcall(Shadows.enabled)
  if ok and on == false then return false end
  return ShadowMap.wanted()
end

-- a caster registers ONCE; cast(ShadowMap, scene, box) draws into the open
-- sun pass with ShadowMap.draw / ShadowMap.drawGroup
function Bridge.registerCaster(name, fn)
  if type(fn) ~= "function" then return false end
  if not Bridge.casters[name] then Bridge.casterOrder[#Bridge.casterOrder + 1] = name end
  Bridge.casters[name] = fn
  return true
end

-- Does something standing at (x, z), `half` world units across, reach the
-- box once its shadow's own length is allowed for? Both sides are padded,
-- because the sun swings through every bearing across the day.
function Bridge.touches(box, x, z, half)
  local pad = box.pad or 0
  half = half or 0
  return x + half >= box.x0 - pad and x - half <= box.x1 + pad
     and z + half >= box.z0 - pad and z - half <= box.z1 + pad
end

-- -- actors: recorded while they draw, cast when the pass opens

function Bridge.recordCast(mesh, tex, model, thin)
  local n = Bridge.actorCount
  if n >= Bridge.MAX_ACTOR_CASTS then return end
  n = n + 1
  local slot = Bridge.actorCasts[n]
  if not slot then slot = {}; Bridge.actorCasts[n] = slot end
  slot.mesh, slot.tex, slot.model, slot.thin, slot.fn = mesh, tex, model, thin, nil
  Bridge.actorCount = n
end

-- for an actor whose geometry does not go through Voxel3D.draw (the Stadium
-- rigs): fn(ShadowMap) is called inside the open pass
function Bridge.recordCastFn(fn)
  local n = Bridge.actorCount
  if n >= Bridge.MAX_ACTOR_CASTS or type(fn) ~= "function" then return end
  n = n + 1
  local slot = Bridge.actorCasts[n]
  if not slot then slot = {}; Bridge.actorCasts[n] = slot end
  slot.mesh, slot.tex, slot.model, slot.thin, slot.fn = nil, nil, nil, nil, fn
  Bridge.actorCount = n
end

-- Run fn() with every Voxel3D.draw it makes ALSO recorded as a caster. Used
-- around the actors, whose draw code mutates animation state and therefore
-- cannot simply be run a second time into the sun pass: record once, cast
-- later. A call that hands Voxel3D.draw an explicit `sunModel` is a thin card
-- (its lit draw reads the shadow through that snugged transform), so it is
-- recorded thin and cast snugged to match -- see ShadowMap.snug.
function Bridge.captureDraws(fn, ...)
  if not Bridge.shadowsWanted() then return fn(...) end
  local real = Voxel3D.draw
  Voxel3D.draw = function(mesh, tex, model, pull, sunModel, sway, waterBody)
    if mesh and model then Bridge.recordCast(mesh, tex, model, sunModel ~= nil) end
    return real(mesh, tex, model, pull, sunModel, sway, waterBody)
  end
  local ok, a, b = pcall(fn, ...)
  Voxel3D.draw = real
  if not ok then error(a, 0) end
  return a, b
end

-- -- the pass

local function outdoorMap(scene)
  local map = scene.map
  if not map then
    local okG, Game = pcall(require, "src.core.Game")
    map = okG and type(Game) == "table" and Game.overworld and Game.overworld.map or nil
  end
  if not map then return true end
  local okS, Spawn = pcall(V.require, "Gen4Spawn")
  if okS and type(Spawn) == "table" and Spawn.isOutdoor then
    local ok, r = pcall(Spawn.isOutdoor, map)
    if ok then return r and true or false end
  end
  return true
end

-- THE SUN ON GEN 4 FOLLOWS THE CARTRIDGE'S CLOCK, NOT THE MOD'S.
--
-- Platinum lights its own world from the real wall clock and the map's light
-- keyframes (Gen4Ground:applyLight -> `ground.nightness`, 0 = full day, 1 =
-- full night, fading through dusk). DayNight.applyRig reads the MOD's clock,
-- which is a separate setting (a pinned DAY, a running cycle...) and so could
-- be at noon while the game's own world was already dark -- the cause of
-- "it's night but the sun's shadows are still there".
--
-- So here the sun's bearing comes from the real clock laid on DayNight's dial
-- (the SYNC mapping), and its strength is multiplied by how much day the
-- cartridge says there is. Returns false when there is no sun to cast from.
Bridge.NIGHT_CUT = 0.08          -- below this much day, no sun pass at all
Bridge.DAY_ALPHA = 0.40          -- Voxel3D's own default shadow weight, for a
                                 -- DayNight that cannot be read

function Bridge.applySun(ground)
  local n = tonumber(ground and ground.nightness)
  local day = 1
  if n then day = 1 - math.max(0, math.min(1, n)) end
  Bridge.sunDay = day
  if day <= Bridge.NIGHT_CUT then return false end

  local alpha = Bridge.DAY_ALPHA
  local okD, DN = pcall(V.require, "DayNight")
  if okD and type(DN) == "table" and DN.syncTime and DN.shearAt then
    local okT, t = pcall(DN.syncTime)
    if okT and tonumber(t) then
      local okK, kx, kz = pcall(DN.shearAt, t)
      if okK and tonumber(kx) and tonumber(kz) then
        ShadowMap.KX, ShadowMap.KZ = kx, kz
        Voxel3D.SHADOW_KX, Voxel3D.SHADOW_KZ = kx, kz
      end
      if DN.alphaAt and DN.strengthAt then
        local okA, a = pcall(function() return DN.alphaAt(t) * DN.strengthAt(t) end)
        if okA and tonumber(a) then alpha = a end
      end
    end
  end
  -- read by the scene shader's sunDark and by the ground receiver's `shade`
  Voxel3D.SHADOW_ALPHA = alpha * day
  return Voxel3D.SHADOW_ALPHA > 0.01
end

-- THE SAME CLOCK FOR EVERYTHING THE MOD DRAWS. Voxel3D.tint is the scene
-- shader's light multiplier. Gen 1-3's frame sets it from the hour; Gen 4 never
-- did, so at night Platinum's own world went dark (its cartridge lighting) while
-- every tree, rock, fence, flower, tuft of grass and 3D actor the mod draws
-- stayed lit as noon. The multiplier here fades from the DAY tint to the NIGHT
-- tint by the cartridge's own `ground.nightness`, so the two halves of the
-- frame darken together. nil (neutral) indoors and where a map has no day cycle.
local tintCache = { key = nil, tint = nil }

function Bridge.gen4Tint(ground)
  local n = tonumber(ground and ground.nightness)
  if not n or n <= 0 then return nil end
  if not outdoorMap({ map = ground.terrariumMap }) then return nil end
  n = math.min(1, n)
  local key = math.floor(n * 64)
  if tintCache.key == key then return tintCache.tint end
  local okD, DN = pcall(V.require, "DayNight")
  if not (okD and type(DN) == "table" and DN.tint and DN.T) then return nil end
  local okA, day = pcall(DN.tint, true, DN.T.day)
  local okB, night = pcall(DN.tint, true, DN.T.night)
  if not (okA and okB and type(day) == "table" and type(night) == "table") then return nil end
  local tint = {}
  for i = 1, 3 do tint[i] = day[i] + (night[i] - day[i]) * n end
  tintCache.key, tintCache.tint = key, tint
  return tint
end

-- set the Gen 4 tint for one scene and hand back what to restore afterwards
-- (pass it to popTint). Always pair them: Voxel3D.tint is global and the sky's
-- pre-terrain scene reads it too.
function Bridge.pushTint(ground)
  local prev = Voxel3D.tint
  local t = Bridge.gen4Tint(ground)
  if t then Voxel3D.tint = t end
  return prev
end

function Bridge.popTint(prev)
  Voxel3D.tint = prev
end

-- Where the engine's free canvas is, as the engine itself binds it. nil when
-- it cannot be found: the pass MUST NOT open then, because finish() unbinds
-- everything and there would be nothing to put back.
local function openTarget(ground)
  local G = Bridge.Ground
  local colour = (G and G.freeColour) or ground.liveColour
  if colour and ground.liveColour == colour and ground.liveDepthBuf then
    return colour, ground.liveDepthBuf
  end
  return nil
end

-- the world-x/z square, and height band, to light: around the player
local function shadowBox(scene)
  local cx, cz
  local okG, Game = pcall(require, "src.core.Game")
  local player = okG and type(Game) == "table" and Game.overworld and Game.overworld.player
  if player and tonumber(player.px) and tonumber(player.py) then
    cx, cz = scene.toWorld(player.px + 8, player.py + 8)
  else
    local fx, fz = scene.focusPx()
    cx, cz = scene.toWorld(fx, fz)
  end
  local snap = Bridge.SHADOW_SNAP
  cx = math.floor(cx / snap + 0.5) * snap
  cz = math.floor(cz / snap + 0.5) * snap
  local r = Bridge.SHADOW_RADIUS
  -- absolute heights, not 0-based: a Sinnoh route can sit hundreds of units up
  local lo, hi
  for _, d in ipairs({ { 0, 0 }, { -r, -r }, { r, -r }, { -r, r }, { r, r } }) do
    local ok, y = pcall(scene.groundY, cx + d[1] - scene.offsetX, cz + d[2] - scene.offsetZ)
    y = ok and tonumber(y) or nil
    if y then
      lo = lo and math.min(lo, y) or y
      hi = hi and math.max(hi, y) or y
    end
  end
  lo, hi = lo or 0, hi or 0
  local lean = math.max(math.abs(ShadowMap.KX), math.abs(ShadowMap.KZ))
  local box = {
    cx = cx, cz = cz,
    x0 = cx - r, x1 = cx + r, z0 = cz - r, z1 = cz + r,
    y0 = lo - 32, y1 = hi + ShadowMap.HEIGHT,
    -- how far outside the square a caster can stand and still throw into it
    pad = ShadowMap.HEIGHT * lean + 24,
  }
  -- casters ask box.touches(x, z, half) so they need no reference to the bridge
  function box.touches(x, z, half) return Bridge.touches(box, x, z, half) end
  return box
end

-- a number that changes whenever the pass's inputs do (the box, the sun, any
-- actor's position), so ShadowMap.stale can skip a redraw of an unchanged world
local function mix(h, v)
  return (h * 31 + math.floor(v * 4 + 0.5)) % 2147483629
end

local function signature(box)
  local h = 7
  h = mix(h, box.cx); h = mix(h, box.cz)
  h = mix(h, ShadowMap.KX * 128); h = mix(h, ShadowMap.KZ * 128)
  for i = 1, Bridge.actorCount do
    local m = Bridge.actorCasts[i].model
    if m then h = mix(h, m[4]); h = mix(h, m[8]); h = mix(h, m[12]) end
  end
  return h
end

local function castAll(scene, box)
  local Sun = Bridge.Sun
  if Sun and Sun.castBuildings then
    local ok, err = pcall(Sun.castBuildings, ShadowMap, scene.ground, box)
    if not ok then report("cast:buildings", "the engine's buildings did not cast: %s", tostring(err)) end
  end
  for _, name in ipairs(Bridge.casterOrder) do
    if not Bridge.disabled["cast:" .. name] then
      local ok, err = pcall(Bridge.casters[name], ShadowMap, scene, box)
      if not ok then
        report("cast:" .. name, "caster '%s' failed: %s", name, tostring(err))
        Bridge.disabled["cast:" .. name] = true     -- don't fail every frame
      end
    end
  end
  for i = 1, Bridge.actorCount do
    local c = Bridge.actorCasts[i]
    if c.fn then
      local ok, err = pcall(c.fn, ShadowMap)
      if not ok then report("cast:actorfn", "an actor caster failed: %s", tostring(err)) end
    elseif c.mesh and c.model then
      ShadowMap.draw(c.mesh, c.tex, c.thin and ShadowMap.snug(c.model) or c.model)
    end
  end
  Bridge.shadowStats.actors = Bridge.actorCount
end

-- Fill the sun map for this frame (or decide it is still good). Returns the
-- box the map covers, which the ground receiver is laid over, or nil when
-- there is no map this frame.
--
-- CALLED WITH THE ENGINE'S FREE CANVAS OPEN. ShadowMap.begin binds its own
-- canvas and finish() unbinds with a bare setCanvas(), so the open pass --
-- colour AND depth -- is rebound by hand afterwards, exactly as Gen4Ground
-- binds it. Without that the effects scene would draw into the screen.
function Bridge.castShadows(scene)
  local stats = Bridge.shadowStats
  local ground = scene.ground
  local function none()
    ShadowMap.retire()
    Bridge.actorCount = 0
    Bridge.castBox = nil
    return nil
  end
  if not Bridge.shadowsWanted() or not ShadowMap.available() then return none() end
  if not outdoorMap(scene) then return none() end
  -- NIGHT: no sun, so no sun shadows. Platinum's own lighting already takes
  -- the world dark at night (ground.nightness, off the cartridge's light
  -- keyframes and the real clock); a sun pass on top of that would throw
  -- daylight shadows across a night map.
  if not Bridge.applySun(ground) then return none() end
  local colour, depth = openTarget(ground)
  if not colour then
    report("cast:target", "no open free canvas to restore; the sun pass is skipped")
    return none()
  end

  local box = shadowBox(scene)
  local frame = Bridge.stats.runs
  -- a map somebody else filled (a battle's) is not ours to reuse
  if Bridge.castUV ~= ShadowMap.uvVP then ShadowMap.retire() end
  local sig = signature(box)
  local since = frame - (Bridge.lastCast or -1000)
  local changed = sig ~= Bridge.lastSig or since >= 30
                  or (Bridge.actorCount > 0 and since >= 3)
  if not ShadowMap.stale(changed) then
    stats.reused = stats.reused + 1
    Bridge.actorCount = 0
    return Bridge.castBox
  end

  local g = love.graphics
  local sx, sy, sw, sh = g.getScissor()
  g.setScissor()                      -- the engine's scissor is sized for ITS canvas
  local began = ShadowMap.begin(box.cx, box.cz, scene.vw, scene.vh, box)
  if began then
    local ok, err = pcall(castAll, scene, box)
    if not ok then
      stats.failed = stats.failed + 1
      report("cast:all", "the sun pass failed part-way: %s", tostring(err))
    end
    ShadowMap.finish()
  end
  pcall(g.setCanvas, { colour, depthstencil = depth })
  g.setScissor(sx, sy, sw, sh)
  Bridge.actorCount = 0
  if not began then
    stats.failed = stats.failed + 1
    ShadowMap.retire()
    Bridge.castBox = nil
    return nil
  end
  stats.passes = stats.passes + 1
  Bridge.castBox, Bridge.castUV = box, ShadowMap.uvVP
  Bridge.lastSig, Bridge.lastCast = sig, frame
  return box
end

-- --------------------------------------------------------------- scene --

local FOCUS_DISTANCE = 128   -- only used to give Voxel3D an eye->focus vector

local function buildScene(ground, view, vw, vh)
  local offX, offZ = ground.offsetX or 0, ground.offsetY or 0
  local fx, fy, fz = view:forward()
  local scene = {
    ground = ground, view = view, vw = vw, vh = vh,
    map = ground.terrariumMap,            -- tagged in install(); may be nil
    offsetX = offX, offsetZ = offZ,
    eye = { view.x, view.y, view.z },
    forward = { fx, fy, fz },
    clock = ground.clock,
    Voxel3D = Voxel3D, Mat4 = Mat4,
  }
  -- map pixel -> world x,z
  function scene.toWorld(px, py) return px + offX, py + offZ end
  -- terrain height (world units) at a map-pixel position
  function scene.groundY(px, py) return ground:groundY(px, py) end
  -- where the view ray meets the ground, in MAP PIXELS: the centre for culling.
  function scene.focusPx()
    local ex, ez = view.x - offX, view.z - offZ
    local gy = ground:groundY(ex, ez) or 0
    if fy < -0.05 then
      local t = math.min((view.y - gy) / -fy, 900)
      return ex + fx * t, ez + fz * t
    end
    return ex + fx * 160, ez + fz * 160
  end
  -- Voxel3D.depth() only knows "always" and test+write, so a blended pass
  -- (glass, water: tested against the scene but never written) sets the mode
  -- itself. The scene is open when these run, so the shader stays bound.
  function scene.blend()
    love.graphics.setDepthMode("lequal", false)
  end
  function scene.opaque()
    love.graphics.setDepthMode("lequal", true)
  end
  -- scene.sphereVisible(x, y, z, r): false only when a sphere (world units) is
  -- well outside the view. Effects use it to skip whole chunks the camera cannot
  -- see (see Gen4Cull). Absent when the view's fov is unreadable: callers must
  -- treat nil as "draw everything".
  do
    local okC, Cull = pcall(V.require, "Gen4Cull")
    local fovRad
    if type(view.effectiveFovY) == "function" then
      local okF, f = pcall(view.effectiveFovY, view, vh)
      if okF and tonumber(f) then fovRad = math.rad(f) end
    end
    if okC and type(Cull) == "table" and fovRad then
      scene.sphereVisible = Cull.sphereTest(scene.eye, scene.forward, fovRad,
                                            (tonumber(vw) or 1) / math.max(tonumber(vh) or 1, 1))
    end
  end
  return scene
end

local function runScene(ground, view, vw, vh, order, effects, tag)
  local scene = buildScene(ground, view, vw, vh)
  -- The sun pass runs BEFORE the scene opens: Voxel3D.beginScene uploads the
  -- shadow map's uniforms, so the map has to be finished by then. Only the
  -- post-terrain scene casts; the pre-terrain (sky) one has nothing to shade.
  if tag == "fx:" then
    local okC, boxOrErr = pcall(Bridge.castShadows, scene)
    if okC then
      scene.shadowBox = boxOrErr
    else
      pcall(ShadowMap.retire)
      Bridge.actorCount = 0
      report("shadows", "the sun pass failed: %s", tostring(boxOrErr))
    end
  end
  -- the hour's light on everything the mod draws (see Bridge.gen4Tint); put
  -- back by Bridge.run, so the pre-terrain sky scene never sees it
  if tag == "fx:" then Bridge._tintSaved = { Bridge.pushTint(ground) } end
  local vp = view:matrix(vw, vh)          -- Gen4's world->clip, Y already flipped
  local fx, fy, fz = view:forward()
  local saved = Voxel3D.camera
  Voxel3D.camera = {
    eye = { view.x, view.y, view.z },
    focus = { view.x + fx * FOCUS_DISTANCE, view.y + fy * FOCUS_DISTANCE,
              view.z + fz * FOCUS_DISTANCE },
    fov = math.rad(view:effectiveFovY(vh)),
    curve = 0,                            -- Gen 4 draws a flat world: no horizon bend
    -- Voxel3D.viewProjection returns S * proj * view with S = scale(1,-1,1).
    -- Gen4View:matrix already applied that flip, so cancel it here:
    -- S * (S * vp) * I == vp.
    view = Mat4.identity(),
    proj = Mat4.mul(Mat4.scale(1, -1, 1), vp),
  }
  local began = Voxel3D.beginScene(vw, vh, view.x, view.z, vw, vh, nil, "current")
  if not began then
    Voxel3D.camera = saved
    return
  end
  for _, name in ipairs(order) do
    if not Bridge.disabled[name] then
      local ok, err = pcall(effects[name], scene)
      if not ok then
        report(tag .. name, "effect '%s' failed: %s", name, tostring(err))
        Bridge.disabled[name] = true      -- don't fail every frame
      end
    end
  end
  Voxel3D.endScene()
  Voxel3D.camera = saved
end

function Bridge.run(ground)
  if not (Bridge.enabled and #Bridge.order > 0) then return end
  local view, vw, vh = ground.view3d, ground.freeW, ground.freeH
  if not (view and vw and vh and view.matrix and view.forward) then return end
  if not Bridge.isGen4() then return end
  Bridge.stats.runs = Bridge.stats.runs + 1
  local ok, err = pcall(runScene, ground, view, vw, vh, Bridge.order, Bridge.effects, "fx:")
  if Bridge._tintSaved ~= nil then
    Voxel3D.tint = Bridge._tintSaved[1]
    Bridge._tintSaved = nil
  end
  if not ok then
    -- make sure a throw between beginScene/endScene can't leave state behind
    pcall(Voxel3D.endScene)
    report("scene", "scene failed: %s", tostring(err))
  end
  for i, fn in ipairs(Bridge.after) do
    local okA, errA = pcall(fn, ground, view, vw, vh)
    if not okA then
      report("after:" .. i, "screen pass %d failed: %s", i, tostring(errA))
    end
  end
end

-- The pre-terrain pass. Called by Gen4Sky from inside Gen4Ground:drawFree, on the
-- first terrain shape, while the free canvas is bound and its depth is clear.
-- Returns true when the scene ran.
function Bridge.runPre(ground)
  if not (Bridge.enabled and #Bridge.preOrder > 0) then return false end
  local view, vw, vh = ground.view3d, ground.freeW, ground.freeH
  if not (view and vw and vh and view.matrix and view.forward) then return false end
  if not Bridge.isGen4() then return false end
  Bridge.stats.pres = Bridge.stats.pres + 1
  local ok, err = pcall(runScene, ground, view, vw, vh, Bridge.preOrder, Bridge.pre, "pre:")
  if not ok then
    pcall(Voxel3D.endScene)
    report("prescene", "pre-terrain scene failed: %s", tostring(err))
    return false
  end
  return true
end

-- ------------------------------------------------------------- install --

function Bridge.install()
  if Bridge.installed then return true end
  local ok, Ground = pcall(require, "src.render.Gen4Ground")
  if not (ok and type(Ground) == "table" and type(Ground.endFree) == "function") then
    return false      -- not a Gen 4 build of the engine: nothing to hook
  end
  Bridge.Ground = Ground
  Bridge.originalEndFree = Ground.endFree
  Bridge.originalForMap = Ground.forMap

  -- Tag each ground with the Map it was built for; effects need the map's
  -- cell queries (grass, water) and Gen4Ground doesn't keep the map itself.
  if type(Ground.forMap) == "function" then
    local forMap = Ground.forMap
    Ground.forMap = function(map, data, ...)
      local g = forMap(map, data, ...)
      if g then g.terrariumMap = map end
      return g
    end
  end

  -- Only the newest install is live; a wrapper left over from an earlier run of
  -- this file (mod reload) passes straight through instead of drawing every
  -- effect a second time.
  local token = {}
  Ground.__terrariumBridgeToken = token

  local original = Ground.endFree
  Ground.endFree = function(self, ...)
    if Ground.__terrariumBridgeToken ~= token then return original(self, ...) end
    -- Runs while the free canvas is still open (colour + depth): terrain,
    -- buildings and characters are already in it. See the header.
    if Ground.freeOpen and self and self.freeW then Bridge.run(self) end
    -- close the frame's shared build budget after the engine has finished with
    -- the canvas, and pass every return value of the original through
    local function finish(...)
      frameEnd()
      return ...
    end
    return finish(original(self, ...))
  end
  Bridge.installed = true

  -- THE SUN, receiving half. Platinum's terrain is the engine's, drawn with a
  -- shader that cannot read the shadow map, so the ground gets a thin shade
  -- layer laid on its height map (lib/Gen4Sun). It goes FIRST: every opaque
  -- Voxel3D pass drawn after it (sand, lawn, bumps...) overdraws it with the
  -- shader's own exact shadow instead of being shaded twice.
  local okSun, Sun = pcall(V.require, "Gen4Sun")
  if okSun and type(Sun) == "table" and Sun.drawReceiver then
    Bridge.Sun = Sun
    Bridge.register("groundshadow", Sun.drawReceiver)
  else
    report("sun", "the ground shadow pass did not load: %s", tostring(Sun))
  end
  -- ...and the casting half: what throws a shadow into the sun pass. Each
  -- module that draws geometry through Voxel3D exports cast(ShadowMap, scene,
  -- box) next to its draw(scene).
  local function caster(name, modName)
    local ok, mod = pcall(V.require, modName)
    if ok and type(mod) == "table" and type(mod.cast) == "function" then
      Bridge.registerCaster(name, mod.cast)
    elseif not ok then
      report("caster:" .. name, "caster '%s' did not load: %s", name, tostring(mod))
    end
  end
  caster("trees", "Gen4Trees")
  caster("rocks", "Gen4Rocks")
  caster("fence", "Gen4Fence")
  caster("flowers", "Gen4Flowers")
  caster("hd_pokemon", "Gen4HdPokemon")

  -- The passes that belong to every Gen 4 game, registered here so they are
  -- FIRST in draw order: the water sheet is opaque and writes depth, and what
  -- main.lua registers after install() (grass, the battle actors) draws over it.
  local okW, GW = pcall(V.require, "Gen4Water")
  if okW and type(GW) == "table" and GW.draw then
    Bridge.register("water", GW.draw)
  else
    report("water", "the water pass did not load: %s", tostring(GW))
  end
  -- The voxel scene's textured ground on the beach sand. Opaque, so it goes
  -- before grass and the actors, after the water it may sit beside.
  local okS, GS = pcall(V.require, "Gen4Sand")
  if okS and type(GS) == "table" and GS.draw then
    Bridge.register("sand", GS.draw)
  else
    report("sand", "the sand pass did not load: %s", tostring(GS))
  end
  -- Neighbour-tile blend skirts for Gen4Lawn swaps (grass/road/sand seams).
  local okL, GL = pcall(V.require, "Gen4Lawn")
  if okL and type(GL) == "table" and GL.draw then
    Bridge.register("lawn", GL.draw)
  else
    report("lawn", "the lawn blend pass did not load: %s", tostring(GL))
  end
  -- Small dirt piles on Platinum jump-down ledges (`criff` / `criffp`). Opaque,
  -- after the lawn, before the trees.
  local okB, GB = pcall(V.require, "Gen4Bump")
  if okB and type(GB) == "table" and GB.draw then
    Bridge.register("bump", GB.draw)
  else
    report("bump", "the bump pass did not load: %s", tostring(GB))
  end
  -- The voxel scene's 3D trees in place of Platinum's flat tree cards. Opaque,
  -- after the ground passes, before grass and the actors.
  local okT, GT = pcall(V.require, "Gen4Trees")
  if okT and type(GT) == "table" and GT.draw then
    Bridge.register("trees", GT.draw)
  else
    report("trees", "the tree pass did not load: %s", tostring(GT))
  end
  -- Small grey voxel rocks where Platinum draws its route rocks (`imped`). Opaque,
  -- after the trees. Gen4Lawn hides the native rock card only where these are built.
  local okR, GR = pcall(V.require, "Gen4Rocks")
  if okR and type(GR) == "table" and GR.draw then
    Bridge.register("rocks", GR.draw)
  else
    report("rocks", "the rock pass did not load: %s", tostring(GR))
  end
  -- Real 3D fences (posts, rails or pickets) where Platinum draws its flat fence
  -- banners (`imped`). Opaque, after the rocks. Gen4Hide drops the native banner
  -- only where every card of the shape has a fence built for it.
  local okFe, GFe = pcall(V.require, "Gen4Fence")
  if okFe and type(GFe) == "table" and GFe.draw then
    Bridge.register("fence", GFe.draw)
  else
    report("fence", "the fence pass did not load: %s", tostring(GFe))
  end
  -- Small voxel flowers on Platinum's flower beds (`nhana`). Opaque, after the
  -- rocks. Gen4Lawn repaints the bed's floor with grass.png once they exist.
  local okF, GF = pcall(V.require, "Gen4Flowers")
  if okF and type(GF) == "table" and GF.draw then
    Bridge.register("flowers", GF.draw)
  else
    report("flowers", "the flower pass did not load: %s", tostring(GF))
  end
  -- The voxel scene's sky (bands, clouds, sun/moon, stars, painted horizon, scenery)
  -- on Gen 4, with the engine's own horizon image hidden. Pre-terrain, so it is
  -- the backdrop. See lib/Gen4Sky.lua.
  local okK, GK = pcall(V.require, "Gen4Sky")
  if okK and type(GK) == "table" and GK.install then
    local okI, errI = pcall(GK.install)
    if not (okI and errI ~= false) then report("sky", "the sky pass did not install: %s", tostring(errI)) end
  else
    report("sky", "the sky pass did not load: %s", tostring(GK))
  end
  return true
end

-- Drop every baked Gen 4 effect mesh (water, sand, lawn, trees, grass). The voxel
-- pipeline's invalidate used to be the only reset path and it knew none of
-- these, so a graphics reset, a mod reload or a cache reset left the old
-- meshes (and, on a lost GL context, dead ones) in place.
function Bridge.invalidateAll()
  for _, name in ipairs({ "Gen4Sun", "Gen4Sand", "Gen4Lawn", "Gen4Bump", "Gen4Rocks", "Gen4Fence", "Gen4Flowers", "Gen4Trees", "Gen4Water", "Gen4Grass", "Gen4NpcModels" }) do
    local ok, mod = pcall(V.require, name)
    if ok and type(mod) == "table" and type(mod.invalidate) == "function" then
      local okI, err = pcall(mod.invalidate)
      if not okI then report("inv:" .. name, "%s.invalidate failed: %s", name, tostring(err)) end
    end
  end
end

function Bridge.uninstall()
  if not Bridge.installed then return end
  pcall(function() V.require("Gen4Sky").uninstall() end)
  pcall(function() V.require("Gen4Lawn").uninstall() end)
    Bridge.Ground.__terrariumBridgeToken = nil

  Bridge.Ground.endFree = Bridge.originalEndFree
  Bridge.Ground.forMap = Bridge.originalForMap
  Bridge.installed = false
end

return Bridge