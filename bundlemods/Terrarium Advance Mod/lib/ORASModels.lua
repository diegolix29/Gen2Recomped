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

-- BUILD: every species ORAS has, National Dex 1-721, into PokemonActors caches
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
for dex = 1, 721 do M.BUILD_DEX[dex] = dex end
local FRAME_BUDGET = 0.012

local job = nil      -- { co, done, total, lines, startedAt }
local packJob = nil  -- { A, started, startedAt } -- the PACK stage after a build

local function now()
  return (love and love.timer and love.timer.getTime and love.timer.getTime()) or os.clock()
end

function M.running() return job ~= nil or packJob ~= nil end

-- PACK stage.  After a build, ORAS MODELS packs oras/pokemon into
-- cbe_cache_archive/oras (lib/CacheArchive.lua, kind "oras": one unit per
-- species, ~3.5 GiB of loose files -> ~1.9 GiB in 721 files).  It is driven
-- from here, not from the Colosseum PACK CACHE menu: a player may have the
-- ORAS dump and no Colosseum disc.  The archive module is shared (one job at
-- a time), its ORAS folder, index and marker are not.
local function archive()
  local A = mod and mod.exports and mod.exports.cacheArchive
  if A then return A end
  -- nothing has loaded it (no Colosseum runtime, and no ORAS runtime yet
  -- because this is the first build): load it like main.lua does
  local okS, src = pcall(function() return mod:read("lib/CacheArchive.lua") end)
  local chunk = okS and type(src) == "string" and load(src, "@lib/CacheArchive.lua")
  if not chunk then return nil end
  local okW, WorkBudget = pcall(V.require, "WorkBudget")
  local okA, arch = pcall(chunk, { mod = mod, WorkBudget = okW and WorkBudget or nil })
  if not (okA and type(arch) == "table") then return nil end
  if mod.exports then mod.exports.cacheArchive = arch end
  return arch
end

local PACK_BUDGET_MS = 12
M.autoPack = true   -- false: build only, leave the files loose

local function startPack()
  local A = archive()
  if not (A and A.beginPack) then
    log("warn", "ORAS MODELS: cache packing unavailable (lib/CacheArchive.lua did not load); models stay loose")
    return false
  end
  packJob = { A = A, started = false, startedAt = now() }
  st.state = "packing"
  return true
end
M.startPack = startPack

local function pumpPack()
  local A = packJob.A
  if not packJob.started then
    -- another pack job (Colosseum auto-pack) holds the archive: drive it to
    -- its end, then start ours
    if A.running and A.running() then A.pump(PACK_BUDGET_MS); return end
    local ok, why = A.beginPack("oras")
    if not ok then
      packJob = nil
      st.state, st.error = "error", "pack: " .. tostring(why)
      log("warn", "ORAS MODELS: packing could not start: %s", tostring(why))
      return
    end
    packJob.started = true
    log("info", "ORAS MODELS: packing the ORAS cache in the background")
    return
  end
  local state, err = A.pump(PACK_BUDGET_MS)
  if state == "working" then return end
  local seconds = now() - packJob.startedAt
  packJob = nil
  M._packStatusStale = true
  if state == "error" then
    st.state, st.error = "error", "pack: " .. tostring(err)
    log("warn", "ORAS MODELS: packing failed (loose files kept): %s", tostring(err))
    return
  end
  local s = A.status and A.status() or {}
  st.state = "packed"
  log("info", "ORAS MODELS: packed in %.0fs -- %s of models in %s (cbe_cache_archive/oras)",
      seconds, tostring(s.orasOriginalLabel), tostring(s.orasArchiveLabel))
end

-- status() lists the archive folders: the menu row asks every frame, so the
-- answer is kept for a second
local packStatusMemo, packStatusAt = nil, -1
function M.packStatus()
  local t = now()
  if packStatusMemo and not packJob and not M._packStatusStale and t - packStatusAt < 1 then return packStatusMemo end
  M._packStatusStale = nil
  local A = archive()
  local okS, s = pcall(function() return A and A.status and A.status() or nil end)
  s = okS and s or nil
  packStatusMemo = s and { packed = s.orasPacked, entries = s.orasEntries, original = s.orasOriginalLabel, archive = s.orasArchiveLabel,
                           running = packJob ~= nil } or { running = packJob ~= nil }
  packStatusAt = t
  return packStatusMemo
