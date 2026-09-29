-- Gen4BallAnim: Sinnoh's thrown Poke Ball.
--
-- WHY THIS FILE EXISTS.
--
-- Item 6 of the play-test list: *"Ball catching animations do not play"*.  They
-- did not, because `BattleState:ballChain` had a Gen 3 branch, a Gen 2 branch
-- and a Gen 1 fallback and no Gen 4 one -- so Sinnoh replayed Gen 1 animation
-- names (`TOSS_ANIM`, `POOF_ANIM`, `HIDEPIC_ANIM`, `SHAKE_ANIM`) that do not
-- exist in Platinum's data, and nothing drew at all.
--
-- THE ARCHIVE THE PORT FIRST WENT LOOKING IN WAS THE WRONG ONE, and it is worth
-- saying so here because it cost a pass: `ball_particle.narc`'s 117 effects are
-- the BALL CAPSULE SEALS.  pokeplatinum opens that NARC in exactly one place,
-- `ov12_02235E94.c`, from `BallCapsuleSealEffect`, and nowhere else.
--
-- The throw is not a particle effect.  It is a 2D cell animation out of
-- `pl_batt_obj`, and the port has been extracting its frames all along --
-- twenty sets of 16x16 cells under `ball_throws/`, which nothing had a name for
-- until `Gen4Battle.ballThrowFor`.
--
-- ---------------------------------------------------------------------------
-- THE FRAME TIMING IS THE CARTRIDGE'S, READ OFF ITS OWN NANR
-- ---------------------------------------------------------------------------
--
-- Not chosen, and not eyeballed against a video.  Each ball names an NANR in
-- `sBallThrowGraphics`, and each of those carries two sequences:
--
--   SEQUENCE 0, looping -- the ball SPINNING in flight.
--   SEQUENCE 1, one-shot -- the ball OPENING.
--
-- Transcribed as `{ cell, delay }` pairs in the cartridge's own frame units:
--
--   shared_anim          spin 0:2 1:2 2:6 3:2 4:2 5:2 6:6 7:2   (24 per turn)
--                        open 0:10 8:10 9:50                    (70)
--   quick_dusk_heal_anim spin 0:2 1:2 2:2 3:2 4:2 5:2 6:2 7:2   (16 per turn)
--                        open 0:10 8:10 9:50                    (70)
--   bait_anim            spin 0:2 1:2 2:2 3:2                   (8)
--                        open 0:60                              (60)
--   mud_anim             spin 0:2 1:2 2:2 3:2                   (8)
--                        open 0:6 4:6 5:6 6:50                  (68)
--
-- THE QUICK, DUSK AND HEAL BALLS SPIN FASTER than every other ball -- 16 frames
-- a revolution against 24 -- and that is a detail nobody would arrive at by
-- taste.  It is the reason this reads the four tables rather than one.
--
-- ---------------------------------------------------------------------------
-- WHAT IS *NOT* FROM THE CARTRIDGE, STATED PLAINLY
-- ---------------------------------------------------------------------------
--
-- The NANR says which cell is on screen and for how long.  It says nothing
-- about WHERE the ball is, because the path is driven by code
-- (`ov12_02235E94.c`'s `BallRotation`) and not by the animation.  So:
--
--   * the ARC -- a parabola from beside the player to the target,
--   * the BOUNCE and the settle,
--   * the SHAKE -- how far it rocks and how long each rock takes,
--
-- are this port's, not Platinum's, and they are the parts to distrust first if
-- the throw looks wrong against a real cartridge.  They are gathered in `ARC`
-- and `SHAKE` below so that replacing them with measured numbers later is one
-- edit and not an archaeology exercise.

local Gen4BallAnim = {}
Gen4BallAnim.__index = Gen4BallAnim

-- { cell, delay } in cartridge frames, straight off each NANR.
local SEQ = {
  shared = {
    spin = { {0,2},{1,2},{2,6},{3,2},{4,2},{5,2},{6,6},{7,2} },
    open = { {0,10},{8,10},{9,50} },
  },
  quick_dusk_heal = {
    spin = { {0,2},{1,2},{2,2},{3,2},{4,2},{5,2},{6,2},{7,2} },
    open = { {0,10},{8,10},{9,50} },
  },
  bait = {
    spin = { {0,2},{1,2},{2,2},{3,2} },
    open = { {0,60} },
  },
  mud = {
    spin = { {0,2},{1,2},{2,2},{3,2} },
    open = { {0,6},{4,6},{5,6},{6,50} },
  },
}

-- Which NANR each ball names, from the fourth column of `sBallThrowGraphics`.
local ANIM_FOR = {
  dusk_ball = "quick_dusk_heal", heal_ball = "quick_dusk_heal",
  quick_ball = "quick_dusk_heal", bait = "bait", mud = "mud",
}

function Gen4BallAnim.sequencesFor(ballName)
  return SEQ[ANIM_FOR[ballName or ""] or "shared"]
end

-- THE PORT'S OWN NUMBERS.  See the note above: these are the first thing to
-- doubt, and they are deliberately together.
-- ---------------------------------------------------------------------------
-- THE TRAJECTORY IS THE CARTRIDGE'S TOO, NOW
-- ---------------------------------------------------------------------------
--
-- These were the port's own invention, and the note above said so and said they
-- were the parts to distrust first.  They have now been looked up.
--
-- Every throw in Platinum is one `BallThrow` with a `mode` and a `type`.
-- `sBallThrowTypes[battlerType]` picks the type, `ov12_022378A0` sets the
-- DESTINATION, arc radius and duration from it, and `ov12_02237B14` sets the
-- ORIGIN -- all in `src/battle_anim/ov12_02235E94.c`.  Two of those types are
-- what this file needs:
--
--   type 6  -- the player's own send-out, from `BALL_THROW_MODE_TRAINER_SEND_OUT`
--             origin (10, 100)      destination battler pos + 32y
--             radius 48             20 frames
--
--   type 15 -- the capture throw, from `BALL_THROW_MODE_THROW`
--             origin (-30, 160)     destination enemy pos + 8y
--             radius 64             16 frames
--
-- (10, 100) is the left edge at about hand height: the trainer's own throw.
-- (-30, 160) is OFF-SCREEN below and to the left, which is the player's hand
-- below the camera -- the capture ball flies in from outside the frame, which is
-- why guessing it from what is visible could never have produced it.
--
-- The destinations are `BATTLER_POS_SOLO_PLAYER` (64, 112) and
-- `BATTLER_POS_SOLO_ENEMY` (192, 48) from `constants/battle/battle_anim.h`,
-- which are the same two the port already uses -- so the coordinate space is
-- the DS's and these numbers transfer without scaling.
--
-- THE ARC IS NOT THE PARABOLA THIS FILE USED.  `XYTransformContext_InitParabolic`
-- is a linear interpolation plus a REVOLUTION from 90 to 270 degrees, and
-- `RevolutionContext_Update` applies it as `cos(angle) * radius` on y with the x
-- radius set to zero.  cos across 90..270 is 0 at both ends and -1 in the
-- middle, so the true curve is
--
--     y = lerp(fromY, toY, u) - radius * sin(PI * u)
--
-- against the `4u(1-u)` this file had.  The same shape family, but the sine is
-- fuller through the middle, and it is the cartridge's own function.
local THROW = {
  -- MEASURED, and used.  Nothing here interacts with a phase the port invented.
  release = { frames = 20, radius = 48, fromX = 10, fromY = 100, toDY = 32 },
  -- Measured origin, radius and duration -- these only govern the FLIGHT.
  -- `toDY` is deliberately left at 0 rather than the cartridge's 8: the landing
  -- point is the one number the `drop` phase below also moves, `drop` is still
  -- the port's, and the cartridge reaches its resting place with a SECOND
  -- parabola this pass did not read.  Correcting one end of a chain whose other
  -- end is a guess makes the throw worse, not better.  The 8 is recorded here so
  -- the next pass does not have to find it again.
  catch   = { frames = 16, radius = 64, fromX = -30, fromY = 160, toDY = 0 },
  -- A FOE'S SEND-OUT IS PLACED, NOT THROWN -- and that is measured for Platinum
  -- now rather than carried over from the Gen 3 note.  The enemy battler types
  -- take `ov12_022378A0`'s cases 0..5, which set the destination to the sprite's
  -- own position with radius 0 over 12 frames: the ball does not travel at all.
  -- Nothing calls this yet; it is here because the measurement was made.
  placed  = { frames = 12, radius = 0, fromX = nil, fromY = nil, toDY = 38 },
}
local SHAKE = {
  frames = 18,   -- one rock, out and back
  angle = 0.30,  -- radians at the extreme
  gap = 14,      -- still frames between rocks
}
-- Where the ball ends up once it has swallowed the Pokemon.  The foe's slot is
-- where the Pokemon's MIDDLE is, and a ball that stops there hangs in the air
-- in front of its face -- which is what the first version of this did, and it
-- read as a bug rather than as a throw.  `drop` carries it down to the platform
-- the foe was standing on.
local DROP = { frames = 12, by = 26 }
Gen4BallAnim.DROP = DROP

-- WHEN, INSIDE THE OPEN SEQUENCE, THE POKEMON IS DRAWN IN.
--
-- Also the port's.  The NANR says the ball is open from its second frame (cell
-- 8 at frame 10) and stays open through cell 9 to frame 70; it does not say
-- when the Pokemon goes in, because on the cartridge that is the mon sprite's
-- own callback and not this animation's business.  Starting at 10 puts the
-- absorb exactly when the ball first opens, which is the one part of it that
-- IS pinned by the NANR.
local ABSORB = { from = 10, span = 30 }
Gen4BallAnim.ABSORB = ABSORB
Gen4BallAnim.ARC, Gen4BallAnim.SHAKE = ARC, SHAKE

