-- STADIUM battles: finding the ROM, and building the models out of it once.
--
-- The mod does not ship the Pokemon Stadium models and cannot: they are that
-- game's data. What it ships is the READER -- StadiumRom, StadiumRom2,
-- StadiumFragment, StadiumFx and StadiumBuild -- and the player supplies the
-- cartridge, which is exactly the arrangement this engine already has for the
-- Game Boy ROM it is a recompilation of (src/import/RomImporter.lua).
--
-- So: supply a Pokemon Stadium (US) ROM for Gen 1 games, or Pokemon Stadium 2
-- (US) ROM for Gen 2 games -- the OPTIONS row opens a file picker for one,
-- or drop it in `baseroms/` -- and the first time the game runs with the mod
-- on, the models are built. Once, on a loading screen, in about ten seconds.
-- After that the packs sit in the save directory and the mod reads them like
-- any other asset.
--
-- ------- where "baseroms/" is
--
-- One relative path, and it deliberately covers two different places at once,
-- because PhysFS searches the save directory AND the game folder under the
-- same names:
--
--   * a folder install, or a checkout -- `baseroms/` next to main.lua
--   * a packaged or fused build, where the game folder is inside an archive
--     and cannot be written to -- `baseroms/` in the save directory, whose
--     absolute path this reports on screen so it can be found
--
-- The file goes STRAIGHT IN THERE, with no revision subfolder under it. The
-- decompilation's own `make init` uses `baseroms/us/`, and the offline
-- pipeline under model_extract/ still reads from there because it shares that
-- tree -- but the instruction given to a player is "drop the file in this
-- folder", and one folder is the whole of it.
--
-- Any of `.z64`, `.n64` and `.v64` is accepted; StadiumRom normalises the
-- byte order on load.
--
-- ------- what "installed" means
--
-- A marker file next to the packs, holding the format magic, how many species
-- were written and the md5 of the ROM they came from. All three matter. The
-- magic catches a format change (the packs are rebuilt rather than read as
-- garbage), the count catches a build that was interrupted half way, and the
-- md5 catches the player swapping the ROM for a different revision.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local StadiumPack = V.require("StadiumPack")

local StadiumInstall = {}
local Compat = V.require("EngineCompat")

-- Where a ROM is looked for, and where the built packs are kept.
StadiumInstall.ROM_DIR = "baseroms"
StadiumInstall.DIR = StadiumPack.CACHE_DIR
StadiumInstall.MARKER = StadiumInstall.DIR .. "/pack.info"

-- Bumped whenever the .dsm format changes, so an old cache is rebuilt rather
-- than misread. Must track StadiumPack's magic.
StadiumInstall.FORMAT = "DSM7"

-- Bumped when the packs' CONTENT changes without the byte layout moving.
-- DSM7 keeps the DSM5/6 structural/material data and changes the extracted
-- CONTENT again so SetTileSize origin/window semantics are baked into UVs and
-- per-material texture variants.  FORMAT (not REV) changes because an older
-- pack cannot supply those discarded tile fields.
StadiumInstall.REV = 1

local function gameGeneration()
  local ok, GameVersion = pcall(require, "src.core.GameVersion")
  if ok and type(GameVersion) == "table" then
    if type(GameVersion.generation) == "function" then
      local okGen, gen = pcall(GameVersion.generation)
      if okGen and tonumber(gen) then return tonumber(gen) end
    end
    if type(GameVersion.isGen2) == "function" then
      local okGen2, yes = pcall(GameVersion.isGen2)
      if okGen2 and yes then return 2 end
    end
  end
  return 1
end

local function targetCount()
  return gameGeneration() == 2 and 251 or 151
end

StadiumInstall.gameGeneration = gameGeneration
StadiumInstall.targetCount = targetCount
StadiumInstall.COUNT = targetCount()

-- Named ROM files, then any ROM at all sitting in the folder.
--
-- Flat in `baseroms/`, with no revision subfolder: the offline pipeline under
-- model_extract/ keeps the decompilation's own `baseroms/us/` convention
-- because it shares that tree, but what is being asked of a PLAYER here is
-- "drop the file in this folder", and one folder is the whole of that
-- instruction. A path they have to build out of two parts is a path half of
-- them will get wrong, and the failure is silent -- the rungs are simply not
-- on the row.
local function namedRoms()
  local stem = (gameGeneration() == 2) and "stadium2" or "stadium"
  return {
    StadiumInstall.ROM_DIR .. "/" .. stem .. ".z64",
    StadiumInstall.ROM_DIR .. "/" .. stem .. ".n64",
    StadiumInstall.ROM_DIR .. "/" .. stem .. ".v64",
    StadiumInstall.ROM_DIR .. "/baserom.z64",
    StadiumInstall.ROM_DIR .. "/baserom.n64",
    StadiumInstall.ROM_DIR .. "/baserom.v64",
  }
