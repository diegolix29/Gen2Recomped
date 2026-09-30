-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- CAN EVERY HOENN MAP ACTUALLY BE DRAWN?
--
-- Reported from play: "petalburg gym in emerald still showing as a black
-- background when i warp through the rooms even with no mods on."
--
-- A Gen 3 map draws by looking each cell's metatile id up in a sheet baked
-- from its tileset PAIR. An id past the end of that sheet gets no quad and the
-- cell draws NOTHING -- not a wrong tile, nothing -- and a room made mostly of
-- such cells is a black room. There is no error and no warning: the fill loop
-- simply skips the cell.
--
-- The id space is the trap. It does NOT run 0..(primary + secondary): it splits
-- at `metatilesInPrimary` (512), so id 511 is the primary's last slot and 512
-- is the SECONDARY'S FIRST, whatever the primary actually filled in. Emerald's
-- outdoor primary defines all 512 and summing the two counts is right for it;
-- its INDOOR primary defines EIGHT, and summing there put every interior's ids
-- past the end of the sheet. That is a fixed bug -- see the note in
-- RomExtractorGen3 -- and this is what keeps it fixed, for every map at once
-- rather than for the one room somebody happened to walk into.
--
-- Section 3 then takes Petalburg Gym apart specifically, because it is the map
-- the report names and the most extreme one in the region: nine blocks wide
-- against a fifteen-block screen, 112 tall, and 36 of its 38 warps point back
-- at itself -- the rooms are stacked inside ONE layout and the doors between
-- them are self-warps. Every room's camera is filled here and the cells are
-- counted.
--
-- WHAT A GREEN RUN MEANS, and this matters because the report is not fixed:
-- the DATA can draw. Every cell of every room resolves to a picture in the
-- sheet at every camera the rooms put it at. If the screen is still black in
-- a real session, it is not the tiles, the tileset pair, the id space or the
-- window bounds -- it is something the live session does that this cannot see,
-- and `[gen3window]` in probe.txt is what names it there.
--
-- Usage: texlua tools/gen3_map_render_check.lua [path/to/emerald/data/generated]

local root = (arg[0] or ""):gsub("[^/\\]*$", "")
if root ~= "" then package.path = root .. "../?.lua;" .. package.path end
package.path = "./?.lua;" .. package.path

local fails, checks = 0, 0
local function ok(cond, fmt, ...)
  checks = checks + 1
  if not cond then
    fails = fails + 1
    io.write("FAIL: ", (select("#", ...) > 0) and fmt:format(...) or fmt, "\n")
  end
end
local function section(n) io.write(("\n-- %s\n"):format(n)) end

-- ---------------------------------------------------------------------------
-- A RECORDING LOVE, enough to bake a tileset pair and fill a window.
--
-- Not a mock that answers plausibly: the sprite batch COUNTS what is added to
-- it, because "how many cells got a picture" is the whole question and a stub
-- that swallows `add` would answer it the same way whether the map drew or not.
-- ---------------------------------------------------------------------------
local function fakeBatch(img)
  local b = { n = 0, img = img }
  function b:clear() self.n = 0 end
  function b:add() self.n = self.n + 1 end
  function b:setTexture(t) self.img = t end
  function b:release() end
  return b
end
local function fakeImage(w, h)
  local i = { w = w or 1, h = h or 1 }
  function i:getWidth() return self.w end
  function i:getHeight() return self.h end
  function i:release() end
  function i:setFilter() end
  return i
