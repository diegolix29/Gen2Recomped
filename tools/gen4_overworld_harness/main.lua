-- tools/gen4_overworld_harness/main.lua
--
-- A HEADLESS SINNOH OVERWORLD, RENDERED TO A PNG AND TRACED PER TICK.
--
-- WHY THIS EXISTS.  The terrain harness stands in Twinleaf and draws the
-- GROUND; the battle harness draws a BATTLE.  Neither stands up an
-- `OverworldState`, so nothing about the live cast -- who is on the map, who
-- is drawn, who follows the player -- could be looked at.  Items 9 and 10 of
-- the play-test list ("Barry is invisible while following", "Rowan is
-- translucent") are both about exactly that, and both were unanswerable.
--
--   POKEPORT_DATA_DIR=<platinum cache>/data/generated \
--     MAP=T01 X=15 Y=25 WALK=down STEPS=8 TAG=barry \
--     love tools/gen4_overworld_harness
--
-- Env: MAP, X, Y, FACING, WALK (a direction to hold), STEPS, TICKS, TAG,
--      W/H, VERSION, FOLLOW (a localId to make into a follower), TRACE,
--      THEN/THEN_X/THEN_Y (cross to another map mid-run), WARPAT=x,y,
--      OBJRELOAD=index,x,y, PARTY/PARTYLEVEL, HURT, PRESS (A every n
--      ticks), GIVE/GIVE_G4 (items), DEX_SEEN (species, or "all"), HOF
--      (hall-of-fame rosters), SCREEN (a UI screen to push over the
--      world, by registry name OR module name) and POCKET.
--
-- WHAT IT DELIBERATELY DOES NOT DO.  No launcher, no save on disk, no window.
-- It pushes the real `OverworldController` onto a real stack, because the
-- whole point is to exercise the engine's own path rather than a
-- reimplementation of it -- the battle harness learned that lesson three
-- times (`enter`, `Font.load`, `Game.input`) and each gap was first reported
-- as an engine fault.
local W = tonumber(os.getenv("W") or "512")
local H = tonumber(os.getenv("H") or "384")
local TAG = os.getenv("TAG") or "ow"

local function dirHeld(want)
  return function(_, k) return want and k == want end
end

function love.load()
  local ok, err = xpcall(function()
    local GameVersion = require("src.core.GameVersion")
    GameVersion.set(os.getenv("VERSION") or "platinum")

    -- POKEPORT_ASSET_ROOT: the launcher mounts the cache's `assets/`; with no
    -- launcher here, read pictures straight from that folder (as the battle
    -- and contest harnesses do), or every screen pushed over the world --
    -- the shop's counter art included -- comes up placeholder.
    local assetRoot = os.getenv("POKEPORT_ASSET_ROOT")
    if assetRoot then
      local Assets = require("src.render.Assets")
      local realImage, held = Assets.image, {}
      Assets.image = function(path, ...)
        if type(path) == "string" and not held[path] then
          local f = io.open(assetRoot .. "/" .. path, "rb")
          if f then
            local bytes = f:read("*a"); f:close()
            local okI, img = pcall(love.graphics.newImage, love.filesystem.newFileData(bytes, path))
            if okI then img:setFilter("nearest", "nearest"); held[path] = img end
          end
        end
        return held[path] or realImage(path, ...)
      end
    end

    local Data = require("src.core.Data")
    Data:load()
    if not Data.isGen4Cache then
      print("WARNING: POKEPORT_DATA_DIR is not a Gen 4 cache")
    end

    local SaveData = require("src.core.SaveData")
    local Game = require("src.core.Game")
    Game.data = Data
    -- Decode BW boot art in memory so screenshots exercise the importer
    -- without changing the user's installed cartridge cache.
    if os.getenv('BW_UI_ROM') then
      local X=assert(require('src.import.RomExtractorGen5').new(os.getenv('BW_UI_ROM'),os.getenv('VERSION') or 'black'))
      local pictures={}
      X.saveImage=function(_,rel,pic,extra)
        local path='__bw_ui/'..rel..'.png'
        local pixels=require('src.import.ImageWriter').fromRGBA8(pic.width,pic.height,pic.rgba)
        if os.getenv('DUMP_BOOT_ART') then pixels:encode('png',rel:gsub('/','_')..'.png') end
        pictures[path]=love.graphics.newImage(pixels)
        local rec={path=path,width=pic.width,height=pic.height}
        for k,v in pairs(extra or {}) do rec[k]=v end
        return rec
      end
      Data.gen5_boot_art=require('src.import.Gen5BootArt').build(X)
      Data.gen5_main_menu_art=require('src.import.Gen5MainMenuArt').build(X)
      Data.gen5_juniper_art=require('src.import.Gen5JuniperArt').build(X)
      -- the gift box's starter app (overlay 223, /a/2/0/5)
      Data.gen5_starter_art=require('src.import.Gen5StarterArt').build(X);X:close()
      local Assets=require('src.render.Assets');local original=Assets.image
      Assets.image=function(path,...) return pictures[path] or original(path,...) end
    end
    -- Exercise freshly decoded HGSS UI assets without overwriting an install.
    if os.getenv('HGSS_UI_ROM') then
      local rom=assert(require('src.import.NdsRom').open(os.getenv('HGSS_UI_ROM')))
      local aliases=require('src.import.Gen4HgssScriptAliases')
      for _,block in pairs((Data.map_scripts or {}).scripts or {}) do
        for _,ins in ipairs(block.instructions or {}) do aliases.apply(ins) end
      end
      local Mart=require('src.import.Gen4Mart')
      local arm9=rom:arm9();local at=Mart.find(arm9)
      Data.constants.martCommon=assert(Mart.parse(arm9,at))
      local pictures={}
      for _,entry in ipairs({{'src.import.Gen4HgssStarterArt','gen4_hgss_starter_art'},
        {'src.import.Gen4HgssOakArt','gen4_hgss_oak_art'},
        {'src.import.Gen4HgssTitleArt','gen4_hgss_title_art'},
        {'src.import.Gen4HgssBootArt','gen4_hgss_boot_art'},
        {'src.import.Gen4HgssMainMenu','gen4_main_menu_art'},
        {'src.import.Gen4HgssPokegearArt','gen4_hgss_pokegear_art'},
        {'src.import.Gen4HgssMenuArt','gen4_hgss_menu_art'}}) do
        local index={}
        local images,sequences,metadata=require(entry[1]).images(rom)
        for key,value in pairs(metadata or {}) do index[key]=value end
        for key,pic in pairs(images) do
          local path='__hgss_ui/'..entry[2]..'/'..key..'.png'
          pictures[path]=love.graphics.newImage(require('src.import.ImageWriter').fromRGBA8(pic.width,pic.height,pic.rgba))
          index[key]={path=path,width=pic.width,height=pic.height,originX=pic.originX,originY=pic.originY}
        end
        if sequences then
          index.sequences=sequences
          if entry[2]=='gen4_hgss_oak_art' then
            index.text={}
            local X=assert(require('src.import.RomExtractorGen4').new(os.getenv('HGSS_UI_ROM'),os.getenv('VERSION') or 'heartgold'))
            for i=1,48 do index.text[i]=X:string(219,i) end
            X:close()
          end
        end
        Data[entry[2]]=index
      end
      -- HGSS_DEX_ART=1: the Pokedex's art and search data fresh from the ROM
      -- (Gen4HgssDexArt: images + listAnims, orders, search), as a re-import
      -- would write them
      if os.getenv('HGSS_DEX_ART') then
        local A=require('src.import.Gen4HgssDexArt')
        local images,anims,meta=A.images(rom)
        local index={listAnims=anims,orders=A.orders(rom),search=A.searchData(rom)}
        for key,value in pairs(meta or {}) do index[key]=value end
        for key,pic in pairs(images or {}) do
          local path='__hgss_ui/gen4_hgss_dex_art/'..key..'.png'
          pictures[path]=love.graphics.newImage(require('src.import.ImageWriter').fromRGBA8(pic.width,pic.height,pic.rgba))
          index[key]={path=path,width=pic.width,height=pic.height,originX=pic.originX,originY=pic.originY}
        end
        Data.gen4_hgss_dex_art=index
      end
      do
        local X=assert(require('src.import.RomExtractorGen4').new(os.getenv('HGSS_UI_ROM'),os.getenv('VERSION') or 'heartgold'))
        local M=require('src.import.Gen4HgssMainMenu')
        Data.gen4_main_menu_ink=M.ink(rom)
        Data.gen4_menus=M.words(function(bank,i) return X:string(bank,i) end)
        X:close()
      end
      if os.getenv('SCREEN')=='HgssTitle' or os.getenv('SCREEN')=='HgssIntro' then
        local X=assert(require('src.import.RomExtractorGen4').new(os.getenv('HGSS_UI_ROM'),os.getenv('VERSION') or 'heartgold'))
        Data.gen4_hgss_title_art.prompt=X:string(719,0)
        X.saveImage=function(_,rel,pic)
          local path='__hgss_ui/models/'..rel..'.png'
          pictures[path]=love.graphics.newImage(require('src.import.ImageWriter').fromRGBA8(pic.width,pic.height,pic.rgba))
          return {path=path,width=pic.width,height=pic.height}
        end
        X.write=function(_,name,value)
          if name=='gen4_models' then
            Data.gen4_models.sets.hgssTitle=value.sets.hgssTitle
            Data.gen4_models.sets.hgssOpening=value.sets.hgssOpening
          end
        end
        X:extractModels();X:close()
      end
      local Assets=require('src.render.Assets');local original=Assets.image
      Assets.image=function(path,...) if pictures[path] then return pictures[path] end return original(path,...) end
      rom:close()
    end

    -- THE SERVICES THE ENGINE BRINGS UP, IN THE ENGINE'S OWN ORDER.
    --
    -- Taken from `Game:boot` rather than picked one at a time as each nil
    -- was hit.  The battle harness was assembled the second way and reported
    -- three engine faults that were all missing lifecycle -- `enter`,
    -- `Font.load`, `Game.input`.  Anything added here should be added
    -- because `Game:boot` does it, and in the place `Game:boot` does it.
    -- MODS FIRST, because that is what REGISTERS THE COMMAND SET.
    -- `src/mods/Builtins.lua` calls `Commands.registerInto`, and that is the
    -- only thing that puts the `g4_*` verbs in the script registry.  Without
    -- it every Gen 4 script runs and every row reports "unknown command
    -- 'g4_set_var' (skipped)" -- which looks exactly like a lowering bug and
    -- is nothing of the kind.  Fifth harness gap of this kind; the rule
    -- stands -- do what `Game:boot` does, in the order it does it.
    local ModLoader = require("src.mods.Loader")
    Game.mods = ModLoader.new()
    Game.mods:load(Data)
    Game.modStatus = Game.mods:status()
    require("src.render.Pipelines").install(Data)
    local Renderer = require("src.render.Renderer")
    Game.renderer = Renderer
    Renderer:init()
    require("src.render.Font").load(Data)
    require("src.ui.Theme").load(Data)
    require("src.core.Strings").load(Data)
    local StateStack = require("src.core.StateStack")
    StateStack:init()
    Game.stack = StateStack
    Game.save = SaveData.newGame(Game.bootConfig and Game:bootConfig() or {})
    if Game.adoptSave then pcall(Game.adoptSave, Game, Game.save, true) end
    -- IMPORT_SAV=<file>: a cartridge / emulator save (.sav, .dsv) through
    -- SaveConvert, exactly as the launcher's Import save does, then spawn
    -- where that save stands (MAP/X/Y still override)
    local importedAt
    if os.getenv("IMPORT_SAV") then
      local f = assert(io.open(os.getenv("IMPORT_SAV"), "rb"))
      local bytes = f:read("*a"); f:close()
      local version = os.getenv("VERSION") or "platinum"
      local imported, why = require("src.save_convert.SaveConvert").importSav(bytes, version, version)
      assert(imported, "IMPORT_SAV: " .. tostring(why))
      local options = Game.save.options
      for k in pairs(Game.save) do Game.save[k] = nil end
      for k, v in pairs(imported) do Game.save[k] = v end
      Game.save.options = options
      Game.save.version = version
      local p = Game.save.player
      importedAt = p
      print(("IMPORT_SAV: %s id %s at %s (%s,%s) party %d money %d badges %d"):format(
        tostring(p.name), tostring(p.id), tostring(p.map), tostring(p.x), tostring(p.y),
        #(Game.save.party or {}), Game.save.money or 0,
        require("src.inventory.Badges").count(Data, Game.save, version)))
    end

    -- HGSS_SAFARI=1: a Safari game already started (SafariZoneAction 0 0)
    if os.getenv("HGSS_SAFARI") then
      require("src.world.HgssSafariZone").action(Game.save, 0, 0)
      print("HGSS_SAFARI: arrangement " .. require("src.world.HgssSafariZone").key(Game.save))
    end

    -- INPUT IS A REAL OBJECT FROM THE FIRST FRAME.  The battle harness
    -- reported a stall as an engine fault because its press loop sat behind
    -- `if Game.input then` with a nil input and pressed nothing.  Here it
    -- exists before anything ticks.
    local held = nil
    local pressA = false
    -- BATTLE_MENU_SHOT=1: from the first tick a battle sits at its command
    -- menu, nothing is pressed or held, so the picture at TICKS is that menu
    local frozen = false
    Game.input = {
      -- PRESS_KEY=right: the scheduled press is that button rather than A
      wasPressed  = function(_, k) return not frozen and ((pressA and k == (os.getenv("PRESS_KEY") or "a")) or (keyNow ~= nil and k == keyNow)) end,
      isDown      = function(_, k) return not frozen and held ~= nil and k == held end,
      wasReleased = function() return false end,
    }

    local OW = require("src.world.OverworldController")
    Game.stack:push(OW, os.getenv("MAP") or (importedAt and importedAt.map) or "T01",
                    tonumber(os.getenv("X") or "") or (importedAt and importedAt.x) or 15,
                    tonumber(os.getenv("Y") or "") or (importedAt and importedAt.y) or 25,
                    os.getenv("FACING") or (importedAt and importedAt.facing) or "down")

    -- OPTIONALLY MAKE SOMEONE A FOLLOWER, which is what `setmovementtype
    -- <id>, 48` does in the cartridge.  Done through the module's own `adopt`
    -- rather than by setting the flag by hand, so the harness exercises the
    -- seam the script uses.
    -- FOLLOW NAMES A SPRITE, NOT JUST A localId.
    --
    -- The first version took a localId and the first run adopted T01's
    -- `map_signpost` -- localId 4 -- which has no character art at all, so
    -- "the follower did not draw" was true and meant nothing.  Two objects
    -- can also share a localId on a Gen 4 map (T01's guitarist and its arrow
    -- signpost are both 3), so a number is not an identifier here.  A sprite
    -- name is, and the cast is printed either way.
    -- FLAGS GO THROUGH THE ENGINE'S OWN COMMANDS, so `syncFlagObjects` runs
    -- exactly as it does for a script.  Route 201 makes Barry the partner and
    -- then SETS his hide flag on the very next line, and that sequence is the
    -- thing under test -- faking it by poking `save.flags` would skip the
    -- half that does the damage.
    local Commands = require("src.script.Commands")
    local flagCtx = { save = Game.save, overworld = OW, game = Game,
                      data = Data, mapCallback = true }

    local clearFlag = os.getenv("CLEAR_FLAG")
    if clearFlag then
      Commands.clear_flag(flagCtx, clearFlag)
      print("cleared " .. clearFlag)
    end

    local Follower = require("src.world.Gen4Follower")
    local follow = os.getenv("FOLLOW")
    if follow then
      local wantId = tonumber(follow)
      local target
      local cast = {}
      for _, e in ipairs(OW.entities or {}) do
        local d = e.def
        local lid = e.localId or (d and d.localId)
        local name = d and (d.spriteName or d.sprite)
        cast[#cast + 1] = ("%s:%s@(%s,%s)"):format(tostring(lid), tostring(name), tostring(e.cellX), tostring(e.cellY))
        if not target and ((wantId and lid == wantId) or (not wantId and name == follow)) then
          target = e
        end
      end
      print("live cast -- " .. table.concat(cast, "  "))
      if target and os.getenv("HIDE_FIRST") then
        -- A HIDDEN OBJECT CAN STILL BE ADOPTED.  The cartridge hides the
        -- partner behind a flag and the script that starts the escort runs
        -- near it, so this is not a contrived state.
        target.hidden = true
        print("marked the target hidden BEFORE adopting")
      end
      if target then
        Follower.adopt(Game.save, OW, target)
        print(("adopted %s (localId %s, sprite %s)"):format(
          follow, tostring(target.localId or (target.def and target.def.localId)),
          tostring(target.def and (target.def.spriteName or target.def.sprite))))
      else
        print(("FOLLOW %s matched nobody on %s"):format(follow, tostring(OW.map and OW.map.id)))
      end
    end

    -- CROSSING A SEAM ON PURPOSE.  `Gen4Follower` has two ways to put the
    -- partner on a map: adopt the map's own object, or REBUILD one with
    -- `spawnFollower`.  Only the first is exercised by staying put, and the
    -- play report is about what happens at a border.
    local thenMap = os.getenv("THEN_MAP")
    local thenAt = tonumber(os.getenv("THEN_AT") or "40")
    if thenMap then
      -- Persistent, or the record is dropped at the door by design -- Amity
      -- Square's pet is the case that rule exists for.
      local rec = Game.save.gen4Follower
      if rec then rec.persistent = true end
    end

    -- ...and the line the cartridge runs immediately after SetMovementType.
    local setFlag = os.getenv("SET_FLAG_AFTER")
    if setFlag then
      Commands.set_flag(flagCtx, setFlag)
      local f = Follower.current(OW)
      local live = 0
      for _, e in ipairs(OW.entities or {}) do live = live + 1 end
      print(("after SetFlag %s -- follower=%s, %d live entit(ies)"):format(
        setFlag, f and "still here" or "GONE", live))
    end

    -- OPEN A UI SCREEN OVER THE WORLD.  Items 13-15 of the play-test list
    -- are all screens (Pokedex, trainer card, bag), and the only honest way
    -- to answer "is it Platinum's art" is to draw it and look.
    -- Pushed AFTER the overworld so the stack is the shape the game has.
    -- ITEMS IN THE BAG, because a new-game save has almost none and a bag
    -- screen with nothing in it draws nothing correctly.
    -- THE ENGINE'S OWN PATH, not Bag.add directly: g4_give_item is what a
    -- Sinnoh script row runs, and it is the thing under test.
    if os.getenv("GIVE_G4") then
      local C = require("src.script.Commands")
      require("src.script.Gen4Commands")
      local ctx = { game = Game, save = Game.save, data = Data, overworld = OW }
      for id in tostring(os.getenv("GIVE_G4")):gmatch("%d+") do
        local ok, err = pcall(C.g4_give_item, ctx, tonumber(id), 2)
        print(("[g4give] item %s -> %s"):format(id, ok and "ok" or tostring(err)))
      end
    end
    local give = os.getenv("GIVE")
    if give then
      local Bag = require("src.inventory.Bag")
      for name in tostring(give):gmatch("[^,]+") do name = tonumber(name) or name
        local ok, err = pcall(Bag.add, Game.save, name, 3, Data)
        print(("[give] %s -> %s"):format(name, ok and "ok" or tostring(err)))
      end
    end
    -- WHICH WARP A TILE RESOLVES TO, asked of the REAL Map rather than of a
    -- second copy of the rule.  "WARPAT=48,43 49,43" prints one line each.
    if os.getenv("WARPAT") and OW.map then
      for pair in tostring(os.getenv("WARPAT")):gmatch("%S+") do
        local x, y = pair:match("(%-?%d+),(%-?%d+)")
        x, y = tonumber(x), tonumber(y)
        local hit = x and OW.map.warpAt
                    and OW.map.warpAt[y * OW.map.widthCells + x]
        print(("[warpat] (%d,%d) -> %s"):format(x or -1, y or -1,
          hit and ("warp %d, dest %s header %s"):format(hit.index,
            tostring(hit.def.destMap), tostring(hit.def.destHeader))
            or "none"))
      end
    end

    -- DOES A SCRIPTED MOVE SURVIVE A SAVE AND A RELOAD?
    -- "OBJRELOAD=index,x,y" moves that object, captures the save, throws
    -- the pool away and rebuilds the map the way a fresh boot would, then
    -- prints where the object came back.
    if os.getenv("OBJRELOAD") then
      local idx, nx, ny = tostring(os.getenv("OBJRELOAD")):match("(%d+),(%d+),(%d+)")
      idx, nx, ny = tonumber(idx), tonumber(nx), tonumber(ny)
      local before
      for _, npc in ipairs(OW.npcs or {}) do
        if npc.def and npc.def.index == idx then before = npc end
      end
      if not before then
        print(("[objreload] no object with index %d on this map"):format(idx or -1))
      else
        print(("[objreload] #%d starts at (%s,%s)"):format(idx,
          tostring(before.cellX), tostring(before.cellY)))
        before.cellX, before.cellY = nx, ny
        before.px, before.py = nx * 16, ny * 16
        print(("[objreload] moved to (%d,%d)"):format(nx, ny))
        OW:captureSave(Game.save)
        local kept = Game.save.gen4Objects
        kept = kept and kept[OW.map.id] and kept[OW.map.id][idx]
        print(("[objreload] save holds %s"):format(kept
          and ("(%s,%s)"):format(tostring(kept.x), tostring(kept.y)) or "NOTHING"))
        OW.npcPool = {}
        OW.npcs = {}
        OW:setMap(OW.map.id, 10, 10, "down")
        local after
        for _, npc in ipairs(OW.npcs or {}) do
          if npc.def and npc.def.index == idx then after = npc end
        end
        print(("[objreload] after a rebuild #%d is at %s"):format(idx,
          after and ("(%s,%s)"):format(tostring(after.cellX),
            tostring(after.cellY)) or "GONE"))
      end
    end

    local screenName = os.getenv("SCREEN")
    if os.getenv("SCREEN") then
      local d = Data.gen4_dex
      local mons = Data.pokemon or {}
      local n, firstKey = 0, nil
      for k in pairs(mons) do n = n + 1; if firstKey == nil then firstKey = k end end
      do local lo, hi, nDex = math.huge, -math.huge, 0
        for k, v in pairs(mons) do
          if type(k) == "number" then
            if k < lo then lo = k end
            if k > hi then hi = k end
          end
          if type(v) == "table" and v.dex then nDex = nDex + 1 end
        end
        print(("[dex] numeric ids %s..%s | species carrying a `dex` field: %d"):format(
          tostring(lo), tostring(hi), nDex)) end
      print(("[dex] pokemon entries=%d firstKey=%s(%s) [1]=%s [387]=%s dexSize=%s"):format(
        n, tostring(firstKey), type(firstKey), tostring(mons[1] ~= nil),
        tostring(mons[387] ~= nil), tostring((Data.constants or {}).dexSize)))
      print(("[dex] data.gen4_dex=%s banner=%s"):format(type(d),
        type(d)=="table" and tostring(d.banner and d.banner.path) or "-"))
    end

    -- GIFT=<key>: a Mystery Gift waiting for the deliveryman (Gen4MysteryGift)
    if os.getenv("GIFT") then
      local MG = require("src.pokemon.Gen4MysteryGift")
      Game.save.hallOfFame = { {} }
      print(("[gift] waiting %s -> %s"):format(os.getenv("GIFT"), tostring(MG.choose(Game.save, os.getenv("GIFT")))))
    end
    -- A PARTY, because a new-game save has none and a heal test on an empty
    -- party is a test that cannot fail.
    if os.getenv("PARTY") then
      local Pokemon = require("src.pokemon.Pokemon")
      Game.save.party = { Pokemon.new(Data, tonumber(os.getenv("PARTY"):match("^%d+")),
                                      tonumber(os.getenv("PARTYLEVEL") or "12")) }
      -- PARTY=495,515: more than one (the rest at the same level)
      for id in os.getenv("PARTY"):gmatch(",(%d+)") do
        Game.save.party[#Game.save.party + 1] = Pokemon.new(Data, tonumber(id),
          tonumber(os.getenv("PARTYLEVEL") or "12"))
      end
      -- PARTYMOVES=15,33: the lead's moves (a field-move test: Cut, Surf...)
      if os.getenv("PARTYMOVES") then
        local mon = Game.save.party[1]
        mon.moves = {}
        for id in os.getenv("PARTYMOVES"):gmatch("%d+") do
          local m = Data.moves and Data.moves[tonumber(id)]
          mon.moves[#mon.moves + 1] = { id = tonumber(id), pp = m and m.pp or 10 }
        end
      end
    end
    -- HURT THE PARTY FIRST, so "it healed" is a change and not a constant.
    -- A heal test on a full-health party passes whether or not anything runs.
    if os.getenv("HURT") then
      for _, mon in ipairs(Game.save.party or {}) do
        mon.hp = math.max(1, math.floor(((mon.stats and mon.stats.hp) or 20) / 4))
      end
    end
    local function partyHp()
      local out = {}
      for _, mon in ipairs(Game.save.party or {}) do
        out[#out+1] = ("%s/%s"):format(tostring(mon.hp), tostring(mon.stats and mon.stats.hp))
      end
      return table.concat(out, " ")
    end
    -- FATEFUL=1: the party lead carries the fateful-encounter mark (a
    -- Mystery Gift Pokemon), SHINY=1 makes it shiny
    if os.getenv("FATEFUL") and Game.save.party and Game.save.party[1] then
      Game.save.party[1].fatefulEncounter = true
      if os.getenv("SHINY") then Game.save.party[1].shiny = true end
    end
    print("party before: " .. partyHp())
    -- MARK SPECIES SEEN/OWNED, so the dex has something to list and an entry
    -- page to open.  A dex screen on an empty dex draws an empty dex
    -- correctly, which tells you nothing about its art.
    local dexSeen = os.getenv("DEX_SEEN")
    if dexSeen then
      Game.save.pokedex = Game.save.pokedex or {}
      local d = Game.save.pokedex
      d.seen, d.owned = d.seen or {}, d.owned or {}
      if dexSeen == "all" then
        for id = 1, 600 do d.seen[id] = true; d.owned[id] = true end
      end
      for id in tostring(dexSeen):gmatch("%d+") do
        d.seen[tonumber(id)] = true; d.owned[tonumber(id)] = true
      end
    end
    -- A HALL OF FAME ENTRY, because the trainer card picks one of SEVEN faces
    -- from the card level, and a screen looked at in one state says nothing
    -- about the other six.  `HOF=n` puts n empty rosters in the save, which is
    -- what `#save.hallOfFame > 0` -- the one criterion of the five that this
    -- port can evaluate -- is asking about.
    if os.getenv("HOF") then
      local rosters = tonumber(os.getenv("HOF")) or 1
      Game.save.hallOfFame = {}
      for i = 1, rosters do Game.save.hallOfFame[i] = {} end
      print(("[hof] %d roster(s)"):format(#Game.save.hallOfFame))
    end
    -- HOF_PARTY=n: n Hall of Fame entries made of the PARTY (with PARTY=...),
    -- for the PC's browser (SCREEN=Gen4PcHallOfFame)
    if os.getenv("HOF_PARTY") and Game.save then
      Game.save.hallOfFame = {}
      for e = 1, tonumber(os.getenv("HOF_PARTY")) or 1 do
        local entry = { date = { year = 2026, month = 10, day = 10 + e } }
        for _, mon in ipairs(Game.save.party or {}) do
          local moves = {}
          for i, mv in ipairs(mon.moves or {}) do moves[i] = type(mv) == "table" and mv.id or mv end
          entry[#entry + 1] = { species = mon.species, level = mon.level + e, nickname = mon.nickname,
            gender = require("src.pokemon.Pokemon").genderOf(Data, mon), otName = "LYRA", moves = moves }
        end
        Game.save.hallOfFame[e] = entry
      end
    end
    -- SECOND_SCREEN=vertical (or any SecondScreen mode): both screens in shot
    if os.getenv("SECOND_SCREEN") and Game.save then
      Game.save.options = Game.save.options or {}
      Game.save.options.secondScreenMode = os.getenv("SECOND_SCREEN")
    end
    -- BADGES=n: the first n of the dataset's badges won (a card / board test)
    if os.getenv("BADGES") and Game.save then
      Game.save.badges = Game.save.badges or {}
      for i, entry in ipairs(require("src.inventory.Badges").list(Data) or {}) do
        if i <= (tonumber(os.getenv("BADGES")) or 0) then Game.save.badges[entry.id] = true end
      end
    end
    -- LEARN_MOVE=<move id>: the lead is offered a move (MoveLearnMenu)
    if os.getenv("LEARN_MOVE") and Game.save and Game.save.party and Game.save.party[1] then
      local okL, errL = pcall(require("src.ui.Screens").push, Game, "MoveLearnMenu",
        Game.save.party[1], tonumber(os.getenv("LEARN_MOVE")), function() print("[learn] done") end)
      print(("[learn] push -> %s"):format(okL and "ok" or tostring(errL)))
    end
    -- HGSS_GEAR="cards=1,2;numbers=0,1,2;level=2;skin=3;app=2": the HGSS
    -- Pokegear's save record (cards 1 map / 2 radio, phone numbers, the map's
    -- unlock level, the skin, the last used app)
    if os.getenv("HGSS_GEAR") and Game.save then
      local pg = { cards = {}, numbers = {}, mapLevel = 0 }
      for k, v in tostring(os.getenv("HGSS_GEAR")):gmatch("(%a+)=([^;]*)") do
        if k == "cards" or k == "numbers" then
          for n in v:gmatch("%d+") do pg[k][tonumber(n)] = true end
        elseif k == "level" then pg.mapLevel = tonumber(v)
        elseif k == "app" then pg.lastApp = tonumber(v)
        else pg[k] = tonumber(v) or v end
      end
      Game.save.hgssPokegear = pg
    end
    if screenName then
      local Screens = require("src.ui.Screens")
      -- OPEN IT AT A NAMED PAGE.  A screen that only ever renders its first
      -- page proves nothing about the ones that select something else: the
      -- bag's pocket icons all look plausible until you check that the
      -- highlighted one MOVES.
      local opts = {}
      if os.getenv("POCKET") then opts.pocket = os.getenv("POCKET") end
      -- BOX_MODE=move (deposit / withdraw / items): the PC box screen's mode;
      -- BOX_MONS="1:155,158,0,161": box 1's slots (0 = empty), EGG_SLOT=box:slot
      -- makes one an Egg, MAIL_PARTY=n gives party mon n a Mail (item 137)
      if os.getenv("BOX_MODE") then opts.mode = os.getenv("BOX_MODE") end
      if os.getenv("BOX_MONS") and Game.save then
        local Pokemon = require("src.pokemon.Pokemon")
        local boxes = require("src.pokemon.Boxes").ensure(Game.save)
        for b, list in tostring(os.getenv("BOX_MONS")):gmatch("(%d+):([%d,]+)") do
          local s = 0
          for id in list:gmatch("%d+") do
            s = s + 1
            if tonumber(id) > 0 then boxes[tonumber(b)][s] = Pokemon.new(Data, tonumber(id), 10) end
          end
        end
        for b, s in tostring(os.getenv("EGG_SLOT") or ""):gmatch("(%d+):(%d+)") do
          local m = boxes[tonumber(b)][tonumber(s)]
          if m then m.egg = true; m.isEgg = true end
        end
      end
      if os.getenv("MAIL_PARTY") and Game.save and Game.save.party then
        local m = Game.save.party[tonumber(os.getenv("MAIL_PARTY"))]
        if m then m.heldItem = tonumber(os.getenv("MAIL_ITEM") or "137") end
      end
      -- the summary opens on the lead (PARTY=...)
      if screenName == "SummaryMenu" and Game.save and Game.save.party then opts.mon = Game.save.party[1] end if screenName == "SummaryMenu" and os.getenv("LEARN_CHOOSE") then opts.choose = { move = tonumber(os.getenv("LEARN_CHOOSE")), onChoose = function(i) print("[learn] chose " .. tostring(i)) end } end
      -- CERT=<id>: which HGSS certificate (0 Johto, 1 National, 2 Shiny Leaf)
      if screenName == 'HgssCertificate' then opts = tonumber(os.getenv('CERT') or '0') end
      if screenName == 'HgssIntro' then opts=function()
        print('[intro] completed; entering HGSS title')
        Screens.push(Game,'HgssTitle',{})
      end end
      -- ANY SCREEN, NOT ONLY A REGISTERED ONE.  The starter selection,
      -- the intro and the title are pushed by script rather than named
      -- in `Screens`, so a harness that can only reach the registry
      -- cannot look at half the screens there are.
      local okS, errS = pcall(Screens.push, Game, screenName, opts)
      if not okS then
        local okM, mod = pcall(require, "src.ui." .. screenName)
        if okM and type(mod) == "table" and mod.new then
          okS, errS = pcall(function()
            Game.stack:push(mod.new(Game, opts))
          end)
          if okS then errS = "pushed by module name" end
        end
      end
      print(("[screen] push %s -> %s"):format(screenName,
             okS and "ok" or tostring(errS)))
      if okS and screenName=='Gen5MainMenu' and os.getenv('MENU_SUMMARY') then
        local menu=Game.stack:top()
        Game.save.playTime=2*3600+5*60
        menu.save=Game.save
        if menu.items[1].key~='continue' then
          table.insert(menu.items,1,{key='continue',label=menu.art.text[0]})
        end
      end
      if okS and screenName=='Gen5JuniperIntro' and os.getenv('JUNIPER_PHASE') then
        local intro=Game.stack:top()
        intro:say(tonumber(os.getenv('JUNIPER_MESSAGE') or '11'),os.getenv('JUNIPER_PHASE'))
        intro.gender=os.getenv('GENDER') or 'boy'
        intro.choice=tonumber(os.getenv('CHOICE') or '1')
      end
    end
    -- BOOT=1: the engine's own boot chain instead of the field -- the
    -- dataset's splash, then the title Game:makeTitleState builds (NEW GAME
    -- runs the professor), exactly as Game:load pushes them
    if os.getenv("BOOT") then
      while Game.stack:top() do Game.stack:pop() end
      Game.overworld = Game.overworld or OW
      local Screens = require("src.ui.Screens")
      local title = Game:makeTitleState()
      local screens = ((Data.field or {}).boot or {}).screens or {}
      if screens.splash then
        Screens.push(Game, screens.splash, function() Game.stack:push(title) end)
      else
        Game.stack:push(title)
      end
      print("[boot] splash " .. tostring(screens.splash) .. ", title " .. tostring(screens.title))
    end
    held = os.getenv("WALK")
    local ticks = tonumber(os.getenv("TICKS") or "180")
    -- A-PRESSES ON A SCHEDULE, and the press is REAL: the battle harness
    -- once guarded its presses behind `if Game.input then` with a nil input
    -- and reported a stall as though presses had been tried.
    local pressEvery = tonumber(os.getenv("PRESS") or "0")
    -- WALKSEQ="up:5,left:3,...": hold each direction until the player has
    -- moved that many cells (the map's cell changes, so a script's pause
    -- just waits), then the next; WALK applies after the last
    local seq = {}
    for dir, n in (os.getenv("WALKSEQ") or ""):gmatch("(%a+):(%d+)") do seq[#seq + 1] = { dir, tonumber(n) } end
    local seqAt, seqMoved, seqCell = 1, 0, nil
    local finalHeld = held
    -- WALKTO="x,y;x,y": walk to each cell in turn by a breadth-first path
    -- over the engine's own Collision.canMove (people included), re-planned
    -- every step; a target that cannot be reached is skipped after a while
    local targets = {}
    for x, y in (os.getenv("WALKTO") or ""):gmatch("(%-?%d+),(%-?%d+)") do targets[#targets + 1] = { tonumber(x), tonumber(y) } end
    local tAt, tStuck, tLastCell, tMap = 1, 0, nil, nil
    -- REPEL=<steps>: keep wild encounters off a story run (the cartridge's
    -- own repel rule -- nothing below the lead's level appears)
    if os.getenv("REPEL") and Game.save then Game.save.repelSteps = tonumber(os.getenv("REPEL")) end
    -- ITEMS="444:1,4:20": bag items by id; COINS=n: the Coin Case's coins
    if os.getenv("ITEMS") and Game.save then
      Game.save.inventory = Game.save.inventory or {}
      for id, n in os.getenv("ITEMS"):gmatch("(%d+):(%d+)") do Game.save.inventory[("ITEM_%03d"):format(tonumber(id))] = tonumber(n) end
    end
    if os.getenv("COINS") and Game.save then Game.save.coins = tonumber(os.getenv("COINS")) end
    -- HGSS_CONTEST=<weekday>: a Bug-Catching Contest already running
    if os.getenv("HGSS_CONTEST") and Game.save then
      require("src.world.HgssBugContest").start(Game.save, tonumber(os.getenv("HGSS_CONTEST")) or 2)
      Game.save.flags = Game.save.flags or {}
      Game.save.flags["FLAG_G4_0996"] = true
      -- HGSS_CONTEST_CAUGHT=<species>:<level>: already holding a catch
      local cs, cl = (os.getenv("HGSS_CONTEST_CAUGHT") or ""):match("^(%d+):(%d+)$")
      if cs then
        Game.save.g2BugContest.caught = require("src.pokemon.Pokemon").new(Data, tonumber(cs), tonumber(cl))
      end
    end
    local Collision = require("src.world.Collision")
    local DIRS = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
    -- `avoid`: cells (x * 4096 + y) never stepped on unless they are the
    -- goal -- the other warps on the way to the one wanted
    local function planStep(ow, tx, ty, avoid)
      local p, map = ow.player, ow.map
      if not (p and map and p.cellX) then return nil end
      local sx, sy = p.cellX, p.cellY
      if sx == tx and sy == ty then return "here" end
      -- a map with levels (def.elevationCells: Drayden's gym's floor, deck
      -- and rails) is searched by cell AND level, the level a step leaves
      -- the walker at (Map:elevationAfter) carried along
      local elevated = map.def and map.def.elevationCells and map.elevationAfter and true or false
      local key = function(x, y, e) return (x * 4096 + y) * 32 + ((elevated and e) or 0) end
      local se = elevated and p.elevation or nil
      local prev, q, head = { [key(sx, sy, se)] = false }, { { sx, sy, se } }, 1
      local ents = ow.cast or ow.entities or ow.npcs or {}
      -- (a cap past the biggest map: Pinwheel Forest is 128 x 96)
      while head <= #q and head < 40000 do
        local c = q[head]; head = head + 1
        for dname, d in pairs(DIRS) do
          local nx, ny = c[1] + d[1], c[2] + d[2]
          local ne = elevated and map:elevationAfter(c[3], nx, ny, c[1], c[2]) or nil
          local k = key(nx, ny, ne)
          if prev[k] == nil then
            local mover = { cellX = c[1], cellY = c[2], elevation = (elevated and c[3]) or p.elevation, facing = dname, surfing = p.surfing }
            local ok = Collision.canMove(map, ents, mover, dname)
            if ok and avoid and avoid[nx * 4096 + ny] and not (nx == tx and ny == ty) then ok = false end
            if ok or (nx == tx and ny == ty) then
              prev[k] = { c[1], c[2], dname, c[3] }
              if nx == tx and ny == ty then
                local cx, cy, ce, first = nx, ny, ne, dname
                while true do
                  local pr = prev[key(cx, cy, ce)]
                  if not pr then break end
                  first = pr[3]
                  if pr[1] == sx and pr[2] == sy and pr[4] == se then break end
                  cx, cy, ce = pr[1], pr[2], pr[4]
                end
                return first
              end
              if ok then q[#q + 1] = { nx, ny, ne } end
            end
          end
        end
      end
      return nil
    end
    -- PLAYTHROUGH=<game>: the story as beats (tools/gen4_playthrough/), the
    -- runner choosing each tick's input; START_AT=<beat> skips ahead
    local PT
    if os.getenv("PLAYTHROUGH") then
      local Runner = dofile("tools/gen4_playthrough/runner.lua")
      local beats = dofile(("tools/gen4_playthrough/%s.lua"):format(os.getenv("PLAYTHROUGH")))
      PT = Runner.new(Game, beats, { startAt = os.getenv("START_AT"), game = os.getenv("PLAYTHROUGH"),
        snapshotDir = os.getenv("PT_SNAPSHOTS") or "G:/Gen2Recomped/scratch_claude/playthrough",
        resume = tonumber(os.getenv("RESUME") or "") })
      _G.__pt = PT
    end
    for i = 1, ticks do
      if PT then
        local h, k = PT:tick(i, Game, OW, planStep)
        held, keyNow, pressA = h, k, false
        if PT.done then print(("[pt] finished at tick %d: %s"):format(i, PT.failed and ("FAILED " .. PT.failed) or "ok")) break end
      end
      -- the music's own tick (Game:update runs it on its real-time clock,
      -- which this loop never reaches): without it a script's `fadeoutbgm`
      -- waits for a DS fade that never ends
      pcall(require("src.core.Music").update, Game.data)
      -- PRESS_UNTIL=n: stop pressing after tick n (a press would re-talk to
      -- whatever is ahead once the walk starts)
      if os.getenv("BATTLE_MENU_SHOT") and not frozen then
        local st = Game.stack and Game.stack.states
        local top = st and st[#st]
        if top and top.battle and top.phase == "menu" then
          frozen = true
          print(("[battle menu shot] frozen at the command menu, tick %d"):format(i))
        end
      end
      -- TAPS="20:128,170;40:30,60": a touch at bottom-screen (x, y) on each
      -- named tick, handed to the top state as the touch screen would (in a
      -- vertical / horizontal window, through the window rect; else as an
      -- injected second-screen touch, which every Gen 4 screen reads as local)
      for t, tx, ty in (os.getenv("TAPS") or ""):gmatch("(%d+):(%d+),(%d+)") do
        if tonumber(t) == i then
          local SS = require("src.ui.SecondScreen")
          local top = Game.stack.states[#Game.stack.states]
          tx, ty = tonumber(tx), tonumber(ty)
          if top and top.touchpressed then
            local px, py = tx, ty
            if SS.combined(Game) then
              local wx, wy, s = SS.windowRect(Game)
              px, py = wx + tx * s, wy + ty * s
            else Game.secondScreenInjecting = true end
            local okT, res = pcall(top.touchpressed, top, 1, px, py)
            if top.touchreleased then pcall(top.touchreleased, top, 1, px, py) end
            Game.secondScreenInjecting = nil
            print(("[tap] tick %d (%d,%d) -> %s"):format(i, tx, ty, tostring(okT and res or res)))
            if os.getenv("TAP_DEBUG") then
              local up = require("src.render.Renderer").uiPresentation or {}
              print(("[tap] ui (%s,%s) x%s row=%s col=%s held=%s party=%s/%s"):format(tostring(up.x), tostring(up.y),
                tostring(up.scaleX), tostring(top.row), tostring(top.col), tostring(top.held ~= nil),
                tostring(top.partyOpen), tostring(top.partyIndex)))
            end
          end
        end
      end
      -- DRAGS="30:40,106>376,136": a stylus drag on one tick -- pressed at the
      -- first point, moved to the second and let go there (same coordinates
      -- as TAPS; the window's)
      for t, x1, y1, x2, y2 in (os.getenv("DRAGS") or ""):gmatch("(%d+):(%d+),(%d+)>(%d+),(%d+)") do
        if tonumber(t) == i then
          local top = Game.stack.states[#Game.stack.states]
          if top and top.touchpressed then
            x1, y1, x2, y2 = tonumber(x1), tonumber(y1), tonumber(x2), tonumber(y2)
            local ok1 = pcall(top.touchpressed, top, 1, x1, y1)
            if top.touchmoved then
              pcall(top.touchmoved, top, 1, (x1 + x2) / 2, (y1 + y2) / 2, 0, 0)
              pcall(top.touchmoved, top, 1, x2, y2, 0, 0)
            end
            local ok2, res = true, nil
            if top.touchreleased then ok2, res = pcall(top.touchreleased, top, 1, x2, y2) end
            print(("[drag] tick %d (%d,%d)>(%d,%d) -> %s %s"):format(i, x1, y1, x2, y2, tostring(ok1), tostring(ok2 and res or res)))
          end
        end
      end
      -- PRESS_KEYS="5:right,9:a": one button on each named tick
      if not PT then
      keyNow = nil
      for t, k in (os.getenv("PRESS_KEYS") or ""):gmatch("(%d+):(%a+)") do if tonumber(t) == i then keyNow = k end end
      -- PRESS_ON_BITE=n: press A n ticks into a Gen 4 rod's "!" (Gen4FishingTask)
      if os.getenv("PRESS_ON_BITE") then
        local top = Game.stack.states[#Game.stack.states]
        if top and top.name == "Gen4FishingTask" and top.state == "checkReel" then
          _G.__biteTicks = (_G.__biteTicks or 0) + 1
          if _G.__biteTicks == (tonumber(os.getenv("PRESS_ON_BITE")) or 1) then keyNow = "a"; print("[fish] A on the bite at tick " .. i) end
        end
      end
      pressA = pressEvery > 0 and (i % pressEvery == 0) and i <= (tonumber(os.getenv("PRESS_UNTIL") or "") or math.huge)
      end
      -- STRENGTH=1: Strength active (as the boulder's field-move script leaves it)
      if os.getenv("STRENGTH") and OW and i == 1 then OW.strengthActive = true end
      -- EMOTE_AT=<tick>[:kind]: the "!" (or "double") over the player, as a
      -- trainer's sighting starts it (OverworldController's emote record)
      if os.getenv("EMOTE_AT") and OW and i == tonumber(os.getenv("EMOTE_AT"):match("^(%d+)")) then
        local E = require("src.import.Gen4Emotes")
        local n = E.framesFor(OW.map and OW.map.def)
        OW.emote = { npc = OW.player, frames = n, totalFrames = n,
                     bubble = os.getenv("EMOTE_AT"):match(":(%a+)$") or 1 }
      end
      -- USE_ITEM=<id> USE_ITEM_AT=<tick>: use an item from the bag (as the
      -- bag's USE does -- BagMenu.useItem)
      if os.getenv("USE_ITEM") and OW and i == (tonumber(os.getenv("USE_ITEM_AT") or "") or 5) then
        local id = tonumber(os.getenv("USE_ITEM")) or os.getenv("USE_ITEM")
        local okU, errU = pcall(require("src.ui.BagMenu").useItem, Game, nil, id,
          { close = function() end, items = {}, index = 1, refresh = function() end })
        print(("[item] used %s: %s onBike=%s repel=%s"):format(tostring(id), okU and "ok" or tostring(errU),
          tostring(Game.save.onBike), tostring(Game.save.repelSteps)))
      end
      -- DIGWARP=MAP,x,y: the recorded Escape Rope / Dig exit (save.digWarp)
      if os.getenv("DIGWARP") and OW and i == 1 then
        local m, x, y = os.getenv("DIGWARP"):match("([^,]+),(%d+),(%d+)")
        Game.save.digWarp = { id = m, x = tonumber(x), y = tonumber(y) }
        OW.digWarp = Game.save.digWarp
      end
      -- FIELD_MOVE=CUT FIELD_MOVE_AT=<tick>: the party menu's field-move row
      -- for party slot 1 (Gen4PartyMenu:useFieldMove), as if chosen
      if os.getenv("FIELD_MOVE") and OW and i == (tonumber(os.getenv("FIELD_MOVE_AT") or "") or 5) then
        local PM = require("src.ui.Gen4PartyMenu")
        local menu = PM.new(Game, {})
        menu.index = 1
        Game.stack:push(menu)
        local okF, errF = pcall(menu.useFieldMove, menu, Game.save.party[1], os.getenv("FIELD_MOVE"))
        local top = Game.stack.states[#Game.stack.states]
        print(("[fieldmove] %s: %s top=%s"):format(os.getenv("FIELD_MOVE"), okF and "ok" or tostring(errF),
          require("src.core.StateStack").describe(top)))
        if top == menu then Game.stack:pop() end
      end
      -- FIND_WATER=1: list land cells that face water (a fishing spot finder)
      if os.getenv("FIND_WATER") and OW and i == 2 then
        local m, n = OW.map, 0
        local W, H = m.width or (m.def and m.def.width) or 64, m.height or (m.def and m.def.height) or 64
        for y = 0, H - 1 do for x = 0, W - 1 do
          if n < 12 and not m:isWaterCell(x, y) then
            for _, d in ipairs({ { 0, 1, "down" }, { 0, -1, "up" }, { 1, 0, "right" }, { -1, 0, "left" } }) do
              if m:inBounds(x + d[1], y + d[2]) and m:isWaterCell(x + d[1], y + d[2]) then
                print(("[water] X=%d Y=%d FACING=%s"):format(x, y, d[3])); n = n + 1; break
              end
            end
          end
        end end
      end
      -- DWWARPTEST=1: open the Distortion World warp (DoDWWarp) at tick 2
      if os.getenv("DWWARPTEST") and OW and i == 2 then
        Game.stack:push(require("src.ui.Gen4DistortionWarp").new(Game, function() print("[dwwarp] done") end))
      end
      -- ITEMAUDIT=1: every item with a field-use function, used from the bag
      -- out of battle (on the lead when it needs a target); lists refusals
      if os.getenv("ITEMAUDIT") and OW and i == 3 then
        local IE = require("src.inventory.ItemEffects")
        local refused = {}
        for id, it in pairs(Game.data.items or {}) do
          if type(it) == "table" and tonumber(it.fieldUseFunc) and it.fieldUseFunc ~= 0 then
            local target = IE.needsTarget(id, it) and Game.save.party[1] or nil
            local okU, kind, msgs = pcall(IE.use, Game.data, Game.save, id, target, nil, nil, OW)
            local line = type(msgs) == "table" and tostring(msgs[1]) or tostring(msgs)
            if not okU then refused[#refused + 1] = ("%s(%s,f%d): ERROR %s"):format(it.name, tostring(id), it.fieldUseFunc, tostring(kind))
            elseif kind == "failed" and (line:find("OAK") or line:find("time to use") or line:find("Rowan")) then
              refused[#refused + 1] = ("%s(%s,f%d): %s"):format(it.name, tostring(id), it.fieldUseFunc, line:gsub("\n", " "))
            end
          end
        end
        table.sort(refused)
        for _, r in ipairs(refused) do print("[audit] " .. r) end
        print(("[audit] %d refused"):format(#refused))
      end
      -- SURFING=1: start on the water (a Waterfall test)
      if os.getenv("SURFING") and OW and i == 1 then OW.player.surfing = true end
      if targets[tAt] and OW and OW.player then
        local t = targets[tAt]
        local d = planStep(OW, t[1], t[2])
        local cell = tostring(OW.map and OW.map.id) .. ":" .. tostring(OW.player.cellX) .. "," .. tostring(OW.player.cellY)
        local st = Game.stack and Game.stack.states
        local busy = (OW.runner and OW.runner.isRunning and OW.runner:isRunning())
                     or (#(OW.scriptMoves or {}) > 0)
                     or (st and st[#st] ~= OW)   -- a battle, a box, a menu
        if cell == tLastCell and not busy then tStuck = tStuck + 1 elseif cell ~= tLastCell then tStuck = 0 end
        tLastCell = cell
        -- a door target is a solid cell: reaching it is the map changing
        local mapNow = OW.map and OW.map.id
        if tMap and mapNow ~= tMap then d = "here" end
        tMap = mapNow
        if d == "here" or tStuck > 600 then
          if tStuck > 600 then print(("[walkto] gave up on %d,%d at %s"):format(t[1], t[2], cell)) end
          tAt, tStuck = tAt + 1, 0
          held = targets[tAt] and nil or finalHeld
        else
          held = d
        end
      elseif seq[seqAt] then
        local p = OW.player
        local cell = p and (tostring(OW.map and OW.map.id) .. ":" .. tostring(p.cellX) .. "," .. tostring(p.cellY))
        -- "holdright:60" holds a direction for that many TICKS instead of
        -- cells (a press at a panel the player cannot walk into)
        -- "wait:30" holds nothing for that many ticks (A presses still land
        -- on whatever the player faces)
        local isHold = seq[seqAt][1]:match("^hold(%a+)$") or seq[seqAt][1] == "wait"
        if isHold then seqMoved = seqMoved + 1
        elseif seqCell and cell ~= seqCell then seqMoved = seqMoved + 1 end
        seqCell = cell
        if seqMoved >= seq[seqAt][2] then seqAt, seqMoved = seqAt + 1, 0 end
        local cur = seq[seqAt] and seq[seqAt][1]
        if cur == "wait" then held = nil
        else held = cur and (cur:match("^hold(%a+)$") or cur) or finalHeld end
      end
      if thenMap and i == thenAt then
        local okM, errM = pcall(OW.setMap, OW, thenMap,
                                tonumber(os.getenv("THEN_X") or "10"),
                                tonumber(os.getenv("THEN_Y") or "10"), "down")
        print(("crossed to %s: %s"):format(thenMap, okM and "ok" or tostring(errM)))
        local f2 = Follower.current(OW)
        print(("after crossing -- follower=%s"):format(
          f2 and ("spawned=%s sprite=%s"):format(tostring(f2.gen4FollowerSpawned),
                 tostring(f2.def and (f2.def.spriteName or f2.def.sprite))) or "NONE"))
      end
      -- TICK THE STACK, NOT THE OVERWORLD.  `StateStack:update` runs the TOP
      -- state, and a text box, menu or yes/no prompt is pushed above the
      -- overworld -- so ticking `OW` directly leaves every box unable to
      -- consume a press.  Measured before this: talking to the Pokemon
      -- Centre nurse parked at `g4_message_var` for 360 frames and the
      -- party never healed, which reads exactly like the play report and
      -- was this loop.
      -- TRANSITION_AT=n: start Platinum's into-battle cut-in on tick n over
      -- the real field (TRANSITION_CLASS for a trainer, else a wild one of
      -- TRANSITION_SPECIES/TRANSITION_LEVEL), with nothing pushed after it.
      if tonumber(os.getenv("TRANSITION_AT") or "") == i then
        local class = tonumber(os.getenv("TRANSITION_CLASS") or "")
        local fake = { kind = class and "trainer" or "wild",
                       trainer = class and { class = class, name = os.getenv("NAME") or "ROARK" } or nil,
                       enemy = { mon = { species = tonumber(os.getenv("TRANSITION_SPECIES") or "396"),
                                         level = tonumber(os.getenv("TRANSITION_LEVEL") or "3") } } }
        local okT, errT = pcall(OW.pushBattleTransition, OW, fake, nil, function() end)
        print(("[transition] %s"):format(okT and "pushed" or tostring(errT)))
      end
      -- RADAR_AT=n: switch the Poke Radar on at tick n where the player
      -- stands, then put them on the first live patch (src/world/Gen4Radar.lua)
      if tonumber(os.getenv("RADAR_AT") or "") == i then
        Game.save.inventory = Game.save.inventory or {}
        Game.save.inventory[431] = 1
        Game.save.gen4RadarCharge = 50
        local why = OW:gen4UseRadar()
        local c = OW.gen4Radar
        print(("[radar] use -> %s; chain active=%s"):format(tostring(why), tostring(c and c.active)))
        for k, pt in ipairs((c and c.patches) or {}) do
          print(("[radar] patch %d at (%d,%d) active=%s continue=%s shake=%s"):format(k, pt.x, pt.y,
            tostring(pt.active), tostring(pt.continueChain), tostring(pt.shakeType)))
        end
        for _, pt in ipairs((c and c.patches) or {}) do
          if pt.active then
            OW.player.cellX, OW.player.cellY = pt.x, pt.y
            local ok, hit = pcall(OW.gen4RadarEncounter, OW,
              require("src.world.Encounter").forMap(Game.data, OW.map.def, OW.map.id, nil, Game.save))
            local top = Game.stack.states[#Game.stack.states]
            print(("[radar] stepped on (%d,%d): encounter=%s top=%s chain=%s species=%s"):format(pt.x, pt.y,
              tostring(ok and hit or hit), tostring(top and (top.kind or top.name or top.style)),
              tostring(OW.gen4Radar and OW.gen4Radar.count), tostring(OW.gen4Radar and OW.gen4Radar.species)))
            break
          end
        end
      end
      local okU, errU = pcall(Game.stack.update, Game.stack, 1 / 60)
      if not okU then print(("update raised on tick %d: %s"):format(i, tostring(errU))) break end
      -- MENU_PICK=new: the first main menu that comes up has its cursor put
      -- on NEW GAME (a save on disk adds CONTINUE above it)
      if os.getenv("MENU_PICK") and not _G.__menuPicked then
        local top = Game.stack.states[#Game.stack.states]
        if type(top) == "table" and type(top.items) == "table" and top.index then
          for n, item in ipairs(top.items) do
            local key = tostring(item.key or ""):lower():gsub("[^%a]", "")
            if key == "newgame" then top.index = n; _G.__menuPicked = true; print("[menu] cursor on NEW GAME at tick " .. i) break end
          end
        end
      end
      -- TOPIC_PICK=3: a professor's topic menu (HgssOakIntro `topics`) answered
      -- with that row
      if os.getenv("TOPIC_PICK") then
        local top = Game.stack.states[#Game.stack.states]
        if type(top) == "table" and top.phase == "topics" then top.choice = tonumber(os.getenv("TOPIC_PICK")) end
      end
      -- SHOTS="60,120,...": a picture at each of those ticks too (ow_<TAG>_<tick>.png),
      -- drawn the way love.draw does into an offscreen canvas
      if os.getenv("SHOTS") then
        _G.__shotSet = _G.__shotSet or {}
        if not next(_G.__shotSet) then for t in os.getenv("SHOTS"):gmatch("%d+") do _G.__shotSet[tonumber(t)] = true end end
        if _G.__shotSet[i] then
          local w, h = love.graphics.getDimensions()
          local canvas = love.graphics.newCanvas(w, h)
          love.graphics.push("all")
          -- the renderer presents by setting the canvas back to the screen;
          -- here "the screen" is this canvas
          local setCanvas = love.graphics.setCanvas
          local target = { canvas, depth = true }
          love.graphics.setCanvas = function(c, ...)
            if c == nil then return setCanvas(target) end
            return setCanvas(c, ...)
          end
          setCanvas(target)
          love.graphics.clear(0, 0, 0, 1)
          local okD, errD = pcall(Game.draw, Game)
          love.graphics.setCanvas = setCanvas
          setCanvas()
          love.graphics.pop()
          if okD then
            canvas:newImageData():encode("png", ("ow_%s_%05d.png"):format(TAG, i))
            local top = Game.stack.states[#Game.stack.states]
            local mt = top and getmetatable(top)
            print(("[shot] %d top=%s"):format(i, tostring(top and (top.name or top.kind or (mt and mt.__name)) or "?")))
          else print("[shot] draw raised: " .. tostring(errD)) end
        end
      end
      -- WATCH ONE ACTOR BY SPRITE NAME.  The absence of a warning is not
      -- evidence that a movement ran; seeing the facing change is.
      local watch = os.getenv("WATCH")
      if watch and i % (tonumber(os.getenv("WATCH_EVERY") or "60")) == 0 then
        for _, e in ipairs(OW.entities or {}) do
          local d = e.def
          if d and (d.spriteName == watch or d.sprite == watch) then
            print(("t=%d %s facing=%s at (%s,%s) moving=%s"):format(
              i, watch, tostring(e.facing), tostring(e.cellX),
              tostring(e.cellY), tostring(e.moving)))
          end
        end
      end
      if screenName and i == 14 then
        local it = Data.items or {}
        local n, sample = 0, nil
        for k, v in pairs(it) do n = n + 1
          if sample == nil and type(v) == "table" then sample = {k, v} end end
        local byName = it["POTION"]
        print(("[items] ITEM_017=%s ITEM_17=%s item_17=%s"):format(
          type(it["ITEM_017"]), type(it["ITEM_17"]), type(it["item_17"])))
        local strKeys = 0
        for k in pairs(it) do if type(k) == "string" then strKeys = strKeys + 1 end end
        print(("[items] string-keyed entries: %d"):format(strKeys))
        local mc = (Data.constants or {}).martCommon
        if type(mc) == "table" then
          local r = mc[1]
          local ks = {}
          if type(r) == "table" then for k, v in pairs(r) do ks[#ks+1] = k .. "=" .. tostring(v) end end
          table.sort(ks)
          print("[mart] row1: " .. table.concat(ks, " "))
        end
        local e0 = it[0] or it[1]
        if type(e0) == "table" then
          local ks = {}
          for k in pairs(e0) do ks[#ks+1] = tostring(k) end
          table.sort(ks)
          print("[items] numeric entry fields: " .. table.concat(ks, ","))
          print("[items] its name=" .. tostring(e0.name) .. " desc=" .. tostring(e0.description and "yes" or "no"))
        end
        print(("[items] count=%d sampleKey=%s(%s) POTION=%s"):format(
          n, tostring(sample and sample[1]), type(sample and sample[1]),
          type(byName)))
        if type(byName) == "table" then
          local keys = {}
          for k in pairs(byName) do keys[#keys+1] = tostring(k) end
          table.sort(keys)
          print("[items] POTION fields: " .. table.concat(keys, ","))
        end
      end
      if screenName and i == 15 then
        local top = Game.stack.states[#Game.stack.states]
        if top and top.selected then
          local r = top:selected()
          print(("[bag] selected=%s desc=%s"):format(
            tostring(r and (r.name or r.id)),
            r and tostring(r.description and r.description:sub(1,40)) or "-"))
        end
      end
      if screenName and i % 20 == 0 then
        local top = Game.stack.states[#Game.stack.states]
        print(("t=%d top=%s page=%s index=%s species=%s"):format(i,
          tostring(top and top.name or (top == OW and "overworld" or "screen")),
          tostring(top and top.page), tostring(top and top.index),
          tostring(top and type(top.species)=='function' and top:species())))
      end
      if os.getenv("TRACE") then
        local f = Follower.current(OW)
        local p = OW.player
        print(("t=%d player=(%s,%s)%s | follower=%s"):format(
          i, tostring(p and p.cellX), tostring(p and p.cellY),
          tostring(p and p.facing),
          f and ("(%s,%s) spawned=%s hidden=%s sprite=%s"):format(
                 tostring(f.cellX), tostring(f.cellY),
                 tostring(f.gen4FollowerSpawned), tostring(f.hidden),
                 tostring(f.def and (f.def.spriteName or f.def.sprite)))
            or "none"))
      end
    end

    -- DRAWING GOES THROUGH `Game:draw`, NOT `OverworldState:draw`.
    --
    -- The first version of this called the state's own `draw` into a canvas,
    -- the way the battle harness does, and got a BLACK FRAME -- not even the
    -- player.  `Game:_draw` is what sizes the UI surface, picks the visible
    -- base, runs the world pass and presents it; the state's `draw` is one
    -- step inside that and paints into a surface nobody had set up.  A
    -- harness that skips it is not testing what the player sees.
    print("party after:  " .. partyHp())
    -- where the player ended up (map, cell, facing)
    if OW and OW.player then
      print(("[pos] %s (%s,%s) facing=%s surfing=%s"):format(tostring(OW.map and OW.map.id), tostring(OW.player.cellX),
        tostring(OW.player.cellY), tostring(OW.player.facing), tostring(OW.player.surfing)))
    end
    -- SHOW_VARS=0x40D7,0x40D9: the story vars a scene was meant to set
    for v in (os.getenv("SHOW_VARS") or ""):gmatch("[^,]+") do
      local G4 = require("src.script.Gen4Commands")
      local id = tonumber(v)
      print(("var %s = %s"):format(v, tostring(id and G4.getVar and G4.getVar(Game.save, id))))
    end
    -- DUMPNPCS=1: every object on the map and whether it stands there
    if os.getenv("GIFT") then
      local MG = require("src.pokemon.Gen4MysteryGift")
      local st = MG.state(Game.save)
      print(("[gift] after: waiting %d, Member Card %s, Oak's Letter %s, Azure Flute %s, var 4043=%s 4044=%s 4045=%s"):format(
        #st.waiting, tostring((Game.save.inventory or {})[454]), tostring((Game.save.inventory or {})[452]),
        tostring((Game.save.inventory or {})[455]), tostring((Game.save.gen4Vars or {})[0x4043]),
        tostring((Game.save.gen4Vars or {})[0x4044]), tostring((Game.save.gen4Vars or {})[0x4045])))
    end
    if os.getenv("DUMPNPCS") then
      for _, n in ipairs(OW.npcs or {}) do
        local d = n.def or {}
        print(("[npc] local %s %s at (%s,%s) hidden=%s"):format(tostring(d.localId or n.localId),
          tostring(d.spriteName or d.sprite), tostring(n.cellX), tostring(n.cellY), tostring(n.hidden)))
      end
    end
    _G.__owHarness = { game = Game, ow = OW, tag = TAG }
  end, debug.traceback)
  if not ok then
    _G.__owHarnessFailed=true
    print("FAILED:\n" .. tostring(err))
  end
end

-- One real frame, captured after it is presented.
local shot = false
function love.draw()
  local h = _G.__owHarness
  if not h then love.event.quit(_G.__owHarnessFailed and 1 or 0) return end
  local okD, errD = pcall(h.game.draw, h.game)
  if not okD then print("draw raised: " .. tostring(errD));love.event.quit(1);return end
  if os.getenv('DUMP_SECOND_SCREEN') and h.game.secondScreenCanvas then
    h.game.secondScreenCanvas:newImageData():encode('png','ow_'..h.tag..'_lower.png')
    print('[screen] lower canvas '..tostring(h.game.secondScreenDrawnThisFrame))
  end
  if not shot then
    shot = true
    love.graphics.captureScreenshot(function(imageData)
      imageData:encode("png", "ow_" .. h.tag .. ".png")
      print("wrote ow_" .. h.tag .. ".png")
      love.event.quit()
    end)
  end
end
