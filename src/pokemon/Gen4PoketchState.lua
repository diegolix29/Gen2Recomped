-- Save-backed records used by Platinum's watch apps.
local State = {}
function State.dowsing(game,x,y)
  local result={kind=0,items={},x=x,y=y}
  local ow=game and game.overworld
  if not (ow and ow.map and ow.player) then return result end
  local save=game.save or {}
  local Pickups=require('src.import.Gen4Pickups')
  local distances={[0]=8,[1]=24,[2]=48}
  for _,item in ipairs((ow.map.def or {}).signs or {}) do
    local pickup=item.pickup
    local flag=Pickups.hiddenFlag(item.script)
    local taken=(save.hiddenTaken or {})[ow.map.id..'_sign_'..item.x..'_'..item.y]
      or item.eventFlag and (save.flags or {})[item.eventFlag]
      or flag and (save.flags or {})[('FLAG_G4_%04X'):format(flag)]
    if pickup and pickup.kind=='hidden' and not taken then
      local dx,dy=item.x-ow.player.cellX,item.y-ow.player.cellY
      if math.abs(dx)<=7 and dy>=-7 and dy<=6 then
        local ix,iy=112+dx*11,101+dy*11
        local squared=(ix-x)^2+(iy-y)^2
        local range=distances[pickup.range]
        if range and squared<=range^2 then
          result.kind=2
          result.items[#result.items+1]={x=ix,y=iy,range=pickup.range}
        elseif squared<=48^2 and result.kind==0 then result.kind=1 end
      end
    end
  end
  return result
end

function State.tick(game, dt)
  if game and game.data and game.data.isGen4Cache then
    require('src.world.Gen4BerryPatches').sync(game)
    require('src.world.Gen4BerryPatches').observe(game)
  end
  local s = game and game.save and game.save.poketch
  if not s then return end
  dt = math.max(0, tonumber(dt) or 0)
  if s.stopwatchRunning then s.stopwatch = (s.stopwatch or 0) + dt end
  if s.timerRunning then
    s.timer = math.max(0, (s.timer or 0) - dt)
    if s.timer == 0 then s.timerRunning, s.timerFinished = false, true end
  end
end

function State.remember(game, mon)
  if not (game and game.data and game.data.isGen4Cache and game.save and mon)
    or mon.isEgg or not mon.species then return end
  local save = game.save
  save.poketch = save.poketch or {}
  local history = save.poketch.history or {}
  save.poketch.history = history
  -- Store a snapshot, so subsequent evolutions and releases do not alter history.
  table.insert(history, 1, {species=mon.species, form=mon.form,
    gender=mon.gender, personality=mon.personality, level=mon.level})
  while #history > 12 do table.remove(history) end
end

function State.compatibility(data, a, b)
  if not (a and b) or a == b then return 0 end
  return require('src.pokemon.DayCare').gen3Score(data, {
    daycare={breed={{mon=a},{mon=b}}}})
end

return State
