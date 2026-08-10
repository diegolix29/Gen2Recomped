-- Native LÖVE2D port of Pokemon Recompilation Projects (Gen 1 & Gen 2). 
-- A packaged build creates its private game-data cache from a user-provided 
-- ROM on first boot.
--
-- The save editor (tools/save-editor/) ships inside every build and is
-- reachable two ways:
--   * standalone: POKEPORT_EDITOR=1 or `love . --editor`, its own window
--   * from the launcher: Edit on a save row, which suspends the launcher,
--     opens the editor on that slot's file, and restores the launcher when
--     the editor's Close button is pressed (openEditor / closeEditor below)

local editorMode = os.getenv("POKEPORT_EDITOR") == "1" or POKEPORT_EDITOR_MODE == true

-- Safely require advanced modules (prevents crashes if Gen 2 branch lacks them)
local hasSwitch, SwitchDiagnostics = pcall(require, "src.debug.SwitchDiagnostics")
local hasLaunch, LaunchOptions = pcall(require, "src.core.LaunchOptions")
local hasNx, NxDisplay = pcall(require, "src.core.NxDisplay")

-- Lua errors: persist a redacted trace in the save dir and surface a hint.
do
  local defaultErrorHandler = love.errorhandler
  function love.errorhandler(msg)
    local hint = nil
    if hasSwitch and SwitchDiagnostics.logLuaError then
      pcall(function() hint = SwitchDiagnostics.logLuaError(msg) end)
    end
    if hint and type(msg) == "string" then
      msg = msg .. "\n\n" .. hint
    end
    if defaultErrorHandler then
      return defaultErrorHandler(msg)
    end
  end
end

local Game, EditorApp, Importer, TouchEditor

-- quit-to-launcher state
local launchedIntoGame = false
local RELAUNCH_MARKER = "relaunch_to_launcher.txt"

local autopilot -- optional scripted-input dev tool (tests/autopilot.lua)
local driverCo  -- optional frame-driver (POKEPORT_DRIVER=file.lua): a
                -- coroutine that receives `Game` and yields once per frame
local speedOverride = tonumber(os.getenv("POKEPORT_SPEED"))
local mouseTouch = os.getenv("POKEPORT_TOUCH") == "1"

local function scriptedIterations()
  if not (autopilot or driverCo) then return 1 end
  return math.max(1, math.floor(require("src.core.GameSpeed").clamp(speedOverride)))
end

-- ------------------------------------------------------------ save editor
local editorHost, editorVersion, editorWindow
local closeEditor  

local function addEditorRequirePath()
  local fs = love.filesystem
  if not (fs.setRequirePath and fs.getRequirePath) then
    package.path = fs.getSource() .. "/tools/save-editor/?.lua;"
                .. fs.getSource() .. "/tools/save-editor/panels/?.lua;"
                .. package.path
    return
  end
  local current = fs.getRequirePath()
  if current:find("tools/save%-editor") then return end
  fs.setRequirePath("tools/save-editor/?.lua;tools/save-editor/panels/?.lua;"
    .. current)
end

local function resizeForEditor()
  if not (love.window and love.window.getMode and love.window.setMode) then return end
  local osName = love.system.getOS()
  if osName ~= "OS X" and osName ~= "Windows" and osName ~= "Linux" then return end
  local w, h, flags = love.window.getMode()
  if flags.fullscreen then return end
  local dw, dh = love.window.getDesktopDimensions()
  local wantW = math.max(w, math.min(1360, math.floor((dw or w) * 0.92)))
  local wantH = math.max(h, math.min(860, math.floor((dh or h) * 0.88)))
  if wantW <= w and wantH <= h then return end
  editorWindow = { w = w, h = h }
  love.window.setMode(wantW, wantH, flags)
end

local function restoreWindow()
  if not editorWindow then return end
  local _, _, flags = love.window.getMode()
  love.window.setMode(editorWindow.w, editorWindow.h, flags)
  editorWindow = nil
end

