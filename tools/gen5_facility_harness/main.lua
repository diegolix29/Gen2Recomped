-- tools/gen5_facility_harness/main.lua
--
-- BLACK AND WHITE'S SIDE FACILITIES (Battle Subway, Nimbasa's stadiums, the
-- Musical) on an installed cache that is read and never written: the script
-- pool is relinked IN MEMORY with the current Gen5ScriptLink (so 0x15A,
-- 0x1F3-0x1F7 and 0x169-0x16B carry their operands) and the facilities'
-- tables are decoded from the ROM (src/import/Gen5Subway.lua, ...), then it
-- hands over to tools/gen4_hgss_overworld_harness (all of its variables
-- apply: MAP, X, Y, PARTY, PARTYLEVEL, PRESS, TICKS, SHOTS, WALKSEQ ...).
--
--   INSTALL=G:/Gen2Recomped/black VERSION=black \
--   ROM="./Pokemon - Black Version (USA, Europe) (NDSi Enhanced).nds" \
--   OUT_DIR=G:/Gen2Recomped/scratch_claude/bwsubway \
--   MAP=Z067 X=12 Y=16 FACING=up PARTY=... PRESS=20 TICKS=... \
--   BW_SUBWAY_AUTOPICK=1 BW_SUBWAY_TRACE=1 \
--   "/c/Program Files/LOVE/lovec.exe" tools/gen5_facility_harness
--
-- Every message box is printed as [msg] and every screen pushed as [screen];
-- BW_SUBWAY_TRACE prints each 0x15A call. BP=n starts with n Battle Points;
-- SUBWAY_STREAK="mode:streak:stage" seeds a line's record (to reach a boss).

io.stdout:setvbuf("line")
local install = assert(os.getenv("INSTALL"), "set INSTALL to the version's folder")
local version = os.getenv("VERSION") or "black"
local romPath = os.getenv("ROM") or (version == "white"
  and "./Pokemon - White Version (USA, Europe) (NDSi Enhanced).nds"
  or "./Pokemon - Black Version (USA, Europe) (NDSi Enhanced).nds")

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
  return x
end

local Data = require("src.core.Data")
local load = Data.load
Data.load = function(self, ...)
  local r = { load(self, ...) }
  local x = extractor()
  self.constants = self.constants or {}
  self.constants.gen5Subway = require("src.import.Gen5Subway").build(x)
  local okF, facilities = pcall(require, "src.import.Gen5Facilities")
  if okF and facilities and facilities.build then
    local okB, rec = pcall(facilities.build, x)
    if okB and rec then for k, v in pairs(rec) do self.constants[k] = v end end
  end
  -- the system banks the facilities print from, into the flat text
  local Text = require("src.import.Gen5Text")
  for _, bank in ipairs({ 11, 184 }) do
    for i = 0, 1200 do
      local s = x:string(bank, i)
      if s == nil then break end
      self.text[Text.label("system", bank, i)] = self.text[Text.label("system", bank, i)] or s
    end
  end
  -- the script pool, relinked
  local gen = install .. "/data/generated/"
  local scripts = self.gen5_scripts or dofile(gen .. "gen5_scripts.lua")
  local zones = self.gen5_zones or dofile(gen .. "gen5_zones.lua")
  local maps = dofile(gen .. "maps.lua")
  local ver = self.gen5_version or dofile(gen .. "gen5_version.lua")
  local Narc = require("src.import.NarcArchive")
  local Link = require("src.import.Gen5ScriptLink")
  -- the widths measured by hand since the cache was made (0x137)
  for op, w in pairs(require("src.import.Gen5ScriptOps").HAND_WIDTHS or {}) do scripts.widths[op] = w end
  local t0 = os.clock()
  local pool, rep = Link.pool(Narc.parse(x.rom:read("/a/0/5/7")), scripts.widths, zones, maps,
                              ver.scriptBands or Link.findBands(x.rom))
  for k, v in pairs(self.map_scripts or {}) do if pool[k] == nil then pool[k] = v end end
  self.map_scripts = pool
  print(("[facility] script pool relinked in %.1fs: %d instructions, %d named; subway %s"):format(
    os.clock() - t0, rep.instructions, rep.named, self.constants.gen5Subway and "decoded" or "MISSING"))
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
local Screens = require("src.ui.Screens")
local push = Screens.push
Screens.push = function(game, name, ...)
  print(("[screen] %s"):format(tostring(name)))
  return push(game, name, ...)
end

-- BP / SUBWAY_STREAK seeding, once the save exists
local Game = require("src.core.Game")
local adopt = Game.adoptSave
Game.adoptSave = function(self, save, ...)
  local r = { adopt and adopt(self, save, ...) }
  if os.getenv("BP") then require("src.pokemon.Gen4BattleTower").addBP(save, tonumber(os.getenv("BP")) or 0) end
  for mode, streak, stage in tostring(os.getenv("SUBWAY_STREAK") or ""):gmatch("(%d+):(%d+):(%d+)") do
    local S = require("src.script.Gen5BattleSubway")
    local s = S.score(save)
    s.streak[tonumber(mode) + 1] = tonumber(streak)
    s.stage[tonumber(mode) + 1] = tonumber(stage)
  end
  return (table.unpack or unpack)(r)
end

-- a forced switch (the lead fainted) opens the party with the cursor on the
-- first one still standing, so the harness's A presses send it in
local PM = require("src.ui.Gen4PartyMenu")
local pmNew = PM.new
PM.new = function(game, opts, ...)
  local menu = pmNew(game, opts, ...)
  if type(opts) == "table" and opts.forceSwitch and menu and menu.party then
    local okP, party = pcall(menu.party, menu)
    for i, mon in ipairs(okP and party or {}) do
      if (tonumber(mon.hp) or 0) > 0 and i ~= 1 then menu.index = i break end
    end
  end
  return menu
end

-- SEED=n: the same draws (trainers, sets, battle rolls) every run
if os.getenv("SEED") then
  local seed = tonumber(os.getenv("SEED")) or 1
  math.randomseed(seed)
  local loadSeed = Data.load
  Data.load = function(...)
    if love.math and love.math.setRandomSeed then love.math.setRandomSeed(seed) end
    return loadSeed(...)
  end
end

-- the record, after the run
local print0 = print
print = function(first, ...)
  print0(first, ...)
  if type(first) == "string" and first:match("^party after") then
    local G = package.loaded["src.core.Game"]
    local s = G and G.save and G.save.gen5Subway
    if s then
      local function list(t) local o = {} for i = 1, 9 do o[i] = tostring(t[i] or 0) end return table.concat(o, ",") end
      print0(("  [subway] BP %d | streak %s | best %s | trains %s | car %s"):format(
        require("src.pokemon.Gen4BattleTower").bp(G.save), list(s.streak), list(s.best), list(s.stage),
        tostring(s.play and s.play.car)))
    end
  end
end

dofile("tools/gen4_hgss_overworld_harness/main.lua")