end

function M.startBuild(list)
  if job then return false end
  list = list or M.BUILD_DEX
  local Cache = V.require("ORASActorCache")
  local lines = {}
  job = { done = 0, total = #list, lines = lines, startedAt = now(), frameStart = now() }
  st.state, st.error, st.summary = "building", nil, nil
  -- Every species line goes to oras/build.txt.  The game log drops a line
  -- shape after 20 repeats (src/core/Logger.lua ignores the numbers), so it
  -- only gets failures and a progress line every 50 species.
  local failures = 0
  job.co = coroutine.create(function()
    return Cache.build(mod, list, function(fmt, ...)
      local line = string.format(fmt, ...)
      lines[#lines + 1] = line
      if line:find("fail", 1, true) or line:find("FAIL", 1, true) then
        failures = failures + 1
        log("warn", "%s", line)
      end
    end, function(done, total)
      job.done, job.total = done, total
      if done % 50 == 0 or done == total then
        log("info", "ORAS MODELS: %d / %d species (%d problems so far)", done, total, failures)
      end
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
  log("info", "ORAS MODELS: %s -- restart the game so every part of the mod picks them up (per-species lines: modstorage/DRAMATIC_SHAPE/oras/build.txt.bin)", st.summary)
  if mod and mod.cache then pcall(mod.cache.write, mod.cache, "oras/build.txt", table.concat(lines, "\n") .. "\n") end
  -- packing is its own row (ORAS PACK); once the player has packed, species
  -- built later are packed right after the build so the install stays packed
  if st.state == "done" and M.autoPack ~= false then
    local s = M.packStatus()
    if s.packed then startPack() end
  end
end

-- once a frame (main.lua)
function M.pump()
  if packJob then return pumpPack() end
  if not job then return end
  job.frameStart = now()
  local ok, built, failed, err, skipped = coroutine.resume(job.co)
  if not ok then return finish(false, built) end
  if coroutine.status(job.co) == "dead" then finish(true, built, failed, err, skipped) end
end

-- kept for the earlier test flow: a synchronous build of a short list
function M.buildTest(list)
  M.startBuild(list or { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 })
  while job or packJob do M.pump() end
end

function M.row()
  return {
    id = M.ID,
    label = M.LABEL,
    value = function()
      if job then return string.format("BUILDING %d/%d", job.done, job.total) end
      if packJob then return "PACKING" end
      if st.state == "error" then return "ERROR" end
      if st.state == "packed" then return "BUILT + PACKED" end
      if st.state == "done" then return "BUILT 1-721" end
      return M.imported() and "BUILD 1-721" or "NO DUMP"
    end,
    step = function()
      if job or packJob then return true end
      if not M.imported() then
        log("info", "ORAS MODELS: import a decrypted Omega Ruby / Alpha Sapphire .3ds from the MODS panel first")
        return true
      end
      M.startBuild()
      return true
    end,
  }
end

-- ORAS PACK: the row under ORAS MODELS.  Packs every loose ORAS model file
-- into cbe_cache_archive/oras (one file per species) and drops the old
-- unpaged banks; pressing it again packs whatever is loose.
function M.packRow()
  local function built()
    local okR, src = pcall(function() return mod.cache:read("oras/pokemon/index.lua") end)
    return okR and type(src) == "string" and src:find("%d") ~= nil
  end
  return {
    id = "oras_pack",
    label = "ORAS PACK",
    value = function()
      if packJob then
        local A = packJob.A
        local label = A and A.stage and A.stage()
        return packJob.started and tostring(label or "PACKING"):gsub("^PACK ORAS ", "") or "WAITING"
      end
      if job then return "AFTER BUILD" end
      if st.state == "error" and tostring(st.error or ""):find("^pack:") then return "ERROR" end
      local s = M.packStatus()
      if s.packed then return "PACKED " .. tostring(s.archive or "") end
      return built() and "LOOSE FILES" or "BUILD FIRST"
    end,
    step = function()
      if job or packJob then return true end
      if not built() then
        log("info", "ORAS PACK: build the models first (ORAS MODELS)")
        return true
      end
      startPack()
      return true
    end,
  }
end

return M