local function openEditor(version, slotId)
  local SaveData = require("src.core.SaveData")
  local path = SaveData.slotDiskPath(version, slotId)
  if not path then
    if Importer then
      Importer.saveNotice = Importer.saveNotice or {}
      Importer.saveNotice[version] =
        { ok = false, text = "Could not resolve that save slot on disk." }
    end
    return
  end
  local GameVersion = require("src.core.GameVersion")
  GameVersion.set(version)
  require("src.import.CacheFs").mountVersion(version)
  editorVersion = version
  editorHost = Importer
  if Importer and Importer.prepareOverlayHandoff then
    Importer:prepareOverlayHandoff()
  end
  Importer = nil
  editorMode = true
  resizeForEditor()
  addEditorRequirePath()
  EditorApp = require("App")
  EditorApp.load(path, { version = version, slotId = slotId, embedded = true,
                         onClose = function() closeEditor() end })
end

function closeEditor()
  local version = editorVersion
  editorMode = false
  if EditorApp and EditorApp.unload then EditorApp.unload() end
  EditorApp = nil
  if version then
    require("src.import.CacheFs").unmountVersion(version)
    require("src.core.Data"):unloadGenerated()
  end
  editorVersion = nil
  restoreWindow()
  Importer = editorHost
  editorHost = nil
  if Importer and Importer.resumeAfterOverlay then
    Importer:resumeAfterOverlay()
  end
  if Importer and version and Importer.savesChanged then
    Importer:savesChanged(version)
  end
end

-- ------------------------------------------------------------ touch controls editor
local touchEditorHost
local closeTouchControlsEditor

local function openTouchControlsEditor()
  touchEditorHost = Importer
  if Importer and Importer.prepareOverlayHandoff then
    Importer:prepareOverlayHandoff()
  end
  Importer = nil
  TouchEditor = require("src.ui.TouchControlsEditor")
  TouchEditor.load({ onClose = function() closeTouchControlsEditor() end })
end

function closeTouchControlsEditor()
  if TouchEditor and TouchEditor.unload then TouchEditor.unload() end
  TouchEditor = nil
  Importer = touchEditorHost
  touchEditorHost = nil
  if Importer and Importer.resumeAfterOverlay then
    Importer:resumeAfterOverlay()
  end
end

local function bootGame(version)
  local GameVersion = require("src.core.GameVersion")
  GameVersion.set(version or os.getenv("POKEPORT_VERSION") or "red")
  local CacheFs = require("src.import.CacheFs")
  
  -- Use cache prefix only if supported by the GameVersion core (prevents crashes on older branches)
  if type(GameVersion.cachePrefix) == "function" then
    CacheFs.prefix = GameVersion.cachePrefix()
  end
  CacheFs.mountVersion(GameVersion.get())
  
  if hasSwitch then
    pcall(function()
      SwitchDiagnostics.probeAssets(GameVersion.get())
    end)
  end
  
  if love.window and love.window.setTitle then
    local Version = require("src.core.Version")
    local info = GameVersion.info()
    local dName = info and info.displayName or (version or "Pokemon")
    love.window.setTitle(Version.title(dName .. " (Pokemon Recompilation Project)"))
  end
  
  Game = require("src.core.Game")
  Game:load()
  
  if os.getenv("POKEPORT_AUTOPILOT") then
    autopilot = require("tests.autopilot")
  end
  local driverPath = os.getenv("POKEPORT_DRIVER")
  if driverPath then
    local fn = assert(loadfile(driverPath))()
    driverCo = coroutine.create(fn)
  end
  Game.speedOverride = (autopilot or driverCo) and 1 or speedOverride
end

