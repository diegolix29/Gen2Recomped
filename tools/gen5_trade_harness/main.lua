-- tools/gen5_trade_harness/main.lua
--
-- BLACK AND WHITE'S IN-GAME TRADES, from the cartridge, with an installed
-- cache read and never written: the trade table (src/import/Gen5Trades.lua),
-- the script pool relinked with the current Gen5ScriptLink (so the trade
-- commands carry their operands) and the trade demo's art
-- (src/import/Gen5TradeArt.lua) are all decoded IN MEMORY from ROM.
--
--   INSTALL=G:/Gen2Recomped/black VERSION=black \
--   ROM="./Pokemon - Black Version (USA, Europe) (NDSi Enhanced).nds" \
--   OUT_DIR=G:/Gen2Recomped/scratch_claude/gen5trade \
--   MODE=overworld MAP=Z023 X=.. Y=.. PARTY=546,501 PRESS=20 TICKS=4000 \
--   SHOTS=... "/c/Program Files/LOVE/lovec.exe" tools/gen5_trade_harness
--
-- MODE=overworld hands over to tools/gen4_hgss_overworld_harness (all of its
-- variables apply). Every message box opened is printed as [msg], and the
-- party is listed (species, nickname, OT, id, level, nature, ability, item,
-- PID) before and after.
--
-- MODE=screen (the default) plays the demo alone: SEND / RECV species,
-- SHOTS=frame,... (or EVERY=n) write trade5_<TAG>_<frame>.png, both screens.

io.stdout:setvbuf("line")
local install = assert(os.getenv("INSTALL"), "set INSTALL to the version's folder")
local romPath = assert(os.getenv("ROM"), "set ROM to the cartridge")
local version = os.getenv("VERSION") or "black"
local outDir = os.getenv("OUT_DIR") or "G:/Gen2Recomped/scratch_claude/gen5trade"

local pictures = {}
local function extractor()
  local x = { rom = assert(require("src.import.NdsRom").open(romPath)), version = version, _banks = {} }
  local Narc = require("src.import.NarcArchive")
  local Text = require("src.import.Gen5Text")
  local system
  function x:string(bank, index)
    if self._banks[bank] == nil then
      system = system or Narc.parse(self.rom:read("/a/0/0/2"))
      self._banks[bank] = Text.bank(system:get(bank)) or false
    end
    return self._banks[bank] and self._banks[bank][index]
  end
  function x:saveImage(rel, pic, extra)
    local path = "__trade5/" .. rel .. ".png"
    local data = love.image.newImageData(pic.width, pic.height, "rgba8", pic.rgba)
    local img = love.graphics.newImage(data)
    img:setFilter("nearest", "nearest")
    pictures[path] = img
    local rec = { path = path, width = pic.width, height = pic.height }
    for k, v in pairs(extra or {}) do rec[k] = v end
    return rec
  end
  return x
end

local function hookAssets()
  local Assets = require("src.render.Assets")
  local original = Assets.image
  Assets.image = function(path, ...)
    if type(path) == "string" and pictures[path] then return pictures[path] end
    return original(path, ...)
  end
end

local function buildArt(x)
  local ok, M = pcall(require, "src.import.Gen5TradeArt")
  if not ok then print("[trade5] no art module: " .. tostring(M)) return nil end
  local okB, art = pcall(M.build, x)
  if not okB then print("[trade5] art failed: " .. tostring(art)) return nil end
  return art
end

local function describe(data, mon)
  if type(mon) ~= "table" then return "-" end
  local def = data.pokemon and data.pokemon[mon.species]
  local nature = mon.nature
  local natures = data.constants and data.constants.natures
  if type(nature) == "number" and natures then nature = natures[nature] or nature end
  local iv = mon.ivs or {}
  return ("%s(%s) nick=%s ot=%s/%s id=%s lv%s nature=%s abil=%s item=%s pid=%08X form=%s ivs=%s/%s/%s/%s/%s/%s gender=%s")
    :format(tostring(def and def.name), tostring(mon.species), tostring(mon.nickname), tostring(mon.ot),
      tostring(mon.otGender), tostring(mon.otId), tostring(mon.level), tostring(nature),
      tostring(mon.abilitySlot), tostring(mon.item), tonumber(mon.personality) or 0, tostring(mon.form),
      tostring(iv.hp), tostring(iv.attack), tostring(iv.defense), tostring(iv.speed), tostring(iv.spatk),
      tostring(iv.spdef), tostring(require("src.pokemon.Pokemon").genderOf(data, mon)))
end

