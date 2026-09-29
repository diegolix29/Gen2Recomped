-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- tools/gen4_moveanim_check.lua -- the seventeenth standing check, and the
-- first about a MOVE ANIMATION rather than a script, a screen or a warp.
--
-- THE WHOLE CHECK IS CLOSURE, and that is what makes it worth having. A width
-- table either walks all 501 programs in /wazaeffect/we.arc to their exact last
-- word or it does not. There is no partial credit and no judgement call: a
-- width that is one too small leaves a trailing word the walk reads as an
-- opcode, a width one too large runs off the end, and either way the program
-- that contains it fails. A table that is 99% right fails loudly on the 1%.
--
-- WHY THE NUMBER IS 501 AND NOT "MOST". `Gen4MoveAnim`'s widths come from
-- pret's handler bodies -- `BattleAnimScript_Next` is `scriptPtr += 1`, so
-- simulating a pointer through a handler gives the width outright -- and that
-- derivation alone reached 456. The remaining 45 came down to TWO opcodes pret
-- cannot state: `setextraparams`, whose handler is `GF_ASSERT(FALSE)` and reads
-- nothing while the cartridge uses it 742 times, and `nop4`, which has no body
-- at all. Both were solved against this check, and `Gen4MoveAnim.SOLVED` names
-- them so the distinction between DERIVED and SOLVED does not quietly rot.
--
-- A SOLVED WIDTH IS ONLY WORTH ANYTHING IF THE SOLUTION IS SHARP, so the check
-- asserts that too: `setextraparams` read as `<count> <count values>` closes
-- all 501, and the neighbouring readings close 433, 463 and 423. A parameter
-- that could be fitted to anything would not separate like that, and stating
-- the margin is the difference between a measurement and a curve fit.
--
-- WHAT IT COVERS BEYOND THE WIDTHS. Sections 9 and 10 are about the ANIMATION
-- rather than the decoding: the fixed-point primitives in `Gen4AnimMath`
-- against NitroSystem's own sine table in the ARM9, and then each of the five
-- per-move sprite callbacks this port applies, measured by running its move and
-- looking at the sprite count, the placement, the lifetime and the one channel
-- the callback drives.
--
-- Run:  texlua tools/gen4_moveanim_check.lua <rom path>

local romPath = arg and arg[1]
if not romPath then
  io.stderr:write("usage: texlua tools/gen4_moveanim_check.lua <rom path>\n")
  os.exit(2)
end

local root = (arg[0] or ""):gsub("[^/\\]*$", "")
if root ~= "" then package.path = root .. "../?.lua;" .. package.path end
package.path = "./?.lua;" .. package.path

local NdsRom = require("src.import.NdsRom")
local Narc = require("src.import.NarcArchive")
local Anim = require("src.import.Gen4MoveAnim")

local fails, checks = 0, 0
-- The cartridge writes negative operands as unsigned 32-bit words; the player
-- signs them on the way into the script vars and this is the same rule, here so
-- the synthetic test can hand over what the ROM would.
-- `math.floor` on a value that may be a float from the draw list; named so the
-- section below reads as an intent rather than a cast.
local function floorDiv(v)
  return math.floor(tonumber(v) or 0)
end

local function signedWord(v)
  v = tonumber(v) or 0
  if v >= 2147483648 then return v - 4294967296 end
  return v
end
local function ok(cond, what, got, want)
  checks = checks + 1
  if cond then
    io.write(("  ok    %-52s %s\n"):format(what, tostring(got)))
  else
    fails = fails + 1
    io.write(("  FAIL  %-52s got %s, expected %s\n")
      :format(what, tostring(got), tostring(want)))
  end
end

-- ---------------------------------------------------------------------------
-- 1: THE TABLE ITSELF, before a single program is decoded with it.
--
-- The opcode numbering is a PASTE of pret's ordered header, and a name dropped
-- or inserted renumbers everything after it -- silently, because the result is
-- still a table of plausible names. Three fixed points at both ends and the
-- middle catch that; a hole anywhere catches a truncated constructor.
-- ---------------------------------------------------------------------------
io.write("the opcode table\n")
local holes, unnamed = 0, 0
for i = 0, Anim.OPCODE_COUNT - 1 do
  if Anim.WIDTHS[i] == nil then holes = holes + 1 end
  if Anim.OPCODES[i] == nil then unnamed = unnamed + 1 end
end
ok(holes == 0 and unnamed == 0,
   "every opcode has a name and a width",
   ("%d nameless, %d widthless"):format(unnamed, holes), "0, 0")
ok(Anim.OPCODE_COUNT == 85, "pret states eighty-five of them",
   Anim.OPCODE_COUNT, 85)
ok(Anim.OPCODES[0] == "delay" and Anim.OPCODES[4] == "end"
   and Anim.OPCODES[84] == "waitforlrx",
   "the numbering's three fixed points",
   ("%s/%s/%s"):format(tostring(Anim.OPCODES[0]), tostring(Anim.OPCODES[4]),
                       tostring(Anim.OPCODES[84])),
   "delay/end/waitforlrx")
-- ...and the one every measurement below leans on
ok(Anim.OPCODES[Anim.PARTICLE_OP] == "loadparticlesystem",
   "the particle opcode is where the summary thinks",
   tostring(Anim.OPCODES[Anim.PARTICLE_OP]), "loadparticlesystem")

