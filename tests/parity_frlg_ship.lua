-- Synthetic ROM data: no cartridge bytes are embedded in this regression.
package.path = "./?.lua;./?/init.lua;" .. package.path
_G.love = _G.love or require("tests.love_stub")
local S = require("tests.harness").suite("FRLG ship composition")
local Extractor = require("src.import.RomExtractorGen3")
local bytes = {}
local function u16(at, value)
  bytes[at], bytes[at + 1] = value % 256, math.floor(value / 256)
end
-- The first subsprite table contains four 64x32 pieces.
bytes[100] = 4
for i = 0, 3 do
  local at = 200 + i * 4
  bytes[at] = (i % 2 == 0 and -32 or 32) % 256
  bytes[at + 1] = (i < 2 and -16 or 16) % 256
  u16(at + 2, 1 + 3 * 4 + i * 32 * 16 + 2 * 16384)
end
local rom = {
  u8 = function(_, at) return bytes[at] or 0 end,
  u16 = function(_, at) return (bytes[at] or 0) + (bytes[at + 1] or 0) * 256 end,
  pointer = function(_, at) if at == 104 then return 200 end end,
}
local raw = {}
for i = 0, 4095 do raw[i + 1] = (math.floor(i / 1024) + 1) * 17 end
local extractor = setmetatable({ rom = rom }, { __index = Extractor })
local px = extractor:overworldFramePixels(raw, 128, 64, 100)
for y = 1, 64 do
  for x = 1, 128 do
    local expected = 1 + (x > 64 and 1 or 0) + (y > 32 and 2 or 0)
    assert(px[y][x] == expected, ("ship piece at %d,%d: %s ~= %s"):format(x,y,px[y][x],expected))
  end
end
S.check(true, "four contiguous OAM pieces compose into their spatial quadrants")
local plain = extractor:overworldFramePixels({17, 17, 17, 17}, 8, 8)
S.check(plain[1][1] == 1 and plain[1][8] == 1, "ordinary single sprites retain tile decoding")
local G = require("src.script.Gen3Commands")
local NPC = require("src.world.NPC")
local boat = setmetatable({def={localId=1}, cellX=33, cellY=6,
  px=528, py=96, facing="down", sliding=true}, {__index=NPC})
local runner = {yield=function() end, resume=function() end}
local ow = {entities={boat}, player={px=528}, fieldTasks={}}
G.SPECIALS[0x1000 + 401]({overworld=ow, runner=runner, save={}})
for i=1,49 do runner.waitingCheck() end
S.check(ow.ssAnneDepartureFx == nil, "wake waits through the initial 50-frame horn pause")
runner.waitingCheck()
S.check(ow.ssAnneDepartureFx and ow.ssAnneDepartureFx.boat == boat,
        "wake is created when the ship starts moving")
for i=1,50 do runner.waitingCheck() end
S.check(boat.px == 528 and boat.cellX == 33, "departure preserves map and collision position")
local _, drawX = boat:pose()
S.check(drawX == 518, "departure slides its render pose one pixel per five frames")
S.check(type(runner.waitingCheck) == "function", "departure remains a live script wait beyond watchdog timeout")
for i=1,19 do runner.waitingCheck() end
S.check(#ow.ssAnneDepartureFx.smoke == 0, "smoke waits for its 70-frame cadence")
runner.waitingCheck()
S.check(#ow.ssAnneDepartureFx.smoke == 1,
        "first smoke puff appears on the 70th movement frame")
local finished = false
for i=1,3000 do
  if runner.waitingCheck and runner.waitingCheck() then finished=true break end
end
S.check(finished, "departure eventually releases the script after its final horn pause")
S.check(ow.ssAnneDepartureFx == nil, "departure clears its wake and smoke when the cutscene ends")
S.finish()