function love.load(args)
  pcall(function() require("src.core.FilePicker").install() end)
  pcall(function() require("src.core.HostShell").hideHostConsole() end)

  pcall(function()
    local Platform = require("src.core.Platform")
    if Platform.isNX and Platform.isNX() then
      require("src.core.NxAssetOverlay").install()
    end
  end)

  local Boot = require("src.update.Boot")
  if Boot.run(args) then return end

  local savePath
  for i, a in ipairs(args or {}) do
    if a == "--editor" then
      editorMode = true
    elseif a == "--developer" then
      _G.POKEPORT_DEV_MODE = true
    elseif a == "--save" and args[i + 1] and args[i + 1] ~= "" then
      savePath = args[i + 1]
    elseif a == "--speed" and tonumber(args[i + 1]) then
      speedOverride = tonumber(args[i + 1])
    end
  end
  love.graphics.setDefaultFilter("nearest", "nearest")
  
  if hasNx then pcall(function() NxDisplay.sync() end) end

  pcall(function()
    require("src.core.Orientation").applyOptions(
      require("src.core.SaveData").loadOptions())
  end)

  if editorMode then
    local version = os.getenv("POKEPORT_VERSION") or "red"
    require("src.core.GameVersion").set(version)
    require("src.import.CacheFs").mountVersion(version)
    addEditorRequirePath()
    EditorApp = require("App")
    EditorApp.load(savePath, { version = version })
    return
  end

  local RomImporter = require("src.import.RomImporter")
  local forceImport = os.getenv("POKEPORT_FORCE_IMPORT") == "1"
  local importPath = os.getenv("POKEPORT_IMPORT_ROM")
  local scriptedVersion = os.getenv("POKEPORT_VERSION") or "red"
  local ready = RomImporter.isReady(scriptedVersion)
  local scripted = os.getenv("POKEPORT_AUTOPILOT") or os.getenv("POKEPORT_DRIVER")
    or os.getenv("POKEPORT_IMPORT_ONLY") == "1" or importPath ~= nil

  if scripted then
    if forceImport or not ready then
      Importer = RomImporter.new(function(version)
        if os.getenv("POKEPORT_IMPORT_ONLY") == "1" then
          love.event.quit()
          return
        end
        Importer = nil
        bootGame(version or scriptedVersion)
      end)
      if importPath then Importer:startPath(importPath) end
      return
    end
    bootGame(scriptedVersion)
    return
  end

  pcall(function()
    local preload = require("src.mods.LauncherMods").translationStrings()
    if preload then require("src.core.Strings").load({ strings = preload }) end
  end)

  local relaunched = love.filesystem.getInfo(RELAUNCH_MARKER) ~= nil
  if relaunched then pcall(love.filesystem.remove, RELAUNCH_MARKER) end

  local launchGame, launchSlot
  if hasLaunch then
    pcall(function() launchGame, launchSlot = LaunchOptions.resolve(arg) end)
  end

  if launchGame and not relaunched and (not hasLaunch or not LaunchOptions.forceLauncher(arg)) then
    if RomImporter.isReady(launchGame) then
      if launchSlot and hasLaunch then pcall(function() LaunchOptions.selectSlot(launchGame, launchSlot) end) end
      launchedIntoGame = true
      bootGame(launchGame)
      return
    end
    if hasLaunch then LaunchOptions.pendingTab = launchGame end
  end

  Importer = RomImporter.new(function(version)
    Importer = nil
    bootGame(version)
  end, {
    launcher = true,
    forceImport = forceImport,
    onEditSave = openEditor,
    onEditTouchControls = openTouchControlsEditor,
  })
end

function love.update(dt)
  if hasSwitch then pcall(function() SwitchDiagnostics.maybeFlush(false) end) end
  if hasNx then pcall(function() NxDisplay.sync() end) end
  
  if editorMode then return EditorApp.update(dt) end
  if TouchEditor then return TouchEditor.update(dt) end
  if Importer then return Importer:update(dt) end

  local iterations = scriptedIterations()

  if autopilot then
    for _ = 1, iterations do
      autopilot.update()
      Game:update(1 / 60)
    end
    return
  end
  if driverCo then
    for _ = 1, iterations do
      local ok, err = coroutine.resume(driverCo, Game)
      if not ok then
        print("driver error: " .. tostring(err))
        love.event.quit(1)
        return
      end
      if coroutine.status(driverCo) == "dead" then
        love.event.quit()
        return
      end
      Game:update(1 / 60)
    end
    return
  end
  Game:update(dt)
end

function love.draw()
  if editorMode then return EditorApp.draw() end
  if TouchEditor then return TouchEditor.draw() end
  if Importer then return Importer:draw() end

  Game:draw()
  if Game.capturePath then
    local path = Game.capturePath
    Game.capturePath = nil
    love.graphics.captureScreenshot(function(imagedata)
      local fd = imagedata:encode("png")
      local f = io.open(path, "wb")
      if f then
        f:write(fd:getString())
        f:close()
      end
    end)
  end
end

function love.keypressed(key, scancode, isrepeat)
  if editorMode then return EditorApp.keypressed(key) end
  if TouchEditor then return TouchEditor.keypressed(key) end
  if Importer then return Importer:keypressed(key) end
  Game:keypressed(key)
end