end
love = {
  timer = { getTime = function() return 0 end },
  image = { newImageData = function(w, h)
    local d = fakeImage(w, h)
    function d:setPixel() end
    return d
  end },
  graphics = {
    newSpriteBatch = fakeBatch,
    newQuad = function(x, y, w, h, sw, sh) return { x, y, w, h, sw, sh } end,
    newImage = function(d) return fakeImage(d and d.w, d and d.h) end,
    newCanvas = function(w, h) return fakeImage(w, h) end,
    draw = function() end, setColor = function() end,
    getColor = function() return 1, 1, 1, 1 end,
    push = function() end, pop = function() end, origin = function() end,
    setScissor = function() end, getScissor = function() end,
    clear = function() end, rectangle = function() end,
    getCanvas = function() return nil end, setCanvas = function() end,
    setBlendMode = function() end, getBlendMode = function() return "alpha" end,
    translate = function() end, scale = function() end,
    getWidth = function() return 240 end, getHeight = function() return 160 end,
  },
  filesystem = { getInfo = function() return nil end },
  system = { getOS = function() return "Linux" end },
}

local dataRoot = arg and arg[1] or "G:/Gen2Recomped/emerald/data/generated"
local function load(name)
  local chunk = loadfile(dataRoot .. "/" .. name .. ".lua")
  if not chunk then return nil end
  local okRun, value = pcall(chunk)
  return okRun and value or nil
end
local data = {
  maps = load("maps"), tilesets = load("tilesets"),
  map_tilesets = load("map_tilesets"), constants = load("constants"),
  field = {},
}
if not (data.maps and data.tilesets and data.map_tilesets) then
  io.write(("  cannot read the generated Emerald data at %s\n"):format(dataRoot))
  io.write("\n  Pass the generated Emerald data root as the first argument.\n")
  os.exit(2)
end

-- ---------------------------------------------------------------------------
section("1. every map's tileset pair exists, and knows how big its id space is")
-- ---------------------------------------------------------------------------
-- maps.lua carries a `_romInfo` record alongside the maps; a map is a record
-- with BLOCKS in it, which is also exactly what this file is about.
local function isMap(def)
  return type(def) == "table" and type(def.blocks) == "string"
     and type(def.width) == "number"
end
local mapCount, pairUse = 0, {}
for id, def in pairs(data.maps) do
 if isMap(def) then
  mapCount = mapCount + 1
  local pair = def.tileset and data.tilesets[def.tileset]
  ok(pair ~= nil, "%s wants tileset %s, which is not in the tilesets registry",
     id, tostring(def.tileset))
  if pair then
    pairUse[def.tileset] = (pairUse[def.tileset] or 0) + 1
    ok(type(pair.metatileCount) == "number" and pair.metatileCount > 0,
       "%s has no metatile count, so nothing can tell a valid id from a "
       .. "missing one", tostring(def.tileset))
  end
 end
end
local pairCount = 0
for _ in pairs(pairUse) do pairCount = pairCount + 1 end
io.write(("  %d maps over %d tileset pairs\n"):format(mapCount, pairCount))
ok(mapCount > 400, "only %d maps loaded", mapCount)

