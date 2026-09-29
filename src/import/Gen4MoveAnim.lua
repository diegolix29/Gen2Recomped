-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Gen 4 (Platinum) MOVE ANIMATION PROGRAMS: the bytecode every move's effect
-- is written in, and the table that says how wide each instruction is.
--
-- Reported from play: *"scratch doesnt work and doesnt show a move animation or
-- fx"*. The damage half of that was the type chain (Gen4TypeChart); the
-- animation half was not a bug at all -- `BattleState` builds THREE animation
-- engines, `AnimPlayer` for Gen 1, `Gen2AnimPlayer` for Gen 2 and
-- `Gen3MoveAnim` for Emerald, each behind a `pcall` so a missing one is silent,
-- and there was no fourth. Nothing was asked to draw anything.
--
-- WHERE IT LIVES. `/wazaeffect/we.arc` is a NARC despite the extension, and it
-- holds 501 programs -- one per move, with a tail of non-move animations above
-- the 471 in pl_waza_tbl. A program is a flat stream of 32-bit WORDS: one
-- opcode, then that opcode's operands, with no headers, no offsets and no
-- terminator beyond the member's own length.
--
-- WHY THE WIDTHS CAN BE DERIVED RATHER THAN GUESSED. pret decompiles the whole
-- system: `include/data/scripts/btlanimcmd.h` is an ORDERED table, so a line's
-- position IS its opcode, and `src/battle_anim/battle_anim_system.c` holds
-- every handler. `BattleAnimScript_Next` is exactly `scriptPtr += 1`, so
-- simulating a pointer through a handler -- Next moves it, ReadWord marks the
-- word under it as part of the instruction -- gives the width with nothing left
-- to guess. Taking the MAX over both arms of an `if` is what makes the
-- two-target branches come out right: `jumpifbattlerside` skips an extra word
-- on the enemy path and then jumps, so it occupies four words even though no
-- single path through the handler touches all four.
--
-- !! AND THE WHOLE TABLE IS CHECKED BY CLOSURE. A width table either walks all
-- 501 programs to their exact last word or it does not; there is no partial
-- credit and no judgement call. `tools/gen4_moveanim_check.lua` asserts it.
-- The derivation alone reached 456 of 501. The other 45 came down to TWO
-- opcodes pret cannot state:
--
--   * `setextraparams` is `GF_ASSERT(FALSE)` in pret -- a handler that was
--     compiled out -- so it reads nothing and states no width. The cartridge
--     uses it 742 times. SOLVED FROM THE DATA as `<count> <count values>`,
--     and the neighbouring hypotheses are not close: count at operand 1 closes
--     500, at operand 2 closes 433, at 3 closes 463, at 4 closes 423. A width
--     that fits anything would not separate like that.
--   * `nop4` has no body at all, and takes ONE operand. It occurs once.
--
-- Those two are the only widths here NOT stated by pret, and they are marked in
-- SOLVED below so the distinction survives. Everything else is derived.
--
-- MEASURED over the corpus: 501 programs, 18,620 instructions, 59 of the 85
-- opcodes ever used, 425 programs loading a particle system between them naming
-- 419 of the 485 members of waza_particle.narc, and 262 distinct sound effects.
--
-- WHAT THIS FILE DOES NOT DO. It decodes the PROGRAM. It does not render one:
-- the visible burst of nearly every move is an `SPA ` particle program in
-- /wazaeffect/effectdata/waza_particle.narc, and nothing in this port reads SPA
-- yet. Scratch's program is `loadparticlesystem 0, 40` -- so a decoder alone
-- puts Sinnoh where Gen 1 was before AnimPlayer: timing, sound and sprite
-- movement real, the particle still missing. That is deliberate, and it is the
-- same discipline Gen4Anim uses for keyframe values: establish the structure,
-- check it, and do not guess the layer underneath it.

local Gen4MoveAnim = {}

