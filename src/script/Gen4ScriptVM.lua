-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- The Gen 4 script lowering.
--
-- Structurally a sibling of src/script/Gen3ScriptVM.lua, and deliberately so:
-- ScriptRunner and Commands.resolve are generation-agnostic, so a fourth
-- generation needs a lowering and a verb set, not a fourth script subsystem.
-- Shared verbs (`jump`, `label`, `show_text`, `ask`, `set_flag`, `wait`,
-- `play_sound`, `play_music`) are emitted as-is; anything Gen 4 does that no
-- earlier generation has gets a `g4_` verb, exactly as Gen 3 uses `g3_`.
--
-- WHAT IS AND IS NOT HERE.  This is the lowering half.  Gen4Script turns
-- cartridge bytes into instructions and this turns instructions into
-- ScriptRunner rows.  The extractor half -- writing a script pool into
-- data/generated and registering a contribution per map through MapScripts --
-- is NOT built yet, so nothing calls this in a running game.  It is written
-- now because the decode is proven and the lowering is what the decode is
-- for, and because a lowering table is far easier to check against the
-- cartridge than against a half-built extractor.
--
-- WHY THESE COMMANDS, AND WHERE IT GOT TO.  Gen4Script's coverage measurement
-- picked them, not taste.  Measured against the whole cartridge -- 4,079
-- scripts, 50,843 instructions -- this table lowers 97.8% of instructions and
-- leaves 85.7% of scripts with nothing unimplemented in them at all.
--
-- It got there in three passes, and the shape of those passes is the useful
-- part.  The conversation set alone reached 87.8% of instructions but only
-- 52.7% of whole scripts, because a script is only as lowered as its worst
-- command.  Adding EIGHT more -- the four generated trainer-battle commands
-- that occur exactly 928 times each, once per trainer in trdata.narc, and the
-- four that drive a signpost -- took it to 97.3% and 82.4%.  The third pass
-- added ten commands that occur twenty-odd times each and are load bearing
-- anyway: `warp`, without which the player cannot leave a map;
-- `starttrainerbattle`, without which the trainer preamble runs and nothing
-- happens; `pokemartcommon`, without which the clerk says hello and sells
-- nothing.
--
-- Frequency is a good guide to what to lower FIRST and a poor guide to what
-- to stop at.  What remains unlowered is a flat tail of side systems -- TV
-- interviews, the journal, the Battle Tower, Turnback Cave, the Poketch --
-- at a few dozen occurrences each, and those are left as explicit
-- `g4_unimplemented` rows rather than dropped.
--
-- TWO GEN 4 SHAPES THAT ARE NOT GEN 3 SHAPES.
--
-- Conditions are a COMPARISON REGISTER, as in Gen 3, but the comparison and
-- the branch are separate commands: `comparevartovalue` sets the register and
-- `gotoif` / `callif` carry a one-byte condition selecting less / equal /
-- greater / less-or-equal / greater-or-equal / not-equal.  That is the single
-- commonest pair in the game -- 8,058 comparisons and 9,400 conditional
-- branches -- so collapsing the six conditions to a boolean would invert or
-- drop a branch in most scripts in Sinnoh.
--
-- `call` is a real subroutine call with a return stack, and `callcommonscript`
-- calls into a SHARED script archive rather than the current file.  Gen 3's
-- `callstd` is the nearest relative.  Common scripts are left as a `g4_common`
-- row rather than inlined: 345 call sites reach them, they are not in the
-- map's own member, and inlining would need the whole common archive resolved
-- before a single map could lower.

local Gen4ScriptVM = {}

-- ---------------------------------------------------------------------------
-- lowering table: one decoded instruction -> zero or more ScriptRunner rows
-- ---------------------------------------------------------------------------

local L = {}
Gen4ScriptVM.LOWERING = L

