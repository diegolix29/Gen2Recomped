-- Read-only National Dex and colour identity, shared by battle/cache consumers.
--
-- TRANSFORM
-- The engine records a Transform by swapping the battler's *picture* and
-- nothing else: mon.species stays DITTO the whole fight. Every Colosseum
-- consumer (CurrentSpriteModels, BattleCache, PokemonActors, doubles) asks
-- this module which model a battler is, so reading mon.species alone meant the
-- 3D actor never changed after Transform, in any generation.
--
-- This module now also OBSERVES the two seams that report a Transform and keeps
-- a small weak-keyed registry of "this mon currently looks like dex N":
--   * the engine's `pokemon.sprite` hook: every battle pic is resolved through
--     it with ctx.mon (the individual) and ctx.species (what is being drawn).
--     A pic whose species differs from the mon's own species is a Transform,
--     and one whose species matches clears it. Generation-neutral.
--   * Gen-I BattleState:speciesSprite(species, isPlayerSide), the explicit seam
--     the Stadium code already uses; it also names the side.
-- Nothing is ever written to a mon (mons are saved); the registry is weak and
-- is dropped when a battle ends or a side switches.
local V=...
local M={version=2}
local sourceNames,sourceDexByName=nil,{}
local function sourceDex(species)
  if species==nil then return nil end
  local names=V.ColosseumDexNames
  if type(names)~="table" then return nil end
  if names~=sourceNames then
    sourceNames=names;sourceDexByName={}
    for dex,name in pairs(names) do
      if tonumber(dex) and type(name)=="string" then sourceDexByName[name:upper()]=tonumber(dex) end
    end
  end
  return sourceDexByName[tostring(species):upper()]
end

-- Transform events are rare (a few lines per transform), so they are logged by
-- default; set CBE_TRANSFORM_DEBUG=0 to silence them.
local DEBUG=not (os and os.getenv and os.getenv("CBE_TRANSFORM_DEBUG")=="0")
local function logf(fmt,...)
  if not DEBUG then return end
  local log=V.mod and V.mod.log
  if log and type(log.info)=="function" then pcall(log.info,log,fmt,...) end
end
M.log=logf

-- species (id / name / number) -> National Dex number, or nil. `mon` is only
-- used for the detached numeric hints a challenge clone may carry.
local function lookupDex(defs,species,mon)
  if species==nil then return nil end
  local def=defs and (defs[species] or defs[tostring(species)])
  -- Species identity wins over detached numeric hints. This keeps 3D actors and
  -- HUD portraits on the exact same National-Dex identity even when a challenge
  -- clone carries a stale/foreign `dex` field.
  local dex=tonumber(def and (def.nationalDex or def.dex or def.number or def.index))
    or sourceDex(species)
  if not dex and type(mon)=="table" then
    dex=tonumber(mon.nationalDex) or tonumber(mon.speciesIndex) or tonumber(mon.dex)
  end
  if not dex and type(species)=="number" then dex=species end
  if not dex and defs then
    local wanted=tostring(species):upper()
    for _,candidate in pairs(defs) do
      if type(candidate)=="table" and (tostring(candidate.id):upper()==wanted
          or tostring(candidate.name):upper()==wanted) then
        dex=tonumber(candidate.nationalDex or candidate.dex or candidate.number or candidate.index);break
      end
    end
  end
  return dex
end

-- The Colosseum actor catalog now genuinely covers National Dex 1..386.
-- Keep identity validation tied to that catalog instead of the old Gen I/II
-- ceiling of 251 so cross-generation Mt. Battle consumers do not reject a
-- source-backed Hoenn actor solely because its National Dex number is >251.
local function validDex(dex)
  if not dex or dex%1~=0 or dex<1 then return false end
  local CD=V.ColosseumDex
  if CD then
    if type(CD.supported)=="function" then return CD.supported(dex) and true or false end
    return true
  end
  return dex<=386
end

-- ------- transform registry
local function newRegistry() return setmetatable({},{__mode="k"}) end
local transforms=newRegistry()
-- Gen I rebuilds its battler/mon wrapper tables during a fight, so a record
-- keyed only by those tables is lost mid-battle (the actor then resolves back to
-- the real species and is retired as a "replacement"). The speciesSprite seam
-- also tells us the side, so it is ALSO recorded against the battle's live
-- player/enemy slot and stays valid for as long as the same species occupies it.
local bySlot=newRegistry()   -- battle -> {player=rec, enemy=rec}

