-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- IDS WHERE THE ENGINE WANTS NAMES -- the check for a bug that has now
-- shipped FOUR TIMES in four different fields.
--
--   * `move.effect`   a number where `BattleState:effectRecord` dispatched on
--                     a name. Every non-damaging Sinnoh move said "But, it
--                     failed!".  [[gen4_move_effects]]
--   * `move.type`     a number where `Damage` wanted one. Every move typeless.
--                     [[gen4_type_system]]
--   * `species.abilities`  ids where `battle/Abilities.lua` compares against
--                     names. NO ABILITY DID ANYTHING IN SINNOH AT ALL.
--                     [[gen4_abilities]]
--   * `item.holdEffect`  a number where `battle/HoldItems.lua` compares
--                     against "LEFTOVERS", "CHOICE_BAND" and twelve more.
--
-- EACH SEARCH FOUND ONLY THE FIELD IT WAS LOOKING AT.  The pattern is
-- structural rather than unlucky: the DS stores enums as ids, this engine grew
-- up on Game Boy datasets that store names, and the Gen 4 importer transcribes
-- the byte. So this stops being a thing anyone has to notice.
--
-- HOW IT DECIDES, and why it needs no knowledge of the engine at all.
--
-- pokeplatinum's `res/` files describe the SAME RECORDS the cartridge does,
-- and they spell every enum as a NAME: `"holdEffect": "HOLD_EFFECT_CHOICE_ATK"`,
-- `"abilities": ["ABILITY_BLAZE", "ABILITY_NONE"]`. So for each field, compare
-- what the CACHE holds against what POKEPLATINUM holds:
--
--     numeric in the cache + named in pokeplatinum  ->  an unresolved id
--
-- No source scanning, no heuristics about which tables are keyed by string,
-- and nothing to keep in step with the engine.
--
-- THE CONTROL.  `abilities` is in the expected list below and the check must
-- find it, on any cache written before the `Gen4Abilities` stage. A run that
-- reports nothing on such a cache has a broken reader, not a clean port --
-- and this check's FIRST version proved it: it only classified scalars, so it
-- walked straight past `abilities` (a LIST of ids) and reported eight fields
-- when there were eleven. A check that misses the bug you already know about
-- is worth nothing against the one you do not.
--
-- WHAT THIS IS NOT.  It does not say a field is BROKEN -- only that it is an
-- id the cartridge's own decompilation gives a name to. Some are deliberate
-- (see EXEMPT). Deciding is the reader's job; noticing is this file's.
--
--   texlua tools/gen4_idname_check.lua <platinum cache>/data/generated <pokeplatinum dir>

local dataDir = arg[1]
local ppDir = arg[2]
if not (dataDir and ppDir) then
  print("usage: gen4_idname_check.lua <cache data/generated> <pokeplatinum dir>")
  os.exit(2)
end