end

local function fs()
  return Compat.fs()
end

local function isFile(path)
  local f = fs()
  if not (f and f.getInfo) then return false end
  local ok, info = pcall(f.getInfo, path, "file")
  return (ok and info) and true or false
end

-- The ROM's path on the PhysFS read path, or nil.
function StadiumInstall.romPath()
  local f = fs()
  if not f then return nil end
  for _, path in ipairs(namedRoms()) do
    if isFile(path) then return path end
  end
  local ok, items = pcall(f.getDirectoryItems, StadiumInstall.ROM_DIR)
  if ok and items then
    table.sort(items)
    for _, name in ipairs(items) do
      if name:lower():match("%.[nvz]64$") then
        local path = StadiumInstall.ROM_DIR .. "/" .. name
        if isFile(path) then return path end
      end
    end
  end
  return nil
end

function StadiumInstall.romPresent()
  return StadiumInstall.romPath() ~= nil
end

-- Where to tell the player to put it. The save directory is the answer that
-- is always writable, and it is the one a packaged build needs.
function StadiumInstall.romHint()
  local f = fs()
  local base = (f and f.getSaveDirectory and select(2, pcall(f.getSaveDirectory)))
  if type(base) ~= "string" then base = "the game folder" end
  return base .. "/" .. StadiumInstall.ROM_DIR
end

-- The same thing with a FILENAME on the end, which is what a player actually
-- needs: a folder alone leaves them guessing what to call the file, and the
-- guess is not obviously "baserom.z64".
--
-- Taken from the head of NAMED rather than retyped, so the name shown is by
-- construction the first name looked for. It is not the ONLY one that works
-- -- `.n64` and `.v64` are accepted, and so is any other name carrying one
-- of those extensions -- but an instruction that names one file is one a
-- player can follow, and an instruction that lists every possibility is one
-- they have to interpret.
function StadiumInstall.romHintFile()
  local paths = namedRoms()
  return StadiumInstall.romHint() .. "/" .. (paths[1]:match("[^/]+$") or "")
end

-- ------- the marker

local function readMarker()
  local f = fs()
  if not (f and isFile(StadiumInstall.MARKER)) then return nil end
  local ok, text = pcall(f.read, StadiumInstall.MARKER)
  if not (ok and type(text) == "string") then return nil end
  local format, count, md5, rev = text:match("^(%S+)%s+(%d+)%s*(%S*)%s*(%S*)")
  if not format then return nil end
  return { format = format, count = tonumber(count), md5 = md5,
           rev = tonumber(rev) }
end

-- Whether a complete, current set of packs is on disk.
local readyCache = nil

function StadiumInstall.ready()
  if readyCache ~= nil then return readyCache end
  local m = readMarker()
  local formatOk = m and m.format == StadiumInstall.FORMAT
    and m.rev == StadiumInstall.REV
  readyCache = (formatOk and m.count >= targetCount()) and true or false
  return readyCache
end

-- Whether there is work to do: something to build from, and nothing usable
-- yet.
function StadiumInstall.pending()
  if StadiumInstall.ready() then return false end
  return StadiumInstall.romPresent()
end

function StadiumInstall.forget()
  readyCache = nil
end

-- ------- building

local job = nil
local status = { state = "idle", done = 0, total = targetCount() }

StadiumInstall.status = status

local function writePack(species, bytes)
  local f = fs()
  if not f then return false, "no filesystem" end
  local ok, err = f.write(("%s/%03d.dsm"):format(StadiumInstall.DIR, species),
                          bytes)
  if not ok then return false, tostring(err) end
  return true
end

local function say(level, fmt, ...)
  local ok, Logger = pcall(require, "src.core.Logger")
  if ok and type(Logger) == "table" and type(Logger[level]) == "function" then
    Logger[level]("[STADIUM2_OVERWORLD_MODELS] " .. fmt, ...)
    return
  end
  local log = V and V.mod and V.mod.log
  if log and log[level] then pcall(log[level], log, fmt, ...) end
end
StadiumInstall.say = say

local function refuse(why)
  say("warn", "stadium build refused: %s", tostring(why))
  return false, why
end

-- Open the ROM found in `baseroms/` and start a stepped build. Returns false
-- plus a reason when there is nothing to build from.
function StadiumInstall.begin()
  local f = fs()
  if not f then return refuse("no filesystem") end
  local path = StadiumInstall.romPath()
  if not path then return refuse("no ROM in " .. StadiumInstall.ROM_DIR) end

  local okRead, bytes = pcall(f.read, path)
  if not (okRead and type(bytes) == "string") then
    return refuse("could not read " .. path)
  end
  return StadiumInstall.beginFrom(bytes, path)
end

