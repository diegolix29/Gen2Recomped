-- HD Pokémon Asset Manager, same pattern as Kanto in Motion:
-- Fetch.download (desktop + Android), then incremental ZIP extract into
-- mod.cache. No Python. No host shell except the optional desktop file picker.
local V = ...
local Compat = V.require("EngineCompat")

local Install = {}
Install.ID = "DRAMATIC_SHAPE:hdPokemon"
Install.LABEL = "HD POKEMON"
Install.PICKED = "picked_hd_pokemon.zip"
Install.TEMP = "hd_pokemon_dl.tmp.zip"
Install.CACHE_ROOT = "hd_pokemon/"
Install.COMPLETE_KEY = "hd_pokemon/complete.txt"
Install.DEX_MAX = 493
Install.REPO = "HaseoSora/Kanto-in-Motion-Assets"
Install.ASSET_VERSION = "1.0.0"
Install.EXTRACT_BUDGET = 0.010
Install.MAX_CACHE_FILE = 64 * 1024 * 1024
Install.DOWNLOAD_MAX_SECONDS = 15 * 60

local NAME_RE = "^(%d+)%-(front|back)%-([ns])(?:%-([fm]))?%.gif$"

Install.status = {
  state = "idle",
  error = nil,
  current = 0,
  total = 1,
  message = "",
  count = 0,
  downloadBytes = 0,
  downloadTotal = 0,
}

local manager = Install

local function modHandle()
  return V.mod
end

local function cacheAvailable()
  local mod = modHandle()
  return mod and mod.cache
    and type(mod.cache.read) == "function"
    and type(mod.cache.write) == "function"
    and type(mod.cache.info) == "function"
end

local function cacheKey(relative)
  return Install.CACHE_ROOT .. tostring(relative or "")
end

local function safeCacheInfo(key)
  if not cacheAvailable() then return nil end
  local ok, info = pcall(function() return modHandle().cache:info(key) end)
  if ok then return info end
  return nil
end

local function safeCacheRead(key)
  if not cacheAvailable() then return nil end
  local ok, bytes = pcall(function() return modHandle().cache:read(key) end)
  if ok and type(bytes) == "string" then return bytes end
  return nil
end

local function safeCacheWrite(key, bytes)
  if not cacheAvailable() then return false, "mod.cache is unavailable" end
  local ok, wrote, err = pcall(function() return modHandle().cache:write(key, bytes) end)
  if not ok then return false, tostring(wrote) end
  if wrote == false then return false, tostring(err or "cache write failed") end
  return true
end

local function resolveRawFilesystem()
  local okSave, SaveData = pcall(require, "src.core.SaveData")
  if not okSave or not SaveData or type(SaveData.persistenceFs) ~= "function" then
    return nil, "save filesystem unavailable"
  end
  local okFs, fs = pcall(SaveData.persistenceFs)
  if not okFs or type(fs) ~= "table" then
    return nil, "save filesystem unavailable"
  end
  if type(fs.newFile) ~= "function" or type(fs.getInfo) ~= "function" then
    return nil, "random-access save filesystem unavailable"
  end
  return fs
end

local function setStatus(state, message)
  Install.status.state = state
  if message then Install.status.message = message end
end

function Install.canDialog()
  return Compat.canFileDialog and Compat.canFileDialog() or false
end

function Install.count()
  local HdPokemon = V.HdPokemon or (V.require and V.require("HdPokemon"))
  if HdPokemon and type(HdPokemon.installedCount) == "function" then
    local ok, n = pcall(HdPokemon.installedCount)
    if ok and type(n) == "number" then return n end
  end
  return 0
end

function Install.isComplete()
  local value = safeCacheRead(Install.COMPLETE_KEY)
  return type(value) == "string" and value ~= ""
end

function Install.row()
  return {
    id = Install.ID,
    label = Install.LABEL,
    value = function()
      local st = Install.status.state
      if st == "checking" then return "CHECK" end
      if st == "downloading" then return "GET" end
      if st == "extracting" then return "INSTALL" end
      if st == "error" then return "ERROR" end
      if Install.isComplete() or Install.count() > 0 then return "READY" end
      return "OPEN"
    end,
    activate = function(game)
      pcall(Install.open, game)
    end,
    step = function(game)
      pcall(Install.open, game)
      return true
    end,
  }
end

