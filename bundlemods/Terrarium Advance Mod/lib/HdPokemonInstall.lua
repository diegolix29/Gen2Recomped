-- HD Pokémon sheets (dex 1-493): in-game download / extract / GIF convert.
--
-- OPTIONS row opens HdPokemonScreen. A downloads HDReloded.zip from GitHub;
-- START installs a local zip (desktop picker, or picked_hd_pokemon.zip /
-- Android document picker). Reloded GIFs convert through HdGif; PNG sheets
-- copy into cache/hd_pokemon. No Python on Android.

local V = ...
local Compat = V.require("EngineCompat")

local Install = {}
Install.ID = "DRAMATIC_SHAPE:hdPokemon"
Install.LABEL = "HD POKEMON"
Install.PICKED = "picked_hd_pokemon.zip"
Install.PROGRESS = "hd_pokemon_dl.progress"
Install.DONE = "hd_pokemon_dl.done"
Install.ERR = "hd_pokemon_dl.err"
Install.CANCEL = "hd_pokemon_dl.cancel"
Install.PENDING = "hd_pokemon_picker_pending.flag"
Install.SCRIPT = "hd_pokemon_import.py"
Install.BUILD = "hd_pokemon_build"
Install.PY_PROGRESS = "hd_pokemon_convert.progress"
Install.DEX_MAX = 493
Install.ZIP_URL = "https://github.com/MMNNGG765/Terri-Assets/releases/download/1.0.0/HDReloded.zip"

Install.status = {
  state = "idle",
  error = nil,
  downloadBytes = 0,
  downloadTotal = 0,
  current = 0,
  total = 0,
  message = "",
  count = 0,
}

-- Same rule as tools/import_hd_pokemon.py (basename, case-insensitive).
-- Lua patterns have no (?:...); optional gender is a captured "-m" / "-f".
local NAME_RE = "^(%d+)%-(front|back)%-([ns])(%-[mf])?%.gif$"
local PNG_RE = "assets/battle/hd%-pokemon/(front|back)/(normal|shiny)/(%d%d%d)(%-m|%-f|)%.png$"
local job = nil

local function clipName(s)
  s = tostring(s or ""):gsub("\\", "/"):match("([^/]+)$") or tostring(s or "")
  if #s <= 18 then return s end
  return s:sub(1, 18)
end

local function pngSize(bytes)
  if type(bytes) ~= "string" or #bytes < 24 then return nil end
  if bytes:sub(1, 8) ~= "\137PNG\r\n\26\n" then return nil end
  local function be32(i)
    local a, b, c, d = bytes:byte(i, i + 3)
    if not d then return 0 end
    return a * 16777216 + b * 65536 + c * 256 + d
  end
  return be32(17), be32(21)
end

local function fs()
  return Compat.fs()
end

local function osName()
  return Compat.osName() or "Unknown"
end

local function saveDir()
  local f = fs()
  if f and type(f.getSaveDirectory) == "function" then
    local ok, dir = pcall(f.getSaveDirectory)
    if ok and type(dir) == "string" and dir ~= "" then return dir, f end
  end
  return nil, f
end

local function fileInfo(path)
  local f = fs()
  if not (f and type(f.getInfo) == "function") then return nil end
  local ok, info = pcall(f.getInfo, path, "file")
  return ok and info or nil
end

local function writeFile(path, data)
  local f = fs()
  if not (f and type(f.write) == "function") then return false end
  local ok, a = pcall(f.write, path, data == nil and "" or tostring(data))
  return ok and a ~= false
end

local function readFile(path)
  local f = fs()
  if not (f and type(f.read) == "function") then return nil end
  local ok, data = pcall(f.read, path)
  if ok and type(data) == "string" then return data end
  return nil
end

local function removeFile(path)
  local f = fs()
  if f and type(f.remove) == "function" then pcall(f.remove, path) end
end

local function cacheWrite(rel, bytes)
  local handle = V.mod
  if handle and handle.cache and type(handle.cache.write) == "function" then
    local ok = pcall(handle.cache.write, handle.cache, "hd_pokemon/" .. rel, bytes)
    if ok then return true end
  end
  local f = fs()
  if f and type(f.createDirectory) == "function" then
    local dir = ("hd_pokemon/" .. rel):match("^(.*)/[^/]+$")
    if dir then pcall(f.createDirectory, dir) end
  end
  if f and type(f.write) == "function" then
    local ok = pcall(f.write, "hd_pokemon/" .. rel, bytes)
    if ok then return true end
  end
  return false
end

local function setIdle()
  Install.status.state = "idle"
  Install.status.error = nil
  Install.status.message = ""
end

local function setError(why)
  job = nil
  Install.status.state = "error"
  Install.status.error = tostring(why or "unknown")
  return false
