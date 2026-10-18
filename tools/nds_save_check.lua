-- DS save import / export check: Platinum, HeartGold/SoulSilver, Black/White.
--
--   python tools/run_lua_check.py tools/nds_save_check.lua <version> <cacheRoot> [realSave]
--
-- e.g. platinum G:/Gen2Recomped/platinum
--      black G:/Gen2Recomped/black tmp/bw_reference/content.dsv
--
-- Builds a save the way the port keeps one, exports it through SaveConvert
-- (blank image), imports it back and compares; then exports the import again
-- (template path) and checks nothing it does not model moved; then the
-- emulator wrappers; and, given a real cartridge save, that its empty slots
-- are exactly what NdsSave.emptyPkm writes and that it imports and exports.

local version, cache, real = arg[1], arg[2], arg[3]
assert(version and cache, "usage: nds_save_check.lua <version> <cacheRoot> [realSave]")
package.path = "./?.lua;./?/init.lua;" .. cache .. "/?.lua;" .. package.path
love = love or require("tests.love_stub")

local GameVersion = require("src.core.GameVersion")
pcall(GameVersion.set, version)
local SaveConvert = require("src.save_convert.SaveConvert")
local NdsSave = require("src.save_convert.NdsSave")

local pass, fail = 0, 0
local function check(ok, what)
  if ok then pass = pass + 1 else fail = fail + 1; print("FAIL " .. what) end
end
local function eq(a, b, what) check(a == b, ("%s: %s ~= %s"):format(what, tostring(a), tostring(b))) end

local data = assert(SaveConvert.loadData(version))
local gen = GameVersion.generation(version)
local boot = (data.field or {}).boot or {}

-- ------------------------------------------------------------ a port save --
local function mon(species, level, extra)
  local m = { species = species, level = level, exp = level * level * level, happiness = 120,
    personality = 0x12345678 + species, otId = 31337, ivs = { hp = 31, attack = 30, defense = 29,
    speed = 28, spatk = 27, spdef = 26 }, evs = { hp = 4, attack = 252, defense = 0, speed = 252,
    spatk = 0, spdef = 0 }, moves = { { id = 33, pp = 35, ppUps = 0 }, { id = 45, pp = 40, ppUps = 3 } },
    hp = 20, maxHp = 30, stats = { hp = 30, attack = 20, defense = 21, speed = 22, spatk = 23, spdef = 24 },
    ball = 4, metLocation = 10, metLevel = 5, ot = "LUCAS", otGender = "boy", gender = "male" }
  for k, v in pairs(extra or {}) do m[k] = v end
  return m
end
local badges = (data.constants or {}).badges or {}
local items = gen == 5 and { [17] = 5, [4] = 10, [328] = 1, [155] = 3, [450] = 1 }
  or { [17] = 5, [4] = 10, [328] = 1, [155] = 3, [450] = 1, [57] = 2, [137] = 1 }
local save = {
  version = version,
  player = { name = "LUCAS", id = 31337, secretId = 4242, gender = "boy", rival = gen == 4 and "BARRY" or nil,
    map = boot.startMap, x = boot.startX, y = boot.startY, facing = "left" },
  money = 123456, coins = 77, playTime = 3 * 3600 + 25 * 60 + 9,
  inventory = items,
  badges = { [badges[1] and (badges[1].id or badges[1])] = true, [badges[3] and (badges[3].id or badges[3])] = true },
  flags = { FLAG_G4_0087 = true, FLAG_G4_00EA = true, FLAG_G4_0964 = gen == 4 or nil, ENGINE_POKEDEX = true },
  gen4Vars = { [0x4040] = 9, [0x40A4] = 6, [0x4000 + 0x100] = 1234 },
  gen4TrainerFlags = { [1] = true, [12] = true },
  party = {
    mon(25, 30, { nickname = "SPARKY", item = 234, gender = "female", fatefulEncounter = true }),
    mon(gen == 5 and 495 or 387, 12),
  },
  boxes = { { name = "FAVORITES", mon(133, 20), mon(1, 5, { isEgg = true, eggCycles = 20 }) }, { mon(150, 70) } },
  currentBox = 2,
  pokedex = { seen = { [25] = true, [387] = true, [133] = true, [150] = true, [495] = true },
    owned = { [25] = true, [133] = true }, national = true },
  poketch = gen == 4 and { enabled = true, registered = { [0] = true, [1] = true, [5] = true } } or nil,
}

