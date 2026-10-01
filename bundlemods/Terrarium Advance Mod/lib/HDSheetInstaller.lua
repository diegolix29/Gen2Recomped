-- One-shot installer for the HD sheet pack(s) used by lib/HDPokemonSheets.lua.
-- (Patched to use gen2rec HostShell/EngineCompat instead of Gen1 Fetch)
--
-- Downloads each configured release ZIP with the engine's HostShell,
-- reads the ZIP directly (no unzip dependency) and copies ONLY the sheet PNGs
-- for National Dex 1..493 into mod.cache under hd_sheets/<facing>/<color>/.
-- That is exactly where HDPokemonSheets looks first, so nothing else needs to
-- be told: it re-scans when the install finishes.

local V = ...
local mod = V and V.mod

local I = { VERSION = 1, ID = "hd_sheets_install", LABEL = "HD SHEETS" }

I.config = {
  -- Processed in order. Add a second entry to pull a Gen 4 (387-493) pack from
  -- another release: same layout, assets/battle/hd-pokemon/<facing>/<color>/NNN.png
  sources = {
    {
      name = "HD Reloded assets",
      url = "https://github.com/MMNNGG765/Terri-Assets/releases/download/1.0.0/HDReloded.zip",
      packId = nil, 
      prefix = "assets/battle/hd-pokemon/",
      userAgent = "terrarium-hd-sheets",
    },
  },
  tempName = "terrarium_hd_sheets.tmp.zip",
  extractBudget = 0.010,       -- seconds of unpacking per frame
  maxSeconds = 15 * 60,        -- max download time
  maxFile = 64 * 1024 * 1024,
}

local st = {
  state = "idle",   -- idle | checking | downloading | extracting | done | error
  error = nil,
  srcIndex = 0,
  total = 0, bytes = 0,            -- download
  files = {}, pos = 1,             -- extraction queue
  counts = nil,
  coverage = nil,
}

local function HD()
  local ok, m = pcall(V.require, "HDPokemonSheets")
  return ok and m or nil
end

local function maxDex()
  local hd = HD()
  return hd and hd.MAX_DEX or 493
end

local function lowMax()
  local hd = HD()
  return hd and hd.COLOSSEUM_MAX or 386
end

local function cacheDir()
  local hd = HD()
  return hd and hd.config and hd.config.cacheDir or "hd_sheets"
end

local function log(level, fmt, ...)
  local l = mod and mod.log
  if l and type(l[level]) == "function" then pcall(l[level], l, fmt, ...) end
end

local function cacheOk()
  local c = mod and mod.cache
  return c and type(c.read) == "function" and type(c.write) == "function" and type(c.info) == "function"
end

local function cacheInfo(key)
  local ok, info = pcall(function() return mod.cache:info(key) end)
  return ok and info or nil
end

local function cacheWrite(key, bytes)
  local ok, wrote, err = pcall(function() return mod.cache:write(key, bytes) end)
  if not ok then return false, tostring(wrote) end
  if wrote == false then return false, tostring(err or "cache write failed") end
  return true
end

-- ------- ZIP & FILESYSTEM --------------------------------------------------

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

local function rawFilesystem()
  local Compat = (V and type(V.require) == "function") and pcall(V.require, "EngineCompat") and V.require("EngineCompat") or nil
  if Compat and type(Compat.fs) == "function" then
    local ok, f = pcall(Compat.fs)
    if ok and type(f) == "table" then return f end
  end
  return love.filesystem
end

local function closeReader()
  local r = st.reader
  if r and r.file and type(r.file.close) == "function" then pcall(function() r.file:close() end) end
  st.reader = nil
end

local function removeTemp()
  local fs = st.fs
  if fs and type(fs.remove) == "function" then 
     pcall(fs.remove, I.config.tempName) 
  else
     pcall(love.filesystem.remove, I.config.tempName)
  end
end

local function cleanup()
  closeReader()
  removeTemp()
end

