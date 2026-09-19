-- Action Replay 0.1.0: FireRed-native port of GameShark Compatibility's
-- hook-based cheats. FireRed Complete Dex supplies the 1-1025 registry.
return function(mod)
  local Version=require('src.core.GameVersion')
  if Version.get() ~= 'firered' then return end

  local state={active={},selectedNat=25,level=5}
  if type(mod.save)=='table' then
    if type(mod.save.activeEffects)=='table' then state.active=mod.save.activeEffects end
    local nat=tonumber(mod.save.selectedNational)
    local level=tonumber(mod.save.spawnLevel)
    if nat and nat>=1 and nat<=1025 then state.selectedNat=math.floor(nat) end
    if level and level>=1 and level<=100 then state.level=math.floor(level) end
  end
  local function persist()
    if type(mod.save)=='table' then
      mod.save.activeEffects=state.active
      mod.save.selectedNational=state.selectedNat
      mod.save.spawnLevel=state.level
    end
  end
  local function enabled(id) return state.active[id]==true end
  local function setEnabled(id,on) state.active[id]=on==true; persist() end

  local BADGE_NAMES={'BOULDER','CASCADE','THUNDER','RAINBOW','SOUL','MARSH','VOLCANO','EARTH'}
  local function runtimeSession()
    local Runtime=package.loaded['src.core.game3.runtime'] or require('src.core.game3.runtime')
    return Runtime.getSession and Runtime.getSession(),Runtime
  end
  local function grantRareCandies()
    local session=runtimeSession()
    if not (session and session.bag) then return end
    require('src.core.game3.bag').set(session.bag,68,999) -- ITEM_RARE_CANDY
  end
  local function grantBadges()
    local session=runtimeSession()
    local Flags=require('src.core.game3.scripting.flags')
    local Space=package.loaded['src.core.game3.scripting.space']
    if not Space then
      local ok,loaded=pcall(require,'src.core.game3.scripting.space')
      if ok then Space=loaded end
    end
    local store=Space and ((Space.getStore and Space.getStore()) or Space.store)
    if store then Flags.setBadgesMask(store,255) end
    if session then
      session.badges=type(session.badges)=='table' and session.badges or {}
      session.flags=type(session.flags)=='table' and session.flags or {}
      for i,name in ipairs(BADGE_NAMES) do
        session.badges[i]=true; session.badges[name]=true
        session.badges[name..'_BADGE']=true
        session.flags[0x81F+i]=true
      end
      local save=session.save
      if save then
        save.player=save.player or {}; save.player.badges=save.player.badges or {}
        for i,name in ipairs(BADGE_NAMES) do
          save.player.badges[i]=true; save.player.badges[name]=true
        end
      end
    end
  end
  local function maintain()
    if enabled('rare_candy') then grantRareCandies() end
    if enabled('badges') then grantBadges() end
  end

  mod.hooks:wrap('input.step',function(next_,game,dt)
    maintain()
    local result=next_(game,dt)
    maintain()
    return result
  end,500)
  mod.hooks:wrap('movement.collision',function(next_,allowed,ctx)
    local result=next_(allowed,ctx)
    if enabled('walk') and ctx and ctx.reason~='bounds' then
      ctx.reason='action_replay'; return true
    end
    return result
  end,500)
  mod.hooks:wrap('encounter.roll',function(next_,def,ctx)
    if enabled('no_encounters') then return nil end
    return next_(def,ctx)
  end,500)
  mod.hooks:wrap('catch.rate',function(next_,ball,mon,def,opts)
    if enabled('always_catch') then return true,4 end
    return next_(ball,mon,def,opts)
  end,500)
  mod.hooks:wrap('battle.damage',function(next_,ctx)
    local damage,info=next_(ctx)
    if enabled('enemy_hp') and ctx and ctx.user and ctx.target
      and ctx.user.side=='player' and ctx.target.side=='enemy' then
      local hp=tonumber(ctx.target.hp) or tonumber(ctx.target.mon and ctx.target.mon.hp) or 1
      damage=math.max(1,hp)
    end
    return damage,info
  end,500)

  -- FireRed's owned player controller calls Collision.canEnter directly, so
  -- wrap that native path as well as the public compatibility hook above.
  local Collision=require('src.core.game3.collision')
  if not Collision.__actionReplayWalk then
    Collision.__actionReplayWalk=true
    local originalCanEnter=Collision.canEnter
    Collision.canEnter=function(game,tx,ty,opts)
      local ok,reason=originalCanEnter(game,tx,ty,opts)
      if enabled('walk') and reason~='bounds' then return true,nil end
      return ok,reason
    end
  end

  -- Fixed-damage effects can call Hit.dealDamage without passing through the
  -- regular battle.damage calculation hook. Cover that native path too.
  local Hit=require('src.core.game3.battle.effects.hit')
  if not Hit.__actionReplayOhko then
    Hit.__actionReplayOhko=true
    local originalDealDamage=Hit.dealDamage
    Hit.dealDamage=function(M,damage,info)
      if enabled('enemy_hp') and M and M.user and M.target
        and M.user.side=='player' and M.target.side=='enemy' then
        local adapter=M.adapter
        local hp=adapter and adapter.hp and adapter:hp(M.target)
          or M.target.hp or (M.target.mon and M.target.mon.hp) or 1
        damage=math.max(1,tonumber(hp) or 1)
      end
      return originalDealDamage(M,damage,info)
    end
  end

  -- Complete Dex v1.1.0 filters every wild BattleBridge call. For an explicit
  -- Action Replay spawn, enter through the trainer-shaped bridge path, then
  -- restore wild identity at Battle.start after Complete Dex has finished its
  -- encounter filtering. This retains normal party writeback and catch logic.
  local Battle=require('src.core.game3.battle')
  if not Battle.__actionReplaySpawn then
    Battle.__actionReplaySpawn=true
    local originalBattleStart=Battle.start
    Battle.start=function(opts)
      if opts and type(opts.foe)=='table' and opts.foe.__actionReplayWild then
        opts.foe.__actionReplayWild=nil
        opts.wild=true
        opts.double=nil
      end
      return originalBattleStart(opts)
    end
  end

  local Menu={open=false,mode='main',cursor=1,scroll=0,cursors={main=1,spawn=1,species=1}}
  local Stack=require('src.ui.game3.stack')
  local Window=require('src.ui.game3.window')
  local Chrome=require('src.ui.game3.chrome')
  local FrlgFont=require('src.ui.game3.frlg_font')
  local VISIBLE=7

  local MAIN={
    {label='WALK THROUGH WALLS',effect='walk'},
    {label='NO WILD BATTLES',effect='no_encounters'},
    {label='100% CATCH RATE',effect='always_catch'},
    {label='INFINITE RARE CANDY',effect='rare_candy'},
    {label='ALL BADGES',effect='badges'},
    {label='ONE-HIT KO',effect='enemy_hp'},
    {label='SPAWN POKéMON >',kind='spawn'},
  }
  local function pokemon()
    return require('src.core.game3.pokemon')
  end
  local function selectedName()
    local P=pokemon(); local slot=P.speciesFromNational(state.selectedNat)
    return slot and P.name(slot) or ('POKéMON '..state.selectedNat)
  end
  local function rowCount()
    if Menu.mode=='main' then return #MAIN end
    if Menu.mode=='spawn' then return 4 end
    return 1025
  end
  local function clamp()
    local total=rowCount()
    if Menu.cursor<1 then Menu.cursor=1 elseif Menu.cursor>total then Menu.cursor=total end
    if Menu.cursor<=Menu.scroll then Menu.scroll=Menu.cursor-1 end
    if Menu.cursor>Menu.scroll+VISIBLE then Menu.scroll=Menu.cursor-VISIBLE end
    Menu.scroll=math.max(0,math.min(Menu.scroll,math.max(0,total-VISIBLE)))
    Menu.cursors[Menu.mode]=Menu.cursor
  end
  local function switchMode(mode)
    Menu.cursors[Menu.mode]=Menu.cursor
    Menu.mode=mode; Menu.cursor=Menu.cursors[mode] or 1; Menu.scroll=0; clamp()
  end
  function Menu.show(game,session)
    Menu.open=true; Menu.game=game; Menu.session=session; Menu.mode='main'
    Menu.cursor=Menu.cursors.main or 1; Menu.scroll=0; clamp()
    Stack.push('action_replay',Menu,{hideBelow=true})
  end
  function Menu.close()
    Menu.open=false; Stack.pop('action_replay')
  end
  local function spawnRows()
    return {
      {label='CHOOSE POKéMON',value=string.format('#%04d',state.selectedNat),kind='species'},
      {label='LEVEL',value=tostring(state.level),kind='level'},
      {label='BATTLE NOW',value='>',kind='battle'},
      {label='BACK',kind='back'},
    }
  end
  local function startSpawn()
    local P=pokemon(); local slot=P.speciesFromNational(state.selectedNat)
    if not (slot and P.keyName(slot)) then return false,'species unavailable' end
    local game=Menu.game
    Menu.close()
    local StartMenu=require('src.ui.game3.start_menu')
    if StartMenu.isOpen() then StartMenu.close() end
    local Bridge=require('src.core.game3.battle_bridge')
    return Bridge.start(mod,game,{species=slot,speciesId=slot,level=state.level,
      __actionReplayWild=true},{wild=false,song=298})
  end
  local function activate()
    if Menu.mode=='main' then
      local row=MAIN[Menu.cursor]
      if row.kind=='spawn' then switchMode('spawn')
      else
        setEnabled(row.effect,not enabled(row.effect))
        if enabled(row.effect) then
          if row.effect=='rare_candy' then grantRareCandies() end
          if row.effect=='badges' then grantBadges() end
        end
      end
    elseif Menu.mode=='spawn' then
      local row=spawnRows()[Menu.cursor]
      if row.kind=='species' then switchMode('species')
      elseif row.kind=='level' then state.level=state.level%100+1; persist()
      elseif row.kind=='battle' then
        local ok=startSpawn()
        if not ok then Menu.show(Menu.game,Menu.session); switchMode('spawn') end
      elseif row.kind=='back' then switchMode('main') end
    else
      state.selectedNat=Menu.cursor; persist(); switchMode('spawn')
    end
  end
  local function back()
    if Menu.mode=='species' then switchMode('spawn')
    elseif Menu.mode=='spawn' then switchMode('main')
    else Menu.close() end
  end
  function Menu.handleInput(input)
    if input:wasPressed('up') then Menu.cursor=Menu.cursor-1
    elseif input:wasPressed('down') then Menu.cursor=Menu.cursor+1
    elseif Menu.mode=='species' and input:wasPressed('left') then Menu.cursor=Menu.cursor-10
    elseif Menu.mode=='species' and input:wasPressed('right') then Menu.cursor=Menu.cursor+10
    elseif Menu.mode=='species' and input:wasPressed('l') then Menu.cursor=Menu.cursor-50
    elseif Menu.mode=='species' and input:wasPressed('r') then Menu.cursor=Menu.cursor+50
    elseif Menu.mode=='spawn' and Menu.cursor==2 and input:wasPressed('left') then
      state.level=(state.level+98)%100+1; persist()
    elseif Menu.mode=='spawn' and Menu.cursor==2 and input:wasPressed('right') then
      state.level=state.level%100+1; persist()
    elseif input:wasPressed('a') then activate()
    elseif input:wasPressed('b') or input:wasPressed('start') then back() end
    clamp()
  end
  local function title()
    if Menu.mode=='species' then return 'CHOOSE POKéMON' end
    if Menu.mode=='spawn' then return 'SPAWN POKéMON' end
    return 'ACTION REPLAY'
  end
  local function displayRow(index)
    if Menu.mode=='main' then
      local row=MAIN[index]
      return row.label,row.effect and (enabled(row.effect) and 'ON' or 'OFF') or ''
    elseif Menu.mode=='spawn' then
      local row=spawnRows()[index]
      if row.kind=='species' then
        return string.format('#%04d %s',state.selectedNat,selectedName()),'>'
      end
      return row.label,row.value or ''
    end
    local P=pokemon(); local slot=P.speciesFromNational(index)
    return string.format('#%04d  %s',index,slot and P.name(slot) or 'UNAVAILABLE'),''
  end
  function Menu.draw()
    if not Menu.open then return end
    love.graphics.setColor(0,0,0,1); love.graphics.rectangle('fill',0,0,240,160)
    love.graphics.setColor(0,123/255,197/255,1); love.graphics.rectangle('fill',0,0,240,16)
    love.graphics.setColor(1,1,1,1)
    FrlgFont.draw('{DPAD_UPDOWN}PICK  {A_BUTTON}OK  {B_BUTTON}BACK',8,1,{small=true,colors=FrlgFont.COLOR.WHITE})
    Chrome.fixedStdFrame(2,3,26,2)
    Window.printPx(title(),24,25,{colors=FrlgFont.COLOR.NORMAL})
    Window.userFrame(Window.template(2,7,26,12),0)
    clamp()
    local total=rowCount()
    for slot=1,VISIBLE do
      local index=Menu.scroll+slot
      if index<=total then
        local y=58+(slot-1)*13
        local label,value=displayRow(index)
        if index==Menu.cursor then Window.cursorPx(17,y) end
        Window.printPx(label,25,y,{colors=FrlgFont.COLOR.NORMAL,maxWidth=154})
        if value~='' then Window.printPx(value,184,y,{colors=FrlgFont.COLOR.NORMAL,maxWidth=40}) end
      end
    end
    if Menu.scroll>0 then FrlgFont.drawGlyph(FrlgFont.CHAR_UP_ARROW,216,56,{colors=FrlgFont.COLOR.RED}) end
    if Menu.scroll+VISIBLE<total then FrlgFont.drawGlyph(FrlgFont.CHAR_DOWN_ARROW,216,139,{colors=FrlgFont.COLOR.RED}) end
  end

  mod.hooks:wrap('ui.start_menu.items',function(next_,game,items)
    local out=next_(game,items)
    if type(out)~='table' then return out end
    for _,row in ipairs(out) do if row.id=='action_replay' then return out end end
    local insertAt=#out+1
    for i,row in ipairs(out) do if row.id=='save' then insertAt=i; break end end
    table.insert(out,insertAt,{id='action_replay',label='CHEATS',onSelect=function(g,session)
      Menu.show(g or game,session)
    end})
    return out
  end,500)

  mod.exports.enabled=enabled
  mod.exports.setEnabled=function(id,on)
    local known={walk=true,no_encounters=true,always_catch=true,rare_candy=true,badges=true,enemy_hp=true}
    if not known[id] then return false,'unknown cheat' end
    setEnabled(id,on); maintain(); return true
  end
  mod.exports.speciesRows=function()
    local P=pokemon(); local rows={}
    for nat=1,1025 do
      local slot=P.speciesFromNational(nat)
      rows[#rows+1]={national=nat,species=slot,name=slot and P.name(slot) or nil}
    end
    return rows
  end
  mod.exports.spawn=function(nat,level,game)
    nat=tonumber(nat); level=tonumber(level)
    if not nat or nat<1 or nat>1025 then return false,'National number must be 1-1025' end
    if not level or level<1 or level>100 then return false,'level must be 1-100' end
    local _,Runtime=runtimeSession()
    state.selectedNat=math.floor(nat); state.level=math.floor(level)
    Menu.game=game or (Runtime and Runtime._game)
    persist(); return startSpawn()
  end
  mod.log:info('Action Replay ready: CHEATS menu and 1025-species spawner installed')
end