local function slurp(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local d = f:read("*a"); f:close(); return d
end

-- The three record tables, and where pokeplatinum keeps the same records.
local TABLES = {
  { name = "pokemon", cache = "pokemon.lua", glob = "res/pokemon/*/data.json" },
  { name = "moves",   cache = "moves.lua",   glob = "res/moves/*/data.json" },
  { name = "items",   cache = "items.lua",   glob = "res/items/data/*.json" },
}

-- FIELDS THAT ARE IDS ON PURPOSE, each with the reason.  An exemption is a
-- claim someone has to stand behind, so it carries one.
local EXEMPT = {
  flags = "a BITMASK, not an enum -- pokeplatinum lists the set bits by name "
       .. "and the engine tests bits. Both are right.",
  id = "the record's own index.",
}

-- WHAT THIS CHECK IS KNOWN TO FIND, so a NEW one is a failure rather than
-- another line in a list nobody reads.  `abilities` is the control and is
-- expected on any cache older than the Gen4Abilities stage.
local KNOWN = {
  effect = "DELIBERATE, and PARTIAL -- 59 of 471 moves. [[gen4_move_effects]]: "
        .. "the 412 ids with a pret name carry it, and the 59 Sinnoh-only ids "
        .. "with none are LEFT AS NUMBERS on purpose, which is Hoenn's own "
        .. "policy -- a number logs itself once through `missing()` rather "
        .. "than pretending to be a plain hit. If this count RISES, the effect "
        .. "table has regressed.",
  abilities = "FIXED in pass 106 (Gen4Abilities). Expected on an older cache; "
           .. "its absence on a fresh one is the fix landing.",
  holdEffect = "FIXED in pass 109 (Gen4HoldEffects). Expected on a cache older "
            .. "than that stage; its absence on a fresh one is the fix landing. "
            .. "battle/HoldItems.lua compares against 33 names and 158 of 446 "
            .. "items carry a non-zero hold effect.",
  battlePocket = "OPEN, low: the engine sorts the bag by the STRING `pocket`.",
  fieldPocket = "OPEN, low: as battlePocket.",
  battleUseCategory = "OPEN: no engine consumer yet.",
  fieldUseFunc = "OPEN: no engine consumer yet.",
  flingEffect = "OPEN: Fling is not implemented.",
  pluckEffect = "OPEN: Pluck/Bug Bite berry effects are not implemented.",
  naturalGiftType = "OPEN: Natural Gift is not implemented. A TYPE id, which "
                 .. "is the field that has already gone wrong once.",
  range = "OPEN: the move's target. The engine picks targets its own way; "
       .. "worth settling whether that agrees with the cartridge.",
}

-- A value's kind, from its Lua source text.  This is a CLASSIFIER, not a
-- parser: it only has to tell a number from a name.
local function cacheKind(v)
  if v == nil then return nil end
  if v:sub(1, 1) == '"' then return "string" end
  if v == "true" or v == "false" then return "bool" end
  if v:match("^%-?[%d%.]+$") then return "number" end
  if v:sub(1, 1) == "{" then
    if v:find('"') then return "list-of-strings" end
    if v:find("%d") then return "list-of-numbers" end
    return "table"
  end
  return "other"
end

local function jsonKind(v)
  v = v:gsub("^%s+", ""):gsub("%s+$", "")
  if v:sub(1, 1) == '"' then return "string" end
  if v == "true" or v == "false" then return "bool" end
  if v:match("^%-?[%d%.]+$") then return "number" end
  if v:sub(1, 1) == "[" then
    if v:find('"') then return "list-of-strings" end
    if v:find("%d") then return "list-of-numbers" end
    return "list"
  end
  return "other"
end

local NAMEY = { string = true, ["list-of-strings"] = true }
local NUMERIC = { number = true, ["list-of-numbers"] = true }

-- Every `field = value` at the top level of a record in a cache file.
local function cacheFieldKinds(text)
  local counts = {}
  for body in text:gmatch("__t%[[^%]]+%] = %{(.-)\n  %}") do
    for field, value in body:gmatch("\n    ([%w_]+) = ([^\n]+)") do
      value = value:gsub(",%s*$", "")
      local kind = cacheKind(value)
      -- a multi-line table opens with "{" and nothing after it; look ahead
      if value == "{" then
        local block = body:match("\n    " .. field .. " = %{(.-)\n    %}")
        kind = block and cacheKind("{" .. block .. "}") or "table"
      end
      counts[field] = counts[field] or {}
      counts[field][kind] = (counts[field][kind] or 0) + 1
    end
  end
  return counts
end

local function jsonFieldKinds(text, counts)
  -- top-level "field": value, with arrays kept whole
  for field, value in text:gmatch('"([%w_]+)"%s*:%s*(%b[])') do
    counts[field] = counts[field] or {}
    local k = jsonKind(value)
    counts[field][k] = (counts[field][k] or 0) + 1
  end
  for field, value in text:gmatch('"([%w_]+)"%s*:%s*("[^"]*")') do
    counts[field] = counts[field] or {}
    counts[field].string = (counts[field].string or 0) + 1
  end
  for field, value in text:gmatch('"([%w_]+)"%s*:%s*(%-?[%d%.]+)') do
    counts[field] = counts[field] or {}
    counts[field].number = (counts[field].number or 0) + 1
  end
  return counts
end

local function listFiles(pattern)
  local out = {}
  local cmd = ("ls %s/%s 2>/dev/null"):format(ppDir, pattern)
  local p = io.popen(cmd)
  if not p then return out end
  for line in p:lines() do out[#out + 1] = line end
  p:close()
  return out
end

local checks, failures, found = 0, 0, {}
local function ok(cond, what)
  checks = checks + 1
  if not cond then
    failures = failures + 1
    print("  FAIL  " .. what)
  end
  return cond
end

print("gen4 id/name check")
print(("  cache        %s"):format(dataDir))
print(("  pokeplatinum %s"):format(ppDir))
print("")

for _, t in ipairs(TABLES) do
  local text = slurp(dataDir .. "/" .. t.cache)
  if not text then
    print(("%-8s  SKIPPED -- no %s"):format(t.name, t.cache))
  else
    local cache = cacheFieldKinds(text)
    local pp, files = {}, listFiles(t.glob)
    for _, f in ipairs(files) do
      local j = slurp(f)
      if j then jsonFieldKinds(j, pp) end
    end
    ok(#files > 0, ("%s: found no pokeplatinum files at %s -- this check "):format(t.name, t.glob)
       .. "cannot fail without them")
    local names = {}
    for field in pairs(cache) do names[#names + 1] = field end
    table.sort(names)
    print(("%-8s  %d fields in the cache, %d pokeplatinum files"):format(
      t.name, #names, #files))
    for _, field in ipairs(names) do
      local numeric = 0
      for kind, n in pairs(cache[field]) do
        if NUMERIC[kind] then numeric = numeric + n end
      end
      local named = 0
      for kind, n in pairs(pp[field] or {}) do
        if NAMEY[kind] then named = named + n end
      end
      if numeric > 0 and named > 0 and not EXEMPT[field] then
        found[field] = { table = t.name, numeric = numeric, named = named }
        print(("    %-20s numeric in %-4d records; pokeplatinum names it in %d%s")
          :format(field, numeric, named, KNOWN[field] and "" or "   <-- NEW"))
      end
    end
  end
end

print("")
-- THE CONTROL: on a cache written before the Gen4Abilities stage this check
-- has to find `abilities`. It is not asserted as required, because a fresh
-- cache should NOT have it -- but the run says which world it is in, so a
-- silent report can never be mistaken for a clean one.
if found.abilities then
  print("CONTROL: found `abilities` -- this cache predates the Gen4Abilities "
        .. "stage, and the check can see a list-valued id field.")
else
  print("CONTROL: `abilities` is NOT numeric here, so this cache has the "
        .. "Gen4Abilities stage. The list-valued path is UNPROVEN on this run "
        .. "-- run it against an older cache to exercise it.")
end

local new = {}
for field in pairs(found) do
  if not KNOWN[field] then new[#new + 1] = field end
end
table.sort(new)
ok(#new == 0, ("%d field(s) not in KNOWN: %s -- read them, then either fix "):format(
     #new, table.concat(new, ", ")) .. "or add them with a reason")

print("")
print(("%d check(s), %d failure(s)"):format(checks, failures))
for field, why in pairs(KNOWN) do
  if found[field] then print(("  %-20s %s"):format(field, why)) end
end
os.exit(failures == 0 and 0 or 1)
