-- Gen 1 / Gen 2 trade-cinematic harness.
--
-- Run from the repository root (never `lovec .`):
--   "C:/Program Files/LOVE/lovec.exe" tools/gen12_trade_harness
--
-- Env:
--   TRADE_OUT   output dir (default G:/Gen2Recomped/scratch_claude/gen12trade)
--   TRADE_ROMS  dir holding the Red/Blue/Yellow .gb files (default
--               $TRADE_OUT/roms); Gold/Silver/Crystal are read from the repo
--               root, where the launcher finds them
--   TRADE_ONLY  comma list of versions (default red,blue,yellow,gold,silver,
--               crystal)
--   TRADE_MODE  "extract" (art only) or "play" (default: extract + play)
--
-- For every version: runs the importer's own trade-art stage
-- (src/import/Gen1TradeArt.lua / Gen2TradeArt.lua) against the ROM into
-- $TRADE_OUT/cache_<version>, then loads that version's installed cache
-- (G:/Gen2Recomped[/<version>]) and plays a real in-game trade through the
-- script command the map scripts call (Commands.trade / Commands.g2_trade),
-- answering YES and picking the wanted mon, and saves a frame sheet of the
-- cinematic to $TRADE_OUT/<version>_*.png.

local repo = love.filesystem.getWorkingDirectory():gsub("\\", "/")
local OUT = (os.getenv("TRADE_OUT") or "G:/Gen2Recomped/scratch_claude/gen12trade")
  :gsub("\\", "/")
local ROMS = (os.getenv("TRADE_ROMS") or (OUT .. "/roms")):gsub("\\", "/")
local MODE = os.getenv("TRADE_MODE") or "all"