function love.keyreleased(key)
  if editorMode or TouchEditor then return end
  if Importer then return end
  Game:keyreleased(key)
end

local function notifyJoystick(...)
  if hasSwitch and SwitchDiagnostics.onJoystickEvent then
    pcall(SwitchDiagnostics.onJoystickEvent, ...)
  end
end

function love.gamepadpressed(joystick, button)
  notifyJoystick("gamepadpressed", joystick, button)
  if editorMode then
    if EditorApp and EditorApp.gamepadpressed then
      return EditorApp.gamepadpressed(joystick, button)
    end
    return
  end
  if TouchEditor then
    if TouchEditor.gamepadpressed then return TouchEditor.gamepadpressed(joystick, button) end
    return
  end
  if Importer then return Importer:gamepadpressed(joystick, button) end
  Game:gamepadpressed(joystick, button)
end

function love.gamepadreleased(joystick, button)
  notifyJoystick("gamepadreleased", joystick, button)
  if editorMode then
    if EditorApp and EditorApp.gamepadreleased then return EditorApp.gamepadreleased(joystick, button) end
    return
  end
  if TouchEditor then
    if TouchEditor.gamepadreleased then return TouchEditor.gamepadreleased(joystick, button) end
    return
  end
  if Importer then return Importer:gamepadreleased(joystick, button) end
  Game:gamepadreleased(joystick, button)
end

function love.gamepadaxis(joystick, axis, value)
  notifyJoystick("gamepadaxis", joystick, axis, { value = value })
  if editorMode then
    if EditorApp and EditorApp.gamepadaxis then return EditorApp.gamepadaxis(joystick, axis, value) end
    return
  end
  if TouchEditor then
    if TouchEditor.gamepadaxis then return TouchEditor.gamepadaxis(joystick, axis, value) end
    return
  end
  if Importer then return Importer:gamepadaxis(joystick, axis, value) end
  Game:gamepadaxis(joystick, axis, value)
end

function love.joystickpressed(joystick, button)
  notifyJoystick("joystickpressed", joystick, button)
  if editorMode then
    if EditorApp and EditorApp.joystickpressed then return EditorApp.joystickpressed(joystick, button) end
    return
  end
  if TouchEditor then
    if TouchEditor.joystickpressed then return TouchEditor.joystickpressed(joystick, button) end
    return
  end
  if Importer then return Importer:joystickpressed(joystick, button) end
  Game:joystickpressed(joystick, button)
end

function love.joystickreleased(joystick, button)
  notifyJoystick("joystickreleased", joystick, button)
  if editorMode then
    if EditorApp and EditorApp.joystickreleased then return EditorApp.joystickreleased(joystick, button) end
    return
  end
  if TouchEditor then
    if TouchEditor.joystickreleased then return TouchEditor.joystickreleased(joystick, button) end
    return
  end
  if Importer then return Importer:joystickreleased(joystick, button) end
  Game:joystickreleased(joystick, button)
end

function love.joystickaxis(joystick, axis, value)
  notifyJoystick("joystickaxis", joystick, axis, { value = value })
  if editorMode then
    if EditorApp and EditorApp.joystickaxis then return EditorApp.joystickaxis(joystick, axis, value) end
    return
  end
  if TouchEditor then
    if TouchEditor.joystickaxis then return TouchEditor.joystickaxis(joystick, axis, value) end
    return
  end
  if Importer then return Importer:joystickaxis(joystick, axis, value) end
  Game:joystickaxis(joystick, axis, value)
end

function love.joystickhat(joystick, hat, direction)
  notifyJoystick("joystickhat", joystick, hat, { direction = direction })
  if editorMode then
    if EditorApp and EditorApp.joystickhat then return EditorApp.joystickhat(joystick, hat, direction) end
    return
  end
  if TouchEditor then
    if TouchEditor.joystickhat then return TouchEditor.joystickhat(joystick, hat, direction) end
    return
  end
  if Importer then return Importer:joystickhat(joystick, hat, direction) end
  Game:joystickhat(joystick, hat, direction)
end

function love.joystickadded(joystick)
  notifyJoystick("joystickadded", joystick)
  if editorMode or TouchEditor then return end
  if Importer then return end
  Game:joystickadded(joystick)
end

function love.joystickremoved(joystick)
  notifyJoystick("joystickremoved", joystick)
  if editorMode or TouchEditor then return end
  if Importer then return end
  Game:joystickremoved(joystick)