end

local function setDone()
  local n = Install.count()
  job = nil
  Install.status.state = "done"
  Install.status.count = n
  Install.status.current = n
  Install.status.message = "READY"
  return true
end

local function reloadHd()
  local HdPokemon = V.HdPokemon or (V.require and V.require("HdPokemon"))
  if HdPokemon and type(HdPokemon.reload) == "function" then
    pcall(HdPokemon.reload)
  end
end

local function quoteWin(path)
  return '"' .. tostring(path):gsub('"', '\\"') .. '"'
end

local function findPython()
  local shell = Compat.hostShell()
  if not shell then return nil end
  local probes = {
    { run = "py -3", check = 'py -3 -c "from PIL import Image; print(\'OK\')"' },
    { run = "python", check = 'python -c "from PIL import Image; print(\'OK\')"' },
    { run = "python3", check = 'python3 -c "from PIL import Image; print(\'OK\')"' },
  }
  for _, probe in ipairs(probes) do
    local out = Compat.pipeOutput(shell, probe.check)
    if type(out) == "string" and out:find("OK", 1, true) then
      return probe.run
    end
  end
  return nil
end

local function stageImporter(f)
  local handle = V.mod
  if not (handle and type(handle.read) == "function") then
    return nil, "import script missing"
  end
  local ok, src = pcall(handle.read, handle, "tools/import_hd_pokemon.py")
  if not (ok and type(src) == "string" and src ~= "") then
    return nil, "import script missing"
  end
  if not writeFile(Install.SCRIPT, src) then return nil, "could not copy import script" end
  local dir = saveDir()
  if not dir then return nil, "save directory unavailable" end
  return dir .. "/" .. Install.SCRIPT
end

local function ingestBuild(f)
  local handle = V.mod
  if not (handle and handle.cache and type(handle.cache.write) == "function") then
    return nil, "mod cache unavailable"
  end
  local okList, list = pcall(f.read, Install.BUILD .. "/files.txt")
  if not (okList and type(list) == "string" and list ~= "") then
    return nil, "import produced no file list"
  end
  local n = 0
  for line in list:gmatch("[^\r\n]+") do
    local rel = line:gsub("^%s+", ""):gsub("%s+$", "")
    if rel ~= "" then
      local okRead, bytes = pcall(f.read, Install.BUILD .. "/" .. rel)
      if okRead and type(bytes) == "string" and #bytes > 0 then
        if cacheWrite(rel, bytes) then n = n + 1 end
      end
    end
  end
  if n < 1 then return nil, "could not store converted sheets" end
  reloadHd()
  return n
end

function Install.commandHint()
  return Install.ZIP_URL
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

function Install.ready()
  return Install.count() > 0
end

local function openScreen(game)
  local ok, Screen = pcall(V.require, "HdPokemonScreen")
  if not (ok and Screen and type(Screen.new) == "function") then return false end
  if not (game and game.stack and type(game.stack.push) == "function") then return false end
  local made = Screen.new(game)
  if not made then return false end
  game.stack:push(made)
  return true
end

function Install.row()
  return {
    id = Install.ID,
    label = Install.LABEL,
    value = function()
      local st = Install.status.state
      if st == "checking" or st == "downloading" or st == "extracting" then
        return "BUSY"
      end
      local n = Install.count()
      if n >= Install.DEX_MAX then return "READY" end
      if n > 0 then return tostring(n) .. " DEX" end
      return "OPEN"
    end,
    step = function(game)
      pcall(openScreen, game)
      return true
    end,
    activate = function(game)
      pcall(openScreen, game)
    end,
  }
end

local function u16(s, i)
  local a, b = s:byte(i, i + 1)
  if not b then return 0 end
  return a + b * 256
end

local function u32(s, i)
  local a, b, c, d = s:byte(i, i + 3)
  if not d then return 0 end
  return a + b * 256 + c * 65536 + d * 16777216
end

local function openZip(path)
  local f = fs()
  if f and type(f.newFile) == "function" then
    local ok, file = pcall(f.newFile, path)
    if ok and file and type(file.open) == "function" then
      local okOpen = pcall(file.open, file, "r")
      if okOpen then return file, "file" end
    end
  end
  -- Colosseum refuses to buffer a ~1.3 GB disc in Lua. Same rule here: only
  -- materialize a zip that already fits in a small save-file read.
  local info = fileInfo(path)
  local size = info and tonumber(info.size) or 0
  if size >= 22 and size <= 32 * 1024 * 1024 then
    local data = readFile(path)
    if type(data) == "string" and #data >= 22 then
      return data, "blob"
    end
  end
  if size > 32 * 1024 * 1024 then
    return nil, "zip is too large to buffer; engine File API unavailable"
  end
  return nil, "could not open zip"
