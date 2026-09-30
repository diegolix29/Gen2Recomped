-- HD Pokémon sheets (dex 1-493): in-game import, without Kanto in Motion.
--
-- OPTIONS row next to CHARACTER VIEWER. Press A, pick a Reloded / HD GIF
-- zip, then HdPokemonScreen shows CONVERTING progress while
-- tools/import_hd_pokemon.py runs. Sheets land in cache/hd_pokemon.

local V = ...
local Compat = V.require("EngineCompat")

local Install = {}
Install.ID = "DRAMATIC_SHAPE:hdPokemon"
Install.LABEL = "HD POKEMON"
Install.PICKED = "picked_hd_pokemon.zip"
Install.SCRIPT = "hd_pokemon_import.py"
Install.BUILD = "hd_pokemon_build"
Install.PROGRESS = "hd_pokemon_build/progress.txt"
Install.DEX_MAX = 493

Install.status = {
  state = "idle",
  error = nil,
  current = 0,
  total = 1,
  message = "",
  count = 0,
}

local function pushScreen(game)
  local ok, Screen = pcall(V.require, "HdPokemonScreen")
  if ok and Screen and game and game.stack and type(Screen.new) == "function" then
    pcall(function() game.stack:push(Screen.new(game)) end)
  end
end

local function note(game, title, lead, body)
  local ok, StadiumScreen = pcall(V.require, "StadiumScreen")
  if not (ok and StadiumScreen and game and game.stack
      and type(StadiumScreen.newNote) == "function") then
    return
  end
  pcall(function()
    game.stack:push(StadiumScreen.newNote(game, title, lead, body))
  end)
end

function Install.commandHint()
  return "python tools/import_hd_pokemon.py --max-dex 493 --target \"<Terrarium Advance Mod>\" \"<reloded-gifs.zip>\""
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

function Install.row()
  return {
    id = Install.ID,
    label = Install.LABEL,
    value = function()
      local st = Install.status.state
      if st == "importing" or st == "starting" then return "BUSY" end
      local n = Install.count()
      if n >= Install.DEX_MAX then return "READY" end
      if n > 0 then return tostring(n) .. " DEX" end
      return Install.canDialog() and "IMPORT" or "WHERE?"
    end,
    step = function(game)
      pcall(Install.import, game)
      return true
    end,
    activate = function(game)
      pcall(Install.import, game)
    end,
  }
end

local function saveDir()
  local f = Compat.fs()
  if f and type(f.getSaveDirectory) == "function" then
    local ok, dir = pcall(f.getSaveDirectory)
    if ok and type(dir) == "string" and dir ~= "" then return dir, f end
  end
  return nil, f
end

local function findPython()
  local shell = Compat.hostShell()
  if not shell then return nil end
  local probes = {
    { exe = "py", args = { "-3" }, check = 'py -3 -c "from PIL import Image; print(\'OK\')"' },
    { exe = "python", args = {}, check = 'python -c "from PIL import Image; print(\'OK\')"' },
    { exe = "python3", args = {}, check = 'python3 -c "from PIL import Image; print(\'OK\')"' },
  }
  for _, probe in ipairs(probes) do
    local out = Compat.pipeOutput(shell, probe.check)
    if type(out) == "string" and out:find("OK", 1, true) then
      return probe
    end
  end
  return nil
end

local function stageImporter(f)
  local handle = V.mod
  if not (handle and type(handle.read) == "function") then
    return nil, "mod files unavailable"
  end
  local ok, src = pcall(handle.read, handle, "tools/import_hd_pokemon.py")
  if not (ok and type(src) == "string" and src ~= "") then
    return nil, "import script missing"
  end
  local okWrite = pcall(f.write, Install.SCRIPT, src)
  if not okWrite then return nil, "could not copy import script" end
  local dir = saveDir()
  if not dir then return nil, "save directory unavailable" end
  return dir .. "/" .. Install.SCRIPT
end

local function ingestBuild(f)
  Install.status.message = "STORING"
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
        local okWrite = pcall(handle.cache.write, handle.cache, "hd_pokemon/" .. rel, bytes)
        if okWrite then n = n + 1 end
      end
    end
  end
  if n < 1 then return nil, "could not store converted sheets" end
  local HdPokemon = V.HdPokemon or (V.require and V.require("HdPokemon"))
  if HdPokemon and type(HdPokemon.reload) == "function" then
    pcall(HdPokemon.reload)
  end
  return n
end

