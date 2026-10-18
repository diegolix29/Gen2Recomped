-- tools/gen3_trade_harness/main.lua
--
-- THE GEN 3 IN-GAME TRADE, RUN AND PHOTOGRAPHED.
--
-- Three modes, all against an imported Emerald or FireRed cache:
--
--   MODE=extract  run src/import/Gen3TradeArt.lua against the cartridge and
--                 write gen3_trade_art.lua + assets/generated/trade/*.png
--                 straight into an EXISTING cache (no full re-import)
--   MODE=scene    push src/ui/Gen3TradeAnim.lua for trade TRADE (0-based,
--                 the script's 0x8004) with a party mon of the requested
--                 species, run it to the end pressing A when it waits, and
--                 save a picture at each tick in SHOTS plus a contact sheet
--   MODE=script   the real thing: the overworld at MAP/X/Y facing FACING,
--                 A pressed every PRESS ticks, so the NPC's own script runs
--                 GetInGameTradeSpeciesInfo, the party picker, specials 256
--                 and 257 and the thank-you line
--
--   VERSION=emerald MODE=scene TRADE=0 SHOTS=20,100,... \
--     "C:/Program Files/LOVE/lovec.exe" tools/gen3_trade_harness
--
-- Env: VERSION, CACHE (default G:/Gen2Recomped/<version>), ROM, OUT (default
-- G:/Gen2Recomped/scratch_claude/gen3trade -- the C: drive is full), TAG,
-- TRADE, SHOTS, TICKS, MAP, X, Y, FACING, PRESS, PARTY (species ids,
-- comma-separated), LEVEL.
--
-- Pictures are written with io.* to OUT, never to LOVE's save directory.

package.path = love.filesystem.getSource() .. "/../../?.lua;"
            .. love.filesystem.getSource() .. "/../../?/init.lua;" .. package.path

local VERSION = os.getenv("VERSION") or "emerald"
local CACHE = os.getenv("CACHE") or ("G:/Gen2Recomped/" .. VERSION)
local OUT = os.getenv("OUT") or "G:/Gen2Recomped/scratch_claude/gen3trade"
local TAG = os.getenv("TAG") or (VERSION .. "_" .. (os.getenv("MODE") or "scene"))
local ROMS = {
  emerald = "Pokemon - Emerald Version (USA, Europe).gba",
  firered = "Pokemon - FireRed Version (USA, Europe).gba",
}

local function writeFile(path, bytes)
  local f = assert(io.open(path, "wb"))
  f:write(bytes)
  f:close()
end

local function mkdirs(path)
  local acc = ""
  for part in path:gmatch("[^/]+") do
    acc = (acc == "" and part) or (acc .. "/" .. part)
    if not acc:match("^%a:$") then os.execute(('mkdir "%s" 2>nul'):format(acc:gsub("/", "\\"))) end
  end
end

local function savePng(imageData, name)
  local fd = imageData:encode("png")
  writeFile(OUT .. "/" .. name, fd:getString())
end

-- ---------------------------------------------------------------------------
local function extract()
  local root = love.filesystem.getSource() .. "/../../"
  local romPath = os.getenv("ROM") or (root .. ROMS[VERSION])
  local f = assert(io.open(romPath, "rb"), "no ROM at " .. romPath)
  local romData = f:read("*a"); f:close()
  local mf = assert(io.open(root .. "tools/rom_manifest_" .. VERSION .. ".json", "rb"))
  local manifest = require("src.link.Json").decode(mf:read("*a")); mf:close()
  local Gen3 = require("src.import.RomExtractorGen3")
  local x = Gen3.new(romData, VERSION, manifest, nil)
  -- the species table the stage reads noFlip against: the cache's own
  local okP, pokemon = pcall(dofile, CACHE .. "/data/generated/pokemon.lua")
  x._pokemon = okP and pokemon or {}
  x.write = function(_, name, value)
    local text = require("src.import.LuaWriter").encode(value)
    writeFile(CACHE .. "/data/generated/" .. name .. ".lua", text)
    print("wrote " .. CACHE .. "/data/generated/" .. name .. ".lua")
  end
  mkdirs(CACHE .. "/assets/generated/trade")
  x.saveImage = function(_, image, rel)
    writeFile(CACHE .. "/assets/generated/" .. rel, image:encode("png"):getString())
  end
  local rec = require("src.import.Gen3TradeArt").extract(x)
  if not rec then print("EXTRACT FAILED (see the warning above)") return end
  print(("extracted %s: %s"):format(rec.key, rec.source))
  for role, text in pairs(rec.text) do print(("  %s = %q"):format(role, text)) end
  local n = 0
  for _ in pairs(rec.noFlip) do n = n + 1 end
  print(("  %d bounce steps, %d signal steps, %d noFlip species, ball colour %04X")
    :format(#rec.velocity, #rec.signalParams, n, rec.ballFadeColor))
end

-- ---------------------------------------------------------------------------
-- the engine, brought up in Game:boot's order (see gen4_overworld_harness)
local Game, Data
local held, pressA, keyNow = nil, false, nil

local function boot()
  require("src.core.GameVersion").set(VERSION)
  -- pictures straight from the cache's assets folder
  local Assets = require("src.render.Assets")
  local realImage, cache = Assets.image, {}
  Assets.image = function(path, ...)
    if type(path) == "string" and not cache[path] then
      local fh = io.open(CACHE .. "/" .. path, "rb")
      if fh then
        local bytes = fh:read("*a"); fh:close()
        local okI, img = pcall(love.graphics.newImage, love.filesystem.newFileData(bytes, path))
        if okI then img:setFilter("nearest", "nearest"); cache[path] = img end
      end
    end
    return cache[path] or realImage(path, ...)
  end
  Data = require("src.core.Data")
  Data:load()
  print(("[boot] %s: gen3_trade_art %s"):format(VERSION,
    Data.gen3_trade_art and Data.gen3_trade_art.key or "MISSING"))
  local SaveData = require("src.core.SaveData")
  Game = require("src.core.Game")
  Game.data = Data
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
  Game.input = {
    wasPressed = function(_, k) return (pressA and k == "a") or (keyNow ~= nil and k == keyNow) end,
    isDown = function(_, k) return held ~= nil and k == held end,
    wasReleased = function() return false end,
  }
  -- the party
  local Pokemon = require("src.pokemon.Pokemon")
  local level = tonumber(os.getenv("LEVEL") or "10")
  Game.save.party = {}
  for id in (os.getenv("PARTY") or ""):gmatch("[^,]+") do
    local sp = tonumber(id) or id
    Game.save.party[#Game.save.party + 1] = Pokemon.new(Data, sp, level)
  end
end

-- a 240x160 picture of what Game:draw would present, cropped to the GBA
local function shot(name)
  local w, h = love.graphics.getDimensions()
  local canvas = love.graphics.newCanvas(w, h)
  love.graphics.push("all")
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
  if not okD then print("[shot] draw raised: " .. tostring(errD)) return nil end
  local data = canvas:newImageData()
  savePng(data, name)
  return data
end

-- the trade screen's own canvas, exactly 240x160 at 1x
local function sceneShot(screen, name)
  screen:render()
  local data = screen.canvas:newImageData()
  savePng(data, name)
  return data
end

local function contactSheet(list, name)
  if #list == 0 then return end
  local cols = 5
  local rows = math.ceil(#list / cols)
  local sheet = love.graphics.newCanvas(cols * 244, rows * 176)
  love.graphics.push("all")
  love.graphics.setCanvas(sheet)
  love.graphics.clear(0.12, 0.12, 0.14, 1)
  for i, s in ipairs(list) do
    local img = love.graphics.newImage(s.data)
    img:setFilter("nearest", "nearest")
    local x, y = ((i - 1) % cols) * 244 + 2, math.floor((i - 1) / cols) * 176 + 2
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(img, x, y, 0, 240 / img:getWidth(), 160 / img:getHeight())
    love.graphics.print(s.label, x, y + 161)
  end
  love.graphics.setCanvas()
  love.graphics.pop()
  savePng(sheet:newImageData(), name)
  print("wrote " .. OUT .. "/" .. name)
end

local STATE_NAMES = {}

local function sceneMode()
  boot()
  local Gen3TradeAnim = require("src.ui.Gen3TradeAnim")
  for k, v in pairs(Gen3TradeAnim.STATES) do STATE_NAMES[v] = k end
  local trades = Data.constants and Data.constants.gen3Trades or {}
  local index = tonumber(os.getenv("TRADE") or "0")
  local trade = trades[index + 1]
  assert(trade, "no trade " .. index)
  if #Game.save.party == 0 then
    Game.save.party[1] = require("src.pokemon.Pokemon").new(Data, trade.request,
                                                            tonumber(os.getenv("LEVEL") or "10"))
  end
  -- what special 256 builds, through the special itself
  local Gen3Commands = require("src.script.Gen3Commands")
  Game.save.vars = Game.save.vars or {}
  local ctx = { game = Game, save = Game.save, data = Data }
  local setVar = Gen3Commands.setVar or function(save, id, v)
    save.vars = save.vars or {}; save.vars[id] = v
  end
  pcall(setVar, Game.save, 0x8004, index)
  pcall(setVar, Game.save, 0x8005, 0)
  Gen3Commands.SPECIALS[256](ctx)
  local received = ctx.g3TradeMon or require("src.pokemon.Pokemon").new(Data, trade.species, 10)
  -- RECEIVE=KADABRA: receive something that evolves by trade, to run the
  -- STATE_TRY_EVOLUTION path (TradeEvolutionScene, then back to the scene)
  if os.getenv("RECEIVE") then
    received = require("src.pokemon.Pokemon").new(Data, os.getenv("RECEIVE"), 20)
    received.nickname = trade.nickname
  end
  local given = Game.save.party[1]
  print(("[trade %d] %s (%s) for %s %q from %s"):format(index, tostring(given.species),
    tostring(given.nickname), tostring(trade.species), tostring(trade.nickname), tostring(trade.otName)))
  local finished = false
  local screen = Gen3TradeAnim.new(Game, {
    trade = trade, given = given, received = received, slot = 1,
    onTrade = function()
      Game.save.party[1] = received
      print("[trade] TradeMons at frame " .. tostring(_G.__frame))
      local Evolution = require("src.pokemon.Evolution")
      local target, row = Evolution.pendingFor(Game, received, { kind = "trade" })
      if not target then return nil end
      print("[trade] evolves into " .. tostring(target))
      return function(resume)
        Evolution.evolve(Game, received, target, function()
          print("[trade] evolution handed back at frame " .. tostring(_G.__frame))
          resume()
        end, "TRADE", row)
      end
    end,
    onDone = function() finished = true end,
  })
  Game.stack:push(screen)
  local shots = {}
  local want = {}
  for t in (os.getenv("SHOTS") or ""):gmatch("%d+") do want[tonumber(t)] = true end
  local every = tonumber(os.getenv("EVERY") or "0")
  local ticks = tonumber(os.getenv("TICKS") or "4000")
  local lastState
  for i = 1, ticks do
    _G.__frame = i
    -- press A only when the scene is waiting for it (STATE_END_LINK_TRADE)
    local top = Game.stack.states[#Game.stack.states]
    pressA = (screen.state == Gen3TradeAnim.STATES.END_LINK_TRADE or top ~= screen)
             and (i % 20 == 0)
    local okU, errU = pcall(Game.stack.update, Game.stack, 1 / 60)
    if not okU then print(("update raised on tick %d: %s"):format(i, tostring(errU))) break end
    if screen.state ~= lastState then
      print(("[f%05d] state %s (%s)"):format(i, tostring(screen.state),
        tostring(STATE_NAMES[screen.state] or "?")))
      lastState = screen.state
    end
    if not finished and (want[i] or (every > 0 and i % every == 0)) then
      local data = sceneShot(screen, ("%s_%05d.png"):format(TAG, i))
      shots[#shots + 1] = { data = data, label = ("f%d %s"):format(i,
        tostring(STATE_NAMES[screen.state] or screen.state)) }
    end
    if finished then print(("[done] the screen handed back at tick %d"):format(i)) break end
  end
  contactSheet(shots, TAG .. "_sheet.png")
end

local function scriptMode()
  boot()
  local Gen3TradeAnim = require("src.ui.Gen3TradeAnim")
  for k, v in pairs(Gen3TradeAnim.STATES) do STATE_NAMES[v] = k end
  local OW = require("src.world.OverworldController")
  Game.stack:push(OW, os.getenv("MAP"), tonumber(os.getenv("X") or "0"),
                  tonumber(os.getenv("Y") or "0"), os.getenv("FACING") or "up")
  local pressEvery = tonumber(os.getenv("PRESS") or "30")
  local ticks = tonumber(os.getenv("TICKS") or "6000")
  local want = {}
  for t in (os.getenv("SHOTS") or ""):gmatch("%d+") do want[tonumber(t)] = true end
  local every = tonumber(os.getenv("EVERY") or "0")
  local shots, lastTop, lastState = {}, nil, nil
  local before = {}
  for i, m in ipairs(Game.save.party) do before[i] = m.species end
  print("[party before] " .. table.concat(before, ","))
  for i = 1, ticks do
    _G.__frame = i
    pcall(require("src.core.Music").update, Game.data)
    local top = Game.stack.states[#Game.stack.states]
    -- A on the schedule, except while the trade scene runs: there it is
    -- pressed only at STATE_END_LINK_TRADE, the one place the scene reads it
    local inScene = getmetatable(top) == Gen3TradeAnim
    if inScene then
      pressA = top.state == Gen3TradeAnim.STATES.END_LINK_TRADE and i % 20 == 0
    else
      pressA = pressEvery > 0 and i % pressEvery == 0
    end
    local okU, errU = pcall(Game.stack.update, Game.stack, 1 / 60)
    if not okU then print(("update raised on tick %d: %s"):format(i, tostring(errU))) break end
    top = Game.stack.states[#Game.stack.states]
    local mt = getmetatable(top)
    local name = (mt == Gen3TradeAnim and "Gen3TradeAnim")
      or (top and (top.name or top.kind))
      or (top and tostring(require("src.core.StateStack").describe(top)):match("([%w_]+)%.lua"))
      or tostring(mt)
    if name ~= lastTop then
      print(("[t%05d] top = %s"):format(i, tostring(name)))
      lastTop = name
    end
    if mt == Gen3TradeAnim and top.state ~= lastState then
      lastState = top.state
      print(("[t%05d]   trade state %s (%s)"):format(i, tostring(top.state),
        tostring(STATE_NAMES[top.state] or "?")))
    end
    if want[i] or (every > 0 and i % every == 0) then
      local data = shot(("%s_%05d.png"):format(TAG, i))
      if data then shots[#shots + 1] = { data = data, label = ("t%d %s"):format(i, tostring(name)) } end
    end
  end
  local after = {}
  for i, m in ipairs(Game.save.party) do
    after[i] = ("%s(%s, happiness %s)"):format(tostring(m.species), tostring(m.nickname), tostring(m.happiness))
  end
  print("[party after] " .. table.concat(after, ", "))
  local sb = Game.stringBuffers or {}
  print(("[buffers] VAR1=%s VAR2=%s"):format(tostring(sb[1]), tostring(sb[2])))
  contactSheet(shots, TAG .. "_sheet.png")
end

function love.load()
  local ok, err = xpcall(function()
    mkdirs(OUT)
    local mode = os.getenv("MODE") or "scene"
    if mode == "extract" then extract()
    elseif mode == "script" then scriptMode()
    else sceneMode() end
  end, debug.traceback)
  if not ok then print("FAILED:\n" .. tostring(err)) end
  love.event.quit()
end
