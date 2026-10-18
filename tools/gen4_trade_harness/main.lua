-- tools/gen4_trade_harness/main.lua
--
-- THE IN-GAME TRADE CUTSCENE (src/ui/Gen4TradeSequence.lua), drawn from art
-- decoded IN MEMORY from the cartridge (src/import/Gen4TradeArt.lua), so an
-- installed cache is read and never written.
--
--   INSTALL=G:/Gen2Recomped/platinum VERSION=platinum \
--   ROM="./Pokemon - Platinum Version (USA) (Rev 1).nds" \
--   OUT_DIR=G:/Gen2Recomped/scratch_claude/gen4trade \
--   SEND=63 RECV=66 BG=0 SHOTS=30,200,... love tools/gen4_trade_harness
--
-- MODE=screen (the default) pushes the cutscene alone and writes, at each
-- frame of SHOTS (or every EVERY frames), trade_<TAG>_<frame>.png: the top
-- screen over the bottom one, as the cartridge would show them.
--
-- MODE=overworld hands over to tools/gen4_hgss_overworld_harness (every one
-- of its variables applies -- MAP, X, Y, PRESS, PARTY, SHOTS ...) with the
-- trade art added to the data it loads, so an NPC's trade script plays the
-- cutscene end to end.

io.stdout:setvbuf("line")
local install = assert(os.getenv("INSTALL"), "set INSTALL to the version's folder")
local romPath = assert(os.getenv("ROM"), "set ROM to the cartridge")
local version = os.getenv("VERSION") or "platinum"
local outDir = os.getenv("OUT_DIR") or "G:/Gen2Recomped/scratch_claude/gen4trade"

-- the decoded pictures, by the path the index names
local pictures = {}
local function buildArt()
  local x = { rom = assert(require("src.import.NdsRom").open(romPath)), version = version }
  function x:saveImage(rel, pic, extra)
    local path = "__trade/" .. rel .. ".png"
    local data = love.image.newImageData(pic.width, pic.height, "rgba8", pic.rgba)
    pictures[path] = love.graphics.newImage(data)
    local rec = { path = path, width = pic.width, height = pic.height }
    for k, v in pairs(extra or {}) do rec[k] = v end
    return rec
  end
  local art = require("src.import.Gen4TradeArt").build(x)
  x.rom:close()
  return art
end

local function hookAssets()
  local Assets = require("src.render.Assets")
  local original = Assets.image
  Assets.image = function(path, ...)
    if type(path) == "string" and pictures[path] then return pictures[path] end
    return original(path, ...)
  end
end

if os.getenv("MODE") == "overworld" then
  local Data = require("src.core.Data")
  local load = Data.load
  Data.load = function(self, ...)
    local r = { load(self, ...) }
    self.gen4_trade_art = buildArt()
    hookAssets()
    print("[trade] art decoded from " .. romPath)
    return (table.unpack or unpack)(r)
  end
  dofile("tools/gen4_hgss_overworld_harness/main.lua")
  return
end

-- ----------------------------------------------------------- MODE=screen --

local ffi = require("ffi")
pcall(ffi.cdef, "int PHYSFS_mount(const char *newDir, const char *mountPoint, int appendToPath);")
for _, lib in ipairs({ function() return ffi.C end, function() return ffi.load("love") end }) do
  local ok, l = pcall(lib)
  if ok and l then
    local okf, fn = pcall(function() return l.PHYSFS_mount end)
    if okf and fn and fn(install, "", 1) ~= 0 then break end
  end
end
local env = { POKEPORT_DATA_DIR = install .. "/data/generated", POKEPORT_ASSET_ROOT = install }
local getenv = os.getenv
os.getenv = function(k) return env[k] or getenv(k) end

local function save(canvas, name)
  local data = canvas:newImageData():encode("png")
  local f = assert(io.open(outDir .. "/" .. name, "wb"))
  f:write(data:getString()); f:close()
end

function love.load()
  local ok, err = xpcall(function()
    local GameVersion = require("src.core.GameVersion")
    GameVersion.set(version)
    -- pictures from the install folder, as the overworld harness reads them
    local assetRoot = install
    local Assets = require("src.render.Assets")
    local realImage, held = Assets.image, {}
    Assets.image = function(path, ...)
      if type(path) == "string" and not held[path] and not pictures[path] then
        local f = io.open(assetRoot .. "/" .. path, "rb")
        if f then
          local bytes = f:read("*a"); f:close()
          local okI, img = pcall(love.graphics.newImage, love.filesystem.newFileData(bytes, path))
          if okI then img:setFilter("nearest", "nearest"); held[path] = img end
        end
      end
      return pictures[path] or held[path] or realImage(path, ...)
    end
    local Data = require("src.core.Data")
    Data:load()
    Data.gen4_trade_art = buildArt()
    local Game = require("src.core.Game")
    Game.data = Data
    local ModLoader = require("src.mods.Loader")
    Game.mods = ModLoader.new()
    Game.mods:load(Data)
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
    Game.save = require("src.core.SaveData").newGame({})
    Game.input = { wasPressed = function() return false end, isDown = function() return false end,
                   wasReleased = function() return false end }
    local Pokemon = require("src.pokemon.Pokemon")
    local sending = Pokemon.new(Data, tonumber(os.getenv("SEND") or "63"), 12)
    local receiving = Pokemon.new(Data, tonumber(os.getenv("RECV") or "66"), 12)
    receiving.nickname = os.getenv("NICK") or receiving.nickname
    local done = false
    local Screen = require("src.ui.Gen4TradeSequence")
    local screen = Screen.new(Game, { sending = sending, receiving = receiving,
      otName = os.getenv("OT") or "MEIKO", background = tonumber(os.getenv("BG") or "0"),
      onDone = function() done = true end })
    Game.stack:push(screen)
    local shots = {}
    for t in tostring(os.getenv("SHOTS") or ""):gmatch("%d+") do shots[tonumber(t)] = true end
    local every = tonumber(os.getenv("EVERY") or "0")
    local tag = os.getenv("TAG") or version
    local maxFrames = tonumber(os.getenv("FRAMES") or "3000")
    local out = love.graphics.newCanvas(256, 192 * 2 + 4)
    local lastPhase
    for frame = 1, maxFrames do
      screen:update()
      if screen.phaseIndex ~= lastPhase then
        lastPhase = screen.phaseIndex
        print(("[trade] frame %d -> phase %d (%s)"):format(frame, lastPhase, tostring(Screen.PHASE_NAMES[lastPhase])))
      end
      if done then print(("[trade] finished at frame %d"):format(frame)) break end
      if shots[frame] or (every > 0 and frame % every == 0) then
        love.graphics.push("all")
        screen:draw()            -- renders both engines
        love.graphics.setCanvas(out)
        love.graphics.origin()
        love.graphics.clear(0.2, 0.2, 0.2, 1)
        local top = screen:topEngine()
        local bottom = top == "main" and "sub" or "main"
        Screen._drawLayer(screen.canvases[top], screen.bright[top], false)
        love.graphics.translate(0, 196)
        Screen._drawLayer(screen.canvases[bottom], screen.bright[bottom], false)
        love.graphics.setCanvas()
        love.graphics.pop()
        save(out, ("trade_%s_%05d.png"):format(tag, frame))
        print(("[shot] %d %s"):format(frame, screen:describe()))
      end
    end
  end, debug.traceback)
  if not ok then print("TRADE HARNESS FAILED: " .. tostring(err)) end
  love.event.quit()
end