end

function love.focus(f)
  if editorMode or TouchEditor then return end
  if Importer then
    pcall(function() require("src.core.Input"):reset() end)
    if Importer.focus then Importer:focus(f) end
    return
  end
  Game:focus(f)
end

function love.visible(v)
  if editorMode or TouchEditor then return end
  if Importer then
    pcall(function() require("src.core.Input"):reset() end)
    return
  end
  Game:visible(v)
end

function love.lowmemory()
  if editorMode or TouchEditor or Importer then return end
  if Game then Game:onResume() end
end

function love.touchpressed(id, x, y, dx, dy, pressure)
  if editorMode then
    if love.system.getOS() == "iOS" then return end
    if EditorApp and EditorApp.mousepressed then return EditorApp.mousepressed(x, y, 1) end
    return
  end
  if TouchEditor then
    if love.system.getOS() == "iOS" then return end
    return TouchEditor.touchpressed(id, x, y)
  end
  if Importer then
    if Importer.touchpressed then return Importer:touchpressed(id, x, y, dx, dy, pressure) end
    -- Fallback for Gen 2 style core
    if love.system.getOS() == "iOS" then return end
    return Importer:mousepressed(x, y, 1)
  end
  if Game and Game.touchpressed then
    -- Handle missing parameters smoothly
    pcall(function() Game:touchpressed(id, x, y, dx, dy, pressure) end)
  end
end

function love.touchmoved(id, x, y, dx, dy, pressure)
  if editorMode then return end
  if TouchEditor then
    if love.system.getOS() == "iOS" then return end
    return TouchEditor.touchmoved(id, x, y)
  end
  if Importer and Importer.touchmoved then
    return Importer:touchmoved(id, x, y, dx, dy, pressure)
  end
  if Game and Game.touchmoved then
    pcall(function() Game:touchmoved(id, x, y, dx, dy, pressure) end)
  end
end

function love.touchreleased(id, x, y, dx, dy, pressure)
  if editorMode then return end
  if TouchEditor then
    if love.system.getOS() == "iOS" then return end
    return TouchEditor.touchreleased(id, x, y)
  end
  if Importer and Importer.touchreleased then
    return Importer:touchreleased(id, x, y, dx, dy, pressure)
  end
  if Game and Game.touchreleased then
    pcall(function() Game:touchreleased(id, x, y, dx, dy, pressure) end)
  end
end

function love.wheelmoved(x, y)
  if editorMode then
    if EditorApp.wheelmoved then return EditorApp.wheelmoved(x, y) end
    return
  end
  if TouchEditor then return end
  if Importer then return end
  Game:wheelmoved(x, y)
end

local eventMouseX, eventMouseY
if love.system and love.system.getOS() == "Linux"
    and love.mouse and love.mouse.getPosition then
  local polledGetPosition = love.mouse.getPosition
  love.mouse.getPosition = function()
    local x, y = polledGetPosition()
    local w, h = love.graphics.getDimensions()
    if x < 0 or y < 0 or x > w or y > h then
      if eventMouseX then return eventMouseX, eventMouseY end
      return math.max(0, math.min(x, w)), math.max(0, math.min(y, h))
    end
    return x, y
  end
end

function love.mousepressed(x, y, button, istouch)
  if not istouch then eventMouseX, eventMouseY = x, y end
  if TouchEditor then
    if love.system.getOS() == "Android" then return end
    return TouchEditor.mousepressed(x, y, button)
  end
  if Importer then
    if istouch and (love.system.getOS() == "Android" or love.system.getOS() == "iOS") then return end
    return Importer:mousepressed(x, y, button)
  end
  if editorMode and EditorApp.mousepressed then
    if istouch and love.system.getOS() == "Android" then return end
    return EditorApp.mousepressed(x, y, button)
  end
  if mouseTouch then
    if Game and button == 1 then pcall(function() Game:touchpressed("mouse", x, y) end) end
    return
  end
  if Game and Game.mousepressed and not istouch then 
    Game:mousepressed(x, y, button, istouch) 
  end
end

