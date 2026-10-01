-- HD Pokémon Asset Manager for THIS engine (gen2rec), not KIM/Gen1 Fetch.
-- Zip open uses save-dir io / love.filesystem.newFile (portable fs has no
-- newFile). Writes go to the save folder so the 64 MiB native cache cap
-- cannot fail the install. Download uses HostShell (curl / Android
-- love.system.httpDownload). START opens the native picker on Android.
local V = ...
local Compat = V.require("EngineCompat")

local Install = {}
Install.ID = "DRAMATIC_SHAPE:hdPokemon"
Install.LABEL = "HD POKEMON"
Install.PICKED = "picked_hd_pokemon.zip"
Install.PICKED_MOD = "picked_mod.zip"
Install.PICKED_ROM = "picked_rom.gb"
Install.PENDING = "hd_pokemon_picker_pending.flag"
Install.TEMP = "hd_pokemon_dl.tmp.zip"
Install.CACHE_ROOT = "hd_pokemon/"
Install.COMPLETE_KEY = "hd_pokemon/complete.txt"
Install.DEX_MAX = 493
Install.REPO = "HaseoSora/Kanto-in-Motion-Assets"
Install.ASSET_VERSION = "1.0.0"
-- Set this to a direct MediaFire (or other) ZIP URL when you have one.
-- Empty = GitHub KIM PNG pack (dex 1-386) via this engine's ModUpdate.
Install.DOWNLOAD_URL = "https://download2390.mediafire.com/qc1joxxc80sgmHUNIG_vF1bQruBWeglUW62vf2X3G4J8i4Lh6Cic9hrSoV1kG8oI33KOY4_zQAf4lLaOqEF4gbQm0JefKxDOOSoZ6HbKLmzIBe0kNVkXjYDE0MUN_xlrzUUT15DmtZ0dnlhcWe0vQha9VTibvg22hllOo0R5GoDexEs/bnbt7vid0etbya1/HDReloded.zip"
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

local function saveFs()
  if Compat and type(Compat.fs) == "function" then
    local ok, f = pcall(Compat.fs)
    if ok and type(f) == "table" then return f end
  end
  return nil
end

local function saveRoot()
  local okSave, SaveData = pcall(require, "src.core.SaveData")
  if okSave and SaveData and type(SaveData.portableBaseDir) == "function" then
    local okBase, base = pcall(SaveData.portableBaseDir)
    if okBase and type(base) == "string" and base ~= "" then return base end
  end
  local ok, dir = pcall(function()
    return love and love.filesystem and love.filesystem.getSaveDirectory
      and love.filesystem.getSaveDirectory()
  end)
  if ok and type(dir) == "string" and dir ~= "" then return dir end
  return nil
end

local function hostJoin(dir, name)
  local sep = package.config:sub(1, 1)
  return tostring(dir):gsub("[/\\]+$", "") .. sep .. tostring(name):gsub("/", sep)
end

local function ensureParent(fs, path)
  if not (fs and type(fs.createDirectory) == "function") then return true end
  local parent = tostring(path or ""):match("^(.*)/[^/]+$")
  if not parent or parent == "" then return true end
  local cur = ""
  for part in parent:gmatch("[^/]+") do
    cur = (cur == "" and part) or (cur .. "/" .. part)
    local ok, err = pcall(fs.createDirectory, cur)
    if ok == false then return false, err end
  end
  return true
end

local function fileExists(fs, name)
  if not (fs and type(fs.getInfo) == "function") then return false end
  local ok, info = pcall(fs.getInfo, name)
  if ok and info then return true end
  ok, info = pcall(fs.getInfo, name, "file")
  return ok and info and true or false
end

local function fsRead(fs, name)
  if not (fs and type(fs.read) == "function") then return nil end
  local ok, bytes = pcall(fs.read, name)
  if ok and type(bytes) == "string" then return bytes end
  return nil
end

local function fsRemove(fs, name)
  if fs and type(fs.remove) == "function" then pcall(fs.remove, name) end
end

local function fsWrite(fs, name, bytes)
  if not (fs and type(fs.write) == "function") then return false, "save filesystem unavailable" end
  ensureParent(fs, name)
  local ok, wrote, err = pcall(fs.write, name, bytes)
  if not ok then return false, tostring(wrote) end
  if wrote == false then return false, tostring(err or "write failed") end
  return true
end