-- The archives. `we.arc` carries no `.narc` extension and is one anyway.
Gen4MoveAnim.ARCHIVE_PROGRAMS = "/wazaeffect/we.arc"
Gen4MoveAnim.ARCHIVE_PARTICLES = "/wazaeffect/effectdata/waza_particle.narc"
Gen4MoveAnim.ARCHIVE_BALL_PARTICLES = "/wazaeffect/effectdata/ball_particle.narc"

-- The 2D cell-actor set an effect's sprites come from -- four archives that are
-- one sprite between them, in the order `loadcharresobj` / `loadplttres` /
-- `loadcellresobj` / `loadanimresobj` ask for them.
Gen4MoveAnim.ARCHIVE_CELL = {
  char = "/wazaeffect/effectclact/wechar.narc",
  pltt = "/wazaeffect/effectclact/wepltt.narc",
  cell = "/wazaeffect/effectclact/wecell.narc",
  anim = "/wazaeffect/effectclact/wecellanm.narc",
}

-- Counts, stated so a cartridge that disagrees is caught rather than composed
-- from whatever happened to be at that index.
Gen4MoveAnim.PROGRAM_COUNT = 501
Gen4MoveAnim.PARTICLE_COUNT = 485
Gen4MoveAnim.MOVE_COUNT = 471
Gen4MoveAnim.WORD_BYTES = 4

-- ---------------------------------------------------------------------------
-- The opcode table
-- ---------------------------------------------------------------------------

-- pret's btlanimcmd.h in order, lower-cased. THE INDEX IS THE OPCODE, which is
-- why this is written as a 0-based array rather than a map: a name inserted in
-- the wrong place renumbers everything after it, and the check asserts three
-- fixed points (0, the first, and the last) rather than trusting the paste.
Gen4MoveAnim.OPCODES = {
  [0] = "delay", "waitforanimtasks", "beginloop",
  "endloop", "end", "playsoundeffect",
  "nop0", "nop1", "setbg0bg1alphablending",
  "setdefaultalphablending", "call", "return",
  "setvar", "jumpifeffectchanceodd", "jumpifeffectchance",
  "jump", "switchbg", "setbgswitchvar",
  "restorebg", "waitforpartialbgswitch", "waitforbgswitch",
  "setbg", "playpannedsoundeffect", "pansoundeffects",
  "playmovingsoundeffectatkdef", "playloopedsoundeffect", "playdelayedsoundeffect",
  "nop2", "nop3", "waitforsoundeffects",
  "jumpifequal", "loadpokemonspriteintobg", "removepokemonspritefrombg",
  "jumpifunk_01", "switchbgex", "playmovingsoundeffectnocorrection",
  "playmovingsoundeffectatkdef2", "nop4", "nop5",
  "nop6", "nop7", "nop8",
  "nop9", "nop10", "stopsoundeffect",
  "callfunc", "createemitter", "createemitterex",
  "createemitterformove", "createemitterforfriendlyfire", "waitforallemitters",
  "loadparticlesystem", "loaddebugparticlesystem", "unloadparticlesystem",
  "nop11", "setextraparams", "initpokemonspritemanager",
  "loadpokemonspritedummyresources", "addpokemonsprite", "freepokemonspritemanager",
  "removepokemonsprite", "canceltrackingtask", "setcameraprojection",
  "setcameraflip", "jumpifbattlerside", "playpokemoncry",
  "waitforpokemoncries", "resetvars", "startbattlerslidein",
  "startbattlerslideout", "jumpifweather", "jumpifcontest",
  "jumpiffriendlyfire", "initspritemanager", "loadcharresobj",
  "loadplttres", "loadcellresobj", "loadanimresobj",
  "addspritewithfunc", "addsprite", "freespritemanager",
  "setpokemonspritevisible", "startpokemonspritedrawtask", "stoppokemonspritedrawtask",
  "waitforlrx",
}
Gen4MoveAnim.OPCODE_COUNT = 85

