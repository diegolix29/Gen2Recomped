-- tools/gen5_evolution_harness/main.lua
--
-- BLACK AND WHITE'S EVOLUTION SCENE (src/ui/Gen5EvolutionState.lua), rendered
-- at points along its timeline into gen5_evolution.png in $POKEPORT_OUT: the
-- whitening, the cylinder and particles, the tile morph on the beats, the
-- climax, the fade back, and a cancelled run. Prints the frame each phase
-- began on. Text boxes complete at once.
--
--   POKEPORT_DATA_DIR=<black cache>/data/generated POKEPORT_ASSET_ROOT=<black cache> \
--   VERSION=black POKEPORT_OUT=<dir> love tools/gen5_evolution_harness

function love.load()
  local ok, err = xpcall(function()
    require("src.core.GameVersion").set(os.getenv("VERSION") or "black")
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
    package.loaded["src.core.Sound"] = { playCry = function() end, play = function() end, playSe = function() end }
    package.loaded["src.core.Music"] = { play = function() end, special = function() end,
      playOnce = function() end, restoreMap = function() end }
    local Data = require("src.core.Data")
    Data:load()
    require("src.render.Font").load(Data)
    pcall(function() require("src.ui.Theme").load(Data) end)
    package.loaded["src.pokemon.Evolution"] = { apply = function() end, learnEvolutionMoves = function(_, _, f) if f then f() end end }

    local pressB = false
    local function makeGame()
      local mon = { species = 495, level = 17, hp = 40, stats = { hp = 40 }, nickname = "SNIVY", moves = {} }
      return { data = Data, save = { party = { mon }, options = {} },
        input = { wasPressed = function(_, k) return k == "b" and pressB end, isDown = function() return false end },
        stack = { push = function(_, s) if s and s.onDone then s.onDone() end end, pop = function() end } }, mon
    end
    local E = require("src.ui.Gen5EvolutionState")
    local pages = {}
    local function snap(state)
      local cv = love.graphics.newCanvas(256, 192)
      love.graphics.setCanvas(cv)
      love.graphics.clear(1, 0, 1, 1)
      state:draw()
      love.graphics.setCanvas()
      pages[#pages + 1] = cv
    end
    local game, mon = makeGame()
    local scene = E.new(game, mon, 496, function() end, "LEVEL", nil)
    local shots = { [10] = true, [40] = true, [150] = true, [560] = true, [575] = true, [700] = true, [760] = true, [800] = true, [830] = true, [880] = true }
    local frame, phase = 0, nil
    while frame < 1200 do
      scene:update()
      frame = frame + 1
      if scene.phase ~= phase then print(("frame %4d  %s"):format(frame, tostring(scene.phase))); phase = scene.phase end
      if shots[frame] then snap(scene) end
      if scene.phase == "done" then snap(scene); break end
    end
    game, mon = makeGame()
    scene = E.new(game, mon, 496, function() end, "LEVEL", nil)
    for f = 1, 900 do
      pressB = scene.phase == "effect" and scene.clock == 300
      scene:update()
      if scene.phase == "done" then print("cancelled at frame " .. f); snap(scene); break end
    end
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
    local out = os.getenv("POKEPORT_OUT") or "."
    local f = assert(io.open(out .. "/gen5_evolution.png", "wb")); f:write(png:getString()); f:close()
    print("saved to " .. out .. "/gen5_evolution.png")
  end, debug.traceback)
  if not ok then print(err) end
  love.event.quit(ok and 0 or 1)
end
