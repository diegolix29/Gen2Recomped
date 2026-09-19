-- Confirmed real, previously-unfixed bug: national_dex never sets baseExp
-- on any species it registers -- grepped its whole src/ tree, zero hits
-- for base_experience/baseExperience/baseExp anywhere, including its own
-- extras data. src/battle/Experience.lua:38,46 (`base = floor(defeatedDef
-- .baseExp / participants) ... return math.max(1, exp)`) floors the WHOLE
-- formula to exactly 1 EXP whenever baseExp is 0/nil -- this is the
-- confirmed mechanism behind the "always 1 EXP" report.
--
-- Real data source, user-supplied this session (Pokemon_Stats/pokemon.txt
-- + pokemon_forms.txt, real PBS-format reference data -- NOT the same
-- thing as the approximation this file originally shipped with):
-- stats/base_exp_data.lua, generated offline by tools/parse_base_exp.ps1
-- (see that script's own comments for the exact parsing/tiered-form-
-- resolution rules) -- 1025 base species direct from pokemon.txt's own
-- BaseExp field, plus 92 hand-verified alternate forms (Mega evolutions
-- pattern-matched, a small set of well-known non-Mega multi-form species
-- hand-mapped from confirmed real ids). This REPLACES the BST-derived
-- approximation as the primary source -- that formula is kept ONLY as a
-- genuine last resort for any id neither this data file nor national_dex
-- covers, not silently removed (still real, still logged separately from
-- the real-data path so the two are never confused in the log line).
--
-- Follows the exact same reapply pattern already established for sprites/
-- learnsets (reapplySpritePacks/reapplyLearnsets, main.lua/
-- learnset_ownership.lua) -- explicit user instruction: "we need a
-- reapply stats too", same save.loaded + mod.options_changed re-sync
-- points, for the same reason (national_dex's own data can change after
-- this mod's very first pass, and a single launch-time-only patch would
-- never pick that up).
return function(mod, realBaseExp)
  local nd = mod.find and mod.find("national_dex")
  local ndExports = nd and nd.exports
  if not (ndExports and ndExports.listSpecies) then
    mod.log:warn("galar_gmax_dex: reapply_national_dex_stats: national_dex not available, baseExp left untouched")
    return { reapplyStats = function() end }
  end

  -- Genuine last resort only: real per-species data covers 1117 ids
  -- (1025 base + 92 forms) -- this formula only ever fires for something
  -- outside that set (a species this reference data doesn't carry at
  -- all). Same BST-correlation reasoning/tuning as before: coefficient
  -- 0.4, clamped to {30, 300}, checked against real reference points
  -- (Caterpie BST195/real39, Pikachu BST320/real112, Charizard BST534/
  -- real240, Mewtwo BST680/real306) -- an approximation, not sourced
  -- data, and logged as a visibly separate count from the real-data path.
  local BST_COEFFICIENT = 0.4
  local MIN_BASE_EXP, MAX_BASE_EXP = 30, 300
  local function approximateBaseExp(baseStats)
    if type(baseStats) ~= "table" then return nil end
    local total = 0
    for _, v in pairs(baseStats) do
      if type(v) == "number" then total = total + v end
    end
    if total <= 0 then return nil end
    local exp = math.floor(total * BST_COEFFICIENT + 0.5)
    return math.max(MIN_BASE_EXP, math.min(MAX_BASE_EXP, exp))
  end

  local patchedReal, patchedApprox, skipped = 0, 0, 0
  local function reapplyStats()
    patchedReal, patchedApprox, skipped = 0, 0, 0
    local ok, roster = pcall(ndExports.listSpecies)
    if not (ok and roster) then
      mod.log:warn("galar_gmax_dex: reapply_national_dex_stats: national_dex.listSpecies() unavailable, baseExp unchanged")
      return
    end
    for _, entry in ipairs(roster) do
      local id = entry.id
      local current = id and mod.content.pokemon:get(id)
      if current and (not current.baseExp or current.baseExp <= 0) then
        local real = realBaseExp and realBaseExp[id]
        if real then
          mod.content.pokemon:patch(id, { baseExp = real })
          patchedReal = patchedReal + 1
        else
          local approx = approximateBaseExp(current.baseStats)
          if approx then
            mod.content.pokemon:patch(id, { baseExp = approx })
            patchedApprox = patchedApprox + 1
          else
            skipped = skipped + 1
          end
        end
      end
    end
    mod.log:info(
      "galar_gmax_dex: reapply_national_dex_stats: %d species patched with REAL baseExp data, %d with a BST-derived approximation (no real data available for those), %d left unresolved",
      patchedReal, patchedApprox, skipped)
  end

  mod.exports.reapplyNationalDexStats = reapplyStats
  reapplyStats()
  mod.events:on("save.loaded", reapplyStats)
  mod.events:on("mod.options_changed", reapplyStats)

  return { reapplyStats = reapplyStats }
end