local function emit(s, row) s.out[#s.out + 1] = row end

-- A decoded jump carries `target`, an absolute position inside the member.
-- The pool keys scripts by that position, so the label is derived from it in
-- one place rather than in every branch entry.
local function labelFor(instruction)
  local t = instruction.target
  if type(t) ~= "number" then return nil end
  return ("S%04X"):format(t)
end
Gen4ScriptVM.labelFor = labelFor

local function branch(s, instruction)
  local label = labelFor(instruction)
  if not label then return nil end
  if s.has and not s.has(label) then return nil end
  if s.want then s.want(label) end
  return label
end

-- control flow -------------------------------------------------------------

L["end"] = function(_, s) emit(s, { "jump", "end" }) end
L["return"] = function(_, s) emit(s, { "g4_return" }) end

L["goto"] = function(ins, s)
  local to = branch(s, ins)
  if to then emit(s, { "jump", to }) end
end

L.call = function(ins, s)
  local to = branch(s, ins)
  if not to then return end
  local ret = s.newLabel()
  emit(s, { "g4_call", ret })
  emit(s, { "jump", to })
  emit(s, { "label", ret })
end

-- The condition byte is the FIRST operand and the target the second.
L.gotoif = function(ins, s)
  local to = branch(s, ins)
  if to then emit(s, { "g4_jump_if", ins.args[1], to }) end
end

L.callif = function(ins, s)
  local to = branch(s, ins)
  if not to then return end
  local ret = s.newLabel()
  emit(s, { "g4_call_if", ins.args[1], ret })
  emit(s, { "jump", to })
  emit(s, { "label", ret })
end

L.callcommonscript = function(ins, s) emit(s, { "g4_common", ins.args[1] }) end
L.returncommonscript = function(_, s) emit(s, { "g4_return" }) end

-- comparisons --------------------------------------------------------------

L.comparevartovalue = function(ins, s)
  emit(s, { "g4_compare_var_value", ins.args[1], ins.args[2] })
end
L.comparevartovar = function(ins, s)
  emit(s, { "g4_compare_var_var", ins.args[1], ins.args[2] })
end

-- variables and flags ------------------------------------------------------

L.setvarfromvalue = function(ins, s) emit(s, { "g4_set_var", ins.args[1], ins.args[2] }) end
L.setvarfromvar = function(ins, s) emit(s, { "g4_copy_var", ins.args[1], ins.args[2] }) end
L.addvar = function(ins, s) emit(s, { "g4_add_var", ins.args[1], ins.args[2] }) end
L.subvar = function(ins, s) emit(s, { "g4_sub_var", ins.args[1], ins.args[2] }) end

-- Flags are named the way Gen 3's are, so the save format and the debug
-- screens do not need a fourth spelling.
local function flagName(n) return ("FLAG_G4_%04X"):format(tonumber(n) or 0) end
Gen4ScriptVM.flagName = flagName

L.setflag = function(ins, s) emit(s, { "set_flag", flagName(ins.args[1]) }) end
L.clearflag = function(ins, s) emit(s, { "clear_flag", flagName(ins.args[1]) }) end
L.checkflag = function(ins, s) emit(s, { "g4_check_flag", flagName(ins.args[1]) }) end
L.settrainerflag = function(ins, s) emit(s, { "g4_set_trainer_flag", ins.args[1] }) end
L.cleartrainerflag = function(ins, s) emit(s, { "g4_clear_trainer_flag", ins.args[1] }) end
L.checktrainerflag = function(ins, s) emit(s, { "g4_check_trainer_flag", ins.args[1] }) end

-- the conversation ---------------------------------------------------------

-- `message` names an entry in the map's own text bank, which the map header's
-- msgArchiveID selects -- so the row carries the entry and the runner
-- resolves the bank.  Carrying a resolved string here instead would bake one
-- language into the lowering.
L.message = function(ins, s) emit(s, { "show_text", ins.args[1] }) end
L.message2 = L.message
L.closemessage = function(_, s) emit(s, { "g4_close_message" }) end
L.closemessagewithouterasing = L.closemessage
L.waitbutton = function(_, s) emit(s, { "g4_wait_button" }) end
L.showyesnomenu = function(_, s) emit(s, { "ask" }) end

L.lockall = function(_, s) emit(s, { "g4_lock_all" }) end
L.releaseall = function(_, s) emit(s, { "g4_release_all" }) end
L.lock = function(ins, s) emit(s, { "g4_lock", ins.args[1] }) end
L.release = function(ins, s) emit(s, { "g4_release", ins.args[1] }) end
L.faceplayer = function(_, s) emit(s, { "g4_face_player" }) end

L.bufferplayername = function(ins, s) emit(s, { "g4_buffer", ins.args[1], "player" }) end
L.bufferpokemonname = function(ins, s)
  emit(s, { "g4_buffer", ins.args[1], "species", ins.args[2] })
end
L.bufferitemname = function(ins, s)
  emit(s, { "g4_buffer", ins.args[1], "item", ins.args[2] })
end

-- movement, sound and screen ----------------------------------------------

L.applymovement = function(ins, s)
  emit(s, { "g4_move", ins.args[1], ins.args[2] })
end
L.waitmovement = function(_, s) emit(s, { "g4_wait_move" }) end
L.playse = function(ins, s) emit(s, { "play_sound", ins.args[1] }) end
L.waitse = function(_, s) emit(s, { "g4_wait_sound" }) end
L.playcry = function(ins, s) emit(s, { "play_cry", ins.args[1], ins.args[2] }) end
L.playfanfare = function(ins, s) emit(s, { "g4_fanfare", ins.args[1] }) end
L.waitfanfare = function(_, s) emit(s, { "g4_wait_fanfare" }) end
L.fadescreen = function(ins, s) emit(s, { "g4_fade", ins.args[1], ins.args[2] }) end
L.waitfadescreen = function(_, s) emit(s, { "g4_wait_fade" }) end
L.waittime = function(ins, s) emit(s, { "wait", ins.args[1] }) end

L.addobject = function(ins, s) emit(s, { "g4_show_object", ins.args[1] }) end
L.removeobject = function(ins, s) emit(s, { "g4_hide_object", ins.args[1] }) end

-- items --------------------------------------------------------------------

L.giveitem = function(ins, s) emit(s, { "g4_give_item", ins.args[1], ins.args[2] }) end
L.takeitem = function(ins, s) emit(s, { "g4_take_item", ins.args[1], ins.args[2] }) end
L.checkitem = function(ins, s) emit(s, { "g4_check_item", ins.args[1], ins.args[2] }) end
L.canfititem = function(ins, s) emit(s, { "g4_can_fit_item", ins.args[1], ins.args[2] }) end

-- the trainer-battle preamble ---------------------------------------------

-- These four are generated, not hand-written: every trainer in the game gets
-- the same opening, which is why each occurs exactly 928 times -- once per
-- trainer in trdata.narc.  Lowering them is worth more than their share of
-- the listing suggests, because a script that stops at one stops before the
-- battle it exists to start.
L.gettrainerid = function(ins, s) emit(s, { "g4_get_trainer_id", ins.args[1] }) end
L.checkistrainerdoublebattle = function(ins, s)
  emit(s, { "g4_check_trainer_double", ins.args[1] })
end
L.checkhastwoalivemons = function(ins, s) emit(s, { "g4_check_two_alive", ins.args[1] }) end
L.getmovementtype = function(ins, s)
  emit(s, { "g4_get_movement_type", ins.args[1], ins.args[2] })
end
L.trainerbattle = function(ins, s)
  emit(s, { "g4_trainer_battle", ins.args[1], ins.args[2] })
end
L.checkwonbattle = function(ins, s) emit(s, { "g4_check_won_battle", ins.args[1] }) end

-- signposts ---------------------------------------------------------------

-- Gen 4's sign boxes are a small state machine rather than one command:
-- draw, set what the box does, poll the player's choice, wait for it to
-- finish.  All four have to lower together or a sign opens and never closes.
L.drawsignpostinstantmessage = function(ins, s)
  emit(s, { "g4_signpost_draw", ins.args[1], ins.args[2] })
end
L.setsignpostcommand = function(ins, s) emit(s, { "g4_signpost_command", ins.args[1] }) end
L.getsignpostinput = function(ins, s) emit(s, { "g4_signpost_input", ins.args[1] }) end
L.waitforsignpostdone = function(_, s) emit(s, { "g4_signpost_wait" }) end

-- odds and ends that the corpus actually reaches --------------------------

L.getplayermappos = function(ins, s) emit(s, { "g4_player_pos", ins.args[1], ins.args[2] }) end
L.getplayergender = function(ins, s) emit(s, { "g4_player_gender", ins.args[1] }) end
L.bufferrivalname = function(ins, s) emit(s, { "g4_buffer", ins.args[1], "rival" }) end
L.waitcry = function(_, s) emit(s, { "g4_wait_cry" }) end
L.setobjecteventpos = function(ins, s)
  emit(s, { "g4_set_object_pos", ins.args[1], ins.args[2], ins.args[3] })
end
L.addmenuentryimm = function(ins, s)
  emit(s, { "g4_menu_entry", ins.args[1], ins.args[2], ins.args[3] })
end
L.showmenu = function(_, s) emit(s, { "g4_menu_show" }) end
L.closemenu = function(_, s) emit(s, { "g4_menu_close" }) end

-- a few that matter far more than their count --------------------------------

-- Each of these occurs only twenty-odd times and every one of them is load
-- bearing: without `warp` the player cannot leave a map, without
-- `starttrainerbattle` the trainer preamble above runs and then nothing
-- happens, and without `pokemartcommon` the clerk that motivated this file
-- says hello and sells nothing.  Frequency is a good guide to what to lower
-- first and a poor guide to what to stop at.
L.warp = function(ins, s)
  emit(s, { "g4_warp", ins.args[1], ins.args[2], ins.args[3] })
end
L.starttrainerbattle = function(ins, s) emit(s, { "g4_start_battle", ins.args[1] }) end
L.pokemartcommon = function(ins, s) emit(s, { "g4_pokemart", ins.args[1] }) end
L.pokemartspecialties = function(ins, s) emit(s, { "g4_pokemart", ins.args[1], "specialty" }) end
L.checkbadgeacquired = function(ins, s) emit(s, { "g4_check_badge", ins.args[1], ins.args[2] }) end
L.getplayerdir = function(ins, s) emit(s, { "g4_player_dir", ins.args[1] }) end
L.returntofield = function(_, s) emit(s, { "g4_return_to_field" }) end
L.waitforanimation = function(_, s) emit(s, { "g4_wait_animation" }) end
L.drawsignposttextbox = function(ins, s)
  emit(s, { "g4_signpost_draw", ins.args[1], ins.args[2], "box" })
end
L.drawsignpostscrollingmessage = function(ins, s)
  emit(s, { "g4_signpost_draw", ins.args[1], ins.args[2], "scrolling" })
end

-- ---------------------------------------------------------------------------

function Gen4ScriptVM.lowered(name) return L[name] ~= nil end

-- ---------------------------------------------------------------------------
-- the pool, and attaching it to maps
-- ---------------------------------------------------------------------------

local MapScripts = require("src.script.MapScripts")
local Logger = require("src.core.Logger")

local compiled = setmetatable({}, { __mode = "k" })

-- The `source` check is the same guard Gen3ScriptVM uses, and for the same
-- reason: a cache built by a different generation's extractor has a pool of
-- the same NAME and an entirely different shape, and attaching it would
-- produce maps whose scripts are another game's.
local function store(data)
  local pool = data and data.map_scripts
  if pool and pool.source == "RomExtractorGen4" then return pool end
  return nil
end
Gen4ScriptVM.store = store

-- Compile one label into ScriptRunner rows, following branches into the
-- labels they reach.  Memoised per pool, because a common script is reached
-- from hundreds of call sites and lowering it hundreds of times would be the
-- slowest thing in a boot.
function Gen4ScriptVM.compile(data, entry)
  local pool = store(data)
  local scripts = pool and pool.scripts
  if not (scripts and type(entry) == "string" and scripts[entry]) then return nil end

  compiled[scripts] = compiled[scripts] or {}
  local hit = compiled[scripts][entry]
  if hit ~= nil then return hit or nil end

  local out, queued, order, counter = {}, { [entry] = true }, { entry }, 0
  local state = {
    out = out,
    has = function(label) return type(label) == "string" and scripts[label] ~= nil end,
    want = function(label)
      if type(label) == "string" and scripts[label] and not queued[label] then
        queued[label] = true
        order[#order + 1] = label
      end
    end,
    newLabel = function()
      counter = counter + 1
      return ("%s_r%d"):format(entry, counter)
    end,
  }

  local index = 1
  while index <= #order do
    local label = order[index]
    index = index + 1
    -- Every block after the first is jumped to, so it needs its label emitted
    -- before its rows or the jump has nothing to land on.
    if label ~= entry then emit(state, { "label", label }) end
    local block = scripts[label]
    Gen4ScriptVM.lower(block and block.instructions, state)
  end

  compiled[scripts][entry] = out
  return out
end

-- A label's branches are resolved against the member it lives in, so a label
-- carries its member: "M0123/S0017".  One place that spelling is built, so a
-- change of key format does not have to be chased through the extractor and
-- the VM separately.
function Gen4ScriptVM.label(member, at)
  return ("M%04d/S%04X"):format(member, at)
end

local PHASE_KEYS = {
  talk = { talk = true },
  scenes = { onEnter = true, onStep = true, onFrame = true },
}

-- What a map contributes.  Gen 4 has no TEXT constant the way Gen 2 and Gen 3
-- do -- an object event carries a SCRIPT ID and nothing else -- so the key
-- `talk` is indexed by is the script's own label, and the extractor writes
-- that same label into each object's `text` field.  Both halves derive it
-- from Gen4ScriptVM.label, so they cannot drift apart.
local function contributionFor(data, mapId, entry)
  local contribution = {}
  local talk = {}
  for _, label in pairs(entry.objects or {}) do
    local rows = Gen4ScriptVM.compile(data, label)
    if rows then talk[label] = rows end
  end
  for _, label in pairs(entry.signs or {}) do
    local rows = Gen4ScriptVM.compile(data, label)
    if rows then talk[label] = rows end
  end
  if next(talk) then contribution.talk = talk end
  return next(contribution) and contribution or nil
end

function Gen4ScriptVM.register(data, phase)
  local keep = PHASE_KEYS[phase]
  local pool = store(data)
  if not (pool and pool.maps) then return 0 end
  local attached = 0
  for mapId, entry in pairs(pool.maps) do
    local ok, contribution = pcall(contributionFor, data, mapId, entry)
    if ok and contribution and keep then
      local filtered = {}
      for key, value in pairs(contribution) do
        if keep[key] then filtered[key] = value end
      end
      contribution = next(filtered) and filtered or nil
    end
    if ok and contribution then
      MapScripts.attachBase(mapId, contribution)
      attached = attached + 1
    elseif not ok then
      Logger.warn("gen4 script vm: %s failed to compile (%s)", mapId, tostring(contribution))
    end
  end
  Logger.info("gen4 script vm: %d maps attached (%s)", attached, tostring(phase or "all"))
  return attached
end

-- Lower one decoded script.  Anything without an entry becomes an explicit
-- `g4_unimplemented` row rather than nothing: a silently dropped command is a
-- script that runs and quietly does the wrong thing, which is far harder to
-- find than one that reports what it could not do.
function Gen4ScriptVM.lower(instructions, state)
  local s = state or {}
  s.out = s.out or {}
  s.newLabel = s.newLabel or (function()
    local n = 0
    return function() n = n + 1; return ("R%04d"):format(n) end
  end)()
  for _, ins in ipairs(instructions or {}) do
    local handler = L[ins.name]
    if handler then
      handler(ins, s)
    elseif ins.variable then
      emit(s, { "g4_unimplemented", ins.name, "variable length" })
    else
      emit(s, { "g4_unimplemented", ins.name })
    end
  end
  return s.out
end

return Gen4ScriptVM
