-- Run from the mod root with: texlua tools/test_gen5_bridge.lua   (or luajit)
-- Stubs LOVE and the engine (no ROM) and drives the REAL Gen4Bridge, Gen4Cells,
-- Gen4WorldHost (detection + grass test), Gen4Spawn.isOutdoor and Gen5Probe to
-- check what the Gen 5 port changed: Black / White are treated as a Gen4Ground
-- world, their behaviour numbers are read as B/W's (not Platinum's), and the
-- season / probe hooks run. Nothing here needs a cartridge.
local fails, passes = 0, 0
local function check(c, m) if c then passes = passes + 1 else fails = fails + 1; print("FAIL: " .. m) end end

love = { timer = { getTime = function() return 0 end }, graphics = {}, system = { getOS = function() return "Linux" end } }

-- ------------------------------------------------------------ engine stubs --
local generation, family = 5, "bw"
package.loaded["src.core.GameVersion"] = {
  generation = function() return generation end,
  family = function() return family end,
}
local season = 0
package.loaded["src.render.Gen5Seasons"] = { current = function() return season end }
package.loaded["src.world.Gen5FieldRules"] = {
  GRASS = { [0x04] = true, [0x05] = true, [0x21] = true, [0x08] = true,
            [0x06] = true, [0x07] = true, [0x22] = true, [0x09] = true },
}
local Game = { data = { map_layouts = {} }, overworld = nil }
package.loaded["src.core.Game"] = Game

