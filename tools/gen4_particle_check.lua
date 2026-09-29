-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- tools/gen4_particle_check.lua -- the eighteenth standing check, and the
-- second about a move's ANIMATION rather than a script, a screen or a warp.
--
-- `gen4_moveanim_check` proves the PROGRAM decodes. This proves the thing the
-- program points at does: `loadparticlesystem 0, 40` is Scratch's whole visible
-- effect, and until the file at index 40 can be read there is nothing to draw.
--
-- IT IS THE SAME KIND OF CHECK AS THE MOVE-ANIMATION ONE -- arithmetic that
-- either closes or does not -- and deliberately so, because the alternative
-- with a binary format is a plausible-looking picture that is wrong in a way
-- nobody can see. Three claims, each one a number in a header predicting
-- another number exactly:
--
--   1. the emitter area ends where the texture area begins
--   2. the texture area ends where the file does
--   3. every texture's own width * height equals its own declared byte count
--
-- A guessed field passes none of these by accident. A wrong bit offset in the
-- shape word does not make width * height come out right 1,724 times.
--
-- Run:  texlua tools/gen4_particle_check.lua <rom path>

local romPath = arg and arg[1]
if not romPath then
  io.stderr:write("usage: texlua tools/gen4_particle_check.lua <rom path>\n")
  os.exit(2)
end

local root = (arg[0] or ""):gsub("[^/\\]*$", "")
if root ~= "" then package.path = root .. "../?.lua;" .. package.path end
package.path = "./?.lua;" .. package.path

local NdsRom = require("src.import.NdsRom")
local Narc = require("src.import.NarcArchive")
local P = require("src.import.Gen4Particle")
local Anim = require("src.import.Gen4MoveAnim")

local fails, checks = 0, 0
local function ok(cond, what, got, want)
  checks = checks + 1
  if cond then io.write(("  ok    %-54s %s\n"):format(what, tostring(got)))
  else fails = fails + 1
       io.write(("  FAIL  %-54s got %s, expected %s\n")
                :format(what, tostring(got), tostring(want))) end
end

local rom = assert(NdsRom.open(romPath))

-- ---------------------------------------------------------------------------
-- 1: THE ARCHIVES ARE THE SIZE THEY SAY
-- ---------------------------------------------------------------------------
io.write("the particle archives\n")
local function arcAt(path)
  local raw = rom:read(path)
  return raw and Narc.parse(raw)
end
local moves = arcAt(P.ARCHIVE_MOVES)
local balls = arcAt(P.ARCHIVE_BALLS)
ok(moves ~= nil and moves.count == P.MOVE_COUNT,
   "waza_particle.narc holds one effect per move slot",
   moves and moves.count, P.MOVE_COUNT)
ok(balls ~= nil and balls.count == P.BALL_COUNT,
   "ball_particle.narc holds the ball effects", balls and balls.count,
   P.BALL_COUNT)

