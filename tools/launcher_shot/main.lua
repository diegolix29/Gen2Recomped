-- tools/launcher_shot/main.lua
--
--   SECTION=games CONSOLE=gb SERIES=pokemon GAME=red FRAMES=20 OUT=shot.png \
--     love tools/launcher_shot
--
-- Builds the launcher the way main.lua does, puts it in the requested view,
-- draws FRAMES frames and writes OUT (a path; default launcher.png in the
-- current folder). CLASSIC=1 shows the tab-bar launcher instead. CLICK=x,y
-- presses there before the shot.
-- the repo's own files (assets/logo, ...) through love.filesystem, the way
-- tools/gen4_hgss_overworld_harness mounts an install
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

local Importer
local frames, want = 0, tonumber(os.getenv("FRAMES") or "12")

function love.load()
  -- FAKE_OS=Android|iOS: the launcher as a phone sees it (touch layout).
  -- SAFE=x,y,w,h: a pretend love.window.getSafeArea (status bar / notch /
  -- gesture bar), e.g. SAFE=0,96,1080,2118 for a 1080x2340 phone.
  if os.getenv("FAKE_OS") then
    local fake = os.getenv("FAKE_OS")
    love.system.getOS = function() return fake end
  end
  if os.getenv("SAFE") then
    local sx, sy, sw, sh = os.getenv("SAFE"):match("(%d+),(%d+),(%d+),(%d+)")
    love.window.getSafeArea = function()
      return tonumber(sx), tonumber(sy), tonumber(sw), tonumber(sh)
    end
  end
  local RomImporter = require("src.import.RomImporter")
  Importer = RomImporter.new(function() end, {
    launcher = true,
    onEditSave = function(v, s) print("EDIT SAVE", v, s) end,
    onEditMaps = function(v) print("EDIT MAPS", v) end,
    onEditTouchControls = function() print("EDIT TOUCH") end,
  })
  if os.getenv("CLASSIC") == "1" then Importer.sidebarMode = false end
  local sec = os.getenv("SECTION")
  if sec and Importer._sbGo then Importer:_sbGo(sec) end
  if os.getenv("CONSOLE") then Importer.browseConsole = os.getenv("CONSOLE"); Importer.gamesView = "series" end
  if os.getenv("SERIES") then Importer.browseSeries = os.getenv("SERIES"); Importer.gamesView = "list" end
  -- SCRAPE=crystal,platinum: fetch their box art + descriptions first
  for v in (os.getenv("SCRAPE") or ""):gmatch("[^,]+") do
    print("SCRAPE", v, Importer:_sbScrape(v))
    print("  " .. tostring(Importer.settingsNotice))
  end
  if os.getenv("GAME") then Importer:_sbOpenGame(os.getenv("GAME")) end
  if os.getenv("MODS") == "find" then Importer:_selectTab("find") end
  if os.getenv("SEARCH") then Importer.modSearch = os.getenv("SEARCH") end
  -- WALKER=1: the Pokewalker screen (Tools); WALKER_PANEL=pickGame|...
  if os.getenv("WALKER") then
    -- WALKER_DATA=<install>: species facts and pictures from there, for a
    -- scratch IDENTITY (one with no data folder of its own)
    if os.getenv("WALKER_DATA") then require("src.core.SaveData").setDataDir(os.getenv("WALKER_DATA")) end
    Importer:_sbGo("walker")
    if os.getenv("WALKER_PANEL") then Importer.walker.panel = os.getenv("WALKER_PANEL") end
    if os.getenv("WALKER_TAB") then Importer.walker.tab = os.getenv("WALKER_TAB") end
    -- WALKER_DEMO=1: a walk in progress, in memory only (nothing saved)
    if os.getenv("WALKER_DEMO") then
      local Wk = require("src.pokewalker.Walker")
      local st = Wk.newState()
      local d = math.floor(os.time() / 86400)
      st.watts, st.lifetimeWatts, st.lifetimeSteps, st.days = 340, 2400, 48000, 9
      st.history = { { day = d, steps = 6420 }, { day = d - 1, steps = 9000 }, { day = d - 2, steps = 4000 }, { day = d - 4, steps = 12000 } }
      st.course = tonumber(os.getenv("WALKER_COURSE") or "15")
      st.caught = { { species = 43, name = "ODDISH", level = 12 } }
      st.items = { { name = "Great Ball" } }
      st.finds = { { kind = "w20", watts = 20 } }
      st.log = { { t = os.time() - 3600, text = "PIKACHU went on a walk to Big Forest." }, { t = os.time(), text = "Caught ODDISH!" } }
      st.walking = { species = tonumber(os.getenv("WALKER_SPECIES") or "25"), name = "PIKACHU", level = 14, types = { "ELECTRIC" },
        friendship = 120, steps = 3200, friendSteps = 0, encounters = {},
        source = { version = "heartgold", slot = "slot1", box = 1, index = 1 } }
      Importer.walker.st = st
      Wk.save = function() end
      -- WALKER_LEGEND=1: a legendary (shiny) among the catches (the gold star);
      -- WALKER_RADAR=legendary|wild: the bushes mid-search; WALKER_BATTLE=
      -- legendary|wild: the radar battle (WalkerRadarPools / P.drawStar)
      local legendEnc = { group = "L", species = tonumber(os.getenv("WALKER_LEGEND_SPECIES") or "250"), name = os.getenv("WALKER_LEGEND_NAME") or "HO-OH",
                          level = 45, legendary = true, shiny = os.getenv("WALKER_SHINY") and true or nil, radar = true }
      local wildEnc = { group = "B", species = 163, name = "HOOTHOOT", level = 9, radar = true }
      if os.getenv("WALKER_LEGEND") then
        st.caught[#st.caught + 1] = { species = legendEnc.species, name = legendEnc.name, level = 45, legendary = true, shiny = true }
      end
      local rmode = os.getenv("WALKER_RADAR")
      if rmode then
        Importer.walker.radar = { bush = 2, timer = 1e9, legendary = rmode == "legendary" or nil, marks = rmode ~= "legendary" and 2 or nil,
                                  encounter = rmode == "legendary" and legendEnc or wildEnc }
      end
      local bmode = os.getenv("WALKER_BATTLE")
      if bmode then
        local enc = bmode == "legendary" and legendEnc or wildEnc
        local b = Wk.newBattle(enc)
        if bmode == "legendary" then b.wild = 4 end
        b.text = (enc.legendary and "The legendary %s appeared!" or "A wild %s appeared!"):format(enc.name)
        Importer.walker.battle = b
      end
      -- WALKER_ECON=1: a streak, scores and achievements to show (WalkerEconomy)
      -- WALKER_SHOP=items|pokemon|gifts|cosmetics, WALKER_CONFIRM=1 (the ask)
      if os.getenv("WALKER_ECON") then
        local E = require("src.pokewalker.WalkerEconomy")
        local e = E.econ(st)
        e.login = { day = E.day(), streak = 4, best = 9 }
        e.passive = { day = E.day(), watts = 23, secs = 300 }
        e.counters = { catch = 7, dowse = 3, minigame_plays = 12, minigame_best = 4, purchases = 2 }
        e.done = { steps1k = os.time(), steps10k = os.time(), watts100 = os.time(), watts1k = os.time(),
                   catch1 = os.time(), play1 = os.time(), best1 = os.time(), buy1 = os.time(), streak3 = os.time(), streak7 = os.time() }
        e.owned.theme.night = true
        e.owned.shell.blue = true
        e.use = { shell = "blue" }
        local t0 = os.time()
        e.scores = {
          slots = { { score = 4200, t = t0 }, { score = 3100, t = t0 - 86400 }, { score = 2500, t = t0 - 3 * 86400 }, { score = 900, t = t0 - 5 * 86400 } },
          memory = { { score = 18, t = t0 - 7200 } },
        }
        st.log[#st.log + 1] = { t = os.time(), text = "Day 4 of your streak! Daily bonus +20 W" }
        Importer.walker.boardGame = os.getenv("WALKER_BOARD")
        Importer.walker.shopTab = os.getenv("WALKER_SHOP")
        if os.getenv("WALKER_CONFIRM") then
          Importer.walker.shopConfirm = { text = "Rare Candy for HeartGold. It will be in the bag the next time you play.", price = 200, y = 400, fn = function() end }
        end
        Importer.walker._loginDay = E.day()
      end
    end
  end
  -- CLOUD_SERVICE=google|onedrive: the cloud choice, in memory only
  if os.getenv("CLOUD_SERVICE") then Importer:_settings().cloudService = os.getenv("CLOUD_SERVICE") end
  -- CLOUD_CODE=WDJB-MJHT: a pretend sign-in waiting on that code (the popup)
  if os.getenv("CLOUD_CODE") then
    Importer._cloudFlow = { name = os.getenv("CLOUD_SERVICE") == "onedrive" and "OneDrive" or "Google Drive",
      auth = { poll = function() return "waiting" end, cancel = function() end },
      flow = { kind = "device", code = os.getenv("CLOUD_CODE"), url = "https://www.google.com/device" } }
  end
  if os.getenv("CLOUD_PENDING") then
    Importer._cloudFlow = { name="Google Drive", flow={kind="pending"},
      auth={cancel=function() end}, hint="Contacting the sign-in service...",
      task={poll=function() end, cancel=function() end} }
  end
  if os.getenv("TOOL") then
    local Sidebar = require("src.import.LauncherSidebar")
    for _, t in ipairs(Sidebar.TOOLS) do
      if t.id == os.getenv("TOOL") then Importer.toolFlow = { tool = t, label = t.label } end
    end
    if os.getenv("TOOLGAME") then Importer.toolFlow.version = os.getenv("TOOLGAME") end
  end
end

function love.update(dt)
  Importer:update(1 / 60)
  frames = frames + 1
  -- SETTINGS_SCROLL=n: scroll the settings page down n pixels
  -- PAGE_SCROLL=n|max: scroll the page column (huge values clamp to the end)
  if frames >= want - 4 and os.getenv("PAGE_SCROLL") then
    Importer.pageScroll = tonumber(os.getenv("PAGE_SCROLL")) or math.huge
  end
  if frames == want - 1 and os.getenv("SETTINGS_SCROLL") then Importer.settingsScroll = tonumber(os.getenv("SETTINGS_SCROLL")) end
  if frames == want - 2 and os.getenv("CLICK") then
    local x, y = os.getenv("CLICK"):match("(%d+),(%d+)")
    Importer:mousepressed(tonumber(x), tonumber(y), 1)
  end
  if frames == want then
    love.graphics.captureScreenshot(function(img)
      local data = img:encode("png")
      local out = os.getenv("OUT") or "launcher.png"
      local f = assert(io.open(out, "wb")); f:write(data:getString()); f:close()
      print("wrote " .. out)
      love.event.quit()
    end)
  end
end

function love.draw()
  -- BACKDROP_ONLY=1: just the background, to see what the game draws
  if os.getenv("BACKDROP_ONLY") == "1" then
    local w, h = love.graphics.getDimensions()
    require("src.import.LauncherBackdrop").draw(w, h)
    return
  end
  Importer:draw()
end

function love.textinput(t) Importer:textinput(t) end