-- Flatten a { cell, delay } list into one cell per frame, so the draw side asks
-- a plain index and no one re-derives the timing.
local function expand(seq)
  local out = {}
  for _, step in ipairs(seq) do
    for _ = 1, step[2] do out[#out + 1] = step[1] end
  end
  return out
end

-- new(opts) -> anim
--   ball    the art name from `Gen4Battle.ballThrowFor`
--   to      { x, y } the target, in DS pixels
--   caught  true if it holds
--   shakes  how many rocks before the answer
function Gen4BallAnim.new(opts)
  opts = type(opts) == "table" and opts or {}
  local seq = Gen4BallAnim.sequencesFor(opts.ball)
  local self = setmetatable({
    ball = opts.ball or "poke_ball",
    to = opts.to or { x = 192, y = 48 },
    caught = opts.caught and true or false,
    -- WHICH SIDE THIS BALL IS ABOUT.  A capture is always about the foe, but a
    -- SEND-OUT can be about either -- and without the question the player's own
    -- throw would shrink the Pokemon standing opposite, which is the mistake the
    -- Gen 3 path records having made.
    side = (opts.side == "player") and "player" or "enemy",
    -- "catch" throws a ball AT a Pokemon; "release" throws one to let a Pokemon
    -- OUT.  The frames and their timings are the same either way -- the
    -- cartridge has one throw animation -- so only the phase list differs.
    mode = (opts.mode == "release") and "release" or "catch",
    shakes = math.max(0, math.floor(tonumber(opts.shakes) or 0)),
    spin = expand(seq.spin),
    open = expand(seq.open),
    t = 0, done = false,
    cell = 0, angle = 0, visible = true,
  }, Gen4BallAnim)
  -- WHICH OF THE CARTRIDGE'S THROWS THIS IS.  A release about the foe is the
  -- one that does not travel; everything else flies.
  local key = "catch"
  if self.mode == "release" then
    key = (self.side == "player") and "release" or "placed"
  end
  self.throw = THROW[key]
  -- The destination offset is the cartridge's, applied here for the same reason
  -- it is applied there: the battler position is the Pokemon's middle, and a
  -- ball that stops at a Pokemon's middle hangs in front of its face.
  self.to = { x = self.to.x, y = self.to.y + self.throw.toDY }
  -- A placed ball has no origin of its own -- it starts where it ends.
  self.fromX = self.throw.fromX or self.to.x
  self.fromY = self.throw.fromY or self.to.y
  self.x, self.y = self.fromX, self.fromY
  -- THE FIRST FRAME HAS TO BE RIGHT BEFORE THE FIRST UPDATE, not after it.
  -- These were left to `update` to set, and for one tick -- between the ball
  -- being created and its own `update` first running -- `monHidden` was nil,
  -- `battlerHidden` therefore answered false, and the Pokemon was drawn at full
  -- size standing on the platform while its ball was still at the left edge.
  -- One frame, which is exactly long enough to be seen and not long enough to
  -- be believed, and it took a per-tick trace to find.
  if self.mode == "release" then
    self.monScale, self.monBlend, self.monHidden = 0, 1, true
  else
    self.monScale, self.monBlend, self.monHidden = 1, 0, false
  end
  self.phases = self:buildPhases()
  return self
end

-- The whole timeline up front, so `estimate` is the length rather than a guess
-- at it -- the queue holds for exactly as long as the animation runs.
function Gen4BallAnim:buildPhases()
  local p = {}
  p[#p + 1] = { kind = "arc",   length = self.throw.frames }
  p[#p + 1] = { kind = "open",  length = #self.open }

  -- A RELEASE ENDS WHERE A CATCH BEGINS.  The ball flies out, opens, the
  -- Pokemon comes out of it, and the ball is gone -- no drop, no shakes and no
  -- answer to wait for.
  if self.mode == "release" then
    local total = 0
    for _, ph in ipairs(p) do ph.at = total total = total + ph.length end
    self.total = total
    return p
  end

  p[#p + 1] = { kind = "drop",  length = DROP.frames }
  for _ = 1, self.shakes do
    p[#p + 1] = { kind = "gap",   length = SHAKE.gap }
    p[#p + 1] = { kind = "shake", length = SHAKE.frames }
  end
  p[#p + 1] = { kind = "settle", length = self.caught and 30 or 16 }
  if not self.caught then p[#p + 1] = { kind = "burst", length = #self.open } end
  local total = 0
  for _, ph in ipairs(p) do ph.at = total total = total + ph.length end
  self.total = total
  return p
end

function Gen4BallAnim:estimate() return self.total end
function Gen4BallAnim:isDone() return self.done end

function Gen4BallAnim:phaseAt(t)
  for _, ph in ipairs(self.phases) do
    if t < ph.at + ph.length then return ph, t - ph.at end
  end
  return self.phases[#self.phases], 0
end

function Gen4BallAnim:update()
  if self.done then return end
  self.t = self.t + 1
  if self.t >= self.total then self.done = true end
  local ph, k = self:phaseAt(math.min(self.t, self.total - 1))
  local tx, ty = self.to.x, self.to.y
  self.visible = true
  self.angle = 0

  if ph.kind == "arc" then
    local u = k / math.max(1, ph.length - 1)
    self.x = self.fromX + (tx - self.fromX) * u
    -- The cartridge's own curve: a straight line plus `cos` across 90..270
    -- degrees, which is zero at both ends and `radius` at the middle.  See the
    -- derivation above `THROW` -- this is `sin(PI * u)`, not `4u(1 - u)`.
    self.y = self.fromY + (ty - self.fromY) * u
      - self.throw.radius * math.sin(math.pi * u)
    -- The spin loops for the whole flight; the cartridge's own cadence.
    self.cell = self.spin[(k % #self.spin) + 1]
  elseif ph.kind == "open" then
    self.x, self.y = tx, ty
    self.cell = self.open[math.min(k + 1, #self.open)]
    -- DRAWN IN, not switched off.  `monScale` shrinks the Pokemon and
    -- `monBlend` carries its centre to the ball's, which is the pair the Gen 3
    -- path in this engine already uses -- so the two generations describe an
    -- absorb the same way rather than each inventing fields.
    local a = (k - ABSORB.from) / ABSORB.span
    if a < 0 then a = 0 elseif a > 1 then a = 1 end
    if self.mode == "release" then
      -- ...and the same span run the other way: the Pokemon comes OUT.  The
      -- ball fades as it does, because a ball still sitting there once its
      -- Pokemon is standing beside it is the tell that nothing cleaned up.
      self.monScale, self.monBlend = a, 1 - a
      self.visible = a < 1
    else
      self.monScale, self.monBlend = 1 - a, a
    end
  elseif ph.kind == "drop" then
    -- Closed, and falling the last short way onto the platform.
    local u = k / math.max(1, ph.length - 1)
    self.x, self.y = tx, ty + DROP.by * u
    self.cell = 0
  elseif ph.kind == "gap" or ph.kind == "settle" then
    self.x, self.y = tx, ty + DROP.by
    self.cell = 0
  elseif ph.kind == "shake" then
    self.x, self.y = tx, ty + DROP.by
    self.cell = 0
    -- One rock out and back, which is a full sine period.
    self.angle = math.sin(k / math.max(1, ph.length) * math.pi * 2) * SHAKE.angle
  elseif ph.kind == "burst" then
    self.x, self.y = tx, ty + DROP.by
    self.cell = self.open[math.min(k + 1, #self.open)]
    -- ...and back out again, the same span run the other way.
    local a = (k - ABSORB.from) / ABSORB.span
    if a < 0 then a = 0 elseif a > 1 then a = 1 end
    self.monScale, self.monBlend = a, 1 - a
  end

  -- THE POKEMON IS INSIDE THE BALL, and the screen has to say so.
  --
  -- The first version left the foe drawn at full size for the whole animation,
  -- so the ball opened, closed, dropped and shook with the Pokemon standing
  -- behind it -- which reads as the ball failing to catch anything.  The second
  -- hid it outright the instant the ball arrived, which is right about where it
  -- ends up and wrong about how it gets there: it POPPED.
  --
  -- Now it is only hidden once the absorb has finished shrinking it, so the
  -- phases that draw it (`arc`, `open`, `burst`) hand the screen a scale and a
  -- blend instead of a yes or no.
  if ph.kind == "arc" then
    if self.mode == "release" then
      -- Not on the field yet: it is inside the ball that is still in the air.
      self.monScale, self.monBlend, self.monHidden = 0, 1, true
    else
      self.monScale, self.monBlend, self.monHidden = 1, 0, false
    end
  elseif ph.kind == "open" or ph.kind == "burst" then
    self.monHidden = (self.monScale or 0) <= 0
  else
    self.monScale, self.monBlend, self.monHidden = 0, 1, true
  end
end

-- Asked by `Gen4Battle.battlerHidden`, which is the seam the move animations
-- already use -- so this does not invent a second way to hide a battler.
--   isPlayer: true for the player's side.  Only the FOE goes into the ball.
function Gen4BallAnim:hidesMon(isPlayer)
  local mine = (self.side == "player") == (isPlayer and true or false)
  return mine and self.monHidden == true
end

-- absorbFor(isPlayer) -> scale, blend, or nil when this battler is untouched.
--
-- Nil rather than 1,0 for a battler the ball has nothing to do with, so the
-- draw side takes its ordinary path instead of an identity transform that only
-- looks like one.
function Gen4BallAnim:absorbFor(isPlayer)
  local mine = (self.side == "player") == (isPlayer and true or false)
  if not mine then return nil end
  local scale = self.monScale
  if scale == nil or scale >= 1 then return nil end
  return scale, self.monBlend or 0
end

return Gen4BallAnim
