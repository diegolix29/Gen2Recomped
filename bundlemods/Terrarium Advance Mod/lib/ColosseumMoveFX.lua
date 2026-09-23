local V = ...
local Models = V.CurrentSpriteModels
local Stadium = V.OverworldStadium
local Handlers = V.WazaHandlers
local M = {}
local context

function M.contextFor(battle)
  -- Overworld COLOSSEUM A/B is a separate compositor from CBE's standalone
  -- arena. A live StandaloneHost session must not hide this path: BattleScene
  -- is what the player sees, and MoveFX audio already advances from update().
  local session = Stadium and Stadium.colosseumSession(battle)
  if not (session and battle and Models) then return nil end
  if not context or context.battle ~= battle then
    M.finish("battle-replaced")
    local arena = {}
    for k, v in pairs(session.arena) do arena[k] = v end
    -- Stadium matrices and attachments are already in world-pixel units.
    arena.figureScale = 1
    context = {
      battle = battle, game = battle.game or V.mod.game, arena = arena,
      sides = {}, groundY = session.groundY,
      services = { colosseumOverworld = true, figureScale = 1 },
    }
  end
  context.groundY = session.groundY
  local records = {}
  for _, side in ipairs({ "player", "enemy" }) do
    local mon, battler = session[side], battle[side]
    context.sides[side] = { battler = battler }
    if mon.actor and session.at[side] == battler then
      records[side] = { actor = mon.actor, battler = battler, dex = mon.species }
    end
  end
  Models:bindOverworld(context, records)
  return context
end

function M.active(battle)
  return context ~= nil and Models.overworldContext == context
    and (battle == nil or context.battle == battle)
end

function M.ownsMove(battle)
  return M.active(battle) and Models.overworldMoveStarted == true
end

function M.update(dt)
  if M.active() then Models:update(context, dt) end
end

function M.actorStep(side, dt)
  if not (M.active() and Handlers) then return dt end
  local state = Handlers:actorControllerState(side)
  if state and state.motionFrozen then return 0 end
  return dt
end

function M.actorVisible(side)
  if not (M.active() and Handlers) then return true end
  return Handlers:actorVisible(side) ~= false
end

local function boundCanvasSize()
  local g = love and love.graphics
  if not (g and g.getCanvas) then return nil end
  local ok, canvas = pcall(function() return select(1, g.getCanvas()) end)
  if not ok then return nil end
  if type(canvas) == "table" then canvas = canvas[1] or canvas.canvas end
  if not canvas then return nil end
  if canvas.getPixelDimensions then
    local w, h = canvas:getPixelDimensions()
    if w and h and w > 0 and h > 0 then return w, h end
  end
  if canvas.getDimensions then
    local w, h = canvas:getDimensions()
    if w and h and w > 0 and h > 0 then return w, h end
  end
  return nil
end

function M.draw(vp, width, height)
  if not (M.active() and vp) then return false end
  width = tonumber(width)
  height = tonumber(height)
  if not (width and height and width > 0 and height > 0) then
    width, height = boundCanvasSize()
  end
  if not (width and height and width > 0 and height > 0) then return false end
  local services = context.services
  services.vp, services.stageVP = vp, vp
  services.renderSize = { width = width, height = height }
  services.project = function(x, y, z)
    local cx = vp[1]*x + vp[2]*y + vp[3]*z + vp[4]
    local cy = vp[5]*x + vp[6]*y + vp[7]*z + vp[8]
    local cw = vp[13]*x + vp[14]*y + vp[15]*z + vp[16]
    if cw <= 1e-6 then return nil end
    return (cx/cw*.5 + .5)*width, (cy/cw*.5 + .5)*height
  end
  return Models:drawWorld(context)
end

function M.drawPost(canvas, width, height)
  if M.active() and Handlers then
    return Handlers.drawPost(context, canvas, width, height)
  end
  return false
end

function M.finish(reason)
  if M.active() then
    Models:finish(context, reason)
    if V.BattleDirector then V.BattleDirector:finish(context, reason) end
    if V.MoveFXOwnership then V.MoveFXOwnership:finish(context, reason) end
    if Handlers then Handlers.finish() end
  end
  context = nil
end

return M