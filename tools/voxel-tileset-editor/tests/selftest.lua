-- The self-test.  `love . --test` runs it and quits.
--
-- IT TESTS THE THINGS THAT FAIL SILENTLY.  A serialiser that drops a key, a
-- merge that loses a side table, an export that resolves a tile differently
-- from the profile it came from -- none of those raise, and all of them
-- produce a profile that loads fine and draws the world wrong.  So the
-- round-trip test is the important one: merge the mod's own profile with an
-- EMPTY document, write it, read it back, and check that every tile of
-- every tileset still resolves to the same class, height and fold.  If that
-- passes, the exporter is not editorialising.

local Fs = require("core.Fs")
local Paths = require("core.Paths")
local Cache = require("core.Cache")
local ModBridge = require("core.ModBridge")
local Serialize = require("core.Serialize")
local Shape = require("core.Shape")
local Doc = require("core.Doc")
local Mesh = require("core.Mesh")
local Zip = require("core.Zip")
local Export = require("core.Export")
local Validate = require("core.Validate")
local Classes = require("core.Classes")
local Scene = require("core.Scene")
local Grid = require("core.Grid")
local StructBridge = require("core.StructBridge")
local Schema = require("core.Schema")
local Gen3Bridge = require("core.Gen3Bridge")
local History = require("core.History")
local Render3D = require("ui.Render3D")

local T = {}
local pass, fail = 0, 0

local function ok(cond, name, detail)
  if cond then
    pass = pass + 1
    print("  ok   " .. name)
  else
    fail = fail + 1
    print("  FAIL " .. name .. (detail and ("  -- " .. tostring(detail)) or ""))
  end
end

local function deepEqual(a, b, path)
  path = path or ""
  if type(a) ~= type(b) then return false, path .. " type" end
  if type(a) ~= "table" then
    if a ~= b then return false, path .. " " .. tostring(a) .. " vs " .. tostring(b) end
    return true
  end
  for k, v in pairs(a) do
    local o, why = deepEqual(v, b[k], path .. "." .. tostring(k))
    if not o then return false, why end
  end
  for k in pairs(b) do
    if a[k] == nil then return false, path .. "." .. tostring(k) .. " added" end
  end
  return true
end

-- --------------------------------------------------------------- the tests

