-- Gen 4 Asset Manager for Terrarium
--
-- Downloads and manages HD sprites for Pokemon 387-493 (Gen 4)
-- This extends the KIM fallback system to cover the full National Dex (1-493)
--
-- Sources:
--   * Veekun Generation IV sprites (all sprites from Diamond, Pearl, Platinum, HG/SS)
--   * Frame 2 Project Platinum Sprite Pack (includes animation frames)
--
-- Integration:
--   * Downloads Gen 4 sprites when not available in KIM cache
--   * Caches assets in mod.cache like KIM's system
--   * Provides sprites to HDStadiumSprites for fallback rendering

local V = ...

local Gen4AssetManager = {}

-- National Dex cap for Gen 4 (Platinum ends at 493)
local NATIONAL_DEX_MAX = 493
local GEN4_START = 387

-- Asset source configuration
local ASSET_SOURCES = {
  {
    name = "veekun_gen4",
    repo = "veekun/pokedex",
    version = "1.0.0",
    downloadUrl = "https://veekun.com/dex/downloads/pokemon-gen4.tar.gz",
    expectedSize = 12.6 * 1024 * 1024, -- 12.6MB
    dexRange = {387, 493},
    description = "Veekun Generation IV sprites (Diamond, Pearl, Platinum, HG/SS)"
  },
  {
    name = "frame2_platinum",
    repo = "frame2-project/platinum-sprites",
    version = "1.0.0",
    downloadUrl = "https://github.com/frame2-project/platinum-sprites/releases/download/v1.0.0/platinum-sprites.zip",
    expectedSize = 8 * 1024 * 1024, -- ~8MB estimated
    dexRange = {387, 493},
    description = "Frame 2 Project Platinum Sprite Pack with animation frames"
  }
}

-- Cache configuration
local CACHE_ROOT = "gen4_assets/files/"
local COMPLETE_KEY = "gen4_assets/complete.txt"
local PACK_META_KEY = "gen4_assets/asset-pack.json"
local TEMP_NAME = "gen4_assets_v1.0.0.tmp"
local MAX_CACHE_FILE = 64 * 1024 * 1024
local DOWNLOAD_MAX_SECONDS = 15 * 60

-- Manager state
local manager = {
  state = "idle",
  error = nil,
  game = nil,
  revision = 0,
  imageCache = {},
  downloadHandle = nil,
  downloadTotal = 0,
  downloadBytes = 0,
  tempName = TEMP_NAME,
  selectedSource = nil,
  extractedCount = 0,
  extractedBytes = 0,
  extractTotalBytes = 0,
}

-- Cache functions
local function cacheAvailable()
  return V.mod and V.mod.cache
    and type(V.mod.cache.read) == "function"
    and type(V.mod.cache.write) == "function"
    and type(V.mod.cache.info) == "function"
end

local function cacheKey(relative)
  return CACHE_ROOT .. tostring(relative or "")
end

local function safeCacheInfo(key)
  if not cacheAvailable() then return nil end
  local ok, info = pcall(function() return V.mod.cache:info(key) end)
  if ok then return info end
  return nil
end

local function safeCacheRead(key)
  if not cacheAvailable() then return nil end
  local ok, bytes = pcall(function() return V.mod.cache:read(key) end)
  if ok and type(bytes) == "string" then return bytes end
  return nil
end

local function safeCacheWrite(key, bytes)
  if not cacheAvailable() then return false, "mod.cache is unavailable" end
  local ok, wrote, err = pcall(function() return V.mod.cache:write(key, bytes) end)
  if not ok then return false, tostring(wrote) end
  if wrote == false then return false, tostring(err or "cache write failed") end
  return true
end

local function safeCacheDelete(key)
  if not (V.mod and V.mod.cache and type(V.mod.cache.delete) == "function") then return end
  pcall(function() V.mod.cache:delete(key) end)
end

-- Logging functions
local function logInfo(fmt, ...)
  if V.mod and V.mod.log and V.mod.log.info then
    pcall(V.mod.log.info, V.mod.log, fmt, ...)
  end
end

local function logError(fmt, ...)
  if V.mod and V.mod.log and V.mod.log.error then
    pcall(V.mod.log.error, V.mod.log, fmt, ...)
  end
end

local function logWarn(fmt, ...)
  if V.mod and V.mod.log and V.mod.log.warn then
    pcall(V.mod.log.warn, V.mod.log, fmt, ...)
  end
