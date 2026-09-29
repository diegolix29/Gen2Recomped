-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- tools/gen4_lift_check.lua -- do Sinnoh's six lifts go anywhere.
--
-- THE FAULT THIS EXISTS FOR WAS TWO COMMENTS. `Gen4Events` called warp
-- destination 4095 a "`nowhere` sentinel" and left six warps unresolved;
-- `Gen4ScriptVM` lowered `setspeciallocation` to a noop because a note said it
-- stamped a met location. Both were wrong about the same slot, so every lift in
-- the region -- Jubilife TV, both Hearthome houses, the Veilstone department
-- store, the Resort Area and the Vista Lighthouse -- opened onto nothing.
--
-- The check that matters is the LAST one, and it is not a transcription:
-- reading `setspeciallocation`'s second operand as a WARP INDEX makes all
-- thirteen script sites land on a door whose own destination is the lift car
-- they belong to. Reading it as an x cannot do that, and no table here decides
-- it -- the cache's warp lists do.
--
-- Run:  texlua tools/gen4_lift_check.lua [cache dir]
--
-- Without a cache only the port's own constants are checked, and it SAYS so.

local cacheDir = arg and arg[1]

local root = (arg[0] or ""):gsub("[^/\\]*$", "")
if root ~= "" then package.path = root .. "../?.lua;" .. package.path end
package.path = "./?.lua;" .. package.path