local function testSerialize()
  print("serialise")
  local v = {
    version = 1,
    heights = { wall = 16, water = -2, ["odd key"] = 3.5 },
    tilesets = {
      POKECENTER = {
        wall = { 2, 3, 4, 40, 92 },
        counter = { 8, 10, 24 },
        when_above = { [0x4C] = { { above = { 0x3C, 0x4B }, class = "wall" } } },
        heights = { counter = 8 },
        prop_bg = { { tiles = { 32, 33 }, shades = { "light", "white" } } },
        empty = {},
        flagged = true,
      },
    },
  }
  local src = "return " .. Serialize.value(v)
  local chunk = (loadstring or load)(src)
  ok(chunk ~= nil, "serialised source compiles")
  if chunk then
    local back = chunk()
    local eq, why = deepEqual(v, back)
    ok(eq, "serialise round-trips", why)
  end
  ok(Serialize.value(v) == Serialize.value(v), "serialise is deterministic")
  local v2 = { b = 1, a = 2, [3] = "x", [1] = "y" }
  ok(Serialize.value(v2) == Serialize.value(v2), "key order is stable")
  ok(#Serialize.hash(v) == 8, "hash is eight hex digits")
end

local function testZip()
  print("zip")
  ok(Zip.crc32("123456789") == 3421780262, "crc32 of the standard check string",
     Zip.crc32("123456789"))
  local blob = Zip.build({ { name = "a.txt", data = "hello" },
                           { name = "b/c.lua", data = "return 1\n" } })
  ok(blob:sub(1, 4) == "PK\3\4", "zip starts with a local header")
  ok(blob:find("PK\5\6", 1, true) ~= nil, "zip has an end-of-central-directory")
  ok(blob == Zip.build({ { name = "a.txt", data = "hello" },
                         { name = "b/c.lua", data = "return 1\n" } }),
     "the same input builds byte-identical archives")
end

local function testMesh()
  print("mesh")
  local ctx = {
    perRow = 16, atlasW = 128, atlasH = 48,
    pixel = function(_, px, py)
      -- a diagonal drawing on a white ground, so silhouettes have something
      -- to find and the background vote has something to win
      if px == py or px == 7 - py then return 0.1, 0.1, 0.1, 1 end
      return 1, 1, 1, 1
    end,
  }
  local folds = { "flat", "top", "upright", "billboard", "post", "cylinder",
                  "canopy", "planter", "grass", "flower", "relief", "stair",
                  "bookcase" }
  for _, art in ipairs(folds) do
    local q = Mesh.tile({ class = "wall", h = 16, art = art }, ctx,
                        { tx = 0, ty = 0, tile = 5,
                          heightAt = function() return 0 end })
    local bad = nil
    for i, quad in ipairs(q) do
      for k = 1, 4 do
        local p = quad[k]
        if not p or #p ~= 3 then bad = "corner " .. k .. " of quad " .. i break end
        for c = 1, 3 do
          if p[c] ~= p[c] or p[c] == math.huge or p[c] == -math.huge then
            bad = "non-finite coordinate in quad " .. i
          end
        end
      end
      local uv = quad.uv
      if not uv then bad = "quad " .. i .. " has no uv" break end
      for k = 1, 4 do
        if not uv[k] or uv[k][1] < 0 or uv[k][1] > 1
           or uv[k][2] < 0 or uv[k][2] > 1 then
          bad = "uv out of range in quad " .. i
        end
      end
    end
    ok(#q > 0 and not bad, "fold '" .. art .. "' emits sane geometry",
       bad or "no quads")
  end

  -- the band crop, worked by hand: a 6px ledge beside flat ground must show
  -- the BOTTOM six art rows, not the top six and not a stretch
  local q = Mesh.tile({ class = "ledge", h = 6, art = "top" }, ctx,
                      { tx = 0, ty = 0, tile = 0,
                        heightAt = function() return 0 end })
  local south = nil
  for _, quad in ipairs(q) do
    if quad[1][3] == 8 and quad[2][3] == 8 and quad[1][2] == 0 then south = quad end
  end
  ok(south ~= nil, "a 6px ledge draws a south face")
  if south then
    local vTop = south.uv[4][2] * ctx.atlasH
    local vBot = south.uv[1][2] * ctx.atlasH
    ok(vTop > 1.9 and vTop < 2.1 and vBot > 7.9 and vBot < 8.1,
       "the 6px face wears art rows 2..8 (the bottom of the lip drawing)",
       ("vTop=%.2f vBot=%.2f"):format(vTop, vBot))
  end

  -- and no face at all where the neighbour is level
  local q2 = Mesh.tile({ class = "ground", h = 0, art = "flat" }, ctx,
                       { tx = 0, ty = 0, tile = 0,
                         heightAt = function() return 0 end })
  ok(#q2 == 1, "flat ground beside flat ground is one quad, no side faces",
     #q2 .. " quads")

  -- a sculpt at res 8 is 64 columns, and its tops are its own heights
  local sub = { res = 2, h = { 0, 8, 8, 16 } }
  local q3 = Mesh.tile({ class = "wall", h = 16, art = "upright", sub = sub },
                       ctx, { tx = 0, ty = 0, tile = 0,
                              heightAt = function() return 0 end })
  local tops = 0
  for _, quad in ipairs(q3) do
    if quad[1][2] == quad[2][2] and quad[2][2] == quad[3][2] then tops = tops + 1 end
  end
  ok(tops >= 4, "a 2x2 sculpt emits a top per sub-column", tops)
end

local function testValidate()
  print("validate")
  local doc = Doc.new()
  Doc.pin(doc, "POKECENTER", 8, "counter")
  Doc.pin(doc, "POKECENTER", 9999, "wall")
  Doc.pin(doc, "POKECENTER", 10, "not_a_real_class")
  Doc.sculpt(doc, "POKECENTER", 8, 4)
  local fakeCache = {
    tilesets = { POKECENTER = { tilesPerRow = 16, imageWidth = 128,
                                imageHeight = 48 } },
  }
  local v = Validate.run(doc, { fakeCache }, { classInfo = Classes.FALLBACK })
  local outOfRange, unknownClass = false, false
  for _, e in ipairs(v.errors) do
    if e.msg:find("outside this tileset") then outOfRange = true end
  end
  for _, e in ipairs(v.warnings) do
    if e.msg:find("not_a_real_class") then unknownClass = true end
  end
  ok(outOfRange, "a tile id past the end of the sheet is an error")
  ok(unknownClass, "a class the host cannot resolve is a warning, not an error")
  ok(not v.ok, "the run reports not-ok while an error stands")

  local clean = Doc.new()
  Doc.pin(clean, "POKECENTER", 8, "counter")
  local v2 = Validate.run(clean, { fakeCache }, { classInfo = Classes.FALLBACK })
  ok(v2.ok and #v2.warnings == 0, "a good pin reports nothing",
     Validate.summary(v2))
end

local function testExportIsPresentationOnly(bridge, doc)
  print("presentation-only")
  local src = Export.profileLua(bridge, doc, { full = false })
  local banned = { "walkable", "collision", "warpTiles", "doorTiles",
                   "counterTiles", "blocks", "image" }
  local found = nil
  for _, k in ipairs(banned) do
    if src:find("%f[%w]" .. k .. "%s*=") then found = k end
  end
  ok(found == nil, "the export states no collision or asset field", found)
  ok(not src:find("assets/generated"), "the export names no cartridge art")
end

local function testRoundTrip(bridge, caches)
  print("profile round-trip")
  if not bridge.live then
    print("  skip -- no voxel mod install found to round-trip against")
    return
  end

  local empty = Doc.new()
  local merged = Shape.mergeProfile(bridge, empty)
  local eq, why = deepEqual(bridge.profile, merged)
  ok(eq, "merging an empty document changes nothing", why)

  local src = "local profile = " .. Serialize.value(merged) .. "\nreturn profile\n"
  local chunk, cerr = (loadstring or load)(src)
  ok(chunk ~= nil, "the full profile re-compiles", cerr)
  if not chunk then return end
  local back = chunk()

  -- and now the question that matters: does the re-read profile resolve
  -- every tile of every tileset to the same shape as the original?
  local drift, checked = 0, 0
  for _, cache in ipairs(caches) do
    for _, tsId in ipairs(cache.ids) do
      local ts = cache.tilesets[tsId]
      local before = Shape.newResolver(bridge, ts, tsId, nil)
      -- SWAP THE BRIDGE'S PROFILE, not just the data slot: newResolver merges
      -- from `bridge.profile` and pushes the result back through setData, so
      -- setting the slot alone would be overwritten on the next line and the
      -- test would compare the original against itself and pass for nothing.
      local original = bridge.profile
      bridge.profile = back
      local after = Shape.newResolver(bridge, ts, tsId, nil)
      bridge.profile = original
      local geom = Cache.tileGeometry(ts)
      for tile = 0, math.min(geom.count, 256) - 1 do
        local a = before:tile(tile)
        local b = after:tile(tile)
        checked = checked + 1
        if not a or not b or a.class ~= b.class or a.h ~= b.h or a.art ~= b.art then
          drift = drift + 1
          if drift <= 3 then
            print(("    drift %s tile %d: %s/%s/%s -> %s/%s/%s"):format(
              tsId, tile, tostring(a and a.class), tostring(a and a.h),
              tostring(a and a.art), tostring(b and b.class),
              tostring(b and b.h), tostring(b and b.art)))
          end
        end
      end
      -- put the original back before the next tileset
      bridge.V.setData("voxel_heights", bridge.profile)
      bridge.TileShape.invalidate()
    end
  end
  ok(drift == 0, ("every one of %d tiles resolves the same after a round-trip")
     :format(checked), drift .. " drifted")
end

local function testPack(bridge, doc, caches)
  print("pack")
  local blob, plan, files = Export.pack(bridge, doc, caches, { sculpts = false })
  ok(#blob > 0, "the pack builds")
  local names = {}
  for _, f in ipairs(files) do names[f.name] = f.data end
  ok(names["manifest.json"] ~= nil, "the pack has a manifest")
  ok(names["main.lua"] ~= nil, "the pack has an entry point")
  ok(names["manifest.json"]:find("DRAMATIC_SHAPE", 1, true) ~= nil,
     "the manifest depends on the voxel mod")
  local chunk, cerr = (loadstring or load)(names["main.lua"])
  ok(chunk ~= nil, "the generated entry point compiles", cerr)
  ok(names["main.lua"]:find("voxelClassPins", 1, true) ~= nil,
     "the pack states its pins where a second mod is actually read")
  ok(not names["main.lua"]:find("isWalkableCell%s*=") ,
     "the pack writes no collision")
end


local function testPickTags()
  print("pick tags")
  local ctx = {
    perRow = 16, atlasW = 128, atlasH = 48,
    pixel = function() return 1, 1, 1, 1 end,
  }
  local q = Mesh.tile({ class = "wall", h = 16, art = "upright" }, ctx,
                      { tx = 1, ty = 2, tile = 5,
                        heightAt = function() return 0 end })
  local kinds = {}
  for _, quad in ipairs(q) do
    if quad.pick then kinds[quad.pick.kind] = (kinds[quad.pick.kind] or 0) + 1 end
  end
  ok(kinds.top == 1, "the top face is tagged once", kinds.top)
  ok((kinds.side or 0) >= 4, "the side bands are tagged", kinds.side)

  local q2 = Mesh.tile({ class = "wall", h = 16, art = "upright",
                         sub = { res = 2, h = { 0, 8, 8, 16 } } }, ctx,
                       { tx = 0, ty = 0, tile = 0,
                         heightAt = function() return 0 end })
  local subs, coords = 0, {}
  for _, quad in ipairs(q2) do
    if quad.pick and quad.pick.kind == "subtop" then
      subs = subs + 1
      coords[quad.pick.j * 2 + quad.pick.i] = true
    end
  end
  ok(subs == 4, "a 2x2 sculpt tags four sub-columns", subs)
  ok(coords[0] and coords[1] and coords[2] and coords[3],
     "and every one of them is reachable by its own i,j")
end

local function testGrid()
  print("grid")
  -- Gen 1/2: a block is 4x4 tiles covering 2x2 cells
  local ts = { blockTiles = 4, blocks = { { 10, 11, 12, 13, 14, 15, 16, 17,
                                            18, 19, 20, 21, 22, 23, 24, 25 } } }
  local def = { width = 1, height = 1, blocks = { { 0 } }, borderBlock = 0 }
  local g = Grid.fromMapWindow(def, ts, 0, 0, 2, 2)
  ok(g.w == 4 and g.h == 4, "a 2x2-cell window is 4x4 tiles", g.w .. "x" .. g.h)
  ok(g:tileAt(0, 0) == 10, "the block's first tile lands top-left", g:tileAt(0, 0))
  ok(g:tileAt(3, 3) == 25, "and its last lands bottom-right", g:tileAt(3, 3))

  -- off the edge is the border block, never nil
  ok(g:tileAt(-1, -1) ~= nil, "off the edge answers, rather than returning nil")

  -- Gen 3: the block ID *is* the metatile, and there is no block table
  local ts3 = { blockTiles = 2, blockCells = 1 }
  local def3 = { width = 2, height = 2, blocks = { { 7, 8 }, { 9, 10 } } }
  local g3 = Grid.fromMapWindow(def3, ts3, 0, 0, 2, 2, { gen3 = true })
  ok(g3:tileAt(0, 0) == 7 * 4 + 0, "metatile 7 quadrant 0 is tile 28",
     g3:tileAt(0, 0))
  ok(g3:tileAt(1, 1) == 7 * 4 + 3, "and its bottom-right quadrant is 31",
     g3:tileAt(1, 1))
  ok(Gen3Bridge.isGen3Record(ts3) and not Gen3Bridge.isGen3Record(ts),
     "a Gen 3 record is recognised by what it states, not by its name")
end

local function testScene()
  print("scene")
  local ctx = {
    perRow = 16, atlasW = 128, atlasH = 48,
    pixel = function() return 1, 1, 1, 1 end,
  }
  local grid = Grid.new(4, 4, 0)
  local heights = {}
  local resolver = {
    atGrid = function(_, _, tx, ty)
      return { class = "wall", h = heights[tx .. "," .. ty] or 0,
               art = "flat", flat = true }
    end,
  }
  local sc = Scene.new()
  sc:setSource(grid, resolver, ctx)
  ok(sc.quadCount > 0, "the scene meshes", sc.quadCount)
  local before = sc.quadCount

  heights["1,1"] = 16
  sc:invalidateTile(1, 1)
  ok(sc.dirtyCount == 5, "an edit dirties the tile and its four neighbours",
     sc.dirtyCount)
  sc:update(64)
  ok(sc.dirtyCount == 0, "and a budgeted update clears them")
  local after = sc:quads()
  ok(#after > before, "raising a column adds the faces around it",
     before .. " -> " .. #after)

  -- the neighbours matter: re-meshing only the edited tile leaves a face
  -- belonging to the tile beside it floating in the air
  local sc2 = Scene.new()
  heights = {}
  sc2:setSource(grid, resolver, ctx)
  heights["2,2"] = 16
  sc2:invalidateTile(2, 2)
  local names = 0
  for _ in pairs(sc2.dirty) do names = names + 1 end
  ok(names == 5, "five buckets, not one", names)
end


local function testGen3Blocks()
  print("gen 3 map blocks")
  -- Two bytes per cell, little endian: metatile in the low ten bits,
  -- collision in bits 10-11, elevation in 12-15.  Verified against the
  -- extractor's own collisionCells/elevationCells on a real Emerald map.
  local function cell(meta, coll, elev)
    local v = meta + coll * 1024 + elev * 4096
    return string.char(v % 256, math.floor(v / 256))
  end
  local blocks = cell(468, 0, 3) .. cell(469, 1, 3)
              .. cell(7, 0, 0) .. cell(614, 3, 15)
  local def = { width = 2, height = 2, blocks = blocks, borderBlock = 1 }
  local ts = { blockTiles = 2, blockCells = 1 }
  local g = Grid.fromMapWindow(def, ts, 0, 0, 2, 2, { gen3 = true })

  ok(g:tileAt(0, 0) == 468 * 4, "metatile 468 quadrant 0", g:tileAt(0, 0))
  ok(g:tileAt(3, 3) == 614 * 4 + 3, "metatile 614 quadrant 3", g:tileAt(3, 3))
  ok(g:tileAt(2, 0) == 469 * 4, "the second cell decodes too", g:tileAt(2, 0))

  -- and the thing that broke: reading the string as an array answers nil for
  -- every in-range cell while the border still answers, so the map comes out
  -- empty with a ring of border blocks around it
  local anyReal = false
  for ty = 0, 3 do
    for tx = 0, 3 do
      if g:tileAt(tx, ty) ~= 1 * 4 then anyReal = true end
    end
  end
  ok(anyReal, "an in-range cell is NOT the border block")

  -- off the edge is the border, never nil
  local g2 = Grid.fromMapWindow(def, ts, -2, -2, 2, 2, { gen3 = true })
  ok(g2:tileAt(-4, -4) == 1 * 4, "off the map is the border block",
     g2:tileAt(-4, -4))

  -- a Gen 3 border may be a 2x2 PATTERN of its own
  local def2 = { width = 1, height = 1, blocks = cell(9, 0, 0),
                 border = cell(20, 0, 0) .. cell(21, 0, 0)
                       .. cell(22, 0, 0) .. cell(23, 0, 0) }
  local g3 = Grid.fromMapWindow(def2, ts, -2, -2, 2, 2, { gen3 = true })
  local seen = {}
  for ty = -4, -1 do
    for tx = -4, -1 do seen[math.floor(g3:tileAt(tx, ty) / 4)] = true end
  end
  ok(seen[20] and seen[23], "the 2x2 border pattern is used, not one block")
end

local function testHistory()
  print("history")
  local doc = Doc.new()
  Doc.pin(doc, "HOUSE", 3, "wall")
  local h = History.new()

  History.record(h, doc, "tileset", "HOUSE", "pin")
  Doc.pin(doc, "HOUSE", 3, "counter")
  ok(doc.tilesets.HOUSE.pins[3] == "counter", "the edit landed")

  local e = History.undoOnce(h, doc)
  ok(e ~= nil and doc.tilesets.HOUSE.pins[3] == "wall",
     "undo puts the slot back", doc.tilesets.HOUSE.pins[3])
  ok(History.canRedo(h), "and offers a redo")
  History.redoOnce(h, doc)
  ok(doc.tilesets.HOUSE.pins[3] == "counter", "redo re-applies it",
     doc.tilesets.HOUSE.pins[3])

  -- a NEW edit after an undo clears the redo stack
  History.undoOnce(h, doc)
  History.record(h, doc, "tileset", "HOUSE", "pin again")
  Doc.pin(doc, "HOUSE", 4, "roof")
  ok(not History.canRedo(h), "a new edit drops the redo stack")

  -- coalescing: one entry for a whole stroke
  local h2 = History.new()
  for i = 1, 20 do
    History.record(h2, doc, "tileset", "HOUSE", "brush", "brush")
  end
  ok(#h2.undo == 1, "twenty brush events are one undo step", #h2.undo)
  History.commit(h2)
  History.record(h2, doc, "tileset", "HOUSE", "brush", "brush")
  ok(#h2.undo == 2, "and the next stroke is its own", #h2.undo)

  -- map slots undo too
  local h3 = History.new()
  Doc.setMapEdit(doc, "AZALEA_TOWN", 4, 5, { art = "roof" })
  History.record(h3, doc, "map", "AZALEA_TOWN", "square")
  Doc.setMapEdit(doc, "AZALEA_TOWN", 4, 5, { h = 24 })
  History.undoOnce(h3, doc)
  local o = Doc.mapEdit(doc, "AZALEA_TOWN", 4, 5)
  ok(o and o.art == "roof" and o.h == nil, "a place edit undoes to its before")
end

local function testPlaceEdits()
  print("place edits")
  local doc = Doc.new()
  Doc.setMapEdit(doc, "MAP_A", 3, 4, { art = "wall", h = 20 })
  ok(Doc.mapEdit(doc, "MAP_A", 3, 4).h == 20, "a square remembers its height")
  Doc.setMapEdit(doc, "MAP_A", 3, 4, { h = false })
  ok(Doc.mapEdit(doc, "MAP_A", 3, 4).h == nil, "false clears one field")
  Doc.setMapEdit(doc, "MAP_A", 3, 4, nil)
  ok(Doc.mapEdit(doc, "MAP_A", 3, 4) == nil, "nil clears the square")
  ok(doc.maps.MAP_A == nil, "and an empty map drops out of the document")

  Doc.setMapEdit(doc, "MAP_B", 1, 1, { art = "roof" })
  local src = Doc.serialise(doc)
  local chunk = (loadstring or load)(src)
  ok(chunk ~= nil, "a document with place edits re-compiles")
  if chunk then
    local back = Doc.adopt(chunk())
    ok(Doc.mapEdit(back, "MAP_B", 1, 1).art == "roof",
       "and they survive the round trip")
  end
  local st = Doc.stats(doc)
  ok(st.places == 1 and st.maps == 1, "counted",
     st.places .. "/" .. st.maps)
end


local function testObjects()
  print("multi-tile objects")
  local doc = Doc.new()
  -- a 2x2 tree: 1E 1F over 2E 2F
  Doc.addGroup(doc, "TilesetJohto", {
    name = "tree", w = 2, h = 2, class = "canopy", cap = 1,
    tiles = { 0x1E, 0x1F, 0x2E, 0x2F },
  })
  local bridge = { classInfo = Classes.FALLBACK, profile = { tilesets = {} } }
  local merged = Shape.mergeProfile(bridge, doc)
  local e = merged.tilesets.TilesetJohto
  ok(e ~= nil, "the tileset entry exists")

  local above = e and e.when_above
  ok(above and above[0x2E], "the bottom-left tile is pinned conditionally")
  if above and above[0x2E] then
    local r = above[0x2E][1]
    ok(r.above[1] == 0x1E and r.class == "canopy",
       "keyed on the tile the arrangement puts above it",
       tostring(r.above[1]))
  end
  local below = e and e.when_below
  ok(below and below[0x1E] and below[0x1E][1].below[1] == 0x2E,
     "and the top-left tile on the one below it")

  -- a single-row object has no neighbour to key on, so it is a plain pin
  local doc2 = Doc.new()
  Doc.addGroup(doc2, "HOUSE", { w = 2, h = 1, class = "counter",
                                tiles = { 8, 9 } })
  local m2 = Shape.mergeProfile(bridge, doc2)
  local c = m2.tilesets.HOUSE and m2.tilesets.HOUSE.counter
  ok(c and #c == 2, "a one-row object falls back to a flat pin",
     c and #c or "none")

  -- and the occurrence counter finds the arrangement wherever it sits
  local field = {
    [0] = 0x1E, [1] = 0x1F, [2] = 0,
    [10] = 0x2E, [11] = 0x2F, [12] = 0,
  }
  local function tileAt(tx, ty)
    return field[ty * 10 + tx] or 0
  end
  local grp = doc.tilesets.TilesetJohto.groups[1]
  ok(Doc.groupOccurrences(grp, tileAt, 0, 0, 3, 2) == 1,
     "one occurrence found where the arrangement sits",
     Doc.groupOccurrences(grp, tileAt, 0, 0, 3, 2))
end

local function testMapReader()
  print("map reader")
  local ts = { blockTiles = 4, blocks = { { 10, 11, 12, 13, 14, 15, 16, 17,
                                            18, 19, 20, 21, 22, 23, 24, 25 } },
               collision = { 1, 2, 3, 4 } }
  local def = { width = 1, height = 1, blocks = { 0 }, borderBlock = 0 }
  local R = Grid.mapReader(def, ts, false)
  ok(R.tileAt(0, 0) == 10, "the whole-map reader agrees with the window",
     R.tileAt(0, 0))
  ok(R.tileAt(3, 3) == 25, "at the far corner too", R.tileAt(3, 3))
  -- and it keeps answering past the edge, where the window would clamp
  ok(R.tileAt(8, 8) ~= nil, "and past the map edge, with the border")
  ok(R.cellCollision(0, 0) == 1 and R.cellCollision(1, 1) == 4,
     "collision is four per block, NW NE SW SE",
     tostring(R.cellCollision(1, 1)))
end


local function testBuildings()
  print("building templates")
  local bridge = {
    classInfo = Classes.FALLBACK,
    profile = {
      tilesets = {},
      buildings = {
        HOUSE = {
          { id = "cottage", tiles = { { 1, 2 }, { 3, 4 } },
            roofRows = 32, roofBack = 2, slab = 4,
            parts = { { kind = "upright", x = { 0, 3 } } } },
        },
      },
    },
  }
  local doc = Doc.new()
  Doc.setBuilding(doc, "HOUSE", "cottage", { roofRows = 24 })
  local merged = Shape.mergeProfile(bridge, doc)
  local list = merged.buildings and merged.buildings.HOUSE
  ok(list and #list == 1, "the shipped template is still there", list and #list)
  local t = list and list[1]
  ok(t and t.roofRows == 24, "the patched field changed", t and t.roofRows)
  ok(t and t.roofBack == 2 and t.slab == 4,
     "and the fields it did not mention did not")
  ok(t and type(t.parts) == "table" and t.parts[1].kind == "upright",
     "the parts list is carried through exactly")
  ok(bridge.profile.buildings.HOUSE[1].roofRows == 32,
     "and the mod's own profile was not mutated",
     bridge.profile.buildings.HOUSE[1].roofRows)

  -- a patch with tiles for an unknown id is a NEW template
  Doc.setBuilding(doc, "HOUSE", "custom_01",
                  { tiles = { { 9, 9 } }, roofRows = 8 })
  local m2 = Shape.mergeProfile(bridge, doc)
  ok(#m2.buildings.HOUSE == 2, "a new template is appended",
     #m2.buildings.HOUSE)

  local src = Doc.serialise(doc)
  local chunk = (loadstring or load)(src)
  ok(chunk ~= nil, "a document with building patches re-compiles")
  if chunk then
    local back = Doc.adopt(chunk())
    ok(Doc.building(back, "HOUSE", "cottage").roofRows == 24,
       "and they survive the round trip")
  end
end


local function testIncrementalPan()
  print("incremental pan")
  local ctx = { perRow = 16, atlasW = 128, atlasH = 48,
                pixel = function() return 1, 1, 1, 1 end }
  local def = { width = 8, height = 8, blocks = {}, borderBlock = 0 }
  for i = 1, 64 do def.blocks[i] = 0 end
  local ts = { blockTiles = 4, blocks = { {} } }
  for i = 1, 16 do ts.blocks[1][i] = 5 end

  local resolver = {
    atGrid = function(_, _, _, _)
      return { class = "ground", h = 0, art = "flat", flat = true }
    end,
    overlay = function(_, _, _, _, rec) return rec end,
  }
  local sc = Scene.new()
  local g1 = Grid.fromMapWindow(def, ts, 0, 0, 4, 4)
  sc:setSource(g1, resolver, ctx, nil)
  sc:update(1000)
  local before = 0
  for _ in pairs(sc.buckets) do before = before + 1 end
  ok(before == 64, "a 4x4-cell window is 64 tiles", before)

  -- pan one cell: only the new column should need meshing, and the buckets
  -- that stayed in view must NOT have been thrown away
  local g2 = Grid.fromMapWindow(def, ts, 1, 0, 4, 4)
  sc:setSource(g2, resolver, ctx, nil)
  ok(sc.dirtyCount == 16, "a one-cell pan dirties two tile columns, not 64",
     sc.dirtyCount)
  local kept = 0
  for _ in pairs(sc.buckets) do kept = kept + 1 end
  ok(kept == 56, "and keeps what stayed in view", kept)

  -- a different map starts over
  local def2 = { width = 8, height = 8, blocks = def.blocks, borderBlock = 0 }
  local g3 = Grid.fromMapWindow(def2, ts, 0, 0, 4, 4)
  sc:setSource(g3, resolver, ctx, nil)
  ok(sc.dirtyCount == 64, "a different map re-meshes everything",
     sc.dirtyCount)
end

-- THE SETTINGS ARE READ OFF THE PROFILE, NOT LISTED HERE.
--
-- The whole point of `core/Schema.lua` is that a fork inventing a key gets an
-- editor for it with nothing to update in the editor's source.  That claim is
-- only true if the typing actually works on shapes nobody wrote it for, so
-- the guard is a made-up profile entry containing one of each shape, plus a
-- key this file has never heard of.
do
  print("the profile types itself")
  local vocab = { wall = { h = 16, art = "upright" },
                  ground = { h = 0, art = "flat" } }
  local entry = {
    wall = { 3, 4, 5 },                       -- a class list
    ground = { 1 },                           -- another
    prop_bg = { 9, 10 },                      -- a bare tile list
    prop_ground = { [7] = 2, [8] = 2 },       -- tile -> tile
    heights = { wall = 40 },                  -- name -> number
    when_above = { [3] = { { above = { 4 }, class = "wall" } } },
    buildings = { { id = "a" } },
    awning_face = { 12, 13 },                 -- a key nobody has ever seen
    column_foot = { [2] = 1 },
    some_flag = true,
    some_count = 4,
  }
  local by = {}
  for _, f in ipairs(Schema.fields(entry, nil, vocab)) do by[f.key] = f end

  ok(by.wall and by.wall.kind == "classList" and by.wall.isClass,
     "a key that is a class name holding tile ids is a class list",
     by.wall and by.wall.kind)
  ok(by.prop_bg and by.prop_bg.kind == "tileList",
     "a bare array of tile ids is a tile list", by.prop_bg and by.prop_bg.kind)
  ok(by.prop_ground and by.prop_ground.kind == "tileMap",
     "tile -> number is a tile map", by.prop_ground and by.prop_ground.kind)
  ok(by.heights and by.heights.kind == "numberMap",
     "heights keeps its own editor", by.heights and by.heights.kind)
  ok(by.when_above and by.when_above.kind == "ruleMap",
     "conditionals keep theirs", by.when_above and by.when_above.kind)
  ok(by.buildings and by.buildings.kind == "templates",
     "and so do building templates", by.buildings and by.buildings.kind)
  ok(by.some_flag and by.some_flag.kind == "flag"
     and by.some_count and by.some_count.kind == "number",
     "scalars are scalars", "yes")

  -- THE ONE THAT MATTERS: a key the editor has never been told about still
  -- arrives typed, and typed as something editable.
  ok(by.awning_face and by.awning_face.kind == "tileList"
     and not by.awning_face.isClass,
     "a key nobody has ever seen is typed by its CONTENTS and is editable",
     by.awning_face and by.awning_face.kind)
  ok(by.column_foot and by.column_foot.kind == "tileMap",
     "and so is the one the exporter used to only round-trip",
     by.column_foot and by.column_foot.kind)

  ok(Schema.mentions(by.wall, 4) and not Schema.mentions(by.wall, 99),
     "membership of a list is answered", "yes")
  ok(Schema.mentions(by.prop_ground, 7) and not Schema.mentions(by.prop_ground, 6),
     "and so is a key of a map", "yes")

  -- a class the tileset does not use yet is still offered
  ok(by.ground ~= nil, "every class in the vocabulary is offered", "yes")

  -- and the side view drops the classes
  local side = {}
  for _, f in ipairs(Schema.sideFields(entry, nil, vocab)) do side[f.key] = true end
  ok(not side.wall and side.awning_face,
     "the side view is everything that is not a class", "yes")
end

-- A generic override reaches the merged profile, or "everything is editable"
-- is a claim about a panel rather than about an export.
do
  print("generic overrides reach the profile")
  local doc = Doc.new()
  Doc.setExtra(doc, "ts", "awning_face", { 12, 13 })
  local bridge = { profile = { tilesets = { ts = { awning_face = { 1 },
                                                   wall = { 3 } } } },
                   classInfo = { wall = { h = 16, art = "upright" } } }
  local merged = Shape.mergeProfile(bridge, doc)
  local got = merged.tilesets.ts.awning_face
  ok(got and #got == 2 and got[1] == 12,
     "an authored key replaces the profile's own value",
     got and table.concat(got, ",") or "missing")
  ok(merged.tilesets.ts.wall and merged.tilesets.ts.wall[1] == 3,
     "and leaves every other key alone", "yes")

  local back = Doc.adopt((loadstring or load)(Doc.serialise(doc))())
  local r = Doc.extra(back, "ts", "awning_face")
  ok(r and r[2] == 13, "and it survives save and load",
     r and table.concat(r, ",") or "lost")
end

-- SIDE-FACE ART: THE VOID, AND WHAT FILLS IT.
--
-- Raise a tile with no measured volume and no upright fold and every 8px band
-- of the new wall wears the tile's own drawing.  An authored band names a
-- different drawing for that face, and the guard here is that it actually
-- reaches the geometry -- because it travels doc -> resolver -> scene -> mesh
-- and a break anywhere in that chain looks exactly like "the painter does
-- nothing".
do
  print("side-face art")
  local ctx = { perRow = 16, atlasW = 128, atlasH = 48,
                pixel = function() return 0.5, 0.5, 0.5, 1 end }
  local o = { tx = 0, ty = 0, tile = 5,
              heightAt = function(nx, ny)
                -- one lower neighbour, so exactly one wall is exposed
                if nx == 0 and ny == 1 then return 0 end
                return 40
              end }
  local shape = { class = "ground", h = 40, art = "flat" }

  -- which tiles the emitted quads' UVs point at
  local function tilesUsed(quads)
    local seen = {}
    for _, q in ipairs(quads) do
      local uv = q.uv
      if uv and uv[1] then
        local ax = math.floor(uv[1][1] * ctx.atlasW)
        local ay = math.floor(uv[1][2] * ctx.atlasH)
        seen[math.floor(ay / 8) * ctx.perRow + math.floor(ax / 8)] = true
      end
    end
    return seen
  end

  local plain = Mesh.tile(shape, ctx, o)
  local pu = tilesUsed(plain)
  ok(pu[5], "with no band art the wall wears the tile's own drawing", "yes")

  -- band -1 is the fallback for every band
  local opts = { tx = 0, ty = 0, tile = 5, heightAt = o.heightAt,
                 bands = { [-1] = 9 } }
  local painted = Mesh.tile(shape, ctx, opts)
  local au = tilesUsed(painted)
  ok(au[9], "an all-bands entry reaches the side faces", "yes")

  -- a specific band outranks the fallback
  local opts2 = { tx = 0, ty = 0, tile = 5, heightAt = o.heightAt,
                  bands = { [-1] = 9, [0] = 11 } }
  local mixed = tilesUsed(Mesh.tile(shape, ctx, opts2))
  ok(mixed[11] and mixed[9],
     "a named band outranks the all-bands fallback, and both are used", "yes")

  -- and the top face is untouched: band art dresses SIDES
  ok(#painted == #plain,
     "painting a face changes what it wears, not how much there is",
     #plain .. " vs " .. #painted)
end

-- The document round-trips band art, or the painter is a session-long toy.
do
  print("band art round-trips")
  local doc = Doc.new()
  Doc.setBand(doc, "ts", 5, -1, 9)
  Doc.setBand(doc, "ts", 5, 2, 11)
  local back = Doc.adopt(assert((loadstring or load)(Doc.serialise(doc)))())
  local b = Doc.bands(back, "ts", 5)
  ok(b and b[-1] == 9 and b[2] == 11, "bands survive save and load",
     b and (tostring(b[-1]) .. "/" .. tostring(b[2])) or "lost")
  ok(Doc.stats(back).bands == 2, "and are counted", Doc.stats(back).bands)
  Doc.setBand(back, "ts", 5, 2, nil)
  ok((Doc.bands(back, "ts", 5) or {})[2] == nil, "and can be cleared", "yes")
end

-- A RUN OF ONE COLOUR IS ONE BOX.
--
-- The per-pixel folds emitted six faces per lit pixel, two of which are
-- always drawn, and a route of trees is half a million quads of that.
-- Adjacent pixels of the same colour are indistinguishable once drawn, so
-- they merge -- and the guard is that a solid single-colour tile, which is
-- the best case, really does collapse rather than merely getting a bit
-- smaller, while a tile of alternating colours, the worst case, still comes
-- out correct.
do
  print("per-pixel runs merge")
  local function ctxOf(fn)
    return { perRow = 16, atlasW = 128, atlasH = 48, pixel = fn }
  end
  local o = { tx = 0, ty = 0, tile = 5, heightAt = function() return 0 end }

  -- A BLOCK ON A WHITE GROUND, not a uniform tile: the background shade is
  -- voted from the drawing's own rim, so a tile that is entirely one colour
  -- votes that colour as background and leaves nothing lit at all.
  local function block(sameColour)
    return function(_, px, py)
      if px >= 2 and px <= 5 and py >= 2 and py <= 5 then
        if sameColour or px % 2 == 0 then return 0.2, 0.3, 0.2, 1 end
        return 0.6, 0.2, 0.2, 1
      end
      return 1, 1, 1, 1
    end
  end

  local merged = Mesh.tile({ class = "prop", h = 16, art = "billboard" },
                           ctxOf(block(true)), o)
  local striped = Mesh.tile({ class = "prop", h = 16, art = "billboard" },
                            ctxOf(block(false)), o)

  ok(#merged > 0, "a per-pixel fold still emits geometry", #merged)
  -- 16 lit pixels unmerged is a floor of 32 front/back quads before any caps
  ok(#merged < 32, "a one-colour block merges under the per-pixel floor",
     #merged)
  ok(#striped > #merged,
     "and a block that cannot merge emits more than one that can",
     #merged .. " vs " .. #striped)

  -- every quad still has to be sane
  local bad
  for _, set in ipairs({ merged, striped }) do
    for i, q in ipairs(set) do
      for k = 1, 4 do
        local pt = q[k]
        if not pt or #pt ~= 3 then bad = "corner " .. k .. " of quad " .. i end
      end
      if not q.uv then bad = "quad " .. i .. " has no uv" end
    end
  end
  ok(not bad, "merged runs are still well-formed quads", bad or "ok")
end

-- A RE-MEASUREMENT IS A DIFF, NOT A RELOAD.
--
-- `Structures.forMap` hands back new tables every run, so the test that used
-- to decide "has the detector's answer changed" -- table identity -- said yes
-- every time and threw the whole map's geometry away.  This is the guard on
-- that: two records that SAY the same thing must dirty nothing, and a record
-- that differs at one square must dirty that square and its neighbours only.
do
  print("re-measuring is a diff")
  local ctx = { perRow = 16, atlasW = 128, atlasH = 48,
                pixel = function() return 1, 1, 1, 1 end }
  local def = { width = 8, height = 8, blocks = {}, borderBlock = 0 }
  for i = 1, 64 do def.blocks[i] = 0 end
  local ts = { blockTiles = 4, blocks = { {} } }
  for i = 1, 16 do ts.blocks[1][i] = 5 end
  local resolver = {
    atGrid = function(_, _, _, _)
      return { class = "ground", h = 0, art = "flat", flat = true }
    end,
    overlay = function(_, _, _, _, rec) return rec end,
    edited = function() return false end,
  }

  local function record(bumpAt)
    local S = { shapeAt = {}, tileAt = {}, skip = {}, ground = {},
                runs = {}, objectQuads = {}, grassQuads = {}, flowerQuads = {},
                roundStamps = {}, figures = {} }
    for ty = 0, 7 do
      for tx = 0, 7 do
        local k = StructBridge.keyOf(tx, ty)
        local h = (bumpAt and bumpAt[1] == tx and bumpAt[2] == ty) and 24 or 0
        S.shapeAt[k] = { class = "ground", h = h, art = "flat", flat = true }
        S.tileAt[k] = 5
      end
    end
    return S
  end

  local sc = Scene.new()
  local g = Grid.fromMapWindow(def, ts, 0, 0, 4, 4)
  sc:setSource(g, resolver, ctx, record(nil))
  sc:update(1000)
  ok(sc.dirtyCount == 0, "the first record meshes and settles", sc.dirtyCount)

  -- SAME NUMBERS, NEW TABLES: nothing may be re-meshed
  local n = sc:setStructures(record(nil))
  ok(n == 0, "an identical re-measurement dirties nothing", n)
  ok(sc.dirtyCount == 0, "and queues nothing", sc.dirtyCount)

  -- ONE SQUARE DIFFERENT: that square and the four that can see it
  local n2 = sc:setStructures(record({ 2, 2 }))
  ok(n2 == 1, "one changed square is found", n2)
  ok(sc.dirtyCount == 5, "and dirties it plus its four neighbours",
     sc.dirtyCount)
end


local function testMatrices()
  print("projection")
  local eye = { 100, 60, 180 }
  local target = { 100, 6, 100 }
  local cam = { eye = eye, target = target, up = { 0, 1, 0 }, fov = 0.85 }
  local V = Render3D.lookAt(cam)
  local P = Render3D.perspective(cam.fov, 16 / 9, 0.5, 4096)
  local M = Render3D.matMul(P, V)

  local function ndc(x, y, z)
    local c = {}
    for r = 1, 4 do
      c[r] = M[0 * 4 + r] * x + M[1 * 4 + r] * y + M[2 * 4 + r] * z
           + M[3 * 4 + r] * 1
    end
    if math.abs(c[4]) < 1e-9 then return nil end
    return c[1] / c[4], c[2] / c[4], c[3] / c[4]
  end

  local cx, cy = ndc(target[1], target[2], target[3])
  ok(math.abs(cx) < 1e-4 and math.abs(cy) < 1e-4,
     "the orbit target lands in the middle of the screen",
     ("%.4f,%.4f"):format(cx or 9, cy or 9))

  local _, uy = ndc(target[1], target[2] + 34, target[3])
  ok(uy < -0.1, "a point ABOVE the target lands at negative ndc y -- LOVE's"
     .. " canvas is y-down, and this is the flip the world was missing",
     ("%.4f"):format(uy or 9))

  local ex = ndc(target[1] + 60, target[2], target[3])
  ok(ex > 0.1, "a point east lands at positive ndc x", ("%.4f"):format(ex or 9))

  local _, _, zFar = ndc(target[1], target[2], target[3] - 40)
  local _, _, zNear = ndc(target[1], target[2], target[3] + 40)
  ok(zFar > zNear, "further away is greater depth, so `less` keeps the nearer"
     .. " fragment", ("%.5f vs %.5f"):format(zFar or 0, zNear or 0))
end

-- ---------------------------------------------------------------- runner

function T.run()
  print("")
  print("Voxel Tileset Editor -- self test")
  print("")

  local paths = Paths.discover()
  print("save dir : " .. tostring(paths.saveDir))
  print("game dir : " .. tostring(paths.gameDir))
  print("caches   : " .. tostring(#paths.cacheRoots))
  print("mod roots: " .. tostring(#paths.modRoots))
  for _, r in ipairs(paths.modRoots) do print("           " .. r) end
  print("")

  local bridge = ModBridge.open(paths.modRoots, paths.modId)
  for _, warn in ipairs(bridge.warnings) do print("  warn: " .. warn) end
  local stubs = ModBridge.stubbedModules()
  if #stubs > 0 then print("  engine stubs: " .. table.concat(stubs, ", ")) end
  print("  host live: " .. tostring(bridge.live)
        .. "  version: " .. tostring(bridge.version))
  print("")

  local caches = {}
  for i, entry in ipairs(paths.cacheRoots) do
    local c = Cache.open(entry.root, entry.version)
    if c then
      caches[#caches + 1] = c
      print(("  cache %d: %-16s %d tilesets"):format(i, c.version, #c.ids))
    end
  end
  print("")

  testSerialize()
  testZip()
  testMesh()
  testMatrices()
  testPickTags()
  testGrid()
  testGen3Blocks()
  testScene()
  testIncrementalPan()
  testHistory()
  testPlaceEdits()
  testObjects()
  testBuildings()
  testMapReader()
  testValidate()

  local doc = Doc.new()
  if caches[1] then
    local tsId = caches[1].ids[1]
    Doc.pin(doc, tsId, 0, "wall")
    Doc.pin(doc, tsId, 1, "ground")
  end
  testExportIsPresentationOnly(bridge, doc)
  testPack(bridge, doc, caches)
  testRoundTrip(bridge, caches)

  print("")
  print(("%d passed, %d failed"):format(pass, fail))
  print("")
  return fail == 0
end

return T
