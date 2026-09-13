-- Gen3-specific battle settings module
-- This handles the different menu system in Gen3 games (Ruby/Sapphire/Emerald/FireRed/LeafGreen)

local S={}
local installed=false
local modRef,Trainer,Music,ArenaCatalog,BattleMenuUI,CacheManager,TrainerRoster,Compat,AudioFidelity

local function prefs(game)
  if not (game and game.save) then
    return {
      music="normal",arena="auto",arenasEnabled=true,cameraEnabled=true,pokemonModelsEnabled=true,
      playerModel="red",enemyTrainerModel="auto",rivalModel="leaf",
      doubleBattlesEnabled=true,abilitiesEnabled=true,freeLookEnabled=true,
      autoProgressEnabled=true,bossIntroEnabled=false,battleSoundsEnabled=true,
    }
  end
  local p=game.save.colosseumBattle
  if type(p)~="table" then p={}; game.save.colosseumBattle=p end
  if p.arenasEnabled==nil then p.arenasEnabled=true end
  p.arenasEnabled=p.arenasEnabled and true or false
  if p.cameraEnabled==nil then p.cameraEnabled=true end
  p.cameraEnabled=p.cameraEnabled and true or false
  if p.pokemonModelsEnabled==nil then p.pokemonModelsEnabled=true end
  p.pokemonModelsEnabled=p.pokemonModelsEnabled and true or false
  if p.battleSoundsEnabled==nil then p.battleSoundsEnabled=true end
  p.battleSoundsEnabled=p.battleSoundsEnabled==true
  if p.bossIntroEnabled==nil then p.bossIntroEnabled=false end
  p.bossIntroEnabled=p.bossIntroEnabled==true
  if p.doubleBattlesEnabled==nil then p.doubleBattlesEnabled=true end
  p.doubleBattlesEnabled=p.doubleBattlesEnabled==true
  if p.abilitiesEnabled==nil then p.abilitiesEnabled=true end
  p.abilitiesEnabled=p.abilitiesEnabled==true
  if p.freeLookEnabled==nil then p.freeLookEnabled=true end
  if p.autoProgressEnabled==nil then p.autoProgressEnabled=true end
  local legacy=p.sprites
  if p.playerModel==nil then
    p.playerModel=(p.playerTrainerModel==false or legacy=="off") and "off" or "red"
  end
  if p.enemyTrainerModel==nil then
    p.enemyTrainerModel=(p.enemyTrainerModels==false or legacy=="off" or legacy=="player") and "off" or "auto"
  end
  if p.rivalModel==nil then p.rivalModel="leaf" end
  if TrainerRoster and TrainerRoster.normalizeChoice then
    p.playerModel=TrainerRoster.normalizeChoice(p.playerModel,"player")
    p.enemyTrainerModel=TrainerRoster.normalizeChoice(p.enemyTrainerModel,"enemy")
    p.rivalModel=TrainerRoster.normalizeChoice(p.rivalModel,"rival")
  else
    p.playerModel=tostring(p.playerModel or "red"):lower()
    p.enemyTrainerModel=tostring(p.enemyTrainerModel or "auto"):lower()
    p.rivalModel=tostring(p.rivalModel or "leaf"):lower()
  end
  p.playerTrainerModel=p.playerModel~="off"
  p.enemyTrainerModels=p.enemyTrainerModel~="off"
  local validMusic={random=true,normal=true,first=true,cipher_peon=true,miror_b=true,cipher_admin=true,mirakle_b=true,semifinal=true,final=true,link1=true,link2=true,link3=true,original=true}
  if p.music=="colosseum" or p.music=="wild" or p.music=="trainer" or p.music=="gym" then p.music="normal" end
  if not validMusic[p.music] then p.music="normal" end
  local validArena={auto=true,random=true,water=true,orre_colosseum=true,relic_chamber=true,relic_cave=true,outskirts=true,pyrite_colosseum=true,deep_colosseum=true,realgam_colosseum=true,outdoor_wild=true,mt_battle_summit=true,cipher_lab_underground=true}
  if not validArena[p.arena] then p.arena="auto" end
  return p
end

