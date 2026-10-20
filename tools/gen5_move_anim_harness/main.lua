-- tools/gen5_move_anim_harness/main.lua
--
-- A BLACK / WHITE MOVE ANIMATION, PLAYED IN A HEADLESS BATTLE AND SAVED AS A
-- FRAME SHEET. The Gen 5 twin of tools/gen4_move_anim_harness: Data:load,
-- a wild battle, then for each move in MOVES its program is started on
-- `battle.gen4Anim` (the BW player sits in the Sinnoh slot) exactly the way BattleState starts it (duration() then
-- update() per frame) and the whole battle screen is drawn every STEP frames.
--
--   POKEPORT_DATA_DIR=G:/Gen2Recomped/black/data/generated \
--   POKEPORT_ASSET_ROOT=G:/Gen2Recomped/black VERSION=black \
--   OUT_DIR=G:/Gen2Recomped/scratch_claude/moveanim/bw \
--   MOVES=33,10,52 STEP=4 COLS=8 SIDE=player \
--     lovec tools/gen5_move_anim_harness
--
-- | var          | default  | meaning                                          |
-- |--------------|----------|--------------------------------------------------|
-- | MOVES        | 33       | comma list of move ids                           |
-- | STEP         | 4        | draw every STEP-th frame                         |
-- | COLS         | 8        | frames per sheet row                             |
-- | MAXFRAMES    | 200      | stop a sheet after this many animation frames    |
-- | SIDE         | player   | who attacks: player or enemy                     |
-- | SPECIES/PARTY| 506/495  | foe / player Pokemon                             |
-- | ROM          | --       | decode the programs/particles from this ROM      |
-- | OUT_DIR      | --       | where the PNGs go (MUST EXIST; LOVE segfaults)   |
-- | TRACE        | --       | print the channels per frame                     |
-- | STILL        | --       | just save the idle battle screen                 |
-- | DOUBLE       | --       | a double battle (PARTY2 / SPECIES2 the partners) |
-- | ATK / DEF    | 0 / 1    | a double's attacker and defender positions (0-3)  |

local W, H = 256, 192
local OUT = os.getenv("OUT_DIR")