local counted = {}
for i = 0, Anim.OPCODE_COUNT - 1 do
  if Anim.WIDTHS[i] == Anim.COUNTED then counted[#counted + 1] = Anim.OPCODES[i] end
end
table.sort(counted)
ok(#counted == 3, "three opcodes state their own length",
   table.concat(counted, ", "), "three")
-- A COUNTED WIDTH WITH NO COUNT POSITION WOULD DECODE AS NIL AND STOP THE WALK
local missingAt = 0
for i = 0, Anim.OPCODE_COUNT - 1 do
  if Anim.WIDTHS[i] == Anim.COUNTED and Anim.COUNT_AT[i] == nil then
    missingAt = missingAt + 1
  end
end
ok(missingAt == 0, "...and each says which operand holds it", missingAt, 0)

-- ---------------------------------------------------------------------------
-- 2: CLOSURE, which is the check.
-- ---------------------------------------------------------------------------
io.write("\nwe.arc\n")
local rom = assert(NdsRom.open(romPath))
local raw = assert(rom:read(Anim.ARCHIVE_PROGRAMS),
                   Anim.ARCHIVE_PROGRAMS .. " is not in this cartridge")
local arc = assert(Narc.parse(raw), "we.arc did not parse as a NARC")
ok(arc.count == Anim.PROGRAM_COUNT, "we.arc holds one program per move slot",
   arc.count, Anim.PROGRAM_COUNT)

local decoded, failed, instructions = 0, {}, 0
local usedOps, particles, sounds = {}, {}, {}
local nUsed, nParticles, nSounds = 0, 0, 0
for i = 0, arc.count - 1 do
  local data = arc:get(i)
  local program, why, at = Anim.decode(data or "")
  if program then
    decoded = decoded + 1
    instructions = instructions + #program
    for _, row in ipairs(program) do
      if not usedOps[row.op] then usedOps[row.op] = true; nUsed = nUsed + 1 end
    end
    local s = Anim.summary(program)
    for _, m in ipairs(s.particles) do
      if not particles[m] then particles[m] = true; nParticles = nParticles + 1 end
    end
    for _, m in ipairs(s.sounds) do
      if not sounds[m] then sounds[m] = true; nSounds = nSounds + 1 end
    end
  elseif #failed < 5 then
    failed[#failed + 1] = ("%d: %s at word %s"):format(i, tostring(why), tostring(at))
  end
end
ok(decoded == arc.count, "EVERY program walks to its exact last word",
   ("%d of %d%s"):format(decoded, arc.count,
     #failed > 0 and ("; " .. table.concat(failed, "; ")) or ""),
   arc.count)
ok(instructions == 18620, "...over the measured instruction count",
   instructions, 18620)

-- A CANARY, BECAUSE CLOSURE CAN BE PASSED BY DECODING NOTHING. A walk that
-- stopped at the first instruction of every program would report 501 programs
-- and 501 instructions, and the count above is what separates the two -- but
-- only if the count is really being reached, so assert the shape as well.
ok(instructions > arc.count * 20,
   "...which is a real walk, not one instruction per program",
   ("%.1f instructions per program"):format(instructions / arc.count),
   "well over 1")

ok(nUsed == 59, "fifty-nine of the eighty-five opcodes ever occur", nUsed, 59)
ok(nParticles == 419 and nSounds == 262,
   "the corpus names this many particle files and sounds",
   ("%d particles, %d sounds"):format(nParticles, nSounds),
   "419 particles, 262 sounds")

-- ---------------------------------------------------------------------------
-- 3: THE TWO SOLVED WIDTHS, AND HOW SHARP THE SOLUTION IS.
--
-- These are the only widths here pret does not state, so they are the only ones
-- that could be a curve fit -- and a fit is exactly what the margin rules out.
-- ---------------------------------------------------------------------------
io.write("\nthe two widths pret cannot state\n")
local solvedNames = {}
for _, name in pairs(Anim.SOLVED) do solvedNames[#solvedNames + 1] = name end
table.sort(solvedNames)
ok(#solvedNames == 2 and solvedNames[1] == "nop4"
   and solvedNames[2] == "setextraparams",
   "exactly two, and named", table.concat(solvedNames, ", "),
   "nop4, setextraparams")

-- Re-solve the sharper of the two IN THIS RUN rather than quoting a number from
-- the margin: move the count to each neighbouring operand and re-walk the whole
-- corpus. The real reading has to beat every alternative outright.
local function closesWith(op, width, countAt)
  local saveW, saveAt = Anim.WIDTHS[op], Anim.COUNT_AT[op]
  Anim.WIDTHS[op], Anim.COUNT_AT[op] = width, countAt
  local n = 0
  for i = 0, arc.count - 1 do
    if Anim.decode(arc:get(i) or "") then n = n + 1 end
  end
  Anim.WIDTHS[op], Anim.COUNT_AT[op] = saveW, saveAt
  return n
end
local EXTRA = 55
local best = closesWith(EXTRA, Anim.COUNTED, 1)
local rivals = {}
for at = 2, 5 do rivals[#rivals + 1] = closesWith(EXTRA, Anim.COUNTED, at) end
local worst = rivals[1]
for _, v in ipairs(rivals) do if v > worst then worst = v end end
ok(best == arc.count, "setextraparams as <count> <values> closes everything",
   best, arc.count)
ok(worst < best - 20,
   "...and the next-best reading is not close",
   ("best %d, nearest rival %d"):format(best, worst), "a wide margin")

-- ---------------------------------------------------------------------------
-- 4: THE ONE PROGRAM THAT STARTED THIS.
-- ---------------------------------------------------------------------------
io.write("\nscratch\n")
local scratch = Anim.summary(Anim.decode(arc:get(10)))
ok(scratch ~= nil and #scratch.particles == 1 and scratch.particles[1] == 40,
   "Scratch loads exactly one particle file, number 40",
   scratch and table.concat(scratch.particles, ","), "40")
local pound = Anim.summary(Anim.decode(arc:get(1)))
ok(pound ~= nil and #pound.particles == 1 and pound.particles[1] ~= 40,
   "...and Pound loads a different one",
   pound and table.concat(pound.particles, ","), "not 40")
-- THE PARTICLE FILE HAS TO EXIST, which is the join this whole decode is for:
-- a member index that is in range but wrong looks identical to a right one, and
-- an out-of-range one is the only kind the data itself can refuse.
local praw = rom:read(Anim.ARCHIVE_PARTICLES)
local parc = praw and Narc.parse(praw)
ok(parc ~= nil and parc.count == Anim.PARTICLE_COUNT,
   "waza_particle.narc holds the stated number of effects",
   parc and parc.count, Anim.PARTICLE_COUNT)
local outOfRange = 0
for i = 0, arc.count - 1 do
  local program = Anim.decode(arc:get(i) or "")
  if program then
    for _, row in ipairs(program) do
      if row.op == Anim.PARTICLE_OP then
        local m = row.args[Anim.PARTICLE_ARG]
        if not m or not parc or m >= parc.count then outOfRange = outOfRange + 1 end
      end
    end
  end
end
ok(outOfRange == 0, "every particle index a program names is in range",
   outOfRange, 0)

-- ---------------------------------------------------------------------------
-- 5: DOES IT PLAY.
--
-- Decoding is half the claim; the other half is that every program can be RUN
-- to its own `end` without hanging. The player has a frame budget precisely so
-- a bad frame count cannot freeze a battle, and the budget being hit is the
-- failure this section exists to catch -- it caught nineteen programs the first
-- time, all of them the same two bugs: operands read UNSIGNED, so a pan of -117
-- arrived as four billion, and the scale command's frame operand being a PACKED
-- PAIR (0x00050005 is five out and five back, not a third of a million).
-- ---------------------------------------------------------------------------
io.write("\nplayback\n")
local Play = require("src.battle.Gen4MoveAnimPlayer")

-- the cache record, built exactly as the `move_anims` import stage builds it
local programs = {}
for i = 0, arc.count - 1 do
  local d = Anim.decode(arc:get(i) or "")
  if d then
    local code, wordAt = {}, {}
    for k, row in ipairs(d) do
      local ins = { row.op }
      for j = 1, #row.args do ins[j + 1] = row.args[j] end
      code[k] = ins
      wordAt[k] = row.at
    end
    local s = Anim.summary(d)
    programs[i] = { code = code, wordAt = wordAt, particles = s.particles,
                    sounds = s.sounds, delayFrames = s.delayFrames }
  end
end
-- AND THE PARTICLE INDEX, built the same way: `gen4_particles` holds one entry
-- per effect keyed "move_<member>", with the emitter list the running game
-- simulates. Building it here from the cartridge is what lets this check drive
-- the player's particle layer at all -- without it every `loadparticlesystem`
-- reports a missing member and the whole layer is untested.
local Particle = require("src.import.Gen4Particle")
local fxRaw = rom:read(Particle.ARCHIVE_MOVES)
local fxArc = fxRaw and Narc.parse(fxRaw)
local effects = {}
if fxArc then
  for member = 0, fxArc.count - 1 do
    local file = fxArc:get(member)
    local textures = file and Particle.textures(file)
    if textures then
      -- THE SAVED-IMAGE SHAPE, not the decoder's. The stage stores each texture
      -- as `{ path, width, height }` from `saveImage`, and the player hands that
      -- entry to whatever draws it -- so a stand-in index without `path` would
      -- test the motion and quietly skip the join to the art.
      local list = {}
      for i, texture in ipairs(textures) do
        list[i] = {
          path = ("assets/generated/gen4/particle/move_%03d_%d.png")
            :format(member, i - 1),
          width = texture.width, height = texture.height,
          format = texture.formatName,
        }
      end
      effects["move_" .. member] = { emitters = Particle.emitters(file) or nil,
                                     textures = list }
    end
  end
end
-- AND THE 2D CELL-ACTOR SPRITES, built the same way from the four archives the
-- `gen4_cellactors` stage reads. Without this every `addspritewithfunc` reports a
-- missing resource tuple and the whole third layer goes untested.
local Cells = require("src.import.Gen4Cells")
local CellAnim = require("src.import.Gen4CellAnim")
local Gfx = require("src.import.Gen4Graphics")
local function cellArchive(path)
  local bytes = rom:read(path)
  return bytes and Narc.parse(bytes) or nil
end
local charArc = cellArchive(CellAnim.ARCHIVE_CHAR)
local plttArc = cellArchive(CellAnim.ARCHIVE_PALETTE)
local cellArc = cellArchive(CellAnim.ARCHIVE_CELL)
local animArc = cellArchive(CellAnim.ARCHIVE_ANIM)
local function cellMember(a, i)
  if not (a and i) then return nil end
  local b = a:get(i)
  if not b then return nil end
  if Gfx.isCompressed(b) then b = Gfx.decompress(b) end
  return b
end
local spriteArt, spriteTuples = {}, 0
if charArc and plttArc and cellArc and animArc then
  for id = 0, arc.count - 1 do
    for _, ins in ipairs((programs[id] or {}).code or {}) do
      local op = ins[1]
      if op == 78 or op == 79 then
        local c, p, ce, an = ins[4], ins[5], ins[6], ins[7]
        local key = ("%s_%s_%s_%s"):format(tostring(c), tostring(p),
                                           tostring(ce), tostring(an))
        if not spriteArt[key] then
          local sheet = Gfx.tiles(cellMember(charArc, c))
          local colours = Gfx.palette(cellMember(plttArc, p))
          local cb = cellMember(cellArc, ce)
          local bank = cb and Cells.parse(cb, Gfx)
          local ab = cellMember(animArc, an)
          local anim = ab and CellAnim.parse(ab, Gfx)
          if sheet and colours and bank and anim then
            colours = CellAnim.paletteFor(colours, CellAnim.bankOf(bank))
            local images = {}
            for i, cell in ipairs(bank.cells) do
              if #(cell.oam or {}) > 0 then
                local image = Cells.assemble(cell, sheet, colours, bank, Gfx)
                if image then
                  images[i] = {
                    path = ("assets/generated/gen4/cellactor/%s_%02d.png")
                      :format(key, i - 1),
                    width = image.width, height = image.height,
                    cellIndex = i - 1,
                  }
                end
              end
            end
            spriteArt[key] = { cells = images, sequences = anim.sequences }
            spriteTuples = spriteTuples + 1
          end
        end
      end
    end
  end
end
local player = Play.new({
  gen4_move_anims = { programs = programs, count = arc.count },
  gen4_particles = { effects = effects },
  gen4_cellactors = { sprites = spriteArt },
})
ok(player ~= nil, "the player builds from a cache record", player ~= nil, true)

local started, budgets, longest, withSound, withMotion = 0, 0, 0, 0, 0
local missing = {}
if player then
  for id = 0, arc.count - 1 do
    if player:start(id, true) then
      started = started + 1
      local frames, motion = 0, false
      while player:update() do
        frames = frames + 1
        local dx, dy = player:monOffset(true)
        local ex, ey = player:monOffset(false)
        if dx ~= 0 or dy ~= 0 or ex ~= 0 or ey ~= 0 then motion = true end
        if frames > Play.Player.FRAME_BUDGET + 10 then break end
      end
      if frames > longest then longest = frames end
      if motion then withMotion = withMotion + 1 end
      if #player.sounds > 0 then withSound = withSound + 1 end
      if player.unsupported["frame budget"] or player.unsupported["step budget"] then
        budgets = budgets + 1
      end
      for what, n in pairs(player.unsupported) do
        missing[what] = (missing[what] or 0) + n
      end
      player.unsupported = {}
    end
  end
end
ok(started == arc.count, "every program starts", started, arc.count)
ok(budgets == 0, "NO program runs into the frame or step budget", budgets, 0)
ok(longest > 0 and longest < Play.Player.FRAME_BUDGET,
   "the longest run finishes well inside the budget",
   ("%d frames of %d"):format(longest, Play.Player.FRAME_BUDGET),
   "under budget")
-- ...AND IT IS A REAL RUN. A player that stopped at the first instruction of
-- every program would also report no budget hits, so assert that the corpus
-- actually produced sound and movement.
ok(withSound > 400, "most programs play a sound", withSound, "over 400")
-- EXACT, NOT A FLOOR. Nothing in this layer is random, and a floor here would be
-- satisfied by a shake that never stops -- which is the exact fault the waveform
-- section below exists for. 289 of the 501.
--
-- 289 AND NOT 287: `RevolveBattler` joined the functions that move one. Its eight
-- calls are over six programs, and two of those six moved a battler no other way --
-- so the count rose by the number of programs whose ONLY motion is the new orbit,
-- which is the shape a re-pointed total should have.
--
-- 290 AND NOT 289: the mon-sprite slots joined `monOffset`. The program that came
-- with them is 464, Dark Void, whose displacement lives entirely on a COPY of the
-- defender while the real battler is hidden -- so counting the battler transform
-- alone still gives 289 and counting what is actually on screen gives 290. MEASURED
-- BOTH WAYS rather than assumed: exactly one program differs and it is that one.
ok(withMotion == 290, "...and this many move a battler", withMotion, 290)

-- THE FRAME OF REFERENCE, which is the one rule here that is easy to get
-- backwards and impossible to see from a still. ATTACKER and DEFENDER are
-- relative to who used the move, so the same program run from each side must
-- produce MIRRORED x offsets -- an enemy's lunge goes the other way. Asserted
-- over the whole corpus rather than one move, because a sign error that only
-- shows on some targets would pass a single example.
local mirrored, compared, flipped, symmetric = 0, 0, 0, 0
if player then
  local function trace(id, isPlayer)
    local out = {}
    player:start(id, isPlayer)
    local f = 0
    while player:update() and f < 200 do
      f = f + 1
      local ax = player:monOffset(isPlayer)          -- the ATTACKER's own side
      out[#out + 1] = ax
    end
    player.unsupported = {}
    return out
  end
  -- A PROGRAM THAT BRANCHES ON THE BATTLER'S SIDE IS NOT COMPARABLE, and that
  -- is the point of it: `jumpifbattlerside` exists so the two sides run
  -- DIFFERENT code, so demanding their traces mirror would be asserting that
  -- the branch does nothing.
  local function branchesOnSide(id)
    for _, row in ipairs(programs[id] and programs[id].code or {}) do
      local n = Anim.OPCODES[row[1]]
      if n == "jumpifbattlerside" or n == "jumpiffriendlyfire" then return true end
    end
    return false
  end
  for id = 0, arc.count - 1 do
    local a, b = trace(id, true), trace(id, false)
    local moved = false
    if branchesOnSide(id) then a, b = {}, {} end
    for _, v in ipairs(a) do if v ~= 0 then moved = true break end end
    if moved and #a == #b then
      compared = compared + 1
      -- ELEMENT BY ELEMENT, MIRRORED OR EQUAL -- and the "or equal" is not a
      -- weakening. A program mixes the two: a SHAKE is symmetric and has no
      -- direction to flip, a LUNGE mirrors, and one program does both, so
      -- demanding the whole trace mirror would fail on the shake frames of a
      -- perfectly correct animation. What must never happen is a frame where
      -- the two sides are simply UNRELATED, and that is what this asserts.
      local consistent = true
      for i = 1, #a do
        if a[i] ~= -b[i] and a[i] ~= b[i] then consistent = false break end
        -- ...AND COUNT THE TWO KINDS SEPARATELY, which is the half that makes
        -- this able to fail at all. "Mirrored or equal" alone is satisfied by
        -- NEVER FLIPPING: both sides get the same offset and every frame is
        -- "equal". Planting exactly that fault passed the relaxed test, which
        -- is the classic way a check gets weakened past usefulness while
        -- looking stricter. So the flip has to be OBSERVED: some frame,
        -- somewhere in the corpus, must be nonzero and strictly opposite.
        if a[i] ~= 0 then
          if a[i] == -b[i] then flipped = flipped + 1
          elseif a[i] == b[i] then symmetric = symmetric + 1 end
        end
      end
      if consistent then mirrored = mirrored + 1 end
    end
  end
end
ok(compared > 0, "some programs move the attacker along x at all", compared,
   "more than none")
ok(compared > 0 and mirrored == compared,
   "every frame mirrors or matches when the enemy uses the move",
   ("%d of %d"):format(mirrored, compared), "all of them")
ok(flipped > 0, "...and the flip is really happening somewhere",
   ("%d flipped frames, %d symmetric"):format(flipped, symmetric),
   "more than 0 flipped")
ok(symmetric > 0, "...beside frames that are symmetric on purpose",
   symmetric, "more than 0")

-- WHAT IS MISSING IS NAMED, AND WHAT IS DELIBERATELY SKIPPED IS NOT IN IT.
-- `Player.NOT_NEEDED` is an argued list; anything on it showing up as a gap
-- means the two have drifted apart and the gap report has started lying.
local leaked = {}
for what in pairs(missing) do
  if Play.Player.NOT_NEEDED[what] then leaked[#leaked + 1] = what end
end
ok(#leaked == 0, "nothing on the deliberate-skip list is reported as missing",
   #leaked == 0 and "none" or table.concat(leaked, ", "), "none")
local gapCount = 0
for _ in pairs(missing) do gapCount = gapCount + 1 end
ok(gapCount > 0, "...and the real gaps are still reported",
   gapCount .. " kinds", "more than none")
-- The three layers, named: every gap should be a particle command, a background
-- command or a 2D cell command. A gap that is none of those is something this
-- player was supposed to handle and did not.
local unexplained = {}
for what in pairs(missing) do
  if not (what:find("emitter") or what:find("particle") or what:find("bg")
          or what:find("extraparams") or what:find("sprite") or what:find("res")
          or what:find("budget") or what:find("clamped") or what:find("cry")
          or what:find("cries") or what:find("wait:") or what:find("callfunc:")
          or what:find("spritemanager") or what:find("alphablending")
          or what:find("lrx") or what:find("sound")
          -- THE TWO BATTLER SLIDES ARE A NAMED GAP, not an oversight. They
          -- move a Pokemon right off the screen and back (Fly, Dig, a
          -- send-out), and the distance and direction are the cartridge's
          -- sprite geometry rather than anything in the program's operands --
          -- so implementing them by picking a plausible offset would be this
          -- port inventing motion, which is the one thing it does not do.
          or what == "startbattlerslidein" or what == "startbattlerslideout"
          -- THE PER-MOVE SPRITE MOTION IS A NAMED GAP, one entry per callback.
          -- `sBattleAnimSpriteFuncs` is thirty-three bespoke routines named after
          -- their moves -- Constrict squeezes, Bonemerang arcs out and back,
          -- FollowMe oscillates off a hand-written table -- and this port places
          -- the sprite where the cartridge places it and plays its animation,
          -- which is everything the layer shares. Inventing the motion would look
          -- deliberate and be wrong; the one generic callback,
          -- `OffsetAndAnimate`, IS implemented and so never appears here.
          or what:find("^sprite motion:")
          or what:find("^cellactor")) then
    unexplained[#unexplained + 1] = what
  end
end
ok(#unexplained == 0, "every gap is a particle, background or 2D-cell command",
   #unexplained == 0 and "all accounted for" or table.concat(unexplained, ", "),
   "all accounted for")

-- and the move that started all of this
if player then
  player:start(10, true)
  local frames = 0
  while player:update() and frames < 300 do frames = frames + 1 end
  ok(frames > 0, "Scratch runs for a nonzero number of frames", frames,
     "more than 0")
  ok(#player.sounds > 0, "...and plays at least one sound", #player.sounds,
     "at least 1")
end

-- ---------------------------------------------------------------------------
-- 6: IS ANYTHING ACTUALLY CALLING IT.
--
-- THIS IS THE SECTION THAT WOULD HAVE CAUGHT THE ORIGINAL REPORT. A move
-- animation engine that nothing constructs, ticks or reads is exactly what
-- Sinnoh had: `BattleState` built three animators behind `pcall`s and there was
-- no fourth, so every Platinum move played nothing and nothing errored. No
-- assertion about the player itself can see that -- the player was fine, it was
-- never asked -- so this reads the SOURCE, the way the roamer check reads it
-- for the three shared hooks.
-- ---------------------------------------------------------------------------
-- ---------------------------------------------------------------------------
-- THE PARTICLE LAYER, END TO END.
--
-- Everything above proves the PROGRAM runs. This proves the program's own
-- answer to "what does the player see": `loadparticlesystem` resolving to a
-- real effect, `createemitter` running one resource out of it, and
-- `waitforallemitters` holding the move open while the burst is in the air.
--
-- It is the section that would have caught the actual bug the player reported.
-- The program decoded, the player ran it, the effect was in the cache, and
-- `Data` never opened the file -- so `Gen4MoveAnimPlayer.new` returned nil and
-- Scratch showed nothing. Here the record is handed over directly, which tests
-- the layer; `tools/gen4_cache_wiring_check.lua` tests that the engine hands it
-- over at all. Both are needed and neither substitutes for the other.
-- ---------------------------------------------------------------------------
io.write("\nparticles, end to end\n")
local effectCount = 0
for _ in pairs(effects) do effectCount = effectCount + 1 end
ok(effectCount >= 450, "the particle index was built from the cartridge",
   effectCount .. " effects", "at least 450")
-- THE STAND-IN'S TEXTURE PATHS ARE SPELLED THE WAY THE STAGE SPELLS THEM, and
-- that is the one thing here duplicated from another file rather than read from
-- it -- so the format string is asserted to still exist over there. A rename in
-- the extractor with no matching change here would otherwise leave this section
-- testing a path shape the cache has not used for months.
do
  local f = io.open(root .. "../src/import/RomExtractorGen4.lua", "rb")
  local src = f and f:read("*a")
  if f then f:close() end
  ok(src ~= nil and src:find('particle/%s_%03d_%d', 1, true) ~= nil,
     "...and the stage still names its textures the same way",
     src ~= nil and (src:find('particle/%s_%03d_%d', 1, true) ~= nil)
       and "found" or "not found",
     "particle/%s_%03d_%d")
end

-- SCRATCH. `loadparticlesystem 0, 40` then its emitters, and by the end of the
-- program there has to be something on the screen.
local scratchDrew, scratchFrames, scratchPeak, scratchArt = 0, 0, 0, nil
if player and player:start(10, true) then
  local frames = 0
  while player:update() and frames < 400 do
    frames = frames + 1
    local list = player:particles()
    if #list > scratchPeak then scratchPeak = #list end
    scratchDrew = scratchDrew + #list
    for _, q in ipairs(list) do scratchArt = scratchArt or q.art end
  end
  scratchFrames = frames
end
ok(scratchDrew > 0, "SCRATCH PUTS PARTICLES ON THE SCREEN",
   scratchDrew .. " particle-frames", "more than 0")
ok(scratchPeak > 0 and scratchPeak < 400,
   "...a plausible number of them at once", scratchPeak, "between 1 and 400")
ok(scratchFrames > 1 and scratchFrames < 400,
   "...and the move ends on its own", scratchFrames .. " frames", "under 400")
-- THE ART IS JOINED, not just the motion: a draw record whose `art` is nil is a
-- particle at the right place with no picture, which draws nothing.
ok(scratchArt ~= nil and scratchArt.path ~= nil,
   "...and every particle knows which texture to draw",
   scratchArt and tostring(scratchArt.path) or "no art",
   "a path from the particle index")
ok(scratchArt ~= nil and (scratchArt.width or 0) > 0,
   "...at the size the cartridge stores it",
   scratchArt and ("%sx%s"):format(tostring(scratchArt.width),
                                   tostring(scratchArt.height)) or "-",
   "a real size")

-- THE WHOLE CORPUS. One move working is a demo; the number that work is the
-- measurement, and it is a floor so it cannot quietly fall.
local withParticles, played, longest = 0, 0, 0
if player then
  for id = 0, arc.count - 1 do
    if player:start(id, true) then
      played = played + 1
      local frames, drew = 0, 0
      while player:update() and frames < 400 do
        frames = frames + 1
        drew = drew + #player:particles()
      end
      if drew > 0 then withParticles = withParticles + 1 end
      if frames > longest then longest = frames end
    end
  end
end
ok(played >= 495, "every program still plays", played, "at least 495")
ok(withParticles >= 400, "AND THIS MANY MOVES DRAW PARTICLES",
   withParticles .. " of " .. played, "at least 400")
ok(longest > 0 and longest < 400, "...and none of them runs away",
   longest .. " frames", "under the 400-frame cap")

-- WHICH SIDE IS ATTACKING HAS TO CHANGE THE ANSWER.
--
-- `createemitterformove` carries SIX resource ids -- three orientations for the
-- player attacking and three for the enemy -- and this port takes the parallel
-- one for the attacking side. Making it always take the player's passed every
-- other assertion in this section: both sides still draw particles, they are
-- just the wrong ones for half the battle, which is exactly the kind of fault
-- that looks fine until somebody watches the opponent use the move.
if player then
  local probe = { 1, 11, 12, 13, 21, 22, 23, 5 }
  player.attackerIsPlayer = true
  local mine = player:resourceForMove(probe)
  player.attackerIsPlayer = false
  local theirs = player:resourceForMove(probe)
  ok(mine == 11, "the attacking player takes the player's parallel resource",
     mine, 11)
  ok(theirs == 21, "...and the attacking enemy takes the enemy's",
     theirs, 21)
  ok(mine ~= theirs, "...which are not the same resource", mine ~= theirs, true)
end

-- AND THE WAIT IS NOT FREE ANY MORE.
--
-- THE FIRST VERSION OF THIS MEASURED THE WRONG THING. It compared a move's total
-- length against the sum of its delays, reasoning that a blocking wait must make
-- the move longer -- and planting "make the wait free" passed it. The reason is
-- the player's own tail: a program that reaches `end` with particles still in
-- the air keeps running until they die, which is correct and which makes the
-- TOTAL length identical either way. Nine assertions in this section and none of
-- them could see it.
--
-- So the thing itself is counted: how many frames the program spent HELD at the
-- wait. A free wait spends none, whatever the move's length comes out as.
local waited, heldFrames = 0, 0
if player then
  for id = 0, arc.count - 1 do
    local record = programs[id]
    local waits = false
    for _, ins in ipairs(record and record.code or {}) do
      if Anim.OPCODES[ins[1]] == "waitforallemitters" then waits = true end
    end
    if waits and player:start(id, true) then
      local frames = 0
      while player:update() and frames < 400 do frames = frames + 1 end
      local delays = record.delayFrames or 0
      if frames > delays then waited = waited + 1 end
      heldFrames = heldFrames + (player.emitterWaits or 0)
    end
  end
end
ok(waited >= 300, "...and this many moves last longer than their delays alone",
   waited, "at least 300")
ok(heldFrames >= 3000,
   "AND THE PROGRAMS ARE REALLY HELD AT THE WAIT, for this many frames",
   heldFrames, "at least 3000")

-- ---------------------------------------------------------------------------
-- THE 2D CELL-ACTOR LAYER, END TO END -- the third and last of a move's three
-- visible layers, and the one that drew nothing at all until now.
--
-- Its format had NO reference to read: pret expects the NitroSystem headers for
-- the animation bank and does not ship them, so `Gen4CellAnim` was derived, and
-- the derivation closes twice -- every sequence tiles the file's frame array
-- exactly, and every frame names a cell that exists in the matching NCER.
-- ---------------------------------------------------------------------------
io.write("\nthe 2D cell actors\n")
ok(spriteTuples == 29, "the sprite art was built for every tuple the programs name",
   spriteTuples, 29)

-- THE ANIMATION BANKS CLOSE. 37 members, 53 sequences, 186 frames, and the frame
-- array is tiled exactly -- which is what fixed the sequence stride at 16 and the
-- offsets' base at 24 without either being assumed.
local anmMembers, anmSequences, anmFrames, anmBad = 0, 0, 0, {}
if animArc then
  for i = 0, animArc.count - 1 do
    local good, s, f = CellAnim.check(animArc:get(i), Gfx)
    if good then
      anmMembers = anmMembers + 1
      anmSequences = anmSequences + s
      anmFrames = anmFrames + f
    elseif #anmBad < 4 then
      anmBad[#anmBad + 1] = ("member %d: %s"):format(i, tostring(s))
    end
  end
end
ok(anmMembers == 37 and #anmBad == 0,
   "EVERY animation bank parses, and its sequences tile its frame array",
   #anmBad == 0 and (anmMembers .. " of 37")
     or table.concat(anmBad, "; "), "37 of 37")
ok(anmSequences == 53 and anmFrames == 186,
   "...over this many sequences and frames",
   ("%d sequences, %d frames"):format(anmSequences, anmFrames),
   "53 and 186")
-- THE CROSS-ARCHIVE TEST, which is the strong one: wecellanm's frames against
-- wecell's cell counts. A wrong result offset names a cell that does not exist.
local crossBad, crossChecked = {}, 0
if animArc and cellArc then
  for i = 0, math.min(animArc.count, cellArc.count) - 1 do
    local anim = CellAnim.parse(animArc:get(i), Gfx)
    local cb = cellMember(cellArc, i)
    local bank = cb and Cells.parse(cb, Gfx)
    if anim and bank then
      for si, seq in ipairs(anim.sequences) do
        for _, fr in ipairs(seq.frames) do
          crossChecked = crossChecked + 1
          if fr.cell >= bank.count and #crossBad < 4 then
            crossBad[#crossBad + 1] = ("m%d seq %d names cell %d of %d")
              :format(i, si, fr.cell, bank.count)
          end
        end
      end
    end
  end
end
ok(crossChecked == 186 and #crossBad == 0,
   "...and EVERY frame names a cell its own bank contains",
   #crossBad == 0 and (crossChecked .. " frames")
     or table.concat(crossBad, "; "), "186, all valid")

-- THE ART HAS PIXELS IN IT, and member 0 is why this is asserted separately.
--
-- Its cell bank's OAM entries ask for PALETTE BANK 9 -- the only member of 37
-- that does not use bank 0 -- and the file's palette holds one bank. Handing
-- `compose` the file as-is makes every lookup miss and produces four perfectly
-- shaped, perfectly transparent 184x64 rectangles. Padding the colours up so the
-- wanted bank lands on them is what `Gen4CellAnim.paletteFor` does, and it is the
-- difference between 20,125 opaque pixels and none.
--
-- ON THE HARDWARE the OAM bank is an index into OBJ palette memory, which every
-- sprite on screen shares; this port has no such memory, so the member's own
-- palette is taken to be whatever ended up in the bank it asks for. That is a
-- reduction, and it is the only reading available with one palette per sprite.
local function opaqueOf(char, palette)
  local sheet = Gfx.tiles(cellMember(charArc, char))
  local colours = Gfx.palette(cellMember(plttArc, palette))
  local cb = cellMember(cellArc, char)
  local bank = cb and Cells.parse(cb, Gfx)
  if not (sheet and colours and bank) then return nil end
  colours = CellAnim.paletteFor(colours, CellAnim.bankOf(bank))
  local total = 0
  for _, cell in ipairs(bank.cells) do
    if #(cell.oam or {}) > 0 then
      local image = Cells.assemble(cell, sheet, colours, bank, Gfx)
      if image then
        for n = 4, #image.rgba, 4 do
          if image.rgba:byte(n) > 0 then total = total + 1 end
        end
      end
    end
  end
  return total
end
if charArc and plttArc and cellArc then
  local bank0 = Cells.parse(cellMember(cellArc, 0), Gfx)
  ok(CellAnim.bankOf(bank0) == 9,
     "member 0's cell bank asks for palette bank 9, alone among the 37",
     CellAnim.bankOf(bank0), 9)
  local zero = opaqueOf(0, 0)
  ok(zero ~= nil and zero >= 20125,
     "...AND IT STILL DRAWS PIXELS, which without the padding it does not",
     tostring(zero), "at least 20125")
  local one = opaqueOf(1, 1)
  ok(one ~= nil and one > 500, "...and a bank-0 member is unaffected by it",
     tostring(one), "over 500")
  -- AND NOT ONE PALETTE READS PAST ITS OWN SECTION. Every member of wepltt states
  -- 480 bytes inside a 56-byte section -- the stated size is a VRAM allocation --
  -- so an unclamped reader returns about twenty real colours followed by whatever
  -- bytes came next, which is a palette that half works.
  local over, palettes = 0, 0
  for i = 0, plttArc.count - 1 do
    local bytes = cellMember(plttArc, i)
    local container = bytes and Gfx.container(bytes)
    local section = container and container.sections.TTLP
    local colours = bytes and Gfx.palette(bytes)
    if section and colours then
      palettes = palettes + 1
      if #colours > math.floor((section.size - 16) / 2) then over = over + 1 end
    end
  end
  ok(palettes == 39, "every move-effect palette was read", palettes, 39)
  ok(over == 0, "...and not one of them reads past its own section", over, 0)
end

-- AND THE LAYER RUNS. A sprite is placed, its animation ticks, and the sprite
-- lives exactly as long as its sequence -- which is pret's rule: the task deletes
-- it the frame `ManagedSprite_IsAnimated` goes false.
local cellPrograms, spriteFrames, withArt, blankFrames = 0, 0, 0, 0
local peakSprites, callbacks, usedBeforeLoad = 0, {}, 0
local longestCellProgram = 0
if player then
  for id = 0, arc.count - 1 do
    local uses = false
    for _, ins in ipairs((programs[id] or {}).code or {}) do
      if ins[1] == 78 or ins[1] == 79 then uses = true end
    end
    if uses and player:start(id, true) then
      cellPrograms = cellPrograms + 1
      local frames, peak = 0, 0
      while player:update() and frames < 500 do
        frames = frames + 1
        local list = player:cells()
        spriteFrames = spriteFrames + #list
        if #list > peak then peak = #list end
        for _, s in ipairs(list) do
          if s.blank then blankFrames = blankFrames + 1
          elseif s.art then withArt = withArt + 1 end
          if s.func then callbacks[s.func] = true end
        end
      end
      if peak > peakSprites then peakSprites = peak end
      if frames > longestCellProgram then longestCellProgram = frames end
      for _, row in ipairs(player:missing()) do
        if row.what:find("used before loading") then
          usedBeforeLoad = usedBeforeLoad + row.count
        end
      end
    end
  end
end
ok(cellPrograms == 31, "this many programs add a 2D sprite", cellPrograms, 31)
-- EXACT, NOT A FLOOR. There is no randomness anywhere in this layer -- the
-- durations are read and the cells are read -- so the total is reproducible, and
-- a floor would not notice a sprite that NEVER DIES. pret deletes the sprite the
-- frame its sequence runs out; removing that made every one of these programs run
-- to the 500-frame cap and sailed past a "more than 733" assertion.
--
-- THE NUMBER MORE THAN DOUBLED, 733 to 1892, AND EVERY PART OF THAT IS A FIX:
-- MetalClaw now puts four claws up where the script only adds one, the player's
-- tail is no longer one frame long, and a callback's task no longer runs on the
-- frame its sprite is created. A total on its own could not tell any of those
-- from a runaway, which is why sections 10 and 11 below measure each callback's
-- own count, placement and lifetime and this line is only the sum.
--
-- IT ALSO WENT DOWN BY 38 WHEN TWO MORE CALLBACKS WERE APPLIED, and that is a fix
-- as well: a callback OWNS its sprite's lifetime, and both of the new ones end it
-- somewhere other than the end of its animation. ScaryFace's face is deleted
-- after about 43 frames though its sequence is 114 long (so 71 frames of it never
-- play, twice over); Foresight's eye lives 107 frames on a sequence of 4. A
-- lifetime taken from the animation was wrong in both directions at once.
ok(spriteFrames == 1892, "A SPRITE IS ON THE SCREEN FOR THIS MANY FRAMES",
   spriteFrames, 1892)
ok(withArt == 1741, "...of which this many carry a picture", withArt, 1741)
ok(longestCellProgram > 0 and longestCellProgram < 200,
   "...and no program with a sprite in it runs away",
   longestCellProgram .. " frames", "under 200")
-- THE BLANK FRAMES ARE A FEATURE, NOT A SHORTFALL: cell 0 of members 17, 19 and
-- 26 has no OAM entries and their own animations name it, a beat of nothing
-- before the sprite appears. Counted apart so the two cannot be confused.
-- 151 NOW, NOT 79, AND THE EXTRA SEVENTY-TWO ARE DELIBERATE: MetalClaw's four
-- claws all spend the frame they are created on animation frame 0, and its right
-- pair spends ten more there while the delay runs -- and frame 0 of that bank is
-- one of these empty cells. Per move that is 2 * 1 + 2 * 11 = 24, and there are
-- three such moves.
ok(blankFrames == 151, "...and the rest are the cartridge's own blank frames",
   blankFrames, 151)
ok(withArt + blankFrames == spriteFrames, "...which accounts for every one",
   withArt .. " + " .. blankFrames, spriteFrames)
ok(peakSprites > 0 and peakSprites <= 10,
   "no program puts more sprites up than the manager allows",
   peakSprites, "between 1 and 10")
-- AND FOUR IS THE MOST ANY PROGRAM MANAGES, which is MetalClaw's four claws: the
-- one callback in the cartridge that multiplies its sprite.
ok(peakSprites == 4, "...and the busiest is MetalClaw's four", peakSprites, 4)
-- pret: "All resource indices specified here must have been previously loaded."
-- True on all 38 in the cartridge, so any failure means the program is not being
-- read the way it runs -- most likely the resource operands being taken for
-- manager slots rather than NARC member indices, which is exactly what they look
-- like.
ok(usedBeforeLoad == 0,
   "every sprite names a resource its own program loaded first",
   usedBeforeLoad .. " used before loading", 0)
-- TWENTY-FIVE DISTINCT PER-MOVE CALLBACKS occur, and they are named rather than
-- numbered so `missing()` says which move's routine is absent.
local callbackCount = 0
for _ in pairs(callbacks) do callbackCount = callbackCount + 1 end
ok(callbackCount == 25, "this many distinct sprite callbacks occur",
   callbackCount, 25)

-- THE ONE GENERIC CALLBACK IS IMPLEMENTED, and move 265 is the proof: it passes
-- `0 24 0`, so the sprite sits 24 above the defender. Any other callback leaves
-- the offset at zero and says so through `missing()`.
if player and player:start(265, true) then
  local offset = nil
  local frames = 0
  while player:update() and frames < 200 do
    frames = frames + 1
    for _, s in ipairs(player:cells()) do
      offset = offset or { s.x, s.y, s.func }
    end
  end
  ok(offset ~= nil and offset[3] == "OffsetAndAnimate",
     "move 265's sprite uses the one generic callback",
     offset and tostring(offset[3]) or "no sprite", "OffsetAndAnimate")
  ok(offset ~= nil and offset[1] == 0 and offset[2] == 24,
     "...and it is offset by the two script vars the command carries",
     offset and ("%s,%s"):format(tostring(offset[1]), tostring(offset[2]))
       or "-", "0,24")
end

-- WHICH SEQUENCE A SPRITE PLAYS, AND IT IS NOT ALWAYS THE FIRST.
--
-- Twelve of the 37 animation banks hold more than one sequence -- nine hold two
-- and three hold more -- and nothing in the SCRIPT selects one. The CALLBACK
-- does: thirteen of the twenty-six call `ManagedSprite_SetAnim`, and three of
-- them with a rule pret states plainly. Playing the first was right by luck for
-- the 25 single-sequence banks and wrong for the rest whenever the battle ran the
-- other way up.
local oneSeq, twoSeq, moreSeq = 0, 0, 0
if animArc then
  for i = 0, animArc.count - 1 do
    local anim = CellAnim.parse(animArc:get(i), Gfx)
    local n = anim and #anim.sequences or 0
    if n == 1 then oneSeq = oneSeq + 1
    elseif n == 2 then twoSeq = twoSeq + 1
    elseif n > 2 then moreSeq = moreSeq + 1 end
  end
end
ok(oneSeq == 25 and twoSeq == 9 and moreSeq == 3,
   "this many banks hold one sequence, two, or more",
   ("%d / %d / %d"):format(oneSeq, twoSeq, moreSeq), "25 / 9 / 3")
ok(twoSeq + moreSeq == 12,
   "...so this many have a sequence to choose", twoSeq + moreSeq, 12)

-- THE THREE RULES, DRIVEN BOTH WAYS UP. Metronome (move 118) and FollowMe (266)
-- take sequence 1 when the ATTACKER is the enemy; Fissure (90) when the DEFENDER
-- is the player -- which is the same test read from the other end, so with the
-- player attacking all three want 0 and with the enemy attacking all three want 1.
-- A rule that ignored the side would give the same answer twice.
local sequenceRows = {
  { move = 118, name = "Metronome" },
  { move = 266, name = "FollowMe" },
  { move = 90, name = "Fissure" },
}
local sequenceDrift = {}
if player then
  for _, row in ipairs(sequenceRows) do
    for _, side in ipairs({ true, false }) do
      local want = side and 0 or 1
      local got = nil
      if player:start(row.move, side) then
        local frames = 0
        while player:update() and frames < 300 do
          frames = frames + 1
          for _, s in ipairs(player:cells()) do got = got or s.sequence end
        end
      end
      if got ~= want then
        sequenceDrift[#sequenceDrift + 1] =
          ("%s with %s attacking played %s, not %d")
            :format(row.name, side and "the player" or "the enemy",
                    tostring(got), want)
      end
    end
  end
end
ok(#sequenceDrift == 0,
   "MOVE 118, 266 AND 90 EACH PICK THEIR SEQUENCE BY THE SIDE",
   #sequenceDrift == 0 and "all six ways round agree"
     or table.concat(sequenceDrift, "; "), "all six")

-- FISSURE'S CRACK OPENS AT AN ABSOLUTE HEIGHT, not an offset from a battler: 126
-- when the defender is on the player's side and 32 when it is on the enemy's,
-- both screen coordinates out of `script_funcs_3.c`.
local fissureDrift = {}
if player then
  for _, side in ipairs({ true, false }) do
    local want = side and 32 or 126
    local got = nil
    if player:start(90, side) then
      local frames = 0
      while player:update() and frames < 300 do
        frames = frames + 1
        for _, s in ipairs(player:cells()) do got = got or s.absoluteY end
      end
    end
    if got ~= want then
      fissureDrift[#fissureDrift + 1] = ("%s attacking gave %s, not %d")
        :format(side and "player" or "enemy", tostring(got), want)
    end
  end
end
ok(#fissureDrift == 0,
   "...and its height is absolute, and swaps with the side",
   #fissureDrift == 0 and "126 and 32, the right way round"
     or table.concat(fissureDrift, "; "), "126 and 32")
-- AND ONLY THE TWO CALLBACKS THAT NEED ONE CLAIM AN ABSOLUTE POSITION: Fissure,
-- whose crack opens at a fixed screen height, and IcicleSpear, which flies a path
-- between the two battlers. A third appearing would mean a rule had been copied
-- where it does not belong.
local absoluteCount, spritesSeen, absoluteFuncs = 0, 0, {}
if player then
  for id = 0, arc.count - 1 do
    local uses = false
    for _, ins in ipairs((programs[id] or {}).code or {}) do
      if ins[1] == 78 or ins[1] == 79 then uses = true end
    end
    if uses and player:start(id, true) then
      local frames, counted = 0, {}
      while player:update() and frames < 300 do
        frames = frames + 1
        for _, s in ipairs(player:cells()) do
          if not counted[s.key .. tostring(s.func)] then
            counted[s.key .. tostring(s.func)] = true
            spritesSeen = spritesSeen + 1
            if s.absoluteY then absoluteCount = absoluteCount + 1 end
            if s.func then absoluteFuncs[s.func] = s.absoluteY ~= nil end
          end
        end
      end
    end
  end
end
ok(spritesSeen > 20, "enough sprites inspected for their placement",
   spritesSeen, "over 20")
ok(absoluteCount == 2, "...and exactly two of them sit at an absolute position",
   absoluteCount, 2)
do
  local named, wrong = {}, {}
  for func, isAbsolute in pairs(absoluteFuncs) do
    if isAbsolute then named[#named + 1] = func end
  end
  table.sort(named)
  for _, func in ipairs(named) do
    if func ~= "Fissure" and func ~= "IcicleSpear" then wrong[#wrong + 1] = func end
  end
  ok(#named == 2 and #wrong == 0,
     "...and they are Fissure and IcicleSpear, by name",
     table.concat(named, " and "), "Fissure and IcicleSpear")
end

-- AND NO SPRITE ASKS FOR A SEQUENCE ITS BANK DOES NOT HAVE. The clamp counts
-- itself, so this is the number that says the rules and the data agree.
local clamped = 0
if player then
  for id = 0, arc.count - 1 do
    if player:start(id, true) then
      for _, row in ipairs(player:missing()) do
        if row.what:find("^sequence %d") then clamped = clamped + row.count end
      end
    end
    if player:start(id, false) then
      for _, row in ipairs(player:missing()) do
        if row.what:find("^sequence %d") then clamped = clamped + row.count end
      end
    end
  end
end
ok(clamped == 0, "no sprite asks for a sequence its bank does not have",
   clamped .. " clamped", 0)
-- ...AND THE COUNTER THAT SAYS SO IS NOT A CONSTANT ZERO. Nothing in the
-- cartridge clamps, so "0 clamped" passes with the report deleted -- the same
-- shape as a floor nothing can cross. Forced on a SYNTHETIC sprite: a
-- single-sequence bank asked for sequence 1 must say so.
do
  local singleKey = nil
  if animArc then
    for key, art in pairs(spriteArt) do
      if art.sequences and #art.sequences == 1 then singleKey = key break end
    end
  end
  local reported = false
  if player and singleKey then
    local char, pltt, cell, anim = singleKey:match("^(%d+)_(%d+)_(%d+)_(%d+)$")
    player:start(1, false)          -- the enemy attacking, so the rule wants 1
    player.managers = {}
    player:initSpriteManager(0, {})
    player:loadSpriteResource("char", 0, tonumber(char))
    player:loadSpriteResource("cell", 0, tonumber(cell))
    player:loadSpriteResource("anim", 0, tonumber(anim))
    -- funcID 4 is Metronome's rule: sequence 1 when the enemy attacks.
    player:addSprite(0, 4, tonumber(char), tonumber(pltt), tonumber(cell),
                     tonumber(anim), nil)
    for _, row in ipairs(player:missing()) do
      if row.what:find("^sequence 1 of") then reported = true end
    end
  end
  ok(singleKey ~= nil, "a single-sequence bank was found to force the clamp",
     singleKey or "none", "one of them")
  ok(reported, "...and asking it for sequence 1 is reported, not swallowed",
     reported, true)
end

-- THE OFFSETS ARE SIGNED, asserted on a SYNTHETIC sprite because the cartridge
-- cannot settle it: the one move that uses the generic callback passes `0 24`, so
-- forcing the X offset to zero changes nothing observable. Move 333 does pass
-- negatives -- -15, -5 -- to a callback this port does not implement, which is
-- what says the arguments arrive unsigned and must be signed here.
if player and next(spriteArt) then
  local key = next(spriteArt)
  local char, pltt, cell, anim = key:match("^(%d+)_(%d+)_(%d+)_(%d+)$")
  if char then
    player:start(1, true)
    player.managers = {}
    player:initSpriteManager(0, {})
    player:loadSpriteResource("char", 0, tonumber(char))
    player:loadSpriteResource("cell", 0, tonumber(cell))
    player:loadSpriteResource("anim", 0, tonumber(anim))
    -- funcID 25, with the two offsets written the way the cartridge writes
    -- negatives: as unsigned 32-bit words. They go through the SCRIPT VARS,
    -- because that is where the handler puts them -- the sign is applied on the
    -- way in and `addSprite` has no argument list of its own to be wrong about.
    player.vars[0] = signedWord(4294967281)
    player.vars[1] = signedWord(4294967291)
    local added = player:addSprite(0, 25, tonumber(char), tonumber(pltt),
                                  tonumber(cell), tonumber(anim))
    local got = added and player:cells()[1] or nil
    ok(got ~= nil and got.x == -15 and got.y == -5,
       "a sprite offset arrives SIGNED, not as four billion",
       got and ("%s,%s"):format(tostring(got.x), tostring(got.y)) or "no sprite",
       "-15,-5")
  end
end

-- ---------------------------------------------------------------------------
-- 9: THE FIXED-POINT PRIMITIVES, against the cartridge's own sine table
--
-- `Gen4AnimMath` is a port of pret's `battle_anim_helpers.c`, and the one part of
-- it that can be checked against the CARTRIDGE rather than against the C is the
-- sine table: NitroSystem's interleaved sin/cos pairs are linked into Platinum's
-- ARM9, and pret does not ship NitroSystem, so the table is the only witness.
-- The port computes the values instead of reading them, which is only allowed if
-- the two agree on all 4096 entries -- so both are produced here and compared.
-- ---------------------------------------------------------------------------
io.write("\nthe fixed-point primitives\n")

local Math4 = require("src.battle.Gen4AnimMath")
ok(Math4.check(), "the arithmetic identities hold", Math4.check(), true)

local arm9 = rom.arm9 and rom:arm9() or nil
ok(type(arm9) == "string" and #arm9 > 0x100000,
   "the ARM9 comes out of the cartridge", arm9 and #arm9 or "nil", "over 1MB")

local sinT, cosT = Math4.sinCosTable()
if type(arm9) == "string" then
  -- The signature is the first six PAIRS -- 24 bytes. Long enough to be unique
  -- in a megabyte and short enough that the other 4090 entries are an
  -- independent measurement rather than a restatement of it.
  local sig = {}
  for i = 0, 5 do
    local s, c = sinT[i], cosT[i]
    sig[#sig + 1] = string.char(s % 256, math.floor(s / 256) % 256,
                                c % 256, math.floor(c / 256) % 256)
  end
  sig = table.concat(sig)
  local at = arm9:find(sig, 1, true)
  ok(at ~= nil, "NitroSystem's sin/cos table is in the ARM9",
     at and ("0x%X"):format(at - 1) or "not found",
     ("0x%X"):format(Math4.SIN_TABLE_ARM9_OFFSET))
  if at then
    ok(at - 1 == Math4.SIN_TABLE_ARM9_OFFSET,
       "...at the offset the port records", ("0x%X"):format(at - 1),
       ("0x%X"):format(Math4.SIN_TABLE_ARM9_OFFSET))
    ok(arm9:find(sig, at + 1, true) == nil,
       "...and nowhere else in it", arm9:find(sig, at + 1, true) == nil, true)
    -- ALL 4096 ENTRIES. A table that agreed on the first few and drifted later
    -- would put every arc a pixel out at exactly the angles that matter.
    local mismatch, worst = 0, 0
    for i = 0, Math4.SIN_TABLE_SIZE - 1 do
      local o = at + i * 4
      local lo, hi = arm9:byte(o), arm9:byte(o + 1)
      local s = lo + hi * 256
      if s >= 32768 then s = s - 65536 end
      local lo2, hi2 = arm9:byte(o + 2), arm9:byte(o + 3)
      local c = lo2 + hi2 * 256
      if c >= 32768 then c = c - 65536 end
      if s ~= sinT[i] or c ~= cosT[i] then
        mismatch = mismatch + 1
        local ds, dc = math.abs(s - sinT[i]), math.abs(c - cosT[i])
        if ds > worst then worst = ds end
        if dc > worst then worst = dc end
      end
    end
    ok(mismatch == 0,
       "...and every one of its 4096 entries is what the port computes",
       mismatch == 0 and "4096 of 4096" or (mismatch .. " differ, worst " .. worst),
       "4096 of 4096")
  end
end

-- THE THREE ROUNDINGS ARE NOT INTERCHANGEABLE, and this is the case that proves
-- it. `ValueLerpContext_Init` divides with the hardware divider (truncating
-- toward zero) and then shifts the result down by 12 (flooring), and IcicleSpear
-- flying left is the one call in the cartridge where the two rules disagree:
-- -7282 index units over ten frames is -728.2, which floors to -729 and
-- truncates to -728. A port that used one rule for both would rotate the icicle
-- ten index units short over its flight.
do
  local rev = Math4.valueLerp(-Math4.degToIdx(90), -Math4.degToIdx(130), 10)
  ok(rev.step == -729, "a value lerp floors its step, it does not truncate",
     rev.step, -729)
  local fwd = Math4.valueLerp(Math4.degToIdx(20), Math4.degToIdx(130), 10)
  ok(fwd.step == 2002, "...and the same arithmetic the other way is 2002",
     fwd.step, 2002)
end

-- A SCALE IS AN INTEGER RATIO. Swagger's 14 against a reference of 10 is
-- 14 * 256 / 10 = 358 and not 358.4, so its vein peaks at 1.3984x and not 1.4x.
ok(Math4.relativeScale(14, 10) == 358 and Math4.relativeScale(12, 10) == 307,
   "a relative scale is integer division",
   Math4.relativeScale(14, 10) .. " and " .. Math4.relativeScale(12, 10),
   "358 and 307")

-- AND A FADE COSTS steps + 1 FRAMES, because the task that runs it is created at
-- priority 0 by a callback at 1100 and therefore steps BEFORE the state machine
-- reads it. This is the number that makes FakeOut's sprite last its animation
-- plus twenty frames rather than plus eighteen.
do
  local fade = Math4.alphaFade(0, 16, 16, 0, 8)
  local pumps = 0
  while not Math4.alphaFadeDone(fade) and pumps < 40 do
    pumps = pumps + 1
    Math4.alphaFadeUpdate(fade)
  end
  ok(pumps == 9, "an eight-frame fade reports done on the ninth", pumps, 9)
  ok(fade.x == 16, "...having reached its end value exactly", fade.x, 16)
end

-- WHERE THE BATTLERS STAND IS STATED IN TWO FILES and they must agree: the
-- player needs pixels for the callbacks that fly between battlers, the screen
-- needs them to place everything else, and a port where the two drifted would
-- draw an icicle that misses.
do
  local gbPath = (root ~= "" and root or "./") .. "../src/battle/Gen4Battle.lua"
  local gbFile = io.open(gbPath, "rb")
  local gb = gbFile and gbFile:read("*a")
  if gbFile then gbFile:close() end
  -- NOT `gb and gb:match(...)`: an `and` expression is truncated to ONE value in
  -- a multiple assignment, so that spelling silently drops every capture but the
  -- first and the Y of both battlers arrives nil.
  local px, py, ex, ey
  if gb then
    px, py = gb:match("%[0%]%s*=%s*{%s*x%s*=%s*(%-?%d+),%s*y%s*=%s*(%-?%d+)")
    ex, ey = gb:match("%[1%]%s*=%s*{%s*x%s*=%s*(%-?%d+),%s*y%s*=%s*(%-?%d+)")
  end
  local me = Play.Player.BATTLER_POS and Play.Player.BATTLER_POS.player
  local foe = Play.Player.BATTLER_POS and Play.Player.BATTLER_POS.enemy
  local agree = me and foe and px and ex
    and tonumber(px) == me.x and tonumber(py) == me.y
    and tonumber(ex) == foe.x and tonumber(ey) == foe.y
  ok(agree == true, "the player and the screen agree where the battlers stand",
     me and ("%s,%s and %s,%s vs %s,%s and %s,%s")
       :format(tostring(me.x), tostring(me.y), tostring(foe.x), tostring(foe.y),
               tostring(px), tostring(py), tostring(ex), tostring(ey))
       or "no table",
     "the same four numbers")
end

-- ---------------------------------------------------------------------------
-- 10: THE FIVE CALLBACKS THIS PORT APPLIES, one measurement each
--
-- A callback is a state machine plus a per-frame task, and what a port can be
-- wrong about is the COUNT of sprites, the PLACEMENT, the LIFETIME and the
-- per-frame channel each one drives. Every assertion below is one of those four
-- on one named move, taken by running the program and looking.
--
-- Seven callbacks are applied; section 11 covers the two that reach a BATTLER
-- rather than only their own sprite.
-- ---------------------------------------------------------------------------
io.write("\nthe sprite callbacks that are applied\n")

-- run(move, attackerIsPlayer) -> frames, rows, endedAt
--   `rows[f]` is `cells()` on frame f; `endedAt` is the frame the SCRIPT stopped,
--   which is not the frame the last sprite went.
local function runSprites(move, attackerIsPlayer, cap)
  if not (player and player:start(move, attackerIsPlayer)) then return nil end
  local rows, frames, endedAt = {}, 0, nil
  while player:update() and frames < (cap or 400) do
    frames = frames + 1
    rows[frames] = player:cells()
    if endedAt == nil and player.playing == false then endedAt = frames end
  end
  return frames, rows, endedAt
end

-- 22 MetalClaw: FOUR claws, two of them flipped, at the corners of a 64x32 box,
-- for exactly forty frames.
do
  local frames, rows, endedAt = runSprites(232, true)
  ok(frames ~= nil, "move 232 runs", frames, "a frame count")
  if frames then
    local peak, first, last, seen = 0, nil, nil, {}
    local flipped, blanks, blanksOnRight = 0, 0, 0
    for f = 1, frames do
      local n = #rows[f]
      if n > peak then peak = n end
      if n > 0 then first = first or f; last = f end
      for _, s in ipairs(rows[f]) do
        local at = ("%d,%d"):format(s.x or 0, s.y or 0)
        if not seen[at] then
          seen[at] = true
          if s.flipX then flipped = flipped + 1 end
        end
        if s.blank then
          blanks = blanks + 1
          if (s.x or 0) > 0 then blanksOnRight = blanksOnRight + 1 end
        end
      end
    end
    ok(peak == 4, "MetalClaw puts FOUR claws up, not the one the script adds",
       peak, 4)
    local want = { ["-32,0"] = true, ["-32,32"] = true,
                   ["32,0"] = true, ["32,32"] = true }
    local places, missing = 0, {}
    for at in pairs(want) do
      if seen[at] then places = places + 1 else missing[#missing + 1] = at end
    end
    ok(places == 4, "...at the four corners of a 64x32 box round the defender",
       places == 4 and "-32/+32 by 0/+32" or table.concat(missing, " "),
       "all four")
    ok(flipped == 2, "...with the left pair mirrored", flipped, 2)
    -- FORTY FRAMES, AND THE COUNTER SAYS SO, NOT THE ANIMATION: member 17's
    -- sequence is 42 frames long, so a lifetime taken from the animation would
    -- run two frames past the cartridge's. Forty DRAWN frames -- the one the
    -- claws are created on plus thirty-nine of the task -- and the fortieth step
    -- is the one that hides them.
    ok(last ~= nil and (last - first + 1) == 40,
       "...drawn for 40 frames, hidden on the 41st",
       last and (last - first + 1), 40)
    -- THE FROZEN PAIR IS BLANK, WHICH IS WHY THE DELAY READS AS AN ENTRANCE.
    -- Twenty-four blank records, and the split is the measurement: all four claws
    -- are on animation frame 0 the frame they are created (4 x 1 = 4... of which
    -- two are the right pair's first), and the right pair stays there for the ten
    -- frames of the delay. 2 x 11 on the right, 2 x 1 on the left.
    ok(blanks == 24, "...and the right pair is frozen on a blank cell for ten",
       blanks, 24)
    ok(blanksOnRight == 22,
       "...twenty-two of the twenty-four on the right, which is the pair that waits",
       blanksOnRight, 22)
    -- AND THE TAIL IS REAL. The script ends long before the claws do, and the
    -- player has to keep running: this is the assertion a one-frame tail fails.
    ok(endedAt ~= nil and frames - endedAt > 1,
       "...and the player outlives the script by more than one frame",
       endedAt and (frames - endedAt) .. " frames of tail", "more than 1")
    ok(endedAt ~= nil and frames == 41,
       "...to the claws' fortieth step exactly", frames, 41)
  end
end

-- and the blank cell is the cartridge's, not a gap in the extractor
do
  local art = spriteArt["17_16_17_17"]
  local bank = art and true
  ok(bank == true, "MetalClaw's art is member 17", bank, true)
  if art then
    ok(art.cells[1] == nil,
       "...whose cell 0 has no OAM entries at all", art.cells[1] == nil, true)
    local firstCell = art.sequences and art.sequences[1]
      and art.sequences[1].frames and art.sequences[1].frames[1]
    ok(firstCell ~= nil and firstCell.cell == 0,
       "...and its animation's first frame names that empty cell",
       firstCell and firstCell.cell, 0)
  end
end

-- 10 Swagger: ONE sprite, TWO pops, a five-frame gap, and a scale envelope.
do
  local frames, rows = runSprites(269, true)
  if frames then
    local runs, current, scales, places = {}, nil, {}, {}
    for f = 1, frames do
      local vein = nil
      for _, s in ipairs(rows[f]) do
        if s.func == "Swagger" then vein = s end
      end
      if vein then
        if not current then current = { from = f, scales = {} } end
        current.to = f
        current.scales[#current.scales + 1] = ("%.4f"):format(vein.scaleX or 1)
        scales[("%.4f"):format(vein.scaleX or 1)] = true
        places[("%d,%d"):format(vein.x or 0, vein.y or 0)] = true
      elseif current then
        runs[#runs + 1] = current
        current = nil
      end
    end
    if current then runs[#runs + 1] = current end
    ok(#runs == 2, "Swagger's one vein appears TWICE, with a gap", #runs, 2)
    if #runs == 2 then
      ok(runs[1].to - runs[1].from == runs[2].to - runs[2].from,
         "...both pops the same length",
         (runs[1].to - runs[1].from + 1) .. " and " .. (runs[2].to - runs[2].from + 1),
         "equal")
      ok(runs[2].from - runs[1].to - 1 == 5,
         "...five frames apart, which is `delay-- until < 0` from four",
         runs[2].from - runs[1].to - 1, 5)
    end
    local placeList = {}
    for k in pairs(places) do placeList[#placeList + 1] = k end
    table.sort(placeList)
    ok(#placeList == 2 and placeList[1] == "-24,-24" and placeList[2] == "24,-16",
       "...on opposite sides, the second one higher",
       table.concat(placeList, " and "), "-24,-24 and 24,-16")
    -- THE WHOLE ENVELOPE IN ORDER, NOT A SET OF VALUES. A set cannot tell a
    -- settle from a swell: 307/256 is 1.1992 whether it is the third step going
    -- up or the second coming down, so "1.1992 occurs" passes on a vein that
    -- never settles at all. The order is the measurement.
    --
    -- 1.0 -> 1.3984 over four frames against a reference of 10, then the peak is
    -- HELD for one frame -- the frame `UpdatePop` finds the first lerp exhausted
    -- and builds the second without applying it -- and then two frames back down
    -- to 1.1992. Eight frames, and the ninth is the frame it hides.
    local want = "1.0000 1.0977 1.1992 1.2969 1.3984 1.3984 1.2969 1.1992"
    local got1 = table.concat(runs[1] and runs[1].scales or {}, " ")
    ok(got1 == want, "...swelling and then settling, in this order", got1, want)
    local got2 = table.concat(runs[2] and runs[2].scales or {}, " ")
    ok(got2 == want, "...and the second pop is the same envelope", got2, want)
    ok(scales["1.3984"] == true, "...peaking at 1.3984x, not 1.4x",
       scales["1.3984"] == true, true)
  end
end

-- 17 IcicleSpear: THREE icicles on three paths, each ten frames, each rotating.
do
  local frames, rows = runSprites(333, true)
  if frames then
    local peak, absolute, offsets, angles, lives = 0, 0, 0, {}, {}
    local paths = {}
    for f = 1, frames do
      if #rows[f] > peak then peak = #rows[f] end
      for _, s in ipairs(rows[f]) do
        if s.func == "IcicleSpear" then
          if s.absoluteX and s.absoluteY then absolute = absolute + 1 end
          if (s.x or 0) ~= 0 or (s.y or 0) ~= 0 then offsets = offsets + 1 end
          angles[("%.4f"):format(s.rotation or 0)] = true
          paths[("%d,%d"):format(s.absoluteX or 0, s.absoluteY or 0)] = true
          lives[#lives + 1] = f
        end
      end
    end
    ok(peak >= 2, "move 333 has more than one icicle in the air at once", peak,
       "2 or more")
    ok(absolute > 0 and offsets == 0,
       "...and every icicle is placed absolutely, never as an offset",
       absolute .. " absolute, " .. offsets .. " offset", "all absolute")
    local angleCount = 0
    for _ in pairs(angles) do angleCount = angleCount + 1 end
    -- Ten frames of flight and a rotation lerp of ten steps, so ten angles --
    -- the first from the callback itself, before the task ever runs.
    ok(angleCount == 10, "...through ten distinct angles, one per frame of flight",
       angleCount, 10)
    local pathCount = 0
    for _ in pairs(paths) do pathCount = pathCount + 1 end
    ok(pathCount >= 25, "...on three different paths, not one drawn three times",
       pathCount .. " distinct points", "at least 25")
    -- AND NOT ONE OF THEM STARTS AT THE ATTACKER'S CENTRE. pret steps the
    -- parabola once inside the callback, so the icicle is already on its way on
    -- the frame it appears; a port that skipped that step would spawn all three
    -- on top of the attacker.
    local me = Play.Player.BATTLER_POS.player
    ok(paths[("%d,%d"):format(me.x, me.y)] == nil,
       "...and none of them is ever at the attacker's centre",
       paths[("%d,%d"):format(me.x, me.y)] == nil, true)
  end
end

-- ...AND EVERY ICICLE FLIES AN ARC, which is the half-revolution the parabola
-- adds to the straight lerp. Measured per icicle rather than in aggregate: the
-- three are in the air together, so the points are separated into tracks by
-- continuity first and each track is then compared with its OWN chord. A port
-- that dropped the arc radius draws three straight lines, which is a bow of zero
-- and passes every other assertion in this section.
for _, side in ipairs({ true, false }) do
  local frames, rows = runSprites(333, side)
  local tracks = {}
  for f = 1, frames or 0 do
    for _, s in ipairs(rows[f]) do
      if s.func == "IcicleSpear" and s.absoluteX then
        local best, bestD = nil, nil
        for _, tr in ipairs(tracks) do
          local last = tr[#tr]
          if last.f == f - 1 then
            local d = math.abs(last.x - s.absoluteX) + math.abs(last.y - s.absoluteY)
            if bestD == nil or d < bestD then best, bestD = tr, d end
          end
        end
        if best and bestD <= 40 then
          best[#best + 1] = { f = f, x = s.absoluteX, y = s.absoluteY }
        else
          tracks[#tracks + 1] = { { f = f, x = s.absoluteX, y = s.absoluteY } }
        end
      end
    end
  end
  local which = side and "with the player attacking" or "with the enemy attacking"
  ok(#tracks == 3, "move 333 throws THREE icicles " .. which, #tracks, 3)
  local lengths, bows, tooFlat = {}, {}, 0
  for _, tr in ipairs(tracks) do
    lengths[#lengths + 1] = #tr
    local a, b, worst = tr[1], tr[#tr], 0
    for j, pt in ipairs(tr) do
      local at = (j - 1) / math.max(1, #tr - 1)
      local lineY = a.y + (b.y - a.y) * at
      local bow = lineY - pt.y
      if bow > worst then worst = bow end
    end
    bows[#bows + 1] = ("%.1f"):format(worst)
    -- The radius is 32 and the chord is sampled at whole frames, so the visible
    -- peak lands a little under it; a straight line is a bow of zero.
    if worst < 20 or worst > 32 then tooFlat = tooFlat + 1 end
  end
  local allTen = true
  for _, n in ipairs(lengths) do if n ~= 10 then allTen = false end end
  ok(allTen and #lengths == 3, "...each flying for exactly ten frames " .. which,
     table.concat(lengths, ","), "10,10,10")
  ok(tooFlat == 0, "...and each one arcs, rather than flying flat " .. which,
     table.concat(bows, ", ") .. " pixels above the chord", "20 to 32 each")
end

-- ...and the other way round, where the rotation starts from a different angle
-- rather than a mirrored one.
do
  local a, rowsA = runSprites(333, true)
  local b, rowsB = runSprites(333, false)
  local function firstAngle(rows, frames)
    for f = 1, frames or 0 do
      for _, s in ipairs(rows[f]) do
        if s.func == "IcicleSpear" then return s.rotation end
      end
    end
  end
  local fa, fb = firstAngle(rowsA, a), firstAngle(rowsB, b)
  -- 20 degrees one way, -90 the other: not a sign flip of the same number.
  local want = Math4.radians(Math4.degToIdx(20))
  ok(fa ~= nil and fb ~= nil and math.abs(fa + fb) > 0.5,
     "IcicleSpear's two directions are different arcs, not mirrored ones",
     fa and ("%.3f and %.3f"):format(fa, fb) or "no sprite",
     "not opposite")
  -- THE ANGLE IS STILL ITS STARTING VALUE ON THE FIRST FRAME while the POSITION
  -- is already one step along the parabola -- and that pair is the whole
  -- scheduler rule in one measurement. The rotation is lerped by the task, which
  -- does not run on the frame the sprite is created; the first step of the
  -- parabola is taken by the callback itself, by hand, before the task exists. A
  -- port that ran the task a frame early fails the first of these; one that
  -- skipped the callback's manual step fails the second, above.
  ok(fa ~= nil and math.abs(fa - want) < 1e-9,
     "...and the first frame's angle is exactly 20 degrees, not yet lerped",
     fa and ("%.4f"):format(fa), ("%.4f"):format(want))
end

-- 18 FakeOut: the alpha envelope, and the frames the scheduler costs.
do
  local frames, rows = runSprites(252, true)
  if frames then
    local seq = {}
    for f = 1, frames do
      for _, s in ipairs(rows[f]) do
        if s.func == "FakeOut" then seq[#seq + 1] = s.alpha or 1 end
      end
    end
    ok(#seq > 20, "move 252 keeps its sprite up", #seq, "over 20")
    ok(seq[1] == 0, "...invisible on the frame it appears", seq[1], 0)
    -- Eight steps of 1/16 up, and the ninth frame is the one the fade reports
    -- done -- which is why the sprite reaches full opacity a frame before the
    -- state machine moves on.
    local rose = 0
    for i = 2, 10 do
      if seq[i] and seq[i - 1] and seq[i] > seq[i - 1] then rose = rose + 1 end
    end
    ok(rose == 8, "...rising by a sixteenth for eight frames", rose, 8)
    local full, dips = 0, 0
    for i = 1, #seq do
      if seq[i] == 1 then full = full + 1 end
      if seq[i] > 1 or seq[i] < 0 then dips = dips + 1 end
    end
    ok(full > 70, "...opaque for the whole animation between the fades", full,
       "over 70")
    ok(dips == 0, "...and never outside 0..1", dips, 0)
    ok(seq[#seq] < 1, "...fading out at the end", ("%.3f"):format(seq[#seq]),
       "under 1")
    -- THE WHOLE LENGTH IS PREDICTED, not recorded, and every term is a rule:
    -- 1 frame for the sprite to exist before its task runs, 1 for the task to
    -- start the fade, 9 for the fade (8 steps and the frame `done` is read), 92
    -- of animation which has been ticking since the task's first step, 9 for the
    -- fade out and 1 to clean up. The sprite is drawn on 103 of those and the
    -- 104th is the frame it goes.
    ok(#seq == 103, "...drawn for 103 frames: 92 of animation plus 11",
       #seq, 103)
    -- 107 AND NOT 104: `LoadParticleResource` costs three frames now that
    -- `RenderPokemonSprites 0` is read as three and not as zero. Program 25 loads
    -- ONE particle file, so its whole timeline starts three frames later. The 103
    -- drawn frames above are unchanged, which is the check that this is a shift and
    -- not a lengthening.
    ok(frames == 107, "...and the player stops on the frame after", frames, 107)
  end
end

-- 25 OffsetAndAnimate, and the sign that was wrong.
do
  local frames, rows = runSprites(265, true)
  if frames then
    local place = nil
    for f = 1, frames do
      for _, s in ipairs(rows[f]) do place = place or ("%d,%d"):format(s.x or 0, s.y or 0) end
    end
    -- MOVE 265 PASSES (0, 24) AND +Y IS DOWN: the sprite belongs twenty-four
    -- pixels BELOW the defender's centre. This port measured Y upwards until the
    -- day it read `ManagedSprite_OffsetPositionXY` properly, and a sprite in the
    -- wrong place still draws, so nothing else could have caught it.
    ok(place == "0,24", "move 265's sprite sits 24 pixels BELOW the defender",
       place, "0,24")
  end
end

-- AND THE SCRIPT VARS ARE SIGNED, AND SHARED. `addspritewithfunc` writes its
-- trailing arguments into the same ten slots `setvar` uses, and the cartridge
-- writes negatives as unsigned words: move 333's third icicle passes -10 and -15.
do
  if player and player:start(333, true) then
    -- READ AT THE MOMENT THE SPRITE APPEARS, not at the end of the program.
    -- These ten slots are shared, and move 333 runs more `callfunc`s after its
    -- last icicle -- each of which fills them with its own arguments. Reading
    -- them afterwards measures whichever command ran last, which is exactly the
    -- clobbering this assertion exists to describe.
    local frames, snapshot = 0, nil
    while player:update() and frames < 60 do
      frames = frames + 1
      if snapshot == nil then
        for _, s in ipairs(player:cells()) do
          if s.func == "IcicleSpear" then
            snapshot = { player.vars[0], player.vars[1], player.vars[2],
                         player.vars[3], player.vars[4] }
          end
        end
      end
    end
    snapshot = snapshot or {}
    ok(snapshot[1] == -15 and snapshot[2] == -5,
       "a callback's arguments arrive SIGNED, not as four billion",
       ("%s,%s"):format(tostring(snapshot[1]), tostring(snapshot[2])),
       "-15,-5")
    ok(snapshot[3] == 10 and snapshot[4] == 32,
       "...and the positive ones unchanged",
       ("%s,%s"):format(tostring(snapshot[3]), tostring(snapshot[4])),
       "10,32")
    ok(snapshot[5] == 0,
       "...with the slots past the argument count zeroed, as the handler does",
       tostring(snapshot[5]), 0)
  end
end

-- ---------------------------------------------------------------------------
-- 11: THE TWO CALLBACKS THAT REACH A BATTLER
--
-- ScaryFace stretches the attacker's own Pokemon and Foresight flashes the
-- defender white. Both go through the channels Emerald's animator already
-- defined -- `monAffine` and `monTint` -- so the assertions here read the SEAM
-- rather than the sprite, and the first of them is the one that caught the guard
-- described below.
-- ---------------------------------------------------------------------------
io.write("\nthe callbacks that move a battler\n")

-- 7 ScaryFace: one sprite, and the attacker stretched vertically.
do
  local frames, rows = runSprites(137, true)
  ok(frames ~= nil, "move 137 runs", frames, "a frame count")
  if frames then
    local origins, alphas, faceScales = {}, {}, {}
    local first, last = nil, nil
    for f = 1, frames do
      for _, s in ipairs(rows[f]) do
        origins[#origins + 1] = s.origin
        alphas[#alphas + 1] = ("%.4f"):format(s.alpha or 1)
        faceScales[#faceScales + 1] = ("%.4f"):format(s.scaleX or 1)
        first = first or f
        last = f
      end
    end
    -- ONE FRAME AT THE DEFENDER, THE REST AT THE ATTACKER, and it is the
    -- cartridge's own artifact: the command builds the template at the DEFENDER
    -- and the callback's base is not applied until its task's first frame, which
    -- is not the frame the sprite appears.
    local atDefender, atAttacker = 0, 0
    for _, o in ipairs(origins) do
      if o == "defender" then atDefender = atDefender + 1
      elseif o == "attacker" then atAttacker = atAttacker + 1 end
    end
    ok(atDefender == 1, "ScaryFace's face spends ONE frame on the wrong Pokemon",
       atDefender, 1)
    ok(atAttacker == #origins - 1,
       "...and every frame after it on the attacker", atAttacker, #origins - 1)
    -- THE FACE FADES OUT, and the ORDER is the assertion: the same eight
    -- sixteenths appear whichever way a fade runs.
    local tailAlphas = {}
    for i = #alphas - 8, #alphas do
      if alphas[i] then tailAlphas[#tailAlphas + 1] = alphas[i] end
    end
    local wantFade = "1.0000 0.8750 0.7500 0.6250 0.5000 0.3750 0.2500 0.1250 0.0000"
    ok(table.concat(tailAlphas, " ") == wantFade,
       "...fading out over eight sixteenths, in that order",
       table.concat(tailAlphas, " "), wantFade)
    -- AND IT GROWS FROM HALF SIZE: 5 against a reference of 10 is 128/256.
    ok(faceScales[1] == "0.5000", "...starting at half scale", faceScales[1],
       "0.5000")
    ok(faceScales[#faceScales] == "1.1992", "...and ending at 1.1992x",
       faceScales[#faceScales], "1.1992")
  end
end

-- ...and the battler channel, which is the part no assertion about the sprite
-- could see.
for _, side in ipairs({ true, false }) do
  if player and player:start(137, side) then
    local f, seq, inTail, neutralAfter = 0, {}, 0, nil
    local scaleXmoved, stretched = 0, 0
    while player:update() and f < 300 do
      f = f + 1
      local sx, sy = player:monAffine(side)
      seq[#seq + 1] = ("%.4f"):format(sy)
      if math.abs(sx - 1) > 0.0001 then scaleXmoved = scaleXmoved + 1 end
      -- THE FRAMES AFTER THE SCRIPT HAS ENDED. This is the assertion that caught
      -- the accessors guarding on `playing`: move 137's script ends long before
      -- its face does, so the stretch lives almost entirely in the tail and a
      -- guard on `playing` reported 1.0 for all of it.
      if math.abs(sy - 1) > 0.0001 then
        stretched = stretched + 1
        if player.playing == false then inTail = inTail + 1 end
      end
    end
    local sx2, sy2 = player:monAffine(side)
    neutralAfter = math.abs(sx2 - 1) < 0.0001 and math.abs(sy2 - 1) < 0.0001
    local which = side and "player" or "enemy"
    ok(scaleXmoved == 0,
       "ScaryFace stretches the " .. which .. " attacker VERTICALLY only",
       scaleXmoved .. " frames of X scale", 0)
    local peak = "1.0000"
    for _, v in ipairs(seq) do if v > peak then peak = v end end
    ok(peak == "1.4961", "...to 1.4961x, which is 383/256 and not 1.5",
       peak, "1.4961")
    ok(seq[#seq] == "1.0000", "...and back to exactly 1.0 at the end",
       seq[#seq], "1.0000")
    -- TWENTY-FOUR FRAMES OF STRETCH, FIFTEEN OF THEM AFTER `end`. Both numbers
    -- are derived: twelve frames up and twelve down is the pair of scale lerps,
    -- and move 137's script finishes while the face is still rising. THIS IS THE
    -- ASSERTION THAT CAUGHT THE ACCESSORS GUARDING ON `playing` -- they reported
    -- 1.0 for every one of those fifteen frames, so the Pokemon snapped back
    -- mid-stretch and nothing else in the check could see it.
    ok(stretched == 24, "...over 24 frames, twelve up and twelve down",
       stretched, 24)
    -- THREE OF THEM AFTER `end`, and it was fifteen until `fadebg` got its real
    -- duration: move 137 dims the background, that task used to be a one-frame
    -- hold and is now the thirteen frames the palette fade actually takes, so
    -- most of the stretch now happens while the script is still running. The
    -- assertion is kept because its POINT is that the number is not ZERO -- which
    -- is what the `playing` guard reported for every frame of it.
    ok(inTail == 3,
       "...three of them AFTER the script has ended, in the tail",
       inTail, 3)
    ok(neutralAfter == true,
       "...and the battler is put back once the player is finished",
       neutralAfter, true)
  end
end

-- 8 Foresight: a six-segment zig-zag that returns to where it started, and a
-- white flash on the DEFENDER.
do
  local frames, rows = runSprites(193, true)
  ok(frames ~= nil, "move 193 runs", frames, "a frame count")
  if frames then
    local waypoints, last, cells = {}, nil, {}
    local alphas = {}
    for f = 1, frames do
      for _, s in ipairs(rows[f]) do
        local at = ("%d,%d"):format(s.x or 0, s.y or 0)
        if at ~= last then
          waypoints[#waypoints + 1] = { f = f, at = at }
          last = at
        end
        cells[tostring(s.cell)] = true
        alphas[#alphas + 1] = ("%.4f"):format(s.alpha or 1)
      end
    end
    -- SIX SEGMENTS OF EIGHT FRAMES, five frames apart, and each one's END IS THE
    -- NEXT ONE'S BASE -- which is why the extent is +-40 from the start rather
    -- than the +-80 the constant names.
    local corners = {}
    for i, w in ipairs(waypoints) do
      -- the last point of each run of eight is a corner
      local nextW = waypoints[i + 1]
      if nextW == nil or nextW.f > w.f + 1 then corners[#corners + 1] = w.at end
    end
    local wantCorners = "0,0 40,40 40,-40 -40,40 -40,-40 40,40 0,0"
    ok(table.concat(corners, " ") == wantCorners,
       "Foresight walks six segments and ENDS WHERE IT STARTED",
       table.concat(corners, " "), wantCorners)
    ok(#waypoints == 49,
       "...through this many distinct positions", #waypoints, 49)
    -- THE FIRST SEGMENT STARTS ON FRAME 7: one frame for the sprite to exist,
    -- then five of delay (`delay++` then `> 4`), then the first step.
    ok(waypoints[2] ~= nil and waypoints[2].f == 7,
       "...the first one starting on frame 7, which is five frames of delay",
       waypoints[2] and waypoints[2].f, 7)
    -- AND IT NEVER ANIMATES: no `SetAnimateFlag`, no `TickFrame` in its task.
    -- MEASURED ON THE MOVE IT CANNOT BE MEASURED ON, and then properly below:
    -- member 9's only sequence is a SINGLE FRAME, so the eye shows one cell
    -- whether it is ticked or not and this assertion passes either way. It is kept
    -- because it states the expected picture, and the real test is the synthetic
    -- pair that follows.
    local cellCount = 0
    for _ in pairs(cells) do cellCount = cellCount + 1 end
    ok(cellCount == 1, "...holding ONE animation frame the whole time, as its "
       .. "callback neither animates nor ticks it", cellCount, 1)
    -- THE SPRITE'S FADE OUTLIVES THE STATE MACHINE. Sixteen frames of fade
    -- against eleven of the defender's flash, so FADE_OUT has already been left
    -- behind when the sprite reaches zero -- and the `SetDrawFlag(FALSE)` in that
    -- arm is never reached on this move. Pumping the fade inside the arm instead
    -- freezes the sprite at 5/16 forever, which is what this asserts.
    local lowest = "1.0000"
    for _, v in ipairs(alphas) do if v < lowest then lowest = v end end
    ok(lowest == "0.0000",
       "...and its own fade reaches zero even after the machine has moved on",
       lowest, "0.0000")
  end
end

-- ...and the white flash on the defender, which is the other battler channel.
do
  if player and player:start(193, true) then
    local f, seq = 0, {}
    while player:update() and f < 200 do
      f = f + 1
      local r, g, b, a = player:monTint(false)
      seq[#seq + 1] = { r = r, g = g, b = b, a = a }
    end
    local steps, peak, white, nonWhite = {}, 0, 0, 0
    for _, t in ipairs(seq) do
      if t.a then
        steps[#steps + 1] = ("%.4f"):format(t.a)
        if t.a > peak then peak = t.a end
        if t.r == 1 and t.g == 1 and t.b == 1 then white = white + 1
        else nonWhite = nonWhite + 1 end
      end
    end
    ok(#steps > 20, "Foresight flashes the defender", #steps .. " tinted frames",
       "over 20")
    ok(nonWhite == 0 and white == #steps,
       "...white, which is GX_RGB(31, 31, 31)", white .. " of " .. #steps,
       "all of them")
    -- 0 -> 10 ONE SIXTEENTH AT A TIME AND BACK, eleven frames each way, because
    -- the blend is applied BEFORE the alpha steps and the target is applied too.
    ok(("%.4f"):format(peak) == "0.6250",
       "...to 10/16 and no further", ("%.4f"):format(peak), "0.6250")
    local up, down, flat = 0, 0, 0
    for i = 2, #steps do
      if steps[i] > steps[i - 1] then up = up + 1
      elseif steps[i] < steps[i - 1] then down = down + 1
      else flat = flat + 1 end
    end
    -- TEN UP, ONE FLAT, TEN DOWN over 22 tinted frames. The flat one is the
    -- frame the second fade is created and applies its own starting value, which
    -- is the value already showing -- and the tenth step down lands on alpha 0,
    -- which is the restore rather than an extra frame of white. A ramp that ran
    -- 0 -> 10 -> 0 continuously would give 10 and 10 with NO flat frame, so the
    -- flat one is part of the measurement.
    ok(up == 10 and down == 10 and flat == 1,
       "...ten steps up, one held, ten back down -- not one long ramp",
       ("%d up, %d flat, %d down"):format(up, flat, down), "10, 1 and 10")
    ok(#steps == 22, "...over 22 frames in all", #steps, 22)
    -- AND THE LAST FRAME OF THE WALK IS THE RESTORE, not a removal: nothing in
    -- the C takes the blend off, because a fraction of zero writes the unfaded
    -- colour back. What takes it off for good is the player finishing.
    -- `steps` holds FORMATTED strings -- they are compared with each other above,
    -- which is safe because every value has the same width and no sign -- so this
    -- compares against the string too rather than against a number it would never
    -- equal.
    ok(steps[#steps] == "0.0000",
       "...ending at a blend of zero, which is the restore",
       tostring(steps[#steps]), "0.0000")
    local r2, g2, b2, a2 = player:monTint(false)
    ok(a2 == nil and r2 == nil,
       "...and the battler is clean once the player is finished",
       tostring(a2), "nil")
  end
end

-- ...AND "IT DOES NOT ANIMATE" MEASURED ON ART THAT CAN, which move 193's cannot.
--
-- A SYNTHETIC PAIR, LABELLED AS ONE: the same multi-frame bank is driven once
-- under Foresight (func 8, which never ticks) and once under OffsetAndAnimate
-- (func 25, which ticks every frame). The second is the control -- it proves the
-- art has more than one cell to show and that this harness can see a change -- and
-- the first is the assertion. Without the control, "the cell never changed" would
-- pass on a bank with one cell, which is exactly how the measurement above fails
-- to be one.
local SYNTHETIC_TICKS = 24
do
  -- THE BANK IS CHOSEN BY WHAT THE TEST NEEDS, which is not "the most frames":
  -- member 20 has twelve and its FIRST ONE LASTS THIRTY TICKS, so nothing changes
  -- inside the window and the control would fail while the port was right. Pick a
  -- bank whose cell demonstrably changes within the window, by asking `at()`.
  local multi, cellsShown = nil, 0
  local keys = {}
  for key in pairs(spriteArt) do keys[#keys + 1] = key end
  table.sort(keys)
  for _, key in ipairs(keys) do
    local seq = spriteArt[key].sequences and spriteArt[key].sequences[1]
    if seq and seq.frames then
      local seen = {}
      for tick = 0, SYNTHETIC_TICKS - 1 do
        seen[tostring(CellAnim.at(seq.frames, tick))] = true
      end
      local n = 0
      for _ in pairs(seen) do n = n + 1 end
      if n > cellsShown then multi, cellsShown = key, n end
    end
  end
  ok(multi ~= nil and cellsShown > 2,
     "a bank whose cell changes inside the window exists to test against",
     multi and (multi .. " shows " .. cellsShown .. " cells in "
                .. SYNTHETIC_TICKS .. " ticks") or "none",
     "more than 2")
  if multi and player then
    local char, pltt, cell, anim = multi:match("^(%d+)_(%d+)_(%d+)_(%d+)$")
    local function cellsUnder(funcId)
      player:start(1, true)
      player.managers = {}
      player:initSpriteManager(0, {})
      player:loadSpriteResource("char", 0, tonumber(char))
      player:loadSpriteResource("cell", 0, tonumber(cell))
      player:loadSpriteResource("anim", 0, tonumber(anim))
      player:addSprite(0, funcId, tonumber(char), tonumber(pltt), tonumber(cell),
                       tonumber(anim))
      local seen = {}
      for _ = 1, SYNTHETIC_TICKS do
        -- The frame counter has to move, because a callback's first step is
        -- withheld on the frame its sprite was born.
        player.frames = player.frames + 1
        player:stepSprites()
        for _, s in ipairs(player:cells()) do seen[tostring(s.cell)] = true end
      end
      local n = 0
      for _ in pairs(seen) do n = n + 1 end
      return n
    end
    local ticked = cellsUnder(25)
    local notTicked = cellsUnder(8)
    ok(ticked > 1, "...and under a callback that TICKS it shows several",
       ticked .. " distinct cells", "more than 1")
    ok(notTicked == 1, "...while under Foresight it shows exactly one",
       notTicked .. " distinct cells", 1)
  end
end

-- !! TWO PLANTS AGAINST THIS SECTION ARE NOT FAULTS, AND SAYING SO IS CHEAPER
-- THAN A READER DISCOVERING IT AGAIN.
--
-- REMOVING ScaryFace's EXPLICIT `MON_SPRITE_SCALE_Y = 0x100`. Its shrink leg is a
-- scale lerp from 384 back to 256 over twelve frames, and the integer arithmetic
-- LANDS ON 256 EXACTLY, so the assignment pret makes afterwards changes nothing.
-- It is a guard, not behaviour -- kept because the lerp is not guaranteed to land
-- on other numbers, and a guard is proved by the faults it would catch elsewhere
-- rather than by one planted where it cannot bite.
--
-- CLEARING THE BATTLER TRANSFORMS AT `end` INSTEAD OF AT THE TAIL'S END. Deferring
-- the reset is right -- the transform tasks are SysTasks and outlive the script --
-- but it is UNOBSERVABLE ON THIS CARTRIDGE: every channel that is non-neutral when
-- a program ends is still being written the next frame by a live task (moves 44 and
-- 292, the only two, are 1 and 2 pixels of enemy offset that a running task brings
-- home), and NOT ONE of the 501 programs reaches `end` with a battler hidden. So
-- the change is an argument, not a measurement, and the assertion that carries real
-- weight is the one above: `alive()` rather than `playing`, which fifteen frames of
-- ScaryFace's stretch depend on.

-- ---------------------------------------------------------------------------
-- 12: THE PALETTE FADE, which is what `fadebg` is
--
-- 272 calls over 108 of the 501 programs, and until now every one of them was a
-- one-frame hold that drew nothing. Two things are asserted here: the ARITHMETIC
-- (pret's `SetTimedFadeParams`, which is not a lerp) and the REACH (how much of
-- the cartridge this turns on).
-- ---------------------------------------------------------------------------
io.write("\nthe background's palette fade\n")

do
  -- WHAT THE CARTRIDGE ASKS FOR, counted from the programs rather than assumed.
  local calls, byType, ramps, delays, colours, users = 0, {}, {}, {}, {}, {}
  for id = 0, arc.count - 1 do
    for _, ins in ipairs((programs[id] or {}).code or {}) do
      -- callfunc is 45 and its first operand is the function id.
      if ins[1] == 45 and ins[2] == 33 then
        calls = calls + 1
        users[id] = true
        local ty = signedWord(ins[4])
        byType[ty] = (byType[ty] or 0) + 1
        delays[signedWord(ins[5])] = (delays[signedWord(ins[5])] or 0) + 1
        local from, to = signedWord(ins[6]), signedWord(ins[7])
        ramps[("%d->%d"):format(from, to)] = (ramps[("%d->%d"):format(from, to)] or 0) + 1
        colours[signedWord(ins[8]) % 65536] = true
      end
    end
  end
  local nUsers, nColours = 0, 0
  for _ in pairs(users) do nUsers = nUsers + 1 end
  for _ in pairs(colours) do nColours = nColours + 1 end
  ok(calls == 272, "the cartridge fades a palette group this many times", calls, 272)
  ok(nUsers == 108, "...across this many of the 501 programs", nUsers, 108)
  -- TYPE 0 IS THE BACKGROUND and is almost all of them, which is why the draw
  -- side is one quad rather than three passes. Type 1 (the Pokemon sprites'
  -- palettes) NEVER OCCURS -- worth stating, because implementing it would be
  -- code no cartridge path reaches.
  ok(byType[0] == 270 and byType[2] == 2 and byType[1] == nil,
     "...270 on the background, 2 on the effect palettes, NONE on the Pokemon",
     ("%s / %s / %s"):format(tostring(byType[0]), tostring(byType[2]),
                             tostring(byType[1])),
     "270 / 2 / none")
  -- THE NEGATIVE-DELAY BRANCH IS REAL. `wait < 0` means step = 2 + |wait| and no
  -- waiting at all -- a different ramp, not a tidier spelling of the same one.
  ok((delays[-2] or 0) + (delays[-4] or 0) == 9,
     "...and nine of them pass a NEGATIVE delay, which changes the step size",
     (delays[-2] or 0) + (delays[-4] or 0), 9)
  ok(delays[1] == 227 and delays[0] == 36,
     "...while the rest wait one frame between steps, or none",
     ("%s and %s"):format(tostring(delays[1]), tostring(delays[0])),
     "227 and 36")
  -- AND THE RAMPS COME IN PAIRS, which is why a port that fades and never
  -- recovers leaves the battle dimmed for the rest of the fight.
  ok(ramps["0->12"] == 98 and ramps["12->0"] == 99,
     "...and the commonest ramp is a dip to 12/16 and back, in matched pairs",
     ("%s down, %s up"):format(tostring(ramps["0->12"]), tostring(ramps["12->0"])),
     "98 and 99")
  ok(nColours == 15, "...in this many distinct colours", nColours, 15)
end

-- THE ARITHMETIC, on the move that shows it plainly.
do
  local fadeMove = nil
  for id = 0, arc.count - 1 do
    for _, ins in ipairs((programs[id] or {}).code or {}) do
      if ins[1] == 45 and ins[2] == 33 then fadeMove = fadeMove or id end
    end
  end
  ok(fadeMove ~= nil, "a program that fades the background was found", fadeMove,
     "a move id")
  if fadeMove and player and player:start(fadeMove, true) then
    local f, steps, last = 0, {}, nil
    local held, peak = 0, 0
    while player:update() and f < 300 do
      f = f + 1
      local r, g, b, a = player:groupTint("base")
      local at = a and ("%.4f"):format(a) or "-"
      if a and a > peak then peak = a end
      if at == last then held = held + 1 else steps[#steps + 1] = { f = f, at = at } end
      last = at
    end
    -- EVERY SECOND FRAME, IN SIXTEENTHS OF TWO, and the first visible value is
    -- 2/16 rather than 0 -- because the first application blends at `cur`, which
    -- starts at zero, and a blend of zero is the unfaded colour.
    local ladder = {}
    for i = 1, math.min(#steps, 7) do ladder[#ladder + 1] = steps[i].at end
    ok(table.concat(ladder, " ") == "- 0.1250 0.2500 0.3750 0.5000 0.6250 0.7500",
       "the fade climbs in sixteenths of two, starting from nothing",
       table.concat(ladder, " "),
       "- 0.1250 0.2500 0.3750 0.5000 0.6250 0.7500")
    local gaps = {}
    for i = 3, math.min(#steps, 7) do gaps[#gaps + 1] = steps[i].f - steps[i - 1].f end
    local everyOther = true
    for _, gv in ipairs(gaps) do if gv ~= 2 then everyOther = false end end
    ok(everyOther and #gaps > 2,
       "...one step every second frame, which is `wait` of 1",
       table.concat(gaps, ","), "all 2")
    ok(("%.4f"):format(peak) == "0.7500",
       "...peaking at 12/16 and no further", ("%.4f"):format(peak), "0.7500")
    -- AND IT HOLDS THERE. The palette stays blended after the fade finishes --
    -- nothing restores it but the second fade of the pair, which is why both
    -- always occur.
    ok(held > 20, "...then HOLDS at its end value until the recovery fade",
       held .. " frames unchanged", "over 20")
    local r2, g2, b2, a2 = player:groupTint("base")
    ok(a2 == nil, "...and ends clean", tostring(a2), "nil")
  end
end

-- AND THE REACH, which is the number that says what this turned on.
do
  local moves, frames = 0, 0
  if player then
    for id = 0, arc.count - 1 do
      local uses = false
      for _, ins in ipairs((programs[id] or {}).code or {}) do
        if ins[1] == 45 and ins[2] == 33 then uses = true end
      end
      if uses and player:start(id, true) then
        local f, tinted = 0, 0
        while player:update() and f < 400 do
          f = f + 1
          local r, g, b, a = player:groupTint("base")
          if a and a > 0 then tinted = tinted + 1 end
        end
        if tinted > 0 then moves = moves + 1; frames = frames + tinted end
      end
    end
  end
  -- 106 AND NOT 108: two of the programs that call `fadebg` never show a tint when
  -- the player attacks, because their call sits behind a branch this side of the
  -- battle does not take. Stated as the measurement rather than rounded up.
  --
  -- IT WAS 105 BEFORE `switchbg` EXISTED, and the program that joined the list did
  -- not gain a `fadebg` -- it gained a background switch. The fade mode fades every
  -- palette but the effect one to black, which is the SAME "base" group `fadebg`
  -- type 0 writes, so a switched background now tints the field whether or not the
  -- program ever called `fadebg`. This count is over the programs that DO call
  -- `fadebg`, so what changed is that one of them now also shows a tint from its
  -- switch on a frame its own fade was not running.
  ok(moves == 106, "this many programs now tint the battle background", moves, 106)
  -- 8748, and the same reason: a switch holds the field at full black for its whole
  -- switched stretch, which is between twenty and a hundred frames a program. Both
  -- numbers are the same measurement; the tint got longer, not commoner.
  --
  -- 8754 AND NOT 8748: the same three-frame load cost, on the two programs whose
  -- tinted stretch is clipped by the end of their run. The count of PROGRAMS is
  -- unchanged, which is what says the load cost moved the window rather than
  -- adding a tint anywhere.
  ok(frames == 8754, "...over this many frames of the corpus", frames, 8754)
end

-- A SECOND FADE WHILE ONE IS RUNNING IS DROPPED, not queued -- pret's `StartFade`
-- skips a buffer that is in `selectedBuffers` and, having skipped every buffer it
-- was given, returns FALSE having done nothing. Nothing in the cartridge does it
-- with two `fadebg`s (the pairs are sequential), so this is forced.
--
-- AND THE GUARD IS PER BUFFER, NOT PER GROUP, which is the second half of the
-- assertion below: the two calls name DIFFERENT groups -- the backdrop's palettes
-- and the BG-resident Pokemon sprite's -- and the second is still refused, because
-- both live in PLTTBUF_MAIN_BG and a buffer holds one fade. Measured before it was
-- changed: 0 of the 227 `fadebg` calls the per-group guard let through would have
-- been refused by this one, so on `fadebg` alone the difference is unobservable.
-- It stopped being unobservable when `switchbg`'s fade mode -- 127 calls -- started
-- taking the same buffer.
do
  if player and player:start(1, true) then
    local first = player:startPaletteFade(0, 1, 0, 12, 0)
    local second = player:startPaletteFade(1, 1, 0, 8, 0x7FFF)
    ok(first == true and second == false,
       "a fade while another buffer fade runs is refused, whatever group it names",
       ("%s then %s"):format(tostring(first), tostring(second)),
       "true then false")
    local dropped = 0
    for _, row in ipairs(player:missing()) do
      if row.what:find("already fading", 1, true) then dropped = dropped + row.count end
    end
    ok(dropped == 1, "...and says so rather than swallowing it", dropped, 1)
  end
end

-- THE FIRST BLEND HAPPENS ON THE COMMAND'S OWN FRAME, and only a fade that
-- starts somewhere other than zero can show it: `StartFade` applies one blend
-- inline before its stepping task exists, and every cartridge fade that starts at
-- 0 blends at zero, which is the unfaded colour. So the recovery direction is
-- where this is visible -- and it is a third of the calls.
do
  if player and player:start(1, true) then
    player.tasks = {}
    player.groups = {}
    player:startPaletteFade(0, 1, 12, 0, 0)
    local r, g, b, a = player:groupTint("base")
    ok(a ~= nil and ("%.4f"):format(a) == "0.7500",
       "a fade downward is at its start value the moment it is asked for",
       a and ("%.4f"):format(a) or "nil", "0.7500")
  end
end

-- THE COLOUR IS BGR555, red in the LOW five bits -- the DS's order, not RGB.
-- 0x001F is RED, and four of the cartridge's calls use it; read the other way
-- round every one of them would flash blue.
do
  if player and player:start(1, true) then
    player.tasks = {}
    player.groups = {}
    player:startPaletteFade(0, 1, 8, 8, 0x001F)
    local r, g, b = player:groupTint("base")
    ok(r == 1 and g == 0 and b == 0,
       "0x001F is RED, because the colour is BGR555",
       ("r=%s g=%s b=%s"):format(tostring(r), tostring(g), tostring(b)),
       "r=1 g=0 b=0")
  end
end

-- AND `callfunc` FILLS THE SHARED SCRIPT VARS, which is the half of that rule the
-- sprite commands do not cover. Move 7's last `fadebg` passes (0, 1, 12, 0, 2124),
-- and those five numbers are what a later `ifvar` on this program would read.
do
  if player and player:start(7, true) then
    local f = 0
    while player:update() and f < 300 do f = f + 1 end
    local got = {}
    for i = 0, 4 do got[#got + 1] = tostring(player.vars[i]) end
    ok(table.concat(got, ",") == "0,1,12,0,2124",
       "a callfunc leaves its arguments in the shared script vars",
       table.concat(got, ","), "0,1,12,0,2124")
  end
end

-- A FINISHED PLAYER LEAVES NOTHING TINTED. Forced, because the cartridge cannot
-- show it: its fades come in matched pairs and the second ends at a blend of
-- zero, so `groups.base` is already empty however the reset behaves. What the
-- reset is FOR is a program that ends mid-fade, and none does -- so the function
-- is exercised directly instead of through a move.
do
  if player and player:start(1, true) then
    player.tasks = {}
    player.groups = {}
    player:startPaletteFade(0, 0, 0, 12, 0x7FFF)
    for _ = 1, 20 do player:stepTasks() end
    local before = player.groups.base ~= nil
    player:clearTransforms()
    local after = player.groups.base ~= nil
    ok(before == true and after == false,
       "clearTransforms takes a finished fade off the background",
       ("tinted %s, then %s"):format(tostring(before), tostring(after)),
       "true then false")
  end
end

-- !! AND ONE THING HERE IS AN ARGUMENT RATHER THAN A MEASUREMENT, said so that
-- nobody plants against it and concludes the check is broken. `groupTint` guards
-- on `alive()` rather than `playing`, like the battler channels -- but NOT ONE of
-- the 105 programs has a background tint still showing after its script ends,
-- because the recovery fade always finishes first. The guard is right and
-- consistent; it is the battler channels where it is measurable (section 11).

-- AND THE NEGATIVE DELAY IS A BIGGER STEP, NOT A SHORTER WAIT. Nine calls pass
-- one, and the two readings differ by the values visited: step 2 with no wait
-- gives 2,4,6,8,10,12 and step 4 gives 4,8,12.
do
  if player and player:start(1, true) then
    player.tasks = {}
    player:startPaletteFade(0, -2, 0, 12, 0)
    -- STOPPING WHEN THE FADE DOES, because the tint HOLDS at its end value
    -- afterwards -- correctly -- and a loop that kept sampling would record a run
    -- of twelves and call it a ramp.
    local seen, guard, last = {}, 0, nil
    while guard < 16 do
      guard = guard + 1
      local r, g, b, a = player:groupTint("base")
      -- `%d` on a float raises in this Lua; the fraction is an exact sixteenth
      -- either way, so it is floored back to one deliberately.
      local at = a and tostring(math.floor(a * 16 + 0.5)) or nil
      if at and at ~= last then seen[#seen + 1] = at end
      last = at
      local live = false
      for _, task in ipairs(player.tasks) do
        if task.kind == "pltfade" and not task.done then live = true end
      end
      if not live then break end
      player:stepTasks()
    end
    ok(table.concat(seen, ",") == "4,8,12",
       "a negative delay steps by 2 + |delay| with no waiting",
       table.concat(seen, ","), "4,8,12")
  end
end

-- ---------------------------------------------------------------------------
-- 13: THE SHAKE, WHICH WAS FOUR TIMES TOO SHORT AND THE WRONG SHAPE
--
-- `shake` is the most-used script function in the cartridge after
-- RenderPokemonSprites -- 398 calls -- and two lines of pret decide what it looks
-- like. `ShakeContext_FlipPosition` is NOT a sign flip: it produces +E, 0, -E, 0,
-- a square wave THROUGH the centre. And `ShakeContext_Update` decrements its
-- remaining count once every `MAX_CYCLES_PER_SHAKE` flips, which is FOUR -- so
-- `amount` counts CYCLES.
--
-- A port that read `amount` as a flip count and alternated between the extremes
-- spends the right kind of frames in the right places and is still wrong about
-- both the shape and the length. Nothing but the waveform can show it.
-- ---------------------------------------------------------------------------
io.write("\nthe shake\n")

do
  -- WHAT THE CARTRIDGE ASKS FOR.
  local calls, amounts, intervals, background = 0, {}, {}, 0
  for id = 0, arc.count - 1 do
    for _, ins in ipairs((programs[id] or {}).code or {}) do
      if ins[1] == 45 and ins[2] == 36 then
        calls = calls + 1
        -- A ROW IS {op, arg1, arg2, ...}, so var N is ins[4 + N]: funcId at 2,
        -- the argument count at 3, then extentX, extentY, interval, amount,
        -- targets. Reading them one short measured the neighbouring operand and
        -- reported 388 shakes with an interval of 1 -- which is the amount.
        intervals[signedWord(ins[6])] = (intervals[signedWord(ins[6])] or 0) + 1
        amounts[signedWord(ins[7])] = (amounts[signedWord(ins[7])] or 0) + 1
        local targets = signedWord(ins[8])
        if math.floor(targets / 1024) % 2 == 1 then background = background + 1 end
      end
    end
  end
  ok(calls == 398, "the cartridge shakes something this many times", calls, 398)
  ok(amounts[2] == 219, "...and the commonest amount is 2, on this many of them",
     amounts[2], 219)
  ok(intervals[1] == 391 and intervals[0] == 7,
     "...with an interval of 1 on all but seven",
     ("%s and %s"):format(tostring(intervals[1]), tostring(intervals[0])),
     "391 and 7")
  -- AND NOT ONE OF THEM SHAKES THE BACKGROUND, which is why `shake` needs no
  -- background arm and `shakebg` is the only caller that would.
  ok(background == 0, "...and NONE of them names the background", background, 0)
end

do
  -- THE WAVEFORM, on a synthetic task because no move shows a whole cycle plainly
  -- (219 of the calls are two cycles at one frame a phase, which is over in eight
  -- frames). Labelled as synthetic; the operands are the cartridge's commonest.
  if player and player:start(1, true) then
    player.tasks = {}
    player:addTask({ kind = "shake", extentX = 2, extentY = 0, interval = 1,
                     amount = 2, sides = { [true] = true } })
    local seq = {}
    for _ = 1, 12 do
      player:stepTasks()
      local dx = player:monOffset(true)
      seq[#seq + 1] = tostring(dx)
    end
    local want = "0,2,0,-2,0,2,0,-2,0,0,0,0"
    ok(table.concat(seq, ",") == want,
       "a shake of amount 2 runs EIGHT flips through the centre",
       table.concat(seq, ","), want)
  end
  -- ...and the interval spaces the phases rather than shortening the shake: one
  -- cycle at interval 5 is twenty frames, not four.
  if player and player:start(1, true) then
    player.tasks = {}
    player:addTask({ kind = "shake", extentX = 0, extentY = 5, interval = 5,
                     amount = 1, sides = { [true] = true } })
    local held, seen = 0, {}
    for _ = 1, 22 do
      player:stepTasks()
      local _, dy = player:monOffset(true)
      seen[#seen + 1] = tostring(dy)
      if dy ~= 0 then held = held + 1 end
    end
    ok(held == 10,
       "...and one cycle at interval 5 holds each extreme for five frames",
       held .. " frames off centre", 10)
    ok(seen[1] == "0" and seen[2] == "5" and seen[7] == "0" and seen[12] == "-5",
       "...in the order +E, 0, -E, 0 -- through the centre, not between extremes",
       ("%s,%s,...,%s,...,%s"):format(seen[1], seen[2], seen[7], seen[12]),
       "0,5,...,0,...,-5")
  end
  -- AND IT COMES HOME BY ARITHMETIC. Four phases per cycle means the last one is
  -- always the centre, so nothing has to put the battler back -- and a waveform
  -- that alternated between the extremes would need to, which is how the old one
  -- hid its own shape.
  if player and player:start(1, true) then
    player.tasks = {}
    player:addTask({ kind = "shake", extentX = 3, extentY = 3, interval = 2,
                     amount = 3, sides = { [true] = true } })
    local last, guard, offCentre = nil, 0, 0
    while guard < 80 do
      guard = guard + 1
      local live = false
      for _, task in ipairs(player.tasks) do
        if task.kind == "shake" and not task.done then live = true end
      end
      if not live then break end
      player:stepTasks()
      local dx, dy = player:monOffset(true)
      if dx ~= 0 or dy ~= 0 then offCentre = offCentre + 1 end
      last = ("%d,%d"):format(dx, dy)
    end
    ok(last == "0,0", "a shake ends centred without being reset",
       tostring(last), "0,0")
    -- DERIVED, NOT COUNTED OFF THE RUN: two phases in every four are off centre
    -- and each phase lasts `interval` frames, so `2 * amount * interval`. Reading
    -- `amount` as a flip count gives a quarter of it.
    ok(offCentre == 2 * 3 * 2,
       "...spending 2 * amount * interval frames off centre",
       offCentre, 2 * 3 * 2)
    -- !! AND ONE PLANT HERE IS NOT A FAULT: removing the `extent == 0` early
    -- return changes nothing, because `-0` equals `0` in Lua and the phase that
    -- would negate it lands on zero anyway. It is kept because it is pret's own
    -- `prevVal == 0` branch and states why 336 of the 398 calls never move
    -- vertically -- a guard, proved by the faults it catches elsewhere.

  end
end

-- ---------------------------------------------------------------------------
-- 14: THE REPORT ITSELF, and the two entries that were noise
--
-- `missing()` is the work queue, so an error in it costs work in the wrong place.
-- Two things were wrong: the report accumulated for the life of the PLAYER rather
-- than the run, and the commonest entry in it was a command that does nothing on
-- the cartridge either.
-- ---------------------------------------------------------------------------
io.write("\nthe gap report\n")

do
  -- PER RUN, NOT PER PLAYER. Walking two programs must not leave the first one's
  -- gaps in the second one's report -- which is what made the queue read as though
  -- nearly every gap touched nearly every move.
  if player then
    local withGaps, withoutGaps = nil, nil
    for id = 0, arc.count - 1 do
      if player:start(id, true) then
        local f = 0
        while player:update() and f < 200 do f = f + 1 end
        local n = 0
        for _ in ipairs(player:missing()) do n = n + 1 end
        if n > 0 and withGaps == nil then withGaps = id end
        if n == 0 and withoutGaps == nil then withoutGaps = id end
      end
      if withGaps and withoutGaps then break end
    end
    ok(withGaps ~= nil and withoutGaps ~= nil,
       "one program with gaps and one without were both found",
       ("%s and %s"):format(tostring(withGaps), tostring(withoutGaps)),
       "two move ids")
    if withGaps and withoutGaps then
      -- Run the gappy one FIRST and the clean one after: a report that carried
      -- over would show the first one's rows on the second.
      player:start(withGaps, true)
      local f = 0
      while player:update() and f < 200 do f = f + 1 end
      player:start(withoutGaps, true)
      f = 0
      while player:update() and f < 200 do f = f + 1 end
      local carried = 0
      for _ in ipairs(player:missing()) do carried = carried + 1 end
      ok(carried == 0,
         "...and a run's gaps do not leak into the next run's report",
         carried .. " rows carried over", 0)
    end
  end
end

do
  -- THE THREE "EXAMPLE" FUNCTIONS ARE REALLY CALLED, which is what makes the
  -- argument about them an argument rather than housekeeping on dead entries.
  local counts, moves = {}, {}
  for id = 0, arc.count - 1 do
    for _, ins in ipairs((programs[id] or {}).code or {}) do
      if ins[1] == 45 then
        local fn = ins[2]
        if fn == 1 or fn == 2 or fn == 3 then
          counts[fn] = (counts[fn] or 0) + 1
          moves[fn] = moves[fn] or {}
          moves[fn][id] = true
        end
      end
    end
  end
  local n1, n2, n3 = 0, 0, 0
  for _ in pairs(moves[1] or {}) do n1 = n1 + 1 end
  for _ in pairs(moves[2] or {}) do n2 = n2 + 1 end
  for _ in pairs(moves[3] or {}) do n3 = n3 + 1 end
  ok(counts[1] == 33 and counts[2] == 33 and counts[3] == 33,
     "the cartridge calls each of pret's three example functions",
     ("%s / %s / %s"):format(tostring(counts[1]), tostring(counts[2]),
                             tostring(counts[3])),
     "33 each")
  ok(n1 == 33 and n2 == 33 and n3 == 33,
     "...once each in this many programs", ("%d / %d / %d"):format(n1, n2, n3),
     "33 each")
  -- AND ONLY THE ANIM ONE COSTS TIME. All three task bodies do nothing; what
  -- separates them is the queue. So two are argued skips and the first is not --
  -- if it ever joins them, a program that waits on anim tasks gets two frames
  -- shorter for no reason anybody would find later.
  ok(Play.Player.NOT_NEEDED["callfunc:soundexample"] ~= nil
     and Play.Player.NOT_NEEDED["callfunc:genericexample"] ~= nil,
     "...the two whose queues nothing waits on are argued skips",
     true, true)
  ok(Play.Player.NOT_NEEDED["callfunc:animexample"] == nil
     and Play.Player.FUNC.ANIM_EXAMPLE == 1,
     "...and the anim one is implemented instead, because it costs two frames",
     Play.Player.FUNC.ANIM_EXAMPLE, 1)
  -- !! AND THE TWO FRAMES ARE UNOBSERVABLE ON THIS CARTRIDGE, said here so that
  -- planting against them and finding nothing does not read as a broken check.
  -- All 33 callers are the example programs at the end of the table (moves 468
  -- upward), they are 60 frames long with the hold or without it, and none of them
  -- waits on anim tasks afterwards. The hold is kept because it is what the task
  -- does -- and because this engine runs mod-authored move scripts too, where a
  -- wait after the call is a thing somebody can write.
  -- `setextraparams` is the same shape of argument and the biggest one: pret's
  -- handler is compiled out, so the cartridge does nothing with it either. Its
  -- WIDTH is still solved against this check, which is section 2.
  ok(Play.Player.NOT_NEEDED["setextraparams"] ~= nil,
     "...and setextraparams is argued, not implemented", true, true)
end

-- ---------------------------------------------------------------------------
-- 15: AN EMITTER THAT TRAVELS
--
-- `MoveEmitterA2BLinear` (65) and `MoveEmitterA2BParabolic` (66): 119 calls over
-- 37 of the 501 programs, and until this section existed every one of them left
-- its emitter on the spot. What can go wrong is the PATH, the SLOT it addresses,
-- and -- the one that looks right and is not -- whether the particles already in
-- the air follow the emitter or stay where they were born.
-- ---------------------------------------------------------------------------
io.write("\nemitters that travel\n")

do
  local calls, moves, radii, params, argCounts = { [65] = 0, [66] = 0 }, { [65] = {}, [66] = {} }, {}, 0, {}
  for id = 0, arc.count - 1 do
    for _, ins in ipairs((programs[id] or {}).code or {}) do
      if ins[1] == 45 and (ins[2] == 65 or ins[2] == 66) then
        local fn = ins[2]
        calls[fn] = calls[fn] + 1
        moves[fn][id] = true
        argCounts[signedWord(ins[3])] = (argCounts[signedWord(ins[3])] or 0) + 1
        radii[signedWord(ins[9])] = (radii[signedWord(ins[9])] or 0) + 1
        if signedWord(ins[11] or 0) ~= 0 then params = params + 1 end
      end
    end
  end
  local n65, n66 = 0, 0
  for _ in pairs(moves[65]) do n65 = n65 + 1 end
  for _ in pairs(moves[66]) do n66 = n66 + 1 end
  ok(calls[65] == 46 and calls[66] == 73,
     "the cartridge moves an emitter this many times",
     ("%d linear, %d parabolic"):format(calls[65], calls[66]), "46 and 73")
  ok(n65 == 15 and n66 == 22, "...across this many programs each",
     ("%d and %d"):format(n65, n66), "15 and 22")
  -- A NEGATIVE RADIUS OCCURS, which is why the operand's sign is kept rather than
  -- folded into the frame conversion: pret negates the radius for its own y-up
  -- frame, this port does not, and a call that asks for the other direction still
  -- gets it.
  ok((radii[-32] or 0) > 0, "...and some of them ask for a radius of -32",
     radii[-32] or 0, "more than none")
  ok(params == 10, "...while this many pack a skip/max window into `params`",
     params, 10)
end

-- THE LINEAR PATH, on move 48, which addresses its emitter by SLOT 1.
do
  local frames, offsets, originName = 0, {}, nil
  if player and player:start(48, true) then
    while player:update() and frames < 200 do
      frames = frames + 1
      for _, e in ipairs(player.emitters) do
        if e.system.emitterX then
          local at = ("%d,%d"):format(e.system.emitterX, e.system.emitterY)
          if offsets[#offsets] ~= at then offsets[#offsets + 1] = at end
          originName = e.origin
        end
      end
    end
  end
  ok(#offsets == 14, "move 48's emitter walks its path in fourteen steps",
     #offsets, 14)
  ok(originName == "attacker", "...measured from the attacker, its own origin",
     tostring(originName), "attacker")
  -- IT LANDS ONE PIXEL SHORT OF THE DEFENDER, and that is the arithmetic rather
  -- than a rounding fudge: a 14-step lerp over 128 pixels floors its accumulator
  -- every frame. Stating 191 rather than 192 is what makes this a measurement.
  -- NOT `player and player:originPixels(...)`: an `and` expression is truncated to
  -- ONE value in a multiple assignment, so the Y arrives nil and the assertion
  -- fails on -64. This repo's own notes record that trap, and it was walked into
  -- again three sections below where it was written down.
  local ox, oy
  if player then ox, oy = player:originPixels(originName or "attacker") end
  local lastX, lastY = (offsets[#offsets] or ""):match("^(%-?%d+),(%-?%d+)$")
  local absX = lastX and (tonumber(lastX) + (ox or 0))
  local absY = lastY and (tonumber(lastY) + (oy or 0))
  ok(absX == 191 and absY == 48,
     "...ending one pixel short of the defender at 192,48",
     ("%s,%s"):format(tostring(absX), tostring(absY)), "191,48")
end

-- !! AND THE PARTICLES ARE LEFT BEHIND. This is the assertion the whole design of
-- the change rests on: a particle records where its emitter was WHEN IT WAS BORN,
-- so a travelling emitter leaves a trail. Adding the emitter's CURRENT position at
-- draw time instead would give a burst that slides along behind it -- a moving
-- picture of an emitter -- and every other assertion in this section would still
-- pass, because the path, the slot and the endpoint would all be right.
do
  local spread, distinct = nil, 0
  if player and player:start(48, true) then
    local f = 0
    while player:update() and f < 60 do
      f = f + 1
      if f == 29 then
        local seen, lo, hi = {}, nil, nil
        for _, q in ipairs(player:particles()) do
          local x = floorDiv(q.x)
          seen[x] = true
          if lo == nil or x < lo then lo = x end
          if hi == nil or x > hi then hi = x end
        end
        for _ in pairs(seen) do distinct = distinct + 1 end
        spread = (hi or 0) - (lo or 0)
      end
    end
  end
  ok(distinct >= 3,
     "a travelling emitter leaves particles at SEVERAL birth points",
     distinct .. " distinct x positions", "3 or more")
  ok(spread == 91, "...spread this far apart on move 48's 29th frame",
     tostring(spread), 91)
end

-- THE PARABOLA BOWS UPWARD IN THIS PORT'S FRAME, which is the opposite sign from
-- pret's -- its world frame has +Y up (the world table puts the player at -1.33
-- and the enemy at +1.07 while the player stands LOWER on screen), so its
-- `radius * -FX32_ONE` and this port's unnegated radius are the same arc.
-- Synthetic, because the three overlapping flights in move 42 cannot be separated
-- from the outside.
do
  if player and player:start(42, true) then
    local fake = { system = { emitterX = 0, emitterY = 0 }, origin = "attacker" }
    player.tasks = {}
    player.emitterAt = { [0] = fake }
    ok(player:startEmitterPath(true, { emitterId = 0, frames = 12, radius = 32 })
       == true, "a synthetic parabolic path starts", true, true)
    local pts = { { x = fake.system.emitterX, y = fake.system.emitterY } }
    for _ = 1, 12 do
      player:stepTasks()
      pts[#pts + 1] = { x = fake.system.emitterX, y = fake.system.emitterY }
    end
    local a, b, worst = pts[1], pts[#pts], 0
    for i, p in ipairs(pts) do
      local at = (i - 1) / math.max(1, #pts - 1)
      local line = a.y + (b.y - a.y) * at
      local bow = line - p.y
      if bow > worst then worst = bow end
    end
    ok(worst > 20 and worst < 34,
       "...and bows between 20 and 34 pixels above its own chord",
       ("%.1f"):format(worst), "a radius of 32, sampled at whole frames")
  end
end

-- AND `maxFrames` PARKS THE EMITTER rather than shortening its trip: pret sets
-- `frame = maxFrames + 1` at init and nothing ever increments `frame`, so the
-- task's own guard suppresses every later update. Twelve of the 119 calls do this;
-- forced here because separating one of them from its move is not possible from
-- the outside.
do
  if player and player:start(42, true) then
    local fake = { system = { emitterX = 0, emitterY = 0 }, origin = "attacker" }
    player.tasks = {}
    player.emitterAt = { [0] = fake }
    -- skipFrames 4 in the high half, maxFrames 6 in the low half.
    player:startEmitterPath(false, { emitterId = 0, frames = 12,
                                     params = 4 * 65536 + 6 })
    local placed = ("%d,%d"):format(fake.system.emitterX, fake.system.emitterY)
    for _ = 1, 10 do player:stepTasks() end
    local after = ("%d,%d"):format(fake.system.emitterX, fake.system.emitterY)
    -- AND THE EXACT POINT IS THE ASSERTION, not merely that it stopped moving.
    -- `params` packs skipFrames in the HIGH half and maxFrames in the low one, and
    -- reading them the other way round still parks the emitter -- just somewhere
    -- else. Four of twelve steps from the attacker (64,112) toward the defender
    -- (192,48) is 42,-22 as an offset from the attacker's own origin, flooring each
    -- axis; six steps would be 64,-32.
    ok(placed == after and placed == "42,-22",
       "a parked emitter is placed once, four steps along, and never moves again",
       ("%s then %s"):format(placed, after), "42,-22 twice")
  end
end

-- AND THE TWO FILES AGREE ABOUT WHERE AN ORIGIN IS. The player resolves origin
-- names now (a path between battlers has to be expressed relative to one), and the
-- screen has always resolved them. A drift between the two puts a travelling
-- emitter somewhere its own particles are not.
do
  local gbPath = (root ~= "" and root or "./") .. "../src/battle/Gen4Battle.lua"
  local gbFile = io.open(gbPath, "rb")
  local gb = gbFile and gbFile:read("*a")
  if gbFile then gbFile:close() end
  local names = { "player", "enemy", "attacker", "defender" }
  local missingName = {}
  for _, name in ipairs(names) do
    if not (gb and gb:find('name == "' .. name .. '"', 1, true)) then
      missingName[#missingName + 1] = name
    end
  end
  ok(#missingName == 0,
     "the screen resolves the same four origin names the player does",
     #missingName == 0 and "all four" or table.concat(missingName, ","), "all four")
  if player and player:start(1, true) then
    local px, py = player:originPixels("player")
    local ex, ey = player:originPixels("enemy")
    local mx, my = player:originPixels("midpoint-or-anything-else")
    ok(px == 64 and py == 112 and ex == 192 and ey == 48,
       "...and the player's own resolution is the battler table",
       ("%d,%d and %d,%d"):format(px, py, ex, ey), "64,112 and 192,48")
    ok(mx == (64 + 192) / 2 and my == (112 + 48) / 2,
       "...with an unknown name landing between the two, as the screen does",
       ("%s,%s"):format(tostring(mx), tostring(my)), "128,80")
  end
end

-- ---------------------------------------------------------------------------
-- 16: THE EFFECT BACKGROUND LAYER
--
-- `switchbg` and `restorebg` are 129 calls over 54 programs and were the largest
-- single thing this player did not do. What can be wrong about them, in order of
-- how badly: the TABLE that says which archive members make up a background, the
-- COMPOSITE that turns those members into a picture, the TIMING of the two state
-- machines, the VARIANT chosen for the attacking side, and the SCROLL and SHAKE
-- that ride on the layer.
--
-- THE FIRST ASSERTION IS THE ONE THAT MATTERS MOST, because every number below it
-- is downstream of the table: the 1,160 bytes of `EFFECT_BG_MEMBERS` are searched
-- for IN THE CARTRIDGE'S OWN OVERLAYS. A table that was transcribed with one digit
-- wrong is found zero times, and nothing else here could tell.
--
-- TWENTY FAULTS WERE PLANTED AGAINST THIS SECTION AND ALL TWENTY FAIL IT. Recorded
-- so nobody has to re-derive which assertion covers what, and because two of them
-- were not faults until something else was changed:
--   one digit of row 30's palette             -> the overlay search finds 0 matches
--   the mirrored and contest columns swapped   -> 116 column comparisons
--   the palette put in sub-palette 0           -> coverage 0, and 81 blank
--   `paletteAtSlot` ignoring its slot          -> the same, four ways
--   the sparse-palette guard back to #colours  -> nothing composes at all
--   `coversScreen` asking "mostly"             -> coverage 81 instead of 35
--   `coversScreen` over the whole 512x256      -> coverage 12 instead of 35
--   the switch task running on its own frame   -> the picture loads on 13, not 14
--   `waitforbgswitch` free again               -> 0 frames held
--   `waitforanimtasks` counting the scroll     -> twelve programs hang
--   shakebg with no outer cycle loop           -> cycles = 3 is one run, not four
--   the blend step clamping to its target      -> no overshoot to full strength
--   the restore ending like the switch         -> 29/2 instead of 31/0
--   the two blend coefficients swapped         -> the field dims to 1/8
--   nothing ever mirrored                      -> program 87 is "normal" both ways
--   the scroll not stepping                    -> 0 steps of 32
--   the layer drawn after the battlers         -> the draw order
--   `effectFade` tinting the particles again   -> the identity assertion
--   the layer reporting no shake without a switch -> 0 displaced frames
--   the palette guard back to being per group  -> the corpus tint total
--
-- AND THE TWO THAT ONLY BECAME FAULTS ONCE SOMETHING ELSE MOVED. Swapping the two
-- tilemap-column constants failed NOTHING at first, because `effectBackground`
-- reached the columns by arithmetic on the first one and left the other two
-- declared and unused; the constants are indexed by name now, and that is what
-- makes the plant bite. And `coversScreen` could not be tested at all while it
-- lived on the extractor, which does not load outside the engine -- moving it to
-- `Gen4Graphics` is what turned three assertions from "the source mentions it" into
-- "the function separates two named backgrounds".
-- ---------------------------------------------------------------------------
io.write("\nthe effect background layer\n")

local okBg, Bg4 = pcall(require, "src.import.Gen4Battle")
local Gfx4 = select(2, pcall(require, "src.import.Gen4Graphics"))

if not okBg then
  io.write("  (src/import/Gen4Battle.lua did not load -- section skipped)\n")
else

ok(Bg4.EFFECT_BG_COUNT == 58, "fifty-eight effect backgrounds",
   Bg4.EFFECT_BG_COUNT, 58)

do
  -- The table, encoded the way the cartridge stores it: 58 rows of five 32-bit
  -- little-endian words, in BgNarcMemberType order.
  local parts = {}
  local holes = 0
  for id = 0, Bg4.EFFECT_BG_COUNT - 1 do
    local row = Bg4.EFFECT_BG_MEMBERS[id]
    if type(row) ~= "table" or #row ~= 5 then
      holes = holes + 1
    else
      for k = 1, 5 do
        local v = row[k]
        parts[#parts + 1] = string.char(v % 256, floorDiv(v / 256) % 256,
                                        floorDiv(v / 65536) % 256,
                                        floorDiv(v / 16777216) % 256)
      end
    end
  end
  ok(holes == 0, "every row is five members wide", holes .. " malformed", 0)
  local needle = table.concat(parts)
  ok(#needle == 58 * 5 * 4, "...which is 1,160 bytes of table", #needle, 1160)

  local found, where = 0, {}
  local header = rom:header()
  local overlays = (header and header.overlays9) or 0
  for i = 0, overlays - 1 do
    local bytes = rom:overlay(i)
    if bytes then
      local at = bytes:find(needle, 1, true)
      while at do
        found = found + 1
        where[#where + 1] = ("overlay %d at 0x%X"):format(i, at - 1)
        at = bytes:find(needle, at + 1, true)
      end
    end
  end
  -- ONCE, AND IN THE BATTLE ANIMATION OVERLAY. Not "at least once": a table that
  -- happened to match a run of graphics data would show up more than once, and a
  -- table that matched nothing would be a transcription error rather than a fact
  -- about the cartridge.
  ok(found == 1, "the port's table IS the cartridge's, found once in its overlays",
     found == 1 and where[1] or (found .. " matches"), "exactly one")
  ok(where[1] ~= nil and where[1]:match("^overlay 12 "),
     "...in overlay 12, which is where the battle animation system lives",
     where[1] or "nowhere", "overlay 12")

  -- AND THE COLUMNS ARE READ IN THE CARTRIDGE'S ORDER, which the search above
  -- CANNOT SEE: the needle is built from the same table `effectBackground` indexes,
  -- so swapping which column means "mirrored" and which means "contest" leaves the
  -- bytes identical and the search still finds them. So the table is decoded back
  -- out of the overlay and the three arrangements are compared against it, member by
  -- member. Measured against the plant: swapping those two constants fails 58 rows
  -- here and nothing else in this section.
  local at = where[1] and tonumber(where[1]:match("0x(%x+)"), 16)
  local overlay12 = rom:overlay(12)
  local wrongColumn, comparedRows = 0, 0
  if at and overlay12 then
    local function word(index)
      local base = at + index * 4
      local b1, b2, b3, b4 = overlay12:byte(base + 1, base + 4)
      if not b4 then return nil end
      return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
    end
    for id = 0, Bg4.EFFECT_BG_COUNT - 1 do
      comparedRows = comparedRows + 1
      for k = 1, #Bg4.EFFECT_VARIANTS do
        local spec = Bg4.effectBackground(id, Bg4.EFFECT_VARIANTS[k])
        -- row `id` is five words; the tilemaps are words 2, 3 and 4 of it.
        local want = word(id * 5 + 1 + k)
        if not (spec and want and spec.tilemap == want) then
          wrongColumn = wrongColumn + 1
        end
        local wantTiles, wantPalette = word(id * 5), word(id * 5 + 1)
        if not (spec and spec.tiles == wantTiles and spec.palette == wantPalette) then
          wrongColumn = wrongColumn + 1
        end
      end
    end
  end
  ok(comparedRows == 58 and wrongColumn == 0,
     "...and normal/mirrored/contest are its columns 3, 4 and 5 in that order",
     ("%d rows, %d columns read wrong"):format(comparedRows, wrongColumn),
     "58 rows, 0 wrong")
end

-- THE MEMBER TYPES, which is the second thing a wrong table would break and the
-- first thing a RESHUFFLED one would. Column 1 has to be a tile sheet, column 2 a
-- palette and columns 3-5 tilemaps; the four-character magic says which.
local bgArc = nil
do
  local raw = rom:read(Bg4.ARCHIVE_BG)
  bgArc = raw and Narc.parse(raw)
  ok(bgArc ~= nil and bgArc.count == 342, "pl_batt_bg opens, with 342 members",
     bgArc and bgArc.count or "no archive", 342)
end

local function bgMember(i)
  if not (bgArc and i) then return nil end
  local b = bgArc:get(i)
  if b and Gfx4.isCompressed(b) then b = Gfx4.decompress(b) end
  return b
end

if bgArc and Gfx4 then
  local want = { "RGCN", "RLCN", "RCSN", "RCSN", "RCSN" }
  local wrong, checkedRows = 0, 0
  for id = 0, Bg4.EFFECT_BG_COUNT - 1 do
    local row = Bg4.EFFECT_BG_MEMBERS[id]
    if row then
      checkedRows = checkedRows + 1
      for k = 1, 5 do
        local b = bgMember(row[k])
        if not b or b:sub(1, 4) ~= want[k] then wrong = wrong + 1 end
      end
    end
  end
  ok(checkedRows == 58 and wrong == 0,
     "a sheet, a palette and three tilemaps, all 290 members",
     ("%d rows, %d members of the wrong kind"):format(checkedRows, wrong),
     "58 rows, 0 wrong")

  -- THE COMPOSITE. 174 (id, arrangement) pairs resolve to 81 distinct pictures,
  -- because most backgrounds reuse one tilemap for two or three arrangements.
  local seen, composed, failed, covered = {}, 0, 0, 0
  local blankAtSlotZero, complements, neither = 0, 0, 0
  local bg19, thin = nil, nil
  for id = 0, Bg4.EFFECT_BG_COUNT - 1 do
    for _, variant in ipairs(Bg4.EFFECT_VARIANTS) do
      local spec = Bg4.effectBackground(id, variant)
      if spec and not seen[spec.art] then
        seen[spec.art] = true
        local sheet = Gfx4.tiles(bgMember(spec.tiles))
        local raw = Gfx4.palette(bgMember(spec.palette))
        local map = Gfx4.tilemap(bgMember(spec.tilemap))
        local image = sheet and raw and map
          and Gfx4.compose(map, sheet, Gfx4.paletteAtSlot(raw, spec.slot))
        if image then
          composed = composed + 1
          -- THE EXTRACTOR'S OWN RULE, called rather than restated. It records an
          -- `opaque` flag per picture and the screen only draws the type-2 palette
          -- blend as a whole-screen quad where that flag is set, so a coverage test
          -- that spelled the rule out a second time here would be testing this file
          -- against itself.
          if Gfx4.coversScreen(image) then covered = covered + 1 end
          if id == 19 then bg19 = image end
          if id == 36 then thin = image end
        else
          failed = failed + 1
        end
        -- ...AND THE SLOT IS LOAD-BEARING, which this measures two ways. Composed
        -- with the palette at slot 0 -- which is what every other sheet in this
        -- archive wants -- 68 of the 81 come out with NO PIXELS AT ALL, because
        -- 64,866 of these tilemaps' cells name sub-palette 9 and read past a
        -- sixteen-entry table. This is the fault that made the first attempt at
        -- this layer look like a missing-image bug.
        --
        -- The other 13 come out as the exact COMPLEMENT: their tilemaps are part
        -- slot-9 cells and part slot-0 cells, and the two halves cover every pixel
        -- between them, so composing at the wrong slot draws precisely the half the
        -- switch does not load. `inkAt` is recorded for both so the complement can
        -- be asserted rather than described.
        if sheet and raw and map then
          local flat = Gfx4.compose(map, sheet, raw)
          if flat and image then
            local byte = string.byte
            local function inkFraction(img)
              local pixels, lit = #img.rgba / 4, 0
              for pix = 0, pixels - 1 do
                if byte(img.rgba, pix * 4 + 4) ~= 0 then lit = lit + 1 end
              end
              return lit / pixels
            end
            local atZero, atNine = inkFraction(flat), inkFraction(image)
            if atZero == 0 then
              blankAtSlotZero = blankAtSlotZero + 1
            elseif ("%.4f"):format(atZero + atNine) == "1.0000" then
              complements = complements + 1
            else
              neither = neither + 1
            end
          end
        end
      end
    end
  end
  ok(composed == 81 and failed == 0,
     "eighty-one distinct pictures, all of which compose",
     ("%d composed, %d failed"):format(composed, failed), "81 and 0")
  ok(covered == 35, "...of which this many cover the visible 256x192", covered, 35)
  ok(blankAtSlotZero == 68,
     "...and 68 of them are EMPTY if the palette goes in slot 0",
     blankAtSlotZero, 68)
  ok(complements == 13 and neither == 0,
     "...while the other 13 come out as the exact complement of themselves",
     ("%d complements, %d neither"):format(complements, neither), "13 and 0")
  -- AND THE RULE ITSELF SEPARATES, which is what makes the 35 above a measurement
  -- rather than a count of whatever the function happened to return. Background 19
  -- -- the one the cartridge's only type-2 palette blend is applied to -- covers the
  -- screen; background 36 does not, and it is 75% covered, so a rule that asked
  -- "mostly" rather than "every pixel" would pass both.
  ok(bg19 ~= nil and Gfx4.coversScreen(bg19) == true,
     "background 19, the one the type-2 fade lands on, covers the screen",
     bg19 and tostring(Gfx4.coversScreen(bg19)) or "not composed", "true")
  ok(thin ~= nil and Gfx4.coversScreen(thin) == false,
     "...and background 36, which is three-quarters covered, does not",
     thin and tostring(Gfx4.coversScreen(thin)) or "not composed", "false")
  -- A window of one pixel is covered by anything with ink in its corner, which is
  -- the degenerate end of the same rule and proves the arguments are read.
  ok(thin ~= nil and Gfx4.coversScreen(thin, 1, 1) == true,
     "...while its top-left pixel alone is covered", "true", "true")
end

-- ---------------------------------------------------------------------------
-- The two state machines, measured by running a program and looking
-- ---------------------------------------------------------------------------

-- run(move, attackerIsPlayer) -> rows, frames
--   `rows[f]` is `bgLayerState()` on frame f, plus the switch state and the base
--   group's tint, which is the channel the fade mode actually blacks the field with.
local function runBg(move, attackerIsPlayer, cap)
  if not (player and player:start(move, attackerIsPlayer)) then return nil end
  local rows, frames = {}, 0
  while player:update() and frames < (cap or 400) do
    frames = frames + 1
    local _, _, _, baseA = player:groupTint("base")
    rows[frames] = {
      st = player:bgLayerState(), switch = player.bgSwitchState, base = baseA,
      waits = player.bgWaits,
    }
  end
  return rows, frames
end

-- PROGRAM 19 (`switchbg 55, 0x20001` then `restorebg 55, 0x40001`) is the ordinary
-- shape: a FADE-mode switch with the MOVE flag, and a restore with STOP. Every
-- number below is a frame count out of pret's own state machine, and there is no
-- rounding available -- a fade is eight palette steps at two per frame and the
-- states either cost a frame each or they do not.
do
  local rows, frames = runBg(19, true)
  ok(rows ~= nil, "program 19 runs", frames, "a frame count")
  if rows then
    local firstSwitch, firstLayer, firstPartial, lastLayer = nil, nil, nil, nil
    local blackFrames, layerFrames = 0, 0
    for f = 1, frames do
      local r = rows[f]
      if firstSwitch == nil and r.switch ~= 0 then firstSwitch = f end
      if firstPartial == nil and r.switch == 2 then firstPartial = f end
      if r.st and r.st.id then
        firstLayer = firstLayer or f
        lastLayer = f
        layerFrames = layerFrames + 1
      end
      if r.base and r.base >= 1 then blackFrames = blackFrames + 1 end
    end
    -- 9 AND NOT 3: program 19 opens with TWO `LoadParticleResource` blocks and each
    -- costs three frames now that `RenderPokemonSprites 0` is read as
    -- RENDER_POKEMON_SPRITES_DEFAULT_FRAMES. Every frame number in this block moved
    -- by exactly six and the INTERVALS between them did not, which is what makes
    -- this a corrected prologue rather than a changed state machine.
    ok(firstSwitch == 9,
       "the switch is running from the frame after its command",
       firstSwitch, 9)
    -- EIGHT PALETTE STEPS AND A SKIPPED FRAME. The task is created at priority 1100
    -- from the script's task at 0, so it does not run on the frame the command
    -- ran; its state 0 starts the fade on frame 4; the fade blends at 0, 2, 4 .. 16
    -- one frame apart and reports itself finished on the frame after it reaches 16.
    -- The picture is loaded on the first frame the switch sees no fade running.
    ok(firstLayer == 20,
       "...the new picture is loaded on frame 20, once the screen is fully black",
       firstLayer, 20)
    ok(firstPartial == 20,
       "...which is the same frame BATTLE_BG_SWITCH_STATE_PARTIAL is reached",
       firstPartial, 20)
    -- The field is held at full black for the whole switched stretch, because the
    -- fade mode never fades the backdrop's palettes back until the restore -- plus
    -- THREE frames that are black with no picture on them, and all three are
    -- accounted for rather than allowed for: two at the start (the frame the
    -- backdrop's fade reaches 16, and the frame the switch spends discovering the
    -- fade has ended) and one at the end (the frame the restore hides the picture,
    -- before its recovery fade takes its first step).
    ok(blackFrames == layerFrames + 3,
       "...and the field is black for all of it and three frames besides",
       ("%d black, %d with a picture"):format(blackFrames, layerFrames),
       "three more black frames than picture frames")
    ok(lastLayer ~= nil and lastLayer < frames,
       "...and the picture comes down before the program ends",
       lastLayer and (frames - lastLayer) .. " frames after it", "more than 0")
    -- THE WAIT IS NOT FREE. 22 frames of `waitforbgswitch` on this program, and a
    -- wait that returned immediately would leave the animation playing over the
    -- unswitched backdrop -- which is what it did until this pass.
    ok(rows[frames].waits >= 20,
       "...and `waitforbgswitch` actually held the program",
       rows[frames].waits .. " frames held", "at least 20")
  end
end

-- THE SCROLL. Program 19 sets BG_MOVE_STEP_Y to 32 and switches with the MOVE flag,
-- so the layer walks down 32 pixels a frame for as long as it is up -- and STOPS
-- when the restore carries the STOP flag, which is the only thing that ever stops
-- it.
do
  local rows, frames = runBg(19, true)
  if rows then
    local steps, firstOffset, lastOffset = {}, nil, nil
    for f = 2, frames do
      local a, b = rows[f - 1].st, rows[f].st
      if a and b and a.id and b.id then
        steps[#steps + 1] = (b.offsetY or 0) - (a.offsetY or 0)
        firstOffset = firstOffset or a.offsetY
        lastOffset = b.offsetY
      end
    end
    local thirtyTwos, others = 0, 0
    for _, d in ipairs(steps) do
      if d == 32 then thirtyTwos = thirtyTwos + 1 else others = others + 1 end
    end
    ok(thirtyTwos > 20 and others <= 1,
       "the layer scrolls 32 pixels a frame while it is up",
       ("%d steps of 32, %d others"):format(thirtyTwos, others),
       "all but the first")
    ok(firstOffset == 0, "...starting from zero, as every call in the corpus does",
       firstOffset, 0)
  end
end

-- THE ARRANGEMENT DEPENDS ON WHO IS ATTACKING, which is the whole reason the
-- cartridge ships three tilemaps a background. `BG_SCREEN_MODE` is 1 on 76 of the
-- 129 calls, and it means "mirrored when the defender is the player".
do
  local mine = select(1, runBg(87, true))
  local theirs = select(1, runBg(87, false))
  local function variantOf(rows)
    for f = 1, 400 do
      local r = rows and rows[f]
      if r and r.st and r.st.id then return r.st.variant, r.st.id end
    end
  end
  local a, aid = variantOf(mine)
  local b, bid = variantOf(theirs)
  ok(a == "normal" and b == "reversed",
     "program 87's background is mirrored when the enemy attacks",
     ("%s then %s"):format(tostring(a), tostring(b)), "normal then reversed")
  ok(aid == 19 and bid == 19, "...and it is the same background either way",
     ("%s and %s"):format(tostring(aid), tostring(bid)), "19 and 19")
end

-- `waitforanimtasks` MUST NOT SEE THE SWITCH OR ITS SCROLL. pret counts only the
-- tasks started through `StartAnimTask`, and the switch, the scroll and the wave are
-- plain `SysTask_Start`s. The scroll never ends on its own, so a `waitforanimtasks`
-- that counted it would hang -- and eight programs did hang, for exactly one
-- afternoon, before this was written down.
do
  local hung = 0
  local longest, at = 0, nil
  if player then
    for id = 0, arc.count - 1 do
      if player:start(id, true) then
        local f = 0
        while player:update() and f < Play.Player.FRAME_BUDGET + 10 do f = f + 1 end
        if f > longest then longest = f; at = id end
        if f >= Play.Player.FRAME_BUDGET then hung = hung + 1 end
      end
    end
  end
  ok(hung == 0, "no program runs into the frame budget",
     hung .. " at the budget", 0)
  ok(longest > 0 and longest < Play.Player.FRAME_BUDGET,
     "...and the longest still ends on its own",
     ("program %s, %d frames of %d"):format(tostring(at), longest,
                                            Play.Player.FRAME_BUDGET),
     "under the budget")
end

-- ---------------------------------------------------------------------------
-- shakebg
-- ---------------------------------------------------------------------------

-- WHAT WAS WRONG HERE WAS NOT THE MISSING PICTURE. This was a `hold` of `cycles`
-- frames, and `cycles` is 0 on 41 of the 42 calls -- so 41 of them held for no
-- frames at all, and every `waitforanimtasks` after one returned about twenty
-- frames early, while the comment above the code said the length was preserved.
--
-- The length is (cycles + 1) inner runs of amount * 4 flips at `interval` spacing,
-- one frame to return the offset to zero between runs, and one more frame in the
-- task's done state. All four of those terms are asserted below, because each of
-- them is a term a reimplementation drops.
do
  -- PROGRAM 284, which is one of the eleven that shake without ever switching.
  -- 32 of its 120 frames are displaced.
  local rows, frames = runBg(284, true)
  local shaken = 0
  if rows then
    for f = 1, frames do
      local r = rows[f]
      if r.st and ((r.st.offsetX or 0) ~= 0 or (r.st.offsetY or 0) ~= 0) then
        shaken = shaken + 1
      end
    end
  end
  -- A program that shakes without switching moves the BACKDROP, because outside a
  -- switch the effect layer is where the backdrop lives. So the state is reported
  -- with no `id` and a non-zero offset, which is exactly what the screen reads to
  -- decide which picture to move.
  ok(shaken == 32, "a shakebg with no switch up still reports an offset",
     shaken .. " frames displaced", 32)
end

-- The waveform, forced rather than found: +E, 0, -E, 0 is `ShakeContext_FlipPosition`
-- and `MAX_CYCLES_PER_SHAKE` is 4, so one unit of `amount` is four flips and the
-- last of them is always zero.
do
  if player and player:start(1, true) then
    player.tasks = {}
    player.bgShake = nil
    player:addTask({ kind = "bgshake", pending = true, extentX = 0, extentY = 5,
                     interval = 0, amount = 2, cycles = 0, layer = "effect",
                     inner = 0, iteration = 0 })
    local seq, alive = {}, 0
    for _ = 1, 20 do
      -- COUNTED BEFORE THE STEP, not after: the frame that ends the task is a frame
      -- the task ran, and counting afterwards loses it. That off-by-one is the
      -- whole difference between "the task lives eleven frames" and "ten".
      if player:taskCount() > 0 then alive = alive + 1 end
      player:stepTasks()
      seq[#seq + 1] = player.bgShake and player.bgShake[2] or 0
    end
    ok(table.concat(seq, " "):find("^0 5 0 %-5 0 5 0 %-5 0 0", 1) ~= nil,
       "the shake waveform is +E 0 -E 0, after one skipped frame",
       table.concat(seq, " "):sub(1, 22), "0 5 0 -5 0 5 0 -5 0 0")
    -- 1 skipped + 8 flips + 1 zeroing + 1 done = 11 frames for amount 2, cycles 0.
    ok(alive == 11, "...and the task lives for eleven frames, not two",
       alive, 11)
  end
end

-- ...AND THE OUTER LOOP IS REAL. `cycles` is 3 on exactly one call in the
-- cartridge, and it means four runs of the inner shake rather than three frames.
do
  if player and player:start(1, true) then
    player.tasks = {}
    player.bgShake = nil
    player:addTask({ kind = "bgshake", pending = true, extentX = 0, extentY = 5,
                     interval = 0, amount = 1, cycles = 3, layer = "effect",
                     inner = 0, iteration = 0 })
    local alive, zeroes, moved = 0, 0, 0
    for _ = 1, 40 do
      if player:taskCount() == 0 then break end
      alive = alive + 1
      player:stepTasks()
      local y = player.bgShake and player.bgShake[2] or 0
      if y == 0 then zeroes = zeroes + 1 else moved = moved + 1 end
    end
    -- 1 skipped + 4 * (4 flips + 1 zeroing) + 1 done = 22.
    ok(alive == 22, "cycles = 3 is FOUR inner shakes, not three frames", alive, 22)
    ok(moved == 8, "...eight of whose frames are actually displaced", moved, 8)
  end
end

-- THE ONE CALL THAT NAMES THE BASE LAYER IS RECORDED, NOT DRAWN. Program 87's
-- shakebg passes six arguments where the other 41 pass five, and the sixth is
-- SHAKE_BG_TARGET_BASE -- a layer this port does not draw, and one the cartridge
-- does not have switched on during a FADE-mode switch either. The player's own
-- comment used to claim all 42 passed five arguments; it was measured and it did
-- not.
do
  if player and player:start(87, true) then
    local f = 0
    while player:update() and f < 400 do f = f + 1 end
    local noted = 0
    for _, row in ipairs(player:missing()) do
      if row.what:find("base layer", 1, true) then noted = noted + row.count end
    end
    ok(noted == 1, "the base-layer shakebg is recorded exactly once", noted, 1)
  end
end

-- ---------------------------------------------------------------------------
-- The blend mode, and the operands nothing else covers
-- ---------------------------------------------------------------------------

-- MODE_BLEND IS TWO CALLS IN THE WHOLE CARTRIDGE, both in program 433, and they are
-- a matched pair: the switch uses BLEND_PARTIAL (the backdrop goes to half) and the
-- restore uses BLEND_INVERSE_PARTIAL (the picture comes up from half). A port that
-- only implemented the fade mode would play this move with no background at all.
do
  local rows, frames = runBg(433, true)
  local blendFrames, minBase, maxEffect, settled = 0, 2, 0, nil
  if rows then
    for f = 1, frames do
      local st = rows[f].st
      if st and st.id and st.blend then
        blendFrames = blendFrames + 1
        if st.base < minBase then minBase = st.base end
        if st.effect > maxEffect then maxEffect = st.effect end
        -- The pair the switch holds once both sides have finished, which is the
        -- frame after the overshoot is put back.
        if settled == nil and ("%.4f"):format(st.effect) == "0.9375" then
          settled = { st.base, st.effect }
        end
      end
    end
  end
  ok(blendFrames > 0, "program 433 cross-fades rather than fading to black",
     blendFrames .. " blended frames", "more than 0")
  -- PARTIAL's targets are A 15 and B 7, so the field bottoms out at 7/16.
  ok(("%.4f"):format(minBase) == "0.4375",
     "...with the field dimmed to 7/16 and no further",
     ("%.4f"):format(minBase), "0.4375")
  -- AND THE PICTURE REACHES FULL STRENGTH ON THE WAY, which is the overshoot and not
  -- a rounding slip: the rising side steps by two until it is NOT LESS THAN its
  -- target, so 14 becomes 16 rather than 15, and 16 is the hardware's maximum
  -- coefficient. It sits there for five frames before the frame on which both sides
  -- are finished writes the exact targets and settles it at 15/16. A port that
  -- clamped the step to the target would never show those five frames.
  ok(("%.4f"):format(maxEffect) == "1.0000",
     "...and the picture overshoots to full strength before settling",
     ("%.4f"):format(maxEffect), "1.0000")
  ok(settled ~= nil and ("%.4f/%.4f"):format(settled[1], settled[2]) == "0.4375/0.9375",
     "...settling at exactly the pair PARTIAL names, 7/16 and 15/16",
     settled and ("%.4f/%.4f"):format(settled[1], settled[2]) or "never settled",
     "0.4375/0.9375")
  -- AND THE RESTORE ENDS SOMEWHERE ELSE ENTIRELY. `BattleBgRestore_Blend` finishes
  -- by putting the overshoot BACK -- targetA + 2 and targetB - 2 -- so the last pair
  -- it writes is 31 and 0: the backdrop whole and the picture gone. The switch does
  -- not do that, and a port that shared one ending between them would leave a ghost
  -- of the effect layer at 2/16 over every blended move.
  local lastPair = nil
  if rows then
    for f = 1, frames do
      local st = rows[f].st
      if st and st.id and st.blend then lastPair = { st.base, st.effect } end
    end
  end
  ok(lastPair ~= nil and ("%.4f/%.4f"):format(lastPair[1], lastPair[2]) == "1.0000/0.0000",
     "...and the restore ends on the backdrop whole and the picture gone",
     lastPair and ("%.4f/%.4f"):format(lastPair[1], lastPair[2]) or "no frames",
     "1.0000/0.0000")
end

-- `setbgswitchvar` WRITES THE LIVE SCROLL, not the script vars -- which is why
-- pret's macro comment says it may only be used after a switch. All nine calls in
-- the cartridge write var 1, the Y step.
do
  if player and player:start(1, true) then
    player.bgAnim = { offsetX = 0, offsetY = 0, stepX = 0, stepY = 0, cancel = false }
    local before = player.bgAnim.stepY
    player.vars = {}
    -- var 1 is BG_MOVE_STEP_Y
    -- A `delay` AND NOT AN `end`. `end` calls `stop()`, which clears every channel
    -- the run owns -- including the scroll this is about to read -- so a program
    -- that ended would leave nothing to look at. Costing a frame instead is the
    -- cheapest way to keep the player mid-run.
    player.code = { { 17, 1, 40 }, { 0, 5 } }
    player.pc = 1
    player.playing = true
    player:update()
    ok(before == 0 and player.bgAnim ~= nil and player.bgAnim.stepY == 40,
       "setbgswitchvar writes the running scroll",
       player.bgAnim and player.bgAnim.stepY or "no scroll", 40)
  end
end

-- AND THE GAP REPORT NO LONGER NAMES THEM. This is the assertion that would catch
-- a switch quietly falling back to `note()`: the corpus is walked and the whole
-- background family has to be absent from what the player says it skipped.
do
  local named = {}
  if player then
    for id = 0, arc.count - 1 do
      if player:start(id, true) then
        local f = 0
        while player:update() and f < 400 do f = f + 1 end
        for _, row in ipairs(player:missing()) do
          for _, name in ipairs({ "switchbg", "restorebg", "setbg",
                                  "waitforbgswitch", "waitforpartialbgswitch",
                                  "setbgswitchvar", "switchbgex",
                                  "callfunc:shakebg" }) do
            if row.what == name or row.what == "wait:" .. name then
              named[name] = true
            end
          end
        end
      end
    end
  end
  local leaked = {}
  for name in pairs(named) do leaked[#leaked + 1] = name end
  table.sort(leaked)
  ok(#leaked == 0, "no background command is in the gap report any more",
     #leaked == 0 and "none" or table.concat(leaked, ", "), "none")
end

-- THE CORPUS TOTAL, which is the number that says the layer is not a one-move demo.
-- All 54 programs that name the family carry a `switchbg`; 52 of them put a picture on
-- the screen when the PLAYER attacks, the other two having theirs behind a branch this
-- side of the battle does not take -- the same shape as `fadebg`'s 106 of 108, and
-- stated as the measurement rather than rounded up to 54.
do
  local showed, frames = 0, 0
  if player then
    for id = 0, arc.count - 1 do
      if player:start(id, true) then
        local f, up = 0, 0
        while player:update() and f < 400 do
          f = f + 1
          local st = player:bgLayerState()
          if st and st.id then up = up + 1 end
        end
        if up > 0 then showed = showed + 1; frames = frames + up end
      end
    end
  end
  ok(showed == 52, "this many programs put a switched background on the screen",
     showed, 52)
  ok(frames > 3000, "...over this many frames of the corpus",
     frames .. " layer-frames", "more than 3000")
end

-- ---------------------------------------------------------------------------
-- The draw side, read as source
-- ---------------------------------------------------------------------------

-- A layer the player computes and the screen never draws is the exact failure this
-- port has already had twice. `Gen4Battle.lua` is read here for four things: that
-- the draw exists, that it is called in the right place in the order, that it
-- honours the wrap, and that `effectFade` no longer tints the particles -- which it
-- did, wrongly, until this pass.
do
  local gbPath = (root ~= "" and root or "./") .. "../src/battle/Gen4Battle.lua"
  local f = io.open(gbPath, "rb")
  local gb = f and f:read("*a")
  if f then f:close() end
  ok(gb ~= nil, "Gen4Battle.lua is readable from here", gbPath, "readable")
  if gb then
    ok(gb:find("function Gen4Battle.drawEffectBackground", 1, true) ~= nil,
       "the screen has a draw for the effect layer", "found", "found")
    -- THE ORDER, and it is the hardware's: field, then the palette fade that blacks
    -- it out, then BG3, then the OBJs.
    -- INSIDE `Gen4Battle.draw` AND NOWHERE ELSE. All three names appear earlier in
    -- the file, in their own definitions and in comments, so a search over the whole
    -- source finds the wrong occurrences and reports an order that is not the draw
    -- order. Measured: doing it that way put `drawBattlers` FIRST.
    local body = gb:match("function Gen4Battle%.draw%(battle%)(.*)$") or ""
    local fade = body:find("Gen4Battle.drawBackgroundFade(battle)", 1, true)
    local eff = body:find("Gen4Battle.drawEffectBackground(battle)", 1, true)
    local mons = body:find("Gen4Battle.drawBattlers(battle)", 1, true)
    ok(fade and eff and mons and fade < eff and eff < mons,
       "...drawn after the background fade and before the battlers",
       (fade and eff and mons) and ("%d < %d < %d"):format(fade, eff, mons)
         or "one of the three is missing",
       "fade < effect < battlers")
    ok(gb:find("function Gen4Battle.backdropOffset", 1, true) ~= nil,
       "...and the backdrop can be shaken, for the 22 calls with no switch up",
       "found", "found")
    -- NEWLINE-AGNOSTIC ON PURPOSE. The engine's .lua files are CRLF on disk and this
    -- tool's own source is read as bytes, so a needle containing a bare \n matches
    -- nothing -- which is a check that passes or fails on line endings rather than on
    -- behaviour. Asserted as a pattern over the function's body instead: it must
    -- return its three arguments unchanged and do nothing else.
    local body = gb:match("local function effectFade%(player, r, g, b%)(.-)\nend")
    local identity = body ~= nil
      and body:gsub("[%s\r]", "") == "returnr,g,b"
    ok(identity == true,
       "...and effectFade no longer tints the particles",
       body and (body:gsub("[%s\r]+", " ")) or "not found", " return r, g, b")
    ok(gb:find("gfx.effects", 1, true) ~= nil,
       "...and the pictures are looked up in the graphics index", "found", "found")
  end
end

-- ...and that the extractor still writes them under the name the screen looks up.
-- Same argument as the particle textures: this is the one thing here duplicated
-- from another file rather than read from it.
do
  local f = io.open(root .. "../src/import/RomExtractorGen4.lua", "rb")
  local src = f and f:read("*a")
  if f then f:close() end
  ok(src ~= nil and src:find('"battle/effect/" .. spec.art', 1, true) ~= nil,
     "the graphics stage writes the effect backgrounds",
     (src and src:find('"battle/effect/" .. spec.art', 1, true)) and "found"
       or "not found", "found")
  ok(src ~= nil and src:find("index.effects[key] = entry", 1, true) ~= nil,
     "...and indexes them under the key the screen builds",
     (src and src:find("index.effects[key] = entry", 1, true)) and "found"
       or "not found", "found")
  ok(src ~= nil and src:find("Gen4Graphics.coversScreen(image)", 1, true) ~= nil,
     "...recording which of them cover the screen, for the type-2 fade",
     (src and src:find("Gen4Graphics.coversScreen(image)", 1, true)) and "found"
       or "not found", "found")
  ok(src ~= nil and src:find("paletteSlot = spec.slot", 1, true) ~= nil,
     "...and composing them with the palette in slot 9",
     (src and src:find("paletteSlot = spec.slot", 1, true)) and "found"
       or "not found", "found")
end

end

-- ---------------------------------------------------------------------------
-- 17: THE TWO REVOLUTIONS, THE FALL FROM THE TOP, AND THE GREY BACKGROUND
--
-- Four functions off the queue, chosen because each is small and because the
-- machinery all four need was already built: the revolution primitive, the emitter
-- path and the graphics stage's compose.
--
-- WHAT IS ACTUALLY AT RISK IN EACH ONE:
--   RevolveBattler (60)          the CENTRE, which is not the battler
--   RevolveEmitter (72)          the Y SIGN, and the 72 calls that do not rotate
--   MoveEmitterViewportTop (73)  WHERE the top of the viewport is
--   SetBgGrayscale (74)          the five-bit arithmetic, and the SCOPE
--
-- SIXTEEN FAULTS PLANTED, FIFTEEN FAIL, and the four that needed the assertion
-- rewritten are the interesting part:
--   the oval's radii not halved          -> the first frame's four-pixel drop
--   revs scaling the step, not the count -> three turns at the same speed
--   the orbit centred on the battler     -> the same first frame
--   the orbit never coming home          -> REWRITTEN: read after the run, the tail
--                                          has already cleared every channel, so
--                                          "not displaced at the end" was true
--                                          either way. Asserted on the frame after
--                                          the task's last instead.
--   the ring's Y sign unflipped          -> the two sides fan opposite ways
--   the ring round the wrong battler     -> REWRITTEN: the bounds were seeded at
--                                          zero, so `hi == 0` meant "nothing
--                                          positive" and a ring shifted 64 pixels
--                                          up passed. Seeded from the first sample.
--   no pre-step before the first place   -> REWRITTEN: every assertion collected the
--                                          union of all frames and skipped the
--                                          undisplaced ones, so one frame at the
--                                          origin was invisible. A synthetic call
--                                          checks the creating frame.
--   the viewport type read backwards     -> the fall becomes a rise
--   the viewport top at mid-screen       -> the arithmetic, not the literal
--   grey weighted on 8-bit channels      -> 75 148 28 against 74 148 25
--   grey with equal weights              -> 82 against 74
--   grey over all 256 entries            -> the scope constant
--   SetBgGrayscale never turning off     -> REWRITTEN: "does program 50 grey" is
--                                          true either way and "is it grey after
--                                          the run" is false either way, because
--                                          the accessor is guarded on `alive()`.
--                                          Program 377's two-frame window instead.
--   the screen not asking for the grey   -> REWRITTEN: `if false` left both the
--                                          function and the "_gray" key in the file
--                                          and passed a search for either. Matched
--                                          inside `backdrop` now -- the same shape
--                                          as the gen4Layout() guard a comment
--                                          satisfied.
--   the stage composing no grey twin     -> REWRITTEN twice: the word also appears
--                                          in the saved entry's metadata, and then
--                                          the tighter needle had a bare \n in it
--                                          and matched nothing in a CRLF file.
--
-- AND THE ONE THAT IS NOT A FAULT: removing the grey's per-run reset, or the clear
-- in `clearTransforms`, or BOTH, fails nothing -- because every one of the five
-- programs runs its own paired off-call on its final frame. Two redundant guards,
-- kept for consistency with the tints beside them, and recorded here rather than
-- defended with an assertion that cannot fail.
-- ---------------------------------------------------------------------------
io.write("\nthe revolutions and the grey background\n")

-- THE OVAL'S SHAPE, forced from the two constants rather than measured off a run.
-- 32 and -8 halved is 16 and -4, and the sine table's quantisation is what makes
-- the extremes 15 and 16 rather than a clean 16 both ways.
do
  local c = Math4.ovalRevolution(1, 10, true)
  ok(c.rx == 65536 and c.ry == -16384,
     "RevolveBattler halves the oval's radii, to 16 by 4 pixels",
     ("%d and %d"):format(c.rx, c.ry), "65536 and -16384")
  ok(c.steps == 10, "...one revolution is stepsPerRev frames", c.steps, 10)
  local three = Math4.ovalRevolution(3, 10, true)
  ok(three.steps == 30 and three.stepX == c.stepX,
     "...and three revolutions are three times as many frames at the SAME speed",
     ("%d steps, step %d vs %d"):format(three.steps, three.stepX, c.stepX),
     "30 steps, the same step")
  local xs, ys, n = {}, {}, 0
  while Math4.revolutionUpdate(c) do
    n = n + 1
    xs[n], ys[n] = c.x, c.y
  end
  ok(n == 10, "...and it runs for exactly its frame count", n, 10)
  local lo, hi = 0, 0
  for i = 1, n do
    if xs[i] < lo then lo = xs[i] end
    if xs[i] > hi then hi = xs[i] end
  end
  ok(lo == -16 and hi == 15,
     "...reaching 15 one way and -16 the other, which is the table's own rounding",
     ("%d to %d"):format(lo, hi), "-16 to 15")
  local ylo, yhi = 0, 0
  for i = 1, n do
    if ys[i] < ylo then ylo = ys[i] end
    if ys[i] > yhi then yhi = ys[i] end
  end
  ok(ylo == -4 and yhi == 4, "...and four pixels each way vertically",
     ("%d to %d"):format(ylo, yhi), "-4 to 4")
end

-- THE CENTRE IS EIGHT PIXELS BELOW HOME, and that is the one thing about this
-- function a port gets wrong. Measured on a real program: the battler's FIRST
-- displaced frame must be BELOW its mark, and the LAST must be exactly on it.
do
  local frames, firstDy, lastDy, maxDx = 0, nil, nil, 0
  local anyAbove = 0
  if player and player:start(35, true) then
    while player:update() and frames < 400 do
      frames = frames + 1
      local dx, dy = player:monOffset(true)
      if dx ~= 0 or dy ~= 0 then
        firstDy = firstDy or dy
        lastDy = dy
        if math.abs(dx) > maxDx then maxDx = math.abs(dx) end
        if dy < 0 then anyAbove = anyAbove + 1 end
      end
    end
  end
  ok(firstDy == 4,
     "the orbit's first frame puts the battler FOUR pixels low, not on its mark",
     firstDy, 4)
  ok(anyAbove == 0,
     "...and it never rises above home, because the centre is eight pixels under it",
     anyAbove .. " frames above", 0)
  ok(maxDx == 16 or maxDx == 15,
     "...while sideways it reaches the full sixteen", maxDx, "15 or 16")
  -- AND IT COMES HOME ON THE FRAME AFTER ITS LAST, WHILE THE PROGRAM IS STILL
  -- RUNNING. A port that simply stopped updating would leave the Pokemon parked on
  -- the edge of its own ellipse for the remaining 34 frames of program 35.
  --
  -- READING IT AFTER THE RUN CANNOT SEE THIS, and the first draft did: by then the
  -- tail has emptied and `clearTransforms` has zeroed every channel, so "not
  -- displaced at the end" is true whatever the orbit did. Planting "never write the
  -- offset back" passed it. The assertion has to land on the frame the task
  -- finishes, which is the frame after the last displaced one.
  local lastDisplaced, afterwards, framesAfter = nil, nil, 0
  if player and player:start(35, true) then
    local f, rows = 0, {}
    while player:update() and f < 400 do
      f = f + 1
      local dx, dy = player:monOffset(true)
      rows[f] = { dx, dy }
      if dx ~= 0 or dy ~= 0 then lastDisplaced = f end
    end
    if lastDisplaced and rows[lastDisplaced + 1] then
      afterwards = rows[lastDisplaced + 1]
      framesAfter = f - lastDisplaced
    end
  end
  ok(afterwards ~= nil and afterwards[1] == 0 and afterwards[2] == 0,
     "...and the frame after its last puts the battler back exactly",
     afterwards and ("%d,%d"):format(afterwards[1], afterwards[2]) or "no frame",
     "0,0")
  ok(framesAfter > 20,
     "...with the program still running for a long time after it",
     framesAfter .. " frames after", "over 20")
end

-- ---------------------------------------------------------------------------
-- RevolveEmitter
-- ---------------------------------------------------------------------------

-- SEVENTY-TWO OF THE 105 CALLS PASS THE SAME START AND END ANGLE, so their step
-- size is zero and the emitter is PLACED rather than spun. Counted off the corpus,
-- because it decides whether "no rotation" is a bug to guard against or the
-- commoner of the two uses.
do
  local still, turning = 0, 0
  for id = 0, arc.count - 1 do
    for _, ins in ipairs((programs[id] or {}).code or {}) do
      if ins[1] == 45 and ins[2] == 72 and (ins[3] or 0) >= 5 then
        -- callfunc row: {op, funcId, count, var0, var1, ...}, so var N is ins[4+N]
        local sx, ex = signedWord(ins[5]), signedWord(ins[6])
        if sx == ex then still = still + 1 else turning = turning + 1 end
      end
    end
  end
  ok(still == 90 and turning == 15,
     "90 of RevolveEmitter's 105 calls place an emitter rather than spin it",
     ("%d still, %d turning"):format(still, turning), "90 and 15")
end

-- THE RING IS A FAN, AND WHICH WAY IT FANS IS THE Y SIGN. Program 307 places twelve
-- emitters round the ATTACKER at fixed angles with radii 48/64/92 by 24.
--
-- IT ONLY EVER REACHES THE UPPER HALF OF THE CIRCLE ON ONE SIDE OF THE BATTLE. The
-- angles the player's attack reaches are -90, -45, 0, 45 and 90 -- cos >= 0 -- and
-- the enemy's branch takes the other half. So the measurement is TWO-SIDED: with
-- the player attacking every vertical offset must be at or ABOVE the attacker, and
-- with the enemy attacking at or BELOW. A flipped Y sign swaps the two and passes
-- neither.
--
-- WHY A SINGLE-SIDED ASSERTION WOULD HAVE BEEN WRONG HERE: the first draft asked for
-- offsets on both sides in one run, reasoning from the angles in the SOURCE -- 135,
-- 180, 225 and 270 are all there. They are on the branch this side of the battle
-- does not take, so the assertion failed against correct code. Read the branch, not
-- the listing.
do
  -- !! THE BOUNDS START FROM THE FIRST SAMPLE, NOT FROM ZERO. Seeding them at 0
  -- makes `hi == 0` mean "nothing positive" rather than "reaches the origin", and a
  -- plant that placed the whole ring round the WRONG BATTLER -- shifting every
  -- offset 64 pixels up -- passed because of it. A bound that one side of the data
  -- can never move is not a bound.
  local function extremes(attackerIsPlayer)
    local lo, hi, xs, seen = nil, nil, {}, 0
    if not (player and player:start(307, attackerIsPlayer)) then return nil end
    local f = 0
    while player:update() and f < 400 do
      f = f + 1
      for slot = 0, 15 do
        local e = player.emitterAt and player.emitterAt[slot]
        local sys = e and e.system
        if sys and ((sys.emitterX or 0) ~= 0 or (sys.emitterY or 0) ~= 0) then
          seen = seen + 1
          local y = sys.emitterY or 0
          if lo == nil or y < lo then lo = y end
          if hi == nil or y > hi then hi = y end
          xs[("%d"):format(sys.emitterX or 0)] = true
        end
      end
    end
    lo, hi = lo or 0, hi or 0
    local distinct = 0
    for _ in pairs(xs) do distinct = distinct + 1 end
    return { lo = lo, hi = hi, seen = seen, distinct = distinct }
  end
  local mine = extremes(true)
  local theirs = extremes(false)
  ok(mine ~= nil and mine.seen > 0, "program 307 places emitters off their own origin",
     mine and (mine.seen .. " emitter-frames displaced") or "no run", "more than 0")
  ok(mine ~= nil and mine.lo < 0 and mine.hi == 0,
     "the player's attack fans them ABOVE the attacker and never below",
     mine and ("%d to %d"):format(mine.lo, mine.hi) or "-", "negative to 0")
  ok(theirs ~= nil and theirs.hi > 0 and theirs.lo == 0,
     "...and the enemy's fans them BELOW, which a flipped Y sign could not do",
     theirs and ("%d to %d"):format(theirs.lo, theirs.hi) or "-", "0 to positive")
  ok(mine ~= nil and mine.distinct >= 8,
     "...at this many distinct horizontal offsets, from the three radii",
     mine and mine.distinct or "-", "at least 8")
end

-- THE FIRST PLACEMENT IS ALREADY ON THE RING, and that is what the single
-- `RevolutionContext_Update` in the script function buys. Without it the context's
-- x and y are still zero, so the emitter spends its first frame at the battler's own
-- centre and steps onto the ring a frame late.
--
-- IT HAS TO BE ASSERTED ON THE CREATING FRAME. A plant that dropped the pre-step
-- passed every assertion above, because they collect the union of every frame and
-- skip the ones where nothing is displaced -- so one extra frame at the origin is
-- invisible to all of them. Synthetic, and only in that the emitter is handed over
-- directly; the operands are program 307's own.
do
  local placed = nil
  if player and player:start(307, true) then
    local f = 0
    while player:update() and f < 80 and not (player.emitterAt or {})[3] do
      f = f + 1
    end
    local e = (player.emitterAt or {})[3]
    if e then
      player.tasks = {}
      e.system.emitterX, e.system.emitterY = 0, 0
      -- angle 0 on both axes: cos is +1, so the ring's point is the full Y radius
      -- ABOVE the battler and level with it horizontally.
      if player:startEmitterRevolution({ emitterId = 3, startX = 0, endX = 0,
                                         startY = 0, endY = 0, radiusX = 48,
                                         radiusY = 24, frames = 7, mode = 0 }) then
        placed = { e.system.emitterX or 0, e.system.emitterY or 0 }
      end
    end
  end
  ok(placed ~= nil and placed[2] == -24,
     "the ring's first placement is already 24 pixels up, not at the battler",
     placed and ("%d,%d"):format(placed[1], placed[2]) or "no placement", "0,-24")
end

-- ...AND THE ONE THAT ACTUALLY TURNS. Program 463's calls are 0 to 360 degrees over
-- 40 frames with radii 64 by 48, mode 1 (the defender) -- so the offset has to
-- sweep a full circle rather than sit still.
do
  local xs, ys = {}, {}
  if player and player:start(463, true) then
    local f = 0
    while player:update() and f < 400 do
      f = f + 1
      local e = player.emitterAt and player.emitterAt[0]
      local sys = e and e.system
      if sys then
        xs[#xs + 1] = sys.emitterX or 0
        ys[#ys + 1] = sys.emitterY or 0
      end
    end
  end
  local lox, hix, loy, hiy = 1e9, -1e9, 1e9, -1e9
  for i = 1, #xs do
    if xs[i] < lox then lox = xs[i] end
    if xs[i] > hix then hix = xs[i] end
    if ys[i] < loy then loy = ys[i] end
    if ys[i] > hiy then hiy = ys[i] end
  end
  ok(#xs > 0 and (hix - lox) > 100,
     "program 463's emitter sweeps the full 128-pixel width of its circle",
     (#xs > 0) and ("%d to %d"):format(lox, hix) or "no frames", "over 100 wide")
  ok(#ys > 0 and (hiy - loy) > 80,
     "...and the full 96 of its height",
     (#ys > 0) and ("%d to %d"):format(loy, hiy) or "no frames", "over 80 tall")
end

-- ---------------------------------------------------------------------------
-- MoveEmitterViewportTop
-- ---------------------------------------------------------------------------

-- THE TOP OF THE VIEWPORT IS ROW ZERO, and the cartridge's own constant says so:
-- BATTLE_PARTICLE_VIEWPORT_TOP / BATTLE_PARTICLE_PIXEL_FACTOR is 16512 / 172 = 96,
-- which is half of 192. In a screen-centred frame, half the height above centre is
-- the top row. Asserted as that arithmetic rather than as the literal 0, so the
-- derivation is what breaks if someone changes the constant.
ok(16512 // 172 == 96 and Play.Player.VIEWPORT_TOP_Y == 96 - 96,
   "the viewport top is half the screen above centre, which is row zero",
   ("16512/172 = %d, and the port uses %d"):format(16512 // 172,
                                                   Play.Player.VIEWPORT_TOP_Y),
   "96, and 0")

-- SYNTHETIC, AND LABELLED AS ONE. The cartridge's single call to this function is in
-- program 19 at instruction 68, which is past a `jumpifeffectchanceodd` -- so the
-- player's attack never reaches it and no run can exercise it. The operands below
-- are that call's own (emitter 0, the defender, type 0, ten frames, four of delay);
-- what is synthetic is only that the emitter is handed over directly.
--
-- THE ASSERTION IS THE DIRECTION. Type 0 is EMITTER_ANIMATION_FROM_TOP, which puts
-- the TOP of the viewport at the START -- so the emitter falls onto the battler. A
-- port that read the type the other way round would have it fly off the screen, and
-- every other number about the path would still be right.
do
  local first, last, steps = nil, nil, 0
  if player and player:start(19, true) then
    -- Run far enough for the program to have created its emitter in slot 0.
    local f = 0
    while player:update() and f < 60 and not (player.emitterAt or {})[0] do
      f = f + 1
    end
    local e = (player.emitterAt or {})[0]
    if e then
      player.tasks = {}
      e.system.emitterX, e.system.emitterY = 0, 0
      local started = player:startEmitterViewportPath({
        emitterId = 0, mode = 1, kind = 0, frames = 10, startDelay = 4, params = 0,
      })
      if started then
        for _ = 1, 30 do
          player:stepTasks()
          steps = steps + 1
          local y = e.system.emitterY or 0
          if y ~= 0 then first = first or y; last = y end
        end
      end
    end
  end
  ok(first ~= nil, "the viewport path moves its emitter",
     first and ("from %d"):format(first) or "never moved", "a start")
  ok(first ~= nil and last ~= nil and last > first,
     "...downwards, because type 0 puts the viewport top at the START",
     (first and last) and ("%d then %d"):format(first, last) or "-", "downwards")
  -- AND IT ARRIVES WHERE THE BATTLER IS, WHICH IS NOT ZERO. The offset is measured
  -- from the EMITTER'S OWN ORIGIN, and program 19's emitter is placed at the
  -- ATTACKER (callback 3) while this path is aimed at the DEFENDER -- so the last
  -- value is the difference between the two, not the origin itself. Derived from the
  -- battler table rather than written as -64, so the expectation moves if the table
  -- does; one pixel of slack for the lerp's truncation, the same pixel the
  -- travelling-emitter section already measures.
  local want = nil
  if player then
    local pos = player:battlerPositions()
    local _, originY = player:originPixels("attacker")
    if pos and originY then want = pos.defender.y - originY end
  end
  ok(want ~= nil and last ~= nil and math.abs(last - want) <= 1,
     "...arriving at the battler it was aimed at, one pixel short at most",
     ("%s against %s"):format(tostring(last), tostring(want)), "within a pixel")
end

-- ---------------------------------------------------------------------------
-- SetBgGrayscale
-- ---------------------------------------------------------------------------

-- THE ARITHMETIC IS FIVE-BIT, and this is the case that separates the two
-- spellings: weighting the EXPANDED eight-bit channels and re-rounding gives 75 for
-- pure red where the cartridge gives 74. One level, on every colour, invisible to
-- anything but a comparison.
do
  local grey = Gfx4 and Gfx4.grayscalePalette({ { 255, 0, 0 }, { 0, 255, 0 },
                                                { 0, 0, 255 }, { 255, 255, 255 },
                                                { 0, 0, 0 } })
  local got = grey and ("%d %d %d %d %d"):format(grey[1][1], grey[2][1], grey[3][1],
                                                 grey[4][1], grey[5][1])
  ok(got == "74 148 25 255 0",
     "the grey of red, green, blue, white and black",
     got or "no palette", "74 148 25 255 0")
  -- WHITE STAYS WHITE, which is what says the weights are the cartridge's: 76 + 151
  -- + 29 is 256 exactly, so a channel triple at the top comes back at the top.
  ok(grey ~= nil and grey[4][1] == 255 and grey[4][2] == 255 and grey[4][3] == 255,
     "...and the weights sum to 256, so nothing clips or dims",
     grey and table.concat(grey[4], ",") or "-", "255,255,255")
end

-- THE SCOPE IS 128 ENTRIES, and that is not decoration: the Pokemon-sprite palette
-- at slot 8 and the effect background's at slot 9 are OUTSIDE it, which is why a
-- switched background stays in colour while the field greys.
do
  local big = {}
  for i = 1, 160 do big[i] = { 255, 0, 0 } end
  local grey = Gfx4 and Gfx4.grayscalePalette(big)
  ok(Gfx4 ~= nil and Gfx4.GRAYSCALE_SCOPE == 128,
     "the grey covers sub-palettes 0 to 7, which is 128 entries",
     Gfx4 and Gfx4.GRAYSCALE_SCOPE or "-", 128)
  ok(grey ~= nil and grey[128][1] == 74 and grey[129][1] == 255,
     "...and entry 129 -- the mon sprite's slot -- is left in colour",
     grey and ("%d then %d"):format(grey[128][1], grey[129][1]) or "-",
     "74 then 255")
end

-- AND IT COVERS THE WHOLE BACKDROP, which had to be measured rather than assumed:
-- 128 entries would leave a backdrop in colour if any of its tiles named an index
-- above 127. The highest any of the 23 sheets uses is 111.
if bgArc and Gfx4 then
  local Bg = Bg4
  local sharedMap = Gfx4.tilemap(bgMember(Bg.BG_TILEMAP_MEMBER))
  local referenced = {}
  if sharedMap then
    for _, cell in ipairs(sharedMap.cells) do referenced[cell.tile] = true end
  end
  local highest = 0
  for background = 0, Bg.BACKGROUND_COUNT - 1 do
    local spec = Bg.background(background, 0)
    local sheet = spec and Gfx4.tiles(bgMember(spec.tiles))
    if sheet and sheet.pixels then
      local per = sheet.perTile or 64
      for tile in pairs(referenced) do
        local base = tile * per
        if base >= 0 and base + per <= #sheet.pixels then
          for k = 1, per do
            local v = string.byte(sheet.pixels, base + k)
            if v and v > highest then highest = v end
          end
        end
      end
    end
  end
  ok(highest == 111,
     "the highest palette index any backdrop uses is inside the grey's 128",
     highest, 111)
end

-- ...and the two halves of the port that have to agree about it.
do
  local f = io.open(root .. "../src/import/RomExtractorGen4.lua", "rb")
  local src = f and f:read("*a")
  if f then f:close() end
  -- THE COMPOSE CALL, NOT THE WORD. `grayscale = true` also appears in the saved
  -- entry's metadata, so a plant that turned the COMPOSITION off left the word in
  -- place and passed. Matched as the argument to the job that builds the picture.
  -- A PATTERN AND NOT A LITERAL, because `%s*` crosses a CRLF and a bare \n does
  -- not: the engine's files are CRLF on disk and the first spelling of this needle
  -- found nothing at all. The same trap the effectFade assertion already records.
  local composed = src ~= nil
    and src:match("tilemap = spec%.tilemap,%s*grayscale = true") ~= nil
  ok(composed, "the graphics stage composes a grey twin of every backdrop",
     composed and "found" or "not found", "found")
  ok(src ~= nil and src:find('"battle/background/" .. name .. "_gray"', 1, true) ~= nil,
     "...and saves it under the name the screen asks for",
     (src and src:find('"battle/background/" .. name .. "_gray"', 1, true))
       and "found" or "not found", "found")
  local g = io.open((root ~= "" and root or "./") .. "../src/battle/Gen4Battle.lua",
                    "rb")
  local gb = g and g:read("*a")
  if g then g:close() end
  -- AND THE PREDICATE IS CALLED, not merely present. A plant that replaced the
  -- condition with `if false` left both the function and the `"_gray"` key in the
  -- file and passed a search for either -- the same shape as the `gen4Layout()`
  -- guard a comment satisfied. Matched inside `backdrop`, which is the only place
  -- the answer can change anything.
  local body = gb and gb:match("function Gen4Battle%.backdrop%(battle%)(.-)\nend")
  ok(body ~= nil and body:find("if Gen4Battle.grayscale(battle) then", 1, true) ~= nil,
     "...and the backdrop asks the player before choosing a picture",
     (body and body:find("if Gen4Battle.grayscale(battle) then", 1, true))
       and "found" or "not found", "found")
  ok(body ~= nil and body:find('"_gray"', 1, true) ~= nil,
     "...and the picture it then chooses is the grey one",
     (body and body:find('"_gray"', 1, true)) and "found" or "not found", "found")
  ok(gb ~= nil and gb:find("function Gen4Battle.grayscale", 1, true) ~= nil,
     "...through one predicate rather than inline in the draw",
     (gb and gb:find("function Gen4Battle.grayscale", 1, true)) and "found"
       or "not found", "found")
end

-- THE TOGGLE IS PAIRED, AND ONE PROGRAM TURNS IT OFF WHILE IT IS STILL RUNNING.
-- Nine calls on and nine off in the cartridge; of the five programs that use it,
-- four still have the grey up on their last frame -- their "off" is on a branch this
-- side of the battle does not take -- and program 377 is the one that does both.
-- Its window is TWO FRAMES out of eighty-five, which is the assertion that makes the
-- operand load-bearing: a port that ignored it and greyed for good would report 54.
--
-- MEASURING IT ON A PROGRAM THAT ENDS GREY CANNOT SEE THAT, and the first draft did:
-- it asked whether program 50 greys at all (yes, either way) and whether the grey is
-- gone after the run (yes either way, because the accessor is guarded on `alive()`).
-- Both plants passed.
do
  local window, total = 0, 0
  if player and player:start(377, true) then
    while player:update() and total < 400 do
      total = total + 1
      if player:bgGrayscale() then window = window + 1 end
    end
  end
  ok(window == 2, "program 377 greys the background for exactly two frames",
     window .. " of " .. total, 2)
  ok(total > 60, "...out of a program more than thirty times that long", total,
     "over 60")
  -- ...AND IT IS THE SCRIPT'S OWN PAIRED CALL THAT TURNS IT OFF, not the port's
  -- housekeeping. Every one of the five programs ends with its grey already cleared:
  -- the last sampled frame of four of them still reads grey, but the final `update`
  -- -- the one that returns false -- runs the off-call. So the per-run reset and the
  -- clear in `clearTransforms` are BOTH redundant guards, and this was measured
  -- rather than assumed: removing either, or BOTH, fails nothing in this suite.
  -- Recorded as a guard removal rather than dressed as a test, and the guards are
  -- kept because the tints beside them work the same way.
  --
  -- WHAT IS FALSIFIABLE is the count: exactly one of the five programs turns the
  -- grey off on a frame this side of the battle can still see. A port that ignored
  -- the operand reports five that never turn it off.
  local offMidRun, greyPrograms = 0, 0
  for _, id in ipairs({ 50, 377, 399, 425, 467 }) do
    if player and player:start(id, true) then
      local f, sawGrey, lastGrey = 0, false, false
      while player:update() and f < 400 do
        f = f + 1
        lastGrey = player:bgGrayscale()
        if lastGrey then sawGrey = true end
      end
      if sawGrey then
        greyPrograms = greyPrograms + 1
        if not lastGrey then offMidRun = offMidRun + 1 end
      end
    end
  end
  ok(greyPrograms == 5, "all five of the programs that grey the field do grey it",
     greyPrograms, 5)
  ok(offMidRun == 1,
     "...and exactly one of them turns it off with frames left to see it",
     offMidRun, 1)
end

-- ---------------------------------------------------------------------------
-- 18: THE SOUND CHANNEL
--
-- 1,220 sound commands over 499 of the 501 programs, and until this pass THE SEAM
-- WAS NIL ON EVERY BOOT: the player called `self.onSound(id)` and nothing anywhere
-- assigned `onSound`, so every Sinnoh move was silent. The gap report could not see
-- it, because a command that calls a nil callback is not a command that was skipped.
-- That is the third time this port has had the same bug -- a cache table nobody
-- opened, an animator nobody constructed, a picture nobody drew into -- so the FIRST
-- thing this section asserts is the wiring, read out of BattleState's source, and
-- only then the arithmetic.
--
-- WHAT IS AUDIBLE AND WHAT IS NOT. Platinum's effects are SDAT SEQUENCES and playing
-- one needs a synthesiser this engine does not have; the CRIES are single PCM8
-- samples and all 493 are already in the cache. So the cries play now and the effects
-- are events with the right id, the right pan and the right FRAME -- which is the
-- half a sequence player cannot work out for itself, and the half this can measure.
--
-- SIXTEEN FAULTS PLANTED, ALL SIXTEEN FAIL, and three assertions had to be rewritten
-- first:
--   the seam never assigned              -> the source search
--   the cry never resolving a species    -> REWRITTEN: `Sound.playCry` appears
--                                          elsewhere in BattleState (the faint cry),
--                                          so the name alone was satisfied by
--                                          unrelated code. The ASSIGNMENT is asserted.
--   the queue forgetting the side        -> the source search
--   the pan not corrected                -> Scratch from the other side
--   the step keeping the operand's sign  -> the three-way correction
--   the loop waiting before its first    -> the first play's frame
--   the loop's period off by one         -> the corpus total, and the gaps
--   the delay decrementing before testing-> the corpus total, and frame 8
--   the moving sound at the wrong pan    -> program 6's start pan
--   the moving pan stepping at once      -> the corpus total, and the first gap
--   a sound task counted as an anim task -> SIX failures, including MetalClaw's
--                                          lifetime: the whole corpus gets longer
--   the cry dropping its modulation      -> REWRITTEN: the first version counted the
--                                          operands in the PROGRAM, which says nothing
--                                          about what the player emitted. Taken off
--                                          the events.
--   the cry wait never blocking          -> the held frames
--   the cry wait blocking with no seam   -> thirteen failures; five programs hang
--   the measuring pass audible           -> ten sounds heard while measuring
--   stopsoundeffect emitted as a play    -> the kind breakdown
--
-- AND ONE NUMBER IN AN EARLIER DRAFT OF THIS SECTION WAS MEASURED OFF THE WRONG
-- OPCODE: `playpokemoncry` is 65 and the draft used 64, which is `jumpifbattlerside`.
-- It reported "37 cries, 36 of them normal" from a command that has nothing to do with
-- sound, and the numbers were plausible enough to write into a comment. Every opcode
-- here is looked up by NAME out of `Anim.OPCODES` now.
-- ---------------------------------------------------------------------------
io.write("\nthe sound channel\n")

-- THE SEAM, FIRST. Read as source, with the comments stripped, because a comment that
-- mentions `onSound` is exactly what this check must not accept -- the `gen4Layout()`
-- guard already taught that lesson once.
do
  local f = io.open((root ~= "" and root or "./") .. "../src/battle/BattleState.lua",
                    "rb")
  local bs = f and f:read("*a")
  if f then f:close() end
  local code = bs and bs:gsub("%-%-[^\n]*", "")
  ok(code ~= nil, "BattleState.lua is readable from here", "read", "read")
  if code then
    ok(code:find("self.gen4Anim.onSound = function", 1, true) ~= nil,
       "the battle assigns the Gen 4 sound seam",
       code:find("self.gen4Anim.onSound = function", 1, true) and "found"
         or "NOT FOUND -- every Sinnoh move is silent", "found")
    ok(code:find("self.gen4Anim.cryPlaying = function", 1, true) ~= nil,
       "...and answers whether a cry is still playing",
       code:find("self.gen4Anim.cryPlaying = function", 1, true) and "found"
         or "not found", "found")
    -- THE CRY HAS TO REACH A SPECIES. An `onSound` that switched on `kind` and never
    -- resolved the attacker would pass the assertion above and still make no noise.
    -- THE EXACT LINE, not the words. `Sound.playCry` appears elsewhere in this file --
    -- the faint cry uses it -- so a search for the name alone is satisfied by
    -- unrelated code, and a plant that replaced this call with `nil` passed it. The
    -- assignment is what makes the noise, so the assignment is what is asserted.
    local cryCall = code:match("gen4CrySource%s*=%s*Sound%.playCry")
    ok(cryCall ~= nil and code:find("gen4AnimAttackerIsPlayer", 1, true) ~= nil,
       "...and a cry event resolves the attacking side to a Pokemon",
       (cryCall and code:find("gen4AnimAttackerIsPlayer", 1, true))
         and "both found" or "one is missing", "both")
    ok(code:find("self.gen4AnimAttackerIsPlayer = item.attackerIsPlayer", 1, true) ~= nil,
       "...which the queue records when it starts the animation",
       code:find("self.gen4AnimAttackerIsPlayer = item.attackerIsPlayer", 1, true)
         and "found" or "not found", "found")
  end
end

-- run(move, attackerIsPlayer) -> the run's sound events
local function runSound(move, attackerIsPlayer)
  if not (player and player:start(move, attackerIsPlayer)) then return nil end
  local f = 0
  while player:update() and f < 600 do f = f + 1 end
  return player.soundEvents, f
end

-- THE CORPUS. 496 of the 501 programs make a sound, which is the number that says
-- this is a layer and not a demo.
do
  local total, programs, kinds = 0, 0, {}
  if player then
    for id = 0, arc.count - 1 do
      local events = runSound(id, true)
      if events then
        if #events > 0 then programs = programs + 1 end
        total = total + #events
        for _, e in ipairs(events) do kinds[e.kind] = (kinds[e.kind] or 0) + 1 end
      end
    end
  end
  ok(programs == 496, "this many programs ask for a sound", programs, 496)
  ok(total == 3865, "...over this many sound events in the corpus", total, 3865)
  -- THE BREAKDOWN, because a total says nothing about which command produced it: a
  -- port that turned every command into a bare play would report the same 3,865.
  -- MORE EVENTS THAN COMMANDS (3,865 against 1,220) is the point of the three sound
  -- TASKS: one `playloopedsoundeffect` is up to 24 plays and one moving sound is a
  -- pan every third frame for as long as the move lasts.
  ok(kinds.play == 1821 and kinds.pan == 2012 and kinds.cry == 10
     and kinds.stop == 12 and kinds.stopcries == 10,
     "...split between plays, pans, cries, stops and cry stops",
     ("%s plays, %s pans, %s cries, %s stops, %s stopcries"):format(
       tostring(kinds.play), tostring(kinds.pan), tostring(kinds.cry),
       tostring(kinds.stop), tostring(kinds.stopcries)),
     "1821, 2012, 10, 12, 10")
end

-- ---------------------------------------------------------------------------
-- The pan, both corrections
-- ---------------------------------------------------------------------------

-- A PAN IS WRITTEN FOR THE PLAYER ATTACKING AND MIRRORED WHEN THE ENEMY IS. The
-- corpus uses exactly three pans -- -117, 0 and +117 -- so this is measurable on any
-- program that passes one: the same move from the other side must come out negated.
do
  local mine = runSound(10, true)
  local theirs = runSound(10, false)
  local a = mine and mine[1] and mine[1].pan
  local b = theirs and theirs[1] and theirs[1].pan
  ok(a == 117 and b == -117,
     "Scratch's sound comes from the right when the player attacks and the left when the enemy does",
     ("%s then %s"):format(tostring(a), tostring(b)), "117 then -117")
  -- ...AND CENTRE STAYS CENTRE, which is what says this is a negation and not a swap
  -- of two constants. 65 of the 649 panned calls pass 0.
  local centre = nil
  if player then
    for id = 0, arc.count - 1 do
      local events = runSound(id, false)
      for _, e in ipairs(events or {}) do
        if e.pan == 0 then centre = 0 end
      end
      if centre then break end
    end
  end
  ok(centre == 0, "...while a centred sound is still centred from the other side",
     tostring(centre), 0)
end

-- THE STEP'S SIGN COMES FROM THE ENDPOINTS, NOT THE OPERAND. 10 of the 113 moving
-- sounds sweep right to left and all ten pass a POSITIVE step; used as written they
-- would walk away from their own end point and the task's end test would never fire.
do
  local rightToLeft, positiveStep = 0, 0
  for id = 0, arc.count - 1 do
    for _, ins in ipairs((programs[id] or {}).code or {}) do
      if ins[1] == 24 then
        local startPan, endPan = signedWord(ins[3]), signedWord(ins[4])
        local step = signedWord(ins[5])
        if startPan > endPan then
          rightToLeft = rightToLeft + 1
          if step > 0 then positiveStep = positiveStep + 1 end
        end
      end
    end
  end
  ok(rightToLeft == 10 and positiveStep == 10,
     "ten moving sounds sweep right to left, and all ten pass a positive step",
     ("%d right-to-left, %d of them positive"):format(rightToLeft, positiveStep),
     "10 and 10")
  if player and player:start(1, true) then
    ok(player:correctPanStep(117, -117, 4) == -4
       and player:correctPanStep(-117, 117, 4) == 4
       and player:correctPanStep(0, 0, 4) == 0,
       "...so the step is signed by its endpoints",
       ("%d, %d, %d"):format(player:correctPanStep(117, -117, 4),
                             player:correctPanStep(-117, 117, 4),
                             player:correctPanStep(0, 0, 4)),
       "-4, 4, 0")
  end
end

-- ---------------------------------------------------------------------------
-- The three sound tasks, measured by their FRAMES
-- ---------------------------------------------------------------------------

-- PROGRAM 0 is the clean case for the repeat: one `playloopedsoundeffect 1977, 117,
-- interval 2, count 10` and no other sound task. Ten plays, THREE frames apart --
-- interval + 1 -- the first on the frame after the command.
--
-- ALL THREE TERMS MATTER AND EACH IS A TERM A REIMPLEMENTATION DROPS: the count, the
-- period, and the fact that the first play is immediate rather than an interval late
-- (the command pre-loads `tickCount` to `applyInterval`, which the delay and pan
-- tasks do not).
do
  local events = runSound(0, true)
  local plays, first, gaps, bad = 0, nil, 0, 0
  local prev = nil
  for _, e in ipairs(events or {}) do
    if e.kind == "play" then
      plays = plays + 1
      first = first or e.frame
      if prev then
        if e.frame - prev == 3 then gaps = gaps + 1 else bad = bad + 1 end
      end
      prev = e.frame
    end
  end
  ok(plays == 10, "program 0's looped sound plays ten times", plays, 10)
  ok(gaps == 9 and bad == 0, "...three frames apart every time, which is interval + 1",
     ("%d gaps of three, %d others"):format(gaps, bad), "9 and 0")
  -- 6 AND NOT 3: one `LoadParticleResource` ahead of it, three frames each. The
  -- GAPS above are still three, which is the part this assertion is really about.
  ok(first == 6, "...the first on the frame after the command, not an interval later",
     first, 6)
end

-- THE DELAY FIRES ONCE, interval + 1 FRAMES AFTER ITS COMMAND. Program 2 passes an
-- interval of 5 and its command runs on frame 2, so the play lands on frame 8: the
-- task skips the frame it was created on, then counts 5, 4, 3, 2, 1 and fires on 0.
-- `(applyInterval--) == 0` is a POST-decrement, which is the one character that
-- decides whether an interval of 0 fires at once or never.
do
  local events = runSound(2, true)
  local delayed = nil
  for _, e in ipairs(events or {}) do
    if e.kind == "play" and e.delayed then delayed = e.frame end
  end
  -- 11 AND NOT 8: the same one load ahead of it. Six frames after ITS COMMAND is
  -- still what is being asserted -- the command moved from frame 2 to frame 5.
  ok(delayed == 11, "program 2's delayed sound lands six frames after its command",
     tostring(delayed), 11)
  local count = 0
  for _, e in ipairs(events or {}) do
    if e.kind == "play" and e.delayed then count = count + 1 end
  end
  ok(count == 1, "...exactly once", count, 1)
end

-- THE MOVING SOUND PLAYS AT ONCE AT ITS START PAN and then a task walks the pan
-- across. Program 6 is -117 to +117, four at a time, every third frame.
do
  local events = runSound(6, true)
  local startedAt, startPan, pans, step = nil, nil, {}, nil
  for _, e in ipairs(events or {}) do
    if e.kind == "play" and e.moving then startedAt = e.frame; startPan = e.pan end
    if e.kind == "pan" then pans[#pans + 1] = { e.frame, e.pan } end
  end
  ok(startPan == -117,
     "program 6's moving sound starts at the left, on the command's own frame",
     tostring(startPan), -117)
  ok(#pans >= 8, "...and then the pan is walked across", #pans .. " pan events",
     "at least 8")
  local goodGap, goodStep = 0, 0
  for i = 2, #pans do
    if pans[i][1] - pans[i - 1][1] == 3 then goodGap = goodGap + 1 end
    if pans[i][2] - pans[i - 1][2] == 4 then goodStep = goodStep + 1 end
  end
  ok(goodGap == #pans - 1 and goodStep == #pans - 1,
     "...four units every three frames, all the way",
     ("%d/%d gaps, %d/%d steps"):format(goodGap, #pans - 1, goodStep, #pans - 1),
     "all of them")
  -- AND THE FIRST STEP IS AN INTERVAL LATE, unlike the repeat's first play: this
  -- command does NOT pre-load the tick counter. One line apart in pret; three frames
  -- apart here.
  ok(pans[1] ~= nil and startedAt ~= nil and pans[1][1] - startedAt == 3,
     "...the first step three frames after the sound started, not on it",
     (pans[1] and startedAt) and (pans[1][1] - startedAt) or "-", 3)
end

-- !! AND NONE OF THE THREE HOLDS THE ANIMATION. `activeSoundTasks` is a separate
-- counter from `activeAnimTasks`, and only `waitforsoundeffects` -- which no program
-- uses -- reads it. Program 0's looped sound runs for thirty frames; if a sound task
-- were counted as an anim task, every `waitforanimtasks` after one would wait for the
-- noise to finish.
do
  local counted = nil
  if player and player:start(0, true) then
    local f = 0
    while player:update() and f < 600 do
      f = f + 1
      if f == 5 then counted = { player:taskCount(), player:soundTaskCount() } end
    end
  end
  ok(counted ~= nil and counted[2] > 0,
     "program 0 has a sound task running on frame 5",
     counted and counted[2] or "no frame", "more than 0")
  ok(counted ~= nil and counted[1] == 0,
     "...and `waitforanimtasks` cannot see it",
     counted and counted[1] or "-", 0)
end

-- ---------------------------------------------------------------------------
-- The cry, and the measuring pass
-- ---------------------------------------------------------------------------

-- THE CRY NAMES A SIDE, NOT A SPECIES, because the player is handed a move and a side
-- and never a party -- which is exactly what the cartridge does too
-- (`context->battlerSpecies[context->attacker]`).
do
  local found = nil
  for _, e in ipairs(runSound(45, true) or {}) do
    if e.kind == "cry" then found = e; break end
  end
  ok(found ~= nil and found.side == "attacker",
     "a cry event names the attacking side", found and found.side or "no cry",
     "attacker")
  ok(found ~= nil and found.modulation ~= nil and found.volume ~= nil,
     "...and carries pret's modulation and volume",
     found and ("mod %s, volume %s"):format(tostring(found.modulation),
                                            tostring(found.volume)) or "-",
     "both")
  -- !! EVERY ONE OF THE EIGHT CRIES ASKS FOR A DIFFERENT MODULATION -- 0, 3, 4, 6, 7,
  -- 8, 9 and 10, one each, which in `enum PokemonCryMod` is NORMAL, MID_MOVE,
  -- HYPERVOICE_1, FAINT... and HOWL and UPROAR. They name the moves. That is why the
  -- modulation is passed through rather than dropped: there is no common case to
  -- default to, and a port that ignored the operand would play the same cry eight
  -- times where the cartridge plays eight different ones.
  --
  -- THE OPCODE NUMBER FOR THIS COMMAND IS 65 AND AN EARLIER DRAFT OF THIS SECTION
  -- USED 64, which is `jumpifbattlerside` -- so its "modulation" was a battler mask
  -- and it reported "36 normal, one half length" off a command that has nothing to do
  -- with cries. Every opcode here is now looked up BY NAME out of `Anim.OPCODES`,
  -- which is the only spelling that cannot drift.
  local byName = {}
  for i = 0, Anim.OPCODE_COUNT - 1 do byName[Anim.OPCODES[i]] = i end
  local mods, uses = {}, 0
  for id = 0, arc.count - 1 do
    for _, ins in ipairs((programs[id] or {}).code or {}) do
      if ins[1] == byName.playpokemoncry then
        uses = uses + 1
        mods[signedWord(ins[2])] = (mods[signedWord(ins[2])] or 0) + 1
      end
    end
  end
  local distinct, repeated = 0, 0
  for _, n in pairs(mods) do
    distinct = distinct + 1
    if n > 1 then repeated = repeated + 1 end
  end
  ok(uses == 8 and distinct == 8 and repeated == 0,
     "all eight cries in the cartridge ask for a DIFFERENT modulation",
     ("%d calls, %d distinct, %d repeated"):format(uses, distinct, repeated),
     "8, 8, 0")
  -- ...AND THE EVENTS CARRY THEM. Counting the operands in the PROGRAM says nothing
  -- about what the player emitted: a plant that hard-coded the modulation to 0 passed
  -- the assertion above with room to spare. Taken off the five programs' own events.
  local emitted, order = {}, {}
  for _, id in ipairs({ 45, 46, 304, 336, 448 }) do
    for _, e in ipairs(runSound(id, true) or {}) do
      if e.kind == "cry" then
        emitted[e.modulation] = (emitted[e.modulation] or 0) + 1
        if id == 45 then
          order[#order + 1] = ("%d/%d"):format(e.modulation, e.volume)
        end
      end
    end
  end
  local emittedDistinct = 0
  for _ in pairs(emitted) do emittedDistinct = emittedDistinct + 1 end
  ok(emittedDistinct == 8, "...and the events carry all eight of them",
     emittedDistinct, 8)
  -- THREE OF THE FIVE PROGRAMS PLAY A PAIR, and the pairs are the enum's own halves:
  -- HOWL_1 then HOWL_2, UPROAR_1 then UPROAR_2, HYPERVOICE_1 then _2 -- at volume 100
  -- and then 127. A move calls the cry twice and the second is louder, which is what
  -- these constants are FOR, and it only reads that way in order.
  ok(table.concat(order, " ") == "9/100 10/127",
     "program 45 plays HOWL_1 at volume 100 and then HOWL_2 at 127",
     table.concat(order, " "), "9/100 10/127")
  -- ...and the five programs that play a cry are exactly the five that wait for one.
  local cries, waits = {}, {}
  for id = 0, arc.count - 1 do
    for _, ins in ipairs((programs[id] or {}).code or {}) do
      if ins[1] == byName.playpokemoncry then cries[id] = true end
      if ins[1] == byName.waitforpokemoncries then waits[id] = true end
    end
  end
  local paired, lonely = 0, 0
  for id in pairs(cries) do
    if waits[id] then paired = paired + 1 else lonely = lonely + 1 end
  end
  for id in pairs(waits) do if not cries[id] then lonely = lonely + 1 end end
  ok(paired == 5 and lonely == 0,
     "...and the five programs that cry are exactly the five that wait for it",
     ("%d paired, %d unpaired"):format(paired, lonely), "5 and 0")
end

-- `waitforpokemoncries` IS THE ONLY SOUND COMMAND THAT WAITS, and it waits on a
-- question only the engine can answer. Both answers are forced here, because a wait
-- that always blocks hangs the move and a wait that never blocks is not a wait.
do
  local held, freed, budget, plain = nil, nil, nil, nil
  if player then
    player.cryPlaying = function() return true end
    if player:start(45, true) then
      local f = 0
      while player:update() and f < Play.Player.FRAME_BUDGET + 10 do f = f + 1 end
      held, budget = player.soundWaits, f
    end
    player.cryPlaying = function() return false end
    if player:start(45, true) then
      local f = 0
      while player:update() and f < 300 do f = f + 1 end
      freed, plain = player.soundWaits, f
    end
    player.cryPlaying = nil
  end
  ok(held ~= nil and held > 0,
     "the cry wait holds the program while the engine says a cry is playing",
     held and (held .. " frames held") or "no run", "more than 0")
  ok(freed == 0 and plain ~= nil and plain < 100,
     "...and does not when it says none is",
     ("%s frames held, %s frames long"):format(tostring(freed), tostring(plain)),
     "0, and short")
  -- AND A SEAM THAT NEVER SAYS NO CANNOT HANG THE BATTLE. This is faithful -- pret
  -- waits on the real cry and would wait as long -- but faithful is not the same as
  -- safe, and the frame budget is what makes the difference. Forced, because a battle
  -- whose audio device stopped answering would otherwise freeze on a move.
  ok(budget ~= nil and budget <= Play.Player.FRAME_BUDGET + 1,
     "...and a cry that never ends is still stopped by the frame budget",
     ("%s frames of %d"):format(tostring(budget), Play.Player.FRAME_BUDGET),
     "the budget")
  -- A BATTLE THAT CANNOT ANSWER AT ALL IS NOT HELD UP. A wait on an unanswerable
  -- question is a hang, which is strictly worse than a cry overlapping the next
  -- command -- so it is recorded instead.
  local noted = 0
  if player and player:start(45, true) then
    local f = 0
    while player:update() and f < 300 do f = f + 1 end
    for _, row in ipairs(player:missing()) do
      if row.what:find("no way to ask", 1, true) then noted = noted + row.count end
    end
  end
  ok(noted == 2, "...and says so, once per call, when it cannot ask at all",
     noted .. " recorded", 2)
end

-- !! THE MEASURING PASS MUST BE SILENT. `duration()` runs the whole program and then
-- starts it again -- which is how the battle queue learns how long to wait -- so a
-- seam wired to the engine would play every sound in every move TWICE, the first time
-- all at once and before anything was drawn. Counted through the seam itself, because
-- that is the only place the duplicate would appear.
do
  local heard = 0
  if player then
    player.onSound = function() heard = heard + 1 end
    local frames = player:duration(0, true)
    ok(frames > 0, "measuring program 0 gives it a length", frames, "more than 0")
    ok(heard == 0, "...and makes no sound at all while doing it",
       heard .. " heard", 0)
    -- ...and the RUN after it is not silent, which is what says the flag was cleared
    -- rather than left on.
    heard = 0
    if player:start(0, true) then
      local f = 0
      while player:update() and f < 600 do f = f + 1 end
    end
    ok(heard > 0, "...while the run that follows it is heard", heard .. " heard",
       "more than 0")
    player.onSound = nil
  end
end

io.write("\nthe wiring in BattleState\n")
local bsPath = (root ~= "" and root or "./") .. "../src/battle/BattleState.lua"
local bsFile = io.open(bsPath, "rb")
local bs = bsFile and bsFile:read("*a")
if bsFile then bsFile:close() end
ok(bs ~= nil, "BattleState.lua is readable from here", bsPath, "readable")

-- !! SEARCH THE CODE, NOT THE COMMENTS. Every assertion below is a string
-- search over a 500,000-character file whose comments explain, by name, exactly
-- what the code does -- so a planted fault that deleted the gen4Layout() guard
-- passed, because the paragraph above it still said "gen4Layout()". A check
-- that a comment can satisfy is a check that the comment is what gets
-- maintained. Line comments are blanked first, and the fault fails after it.
if bs then
  bs = bs:gsub("%-%-[^\n]*", "")
end

if bs then
  -- THE CALL, not the assignment: `self.gen4Anim = nil` is an assignment too,
  -- and it passed this check before the name of the constructor was required.
  ok(bs:find("src.battle.Gen4MoveAnimPlayer", 1, true) ~= nil
     and bs:find("self.gen4Anim = Gen4MoveAnimPlayer.new", 1, true) ~= nil,
     "BattleState constructs the Gen 4 animator", "found", "found")
  -- THE CALL BEING PRESENT IS NOT THE CLAIM; being REACHED is. Planting a
  -- dead guard above this line left the call text untouched and passed a
  -- find() for it, which is a check that cannot fail dressed as one -- so
  -- assert the nearest guard above the tick actually names the playing flag,
  -- the same rule the roamer check uses on its three shared hooks.
  local tickAt = bs:find("self.gen4Anim:update()", 1, true)
  ok(tickAt ~= nil, "...and ticks it every frame", "found", "found")
  if tickAt then
    local before = bs:sub(math.max(1, tickAt - 300), tickAt)
    local guard = before:match(".*\n(%s*if [^\n]*)\n[^\n]*$")
             or before:match(".*(if [^\n]*)$")
    ok(guard ~= nil and guard:find("gen4AnimPlaying", 1, true) ~= nil,
       "...under a guard that names gen4AnimPlaying",
       guard and guard:gsub("^%s+", "") or "no guard found",
       "if self.gen4AnimPlaying ...")
  end
  -- STARTED BEHIND gen4Layout(), not beside Emerald's arm without a guard: a
  -- Gen 4 move index handed to Emerald's animator looks up a Hoenn table and
  -- plays whatever is at that index, which is worse than playing nothing.
  local startAt = bs:find("self.gen4Anim:duration(", 1, true)
  ok(startAt ~= nil, "...and starts it from the queue", "found", "found")
  if startAt then
    local before = bs:sub(math.max(1, startAt - 400), startAt)
    ok(before:find("gen4Layout()", 1, true) ~= nil,
       "...behind a gen4Layout() guard", "guarded", "guarded")
  end
  -- ALL THREE TRANSFORM CHANNELS, because a player wired into one of them
  -- moves a Pokemon that never scales or tints, and that reads as "the
  -- animation is half implemented" rather than as a missing branch.
  local wired = 0
  for _, m in ipairs({ "monOffset", "monAffine", "monTint" }) do
    if bs:find("self.gen4Anim%." .. m) then wired = wired + 1 end
  end
  ok(wired == 3, "all three transform channels read the Gen 4 animator",
     wired .. " of 3", 3)
  -- ...AND THE OLDER GAMES ARE STILL REACHED. A guard that excluded everything
  -- would pass every test above while quietly retiring Emerald's animator --
  -- the same failure the roamer check exists to catch on the shared hooks.
  ok(bs:find("self.gen3AnimPlaying and self.gen3Anim", 1, true) ~= nil,
     "...and Emerald's animator is still reached", "found", "found")
end

-- ---------------------------------------------------------------------------
-- 19: THE MON-SPRITE SLOTS, THE HIDE CHANNEL AND DARK VOID
--
-- THREE THINGS THIS PASS FOUND, and the first is the one that matters most:
--
--  (1) `Player:monHidden` HAD NO CALLER ANYWHERE IN THE PORT. `Func_HideBattler`
--      (40) is 50 calls over 16 programs and every one of them drew nothing --
--      Whirlwind and Roar blow the foe away and never bring it back, and the
--      Pokemon stood there through both. The fourth time this port has had the
--      same bug: a cache table nobody opened, an animator nobody constructed, a
--      picture nobody drew into, and now a method nobody called. So this section
--      asserts THE CALL SITE out of Gen4Battle's source before any arithmetic.
--
--  (2) THE WHOLE MON-SPRITE FAMILY WAS `NOT_NEEDED` FOR A REASON THAT WAS RIGHT
--      439 TIMES OUT OF 440. `LoadParticleResource` is a SEVENTEEN-INSTRUCTION
--      MACRO -- init the manager, four dummy resources, four `AddPokemonSprite`
--      (PLAYER_1, ENEMY_1, PLAYER_2, ENEMY_2), `RenderPokemonSprites 0`, the
--      actual load, `WaitForAnimTasks`, free, four removes -- so the four copies
--      are there to KEEP THE POKEMON ON SCREEN ACROSS A SYNCHRONOUS NARC READ.
--      That is the whole purpose in 439 programs and this port has no such stall,
--      which is exactly what "the battler is already on screen" said. Dark Void
--      is the one program that animates a copy, and for it the reason was wrong.
--
--  (3) `RenderPokemonSprites` TREATED ITS OPERAND LITERALLY. `if (GetScriptVar
--      (FRAMES) == 0) ctx->frames = RENDER_POKEMON_SPRITES_DEFAULT_FRAMES;` with
--      that constant being 3 -- and 476 of the 477 calls pass 0, so 476 tasks
--      ended on their first step instead of holding three frames.
--
-- FIFTEEN FAULTS PLANTED, ALL FIFTEEN FAIL. Five assertions had to be rewritten
-- first, and one thing written down as "not a fault" turned out to be one:
--   monHidden never called            -> the Gen4Battle source search
--   the window never raised           -> the windowed frame count
--   the window never lowered          -> REWRITTEN: "is a window up after the run"
--      is false either way because `monWindow` is behind `alive()`, exactly like
--      the greyscale plant in section 17. Taken onto the LAST windowed frame.
--   the sink applied to the battler    -> the offset under a visible battler
--      rather than "does the enemy move", which is true on both readings
--   the coin read as "whether"        -> REWRITTEN: the first version asserted the
--      total sink, which the forcing rows make 20 whichever way every coin falls
--      -- a measurement that cannot fail. Taken onto a FORCED all-tails run, where
--      the four steps must land on states 7, 12, 17 and 24 exactly.
--   the forcing rows dropped          -> the same all-tails run: total 0, not 20
--   `unless` read as `need`           -> the all-heads run
--   the long step made short          -> the total, 16 not 20
--   the cut-off measured on the wrong
--     battler                         -> the frame the copy goes invisible, which
--      is 24 pixels in instead of 84. THIS WAS THE REAL BUG, not a plant: it was
--      `self.attackerIsPlayer and false or true`, which is always true.
--   the partner role given a task     -> the task count, and the window's owner
--   the partner role not hidden       -> the slot's visibility at the first frame
--   the slots not cleared per run     -> a hidden side in the NEXT program
--   the renderer condition dropped    -> the hidden-frame total over the corpus
--   zero frames not read as three     -> the whole corpus's timing, eight failures
--   `monSpriteFor` ignoring `visible`  -> the hidden-frame total, 434 not 462. I
--      wrote this one down as NOT a fault first, reasoning that a copy is invisible
--      only on frames where the battler is hidden anyway. WRONG, and the plant said
--      so: those are exactly the frames where the two readings disagree -- Dark
--      Void's last twenty-eight frames have a hidden battler AND an invisible copy,
--      and without the test the copy keeps answering for it. PREDICTING WHICH
--      PLANTS WILL FAIL IS NOT A SUBSTITUTE FOR PLANTING THEM.
--   the slots not cleared per run      -> REWRITTEN: running a program to its end
--      and starting another tests nothing, because `clearTransforms` has already
--      emptied the slots. Taken onto a run ABANDONED mid-animation.
-- ---------------------------------------------------------------------------
io.write("\nthe mon-sprite slots, the hide channel and Dark Void\n")

-- The constants live on the metatable an instance inherits from, which the module
-- publishes as `Play.Player` -- `Play` itself is the two-function constructor.
local PL = Play.Player

local Gen4Battle_ok, Gen4Battle = pcall(require, "src.battle.Gen4Battle")
ok(Gen4Battle_ok and type(Gen4Battle) == "table",
   "Gen4Battle loads with no graphics device",
   Gen4Battle_ok and "loaded" or tostring(Gen4Battle), "loaded")

-- THE CALL SITE, FIRST, and read as source with the comments stripped -- a comment
-- that mentions `monHidden` is exactly what this must not accept.
do
  local f = io.open((root ~= "" and root or "./") .. "../src/battle/Gen4Battle.lua",
                    "rb")
  local src = f and f:read("*a")
  if f then f:close() end
  local code = src and src:gsub("%-%-[^\n]*", "")
  ok(code ~= nil, "Gen4Battle.lua is readable from here", "read", "read")
  if code then
    ok(code:find("player%.monHidden") ~= nil,
       "the Gen 4 screen asks the animator whether a battler is hidden",
       code:find("player%.monHidden") and "found"
         or "NOT FOUND -- every HideBattler draws nothing", "found")
    -- IN THE DRAW LOOP, not merely defined somewhere: a helper nobody calls is
    -- the bug this whole section exists because of.
    local at = code:find("function Gen4Battle%.drawBattlers")
    local body = at and code:sub(at, at + 1600) or ""
    ok(body:find("battlerHidden", 1, true) ~= nil,
       "...inside drawBattlers, not merely defined",
       body:find("battlerHidden", 1, true) and "called" or "NOT CALLED", "called")
    ok(body:find("monWindowClip", 1, true) ~= nil,
       "...and the window clip is applied there too",
       body:find("monWindowClip", 1, true) and "applied" or "NOT APPLIED",
       "applied")
    -- AND THE OTHER GENERATIONS ARE UNTOUCHED: this is on the Gen 4 screen and
    -- not in `BattleState:drawBattlerPic`, which Kanto, Johto and Hoenn share.
    local bf = io.open((root ~= "" and root or "./") .. "../src/battle/BattleState.lua",
                       "rb")
    local bs = bf and bf:read("*a")
    if bf then bf:close() end
    -- NARROWED ON PURPOSE: BattleState carries an UNRELATED `monHidden` -- a field
    -- on the Gen 3 ball record -- so the bare name is satisfied by code that has
    -- nothing to do with this. The question is whether the SHARED draw asks the
    -- Gen 4 animator, which is `gen4Anim.monHidden`.
    local shared = bs and bs:gsub("%-%-[^\n]*", "") or ""
    ok(shared ~= "" and shared:find("gen4Anim%.monHidden") == nil
       and shared:find("gen4Anim, *battler") == nil,
       "...and the shared battler draw does not ask it",
       shared:find("gen4Anim%.monHidden") and "IT DOES" or "untouched", "untouched")
  end
end

-- TWO STATEMENTS OF THE SAME TWO BATTLER CENTRES. The animator needs them because
-- Dark Void's cut-off is an ABSOLUTE y and a slot only carries a delta; the screen
-- needs them to place a Pokemon. Both are `BATTLER_POS_SOLO_*` out of
-- battle_anim.h, and duplicating a number is only safe if something checks it
-- stayed duplicated.
if Gen4Battle_ok then
  local a, b = PL.BATTLER_CENTRE[true], Gen4Battle.BATTLER_POS[0]
  ok(a and b and a.x == b.x and a.y == b.y,
     "the animator and the screen agree on the player's centre",
     ("%s,%s vs %s,%s"):format(a and a.x, a and a.y, b and b.x, b and b.y),
     "64,112")
  local c, d = PL.BATTLER_CENTRE[false], Gen4Battle.BATTLER_POS[1]
  ok(c and d and c.x == d.x and c.y == d.y,
     "...and on the foe's", ("%s,%s vs %s,%s"):format(c and c.x, c and c.y,
                                                      d and d.x, d and d.y),
     "192,48")
end

-- THE TWO WINDOWS, as arithmetic on the screen rather than as literals.
do
  local w0, w1 = PL.MON_WINDOW[0], PL.MON_WINDOW[1]
  ok(w0 and w1, "both window types are declared", (w0 and 1 or 0) + (w1 and 1 or 0), 2)
  if w0 and w1 then
    ok(w0.bottom == 192 and w1.bottom == 192,
       "both windows run to the bottom of the screen",
       ("%d, %d"):format(w0.bottom, w1.bottom), "192, 192")
    ok(w0.left == 0 and w0.right == 128 and w1.left == 128 and w1.right == 256,
       "...and each covers exactly one half horizontally",
       ("%d-%d and %d-%d"):format(w0.left, w0.right, w1.left, w1.right),
       "0-128 and 128-256")
    ok(w1.top == 192 / 2 - 10,
       "window 1's top is ten pixels above the middle of the screen",
       w1.top, 192 / 2 - 10)
    ok(w0.top == 160, "...and window 0's is at 160", w0.top, 160)
    -- THE CLAIM A SINGLE SCISSOR RESTS ON. An 80-wide Sinnoh picture centred on
    -- either solo battler must lie WHOLLY inside its own window's x span, or
    -- "inside the window" would not reduce to "below the top edge" and the clip
    -- would cut the wrong half of a Pokemon.
    local straddles = 0
    for _, row in ipairs({ { PL.BATTLER_CENTRE[true], w0 },
                           { PL.BATTLER_CENTRE[false], w1 } }) do
      local cx, win = row[1].x, row[2]
      if cx - 40 < win.left or cx + 40 > win.right then
        straddles = straddles + 1
      end
    end
    ok(straddles == 0,
       "neither solo battler's picture straddles its window's x edge",
       straddles, 0)
  end
end

-- `sideForRole` FOR ALL EIGHT ROLES, BOTH DIRECTIONS.
do
  player.attackerIsPlayer = true
  local R = PL.ROLE
  ok(player:sideForRole(R.ATTACKER) == true
     and player:sideForRole(R.DEFENDER) == false,
     "attacker and defender resolve to the two sides",
     tostring(player:sideForRole(R.ATTACKER)) .. "/"
       .. tostring(player:sideForRole(R.DEFENDER)), "true/false")
  player.attackerIsPlayer = false
  ok(player:sideForRole(R.ATTACKER) == false
     and player:sideForRole(R.DEFENDER) == true,
     "...and swap when the foe is attacking",
     tostring(player:sideForRole(R.ATTACKER)) .. "/"
       .. tostring(player:sideForRole(R.DEFENDER)), "false/true")
  -- A PARTNER ROLE IS NOT AN ABSENCE: `BattleAnimUtil_GetAlliedBattler` returns
  -- THE BATTLER'S OWN TYPE for a solo battler, so the partner of the defender in
  -- a single battle IS the defender.
  player.attackerIsPlayer = true
  ok(player:sideForRole(R.ATTACKER_PARTNER) == player:sideForRole(R.ATTACKER),
     "a partner role resolves to its primary's own side",
     tostring(player:sideForRole(R.ATTACKER_PARTNER)), "the same side")
  ok(player:sideForRole(R.DEFENDER_PARTNER) == player:sideForRole(R.DEFENDER),
     "...on the defending side too",
     tostring(player:sideForRole(R.DEFENDER_PARTNER)), "the same side")
  -- ...AND PLAYER_2 / ENEMY_2 FALL BACK TO THE PLAYER, not to the foe and not to
  -- nothing: each scans for its own slot type, finds none, and ends
  -- `result = BATTLER_PLAYER_1`.
  ok(player:sideForRole(R.PLAYER_1) == true
     and player:sideForRole(R.ENEMY_1) == false,
     "PLAYER_1 and ENEMY_1 are the two absolute sides",
     tostring(player:sideForRole(R.PLAYER_1)) .. "/"
       .. tostring(player:sideForRole(R.ENEMY_1)), "true/false")
  ok(player:sideForRole(R.PLAYER_2) == true
     and player:sideForRole(R.ENEMY_2) == true,
     "...and both slot-2 roles fall back to the player",
     tostring(player:sideForRole(R.PLAYER_2)) .. "/"
       .. tostring(player:sideForRole(R.ENEMY_2)), "true/true")
end

-- THE CORPUS SHAPE OF FUNC 75, off we.arc and not off pret's res/.
do
  local byName75 = {}
  for i = 0, Anim.OPCODE_COUNT - 1 do byName75[Anim.OPCODES[i]] = i end
  local CF = byName75.callfunc
  ok(CF ~= nil, "callfunc has a name in the table", tostring(CF), "an opcode")
  local calls, five, seven, bg3, prio0, partners = 0, 0, 0, 0, 0, 0
  local progs = {}
  for id = 0, arc.count - 1 do
    local rec = programs[id]
    if rec then
      for _, ins in ipairs(rec.code) do
        if ins[1] == CF and signedWord(ins[2]) == 75 then
          calls = calls + 1
          progs[id] = true
          local nv = signedWord(ins[3])
          if nv == 5 then five = five + 1 elseif nv == 7 then seven = seven + 1 end
          if signedWord(ins[6]) == 3 then bg3 = bg3 + 1 end
          if signedWord(ins[7]) == 0 then prio0 = prio0 + 1 end
          local role = signedWord(ins[8])
          if role == 2 or role == 3 then partners = partners + 1 end
        end
      end
    end
  end
  local nprogs = 0
  for _ in pairs(progs) do nprogs = nprogs + 1 end
  ok(calls == 12 and nprogs == 6,
     "func 75 is called twelve times over six programs",
     ("%d calls / %d programs"):format(calls, nprogs), "12 / 6")
  ok(five == 10 and seven == 2,
     "...ten as SetPokemonSpritePriority and two as DarkVoid",
     ("%d five-var, %d seven-var"):format(five, seven), "10 and 2")
  -- THE THREE FACTS THAT MAKE THE PRIORITY HALF A NO-OP, and the first two are
  -- these: every call names BATTLE_ANIM_BG_POKEMON and asks for priority 0.
  ok(bg3 == 12, "every call names BATTLE_ANIM_BG_POKEMON (3)", bg3, 12)
  ok(prio0 == 12, "...and every call asks for sprite priority 0", prio0, 12)
  ok(partners == 6, "...and half of them name a partner role", partners, 6)
end

-- THE THIRD FACT, out of the tables rather than out of a comment.
do
  local t = PL.SPRITE_PRIORITY_BY_TYPE
  ok(t and t[0] == 0 and t[1] == 0,
     "both solo battler types default to sprite priority 0",
     ("%s, %s"):format(tostring(t and t[0]), tostring(t and t[1])), "0, 0")
  ok(t and t[2] == 20 and t[3] == 10 and t[4] == 10 and t[5] == 20,
     "...and the four doubles types are the 20/10/10/20 the switch would write",
     ("%s,%s,%s,%s"):format(tostring(t and t[2]), tostring(t and t[3]),
                            tostring(t and t[4]), tostring(t and t[5])),
     "20,10,10,20")
  ok(PL.MON_SPRITE_BG_PRIORITY == 1,
     "and BATTLE_ANIM_BG_POKEMON resolves to the template's own bg priority",
     PL.MON_SPRITE_BG_PRIORITY, 1)
end

-- ...SO THE RECORD SAYS EVERY CALL CHANGED NOTHING. Asserted off what the player
-- actually wrote, not off the three facts above -- that is the point of recording
-- it at all.
do
  local rows, changed = 0, 0
  for _, move in ipairs({ 92, 307, 399, 401, 461, 464 }) do
    if player:start(move, true) then
      local n = 0
      while player:update() and n < 400 do n = n + 1 end
      for _, r in ipairs(player.monPriority or {}) do
        rows = rows + 1
        if r.explicit ~= r.explicitWas then changed = changed + 1 end
        if r.priority ~= r.priorityWas then changed = changed + 1 end
        if r.override ~= nil then changed = changed + 1 end
      end
      player:stop()
    end
  end
  ok(rows == 12, "all six programs reach both of their calls from the player's side",
     rows, 12)
  ok(changed == 0,
     "...and not one of them changes a priority from what it already was",
     changed, 0)
end

-- DARK VOID, DRIVEN.
local function runVoid(move, atkIsPlayer, forceCoin)
  if not player:start(move, atkIsPlayer) then return nil end
  if forceCoin ~= nil then
    -- A FORCED COIN, so the timing claims can be asserted at all. `lcrng` is the
    -- one draw the sink makes; replacing it is how an all-tails and an all-heads
    -- run become two different measurements instead of one lucky seed.
    player.lcrng = function() return forceCoin end
  end
  local rows, n = {}, 0
  while player:update() and n < 400 do
    n = n + 1
    local task = nil
    for _, t in ipairs(player.tasks) do
      if t.kind == "monprio" then task = t end
    end
    local slot0 = player.monSprites and player.monSprites[0]
    local slot1 = player.monSprites and player.monSprites[1]
    local _, dy = player:monOffset(not atkIsPlayer)
    rows[n] = {
      win = player.monWindowRect and player.monWindowRect.top or nil,
      state = task and task.state or nil,
      step = task and task.stepCount or nil,
      sinkFrom = task and task.sinkFrom or nil,
      dy0 = slot0 and slot0.dy or nil,
      hiddenDef = player:monHidden(not atkIsPlayer),
      offDef = dy,
    }
    -- ASSIGNED SEPARATELY, NOT IN THE TABLE LITERAL: `slot and slot.visible or nil`
    -- collapses a FALSE to nil, which is the one value these two tests are looking
    -- for. Two assertions passed on nothing at all before this was noticed.
    if slot0 then rows[n].vis0 = slot0.visible == true end
    if slot1 then rows[n].vis1 = slot1.visible == true end
  end
  player.lcrng = nil
  return rows, n
end

do
  local rows, n = runVoid(464, true)
  ok(rows ~= nil and n > 100, "program 464 runs", n, "over 100 frames")
  if rows then
    local winFrames, firstWin, lastWin = 0, nil, nil
    local maxDy, firstInvisible, hiddenFrames = 0, nil, 0
    local dyAt24, sinkFrom = nil, nil
    for f = 1, n do
      local r = rows[f]
      if r.win then
        winFrames = winFrames + 1
        firstWin = firstWin or f
        lastWin = f
      end
      if (r.dy0 or 0) > maxDy then maxDy = r.dy0 end
      if r.vis0 == false and firstInvisible == nil and r.state then
        firstInvisible = r.state
      end
      if r.hiddenDef then hiddenFrames = hiddenFrames + 1 end
      if r.state == 25 and dyAt24 == nil then dyAt24 = r.dy0 end
      sinkFrom = sinkFrom or r.sinkFrom
    end
    ok(winFrames == 79, "the window is up for the task's whole life but its last frame",
       winFrames, 79)
    -- THE LAST WINDOWED FRAME, not "is a window up afterwards": `monWindow` is
    -- behind `alive()` and answers nil once the run is over whether the task took
    -- the window down or not -- the same shape as the greyscale plant in section 17.
    ok(lastWin ~= nil and lastWin < n and rows[lastWin + 1]
       and rows[lastWin + 1].win == nil,
       "...and is switched off while the program still has frames to run",
       ("last windowed frame %s of %d"):format(tostring(lastWin), n),
       "before the last frame")
    ok(sinkFrom ~= nil and sinkFrom >= PL.DARK_VOID_SINK_MIN
       and sinkFrom < PL.DARK_VOID_SINK_MIN + PL.DARK_VOID_SINK_RNG,
       "the frame the fall begins on is rolled inside its stated range",
       sinkFrom, "35..39")
    -- THE FOUR JITTER STEPS TOTAL TWENTY BY STATE 24, WHATEVER THE COIN DID.
    ok(dyAt24 == 20, "the four jittered steps have moved it twenty pixels by state 24",
       dyAt24, 20)
    -- ...AND THE FALL TAKES IT TO EIGHTY-FOUR, WHICH IS WHERE THE TWO LIMITS MEET:
    -- the twentieth step and `y > 130` land on the same frame because the foe's
    -- centre is 48, the jitter puts it at 68, and sixteen more steps of four is 132.
    ok(maxDy == 84, "the fall takes it to eighty-four pixels and stops", maxDy, 84)
    ok(PL.BATTLER_CENTRE[false].y + maxDy > PL.DARK_VOID_MAX_Y
       and PL.BATTLER_CENTRE[false].y + maxDy - PL.DARK_VOID_STEP_Y
           <= PL.DARK_VOID_MAX_Y,
       "...on the first step that carries the foe's centre past 130",
       PL.BATTLER_CENTRE[false].y + maxDy, "131..134")
    ok(firstInvisible ~= nil and firstInvisible > 24,
       "the copy is drawn through the whole jitter and vanishes in the fall",
       tostring(firstInvisible), "past state 24")
    -- THE POINT OF THE WHOLE PASS: the defender is hidden and the COPY is what the
    -- offset reports, so the foe sinks instead of blinking out.
    local sinking = 0
    for f = 1, n do
      if rows[f].hiddenDef == false and (rows[f].offDef or 0) > 0 then
        sinking = sinking + 1
      end
    end
    ok(sinking >= 40,
       "the foe is on screen and displaced for the length of the sink",
       sinking, "at least 40 frames")
    ok(hiddenFrames > 0 and hiddenFrames < n,
       "...and off it afterwards, not for the whole program", hiddenFrames,
       "some but not all")
    -- THE PARTNER CALL STARTED NO TASK AND HID ITS SLOT ON THE FIRST FRAME.
    -- ASKED AT THE FIRST FRAME THE TASK EXISTS, not at the first frame a slot 1
    -- exists: `LoadParticleResource`'s own preamble fills slot 1 with a VISIBLE
    -- copy of the foe thirty frames earlier, and a test that found that frame was
    -- answering a different question.
    local firstTask = nil
    for f = 1, n do
      if rows[f].state ~= nil then firstTask = f; break end
    end
    ok(firstTask ~= nil and rows[firstTask].vis1 == false,
       "the partner copy is hidden the moment its call is made",
       firstTask and tostring(rows[firstTask].vis1) or "no task", "false")
  end
end

-- AND THE OTHER DIRECTION IS A DIFFERENT SCRIPT. `jumpifbattlerside` sends a
-- foe-cast Dark Void down a branch with NO func 75 in it at all -- the sink there
-- is plain `MoveBattler` on the battler sprite, which this port has had all along.
-- So the two halves of the same move are implemented twice on the cartridge.
do
  local rows, n = runVoid(464, false)
  ok(rows ~= nil, "program 464 runs from the foe's side too", n, "a frame count")
  if rows then
    local winFrames = 0
    for f = 1, n do if rows[f].win then winFrames = winFrames + 1 end end
    ok(winFrames == 0, "...with no window at all on that branch", winFrames, 0)
  end
end

-- THE FORCED COINS. Every claim about WHEN the jitter steps land needs the die
-- taken away, and the two extremes are the two measurements.
do
  local tails, n1 = runVoid(464, true, 0)          -- LCRNG_Next() % 2 == 0
  local heads, n2 = runVoid(464, true, 1)          -- ... == 1
  local function dyAtState(rows, count, state)
    for f = 1, count do if rows[f].state == state then return rows[f].dy0 end end
    return nil
  end
  ok(tails ~= nil and heads ~= nil, "both forced runs complete",
     ("%s and %s frames"):format(tostring(n1), tostring(n2)), "two runs")
  if tails and heads then
    -- ALL TAILS: no coin row ever fires, so every step is a FORCING row and the
    -- four land on states 7, 12, 17 and 24 exactly.
    ok(dyAtState(tails, n1, 7) == 0 and dyAtState(tails, n1, 8) == 4,
       "all tails: the first step is forced at state 7",
       ("%s then %s"):format(tostring(dyAtState(tails, n1, 7)),
                             tostring(dyAtState(tails, n1, 8))), "0 then 4")
    ok(dyAtState(tails, n1, 13) == 8 and dyAtState(tails, n1, 18) == 12,
       "...and the second and third at 12 and 17",
       ("%s, %s"):format(tostring(dyAtState(tails, n1, 13)),
                         tostring(dyAtState(tails, n1, 18))), "8, 12")
    ok(dyAtState(tails, n1, 25) == 20,
       "...and the fourth, by EIGHT, at 24", dyAtState(tails, n1, 25), 20)
    -- ALL HEADS: every coin row fires at the first opportunity, so the steps land
    -- on 5, 10, 15 and 22 and the forcing rows do nothing.
    ok(dyAtState(heads, n2, 6) == 4 and dyAtState(heads, n2, 11) == 8,
       "all heads: the first two steps land at the top of their windows",
       ("%s, %s"):format(tostring(dyAtState(heads, n2, 6)),
                         tostring(dyAtState(heads, n2, 11))), "4, 8")
    ok(dyAtState(heads, n2, 16) == 12 and dyAtState(heads, n2, 23) == 20,
       "...and so do the third and fourth",
       ("%s, %s"):format(tostring(dyAtState(heads, n2, 16)),
                         tostring(dyAtState(heads, n2, 23))), "12, 20")
    -- THE COIN CHANGES WHEN, NEVER WHETHER.
    local function maxDy(rows, count)
      local m = 0
      for f = 1, count do if (rows[f].dy0 or 0) > m then m = rows[f].dy0 end end
      return m
    end
    ok(maxDy(tails, n1) == 84 and maxDy(heads, n2) == 84,
       "either way the Pokemon sinks exactly as far",
       ("%d and %d"):format(maxDy(tails, n1), maxDy(heads, n2)), "84 and 84")
  end
end

-- THE HIDE CHANNEL OVER THE WHOLE CORPUS, both directions.
do
  local hides, shows, progs, never = 0, 0, {}, {}
  local byName40 = {}
  for i = 0, Anim.OPCODE_COUNT - 1 do byName40[Anim.OPCODES[i]] = i end
  local CF = byName40.callfunc
  for id = 0, arc.count - 1 do
    local rec = programs[id]
    if rec then
      local h, sh = 0, 0
      for _, ins in ipairs(rec.code) do
        if ins[1] == CF and signedWord(ins[2]) == 40 then
          if signedWord(ins[5] or 0) ~= 0 then h = h + 1 else sh = sh + 1 end
        end
      end
      if h + sh > 0 then
        progs[id] = true
        hides, shows = hides + h, shows + sh
        if sh == 0 then never[#never + 1] = id end
      end
    end
  end
  local nprogs = 0
  for _ in pairs(progs) do nprogs = nprogs + 1 end
  ok(hides == 24 and shows == 26 and nprogs == 16,
     "the hide channel is fifty calls over sixteen programs",
     ("%d hides, %d shows, %d programs"):format(hides, shows, nprogs),
     "24, 26, 16")
  -- TWO PROGRAMS HIDE AND NEVER SHOW. Whirlwind and Roar blow the foe off the
  -- field, so the flag has to be cleared by `clearTransforms` rather than by the
  -- program -- and if it were not, the next Pokemon out would be invisible.
  ok(#never == 2, "two programs hide a battler and never show it again",
     table.concat(never, ","), "two of them")
  local leaked = 0
  for _, id in ipairs(never) do
    if player:start(id, true) then
      local n = 0
      while player:update() and n < 400 do n = n + 1 end
      player:stop()
      if player:monHidden(true) or player:monHidden(false) then
        leaked = leaked + 1
      end
    end
  end
  ok(leaked == 0, "...and neither leaves a side hidden once the player is idle",
     leaked, 0)
end

-- ...AND THE FRAMES IT IS WORTH. Zero of these were observable before this pass.
do
  local function hiddenFrames(dir)
    local total, progs = 0, {}
    for id = 0, arc.count - 1 do
      if programs[id] and player:start(id, dir) then
        local n, saw = 0, false
        while player:update() and n < 900 do
          n = n + 1
          if player:monHidden(true) then total = total + 1; saw = true end
          if player:monHidden(false) then total = total + 1; saw = true end
        end
        if saw then progs[id] = true end
        player:stop()
      end
    end
    local np = 0
    for _ in pairs(progs) do np = np + 1 end
    return total, np
  end
  local a, ap = hiddenFrames(true)
  local b, bp = hiddenFrames(false)
  ok(a == 462 and ap == 14,
     "a Pokemon is off the field for 462 frames over 14 programs, player casting",
     ("%d frames / %d programs"):format(a, ap), "462 / 14")
  ok(b == 409 and bp == 13, "...and 409 over 13 with the foe casting",
     ("%d frames / %d programs"):format(b, bp), "409 / 13")
  -- A FLOOR THAT CANNOT BE HIT BY ACCIDENT: before this pass both numbers were
  -- zero, because nothing read the channel.
  ok(a > 0 and b > 0, "...which is not zero, as it was before this pass",
     ("%d and %d"):format(a, b), "both above zero")
end

-- THE RENDERER CONDITION, which is the one line of pret that makes the slot layer
-- sound: `SpriteSystem_DrawSprites` IS `SpriteList_Update`, so a copy reaches OAM
-- only while a function that calls it is alive.
do
  ok(player:start(464, true), "464 starts", "started", "started")
  local rendered, notRendered, slotsWhileIdle = 0, 0, 0
  local n = 0
  while player:update() and n < 400 do
    n = n + 1
    local live = player:monSpritesRendered()
    if live then rendered = rendered + 1 else notRendered = notRendered + 1 end
    if not live then
      local count = 0
      for _ in pairs(player.monSprites or {}) do count = count + 1 end
      if count > 0 then slotsWhileIdle = slotsWhileIdle + 1 end
    end
  end
  player:stop()
  ok(rendered > 0 and notRendered > 0,
     "the manager is rendered on some frames of 464 and not on others",
     ("%d rendered, %d not"):format(rendered, notRendered), "both")
  -- SLOTS EXIST WITH NOTHING RENDERING THEM, which is exactly the state the four
  -- copies of `LoadParticleResource` sit in for one frame of every load.
  ok(slotsWhileIdle > 0,
     "...and slots do exist on frames nothing is rendering them",
     slotsWhileIdle, "more than none")
end

-- `LoadParticleResource`'S OWN EXPANSION, which is where 439 of the 440 programs'
-- mon sprites come from -- and the reason the whole family looked like bookkeeping.
do
  local byNameLP = {}
  for i = 0, Anim.OPCODE_COUNT - 1 do byNameLP[Anim.OPCODES[i]] = i end
  local rec = programs[464]
  ok(rec ~= nil, "464 is decoded", rec and #rec.code, "an instruction count")
  if rec then
    local c = rec.code
    local shape = { "initpokemonspritemanager",
                    "loadpokemonspritedummyresources",
                    "loadpokemonspritedummyresources",
                    "loadpokemonspritedummyresources",
                    "loadpokemonspritedummyresources",
                    "addpokemonsprite", "addpokemonsprite",
                    "addpokemonsprite", "addpokemonsprite",
                    "callfunc" }
    local matched = 0
    for i, want in ipairs(shape) do
      if c[i] and Anim.OPCODES[c[i][1]] == want then matched = matched + 1 end
    end
    ok(matched == #shape,
       "464 opens with LoadParticleResource's seventeen-instruction expansion",
       matched .. " of " .. #shape, #shape)
    -- THE FOUR ROLES ARE THE ABSOLUTE ONES, which is what makes the copies a
    -- placeholder for a file read rather than part of any animation.
    local roles = {}
    for i = 6, 9 do roles[#roles + 1] = signedWord(c[i] and c[i][2]) end
    ok(table.concat(roles, ",") == "4,5,6,7",
       "...adding PLAYER_1, ENEMY_1, PLAYER_2 and ENEMY_2",
       table.concat(roles, ","), "4,5,6,7")
    ok(signedWord(c[10][2]) == 78 and signedWord(c[10][4]) == 0,
       "...and rendering them with RenderPokemonSprites 0",
       ("func %d operand %d"):format(signedWord(c[10][2]), signedWord(c[10][4])),
       "func 78 operand 0")
  end
end

-- ZERO MEANS THREE. 476 of the 477 calls pass 0 and the cartridge turns that into
-- RENDER_POKEMON_SPRITES_DEFAULT_FRAMES.
do
  local byName78 = {}
  for i = 0, Anim.OPCODE_COUNT - 1 do byName78[Anim.OPCODES[i]] = i end
  local CF = byName78.callfunc
  local zero, real = 0, 0
  for id = 0, arc.count - 1 do
    local rec = programs[id]
    if rec then
      for _, ins in ipairs(rec.code) do
        if ins[1] == CF and signedWord(ins[2]) == 78 then
          if signedWord(ins[3]) >= 1 and signedWord(ins[4]) ~= 0 then
            real = real + 1
          else
            zero = zero + 1
          end
        end
      end
    end
  end
  ok(zero == 476 and real == 1,
     "476 of the 477 RenderPokemonSprites calls pass zero frames",
     ("%d zero, %d real"):format(zero, real), "476 and 1")
  -- AND THE PLAYER HOLDS THREE FRAMES FOR THEM. Measured on 464's first load,
  -- where the block is four frames long: three with the manager rendered and the
  -- fourth the frame the hold ends.
  if player:start(464, true) then
    local renderedRun = 0
    local n = 0
    while player:update() and n < 20 do
      n = n + 1
      if player:monSpritesRendered() then renderedRun = renderedRun + 1 end
    end
    player:stop()
    ok(renderedRun >= 3,
       "...and the hold they build lasts three frames, not none",
       renderedRun, "at least 3")
  end
end

-- THE WINDOW CLIP, THROUGH THE SCREEN'S OWN FUNCTION, with a stand-in picture --
-- which is the only way to test it without a graphics device, and enough, because
-- the only thing it reads off an image is its width.
if Gen4Battle_ok then
  local pic = { getWidth = function() return 80 end }
  local fake = { gen4AnimPlaying = true, gen4Anim = player,
                 player = { name = "p" }, enemy = { name = "e" } }
  player.monWindowRect = PL.MON_WINDOW[1]
  player.playing = true
  local clipFoe = Gen4Battle.monWindowClip(fake, Gen4Battle.BATTLER_POS[1], pic)
  local clipMe = Gen4Battle.monWindowClip(fake, Gen4Battle.BATTLER_POS[0], pic)
  ok(clipFoe == PL.MON_WINDOW[1].top,
     "window 1 clips the foe at its own top edge", tostring(clipFoe),
     PL.MON_WINDOW[1].top)
  ok(clipMe == nil, "...and does not touch the player, who is outside it",
     tostring(clipMe), "nil")
  player.monWindowRect = PL.MON_WINDOW[0]
  ok(Gen4Battle.monWindowClip(fake, Gen4Battle.BATTLER_POS[0], pic)
       == PL.MON_WINDOW[0].top,
     "window 0 clips the player instead",
     tostring(Gen4Battle.monWindowClip(fake, Gen4Battle.BATTLER_POS[0], pic)),
     PL.MON_WINDOW[0].top)
  -- A WIDER PICTURE STRADDLES AND GETS NO CLIP AT ALL, because half a Pokemon is a
  -- worse failure than a whole one.
  local wide = { getWidth = function() return 200 end }
  ok(Gen4Battle.monWindowClip(fake, Gen4Battle.BATTLER_POS[0], wide) == nil,
     "...and a picture too wide for the window is left unclipped",
     tostring(Gen4Battle.monWindowClip(fake, Gen4Battle.BATTLER_POS[0], wide)),
     "nil")
  player.monWindowRect = nil
  ok(Gen4Battle.monWindowClip(fake, Gen4Battle.BATTLER_POS[1], pic) == nil,
     "...and with no window up there is no clip", "nil", "nil")
  player.playing = false
end

-- THE SLOTS ARE CLEARED PER RUN. A copy left live keeps answering `monHidden` for
-- a move that has finished, which would make the NEXT move's hidden battler draw.
do
  player:start(464, true)
  local n = 0
  while player:update() and n < 400 do n = n + 1 end
  player:stop()
  ok(player.monWindowRect == nil,
     "no window survives the end of a program", tostring(player.monWindowRect),
     "nil")
  -- !! INTERRUPTED MID-RUN, and the first version of this was a measurement that
  -- could not fail. Running 464 to its end and then starting another program tests
  -- nothing: `clearTransforms` has already emptied the slots, so `start` could
  -- inherit them and the count would still be zero. A plant that made `start` keep
  -- whatever was there passed. Taken onto a run ABANDONED with slots live, which is
  -- the state a program that never reaches `freepokemonspritemanager` leaves behind.
  player:start(464, true)
  local mid = 0
  while player:update() and mid < 40 do mid = mid + 1 end
  local live = 0
  for _ in pairs(player.monSprites or {}) do live = live + 1 end
  ok(live > 0, "a run abandoned mid-animation still holds its slots", live,
     "more than none")
  player:start(1, true)
  local fresh = 0
  for _ in pairs(player.monSprites or {}) do fresh = fresh + 1 end
  ok(fresh == 0, "...and the next program starts with none of them", fresh, 0)
  player:stop()
end

-- THE LCRNG IS THE CARTRIDGE'S RECURRENCE, not a generator chosen to look random.
do
  local state, value = PL.lcrngStep(0)
  ok(state == PL.LCRNG_ADD and value == floorDiv(PL.LCRNG_ADD / 65536),
     "from zero the state is the increment and the value its top half",
     ("%d, %d"):format(state, value),
     ("%d, %d"):format(PL.LCRNG_ADD, floorDiv(PL.LCRNG_ADD / 65536)))
  ok(PL.LCRNG_MUL == 1103515245 and PL.LCRNG_ADD == 24691,
     "...with pret's own multiplier and increment",
     ("%d, %d"):format(PL.LCRNG_MUL, PL.LCRNG_ADD), "1103515245, 24691")
  -- EXACT 32-BIT ARITHMETIC IN A DOUBLE, which is why the multiply is done in two
  -- halves: a single `state * 1103515245` for a full 32-bit state is 4.7e18 and
  -- loses its low bits, and the low bits are the whole output.
  local s2 = PL.lcrngStep(0x12345678)
  ok(s2 == (0x12345678 * 1103515245 + 24691) % 4294967296
     or s2 == math.fmod(math.fmod(0x5678 * 1103515245, 4294967296)
                        + math.fmod(0x1234 * 1103515245 % 65536 * 65536, 4294967296)
                        + 24691, 4294967296),
     "...and a 32-bit state steps without losing its low bits", s2,
     "the exact product mod 2^32")
  local seen, s = {}, 0
  for _ = 1, 64 do
    local v
    s, v = PL.lcrngStep(s)
    seen[v % 2] = true
  end
  ok(seen[0] and seen[1], "and its low bit is not stuck", "both values", "both")
end

io.write(("\n%d checks, %d failures\n"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