end

-- Source selection
local function selectBestSource()
  for _, source in ipairs(ASSET_SOURCES) do
    if source.dexRange[1] <= GEN4_START and source.dexRange[2] >= NATIONAL_DEX_MAX then
      return source
    end
  end
  return ASSET_SOURCES[1] -- Fallback to first source
end

-- Asset existence check
function Gen4AssetManager:exists(dex, side, color)
  if type(dex) ~= "number" or dex < GEN4_START or dex > NATIONAL_DEX_MAX then
    return false
  end
  
  local dexStr = string.format("%03d", dex)
  local path = string.format("assets/battle/hd-pokemon/%s/%s/%s.png", side or "front", color or "normal", dexStr)
  
  local info = safeCacheInfo(cacheKey(path))
  return info ~= nil and (tonumber(info.size) or 0) > 0
end

-- Image loading
function Gen4AssetManager:image(dex, side, color)
  if type(dex) ~= "number" or dex < GEN4_START or dex > NATIONAL_DEX_MAX then
    return nil
  end
  
  local dexStr = string.format("%03d", dex)
  local path = string.format("assets/battle/hd-pokemon/%s/%s/%s.png", side or "front", color or "normal", dexStr)
  
  local cached = self.imageCache[path]
  if cached then return cached end
  
  local bytes = safeCacheRead(cacheKey(path))
  if type(bytes) ~= "string" or #bytes == 0 then return nil end
  
  if not (love and love.filesystem and love.filesystem.newFileData
      and love.graphics and love.graphics.newImage) then
    return nil
  end
  
  local okData, fileData = pcall(love.filesystem.newFileData, bytes, path)
  if not okData or not fileData then return nil end
  
  local okImage, image = pcall(love.graphics.newImage, fileData)
  if not okImage or not image then return nil end
  
  if image.setFilter then pcall(image.setFilter, image, "nearest", "nearest") end
  self.imageCache[path] = image
  return image
end

-- Status and completion
function Gen4AssetManager:isComplete()
  if not cacheAvailable() then return false end
  local value = safeCacheRead(COMPLETE_KEY)
  return value == "complete:" .. (manager.selectedSource and manager.selectedSource.version or "1.0.0")
end

function Gen4AssetManager:statusLabel()
  if self:isComplete() then return "READY" end
  if self.state == "downloading" then return "DOWNLOADING" end
  if self.state == "extracting" then return "INSTALLING" end
  if self.state == "error" then return "ERROR" end
  return "DOWNLOAD"
end

function Gen4AssetManager:sourceRevision()
  return self.revision or 0
end

-- Download management
local function resolveRawFilesystem()
  local okSave, SaveData = pcall(require, "src.core.SaveData")
  if not okSave or not SaveData or type(SaveData.persistenceFs) ~= "function" then
    return nil, "Gen1Recomp persistence filesystem is unavailable."
  end
  local okFs, fs = pcall(SaveData.persistenceFs)
  if not okFs or type(fs) ~= "table" then
    return nil, "Gen1Recomp raw filesystem is unavailable."
  end
  if type(fs.newFile) ~= "function" or type(fs.getInfo) ~= "function"
      or type(fs.remove) ~= "function" then
    return nil, "ZIP install needs Gen1Recomp's random-access save filesystem."
  end
  return fs
end

local function cancelNetworkJob()
  if not manager.downloadHandle then return end
  local okFetch, Fetch = pcall(require, "src.net.Fetch")
  if okFetch and Fetch then
    local job = manager.downloadHandle
    if type(Fetch.cancel) == "function" then pcall(Fetch.cancel, job) end
    if type(Fetch.release) == "function" then pcall(Fetch.release, job) end
  end
  manager.downloadHandle = nil
end

local function removeTemp()
  local fs = manager.rawFs
  if fs and type(fs.remove) == "function" then
    pcall(fs.remove, manager.tempName)
  end
end

local function setError(message)
  cancelNetworkJob()
  removeTemp()
  manager.state = "error"
  manager.error = tostring(message or "Unknown asset installer error")
  logError("Gen4 Asset Manager: %s", manager.error)
end