local function split(s)
  local out = {}
  for v in tostring(s or ""):gmatch("[^,]+") do out[#out + 1] = tonumber(v) or v end
  return out
end

local function installAssetRoot(assetRoot)
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
  local realData, heldData = Assets.imageData, {}
  Assets.imageData = function(path, ...)
    if type(path) == "string" and not heldData[path] then
      local f = io.open(assetRoot .. "/" .. path, "rb")
      if f then
        local bytes = f:read("*a"); f:close()
        local okD, d = pcall(love.image.newImageData, love.filesystem.newFileData(bytes, path))
        if okD then heldData[path] = d end
      end
    end
    return heldData[path] or realData(path, ...)
  end
end

local function save(canvas, name)
  local data = canvas:newImageData():encode("png"):getString()
  if OUT then
    local file = assert(io.open(OUT .. "/" .. name, "wb"))
    file:write(data); file:close()
  else
    love.filesystem.write(name, data)
  end
end

function love.load()
  local ok, err = xpcall(function()
    local GameVersion = require("src.core.GameVersion")
    GameVersion.set(os.getenv("VERSION") or "black")
    local assetRoot = os.getenv("POKEPORT_ASSET_ROOT")
    if assetRoot then installAssetRoot(assetRoot) end

    local Data = require("src.core.Data")
    Data:load()
    if os.getenv("ROM") then
      -- the programs and particles straight from the cartridge, for a cache
      -- written before the move-animation stage existed
      local NdsRom = require("src.import.NdsRom")
      local rom = assert(NdsRom.open(os.getenv("ROM")))
      local Ext = require("src.import.Gen5MoveAnimData")
      Data.gen5_move_anims = Ext.runtime(rom)
    end
    require("src.render.Font").load(Data)
    if os.getenv("CAMEXP") then dofile(os.getenv("CAMEXP")) end

    local Pokemon = require("src.pokemon.Pokemon")
    local SaveData = require("src.core.SaveData")
    local BattleState = require("src.battle.BattleState")
    local Game = require("src.core.Game")
    Game.data = Data
    Game.save = SaveData.newGame(Game.bootConfig and Game:bootConfig() or {})
    Game.save.party = { Pokemon.new(Data, tonumber(os.getenv("PARTY") or "495"), 30) }
    -- WIDE=1: BATTLE LAYOUT = WIDE in a 16:9 window
    if os.getenv("WIDE") then
      Game.save.options = Game.save.options or {}
      Game.save.options.battleLayout = "wide"
      pcall(love.window.setMode, 854, 480)
    end
    -- PMOVES=144,33: the lead's moves (FIGHT=1 uses the first)
    if os.getenv("PMOVES") then
      local mv = {}
      for id in tostring(os.getenv("PMOVES")):gmatch("%d+") do
        local d = Data.moves[tonumber(id)]
        mv[#mv + 1] = { id = tonumber(id), pp = d and d.pp or 10 }
      end
      Game.save.party[1].moves = mv
    end
    -- DOUBLE=1: two of each side (PARTY2 / SPECIES2), the doubles layout
    if os.getenv("DOUBLE") then
      Game.save.party[2] = Pokemon.new(Data, tonumber(os.getenv("PARTY2") or "498"), 30)
    end
    local battle = BattleState.newWild(Game, tonumber(os.getenv("SPECIES") or "506"), 30)
    -- TRAINER=n: a trainer battle instead (a double trainer such as 18, the
    -- Twins, lays out as a double); INTRO=1 saves its intro as a sheet
    if os.getenv("TRAINER") then
      battle = BattleState.newTrainer(Game, tonumber(os.getenv("TRAINER")), 1)
    end
    if os.getenv("DOUBLE") and not os.getenv("TRAINER") then
      battle:makeWildDouble(Pokemon.new(Data, tonumber(os.getenv("SPECIES2") or "504"), 30))
    end
    if battle.enter then pcall(battle.enter, battle) end
    local pressed = false
    Game.input = {
      wasPressed = function(_, k) return pressed and k == "a" end,
      isDown = function() return false end,
      wasReleased = function() return false end,
    }
    local introShots = {}
    for i = 1, tonumber(os.getenv("TICKS") or "400") do
      pressed = (i % 20 == 0)
      pcall(battle.update, battle, 1 / 60)
      if os.getenv("INTRO") and i % tonumber(os.getenv("INTRO_STEP") or "10") == 0 and #introShots < 64 then
        local c = love.graphics.newCanvas(W, H)
        love.graphics.push("all"); love.graphics.setCanvas(c); love.graphics.clear(0, 0, 0, 1)
        pcall(battle.draw, battle); love.graphics.pop()
        introShots[#introShots + 1] = { canvas = c, frame = i }
      end
      if battle.phase == "menu" then break end
    end
    pressed = false
    if os.getenv("INTRO") then
      local cols = 8
      local sheet = love.graphics.newCanvas(cols * W, math.max(1, math.ceil(#introShots / cols)) * (H + 12))
      love.graphics.push("all"); love.graphics.setCanvas(sheet); love.graphics.clear(0.1, 0.1, 0.1, 1)
      for k, sh in ipairs(introShots) do
        local cx, cy = ((k - 1) % cols) * W, math.floor((k - 1) / cols) * (H + 12)
        love.graphics.draw(sh.canvas, cx, cy + 12)
        love.graphics.print(("t%d"):format(sh.frame), cx + 2, cy)
      end
      love.graphics.pop()
      save(sheet, ("intro_%s.png"):format(os.getenv("TAG") or "bw"))
    end

    local function shot()
      -- WIDE=1: the battle's own surface width (Gen4Battle.width)
      local sw = W
      if os.getenv("WIDE") then local okB, GB = pcall(require, "src.battle.Gen4Battle"); if okB then sw = GB.width(battle) end end
      local c = love.graphics.newCanvas(sw, H)
      love.graphics.push("all")
      love.graphics.setCanvas(c)
      love.graphics.clear(0, 0, 0, 1)
      local okD, errD = pcall(battle.draw, battle)
      love.graphics.pop()
      if not okD then print("draw raised: " .. tostring(errD)) end
      return c
    end

    -- FIGHT=1: the REAL path -- choose FIGHT and the first move with the A
    -- button and let BattleState start the animation itself; every frame
    -- the battle is animating is drawn (FIGHT_STEP apart) into one sheet
    if os.getenv("FIGHT") then
      local fstep = tonumber(os.getenv("FIGHT_STEP") or "4")
      -- FIGHT_LINES=1: every battle line as it is shown, in the cartridge's words
      if os.getenv("FIGHT_LINES") then
        local realStart = battle.startMessage
        battle.startMessage = function(self_, item, ...)
          if item and type(item.text) == "string" then
            local T = require("src.battle.Gen5BattleText")
            print("[line] " .. T.translate(self_, item.text):gsub("\n", " "))
          end
          return realStart(self_, item, ...)
        end
      end
      local shots, seen, tick = {}, 0, 0
      local a5 = battle.gen4Anim
      if a5 then
        local realStart = a5.start
        a5.start = function(self_, id, side, ...)
          if not self_.quiet then print(("[fight] start effect %s attackerIsPlayer=%s"):format(tostring(id), tostring(side))) end
          return realStart(self_, id, side, ...)
        end
      end
      for i = 1, tonumber(os.getenv("FIGHT_TICKS") or "3000") do
        pressed = (i % 12 == 0) and not battle.gen4AnimPlaying
        pcall(battle.update, battle, 1 / 60)
        if battle.gen4AnimPlaying then
          seen = seen + 1
          if seen % fstep == 1 and #shots < 64 then shots[#shots + 1] = { canvas = shot(), frame = i } end
        end
        tick = i
      end
      local cols = 8
      local rows = math.max(1, math.ceil(#shots / cols))
      local sheet = love.graphics.newCanvas(cols * W, rows * (H + 12))
      love.graphics.push("all")
      love.graphics.setCanvas(sheet)
      love.graphics.clear(0.1, 0.1, 0.1, 1)
      for k, s in ipairs(shots) do
        local cx, cy = ((k - 1) % cols) * W, math.floor((k - 1) / cols) * (H + 12)
        love.graphics.draw(s.canvas, cx, cy + 12)
        love.graphics.print(("t%d"):format(s.frame), cx + 2, cy)
      end
      love.graphics.pop()
      print(("[fight] %d animating frames over %d ticks, player=%s"):format(seen, tick,
        tostring(battle.gen4Anim and (battle.gen4Anim.gen5 and "gen5" or "gen4"))))
      save(sheet, ("fight_%s.png"):format(os.getenv("TAG") or "bw"))
      save(shot(), ("fight_%s_end.png"):format(os.getenv("TAG") or "bw"))
      return
    end
    -- BAGUI=1: BW's own battle bag screen, keys and taps (bagui.lua)
    if os.getenv("BAGUI") then
      require("bagui").run({ Game = Game, Data = Data, battle = battle, shot = shot, save = save })
      return
    end
    -- BAG=4,17: the battle bag used for real (tools/gen5_move_anim_harness/bag.lua)
    if os.getenv("BAG") then
      require("bag").run({ Game = Game, Data = Data, battle = battle, shot = shot, save = save })
      return
    end
    if os.getenv("STILL") then
      save(shot(), ("still_%s.png"):format(os.getenv("TAG") or "bw"))
      return
    end
    -- CATCH="caught:shakes:itemId" (e.g. 1:3:4): the capture throw through
    -- BattleState:gen4BallChain, every CATCH_STEP-th frame into one sheet
    if os.getenv("CATCH") then
      local c, sh, item = tostring(os.getenv("CATCH")):match("(%d+):(%d+):(%d+)")
      local okC, errC = pcall(battle.gen4BallChain, battle, c == "1", tonumber(sh), tonumber(item))
      local anim5 = battle.gen4Ball
      print(("[catch] chain=%s err=%s anim=%s total=%s"):format(tostring(okC and errC), tostring(not okC and errC or nil),
        anim5 and (anim5.gen5 and "gen5" or "gen4") or "none", tostring(anim5 and anim5:estimate())))
      local cstep = tonumber(os.getenv("CATCH_STEP") or "8")
      local shots = {}
      local total = anim5 and anim5:estimate() or 0
      for f = 0, total + 20 do
        if f % cstep == 0 and #shots < 96 then shots[#shots + 1] = { canvas = shot(), frame = f } end
        if battle.gen4Ball then battle:updateGen4Ball() end
      end
      local cols = 8
      local rows = math.max(1, math.ceil(#shots / cols))
      local sheet = love.graphics.newCanvas(cols * W, rows * (H + 12))
      love.graphics.push("all")
      love.graphics.setCanvas(sheet)
      love.graphics.clear(0.1, 0.1, 0.1, 1)
      for k, s in ipairs(shots) do
        local cx, cy = ((k - 1) % cols) * W, math.floor((k - 1) / cols) * (H + 12)
        love.graphics.draw(s.canvas, cx, cy + 12)
        love.graphics.print(("f%d"):format(s.frame), cx + 2, cy)
      end
      love.graphics.pop()
      local p5 = anim5 and anim5.player
      if p5 then
        local gaps = {}
        for _, row in ipairs(p5:missing()) do gaps[#gaps + 1] = row.what .. "x" .. row.count end
        print("[catch] gaps: " .. (#gaps > 0 and table.concat(gaps, ", ") or "none"))
      end
      save(sheet, ("catch_%s.png"):format(os.getenv("TAG") or "bw"))
      return
    end

    local anim = battle.gen4Anim
    assert(anim and anim.gen5, "no BW move-animation player on the battle (cache has no gen5_move_anims? set ROM=)")
    anim.onSound = nil

    -- DRY=1: every effect 1..559 (and the shared 561..658) run headless; the
    -- frame counts, the longest, and every gap the player reported
    if os.getenv("DRY") then
      local gaps, longest, total, n = {}, {}, 0, 0
      for id = 1, 658 do
        if anim.programs[id] then
          for _, side in ipairs({ true, false }) do
            anim.unsupported = {}
            -- (DOUBLE=1: run each in the doubles layout, the left flanks)
            if os.getenv("DOUBLE") and anim.setLayout then anim:setLayout("double", side and 0 or 1, side and 1 or 0) end
            local f = anim:duration(id, side)
            total, n = total + f, n + 1
            longest[#longest + 1] = { id = id, f = f }
            for _, row in ipairs(anim:missing()) do gaps[row.what] = (gaps[row.what] or 0) + 1 end
          end
        end
      end
      table.sort(longest, function(a, b) return a.f > b.f end)
      print(("[dry] %d runs, mean %.1f frames"):format(n, total / math.max(1, n)))
      for k = 1, 8 do local r = longest[k]; if r then print(("[dry] long: effect %d = %d frames"):format(r.id, r.f)) end end
      local list = {}
      for what, c in pairs(gaps) do list[#list + 1] = { what, c } end
      table.sort(list, function(a, b) return a[2] > b[2] end)
      for _, r in ipairs(list) do print(("[dry] gap %-40s in %d runs"):format(r[1], r[2])) end
      return
    end
    local step = tonumber(os.getenv("STEP") or "4")
    local cols = tonumber(os.getenv("COLS") or "8")
    local maxFrames = tonumber(os.getenv("MAXFRAMES") or "200")
    local attackerIsPlayer = (os.getenv("SIDE") or "player") ~= "enemy"
    local font = love.graphics.newFont(10)
    for _, move in ipairs(split(os.getenv("MOVES") or "33")) do
      -- a double: ATK / DEF are BattleState positions (0 / 2 the player's,
      -- 1 / 3 the foe's); the defaults are each side's left flank
      if os.getenv("DOUBLE") and anim.setLayout then
        local atk = tonumber(os.getenv("ATK") or (attackerIsPlayer and "0" or "1"))
        local def = tonumber(os.getenv("DEF") or (attackerIsPlayer and "1" or "0"))
        anim:setLayout("double", atk, def)
        attackerIsPlayer = atk % 2 == 0
      end
      local total = anim:duration(move, attackerIsPlayer)
      battle.gen4AnimPlaying = true
      battle.gen4AnimAttackerIsPlayer = attackerIsPlayer
      local shots = {}
      local f = 0
      shots[1] = { canvas = shot(), frame = 0 }
      while f < math.min(total + 2, maxFrames) do
        local live = anim:update()
        f = f + 1
        if os.getenv("TRACE") then print(("f%3d %s"):format(f, anim:traceLine())) end
        if f % step == 0 then shots[#shots + 1] = { canvas = shot(), frame = f } end
        if not live then break end
      end
      battle.gen4AnimPlaying = false
      local rows = math.ceil(#shots / cols)
      local sheet = love.graphics.newCanvas(cols * W, rows * (H + 12))
      love.graphics.push("all")
      love.graphics.setCanvas(sheet)
      love.graphics.clear(0.1, 0.1, 0.1, 1)
      love.graphics.setFont(font)
      for i, s in ipairs(shots) do
        local cx = ((i - 1) % cols) * W
        local cy = math.floor((i - 1) / cols) * (H + 12)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(s.canvas, cx, cy + 12)
        love.graphics.print(("f%d"):format(s.frame), cx + 2, cy)
      end
      love.graphics.pop()
      local gaps = {}
      for _, row in ipairs(anim:missing()) do gaps[#gaps + 1] = row.what .. "x" .. row.count end
      print(("[move %s] %d frames (duration %d), %d shots; gaps: %s"):format(
        tostring(move), f, total, #shots, #gaps > 0 and table.concat(gaps, ", ") or "none"))
      save(sheet, ("bw_move_%03d_%s.png"):format(tonumber(move) or 0, attackerIsPlayer and "pl" or "en"))
    end
  end, debug.traceback)
  if not ok then print("FAILED:\n" .. tostring(err)) end
  love.event.quit(ok and 0 or 1)
end

function love.draw() end