-- The same, from bytes somebody else has already got hold of -- which is the
-- IMPORTED path (StadiumRomPick), where the file is at an absolute location
-- love.filesystem cannot see and was read with io.open.
function StadiumInstall.beginFrom(bytes, label)
  local f = fs()
  if not f then return refuse("no filesystem") end
  if type(bytes) ~= "string" or #bytes == 0 then return refuse("empty file") end

  local StadiumBuild = V.require("StadiumBuild")
  local gen = gameGeneration()
  local wanted = targetCount()
  StadiumInstall.COUNT = wanted
  status.total = wanted
  status.wrongVersion = false
  status.sourceGame = (gen == 2) and "Pokemon Stadium 2" or "Pokemon Stadium"

  local RomReader
  if gen == 2 then
    RomReader = V.require("StadiumRom2")
  else
    RomReader = V.require("StadiumRom")
  end

  local rom, err = RomReader.open(bytes)
  if not rom then
    if gen == 2 then
      return refuse("Gold/Silver needs a Pokemon Stadium 2 ROM: " .. tostring(err))
    end
    return refuse(tostring(err))
  end

  if not rom:isExpectedUS() then
    status.wrongVersion = true
    if gen == 2 then
      V.mod.log:warn("stadium2: %s is md5 %s -- canonical Pokemon Stadium 2 US "
                     .. "is md5 %s. The archive layout will still be validated "
                     .. "before a build is started.",
                     tostring(label or "the ROM"), tostring(rom:md5()),
                     tostring(RomReader.US_MD5))
    else
      V.mod.log:warn("stadium: %s is md5 %s -- the model offsets are keyed to "
                     .. "Pokemon Stadium (US) 1.0, which is md5 %s. Building "
                     .. "anyway, but the models may be wrong or fail to build.",
                     tostring(label or "the ROM"), tostring(rom:md5()),
                     tostring(RomReader.US_MD5))
    end
  end

  local models = rom:modelCount()
  if not (models and models >= wanted) then
    if gen == 2 then
      return refuse(("model archive holds %s entries; %d are needed")
        :format(tostring(models), wanted))
    end
    return refuse("needs Pokemon Stadium US 1.0")
  end

  pcall(f.createDirectory, StadiumInstall.DIR)
  job = StadiumBuild.job(rom, writePack, wanted)
  job.md5 = rom:md5()
  job.sourceGame = status.sourceGame
  status.state = "building"
  status.done = 0
  status.total = job.total
  status.error = nil
  say("info", "stadium build started: %d models from %s (md5 %s)",
      job.total or 0, tostring(label or "?"), tostring(job.md5))
  return true
end

-- One species. Returns true while there is more to do.
function StadiumInstall.step()
  if not job then return false end
  local okStep, more = pcall(job.step, job)
  if not okStep then
    status.state = "failed"
    status.error = tostring(more)
    say("error", "stadium build step threw: %s", tostring(more))
    job = nil
    return false
  end
  status.done = job.done
  status.species = job.species
  StadiumInstall._ticks = (StadiumInstall._ticks or 0) + 1
  local done = tonumber(job.done) or 0
  if StadiumInstall._ticks <= 3 or done % 50 == 0 then
    if StadiumInstall._lastSaid ~= done or StadiumInstall._ticks <= 3 then
      StadiumInstall._lastSaid = done
      say("info", "stadium build: %d/%d (%s) after %d steps",
          done, tonumber(job.total) or 0, tostring(job.species or "?"),
          StadiumInstall._ticks)
    end
  end
  if StadiumInstall._ticks == 240 and done == 0 then
    say("error", "stadium build has run 240 steps without writing a model"
        .. " -- the archive is being read but nothing is decoding")
  end
  if job.error then
    status.state = "failed"
    status.error = job.error
    say("error", "stadium build failed at %d/%d: %s",
        done, tonumber(job.total) or 0, tostring(job.error))
    job = nil
    return false
  end
  if not more then
    local f = fs()
    local wrote = #job.failed == 0 and job.total > 0
    if wrote then
      pcall(f.write, StadiumInstall.MARKER,
            ("%s %d %s %d\n"):format(StadiumInstall.FORMAT, job.total,
                                     tostring(job.md5 or ""),
                                     StadiumInstall.REV))
      readyCache = nil
      StadiumPack.forget()
    end
    if not wrote then
      status.state = "failed"
      if #job.failed >= job.total then
        if gameGeneration() == 2 then
          status.error = "needs a compatible Pokemon Stadium 2 ROM / GS model+animation archives"
        else
          status.error = "needs Pokemon Stadium US 1.0"
        end
      else
        status.error = ("%d of %d models could not be built")
                       :format(#job.failed, job.total)
      end
    else
      status.state = "done"
    end
    job = nil
    return false
  end
  return true
end

function StadiumInstall.cancel()
  job = nil
  status.state = "idle"
end

return StadiumInstall
