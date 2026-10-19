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
    local battle = BattleState.newWild(Game, tonumber(os.getenv("SPECIES") or "506"), 30)
    if battle.enter then pcall(battle.enter, battle) end
    local pressed = false
    Game.input = {
      wasPressed = function(_, k) return pressed and k == "a" end,
      isDown = function() return false end,
      wasReleased = function() return false end,
    }
    for i = 1, tonumber(os.getenv("TICKS") or "400") do
      pressed = (i % 20 == 0)
      pcall(battle.update, battle, 1 / 60)
      if battle.phase == "menu" then break end
    end
    pressed = false

    local function shot()
      local c = love.graphics.newCanvas(W, H)
      love.graphics.push("all")
      love.graphics.setCanvas(c)
      love.graphics.clear(0, 0, 0, 1)
      local okD, errD = pcall(battle.draw, battle)
      love.graphics.pop()
      if not okD then print("draw raised: " .. tostring(errD)) end
      return c
    end

    if os.getenv("STILL") then
      save(shot(), ("still_%s.png"):format(os.getenv("TAG") or "bw"))
      return
    end

    local anim = battle.gen4Anim
    assert(anim and anim.gen5, "no BW move-animation player on the battle (cache has no gen5_move_anims? set ROM=)")
    anim.onSound = nil

    local step = tonumber(os.getenv("STEP") or "4")
    local cols = tonumber(os.getenv("COLS") or "8")
    local maxFrames = tonumber(os.getenv("MAXFRAMES") or "200")
    local attackerIsPlayer = (os.getenv("SIDE") or "player") ~= "enemy"
    local font = love.graphics.newFont(10)
    for _, move in ipairs(split(os.getenv("MOVES") or "33")) do
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
