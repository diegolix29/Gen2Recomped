-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- REGISTERING THE SCRIPT VERBS MUST NOT DEPEND ON WHAT IS ALREADY LOADED.
--
-- Reported from play, on EMERALD: "src/mods/Registry.lua:113: commands already
-- registered: g4_check_two_alive" -- a Sinnoh verb, crashing a Hoenn cartridge
-- at boot, from `Loader.load` -> `Builtins.install` -> `Commands.registerInto`.
--
-- WHY IT TOOK TWO BOOTS TO APPEAR.  `Gen4Commands` puts its 143 verbs on the
-- `Commands` table itself.  `registerInto` used to require that module AFTER its
-- general "register everything on Commands" loop and then run a second `g4_`
-- loop -- so whether the general loop saw the Gen 4 verbs depended entirely on
-- whether anything had required the module yet.  First call: not loaded, general
-- loop missed them, the `g4_` loop registered them.  Second call -- and
-- `Loader.load` runs once at startup and again for every game booted from the
-- launcher -- the module WAS loaded, the general loop took them, and the `g4_`
-- loop registered them into a registry that had just taken them.
--
-- The shape is worth naming: A FUNCTION WHOSE RESULT DEPENDS ON WHETHER IT HAS
-- RUN BEFORE. Calling it once proves nothing about calling it twice, which is
-- why nothing caught this. Every section below calls it at least twice.
--
-- Usage: texlua tools/gen_script_registry_check.lua

local root = (arg[0] or ""):gsub("[^/\\]*$", "")
if root ~= "" then package.path = root .. "../?.lua;" .. package.path end
package.path = "./?.lua;" .. package.path

local fails, checks = 0, 0
local function ok(cond, fmt, ...)
  checks = checks + 1
  if not cond then
    fails = fails + 1
    io.write("FAIL: ", (select("#", ...) > 0) and fmt:format(...) or fmt, "\n")
  end
end
local function section(n) io.write(("\n-- %s\n"):format(n)) end

