-- Run:  python tools/run_lua_check.py tools/gen4_battle_tower_extract.lua <platinum .nds> <cache dir>
--
-- Writes the Battle Tower's trainers and Pokemon sets
-- (src/import/Gen4BattleTowerData.lua) into an EXISTING Platinum cache as
-- <cache dir>/gen4_battle_tower.lua.

package.path = './?.lua;./?/init.lua;' .. package.path
love = require('tests.love_stub')
local romPath, cacheDir = arg[1], arg[2]
assert(romPath and cacheDir, 'usage: gen4_battle_tower_extract.lua <rom> <cache dir>')
cacheDir = cacheDir:gsub('[/\\]$', '')
local rom = assert(require('src.import.NdsRom').open(romPath))
local rec = assert(require('src.import.Gen4BattleTowerData').read(rom))
local f = assert(io.open(cacheDir .. '/gen4_battle_tower.lua', 'wb'))
f:write(require('src.import.LuaWriter').encode(rec))
f:close()
local nt, ns = 0, 0
for _ in pairs(rec.trainers) do nt = nt + 1 end
for _ in pairs(rec.sets) do ns = ns + 1 end
local nh = 0
for _ in pairs(rec.hallSets or {}) do nh = nh + 1 end
print(('wrote %d trainers, %d sets and %d Hall sets to %s/gen4_battle_tower.lua'):format(nt, ns, nh, cacheDir))