local function openBattleMenu(game)
  if mod.log then mod.log:info("openBattleMenu called for Gen3") end
  
  local ok,Menu=pcall(require,"src.ui.Menu")
  if not ok or not Menu then 
    if mod.log then mod.log:warn("Failed to load src.ui.Menu for Gen3 battle settings") end
    return 
  end
  
  if mod.log then mod.log:info("Menu loaded successfully") end
  
  local p=prefs(game)
  if ArenaCatalog and ArenaCatalog.sync then ArenaCatalog.sync(game) end
  if ArenaCatalog and ArenaCatalog.selected then p.arena=ArenaCatalog.selected(game) end
  
  -- Simple settings menu for Gen3
  local function refresh()
    if mod.log then mod.log:info("Refreshing Gen3 battle settings menu") end
  end
  
  local arenaToggle={keepOpen=true,label="COLOSSEUM ARENAS  "..(p.arenasEnabled and "ON" or "OFF")}
  local cameraToggle={keepOpen=true,label="COLOSSEUM CAMERA  "..(p.cameraEnabled and "ON" or "OFF")}
  local modelsToggle={keepOpen=true,label="COLOSSEUM MODELS  "..(p.pokemonModelsEnabled and "ON" or "OFF")}
  local soundsToggle={keepOpen=true,label="BATTLE SOUNDS  "..(p.battleSoundsEnabled and "COLOSSEUM" or "ORIGINAL")}
  
  arenaToggle.onSelect=function()
    p.arenasEnabled=not p.arenasEnabled
    if ArenaCatalog and ArenaCatalog.setEnabled then ArenaCatalog.setEnabled(game,p.arenasEnabled) end
    refresh()
  end
  
  cameraToggle.onSelect=function()
    p.cameraEnabled=not p.cameraEnabled
    refresh()
  end
  
  modelsToggle.onSelect=function()
    p.pokemonModelsEnabled=not p.pokemonModelsEnabled
    refresh()
  end
  
  soundsToggle.onSelect=function()
    p.battleSoundsEnabled=not p.battleSoundsEnabled
    refresh()
  end
  
  local mainRows={arenaToggle,cameraToggle,modelsToggle,soundsToggle,{label="BACK",onSelect=function()
    if mod.log then mod.log:info("BACK selected in Gen3 battle settings") end
    if game.stack and type(game.stack.pop)=="function" then
      game.stack:pop()
    end
  end}}
  
  if mod.log then mod.log:info("Creating Gen3 battle settings menu with " .. #mainRows .. " rows") end
  
  local ok2, menu = pcall(function()
    return Menu.new(game,mainRows,{tx=1,ty=2,tw=24,maxVisible=10,onCancel=function()
      if mod.log then mod.log:info("CANCEL in Gen3 battle settings") end
      if game.stack and type(game.stack.pop)=="function" then
        game.stack:pop()
      end
    end})
  end)
  
  if not ok2 then
    if mod.log then mod.log:warn("Failed to create Gen3 battle settings menu: " .. tostring(menu)) end
    return
  end
  
  if mod.log then mod.log:info("Gen3 battle settings menu created successfully") end
  
  menu.screenId="CbeBattleSettingsGen3"
  
  if BattleMenuUI and BattleMenuUI.mark then
    BattleMenuUI.mark(menu,"COLOSSEUM BATTLE",mainRows,10,"ENVIRONMENT / CAMERA / POKEMON / AUDIO")
  end
  
  local ok3, pushErr = pcall(function()
    game.stack:push(menu)
  end)
  
  if not ok3 then
    if mod.log then mod.log:warn("Failed to push Gen3 battle settings menu: " .. tostring(pushErr)) end
  else
    if mod.log then mod.log:info("Gen3 battle settings menu pushed successfully") end
  end
end

function S.install(mod,trainer,music,arenaCatalog,battleMenuUI,cacheManager,trainerRoster,compat,audioFidelity)
  if installed then 
    if mod.log then mod.log:info("Gen3 battle settings already installed") end
    return true 
  end
  
  if mod.log then mod.log:info("Gen3 battle settings install function called") end
  
  modRef,Trainer,Music,ArenaCatalog,BattleMenuUI,CacheManager,TrainerRoster,Compat,AudioFidelity=mod,trainer,music,arenaCatalog,battleMenuUI,cacheManager,trainerRoster,compat,audioFidelity
  if BattleMenuUI and BattleMenuUI.install then BattleMenuUI.install() end
  if not (mod and mod.hooks and type(mod.hooks.wrap)=="function") then 
    if mod.log then mod.log:warn("Gen3 battle settings install failed: mod.hooks.wrap not available") end
    return false 
  end
  
  if mod.log then mod.log:info("Installing Gen3 battle settings") end
  
  -- Store the battle menu opener globally for keybind access
  _G.DRAMATIC_GEN3_BATTLE_MENU_OPENER = function(g)
    if mod.log then mod.log:info("Global Gen3 battle menu opener called") end
    openBattleMenu(g or (modRef and modRef.game))
  end
  
  -- Try to register a console command for Gen3
  local okCmd, cmdErr = pcall(function()
    if mod and mod.commands and mod.commands.register then
      mod.commands.register("battle_settings", function()
        if mod.log then mod.log:info("Battle settings console command called") end
        openBattleMenu(modRef and modRef.game)
      end, "Open Colosseum battle settings")
      if mod.log then mod.log:info("Gen3 battle settings console command registered") end
    end
  end)
  
  if not okCmd then
    if mod.log then mod.log:warn("Failed to register console command: " .. tostring(cmdErr)) end
  end
  
  -- For Gen3, try hooking into menu execution instead of callbacks
  local success = false
  
  -- Try hooking the menu selection directly
  local ok, err = pcall(function()
    mod.hooks:wrap("ui.start_menu.items",function(next,game,items)
      local out=next(game,items)
      if type(out)~="table" then out=items end
      
      if mod.log then mod.log:info("Gen3 battle settings hook called, items count: " .. #out) end
      
      for _,entry in ipairs(out) do
        if entry.__colosseumBattleEntryGen3 or tostring(entry.label or ""):upper()=="BATTLE" then 
          if mod.log then mod.log:info("BATTLE entry already exists") end
          return out 
        end
      end
      
      local at=#out+1
      for i,entry in ipairs(out) do
        if tostring(entry.label or ""):upper()=="OPTION" then at=i;break end
      end
      
      -- Store the battle menu opener in a global that can be called from anywhere
      if not _G.DRAMATIC_GEN3_BATTLE_MENU then
        _G.DRAMATIC_GEN3_BATTLE_MENU = function(g)
          if mod.log then mod.log:info("Global Gen3 battle menu opener called") end
          openBattleMenu(g or game)
        end
      end
      
      table.insert(out,at,{
        label="BATTLE",
        __colosseumBattleEntryGen3=true,
        -- Try all possible callback names
        onSelect=function()
          if mod.log then mod.log:info("Gen3 BATTLE option selected via onSelect") end
          local ok, err = pcall(openBattleMenu, game)
          if not ok then mod.log:warn("Gen3 BATTLE menu open failed: " .. tostring(err)) end
        end,
        action=function()
          if mod.log then mod.log:info("Gen3 BATTLE option selected via action") end
          local ok, err = pcall(openBattleMenu, game)
          if not ok then mod.log:warn("Gen3 BATTLE menu open failed: " .. tostring(err)) end
        end,
        handler=function()
          if mod.log then mod.log:info("Gen3 BATTLE option selected via handler") end
          local ok, err = pcall(openBattleMenu, game)
          if not ok then mod.log:warn("Gen3 BATTLE menu open failed: " .. tostring(err)) end
        end,
        activate=function()
          if mod.log then mod.log:info("Gen3 BATTLE option selected via activate") end
          local ok, err = pcall(openBattleMenu, game)
          if not ok then mod.log:warn("Gen3 BATTLE menu open failed: " .. tostring(err)) end
        end,
        -- Try storing a direct function reference
        _battleMenuOpener = openBattleMenu
      })
      
      if mod.log then mod.log:info("BATTLE entry inserted at position " .. at) end
      return out
    end,650)
  end)
  
  if ok then
    success = true
    if mod.log then mod.log:info("Gen3 battle settings ui.start_menu.items hook installed successfully") end
  else
    if mod.log then mod.log:warn("Gen3 battle settings ui.start_menu.items hook failed: " .. tostring(err)) end
  end
  
  -- Try hooking into menu choice execution as a fallback
  if not success then
    local ok2, err2 = pcall(function()
      mod.hooks:wrap("ui.menu.choice",function(next,game,choice,index)
        if mod.log then mod.log:info("Gen3 menu choice hook called: " .. tostring(choice) .. " at index " .. tostring(index)) end
        
        local choiceLabel = tostring(choice or "")
        if choiceLabel:upper()=="BATTLE" then
          if mod.log then mod.log:info("BATTLE choice detected, opening menu") end
          local ok3, err3 = pcall(openBattleMenu, game)
          if not ok3 then mod.log:warn("Gen3 BATTLE menu open failed: " .. tostring(err3)) end
          return -- Don't call next, we handled it
        end
        
        return next(game,choice,index)
      end,650)
    end)
    
    if ok2 then
      success = true
      if mod.log then mod.log:info("Gen3 battle settings ui.menu.choice hook installed successfully") end
    else
      if mod.log then mod.log:warn("Gen3 battle settings ui.menu.choice hook failed: " .. tostring(err2)) end
    end
  end
  
  -- Try hooking into pause menu execution as another fallback
  if not success then
    local ok3, err3 = pcall(function()
      mod.hooks:wrap("ui.pause_menu.items",function(next,game,items)
        local out=next(game,items)
        if type(out)~="table" then out=items end
        
        if mod.log then mod.log:info("Gen3 pause menu hook called, items count: " .. #out) end
        
        for _,entry in ipairs(out) do
          if entry.__colosseumBattleEntryGen3 or tostring(entry.label or ""):upper()=="BATTLE" then 
            if mod.log then mod.log:info("BATTLE entry already exists in pause menu") end
            return out 
          end
        end
        
        local at=#out+1
        for i,entry in ipairs(out) do
          if tostring(entry.label or ""):upper()=="OPTION" then at=i;break end
        end
        table.insert(out,at,{
          label="BATTLE",
          __colosseumBattleEntryGen3=true,
          onSelect=function()
            if mod.log then mod.log:info("Gen3 BATTLE option selected from pause menu") end
            local ok4, err4 = pcall(openBattleMenu, game)
            if not ok4 then mod.log:warn("Gen3 BATTLE menu open failed: " .. tostring(err4)) end
          end
        })
        return out
      end,650)
    end)
    
    if ok3 then
      success = true
      if mod.log then mod.log:info("Gen3 battle settings ui.pause_menu.items hook installed successfully") end
    else
      if mod.log then mod.log:warn("Gen3 battle settings ui.pause_menu.items hook failed: " .. tostring(err3)) end
    end
  end
  
  installed = success
  return success
end

function S.prefs(game) return prefs(game) end
function S.cameraEnabled(game) return prefs(game or (modRef and modRef.game)).cameraEnabled~=false end
function S.pokemonModelsEnabled(game) return prefs(game or (modRef and modRef.game)).pokemonModelsEnabled~=false end
function S.abilitiesEnabled(game) return prefs(game or (modRef and modRef.game)).abilitiesEnabled==true end
function S.setCameraEnabled(game,value)
  local p=prefs(game or (modRef and modRef.game)); p.cameraEnabled=value~=false; return p.cameraEnabled
end
function S.status(game)
  local p=prefs(game or (modRef and modRef.game))
  return {
    installed=installed,arenasEnabled=p.arenasEnabled,cameraEnabled=p.cameraEnabled,pokemonModelsEnabled=p.pokemonModelsEnabled,
    battleSoundsEnabled=p.battleSoundsEnabled,freeLookEnabled=p.freeLookEnabled,autoProgressEnabled=p.autoProgressEnabled,bossIntroEnabled=p.bossIntroEnabled,doubleBattlesEnabled=p.doubleBattlesEnabled,
    abilitiesEnabled=p.abilitiesEnabled,
    music=p.music,musicLabel=Music and Music.themeLabel and Music.themeLabel(game,p.music),
    arena=p.arena,playerModel=p.playerModel,enemyTrainerModel=p.enemyTrainerModel,rivalModel=p.rivalModel,
    playerTrainerModel=p.playerTrainerModel,enemyTrainerModels=p.enemyTrainerModels,
    cache=CacheManager and CacheManager.status and CacheManager.status() or nil,
    audioFidelity=AudioFidelity and AudioFidelity.status(modRef) or nil,
  }
end
return S