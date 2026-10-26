-- Zallax's Emerald 3DS Voxels (ported by Ceedrack): the voxel overworld of Emerald 3DS
-- (https://github.com/ZallaxDev/emerald-3ds, by Zallax, MIT) on this engine.
--
-- Emerald 3DS models Hoenn from the cartridge's own drawing: every building
-- is a mesh that reproduces its art pixel for pixel in the GBA's projection,
-- the mountains are relief lattices read off the drawing, the signposts are
-- pixel voxels and the trees are its own original art.  Its generators turn
-- the player's ROM into four files (buildings, relief, regions, signposts);
-- bake/bake.py runs them unchanged and drops the files in generated/ -- a folder name
-- scripts/pack_love.sh prunes from every build, so the ROM-derived files
-- never leave the player's own machine.  This mod
-- reads those files and draws them the way the 3DS does -- see lib/Render.lua
-- for the frame and lib/Builder.lua for the geometry.
--
-- It registers one drawWorld pipeline, "e3ds_voxel": OFF and the five 3D
-- ANGLE rungs of the original (34-46 degrees, 40 its default), on hotkey 0.
-- Presentational only: nothing about where anybody stands changes.

local mod = ...

local V = { mod = mod, path = mod.path }
local modules = {}

function V.log(fmt, ...)
  local ok, Logger = pcall(require, "src.core.Logger")
  local msg = ("e3ds_voxel: " .. fmt):format(...)
  if ok and Logger and Logger.warn then Logger.warn("%s", msg) else print(msg) end
end

function V.require(name)
  local hit = modules[name]
  if hit ~= nil then return hit end
  local rel = "lib/" .. name .. ".lua"
  local source = mod:read(rel)
  if not source then error(("EMERALD_3DS_VOXEL: %s is missing -- reinstall the mod"):format(rel), 0) end
  local chunk, err = load(source, "@" .. mod.path .. "/" .. rel)
  if not chunk then error(("EMERALD_3DS_VOXEL: %s did not compile: %s"):format(rel, tostring(err)), 0) end
  local value = chunk(V)
  modules[name] = value
  return value
end
mod.V = V
_G.__EMERALD_3DS_VOXEL_V = V

local Data = V.require("Data")
local Render = V.require("Render")
local Battle = V.require("Battle")

local function isEmerald()
  local ok, GameVersion = pcall(require, "src.core.GameVersion")
  return ok and GameVersion.get and GameVersion.get() == "emerald"
end

local warned = false
local function ready()
  if not isEmerald() then return false end
  local ok, why = Data.load()
  if not ok and not warned then
    warned = true
    V.log("voxel data not baked (%s) -- run bake/bake.py with your Emerald ROM", tostring(why))
  end
  return ok
end

local frameDt = 1 / 60

mod.content.render_pipelines:register("e3ds_voxel", {
  label = "E3DS 3D",
  levels = { "OFF", "34", "37", "40", "43", "46" },
  hotkey = "0",
  -- above DRAMATIC_SHAPE's voxel mode (20), so with both switched on this is
  -- the one that draws
  priority = 30,
  available = function()
    return isEmerald() and Render.available() and true or false
  end,
  update = function(dt, level)
    frameDt = dt or frameDt
    -- the 3D battles (lib/Battle.lua): installed on the first tick, when the
    -- engine's battle modules and DRAMATIC_SHAPE's are all loaded
    if isEmerald() then
      if not Battle.installed then
        local ok, err = pcall(Battle.install)
        Battle.installed = true
        if not ok then V.log("battle seams not installed: %s", tostring(err)) end
      end
      if level and level > 0 then ready() end
      Battle.quietDramaticShape()
      Battle.update()
    end
  end,
  drawWorld = function(ctx)
    if not ready() then return nil end
    -- an error mid-frame must not leave the frame's graphics state pushed
    -- (the engine retires a pipeline that does): unwind, log once a kind,
    -- and let this frame fall back to the flat view
    local depth = love.graphics.getStackDepth and love.graphics.getStackDepth() or nil
    local ok, result = pcall(Render.drawWorld, ctx, frameDt, ctx.level or 3)
    if ok then return result end
    if depth then
      while love.graphics.getStackDepth() > depth do love.graphics.pop() end
    end
    love.graphics.setShader()
    love.graphics.setCanvas()
    Render.errors = Render.errors or {}
    if not Render.errors[tostring(result)] then
      Render.errors[tostring(result)] = true
      V.log("frame failed: %s", tostring(result))
    end
    return nil
  end,
  invalidate = function()
    Render.invalidate()
  end,
})

-- Where the battle's picture lies in the window, for the battle camera's
-- framing: the metrics of the frame just finished.
mod.hooks:wrap("render.hud", function(next, game, viewport, ...)
  Battle.viewport = viewport
  return next(game, viewport, ...)
end)
