-- Run:  python tools/run_lua_check.py tools/gen4_contest_dressup_check.lua <platinum cache dir>
--
-- THE VISUAL COMPETITION'S DRESS-UP (src/ui/Gen4ContestDressUp.lua and
-- src/import/Gen4DressUp.lua) against overlay022: the accessories' art, the
-- cap by rank, the sixteen points, the chain of attachment, and the score.

package.path = './?.lua;./?/init.lua;' .. package.path
love = require('tests.love_stub')
local PASS, FAIL = 0, 0
local function check(c, l) if c then PASS = PASS + 1 else FAIL = FAIL + 1; print('FAIL: ' .. l) end end
local dir = (arg and arg[1] or 'G:/Gen2Recomped/platinum/data/generated'):gsub('[/\\]$', '')
local function load(n) local f = loadfile(dir .. '/' .. n .. '.lua') return f and f() end

local rec = load('gen4_dressup')
check(rec, 'the cache has gen4_dressup (love tools/gen4_dressup_extract)')
if rec then
  local n, slots = 0, {}
  for id, a in pairs(rec.accessories) do n = n + 1; slots[a.slot] = true end
  check(n == 100, 'a hundred accessories (' .. n .. ')')
  check(slots[0] and slots[1] and slots[2] and not slots[3], 'palette rows 0..2 from member 235')
  check(rec.accessories[0].width == 16 and rec.accessories[83].width >= 16, 'sizes read from each NCGR')
  check(rec.room and rec.room.path, 'the dressing room backdrop')
end
check(require('src.core.Data') and io.open('src/core/Data.lua'):read('*a'):find('"gen4_dressup"', 1, true),
  'Data loads gen4_dressup')

local D = require('src.ui.Gen4ContestDressUp')
check(D.cap(0) == 5 and D.cap(1) == 10 and D.cap(2) == 15 and D.cap(3) == 20 and D.cap(0, true) == 20,
  'out at once: 5 / 10 / 15 / 20 by rank, 20 linked (ov22_02257580)')

local pts = D.gridPoints({ 10, 20, 40, 50 })
check(#pts == 16, 'sixteen points')
check(pts[1][1] == 10 and pts[1][2] == 20 and pts[16][1] == 40 and pts[16][2] == 50, 'corners included')
check(pts[6][1] == 20 and pts[6][2] == 30, 'the thirds, integer-divided as the overlay does')

-- shapes: a filled rectangle
local function rect(l, t, r, b)
  return { box = { l, t, r, b }, opaque = function(x, y) return x >= l and x <= r and y >= t and y <= b end }
end
local mon = rect(100, 100, 160, 160)
local onCorner = rect(95, 95, 105, 105)           -- covers the box's top-left
local inMiddle = rect(125, 125, 135, 135)         -- inside, between the points
local chained = rect(85, 85, 96, 96)              -- touches only onCorner's corner
local far = rect(0, 0, 10, 10)
local worn = D.attached(mon, { inMiddle, far, chained, onCorner })
local set = {}
for _, w in ipairs(worn) do set[w] = true end
check(set[onCorner], 'an accessory over one of the sixteen points is on')
check(not set[inMiddle], 'one between the points is not -- the cartridge\'s own rule')
check(set[chained], 'an accessory touching an attached one is on too (the chain)')
check(not set[far], 'one off to the side is not')
local many = {}
for k = 1, 25 do many[k] = rect(95, 95, 105, 105) end
check(#D.attached(mon, many) == 20, 'at most twenty are kept')

-- the score: each worn accessory's worth in the theme's table
local contest = load('gen4_contest')
if contest then
  local C = require('src.pokemon.Gen4Contest')
  local c = { theme = 0 }
  local data = { gen4_contest = contest }
  local tbl = contest.themes[0]
  local want = (tbl[83] or 0) + (tbl[73] or 0)
  check(C.dressScore(c, data, { { accessory = 83 }, { accessory = 73 } }) == want, 'the score sums the theme table')
end

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