local warned = {}
local logger = {
  warn = function(fmt, ...) warned[#warned + 1] = tostring(fmt) end,
  info = function() end, error = function() end, debug = function() end,
}
local inert = setmetatable({}, { __index = function() return function() end end })
local runtime = { wantsHook = function() return false end,
                  call = function() end, emit = function() end }
table.insert(package.searchers, 1, function(name)
  if name == "src.import.Gen4Elevators" then return nil end
  if name == "src.import.Gen4PlatformLifts" then return nil end
  if name == "src.import.Gen4Maps" then return nil end
  if name == "src.world.Warp" then return nil end
  if name == "src.core.Logger" then return function() return logger end end
  if name == "src.mods.Runtime" then return function() return runtime end end
  if name:sub(1, 4) ~= "src." then return nil end
  return function() return inert end
end)

local Elevators = require("src.import.Gen4Elevators")
local Platforms = require("src.import.Gen4PlatformLifts")
local Gen4Maps = require("src.import.Gen4Maps")
local Warp = require("src.world.Warp")

local fails, checks = 0, 0
local function ok(cond, what, got, want)
  checks = checks + 1
  if cond then io.write(("  ok    %-58s %s\n"):format(what, tostring(got)))
  else fails = fails + 1
       io.write(("  FAIL  %-58s got %s, expected %s\n")
                :format(what, tostring(got), tostring(want))) end
end
local function note(line) io.write("  --    " .. line .. "\n") end

-- ----------------------------------------------------------- the sentinel --

io.write("the dynamic-warp sentinel\n")

ok(Elevators.DYNAMIC_HEADER == 0xfff, "destination header is 0xfff",
   Elevators.DYNAMIC_HEADER, 4095)
ok(Elevators.DYNAMIC_ANCHOR == 0x100, "...paired with anchor 0x100",
   Elevators.DYNAMIC_ANCHOR, 256)
ok(Elevators.WARP_NONE == 0xFFFF, "WARP_ID_NONE as a u16 operand",
   ("0x%X"):format(Elevators.WARP_NONE), "0xFFFF")
ok(#Elevators.CARS == 6, "six lift cars are named", #Elevators.CARS, 6)

-- ------------------------------------------------------------- the floors --

io.write("\nFieldMenu_GetFloorsAbove, transcribed\n")

local rows = 0
for _ in pairs(Elevators.FLOORS_ABOVE) do rows = rows + 1 end
ok(rows == 18, "eighteen cases, as the switch has", rows, 18)
ok(Elevators.FLOORS_ABOVE_DEFAULT == 1,
   "the default is 1, which is Hearthome's `go up`",
   Elevators.FLOORS_ABOVE_DEFAULT, 1)
ok(Elevators.floorsAbove("NOT_A_MAP") == 1,
   "...and an unnamed map takes it",
   Elevators.floorsAbove("NOT_A_MAP"), 1)

-- The runs, asserted as runs rather than row by row: a building's floors step
-- down by one from the bottom up, and a transposed pair inside a run is the
-- mistake a row-by-row check cannot see.
local RUNS = {
  { "Jubilife TV", { "C01R0201", "C01R0202", "C01R0203", "C01R0204" } },
  { "Veilstone Store 1F..5F",
    { "C07R0201", "C07R0202", "C07R0203", "C07R0204", "C07R0205" } },
  { "Hearthome SE house", { "C05R0101", "C05R0102" } },
  { "Hearthome NE house", { "C05R0801", "C05R0802" } },
  { "Resort Area Ribbon Syndicate", { "T07R0101", "T07R0102" } },
  { "Vista Lighthouse", { "C08", "C08R0801" } },
}
for _, run in ipairs(RUNS) do
  local name, ids = run[1], run[2]
  local descending, top = true, Elevators.floorsAbove(ids[1])
  for i = 1, #ids do
    if Elevators.floorsAbove(ids[i]) ~= top - (i - 1) then descending = false end
  end
  ok(descending and Elevators.floorsAbove(ids[#ids]) == 0,
     ("%s counts down to 0"):format(name),
     ("%d..%d"):format(top, Elevators.floorsAbove(ids[#ids])),
     ("%d..0"):format(#ids - 1))
end
ok(Elevators.floorsAbove("C07R0207") == 5,
   "...and Veilstone's basement sits one BELOW its 1F", -- 4 floors above 1F, 5 above B1F
   Elevators.floorsAbove("C07R0207"), 5)

-- -------------------------------------------------------- the floor label --

io.write("\nStringTemplate_SetFloorNumber's index\n")

ok(Elevators.floorEntry(0) == Elevators.FLOOR_B1F,
   "zero is the BASEMENT, not floor zero",
   Elevators.floorEntry(0), Elevators.FLOOR_B1F)
local laddered = true
for f = 1, Elevators.FLOOR_MAX do
  if Elevators.floorEntry(f) ~= Elevators.FLOOR_1F + f - 1 then laddered = false end
end
ok(laddered, "1..5 walk the bank from `1F`",
   ("%d..%d"):format(Elevators.floorEntry(1), Elevators.floorEntry(5)),
   ("%d..%d"):format(Elevators.FLOOR_1F, Elevators.FLOOR_1F + 4))
ok(Elevators.floorLabel(0) == "B1F" and Elevators.floorLabel(3) == "3F",
   "the no-text fallback reads the same way",
   Elevators.floorLabel(0) .. "/" .. Elevators.floorLabel(3), "B1F/3F")

-- ------------------------------------------- the games that share Warp.lua --

io.write("\nGen 1-3, which share Warp.lua and OverworldController\n")

-- BOTH EDITS LIVE IN SHARED CODE, so the cheapest way for this work to break
-- Gold, Crystal or Prism is for the new arm to catch a door it has no business
-- catching. Built here rather than loaded from a cache: what is under test is
-- the dispatch, and a hand-built map says exactly which door is which.
local older = { maps = {
  PLAYERS_HOUSE_1F = { warps = { { x = 4, y = 7, destMap = "NEW_BARK_TOWN", destWarp = 1 },
                                 { x = 5, y = 7, destMap = "PLAYERS_HOUSE_2F", destWarp = 1 } } },
  NEW_BARK_TOWN    = { warps = { { x = 9, y = 9, destMap = "PLAYERS_HOUSE_1F", destWarp = 1 } } },
  MAP_G127_N127    = { warps = { { x = 1, y = 1 } } },
  LITTLEROOT_TOWN  = { warps = { { x = 2, y = 2 }, { x = 6, y = 6 } } },
} }

warned = {}
local function goes(warpDef, save, lastMap, backupWarp)
  local m, x, y = Warp.destination(older, warpDef, lastMap, backupWarp, save or {})
  return ("%s (%s,%s)"):format(tostring(m), tostring(x), tostring(y))
end

ok(goes(older.maps.PLAYERS_HOUSE_1F.warps[1]) == "NEW_BARK_TOWN (9,9)",
   "an ordinary Gen 2 door still resolves",
   goes(older.maps.PLAYERS_HOUSE_1F.warps[1]), "NEW_BARK_TOWN (9,9)")

local lastOutdoor = { id = "NEW_BARK_TOWN", x = 9, y = 9 }
ok(goes({ destMap = "LAST_MAP", destWarp = 1 }, nil, lastOutdoor)
     == "NEW_BARK_TOWN (9,9)", "LAST_MAP still resolves",
   goes({ destMap = "LAST_MAP", destWarp = 1 }, nil, lastOutdoor),
   "NEW_BARK_TOWN (9,9)")

ok(goes({ destMap = "LAST_WARP" }, nil, lastOutdoor,
        { id = "PLAYERS_HOUSE_1F", x = 5, y = 7 }) == "PLAYERS_HOUSE_1F (5,7)",
   "LAST_WARP still resolves",
   goes({ destMap = "LAST_WARP" }, nil, lastOutdoor,
        { id = "PLAYERS_HOUSE_1F", x = 5, y = 7 }), "PLAYERS_HOUSE_1F (5,7)")

-- Gen 3's own dynamic warp is the arm the Gen 4 one now sits in front of, so
-- both of its halves are asserted: the warp id, and the $FF that means
-- "coordinates".
ok(goes({ destMap = "MAP_G127_N127" },
        { gen3DynamicWarp = { map = "LITTLEROOT_TOWN", warp = 1 } })
     == "LITTLEROOT_TOWN (6,6)",
   "gen 3's dynamic warp still names its warp",
   goes({ destMap = "MAP_G127_N127" },
        { gen3DynamicWarp = { map = "LITTLEROOT_TOWN", warp = 1 } }),
   "LITTLEROOT_TOWN (6,6)")
ok(goes({ destMap = "MAP_G127_N127" },
        { gen3DynamicWarp = { map = "LITTLEROOT_TOWN", warp = 0xFF, x = 11, y = 12 } })
     == "LITTLEROOT_TOWN (11,12)",
   "...and $FF still means the coordinates",
   goes({ destMap = "MAP_G127_N127" },
        { gen3DynamicWarp = { map = "LITTLEROOT_TOWN", warp = 0xFF, x = 11, y = 12 } }),
   "LITTLEROOT_TOWN (11,12)")

local older_save = {}
Warp.noteGen4Entrance(older, older_save, older.maps.PLAYERS_HOUSE_1F.warps[1],
                      "NEW_BARK_TOWN", "PLAYERS_HOUSE_1F", 4, 7, "down")
ok(older_save.gen4SpecialLocation == nil,
   "the entrance capture is inert on an ordinary door",
   tostring(older_save.gen4SpecialLocation), "nil")
ok(#warned == 0, "...and none of it logged a thing", #warned, 0)

-- ------------------------------------------------- the nine rising platforms --

io.write("\nPersistedMapFeatures_InitForPlatformLift, transcribed\n")

local lifts, league = 0, 0
for _, row in pairs(Platforms.LIFTS) do
  lifts = lifts + 1
  if row.league then league = league + 1 end
end
ok(lifts == 9, "nine platform lifts, as the enum has", lifts, 9)
ok(league == 6, "...six of them in the Pokemon League", league, 6)
ok(#Platforms.ASKING == 5,
   "...and five ASK -- the five League elevator rooms", #Platforms.ASKING, 5)

-- THE ASYMMETRY IS THE WHOLE RULE and it is easy to read past: the League
-- clears the flag when entered from above, Iron Island never clears it.
local leagueRule, islandRule = 0, 0
for header, row in pairs(Platforms.LIFTS) do
  local atBottom = Platforms.notUsedWhenEnteredMap(header, row.bottomZ)
  local atTop = Platforms.notUsedWhenEnteredMap(header, row.bottomZ + 1)
  if row.league then
    if atBottom and not atTop then leagueRule = leagueRule + 1 end
  else
    if atBottom and atTop then islandRule = islandRule + 1 end
  end
end
ok(leagueRule == 6, "a League room answers yes at the bottom and no above",
   leagueRule .. "/6", "6/6")
ok(islandRule == 3, "...and Iron Island answers yes on both floors",
   islandRule .. "/3", "3/3")
ok(Platforms.notUsedWhenEnteredMap(4095, 0) == true,
   "a map the switch does not name keeps the initialiser's TRUE",
   tostring(Platforms.notUsedWhenEnteredMap(4095, 0)), "true")

local floors = 0
for header, row in pairs(Platforms.LIFTS) do
  if Platforms.floorId(header, row.bottomZ) == Platforms.BOTTOM_FLOOR
     and Platforms.floorId(header, row.bottomZ + 1) == Platforms.TOP_FLOOR then
    floors = floors + 1
  end
end
ok(floors == 9, "floorId splits at the bottom-floor warp on all nine",
   floors .. "/9", "9/9")

-- ---------------------------------------------------------------- a cache --

if not cacheDir then
  io.write("\n(no cache was checked -- pass a cache dir as the first argument\n"
           .. " to verify the six cars, the header ids, the thirteen\n"
           .. " `setspeciallocation` sites and the nine platform lifts\n"
           .. " against real map data)\n")
  io.write(("\n%d checks, %d failures\n"):format(checks, fails))
  os.exit(fails == 0 and 0 or 1)
end

local function load(name)
  local chunk = loadfile(cacheDir .. "/" .. name .. ".lua")
  return chunk and chunk() or nil
end

local maps = load("maps")
if not maps then
  io.write("\ncannot read maps.lua from " .. cacheDir .. "\n")
  os.exit(2)
end

io.write("\nthe six cars, in a cache\n")

local dynamic, byHeader = {}, {}
for id, def in pairs(maps) do
  if def.header then byHeader[def.header] = id end
  for _, w in ipairs(def.warps or {}) do
    if w.destHeader == Elevators.DYNAMIC_HEADER then
      dynamic[#dynamic + 1] = { map = id, warp = w }
    end
  end
end
table.sort(dynamic, function(a, b) return a.map < b.map end)

ok(#dynamic == 6, "six warps carry the sentinel header", #dynamic, 6)

local want = {}
for _, id in ipairs(Elevators.CARS) do want[id] = true end
local unexpected, missing = {}, {}
for _, d in ipairs(dynamic) do
  if want[d.map] then want[d.map] = nil else unexpected[#unexpected + 1] = d.map end
end
for id in pairs(want) do missing[#missing + 1] = id end
ok(#unexpected == 0 and #missing == 0,
   "...and they are exactly the six named cars",
   (#unexpected + #missing == 0) and "exactly"
     or ("extra " .. table.concat(unexpected, ",") .. " missing "
         .. table.concat(missing, ",")),
   "exactly")

local sameShape, marked = true, 0
for _, d in ipairs(dynamic) do
  local w = d.warp
  if not (w.index == 1 and w.x == 3 and w.y == 6
          and w.destWarp == Elevators.DYNAMIC_ANCHOR + 1) then
    sameShape = false
    note(("%s warp %s at (%s,%s) destWarp %s -- not the shape the others have")
         :format(d.map, tostring(w.index), tostring(w.x), tostring(w.y),
                 tostring(w.destWarp)))
  end
  if w.destMap == Elevators.DYNAMIC_MAP then marked = marked + 1 end
end
ok(sameShape, "all six are warp 1 at (3,6) with anchor 0x100",
   sameShape and "identical" or "mixed", "identical")
-- The extractor's marking is what `Warp.resolve` dispatches on. A cache built
-- before that landed leaves destMap nil, which is a STALE CACHE and not a
-- failing port, so it is reported rather than failed.
if marked == 6 then
  ok(true, "...and the extractor marked them dynamic", marked .. "/6", "6/6")
else
  note(("this cache marks %d/6 of them -- it predates the extractor's lift "
        .. "edit, so run an import before trusting the resolution below")
       :format(marked))
end

io.write("\nthe eighteen header ids, against the cache's own labels\n")

local headersOk, floorsOk = 0, 0
for id, row in pairs(Elevators.FLOORS_ABOVE) do
  local def = maps[id]
  if def and def.header == row.header then headersOk = headersOk + 1
  else note(("%s: the table says header %d, the cache says %s")
            :format(id, row.header, def and tostring(def.header) or "no such map")) end
  if def and Elevators.floorsAbove(id) == row.above then floorsOk = floorsOk + 1 end
end
ok(headersOk == 18, "every row's header id lands on the map it names",
   headersOk .. "/18", "18/18")
ok(floorsOk == 18, "...and floorsAbove answers each row's own count",
   floorsOk .. "/18", "18/18")

-- ------------------------------------------ what the second operand means --

io.write("\nthe thirteen `setspeciallocation` sites\n")
note("read as a WARP INDEX. Every site must land on the door into its car.")

-- Every (mapHeaderID, warpId) pair the cartridge's scripts write, from a walk
-- over scr_seq.narc -- twelve lift panels and the Great Marsh's gate. `car` is
-- the map the resolved warp must LEAD TO, which is what makes this a check on
-- the reading of the operand and not a second copy of the operand.
local SITES = {
  { 11,  2, "C01R0208" }, { 12,  3, "C01R0208" },
  { 13,  4, "C01R0208" }, { 14,  1, "C01R0208" },
  { 137, 2, "C07R0206" }, { 138, 2, "C07R0206" },
  { 139, 2, "C07R0206" }, { 140, 2, "C07R0206" },
  { 141, 1, "C07R0206" }, { 566, 1, "C07R0206" },
  { 461, 1, "T07R0103" }, { 462, 0, "T07R0103" },
  -- the Great Marsh: the gate's own door into the marsh, which is where
  -- running out of balls puts you back (encounter.c 484)
  { 125, 2, "D06R0206" },
}
local landed, resolved = 0, 0
for _, s in ipairs(SITES) do
  local header, warpId, wantDest = s[1], s[2], s[3]
  local id = byHeader[header]
  local def = id and maps[id]
  local dw = def and def.warps and def.warps[warpId + 1]
  if dw then
    resolved = resolved + 1
    if dw.destMap == wantDest then landed = landed + 1
    else note(("header %d warp %d is %s's (%s,%s), which leads to %s and not %s")
              :format(header, warpId, tostring(id), tostring(dw.x), tostring(dw.y),
                      tostring(dw.destMap), wantDest)) end
  else
    note(("header %d warp %d does not exist on %s"):format(header, warpId,
         tostring(id)))
  end
end
ok(resolved == #SITES, "every site names a warp the cache has",
   resolved .. "/" .. #SITES, #SITES .. "/" .. #SITES)
ok(landed == #SITES, "...and every one leads to the lift it belongs to",
   landed .. "/" .. #SITES, #SITES .. "/" .. #SITES)

-- ------------------------------------------------------- the round trip --

io.write("\nin and out of the Veilstone store's lift\n")

-- The cache may predate the extractor's marking, so the car's warp is marked
-- here rather than depended on: what is under test is Warp.lua's two halves,
-- not the extractor's (which the count above reports on).
local data = { maps = maps }
local car = maps["C07R0206"]
local carDoor = car and car.warps and car.warps[1]
local floorDoor
for _, w in ipairs((maps["C07R0201"] or {}).warps or {}) do
  if w.destMap == "C07R0206" then floorDoor = w end
end
if carDoor and floorDoor then
  carDoor.destMap = Elevators.DYNAMIC_MAP
  local save = {}
  -- 1. step off 1F into the car
  Warp.noteGen4Entrance(data, save, floorDoor, "C07R0206", "C07R0201",
                        floorDoor.x, floorDoor.y, "up")
  local spot = save.gen4SpecialLocation
  ok(spot ~= nil and spot.map == "C07R0201",
     "arriving in the car remembers the floor you got on at",
     spot and tostring(spot.map) or "nothing", "C07R0201")
  ok(spot ~= nil and spot.warp == (floorDoor.index - 1),
     "...as the cartridge's zero-based event index",
     spot and tostring(spot.warp) or "nil", floorDoor.index - 1)
  -- 2. the panel-less case: which way does the car go from here
  ok(Elevators.floorsAbove(spot and spot.map) == 4,
     "...so `getfloorsabove` answers about 1F and not the car",
     Elevators.floorsAbove(spot and spot.map), 4)
  -- 3. walk straight back out
  local back, bx, by = Warp.destination(data, carDoor, nil, nil, save)
  ok(back == "C07R0201" and bx == floorDoor.x and by == floorDoor.y,
     "walking back out returns to that same door",
     ("%s (%s,%s)"):format(tostring(back), tostring(bx), tostring(by)),
     ("C07R0201 (%d,%d)"):format(floorDoor.x, floorDoor.y))
  -- 4. the panel picks the basement: `setspeciallocation 566 1 ...`
  save.gen4SpecialLocation = { map = byHeader[566], warp = 1, x = 14, y = 2,
                               facing = "down" }
  local down, dx, dy = Warp.destination(data, carDoor, nil, nil, save)
  local b1f = maps[byHeader[566]]
  local bw = b1f and b1f.warps and b1f.warps[2]
  ok(down == byHeader[566] and bw ~= nil and dx == bw.x and dy == bw.y,
     "choosing B1F lands on B1F's own lift door",
     ("%s (%s,%s)"):format(tostring(down), tostring(dx), tostring(dy)),
     ("%s (%s,%s)"):format(tostring(byHeader[566]),
                           bw and tostring(bw.x) or "?",
                           bw and tostring(bw.y) or "?"))
  -- 5. and the refusal, which is the whole reason the bug was invisible
  save.gen4SpecialLocation = nil
  warned = {}
  local none = Warp.destination(data, carDoor, nil, nil, save)
  ok(none == nil and #warned > 0,
     "an unset slot refuses the door and says so",
     none == nil and ("nil, %d warning(s)"):format(#warned) or tostring(none),
     "nil, 1 warning(s)")
else
  ok(false, "the cache carries the Veilstone car and its 1F door",
     "missing", "both")
end

-- ------------------------------------------- the platforms, against a cache --

io.write("\nthe nine platform lifts, in a cache\n")

-- A def only carries `blocks` when it OWNS its grid; four of the League rooms
-- share a matrix and reference `map_layouts` instead, so both are read. Loaded
-- lazily because that file is thirteen megabytes and most runs do not need it.
local layouts = nil
local function gridOf(def)
  if def.blocks then return def.blocks, def.width, def.height end
  if layouts == nil then layouts = load("map_layouts") or false end
  local L = layouts and layouts[def.layout]
  if not L then return nil end
  return L.blocks, L.width or def.width, L.height or def.height
end

local function permission(def, x, y)
  local blocks, w, h = gridOf(def)
  if not blocks then return nil end
  if x < 0 or y < 0 or x >= w or y >= h then return nil end
  local i = (y * w + x) * 2 + 1
  local lo, hi = blocks:byte(i, i + 1)
  if not lo then return nil end
  -- the same ten bits `Map.blockArray` keeps, which is what the engine walks on
  return (lo + hi * 256) % 1024
end

local named, onWarp, slabOpen, withCoord, noCoord = 0, 0, 0, 0, 0
for header, row in pairs(Platforms.LIFTS) do
  local id = byHeader[header]
  local def = id and maps[id]
  if id == row.map then named = named + 1
  else note(("header %d: the table says %s, the cache says %s")
            :format(header, row.map, tostring(id))) end
  if def then
    -- the bottom-floor z is a MATRIX coordinate, so the origin goes back on
    local oy = tonumber(def.originY) or 0
    local hit = false
    for _, w in ipairs(def.warps or {}) do
      if (tonumber(w.y) or -1) + oy == row.bottomZ then hit = true end
    end
    if hit then onWarp = onWarp + 1
    else note(("%s: bottom-floor z %d is not any warp's y")
              :format(tostring(id), row.bottomZ)) end

    local open, total = 0, 0
    for yy = row.start[2], row.start[2] + Platforms.SIZE_Y - 1 do
      for xx = row.start[1], row.start[1] + Platforms.SIZE_X - 1 do
        total = total + 1
        local v = permission(def, xx, yy)
        if v and v ~= Gen4Maps.BLOCKED_CELL then open = open + 1 end
      end
    end
    if open == total and total == Platforms.SIZE_X * Platforms.SIZE_Y then
      slabOpen = slabOpen + 1
    else
      note(("%s: the platform's own %dx%d slab is %d/%d open")
           :format(tostring(id), Platforms.SIZE_X, Platforms.SIZE_Y, open, total))
    end

    local inside = 0
    for _, c in ipairs(def.coordEvents or {}) do
      if c.x >= row.start[1] and c.x < row.start[1] + Platforms.SIZE_X
         and c.y >= row.start[2] and c.y < row.start[2] + Platforms.SIZE_Y then
        inside = inside + 1
      end
    end
    if inside > 0 then withCoord = withCoord + 1
    elseif #(def.coordEvents or {}) == 0 then noCoord = noCoord + 1
    else note(("%s: has %d coord event(s) and none on its platform")
              :format(tostring(id), #def.coordEvents)) end
  end
end
ok(named == 9, "every row's header id lands on the map it names",
   named .. "/9", "9/9")
ok(onWarp == 9, "every bottom-floor z is a real warp's y", onWarp .. "/9", "9/9")
ok(slabOpen == 9, "every platform's own slab is walkable ground",
   slabOpen .. "/9", "9/9")
-- THE START TILES ARE TRANSCRIBED FROM A C TABLE and this is what checks them:
-- a 3x2 slab from each corner has to contain that room's lift trigger. Eight do;
-- the ninth is asserted to have NO trigger rather than assumed to be an
-- exception -- the Champion's room lift is started by the script after Cynthia.
ok(withCoord == 8, "eight slabs contain their room's own lift trigger",
   withCoord .. "/8", "8/8")
ok(noCoord == 1, "...and the ninth room has no trigger at all",
   noCoord .. "/1", "1/1")

-- ...AND THE ONE THAT DECIDES WHETHER THE NO-OP IS HONEST.
--
-- Each League room is a shaft: a warp in the wall at the top and one on the
-- floor at the bottom. If the column between them is open, the lift is scenery
-- and the Elite Four are reachable in order without it. If it is not, this
-- port's `triggerplatformlift` no-op is a wall across the main path -- which is
-- exactly what the six League rooms were never checked for.
io.write("\nis the Pokemon League walkable without its lifts\n")

local shafts, shaftRooms = 0, 0
for header, row in pairs(Platforms.LIFTS) do
  if row.league then
    shaftRooms = shaftRooms + 1
    local def = maps[byHeader[header]]
    local bottom, top
    for _, w in ipairs((def or {}).warps or {}) do
      if (tonumber(w.y) or -1) + (tonumber(def.originY) or 0) == row.bottomZ then
        bottom = w
      end
      if not top or w.y < top.y then top = w end
    end
    if bottom and top and bottom.x == top.x then
      local open, total = 0, 0
      for yy = top.y + 1, bottom.y do
        total = total + 1
        local v = permission(def, bottom.x, yy)
        if v and v ~= Gen4Maps.BLOCKED_CELL then open = open + 1 end
      end
      if total > 0 and open == total then
        shafts = shafts + 1
        note(("%-10s %-38s x=%d, %d/%d open"):format(row.map, row.what,
             bottom.x, open, total))
      else
        note(("%-10s %s -- ONLY %d/%d OPEN, the lift is a GATE here")
             :format(row.map, row.what, open, total))
      end
    else
      note(("%s: its two warps are not in one column (%s vs %s)")
           :format(row.map, bottom and bottom.x or "?", top and top.x or "?"))
    end
  end
end
ok(shafts == 6 and shaftRooms == 6,
   "all six League shafts are open floor end to end",
   shafts .. "/" .. shaftRooms, "6/6")

io.write(("\n%d checks, %d failures\n"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