local function slotTransform(battler,mon)
  for battle,slots in pairs(bySlot) do
    for key,rec in pairs(slots) do
      local live=type(battle)=="table" and battle[key] or nil
      if type(live)=="table" and (live==battler or (mon~=nil and (live.mon==mon or live==mon))) then
        local lm=type(live.mon)=="table" and live.mon or live
        if lookupDex(rec.defs,lm.species or lm.id,lm)==rec.ownDex then return rec end
        slots[key]=nil  -- another species now occupies the slot: transform is over
        logf("ModelIdentity: slot %s occupant changed species; transform dropped",tostring(key))
      end
    end
  end
  return nil
end

function M.transformDex(battler,mon)
  local rec=type(mon)=="table" and transforms[mon] or nil
  if not rec and type(battler)=="table" then
    local r=transforms[battler]
    -- Gen II hands out ONE wrapper per slot for the whole battle and swaps
    -- .mon inside it, so a wrapper-keyed record is only valid for its own mon.
    if r and (not battler.__cbeGen2Slot or r.mon==mon) then rec=r end
  end
  if not rec then rec=slotTransform(battler,mon) end
  return rec and rec.dex or nil,rec
end

-- Record (or clear) what `mon` currently looks like. `species` is whatever the
-- engine is drawing for it. `defs` is data.pokemon.
function M.noteTransform(defs,mon,battler,species)
  if type(mon)~="table" or species==nil then return false end
  local own=lookupDex(defs,mon.species or mon.id,mon)
  local target=lookupDex(defs,species,nil)
  if target and own and target~=own and validDex(target) then
    local rec={dex=target,species=species,mon=mon}
    transforms[mon]=rec
    if type(battler)=="table" then transforms[battler]=rec end
    logf("ModelIdentity: %s now looks like dex %s (own dex %s)",tostring(mon.species or mon.id),tostring(target),tostring(own))
    return true
  end
  if transforms[mon] then logf("ModelIdentity: %s transform cleared",tostring(mon.species or mon.id)) end
  transforms[mon]=nil
  if type(battler)=="table" then transforms[battler]=nil end
  return false
end

function M.clear(mon,battler)
  if type(mon)=="table" then transforms[mon]=nil end
  if type(battler)=="table" then transforms[battler]=nil end
end

function M.clearAll() transforms=newRegistry();bySlot=newRegistry() end

-- Record a Transform reported with its side (Gen I speciesSprite).
function M.noteSlotTransform(battle,isPlayerSide,defs,species)
  if type(battle)~="table" then return end
  local key=isPlayerSide and "player" or "enemy"
  local battler=battle[key]
  local mon=type(battler)=="table" and type(battler.mon)=="table" and battler.mon or nil
  if not mon then return end
  local own=lookupDex(defs,mon.species or mon.id,mon)
  local target=lookupDex(defs,species,nil)
  local slots=bySlot[battle]
  if target and own and target~=own and validDex(target) then
    if not slots then slots={};bySlot[battle]=slots end
    slots[key]={dex=target,species=species,ownDex=own,defs=defs}
    logf("ModelIdentity: %s side %s now looks like dex %s (own dex %s)",tostring(mon.species or mon.id),key,tostring(target),tostring(own))
  elseif slots and slots[key] then
    slots[key]=nil
    logf("ModelIdentity: %s side %s transform cleared",tostring(mon.species or mon.id),key)
  end
end

-- ------- seams
local state={hook=false,events=false,battleState=false,tries=0}

local function observeSprite(ctx)
  if type(ctx)~="table" or ctx.kind~="battle" then return end
  local mon=ctx.mon
  if type(mon)~="table" or ctx.species==nil then return end
  M.noteTransform(ctx.data and ctx.data.pokemon,mon,nil,ctx.species)
end

local function battleDefs(battle)
  local data=battle and (battle.data or (battle.game and battle.game.data))
  return data and data.pokemon
end

local function onSpeciesSprite(battle,species,isPlayerSide)
  if type(battle)~="table" then return end
  -- A grow-in is a send-out, not a Transform.
  if isPlayerSide and battle.sendingOut then return end
  if not isPlayerSide and battle.enemySendingOut then return end
  local battler=isPlayerSide and battle.player or battle.enemy
  local mon=type(battler)=="table" and battler.mon or nil
  M.noteTransform(battleDefs(battle),mon,battler,species)
  M.noteSlotTransform(battle,isPlayerSide,battleDefs(battle),species)
end

local function onResolveSwitch(battle,newMon,after)
  if type(battle)~="table" then return end
  local battler=battle.player
  if type(battler)=="table" then M.clear(battler.mon,battler) end
  if after then M.clear(newMon) end
  local slots=bySlot[battle]
  if slots then slots.player=nil end
