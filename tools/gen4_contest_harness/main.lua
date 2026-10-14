-- tools/gen4_contest_harness/main.lua
--
-- THE SUPER CONTEST SCREEN, RENDERED: builds a Normal-rank Cool contest for a
-- Pikachu, runs Gen4ContestScreen and saves each page into contest_pages.png
-- (LOVE save directory for `bt_gen4`), printing the placements.
--
--   POKEPORT_DATA_DIR=<platinum cache>/data/generated \
--   POKEPORT_ASSET_ROOT=<platinum cache> love tools/gen4_contest_harness

function love.load()
  local ok, err = xpcall(function()
    require("src.core.GameVersion").set("platinum")
    -- POKEPORT_ASSET_ROOT: the launcher mounts the cache's `assets/`; this
    -- harness has no launcher, so read the pictures (contest art, fonts,
    -- sprites) straight from that folder, as the battle harness does.
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
    local C = require("src.pokemon.Gen4Contest")
    local pressed = {}
    if assetRoot then
      local Assets = require("src.render.Assets")
      local realData = Assets.imageData
      Assets.imageData = function(path, ...)
        local f = type(path) == "string" and io.open(assetRoot .. "/" .. path, "rb")
        if f then
          local bytes = f:read("*a"); f:close()
          local ok, d = pcall(love.image.newImageData, love.filesystem.newFileData(bytes, path))
          if ok then return d end
        end
        return realData(path, ...)
      end
    end
    local game = { data = Data, input = { wasPressed = function(_, k) local v = pressed[k]; pressed[k] = nil; return v end,
                                          isDown = function() return false end },
      stack = { pop = function() end },
      -- a few Accessories to dress with: Top Hat, Red Barrette, White Fluff, Gold Pedestal
      save = { gen4Accessories = { [83] = 1, [73] = 1, [0] = 3, [88] = 1 } } }
    local c = C.new({ data = Data, rank = tonumber(os.getenv("RANK") or "0"), type = C.COOL, competition = C.OFFICIAL, seed = 7,
      mon = { species = 25, nickname = "PIKACHU", contest = { cool = 60, tough = 20, beauty = 30, sheen = 40 },
              moves = { { id = 85 }, { id = 98 }, { id = 86 }, { id = 231 } } },
      playerName = "LUCAS", partySlot = 0 })
    local done = false
    local screen = require("src.ui.Gen4ContestScreen").new(game, c, function() done = true end)
    local pages = {}
    -- every page outside the Acting round, and inside it the first frames,
    -- each move menu and each judge pick; the Acting lines are printed
    local frame, lastMode = 0, nil
    while not done and frame < 12000 do
      frame = frame + 1
      local act = screen.acting or screen.dressup
      local mode = act and (#act.queue > 0 and "msg" or act.mode)
      if screen.dressup then mode = "du-" .. screen.dressup.mode .. "-" .. #screen.dressup.placed .. tostring(screen.dressup.held ~= nil) end
      local snap = not act or (mode ~= lastMode)
      if snap and #pages < 30 then
        local cv = love.graphics.newCanvas(256, 192)
        love.graphics.setCanvas(cv)
        love.graphics.clear(0, 0, 0, 1)
        screen:draw()
        love.graphics.setCanvas()
        pages[#pages + 1] = cv
      end
      if act and act.queue and type(act.queue[1]) == "string" and os.getenv("LINES") then print("  | " .. (act.queue[1]:gsub("\n", " "))) end
      lastMode = mode
      if os.getenv("DBG") and frame % 50 == 0 then print("frame", frame, mode, act and act.cursor, act and act.judge, screen.pages[screen.page]) end
      if act and mode == "judge" then pressed.right = frame % 2 == 0 end
      if act and mode == "move" and frame % 3 == 0 then pressed.down = true end
      local du = screen.dressup
      if du and du.mode == "play" then
        -- put things on until three are on, moving along the case, then DONE
        if #du.placed >= 3 then pressed.start = true
        elseif not du.held then pressed.right = true
        elseif du.held and not du.aimed then
          -- as a player would: over one of the sixteen points of the Pokemon's
          -- box (the top row's thirds, then its middle)
          local D = require("src.ui.Gen4ContestDressUp")
          local mx, my = du:monAt()
          local m = du:monImage()
          local box = m.data and D.shape(m.data, mx, my).box or { mx, my, mx + 79, my + 79 }
          local pts = D.gridPoints(box)
          local pt = pts[({ 2, 6, 10 })[#du.placed + 1] or 6]
          du.held.x, du.held.y = pt[1] - math.floor(du.held.w / 2), pt[2] - math.floor(du.held.h / 2)
          du.aimed = true
        end
        if not du.held then du.aimed = nil end
      end
      pressed.a = true
      screen:update()
    end
    print(("dress-up: wore %d accessories (%s), dress score %d, hearts %d"):format(
      #(c.contestants[0].accessories or {}),
      (function() local t = {} for _, a in ipairs(c.contestants[0].accessories or {}) do t[#t + 1] = a.accessory end return table.concat(t, ",") end)(),
      c.scores[0].visualDress or -1, C.hearts(c, 0)))
    if screen.acting == nil and c.scores then
      print(("acting totals %d %d %d %d"):format(c.scores[0].acting, c.scores[1].acting, c.scores[2].acting, c.scores[3].acting))
    end
    local cols = math.min(#pages, 6)
    local sheet = love.graphics.newCanvas(cols * 260, math.ceil(#pages / cols) * 196)
    love.graphics.setCanvas(sheet)
    love.graphics.clear(0.1, 0.1, 0.1, 1)
    for i, p in ipairs(pages) do love.graphics.setColor(1, 1, 1, 1); love.graphics.draw(p, ((i - 1) % cols) * 260, math.floor((i - 1) / cols) * 196 + 2) end
    love.graphics.setCanvas()
    sheet:newImageData():encode("png", "contest_pages.png")
    for id = 0, 3 do
      local e = c.contestants[id]
      print(("%d. %s (%s) stars %d hearts %d bars %d/%d/%d"):format(c.placement[id] + 1, tostring(e.mon.nickname), e.trainer,
        C.stars(c, id), C.hearts(c, id), c.bars[id][1], c.bars[id][2], c.bars[id][3]))
    end
    print("saved to " .. love.filesystem.getSaveDirectory())
  end, debug.traceback)
  if not ok then print(err) end
  love.event.quit()
end