-- ---------------------------------------------------------------------------
section("2. no map names a metatile its pair does not have")
-- ---------------------------------------------------------------------------
-- THE BLACK-ROOM CLASS, for the whole region at once.  Reading the blocks the
-- way the renderer does -- ten bits, the same `% 1024` MapLoader's blockArray
-- applies -- and asking the same question the fill loop asks.
local worst, worstMap, offenders = nil, nil, 0
local byte = string.byte
for id, def in pairs(data.maps) do
  local pair = isMap(def) and def.tileset and data.tilesets[def.tileset]
  local blocks = isMap(def) and def.blocks
  if pair and blocks then
    local limit = pair.metatileCount or 0
    local hi, over = -1, 0
    for i = 1, math.floor(#blocks / 2) do
      local lo, up = byte(blocks, i * 2 - 1, i * 2)
      local v = (lo + up * 256) % 1024
      if v > hi then hi = v end
      if v >= limit then over = over + 1 end
    end
    checks = checks + 1
    if over > 0 then
      fails = fails + 1
      offenders = offenders + 1
      if offenders <= 8 then
        io.write(("FAIL: %s names %d cell(s) at or past its pair's %d "
                  .. "metatiles (highest id %d) -- every one of them draws "
                  .. "NOTHING\n"):format(id, over, limit, hi))
      end
    end
    -- and the HEADROOM, so a pair that only just fits is visible rather than
    -- merely passing. Petalburg Gym's highest id is 735 against 736 slots: it
    -- fits by exactly one, which is worth knowing about before something
    -- changes the id space by one.
    local slack = limit - 1 - hi
    if worst == nil or slack < worst then worst, worstMap = slack, id end
  end
end
io.write(("  tightest fit: %s, %d slot(s) of headroom above its highest id\n")
         :format(tostring(worstMap), worst))
ok(offenders == 0, "%d maps name a metatile their tileset pair does not have",
   offenders)

-- ---------------------------------------------------------------------------
section("3. Petalburg Gym draws, in every one of its rooms")
-- ---------------------------------------------------------------------------
local GYM = "MAP_G08_N01"
local gym = data.maps[GYM]
ok(gym ~= nil, "%s is not in the dataset", GYM)
if gym then
  ok(gym.width == 9 and gym.height == 112,
     "the gym is %sx%s; the cartridge's layout is 9x112",
     tostring(gym.width), tostring(gym.height))
  -- 36 of the 38 warps point back at this map: the rooms are one layout
  local self_, other = 0, 0
  for _, w in ipairs(gym.warps or {}) do
    if w.destMap == GYM then self_ = self_ + 1 else other = other + 1 end
  end
  io.write(("  %d warps, %d of them back into this map\n")
           :format(self_ + other, self_))
  ok(self_ >= 30, "only %d of the gym's warps are self-warps; the rooms are "
     .. "supposed to be one layout", self_)

  local MapLoader = require("src.world.MapLoader")
  local okLoad, map = pcall(MapLoader.load, data, GYM)
  ok(okLoad, "the gym would not load: %s", tostring(map))
  if okLoad then
    local r = map.renderer
    ok(r ~= nil, "the gym built no renderer")
    ok(r and r.gen3 ~= nil,
       "the gym's tileset pair did not bake, so the map falls through to a "
       .. "tile path a Gen 3 tileset has no sheet for -- which draws blank")
    if r and r.gen3 then
      io.write(("  sheet %dx%d, %s metatiles in %s slots\n")
               :format(r.gen3.width, r.gen3.height, tostring(r.gen3.metatiles),
                       tostring(r.gen3.slots)))
      ok((r.gen3.metatiles or 0) >= 736,
         "the sheet holds %s metatiles; the gym's pair is 512 primary slots "
         .. "plus 224 secondary", tostring(r.gen3.metatiles))
    end
    -- the twelve rooms, by the y the cartridge's warps land in
    local ROOMS = { 111, 105, 98, 92, 85, 79, 72, 66, 59, 53, 46, 40 }
    local totalCells, totalDrew = 0, 0
    for _, by in ipairs(ROOMS) do
      local camX, camY = 4 * 16 - 120, by * 16 - 80
      r.win, r.winBatch, r.winBatchTop = nil, nil, nil
      local okW, err = pcall(r.ensureWindow, r, camX, camY, 240, 160)
      ok(okW, "room y=%d raised while filling its window: %s", by, tostring(err))
      if okW then
        local w = r.win
        local n = r.blockTiles
        local cx0, cy0 = math.floor(w.tx0 / n), math.floor(w.ty0 / n)
        local cx1, cy1 = math.ceil(w.tx1 / n), math.ceil(w.ty1 / n)
        local cells, drew, firstBad = 0, 0, nil
        for cy = cy0, cy1 - 1 do
          for cx = cx0, cx1 - 1 do
            cells = cells + 1
            local id = map:blockAt(cx, cy)
            if id and r:gen3QuadFor(id) then drew = drew + 1
            elseif not firstBad then
              firstBad = ("cell %d,%d id %s"):format(cx, cy, tostring(id))
            end
          end
        end
        totalCells, totalDrew = totalCells + cells, totalDrew + drew
        ok(cells > 0, "room y=%d filled an EMPTY window (%d,%d..%d,%d) -- the "
           .. "camera is looking somewhere the map is not", by,
           w.tx0, w.ty0, w.tx1, w.ty1)
        ok(drew == cells, "room y=%d: %d of %d cells have no picture (%s)",
           by, cells - drew, cells, tostring(firstBad))
        -- and the batch took every one of them, which is the thing that is
        -- actually handed to the GPU
        ok(r.winBatch and r.winBatch.n == drew,
           "room y=%d: %d cells resolved but %s reached the batch",
           by, drew, tostring(r.winBatch and r.winBatch.n))
      end
    end
    io.write(("  %d cells across %d rooms, %d with a picture\n")
             :format(totalCells, #ROOMS, totalDrew))
    ok(totalDrew == totalCells, "%d cells in the gym draw nothing",
       totalCells - totalDrew)
    -- A SWEEP THAT CANNOT FAIL SAYS NOTHING.
    --
    -- 1,944 of 1,944 is only worth having if the same sweep can come back
    -- short, so one cell is given an id past the end of the sheet -- which is
    -- exactly the black-room fault section 2 looks for region-wide -- and the
    -- count has to drop by one and come back when it is put back.
    do
      local by = 105
      local camX, camY = 4 * 16 - 120, by * 16 - 80
      local function sweep()
        r.win, r.winBatch, r.winBatchTop = nil, nil, nil
        r:ensureWindow(camX, camY, 240, 160)
        local w, n = r.win, r.blockTiles
        local cx0, cy0 = math.floor(w.tx0 / n), math.floor(w.ty0 / n)
        local cx1, cy1 = math.ceil(w.tx1 / n), math.ceil(w.ty1 / n)
        local cells, drew = 0, 0
        for cy = cy0, cy1 - 1 do
          for cx = cx0, cx1 - 1 do
            cells = cells + 1
            local id = map:blockAt(cx, cy)
            if id and r:gen3QuadFor(id) then drew = drew + 1 end
          end
        end
        return cells, drew
      end
      local baseCells, baseDrew = sweep()
      local before = map:blockAt(4, by)
      map:setBlock(4, by, (r.gen3.slots or 0) + 16)
      local faultCells, faultDrew = sweep()
      map:setBlock(4, by, before)
      local backCells, backDrew = sweep()
      ok(baseDrew == baseCells, "the control sweep is already short: %d of %d",
         baseDrew, baseCells)
      ok(faultDrew == baseDrew - 1,
         "one cell was given an id past the sheet and the count went %d -> %d; "
         .. "it should have dropped by exactly one -- this sweep cannot see a "
         .. "black cell at all", baseDrew, faultDrew)
      ok(faultCells == baseCells, "the planted id changed the window size")
      ok(backDrew == baseDrew, "the cell was not restored: %d, was %d",
         backDrew, baseDrew)
    end
  end
end

-- ---------------------------------------------------------------------------
section("4. the probe that names it in a session this cannot reach")
-- ---------------------------------------------------------------------------
local function slurp(rel)
  local f = io.open(root .. "../" .. rel, "rb") or io.open(rel, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return (s:gsub("\r\n", "\n"))
end
local tr = slurp("src/render/TileRenderer.lua")
ok(tr ~= nil, "could not open TileRenderer.lua")
if tr then
  ok(tr:find('Probe.say("gen3window"', 1, true) ~= nil,
     "the Gen 3 window fill reports nothing, so a black room in somebody "
     .. "else's session leaves no trace of the camera or the cell count")
  -- It has to fire when the fill drew NOTHING, not only once per map -- and
  -- this is ANCHORED TO THE `if`, not a bare find for "drew == 0". The prose
  -- above the report explains the empty-draw case in those very words, so a
  -- bare find matched the COMMENT while the condition itself was gone, and the
  -- planted fault walked through. Fourth time this shape has bitten.
  ok(tr:find('if drew == 0 or not gen3WinSaid[', 1, true) ~= nil,
     "the window report is not keyed on having drawn nothing, which is the "
     .. "one case worth a line every time it happens")
end

io.write(("\n%d checks, %d failed\n"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