function Install.open(game)
  local ok, Screen = pcall(V.require, "HdPokemonScreen")
  if ok and Screen and game and game.stack then
    pcall(function() game.stack:push(Screen.new(game)) end)
  end
end

local function le16(s, p)
  local a, b = s:byte(p, p + 1)
  if not b then return nil end
  return a + b * 256
end

local function le32(s, p)
  local a, b, c, d = s:byte(p, p + 3)
  if not d then return nil end
  return a + b * 256 + c * 65536 + d * 16777216
end

local function closeZipReader()
  local r = manager.zipReader
  if r and r.file and type(r.file.close) == "function" then
    pcall(function() r.file:close() end)
  end
  manager.zipReader = nil
end

local function removeTemp()
  local fs = manager.rawFs
  if fs and type(fs.remove) == "function" and manager.tempName == Install.TEMP then
    pcall(fs.remove, manager.tempName)
  end
end

local function cleanupArchive()
  closeZipReader()
  removeTemp()
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

local function setError(message)
  cleanupArchive()
  cancelNetworkJob()
  manager.releaseHandle = nil
  Install.status.state = "error"
  Install.status.error = tostring(message or "unknown error")
  Install.status.message = "ERROR"
end

local function openZipReader(name)
  closeZipReader()
  local fs = manager.rawFs
  if not fs then return nil, "save filesystem unavailable" end
  local okNew, fileOrErr = pcall(fs.newFile, name)
  if not okNew or not fileOrErr then return nil, tostring(fileOrErr or "could not open zip") end
  local f = fileOrErr
  local okOpen, opened, openErr = pcall(function() return f:open("r") end)
  if not okOpen or opened == false then
    pcall(function() f:close() end)
    return nil, tostring(openErr or "could not open zip")
  end
  local okSize, size = pcall(function() return f:getSize() end)
  if not okSize or not tonumber(size) or tonumber(size) < 22 then
    pcall(function() f:close() end)
    return nil, "file is too small to be a zip"
  end
  local r = { file = f, size = tonumber(size) }
  function r:readAt(offset, count)
    if offset < 0 or count < 0 or offset + count > self.size then
      return nil, "zip read out of range"
    end
    local okSeek, seeked = pcall(function() return self.file:seek(offset) end)
    if not okSeek or seeked == false then return nil, "zip seek failed" end
    local okRead, data = pcall(function() return self.file:read(count) end)
    if not okRead or type(data) ~= "string" or #data ~= count then
      return nil, "zip read failed"
    end
    return data
  end
  manager.zipReader = r
  manager.tempName = name
  return r
end

local function gifName(path)
  local base = tostring(path or ""):gsub("\\", "/"):match("([^/]+)$") or ""
  return base:lower()
end

local function classifyEntry(name)
  name = tostring(name or ""):gsub("\\", "/")
  if name:sub(-1) == "/" then return nil end
  if name == "data/hd_pokemon.lua" or name:match("hd_pokemon%.lua$") then
    return { kind = "lua", relative = "data/hd_pokemon.lua" }
  end
  if name:match("^assets/battle/hd%-pokemon/.+%.png$")
      or name:match("/assets/battle/hd%-pokemon/.+%.png$") then
    local rel = name:match("(assets/battle/hd%-pokemon/.+)$")
    return { kind = "png", relative = rel }
  end
  local base = gifName(name)
  local dex, side, color, gender = base:match(NAME_RE)
  if dex then
    return {
      kind = "gif",
      relative = name,
      dex = tonumber(dex),
      side = side,
      color = color == "s" and "shiny" or "normal",
      gender = gender == "m" and "male" or (gender == "f" and "female" or "default"),
    }
  end
  return nil
end

