-- Run:  python tools/run_lua_check.py tools/gen4_snow_check.lua
--
-- PLATINUM'S SNOW (src/render/Gen4SnowView.lua) against the timelines the
-- weather task produces (pokeplatinum src/overlay005/ov5_021D5EB8.c),
-- simulated tick by tick.

package.path = './?.lua;./?/init.lua;' .. package.path
love = love or {}
love.math = love.math or {}
local seed = 12345
love.math.random = function(a, b)
  seed = (seed * 1103515245 + 12345) % 2147483648
  if not b then return seed % a + 1 end
  return a + seed % (b - a + 1)
end

local PASS, FAIL = 0, 0
local function check(cond, label)
  if cond then PASS = PASS + 1 else FAIL = FAIL + 1; print('FAIL: ' .. label) end
end

local V = require('src.render.Gen4SnowView')

-- watch the spawner: the tick each spawn call lands on, and its count
local function timeline(id, ticks)
  V.start(id, false)
  local real = V.state
  for t = 1, ticks do
    V.tick(0, 0)
    if real.state == 3 and not real.at3 then real.at3 = t end
  end
  return real
end

-- SNOWING: state 0 for one tick, then 16 delay + 127 fog in state 1
local st = timeline(5, 400)
check(st.at3 == 1 + 143 + 1 or st.at3 == 1 + 143, ('snowing reaches its steady state after 143 ticks of fade-in (%s)'):format(tostring(st.at3)))
check(st.sp.interval == 14 and st.sp.count == 1, 'and spawns one flake every fifteen ticks')

-- HEAVY_SNOW: 8 + 254
st = timeline(6, 400)
check(st.at3 and math.abs(st.at3 - (1 + 262)) <= 1, ('heavy snow fades in over 262 ticks (%s)'):format(tostring(st.at3)))
check(st.sp.count == 6 and st.sp.interval == 3, 'six flakes every four ticks once steady')
check(#st.list > 20 and #st.list <= 48, ('...about forty live (%d)'):format(#st.list))

-- BLIZZARD: 16 + 127, the layer shown when the fade-in ends, the pool full
st = timeline(7, 300)
check(st.at3 and math.abs(st.at3 - (1 + 143)) <= 1, ('the blizzard fades in over 143 ticks (%s)'):format(tostring(st.at3)))
check(st.layer == true, 'its BG2 layer is on once it is steady')
check(#st.list >= 36 and #st.list <= 48, ('and the 48-flake pool runs near full between spawn calls (%d)'):format(#st.list))
V.stop()
V.tick(0, 0)
check(V.state and V.state.layer == false and V.state.state == 4, 'the layer goes the moment the fade-out starts')
for _ = 1, 400 do V.tick(0, 0) end
check(V.state == nil, 'and the task ends once the last flake has gone')

-- the instant start (a map that loads with snow) is already in full swing
V.start(7, true)
V.tick(0, 0)
check(V.state.state == 3 and #V.state.list == 48, 'a map that loads in a blizzard starts saturated')

-- the wrap (ov5_021D630C)
check(V.WRAP_X == 319 and V.WRAP_Y == 256 and V.MARGIN == -64, 'wrapped at 319 x 256 with a -64 margin')

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
