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
}

-- Below this the multiply is close enough to white to change no pixel.
Tint.NEUTRAL = 0.999

local function isGen4()
  local ok, GameVersion = pcall(require, "src.core.GameVersion")
  if not (ok and GameVersion and GameVersion.generation) then return false end
  local okG, g = pcall(GameVersion.generation)
  return okG and tonumber(g) == 4
end
Tint.isGen4 = isGen4

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
