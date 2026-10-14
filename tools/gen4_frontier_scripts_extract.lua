-- Run:  python tools/run_lua_check.py tools/gen4_frontier_scripts_extract.lua <platinum .nds> <cache dir>
--
-- Writes the Battle Frontier's scene scripts (src/import/Gen4FrontierScripts.lua,
-- /frontier/script/fr_script.narc) into an EXISTING Platinum cache as
-- <cache dir>/gen4_frontier_scripts.lua.

package.path = './?.lua;./?/init.lua;' .. package.path
love = require('tests.love_stub')
local romPath, cacheDir = arg[1], arg[2]
assert(romPath and cacheDir, 'usage: gen4_frontier_scripts_extract.lua <rom> <cache dir>')
cacheDir = cacheDir:gsub('[/\\]$', '')
local rom = assert(require('src.import.NdsRom').open(romPath))
local rec = assert(require('src.import.Gen4FrontierScripts').read(rom))
local f = assert(io.open(cacheDir .. '/gen4_frontier_scripts.lua', 'wb'))
f:write(require('src.import.LuaWriter').encode(rec))
f:close()
local n = 0
for _ in pairs(rec.members) do n = n + 1 end
print(('wrote %d scene scripts to %s/gen4_frontier_scripts.lua'):format(n, cacheDir))
