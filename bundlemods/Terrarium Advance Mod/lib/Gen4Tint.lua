-- Gen4Tint: the hour's light on Platinum's own 3D world.
--
-- WHY THIS EXISTS
--
-- lib/DayTint paints the clock's colour (dusk warm, night blue) over the world
-- on the flat path. It can never fire on Gen 4, for two independent reasons:
--
--   1. Platinum's frame is the ENGINE's 3D world, handed to the Renderer as a
--      `worldOverride`. DayTint reads an override as "a pipeline drew this and
--      tinted it in its own shader" and stands down -- but the voxel pipeline
--      declines on Gen 4 (see Gen4Bridge), so nothing tinted it.
--   2. Its outdoor test is Map.isOutdoor, which reads Gen 1/2 header fields
--      and answers "indoors" for every Gen 4 map.
--
-- So a Platinum night was a noon with a dark sky painted behind it, and every
-- mesh Terrarium draws (trees, NPC bodies, Pokemon) sat at full daylight
-- brightness in the dark. This module is DayTint's Gen 4 twin: same multiply,
-- same seam (after the world blit, before the UI blit), Gen 4's own answers to
-- the two questions above. DayTint itself is untouched.
--
-- The colour is DayNight.tint -- the same clock the shadows (Gen4Sun), the
-- sky and Gen 1-3 follow, SYNC to the wall clock by default. Voxel3D.tint stays
-- neutral on purpose: this multiply covers the whole frame, effect meshes
-- included, so tinting them as well would darken them twice.
--
-- Rain is NOT painted here: on Gen 4 it is drawn in the 3D pass
-- (Gen4WorldHost.drawFpWeather / overlayFx) and a flat pass would double it.

local V = ...

local DayNight = V.require("DayNight")

