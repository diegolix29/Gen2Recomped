-- Run:  python tools/run_lua_check.py tools/emerald_screen_fx_check.lua
--
-- EMERALD'S SCRIPTED SCREEN EFFECTS (src/world/Gen3ScreenFx.lua) against
-- field_specials.c's Task_ShakeCamera and field_screen_effect.c's
-- Task_OrbEffect -- and the waitstate that waits for them.

package.path = './?.lua;./?/init.lua;' .. package.path
love = require('tests.love_stub')
local PASS, FAIL = 0, 0
local function check(c, l) if c then PASS = PASS + 1 else FAIL = FAIL + 1; print('FAIL: ' .. l) end end

local Fx = require('src.world.Gen3ScreenFx')

-- ShakeCamera(1, 1, 8, 5): eight flips, five frames apart, then let go
local ow = {}
Fx.shakeCamera(ow, 1, 1, 8, 5)
local resumed = 0
check(Fx.wait(ow, function() resumed = resumed + 1 end), 'waitstate parks on a running shake')
local frames, pans = 0, {}
while ow.g3Shake and frames < 200 do
  Fx.tick(ow); frames = frames + 1
  if ow.g3Pan then pans[#pans + 1] = ow.g3Pan.y end
end
check(frames == 40, 'eight shakes five frames apart take forty frames (' .. frames .. ')')
check(pans[1] == -1 and pans[6] == 1, 'the pan flips sign every shake')
check(resumed == 1 and ow.g3Pan == nil, 'the script resumes when it ends, the camera recentred')
check(not Fx.wait(ow, function() end), 'nothing running: waitstate goes straight on')
check(not Fx.shakeCamera(ow, 1, 1, 0, 5), 'no shakes asked for is no shake')
Fx.shakeCamera(ow, 2, 1, 16, 3, true)
check(not Fx.pending(ow), 'the Mirage Tower\'s crumble shake is not one the script waits for')
ow.g3Shake = nil; ow.g3Pan = nil

-- the Orb: red at 104 for VAR_RESULT 0, blue at 136 for 1, centred otherwise
Fx.orb(ow, 1)
check(ow.g3Orb.blue and ow.g3Orb.cx == 136, 'VAR_RESULT 1 is Kyogre\'s blue, at 136')
Fx.orb(ow, 0)
check(not ow.g3Orb.blue and ow.g3Orb.cx == 104, 'VAR_RESULT 0 is Groudon\'s red, at 104')
resumed = 0
check(Fx.wait(ow, function() resumed = resumed + 1 end), 'the growing circle holds the script')
frames = 0
while ow.g3Orb.state == 'grow' and frames < 1000 do Fx.tick(ow); frames = frames + 1 end
check(frames == 160, 'radius 1 to past 160, 2 every second frame: 160 frames (' .. frames .. ')')
check(resumed == 1, 'grown, the script goes on')
local rocks = {}
for _ = 1, 16 do Fx.tick(ow); rocks[#rocks + 1] = ow.g3Orb.pan end
check(rocks[4] == 4 and rocks[8] == -4, 'the camera rocks 4 px every 4 frames')
local px, py = Fx.pan(ow)
check(px == 0 and math.abs(py) == 4, 'the rocking is vertical')
Fx.fadeOutOrb(ow)
resumed = 0
check(Fx.wait(ow, function() resumed = resumed + 1 end), 'the fade holds a waitstate too')
frames = 0
while ow.g3Orb and frames < 2000 do Fx.tick(ow); frames = frames + 1 end
-- 12 EVA steps and 9 EVB steps, alternating from EVA, every 8 frames: the
-- last EVA step is the 23rd step
check(frames == 23 * 8, 'the blend steps out in 23 eight-frame steps (' .. frames .. ')')
check(resumed == 1 and Fx.pan(ow) == nil, 'and lets the script go, the camera still')

-- the window: a circle, symmetric, a span per row
local spans = Fx.spans(120, 80, 10)
check(spans[80][1] == 110 and spans[80][2] == 130, 'the centre row spans the diameter')
check(spans[70] and spans[90] and spans[70][1] == spans[90][1], 'top and bottom rows match')
check(spans[69] == nil and spans[91] == nil, 'nothing past the radius')

-- the specials and waitstate, through the command table
local G3 = require('src.script.Gen3Commands')
local save = { gen3Vars = { [0x8004] = 1, [0x8005] = 1, [0x8006] = 8, [0x8007] = 5, [0x800D] = 1 } }
local ow2 = {}
G3.SPECIALS[312]({ save = save, overworld = ow2 })
check(ow2.g3Shake and ow2.g3Shake.shakes == 8 and ow2.g3Shake.delay == 5, 'special 312 reads its four vars')
local parked = false
local runner = { yield = function() parked = true end, resume = function() parked = false end }
require('src.script.Commands').g3_wait_state({ save = save, overworld = ow2, runner = runner })
check(parked, 'waitstate after ShakeCamera parks the runner')
while ow2.g3Shake do Fx.tick(ow2) end
check(not parked, '...and the shake ending resumes it')
G3.SPECIALS[284]({ save = save, overworld = ow2 })
check(ow2.g3Orb and ow2.g3Orb.blue, 'special 284 reads VAR_RESULT')
G3.SPECIALS[285]({ save = save, overworld = ow2 })
check(ow2.g3Orb.state == 'fade', 'special 285 starts the fade')

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