local function safeCacheRead(key)
  local fs = saveFs()
  local bytes = fsRead(fs, key)
  if type(bytes) == "string" then return bytes end
  if not cacheAvailable() then return nil end
  local ok, got = pcall(function() return modHandle().cache:read(key) end)
  if ok and type(got) == "string" then return got end
  return nil
end

local function safeCacheWrite(key, bytes)
  if type(bytes) ~= "string" then return false, "install data is not bytes" end
  local fs = saveFs()
  local ok, err = fsWrite(fs, key, bytes)
  if not ok then return false, err end
  if cacheAvailable() and #bytes <= Install.MAX_CACHE_FILE then
    pcall(function() return modHandle().cache:write(key, bytes) end)
  end
  return true
end

local function resolveRawFilesystem()
  local fs = saveFs()
  if not fs then return nil, "save filesystem unavailable" end
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
      if st == "picking" then return "PICK" end
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
  local fs = manager.rawFs or saveFs()
  if fs and manager.tempName == Install.TEMP then
    fsRemove(fs, manager.tempName)
  end
end

local function cleanupArchive()
  closeZipReader()
  removeTemp()
end

local function cancelNetworkJob()
  manager.downloadHandle = nil
  manager.blockingDownload = nil
  if manager.downloadChannel and type(manager.downloadChannel.clear) == "function" then
    pcall(function() manager.downloadChannel:clear() end)
  end
  manager.downloadChannel = nil
  manager.downloadThread = nil
end

local function setError(message)
  cleanupArchive()
  cancelNetworkJob()
  manager.releaseHandle = nil
  local fs = saveFs()
  fsRemove(fs, Install.PENDING)
  Install.status.state = "error"
  Install.status.error = tostring(message or "unknown error")
  Install.status.message = "ERROR"
end

local function wrapSeekable(file, size, seekFn)
  local r = { file = file, size = tonumber(size) }
  function r:readAt(offset, count)
    if offset < 0 or count < 0 or offset + count > self.size then
      return nil, "zip read out of range"
    end
    local okSeek, seeked = pcall(seekFn, self.file, offset)
    if not okSeek or seeked == false then return nil, "zip seek failed" end
    local okRead, data = pcall(function() return self.file:read(count) end)
    if not okRead or type(data) ~= "string" or #data ~= count then
      return nil, "zip read failed"
    end
    return data
  end
  return r
end

local function openLoveFile(name)
  local okNew, file = pcall(function()
    return love.filesystem.newFile(name)
  end)
  if not (okNew and file) then return nil, tostring(file or "newFile unavailable") end
  local okOpen, opened, openErr = pcall(function() return file:open("r") end)
  if not okOpen or opened == false then
    pcall(function() file:close() end)
    return nil, tostring(openErr or "could not open zip")
  end
  local okSize, size = pcall(function() return file:getSize() end)
  if not okSize or not tonumber(size) or tonumber(size) < 22 then
    pcall(function() file:close() end)
    return nil, "file is too small to be a zip"
  end
  return wrapSeekable(file, size, function(f, offset) return f:seek(offset) end)
end

local function openHostFile(name)
  local root = saveRoot()
  if not (root and io and io.open) then return nil, "host zip open unavailable" end
  local abs = hostJoin(root, name)
  local ok, file = pcall(io.open, abs, "rb")
  if not (ok and file) then return nil, "could not open zip" end
  local okEnd, size = pcall(function() return file:seek("end") end)
  if not okEnd or not tonumber(size) or tonumber(size) < 22 then
    pcall(function() file:close() end)
    return nil, "file is too small to be a zip"
  end
  pcall(function() file:seek("set", 0) end)
  return wrapSeekable(file, size, function(f, offset) return f:seek("set", offset) end)
end

