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
