-- ENGINE SEAMS THAT SURVIVE A SECOND BOOT IN THE SAME PROCESS.
--
-- Every wrap this mod puts on an engine table used to be guarded by a plain
-- `X.dramaticShape...Hook = true` flag, so that a hot reload could not stack
-- two copies. That assumed one load per process, and the launcher broke it:
-- EXIT GAME / QUIT GAME go back to the launcher IN PROCESS (main.lua
-- returnToLauncher), and the next Play runs Game:load again. The engine's own
-- modules (BattleState, OverworldController, Renderer) stay in package.loaded,
-- flags and wrappers included, but this mod is loaded afresh -- new
-- OverworldBattle, new session, new locals. So the second boot saw the flag,
-- skipped install, and every wrapper still on the engine was the FIRST load's,
-- talking to a module nothing drives any more:
--
--   * pushBattle staged the fight on the dead instance (the live one never
--     saw it; battle.started's ensure() staged it again without the cull);
--   * BattleState:draw asked the dead instance for its shot, got nil, and drew
--     the plain white battle screen;
--   * the live instance's innerPics was never captured, so sideTexture
--     returned nil -- "no enemy billboard -- ... render=true (nil)".
--
-- So the flag now carries what the wrap replaced and what it put there. A
-- later install puts the original back first -- only where the function is
-- still that wrapper, so a wrap another mod stacked on top is left alone --
-- and then wraps again with this load's closures.

local Rewrap = {}

-- ------- EVERY WRAP, IN THE ORDER IT WAS MADE
--
-- Several wraps share one engine function -- FirstPerson and CamControl both
-- wrap Game.touchpressed, FreeMove, the SELECT hook and Horde all wrap
-- OverworldState.handleInput -- so putting one load's wraps back flag by flag
-- would find the outermost one on top and every inner one buried under it.
-- The list lives on the engine's Game module because that table, unlike this
-- mod's, survives into the next load; unwindAll walks it newest-first, which
-- peels a chain from the outside in.
local function registry()
  local Game = require("src.core.Game")
  local r = rawget(Game, "dramaticShapeRewraps")
  if type(r) ~= "table" then
    r = {}
    Game.dramaticShapeRewraps = r
  end
  return r
end

-- Called once, at the top of main.lua, before anything installs: put back
-- every function a previous load of this mod replaced (where it is still that
-- load's wrapper), newest first.
function Rewrap.unwindAll()
  local r = registry()
  for i = #r, 1, -1 do
    local e = r[i]
    if e.cleanup then e.cleanup()
    elseif rawget(e.tbl, e.name) == e.wrapper then e.tbl[e.name] = e.orig end
    r[i] = nil
  end
end

function Rewrap.onUnwind(cleanup)
  local r = registry()
  r[#r + 1] = { cleanup = cleanup }
end

-- specs: a list of { table, flagKey, { functionName, ... } }.
-- install(): the existing guarded install body; it runs with every flag
-- cleared, so its own `if X.flag then return end` guards pass.
function Rewrap.install(specs, install)
  for _, spec in ipairs(specs) do
    local tbl, flag = spec[1], spec[2]
    local saved = rawget(tbl, flag)
    if type(saved) == "table" then
      for name, rec in pairs(saved) do
        if rawget(tbl, name) == rec.wrapper then tbl[name] = rec.orig end
      end
    end
    tbl[flag] = nil
  end
  local before = {}
  for i, spec in ipairs(specs) do
    local snap = {}
    for _, name in ipairs(spec[3]) do snap[name] = rawget(spec[1], name) end
    before[i] = snap
  end
  install()
  for i, spec in ipairs(specs) do
    local tbl, flag = spec[1], spec[2]
    -- two specs may share one table and one flag (OverworldBattle's
    -- pushBattle and its BattleState seams do not, but nothing stops it)
    local rec = type(rawget(tbl, flag)) == "table" and rawget(tbl, flag) or {}
    for _, name in ipairs(spec[3]) do
      local now = rawget(tbl, name)
      if now ~= before[i][name] then
        rec[name] = { orig = before[i][name], wrapper = now }
        local r = registry()
        r[#r + 1] = { tbl = tbl, name = name, orig = before[i][name], wrapper = now }
      end
    end
    -- truthy, so any older guard reading the flag still sees "installed"
    tbl[flag] = rec
  end
end

return Rewrap