local function openZipReader(name)
  closeZipReader()
  manager.rawFs = manager.rawFs or saveFs()
  local reader, err
  reader, err = openHostFile(name)
  if not reader then
    reader, err = openLoveFile(name)
  end
  if not reader and manager.rawFs and type(manager.rawFs.newFile) == "function" then
    local okNew, file = pcall(manager.rawFs.newFile, name)
    if okNew and file then
      local okOpen, opened, openErr = pcall(function() return file:open("r") end)
      if okOpen and opened ~= false then
        local okSize, size = pcall(function() return file:getSize() end)
        if okSize and tonumber(size) and tonumber(size) >= 22 then
          reader = wrapSeekable(file, size, function(f, offset) return f:seek(offset) end)
        else
          pcall(function() file:close() end)
          err = "file is too small to be a zip"
        end
      else
        pcall(function() file:close() end)
        err = tostring(openErr or "could not open zip")
      end
    end
  end
  if not reader then return nil, err or "could not open zip" end
  manager.zipReader = reader
  manager.tempName = name
  return reader
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
  
  -- Use a standard Lua pattern: captures dex, side, color, and any trailing text
  local dex, side, color, extra = base:match("^(%d+)%-(%a+)%-([ns])(.-)%.gif$")
  
  if dex and (side == "front" or side == "back") then
    local gender = "default"
    if extra == "-m" then
      gender = "male"
    elseif extra == "-f" then
      gender = "female"
    elseif extra ~= "" then
      return nil -- Invalid format if it has unrecognized trailing text
    end

    return {
      kind = "gif",
      relative = name,
      dex = tonumber(dex),
      side = side,
      color = color == "s" and "shiny" or "normal",
      gender = gender,
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

local function refreshDownloadBytes()
  local fs = manager.rawFs or saveFs()
  if not fs then return end
  local okInfo, info = pcall(fs.getInfo, Install.TEMP)
  if okInfo and info then
    Install.status.downloadBytes = tonumber(info.size) or Install.status.downloadBytes
  end
end

local function beginHostDownload(url, expectBytes)
  local fs = manager.rawFs or saveFs()
  fsRemove(fs, Install.TEMP)
  local root = saveRoot()
  if not root then return setError("save directory unavailable") end
  local abs = hostJoin(root, Install.TEMP)
  Install.status.downloadTotal = tonumber(expectBytes) or 0
  Install.status.downloadBytes = 0
  manager.downloadRel = Install.TEMP
  setStatus("downloading", "DOWNLOADING")

  local osName = Compat.osName and Compat.osName() or ""
  local desktop = osName == "Windows" or osName == "OS X" or osName == "Linux"
  if desktop and love and love.thread and type(love.thread.newThread) == "function" then
    local code = [[
      local url, abs = ...
      local okReq, HostShell = pcall(require, "src.core.HostShell")
      local ok, err
      if okReq and HostShell and type(HostShell.httpDownload) == "function" then
        ok, err = HostShell.httpDownload(url, abs, "terrarium-hd-pokemon")
      else
        ok, err = false, "HostShell unavailable"
      end
      love.thread.getChannel("terrarium_hd_pokemon_dl"):push({
        ok = ok and true or false,
        err = err,
      })
    ]]
    manager.downloadChannel = love.thread.getChannel("terrarium_hd_pokemon_dl")
    pcall(function() manager.downloadChannel:clear() end)
    manager.downloadThread = love.thread.newThread(code)
    manager.downloadThread:start(url, abs)
    return true
  end

  manager.blockingDownload = { url = url, abs = abs }
  return true
end

local function resolveDownloadUrl()
  local direct = tostring(Install.DOWNLOAD_URL or "")
  if direct ~= "" then return direct, nil end
  local okModUpdate, ModUpdate = pcall(require, "src.mods.ModUpdate")
  if not okModUpdate or not ModUpdate or type(ModUpdate.fetchReleases) ~= "function" then
    return nil, "engine release list unavailable"
  end
  local releases, err = ModUpdate.fetchReleases(Install.REPO, nil, { force = true })
  if not releases then return nil, err or "could not check release" end
  local wanted
  for _, rel in ipairs(releases) do
    if tostring(rel.version or "") == Install.ASSET_VERSION and rel.zip and rel.zip.url then
      wanted = rel
      break
    end
  end
  if not wanted and releases[1] and releases[1].zip then wanted = releases[1] end
  if not (wanted and wanted.zip and wanted.zip.url) then
    return nil, "asset release not found"
  end
  return wanted.zip.url, tonumber(wanted.zip.size)
end

local function pumpDownload()
  if Install.status.state ~= "downloading" then return end
  refreshDownloadBytes()
  if manager.blockingDownload then
    local job = manager.blockingDownload
    manager.blockingDownload = nil
    local okReq, HostShell = pcall(require, "src.core.HostShell")
    if not okReq or not HostShell or type(HostShell.httpDownload) ~= "function" then
      return setError("engine downloader unavailable")
    end
    local ok, err = HostShell.httpDownload(job.url, job.abs, "terrarium-hd-pokemon")
    if not ok then return setError(err or "download failed") end
    beginExtraction(Install.TEMP, true)
    return
  end
  if manager.downloadChannel then
    local msg = manager.downloadChannel:pop()
    if not msg then return end
    manager.downloadChannel = nil
    manager.downloadThread = nil
    if type(msg) ~= "table" or not msg.ok then
      return setError((msg and msg.err) or "download failed")
    end
    beginExtraction(Install.TEMP, true)
  end
end

local function consumePickedZip()
  local fs = manager.rawFs or saveFs()
  if not fs then return false end
  if not fileExists(fs, Install.PENDING) then
    manager.pickIdleFrames = 0
    return false
  end
  local name
  if fileExists(fs, Install.PICKED) then
    name = Install.PICKED
  elseif fileExists(fs, Install.PICKED_MOD) then
    name = Install.PICKED_MOD
  elseif fileExists(fs, Install.PICKED_ROM) then
    name = Install.PICKED_ROM
  end
  if not name then
    manager.pickIdleFrames = (manager.pickIdleFrames or 0) + 1
    if manager.pickIdleFrames > 180 then
      fsRemove(fs, Install.PENDING)
      manager.pickIdleFrames = 0
      if Install.status.state == "picking" then
        Install.status.state = "idle"
        Install.status.message = ""
      end
    end
    return false
  end
  fsRemove(fs, Install.PENDING)
  manager.pickIdleFrames = 0
  beginExtraction(name, false)
  return true
end

function Install.startDownload()
  Install.status.error = nil
  local fs, fsErr = resolveRawFilesystem()
  if not fs then return setError(fsErr) end
  manager.rawFs = fs
  local okShell, HostShell = pcall(require, "src.core.HostShell")
  if not okShell or not HostShell or type(HostShell.canFetch) ~= "function" or not HostShell.canFetch() then
    return setError("no network; press START and pick the zip")
  end
  cleanupArchive()
  setStatus("checking", "CHECKING")
  local url, sizeOrErr = resolveDownloadUrl()
  if not url then return setError(sizeOrErr) end
  return beginHostDownload(url, type(sizeOrErr) == "number" and sizeOrErr or nil)
end

function Install.startLocalZip()
  Install.status.error = nil
  local fs, fsErr = resolveRawFilesystem()
  if not fs then return setError(fsErr) end
  manager.rawFs = fs
  local osName = Compat.osName and Compat.osName() or ""
  if osName == "Android" or osName == "iOS" then
    fsRemove(fs, Install.PENDING)
    local okMark, markErr = fsWrite(fs, Install.PENDING, "hd-pokemon\n")
    if not okMark then return setError(markErr or "could not create picker marker") end
    local opener = Compat.openMobileZipPicker or Compat.openMobileFilePicker
    local ok, launched, why = pcall(opener)
    if not ok or not launched then
      fsRemove(fs, Install.PENDING)
      return setError(ok and tostring(why or launched) or tostring(launched))
    end
    manager.pickIdleFrames = 0
    setStatus("picking", "PICK ZIP")
    return true
  end
  if Install.canDialog() then
    local path = Compat.chooseFile("Choose HD Pokemon zip", { "zip" }, "HD Pokemon ZIP")
    if not path then return false end
    local ok, err = Compat.stageExternal(path, Install.PICKED)
    if not ok then return setError(err or "could not copy zip") end
    beginExtraction(Install.PICKED, false)
    return true
  end
  if fileExists(fs, Install.PICKED) then
    beginExtraction(Install.PICKED, false)
    return true
  end
  if fileExists(fs, Install.PICKED_MOD) then
    beginExtraction(Install.PICKED_MOD, false)
    return true
  end
  return setError("put the zip in the save folder as " .. Install.PICKED)
end

function Install.cancel()
  cancelNetworkJob()
  manager.releaseHandle = nil
  cleanupArchive()
  fsRemove(saveFs(), Install.PENDING)
  Install.status.state = "idle"
  Install.status.error = nil
  Install.status.message = ""
end

function Install.update()
  local st = Install.status.state
  if st == "picking" then consumePickedZip()
  elseif st == "downloading" then pumpDownload()
  elseif st == "extracting" then pumpExtraction()
  end
end

function Install.poll()
  Install.update()
end

return Install
