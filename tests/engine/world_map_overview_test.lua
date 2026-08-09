package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local Assets = require("src.render.Assets")
local WorldAPI = require("src.world.WorldAPI")

Assets.imageData = function()
  return { getPixel = function(_, x)
    local shade = x < 8 and 1 or 0
    return shade, shade, shade, 1
  end }
end

local api = WorldAPI.new({ stack = { states = {} } }, "tester")
local overview, err = api:mapOverview()
T.eq(overview, nil, "map overview is unavailable outside the overworld")
T.eq(err, "no overworld", "map overview reports why it is unavailable")

local map = { id = "TEST_MAP", widthCells = 2, heightCells = 2 }
function map:isWarpTileCell(x, y) return x == 1 and y == 0 end
function map:isWaterCell(x, y) return x == 0 and y == 1 end
function map:isWalkableCell(x, y) return x == 0 and y == 0 end
function map:tileAt(x) return x % 2 end

api = WorldAPI.new({ stack = { states = {
  { isOverworld = true, map = map },
} } }, "tester")
overview = api:mapOverview()
T.eq(overview.mapId, "TEST_MAP", "map overview identifies the active map")
T.eq(overview.width, 2, "map overview reports its width")
T.eq(overview.height, 2, "map overview reports its height")
T.eq(overview.rows[1], ".+", "walkable land and warps are distinct")
T.eq(overview.rows[2], "~ ", "water and blocked terrain are distinct")
T.eq(overview.tileRows, nil, "tile overview is optional")

map.tileset = { image = "test.png", tilesPerRow = 2 }
overview = api:mapOverview()
T.eq(overview.tileWidth, 4, "tile overview reports its width")
T.eq(overview.tileHeight, 4, "tile overview reports its height")
T.eq(overview.tileRows[1], "0303", "tile overview preserves map shading")

T.finish("world map overview")
