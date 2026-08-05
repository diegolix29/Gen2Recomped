-- Wrapper for native file pickers that handles borderless fullscreen mode.
--
-- Borderless fullscreen (desktop fullscreen) covers the entire screen, which
-- prevents native file pickers from appearing on top. This module wraps LOVE's
-- file picker functions and shell execution functions to temporarily exit
-- fullscreen before showing dialogs, then restore the original mode afterward.

local FilePicker = {}

-- Original LOVE functions that we wrap
local originalShowFileDialog = nil
local originalPickFile = nil
local originalOsExecute = nil
local originalIoPopen = nil
local installed = false

-- Temporarily exit borderless fullscreen before running a function, then restore.
-- Public function that other modules can use for their custom file pickers.
function FilePicker.withWindowedFullscreen(fn, ...)
  if not (love and love.window and love.window.getMode and love.window.setMode) then
    return fn(...)
  end
  local curW, curH, flags = love.window.getMode()
  flags = flags or {}
  local wasFullscreen = flags.fullscreen
  local wasDesktop = flags.fullscreentype == "desktop"

  if wasFullscreen and wasDesktop then
    love.window.setFullscreen(false)
    -- Wait for the mode change to take effect
    if love.event then
      for i = 1, 10 do
        love.event.pump()
        if love.timer then love.timer.sleep(0.05) end
      end
    end
  end

  local ok, result = pcall(fn, ...)

  if wasFullscreen and wasDesktop then
    love.window.setFullscreen(true, "desktop")
    if love.event then love.event.pump() end
  end

  if not ok then error(result) end
  return result
end

-- Wrapped version of love.window.showFileDialog
local function wrappedShowFileDialog(...)
  if not originalShowFileDialog then
    error("FilePicker not installed: call FilePicker.install() first")
  end
  return FilePicker.withWindowedFullscreen(originalShowFileDialog, ...)
end

-- Wrapped version of love.system.pickFile
local function wrappedPickFile(...)
  if not originalPickFile then
    error("FilePicker not installed: call FilePicker.install() first")
  end
  return FilePicker.withWindowedFullscreen(originalPickFile, ...)
end

-- Check if a command looks like it might spawn a file picker dialog
local function isFilePickerCommand(command)
  if type(command) ~= "string" then return false end
  local lower = command:lower()
  -- Known file picker commands
  return lower:find("powershell") or lower:find("osascript") or
         lower:find("zenity") or lower:find("kdialog") or
         lower:find("openfiledialog") or lower:find("savefiledialog")
end

-- Wrapped version of os.execute for shell commands that might spawn dialogs
local function wrappedOsExecute(...)
  if not originalOsExecute then
    error("FilePicker not installed: call FilePicker.install() first")
  end
  local command = ...
  if isFilePickerCommand(command) then
    return FilePicker.withWindowedFullscreen(originalOsExecute, ...)
  end
  return originalOsExecute(...)
end

-- Wrapped version of io.popen for shell commands that might spawn dialogs
local function wrappedIoPopen(...)
  if not originalIoPopen then
    error("FilePicker not installed: call FilePicker.install() first")
  end
  local command = ...
  if isFilePickerCommand(command) then
    return FilePicker.withWindowedFullscreen(originalIoPopen, ...)
  end
  return originalIoPopen(...)
end

-- Install the wrappers. Should be called early in love.load before any mods load.
function FilePicker.install()
  if installed then return end
  installed = true

  if love and love.window and love.window.showFileDialog then
    originalShowFileDialog = love.window.showFileDialog
    love.window.showFileDialog = wrappedShowFileDialog
  end

  if love and love.system and love.system.pickFile then
    originalPickFile = love.system.pickFile
    love.system.pickFile = wrappedPickFile
  end

  -- Wrap os.execute and io.popen for mods that might spawn shell dialogs
  originalOsExecute = os.execute
  os.execute = wrappedOsExecute

  originalIoPopen = io.popen
  io.popen = wrappedIoPopen
end

-- Restore the original functions (for testing or cleanup)
function FilePicker.uninstall()
  if not installed then return end
  installed = false

  if love and love.window and originalShowFileDialog then
    love.window.showFileDialog = originalShowFileDialog
    originalShowFileDialog = nil
  end

  if love and love.system and originalPickFile then
    love.system.pickFile = originalPickFile
    originalPickFile = nil
  end

  if originalOsExecute then
    os.execute = originalOsExecute
    originalOsExecute = nil
  end

  if originalIoPopen then
    io.popen = originalIoPopen
    originalIoPopen = nil
  end
end

return FilePicker
