-- tools/walker_minigames_shot/main.lua
--
--   GAME=hub|scores|runner|catch|treasure|memory|rhythm|results  W=1280 H=800
--   OUT=shot.png  [FAKE_OS=Android SAFE=x,y,w,h]  [ART=G:/Gen2Recomped]
--   [LAUNCHER=1]  lovec tools/walker_minigames_shot
--
-- Opens the Pokewalker minigames on a demo walker (Pikachu on Refreshing
-- Field, some scores on the board), plays the chosen game for a few seconds
-- with a scripted player so the shot is mid-play, and writes OUT. Pictures
-- come from the imported games' caches under ART (WalkerArt._roots), so
-- nothing is read from or written to the player's own save directory.
-- LAUNCHER=1 builds the real launcher (as tools/launcher_shot does), goes to
-- the Pokewalker and opens the hub through WalkerMinigames.open(screen, st):
-- the shot then shows the hub drawn over the launcher it covers.

do
  local root = (os.getenv("ROOT") or love.filesystem.getWorkingDirectory()):gsub("\\", "/")
  local ffi = require("ffi")
  pcall(ffi.cdef, "int PHYSFS_mount(const char *newDir, const char *mountPoint, int appendToPath);")
  for _, lib in ipairs({ function() return ffi.C end, function() return ffi.load("love") end }) do
    local ok, l = pcall(lib)
    if ok and l then
      local okf, fn = pcall(function() return l.PHYSFS_mount end)
      if okf and fn and fn(root, "", 1) ~= 0 then break end
    end
  end
end

local Hub, hub, Importer
local frames, want = 0, tonumber(os.getenv("FRAMES") or "8")
local GAME = os.getenv("GAME") or "hub"
local IDX = { runner = 1, catch = 2, treasure = 3, memory = 4, rhythm = 5 }

local function demoState()
  local W = require("src.pokewalker.Walker")
  W.save = function() end
  local st = W.newState()
  st.watts, st.lifetimeWatts = 340, 2400
  st.course = tonumber(os.getenv("WALKER_COURSE") or "0")
  st.walking = { species = tonumber(os.getenv("WALKER_SPECIES") or "25"), name = "PIKACHU", level = 14,
    types = { "ELECTRIC" }, friendship = 120, steps = 3200, friendSteps = 0, encounters = {} }
  local R = require("src.pokewalker.minigames.Rewards")
  R._economy = false
  local day = math.floor(os.time() / 86400)
  st.minigames = { day = day, daily = { watts = 64, items = 2, pokemon = 1, friendship = 3, plays = 4 }, games = {
    runner = { best = 4210, plays = 6, totalWatts = 88, scores = {
      { score = 4210, watts = 26, t = os.time() - 3600 }, { score = 3380, watts = 21, t = os.time() - 86400 },
      { score = 2950, watts = 18, t = os.time() - 86400 * 2 }, { score = 1200, watts = 7, t = os.time() - 86400 * 3 } } },
    memory = { best = 1460, plays = 2, totalWatts = 40, scores = { { score = 1460, watts = 24, t = os.time() - 7200 } } },
  } }
  return st
end