local function cancelNetwork()
  st.blockingDownload = nil
  if st.downloadChannel and type(st.downloadChannel.clear) == "function" then
    pcall(function() st.downloadChannel:clear() end)
  end
  st.downloadChannel = nil
  st.downloadThread = nil
end

local function fail(message)
  cleanup()
  cancelNetwork()
  st.state = "error"
  st.error = tostring(message or "unknown installer error")
  log("error", "HD sheet installer: %s", st.error)
end

local function openReader()
  closeReader()
  local file
  if st.fs and type(st.fs.newFile) == "function" then
    local okNew, f = pcall(st.fs.newFile, I.config.tempName)
    if okNew and f then file = f end
  end
  if not file then
    local okNew, f = pcall(love.filesystem.newFile, I.config.tempName)
    if okNew and f then file = f end
  end

  if not file then return nil, "could not open the downloaded ZIP" end
  
  local okOpen, opened, openErr = pcall(function() return file:open("r") end)
  if not okOpen or opened == false then
    pcall(function() file:close() end)
    return nil, tostring(openErr or opened or "could not open the downloaded ZIP")
  end
  
  local okSize, size = pcall(function() return file:getSize() end)
  if not okSize or not tonumber(size) or tonumber(size) < 22 then
    pcall(function() file:close() end)
    return nil, "downloaded file is too small to be a ZIP"
  end
  
  local r = { file = file, size = tonumber(size) }
  function r:readAt(offset, count)
    if offset < 0 or count < 0 or offset + count > self.size then return nil, "read outside the archive" end
    local okSeek, seeked = pcall(function() return self.file:seek(offset) end)
    if not okSeek or seeked == false then return nil, "ZIP seek failed" end
    local okRead, data, readErr = pcall(function() return self.file:read(count) end)
    if not okRead or type(data) ~= "string" then return nil, tostring(readErr or data or "ZIP read failed") end
    if #data ~= count then return nil, "ZIP read was truncated" end
    return data
  end
  
  st.reader = r
  return r
end