end

local function zipClose(zf, kind)
  if kind == "file" and zf and zf.close then pcall(zf.close, zf) end
end

local function zipSize(zf, kind, zipRel)
  if kind == "blob" then return #zf end
  if zf.getSize then
    local ok, n = pcall(zf.getSize, zf)
    if ok and type(n) == "number" and n > 0 then return n end
  end
  local info = fileInfo(zipRel or (job and job.zipRel) or Install.PICKED)
  return info and tonumber(info.size) or 0
end

local function zipSeek(zf, offset)
  if not (zf and type(zf.seek) == "function") then return false end
  if pcall(zf.seek, zf, offset) then return true end
  if pcall(zf.seek, zf, "set", offset) then return true end
  return false
end

local function zipRead(zf, kind, offset, size)
  size = math.max(0, math.floor(tonumber(size) or 0))
  offset = math.max(0, math.floor(tonumber(offset) or 0))
  if size == 0 then return "" end
  if kind == "blob" then
    return zf:sub(offset + 1, offset + size)
  end
  zipSeek(zf, offset)
  local ok, chunk = pcall(zf.read, zf, size)
  if ok and type(chunk) == "string" then return chunk end
  return nil
end

local function u64(s, i)
  local lo = u32(s, i)
  local hi = u32(s, i + 4)
  return hi * 4294967296 + lo
end

local function findEocd(zf, kind, zipRel)
  local size = zipSize(zf, kind, zipRel)
  if size < 22 then return nil, "zip too small" end
  local span = math.min(size, 22 + 65535 + 56)
  local blob = zipRead(zf, kind, size - span, span)
  if type(blob) ~= "string" then return nil, "could not read zip footer" end
  local function eocdAt(i)
    return {
      entries = u16(blob, i + 10),
      cdSize = u32(blob, i + 12),
      cdOff = u32(blob, i + 16),
    }
  end
  local eocd
  for i = #blob - 21, 1, -1 do
    if blob:sub(i, i + 3) == "PK\005\006" then
      local commentLen = u16(blob, i + 20)
      if i + 21 + commentLen == #blob + 1 or commentLen == 0 then
        eocd = eocdAt(i)
        break
      end
    end
  end
  if not eocd then
    for i = #blob - 21, 1, -1 do
      if blob:sub(i, i + 3) == "PK\005\006" then
        eocd = eocdAt(i)
        break
      end
    end
  end
  if not eocd then return nil, "not a zip archive" end
  if eocd.cdOff == 0xFFFFFFFF or eocd.cdSize == 0xFFFFFFFF or eocd.entries == 0xFFFF then
    for i = #blob - 55, 1, -1 do
      if blob:sub(i, i + 3) == "PK\006\006" then
        eocd.cdSize = u64(blob, i + 40)
        eocd.cdOff = u64(blob, i + 48)
        eocd.entries = u64(blob, i + 32)
        break
      end
    end
  end
  return eocd
end

local function parseGifName(name)
  name = tostring(name or ""):gsub("\\", "/"):match("([^/]+)$") or ""
  local lower = name:lower()
  local dex, side, color, gender = lower:match(NAME_RE)
  dex = tonumber(dex)
  if not dex or dex < 1 or dex > Install.DEX_MAX then return nil end
  return {
    kind = "gif",
    dex = dex,
    side = side,
    color = color == "s" and "shiny" or "normal",
    gender = (gender == "-m" or gender == "m") and "male"
      or (gender == "-f" or gender == "f") and "female"
      or "default",
    name = name,
  }
end

local function parsePngPath(path)
  path = tostring(path or ""):gsub("\\", "/")
  local side, color, dex, suffix = path:lower():match(PNG_RE)
  dex = tonumber(dex)
  if not (side and color and dex) then return nil end
  if dex < 1 or dex > Install.DEX_MAX then return nil end
  local gender = "default"
  if suffix == "-m" then gender = "male"
  elseif suffix == "-f" then gender = "female" end
  return {
    kind = "png",
    dex = dex,
    side = side,
    color = color,
    gender = gender,
    rel = string.format("assets/battle/hd-pokemon/%s/%s/%03d%s.png",
      side, color, dex, suffix),
  }
end

