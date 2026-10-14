-- tools/gen4_evolution_harness/main.lua
--
-- PLATINUM'S EVOLUTION SCENE (src/ui/Gen4EvolutionState.lua), rendered at
-- points along its timeline into evolution.png (or $POKEPORT_OUT): the fade
-- in, the opening line, the window closing, the forms trading places with the
-- particles, the white-out, the reveal, a cancelled run, and the bottom
-- screen. Prints the frame each phase began on.
--
--   POKEPORT_DATA_DIR=<platinum cache>/data/generated \
--   POKEPORT_ASSET_ROOT=<platinum cache> love tools/gen4_evolution_harness
--
-- Needs `gen4_evolution_art` / `gen4_evolution_ink` (tools/gen4_art_extract
-- `evolution`).

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
    local bottomFn
    package.loaded["src.ui.SecondScreen"] = { mode = function() return "display" end,
      toLocal = function(_, x, y) return x, y end, drawFrame = function() end,
      draw = function(_, fn) bottomFn = fn end }
    package.loaded["src.core.Sound"] = { playCry = function() end, play = function() end }
    package.loaded["src.core.Music"] = { play = function() end, special = function() end,
      playOnce = function() end, restoreMap = function() end }
    local Data = require("src.core.Data")
    Data:load()
    require("src.render.Font").load(Data)
    pcall(function() require("src.ui.Theme").load(Data) end)

    local pressB = false
    local function makeGame()
      local mon = { species = 393, level = 16, hp = 40, stats = { hp = 40 }, nickname = "PIPLUP", moves = {} }
      return { data = Data, save = { party = { mon }, options = {} },
        input = { wasPressed = function(_, k) return k == "b" and pressB end, isDown = function() return false end },
        stack = { push = function() end, pop = function() end } }, mon
    end
    local E = require("src.ui.Gen4EvolutionState")
    local pages = {}
    local function snap(state)
      local cv = love.graphics.newCanvas(256, 192)
      love.graphics.setCanvas(cv)
      love.graphics.clear(1, 0, 1, 1)
      bottomFn = nil
      state:draw()
      love.graphics.setCanvas()
      pages[#pages + 1] = cv
    end
    -- the full run
    local game, mon = makeGame()
    local scene = E.new(game, mon, 394, function() end, "LEVEL", nil)
    scene:enter()
    local shots = { 4, 40, 140, 175, 210, 260, 300 }
    local want, frame, phase = 1, 0, nil
    local alternateShots = 0
    while frame < 1400 and want <= #shots + 4 do
      scene:update()
      frame = frame + 1
      if scene.phase ~= phase then print(("frame %4d  %s"):format(frame, tostring(scene.phase))); phase = scene.phase end
      if shots[want] and frame == shots[want] then snap(scene); want = want + 1 end
      if scene.phase == "alternate" and alternateShots < 2 and scene.t % 23 == 10 then snap(scene); alternateShots = alternateShots + 1 end
      if scene.phase == "clampOut" and scene.t == 12 then snap(scene) end
      if scene.phase == "reveal" and scene.t == 30 then snap(scene) end
      if scene.phase == "done" then snap(scene); break end
    end
    if bottomFn then
      local b = love.graphics.newCanvas(256, 192)
      love.graphics.setCanvas(b); love.graphics.clear(0, 0, 0, 1); bottomFn(); love.graphics.setCanvas()
      pages[#pages + 1] = b
    end
    -- a cancelled run
    game, mon = makeGame()
    scene = E.new(game, mon, 394, function() end, "LEVEL", nil)
    scene:enter()
    for f = 1, 700 do
      pressB = scene.phase == "alternate" and scene.t == 30
      scene:update()
      if scene.phase == "cancel" and scene.t == 4 then snap(scene) end
      if scene.phase == "done" then print("cancelled at frame " .. f); snap(scene); break end
    end
    pressB = false

    local perRow = 4
    local rows = math.ceil(#pages / perRow)
    local sheet = love.graphics.newCanvas(perRow * 260, rows * 196)
    love.graphics.setCanvas(sheet)
    love.graphics.clear(0.2, 0.2, 0.2, 1)
    for i, p in ipairs(pages) do
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(p, ((i - 1) % perRow) * 260, math.floor((i - 1) / perRow) * 196)
    end
    love.graphics.setCanvas()
    local png = sheet:newImageData():encode("png")
    local out = os.getenv("POKEPORT_OUT")
    if out then
      local f = assert(io.open(out .. "/evolution.png", "wb")); f:write(png:getString()); f:close()
      print("saved to " .. out .. "/evolution.png")
    else
      love.filesystem.write("evolution.png", png)
      print("saved to " .. love.filesystem.getSaveDirectory())
    end
  end, debug.traceback)
  if not ok then print(err) end
  love.event.quit()
end
