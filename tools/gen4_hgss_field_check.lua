-- Run:  python tools/run_lua_check.py tools/gen4_hgss_field_check.lua [<HeartGold .nds>]
--
-- HeartGold / SoulSilver's field rendering fixes (docs/hgss-bw-import.md,
-- "Water, the shoreline, the "!" and the ledge hop"):
--   1. the area's /a/1/4/0 texture animation, mapped POSITIONALLY onto a
--      chunk's materials (Gen4HgssTexAnim / Gen4TerrainAnim)
--   2. the "!" anchored 32 world units up through the camera (Gen4EmoteDraw)
--   3. the ledge hop's height from the cartridge's jump table (Gen4Jump)
-- With a ROM path it also reads /a/1/4/0 and the area records off it.

package.path = './?.lua;./?/init.lua;' .. package.path
love = love or { math = { random = math.random } }

local PASS, FAIL = 0, 0
local function check(cond, label)
  if cond then PASS = PASS + 1 else FAIL = FAIL + 1; print('FAIL: ' .. label) end
end

-- ============================ 1. the water
local T = require('src.import.Gen4HgssTexAnim')
check(T.areaAnim(string.char(0, 0, 2, 0, 0xFF, 0xFF, 1, 1)) == nil, '0xFFFF names no animation')
check(T.areaAnim(string.char(0, 0, 2, 0, 1, 0, 1, 1)) == 1, 'the record\'s +4 is the /a/1/4/0 member')
check(T.SKIP_LAND[0xD0] and T.SKIP_LAND[0xD2] and T.SKIP_LAND[0xD3] and not T.SKIP_LAND[0xD1],
      'chunks 0xD0, 0xD2, 0xD3 are left still (sub_02054E20)')

local A = require('src.render.Gen4TerrainAnim')
check(A.forMap({}, { texture = 2 }) == nil, 'a map with no animation gets none (Platinum, rooms)')
local terrain = {
  texAnims = { [0] = { kind = 'BTA0', frames = 4, srt = {
    { name = 'pond_on', translateS = { 0, -0.25, -0.5, -0.75 } },
    { name = 'swave_p', translateT = { 0.6, 0.7, 0.8, 0.7 } } } } },
  texAnimLand = { [5] = { 'pond_on', 'swave_p' }, [6] = { 'odd_a', 'odd_b' } },
  texAnimSkip = { [0xD0] = true },
}
local anim = A.forMap(terrain, { texAnim = 0 })
check(anim ~= nil, 'a map whose area names an animation gets it')
local m = anim:materials(5, 2 * A.TICKS_PER_FRAME)       -- field frame 2
check(m and m.swave_p and math.abs(m.swave_p.uv[6] - 0.8) < 1e-9, 'swave_p at field frame 2 is 0.8')
check(m and m.pond_on and math.abs(m.pond_on.uv[5] + 0.5) < 1e-9, 'pond_on scrolls S')
local odd = anim:materials(6, 0)
check(odd and odd.odd_a and odd.odd_b and not odd.pond_on,
      'entry i drives the chunk\'s material i, whatever its name (mapData[i] = i | 0x100)')
check(anim:materials(0xD0, 0) == nil, 'a skipped chunk is not animated')
check(anim:materials(99, 0) == nil, 'a chunk with no recorded order is not animated')

-- ============================ 2. the "!"
local E = require('src.import.Gen4Emotes')
check(E.ticksFor({ cameraFamily = 'hgss' }) == 2 and E.ticksFor({}) == 1,
      'HGSS plays the emote at the field\'s rate; Platinum as before')
check(E.framesFor({ cameraFamily = 'hgss' }) == 74 and E.framesFor({}) == 37, 'its life in ticks')
local D = require('src.world.Gen4EmoteDraw')
check(D.applies({ def = { cameraFamily = 'hgss' } }) and not D.applies({ def = {} }),
      'the cartridge anchor is HGSS\'s; Platinum keeps the sprite top')
check(D.rise({ cameraFamily = 'hgss' }, 2) == 6 and D.rise({ cameraFamily = 'hgss' }, 6) == 12,
      'the bounce at the field\'s rate')
local ground = { heightScale = 0.66, groundScale = 0.751,
                 rise = function() return 0 end }
local npc = { px = 96, py = 160, sprite = { tileW = 32, tileH = 32, offsetX = 8, offsetY = 16, cellYBias = -4 } }
local cam = { x = 0, y = 160 }   -- py - camY = 0 at groundScale < 1: rise 0
local bx, by = D.flatSpot(ground, npc, cam, 16, 16, 0)
-- feet at 12; anchor 32 x 0.66 = 21.1 up, +0.75 toward the camera
check(by + 16 == math.floor(12 - 32 * 0.66 + 0.751 + 0.5), 'the bubble\'s bottom is 32 units up at cos(pitch)')
check(bx == 96 - 8 + 16 - 8, 'centred on the sprite')

-- ============================ 3. the hop
local J = require('src.world.Gen4Jump')
local seq = {}
for remaining = 31, 0, -2 do seq[#seq + 1] = J.units(remaining, 32) end
check(table.concat(seq, ',') == '6,8,10,11,12,12,12,11,10,9,8,6,4,0,0,0',
      'sJumpHeights_High at the field\'s rate: got ' .. table.concat(seq, ','))
check(J.units(0, 32) == 0, 'landed is on the ground')
local p = io.open('src/world/Player.lua'):read('a')
local freeAt = p:find('return self:freeWalk(free[1], free[2], free[3], free[4])', 1, true)
local hopAt = p:find('if self.hopFrames and self.hopFrames > 0 then self.hopFrames = self.hopFrames - 1 end', 1, true)
check(freeAt and hopAt and hopAt < freeAt, 'the free cameras\' update counts the hop down too')

-- ============================ ROM
local rom = arg and arg[1]
if rom and rom ~= '' then
  local X = assert(require('src.import.RomExtractorGen4').new(rom, 'heartgold'))
  local arc = X:archiveAt(T.ARCHIVE)
  check(arc and arc.count == 2, '/a/1/4/0 holds two animations')
  local a0, a1 = T.parse(arc:get(0)), T.parse(arc:get(1))
  check(a0 and a0.name == 'area00_ani' and a0.frames == 360 and #a0.srt == 8, 'area00_ani: 8 materials, 360 frames')
  check(a1 and a1.name == 'dun18_ani' and #a1.srt == 5, 'dun18_ani: 5 materials')
  local order = T.materialOrder(X:archive('land'):get(0), 8)
  check(order and table.concat(order, ',') == 'pond_on,swave_p,pond_edge,sea_line02,sea_un,sea_on,river,river_r',
        'land 0 opens with area00_ani\'s materials in its order')
  X:close()
end

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
