-- tools/gen4_transition_harness/main.lua
--
-- PLATINUM'S BATTLE TRANSITIONS, RENDERED TO CONTACT SHEETS.
--
--   cd <repo>
--   POKEPORT_DATA_DIR=<platinum cache>/data/generated \
--   POKEPORT_ASSET_ROOT=<platinum cache> EFFECTS=grass_low,leader_roark EVERY=2 \
--     love tools/gen4_transition_harness
--
-- Each effect runs from its first tick on a stand-in "field" (a battle
-- backdrop in a 256x192 letterbox, inside a WIDER window -- WW x WH, default
-- 352x240 -- whose margin is more field, as the overworld draws it),
-- and every EVERY-th 30 Hz tick is drawn into a grid, written as
-- trans_<effect>.png in LOVE's save directory for `bt_gen4`.

local EVERY = tonumber(os.getenv("EVERY") or "2")
local COLS = tonumber(os.getenv("COLS") or "8")

function love.load()
  local ok, err = xpcall(function()
    require("src.core.GameVersion").set("platinum")
    local Data = require("src.core.Data")
    Data:load()
    local Font = require("src.render.Font")
    Font.load(Data)
    local T = require("src.render.Gen4BattleTransition")
    local C = require("src.world.Gen4EncounterEffect")
    local root = os.getenv("POKEPORT_ASSET_ROOT") or ""
    local function img(path)
      local f = io.open(root .. "/" .. path, "rb")
      if not f then return nil end
      local bytes = f:read("*a"); f:close()
      local i = love.graphics.newImage(love.filesystem.newFileData(bytes, path))
      i:setFilter("nearest", "nearest")
      return i
    end
    local bg = img(os.getenv("FIELD") or "assets/generated/gen4/battle/background/plain_day.png")
    local list = {}
    local want = os.getenv("EFFECTS") or "all"
    if want == "all" then
      for i = 0, #C.CUTINS do list[#list + 1] = C.CUTINS[i] end
    else
      for n in want:gmatch("[^,]+") do list[#list + 1] = n end
    end
    local WW, WH = tonumber(os.getenv("WW") or "352"), tonumber(os.getenv("WH") or "240")
    local OX, OY = math.floor((WW - 256) / 2), math.floor((WH - 192) / 2)
    local source = love.graphics.newCanvas(WW, WH)
    love.graphics.setCanvas(source)
    love.graphics.clear(0.35, 0.55, 0.35, 1)
    if bg then love.graphics.draw(bg, OX, OY, 0, 256 / bg:getWidth(), 192 / bg:getHeight()) end
    -- a cross-hair, so slices, waves and zooms read
    love.graphics.setColor(1, 0.2, 0.2, 1)
    love.graphics.rectangle("fill", OX + 126, 0, 4, WH)
    love.graphics.rectangle("fill", 0, OY + 94, WW, 4)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setCanvas()

    for _, name in ipairs(list) do
      local stack = { pop = function() end }
      local game = { data = Data, stack = stack }
      local t = setmetatable({}, T)
      t.game, t.ctx = game, { trainerName = os.getenv("NAME") or "ROARK", playerGender = "boy" }
      t.name = name
      t.S = { bright = 0, other = 0, zoom = 1, sprites = {}, rects = {}, tasks = {}, animTick = 0 }
      local S, TT = t.S, t.ctx
      t.main = coroutine.create(function() T.EFFECTS[name](S, TT) end)
      -- hgss_<id>: HeartGold / SoulSilver's own (src/render/HgssBattleTransition.lua)
      local hid = tonumber(name:match("^hgss_(%d+)$"))
      if hid then
        package.loaded["src.import.Gen4ScriptBands"] = { family = "hgss" }
        -- ROM=<hgss .nds>: the art straight from /a/1/0/9, in memory only
        if os.getenv("ROM") and not (Data.gen4_encounter_effects or {}).images then
          Data.gen4_encounter_effects = require("src.import.HgssEncounterEffects").extract(
            require("src.import.NdsRom").open(os.getenv("ROM")))
        end
        local terrain = ({ [0] = "grass", "grass", "water", "water", "cave", "cave" })[hid % 6]
        local class = hid == 46 and 109 or 1
        if hid >= 12 and hid <= 28 then
          local want = hid <= 27 and hid - 12 or 21
          for c, p in pairs(require("src.render.HgssBattleTransition").CLASS_PARAM) do if p == want then class = c end end
        end
        class = ({ [29] = 87, [30] = 89, [31] = 112, [32] = 88, [33] = 86, [39] = 55, [40] = 118, [41] = 117, [42] = 116, [43] = 114, [44] = 124, [45] = 47 })[hid] or class
        local legend = ({ [34] = 150, [35] = 250, [36] = 249 })[hid]
        t = T.new(game, nil, { trainer = hid >= 6 and not legend, trainerClass = class, species = legend or 16, terrain = terrain,
                               frontier = hid == 37 or nil, double = hid == 38 or nil,
                               trainerName = os.getenv("NAME") or "FALKNER",
                               hour = hid % 2 == 1 and 22 or 12 })
      end
      t.frame, t.finished = 0, false
      local frames = {}
      local n = 0
      while not t.finished and n < 600 do
        t:step(); n = n + 1
        if n % EVERY == 0 or t.finished then
          local c = love.graphics.newCanvas(WW, WH)
          love.graphics.setCanvas(c)
          love.graphics.clear(0, 0, 0, 1)
          t:drawScreen(0.5, WW, WH, 1, 1, source, OX, OY, 256, 192)
          love.graphics.setScissor()
          love.graphics.setCanvas()
          frames[#frames + 1] = { c = c, n = n }
        end
      end
      local rows = math.ceil(#frames / COLS)
      local sheet = love.graphics.newCanvas(COLS * (WW + 4), rows * (WH + 16))
      love.graphics.setCanvas(sheet)
      love.graphics.clear(0.1, 0.1, 0.1, 1)
      for i, f in ipairs(frames) do
        local x, y = ((i - 1) % COLS) * (WW + 4), math.floor((i - 1) / COLS) * (WH + 16)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(f.c, x, y)
        love.graphics.print(tostring(f.n), x + 2, y + WH + 1)
      end
      love.graphics.setCanvas()
      sheet:newImageData():encode("png", "trans_" .. name .. ".png")
      print(("%s: %d ticks, %d frames -> trans_%s.png"):format(name, n, #frames, name))
    end
    print("saved to " .. love.filesystem.getSaveDirectory())
  end, debug.traceback)
  if not ok then print(err) end
  love.event.quit()
end