-- How many OPERAND words follow each opcode. `Gen4MoveAnim.COUNTED` marks the
-- three whose length is stated by one of their own operands; `COUNT_AT` says
-- which one. A self-describing length is the friendliest kind of variable
-- width -- the stream never has to be guessed at.
--
-- A FILE-LOCAL, and deliberately: the WIDTHS table below spells this name 3
-- times inside a table constructor, and a bare `COUNTED` there would resolve
-- as a GLOBAL, come back nil, and put holes in the array instead of marking
-- the three counted opcodes -- the same class of fault `lua_use_before_local`
-- exists to catch, and it would not have raised, it would have silently made
-- three widths unknown.
local COUNTED = -1
Gen4MoveAnim.COUNTED = COUNTED
Gen4MoveAnim.COUNT_AT = {
  [45] = 2,   -- callfunc
  [55] = 1,   -- setextraparams
  [78] = 9,   -- addspritewithfunc
}

-- The two the derivation could not reach; see the header.
Gen4MoveAnim.SOLVED = { [37] = "nop4", [55] = "setextraparams" }

Gen4MoveAnim.WIDTHS = {
  [0] = 1, 0, 1, 0, 0, 1,
  0, 0, 2, 0, 1, 0,
  2, 2, 2, 1, 2, 2,
  2, 0, 0, 1, 2, 1,
  5, 4, 3, 0, 0, 0,
  3, 2, 1, 1, 3, 5,
  5, 1, 0, 0, 0, 0,
  0, 0, 1, COUNTED, 3, 4,
  8, 6, 0, 2, 3, 1,
  0, COUNTED, 0, 1, 4, 0,
  1, 1, 2, 0, 3, 3,
  1, 0, 1, 1, 3, 1,
  1, 8, 2, 3, 2, 2,
  COUNTED, 8, 1, 2, 3, 1,
  0,
}

-- ---------------------------------------------------------------------------
-- Decoding
-- ---------------------------------------------------------------------------

local floor = math.floor
local byte = string.byte

-- A little-endian 32-bit word at a ZERO-BASED word index, or nil past the end.
-- Word-addressed rather than byte-addressed because the format is: every
-- operand, every opcode and every jump offset in it is a whole word, and
-- carrying byte offsets around is how an off-by-four gets in.
function Gen4MoveAnim.word(data, index)
  if type(data) ~= "string" then return nil end
  local at = index * 4
  if at < 0 or at + 4 > #data then return nil end
  local b0, b1, b2, b3 = byte(data, at + 1, at + 4)
  return b0 + b1 * 256 + b2 * 65536 + b3 * 16777216
end

