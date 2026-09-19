-- Replaces a direct edit that used to live inside src/core/SaveData.lua's
-- own scrubKnownMon (engine tree, now reverted to stock) -- clamps the
-- modern ivs/evs/dynamaxLevel fields ModernStats.lua introduces on every
-- mon in a loaded save, and calls ModernStats.ensure so a legacy save's
-- mons get real Sp.Atk/Sp.Def/IVs/EVs derived once, saved from then on --
-- not just a transient in-memory view for whichever mon a screen happens
-- to open.
--
-- SaveData.validate(save, data) (src/core/SaveData.lua:1322, confirmed via
-- direct read, the ONLY call site is Game.lua:1095, once per load) already
-- walks save.party, every save.boxes[*], and save.daycare.mon through its
-- own scrubMonList/scrubKnownMon -- reclaiming orphaned mons, clamping
-- legacy dvs/statExp, calling Stats.ensure. This file does NOT reimplement
-- any of that (still fully native, untouched): it wraps SaveData.validate,
-- calls the real one first, then walks the SAME three locations again
-- doing only the modern-fields half that used to be inlined into
-- scrubKnownMon directly.
return function(mod)
  local SaveData = require("src.core.SaveData")
  local ModernStats = mod.exports.ModernStats

  if SaveData.galarSaveScrubHook then return end
  SaveData.galarSaveScrubHook = true

  local function clamp(n, lo, hi, fallback)
    if type(n) ~= "number" then return fallback end
    if n < lo then return lo end
    if n > hi then return hi end
    return n
  end

  -- evs gets a second pass after the per-stat clamp for the 510 total cap
  -- (fixed key order so the result is deterministic, not iteration-order
  -- dependent): anything past the remaining budget is clamped down rather
  -- than left to smuggle in a stat total no legitimate mon could reach.
  local EV_ORDER = { "hp", "atk", "def", "spa", "spd", "spe" }

  local function scrubModernFields(mon, data)
    if type(mon) ~= "table" then return end
    if type(mon.ivs) == "table" then
      for stat, v in pairs(mon.ivs) do mon.ivs[stat] = clamp(v, 0, 31, 0) end
    end
    if type(mon.evs) == "table" then
      local remaining = 510
      for _, stat in ipairs(EV_ORDER) do
        local v = mon.evs[stat]
        if v ~= nil then
          v = clamp(v, 0, 252, 0)
          v = math.min(v, remaining)
          mon.evs[stat] = v
          remaining = remaining - v
        end
      end
    end
    if mon.dynamaxLevel ~= nil then
      mon.dynamaxLevel = clamp(mon.dynamaxLevel, 0, 10, 0)
    end
    -- Runs after SaveData's own Stats.ensure (already ran inside the real
    -- validate() call above -- mon.stats exists) and after the dvs/statExp
    -- clamp above (a legacy mon's modern fields derive FROM those).
    ModernStats.ensure(data.pokemon and data.pokemon[mon.species], mon)
  end

  local function scrubSave(save, data)
    for _, mon in ipairs(save.party or {}) do scrubModernFields(mon, data) end
    for _, box in ipairs(save.boxes or {}) do
      for _, mon in ipairs(box) do scrubModernFields(mon, data) end
    end
    local daycare = save.daycare
    if type(daycare) == "table" and type(daycare.mon) == "table" then
      scrubModernFields(daycare.mon, data)
    end
  end

  local vanillaValidate = SaveData.validate
  function SaveData.validate(save, data)
    local report = vanillaValidate(save, data)
    local ok, err = pcall(scrubSave, save, data)
    if not ok then
      mod.log:warn("galar_gmax_dex: save_scrub: errored: %s", tostring(err))
    end
    return report
  end

  mod.log:info("galar_gmax_dex: save_scrub installed (modern-fields clamp, engine tree untouched)")
end
