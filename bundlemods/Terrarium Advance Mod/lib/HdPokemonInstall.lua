-- HD Pokémon sheets (dex 1-493): in-game import, without Kanto in Motion.
--
-- OPTIONS row next to CHARACTER VIEWER. Press A, pick a Reloded / HD GIF
-- zip (names like 025-front-n.gif), and Python+Pillow convert them into
-- cache/hd_pokemon. 3D Colosseum/Stadium models still win when present.

local V = ...
local Compat = V.require("EngineCompat")

local Install = {}
Install.ID = "DRAMATIC_SHAPE:hdPokemon"
Install.LABEL = "HD POKEMON"
Install.PICKED = "picked_hd_pokemon.zip"
Install.SCRIPT = "hd_pokemon_import.py"
Install.BUILD = "hd_pokemon_build"
Install.DEX_MAX = 493

Install.status = { state = "idle", error = nil }

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
      if Install.status.state == "importing" then return "BUSY" end
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

function Install.import(game)
  if Install.status.state == "importing" then return false end

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
    Install.status.state = "failed"
    Install.status.error = why
    note(game, "HD POKEMON", "IMPORT FAILED", tostring(why))
    return false
  end

  local python = findPython()
  if not python then
    return fail("need Python 3 with Pillow (pip install pillow). " .. Install.commandHint())
  end

  local okStage, relOrErr = Compat.stageExternal(path, Install.PICKED)
  if not okStage then return fail(relOrErr or "could not open that file") end

  local dir, f = saveDir()
  if not dir then return fail("save directory unavailable") end
  local scriptPath, scriptErr = stageImporter(f)
  if not scriptPath then return fail(scriptErr) end

  local outDir = dir .. "/" .. Install.BUILD
  local zipPath = dir .. "/" .. Install.PICKED
  local shell = Compat.hostShell()
  local osName = Compat.osName()
  local command
  if osName == "Windows" then
    command = python .. " " .. quoteWin(scriptPath)
      .. " --max-dex 493 --out " .. quoteWin(outDir)
      .. " " .. quoteWin(zipPath)
  else
    local quote = (shell and type(shell.quote) == "function")
      and function(v) return shell.quote(v) end
      or function(v) return "'" .. tostring(v):gsub("'", "'\\''") .. "'" end
    command = python .. " " .. quote(scriptPath)
      .. " --max-dex 493 --out " .. quote(outDir)
      .. " " .. quote(zipPath)
  end

  Install.status.state = "importing"
  local out = Compat.pipeOutput(shell, command)
  Install.status.state = "idle"

  local stored, ingestErr = ingestBuild(f)
  if not stored then
    local extra = (type(out) == "string" and out:sub(-180)) or ingestErr
    return fail(ingestErr or extra or "conversion failed")
  end

  note(game, "HD POKEMON", "READY", tostring(Install.count()) .. " SPECIES CACHED")
  return true
end

return Install