function Gen4MoveAnim.wordCount(data)
  if type(data) ~= "string" then return 0 end
  return floor(#data / 4)
end

-- How many WORDS the instruction at `index` occupies, opcode included, or nil
-- when the opcode is out of range or its counted length runs off the end.
function Gen4MoveAnim.step(data, index)
  local op = Gen4MoveAnim.word(data, index)
  if not op then return nil, "past the end" end
  local width = Gen4MoveAnim.WIDTHS[op]
  if width == nil then
    return nil, ("opcode %d is not one of the %d"):format(
      op, Gen4MoveAnim.OPCODE_COUNT)
  end
  if width ~= Gen4MoveAnim.COUNTED then return 1 + width, op end
  local at = Gen4MoveAnim.COUNT_AT[op]
  local count = at and Gen4MoveAnim.word(data, index + at)
  if not count then return nil, "counted operand runs past the end" end
  return 1 + at + count, op
end

-- decode(data) -> { { at, op, name, args = { ... } }, ... }, nil
--         or     nil, why, at
--
-- A LINEAR WALK IS THE WHOLE POINT, and it is only defensible because the
-- closure check says every one of the 501 programs is exactly a linear stream:
-- the jumps in them land on instruction boundaries the walk already visits, so
-- there is no region reachable only by branch and no data block between them.
-- If that ever stops being true the check fails first and loudly, rather than
-- this function quietly returning half a program.
function Gen4MoveAnim.decode(data)
  local out, index = {}, 0
  local total = Gen4MoveAnim.wordCount(data)
  while index < total do
    local step, op = Gen4MoveAnim.step(data, index)
    if not step then return nil, op, index end
    if index + step > total then
      return nil, ("instruction at %d runs %d words past the end")
        :format(index, index + step - total), index
    end
    local args = {}
    for i = 1, step - 1 do args[i] = Gen4MoveAnim.word(data, index + i) end
    out[#out + 1] = {
      at = index, op = op, name = Gen4MoveAnim.OPCODES[op], args = args,
    }
    index = index + step
  end
  return out
end

-- ---------------------------------------------------------------------------
-- What a decoded program SAYS
-- ---------------------------------------------------------------------------

-- The opcodes whose first operand is a sound effect id. Listed rather than
-- pattern-matched on the name, because `stopsoundeffect` and
-- `waitforsoundeffects` are sound commands that carry no id and
-- `pansoundeffects` carries a pan.
Gen4MoveAnim.SOUND_OPS = {
  [5] = true,    -- playsoundeffect
  [22] = true,   -- playpannedsoundeffect
  [24] = true,   -- playmovingsoundeffectatkdef
  [25] = true,   -- playloopedsoundeffect
  [26] = true,   -- playdelayedsoundeffect
  [35] = true,   -- playmovingsoundeffectnocorrection
  [36] = true,   -- playmovingsoundeffectatkdef2
}

-- `loadparticlesystem <slot> <member>` -- the second operand is the index into
-- waza_particle.narc, confirmed in pret's handler (`psIndex` then
-- `memberIndex`). This is the one number that says what a move LOOKS like:
-- Scratch is 40, Pound is 31.
Gen4MoveAnim.PARTICLE_OP = 51
Gen4MoveAnim.PARTICLE_ARG = 2

-- `delay <frames>` is the only command that spends time on its own; every other
-- wait is on a task finishing, so a frame total from this alone is a FLOOR and
-- is named as one.
Gen4MoveAnim.DELAY_OP = 0

-- summary(program) -> { particles = {...}, sounds = {...}, delayFrames = n,
--                       instructions = n, ends = n }
function Gen4MoveAnim.summary(program)
  if type(program) ~= "table" then return nil end
  local seenP, seenS = {}, {}
  local out = { particles = {}, sounds = {}, delayFrames = 0,
                instructions = #program, ends = 0 }
  for _, row in ipairs(program) do
    if row.op == Gen4MoveAnim.PARTICLE_OP then
      local member = row.args[Gen4MoveAnim.PARTICLE_ARG]
      if member and not seenP[member] then
        seenP[member] = true
        out.particles[#out.particles + 1] = member
      end
    elseif Gen4MoveAnim.SOUND_OPS[row.op] then
      local id = row.args[1]
      if id and not seenS[id] then
        seenS[id] = true
        out.sounds[#out.sounds + 1] = id
      end
    elseif row.op == Gen4MoveAnim.DELAY_OP then
      out.delayFrames = out.delayFrames + (row.args[1] or 0)
    elseif row.name == "end" then
      out.ends = out.ends + 1
    end
  end
  table.sort(out.particles)
  table.sort(out.sounds)
  return out
end

-- check(data) -> true, instructionCount   or   false, why, at
--
-- The closure question for ONE program, so a caller can ask it without pulling
-- in the tool. "Does the walk land exactly on the last word" is the whole test;
-- a stream that ends one word early is a width that is one too small somewhere
-- and there is no way for it to look almost right.
function Gen4MoveAnim.check(data)
  local program, why, at = Gen4MoveAnim.decode(data)
  if not program then return false, why, at end
  return true, #program
end

return Gen4MoveAnim