local VERSIONS = {
  red = { gen = 1, rom = ROMS .. "/Pokemon - Red Version (USA, Europe) (SGB Enhanced).gb",
          manifest = "tools/rom_manifest.json", cache = "G:/Gen2Recomped" },
  blue = { gen = 1, rom = ROMS .. "/Pokemon - Blue Version (USA, Europe) (SGB Enhanced).gb",
           manifest = "tools/rom_manifest_blue.json", cache = "G:/Gen2Recomped/blue" },
  yellow = { gen = 1, rom = ROMS .. "/Pokemon - Yellow Version - Special Pikachu Edition (USA, Europe) (GBC,SGB Enhanced).gb",
             manifest = "tools/rom_manifest_yellow.json", cache = "G:/Gen2Recomped/yellow" },
  gold = { gen = 2, rom = repo .. "/Pokemon - Gold Version (USA, Europe) (SGB Enhanced) (GB Compatible).gbc",
           manifest = "tools/rom_manifest_gold.json", cache = "G:/Gen2Recomped/gold" },
  silver = { gen = 2, rom = repo .. "/Pokemon - Silver Version (USA, Europe) (SGB Enhanced) (GB Compatible).gbc",
             manifest = "tools/rom_manifest_silver.json", cache = "G:/Gen2Recomped/silver" },
  crystal = { gen = 2, rom = repo .. "/Pokemon - Crystal Version (USA, Europe) (Rev 1).gbc",
              manifest = "tools/rom_manifest_crystal.json", cache = "G:/Gen2Recomped/crystal" },
}
local ORDER = {}
for v in (os.getenv("TRADE_ONLY") or "red,blue,yellow,gold,silver,crystal"):gmatch("[^,]+") do
  ORDER[#ORDER + 1] = v
end

local log = {}
local function say(fmt, ...)
  local line = select("#", ...) > 0 and fmt:format(...) or fmt
  print(line)
  log[#log + 1] = line
end

local function readFile(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local function writeFile(path, bytes)
  local f = assert(io.open(path, "wb"))
  f:write(bytes)
  f:close()
end

local function fileImage(path)
  local bytes = readFile(path)
  if not bytes then return nil end
  return love.image.newImageData(love.filesystem.newFileData(bytes, path))
end

-- ------------------------------------------------------------------ extract

local function extract(version)
  local spec = VERSIONS[version]
  local raw = readFile(spec.rom)
  if not raw then say("%s: ROM missing at %s", version, spec.rom) return nil end
  local manifest = require("src.link.Json").decode(assert(readFile(repo .. "/" .. spec.manifest)))
  local CacheFs = require("src.import.CacheFs")
  local root = OUT .. "/cache_" .. version
  CacheFs.mkdirReal(OUT)
  CacheFs.mkdirReal(root)
  CacheFs.root = function() return root end
  CacheFs.prefix = ""
  require("src.core.GameVersion").set(version)
  local art
  if spec.gen == 1 then
    local e = require("src.import.RomExtractor").new(raw, manifest)
    art = require("src.import.Gen1TradeArt").extract(e)
  else
    local e = require("src.import.RomExtractorGen2").new(raw, version, manifest)
    e.readSourceTable = function(self, name)
      return assert(loadfile(repo .. "/" .. self.sourceDir .. "/" .. name .. ".lua"))()
    end
    art = require("src.import.Gen2TradeArt").extract(e)
  end
  say("%s: trade art %s -> %s", version, art and "extracted" or "NOT extracted", root)
  return art, root
end

-- ------------------------------------------------------------------ play

local function loadCache(version, spec, art, artRoot)
  local Data = require("src.core.Data")
  local gen = spec.cache .. "/data/generated/"
  for _, key in ipairs({ "font", "charmap", "sprites", "text", "palettes",
                         "pokemon", "moves", "type_chart", "items", "constants",
                         "maps", "tilesets", "audio", "icons", "field",
                         "battle_anims", "trainers" }) do
    local chunk = loadfile(gen .. key .. ".lua")
    if chunk then Data[key] = chunk() end
  end
  -- the freshly extracted art rides on the installed cache's field table
  if spec.gen == 1 then Data.field.tradeArt = art else Data.field.gen2TradeAnim = art end
  local Assets = require("src.render.Assets")
  Assets.flush()
  local function resolveReal(path)
    if type(path) ~= "string" then return nil end
    for _, base in ipairs({ artRoot, spec.cache }) do
      local p = base .. "/" .. path
      local f = io.open(p, "rb")
      if f then f:close() return p end
    end
    return nil
  end
  Assets.exists = function(path) return resolveReal(path) ~= nil end
  Assets.imageData = function(path)
    local p = resolveReal(path)
    return p and fileImage(p) or love.image.newImageData(8, 8)
  end
  Assets.image = function(path)
    local p = resolveReal(path)
    return love.graphics.newImage(p and fileImage(p) or love.image.newImageData(8, 8))
  end
  -- plain love.graphics.newImage("assets/generated/...") callers (sprites)
  local newImage = love.graphics.newImage
  love.graphics.newImage = function(src, ...)
    if type(src) == "string" then
      local p = resolveReal(src)
      if p then return newImage(fileImage(p), ...) end
    end
    return newImage(src, ...)
  end
  return Data
end

-- a 160x144 canvas per captured frame, tiled 6 wide into one sheet
local function makeSheet()
  return { frames = {}, labels = {} }
end

-- A version with no installed cache (Yellow / Blue on this machine) gets a
-- full import into $TRADE_OUT/import_<version> first -- the same
-- RomExtractor:run() the launcher calls.
local function ensureCache(version)
  local spec = VERSIONS[version]
  if readFile(spec.cache .. "/data/generated/field.lua") then return true end
  local root = OUT .. "/import_" .. version
  spec.cache = root
  if readFile(root .. "/data/generated/field.lua") then return true end
  if spec.gen ~= 1 then return false end
  say("%s: no installed cache, importing into %s", version, root)
  local CacheFs = require("src.import.CacheFs")
  CacheFs.mkdirReal(root)
  CacheFs.root = function() return root end
  CacheFs.prefix = ""
  require("src.core.GameVersion").set(version)
  local manifest = require("src.link.Json").decode(assert(readFile(repo .. "/" .. spec.manifest)))
  local e = require("src.import.RomExtractor").new(assert(readFile(spec.rom)), manifest)
  e:run()
  return readFile(root .. "/data/generated/field.lua") ~= nil
end

local function play(version, art, artRoot)
  local spec = VERSIONS[version]
  if not ensureCache(version) then
    say("%s: no cache to play against", version)
    return
  end
  local GameVersion = require("src.core.GameVersion")
  GameVersion.set(version)
  local Data = loadCache(version, spec, art, artRoot)
  local Game = require("src.core.Game")
  local Input = require("src.core.Input")
  local StateStack = require("src.core.StateStack")
  local SaveData = require("src.core.SaveData")
  local Pokemon = require("src.pokemon.Pokemon")
  local Renderer = require("src.render.Renderer")
  Renderer.WIDTH, Renderer.HEIGHT = 160, 144
  Game.data = Data
  Game.input = Input; Input:init()
  Game.stack = StateStack; StateStack:init()
  Game.save = SaveData.newGame()
  Game.save.player = Game.save.player or {}
  Game.save.player.name = spec.gen == 1 and "RED" or "GOLD"
  Game.save.player.id = 12345
  require("src.render.Font").load(Data)
  pcall(function() require("src.ui.Theme").load(Data) end)

  -- the trade the map scripts run, by index, with its wanted mon in the party
  local give, index, run
  if spec.gen == 1 then
    local trades = Data.field.trades
    index = version == "yellow" and 1 or 5      -- Yellow: Route 2's; R/B: DUX
    give = trades[index].give
    run = function(ctx) require("src.script.Commands").trade(ctx, index) end
  else
    local def = Data.field.gen2Trades
    index = 0                                    -- Violet City: BELLSPROUT/ONIX
    give = def.trades[index + 1].give
    run = function(ctx)
      require("src.script.Gen2Commands")
      require("src.script.Commands").g2_trade(ctx, index)
    end
  end
  Game.save.party = { Pokemon.new(Data, give, 12) }
  Game.save.party[1].otId = 12345
  Game.save.party[1].ot = Game.save.player.name

  -- drive the command as a coroutine the way ScriptRunner does
  local co
  local runner = {
    yield = function() coroutine.yield() end,
    resume = function()
      if co and coroutine.status(co) == "suspended" then
        local ok, err = coroutine.resume(co)
        if not ok then say("%s: script error %s", version, tostring(err)) end
      end
    end,
  }
  local ctx = { game = Game, runner = runner, save = Game.save, data = Data }
  -- TRADE_EXTERNAL=1: the link-trade guest's sequence (ExternalClockTradeAnim
  -- / TradeAnimationPlayer2), pushed directly the way LinkState does
  local EXTERNAL = os.getenv("TRADE_EXTERNAL") == "1"
  if EXTERNAL then
    run = function()
      local Pokemon = require("src.pokemon.Pokemon")
      local want = spec.gen == 1 and Data.field.trades[index].get
        or Data.field.gen2Trades.trades[index + 1].get
      local recv = Pokemon.new(Data, want, 12)
      recv.ot, recv.otId = "PARTNER", 4321
      require("src.ui.Screens").push(Game,
        spec.gen == 1 and "TradeAnim" or "Gen2TradeAnim", {
          sent = Game.save.party[1], received = recv, enemyName = "PARTNER",
          externalClock = true, onDone = function() runner.resume() end })
      runner.yield()
    end
  end
  local tag = EXTERNAL and (version .. "_external") or version
  co = coroutine.create(function() run(ctx) end)

  -- the frame as the renderer composites it: the stack drawn in DMG shades
  -- into one canvas, re-blitted once per palette zone of the topmost state
  -- that has zones, then the true-colour rects unshaded on top
  local raw = love.graphics.newCanvas(160, 144)
  local canvas = love.graphics.newCanvas(160, 144)
  local P = require("src.render.PaletteFX")
  local frames, labels = {}, {}
  local frame = 0
  local lastPhase
  local function snap(label)
    P.clearTrueColor()
    P.setPass("ui")
    love.graphics.setCanvas({ raw, stencil = true })
    love.graphics.clear(1, 1, 1, 1)
    love.graphics.push("all")
    local zones
    for i = 1, #StateStack.states do
      local s = StateStack.states[i]
      if s.draw then s:draw() end
    end
    for i = #StateStack.states, 1, -1 do
      local s = StateStack.states[i]
      if s.sgbPalettes then zones = s:sgbPalettes(Game) break end
    end
    love.graphics.pop()
    love.graphics.setCanvas(canvas)
    love.graphics.clear(1, 1, 1, 1)
    local shader = P.shader()
    if not zones then love.graphics.draw(raw) end
    for _, z in ipairs(zones or {}) do
      love.graphics.setScissor(z.x, z.y, z.w, z.h)
      if z.colors and shader then
        love.graphics.setShader(shader)
        P.sendColors(shader, z.colors)
      end
      love.graphics.draw(raw)
      love.graphics.setShader()
    end
    love.graphics.setScissor()
    local rects, n = P.trueColorRects("ui")
    for i = 1, n do
      local r = rects[i]
      love.graphics.setScissor(r.x, r.y, r.w, r.h)
      love.graphics.draw(raw)
    end
    love.graphics.setScissor()
    P.setPass(nil)
    love.graphics.setCanvas()
    frames[#frames + 1] = canvas:newImageData()
    labels[#labels + 1] = label
  end

  local ok, err = coroutine.resume(co)
  if not ok then say("%s: script error %s", version, tostring(err)) return end

  local animClass = spec.gen == 1 and require("src.ui.TradeAnim")
    or require("src.ui.Gen2TradeAnim")
  local ChoiceBox = require("src.ui.ChoiceBox")
  local PartyMenu = require("src.ui.PartyMenu")
  local seenAnim, wantShots = false, {}
  local animStart = 0
  local EVERY = tonumber(os.getenv("TRADE_EVERY") or "") or 40
  for f = 1, 12000 do
    frame = f
    local top = StateStack:top()
    local mt = top and getmetatable(top)
    local isAnim = mt == animClass or mt == require("src.ui.TradeAnim")
    Input.pressed = {}
    if not isAnim then
      if mt == ChoiceBox then
        Input.pressed = { a = true }          -- YES
      elseif mt == PartyMenu then
        Input.pressed = { a = true }          -- first slot, then PICK
      elseif f % 4 == 0 then
        Input.pressed = { a = true }          -- advance dialogue
      end
    else
      if not seenAnim then animStart = f end
      seenAnim = true
      local phase = tostring(top.phase)
      if phase ~= lastPhase then lastPhase = phase end
      if (f - animStart) % EVERY == 0 then
        wantShots[#wantShots + 1] = { at = f, label = ("%04d_%s"):format(f - animStart, phase) }
      end
    end
    StateStack:update(1 / 60)
    for _, w in ipairs(wantShots) do
      if not w.done and w.at == f then w.done = true snap(w.label) end
    end
    if seenAnim and coroutine.status(co) == "dead" then break end
    if not StateStack:top() and coroutine.status(co) == "dead" then break end
  end
  say("%s: script %s after %d frames, cinematic %s, party[%d] = %s",
      version, coroutine.status(co), frame, seenAnim and "played" or "NOT played",
      #Game.save.party, tostring(Game.save.party[#Game.save.party].species))

  -- one PNG per captured frame and a contact sheet
  local cols = 8
  local rows = math.ceil(#frames / cols)
  if #frames > 0 then
    local sheet = love.image.newImageData(cols * 160, rows * 144)
    for i, img in ipairs(frames) do
      local x, y = ((i - 1) % cols) * 160, math.floor((i - 1) / cols) * 144
      sheet:paste(img, x, y, 0, 0, 160, 144)
      require("src.import.CacheFs").mkdirReal(OUT .. "/" .. tag)
      writeFile(("%s/%s/%s.png"):format(OUT, tag, (labels[i]:gsub("[^%w_]", "_"))),
                img:encode("png"):getString())
    end
    writeFile(("%s/%s_sheet.png"):format(OUT, tag), sheet:encode("png"):getString())
  end
end

function love.load()
  local ok, why = xpcall(function()
    for _, version in ipairs(ORDER) do
      local art, root = extract(version)
      if MODE ~= "extract" and art then
        local okPlay, errPlay = xpcall(play, debug.traceback, version, art, root)
        if not okPlay then say("%s: play failed: %s", version, errPlay) end
      end
    end
  end, debug.traceback)
  if not ok then say("FAILED: %s", tostring(why)) end
  writeFile(OUT .. "/result.txt", table.concat(log, "\n") .. "\n")
  love.event.quit(ok and 0 or 1)
end

function love.errorhandler(m)
  print(debug.traceback(tostring(m)))
  return function() return 1 end
end