if os.getenv("MODE") == "overworld" then
  local Data = require("src.core.Data")
  local load = Data.load
  Data.load = function(self, ...)
    local r = { load(self, ...) }
    local x = extractor()
    -- the trade table
    self.constants = self.constants or {}
    self.constants.gen5Trades = require("src.import.Gen5Trades").build(x)
    print(("[trade5] %d trade records decoded from %s"):format(#(self.constants.gen5Trades or {}), romPath))
    -- the script pool, relinked
    local gen = install .. "/data/generated/"
    local scripts = self.gen5_scripts or dofile(gen .. "gen5_scripts.lua")
    local zones = self.gen5_zones or dofile(gen .. "gen5_zones.lua")
    local maps = dofile(gen .. "maps.lua")
    local ver = self.gen5_version or dofile(gen .. "gen5_version.lua")
    local Narc = require("src.import.NarcArchive")
    local Link = require("src.import.Gen5ScriptLink")
    local t0 = os.clock()
    local pool, rep = Link.pool(Narc.parse(x.rom:read("/a/0/5/7")), scripts.widths, zones, maps,
                                ver.scriptBands or Link.findBands(x.rom))
    local old = self.map_scripts
    -- keep anything the cache's pool carries that a relink does not make
    for k, v in pairs(old or {}) do if pool[k] == nil then pool[k] = v end end
    self.map_scripts = pool
    print(("[trade5] script pool relinked in %.1fs: %d instructions, %d named"):format(
      os.clock() - t0, rep.instructions, rep.named))
    -- the demo's art
    self.gen5_trade_art = buildArt(x)
    hookAssets()
    x.rom:close()
    return (table.unpack or unpack)(r)
  end
  -- every message box, printed
  local TextBox = require("src.render.TextBox")
  local new = TextBox.new
  TextBox.new = function(game, text, ...)
    print(("[msg] %s"):format(tostring(text):gsub("\n", " / ")))
    return new(game, text, ...)
  end
  -- every screen pushed, with the frame it opened on (to aim PRESS_KEYS)
  local Screens = require("src.ui.Screens")
  local push = Screens.push
  local frames = 0
  local Stack = require("src.core.StateStack")
  local stackUpdate = Stack.update
  Stack.update = function(...) frames = frames + 1 return stackUpdate(...) end
  -- PICK_SLOT=n: the trade's party menu opens with its cursor on slot n (the
  -- A press that follows picks it), instead of aiming PRESS_KEYS at it
  Screens.push = function(game, name, ...)
    print(("[screen] %s at stack update %d"):format(tostring(name), frames))
    local r = { push(game, name, ...) }
    local pick = tonumber(os.getenv("PICK_SLOT") or "")
    if pick and name == "PartyMenu" then
      local states = game.stack and game.stack.states
      local top = states and states[#states]
      if top and top.index then top.index = pick; print(("[screen] party cursor on slot %d"):format(pick)) end
    end
    return (table.unpack or unpack)(r)
  end
  -- the party, described, at the harness's own before / after lines
  local print0 = print
  print = function(first, ...)
    print0(first, ...)
    if type(first) == "string" and (first:match("^party before") or first:match("^party after")) then
      local G = package.loaded["src.core.Game"]
      for i, mon in ipairs((G and G.save and G.save.party) or {}) do
        print0(("  slot %d: %s"):format(i, describe(G.data, mon)))
      end
      local T = package.loaded["src.script.Gen5TradeCommands"]
      if T and T.last and first:match("^party after") then
        print0(("  [trade5] last trade %s into slot %d"):format(tostring(T.last.trade), T.last.slot))
      end
    end
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
    local Assets = require("src.render.Assets")
    local realImage, held = Assets.image, {}
    Assets.image = function(path, ...)
      if type(path) == "string" and not held[path] and not pictures[path] then
        local f = io.open(install .. "/" .. path, "rb")
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
    local x = extractor()
    Data.gen5_trade_art = buildArt(x)
    Data.constants.gen5Trades = require("src.import.Gen5Trades").build(x)
    x.rom:close()
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
    local sending = Pokemon.new(Data, tonumber(os.getenv("SEND") or "546"), 15)
    local T = require("src.script.Gen5TradeCommands")
    local row = T.row(Data, tonumber(os.getenv("TRADE") or "0"))
    local receiving = row and T.build(Data, row) or Pokemon.new(Data, tonumber(os.getenv("RECV") or "548"), 15)
    local done = false
    local Screen = require("src.ui.Gen5TradeSequence")
    local screen = Screen.new(Game, { sending = sending, receiving = receiving,
      otName = row and row.otName or "Dye", onDone = function() done = true end })
    Game.stack:push(screen)
    local shots = {}
    for t in tostring(os.getenv("SHOTS") or ""):gmatch("%d+") do shots[tonumber(t)] = true end
    local every = tonumber(os.getenv("EVERY") or "0")
    local tag = os.getenv("TAG") or version
    local maxFrames = tonumber(os.getenv("FRAMES") or "4000")
    local out = love.graphics.newCanvas(256, 192 * 2 + 4)
    local last
    for frame = 1, maxFrames do
      screen:update(1 / 60)
      local d = screen:describe()
      if d ~= last then last = d; print(("[trade5] frame %d %s"):format(frame, d)) end
      if done then print(("[trade5] finished at frame %d"):format(frame)) break end
      if shots[frame] or (every > 0 and frame % every == 0) then
        love.graphics.push("all")
        love.graphics.setCanvas(out)
        love.graphics.origin()
        love.graphics.clear(0.2, 0.2, 0.2, 1)
        screen:drawScreens(0, 196)
        love.graphics.setCanvas()
        love.graphics.pop()
        save(out, ("trade5_%s_%05d.png"):format(tag, frame))
        print(("[shot] %d %s"):format(frame, d))
      end
    end
  end, debug.traceback)
  if not ok then print("TRADE5 HARNESS FAILED: " .. tostring(err)) end
  love.event.quit()
end
