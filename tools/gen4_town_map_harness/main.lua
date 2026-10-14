-- tools/gen4_town_map_harness/main.lua
--
-- PLATINUM'S TOWN MAP (src/ui/Gen4TownMap.lua), rendered into town_map.png
-- (or $POKEPORT_OUT): the Town Map key item on Twinleaf, on Jubilife and on a
-- route; Fly mode with every town visited, the cursor on a town (both blink
-- phases) and on a route; a save with nothing visited; and the hidden
-- locations unlocked.
--
--   POKEPORT_DATA_DIR=<platinum cache>/data/generated \
--   POKEPORT_ASSET_ROOT=<platinum cache> love tools/gen4_town_map_harness

function love.load()
  local ok, err = xpcall(function()
    require("src.core.GameVersion").set("platinum")
    local assetRoot = os.getenv("POKEPORT_ASSET_ROOT")
    if assetRoot then
      local Assets = require("src.render.Assets")
      local realImage, held = Assets.image, {}
      Assets.image = function(path, ...)
        if type(path) == "string" and not held[path] then
          local f = io.open(assetRoot .. "/" .. path, "rb")
          if f then
            local bytes = f:read("*a"); f:close()
            local okI, img = pcall(love.graphics.newImage, love.filesystem.newFileData(bytes, path))
            if okI then img:setFilter("nearest", "nearest"); held[path] = img end
          end
        end
        return held[path] or realImage(path, ...)
      end
    end
    local Data = require("src.core.Data")
    Data:load()
    require("src.render.Font").load(Data)
    pcall(function() require("src.ui.Theme").load(Data) end)
    local T = require("src.ui.Gen4TownMap")
    local function game(visited, extra)
      local flags = {}
      if visited then for fa = 0, 40 do flags[("FLAG_G4_%04X"):format(0x9B1 + fa)] = true end end
      local save = { flags = flags, player = { gender = "boy" }, gen4TownMapCell = { x = 3, z = 27 }, vars = {} }
      for k, v in pairs(extra or {}) do save[k] = v end
      return { data = Data, save = save, stack = { pop = function() end },
        input = { wasPressed = function() return false end, isDown = function() return false end } }
    end
    local scenes = {
      { "map Twinleaf", game(true), "map", 3, 27, 0 },
      { "map Jubilife", game(true), "map", 4, 23, 0 },
      { "map route", game(true), "map", 5, 20, 0 },
      { "fly town", game(true), "fly", 4, 23, 0 },
      { "fly town blink", game(true), "fly", 4, 23, 40 },
      { "fly route", game(true), "fly", 5, 20, 0 },
      { "fly nothing visited", game(false), "fly", 4, 23, 0 },
      { "hidden unlocked", game(true, { gen4HiddenPaths = { 0, 1, 2, 3 } }), "map", 26, 9, 0 },
    }
    local pages = {}
    for _, sc in ipairs(scenes) do
      local m = T.new(sc[2], { mode = sc[3] })
      if sc[1] == "hidden unlocked" then
        local H = require("src.world.Gen4HiddenPaths")
        for i = 0, 3 do pcall(H.set, sc[2].save, i, true) end
      end
      m.cx, m.cz = sc[4], sc[5]
      m.frame = sc[6]
      local cv = love.graphics.newCanvas(256, 192)
      love.graphics.setCanvas(cv); love.graphics.clear(0, 0, 0, 1); m:draw(); love.graphics.setCanvas()
      pages[#pages + 1] = cv
      if m.drawBottom then
        local b = love.graphics.newCanvas(256, 192)
        love.graphics.setCanvas(b); love.graphics.clear(0, 0, 0, 1); m:drawBottom(); love.graphics.setCanvas()
        pages[#pages + 1] = b
      end
    end
    -- the bottom screen's other states, each top screen beside its touch
    -- screen: the zoom button pressed, the fade, the zoomed map on a town
    -- (MAP signpost), a route (ARROW signpost), a landmark, mid-slide, and
    -- the location history (the dot cycling)
    local function both(m)
      local a = love.graphics.newCanvas(256, 192)
      love.graphics.setCanvas(a); love.graphics.clear(0, 0, 0, 1); m:draw(); love.graphics.setCanvas()
      local b = love.graphics.newCanvas(256, 192)
      love.graphics.setCanvas(b); love.graphics.clear(0, 0, 0, 1); m:drawBottom(); love.graphics.setCanvas()
      pages[#pages + 1] = a; pages[#pages + 1] = b
    end
    local function zoomedAt(x, z, g)
      local m = T.new(g or game(true), { mode = "map" })
      m.cx, m.cz = x, z
      m.zx, m.zy = x * 16 + 8 - 112, z * 16 - 96
      m.zoomed = true
      m:stepBottom()
      return m
    end
    do
      local m = T.new(game(true), { mode = "map" })
      m:bottomTouch(128, 108); for _ = 1, 5 do m:update() end
      print("zoom pressed", m:zoomButtonState()); both(m)
      for _ = 1, 9 do m:update() end
      print("fading", m:bottomFade()); both(m)
      for _ = 1, 30 do m:update() end
      print("zoomed", m.zoomed); both(m)
    end
    both(zoomedAt(4, 23))     -- Jubilife: MAP signpost
    both(zoomedAt(5, 20))     -- a route: ARROW signpost
    both(zoomedAt(12, 16))    -- Mt. Coronet
    both(zoomedAt(17, 22))
    do
      local g = game(true)
      local TM = require("src.ui.Gen4TownMap")
      for _, c in ipairs({ { 3, 27 }, { 3, 26 }, { 4, 25 }, { 4, 23 }, { 7, 22 }, { 9, 22 } }) do TM.pushHistory(g.save, c[1], c[2], 1) end
      g.save.gen4TownMapCell = { x = 9, z = 22 }
      local m = T.new(g, { mode = "map" })
      print("history", #m.history)
      m.frame = 0; both(m)
      m.frame = 52 * 2; both(m)
    end
    local perRow = 4
    local rows = math.ceil(#pages / perRow)
    local sheet = love.graphics.newCanvas(perRow * 260, rows * 196)
    love.graphics.setCanvas(sheet); love.graphics.clear(1, 0, 1, 1)
    for i, p in ipairs(pages) do
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(p, ((i - 1) % perRow) * 260, math.floor((i - 1) / perRow) * 196)
    end
    love.graphics.setCanvas()
    local png = sheet:newImageData():encode("png")
    local out = os.getenv("POKEPORT_OUT")
    if out then
      local f = assert(io.open(out .. "/town_map.png", "wb")); f:write(png:getString()); f:close()
      print("saved to " .. out .. "/town_map.png")
    else
      love.filesystem.write("town_map.png", png)
      print("saved to " .. love.filesystem.getSaveDirectory())
    end
  end, debug.traceback)
  if not ok then print(err) end
  love.event.quit()
end