local function scanZipDirectory(reader)
  local tailSize = math.min(reader.size, 22 + 65535 + 256)
  local tail, tailErr = reader:readAt(reader.size - tailSize, tailSize)
  if not tail then return nil, tailErr end
  local eocd
  for i = #tail - 21, 1, -1 do
    if tail:sub(i, i + 3) == "PK\005\006" then eocd = i break end
  end
  if not eocd then return nil, "zip end record not found" end
  local entries = le16(tail, eocd + 10)
  local cdSize = le32(tail, eocd + 12)
  local cdOffset = le32(tail, eocd + 16)
  if not entries or not cdSize or not cdOffset then return nil, "zip end record truncated" end
  if entries == 0xFFFF or cdSize == 0xFFFFFFFF or cdOffset == 0xFFFFFFFF then
    return nil, "zip64 not supported"
  end
  local cd, cdErr = reader:readAt(cdOffset, cdSize)
  if not cd then return nil, cdErr end
  local out, pos = {}, 1
  for _ = 1, entries do
    if cd:sub(pos, pos + 3) ~= "PK\001\002" then return nil, "invalid zip directory" end
    local flags = le16(cd, pos + 8) or 0
    local method = le16(cd, pos + 10)
    local compSize = le32(cd, pos + 20)
    local uncompSize = le32(cd, pos + 24)
    local nameLen = le16(cd, pos + 28)
    local extraLen = le16(cd, pos + 30)
    local commentLen = le16(cd, pos + 32)
    local localOffset = le32(cd, pos + 42)
    local nameStart = pos + 46
    local name = cd:sub(nameStart, nameStart + nameLen - 1)
    pos = nameStart + nameLen + extraLen + commentLen
    if (flags % 2) == 1 then return nil, "encrypted zip" end
    local cls = classifyEntry(name)
    if cls then
      if method ~= 0 and method ~= 8 then
        return nil, "unsupported zip method for " .. name
      end
      if uncompSize > Install.MAX_CACHE_FILE then
        return nil, "file exceeds 64 MB: " .. name
      end
      cls.method = method
      cls.compressedSize = compSize
      cls.size = uncompSize
      cls.localOffset = localOffset
      out[#out + 1] = cls
    end
  end
  return out
end

local function readZipEntry(reader, item)
  local hdr, hdrErr = reader:readAt(item.localOffset, 30)
  if not hdr then return nil, hdrErr end
  if hdr:sub(1, 4) ~= "PK\003\004" then return nil, "invalid zip local header" end
  local method = le16(hdr, 9)
  local nameLen = le16(hdr, 27)
  local extraLen = le16(hdr, 29)
  local dataOffset = item.localOffset + 30 + nameLen + extraLen
  local packed, packedErr = reader:readAt(dataOffset, item.compressedSize)
  if not packed then return nil, packedErr end
  local bytes = packed
  if item.method == 8 then
    if not (love and love.data and type(love.data.decompress) == "function") then
      return nil, "deflate unavailable"
    end
    local okInflate, inflated = pcall(love.data.decompress, "string", "deflate", packed)
    if not okInflate or type(inflated) ~= "string" then return nil, "deflate failed" end
    bytes = inflated
  end
  return bytes
end

local function luaRecord(image, meta)
  local durs = {}
  for i = 1, #(meta.durations or {}) do
    durs[i] = tostring(meta.durations[i])
  end
  return string.format(
    '{ image = "%s", width = %d, height = %d, columns = %d, frames = %d, durations = {%s}, displayScale = %.6f }',
    image, meta.width, meta.height, meta.columns, meta.frames,
    table.concat(durs, ","), tonumber(meta.displayScale) or 0.33)
end

local function writeMetadata()
  local records = manager.records or {}
  local lines = { "return {" }
  local dexes = {}
  for dex in pairs(records) do dexes[#dexes + 1] = dex end
  table.sort(dexes)
  for _, dex in ipairs(dexes) do
    local species = records[dex]
    lines[#lines + 1] = string.format("  [%d] = {", dex)
    lines[#lines + 1] = string.format("    dex = %d,", dex)
    for _, side in ipairs({ "front", "back" }) do
      local sideRec = species[side]
      if sideRec then
        lines[#lines + 1] = "    " .. side .. " = {"
        for _, color in ipairs({ "normal", "shiny" }) do
          local colorRec = sideRec[color]
          if colorRec then
            lines[#lines + 1] = "      " .. color .. " = {"
            for _, gender in ipairs({ "default", "male", "female" }) do
              local rec = colorRec[gender]
              if rec then
                lines[#lines + 1] = "        " .. gender .. " = " .. luaRecord(rec.image, rec) .. ","
              end
            end
            lines[#lines + 1] = "      },"
          end
        end
        lines[#lines + 1] = "    },"
      end
    end
    lines[#lines + 1] = "  },"
  end
  lines[#lines + 1] = "}"
  return safeCacheWrite(cacheKey("data/hd_pokemon.lua"), table.concat(lines, "\n") .. "\n")
end

local function finishExtraction()
  if manager.wroteGifs then
    local okMeta, err = writeMetadata()
    if not okMeta then return setError("could not write metadata: " .. tostring(err)) end
  end
  safeCacheWrite(Install.COMPLETE_KEY, "zip:" .. tostring(Install.status.current or 0))
  cleanupArchive()
  local HdPokemon = V.HdPokemon
  if HdPokemon and type(HdPokemon.reload) == "function" then pcall(HdPokemon.reload) end
  Install.status.state = "done"
  Install.status.count = Install.count()
  Install.status.message = "READY"
  Install.status.error = nil
end

local function installGif(bytes, item)
  local HdGif = V.require("HdGif")
  local decoded, err = HdGif.decode(bytes)
  if not decoded then return nil, err end
  local packed, packErr = HdGif.packSheet(decoded, 0.60)
  if not packed then return nil, packErr end
  local suffix = ""
  if item.gender == "male" then suffix = "-m"
  elseif item.gender == "female" then suffix = "-f" end
  local rel = string.format("assets/battle/hd-pokemon/%s/%s/%03d%s.png",
    item.side, item.color, item.dex, suffix)
  packed.image = rel
  packed.displayScale = item.side == "back" and 0.315 or 0.33
  local ok, writeErr = safeCacheWrite(cacheKey(rel), packed.bytes)
  if not ok then return nil, writeErr end
  local records = manager.records
  records[item.dex] = records[item.dex] or {}
  records[item.dex][item.side] = records[item.dex][item.side] or {}
  records[item.dex][item.side][item.color] = records[item.dex][item.side][item.color] or {}
  records[item.dex][item.side][item.color][item.gender] = packed
  manager.wroteGifs = true
  return rel
end

local function beginExtraction(zipName, official)
  local reader, openErr = openZipReader(zipName)
  if not reader then return setError(openErr) end
  local entries, scanErr = scanZipDirectory(reader)
  if not entries then return setError(scanErr) end
  if #entries == 0 then return setError("zip has no HD pokemon files") end
  manager.extractFiles = entries
  manager.extractPos = 1
  manager.records = {}
  manager.wroteGifs = false
  Install.status.current = 0
  Install.status.total = #entries
  Install.status.message = "EXTRACTING"
  setStatus("extracting")
end

local function pumpExtraction()
  if Install.status.state ~= "extracting" then return end
  local reader = manager.zipReader
  if not reader then return setError("zip closed") end
  local started = love.timer and love.timer.getTime and love.timer.getTime() or nil
  local processed = 0
  while manager.extractPos <= #manager.extractFiles do
    local item = manager.extractFiles[manager.extractPos]
    local bytes, readErr = readZipEntry(reader, item)
    if type(bytes) ~= "string" then
      return setError("extract failed: " .. tostring(readErr))
    end
    local ok, err
    if item.kind == "gif" then
      if item.dex and item.dex >= 1 and item.dex <= Install.DEX_MAX then
        ok, err = installGif(bytes, item)
      else
        ok = true
      end
    elseif item.kind == "lua" then
      ok, err = safeCacheWrite(cacheKey("data/hd_pokemon.lua"), bytes)
    else
      ok, err = safeCacheWrite(cacheKey(item.relative), bytes)
    end
    if not ok then return setError(tostring(err or "install failed")) end
    manager.extractPos = manager.extractPos + 1
    Install.status.current = manager.extractPos - 1
    Install.status.message = (item.relative or ""):match("([^/]+)$") or "FILE"
    processed = processed + 1
    if started and love.timer and love.timer.getTime then
      if love.timer.getTime() - started >= Install.EXTRACT_BUDGET then break end
    elseif processed >= 1 then
      break
    end
  end
  if manager.extractPos > #manager.extractFiles then finishExtraction() end
end

local function beginDownloadForRelease(release)
  if type(release) ~= "table" or not release.zip or not release.zip.url then
    return setError("github release has no zip")
  end
  local okFetch, Fetch = pcall(require, "src.net.Fetch")
  if not okFetch or not Fetch or type(Fetch.download) ~= "function" then
    return setError("engine downloader unavailable")
  end
  manager.rawFs = manager.rawFs or select(1, resolveRawFilesystem())
  if manager.rawFs and type(manager.rawFs.remove) == "function" then
    pcall(manager.rawFs.remove, Install.TEMP)
  end
  Install.status.downloadTotal = tonumber(release.zip.size) or 0
  Install.status.downloadBytes = 0
  manager.downloadHandle = Fetch.download(release.zip.url, Install.TEMP, {
    size = Install.status.downloadTotal > 0 and Install.status.downloadTotal or nil,
    userAgent = "terrarium-hd-pokemon",
    maxSeconds = Install.DOWNLOAD_MAX_SECONDS,
  })
  if not manager.downloadHandle then return setError("could not start download") end
  setStatus("downloading", "DOWNLOADING")
end

local function pumpReleaseCheck()
  if Install.status.state ~= "checking" then return end
  local okModUpdate, ModUpdate = pcall(require, "src.mods.ModUpdate")
  if not okModUpdate or not ModUpdate then return setError("release checker unavailable") end
  local done, releases, err = ModUpdate.pumpFetchReleases(manager.releaseHandle)
  if not done then return end
  manager.releaseHandle = nil
  if not releases then return setError(err or "could not check release") end
  local wanted
  for _, rel in ipairs(releases) do
    if tostring(rel.version or "") == Install.ASSET_VERSION and rel.zip and rel.zip.url then
      wanted = rel
      break
    end
  end
  if not wanted and releases[1] and releases[1].zip then wanted = releases[1] end
  if not wanted then return setError("asset release not found") end
  beginDownloadForRelease(wanted)
end

local function pumpDownload()
  if Install.status.state ~= "downloading" then return end
  local okFetch, Fetch = pcall(require, "src.net.Fetch")
  if not okFetch or not Fetch then return setError("downloader unavailable") end
  local fs = manager.rawFs
  if fs then
    local okInfo, info = pcall(fs.getInfo, Install.TEMP, "file")
    if okInfo and info then
      Install.status.downloadBytes = tonumber(info.size) or Install.status.downloadBytes
    end
  end
  local st = Fetch.poll(manager.downloadHandle)
  if st.status == "pending" then
    if Install.status.downloadTotal > 0 and tonumber(st.progress) then
      Install.status.downloadBytes = math.max(
        Install.status.downloadBytes or 0,
        Install.status.downloadTotal * tonumber(st.progress))
    end
    return
  end
  local job = manager.downloadHandle
  manager.downloadHandle = nil
  Fetch.release(job)
  if st.status ~= "ok" then return setError(st.err or "download failed") end
  beginExtraction(Install.TEMP, true)
end

function Install.startDownload()
  Install.status.error = nil
  local fs, fsErr = resolveRawFilesystem()
  if not fs then return setError(fsErr) end
  manager.rawFs = fs
  local okModUpdate, ModUpdate = pcall(require, "src.mods.ModUpdate")
  if not okModUpdate or not ModUpdate or type(ModUpdate.beginFetchReleases) ~= "function" then
    return setError("engine release downloader unavailable")
  end
  cleanupArchive()
  manager.releaseHandle = ModUpdate.beginFetchReleases(Install.REPO, nil, { force = true })
  setStatus("checking", "CHECKING")
  return true
end

function Install.startLocalZip(game)
  Install.status.error = nil
  local fs, fsErr = resolveRawFilesystem()
  if not fs then return setError(fsErr) end
  manager.rawFs = fs
  if Install.canDialog() then
    local path = Compat.chooseFile("Choose HD Pokemon zip", { "zip" }, "HD Pokemon ZIP")
    if not path then return false end
    local ok, err = Compat.stageExternal(path, Install.PICKED)
    if not ok then return setError(err or "could not copy zip") end
  else
    local okInfo, info = pcall(fs.getInfo, Install.PICKED, "file")
    if not (okInfo and info) then
      return setError("put the zip in the save folder as " .. Install.PICKED)
    end
  end
  beginExtraction(Install.PICKED, false)
  return true
end

function Install.cancel()
  cancelNetworkJob()
  manager.releaseHandle = nil
  cleanupArchive()
  Install.status.state = "idle"
  Install.status.error = nil
  Install.status.message = ""
end

function Install.update()
  local st = Install.status.state
  if st == "checking" then pumpReleaseCheck()
  elseif st == "downloading" then pumpDownload()
  elseif st == "extracting" then pumpExtraction()
  end
end

function Install.poll()
  Install.update()
end

return Install
