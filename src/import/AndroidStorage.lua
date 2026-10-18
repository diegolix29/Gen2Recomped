-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- ANDROID'S STORAGE GRANT FOR A CHOSEN GAME-DATA FOLDER (docs/data-location.md).
--
-- A folder outside the app's own directories (Browse... in CHOOSE STORAGE)
-- is written with POSIX io.open, which Android 11+ allows only with "All
-- files access" (MANAGE_EXTERNAL_STORAGE; WRITE_EXTERNAL_STORAGE before 11).
-- GameActivity asks once, when the folder is picked. Nothing asked again when
-- the grant was missing LATER -- reinstalled app, grant revoked, a prompt that
-- another runtime permission dialog cancelled -- and the launcher just fell
-- back to the app folder in silence. This asks through the bridges the APK
-- already has (love.system.hasStorageAccess / requestStorageAccess /
-- pathIsAppOwned), and on the way back (love.focus) re-applies the folder.
--
-- Every function is a no-op off Android and on an APK without the bridges.

local A = {}

local function bridge(name)
  local sys = love and love.system
  return sys and type(sys[name]) == "function" and sys[name] or nil
end

local function isAndroid()
  return love and love.system and love.system.getOS and love.system.getOS() == "Android"
end

-- true when `path` needs the shared-storage grant and does not have it
function A.needsGrant(path)
  if not isAndroid() or type(path) ~= "string" or path == "" then return false end
  local has, owned = bridge("hasStorageAccess"), bridge("pathIsAppOwned")
  if not (has and owned and bridge("requestStorageAccess")) then return false end
  local okO, isOwned = pcall(owned, path)
  if okO and isOwned then return false end
  local okH, granted = pcall(has)
  return not (okH and granted)
end

-- Ask for the grant for `path` (the system screen / prompt opens over the
-- launcher) and remember the folder so focus() can re-apply it. True when
-- the prompt was raised.
function A.ask(importer, path)
  if not A.needsGrant(path) then return false end
  local ok = pcall(bridge("requestStorageAccess"))
  if not ok then return false end
  importer._storageAskFor = path
  importer.settingsNotice = "Android needs \"All files access\" to use " .. tostring(path)
    .. ". Allow it on the screen that opened, then come back."
  importer._settingsRowCache = nil
  return true
end

-- Once per launch: a folder chosen earlier that is unusable now only for want
-- of the grant asks for it again instead of falling back without a word.
function A.checkStored(importer)
  if importer._storageChecked then return end
  importer._storageChecked = true
  if not isAndroid() then return end
  local SaveData = require("src.core.SaveData")
  local raw = SaveData.dataDirSetting()
  if not raw or SaveData.isPortable() then return end
  if SaveData.dataDirProblem() == nil then return end
  A.ask(importer, raw)
end

-- Back from the system screen: with the grant now in hand, apply the folder.
function A.focus(importer, f)
  local path = importer._storageAskFor
  if not (f and path) then return end
  if A.needsGrant(path) then return end   -- still not granted: keep waiting
  importer._storageAskFor = nil
  importer:setDataDir(path)
end

-- wired into the launcher (RomImporter's tail): the boot check from update,
-- the re-apply from focus, and an ask after a folder change that failed
function A.install(RI)
  local origUpdate = RI.update
  RI.update = function(self, ...)
    if not self._storageChecked then pcall(A.checkStored, self) end
    return origUpdate(self, ...)
  end
  local origFocus = RI.focus
  RI.focus = function(self, f, ...)
    local r = origFocus and origFocus(self, f, ...)
    pcall(A.focus, self, f)
    return r
  end
  local origSet = RI.setDataDir
  RI.setDataDir = function(self, path, ...)
    local r = origSet(self, path, ...)
    if path ~= nil and path ~= "" then
      local okR, report = pcall(function() return require("src.import.CacheFs").rootReport() end)
      if not r or not (okR and report and report.kind == "custom") then pcall(A.ask, self, path) end
    end
    return r
  end
end

return A