function love.mousereleased(x, y, button, istouch)
  if TouchEditor then
    if love.system.getOS() == "Android" then return end
    return TouchEditor.mousereleased(x, y, button)
  end
  if Importer then return end
  if editorMode and EditorApp.mousereleased then
    return EditorApp.mousereleased(x, y, button)
  end
  if mouseTouch then
    if Game and button == 1 then pcall(function() Game:touchreleased("mouse", x, y) end) end
    return
  end
  if Game and Game.mousereleased and not istouch then 
    Game:mousereleased(x, y, button, istouch) 
  end
end

function love.mousemoved(x, y, dx, dy, istouch)
  if not istouch then eventMouseX, eventMouseY = x, y end
  if TouchEditor then
    if love.system.getOS() == "Android" then return end
    return TouchEditor.mousemoved(x, y)
  end
  if editorMode or Importer then return end
  if mouseTouch then
    if Game and love.mouse.isDown(1) then pcall(function() Game:touchmoved("mouse", x, y) end) end
    return
  end
  if Game and Game.mousemoved and not istouch then 
    Game:mousemoved(x, y, dx, dy, istouch) 
  end
end

function love.textinput(text)
  if TouchEditor then return end
  if Importer and Importer.textinput then return Importer:textinput(text) end
  if editorMode and EditorApp.textinput then
    return EditorApp.textinput(text)
  end
end

local quitToLauncher = false

function love.quit()
  if editorMode and EditorApp.quit then
    if EditorApp.quit() then return true end
  end
  
  local scripted = os.getenv("POKEPORT_AUTOPILOT") or os.getenv("POKEPORT_DRIVER")
    or os.getenv("POKEPORT_IMPORT_ONLY") == "1" or os.getenv("POKEPORT_IMPORT_ROM")
    
  if Game and not Importer and not quitToLauncher and not scripted
      and not launchedIntoGame then
    quitToLauncher = true
    pcall(love.filesystem.write, RELAUNCH_MARKER, "1")
    pcall(function() require("src.core.HostShell").restart() end)
    return true
  end
  
  pcall(function() require("src.core.DiscordPresence").shutdown() end)
  if package.loaded["src.core.ChipAudio"] then
    pcall(package.loaded["src.core.ChipAudio"].shutdown)
  end
  if package.loaded["src.update.Check"] then
    pcall(package.loaded["src.update.Check"].shutdown)
  end
  if package.loaded["src.net.Fetch"] then
    pcall(package.loaded["src.net.Fetch"].shutdown)
  end
end

function love.filedropped(file)
  if editorMode and EditorApp and EditorApp.filedropped then
    return EditorApp.filedropped(file)
  end
  if Importer then Importer:filedropped(file) end
end

local function pacingEnabled()
  if os.getenv("POKEPORT_AUTOPILOT") then return false end
  if os.getenv("POKEPORT_DRIVER") then return false end
  if os.getenv("POKEPORT_IMPORT_ONLY") == "1" then return false end
  return true
end

function love.run()
  if love.load then love.load(love.arg.parseGameArguments(arg), arg) end
  if love.timer then love.timer.step() end

  local hasFrameCap, FrameCap = pcall(require, "src.core.FrameCap")
  local paced = pacingEnabled()
  local nextFrame = love.timer and love.timer.getTime() or 0
  local dt = 0

  return function()
    if love.event then
      love.event.pump()
      for name, a, b, c, d, e, f in love.event.poll() do
        if name == "quit" then
          if not love.quit or not love.quit() then
            if love.system and love.system.getOS() == "Android" then
              os.exit(a or 0)
            end
            return a or 0
          end
        end
        love.handlers[name](a, b, c, d, e, f)
      end
    end

    if love.timer then dt = love.timer.step() end
    if love.update then love.update(dt) end

    if love.graphics and love.graphics.isActive() then
      love.graphics.origin()
      love.graphics.clear(love.graphics.getBackgroundColor())
      if love.draw then love.draw() end
      love.graphics.present()
    end

    if love.timer then
      if paced and hasFrameCap and FrameCap.current then
        local budget = 1 / FrameCap.current
        nextFrame = nextFrame + budget
        local now = love.timer.getTime()
        if now - nextFrame > budget then
          nextFrame = now
        end
        while true do
          local remaining = nextFrame - love.timer.getTime()
          if remaining <= 0 then break end
          love.timer.sleep(remaining < 0.001 and remaining or 0.001)
        end
      else
        love.timer.sleep(0.001)
      end
    end
  end
end