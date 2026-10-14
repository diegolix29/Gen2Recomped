-- tools/gen3_mirage_tower_harness/main.lua
--
-- THE MIRAGE TOWER'S COLLAPSE, RENDERED (src/world/Gen3MirageTower.lua):
-- Route 111's tower in the map's own palette, through the shake, the
-- disintegration and the fossil's fall, plus the 4F ceiling crumbs, saved
-- as mirage_tower.png (LOVE save directory for `bt_gen3`). Prints the frame
-- counts each effect took.
--
--   POKEPORT_DATA_DIR=<emerald cache>/data/generated \
--   POKEPORT_ASSET_ROOT=<emerald cache> love tools/gen3_mirage_tower_harness

package.path = love.filesystem.getSource() .. "/../../?.lua;" .. package.path
function love.load()
  local ok, err = xpcall(function()
    require("src.core.GameVersion").set("emerald")
    local Data = require("src.core.Data")
    Data:load()
    local M = require("src.world.Gen3MirageTower")
    local map = Data.maps["MAP_G00_N26"]
    local blocks = {}
    local ow = {
      map = { id = "MAP_G00_N26", tileset = map and map.tileset and (Data.tilesets or {})[map.tileset] or map.tileset,
              setBlock = function(_, x, y, id, shut) blocks[#blocks + 1] = ("%d,%d=%03X"):format(x, y, id) end },
      player = { px = 19 * 16, py = 59 * 16 },
    }
    local game = { data = Data, save = { player = { gender = "boy" } } }
    local cam = { x = 19 * 16 - 112, y = 59 * 16 - 72 }
    local shots, frame = {}, 0
    local function shot(label)
      local cv = love.graphics.newCanvas(240, 160)
      love.graphics.setCanvas(cv); love.graphics.clear(0.85, 0.75, 0.5, 1)
      M.drawTower(ow, cam); M.drawAbove(ow, cam)
      love.graphics.setColor(0.2, 0.2, 0.8, 1); love.graphics.rectangle("line", 112, 72, 16, 16)  -- the player's cell
      love.graphics.setCanvas()
      shots[#shots + 1] = { cv = cv, label = label }
    end
    local function run(n) for _ = 1, n do M.tick(ow); frame = frame + 1 end end
    M.startShake(ow, game)
    print("metatiles set: " .. #blocks .. " (" .. tostring(blocks[1]) .. " .. " .. tostring(blocks[#blocks]) .. ")")
    shot("start"); run(1); shot("shake")
    run(24)
    M.startDisintegration(ow); M.startFossil(ow, game)
    local t0 = frame
    for _, at in ipairs({ 40, 100, 160, 220 }) do run(at - (frame - t0)); shot("+" .. at) end
    while ow.g3MirageTower and frame - t0 < 2000 do run(1) end
    print(("disintegration + fossil finished after %d frames"):format(frame - t0))
    shot("done")
    ow.map.id = "MAP_4F"
    M.ceilingCrumble(ow, game)
    shot("crumble 0"); run(20); shot("crumble 20")
    local c0 = frame
    while ow.g3MirageCrumbles and frame - c0 < 500 do run(1) end
    print(("ceiling crumbs gone after %d frames, quake %s"):format(frame - c0 + 20, tostring(ow.quakeFrames)))
    local sheet = love.graphics.newCanvas(5 * 244, math.ceil(#shots / 5) * 164)
    love.graphics.setCanvas(sheet); love.graphics.clear(0.1, 0.1, 0.1, 1)
    for i, s in ipairs(shots) do
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(s.cv, ((i - 1) % 5) * 244, math.floor((i - 1) / 5) * 164)
      love.graphics.print(s.label, ((i - 1) % 5) * 244 + 2, math.floor((i - 1) / 5) * 164 + 146)
    end
    love.graphics.setCanvas()
    sheet:newImageData():encode("png", "mirage_tower.png")
    print("saved to " .. love.filesystem.getSaveDirectory())
  end, debug.traceback)
  if not ok then print(err) end
  love.event.quit()
end
