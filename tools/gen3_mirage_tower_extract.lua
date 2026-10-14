-- Run:  python tools/run_lua_check.py tools/gen3_mirage_tower_extract.lua <emerald .gba> <cache dir>
--
-- Adds `constants.gen3MirageTower` -- the Mirage Tower's collapse graphics,
-- read by RomExtractorGen3:extractMirageTower -- to an EXISTING Emerald cache,
-- without a full re-import.

package.path = './?.lua;./?/init.lua;' .. package.path
love = require('tests.love_stub')
local romPath, cacheDir = arg and arg[1], arg and arg[2]
if not (romPath and cacheDir) then
  print('usage: gen3_mirage_tower_extract.lua <emerald .gba> <cache dir>')
  os.exit(2)
end
cacheDir = cacheDir:gsub('[/\\]$', '')
local f = assert(io.open(romPath, 'rb')); local romData = f:read('*a'); f:close()
local mf = assert(io.open('tools/rom_manifest_emerald.json', 'rb'))
local manifest = require('src.link.Json').decode(mf:read('*a')); mf:close()
local LuaWriter = require('src.import.LuaWriter')
local constants = assert(loadfile(cacheDir .. '/constants.lua'))()
local Gen3 = require('src.import.RomExtractorGen3')
local x = Gen3.new(romData, 'emerald', manifest, nil)
x._constants = constants
local wrote
x.write = function(_, name, value) wrote = value end
x:extractMirageTower()
assert(wrote and wrote.gen3MirageTower, 'the stage did not produce gen3MirageTower')
local out = assert(io.open(cacheDir .. '/constants.lua', 'wb'))
out:write(LuaWriter.encodeSplit and LuaWriter.encodeSplit(wrote) or LuaWriter.encode(wrote))
out:close()
local m = wrote.gen3MirageTower
print(('wrote %s/constants.lua: %d tower tile bytes, %d tilemap entries, fossil %d, crumbles %d, palettes brendan=%s may=%s')
  :format(cacheDir, #m.tiles / 2, #m.tilemap, #m.fossil / 2, #m.crumbles / 2,
    tostring(m.playerPalettes.brendan ~= nil), tostring(m.playerPalettes.may ~= nil)))