local function scanDirectory(reader)
  local tailSize = math.min(reader.size, 22 + 65535 + 256)
  local tail, tailErr = reader:readAt(reader.size - tailSize, tailSize)
  if not tail then return nil, tailErr end
  local eocd
  for i = #tail - 21, 1, -1 do
    if tail:sub(i, i + 3) == "PK\005\006" then eocd = i; break end
  end
  if not eocd then return nil, "ZIP end record not found" end
  local entries, cdSize, cdOffset = le16(tail, eocd + 10), le32(tail, eocd + 12), le32(tail, eocd + 16)
  if not (entries and cdSize and cdOffset) then return nil, "ZIP end record is truncated" end
  if entries == 0xFFFF or cdSize == 0xFFFFFFFF or cdOffset == 0xFFFFFFFF then
    return nil, "ZIP64 packs are not supported"
  end
  if cdOffset + cdSize > reader.size then return nil, "ZIP directory is outside the archive" end
  local cd, cdErr = reader:readAt(cdOffset, cdSize)
  if not cd then return nil, cdErr end
  local out, pos = {}, 1
  for _ = 1, entries do
    if cd:sub(pos, pos + 3) ~= "PK\001\002" then return nil, "ZIP directory entry is invalid" end
    local flags = le16(cd, pos + 8) or 0
    local method = le16(cd, pos + 10)
    local compSize, size = le32(cd, pos + 20), le32(cd, pos + 24)
    local nameLen, extraLen, commentLen = le16(cd, pos + 28), le16(cd, pos + 30), le16(cd, pos + 32)
    local localOffset = le32(cd, pos + 42)
    if not (method and compSize and size and nameLen and extraLen and commentLen and localOffset) then
      return nil, "ZIP directory is truncated"
    end
    local nameStart = pos + 46
    local name = cd:sub(nameStart, nameStart + nameLen - 1):gsub("\\", "/")
    if flags % 2 == 1 then return nil, "encrypted ZIP entries are not supported" end
    if name:sub(-1) ~= "/" then
      out[#out + 1] = { name = name, method = method, compressedSize = compSize, size = size, localOffset = localOffset }
    end
    pos = nameStart + nameLen + extraLen + commentLen
  end
  return out
end

local function readEntry(reader, item)
  local hdr, hdrErr = reader:readAt(item.localOffset, 30)
  if not hdr then return nil, hdrErr end
  if hdr:sub(1, 4) ~= "PK\003\004" then return nil, "ZIP local header is invalid" end
  local method, nameLen, extraLen = le16(hdr, 9), le16(hdr, 27), le16(hdr, 29)
  if not (method and nameLen and extraLen) then return nil, "ZIP local header is truncated" end
  if method ~= item.method then return nil, "ZIP compression metadata mismatch" end
  local packed, packedErr = reader:readAt(item.localOffset + 30 + nameLen + extraLen, item.compressedSize)
  if not packed then return nil, packedErr end
  local bytes = packed
  if item.method == 8 then
    if not (love and love.data and type(love.data.decompress) == "function") then
      return nil, "raw DEFLATE support is unavailable"
    end
    local ok, inflated = pcall(love.data.decompress, "string", "deflate", packed)
    if not ok or type(inflated) ~= "string" then return nil, "DEFLATE decompression failed" end
    bytes = inflated
  elseif item.method ~= 0 then
    return nil, "unsupported ZIP compression method " .. tostring(item.method)
  end
  if #bytes ~= item.size then return nil, ("ZIP entry size mismatch (%d/%d)"):format(#bytes, item.size) end
  return bytes
end

-- ------- which entries are sheets ------------------------------------------

local function sheetOf(name, prefix)
  if name:sub(1, #prefix) ~= prefix then return nil end
  local facing, color, num, rest = name:sub(#prefix + 1):match("^(%a+)/(%a+)/(%d%d%d)([%w%-]*)%.png$")
  if not facing or (facing ~= "front" and facing ~= "back") or (color ~= "normal" and color ~= "shiny") then
    return nil
  end
  return ("%s/%s/%s%s.png"):format(facing, color, num, rest), tonumber(num)
end
I._sheetOf = sheetOf

-- ------- state machine -----------------------------------------------------

local function source() return I.config.sources[st.srcIndex] end

local function finishAll()
  cleanup()
  st.state = "done"
  st.error = nil
  st.coverage = nil
  local hd = HD()
  if hd and hd.rescan then pcall(hd.rescan) end
  local c = I.coverage()
  log("info", "HD sheets installed: dex 1-%d %d/%d, dex %d-%d %d/%d (needs front+back)",
    lowMax(), c.low, lowMax(), lowMax() + 1, maxDex(), c.high, maxDex() - lowMax())
end

local function finishSource()
  closeReader()
  removeTemp()
  if st.srcIndex < #I.config.sources then
    I._startSource(st.srcIndex + 1)
  else
    finishAll()
  end
end

local function beginExtraction()
  local reader, openErr = openReader()
  if not reader then return fail("downloaded ZIP could not be read: " .. tostring(openErr)) end
  local entries, scanErr = scanDirectory(reader)
  if not entries then return fail("downloaded ZIP is invalid: " .. tostring(scanErr)) end
  local src = source()
  local cap = maxDex()
  local queue, c = {}, st.counts
  for _, e in ipairs(entries) do
    local rel, dex = sheetOf(e.name, src.prefix)
    if rel then
      if dex < 1 or dex > cap then
        c.over = c.over + 1
      elseif e.size > I.config.maxFile then
        return fail("sheet exceeds the 64 MB cache limit: " .. e.name)
      else
        queue[#queue + 1] = { rel = rel, dex = dex, item = e }
      end
    else
      c.other = c.other + 1
    end
  end
  if #queue == 0 then return fail("the pack contains no HD sheets for dex 1-" .. cap) end
  table.sort(queue, function(a, b) return a.rel < b.rel end)
  st.files, st.pos = queue, 1
  st.state = "extracting"
  log("info", "HD sheet pack '%s': %d sheets for dex 1-%d (%d above the cap ignored)",
    tostring(src.name), #queue, cap, c.over)
end

local function pumpExtraction()
  local reader = st.reader
  if not reader then return fail("temporary ZIP closed during extraction") end
  local timer = love and love.timer and love.timer.getTime
  local started = timer and timer() or nil
  local processed = 0
  local dir, c = cacheDir(), st.counts
  while st.pos <= #st.files do
    local f = st.files[st.pos]
    local key = dir .. "/" .. f.rel
    local info = cacheInfo(key)
    if info and (tonumber(info.size) or -1) == f.item.size then
      c.existing = c.existing + 1
    else
      local bytes, readErr = readEntry(reader, f.item)
      if type(bytes) ~= "string" then
        return fail("could not extract " .. f.rel .. ": " .. tostring(readErr or "read failed"))
      end
      local ok, writeErr = cacheWrite(key, bytes)
      if not ok then return fail("could not install " .. f.rel .. ": " .. tostring(writeErr)) end
      c.written = c.written + 1
    end
    if f.dex <= lowMax() then c.low = c.low + 1 else c.high = c.high + 1 end
    st.pos = st.pos + 1
    processed = processed + 1
    if timer then
      if timer() - started >= I.config.extractBudget then break end
    elseif processed >= 2 then
      break
    end
  end
  if st.pos > #st.files then finishSource() end
end

local function beginDownload()
  local src = source()
  if not src.url then return fail("source has no download URL") end

  removeTemp()
  st.total = 0 
  st.bytes = 0

  local Compat = (V and type(V.require) == "function") and pcall(V.require, "EngineCompat") and V.require("EngineCompat") or nil
  local osName = Compat and Compat.osName and Compat.osName() or ""

  local root = nil
  local okSave, SaveData = pcall(require, "src.core.SaveData")
  if okSave and SaveData and type(SaveData.portableBaseDir) == "function" then
    local okBase, base = pcall(SaveData.portableBaseDir)
    if okBase and type(base) == "string" and base ~= "" then root = base end
  end
  if not root then
    local ok, dir = pcall(function() return love.filesystem.getSaveDirectory() end)
    if ok and type(dir) == "string" and dir ~= "" then root = dir end
  end
  if not root then return fail("save directory unavailable") end

  local sep = package.config:sub(1, 1)
  local abs = tostring(root):gsub("[/\\]+$", "") .. sep .. I.config.tempName

  local desktop = (osName == "Windows" or osName == "OS X" or osName == "Linux")
  if desktop and love and love.thread and type(love.thread.newThread) == "function" then
    local code = [[
      local url, abs = ...
      local okReq, HostShell = pcall(require, "src.core.HostShell")
      local ok, err
      if okReq and HostShell and type(HostShell.httpDownload) == "function" then
        ok, err = HostShell.httpDownload(url, abs, "terrarium-hd-sheets")
      else
        ok, err = false, "HostShell unavailable"
      end
      love.thread.getChannel("terrarium_hd_sheets_dl"):push({
        ok = ok and true or false,
        err = err,
      })
    ]]
    st.downloadChannel = love.thread.getChannel("terrarium_hd_sheets_dl")
    pcall(function() st.downloadChannel:clear() end)
    st.downloadThread = love.thread.newThread(code)
    st.downloadThread:start(src.url, abs)
  else
    st.blockingDownload = { url = src.url, abs = abs }
  end

  st.state = "downloading"
end

local function pumpRelease()
  return beginDownload()
end

local function pumpDownload()
  local fs = st.fs
  if fs and type(fs.getInfo) == "function" then
    local ok, info = pcall(fs.getInfo, I.config.tempName, "file")
    if ok and info then st.bytes = tonumber(info.size) or st.bytes end
  end

  if st.blockingDownload then
    local job = st.blockingDownload
    st.blockingDownload = nil
    local okReq, HostShell = pcall(require, "src.core.HostShell")
    if not okReq or not HostShell or type(HostShell.httpDownload) ~= "function" then
      return fail("engine downloader unavailable")
    end
    local ok, err = HostShell.httpDownload(job.url, job.abs, "terrarium-hd-sheets")
    if not ok then return fail(err or "download failed") end
    beginExtraction()
    return
  end

  if st.downloadChannel then
    local msg = st.downloadChannel:pop()
    if not msg then return end 
    st.downloadChannel = nil
    st.downloadThread = nil
    if type(msg) ~= "table" or not msg.ok then
      return fail((msg and msg.err) or "download failed")
    end
    beginExtraction()
  end
end

function I._startSource(index)
  st.srcIndex = index
  st.state = "checking"
end

-- ------- public --------------------------------------------------------------

function I.start()
  if st.state == "checking" or st.state == "downloading" or st.state == "extracting" then return false end
  st.error = nil
  if not cacheOk() then
    st.state, st.error = "error", "this build does not provide mod.cache"
    return false
  end
  local fs = rawFilesystem()
  if not fs then st.state, st.error = "error", "filesystem error"; return false end
  st.fs = fs
  cleanup()
  st.counts = { written = 0, existing = 0, low = 0, high = 0, over = 0, other = 0 }
  st.files, st.pos, st.total, st.bytes = {}, 1, 0, 0
  if #I.config.sources == 0 then st.state, st.error = "error", "no sources configured"; return false end
  I._startSource(1)
  return st.state ~= "error"
end

function I.cancel()
  if st.state == "checking" or st.state == "downloading" then
    cancelNetwork()
    cleanup()
    st.state, st.error = "idle", nil
    return true
  end
  return false
end

function I.update()
  local s = st.state
  if s == "idle" or s == "done" or s == "error" then return end
  local ok, err = pcall(function()
    if s == "checking" then pumpRelease()
    elseif s == "downloading" then pumpDownload()
    elseif s == "extracting" then pumpExtraction()
    end
  end)
  if not ok then fail(err) end
end

function I.active()
  return st.state == "checking" or st.state == "downloading" or st.state == "extracting"
end

function I.coverage()
  if st.coverage then return st.coverage end
  local hd = HD()
  local c = { low = 0, high = 0, total = 0 }
  if hd then
    for dex = 1, maxDex() do
      if hd.available(dex, "front", false) and hd.available(dex, "back", false) then
        if dex <= lowMax() then c.low = c.low + 1 else c.high = c.high + 1 end
      end
    end
  end
  c.total = c.low + c.high
  st.coverage = c
  return c
end

function I.invalidate() st.coverage = nil end

function I.status()
  return {
    state = st.state, error = st.error, source = st.srcIndex,
    downloaded = st.bytes, total = st.total,
    extracted = st.pos - 1, queued = #st.files, counts = st.counts,
  }
end

function I.statusText()
  local s = st.state
  if s == "checking" then return "CHECKING" end
  if s == "downloading" then
    if st.total > 0 then return ("DOWNLOAD %d%%"):format(math.floor(100 * (st.bytes or 0) / st.total)) end
    return "DOWNLOADING"
  end
  if s == "extracting" then return ("UNPACK %d/%d"):format(st.pos - 1, #st.files) end
  if s == "error" then return "ERROR RETRY" end
  local c = I.coverage()
  if c.total == 0 then return "GET SHEETS" end
  return ("%d/%d"):format(c.total, maxDex())
end

function I.lastError() return st.error end

function I.row()
  return {
    id = I.ID,
    label = I.LABEL,
    value = function() return I.statusText() end,
    step = function()
      if I.active() then
        I.cancel()
      else
        pcall(I.start)
      end
      return true
    end,
  }
end

return I