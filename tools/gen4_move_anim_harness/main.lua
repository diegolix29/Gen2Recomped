-- tools/gen4_move_anim_harness/main.lua
--
-- A GEN 4 MOVE ANIMATION, PLAYED IN A HEADLESS BATTLE AND SAVED AS A FRAME
-- SHEET. Built on tools/gen4_battle_harness (same lifecycle: Data:load,
-- Font.load, SaveData.newGame, BattleState.newWild, enter), then for each move
-- in MOVES it starts the move's program on `battle.gen4Anim` exactly the way
-- BattleState does (duration() then update() per frame) and draws the whole
-- battle screen every STEP frames into one sheet per move.
--
--   POKEPORT_DATA_DIR=G:/Gen2Recomped/platinum/data/generated \
--   POKEPORT_ASSET_ROOT=G:/Gen2Recomped/platinum \
--   OUT_DIR=G:/Gen2Recomped/scratch_claude/moveanim/shots \
--   MOVES=33,52,85 STEP=4 COLS=8 SIDE=player \
--     love tools/gen4_move_anim_harness
--
-- | var          | default  | meaning                                          |
-- |--------------|----------|--------------------------------------------------|
-- | MOVES        | 33       | comma list of move ids                           |
-- | STEP         | 4        | draw every STEP-th frame                         |
-- | COLS         | 8        | frames per sheet row                             |
-- | MAXFRAMES    | 160      | stop a sheet after this many animation frames    |
-- | SIDE         | player   | who attacks: player or enemy                     |
-- | SPECIES/PARTY| 396/393  | foe / player Pokemon                             |
-- | VERSION      | platinum | game version                                     |
-- | ROM          | --       | decode the programs from this ROM in memory      |
-- | OUT_DIR      | --       | where the PNGs go (MUST EXIST; LÖVE segfaults)   |
-- | TRACE        | --       | print the channels per frame                     |

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

-- Programs decoded from the cartridge in memory, for a cache written before a
-- decoder fix (HGSS's three extra opcodes).
local function programsFromRom(path)
  local NdsRom = require("src.import.NdsRom")
  local Narc = require("src.import.NarcArchive")
  local Anim = require("src.import.Gen4MoveAnim")
  local rom = assert(NdsRom.open(path))
  local bytes = rom:read("/wazaeffect/we.arc") or rom:read("/a/0/1/0")
  local arc = assert(Narc.parse(bytes))
  local programs = {}
  for index = 0, arc.count - 1 do
    local decoded = Anim.decode(arc:get(index))
    if decoded then
      local code, wordAt = {}, {}
      for i, row in ipairs(decoded) do
        local ins = { row.op }
        for j = 1, #row.args do ins[j + 1] = row.args[j] end
        code[i], wordAt[i] = ins, row.at
      end
      programs[index] = { code = code, wordAt = wordAt }
    end
  end
  return { programs = programs, count = arc.count }
end

function love.load()
  local ok, err = xpcall(function()
    local GameVersion = require("src.core.GameVersion")
    GameVersion.set(os.getenv("VERSION") or "platinum")
    local assetRoot = os.getenv("POKEPORT_ASSET_ROOT")
    if assetRoot then installAssetRoot(assetRoot) end

    local Data = require("src.core.Data")
    Data:load()
    if os.getenv("ROM") then Data.gen4_move_anims = programsFromRom(os.getenv("ROM")) end
    require("src.render.Font").load(Data)

    local Pokemon = require("src.pokemon.Pokemon")
    local SaveData = require("src.core.SaveData")
    local BattleState = require("src.battle.BattleState")
    local Game = require("src.core.Game")
    Game.data = Data
    Game.save = SaveData.newGame(Game.bootConfig and Game:bootConfig() or {})
    Game.save.party = { Pokemon.new(Data, tonumber(os.getenv("PARTY") or "393"), 30) }
    local battle = BattleState.newWild(Game, tonumber(os.getenv("SPECIES") or "396"), 30)
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
    local anim = battle.gen4Anim
    assert(anim, "no gen4Anim on the battle (cache has no gen4_move_anims?)")
    anim.onSound = nil

    local step = tonumber(os.getenv("STEP") or "4")
    local cols = tonumber(os.getenv("COLS") or "8")
    local maxFrames = tonumber(os.getenv("MAXFRAMES") or "160")
    local attackerIsPlayer = (os.getenv("SIDE") or "player") ~= "enemy"
    local font = love.graphics.newFont(10)
    for _, move in ipairs(split(os.getenv("MOVES") or "33")) do
      local total = anim:duration(move, attackerIsPlayer)
      battle.gen4AnimPlaying = true
      battle.gen4AnimAttackerIsPlayer = attackerIsPlayer
      local shots = {}
      local f = 0
      local function snap()
        local c = love.graphics.newCanvas(W, H)
        love.graphics.setCanvas(c)
        love.graphics.clear(0, 0, 0, 1)
        local okD, errD = pcall(battle.draw, battle)
        love.graphics.setCanvas()
        if not okD then print("draw raised: " .. tostring(errD)) end
        shots[#shots + 1] = { canvas = c, frame = f }
      end
      snap()
      while f < math.min(total + 2, maxFrames) do
        local live = anim:update()
        f = f + 1
        if os.getenv("TRACE") then
          local s1, s2 = anim.state[true], anim.state[false]
          print(("f%3d pl dx=%s dy=%s sx=%.2f sy=%.2f rot=%.2f a=%.2f hid=%s | en dx=%s dy=%s sx=%.2f sy=%.2f rot=%.2f a=%.2f hid=%s | em=%d sp=%d bg=%s wash=%s"):format(
            f, s1.dx, s1.dy, s1.sx, s1.sy, s1.rot or 0, s1.alpha or 1, tostring(s1.hidden),
            s2.dx, s2.dy, s2.sx, s2.sy, s2.rot or 0, s2.alpha or 1, tostring(s2.hidden),
            anim:emitterCount(), anim:spriteCount(), tostring(anim.bgLayer and anim.bgLayer.id),
            tostring(anim.screenFlash and anim.screenFlash[4])))
        end
        if f % step == 0 then snap() end
        if not live then break end
      end
      battle.gen4AnimPlaying = false
      local rows = math.ceil(#shots / cols)
      local sheet = love.graphics.newCanvas(cols * W, rows * (H + 12))
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
      love.graphics.setCanvas()
      local missing = {}
      for _, row in ipairs(anim:missing()) do missing[#missing + 1] = row.what .. "x" .. row.count end
      print(("[move %s] %d frames (duration %d), %d shots; gaps: %s"):format(
        tostring(move), f, total, #shots, #missing > 0 and table.concat(missing, ", ") or "none"))
      local name = ("move_%s_%03d_%s.png"):format(os.getenv("TAG") or os.getenv("VERSION") or "platinum",
                                                 tonumber(move) or 0, attackerIsPlayer and "pl" or "en")
      local data = sheet:newImageData():encode("png"):getString()
      if OUT then
        local file = assert(io.open(OUT .. "/" .. name, "wb"))
        file:write(data); file:close()
      else
        love.filesystem.write(name, data)
      end
    end
  end, debug.traceback)
  if not ok then print("FAILED:\n" .. tostring(err)) end
  love.event.quit(ok and 0 or 1)
end

function love.draw() end