-- the scripted players: a few seconds of each game
local function autoplay(session, secs)
  local g = session.game
  local dt = 1 / 60
  local id = session.module.id
  local t = 0
  local dug, flips = 0, 0
  while t < secs and session.phase == "play" do
    if id == "runner" then
      local px = g.dist + g.PLAYER_X
      for _, e in ipairs(g.ents) do
        local ahead = e.x - px
        if (e.kind == "block" or (e.kind == "mon" and not e.flying and not e.dead)) and ahead > 0
           and ahead < g.speed * 0.16 + 0.6 and g.ground then g:input("a") end
      end
    elseif id == "catch" then
      -- stop just before the throw: the ring is closing on the circle
    elseif id == "treasure" then
      if t > dug * 0.5 + 0.3 and dug < 5 then
        local cells = { { 2, 2 }, { 5, 3 }, { 3, 5 }, { 4, 4 }, { 1, 6 } }
        local c = cells[dug + 1]
        g:dig(c[1], c[2]); dug = dug + 1
      end
    elseif id == "memory" then
      if t > flips * 0.6 + 0.3 and flips < 7 then
        -- find one pair, miss one, open one more
        if flips < 2 then
          for j = 2, 16 do if g.cards[j].id == g.cards[1].id then if flips == 0 then g:flip(1) else g:flip(j) end break end end
        elseif flips < 4 then
          local a = 2
          while g.cards[a].matched do a = a + 1 end
          local b = a + 1
          while g.cards[b].matched or g.cards[b].id == g.cards[a].id do b = b + 1 end
          g:flip(flips == 2 and a or b)
        elseif flips == 6 then
          for i = 16, 1, -1 do if not g.cards[i].matched and not g.cards[i].up then g:flip(i) break end end
        end
        flips = flips + 1
      end
    elseif id == "rhythm" then
      for k = g.nextNote, math.min(#g.notes, g.nextNote + 2) do
        local n = g.notes[k]
        if not n.judged and g.clock >= n.t then g:tap(n.t + 0.02) end
      end
    end
    session:update(dt)
    t = t + dt
  end
end

function love.load()
  if os.getenv("FAKE_OS") then
    local fake = os.getenv("FAKE_OS")
    love.system.getOS = function() return fake end
  end
  if os.getenv("SAFE") then
    local sx, sy, sw, sh = os.getenv("SAFE"):match("(%d+),(%d+),(%d+),(%d+)")
    love.window.getSafeArea = function() return tonumber(sx), tonumber(sy), tonumber(sw), tonumber(sh) end
  end
  require("src.pokewalker.WalkerArt")._roots = { os.getenv("ART") or "G:/Gen2Recomped" }
  Hub = require("src.ui.WalkerMinigames")
  local st = demoState()
  if os.getenv("LAUNCHER") == "1" then
    local RomImporter = require("src.import.RomImporter")
    Importer = RomImporter.new(function() end, { launcher = true, onEditSave = function() end,
      onEditMaps = function() end, onEditTouchControls = function() end })
    Importer:_sbGo("walker")
    Importer.walker.st = st
    hub = Hub.open(Importer.walker, st, { seed = 7 })
  else
    hub = Hub.new(nil, st, { seed = 7 })
  end
  if GAME == "scores" then hub.scoresOf, hub.view = 1, "scores"
  elseif GAME == "hub" then hub.keyed = os.getenv("KEYED") == "1"
  else
    local i = IDX[GAME] or 1
    local session = hub:play(i, os.getenv("INTRO") ~= "1")
    local secs = tonumber(os.getenv("T") ~= "" and os.getenv("T") or nil) or tonumber(({ runner = 9, catch = 1.15, treasure = 3, memory = 4.4, rhythm = 14, results = 4 })[GAME] or 4)
    if GAME == "results" then
      session = hub:play(3, true)
      for _, c in ipairs(session.game.cells) do if c.hide then session.game:dig(c.c, c.r) end end
      for _ = 1, 120 do session:update(1 / 60) end
    elseif os.getenv("INTRO") ~= "1" then
      autoplay(session, secs)
      if os.getenv("PAUSE") == "1" then session:pause() end
    end
  end
end

function love.update(dt)
  if Importer then Importer:update(1 / 60) else hub:update(0) end
  frames = frames + 1
  if frames == want then
    love.graphics.captureScreenshot(function(img)
      local out = os.getenv("OUT") or "walker_games.png"
      local f = assert(io.open(out, "wb")); f:write(img:encode("png"):getString()); f:close()
      print("wrote " .. out)
      love.event.quit()
    end)
  end
end

function love.draw()
  if Importer then Importer:draw() else hub:drawFull() end
end