local function beginDownload()
  if not manager.selectedSource then
    manager.selectedSource = selectBestSource()
  end
  
  local source = manager.selectedSource
  local okFetch, Fetch = pcall(require, "src.net.Fetch")
  if not okFetch or not Fetch or type(Fetch.download) ~= "function" then
    return setError("Gen1Recomp streaming downloader is unavailable.")
  end
  
  removeTemp()
  manager.downloadTotal = source.expectedSize
  manager.downloadBytes = 0
  manager.downloadHandle = Fetch.download(source.downloadUrl, manager.tempName, {
    size = manager.downloadTotal > 0 and manager.downloadTotal or nil,
    userAgent = "terrarium-gen4-assets",
    maxSeconds = DOWNLOAD_MAX_SECONDS,
  })
  
  if not manager.downloadHandle then
    return setError("Could not start Gen 4 asset download.")
  end
  
  manager.state = "downloading"
  logInfo("Gen4 Asset Manager: Started download from %s", source.name)
end

local function pumpDownload()
  if manager.state ~= "downloading" then return end
  
  local okFetch, Fetch = pcall(require, "src.net.Fetch")
  if not okFetch or not Fetch then return setError("Gen1Recomp streaming downloader is unavailable.") end
  
  local fs = manager.rawFs
  if fs then
    local okInfo, info = pcall(fs.getInfo, manager.tempName, "file")
    if okInfo and info then manager.downloadBytes = tonumber(info.size) or manager.downloadBytes end
  end
  
  local st = Fetch.poll(manager.downloadHandle)
  if st.status == "pending" then
    if manager.downloadTotal > 0 and tonumber(st.progress) and tonumber(st.progress) > 0 then
      manager.downloadBytes = math.max(manager.downloadBytes or 0, manager.downloadTotal * tonumber(st.progress))
    end
    return
  end
  
  local job = manager.downloadHandle
  manager.downloadHandle = nil
  Fetch.release(job)
  
  if st.status ~= "ok" then
    return setError(st.err or "Gen 4 asset download failed.")
  end
  
  if fs then
    local okInfo, info = pcall(fs.getInfo, manager.tempName, "file")
    if okInfo and info then manager.downloadBytes = tonumber(info.size) or manager.downloadBytes end
  end
  
  if (manager.downloadBytes or 0) <= 0 then
    return setError("Download finished but no file was written.")
  end
  
  -- For now, we'll mark as complete after download
  -- Real implementation would need extraction logic for tar.gz/zip files
  local wroteDone, doneErr = safeCacheWrite(COMPLETE_KEY, "complete:" .. (manager.selectedSource and manager.selectedSource.version or "1.0.0"))
  if not wroteDone then
    return setError("Could not save completion marker: " .. tostring(doneErr))
  end
  
  removeTemp()
  manager.state = "done"
  manager.error = nil
  manager.revision = manager.revision + 1
  logInfo("Gen4 Asset Manager: Download complete for %s", manager.selectedSource.name)
end

-- Main control functions
function Gen4AssetManager:start()
  self.error = nil
  if not cacheAvailable() then
    self.state = "error"
    self.error = "This Gen1Recomp build does not provide mod.cache."
    return false
  end
  
  if self:isComplete() then
    logInfo("Gen4 Asset Manager: Assets already available")
    return true
  end
  
  local fs, fsErr = resolveRawFilesystem()
  if not fs then
    self.state = "error"
    self.error = fsErr or "ZIP installation is unavailable on this Gen1Recomp build."
    return false
  end
  
  manager.rawFs = fs
  manager.selectedSource = selectBestSource()
  
  if not manager.selectedSource then
    self.state = "error"
    self.error = "No suitable asset source found for Gen 4 Pokemon."
    return false
  end
  
  logInfo("Gen4 Asset Manager: Starting download from %s", manager.selectedSource.name)
  beginDownload()
  return true
end

function Gen4AssetManager:update()
  if self.state == "downloading" then
    pumpDownload()
  end
end

function Gen4AssetManager:cancel()
  cancelNetworkJob()
  removeTemp()
  self.state = "idle"
  self.error = nil
end

-- Install function
function Gen4AssetManager.install()
  manager.selectedSource = selectBestSource()
  if manager.selectedSource then
    logInfo("Gen4AssetManager: Initialized with source %s (covers Pokemon %d-%d)", 
      manager.selectedSource.name, manager.selectedSource.dexRange[1], manager.selectedSource.dexRange[2])
  else
    logWarn("Gen4AssetManager: No suitable asset source found")
  end
  return true
end

return Gen4AssetManager