-- ------------------------------------------------------------------- mod V --
local logs = {}
local logger = {
  info = function(_, m) logs[#logs + 1] = m end,
  warn = function(_, m) logs[#logs + 1] = m end,
}
local invalidated = {}
local stubs = {
  Voxel3D = {}, Mat4 = {},
  Gen4Trees = { invalidate = function() invalidated[#invalidated + 1] = "Gen4Trees" end },
  Gen4Sand = { invalidate = function() invalidated[#invalidated + 1] = "Gen4Sand" end },
}
local V = { mod = { log = logger }, path = "." }
local loaded = {}
function V.require(name)
  if stubs[name] then return stubs[name] end
  if loaded[name] then return loaded[name] end
  local f = assert(loadfile("lib/" .. name .. ".lua"))
  local m = f(V)
  loaded[name] = m
  return m
end
function V.optional(name) local ok, m = pcall(V.require, name); return ok and m or nil end

-- ------------------------------------------------------------------ bridge --
local Bridge = V.require("Gen4Bridge")
for g = 1, 5 do
  generation = g
  check(Bridge.isGen4() == (g == 4 or g == 5), "isGen4 for generation " .. g)
  check(Bridge.isGen5() == (g == 5), "isGen5 for generation " .. g)
end
generation = 5
check(Bridge.family() == "bw", "family() reads GameVersion.family")
check(Bridge.generation() == 5, "generation() exported")

-- season watcher: no flush on the first frame, one flush when the season turns
generation = 5
Bridge.gen5FrameStart({ def = { id = "Z1" }, terrain = { chunks = {} } })
check(#invalidated == 0, "first frame does not flush baked meshes")
season = 2
Bridge.gen5FrameStart({ def = { id = "Z1" }, terrain = { chunks = {} } })
check(#invalidated >= 2, "a season change flushes the baked effect meshes (" .. #invalidated .. ")")
local n = #invalidated
Bridge.gen5FrameStart({ def = { id = "Z1" }, terrain = { chunks = {} } })
check(#invalidated == n, "no second flush while the season stays put")

-- gen5Off is honoured by install(): emulate its last step
Bridge.gen5Off = { glass = true }
Bridge.disabled = {}
for name, off in pairs(Bridge.gen5Off) do if off then Bridge.disabled[name] = true end end
check(Bridge.disabled.glass == true, "gen5Off entries switch effects off")

-- an effect an ERROR switched off gets one retry on the next map; a player's
-- (or gen5Off's) switch-off does not
Bridge.disabled = { trees = true, water = true, glass = true }
Bridge.failed = { trees = true }
Bridge.gen5FrameStart({ def = { id = "Z1" }, terrain = { chunks = {} } })
check(Bridge.disabled.trees == true, "same map: the errored effect stays off")
Bridge.gen5FrameStart({ def = { id = "Z9" }, terrain = { chunks = {} } })
check(Bridge.disabled.trees == nil, "new map: the errored effect gets another try")
check(Bridge.disabled.water == true and Bridge.disabled.glass == true,
      "new map: effects switched off on purpose stay off")
check(next(Bridge.failed) == nil, "the failed list is cleared")

-- ------------------------------------------------------------------- cells --
local Cells = V.require("Gen4Cells")
local bwBehaviour = { [0] = 0x04, [1] = 0x03, [2] = 0x08, [3] = 0x21, [4] = 0x0C, [5] = 0x00 }
local bwMap = {
  def = { gen5 = true, width = 6, height = 1, layout = "L1", originX = 0, originY = 0 },
  inBounds = function(self, cx, cy) return cy == 0 and cx >= 0 and cx < 6 end,
  cellBehaviour = function(self, cx, cy) return bwBehaviour[cx] end,
  blockAt = function() return 0 end,           -- B/W's rails: open / blocked, never a behaviour
}
check(Cells.isBW(bwMap), "isBW reads def.gen5")
check(Cells.behaviour(bwMap, 0, 0) == 0x04, "B/W behaviour comes from cellBehaviour, not blockAt")
check(Cells.isGrassValue(bwMap, 0x04), "0x04 is B/W grass")
check(Cells.isGrassValue(bwMap, 0x08), "0x08 is B/W tall grass")
check(Cells.isGrassValue(bwMap, 0x21), "0x21 is B/W grass")
check(not Cells.isGrassValue(bwMap, 0x03), "0x03 (dirt path) is NOT grass on B/W")
check(not Cells.isGrassValue(bwMap, 0x02), "0x02 is not B/W grass")
check(Cells.isSandValue(bwMap, 0x0C, { [33] = true}), "0x0C is B/W sand")
check(not Cells.isSandValue(bwMap, 33, { [33] = true}), "Platinum's sand number is not B/W sand")
local ptMap = { def = { width = 4, height = 1 } }
check(Cells.isGrassValue(ptMap, 2) and Cells.isGrassValue(ptMap, 3), "Platinum 2/3 still grass")
check(not Cells.isGrassValue(ptMap, 4), "Platinum 4 is not grass")
check(Cells.isSandValue(ptMap, 33, { [33] = true }), "Platinum sand 33 still sand")

-- outside the crop: the shared layout's behaviorCells, one byte a cell
Game.data.map_layouts.L1 = { width = 8, height = 1, blocks = string.rep("\0\0", 8),
                             behaviorCells = string.char(9, 9, 9, 9, 9, 9, 0x05, 0x03) }
check(Cells.behaviour(bwMap, 6, 0) == 0x05, "outside the crop reads layout.behaviorCells")
check(Cells.behaviour(bwMap, 7, 0) == 0x03, "outside the crop, last cell")
check(Cells.behaviour(bwMap, 8, 0) == nil, "off the grid is nil")

-- -------------------------------------------------------------- world host --
local Host = V.require("Gen4WorldHost")
generation = 5
check(Host.isGen4() and Host.isGen5(), "Host treats generation 5 as a Gen4Ground world")
generation = 4
check(Host.isGen4() and not Host.isGen5(), "Host: Platinum is still Gen 4, not Gen 5")
generation = 5
check(Host.isTallGrass(bwMap, 0, 0) == true, "Host.isTallGrass: B/W grass")
check(not Host.isTallGrass(bwMap, 1, 0), "Host.isTallGrass: B/W dirt path is not grass")
check(Host.behaviourAt(bwMap, 2, 0) == 0x08, "Host.behaviourAt reads cellBehaviour on B/W")

-- ------------------------------------------------------------------- spawn --
local Spawn = V.require("Gen4Spawn")
local bwOutdoor = { def = { gen5 = true, width = 10, height = 10 },
                    renderer = { gen4Ground = { outdoors = true } } }
local bwIndoor = { def = { gen5 = true, width = 40, height = 40 },
                   renderer = { gen4Ground = { outdoors = false } } }
check(Spawn.isOutdoor(bwOutdoor) == true, "small outdoor B/W map is outdoors (ground.outdoors)")
check(Spawn.isOutdoor(bwIndoor) == false, "big indoor B/W map is indoors (ground.outdoors)")

-- ------------------------------------------------------------------- probe --
local Probe = V.require("Gen5Probe")
logs = {}
local ground = {
  def = { id = "Z42", gen5 = true }, outdoors = true,
  terrain = {
    maps = { Z42 = { area = 6 } },
    chunks = {
      [1] = { shapes = { { texture = "sea01", material = "m1", name = "a", tris = { 1, 2 } },
                         { texture = "tree_a", material = "m2", name = "b" } } },
      [2] = { shapes = { { texture = "sea01", material = "m1", name = "c" } } },
    },
  },
  set = { textures = { zeta = 1, alpha = 2 } },
}
Probe.reset()
Probe.scan(ground)
local text = table.concat(logs, "\n")
check(text:find("map Z42 area 6 outdoors=true", 1, true) ~= nil, "probe header names the map and area")
check(text:find("tex='sea01' mat='m1' shapes=2", 1, true) ~= nil, "probe counts shapes per texture/material")
check(text:find("alpha, zeta", 1, true) ~= nil, "probe lists the texture set, sorted")
local before = #logs
Probe.scan(ground)
check(#logs == before, "probe logs each map once")

print(("test_gen5_bridge: %d passed, %d failed"):format(passes, fails))
if fails > 0 then os.exit(1) end
