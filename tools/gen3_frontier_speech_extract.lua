-- Run:  python tools/run_lua_check.py tools/gen3_frontier_speech_extract.lua <emerald .gba> <cache dir>
--
-- Adds `gen3_frontier_speech` -- the Battle Frontier trainers' easy chat
-- lines, RomExtractorGen3:extractFrontierSpeech -- to an EXISTING Emerald
-- cache, without a full re-import.

package.path = './?.lua;./?/init.lua;' .. package.path
love = require('tests.love_stub')
local romPath, cacheDir = arg and arg[1], arg and arg[2]
if not (romPath and cacheDir) then
  print('usage: gen3_frontier_speech_extract.lua <emerald .gba> <cache dir>')
  os.exit(2)
end
cacheDir = cacheDir:gsub('[/\\]$', '')
local f = assert(io.open(romPath, 'rb')); local romData = f:read('*a'); f:close()
local mf = assert(io.open('tools/rom_manifest_emerald.json', 'rb'))
local manifest = require('src.link.Json').decode(mf:read('*a')); mf:close()
local Gen3 = require('src.import.RomExtractorGen3')
local x = Gen3.new(romData, 'emerald', manifest, nil)
local wrote
x.write = function(_, name, value) wrote = value end
x:extractFrontierSpeech()
assert(wrote and wrote[1], 'the stage produced nothing')
local out = assert(io.open(cacheDir .. '/gen3_frontier_speech.lua', 'wb'))
out:write(require('src.import.LuaWriter').encode(wrote))
out:close()
print(('wrote %d trainers to %s/gen3_frontier_speech.lua'):format(#wrote, cacheDir))
