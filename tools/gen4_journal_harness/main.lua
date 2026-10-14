-- tools/gen4_journal_harness/main.lua
--
-- THE JOURNAL, RENDERED: two days of pages for a boy, drawn by
-- src/ui/Gen4Journal.lua, with a page turn caught part way, saved as
-- journal_pages.png (LOVE save directory for `bt_gen4`).
--
--   POKEPORT_DATA_DIR=<platinum cache>/data/generated \
--   POKEPORT_ASSET_ROOT=<platinum cache> love tools/gen4_journal_harness

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
    local J = require("src.pokemon.Gen4Journal")
    local E = J.EVENT
    local save = { player = { name = "LUCAS", rival = "BARRY", gender = 0 }, gen4Journal = { acquired = true, pages = {} } }
    local d1 = { year = 26, month = 10, day = 9, week = 5 }
    local d2 = { year = 26, month = 10, day = 10, week = 6 }
    J.title(save, 411, d1)
    J.location(save, { type = E.RESTED_AT_HOME }, d1)
    J.location(save, { type = E.LEFT_RESEARCH_LAB }, d1)
    J.mon(save, "caught", 396, 0, 0, 5, d1)
    J.title(save, 3, d2)
    J.location(save, { type = E.ARRIVED_IN_LOCATION, location = 3 }, d2)
    J.location(save, { type = E.SHOPPED_AT_MART }, d2)
    J.location(save, { type = E.GYM_WAS_TOO_TOUGH, location = 0 }, d2)
    J.location(save, { type = E.ITEM_WAS_OBTAINED, item = 4 }, d2)
    J.mon(save, "defeated", 399, 1, 1, 25, d2)
    J.trainer(save, 3, 1, d2)
    local pressed = {}
    local game = { data = Data, save = save,
      input = { wasPressed = function(_, k) local v = pressed[k]; pressed[k] = nil; return v end },
      stack = { pop = function() end } }
    local sc = require("src.ui.Gen4Journal").new(game, {})
    local shots = {}
    local function snap()
      local cv = love.graphics.newCanvas(256, 192)
      love.graphics.setCanvas(cv); love.graphics.clear(0, 0, 0, 1); sc:draw(); love.graphics.setCanvas()
      shots[#shots + 1] = cv
    end
    for _ = 1, 10 do sc:update() end
    snap()
    pressed.right = true; sc:update()
    for _ = 1, 4 do sc:update() end
    snap()
    for _ = 1, 10 do sc:update() end
    snap()
    pressed.left = true; sc:update()
    for _ = 1, 3 do sc:update() end
    snap()
    local sheet = love.graphics.newCanvas(2 * 260, 2 * 196)
    love.graphics.setCanvas(sheet); love.graphics.clear(0.1, 0.1, 0.1, 1)
    for i, cv in ipairs(shots) do love.graphics.setColor(1, 1, 1, 1); love.graphics.draw(cv, ((i - 1) % 2) * 260, math.floor((i - 1) / 2) * 196) end
    love.graphics.setCanvas()
    sheet:newImageData():encode("png", "journal_pages.png")
    print("saved to " .. love.filesystem.getSaveDirectory())
  end, debug.traceback)
  if not ok then print(err) end
  love.event.quit()
end