-- -------------------------------------------------------- blank export --
local bytes, err = SaveConvert.exportSav(save, version)
check(bytes ~= nil, "blank export: " .. tostring(err))
if not bytes then print(("%d passed, %d failed"):format(pass, fail)) os.exit(1) end
eq(#bytes, NdsSave.SIZE, "image size")

local back, ierr = SaveConvert.importSav(bytes, version, version)
check(back ~= nil, "import of blank export: " .. tostring(ierr))
if back then
  eq(back.player.name, "LUCAS", "name")
  eq(back.player.id, 31337, "tid")
  eq(back.player.secretId, 4242, "sid")
  eq(back.player.map, boot.startMap, "map")
  eq(back.player.x, boot.startX, "x"); eq(back.player.y, boot.startY, "y")
  if gen == 4 then
    eq(back.player.facing, "left", "facing"); eq(back.player.rival, "BARRY", "rival"); eq(back.coins, 77, "coins")
    if GameVersion.info(version).family ~= "hgss" then
      check(back.poketch and back.poketch.enabled and back.poketch.registered[5], "poketch")
    end
  end
  eq(back.money, 123456, "money")
  eq(math.floor(back.playTime), 3 * 3600 + 25 * 60 + 9, "play time")
  for k, n in pairs(items) do eq(back.inventory[k], n, "item " .. k) end
  check(back.badges[badges[1].id or badges[1]] and back.badges[badges[3].id or badges[3]]
    and not back.badges[badges[2].id or badges[2]], "badges")
  check(back.flags.FLAG_G4_0087 and back.flags.FLAG_G4_00EA, "flags")
  eq(back.gen4Vars[0x40A4], 6, "var 40A4"); eq(back.gen4Vars[0x4100], 1234, "var 4100")
  check(back.gen4TrainerFlags[1] and back.gen4TrainerFlags[12] and not back.gen4TrainerFlags[2], "trainer flags")
  check(back.pokedex.owned[25] and back.pokedex.seen[150] and not back.pokedex.owned[150] and back.pokedex.national, "dex")
  check(back.flags.ENGINE_POKEDEX, "dex obtained")
  eq(#back.party, 2, "party size")
  local p = back.party[1]
  eq(p.species, 25, "species"); eq(p.nickname, "SPARKY", "nickname"); eq(p.item, 234, "held item")
  eq(p.level, 30, "level"); eq(p.hp, 20, "hp"); eq(p.personality, 0x12345678 + 25, "pid")
  eq(p.ivs.spdef, 26, "iv spdef"); eq(p.evs.speed, 252, "ev speed")
  eq(p.moves[2].id, 45, "move 2"); eq(p.moves[2].ppUps, 3, "pp ups")
  eq(p.gender, "female", "gender"); check(p.fatefulEncounter, "fateful"); eq(p.otId, 31337 + 4242 * 65536, "ot id")
  eq(p.ot, "LUCAS", "ot name"); eq(p.metLocation, 10, "met location"); eq(p.ball, 4, "ball")
  eq(back.currentBox, 2, "current box")
  eq(back.boxes[1].name, "FAVORITES", "box name")
  eq(#back.boxes[1], 2, "box 1 count"); eq(#back.boxes[2], 1, "box 2 count")
  check(back.boxes[1][2] and back.boxes[1][2].isEgg, "egg")
  eq(back.boxes[2][1].species, 150, "box mon")
  eq(#(back.warnings or {}), 0, "warnings: " .. table.concat(back.warnings or {}, "; "))

  -- ------------------------------------------------- template round trip --
  back.money = 5
  back.party[2].level = 13
  local again = assert(SaveConvert.exportSav(back, version))
  local third = assert(SaveConvert.importSav(again, version, version))
  eq(third.money, 5, "money after template export")
  eq(third.party[2].level, 13, "level after template export")
  eq(third.party[1].nickname, "SPARKY", "nickname after template export")
  eq(third.party[1].ndsRaw, back.party[1].ndsRaw, "unmodelled record bytes kept")
end

-- ---------------------------------------------------------- the wrappers --
local dsv = NdsSave.wrapDesmume(bytes)
eq(#dsv, NdsSave.SIZE + 122, "dsv size")
eq((NdsSave.unwrap(dsv)), bytes, "dsv unwrap")
eq((NdsSave.unwrap(bytes .. string.rep("\255", NdsSave.SIZE))), bytes, "1 MiB padded unwrap")
local hdr = "NocashGbaBackupMediaSavDataFile\26" .. string.rep("\0", 0x40 - 32)
  .. "SRAM" .. "\0\0\0\0" .. "\0\0\8\0"
eq((NdsSave.unwrap(hdr .. bytes)), bytes, "no$gba plain unwrap")
check(SaveConvert.importSav(dsv, version, version) ~= nil, "import straight from .dsv")
check(NdsSave.unwrap(string.rep("\0", 1000)) == nil, "short file refused")

-- --------------------------------------------------------- a real save --
if real then
  local f = assert(io.open(real, "rb")); local file = f:read("*a"); f:close()
  local raw = assert(NdsSave.unwrap(file))
  if gen == 5 then
    eq(raw:sub(0x401, 0x400 + 136), NdsSave.emptyPkm(136), "empty box slot matches the cartridge")
    eq(raw:sub(0x18E09, 0x18E08 + 220), NdsSave.emptyPkm(220), "empty party slot matches the cartridge")
  end
  -- a save nobody has played yet is refused with a reason, not invented
  local fresh, why = SaveConvert.importSav(file, version, version)
  local blank = raw:sub(0x19405, 0x19414) == string.rep("\0", 16)
  if gen == 5 and blank then
    check(fresh == nil and tostring(why):find("no adventure"), "unplayed save refused: " .. tostring(why))
  else
    check(fresh ~= nil, "real save imports: " .. tostring(why))
  end
  -- the port's save written ONTO the cartridge's own image
  local codec = SaveConvert.codecFor(version)
  local ok, out = pcall(codec.encode, save, data, raw, version)
  check(ok, "export onto the cartridge image: " .. tostring(out))
  if ok then
    local re, e3 = SaveConvert.importSav(out, version, version)
    check(re ~= nil, "re-import after export onto the cartridge image: " .. tostring(e3))
    if re then
      eq(re.player.name, "LUCAS", "name on cartridge image")
      eq(re.party[1] and re.party[1].nickname, "SPARKY", "party on cartridge image")
    end
    if gen == 5 then
      eq(out:sub(0x48001), raw:sub(0x48001), "extra data (Hall of Fame, C-Gear...) untouched")
      eq(out:sub(0x1C801, 0x1C800 + 0xA94), raw:sub(0x1C801, 0x1C800 + 0xA94), "mystery gift block untouched")
      eq(out:sub(0x22C01, 0x22C00 + 0x850), raw:sub(0x22C01, 0x22C00 + 0x850), "entralink forest untouched")
    end
  end
end

print(("%s: %d passed, %d failed"):format(version, pass, fail))
os.exit(fail == 0 and 0 or 1)
