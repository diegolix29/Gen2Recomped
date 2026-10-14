-- Run:  python tools/run_lua_check.py tools/emerald_mirage_tower_check.lua
--
-- THE MIRAGE TOWER'S COLLAPSE (src/world/Gen3MirageTower.lua) against
-- mirage_tower.c: the cached graphics, the sand it leaves, the cartridge's
-- pixel quirk, how long each effect runs, and the specials that start them.

package.path = './?.lua;./?/init.lua;' .. package.path
love = require('tests.love_stub')
love.math = love.math or {}
love.math.random = love.math.random or function(a, b) return math.random(a, b) end
local PASS, FAIL = 0, 0
local function check(c, l) if c then PASS = PASS + 1 else FAIL = FAIL + 1; print('FAIL: ' .. l) end end

local constants = assert(loadfile('G:/Gen2Recomped/emerald/data/generated/constants.lua'))()
local rec = constants.gen3MirageTower
check(rec, 'the Emerald cache has gen3MirageTower (tools/gen3_mirage_tower_extract.lua)')
if not rec then print(('%d checks, %d failed'):format(PASS + FAIL, FAIL)) os.exit(1) end
check(#rec.tiles == 73 * 64 and #rec.tilemap == 72 and #rec.fossil == 256 and #rec.crumbles == 256,
  '73 tiles, a 6x12 tilemap, a 16x16 fossil and crumbs')
check(rec.tilemap[1] == 0x6001, 'the tilemap\'s first entry is tile 1 in BG palette 6')
check(rec.playerPalettes.brendan and rec.playerPalettes.may, 'both player palettes ride along')

local M = require('src.world.Gen3MirageTower')

-- the pixel quirk: an even pick clears the pixel to its right (the high
-- nibble), an odd one the pixel to its left (the low nibble)
local t = {}
for i = 1, 64 do t[i] = 0xFF end
M.disintegrate(t, 0, 16, 0)
check(t[1] == 0x0F, 'pick 0 clears the high nibble of byte 0')
M.disintegrate(t, 3, 16, 0)
check(t[2] == 0xF0, 'pick 3 clears the low nibble of byte 1')
M.disintegrate(t, 16, 16, 0)
check(t[5] == 0x0F, 'pick 16 (row 1) lands in the tile\'s second row')
local w = {}
for i = 1, 73 * 32 do w[i] = 0xFF end
M.disintegrate(w, 47, 48, 1)
check(w[32 + 5 * 32 + 3 + 1] == 0xF0, 'a tower pick skips tile 0 and walks the 6-wide tile grid')

-- the specials
local blocks, shut = {}, {}
local ow = { map = { id = 'R111', setBlock = function(_, x, y, id, s) blocks[x .. ',' .. y] = id; shut[#shut + 1] = s end },
             player = { px = 19 * 16, py = 59 * 16 } }
local game = { data = { constants = constants, map_tilesets = {} }, save = { player = { gender = 'girl' } } }
M.startShake(ow, game)
check(blocks['18,53'] == 0x251 and blocks['20,57'] == 0x259 and blocks['19,58'] == 0x121, 'the tower\'s cells become sand')
local n = 0 for _ in pairs(blocks) do n = n + 1 end
check(n == 18 and not shut[1], 'eighteen cells, all walkable')
local h0 = ow.g3MirageTower.hofs
M.tick(ow)
check(ow.g3MirageTower.hofs == -h0, 'BG0 flips on the first frame')
M.tick(ow); M.tick(ow)
check(ow.g3MirageTower.hofs == -h0, '...and holds for two')
M.tick(ow)
check(ow.g3MirageTower.hofs == h0, '...then flips back')
M.startDisintegration(ow); M.startFossil(ow, game)
local frames = 0
while ow.g3MirageTower and frames < 2000 do M.tick(ow); frames = frames + 1 end
check(frames > 230 and frames < 260, 'the tower and the fossil are gone after ~4 seconds (' .. frames .. ' frames)')

M.ceilingCrumble(ow, game)
check(#ow.g3MirageCrumbles.sprites == 16 and ow.g3Shake and ow.g3Shake.shakes == 16 and ow.g3Shake.delay == 3, 'sixteen crumbs and StartScreenShake(2, 1, 16, 3)')
frames = 0
while ow.g3MirageCrumbles and frames < 500 do M.tick(ow); frames = frames + 1 end
check(frames > 40 and frames < 120, 'the crumbs land (' .. frames .. ' frames)')
M.ceilingCrumble(ow, game)
ow.map.id = 'elsewhere'; M.tick(ow)
check(ow.g3MirageCrumbles == nil, 'a warp clears what is left')

local G3 = require('src.script.Gen3Commands')
for _, id in ipairs({ 411, 413, 483, 484, 485, 133, 80, 82, 83 }) do
  check(type(G3.SPECIALS[id]) == 'function', 'special ' .. id .. ' is handled')
end
local save = { registeredItem = 'MACH_BIKE' }
G3.SPECIALS[133]({ save = save })
check(save.registeredItem == 'ACRO_BIKE', 'Rydel\'s swap moves the registered bike')
local cs = { save = { contest = { standings = { 3, 1, 2, 4 }, names = { 'A', 'B', 'C', 'D' }, trainers = { 'p', 'q', 'r', 's' }, playerIndex = 0 } } }
G3.SPECIALS[83](cs); G3.SPECIALS[82](cs)
check(cs.save.buffers[1] == 'B' and cs.save.buffers[3] == 'q', 'the contest winner\'s names fill STR_VAR_1 and STR_VAR_3')

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