end

local function installBattleState()
  if state.battleState then return true end
  local req=V.engineRequire or require
  local ok,B=pcall(req,"src.battle.BattleState")
  if not ok or type(B)~="table" then return false end
  if B.__cbeTransformIdentity then state.battleState=true;return true end
  if type(B.speciesSprite)=="function" then
    local inner=B.speciesSprite
    B.speciesSprite=function(self,species,isPlayerSide,...)
      pcall(onSpeciesSprite,self,species,isPlayerSide)
      return inner(self,species,isPlayerSide,...)
    end
  end
  if type(B.resolveSwitch)=="function" then
    local inner=B.resolveSwitch
    B.resolveSwitch=function(self,newMon,...)
      pcall(onResolveSwitch,self,newMon,false)
      local r1,r2,r3=inner(self,newMon,...)
      -- Whatever the send-out drew while resolving is not a Transform.
      pcall(onResolveSwitch,self,newMon,true)
      return r1,r2,r3
    end
  end
  B.__cbeTransformIdentity=true
  state.battleState=true
  return true
end

-- Idempotent. Safe to call as often as convenient; the BattleState seam is
-- retried lazily because the engine module may not be loadable this early.
function M.install()
  local mod=V.mod
  if mod and not state.hook and mod.hooks and type(mod.hooks.wrap)=="function" then
    local ok=pcall(mod.hooks.wrap,mod.hooks,"pokemon.sprite",function(next,path,ctx)
      local out=next(path,ctx)
      pcall(observeSprite,ctx)
      return out
    end)
    state.hook=ok and true or false
  end
  if mod and not state.events and mod.events and type(mod.events.on)=="function" then
    local ok1=pcall(mod.events.on,mod.events,"battle.ended",function() M.clearAll() end)
    local ok2=pcall(mod.events.on,mod.events,"battle.started",function() M.clearAll() end)
    state.events=(ok1 and ok2) and true or false
  end
  if not state.battleState and state.tries<50 then
    state.tries=state.tries+1
    installBattleState()
  end
  return state.hook,state.battleState
end

function M.status()
  return {hook=state.hook,events=state.events,battleState=state.battleState,tries=state.tries}
end

-- A species that IS identified (a real National Dex number) but that the
-- Colosseum actor catalog has no body for: Sinnoh (387-493) and Unova (494-649).
-- The disc only ships 386 models, so no amount of cache preparation will ever
-- produce one. Returns that dex number, or nil for anything else (identified and
-- modelled, or genuinely unidentifiable -- that one stays an error).
--
-- Callers use it to tell "nothing to prepare, draw the 2D sprite" apart from
-- "identity lookup failed". Before this existed both came back as `nil, nil`, so a
-- Gen 5 party/opponent was reported as a missing National Dex mapping: the model
-- cache could never finish, and the battle never got past the preparation screen.
function M.unsupported(game,battler)
  if type(battler)~="table" then return nil end
  local mon=type(battler.mon)=="table" and battler.mon or battler
  local defs=game and game.data and game.data.pokemon
  local candidates={}
  local tdex=M.transformDex(battler,mon)
  if tdex then candidates[#candidates+1]=tdex end
  candidates[#candidates+1]=lookupDex(defs,mon.species or mon.id,mon)
  for _,dex in ipairs(candidates) do
    if dex and dex%1==0 and dex>=1 and not validDex(dex) then return dex end
  end
  return nil
end

function M.resolve(game,battler,baseOnly)
  if type(battler)~="table" then return nil,"Pokemon identity unavailable" end
  if not state.battleState and state.tries<50 then M.install() end
  local mon=type(battler.mon)=="table" and battler.mon or battler
  local species=mon.species or mon.id
  local defs=game and game.data and game.data.pokemon
  -- A Transformed mon is drawn as what it copied. Unsupported targets (e.g. a
  -- Gen 4 species the actor catalog cannot model) are ignored rather than
  -- turning a valid actor into a "no dex mapping" error.
  local dex
  if baseOnly~=true then
    local tdex=M.transformDex(battler,mon)
    if tdex and validDex(tdex) then dex=tdex end
  end
  dex=dex or lookupDex(defs,species,mon)
  if not validDex(dex) then
    return nil,nil  -- Unsupported dex (e.g., Gen 4 Pokemon 387+), return nil for both dex and variant
  end
  return dex,V.ShinySupport.variant(battler)
end
return M