-- A registry with the one behaviour that matters: a second `register` of the
-- same id RAISES, exactly as src/mods/Registry.lua does for record semantics.
-- Standing in for it rather than driving the real one keeps this check about
-- registerInto; the duplicate rule itself is one line there and is quoted in
-- section 4.
local function newRegistry()
  local r = { items = {}, order = {}, owners = {} }
  function r:get(id) return self.items[id] end
  function r:register(id, value, owner)
    assert(value ~= nil, "value is required for " .. tostring(id))
    if self.items[id] ~= nil then
      error(("commands already registered: %s"):format(id), 0)
    end
    self.items[id] = value
    self.owners[id] = owner
    self.order[#self.order + 1] = id
    return true
  end
  return r
end

local function countPrefix(reg, prefix)
  local n = 0
  for id in pairs(reg.items) do
    if type(id) == "string" and id:sub(1, #prefix) == prefix then n = n + 1 end
  end
  return n
end

local function freshCommands()
  for _, name in ipairs({ "src.script.Commands", "src.script.Gen3Commands",
                          "src.script.Gen4Commands" }) do
    package.loaded[name] = nil
  end
  return require("src.script.Commands")
end

-- ---------------------------------------------------------------------------
section("1. the boot that crashed: two loads in one process")
-- ---------------------------------------------------------------------------
-- The launcher boots once and then boots the chosen game, so `Loader.load` --
-- and this function with it -- runs at least twice in the life of a process.
-- The SECOND call is the one that raised.
do
  local Commands = freshCommands()
  local first = newRegistry()
  local ok1, err1 = pcall(Commands.registerInto, first, nil, "engine")
  ok(ok1, "the first registerInto raised: %s", tostring(err1))
  local second = newRegistry()
  local ok2, err2 = pcall(Commands.registerInto, second, nil, "engine")
  ok(ok2, "the SECOND registerInto raised: %s -- this is the reported crash, "
     .. "and it is why booting a game from the launcher died on a cartridge "
     .. "with no Gen 4 content in it", tostring(err2))
  -- ...and a third, because "works twice" is not "idempotent"
  local third = newRegistry()
  local ok3, err3 = pcall(Commands.registerInto, third, nil, "engine")
  ok(ok3, "the third registerInto raised: %s", tostring(err3))
  -- every call must produce the SAME registry, or the first boot of a session
  -- silently has fewer verbs than the second
  local a, b = #first.order, #second.order
  ok(a == b, "the first load registered %d verbs and the second %d -- the "
     .. "first boot of a session is not the same game as the second", a, b)
  ok(#third.order == a, "the third load registered %d, not %d",
     #third.order, a)
  for id in pairs(second.items) do
    ok(first.items[id] ~= nil, "%q reached the registry only on the second "
       .. "load", id)
  end
  io.write(("  %d verbs, identical across three loads\n"):format(a))
end

-- ---------------------------------------------------------------------------
section("2. the same, with Sinnoh's module already loaded")
-- ---------------------------------------------------------------------------
-- The other order, which is the one the old code happened to survive. Both
-- must work, because nothing in the engine promises either.
do
  local Commands = freshCommands()
  require("src.script.Gen4Commands")
  local reg = newRegistry()
  local okA, errA = pcall(Commands.registerInto, reg, nil, "engine")
  ok(okA, "registerInto raised with Gen4Commands pre-loaded: %s", tostring(errA))
  local reg2 = newRegistry()
  local okB, errB = pcall(Commands.registerInto, reg2, nil, "engine")
  ok(okB, "the second call raised with Gen4Commands pre-loaded: %s", tostring(errB))
  ok(#reg.order == #reg2.order, "%d verbs then %d", #reg.order, #reg2.order)
end

-- ---------------------------------------------------------------------------
section("3. the verbs are all actually there")
-- ---------------------------------------------------------------------------
-- A registerInto that registered NOTHING would sail through everything above.
-- The expected set is taken from the LIVE tables rather than by counting
-- `function Commands.x` in the source: thirteen of Sinnoh's verbs are plain
-- assignments (`Commands.g4_wait_cry = noop`, `g4_trainer_battle =
-- g4_start_battle`) and a source count silently missed every one of them.
do
  local Commands = freshCommands()
  local Gen3 = require("src.script.Gen3Commands")
  local Gen4 = require("src.script.Gen4Commands")
  local want = {}
  for verb, fn in pairs(Commands) do
    if type(fn) == "function" and verb ~= "registerInto" and verb ~= "resolve" then
      want[verb] = true
    end
  end
  for _, mod in ipairs({ Gen3, Gen4 }) do
    for verb, fn in pairs(mod) do
      if type(fn) == "function"
         and (verb:sub(1, 3) == "g3_" or verb:sub(1, 3) == "g4_") then
        want[verb] = true
      end
    end
  end
  local reg = newRegistry()
  local okR, errR = pcall(Commands.registerInto, reg, nil, "engine")
  ok(okR, "registerInto raised: %s", tostring(errR))
  local missing, extra = {}, {}
  for verb in pairs(want) do
    if reg.items[verb] == nil then missing[#missing + 1] = verb end
  end
  for verb in pairs(reg.items) do
    if not want[verb] then extra[#extra + 1] = verb end
  end
  table.sort(missing) table.sort(extra)
  io.write(("  %d verbs expected, %d registered, %d missing, %d unexpected\n")
           :format((function() local n = 0 for _ in pairs(want) do n = n + 1 end return n end)(),
                   #reg.order, #missing, #extra))
  ok(#missing == 0, "%d verbs never reached the registry: %s",
     #missing, table.concat(missing, " ", 1, math.min(#missing, 12)))
  ok(#extra == 0, "%d things reached the registry that are not verbs: %s",
     #extra, table.concat(extra, " ", 1, math.min(#extra, 12)))
  io.write(("  Gen 3: %d   Gen 4: %d\n")
           :format(countPrefix(reg, "g3_"), countPrefix(reg, "g4_")))
  -- Hoenn's own vocabulary is the one that was quietly short, so it is pinned
  -- against a floor rather than only against itself.
  ok(countPrefix(reg, "g3_") >= 109,
     "only %d g3_ verbs are registered; Gen3Commands alone defines 109",
     countPrefix(reg, "g3_"))
  ok(countPrefix(reg, "g4_") >= 143,
     "only %d g4_ verbs are registered; Gen4Commands alone defines 143",
     countPrefix(reg, "g4_"))
  ok(reg.items.g4_check_two_alive ~= nil,
     "g4_check_two_alive is not registered at all now")
  for _, verb in ipairs({ "show_text", "warp", "start_battle", "give_item" }) do
    ok(reg.items[verb] ~= nil, "the base verb %q is gone", verb)
  end
  ok(reg.items.registerInto == nil, "registerInto registered itself as a verb")
  ok(reg.items.resolve == nil, "resolve registered itself as a verb")
end

-- ---------------------------------------------------------------------------
section("4. the shape that caused it cannot come back")
-- ---------------------------------------------------------------------------
local function slurp(rel)
  local f = io.open(root .. "../" .. rel, "rb") or io.open(rel, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return (s:gsub("\r\n", "\n"))
end
local cmd = slurp("src/script/Commands.lua")
ok(cmd ~= nil, "could not open Commands.lua")
if cmd then
  local body = cmd:match("\nfunction Commands%.registerInto%(.-\n(.-)\nend\n")
  ok(body ~= nil, "registerInto could not be found to check its order")
  if body then
    local iRequire = body:find('require, "src.script.Gen4Commands"', 1, true)
    local iLoop = body:find("for verb, fn in pairs(Commands) do", 1, true)
    ok(iRequire and iLoop and iRequire < iLoop,
       "Gen4Commands is required AFTER the general loop again, so what the loop "
       .. "sees depends on load order -- require at %s, first loop at %s",
       tostring(iRequire), tostring(iLoop))
  end
  -- BOTH backstops must still refuse to re-register, and this is COUNTED, not
  -- found. A bare find matched the Hoenn pass's copy of the same line while the
  -- Sinnoh one had its guard removed, and the planted fault walked through.
  local guards = select(2, cmd:gsub("and registry:get%(verb%) == nil", ""))
  ok(guards >= 2,
     "the registry guard appears %d time(s) in Commands.lua; the Hoenn and "
     .. "Sinnoh backstops need one each, or moving a require back down brings "
     .. "the crash straight back", guards)
end
local reg = slurp("src/mods/Registry.lua")
if reg then
  ok(reg:find("already registered: %s", 1, true) ~= nil,
     "Registry no longer raises on a duplicate -- this whole file is about a "
     .. "crash from that line, and a silent second register is worse")
end

io.write(("\n%d checks, %d failed\n"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
