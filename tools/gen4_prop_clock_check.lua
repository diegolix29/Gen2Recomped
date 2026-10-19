-- tools/gen4_prop_clock_check.lua -- the map prop animations that loop on
-- the field clock (src/render/Gen4PropClock.lua).
--
--   python tools/run_lua_check.py tools/gen4_prop_clock_check.lua \
--     "<Platinum .nds>" ["<HeartGold .nds>"]
--
-- 1. the field rate: one animation frame per two engine ticks
-- 2. PLATINUM_LOOPS re-derived from the cartridge: every bm_anime BCA0 member
--    whose bm_anime_list claims are all flags-0 (attached, loop count -1)
-- 3. HGSS: New Bark's windmill (/a/0/4/0 member 27, wk_sp1) is claimed on the
--    clock by /a/1/0/7 and its animation /a/1/0/6 member 5 is a BCA0
-- 4. the pose is read at the field frame, and a Platinum ground plays a
--    PLATINUM_LOOPS record without a `loop` stamp

package.path = "./?.lua;" .. package.path
local here = (arg and arg[0] or ""):gsub("[^/\\]*$", "")
if here ~= "" then package.path = here .. "../?.lua;" .. package.path end

local checks, fails = 0, 0
local function ok(cond, fmt, ...)
  checks = checks + 1
  if not cond then
    fails = fails + 1
    io.write("FAIL: " .. string.format(fmt, ...) .. "\n")
  end
end

local Clock = require("src.render.Gen4PropClock")
local HgssPropAnim = require("src.import.Gen4HgssPropAnim")

-- 1 ---------------------------------------------------------------------
ok(Clock.TICKS_PER_FRAME == 2, "TICKS_PER_FRAME is %s, not 2", tostring(Clock.TICKS_PER_FRAME))
for tick, want in pairs({ [0] = 0, [1] = 0, [2] = 1, [3] = 1, [479] = 239, [480] = 240 }) do
  ok(Clock.fieldFrame(tick) == want, "fieldFrame(%d) = %s, want %d", tick, tostring(Clock.fieldFrame(tick)), want)
end

-- 2 ---------------------------------------------------------------------
local PT, HG = arg and arg[1], arg and arg[2]
if PT then
  local X = require("src.import.RomExtractorGen4").new(PT, "platinum")
  ok(X ~= nil, "could not open %s", PT)
  local list = X and X:archiveAt("/arc/bm_anime_list.narc")
  local anim = X and X:archiveAt("/arc/bm_anime.narc")
  ok(list and anim, "bm_anime_list / bm_anime missing")
  if list and anim then
    local PropAnim = require("src.import.Gen4PropAnim")
    local kinds = {}
    for model = 0, list.count - 1 do
      local entry = PropAnim.parse(list:get(model))
      local kind = HgssPropAnim.classify(entry)
      for _, id in ipairs(kind and entry.ids or {}) do
        kinds[id] = kinds[id] or {}
        kinds[id][kind] = true
      end
    end
    local Graphics = require("src.import.Gen4Graphics")
    local want = {}
    for id, set in pairs(kinds) do
      local bytes = anim:get(id)
      if bytes and Graphics.isCompressed(bytes) then bytes = Graphics.decompress(bytes) end
      local only = set.clock and not (set.script or set.held or set.timeOfDay)
      if only and bytes and bytes:sub(1, 4) == "BCA0" then want[id] = true end
    end
    for id in pairs(want) do
      ok(Clock.PLATINUM_LOOPS[id], "bm_anime %d is a looping BCA0 on the cartridge and is missing from PLATINUM_LOOPS", id)
    end
    for id in pairs(Clock.PLATINUM_LOOPS) do
      ok(want[id], "PLATINUM_LOOPS names bm_anime %d, which the cartridge does not loop", id)
    end
    -- valley windworks: build_model 146 (d2_s01) owns member 25
    local e = PropAnim.parse(list:get(146))
    ok(e and HgssPropAnim.classify(e) == "clock" and e.ids[1] == 25,
       "build_model 146 is not claimed on the clock by member 25")
  end
else
  io.write("skip: no Platinum ROM given\n")
end

-- 3 ---------------------------------------------------------------------
if HG then
  local X = require("src.import.RomExtractorGen4").new(HG, "heartgold")
  ok(X ~= nil, "could not open %s", HG)
  local list = X and X:archiveAt(HgssPropAnim.LISTS.buildings)
  local anim = X and X:archiveAt(HgssPropAnim.ANIMATIONS)
  if list and anim then
    local e = HgssPropAnim.parse(list:get(27))
    ok(HgssPropAnim.classify(e) == "clock", "wk_sp1 (27) is not on the clock")
    ok(e and e.ids[1] == 5, "wk_sp1 (27) does not name animation 5")
    local bytes = anim:get(5)
    ok(bytes and bytes:sub(1, 4) == "BCA0", "/a/1/0/6 member 5 is not a BCA0")
  else
    ok(false, "HGSS prop archives missing")
  end
else
  io.write("skip: no HeartGold ROM given\n")
end

-- 4 ---------------------------------------------------------------------
do
  -- a 240-frame one-joint track whose frame f carries f in its x translation
  local Anim = require("src.import.Gen4Anim")
  local track = {}
  for f = 0, 239 do track[f + 1] = { 1, 0, 0, f, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 } end
  local record = { kind = "BCA0", member = 5, frames = 240, loop = true,
                   tracks = { { index = 1, frames = 240, matrices = Anim.packTrack(track) } } }
  local building = { posed = function(_, f) return f(1) end }
  local ground = { animsByProp = { [27] = { record } }, claimsOnly = true, clock = 0 }
  local object = { model = 27 }
  for _, case in ipairs({ { 0, 0 }, { 1, 0 }, { 2, 1 }, { 101, 50 }, { 480, 0 }, { 482, 1 } }) do
    ground.clock = case[1]
    local m = Clock.pose(ground, object, building)
    ok(m and math.abs(m[4] - case[2]) < 1e-6, "clock %d posed frame %s, want field frame %d",
       case[1], tostring(m and m[4]), case[2])
  end
  -- a script-owned or unstamped HGSS record does not loop
  record.loop = nil
  ground.clock = 10
  ok(Clock.pose(ground, object, building) == nil, "an HGSS record without `loop` was played")
  -- Platinum: member 25 loops unstamped, member 7 (door_op) does not
  local GameVersion = require("src.core.GameVersion")
  local okSet = pcall(GameVersion.set, "platinum")
  if okSet and GameVersion.family() == "platinum" then
    ground.claimsOnly = nil
    record.member = 25
    ok(Clock.pose(ground, object, building) ~= nil, "Platinum's windmill (member 25) did not loop")
    record.member = 7
    ok(Clock.pose(ground, object, building) == nil, "Platinum's door_op (member 7) looped on the clock")
  else
    io.write("skip: GameVersion.set('platinum') unavailable\n")
  end
end

io.write(("\n%d checks, %d failed\n"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