local function parseProgress(text)
  if type(text) ~= "string" then return nil end
  local lines = {}
  for line in text:gmatch("[^\r\n]+") do
    lines[#lines + 1] = line
  end
  if #lines < 1 then return nil end
  return {
    state = lines[1] or "",
    current = tonumber(lines[2]) or 0,
    total = math.max(1, tonumber(lines[3]) or 1),
    message = lines[4] or "",
  }
end

local function psQuote(s)
  return "'" .. tostring(s):gsub("'", "''") .. "'"
end

local function launchPython(python, scriptPath, outDir, zipPath, progressPath)
  local shell = Compat.hostShell()
  if not shell then return nil, "no host shell" end
  local osName = Compat.osName()
  local args = {}
  for _, extra in ipairs(python.args or {}) do args[#args + 1] = extra end
  args[#args + 1] = scriptPath
  args[#args + 1] = "--max-dex"
  args[#args + 1] = "493"
  args[#args + 1] = "--out"
  args[#args + 1] = outDir
  args[#args + 1] = "--progress-file"
  args[#args + 1] = progressPath
  args[#args + 1] = zipPath

  local command
  if osName == "Windows" then
    local listed = {}
    for _, a in ipairs(args) do
      listed[#listed + 1] = psQuote(a)
    end
    command = "powershell -NoProfile -NonInteractive -Command "
      .. '"Start-Process -FilePath ' .. psQuote(python.exe)
      .. " -ArgumentList @(" .. table.concat(listed, ",") .. ")"
      .. ' -WindowStyle Hidden"'
  else
    local quote = (type(shell.quote) == "function")
      and function(v) return shell.quote(v) end
      or function(v) return "'" .. tostring(v):gsub("'", "'\\''") .. "'" end
    local parts = { quote(python.exe) }
    for _, a in ipairs(args) do parts[#parts + 1] = quote(a) end
    command = table.concat(parts, " ") .. " >/dev/null 2>&1 &"
  end
  Compat.pipeOutput(shell, command)
  return true
end

function Install.poll()
  local st = Install.status
  if st.state ~= "importing" and st.state ~= "starting" then return end
  if st.startedAt and (os.clock() - st.startedAt) > 180 and (tonumber(st.current) or 0) < 1 then
    st.state = "failed"
    st.error = "importer did not start (need Python 3 + Pillow)"
    return
  end
  local f = Compat.fs()
  local text
  if f then
    local ok, got = pcall(f.read, Install.PROGRESS)
    if ok then text = got end
  end
  if type(text) ~= "string" or text == "" then
    local dir = saveDir()
    local shell = Compat.hostShell()
    if dir and shell then
      local osName = Compat.osName()
      local abs = dir .. "/" .. Install.PROGRESS
      if osName == "Windows" then
        text = Compat.pipeOutput(shell,
          "powershell -NoProfile -NonInteractive -Command "
          .. '"Get-Content -LiteralPath ' .. psQuote(abs) .. ' -Raw"')
      else
        local quote = (type(shell.quote) == "function")
          and function(v) return shell.quote(v) end
          or function(v) return "'" .. tostring(v):gsub("'", "'\\''") .. "'" end
        text = Compat.pipeOutput(shell, "cat " .. quote(abs) .. " 2>/dev/null")
      end
    end
  end
  local parsed = parseProgress(text)
  if parsed then
    st.current = parsed.current
    st.total = parsed.total
    st.message = parsed.message
    if parsed.state == "done" then
      local stored, err = ingestBuild(f)
      if stored then
        st.state = "done"
        st.count = Install.count()
        st.message = "READY"
      else
        st.state = "failed"
        st.error = err or "could not store sheets"
      end
      return
    end
    if parsed.state == "fail" then
      st.state = "failed"
      st.error = parsed.message
      return
    end
    st.state = "importing"
  end
end

function Install.import(game)
  local st = Install.status
  if st.state == "importing" or st.state == "starting" then
    pushScreen(game)
    return false
  end

  if not Install.canDialog() then
    note(game, "HD POKEMON", "CONVERT GIF ZIP WITH:", Install.commandHint())
    return false
  end

  local path = Compat.chooseFile(
    "Choose HD Pokemon GIF zip (Reloded / 1-493)",
    { "zip", "gif" },
    "HD Pokemon GIFs")
  if not path then return false end

  local function fail(why)
    st.state = "failed"
    st.error = why
    pushScreen(game)
    return false
  end

  local python = findPython()
  if not python then
    return fail("need Python 3 with Pillow (pip install pillow)")
  end

  local okStage, relOrErr = Compat.stageExternal(path, Install.PICKED)
  if not okStage then return fail(relOrErr or "could not open that file") end

  local dir, f = saveDir()
  if not dir then return fail("save directory unavailable") end
  local scriptPath, scriptErr = stageImporter(f)
  if not scriptPath then return fail(scriptErr) end

  pcall(f.write, Install.PROGRESS, "converting\n0\n1\nSTARTING\n")
  pcall(f.remove, Install.BUILD .. "/files.txt")

  local outDir = dir .. "/" .. Install.BUILD
  local zipPath = dir .. "/" .. Install.PICKED
  local progressPath = dir .. "/" .. Install.PROGRESS
  local okLaunch, launchErr = launchPython(python, scriptPath, outDir, zipPath, progressPath)
  if not okLaunch then return fail(launchErr or "could not start importer") end

  st.state = "starting"
  st.error = nil
  st.current = 0
  st.total = 1
  st.message = "STARTING"
  st.count = 0
  st.startedAt = os.clock()
  pushScreen(game)
  return true
end

return Install
