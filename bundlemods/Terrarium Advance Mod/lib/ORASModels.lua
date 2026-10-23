-- ORAS MODELS: Pokemon 3D models built from the player's own decrypted Omega
-- Ruby / Alpha Sapphire dump, for every species 1-721.
--
-- The mod ships no 3DS data.  The dump is a launcher import (manifest.json
-- `required_imports`, id "pokemon_oras", file pokemon_oras.3ds), supplied
-- from the MODS panel's IMPORT button the same way the Colosseum disc is, and
-- read in bounded slices (lib/N3DSRom.lua) -- a cartridge image is ~2 GB.
--
-- STAGE 1 (this file today): the OPTIONS row runs lib/ORASProbe.lua, which
-- reports which GARC holds the models and how a species' members are laid
-- out (mod.cache "oras/probe.txt").  The decoder that follows -- GFModel
-- geometry, PICA textures, idle/attack/hit/faint motions baked to the
-- morph-frame cache PokemonActors already draws -- is written against that
-- report, not against guessed offsets.

local V = ...
local mod = V and V.mod

local M = { ID = "oras_models", LABEL = "ORAS MODELS" }

M.IMPORT_ID = "pokemon_oras"

local st = { state = "idle", summary = nil, error = nil }   -- idle | done | error
M.status = st

local function log(level, fmt, ...)
  local l = mod and mod.log
  if l and type(l[level]) == "function" then pcall(l[level], l, fmt, ...) end
end

function M.imported()
  local imports = mod and mod.imports
  if not imports then return false end
  local ok, info = pcall(imports.info, imports, M.IMPORT_ID)
  return ok and type(info) == "table" and info.ready ~= false
end

-- Synchronous: a few hundred small reads plus a handful of inflates.  It runs
-- from an OPTIONS-menu press, so the frame it holds is a menu frame.
function M.probe()
  -- the archive survey (ORASProbe.run) found a/0/0/8, the model probe
  -- (ORASProbe.models) its layout and the anatomy probe its structs; this
  -- press decodes one form and exports it as OBJ + PNG for a visual check
  local ok, result, err = pcall(function()
    return V.require("ORASProbe").export(mod)
  end)
  if not ok or not result then
    st.state, st.error = "error", tostring(ok and err or result)
    log("warn", "ORAS probe failed: %s", st.error)
    return false
  end
  st.state, st.summary, st.error = "done", result.summary, nil
  log("info", "ORAS probe: %s%s", result.summary,
      result.saved and " (report in mod cache oras/export.txt)" or "")
  -- the report is the deliverable of this stage; the log gets it too, so it
  -- reaches a player who cannot open the cache folder
  for line in result.text:gmatch("[^\n]+") do log("info", "%s", line) end
  return true
end

-- BUILD: National Dex 1-151 (Gen 1) into PokemonActors caches
-- (lib/ORASActorCache.lua) -- the same cache every 3D-actor surface reads, so
-- they appear in battles, as followers and in the overworld like Colosseum's.
--
-- A BACKGROUND JOB: the build runs in a coroutine that M.pump() resumes once a
-- frame (main.lua's update tick), and ORASActorCache yields at its stage
-- checkpoints once FRAME_BUDGET seconds of the frame are used -- the game
-- keeps running, with a hitch on the heaviest single steps (inflating a
-- texture set).  The row shows progress; species already built in the
-- current format are skipped, so pressing it again only does what is left.
M.BUILD_DEX = {}
for dex = 1, 151 do M.BUILD_DEX[dex] = dex end
local FRAME_BUDGET = 0.012

local job = nil      -- { co, done, total, lines, startedAt }

local function now()
  return (love and love.timer and love.timer.getTime and love.timer.getTime()) or os.clock()
end

function M.running() return job ~= nil end

function M.startBuild(list)
  if job then return false end
  list = list or M.BUILD_DEX
  local Cache = V.require("ORASActorCache")
  local lines = {}
  job = { done = 0, total = #list, lines = lines, startedAt = now(), frameStart = now() }
  st.state, st.error, st.summary = "building", nil, nil
  job.co = coroutine.create(function()
    return Cache.build(mod, list, function(fmt, ...)
      local line = string.format(fmt, ...)
      lines[#lines + 1] = line
      log("info", "%s", line)
    end, function(done, total)
      job.done, job.total = done, total
    end)
  end)
  Cache.checkpoint = function()
    if job and coroutine.running() == job.co and now() - job.frameStart > FRAME_BUDGET then
      coroutine.yield()
    end
  end
  log("info", "ORAS MODELS: building %d species in the background", #list)
  return true
end

local function finish(ok, built, failed, err, skipped)
  local Cache = V.require("ORASActorCache")
  Cache.checkpoint = nil
  local lines = job and job.lines or {}
  local seconds = job and (now() - job.startedAt) or 0
  job = nil
  if not ok then
    st.state, st.error = "error", tostring(built)
    log("warn", "ORAS build failed: %s", st.error)
    return
  end
  if err then log("warn", "ORAS build: %s", tostring(err)) end
  st.state = ((built or 0) + (skipped or 0)) > 0 and "done" or "error"
  st.summary = string.format("%d built, %d skipped, %d failed in %.0fs",
                             built or 0, skipped or 0, failed or 0, seconds)
  st.error = err
  log("info", "ORAS MODELS: %s -- restart the game so every part of the mod picks them up", st.summary)
  if mod and mod.cache then pcall(mod.cache.write, mod.cache, "oras/build.txt", table.concat(lines, "\n") .. "\n") end
end

-- once a frame (main.lua)
function M.pump()
  if not job then return end
  job.frameStart = now()
  local ok, built, failed, err, skipped = coroutine.resume(job.co)
  if not ok then return finish(false, built) end
  if coroutine.status(job.co) == "dead" then finish(true, built, failed, err, skipped) end
end

-- kept for the earlier test flow: a synchronous build of a short list
function M.buildTest(list)
  M.startBuild(list or { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 })
  while job do M.pump() end
end

function M.row()
  return {
    id = M.ID,
    label = M.LABEL,
    value = function()
      if job then return string.format("BUILDING %d/%d", job.done, job.total) end
      if st.state == "error" then return "ERROR" end
      if st.state == "done" then return "BUILT 1-151" end
      return M.imported() and "BUILD 1-151" or "NO DUMP"
    end,
    step = function()
      if job then return true end
      if not M.imported() then
        log("info", "ORAS MODELS: import a decrypted Omega Ruby / Alpha Sapphire .3ds from the MODS panel first")
        return true
      end
      M.startBuild()
      return true
    end,
  }
end

return M
