-- Day/night tint for Gen 4's native 3D world.
--
-- Gen 4 renders its world through the engine's Gen4Ground, not VoxelScene.
-- DayTint only works for the 2D flat world (Gen 1-3 without voxel mode).
-- This module applies the day/night tint as a post-process pass through
-- Gen4Bridge, drawing a full-screen quad with the hour's tint multiplied
-- over the engine's rendered world.

local V = ...
local DayNight = V.require("DayNight")
local Voxel3D = V.require("Voxel3D")

local Tint = {}

local SHADER = [[
#ifdef VERTEX
  vec4 position(mat4 transform_projection, vec4 vertex_position) {
    return transform_projection * vertex_position;
  }
#endif
#ifdef PIXEL
  uniform vec3 tint;
  vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    return vec4(color.rgb * tint, color.a);
  }
#endif
]]

local shader = nil

local function getShader()
  if shader == nil then
    local ok, sh = pcall(love.graphics.newShader, SHADER)
    shader = (ok and sh) or false
  end
  return shader or nil
end

local function outdoorNow()
  local ok, Game = pcall(require, "src.core.Game")
  if not ok then return false end
  local ow = Game and Game.overworld
  local map = ow and ow.map
  if not map then return false end
  
  -- Gen 4: use Gen4Spawn.isOutdoor
  local okS, Spawn = pcall(V.require, "Gen4Spawn")
  if okS and type(Spawn) == "table" and Spawn.isOutdoor then
    local ok, r = pcall(Spawn.isOutdoor, map)
    if ok then return r and true or false end
  end
  
  return false
end

-- Draw the tint as a full-screen quad over the rendered world
function Tint.draw(scene)
  if not outdoorNow() then return end
  
  local tint = DayNight.tint(true)
  if not tint then return end
  local r, g, b = tint[1] or 1, tint[2] or 1, tint[3] or 1
  
  -- Skip if neutral (midday)
  if r > 0.999 and g > 0.999 and b > 0.999 then return end
  
  local sh = getShader()
  if not sh then return end
  
  local gfx = love.graphics
  local prevShader = gfx.getShader()
  local prevBlend, prevAlpha = gfx.getBlendMode()
  local prevDepth, prevDepthWrite = gfx.getDepthMode()
  
  -- Disable depth test for full-screen tint
  gfx.setDepthMode("always", false)
  gfx.setShader(sh)
  gfx.setBlendMode("multiply", "premultiplied")
  pcall(sh.send, sh, "tint", r, g, b)
  
  -- Draw full-screen quad covering the view
  local vw, vh = scene.vw or 1, scene.vh or 1
  gfx.rectangle("fill", 0, 0, vw, vh)
  
  gfx.setDepthMode(prevDepth or "lequal", prevDepthWrite)
  gfx.setBlendMode(prevBlend or "alpha", prevAlpha)
  gfx.setShader(prevShader)
end

return Tint