local function listZipMembers(zf, kind, zipRel)
  local eocd, err = findEocd(zf, kind, zipRel)
  if not eocd then return nil, err end
  local cd = zipRead(zf, kind, eocd.cdOff, eocd.cdSize)
  if type(cd) ~= "string" or #cd < 46 then return nil, "zip directory unreadable" end
  local members, p = {}, 1
  while p + 45 <= #cd do
    if cd:sub(p, p + 3) ~= "PK\001\002" then
      local nextSig = cd:find("PK\001\002", p, true)
      if not nextSig then break end
      p = nextSig
    end
    local method = u16(cd, p + 10)
    local comp = u32(cd, p + 20)
    local raw = u32(cd, p + 24)
    local nameLen = u16(cd, p + 28)
    local extraLen = u16(cd, p + 30)
    local commentLen = u16(cd, p + 32)
    local localOff = u32(cd, p + 42)
    local name = cd:sub(p + 46, p + 45 + nameLen)
    p = p + 46 + nameLen + extraLen + commentLen
    if name ~= "" and name:sub(-1) ~= "/" then
      -- Python walks every *.gif by basename; do the same, then PNG/lua.
      local meta
      if name:lower():match("%.gif$") then
        meta = parseGifName(name)
      else
        meta = parsePngPath(name)
        if name:lower():match("data/hd_pokemon%.lua$") then
          meta = { kind = "lua", rel = "data/hd_pokemon.lua", name = name }
        end
      end
      if meta then
        meta.method = method
        meta.comp = comp
        meta.raw = raw
        meta.localOff = localOff
        meta.zipName = name
        members[#members + 1] = meta
      end
    end
  end
  return members
end

local function extractMember(zf, kind, member)
  local header = zipRead(zf, kind, member.localOff, 30)
  if type(header) ~= "string" or header:sub(1, 4) ~= "PK\003\004" then
    return nil, "bad zip local header"
  end
  local nameLen = u16(header, 27)
  local extraLen = u16(header, 29)
  local dataOff = member.localOff + 30 + nameLen + extraLen
  local payload = zipRead(zf, kind, dataOff, member.comp)
  if type(payload) ~= "string" then return nil, "truncated zip member" end
  if member.method == 0 then return payload end
  if member.method ~= 8 then return nil, "unsupported zip compression" end
  if not (love and love.data and type(love.data.decompress) == "function") then
    return nil, "love.data.decompress unavailable"
  end
  local ok, out = pcall(love.data.decompress, "string", "deflate", payload)
  if ok and type(out) == "string" then return out end
  ok, out = pcall(love.data.decompress, "string", "zlib", payload)
  if ok and type(out) == "string" then return out end
  return nil, "zip inflate failed"
end

local function luaQuote(s)
  return '"' .. tostring(s):gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
end

local function writeMetadata(records)
  local lines = {
    "-- Generated by HdPokemonInstall. Do not hand-edit.",
    "-- National Dex 1-493 HD front/back sheets (normal + shiny).",
    "return {",
  }
  local dexes = {}
  for dex in pairs(records) do dexes[#dexes + 1] = dex end
  table.sort(dexes)
  for _, dex in ipairs(dexes) do
    local species = records[dex]
    lines[#lines + 1] = string.format("  [%d] = {", dex)
    lines[#lines + 1] = string.format("    dex = %d,", dex)
    for _, side in ipairs({ "front", "back" }) do
      local sideRec = species[side]
      if type(sideRec) == "table" then
        lines[#lines + 1] = "    " .. side .. " = {"
        for _, color in ipairs({ "normal", "shiny" }) do
          local colorRec = sideRec[color]
          if type(colorRec) == "table" then
            lines[#lines + 1] = "      " .. color .. " = {"
            for _, gender in ipairs({ "default", "male", "female" }) do
              local rec = colorRec[gender]
              if type(rec) == "table" then
                local durs = {}
                local src = rec.durations or { 100 }
                for i = 1, math.max(1, tonumber(rec.frames) or 1) do
                  durs[i] = tostring(math.max(1, tonumber(src[i]) or 100))
                end
                lines[#lines + 1] = string.format(
                  "        %s = { image = %s, width = %d, height = %d, columns = %d, frames = %d, durations = {%s}, displayScale = %.6f },",
                  gender,
                  luaQuote(rec.image),
                  tonumber(rec.width) or 1,
                  tonumber(rec.height) or 1,
                  tonumber(rec.columns) or 1,
                  tonumber(rec.frames) or 1,
                  table.concat(durs, ","),
                  tonumber(rec.displayScale) or 1)
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
  lines[#lines + 1] = ""
  return cacheWrite("data/hd_pokemon.lua", table.concat(lines, "\n"))
end

local function putRecord(records, member, rec)
  local species = records[member.dex]
  if not species then
    species = {}
    records[member.dex] = species
  end
  species[member.side] = species[member.side] or {}
  species[member.side][member.color] = species[member.side][member.color] or {}
  species[member.side][member.color][member.gender] = rec
end

local function convertGif(member, bytes)
  local HdGif = V.require("HdGif")
  if not (HdGif and type(HdGif.decode) == "function") then
    return nil, "HdGif unavailable"
  end
  local decoded, err = HdGif.decode(bytes)
  if not decoded then return nil, err or "gif decode failed" end
  local packed, packErr = HdGif.packSheet(decoded, 0.60)
  if not packed then return nil, packErr or "gif pack failed" end
  local suffix = ""
  if member.gender == "male" then suffix = "-m"
  elseif member.gender == "female" then suffix = "-f" end
  local rel = string.format("assets/battle/hd-pokemon/%s/%s/%03d%s.png",
    member.side, member.color, member.dex, suffix)
  if not cacheWrite(rel, packed.bytes) then return nil, "could not store sheet" end
  return {
    image = rel,
    width = packed.width,
    height = packed.height,
    columns = packed.columns,
    frames = packed.frames,
    durations = packed.durations,
    displayScale = member.side == "back" and 0.315 or 0.33,
  }
end

local function beginPythonConvert(zipRel, python)
  local dir, f = saveDir()
  if not dir then return setError("save directory unavailable") end
  local scriptPath, scriptErr = stageImporter(f)
  if not scriptPath then return setError(scriptErr) end
  local outDir = dir .. "/" .. Install.BUILD
  local zipPath = dir .. "/" .. zipRel
  local progPath = dir .. "/" .. Install.PY_PROGRESS
  removeFile(Install.PY_PROGRESS)
  writeFile(Install.PY_PROGRESS, "converting\n0\n1\nSCANNING\n")
  local shell = Compat.hostShell()
  if not (shell and type(shell.popen) == "function") then
    return setError("host shell unavailable")
  end
  local osn = osName()
  local command
  if osn == "Windows" then
    command = 'start /b "" ' .. python .. " " .. quoteWin(scriptPath)
      .. " --max-dex 493 --out " .. quoteWin(outDir)
      .. " --progress-file " .. quoteWin(progPath)
      .. " " .. quoteWin(zipPath)
  else
    local quote = (type(shell.quote) == "function")
      and function(v) return shell.quote(v) end
      or function(v) return "'" .. tostring(v):gsub("'", "'\\''") .. "'" end
    command = python .. " " .. quote(scriptPath)
      .. " --max-dex 493 --out " .. quote(outDir)
      .. " --progress-file " .. quote(progPath)
      .. " " .. quote(zipPath) .. " >/dev/null 2>&1 &"
  end
  local ok, pipe = pcall(shell.popen, command, "r")
  if not (ok and pipe) then return setError("could not start GIF converter") end
  if type(shell.pclose) == "function" then pcall(shell.pclose, pipe)
  elseif pipe.close then pcall(pipe.close, pipe) end
  job = { phase = "python", zipRel = zipRel, stall = 0 }
  Install.status.state = "extracting"
  Install.status.current = 0
  Install.status.total = 1
  Install.status.message = "SCANNING GIFS"
  return true
end

local function pollPython()
  local raw = readFile(Install.PY_PROGRESS)
  if type(raw) ~= "string" or raw == "" then
    job.stall = (job.stall or 0) + 1
    if job.stall > 3600 then
      return setError("GIF convert stalled; need Python 3 + Pillow")
    end
    return
  end
  local state, cur, total, msg = raw:match("^([^\r\n]+)[\r\n]+(%-?%d+)[\r\n]+(%-?%d+)[\r\n]*([^\r\n]*)")
  state = tostring(state or ""):lower()
  Install.status.current = tonumber(cur) or 0
  Install.status.total = math.max(1, tonumber(total) or 1)
  if msg and msg ~= "" then Install.status.message = clipName(msg) end
  if state == "fail" then
    return setError(msg ~= "" and msg or "no matching HD Pokemon GIFs found")
  end
  if state == "done" then
    local f = fs()
    local stored, ingestErr = ingestBuild(f)
    if not stored then return setError(ingestErr or "could not store converted sheets") end
    return setDone()
  end
end

local function beginLuaExtract(zipRel)
  local zf, kindOrErr = openZip(zipRel)
  if not zf then return setError(kindOrErr or "could not open zip") end
  local kind = type(zf) == "string" and "blob" or kindOrErr
  job = { zipRel = zipRel }
  local members, listErr = listZipMembers(zf, kind, zipRel)
  if not members then
    zipClose(zf, kind)
    job = nil
    return setError(listErr or "empty zip")
  end
  if #members < 1 then
    zipClose(zf, kind)
    job = nil
    return setError("no matching HD Pokemon GIFs found")
  end
  local hadLua = false
  for i = 1, #members do
    if members[i].kind == "lua" then hadLua = true; break end
  end
  job = {
    phase = "extract",
    zipRel = zipRel,
    zf = zf,
    kind = kind,
    members = members,
    index = 0,
    records = {},
    stored = 0,
    hadLua = hadLua,
  }
  Install.status.state = "extracting"
  Install.status.current = 0
  Install.status.total = #members
  Install.status.message = "INSTALLING"
  return true
end

local function beginExtract(zipRel)
  zipRel = zipRel or Install.PICKED
  local osn = osName()
  if osn ~= "Android" and osn ~= "iOS" then
    local python = findPython()
    if python then return beginPythonConvert(zipRel, python) end
  end
  return beginLuaExtract(zipRel)
end

local function stepExtract()
  if not job or job.phase ~= "extract" then return end
  job.index = job.index + 1
  local member = job.members[job.index]
  if not member then
    zipClose(job.zf, job.kind)
    if job.stored < 1 then return setError("could not store converted sheets") end
    if not job.hadLua then
      if not writeMetadata(job.records) then
        return setError("could not write HD metadata")
      end
    end
    reloadHd()
    return setDone()
  end
  Install.status.current = job.index
  Install.status.total = #job.members
  Install.status.message = clipName(member.name or member.zipName or member.rel)
  local bytes, err = extractMember(job.zf, job.kind, member)
  if not bytes then return end
  if member.kind == "lua" then
    if cacheWrite("data/hd_pokemon.lua", bytes) then job.stored = job.stored + 1 end
    return
  end
  if member.kind == "png" then
    if cacheWrite(member.rel, bytes) then
      job.stored = job.stored + 1
      local w, h = pngSize(bytes)
      putRecord(job.records, member, {
        image = member.rel,
        width = w or 1,
        height = h or 1,
        columns = 1,
        frames = 1,
        durations = { 100 },
        displayScale = member.side == "back" and 0.315 or 0.33,
      })
    end
    return
  end
  local rec, convErr = convertGif(member, bytes)
  if rec then
    job.stored = job.stored + 1
    putRecord(job.records, member, rec)
  else
    Install.status.message = tostring(convErr or err or "skip")
  end
end

local DOWNLOAD_THREAD = [[
require("love.filesystem")
local url, destRel, progressRel, doneRel, errRel, cancelRel = ...
local function report(bytes, total)
  pcall(love.filesystem.write, progressRel, tostring(bytes or 0) .. "\n" .. tostring(total or 0) .. "\n")
end
local function fail(why)
  pcall(love.filesystem.write, errRel, tostring(why or "download failed"))
  pcall(love.filesystem.write, doneRel, "FAIL")
end
local function cancelled()
  local data = love.filesystem.read(cancelRel)
  return type(data) == "string" and data ~= ""
end
local function saveAbs()
  local dir = love.filesystem.getSaveDirectory and love.filesystem.getSaveDirectory()
  if type(dir) == "string" and dir ~= "" then return dir .. "/" .. destRel end
  return destRel
end
local function okWrite(bytes)
  if type(bytes) ~= "string" or #bytes < 4 then return false, "empty download" end
  if bytes:sub(1, 2) ~= "PK" then return false, "download was not a zip" end
  local ok = love.filesystem.write(destRel, bytes)
  if not ok then
    local ioOpen = io and io.open
    if ioOpen then
      local fh = ioOpen(saveAbs(), "wb")
      if fh then fh:write(bytes); fh:close(); ok = true end
    end
  end
  return ok, "could not write zip"
end
report(0, 0)
if cancelled() then fail("cancelled"); return end
local function tryHttps()
  local okMod, https = pcall(require, "https")
  if not (okMod and https and type(https.request) == "function") then return false end
  local code, body = https.request(url, { headers = { ["user-agent"] = "TerrariumAdvance" } })
  if type(code) == "number" and code >= 200 and code < 300 and type(body) == "string" then
    report(#body, #body)
    local ok, why = okWrite(body)
    if ok then pcall(love.filesystem.write, doneRel, "OK"); return true end
    fail(why); return true
  end
  return false
end
local function trySsl()
  local okMod, https = pcall(require, "ssl.https")
  if not (okMod and https and type(https.request) == "function") then return false end
  local body, code = https.request(url)
  if type(code) == "number" and code >= 200 and code < 300 and type(body) == "string" then
    report(#body, #body)
    local ok, why = okWrite(body)
    if ok then pcall(love.filesystem.write, doneRel, "OK"); return true end
    fail(why); return true
  end
  return false
end
local function shQuote(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end
local function tryCurl()
  local popen = io and io.popen
  if not popen then return false end
  local abs = saveAbs()
  local cmd = "curl -L --fail -A TerrariumAdvance -o " .. shQuote(abs) .. " " .. shQuote(url) .. " && echo OK"
  local pipe = popen(cmd)
  if not pipe then return false end
  local out = pipe:read("*a") or ""
  pipe:close()
  if not out:find("OK", 1, true) then return false end
  local info = love.filesystem.getInfo(destRel, "file")
  local n = info and info.size or 0
  report(n, n)
  if n > 4 then pcall(love.filesystem.write, doneRel, "OK"); return true end
  return false
end
if not (tryHttps() or trySsl() or tryCurl()) then
  fail("https download unavailable")
end
]]

local function clearDownloadSidecars()
  removeFile(Install.PROGRESS)
  removeFile(Install.DONE)
  removeFile(Install.ERR)
  removeFile(Install.CANCEL)
end

local function psq(s)
  return "'" .. tostring(s):gsub("'", "''") .. "'"
end

local function startHostDownload()
  local dir = saveDir()
  if not dir then return false, "save directory unavailable" end
  local shell = Compat.hostShell()
  if not (shell and type(shell.popen) == "function") then
    return false, "host download unavailable"
  end
  local dest = dir .. "/" .. Install.PICKED
  local done = dir .. "/" .. Install.DONE
  local errp = dir .. "/" .. Install.ERR
  local url = Install.ZIP_URL
  local osn = osName()
  local command
  if osn == "Windows" then
    local script = table.concat({
      "$ProgressPreference='SilentlyContinue'",
      "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12",
      "$dest = " .. psq(dest),
      "$done = " .. psq(done),
      "$errp = " .. psq(errp),
      "$url = " .. psq(url),
      "try {",
      "  $curl = Get-Command curl.exe -ErrorAction SilentlyContinue",
      "  if ($curl) {",
      "    & curl.exe -L --fail -A TerrariumAdvance -o $dest $url",
      "    if ($LASTEXITCODE -ne 0) { throw 'curl.exe failed' }",
      "  } else {",
      "    Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -UserAgent 'TerrariumAdvance'",
      "  }",
      "  if (-not (Test-Path -LiteralPath $dest)) { throw 'download produced no file' }",
      "  Set-Content -LiteralPath $done -Value 'OK' -Encoding ASCII",
      "} catch {",
      "  Set-Content -LiteralPath $errp -Value $_.Exception.Message -Encoding ASCII",
      "  Set-Content -LiteralPath $done -Value 'FAIL' -Encoding ASCII",
      "}",
    }, "\r\n")
    if not writeFile("hd_pokemon_dl.ps1", script) then
      return false, "could not write download script"
    end
    command = "start /b powershell -NoProfile -WindowStyle Hidden -File "
      .. quoteWin(dir .. "/hd_pokemon_dl.ps1")
  else
    local quote = (type(shell.quote) == "function")
      and function(v) return shell.quote(v) end
      or function(v) return "'" .. tostring(v):gsub("'", "'\\''") .. "'" end
    command = "(curl -L --fail -A TerrariumAdvance -o " .. quote(dest) .. " "
      .. quote(url) .. " && printf OK > " .. quote(done)
      .. ") || (printf 'curl failed' > " .. quote(errp) .. "; printf FAIL > " .. quote(done) .. ") &"
  end
  local ok, pipe = pcall(shell.popen, command, "r")
  if not (ok and pipe) then return false, "could not start download" end
  job = { phase = "download", pipe = pipe, host = true, stall = 0 }
  return true
end

local function startThreadDownload()
  if not (love and love.thread and type(love.thread.newThread) == "function") then
    return false, "download thread unavailable"
  end
  local ok, thread = pcall(love.thread.newThread, DOWNLOAD_THREAD)
  if not (ok and thread) then return false, tostring(thread) end
  local started = pcall(function()
    thread:start(Install.ZIP_URL, Install.PICKED, Install.PROGRESS,
      Install.DONE, Install.ERR, Install.CANCEL)
  end)
  if not started then return false, "could not start download thread" end
  job = { phase = "download", thread = thread, stall = 0 }
  return true
end

function Install.startDownload()
  local st = Install.status.state
  if st == "checking" or st == "downloading" or st == "extracting" then return false end
  clearDownloadSidecars()
  removeFile(Install.PICKED)
  Install.status.state = "checking"
  Install.status.error = nil
  Install.status.downloadBytes = 0
  Install.status.downloadTotal = 0
  Install.status.message = "CHECKING RELEASE"
  local osn = osName()
  local ok, why
  if osn == "Android" or osn == "iOS" then
    ok, why = startThreadDownload()
    if not ok then ok, why = startHostDownload() end
  else
    ok, why = startHostDownload()
    if not ok then ok, why = startThreadDownload() end
  end
  if not ok then
    return setError(why or "cannot download on this device")
  end
  Install.status.state = "downloading"
  return true
end

local function consumeMobilePick()
  if not fileInfo(Install.PENDING) then return false end
  -- Same as StadiumRomMenu: the Android SAF bridge lands on picked_rom.gb
  -- (or picked_mod.zip). Extract in place. Never Lua-copy the archive.
  local src
  if fileInfo("picked_mod.zip") then src = "picked_mod.zip"
  elseif fileInfo("picked_rom.gb") then src = "picked_rom.gb"
  elseif fileInfo(Install.PICKED) then src = Install.PICKED
  end
  if not src then return false end
  removeFile(Install.PENDING)
  return beginExtract(src)
end

function Install.startLocalZip(game)
  local st = Install.status.state
  if st == "checking" or st == "downloading" or st == "extracting" then return false end
  local osn = osName()
  if osn == "Android" or osn == "iOS" then
    if fileInfo(Install.PICKED) then
      return beginExtract(Install.PICKED)
    end
    writeFile(Install.PENDING, "hd-pokemon\n")
    local opener = Compat.openMobileZipPicker or Compat.openMobileFilePicker
    local ok, launched, why = pcall(opener)
    if not ok or not launched then
      removeFile(Install.PENDING)
      if fileInfo(Install.PICKED) then return beginExtract(Install.PICKED) end
      return setError(ok and (why or launched) or launched or "file picker did not open")
    end
    Install.status.state = "checking"
    Install.status.message = "PICK ZIP"
    job = { phase = "pick", idle = 0 }
    return true
  end
  if Install.canDialog() then
    local path = Compat.chooseFile(
      "Choose HD Pokemon GIF zip (Reloded / 1-493)",
      { "zip" },
      "HD Pokemon ZIP")
    if not path then return false end
    removeFile(Install.PICKED)
    local okStage, relOrErr = Compat.stageExternal(path, Install.PICKED)
    if not okStage then return setError(relOrErr or "could not copy selected file") end
    return beginExtract(Install.PICKED)
  end
  if fileInfo(Install.PICKED) then
    return beginExtract(Install.PICKED)
  end
  return setError("put HDReloded.zip in the save folder as picked_hd_pokemon.zip")
end

local function pollDownload()
  if fileInfo(Install.ERR) and fileInfo(Install.DONE) then
    local why = readFile(Install.ERR) or "download failed"
    clearDownloadSidecars()
    return setError(why)
  end
  local progress = readFile(Install.PROGRESS)
  if type(progress) == "string" then
    local have, total = progress:match("^(%d+)[\r\n]+(%d+)")
    Install.status.downloadBytes = tonumber(have) or Install.status.downloadBytes
    Install.status.downloadTotal = tonumber(total) or 0
  end
  local info = fileInfo(Install.PICKED)
  if info and tonumber(info.size) then
    Install.status.downloadBytes = math.max(Install.status.downloadBytes or 0, info.size)
  end
  local have = tonumber(Install.status.downloadBytes) or 0
  if have ~= (job.lastBytes or 0) then
    job.lastBytes = have
    job.stall = 0
  else
    job.stall = (job.stall or 0) + 1
  end
  -- ~60s with no file growth before first byte, then keep waiting while the
  -- host is still writing. The old 3s timeout fired before GitHub started.
  if job.stall > 3600 and have < 8 and not fileInfo(Install.DONE) then
    clearDownloadSidecars()
    return setError("download stalled; use START with a local zip")
  end
  if fileInfo(Install.DONE) then
    local mark = readFile(Install.DONE) or ""
    clearDownloadSidecars()
    if not mark:find("OK", 1, true) then
      return setError(readFile(Install.ERR) or "download failed")
    end
    if not (info and info.size and info.size > 4) then
      info = fileInfo(Install.PICKED)
    end
    if not (info and tonumber(info.size) and info.size > 4) then
      return setError("download produced an empty file")
    end
    return beginExtract(Install.PICKED)
  end
end

function Install.poll()
  if not job then return end
  if job.phase == "pick" then
    consumeMobilePick()
    return
  end
  if job.phase == "download" then
    pollDownload()
    return
  end
  if job.phase == "python" then
    pollPython()
    return
  end
  if job.phase == "extract" then
    local budget = 1
    local osn = osName()
    if osn == "Windows" or osn == "Linux" or osn == "OS X" then budget = 2 end
    for _ = 1, budget do
      if not job or job.phase ~= "extract" then break end
      stepExtract()
    end
  end
end

function Install.cancel()
  writeFile(Install.CANCEL, "1")
  if job and job.zf then zipClose(job.zf, job.kind) end
  job = nil
  setIdle()
end

-- Desktop-only Python path kept for tools/import_hd_pokemon.py; the screen
-- uses startDownload / startLocalZip instead.
function Install.import(game)
  return Install.startLocalZip(game)
end

return Install
