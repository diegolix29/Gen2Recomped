-- Run:  python tools/run_lua_check.py tools/gen3_trades_extract.lua <emerald|firered> <.gba> <cache dir>
--
-- Re-runs RomExtractorGen3:extractTrades against an EXISTING Emerald /
-- FireRed cache and rewrites `gen3Trades` in its constants.lua, without a
-- full re-import.  Needed once for a FireRed cache made before the trade
-- scan accepted the cartridge's apostrophe ($B4): those hold only the last
-- five of the nine trades, so every trade special read the wrong record.

package.path = './?.lua;./?/init.lua;' .. package.path
love = require('tests.love_stub')
local game, romPath, cacheDir = arg and arg[1], arg and arg[2], arg and arg[3]
if not (game and romPath and cacheDir) then
  print('usage: gen3_trades_extract.lua <emerald|firered> <.gba> <cache dir>')
  os.exit(2)
end
cacheDir = cacheDir:gsub('[/\\]$', '')
local f = assert(io.open(romPath, 'rb')); local romData = f:read('*a'); f:close()
local mf = assert(io.open('tools/rom_manifest_' .. game .. '.json', 'rb'))
local manifest = require('src.link.Json').decode(mf:read('*a')); mf:close()
local x = require('src.import.RomExtractorGen3').new(romData, game, manifest, nil)
local constantsPath = cacheDir .. '/constants.lua'
local constants = dofile(constantsPath)
local before = type(constants.gen3Trades) == 'table' and #constants.gen3Trades or 0
x._constants = constants
x.write = function() end
x.beginStage = function() end
x:extractTrades()
assert(constants.gen3Trades and #constants.gen3Trades > 0, 'the stage produced nothing')
local out = assert(io.open(constantsPath, 'wb'))
out:write(require('src.import.LuaWriter').encodeSplit(constants))
out:close()
print(('gen3Trades: %d -> %d records in %s'):format(before, #constants.gen3Trades, constantsPath))
