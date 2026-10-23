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

-- TEST BATCH: National Dex 1-20 built into PokemonActors caches
-- (lib/ORASActorCache.lua) -- the same cache every 3D-actor surface reads, so
-- they appear in battles, as followers and in the overworld like Colosseum's.
-- Synchronous for now: about ten seconds per species of pure-Lua inflate and
-- decode on the options menu.  The full 1-721 install becomes a background job.
M.TEST_DEX = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20 }

function M.buildTest()
  local lines = {}
  local ok, built, failed, err = pcall(function()
    return V.require("ORASActorCache").build(mod, M.TEST_DEX, function(fmt, ...)
      local line = string.format(fmt, ...)
      lines[#lines + 1] = line
      log("info", "%s", line)
    end)
  end)
  if not ok then
    st.state, st.error = "error", tostring(built)
    log("warn", "ORAS build failed: %s", st.error)
    return false
  end
  if err then log("warn", "ORAS build: %s", tostring(err)) end
  st.state = (built or 0) > 0 and "done" or "error"
  st.summary = string.format("%d built, %d failed", built or 0, failed or 0)
  st.error = err
  log("info", "ORAS MODELS test batch: %s", st.summary)
  if mod and mod.cache then pcall(mod.cache.write, mod.cache, "oras/build.txt", table.concat(lines, "\n") .. "\n") end
  return true
end

function M.row()
  return {
    id = M.ID,
    label = M.LABEL,
    value = function()
      if st.state == "error" then return "ERROR" end
      if st.state == "done" then return "BUILT 1-20" end
      return M.imported() and "BUILD 1-20" or "NO DUMP"
    end,
    step = function()
      if not M.imported() then
        log("info", "ORAS MODELS: import a decrypted Omega Ruby / Alpha Sapphire .3ds from the MODS panel first")
        return true
      end
      M.buildTest()
      return true
    end,
  }
end

return M