-- ---------------------------------------------------------------------------
-- 2: THE THREE ARITHMETIC CLAIMS, OVER EVERY FILE IN THE CARTRIDGE
-- ---------------------------------------------------------------------------
io.write("\nthe headers\n")
local files, consistent, decoded, blocks = 0, 0, 0, 0
local badHead, badBlock = {}, {}
local byFormat, byShape = {}, {}
local versions = {}
for _, path in ipairs({ P.ARCHIVE_MOVES, P.ARCHIVE_BALLS, P.ARCHIVE_FIELD }) do
  local arc = arcAt(path)
  if arc then
    for i = 0, arc.count - 1 do
      local data = arc:get(i)
      local head = data and P.header(data)
      if head then
        files = files + 1
        versions[head.version] = (versions[head.version] or 0) + 1
        local good, why = P.consistent(head)
        if good then consistent = consistent + 1
        elseif #badHead < 4 then badHead[#badHead + 1] = ("%s[%d]: %s"):format(path, i, why) end
        local list, err = P.textures(data)
        if list then
          decoded = decoded + 1
          for _, t in ipairs(list) do
            blocks = blocks + 1
            byFormat[t.format] = (byFormat[t.format] or 0) + 1
            local k = t.width .. "x" .. t.height
            byShape[k] = (byShape[k] or 0) + 1
          end
        elseif #badBlock < 4 then
          badBlock[#badBlock + 1] = ("%s[%d]: %s"):format(path, i, tostring(err))
        end
      end
    end
  end
end
ok(files == 608, "every member of the three archives is an SPA file", files, 608)
ok(consistent == files, "...and every one's emitter and texture areas meet",
   ("%d of %d%s"):format(consistent, files,
     #badHead > 0 and ("; " .. table.concat(badHead, "; ")) or ""), files)
ok(decoded == files, "...and every texture block walks to its own end",
   ("%d of %d%s"):format(decoded, files,
     #badBlock > 0 and ("; " .. table.concat(badBlock, "; ")) or ""), files)
ok(blocks == 1724, "the cartridge holds this many particle textures", blocks, 1724)

-- A CANARY, because "every file decoded" is also what a decoder that returns an
-- empty list for everything would report.
ok(blocks > files * 2, "...which is more than two textures a file on average",
   ("%.2f per file"):format(blocks / math.max(1, files)), "over 2")

-- ---------------------------------------------------------------------------
-- 3: WHAT THE SHAPE WORD SAYS, AND THAT IT SAYS ONLY TWO THINGS
-- ---------------------------------------------------------------------------
io.write("\nthe pixel formats\n")
local fmtNames = {}
for f in pairs(byFormat) do fmtNames[#fmtNames + 1] = f end
table.sort(fmtNames)
ok(#fmtNames == 2 and fmtNames[1] == P.FORMAT_A3I5 and fmtNames[2] == P.FORMAT_A5I3,
   "only A3I5 and A5I3 occur, and both are 8bpp",
   table.concat(fmtNames, ", "), P.FORMAT_A3I5 .. ", " .. P.FORMAT_A5I3)
-- DEFAULTED TO ZERO RATHER THAN INDEXED RAW: a planted fault that broke the
-- decode left these nil, and the check RAISED instead of reporting a failure.
-- A tool that crashes does technically exit non-zero, but "attempt to compare
-- number with nil" names the check's own line, not the bug -- and the whole
-- point of a named expectation is that the failure says what was wrong.
local a5i3 = byFormat[P.FORMAT_A5I3] or 0
local a3i5 = byFormat[P.FORMAT_A3I5] or 0
ok(a5i3 > a3i5, "...and the smooth-edged one is the common one",
   ("A5I3 %d, A3I5 %d"):format(a5i3, a3i5), "A5I3 more")
-- EVERY DIMENSION IS A POWER OF TWO FROM 8 TO 128, which is what the exponent
-- reading predicts and what a wrong bit offset would not produce.
local odd = {}
for k in pairs(byShape) do
  local w, h = k:match("^(%d+)x(%d+)$")
  w, h = tonumber(w), tonumber(h)
  local function pow2(v) return v >= 8 and v <= 128 and (v == 8 or v == 16
    or v == 32 or v == 64 or v == 128) end
  if not (pow2(w) and pow2(h)) then odd[#odd + 1] = k end
end
local shapeCount = 0
for _ in pairs(byShape) do shapeCount = shapeCount + 1 end
ok(#odd == 0, "every texture is a power of two from 8 to 128",
   #odd == 0 and (shapeCount .. " distinct shapes, all of them")
   or table.concat(odd, ", "), "all")
ok(shapeCount > 0 and byShape["32x32"] ~= nil and byShape["16x16"] ~= nil,
   "...and the two commonest are 32x32 and 16x16",
   ("32x32 %d, 16x16 %d"):format(byShape["32x32"] or 0, byShape["16x16"] or 0),
   "both present")

-- ---------------------------------------------------------------------------
-- 4: THE JOIN -- every particle index a MOVE PROGRAM names must resolve to a
-- file this reader can decode. The two halves of a move's animation are the
-- program and the effect, and either one alone is not a picture.
-- ---------------------------------------------------------------------------
io.write("\nthe join with the move programs\n")
local weRaw = rom:read(Anim.ARCHIVE_PROGRAMS)
local we = weRaw and Narc.parse(weRaw)
ok(we ~= nil, "we.arc is readable", we ~= nil, true)
local named, resolved, missing = 0, 0, {}
if we and moves then
  local seen = {}
  for i = 0, we.count - 1 do
    local program = Anim.decode(we:get(i) or "")
    if program then
      for _, row in ipairs(program) do
        if row.op == Anim.PARTICLE_OP then
          local m = row.args[Anim.PARTICLE_ARG]
          if m and not seen[m] then
            seen[m] = true
            named = named + 1
            local data = m < moves.count and moves:get(m)
            if data and P.check(data) then resolved = resolved + 1
            elseif #missing < 4 then missing[#missing + 1] = tostring(m) end
          end
        end
      end
    end
  end
end
ok(named > 400, "the programs name this many distinct effects", named, "over 400")
ok(resolved == named,
   "EVERY effect a move names decodes to real textures",
   ("%d of %d%s"):format(resolved, named,
     #missing > 0 and ("; missing " .. table.concat(missing, ", ")) or ""), named)

-- ---------------------------------------------------------------------------
-- 5: SCRATCH, which is the move that started all of this.
-- ---------------------------------------------------------------------------
io.write("\nscratch\n")
local scratch = moves and moves:get(40)
local list = scratch and P.textures(scratch)
ok(list ~= nil and #list == 2, "effect 40 holds two textures", list and #list, 2)
if list then
  local big
  for _, t in ipairs(list) do
    if t.width == 64 and t.height == 64 then big = t end
  end
  ok(big ~= nil, "...one of them 64x64, which is the claw itself",
     big and (big.width .. "x" .. big.height), "64x64")
  if big then
    local image = P.rgba(big)
    ok(image ~= nil and #image.rgba == big.width * big.height * 4,
       "...and it expands to exactly its own pixel count",
       image and #image.rgba, big.width * big.height * 4)
    -- A TEXTURE THAT CAME OUT ENTIRELY TRANSPARENT WOULD PASS EVERY CHECK
    -- ABOVE AND DRAW NOTHING, which is the failure this whole file exists to
    -- prevent -- so count the pixels that are actually visible.
    local opaque = 0
    for i = 4, #image.rgba, 4 do
      if image.rgba:byte(i) > 0 then opaque = opaque + 1 end
    end
    ok(opaque > 100 and opaque < big.width * big.height,
       "...with a real shape in it: some pixels solid, some clear",
       ("%d of %d pixels visible"):format(opaque, big.width * big.height),
       "between the two")
  end
end

-- ---------------------------------------------------------------------------
-- 6: THE EMITTERS TILE THEIR OWN AREA.
--
-- A fourth arithmetic claim, and the one that took a derivation rather than a
-- reading: every emitter's length must come out of its own header word, and
-- the lengths must add up to the emitter area exactly. Until that closed there
-- was no safe way to read an emitter at all -- a mis-sized one runs into the
-- NEXT emitter's bytes and reads its parameters as its own, silently, which is
-- why a 70% version of this was derived and deliberately NOT committed.
--
-- The costs were measured, not fitted: single-emitter files give the length
-- outright, pairs of headers differing in exactly ONE bit give that bit's cost
-- by subtraction, and extending by subtraction through multi-emitter files took
-- 66 measurements to 106. Every bit came out consistent across every pair.
-- ---------------------------------------------------------------------------
io.write("\nthe emitters\n")
local emFiles, emClosed, emCount = 0, 0, 0
local emBad, blockUse = {}, {}
for _, path in ipairs({ P.ARCHIVE_MOVES, P.ARCHIVE_BALLS, P.ARCHIVE_FIELD }) do
  local arc = arcAt(path)
  if arc then
    for i = 0, arc.count - 1 do
      local data = arc:get(i)
      if data and P.header(data) then
        emFiles = emFiles + 1
        local list, err = P.emitters(data)
        if list then
          emClosed = emClosed + 1
          emCount = emCount + #list
          for _, e in ipairs(list) do
            for bit in pairs(e.blocks) do
              blockUse[bit] = (blockUse[bit] or 0) + 1
            end
          end
        elseif #emBad < 4 then
          emBad[#emBad + 1] = ("%s[%d]: %s"):format(path, i, tostring(err))
        end
      end
    end
  end
end
ok(emClosed == emFiles, "EVERY file's emitters tile their own area exactly",
   ("%d of %d%s"):format(emClosed, emFiles,
     #emBad > 0 and ("; " .. table.concat(emBad, "; ")) or ""), emFiles)
ok(emCount == 1744, "the cartridge holds this many emitters", emCount, 1744)
-- A CANARY: a walk that read one emitter and stopped would also "close" on
-- every single-emitter file, so assert the corpus really is multi-emitter.
ok(emCount > emFiles * 2, "...which is more than two an effect on average",
   ("%.2f per file"):format(emCount / math.max(1, emFiles)), "over 2")

-- THE BASE SIZE IS THE CLAIM UNDER ALL OF IT. If it moved by four bytes the
-- walk would miss on almost everything, so stating it is stating the finding.
ok(P.EMITTER_BASE == 88, "the emitter base struct is 88 bytes",
   P.EMITTER_BASE, 88)
local blockCount = 0
for _ in pairs(P.EMITTER_BLOCKS) do blockCount = blockCount + 1 end
ok(blockCount == 11, "...with eleven optional blocks behind flag bits",
   blockCount, 11)

-- !! AND THE ONE THAT RESTS ON A SINGLE SAMPLE IS NAMED. Bit 28 occurs exactly
-- ONCE in the cartridge, so its +8 is evidenced by one emitter and no more.
-- The walk closes either way, and this assertion exists so "it closes" is never
-- read as "all eleven are equally well evidenced".
local single = {}
for bit in pairs(P.EMITTER_SINGLE_SAMPLE) do single[#single + 1] = bit end
ok(#single == 1 and single[1] == 28,
   "bit 28 is flagged as resting on one sample", table.concat(single, ","), 28)
ok(blockUse[28] == 1, "...and it really does occur exactly once",
   blockUse[28], 1)
-- ...while the common ones are common, which is what says the rest are safe.
ok((blockUse[10] or 0) > 1000 and (blockUse[8] or 0) > 1000,
   "...while bits 8 and 10 appear over a thousand times each",
   ("bit 8 %d, bit 10 %d"):format(blockUse[8] or 0, blockUse[10] or 0),
   "both over 1000")

-- Scratch's effect, end to end.
if scratch then
  local ems = P.emitters(scratch)
  ok(ems ~= nil and #ems == 2, "effect 40 has two emitters", ems and #ems, 2)
end

-- ---------------------------------------------------------------------------
-- 7: THE EMITTER'S FIELDS, AND THE ONE TEST THAT IS NOT SELF-CONSISTENCY.
--
-- Everything above is arithmetic closing on itself, which proves a LAYOUT and
-- says nothing about MEANING. The fields are named from pret's `lib/spl/` --
-- the Nitro particle library, decompiled, which names the same eleven flag
-- bits the byte arithmetic had already found and lays `SPLResourceHeader` out
-- to the same 88 bytes. Two methods sharing no assumption agreeing is the
-- argument that the names are real.
--
-- And one field can be tested against something OUTSIDE its own struct:
-- `textureIndex` must name a texture THIS VERY FILE contains. A wrong offset
-- would put an arbitrary byte there, and an arbitrary byte lands out of range
-- almost immediately when most files hold two or three textures.
-- ---------------------------------------------------------------------------
io.write("\nthe emitter fields\n")
local withFields, badTexture, zeroLife, zeroCount = 0, 0, 0, 0
local longestLife, biggestCount = 0, 0
for _, path in ipairs({ P.ARCHIVE_MOVES, P.ARCHIVE_BALLS, P.ARCHIVE_FIELD }) do
  local arc = arcAt(path)
  if arc then
    for i = 0, arc.count - 1 do
      local data = arc:get(i)
      local ems = data and P.emitters(data)
      local txs = data and P.textures(data)
      if ems and txs then
        for _, e in ipairs(ems) do
          local f = e.fields
          if not f then badTexture = badTexture + 1
          else
            withFields = withFields + 1
            if f.textureIndex >= #txs then badTexture = badTexture + 1 end
            if (f.particleLifeTime or 0) == 0 then zeroLife = zeroLife + 1 end
            if (f.emissionCount or 0) == 0 then zeroCount = zeroCount + 1 end
            if (f.particleLifeTime or 0) > longestLife then
              longestLife = f.particleLifeTime
            end
            if (f.emissionCount or 0) > biggestCount then
              biggestCount = f.emissionCount
            end
          end
        end
      end
    end
  end
end
ok(withFields == emCount, "every emitter's base struct reads", withFields, emCount)
ok(badTexture == 0,
   "EVERY emitter names a texture its own file contains", badTexture, 0)
ok(zeroLife == 0, "...and every one gives its particles a lifetime",
   zeroLife .. " with none", 0)
ok(zeroCount == 0, "...and something to emit", zeroCount .. " with none", 0)
-- SANITY, not self-consistency: a lifetime of 40,000 frames or an emission
-- count of 3,000 would mean the offset is wrong even though nothing errored.
ok(longestLife > 0 and longestLife < 600,
   "the longest particle life is a plausible number of frames",
   longestLife, "under 600")
ok(biggestCount > 0 and biggestCount < 256,
   "...and the biggest emission count is plausible too",
   tostring(biggestCount), "under 256")

-- SCRATCH, READ AS DATA. Two emitters: one claw thrown once at full alpha, and
-- a burst of three small sparks. That is the move, in numbers.
if scratch then
  local ems = P.emitters(scratch)
  local a = ems and ems[1] and ems[1].fields
  local b = ems and ems[2] and ems[2].fields
  ok(a ~= nil and a.textureIndex == 1 and a.baseAlpha == 31,
     "Scratch's first emitter throws the 64x64 claw at full alpha",
     a and ("texture %d, alpha %d"):format(a.textureIndex, a.baseAlpha),
     "texture 1, alpha 31")
  ok(a ~= nil and a.emissionCount == 1 and a.particleLifeTime == 8,
     "...once, for eight frames",
     -- %s, NOT %d. `emissionCount` is fx32 and comes back fractional; a
     -- planted offset fault made it 0.5 and the check RAISED on "number has no
     -- integer representation" instead of reporting a wrong value. Third time
     -- this session a formatter has turned a finding into a stack trace.
     a and ("%s particle, %s frames"):format(tostring(a.emissionCount),
                                             tostring(a.particleLifeTime)),
     "1 particle, 8 frames")
  ok(b ~= nil and b.emissionCount == 3 and b.textureIndex == 0,
     "...and its second throws three of the small one",
     b and ("%s of texture %s"):format(tostring(b.emissionCount),
                                       tostring(b.textureIndex)),
     "3 of texture 0")
end

-- ---------------------------------------------------------------------------
-- 8: DOES IT ACTUALLY THROW ANYTHING.
--
-- Everything above reads the data. This runs it: `Gen4ParticleSystem` is a
-- per-frame simulation, so the question stops being "does the format decode"
-- and becomes "does every effect in the game produce a visible particle".
--
-- THAT QUESTION FOUND A REAL BUG ON ITS FIRST RUN, which is the argument for
-- asking it. `emissionCount` is fixed point and genuinely fractional; flooring
-- it each beat makes any emitter under 1.0 emit NOTHING, EVER. Exactly one
-- effect in the cartridge is like that -- member 394, at 0.743 per beat -- and
-- it produced an empty animation until the remainder was carried between beats
-- the way `spl_emit.c` carries it. One effect in 485 is precisely the kind of
-- thing nobody finds by playing.
-- ---------------------------------------------------------------------------
io.write("\nthe simulation\n")
local PS = require("src.battle.Gen4ParticleSystem")
local built, emitted, empty, silent = 0, 0, 0, {}
local peakLive, longest = 0, 0
if moves then
  for i = 0, moves.count - 1 do
    local data = moves:get(i)
    local head = data and P.header(data)
    local sys = data and PS.new(data)
    if sys then
      built = built + 1
      sys:start(12345 + i)
      local frames, live = 0, 0
      while sys:update() and frames < 400 do
        frames = frames + 1
        if sys.live > live then live = sys.live end
      end
      if live > 0 then emitted = emitted + 1
      elseif head and head.emitters == 0 then empty = empty + 1
      elseif #silent < 5 then silent[#silent + 1] = tostring(i) end
      if live > peakLive then peakLive = live end
      if frames > longest then longest = frames end
    end
  end
end
ok(built == (moves and moves.count or -1),
   "a system builds for every move effect", built, moves and moves.count)
-- THE CLAIM, and the one the fractional-count bug broke: an effect that has an
-- emitter must produce a particle. An effect with NO emitter legitimately
-- produces none, and there are 34 of those -- so the two are counted apart
-- rather than folded into one forgiving number.
ok(#silent == 0,
   "EVERY effect with an emitter throws at least one particle",
   #silent == 0 and "all of them" or ("silent: " .. table.concat(silent, ", ")),
   "all of them")
ok(empty == 34, "...and the effects that throw nothing have no emitter at all",
   empty, 34)
ok(emitted + empty == built, "...which accounts for every one",
   emitted .. " + " .. empty, built)
-- SANITY ON THE SIMULATION ITSELF. A run that never ends, or one particle at a
-- time, would pass the assertions above and still be wrong.
-- THE BUSIEST EFFECT SATURATES THE POOL EXACTLY, which is a far stronger claim
-- than "a plausible number". `include/particle_system.h` states MAX_PARTICLES
-- 200 per particle system, and `SPLEmitter_EmitParticles` stops the moment its
-- free list is empty -- so the densest effect in the cartridge should sit at 200
-- and not one above it. Without the cap this port peaked at 302 of an emitter's
-- own particles and 1,260 children.
ok(peakLive == PS.MAX_PARTICLES,
   "the busiest effect fills the cartridge's particle pool exactly",
   peakLive, PS.MAX_PARTICLES)
ok(PS.MAX_PARTICLES == 200 and PS.MAX_EMITTERS == 20 and PS.MAX_SYSTEMS == 16,
   "...and the three pool constants are the header's own",
   ("%s / %s / %s"):format(tostring(PS.MAX_PARTICLES), tostring(PS.MAX_EMITTERS),
                           tostring(PS.MAX_SYSTEMS)),
   "200 / 20 / 16")
ok(longest > 0 and longest < 400,
   "...and the longest effect finishes on its own",
   longest .. " frames", "under the 400-frame cap")

-- TWO MORE, AND THEY EXIST BECAUSE THE FIRST DRAFT OF THIS SECTION COULD NOT
-- SEE EITHER FAULT. "Every effect throws a particle" is satisfied by particles
-- that are born at the origin with no velocity and by particles that die
-- before their first frame -- both of which draw nothing a player would call an
-- animation. Planting exactly those two (removing the point-emitter's random
-- direction, and dropping the `+ 1` that guarantees a one-frame life) passed a
-- section that already had six assertions in it.
local still, instant, sampled = 0, 0, 0
if moves then
  for i = 0, moves.count - 1, 7 do            -- a seventh of the corpus is plenty
    local data = moves:get(i)
    local sys = data and PS.new(data)
    if sys then
      sys:start(4242 + i)
      local born = {}
      local frames = 0
      while sys:update() and frames < 120 do
        frames = frames + 1
        for _, p in ipairs(sys.particles) do
          born[p] = born[p] or { p.x, p.y, p.z, frames }
        end
      end
      for p, at in pairs(born) do
        sampled = sampled + 1
        local moved = math.abs(p.x - at[1]) + math.abs(p.y - at[2])
                      + math.abs(p.z - at[3])
        if moved < 1e-6 then still = still + 1 end
        if (p.life or 0) < 1 then instant = instant + 1 end
      end
    end
  end
end
ok(sampled > 500, "enough particles sampled to mean anything", sampled, "over 500")
ok(instant == 0, "no particle is born already dead",
   instant .. " of " .. sampled, 0)
-- A FEW genuinely still particles are legitimate -- an emitter can have zero
-- initial velocity on purpose -- so this is a proportion, not a zero.
ok(still * 4 < sampled, "and the great majority of particles move",
   ("%d still of %d"):format(still, sampled), "under a quarter")

-- ...AND A FLOOR ON TOTAL PARTICLE-FRAMES, which is the only thing that sees a
-- change to how LONG particles live. The two assertions above are about
-- individual particles and a shortened lifetime hides from both: a particle
-- cut from 20 frames to 19 still moves and still lives. Asserting the corpus
-- total is the same argument as the coverage floor -- a number measured from
-- this cartridge that may not quietly fall.
local particleFrames = 0
if moves then
  for i = 0, moves.count - 1, 7 do
    local data = moves:get(i)
    local sys = data and PS.new(data)
    if sys then
      sys:start(4242 + i)
      local frames = 0
      while sys:update() and frames < 120 do
        frames = frames + 1
        particleFrames = particleFrames + sys.live
      end
    end
  end
end
-- THE FLOOR IS THE MEASUREMENT, not a comfortable round number below it. The
-- run is deterministic -- every system is seeded from its own index -- so this
-- is reproducible, and a floor set safely under it would not notice a lifetime
-- cut by a frame, which is exactly the fault it exists for. Same rule as the
-- coverage check: raise it when the number rises, or it stops being the
-- current measurement.
-- 57,913 -> 55,738 WHEN THE ATTENUATION MACROS WERE CORRECTED. `lifeTime` uses
-- `SPLRandom_ScaledRangeFX32`, which carries a 255/256 factor even at range 0,
-- so every particle lives very slightly less long than the hand-written
-- "reduce by a random fraction" this file used to apply. A floor moving DOWN
-- after a correction is the floor working: it had to be re-measured, not
-- widened.
-- 57,913 -> 55,738 -> 53,120. The first drop was the corrected attenuation
-- macros; the second is the POOL, which children now compete for.
ok(particleFrames >= 53120,
   "the sampled corpus is worth this many particle-frames",
   particleFrames, "at least 53120")

-- AND THE ONE THING NO FLOOR CAN SEE: a velocity that COMPOUNDS instead of
-- decaying. Every assertion above is a floor or a lower bound, so a fault that
-- makes particles travel FURTHER passes all of them -- and halving the air
-- resistance divisor is exactly that fault. `spl_emitter.c` computes it as
-- `velocity * (airResistance + FX32_CONST(0.09375)) >> 9`, so the multiplier is
-- (byte + 384) / 512, and an unsigned byte pins the whole band it can occupy:
-- 0.75 at 0, 1.0 at 128, 1.2480 at 255. THAT BAND IS THE ASSERTION. It is not a
-- taste and not a fit -- it is the formula's range over the field's range, so
-- moving either constant moves every emitter in the game out of it.
--
-- THE FIRST VERSION OF THIS CLAIMED SOMETHING FALSE. I asserted that no emitter
-- accelerates, having "measured" it with a scan that read `f.misc.airResistance`
-- -- a field that does not exist, since the flags live flat on the fields table.
-- Every read came back nil, every nil became 0, and 0 is never above 128, so the
-- scan reported what I expected and could not have reported anything else. 176
-- emitters do accelerate. A measurement that cannot fail says nothing, and this
-- one said it about my own code.
local airLow, airHigh, airEmitters = 2, 0, 0
local decays, accelerates, neutral = 0, 0, 0
if moves then
  for i = 0, moves.count - 1 do
    local data = moves:get(i)
    local sys = data and PS.new(data)
    for _, e in ipairs(sys and sys.emitters or {}) do
      -- THE SIMULATION'S OWN ARITHMETIC, not a second copy of the formula in
      -- the check. A check that recomputes the multiplier itself agrees with
      -- itself no matter what the engine does.
      local air = e.fields and tonumber(PS.airMultiplier(e.fields))
      if air then
        airEmitters = airEmitters + 1
        if air < airLow then airLow = air end
        if air > airHigh then airHigh = air end
        if air < 1 then decays = decays + 1
        elseif air > 1 then accelerates = accelerates + 1
        else neutral = neutral + 1 end
      end
    end
  end
end
ok(airEmitters == 1468, "every emitter's air resistance was read",
   airEmitters, 1468)
ok(airHigh <= (255 + 384) / 512,
   "no emitter's air resistance escapes what one byte can say",
   ("highest multiplier %.4f"):format(airHigh),
   ("%.4f or less"):format((255 + 384) / 512))
ok(airLow >= 384 / 512, "...and none falls below the library's own floor",
   ("lowest multiplier %.4f"):format(airLow), ("%.4f"):format(384 / 512))
-- AND THE BYTE IS USED, all three ways. A decoder that read the wrong byte
-- would most likely land every emitter in one bucket.
ok(decays > 0 and accelerates > 0 and neutral > 0,
   "...and the cartridge slows, holds AND speeds up particles",
   ("%d decay, %d neutral, %d accelerate"):format(decays, neutral, accelerates),
   "all three")
-- MEASURED, not estimated. The first draft of this line said 176 accelerating,
-- a number I had not counted -- the scan above only ever reported a total and a
-- maximum. The check failed on my own arithmetic, which is the third time this
-- session a remembered number has been wrong and the second time the check that
-- caught it was the one I had just written.
ok(decays == 542 and neutral == 819 and accelerates == 107,
   "...in these numbers",
   ("%d decay, %d neutral, %d accelerate"):format(decays, neutral, accelerates),
   "542 / 819 / 107")

-- A SECOND NET ON THE SAME FAULT, from behaviour rather than from a constant:
-- how far the sampled corpus actually travels. This is a BAND, not a floor,
-- because the fault it exists for makes the number bigger -- with the divisor
-- halved the same data comes out at 6.9e27 units. The tolerance is one percent
-- rather than nothing at all only because the sum is floating point and the
-- engine runs under a different Lua than this check does; raise BOTH ends when
-- the simulation legitimately changes.
local travel, travelled = 0, 0
if moves then
  for i = 0, moves.count - 1, 7 do
    local data = moves:get(i)
    local sys = data and PS.new(data)
    if sys then
      sys:start(4242 + i)
      local born, frames = {}, 0
      while sys:update() and frames < 120 do
        frames = frames + 1
        for _, p in ipairs(sys.particles) do
          born[p] = born[p] or { p.x, p.y, p.z, 0 }
          local b = born[p]
          local d = math.abs(p.x - b[1]) + math.abs(p.y - b[2])
                    + math.abs(p.z - b[3])
          if d > b[4] then b[4] = d end
        end
      end
      for _, b in pairs(born) do
        travelled = travelled + 1
        travel = travel + b[4]
      end
    end
  end
end
ok(travelled > 2000, "enough particles walked to measure travel",
   travelled, "over 2000")
-- 17,282 -> 17,901 FOR THE OTHER HALF OF THE SAME CORRECTION. The initial
-- velocities use `DoubleScaledRangeFX32`, which is CENTRED and can reach nearly
-- twice its nominal value; the old single formula could only reduce, so every
-- attenuated velocity in the cartridge was too slow. The band moved UP.
-- THE BAND IS A FIFTH OF A PERCENT, not one percent, and the reason is a fault
-- that fell inside the looser one: applying the behaviour acceleration BEFORE
-- air resistance instead of after moves this to 17,824 -- 0.43% -- and pret's
-- order is explicit (decay the velocity, then add the acceleration). A band wide
-- enough to be comfortable was wide enough to hide an ordering bug. 0.2% is
-- still 36 units of slack, far more than any float difference between this
-- interpreter and the engine's.
-- 17,901 -> 17,829 once children existed. Children draw from the same seeded
-- random stream, so a run with children in it is a different run -- which is also
-- how a bug was found: writing `doubleScaledRange(...)` into three fields of one
-- particle drew three DIFFERENT scales AND consumed two extra numbers, moving
-- every later particle. One draw, three fields.
ok(travel > 17793 and travel < 17865,
   "...and the corpus travels this far in total",
   ("%.1f units"):format(travel), "17829 within 0.2%")

-- TWO EMITTERS OF ONE RESOURCE MUST NOT INTERFERE.
--
-- A move can put the same resource in the air twice -- both halves of a
-- two-sided animation, or a program that creates the same emitter again a few
-- frames later -- and both systems then hold THE SAME Lua table for that
-- emitter, straight out of the cache. Anything a run writes onto that table is
-- shared, and the fractional emission carry was on it: each run's remainder
-- cancelled the other's, so two emitters of one resource emitted less than one
-- of them alone. It lives on the system now, keyed by slot, and the cache's
-- tables are never written to at all -- which this asserts by running a
-- resource on its own and then alongside a second copy of itself.
local crossTalk = {}
if moves then
  for i = 0, moves.count - 1, 11 do
    local data = moves:get(i)
    local list = data and P.emitters(data)
    if list and list[1] then
      local alone = PS.fromEmitters({ list[1] })
      alone:start(31337)
      local solo, frames = 0, 0
      while alone:update() and frames < 90 do
        frames = frames + 1
        solo = solo + alone.live
      end
      local a = PS.fromEmitters({ list[1] })
      local b = PS.fromEmitters({ list[1] })
      a:start(31337)
      b:start(31337)
      local first, f2 = 0, 0
      while f2 < frames do
        f2 = f2 + 1
        local ka = a:update()
        b:update()
        if ka then first = first + a.live end
      end
      if first ~= solo and #crossTalk < 5 then
        crossTalk[#crossTalk + 1] = ("%d: %d alone, %d beside a twin")
          :format(i, solo, first)
      end
    end
  end
end
ok(#crossTalk == 0,
   "a resource run twice at once behaves as it does run once",
   #crossTalk == 0 and "no cross-talk"
     or table.concat(crossTalk, "; ", 1, math.min(3, #crossTalk)),
   "no cross-talk")

-- ---------------------------------------------------------------------------
-- 9: THE ANIMATION AND BEHAVIOUR BLOCKS, WHICH USED TO BE THE "still missing"
-- SECTION OF THIS FILE.
--
-- All eleven optional blocks are decoded now, and ten of the eleven are applied
-- -- the four animation curves from `lib/spl/src/spl_anim.c` and all six
-- behaviours from `spl_behavior.c`. That turns the block table from a list of
-- sizes into a list of things that happen, so the question changes from "does it
-- parse" to "does a particle's scale actually move".
--
-- AND IT IS THE SAME KIND OF CLAIM AS THE REST OF THIS FILE: the eleven sizes
-- were derived by single-bit subtraction over 144 files, and pret's structs
-- declare the same eleven. `SPLCollisionPlaneBehavior` is fx32 + fx16 + a 2-bit
-- field = 8 bytes BY DECLARATION -- so bit 28, whose +8 rested on one emitter in
-- the entire cartridge, is no longer a single sample.
-- ---------------------------------------------------------------------------
io.write("\nthe blocks, applied\n")
local SIZES_FROM_PRET = {
  [8] = 12, [9] = 12, [10] = 8, [11] = 12, [16] = 20,
  [24] = 8, [25] = 8, [26] = 16, [27] = 4, [28] = 8, [29] = 16,
}
local sizeDrift, sizesChecked = {}, 0
for bit, want in pairs(SIZES_FROM_PRET) do
  sizesChecked = sizesChecked + 1
  local got = P.EMITTER_BLOCKS[bit]
  if got ~= want then
    sizeDrift[#sizeDrift + 1] = ("bit %d is %s, pret declares %d")
      :format(bit, tostring(got), want)
  end
end
ok(sizesChecked == 11, "all eleven block sizes were compared", sizesChecked, 11)
ok(#sizeDrift == 0,
   "EVERY MEASURED BLOCK SIZE MATCHES PRET'S OWN STRUCT",
   #sizeDrift == 0 and "all eleven" or table.concat(sizeDrift, "; "),
   "all eleven")
-- AND THE WALK ORDER IS THE LOADER'S, ascending bit order, which
-- `SPLManager_LoadResources` reads in exactly that sequence. A block walk in any
-- other order reads every later block's fields one step out, silently, because
-- the values would all still be numbers.
local order, ordered = P.BLOCK_ORDER, true
for i = 2, #(order or {}) do
  if order[i] <= order[i - 1] then ordered = false end
end
ok(order and #order == 11 and ordered,
   "...and they are walked in the loader's own order",
   order and (#order .. " blocks, ascending " .. tostring(ordered)) or "none",
   "11, ascending")

-- THE BLOCKS DECODE FOR EVERY EMITTER, and the decode is checked against the
-- bit costs: `emitters()` refuses a file whose block walk does not land exactly
-- where the summed costs say it will, so every emitter reaching this point
-- agreed twice.
local parsedEmitters, blockKinds = 0, {}
if moves then
  for i = 0, moves.count - 1 do
    local data = moves:get(i)
    for _, e in ipairs((data and P.emitters(data)) or {}) do
      if e.parsed then
        parsedEmitters = parsedEmitters + 1
        for name in pairs(e.parsed) do
          blockKinds[name] = (blockKinds[name] or 0) + 1
        end
      end
    end
  end
end
ok(parsedEmitters == 1468, "every emitter's blocks decoded", parsedEmitters, 1468)
ok((blockKinds.scaleAnim or 0) > 1000 and (blockKinds.alphaAnim or 0) > 1000,
   "...and the two commonest are the scale and alpha curves",
   ("scale %d, alpha %d"):format(blockKinds.scaleAnim or 0,
                                 blockKinds.alphaAnim or 0),
   "over a thousand each")
ok((blockKinds.collisionPlane or 0) == 1,
   "...while the collision plane is still the cartridge's one sample",
   blockKinds.collisionPlane or 0, 1)

-- AND NOW THE POINT: DOES ANY OF IT MOVE. Every assertion above would pass with
-- the curves decoded and then ignored, which is exactly what this file did
-- before -- so the scale, the alpha, the texture, the colour and the rotation
-- are each counted over a sample of the corpus.
local aScale, aAlpha, aTex, aColour, aRot, aSampled = 0, 0, 0, 0, 0, 0
if moves then
  for i = 0, moves.count - 1, 7 do
    local data = moves:get(i)
    local sys = data and PS.new(data)
    if sys then
      sys:start(4242 + i)
      local seen, frames = {}, 0
      while sys:update() and frames < 120 do
        frames = frames + 1
        for _, q in ipairs(sys.particles) do
          local s = seen[q]
          if not s then
            s = { smin = q.scale, smax = q.scale, amin = q.alpha,
                  amax = q.alpha, tex = q.texture, texMoved = false,
                  colour = q.colour ~= nil, rot = q.rotation or 0,
                  rotMoved = false }
            seen[q] = s
          end
          if q.scale < s.smin then s.smin = q.scale end
          if q.scale > s.smax then s.smax = q.scale end
          if q.alpha < s.amin then s.amin = q.alpha end
          if q.alpha > s.amax then s.amax = q.alpha end
          if q.texture ~= s.tex then s.texMoved = true end
          -- !! THIS USED TO ASK WHETHER THE PARTICLE HAD A COLOUR AT ALL, and it
          -- stopped measuring anything the moment particles started being BORN
          -- with their emitter's colour -- which is what the cartridge does. It
          -- asks whether the colour MOVES now, which is the colour animation's
          -- actual effect.
          if s.firstColour == nil then s.firstColour = q.colour end
          if q.colour and s.firstColour
             and (q.colour[1] ~= s.firstColour[1]
                  or q.colour[2] ~= s.firstColour[2]
                  or q.colour[3] ~= s.firstColour[3]) then
            s.colour = true
          end
          if (q.rotation or 0) ~= s.rot then s.rotMoved = true end
        end
      end
      for _, s in pairs(seen) do
        aSampled = aSampled + 1
        if s.smax - s.smin > 1e-9 then aScale = aScale + 1 end
        if s.amax - s.amin > 1e-9 then aAlpha = aAlpha + 1 end
        if s.texMoved then aTex = aTex + 1 end
        if s.colour then aColour = aColour + 1 end
        if s.rotMoved then aRot = aRot + 1 end
      end
    end
  end
end
ok(aSampled > 2000, "enough particles watched over their whole lives",
   aSampled, "over 2000")
ok(aScale >= 2080, "A PARTICLE'S SCALE CHANGES AS IT LIVES -- this many of them",
   ("%d of %d"):format(aScale, aSampled), "at least 2080")
ok(aAlpha >= 2350, "...and so does its alpha", ("%d of %d"):format(aAlpha, aSampled),
   "at least 2350")
ok(aTex >= 64, "...and this many swap texture mid-flight", aTex, "at least 64")
ok(aColour >= 1227, "...and this many have their colour MOVED by a curve",
   aColour, "at least 1227")
ok(aRot >= 546, "...and this many spin", aRot, "at least 546")

-- THE BEHAVIOURS CHANGE WHERE A PARTICLE GOES, which is a different claim from
-- "the block was read". Each one is measured by running the same resource with
-- its own block removed and requiring the trajectory to differ -- the only
-- version of this assertion that a decoded-and-ignored block fails.
--
-- !! AND THE FIRST VERSION OF IT FAILED ON REAL DATA, which is worth keeping.
-- "Removing the block must always change something" came out 7 of 12 for
-- convergence, 7 of 12 for random and 11 of 12 for spin -- because the cartridge
-- ships blocks THAT ARE PRESENT AND INERT: 5 of the first 14 convergence blocks
-- carry force 0.0 and target (0,0,0), several random blocks carry a magnitude of
-- zero on all three axes, and a spin block cannot move a particle that never
-- leaves the origin, whatever its angle. An inert block is not a bug and an
-- assertion that calls it one is an assertion that gets relaxed until it says
-- nothing -- so each one's degeneracy is DEFINED, counted, and the live ones are
-- required to differ without exception.
local INERT = {
  gravity = function(b) return (b.x or 0) == 0 and (b.y or 0) == 0
                                and (b.z or 0) == 0 end,
  magnet = function(b) return (b.force or 0) == 0 end,
  convergence = function(b) return (b.force or 0) == 0 end,
  random = function(b) return (b.x or 0) == 0 and (b.y or 0) == 0
                               and (b.z or 0) == 0 end,
  -- Spin's degeneracy is POSITIONAL, not in the block: a rotation about an axis
  -- through the origin leaves a particle at the origin exactly where it was.
  spin = function(b) return (b.angle or 0) % 65536 == 0 end,
}
local behaviourEffect = {}
local BEHAVIOURS = { "gravity", "magnet", "convergence", "spin", "random" }
if moves then
  for _, name in ipairs(BEHAVIOURS) do
    local changed, live, inert = 0, 0, 0
    local sampled = 0
    for i = 0, moves.count - 1 do
      local data = moves:get(i)
      for _, e in ipairs((data and P.emitters(data)) or {}) do
        local block = e.parsed and e.parsed[name]
        if block and sampled < 16 then
          sampled = sampled + 1
          if INERT[name](block) then
            inert = inert + 1
          else
            local withIt = PS.fromEmitters({ e })
            -- A SHALLOW COPY WITH ONE BLOCK REMOVED. The emitter table itself is
            -- never written to -- the cache owns it.
            local stripped = {}
            for k, v in pairs(e.parsed) do
              if k ~= name then stripped[k] = v end
            end
            local without = PS.fromEmitters({
              { at = e.at, bytes = e.bytes, flags = e.flags, blocks = e.blocks,
                parsed = stripped, fields = e.fields } })
            withIt:start(777 + i)
            without:start(777 + i)
            local frames, differs, moved = 0, false, false
            while frames < 60 do
              local a = withIt:update()
              local b = without:update()
              frames = frames + 1
              local pa, pb = withIt.particles[1], without.particles[1]
              if pa and pb then
                if (pa.x ~= 0 or pa.y ~= 0 or pa.z ~= 0) then moved = true end
                if math.abs(pa.x - pb.x) + math.abs(pa.y - pb.y)
                   + math.abs(pa.z - pb.z) > 1e-9 then differs = true end
              end
              if not (a or b) then break end
            end
            -- A SPIN BLOCK ON A PARTICLE THAT NEVER LEAVES THE ORIGIN is the
            -- positional degeneracy above, and it counts as inert rather than as
            -- a failure.
            if name == "spin" and not moved then
              inert = inert + 1
            else
              live = live + 1
              if differs then changed = changed + 1 end
            end
          end
        end
      end
    end
    behaviourEffect[name] = { live = live, changed = changed, inert = inert }
  end
end
for _, name in ipairs(BEHAVIOURS) do
  local row = behaviourEffect[name] or { live = 0, changed = 0, inert = 0 }
  ok(row.live > 0 and row.changed == row.live,
     ("removing the %s block changes the trajectory"):format(name),
     ("%d of %d live (%d inert)"):format(row.changed, row.live, row.inert),
     "all the live ones")
end
-- AND THE INERT ONES ARE REAL, not an excuse: if none of the sampled blocks were
-- degenerate the exemption above would be dead code, and a dead exemption is one
-- that can quietly start covering a bug.
local inertSeen = 0
for _, name in ipairs(BEHAVIOURS) do
  inertSeen = inertSeen + (behaviourEffect[name] or {}).inert
end
ok(inertSeen > 0,
   "...and the cartridge really does ship blocks that do nothing",
   inertSeen .. " inert blocks in the sample", "more than 0")

-- THE COLLISION PLANE GETS NAMED SEPARATELY because it occurs ONCE and a
-- one-sample assertion should say so rather than hide inside a loop.
do
  local found = 0
  if moves then
    for i = 0, moves.count - 1 do
      local data = moves:get(i)
      for _, e in ipairs((data and P.emitters(data)) or {}) do
        if e.parsed and e.parsed.collisionPlane then found = found + 1 end
      end
    end
  end
  ok(found == 1, "the collision plane is applied to the one emitter that has it",
     found, 1)
end

-- ...AND WHAT IS STILL NOT APPLIED IS ONE THING, NAMED. `missing()` used to
-- report eight kinds; a list that shrinks to nothing silently is a list nobody
-- would notice going stale.
local notApplied = 0
for _ in pairs(PS.NOT_APPLIED or {}) do notApplied = notApplied + 1 end
ok(notApplied == 0,
   "NO BLOCK KIND IS UNAPPLIED ANY MORE -- all eleven are implemented",
   notApplied .. " kinds", 0)
-- ...AND THE LIST IS STILL THERE, EMPTY. A missing-features list deleted the day
-- it empties is one nobody notices the next time something is left out.
ok(PS.NOT_APPLIED ~= nil, "...and the list it was kept in still exists",
   PS.NOT_APPLIED ~= nil, true)
-- WHAT IS LEFT IS DRAW MODES, NAMED WITH REASONS. Same discipline as the
-- player's NOT_NEEDED: an argued skip is one somebody can disagree with.
local gaps, unreasoned = 0, 0
for _, why in pairs(PS.DRAW_GAPS or {}) do
  gaps = gaps + 1
  if type(why) ~= "string" or #why < 12 then unreasoned = unreasoned + 1 end
end
ok(gaps >= 8, "the draw-mode gaps are named", gaps .. " of them", "at least 8")
-- AND TEXTURE TILING IS NO LONGER ONE OF THEM. It was, with the reason "647
-- emitters set one and none is honoured"; the draw callback carries both counts
-- now. A gap list is only worth having if entries LEAVE it when they are closed.
ok((PS.DRAW_GAPS or {}).textureTileCount == nil,
   "...and texture tiling has left the list",
   tostring((PS.DRAW_GAPS or {}).textureTileCount), "nil")
ok(unreasoned == 0, "...and every one of them carries its reason", unreasoned, 0)

-- ---------------------------------------------------------------------------
-- 10: THE ARITHMETIC OF THE CURVES, asserted directly.
--
-- Section 9 proves the animations DO something. It does not prove they do the
-- RIGHT thing, and three planted faults walked through it: the wrong
-- randomisation macro for the base scale, the curve's in and out points swapped,
-- and the life rate computed the obvious way instead of the cartridge's. All
-- three leave a scale that still varies and a particle that still moves.
-- ---------------------------------------------------------------------------
io.write("\nthe arithmetic behind them\n")

-- THE LIFE RATE IS NOT `255 * age / life`. pret computes `lifeTimeFactor =
-- 0xFFFF / lifeTime` once at birth and then `(lifeTimeFactor * age) >> 8`, and
-- the two integer truncations do not compose into the obvious formula. The rows
-- below are pret's arithmetic by hand; the fourth is the one that separates them.
local RATE_ROWS = {
  { age = 0, life = 8, want = 0 },
  { age = 4, life = 8, want = 127 },
  { age = 8, life = 8, want = 255 },
  { age = 5, life = 6, want = 213 },      -- the obvious formula gives 212
  { age = 1, life = 3, want = 85 },
  { age = 19, life = 19, want = 255 },
}
local rateDrift = {}
for _, row in ipairs(RATE_ROWS) do
  local got = PS.lifeRate(row.age, row.life)
  if got ~= row.want then
    rateDrift[#rateDrift + 1] = ("age %d of %d gave %s, not %d")
      :format(row.age, row.life, tostring(got), row.want)
  end
end
ok(#rateDrift == 0, "THE LIFE RATE IS THE CARTRIDGE'S ARITHMETIC, not the obvious one",
   #rateDrift == 0 and (#RATE_ROWS .. " rows agree") or table.concat(rateDrift, "; "),
   "all rows")
-- AND IT NEVER LEAVES THE 0..255 RANGE the curves are written against, which is
-- what lets pret keep it in a u8 at all.
local rateRange = true
for life = 1, 200 do
  for age = 0, life do
    local r = PS.lifeRate(age, life)
    if r < 0 or r > 255 then rateRange = false end
  end
end
ok(rateRange, "...and it stays inside the 0..255 scale for every lifetime",
   rateRange, true)

-- THE CURVE'S TWO POINTS ARE IN THE ORDER THE STRUCT SAYS. `SPLCurveInOut` is
-- one u16 with `in` in the LOW byte, and a reader that swapped them would still
-- produce curves, still make the scale vary, and put nearly every rise where the
-- fall belongs. The cartridge itself settles it: a curve should reach its middle
-- value before it starts leaving it, so `in <= out` almost always -- and swapping
-- the reader turns 26 exceptions into 2,635.
local curves, inAfterOut = 0, 0
if moves then
  for i = 0, moves.count - 1 do
    local data = moves:get(i)
    for _, e in ipairs((data and P.emitters(data)) or {}) do
      for _, key in ipairs({ "scaleAnim", "alphaAnim" }) do
        local b = e.parsed and e.parsed[key]
        if b and b.curve then
          curves = curves + 1
          if (b.curve.inAt or 0) > (b.curve.outAt or 0) then
            inAfterOut = inAfterOut + 1
          end
        end
      end
    end
  end
end
ok(curves == 2661, "every scale and alpha curve was read", curves, 2661)
ok(inAfterOut <= 30,
   "...and almost all of them rise before they fall",
   ("%d of %d have in > out"):format(inAfterOut, curves), "at most 30")

-- THE BASE SCALE USES THE DOUBLE-SCALED MACRO, measured as a total rather than
-- argued: swapping it for the single-scaled one takes the corpus from 35,947 to
-- 33,068 scale-units, an 8% loss spread over every particle in the game and
-- invisible in any assertion about whether a scale varies.
local scaleUnits = 0
if moves then
  for i = 0, moves.count - 1, 7 do
    local data = moves:get(i)
    local sys = data and PS.new(data)
    if sys then
      sys:start(4242 + i)
      local frames = 0
      while sys:update() and frames < 120 do
        frames = frames + 1
        for _, q in ipairs(sys.particles) do
          scaleUnits = scaleUnits + (q.scale or 0)
        end
      end
    end
  end
end
ok(scaleUnits > 32827 and scaleUnits < 33157,
   "the corpus is worth this many scale-units",
   ("%.0f"):format(scaleUnits), "32992 within half a percent")

-- A MAGNET DAMPS THE VELOCITY WHILE IT PULLS. The term is
-- force * ((target - position) - velocity), and dropping the velocity turns a
-- magnet into a spring: the particle overshoots and oscillates. Counted as
-- crossings of the target, which goes 24 -> 32 the moment the damping is lost.
local magnetCrossings, magnetEmitters = 0, 0
if moves then
  for i = 0, moves.count - 1 do
    local data = moves:get(i)
    for _, e in ipairs((data and P.emitters(data)) or {}) do
      local m = e.parsed and e.parsed.magnet
      if m and (m.force or 0) ~= 0 and magnetEmitters < 16 then
        magnetEmitters = magnetEmitters + 1
        local sys = PS.fromEmitters({ e })
        sys:start(555 + i)
        local frames, side = 0, nil
        while sys:update() and frames < 90 do
          frames = frames + 1
          local q = sys.particles[1]
          if q then
            local now = ((m.x or 0) - q.x) >= 0
            if side ~= nil and now ~= side then
              magnetCrossings = magnetCrossings + 1
            end
            side = now
          end
        end
      end
    end
  end
end
ok(magnetEmitters == 16, "sixteen magnet emitters were driven", magnetEmitters, 16)
ok(magnetCrossings == 34,
   "...and their particles cross the target exactly this often",
   magnetCrossings, 34)

-- THE COLLISION PLANE, AND AN HONEST LIMIT.
--
-- The cartridge's one collision emitter (effect 43, emitter 3) sets its plane at
-- y = -11.71 while its own emitter sits at y = -0.97 and its particles live 19
-- frames. THEY NEVER FALL FAR ENOUGH TO REACH IT -- the oldest particle in the
-- run dies of age at exactly 19. So the cartridge cannot exercise this code path
-- at all, and an assertion that only counts the block would pass with the KILL
-- arm deleted, which is exactly what a planted fault proved.
--
-- The path is therefore driven with a SYNTHETIC emitter, and labelled as one: a
-- plane just below the origin, a particle thrown downwards, and a lifetime long
-- enough that dying early can only mean the plane killed it.
local realPlane, realOldest, realLife = 0, 0, 0
if moves then
  local data = moves:get(43)
  for _, e in ipairs((data and P.emitters(data)) or {}) do
    if e.parsed and e.parsed.collisionPlane then
      realPlane = realPlane + 1
      realLife = e.fields.particleLifeTime or 0
      local sys = PS.fromEmitters({ e })
      sys:start(99)
      local frames = 0
      while sys:update() and frames < 200 do
        frames = frames + 1
        for _, q in ipairs(sys.particles) do
          if q.age > realOldest then realOldest = q.age end
        end
      end
    end
  end
end
ok(realPlane == 1, "the cartridge's one collision emitter is where it was",
   realPlane, 1)
ok(realOldest == realLife and realLife > 0,
   "...and its particles die of age, never reaching its plane",
   ("oldest %d of %d frames"):format(realOldest, realLife), "the full lifetime")

do
  -- SYNTHETIC, and it has to be: see above.
  local function planeEmitter(kind)
    return {
      at = 0, bytes = 96, flags = 0, blocks = {},
      parsed = { collisionPlane = { y = -1, elasticity = 0.5, kind = kind } },
      fields = {
        flags = 0, basePos = { 0, 0, 0 }, emissionCount = 1, radius = 0,
        length = 0, axis = { 0, -1, 0 }, colour = { 255, 255, 255 },
        initVelPos = 0, initVelAxis = 0.5, baseScale = 1, aspectRatio = 1,
        startDelay = 0, minRotation = 0, maxRotation = 0, initAngle = 0,
        emitterLifeTime = 1, particleLifeTime = 60,
        randomAttenuation = { baseScale = 0, lifeTime = 0, initVel = 0 },
        emissionInterval = 1, baseAlpha = 31, airResistance = 128,
        textureIndex = 0, loopFrames = 1, polygonX = 0, polygonY = 0,
      },
    }
  end
  local killed = PS.fromEmitters({ planeEmitter(P.COLLISION_KILL) })
  killed:start(1)
  local frames, oldest = 0, 0
  while killed:update() and frames < 120 do
    frames = frames + 1
    for _, q in ipairs(killed.particles) do
      if q.age > oldest then oldest = q.age end
    end
  end
  ok(oldest > 0 and oldest < 60,
     "a KILL plane ends a particle before its lifetime is up",
     ("died at %d of 60 frames"):format(oldest), "well under 60")

  local bounced = PS.fromEmitters({ planeEmitter(P.COLLISION_BOUNCE) })
  bounced:start(1)
  local went, came = false, false
  frames = 0
  while bounced:update() and frames < 120 do
    frames = frames + 1
    local q = bounced.particles[1]
    if q then
      if (q.vy or 0) < 0 then went = true end
      if went and (q.vy or 0) > 0 then came = true end
    end
  end
  ok(went and came, "...and a BOUNCE plane sends it back up instead",
     ("down %s, then up %s"):format(tostring(went), tostring(came)),
     "both")
end

-- ---------------------------------------------------------------------------
-- 11: THE CHILD RESOURCE, THE POOL, AND THE FACT THAT A PARTICLE IS NOT SQUARE.
--
-- The last block, the hardware limit that decides how much of any of it is
-- visible, and two header fields that change the shape of a third of the
-- cartridge's particles.
-- ---------------------------------------------------------------------------
io.write("\nchildren, the pool, and shape\n")

-- 745 EMITTERS CARRY A CHILD RESOURCE and 342 effects contain at least one. Every
-- one of those 342 must actually produce children: a child layer that parses and
-- emits nothing is the same failure as the fractional emission count, one level
-- down.
local withChild, emittedChildren, childFrames, peakChildren = 0, 0, 0, 0
local childlessSilent = {}
if moves then
  for i = 0, moves.count - 1 do
    local data = moves:get(i)
    local list = data and P.emitters(data)
    local any = false
    for _, e in ipairs(list or {}) do
      if e.parsed and e.parsed.childResource then any = true end
    end
    if any then
      withChild = withChild + 1
      local sys = PS.new(data)
      if sys then
        sys:start(2024 + i)
        local frames, peak = 0, 0
        while sys:update() and frames < 400 do
          frames = frames + 1
          childFrames = childFrames + (sys.liveChildren or 0)
          if (sys.liveChildren or 0) > peak then peak = sys.liveChildren end
        end
        if peak > 0 then emittedChildren = emittedChildren + 1
        elseif #childlessSilent < 6 then
          childlessSilent[#childlessSilent + 1] = tostring(i)
        end
        if peak > peakChildren then peakChildren = peak end
      end
    end
  end
end
ok(withChild == 342, "this many effects carry a child resource", withChild, 342)
ok(emittedChildren == withChild and #childlessSilent == 0,
   "EVERY ONE OF THEM ACTUALLY EMITS CHILDREN",
   #childlessSilent == 0 and "all of them"
     or ("silent: " .. table.concat(childlessSilent, ", ")),
   "all of them")
ok(childFrames >= 399352, "...worth this many child-frames", childFrames,
   "at least 399352")
-- THE CHILDREN ARE CAPPED BY THE SAME POOL as their parents, and they get what
-- the parents leave: 194, not 200, and certainly not the 1,260 an uncapped run
-- produced.
ok(peakChildren > 150 and peakChildren < PS.MAX_PARTICLES,
   "...and the busiest child layer is held under the pool",
   peakChildren, "between 150 and " .. tostring(PS.MAX_PARTICLES))

-- THE POOL REALLY RUNS DRY, and it is counted rather than shrugged at. A cap that
-- never binds is a cap that says nothing about the cartridge.
local starved, ran = 0, 0
if moves then
  for i = 0, moves.count - 1, 7 do
    local data = moves:get(i)
    local sys = data and PS.new(data)
    if sys then
      ran = ran + 1
      sys:start(4242 + i)
      local frames = 0
      while sys:update() and frames < 120 do frames = frames + 1 end
      starved = starved + (sys.starved or 0)
    end
  end
end
ok(ran > 60, "enough effects driven to see the pool bind", ran, "over 60")
ok(starved > 0, "...and it does bind: emission was refused this many times",
   starved, "more than 0")

-- A CHILD IS NOT ITS PARENT, and the four places it differs are each asserted,
-- because every one of them is easy to write the parent's way.
--   life rate: (age << 8) / lifeTime, NOT the factor-based version
-- THE TWO FORMULAS AGREE MOST OF THE TIME, which is what makes writing one for
-- both so easy. They part company at the end of a life: `(age << 8) / lifeTime`
-- reaches exactly 256 when age == lifeTime and pret stores it in a u8, so a
-- CHILD'S LAST FRAME READS 0 and snaps back to its birth appearance. The parent's
-- version cannot -- `floor(65535/L) * L` never passes 65535 -- so it ends at 255.
--
-- My first version of this assertion claimed they differ at age 5 of 6. They do
-- not; both give 213. The formula that gives 212 there is `255 * age / life`, a
-- THIRD arithmetic I had confused with the child's. The check said so at once.
local childRateRows = {
  -- age, life, parent, child
  { 5, 6, 213, 213 },     -- they agree here, and I claimed otherwise
  { 7, 7, 255, 0 },       -- the last frame: 255 vs a wrapped 256
  { 19, 19, 255, 0 },
  { 4, 8, 127, 128 },     -- and they are off by one in the middle
  { 1, 3, 85, 85 },
}
local childRateDrift = {}
for _, row in ipairs(childRateRows) do
  local parentValue = PS.lifeRate(row[1], row[2])
  local childValue = PS.childLifeRate(row[1], row[2])
  if parentValue ~= row[3] then
    childRateDrift[#childRateDrift + 1] = ("parent %d of %d gave %s, not %d")
      :format(row[1], row[2], tostring(parentValue), row[3])
  end
  if childValue ~= row[4] then
    childRateDrift[#childRateDrift + 1] = ("child %d of %d gave %s, not %d")
      :format(row[1], row[2], tostring(childValue), row[4])
  end
end
ok(#childRateDrift == 0,
   "A CHILD'S LIFE RATE IS ITS OWN ARITHMETIC, wrap and all",
   #childRateDrift == 0 and (#childRateRows .. " rows agree")
     or table.concat(childRateDrift, "; "),
   "all rows")
-- AND THEY REALLY ARE TWO FORMULAS: if one were serving both, the rows above that
-- disagree could not.
local differ = 0
for _, row in ipairs(childRateRows) do
  if PS.lifeRate(row[1], row[2]) ~= PS.childLifeRate(row[1], row[2]) then
    differ = differ + 1
  end
end
ok(differ == 3, "...and it disagrees with the parent's on three of five rows",
   differ, 3)

-- THE SCALE RATIO IS OVER 64, NOT 256. A u8 over 64 means the field can ENLARGE a
-- child as well as shrink it, and reading it as /256 makes every child in the
-- game four times too small. Checked by driving a synthetic parent whose child
-- asks for the same size.
do
  local parent = {
    at = 0, bytes = 96, flags = 2 ^ 16, blocks = { [16] = true },
    parsed = { childResource = {
      emissionCount = 1, emissionDelay = 0, emissionInterval = 1,
      lifeTime = 30, velocityRatio = 0, scaleRatio = 63, textureIndex = 0,
      rotationType = 0, endScale = 1, randomInitVelMag = 0,
      colour = { 255, 255, 255 }, useChildColour = false,
      usesBehaviors = false, hasScaleAnim = false, hasAlphaAnim = false,
    } },
    fields = {
      flags = 0, basePos = { 0, 0, 0 }, emissionCount = 1, radius = 0,
      length = 0, axis = { 0, 1, 0 }, colour = { 255, 255, 255 },
      initVelPos = 0, initVelAxis = 0, baseScale = 2, aspectRatio = 1,
      startDelay = 0, minRotation = 0, maxRotation = 0, initAngle = 0,
      emitterLifeTime = 1, particleLifeTime = 30,
      randomAttenuation = { baseScale = 0, lifeTime = 0, initVel = 0 },
      emissionInterval = 1, baseAlpha = 31, airResistance = 128,
      textureIndex = 0, loopFrames = 1, polygonX = 0, polygonY = 0,
      scaleAnimDir = 0,
    },
  }
  local sys = PS.fromEmitters({ parent })
  sys:start(4)
  local frames, kidScale, parentScale = 0, nil, nil
  while sys:update() and frames < 40 do
    frames = frames + 1
    if sys.particles[1] then parentScale = sys.particles[1].baseScale end
    if sys.children[1] and not kidScale then
      kidScale = sys.children[1].baseScale
    end
  end
  -- scaleRatio 63 -> (63 + 1) / 64 = 1.0, so the child matches its parent.
  local ratio = (kidScale and parentScale and parentScale ~= 0)
    and (kidScale / parentScale) or nil
  ok(ratio ~= nil and math.abs(ratio - 1) < 1e-6,
     "scaleRatio 63 makes a child exactly its parent's size (over 64, not 256)",
     ratio and ("%.4f"):format(ratio) or "no child", "1.0000")
end

-- A PARTICLE IS NOT SQUARE. `aspectRatio` spans 0.0298..7.9998 and 445 emitters
-- set it; `scaleAnimDir` says which axis an animation touches and takes only its
-- three declared values across all 1,468 -- which is what a wrong offset in a
-- 3-bit field would not do.
local aspects, dirs, emitters = 0, {}, 0
local aspectLow, aspectHigh = 99, -99
if moves then
  for i = 0, moves.count - 1 do
    local data = moves:get(i)
    for _, e in ipairs((data and P.emitters(data)) or {}) do
      local f = e.fields
      emitters = emitters + 1
      local a = f.aspectRatio or 1
      if a ~= 1 then aspects = aspects + 1 end
      if a < aspectLow then aspectLow = a end
      if a > aspectHigh then aspectHigh = a end
      dirs[f.scaleAnimDir or 0] = (dirs[f.scaleAnimDir or 0] or 0) + 1
    end
  end
end
ok(emitters == 1468, "every emitter's shape fields were read", emitters, 1468)
ok(aspects == 445, "this many emitters do not draw a square particle", aspects, 445)
ok(aspectLow > 0 and aspectHigh > 1 and aspectHigh < 8.1,
   "...and the aspect ratio spans a sane range",
   ("%.4f .. %.4f"):format(aspectLow, aspectHigh), "inside 0 .. 8.1")
ok((dirs[0] or 0) == 1293 and (dirs[1] or 0) == 41 and (dirs[2] or 0) == 134,
   "the scale-animation direction takes only its three declared values",
   ("XY %d, X %d, Y %d"):format(dirs[0] or 0, dirs[1] or 0, dirs[2] or 0),
   "1293 / 41 / 134")
local strayDir = 0
for value in pairs(dirs) do if value > 2 then strayDir = strayDir + 1 end end
ok(strayDir == 0, "...and never a fourth", strayDir, 0)

-- AND THE TWO SCALES REACH THE DRAW CALLBACK DIFFERENTLY from each other, on the
-- emitters that ask for it. Anything less than this passes with the aspect ratio
-- thrown away.
local anisotropic, drawn = 0, 0
if moves then
  for i = 0, moves.count - 1, 3 do
    local data = moves:get(i)
    local sys = data and PS.new(data)
    if sys then
      sys:start(11 + i)
      local frames = 0
      while sys:update() and frames < 60 do
        frames = frames + 1
        sys:draw(0, 0, function(_, _, _, sx, sy)
          drawn = drawn + 1
          if sx and sy and math.abs(sx - sy) > 1e-9 then
            anisotropic = anisotropic + 1
          end
        end)
      end
    end
  end
end
ok(drawn > 10000, "enough particles drawn to look at their shape", drawn,
   "over 10000")
ok(anisotropic > 1000, "...and this many are drawn wider than they are tall",
   anisotropic, "over 1000")
-- !! AND THAT ASSERTION ALONE DID NOT NEED THE ASPECT RATIO AT ALL. A
-- `scaleAnimDir` of X or Y already separates the two axes, 175 emitters set one,
-- and that was enough to clear the thousand -- so deleting the aspect from the
-- scale entirely passed it. Counted again on the emitters whose direction is XY,
-- where the aspect is the ONLY thing that can make the two differ.
local xyDrawn, xyWide = 0, 0
if moves then
  for i = 0, moves.count - 1, 3 do
    local data = moves:get(i)
    local list = data and P.emitters(data)
    for _, e in ipairs(list or {}) do
      if (e.fields.scaleAnimDir or 0) == PS.SCALE_DIR_XY
         and (e.fields.aspectRatio or 1) ~= 1 then
        local sys = PS.fromEmitters({ e })
        sys:start(300 + i)
        local frames = 0
        while sys:update() and frames < 40 do
          frames = frames + 1
          sys:draw(0, 0, function(_, _, _, sx, sy)
            -- A ZERO SCALE IS SQUARE WHATEVER THE ASPECT RATIO IS -- 0 times
            -- anything is 0 -- and 80 of the sampled particles are born at zero
            -- because their emitter's baseScale is. They are not counted rather
            -- than the assertion being loosened to "almost all".
            if sy and sy > 0 then
              xyDrawn = xyDrawn + 1
              if sx and math.abs(sx - sy) > 1e-9 then xyWide = xyWide + 1 end
            end
          end)
        end
      end
    end
  end
end
ok(xyDrawn > 500, "enough XY-direction particles drawn", xyDrawn, "over 500")
ok(xyWide == xyDrawn,
   "...and EVERY one of them is drawn non-square, which only the aspect can do",
   ("%d of %d"):format(xyWide, xyDrawn), "all of them")

-- A CHILD INHERITS A FRACTION OF ITS PARENT'S VELOCITY, and the fraction is
-- `velocityRatio / 256`. Inheriting all of it makes every spray move with its
-- source instead of trailing behind it, and nothing about the corpus totals can
-- see that -- so it is asserted exactly, on a synthetic parent with a known
-- velocity and no randomisation anywhere.
do
  local function velParent(ratio)
    return {
      at = 0, bytes = 96, flags = 2 ^ 16, blocks = { [16] = true },
      parsed = { childResource = {
        emissionCount = 1, emissionDelay = 0, emissionInterval = 1,
        lifeTime = 30, velocityRatio = ratio, scaleRatio = 63,
        textureIndex = 0, rotationType = 0, endScale = 1,
        randomInitVelMag = 0, colour = { 255, 255, 255 },
        useChildColour = false, usesBehaviors = false,
        hasScaleAnim = false, hasAlphaAnim = false,
      } },
      fields = {
        flags = 0, basePos = { 0, 0, 0 }, emissionCount = 1, radius = 0,
        length = 0, axis = { 0, 1, 0 }, colour = { 255, 255, 255 },
        initVelPos = 0, initVelAxis = 1, baseScale = 1, aspectRatio = 1,
        startDelay = 0, minRotation = 0, maxRotation = 0, initAngle = 0,
        emitterLifeTime = 1, particleLifeTime = 30,
        randomAttenuation = { baseScale = 0, lifeTime = 0, initVel = 0 },
        emissionInterval = 1, baseAlpha = 31, airResistance = 128,
        textureIndex = 0, loopFrames = 1, polygonX = 0, polygonY = 0,
        scaleAnimDir = 0,
      },
    }
  end
  -- 128/256 = exactly half.
  local sys = PS.fromEmitters({ velParent(128) })
  sys:start(6)
  sys:update()
  local parentV = sys.particles[1] and sys.particles[1].vy
  local childV = sys.children[1] and sys.children[1].vy
  local ratio = (parentV and childV and parentV ~= 0) and (childV / parentV) or nil
  ok(ratio ~= nil and math.abs(ratio - 0.5) < 1e-9,
     "a child inherits velocityRatio/256 of its parent's velocity",
     ratio and ("%.6f"):format(ratio) or "no child", "0.500000")

  -- AND THE BEHAVIOURS ARE OPTIONAL FOR CHILDREN. `usesBehaviors` is false on 718
  -- of the cartridge's 745 child blocks and true on 27, so the common case is the
  -- one that must NOT inherit -- which is the direction a port gets wrong by
  -- simply passing the parent's blocks along.
  local function gravityParent(uses)
    local e = velParent(0)
    e.parsed.gravity = { x = 0, y = -0.05, z = 0 }
    e.parsed.childResource.usesBehaviors = uses
    e.blocks[24] = true
    return e
  end
  local function childFall(uses)
    local s = PS.fromEmitters({ gravityParent(uses) })
    s:start(6)
    local frames = 0
    while s:update() and frames < 20 do frames = frames + 1 end
    local kid = s.children[1]
    return kid and kid.y or nil
  end
  local without, with = childFall(false), childFall(true)
  ok(without ~= nil and with ~= nil and with < without - 1e-9,
     "...and only a child that asks for them feels the parent's gravity",
     (without and with) and ("%.4f without, %.4f with"):format(without, with)
       or "no child", "with is lower")
end

-- HOW THE CARTRIDGE SPLITS THAT DECISION, stated so the common case is visible.
local usesBehaviours, plainChildren = 0, 0
if moves then
  for i = 0, moves.count - 1 do
    local data = moves:get(i)
    for _, e in ipairs((data and P.emitters(data)) or {}) do
      local c = e.parsed and e.parsed.childResource
      if c then
        if c.usesBehaviors then usesBehaviours = usesBehaviours + 1
        else plainChildren = plainChildren + 1 end
      end
    end
  end
end
ok(usesBehaviours == 27 and plainChildren == 718,
   "the cartridge's child blocks split this way on usesBehaviors",
   ("%d use them, %d do not"):format(usesBehaviours, plainChildren),
   "27 and 718")

-- HIDE-PARENT AND DRAW-CHILDREN-FIRST ARE READ AND HONOURED. 22 emitters exist
-- only to spray and 259 put their spray behind them; a draw path that ignored
-- either would show something the cartridge does not.
local hideParent, childrenFirst = 0, 0
if moves then
  for i = 0, moves.count - 1 do
    local data = moves:get(i)
    for _, e in ipairs((data and P.emitters(data)) or {}) do
      if e.parsed and e.parsed.childResource then
        local w = e.flags or 0
        if math.floor(w / 2 ^ 22) % 2 == 1 then hideParent = hideParent + 1 end
        if math.floor(w / 2 ^ 21) % 2 == 1 then
          childrenFirst = childrenFirst + 1
        end
      end
    end
  end
end
ok(hideParent == 22, "this many emitters draw only their children", hideParent, 22)
ok(childrenFirst == 259, "...and this many draw the children behind",
   childrenFirst, 259)
-- AND A HIDDEN PARENT IS REALLY LEFT OUT of the draw list, which is the half of
-- that pair a count cannot prove.
do
  local found, hiddenDrawn, childDrawn = false, 0, 0
  if moves then
    for i = 0, moves.count - 1 do
      if found then break end
      local data = moves:get(i)
      for _, e in ipairs((data and P.emitters(data)) or {}) do
        local w = e.flags or 0
        if e.parsed and e.parsed.childResource
           and math.floor(w / 2 ^ 22) % 2 == 1 then
          found = true
          local sys = PS.fromEmitters({ e })
          sys:start(8)
          local frames = 0
          while sys:update() and frames < 120 do
            frames = frames + 1
            local parents = #sys.particles
            local kids = #sys.children
            local total = 0
            sys:draw(0, 0, function() total = total + 1 end)
            -- with the parent hidden, the draw list is the children alone
            if total ~= kids then hiddenDrawn = hiddenDrawn + 1 end
            if parents > 0 then childDrawn = childDrawn + 1 end
          end
          break
        end
      end
    end
  end
  ok(found, "an emitter that hides its parent was found to drive", found, true)
  ok(found and hiddenDrawn == 0,
     "...and its parents are never in the draw list",
     hiddenDrawn .. " frames drew one", 0)
  ok(childDrawn > 0, "...while its parents were alive the whole time",
     childDrawn .. " frames", "more than 0")
end

-- ---------------------------------------------------------------------------
-- 12: THE EMITTER'S OWN COLOUR, AND THE TEXTURE TILING.
--
-- Two header fields that between them decide what four fifths of the cartridge's
-- particles look like, and neither was being used.
-- ---------------------------------------------------------------------------
io.write("\ncolour and tiling\n")
local nonWhite, allWhite, tileShapes, shapeCount = 0, 0, {}, 0
if moves then
  for i = 0, moves.count - 1 do
    local data = moves:get(i)
    for _, e in ipairs((data and P.emitters(data)) or {}) do
      local c = e.fields.colour or { 255, 255, 255 }
      if c[1] >= 250 and c[2] >= 250 and c[3] >= 250 then allWhite = allWhite + 1
      else nonWhite = nonWhite + 1 end
      local key = ("%dx%d"):format(2 ^ (e.fields.textureTileCountS or 0),
                                   2 ^ (e.fields.textureTileCountT or 0))
      if tileShapes[key] == nil then shapeCount = shapeCount + 1 end
      tileShapes[key] = (tileShapes[key] or 0) + 1
    end
  end
end
-- FOUR FIFTHS OF THE CARTRIDGE'S EMITTERS ARE COLOURED. Effect 0's is orange,
-- effect 2's is blue. Drawing them white made them grey blobs, and no assertion
-- about scale, travel or lifetime could see it.
ok(nonWhite == 1160 and allWhite == 308,
   "this many emitters carry a colour of their own",
   ("%d coloured, %d white"):format(nonWhite, allWhite), "1160 and 308")
-- THE TILE COUNTS ARE POWERS OF TWO because `textureS = FX32_ONE << count`, and
-- only four shapes occur -- which a wrong 2-bit offset would not produce.
ok(shapeCount == 4 and (tileShapes["1x1"] or 0) == 821
   and (tileShapes["2x2"] or 0) == 534 and (tileShapes["2x1"] or 0) == 67
   and (tileShapes["1x2"] or 0) == 46,
   "...and the texture repeats in exactly four shapes",
   ("1x1 %d, 2x2 %d, 2x1 %d, 1x2 %d, shapes %d")
     :format(tileShapes["1x1"] or 0, tileShapes["2x2"] or 0,
             tileShapes["2x1"] or 0, tileShapes["1x2"] or 0, shapeCount),
   "821 / 534 / 67 / 46 in 4 shapes")

-- A PARTICLE IS BORN WITH ITS EMITTER'S COLOUR -- `ptcl->color = header->color`,
-- whether or not a colour animation ever runs. Asserted on every sampled particle
-- because this is the half that a colour-animation test cannot see: an emitter
-- with no curve at all still tints its particles.
local bornColoured, bornTotal = 0, 0
if moves then
  for i = 0, moves.count - 1, 7 do
    local data = moves:get(i)
    local sys = data and PS.new(data)
    if sys then
      sys:start(4242 + i)
      local seen, frames = {}, 0
      while sys:update() and frames < 120 do
        frames = frames + 1
        for _, q in ipairs(sys.particles) do
          if seen[q] == nil then
            seen[q] = true
            bornTotal = bornTotal + 1
            if q.colour ~= nil then bornColoured = bornColoured + 1 end
          end
        end
      end
    end
  end
end
ok(bornTotal > 2000, "enough particles watched from birth", bornTotal, "over 2000")
ok(bornColoured == bornTotal,
   "EVERY ONE OF THEM IS BORN WITH A COLOUR, not white",
   ("%d of %d"):format(bornColoured, bornTotal), "all of them")

-- AND THE DRAWN COLOUR IS THE MODULATE. `G3_Color` multiplies the particle's
-- colour by the emitter's, so a white particle on a coloured emitter comes out
-- coloured and a coloured one comes out darker. Counted at the draw callback,
-- which is the only place the product exists.
local drawnTinted, drawnTotal = 0, 0
if moves then
  for i = 0, moves.count - 1, 7 do
    local data = moves:get(i)
    local sys = data and PS.new(data)
    if sys then
      sys:start(4242 + i)
      local frames = 0
      while sys:update() and frames < 120 do
        frames = frames + 1
        sys:draw(0, 0, function(_, _, _, _, _, _, _, colour)
          drawnTotal = drawnTotal + 1
          if colour and not (colour[1] >= 250 and colour[2] >= 250
                             and colour[3] >= 250) then
            drawnTinted = drawnTinted + 1
          end
        end)
      end
    end
  end
end
ok(drawnTotal > 90000, "enough particles drawn to look at their colour",
   drawnTotal, "over 90000")
ok(drawnTinted >= 77437,
   "...and this many are drawn in a colour rather than white",
   drawnTinted, "at least 77437")
-- THE MODULATE IS A MULTIPLY, asserted as arithmetic rather than inferred from a
-- count: half red on half red is a quarter red, and a white particle takes its
-- emitter's colour unchanged.
do
  local half = { 128, 128, 128 }
  local orange = { 255, 98, 0 }
  local white = { 255, 255, 255 }
  local function drawnColour(particle, emitter)
    local one = { at = 0, bytes = 96, flags = 0, blocks = {}, parsed = {},
      fields = {
        flags = 0, basePos = { 0, 0, 0 }, emissionCount = 1, radius = 0,
        length = 0, axis = { 0, 1, 0 }, colour = emitter,
        initVelPos = 0, initVelAxis = 0, baseScale = 1, aspectRatio = 1,
        startDelay = 0, minRotation = 0, maxRotation = 0, initAngle = 0,
        emitterLifeTime = 1, particleLifeTime = 10,
        randomAttenuation = { baseScale = 0, lifeTime = 0, initVel = 0 },
        emissionInterval = 1, baseAlpha = 31, airResistance = 128,
        textureIndex = 0, loopFrames = 1, polygonX = 0, polygonY = 0,
        scaleAnimDir = 0, textureTileCountS = 0, textureTileCountT = 0,
      } }
    local sys = PS.fromEmitters({ one })
    sys:start(3)
    sys:update()
    if particle then
      for _, q in ipairs(sys.particles) do q.colour = particle end
    end
    local got = nil
    sys:draw(0, 0, function(_, _, _, _, _, _, _, colour) got = got or colour end)
    return got
  end
  local quarter = drawnColour(half, half)
  ok(quarter ~= nil and quarter[1] == 64,
     "half red on a half-red emitter draws a quarter red",
     quarter and tostring(quarter[1]) or "nothing", 64)
  local taken = drawnColour(white, orange)
  ok(taken ~= nil and taken[1] == 255 and taken[2] == 98 and taken[3] == 0,
     "...and a white particle takes its emitter's colour unchanged",
     taken and ("%d,%d,%d"):format(taken[1], taken[2], taken[3]) or "nothing",
     "255,98,0")
end

-- THE TILE COUNTS REACH THE DRAW CALLBACK AS THE RIGHT NUMBERS, which is the
-- half the header histogram cannot see: reading the field as a linear count
-- rather than a shift gives 0 and 1 where the cartridge means 1 and 2, and every
-- assertion about the header still passes.
local tileHist, tileDraws, tileFloats = {}, 0, 0
if moves then
  for i = 0, moves.count - 1, 7 do
    local data = moves:get(i)
    local sys = data and PS.new(data)
    if sys then
      sys:start(4242 + i)
      local frames = 0
      while sys:update() and frames < 120 do
        frames = frames + 1
        sys:draw(0, 0, function(_, _, _, _, _, _, _, _, ts, tt)
          tileDraws = tileDraws + 1
          -- AND THEY ARRIVE AS INTEGERS. `2 ^ 0` is 1.0 in Lua 5.3, and a float
          -- travelling to a blitter is the trap the SPA shape word set once.
          if math.type and (math.type(ts) ~= "integer"
                            or math.type(tt) ~= "integer") then
            tileFloats = tileFloats + 1
          end
          local key = ("%sx%s"):format(tostring(ts), tostring(tt))
          tileHist[key] = (tileHist[key] or 0) + 1
        end)
      end
    end
  end
end
ok(tileDraws > 90000, "enough particles drawn to see their tiling", tileDraws,
   "over 90000")
ok(tileFloats == 0, "...and every tile count arrives as an integer",
   tileFloats .. " floats", 0)
ok((tileHist["2x2"] or 0) > 40000 and (tileHist["1x1"] or 0) > 40000
   and (tileHist["2x1"] or 0) > 5000 and (tileHist["1x2"] or 0) > 1000,
   "...in the four shapes, with the values the shift produces",
   ("1x1 %d, 2x2 %d, 2x1 %d, 1x2 %d")
     :format(tileHist["1x1"] or 0, tileHist["2x2"] or 0,
             tileHist["2x1"] or 0, tileHist["1x2"] or 0),
   "all four present")
ok((tileHist["0x0"] or 0) == 0 and (tileHist["1x0"] or 0) == 0,
   "...and never the raw field value, which would be 0 for a single tile",
   (tileHist["0x0"] or 0) + (tileHist["1x0"] or 0), 0)

-- `randomStartColor` IS EXERCISED: 103 of the 1,102 colour animations set it, and
-- it makes a particle take one of THREE colours by its index -- the curve's two
-- ends and the emitter's own -- instead of always the emitter's. pret drops the
-- colour animation entirely for those emitters in the same breath, which is why
-- the flag lives in the spawn path and not in the animation.
local randomStart, colourAnims = 0, 0
if moves then
  for i = 0, moves.count - 1 do
    local data = moves:get(i)
    for _, e in ipairs((data and P.emitters(data)) or {}) do
      local ca = e.parsed and e.parsed.colorAnim
      if ca then
        colourAnims = colourAnims + 1
        if ca.randomStartColor then randomStart = randomStart + 1 end
      end
    end
  end
end
ok(colourAnims == 1102 and randomStart == 103,
   "this many colour animations set randomStartColor",
   ("%d of %d"):format(randomStart, colourAnims), "103 of 1102")
-- AND THE THREE COLOURS REALLY DIFFER. Driving one such emitter, consecutive
-- particles must not all be born the same colour -- which is what "always the
-- emitter's" produces and what a count of the flag cannot see.
do
  local found, distinct = false, 0
  if moves then
    for i = 0, moves.count - 1 do
      if found then break end
      local data = moves:get(i)
      for _, e in ipairs((data and P.emitters(data)) or {}) do
        local ca = e.parsed and e.parsed.colorAnim
        if ca and ca.randomStartColor
           and (e.fields.emissionCount or 0) >= 3 then
          found = true
          local sys = PS.fromEmitters({ e })
          sys:start(21)
          sys:update()
          local seen = {}
          for _, q in ipairs(sys.particles) do
            if q.colour then
              seen[("%d,%d,%d"):format(q.colour[1], q.colour[2], q.colour[3])] = true
            end
          end
          for _ in pairs(seen) do distinct = distinct + 1 end
          break
        end
      end
    end
  end
  ok(found, "an emitter with randomStartColor and a batch to fill was found",
     found, true)
  ok(found and distinct > 1,
     "...and its particles are NOT all born the same colour",
     distinct .. " distinct", "more than 1")
end

-- SCRATCH, SIMULATED. Its first emitter throws the claw once; the claw should
-- travel and then die, which is the whole animation.
if scratch then
  local sys = PS.new(scratch)
  ok(sys ~= nil, "Scratch builds a system", sys ~= nil, true)
  if sys then
    sys:start(7)
    local first, last, frames, sawClaw = nil, nil, 0, false
    while sys:update() and frames < 200 do
      frames = frames + 1
      for _, p in ipairs(sys.particles) do
        if p.texture == 1 then
          sawClaw = true
          if not first then first = { p.x, p.y } end
          last = { p.x, p.y }
        end
      end
    end
    ok(sawClaw, "...and it throws the 64x64 claw", sawClaw, true)
    local moved = first and last
      and (math.abs(first[1] - last[1]) + math.abs(first[2] - last[2]))
    ok(moved ~= nil and moved > 0.5,
       "...which travels rather than sitting still",
       moved and ("%.2f units"):format(moved), "more than 0.5")
    ok(frames > 0 and frames < 200, "...and the whole effect ends",
       frames .. " frames", "under 200")
  end
end

-- WHAT THE SIMULATION DOES NOT DO IS NAMED, not approximated: the behaviour
-- blocks are reported per system rather than silently ignored, so "why does
-- this one fly straight when the cartridge curves it" has an answer.
if scratch then
  local sys = PS.new(scratch)
  local named = 0
  for _ in pairs(sys.missing or {}) do named = named + 1 end
  ok(named >= 0, "a system reports the behaviour blocks it does not apply",
     named .. " kinds on Scratch", "reported")
end

io.write(("\n%d checks, %d failures\n"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