local Tint = {
  installed = false,
  enabled = true,         -- master switch (a quick way to compare with / without)
  last = nil,             -- {r, g, b} of the last painted frame, for probes
  -- Screen-space lamp / window pools, fed from Gen4Bridge while the 3D
  -- camera is live. Drawn ADDITIVE after the night multiply so Platinum's
  -- own buildings and roads actually brighten (Voxel3D.lampLights never
  -- reach the engine's shader).
  blobs = {},
}

-- Below this the multiply is close enough to white to change no pixel.
Tint.NEUTRAL = 0.999

-- ---------------------------------------------------------------- settlements
--
-- Gen 4's deep night (DayNight.TINTS_DEEP: 36/44/80, about 0.14/0.17/0.31) is a
-- fine colour for a dark route and far too dark for a town, where the lamps and
-- lit windows are supposed to make the street readable. Gen 2 multiplies by
-- 88/104/168 (about 0.35/0.41/0.66) everywhere, which is why its towns look
-- open and Platinum's look like a wall.
--
-- So the multiply is eased toward a town floor while the camera is in a
-- settlement, and left alone on a route. A settlement is detected from what the
-- bridge already feeds us each frame: street posts count 1, lit windows count
-- TOWN_PANE_WEIGHT. The result is smoothed, so walking into a town brightens it
-- over ~TOWN_FADE seconds instead of popping.
--
-- THE KNOBS (all live; nothing needs a restart):
--   TOWN_FLOOR   the darkest a town's multiply may be, r/g/b 0..1. Raise it for a
--                brighter town, lower it for a darker one. {0.35, 0.41, 0.66} is
--                exactly Gen 2's night; {0,0,0} turns the lift off.
--   WILD_SCALE   multiplies the tint on routes and anywhere with no settlement.
--                1 leaves routes alone, 0.8 makes them 20% darker.
--   TOWN_FULL    how many post-equivalents count as "fully a town".
Tint.TOWN_FLOOR = { 0.40, 0.46, 0.70 }
Tint.WILD_SCALE = 0.75       -- routes: 25% darker than the hour's tint (was 1.0)
Tint.TOWN_FULL = 4
Tint.TOWN_PANE_WEIGHT = 0.35
-- A lit window counts toward "this is a town" by how far it is: in full inside
-- TOWN_NEAR world units, fading to nothing at TOWN_REACH. Windows are lit across
-- the whole 7x7-land window now, so without this a route passing a town a few
-- chunks away would be lifted to town brightness. Routes stay dark; walking
-- toward a town brightens the night as its windows come into range.
Tint.TOWN_NEAR = 350
Tint.TOWN_REACH = 1100
Tint.TOWN_FADE = 1.2          -- seconds to ease in / out
Tint.town = 0                 -- 0..1, smoothed; read by Gen4Light too

local clock = (love and love.timer and love.timer.getTime) or os.clock

-- The tint this frame will really be multiplied by, given the hour's own.
-- Gen4Light divides by exactly this, so it must stay the single place that
-- turns one into the other.
function Tint.adjust(r, g, b)
  local town = math.max(0, math.min(1, Tint.town or 0))
  local w = tonumber(Tint.WILD_SCALE) or 1
  if w ~= 1 then
    local k = w + (1 - w) * town
    r, g, b = r * k, g * k, b * k
  end
  local f = Tint.TOWN_FLOOR
  if f and town > 0 then
    r = r + (math.max(r, f[1] or 0) - r) * town
    g = g + (math.max(g, f[2] or 0) - g) * town
    b = b + (math.max(b, f[3] or 0) - b) * town
  end
  return math.min(1, r), math.min(1, g), math.min(1, b)
end

-- Called once per fx frame from feed(): how much of a settlement is around us.
local function updateTown(lights)
  local score = 0
  if type(lights) == "table" then
    local near, reach = Tint.TOWN_NEAR, Tint.TOWN_REACH
    for _, l in ipairs(lights) do
      if l.kind == "post" then
        score = score + 1
      else
        local w = Tint.TOWN_PANE_WEIGHT
        if l.d2 and reach > near then
          local d = math.sqrt(l.d2)
          local f = (reach - d) / (reach - near)
          w = w * (f < 0 and 0 or (f > 1 and 1 or f))
        end
        score = score + w
      end
    end
  end
  local target = math.max(0, math.min(1, score / math.max(0.1, Tint.TOWN_FULL)))
  local now = clock()
  local dt = Tint.townStamp and math.min(0.25, math.max(0, now - Tint.townStamp)) or nil
  Tint.townStamp = now
  if dt == nil then
    Tint.town = target                          -- first frame: no fade from nothing
  else
    Tint.town = Tint.town + (target - Tint.town) * (1 - math.exp(-dt / math.max(0.05, Tint.TOWN_FADE)))
  end
end

local function isNativeWorld()
  local okN, N = pcall(V.require, "NativeWorld")
  if okN and N and N.isNative then return N.isNative() end
  local ok, GameVersion = pcall(require, "src.core.GameVersion")
  if not (ok and GameVersion and GameVersion.generation) then return false end
  local okG, g = pcall(GameVersion.generation)
  g = okG and tonumber(g) or nil
  return g == 4 or g == 5
end
local function isGen4()
  return isNativeWorld()
end
Tint.isGen4 = isGen4
Tint.isNativeWorld = isNativeWorld

-- Is the player under the open sky? Gen4Spawn.isOutdoor is the real answer on
-- Platinum; a canopy floor takes the hour's colour like it does elsewhere.
local function outdoorNow()
  local okG, Game = pcall(require, "src.core.Game")
  local ow = okG and type(Game) == "table" and Game.overworld or nil
  local map = ow and ow.map
  if not map then return false end
  local okS, Spawn = pcall(V.require, "Gen4Spawn")
  if okS and type(Spawn) == "table" and Spawn.isOutdoor then
    local ok, r = pcall(Spawn.isOutdoor, map)
    if ok and r then return true end
  end
  local okC, canopy = pcall(DayNight.isCanopy, map)
  return okC and canopy and true or false
end

-- Project world-space flames into normalised window coords. Call while
-- Voxel3D.beginScene is open so Voxel3D.project sees this frame's matrix.
local glowTex = nil
local function glowImage()
  if glowTex then return glowTex end
  local ok, img = pcall(function()
    local n = 64
    local data = love.image.newImageData(n, n)
    local c = (n - 1) * 0.5
    for y = 0, n - 1 do
      for x = 0, n - 1 do
        local dx, dy = (x - c) / c, (y - c) / c
        local d = math.sqrt(dx * dx + dy * dy)
        local a = 0
        if d < 1 then a = (1 - d) * (1 - d) end
        data:setPixel(x, y, 1, 1, 1, a)
      end
    end
    local t = love.graphics.newImage(data)
    t:setFilter("linear", "linear")
    return t
  end)
  glowTex = (ok and img) or false
  return glowTex or nil
end

-- FALLBACK ONLY. Gen4Light (the world-space receiver) lights the real roads and
-- walls, depth-tested, and sets `Light.ok` every frame it ran. These flat discs
-- are painted over the finished frame with no depth, so they sit on top of
-- characters and read as specks; they are only drawn when the receiver did NOT
-- run this frame (its shader failed to compile, or the effect was disabled),
-- or when Tint.FORCE_BLOBS is on.
Tint.FORCE_BLOBS = false

local function receiverRan()
  local ok, Light = pcall(V.require, "Gen4Light")
  if not (ok and type(Light) == "table") then return false end
  local ran = Light.ok == true
  Light.ok = false                      -- consumed: the next frame must prove it again
  return ran
end

function Tint.feed(lights, vw, vh)
  Tint.blobs = {}
  updateTown(lights)
  if receiverRan() and not Tint.FORCE_BLOBS then return end
  vw, vh = tonumber(vw) or 0, tonumber(vh) or 0
  if vw < 1 or vh < 1 or type(lights) ~= "table" then return end
  local Voxel3D = V.require("Voxel3D")
  for _, l in ipairs(lights) do
    -- ONE pool per light, where it lands. (There used to be a second "hot
    -- spot" disc on the lantern: the light on top and bottom.)
    local ok, sx, sy, sc = pcall(Voxel3D.project, l.x or 0, l.y or 0, l.z or 0)
    if ok and sx and sy then
      Tint.blobs[#Tint.blobs + 1] = {
        nx = sx / vw,
        ny = sy / vh,
        nr = ((l.radius or 300) * (tonumber(sc) or 1) * 0.8) / vw,
        power = (tonumber(l.power) or 1) * 0.9,
      }
    end
  end
end

-- Point glows painted ADDITIVE after the multiply, like the lamp pools above but
-- coloured per glow and without the receiver check: fireflies (AmbientLife and
-- Flora's flies) are drawn into the frame before this multiply and would come out
-- at deep-night brightness (about 0.14/0.17/0.31). Coordinates are normalised to
-- the world canvas. The owner calls beginGlows once per frame; a list older than a
-- quarter second is ignored, so a frame that never refreshed it paints nothing.
Tint.glows = {}
Tint.glowAt = 0
Tint.glowLayer = nil     -- Gen4Glow's depth-occluded version of the same glows
Tint.glowLayerAt = 0
function Tint.beginGlows()
  Tint.glows = {}
  Tint.glowAt = (love.timer and love.timer.getTime()) or 0
end
function Tint.addGlow(nx, ny, nr, r, g, b, a)
  local list = Tint.glows
  if #list >= 96 then return end
  list[#list + 1] = { nx = nx, ny = ny, nr = nr, r = r or 1, g = g or 1, b = b or 1, a = a or 1 }
end

-- The colour this frame should be multiplied by, or nil to leave it alone.
function Tint.forFrame(renderer)
  if not (Tint.enabled and renderer) then return nil end
  if not isGen4() then return nil end
  -- the engine's 3D frame is the override; accept it, and a plain world too
  if not (renderer.worldOverride or renderer.worldActive) then return nil end
  if not outdoorNow() then return nil end
  local ok, tint = pcall(DayNight.tint, true)
  if not (ok and tint) then return nil end
  local r, g, b = tint[1] or 1, tint[2] or 1, tint[3] or 1
  if r > Tint.NEUTRAL and g > Tint.NEUTRAL and b > Tint.NEUTRAL then return nil end
  r, g, b = Tint.adjust(r, g, b)         -- settlement lift / route darkening
  if r > Tint.NEUTRAL and g > Tint.NEUTRAL and b > Tint.NEUTRAL then return nil end
  return r, g, b
end

-- One rectangle over the window, multiplied into what is under it. Every
-- graphics-state read is optional and put back, exactly as DayTint does.
local function saved(name, ...)
  local fn = love.graphics[name]
  if not fn then return nil end
  local ok, a, b, c, d = pcall(fn, ...)
  if not ok then return nil end
  return a, b, c, d
end

function Tint.paint(r, g, b)
  local gfx = love.graphics
  local shader = saved("getShader")
  local sx, sy, sw, sh = saved("getScissor")
  local blend, alpha = saved("getBlendMode")
  local pr, pg, pb, pa = saved("getColor")
  local w, h = gfx.getDimensions()

  if gfx.setShader then gfx.setShader() end
  if gfx.setScissor then gfx.setScissor() end
  gfx.setBlendMode("multiply", "premultiplied")
  gfx.setColor(r, g, b, 1)
  gfx.rectangle("fill", 0, 0, w, h)

  -- Native Gen 4 has no voxel lamp shader. Additive pools after the
  -- multiply are the light source for streets and walls.
  local blobs = Tint.blobs
  local glow = glowImage()
  if blobs and #blobs > 0 then
    local okC, lamp = pcall(DayNight.lampColor)
    lamp = (okC and lamp) or { 1.0, 0.84, 0.5 }
    gfx.setBlendMode("add", "alphamultiply")
    for _, b in ipairs(blobs) do
      local p = math.min(1.4, (b.power or 1) * 1.15)
      local cx, cy = b.nx * w, b.ny * h
      local rad = math.max(48, (b.nr or 0.12) * w)
      gfx.setColor(lamp[1] * p, lamp[2] * p, lamp[3] * p, 1)
      if glow then
        gfx.draw(glow, cx, cy, 0, (rad * 2) / glow:getWidth(), (rad * 2) / glow:getHeight(),
                 glow:getWidth() * 0.5, glow:getHeight() * 0.5)
      else
        gfx.circle("fill", cx, cy, rad)
      end
    end
  end

  local glows = Tint.glows
  local nowT = (love.timer and love.timer.getTime()) or 0
  local gLayer = Tint.glowLayer
  if gLayer and (nowT - (Tint.glowLayerAt or 0)) < 0.25 then
    -- Gen4Glow's layer: the same glows, already hidden behind whatever the scene
    -- has in front of them. Its colour is accumulated pre-multiplied.
    gfx.setBlendMode("add", "premultiplied")
    gfx.setColor(1, 1, 1, 1)
    gfx.draw(gLayer, 0, 0, 0, w / gLayer:getWidth(), h / gLayer:getHeight())
  elseif glow and glows and #glows > 0 and (nowT - (Tint.glowAt or 0)) < 0.25 then
    gfx.setBlendMode("add", "alphamultiply")
    for _, b2 in ipairs(glows) do
      local rad = math.max(3, (b2.nr or 0.02) * w)
      gfx.setColor(b2.r, b2.g, b2.b, math.min(1, b2.a))
      gfx.draw(glow, b2.nx * w, b2.ny * h, 0, (rad * 2) / glow:getWidth(),
               (rad * 2) / glow:getHeight(), glow:getWidth() * 0.5, glow:getHeight() * 0.5)
    end
  end

  gfx.setBlendMode(blend or "alpha", alpha)
  gfx.setColor(pr or 1, pg or 1, pb or 1, pa or 1)
  if gfx.setScissor then
    if sx then gfx.setScissor(sx, sy, sw, sh) else gfx.setScissor() end
  end
  if shader and gfx.setShader then gfx.setShader(shader) end
  Tint.last = { r, g, b }
end

-- Wrap Renderer:endFrame. The world is blitted first and the UI canvas after
-- it; the first draw of the UI canvas is the boundary, so the multiply lands on
-- the world and never on the dialogs and menus in front of it.
function Tint.install()
  if Tint.installed then return true end
  local okR, Renderer = pcall(require, "src.render.Renderer")
  if not (okR and type(Renderer) == "table" and type(Renderer.endFrame) == "function") then
    return false
  end
  Tint.Renderer = Renderer
  -- only the newest install is live; a wrapper left by a mod reload passes
  -- straight through instead of tinting twice
  local token = {}
  Renderer.__terrariumGen4TintToken = token
  local inner = Renderer.endFrame

  function Renderer:endFrame(zones, worldZones)
    if Renderer.__terrariumGen4TintToken ~= token then
      return inner(self, zones, worldZones)
    end
    local okF, r, g, b = pcall(Tint.forFrame, self)
    if not (okF and r) then return inner(self, zones, worldZones) end

    local gfx = love.graphics
    local draw = gfx.draw
    local ui = self.canvas
    local painted = false
    gfx.draw = function(tex, ...)
      if not painted and tex == ui then
        painted = true
        gfx.draw = draw                     -- the rectangle must not re-enter
        pcall(Tint.paint, r, g, b)
      end
      return draw(tex, ...)
    end

    local ok, err = pcall(inner, self, zones, worldZones)
    gfx.draw = draw
    if not ok then error(err, 0) end
  end

  Tint.installed = true
  return true
end

function Tint.uninstall()
  if not Tint.installed then return end
  -- Do not restore Renderer.endFrame: DayTint installs its own wrapper on top
  -- of ours later, and putting the old one back would drop it. A dead token
  -- turns this wrapper into a pass-through instead.
  if Tint.Renderer then Tint.Renderer.__terrariumGen4TintToken = nil end
  Tint.installed = false
end

return Tint