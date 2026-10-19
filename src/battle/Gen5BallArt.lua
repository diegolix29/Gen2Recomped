-- src/battle/Gen5BallArt.lua
--
-- BLACK AND WHITE'S THROWN POKe BALL, drawn out of the cartridge's own art.
--
-- Platinum and HeartGold keep their thrown balls as OBJ cells
-- (`ball_throws/*` in the battle archive, `gen4_graphics.battleObjects`), and
-- `Gen4Battle.drawThrownBall` draws the cell `Gen4BallAnim` names.  Black and
-- White have no such archive: the ball is a PARTICLE.  /a/0/0/6 (the SPA
-- archive the move animations already read, `data.gen5_particles`) carries it
-- as two texture sets:
--
--   spa 60   eight 32x32 frames of a Poke Ball turning over -- the emitter
--            animates textures 0..7 on a loop, which is the spin in flight
--   spa 61   five frames of the ball at rest and opening: 2 the ball facing
--            the camera, 4 the ball split open
--
-- These are the Poke Ball's. EVERY BALL HAS ITS OWN FOUR FILES: the effect
-- VM's PARTICLE_LOAD remaps 46-49 by the ball (0x021FE38C: + (ball - 1) * 4),
-- so ball b's spin is 48 + 4(b - 1) and its rest set 49 + 4(b - 1) -- the
-- Master Ball 48 / 49, Ultra 52 / 53, Great 56 / 57, Poke 60 / 61 ... up to
-- the 25th (the Dream Ball) at 144 / 145; `Gen5MoveAnimData` imports all 25.
--
-- The CAPTURE is the cartridge's own shared effect 570 now
-- (src/battle/Gen5BallAnim.lua, which draws itself). This file draws what
-- still rides `Gen4BallAnim` -- the player's send-out -- with Gen4BallAnim's
-- path and timing and these pictures. The cell numbers `Gen4BallAnim` hands
-- out are the ball_throws sheet's (0..7 spin, 8 opening, 9 open), and they map
-- onto the two sets above.

local M = {}

M.SPIN_SPA = 60
M.REST_SPA = 61
M.REST_FRONT = 2   -- spa 61 texture: the closed ball facing the camera
M.REST_OPEN = 4    -- spa 61 texture: the ball split open

-- the ball id (1..25) of a `Gen4Battle.BALL_THROWS` art name
function M.ballIdOf(name)
  if name == "park_ball" then return 25 end
  local ok, Gen4Battle = pcall(require, "src.battle.Gen4Battle")
  for i, n in pairs(ok and Gen4Battle.BALL_THROWS or {}) do
    if n == name and i <= 15 then return i + 1 end
  end
  return 4
end

local function texturePath(data, spa, index)
  local fx = data and data.gen5_particles
  local effects = type(fx) == "table" and fx.effects or nil
  local entry = type(effects) == "table" and effects["spa_" .. spa] or nil
  local tex = type(entry) == "table" and entry.textures or nil
  local row = type(tex) == "table" and tex[index + 1] or nil
  return type(row) == "table" and row.path or nil
end

-- framePath(data, cell) -> asset path of the picture for a Gen4BallAnim cell,
-- or nil on a cache without Black and White's particles
function M.framePath(data, cell, ballId)
  cell = tonumber(cell) or 0
  local shift = ((tonumber(ballId) or 4) - 4) * 4
  local spin, rest = M.SPIN_SPA + shift, M.REST_SPA + shift
  if not texturePath(data, spin, 1) then spin, rest = M.SPIN_SPA, M.REST_SPA end
  if cell >= 8 then return texturePath(data, rest, M.REST_OPEN) end
  if cell == 0 then
    return texturePath(data, rest, M.REST_FRONT) or texturePath(data, spin, 0)
  end
  return texturePath(data, spin, cell)
end

function M.available(data)
  return M.framePath(data, 1) ~= nil
end

-- draw(battle, anim) -> true when it drew.  Centred on the anim's point and
-- rotated about its own centre, as `drawThrownBall` draws an OBJ cell.
function M.draw(battle, anim)
  if not (battle and anim and anim.visible) then return false end
  local data = battle.data or (battle.game and battle.game.data)
  local path = M.framePath(data, anim.cell, M.ballIdOf(anim.ball))
  if not path then return false end
  local ok, img = pcall(require("src.render.Assets").image, path)
  if not (ok and img) then return false end
  local w, h = img:getDimensions()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, anim.x, anim.y, anim.angle or 0, 1, 1, w / 2, h / 2)
  return true
end

return M
