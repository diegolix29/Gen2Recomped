-- Captures one still frame of the overworld the instant a battle is about to
-- replace it, for Colosseum Battle Environments' "OVERWORLD" arena entry
-- (see ArenaCatalog.DEFINITIONS.overworld) to paint as its backdrop.
--
-- Deliberately does NOT change who owns or draws the battle. CBE keeps every
-- one of its own mechanics -- camera rig, actors, crowd, move FX ownership --
-- exactly as it would for any baked entry in its catalog; this module only
-- remembers what the ground looked like a moment before the fight covered
-- it, so Arena.lua's backdrop painter has a picture to draw instead of a
-- procedural sky. See lib/Arena.lua's "overworld" profile branch of
-- paintBackdropStatic for the other half of this.
local V = ...
local M = {}

local snapshotCanvas, snapshotW, snapshotH = nil, 0, 0

-- True only at the one moment this matters: CBE is on, and its own resolved
-- arena for THIS battle is the live-overworld pick. Every other battle
-- (CBE off, or any baked arena) makes this a no-op.
local function wantsSnapshot(battle)
  local ArenaCatalog = V.ArenaCatalog
  if not (ArenaCatalog and type(ArenaCatalog.enabled) == "function"
      and type(ArenaCatalog.resolve) == "function") then return false end
  local game = battle and battle.game
  local okEnabled, enabled = pcall(ArenaCatalog.enabled, game)
  if not (okEnabled and enabled) then return false end
  local okDef, def = pcall(ArenaCatalog.resolve, game, battle)
  return okDef and type(def) == "table" and def.liveOverworld == true
end

-- Copies whatever Voxel3D.canvas() currently holds into a canvas this module
-- owns. Called from the pushBattle seam below, which runs before the
-- transition wipe -- the last point at which that canvas still holds the
-- frame the player was actually looking at, not a battle-screen frame.
function M.capture(battle)
  if not wantsSnapshot(battle) then return false end
  local Voxel3D = V.Voxel3D
  if not (Voxel3D and type(Voxel3D.canvas) == "function") then return false end
  local okSrc, src = pcall(Voxel3D.canvas)
  if not (okSrc and src) then return false end
  local okSize, w, h = pcall(Voxel3D.size)
  if not okSize then return false end
  w, h = tonumber(w) or 0, tonumber(h) or 0
  if w <= 0 or h <= 0 then return false end
  if not (love and love.graphics and love.graphics.newCanvas) then return false end
  if not (snapshotCanvas and snapshotW == w and snapshotH == h) then
    if snapshotCanvas then
      pcall(function() if snapshotCanvas.release then snapshotCanvas:release() end end)
    end
    snapshotCanvas, snapshotW, snapshotH = nil, 0, 0
    local okNew, c = pcall(love.graphics.newCanvas, w, h)
    if not okNew or not c then return false end
    snapshotCanvas, snapshotW, snapshotH = c, w, h
  end
  local prior = love.graphics.getCanvas()
  local ok = pcall(function()
    love.graphics.push("all")
    if love.graphics.origin then love.graphics.origin() end
    if love.graphics.setScissor then love.graphics.setScissor() end
    love.graphics.setCanvas(snapshotCanvas)
    love.graphics.clear(0, 0, 0, 1)
    love.graphics.setBlendMode("replace", "premultiplied")
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(src, 0, 0)
    love.graphics.setCanvas(prior)
    love.graphics.pop()
  end)
  if not ok then
    pcall(love.graphics.setCanvas, prior)
    return false
  end
  return true
end

-- What Arena.lua's backdrop painter draws. Returns nil, 0, 0 when nothing
-- has been captured yet (e.g. the very first battle of a session that
-- somehow reaches the arena before pushBattle ran) so the caller can fall
-- back to a plain gradient instead of erroring.
function M.image()
  return snapshotCanvas, snapshotW, snapshotH
end

function M.install()
  local ok, OverworldState = pcall(require, "src.world.OverworldController")
  if not (ok and OverworldState) then return false end
  if OverworldState.cbeOverworldSnapshotHook then return true end
  local inner = OverworldState.pushBattle
  -- The one place the overworld starts a battle, and it runs BEFORE the
  -- transition is pushed -- the same seam OverworldBattle.install uses, for
  -- the same reason. Purely an observer: never returns early, never touches
  -- battle or inner's result, so it cannot change what the engine or any
  -- other mod does with this battle.
  function OverworldState:pushBattle(battle)
    pcall(M.capture, battle)
    return inner(self, battle)
  end
  OverworldState.cbeOverworldSnapshotHook = true
  return true
end

return M
