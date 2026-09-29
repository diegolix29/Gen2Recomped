-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Gen 4 (Platinum) MOVE ANIMATION PLAYER -- the fourth of these, after
-- `AnimPlayer` (Gen 1), `Gen2AnimPlayer` and `Gen3MoveAnim`.
--
-- Reported from play: *"scratch doesnt work and doesnt show a move animation or
-- fx"*. There was no Gen 4 animator at all; `BattleState` built three behind
-- `pcall`s and there was no fourth, so nothing was asked to draw anything.
--
-- WHAT IT RUNS. `src/import/Gen4MoveAnim` decodes the cartridge's bytecode and
-- the `move_anims` import stage writes every program to the cache. This walks
-- one of those programs a frame at a time: the waits, the loops, the sounds and
-- the script functions that move the two Pokemon.
--
-- WHY THAT SUBSET AND NOT ALL OF IT. Measured over the 501 decoded programs:
--
--     440 of 501 move the Pokemon sprites        <- this file
--     426 of 501 create 3D particle emitters     <- needs an SPA reader
--      59 of 501 touch the background
--      32 of 501 use 2D cell-actor sprites
--
-- and of `callfunc`'s 2,286 calls across 76 distinct functions, the ones that
-- need no particle engine are most of them: RenderPokemonSprites 477, Shake
-- 398, FadeBg 272, FadeBattlerSprite 270, MoveBattler 129, MoveBattlerX2 86,
-- ScaleBattlerSprite 53, HideBattler 50, ShakeBg 42. So the motion, the timing
-- and the sound of nearly every move in Sinnoh are reachable WITHOUT reading a
-- single SPA file, and that is the whole argument for this file existing before
-- the particle engine rather than after it.
--
-- WHAT IS STILL MISSING IS SAID OUT LOUD. Every command this player does not
-- implement is COUNTED BY NAME in `self.unsupported`, so "what did this move
-- need that it did not get" is a question with an answer instead of a shrug. A
-- silent skip is how a port ends up believing it plays animations it does not.
--
-- THE SEAM IT PLUGS INTO is the one Emerald's animator already defined:
-- `monOffset`, `monTint` and `monAffine`, each taking `isPlayer` and returning
-- the transform for that side. `BattleState:gen3AnimShake` / `gen3AnimTint` /
-- `gen3AnimSquash` call exactly those three on `self.gen3Anim`, so a Gen 4 arm
-- beside them is three lines rather than a second draw path -- and a second
-- draw path would have none of the grow-in scale, hit shake or rotate that
-- `drawBattlerPic` already carries.

local Gen4MoveAnim = require("src.import.Gen4MoveAnim")
local Gen4ParticleSystem = require("src.battle.Gen4ParticleSystem")
local Gen4CellAnim = require("src.import.Gen4CellAnim")
local Gen4AnimMath = require("src.battle.Gen4AnimMath")

-- ---------------------------------------------------------------------------
-- WHERE AN EMITTER SITS, which is the one thing `createemitter` says that this
-- port has to answer in two dimensions.
--
-- `BattleParticleUtil_CreateEmitter` indexes a 23-entry table of callbacks by
-- the command's third operand, and pret has that table decoded and NAMED in
-- `src/battle_anim/battle_particle_util.c`. So this is a reading, not a guess:
-- every row below is one of those names reduced to an origin this port can
-- place. Row 3 is SetPosToAttacker; row 4 SetPosToDefender; rows 7-11 are the
-- five convergence variants and 12-16 the five magnet ones, whose POSITION this
-- honours and whose PULL it does not -- and the pull is already what
-- `Gen4ParticleSystem.missing` reports, so the gap is named in one place.
--
-- `axis` means the emitter's own axis points from its origin at the other
-- battler: the cartridge sets it so a beam leaves the attacker aimed at the
-- target rather than along the resource's stored axis.
local EMITTER_AT = {
  [0]  = { origin = "emitter" },                      -- Nop
  [1]  = { origin = "enemy" },                        -- SetPosToEnemy1 (unused)
  [2]  = { origin = "player" },                       -- SetPosToPlayer1 (unused)
  [3]  = { origin = "attacker" },                     -- SetPosToAttacker
  [4]  = { origin = "defender" },                     -- SetPosToDefender
  [5]  = { origin = "attacker", axis = true },        -- SetAxisAndPos
  [6]  = { origin = "defender", axis = true },        -- ...Reverse
  [7]  = { origin = "attacker", axis = true },        -- ConvergeDefault
  [8]  = { origin = "midpoint", axis = true },        -- ConvergeCenter
  [9]  = { origin = "defender", axis = true },        -- ConvergeDefender
  [10] = { origin = "attacker", axis = true },        -- ConvergeAttacker
  [11] = { origin = "attacker", axis = true },        -- ConvergeExplicit
  [12] = { origin = "attacker", axis = true },        -- MagnetDefault
  [13] = { origin = "midpoint", axis = true },        -- MagnetCenter
  [14] = { origin = "defender", axis = true },        -- MagnetDefender
  [15] = { origin = "attacker", axis = true },        -- MagnetAttacker
  [16] = { origin = "attacker", axis = true },        -- MagnetExplicit
  [17] = { origin = "emitter" },                      -- Generic
  [18] = { origin = "midpoint" },                     -- SetPosBasedOnBattlers
  [19] = { origin = "attacker" },                     -- SetPosToAttackerSide
  [20] = { origin = "defender" },                     -- SetPosToDefenderSide
  [21] = { origin = "attacker" },                     -- SetPosToAttacker2
  [22] = { origin = "emitter" },                      -- Nop2
}

-- ---------------------------------------------------------------------------
-- THE 2D CELL-ACTOR SPRITE CALLBACKS, from pret's own `sBattleAnimSpriteFuncs`
-- in `src/battle_anim/script_func_tables.c` -- thirty-three entries, and all but
-- two are named after the MOVE whose sprite they drive.
--
-- WHAT THEY ALL SHARE, and what this port does: `addspritewithfunc` places the
-- sprite at the DEFENDER's position, loads its four resources, copies its
-- trailing arguments into script vars 0..n-1 (zeroing the rest), and only then
-- calls the callback. So the sprite, its art and its animation are generic; the
-- callback is the per-move MOTION on top.
--
-- WHICH OF THEM THIS PORT APPLIES is recorded at `SPRITE_MOTION` further down,
-- with the reason each is a separate reading of pret rather than one shared
-- routine: `Constrict` squeezes, `Bonemerang` arcs out and back, `FollowMe`
-- oscillates off a hand-written offset table. A guessed motion is worse than a
-- still sprite in the right place, because it looks deliberate.
local SPRITE_FUNCS = {
  [0] = "SpriteExample", "StringShot", "Kinesis", "Trick", "Metronome",
  "Constrict", "Bonemerang", "ScaryFace", "Foresight", "LockOn", "Swagger",
  "MeanLook", "Torment", "BatonPass", "Unused", "Grudge", "GrassWhistle",
  "IcicleSpear", "FakeOut", "Taunt", "HelpingHand", "Assist", "MetalClaw",
  "Ingrain", "FrenzyPlant", "OffsetAndAnimate", "FollowMe", "Fissure",
  "EscapeItem", "Sleep", "Burn", "Freeze", "ConfusionStatus",
}
local SPRITE_FUNC_OFFSET_AND_ANIMATE = 25

-- `BATTLE_ANIM_SCRIPT_VAR_COUNT` -- ten slots, shared by `setvar`,
-- `resetvars` and `addspritewithfunc`'s trailing arguments.
local VAR_COUNT = 10

-- WHICH SEQUENCE A SPRITE PLAYS, AND IT IS NOT ALWAYS THE FIRST.
--
-- Thirteen of the twenty-six callbacks call `ManagedSprite_SetAnim`, and three of
-- them do it with a rule this port can state exactly:
--
--   Metronome (4)  SetAnim(attacker is ENEMY  and 1 or 0)
--   FollowMe  (26) SetAnim(attacker is ENEMY  and 1 or 0)   -- identical
--   Fissure   (27) SetAnim(defender is PLAYER and 1 or 0)
--
-- The other ten either drive SEVERAL sprites with a sequence each (Taunt,
-- HelpingHand, GrassWhistle) or call `SetAnimateFlag` and `SetAnimationFrame`,
-- which are not sequence selection at all.
--
-- IT MATTERS BECAUSE TWELVE OF THE 37 ANIMATION BANKS HOLD MORE THAN ONE
-- SEQUENCE -- nine hold two and three hold more -- so playing the first was right
-- by luck for 25 members and wrong for the rest whenever the battle ran the other
-- way up.
local SPRITE_SEQUENCE = {
  [4] = function(attackerIsPlayer) return attackerIsPlayer and 0 or 1 end,
  [26] = function(attackerIsPlayer) return attackerIsPlayer and 0 or 1 end,
  -- The DEFENDER's side, not the attacker's: with the player attacking, the
  -- defender is the enemy, so this is the opposite way round.
  [27] = function(attackerIsPlayer) return attackerIsPlayer and 0 or 1 end,
}

-- FISSURE PUTS ITS SPRITE AT AN ABSOLUTE HEIGHT, not an offset from a battler:
-- the defender's X, and then Y = 126 when the defender is on the player's side
-- and 32 when it is on the enemy's. Both are screen coordinates in the DS's
-- 256x192 space, straight out of `script_funcs_3.c`.
local FISSURE_Y_PLAYER = 126
local FISSURE_Y_ENEMY = 32
local SPRITE_FUNC_FISSURE = 27

local Player = {}
Player.__index = Player

-- ---------------------------------------------------------------------------
-- The cartridge's own constants
-- ---------------------------------------------------------------------------

-- Target masks, from include/constants/battle/battle_anim.h.  A target is a
-- BITMASK of who plus which kind of sprite, not an enum, which is why a
-- straight equality test against ATTACKER would miss every real value.
Player.ATTACKER          = 0x002   -- 1 << 1
Player.ATTACKER_PARTNER  = 0x004   -- 1 << 2
Player.DEFENDER          = 0x008   -- 1 << 3
Player.DEFENDER_PARTNER  = 0x010   -- 1 << 4
Player.NOT_ATTACKER      = 0x020   -- 1 << 5
Player.ALL_BATTLERS      = 0x040   -- 1 << 6
Player.BATTLER_SPRITES   = 0x100   -- 1 << 8
Player.POKEMON_SPRITES   = 0x200   -- 1 << 9
Player.BACKGROUND        = 0x400   -- 1 << 10
Player.SPECIFIC_BATTLER  = 0x800   -- 1 << 11

-- The script functions this player implements, by the id `callfunc` names.
-- Numbered from pret's sBattleAnimScriptFuncs table, whose position IS the id.
Player.FUNC = {
  NOP = 0,
  -- pret's names, and they are accurate: all three are DEMOS whose tasks spend
  -- one frame in RUNNING, one in DONE and end. See the arms below.
  ANIM_EXAMPLE = 1,
  SOUND_EXAMPLE = 2,
  GENERIC_EXAMPLE = 3,
  SHAKE = 36,
  FADE_BG = 33,
  FADE_BATTLER_SPRITE = 34,
  HIDE_BATTLER = 40,
  SCALE_BATTLER_SPRITE = 42,
  MOVE_BATTLER_X2 = 52,
  MOVE_BATTLER = 57,
  REVOLVE_BATTLER = 60,
  MOVE_EMITTER_LINEAR = 65,
  MOVE_EMITTER_PARABOLIC = 66,
  SHAKE_BG = 68,
  REVOLVE_EMITTER = 72,
  MOVE_EMITTER_VIEWPORT_TOP = 73,
  SET_BG_GRAYSCALE = 74,
  SET_POKEMON_SPRITE_PRIORITY = 75,
  RENDER_POKEMON_SPRITES = 78,
}

-- Each function's operands, by the index `BattleAnimSystem_GetScriptVar` reads
-- them at -- the `#define <FUNC>_VAR_<NAME> n` lines beside each handler. These
-- are ZERO-BASED like the cartridge's, and `arg()` below adds the one.
Player.VARS = {
  [36] = { extentX = 0, extentY = 1, interval = 2, amount = 3, targets = 4 },
  [57] = { frames = 0, offsetX = 1, offsetY = 2, target = 3 },
  [52] = { frames = 0, offset = 1, target = 2 },
  [40] = { target = 0, hide = 1 },
  [42] = { target = 0, startX = 1, endX = 2, startY = 3, endY = 4,
           reference = 5, holdCycles = 6, frames = 7 },
  [34] = { target = 0, stepFrames = 1, endDelay = 2, colour = 3, alpha = 4,
           holdFrames = 5 },
  [33] = { bgType = 0, delay = 1, startValue = 2, endValue = 3, colour = 4 },
  -- `EmitterAnimationContext_Init`'s nine, shared by both A2B functions.
  -- `RevolveEmitter` (72) uses the *_ALT layout instead -- emitterId, mode, type,
  -- frames, startDelay, params -- which is why it is not on this table.
  [65] = { emitterId = 0, offsetX = 1, offsetY = 2, startDelay = 3, frames = 4,
           radius = 5, mode = 6, params = 7, curve = 8 },
  [66] = { emitterId = 0, offsetX = 1, offsetY = 2, startDelay = 3, frames = 4,
           radius = 5, mode = 6, params = 7, curve = 8 },
  [68] = { extentX = 0, extentY = 1, interval = 2, amount = 3, cycles = 4,
           target = 5 },
  -- `RevolveBattler`'s three, and the oval's radii are constants rather than
  -- operands -- see Gen4AnimMath.ovalRevolution.
  [60] = { target = 0, revs = 1, framesPerRev = 2 },
  -- `RevolveEmitter`'s TEN, and they are NOT the `_ALT` layout. An earlier note in
  -- this port said they were; the `_ALT` six (emitterId, mode, type, frames,
  -- startDelay, params) belong to `MoveEmitterViewportTop` (73), which is the
  -- entry below. Both are read from pret's own `#define`s beside each handler.
  [72] = { emitterId = 0, startX = 1, endX = 2, startY = 3, endY = 4,
           radiusX = 5, radiusY = 6, frames = 7, mode = 8, particleSystem = 9 },
  [73] = { emitterId = 0, mode = 1, kind = 2, frames = 3, startDelay = 4,
           params = 5 },
  [74] = { grayscale = 0 },
  -- `SetPokemonSpritePriority`'s SEVEN, and the last two only exist on the calls
  -- that pass them: `Func_SetPokemonSpritePriority` hands over five operands and
  -- `Func_DarkVoid` seven, through the same function id. `callFunc` zeroes the
  -- vars a call does not supply, so mode and windowType read 0 -- which is
  -- POKEMON_SPRITE_PRIORITY_MODE_DEFAULT and window type 0 -- exactly as the
  -- cartridge's own `BattleAnimSystem_GetScriptVar` would answer them.
  [75] = { spriteId = 0, maxFrames = 1, bg = 2, spritePriority = 3, battler = 4,
           mode = 5, windowType = 6 },
  [78] = { frames = 0 },
}

-- ---------------------------------------------------------------------------
-- The sound channel
-- ---------------------------------------------------------------------------

-- 1,220 SOUND COMMANDS OVER 499 OF THE 501 PROGRAMS, and until this pass NOT ONE
-- OF THEM REACHED THE ENGINE. The player called `self.onSound(id)` and nothing
-- anywhere set `onSound`, so every Sinnoh move was silent -- and the gap report
-- could not see it, because a command that calls a nil callback is not a command
-- that was skipped. The same shape as the `Data.lua` name that made the whole
-- player invisible and the summary picture nobody drew into: A CHANNEL WIRED TO
-- NOTHING REPORTS NOTHING.
--
-- THE CORPUS, and it decided what is worth building:
--   playpannedsoundeffect   649 / 347 programs   the workhorse
--   playdelayedsoundeffect  203 /  99            a sound task
--   playloopedsoundeffect   199 / 156            a sound task
--   playmovingsoundeffect*  113 /  78            a sound task (pans over time)
--   playsoundeffect          26 /  26
--   stopsoundeffect          14 /  10
--   playpokemoncry            8 /   5            THE ONE THAT CAN MAKE A NOISE
--   waitforpokemoncries       8 /   5            the only sound command that WAITS,
--                                                and it is the same five programs
--   pansoundeffects           0                  implemented, unexercised
--   waitforsoundeffects       0                  implemented, unexercised
--   playmovingsoundeffect{nocorrection,atkdef2}
--                             0                  implemented, unexercised
--
-- THE OPCODE NUMBERS ARE NOT WHERE A HAND-COUNT PUTS THEM. A first draft of these
-- measurements read `playpokemoncry` as opcode 64 -- it is 65 -- and 64 is
-- `jumpifbattlerside`, which carries three operands and no cry. The counts came out
-- plausible ("37 cries, 36 of them normal") off a command with nothing to do with
-- sound. Every number above is now taken by looking the NAME up in
-- `Gen4MoveAnim.OPCODES`.
--
-- THE EFFECTS CANNOT MAKE A NOISE YET AND THE CRIES CAN. Platinum's effects are
-- SDAT SEQUENCES -- notes over banks over wave archives -- and playing one means
-- writing a synthesiser. The CRIES are single PCM8 samples and the import stage
-- already writes all 493 of them into the same `audio.cries` table Gen 1, 2 and 3
-- fill. So what this layer delivers now is: every cry audible, and every effect
-- an EVENT with the right id, the right pan and the right FRAME -- which is the
-- half a sequence player cannot work out for itself.
--
-- `BATTLE_SOUND_PAN_*`, and the corpus uses all three and nothing else: -117 on
-- 223 calls, 0 on 65, +117 on 361.
Player.SOUND_PAN_LEFT = -117
Player.SOUND_PAN_CENTRE = 0
Player.SOUND_PAN_RIGHT = 117

-- `enum PokemonCryMod`. ALL EIGHT CRIES IN THE CARTRIDGE ASK FOR A DIFFERENT ONE --
-- 0, 3, 4, 6, 7, 8, 9 and 10, one each, which are NORMAL, MID_MOVE, HYPERVOICE_1,
-- FAINT, HYPERVOICE_2, HOWL_1, HOWL_2 and UPROAR_1. They name the moves. So there is
-- no common case to default to and the operand is passed through: a port that
-- dropped it would play one cry eight times where the cartridge plays eight.
Player.CRY_NORMAL = 0
Player.CRY_HALF_DURATION = 1

-- pret's own upper bound on `waitforsoundeffects`: it gives up after ninety
-- frames rather than waiting forever on a sound that will not end.
local SOUND_WAIT_CAP = 90

-- ---------------------------------------------------------------------------
-- The effect background layer
-- ---------------------------------------------------------------------------

-- `switchbg` swaps the battle backdrop for one of fifty-eight pictures out of
-- pl_batt_bg, and `restorebg` puts it back. 129 calls over 54 of the 501
-- programs, which makes it the largest single thing this player did not do.
--
-- THE LAYER IT USES IS THE ONE THE BACKDROP ALREADY LIVES ON. `BATTLE_BG_EFFECT`
-- is BG3, and outside a switch BG3 holds the ordinary battle background -- which
-- is why `BattleBgRestore_*` ends by loading the backdrop back INTO the effect
-- layer rather than by hiding it. Two consequences the port has to honour:
-- a `shakebg` aimed at the "effect" layer shakes the BACKDROP when no switch is
-- up (22 of its 42 calls), and the `fadebg` type that names the effect palette is
-- naming this layer's sixteen colours, not the particles'.
--
-- MEASURED OVER THE CORPUS, which is what decided how much of pret's machinery is
-- worth porting:
--   * 127 of the 129 calls use MODE_FADE and 2 use MODE_BLEND (one switch and one
--     restore, both in program 433). The fade path is the one that matters.
--   * `setbg` (21) and `switchbgex` (34) are used ZERO times. Both are here
--     anyway because they are three lines each; neither is exercised.
--   * the flag field is only ever 0x00 (44 calls), 0x02 MOVE (39) or 0x04 STOP
--     (46). The two WAVE flags and CANCEL never appear, so the scanline wave is
--     recorded and not drawn.
--   * `setbgswitchvar` appears 9 times and every one of them writes var 1.
--   * no program switches without restoring -- six restore more than once,
--     because a branch picks the path -- so the layer always comes down.
local BG_SWITCH_MODE_BLEND = 0
local BG_SWITCH_MODE_FADE = 1
local BG_SWITCH_MODE_FLAGS = 2
local BG_SWITCH_MODE_COUNT = 3

-- pret packs mode and flags into ONE operand: the low half is the mode and the
-- high half the flags. `BATTLE_BG_SWITCH_FLAGS(VAR)` shifts by 16, so the flag
-- values below are the SHIFTED-DOWN ones -- 0x02 and not 0x20000.
local BG_FLAG_MOVE = 0x02
local BG_FLAG_STOP = 0x04
local BG_FLAG_CANCEL = 0x08
local BG_FLAG_WAVE = 0x20
local BG_FLAG_REGISTER_WAVE = 0x40

-- THE ORDER MATTERS AND SO DOES THE OMISSION. `BattleBgSwitch_ApplyFlags` walks a
-- four-entry array and CANCEL is not in it -- the flag exists, the constant
-- exists, and `BattleBgSwitch_AnimCancel` is in the dispatch table, but nothing
-- ever reaches it through ApplyFlags. Written out so the gap is visible instead
-- of looking like a transcription slip; and no program sets CANCEL anyway.
local BG_FLAG_ORDER = { BG_FLAG_MOVE, BG_FLAG_STOP, BG_FLAG_WAVE,
                        BG_FLAG_REGISTER_WAVE }

local BG_STATE_NONE = 0
local BG_STATE_RUNNING = 1
local BG_STATE_PARTIAL = 2

-- `G2_SetBlendAlpha`'s EVA/EVB are five-bit fields the hardware CLAMPS AT 16, and
-- pret leans on that: a switch starts its coefficients at 0 and 31 and steps by
-- two, so the first eight steps of the rising side and the last eight of the
-- falling side are the only ones that change anything. Dividing by 16 after the
-- clamp is what turns a coefficient into an alpha.
local BG_BLEND_CLAMP = 16
local BG_BLEND_STEP = 2

-- `BlendColor`'s fraction is out of sixteen: `src + ((target - src) * f >> 4)`.
-- Used by the palette fades further down AND by the switch's fade mode up here.
local PALETTE_BLEND_MAX = 16

-- The switch's own script vars, by `BATTLE_ANIM_VAR_BG_*`.
Player.BG_VAR = {
  stepX = 0, stepY = 1, startX = 2, startY = 3,
  fadeType = 4, blendType = 5, animMode = 6, screenMode = 7,
}

-- `BATTLE_BG_FADE_TO_BLACK` is 0 and `_WHITE` is 1, and the colours are the two
-- the fade handlers name literally: GX_RGBA(0,0,0,0) and GX_RGBA(31,31,31,1).
local BG_FADE_COLOUR = { [0] = 0, [1] = 0x7FFF }

-- `BATTLE_BG_BLEND_*`: the coefficient pairs `BattleAnimSystem_CreateBgSwitch`
-- picks between. { fromA, fromB, targetA, targetB } -- A is the EFFECT side on a
-- switch and the BASE side on a restore, because the two handlers hand the same
-- two numbers to `G2_SetBlendAlpha` in the opposite order.
local BG_BLEND_COEFFS = {
  [0] = { 0, 31, 29, 2 },    -- FULL_B_TO_A:     effect 0 -> full, base full -> off
  [1] = { 0, 31, 15, 7 },    -- PARTIAL:         base full -> half
  [2] = { 7, 15, 29, 2 },    -- INVERSE_PARTIAL: effect half -> full
}

-- COMMANDS THIS PORT DELIBERATELY DOES NOT NEED, each with the reason, because
-- a list of gaps that includes things nobody intends to implement is a list
-- nobody reads. Same argument as `gen4_operand_roles.py`'s IN_OUT_HANDLES: a
-- skip has to be ARGUED FOR on the page rather than made silently, and anything
-- not on this list that this player ignores is a real gap that `missing()`
-- reports.
--
-- The cartridge allocates and frees a sprite manager, loads placeholder
-- resources into it, adds the two Pokemon to it and takes them out again. This
-- port already draws both battlers every frame through `drawBattlerPic`, so
-- the whole manager is bookkeeping for a renderer it does not have -- and
-- implementing it would mean drawing the Pokemon twice.
Player.NOT_NEEDED = {
  -- !! SIX OF THE EIGHT MON-SPRITE COMMANDS LEFT THIS TABLE, and the paragraph
  -- above is what was wrong: the sprite manager is NOT bookkeeping for a renderer
  -- this port does not have. `AddPokemonSprite` makes a second sprite out of the
  -- battler's own picture and one move animates it while the battler is hidden.
  -- The slot layer beside `Player.MON_SPRITE_SLOTS` records them; these two are
  -- all that is left, and both are argued rather than assumed:
  --   the dummy resources ARE placeholders -- the slots this port keeps are filled
  --   from the battler's own picture, so there is nothing for a resource id to
  --   name;
  --   `StopPokemonSpriteDrawTask` sets `pokemonSpriteDrawContexts[n].active = 0`
  --   and nothing else, and outside a double battle the task that field gates
  --   WAS NEVER STARTED -- the whole body of `StartPokemonSpriteDrawTask` past
  --   one hide sits inside `if (IsDoubleBattle == TRUE)`.
  ["loadpokemonspritedummyresources"] = "placeholder resources for slots this port fills from the battler's own picture",
  ["stoppokemonspritedrawtask"] = "clears `active` on a context whose task a single battle never starts",
  ["nop0"] = "a nop", ["nop1"] = "a nop", ["nop2"] = "a nop",
  ["nop3"] = "a nop", ["nop4"] = "a nop", ["nop5"] = "a nop",
  ["nop6"] = "a nop", ["nop7"] = "a nop", ["nop8"] = "a nop",
  ["nop9"] = "a nop", ["nop10"] = "a nop", ["nop11"] = "a nop",
  ["setcameraprojection"] = "there is no 3D camera here",
  ["setcameraflip"] = "there is no 3D camera here",
  ["canceltrackingtask"] = "nothing here tracks a battler for an emitter",
  -- !! AND THE ONE THAT WAS TOP OF THE GAP LIST WITHOUT BEING A GAP.
  -- `setextraparams` is the opcode pret cannot state a width for, because its
  -- handler is `GF_ASSERT(FALSE)` -- and GF_ASSERT is COMPILED OUT of the retail
  -- build, so on the cartridge the instruction reads its operands and does
  -- NOTHING. It is the most frequent command in the corpus after `delay` (742
  -- instructions, 159 of the 501 programs), so leaving it in the report put a
  -- no-op at the head of the work queue and pushed the real gaps down the page.
  -- Its WIDTH still matters and is still solved against the check -- what is not
  -- needed is a behaviour, because there is none.
  ["setextraparams"] = "pret's handler is GF_ASSERT(FALSE), compiled out of the "
                       .. "retail build: the instruction reads its operands and "
                       .. "does nothing",
  -- The two demo functions whose tasks nothing waits for. `AnimExample` is NOT
  -- here: it occupies an anim-task slot for two frames and is held.
  ["callfunc:soundexample"] = "a demo task that does nothing, on the sound queue "
                              .. "no wait in this player reads",
  ["callfunc:genericexample"] = "a demo task that does nothing, on a plain "
                                .. "SysTask nothing waits for",
}

-- A PROGRAM THAT NEVER ENDS MUST NOT TAKE THE BATTLE WITH IT.  Every wait here
-- is on a task this player owns, so a program cannot really hang -- but a
-- cartridge whose loop counter this port reads wrong would, and a battle frozen
-- on an animation is worse than a missing one.  Stated as frames because that
-- is what the caller spends, and generously: the longest program in the corpus
-- is well under this.
Player.FRAME_BUDGET = 600

-- ...and a step budget per frame, for the same reason at the other scale: the
-- VM runs instructions until it has to wait, and a jump backwards to itself
-- would spin inside one frame rather than across many.
Player.STEP_BUDGET = 4096

local floor, abs, max, min = math.floor, math.abs, math.max, math.min
-- `sin` and `pi` are for the one script function with a sine wobble on its
-- path. Named here because a bare `sin(...)` resolves as a GLOBAL, comes back
-- nil and RAISES -- and `lua_use_before_local.py` does not catch a name that
-- was never a local, which is written up in this repo's own notes.
local sin, pi = math.sin, math.pi

-- EVERY OPERAND IS A SIGNED 32-BIT WORD, and the decoder hands them over raw.
-- Read unsigned, a pan of -117 arrives as 4,294,967,179 and a fade delay of -2
-- as 4,294,967,294 -- and a "frame count" of four billion is a task that never
-- finishes, which is exactly how nineteen programs ran into the frame budget
-- the first time this player was driven over the corpus.
local TWO31, TWO32 = 2147483648, 4294967296
local function signed(v)
  v = tonumber(v) or 0
  if v >= TWO31 then return v - TWO32 end
  return v
end

-- ...AND SOME OPERANDS ARE TWO 16-BIT VALUES IN ONE WORD.
-- `SCALE_BATTLER_SPRITE_FRAMES(scale, restore)` packs them as
-- `(scale << 16) | restore`, and `HOLD_CYCLES` packs a delay over a cycle
-- count the same way. 327685 is 0x00050005, which is five frames out and five
-- back -- not a third of a million frames.
local function hi16(v) return floor((tonumber(v) or 0) / 65536) % 65536 end
local function lo16(v) return (tonumber(v) or 0) % 65536 end

-- ---------------------------------------------------------------------------
-- THE MON-SPRITE SLOTS
-- ---------------------------------------------------------------------------
--
-- `InitPokemonSpriteManager`, `AddPokemonSprite`, `RemovePokemonSprite` and
-- their neighbours were eight lines of `NOT_NEEDED` with one reason between
-- them: "the battler is already on screen". That reason is RIGHT for 439 of the
-- 440 programs that use them and WRONG for the one that matters.
--
-- WHAT THE COMMANDS ACTUALLY DO. `AddPokemonSprite role, track, slot, res`
-- builds a SECOND sprite out of the named battler's own picture, at that
-- battler's centre, in one of five slots
-- (BATTLE_ANIM_SCRIPT_MAX_POKEMON_SPRITES = 5). Nothing about it is a
-- placeholder: it is the battler's pixels, drawn twice. In a single battle the
-- copy lands exactly on top of the battler at the same priority -- see
-- `startMonSpritePriority` for that arithmetic -- so it is INVISIBLE, which is
-- why ignoring the whole family cost nothing for 439 programs.
--
-- THE ONE PROGRAM IT COSTS EVERYTHING. Dark Void (464) adds a copy of the
-- defender, sinks the COPY into a hole, and hides the REAL battler one frame
-- later. With no copy this port hid the defender and sank nothing: the foe
-- blinked out instead of being swallowed, and the eighty frames the move is
-- about were eighty frames of empty platform.
--
-- SO THE SLOTS ARE RECORDED, NOT DRAWN. A slot holds which side it copies, how
-- far the animation has pushed it and whether it is visible, and the draw asks
-- two questions of it: may this side be hidden, and how far down is it. No
-- second picture and no second draw path, because in a single battle the copy
-- and the battler are the same pixels in the same place and the only case where
-- they differ is the case where the battler is hidden.
Player.MON_SPRITE_SLOTS = 5

-- `BATTLER_ROLE_*` (include/constants/battle/battle_anim.h).
Player.ROLE = {
  ATTACKER = 0, DEFENDER = 1,
  ATTACKER_PARTNER = 2, DEFENDER_PARTNER = 3,
  PLAYER_1 = 4, ENEMY_1 = 5, PLAYER_2 = 6, ENEMY_2 = 7,
}
-- The two roles `SetPokemonSpritePriority` refuses outside a double battle.
Player.ROLE_PARTNER = { [2] = true, [3] = true }

-- `BATTLE_ANIM_BG_*` and the one default marker, all three 0xFF-shaped and all
-- three meaning different things -- which is exactly why they are named.
Player.BATTLE_ANIM_BG_POKEMON = 3
Player.BATTLE_ANIM_BG_NONE = 0xFF
Player.BATTLE_ANIM_DEFAULT_PRIORITY = 0xFF
Player.MON_SPRITE_PRIORITY_MODE_DARK_VOID = 0xFF

-- WHAT A MON SPRITE'S PRIORITY ALREADY IS BEFORE ANY FUNCTION TOUCHES IT.
-- `sPriorityByBattlerType[] = { 0, 0, 20, 10, 10, 20 }` in
-- `BattleSystem_CreateBattlerSprites`, indexed by BATTLER_TYPE_*, and the sprite
-- template beside it sets `bgPriority = 1`.
Player.SPRITE_PRIORITY_BY_TYPE = { [0] = 0, 0, 20, 10, 10, 20 }
Player.BATTLER_TYPE_SOLO_PLAYER = 0
Player.BATTLER_TYPE_SOLO_ENEMY = 1
Player.MON_SPRITE_BG_PRIORITY = 1

-- THE TWO SOLO BATTLER CENTRES, because Dark Void's cut-off is an ABSOLUTE y
-- and a slot only carries a delta. `BATTLER_POS_SOLO_PLAYER_*` /
-- `BATTLER_POS_SOLO_ENEMY_*` in battle_anim.h -- the same two pairs
-- `Gen4Battle.BATTLER_POS` draws at, and the check asserts the two tables agree
-- rather than trusting that a duplicated number stayed duplicated.
Player.BATTLER_CENTRE = {
  [true]  = { x = 64,  y = 112 },
  [false] = { x = 192, y = 48 },
}

-- DARK VOID'S WINDOW IS THE VOID.
--
-- `GX_SetVisibleWnd(GX_WNDMASK_W0)`, an INSIDE plane of BG0|BG1|BG2|BG3 and an
-- OUTSIDE plane of those four PLUS `GX_WND_PLANEMASK_OBJ`. Read together they say
-- one thing: inside window 0 every SPRITE disappears and the four backgrounds
-- stay. That is the hole the Pokemon sinks into -- there is no hole drawn
-- anywhere, the mon is simply cut off where the window starts.
--
-- `G2_SetWnd0Position(left, top, right, bottom)` -- the argument order is stated
-- by hall_of_fame.c's own `(left, 32, right, 32 + POKEMON_FRAME_HEIGHT)` and
-- again by end_credits' `(0, 192 - 24, 255, 192)`.
--   type 0   0, 160, 128, 192    the bottom-left quarter -- under the player
--   type 1   128, 86, 256, 192   the bottom-right, from ten pixels above the
--                                middle -- under the foe
-- BOTH RUN TO THE BOTTOM OF THE SCREEN and each covers one half horizontally,
-- which is what makes a single scissor exact: for a battler inside the window's
-- x span, "inside the window" is just "below the top edge".
Player.MON_WINDOW = {
  [0] = { left = 0,   top = 160, right = 128, bottom = 192 },
  [1] = { left = 128, top = 86,  right = 256, bottom = 192 },
}

-- THE CARTRIDGE'S OWN LCRNG, and the recurrence is exact: `sLCRNGState =
-- sLCRNGState * 1103515245 + 24691` with the value being the TOP HALF of the new
-- 32-bit state (`return sLCRNGState >> 16`).
--
-- Multiplied in two 16-bit halves because a Lua 5.1 number is a double: the
-- product of a full 32-bit state and the multiplier is 4.7e18 and loses its low
-- bits, while `lo * MUL` is at most 7.3e13 and is exact.
local LCRNG_MUL, LCRNG_ADD = 1103515245, 24691
local function lcrngNext(state)
  state = tonumber(state) or 0
  local lo = state % 65536
  local hi = floor(state / 65536) % 65536
  state = (lo * LCRNG_MUL + (hi * LCRNG_MUL % 65536) * 65536 + LCRNG_ADD) % TWO32
  return state, floor(state / 65536)
end
Player.LCRNG_MUL, Player.LCRNG_ADD = LCRNG_MUL, LCRNG_ADD
function Player.lcrngStep(state) return lcrngNext(state) end

-- `DARK_VOID_*` beside the handler.
local DARK_VOID_STEP_Y = 4
local DARK_VOID_STEP_Y_L = 8
local DARK_VOID_MAX_Y = 130
local DARK_VOID_SINK_MIN = 35
local DARK_VOID_SINK_RNG = 5
-- ...and the one bound that is NOT a `#define`: `if (ctx->stepCount < 20)`.
local DARK_VOID_STEP_CAP = 20
Player.DARK_VOID_STEP_Y = DARK_VOID_STEP_Y
Player.DARK_VOID_STEP_Y_L = DARK_VOID_STEP_Y_L
Player.DARK_VOID_MAX_Y = DARK_VOID_MAX_Y
Player.DARK_VOID_SINK_MIN = DARK_VOID_SINK_MIN
Player.DARK_VOID_SINK_RNG = DARK_VOID_SINK_RNG
Player.DARK_VOID_STEP_CAP = DARK_VOID_STEP_CAP

-- THE SINK, STATE BY STATE.
--
-- `SetPokemonSpritePriorityContext_DoDarkVoidEffects` is a switch on the task's
-- own frame counter and its shape is four JITTERED STEPS then a free fall:
--   state 0              set the window, and roll the frame the fall begins on
--   states 5, 6          a coin each frame: on heads step down 4, but only once
--   state 7              if the coin never came up, step anyway
--   states 10, 11 / 12   the same pair again
--   states 15, 16 / 17   and again
--   states 22, 23 / 24   and again, this time by EIGHT
--   past the rolled frame   step down 4 EVERY frame, twenty steps at most, and
--                           stop being drawn once the centre passes 130
--
-- THE COIN CHANGES WHEN, NEVER WHETHER. Every `if (ctx->stepCount != n)` line is
-- a forcing move that makes the step happen at the end of its window if the coin
-- refused, so the four steps always total 4 + 4 + 4 + 8 = 20 pixels by state 24
-- and only their timing is random. A port that read the coin as "maybe" would
-- have a foe that sometimes sank twenty pixels and sometimes did not.
--
-- `need` is the stepCount a coin row requires (`== n`); `unless` is the one a
-- forcing row skips on (`!= n`). Two field names rather than one because the two
-- comparisons are opposite and a single "count" field would read as either.
local DARK_VOID_JITTER = {
  [5]  = { coin = true,  need = 0,   step = DARK_VOID_STEP_Y },
  [6]  = { coin = true,  need = 0,   step = DARK_VOID_STEP_Y },
  [7]  = { coin = false, unless = 1, step = DARK_VOID_STEP_Y },
  [10] = { coin = true,  need = 1,   step = DARK_VOID_STEP_Y },
  [11] = { coin = true,  need = 1,   step = DARK_VOID_STEP_Y },
  [12] = { coin = false, unless = 2, step = DARK_VOID_STEP_Y },
  [15] = { coin = true,  need = 2,   step = DARK_VOID_STEP_Y },
  [16] = { coin = true,  need = 2,   step = DARK_VOID_STEP_Y },
  [17] = { coin = false, unless = 3, step = DARK_VOID_STEP_Y },
  [22] = { coin = true,  need = 3,   step = DARK_VOID_STEP_Y_L },
  [23] = { coin = true,  need = 3,   step = DARK_VOID_STEP_Y_L },
  [24] = { coin = false, unless = 4, step = DARK_VOID_STEP_Y_L },
}
Player.DARK_VOID_JITTER = DARK_VOID_JITTER

-- ---------------------------------------------------------------------------
-- Construction
-- ---------------------------------------------------------------------------

local Gen4MoveAnimPlayer = {}

-- new(data) -> player or nil
--
-- nil rather than an error when the cache has no `move_anims`, because that is
-- simply a cache written before the import stage existed and the battle should
-- still run.  The caller's `pcall` would swallow an error anyway, and a nil
-- that is checked reads better than an exception that is not.
function Gen4MoveAnimPlayer.new(data)
  local rec = data and data.gen4_move_anims
  if not (rec and rec.programs) then return nil end
  local self = setmetatable({}, Player)
  self.programs = rec.programs
  self.count = rec.count or 0
  -- THE EFFECTS, and nil is survivable on purpose: a cache written before the
  -- `gen4_particles` stage existed still plays every program, every sound and
  -- every battler move, and reports the particle systems it could not load
  -- through `missing()` rather than refusing to start.
  local fx = data and data.gen4_particles
  self.effects = fx and fx.effects or nil
  -- THE THIRD LAYER. 32 of the 501 programs build a flat 2D sprite out of four
  -- separate archives, and the `gen4_cellactors` stage extracts exactly the 29
  -- resource tuples they name -- keyed "<char>_<pltt>_<cell>_<anim>", which is
  -- how the player finds one without re-deriving the key.
  local ca = data and data.gen4_cellactors
  self.cellArt = ca and ca.sprites or nil
  self.unsupported = {}
  self.skipped = {}
  self.playing = false
  return self
end

-- ---------------------------------------------------------------------------
-- Starting a program
-- ---------------------------------------------------------------------------

-- start(moveId, attackerIsPlayer) -> true when a program was found
--
-- `moveId` indexes we.arc directly: member N is move N's program, which is what
-- the decoder's cross-check established (every program's first word is a valid
-- opcode across all 501, and the count matches the move table's own slots).
function Player:start(moveId, attackerIsPlayer)
  local program = self.programs[moveId]
  if not (program and program.code and #program.code > 0) then
    self.playing = false
    return false
  end
  self.code = program.code
  self.record = program
  -- WORD OFFSET -> INSTRUCTION INDEX, which is what makes a jump followable.
  -- Built per start rather than cached on the record because the record comes
  -- out of the cache and this is derived state, not data.
  self.atWord = nil
  if program.wordAt then
    self.atWord = {}
    for i, at in pairs(program.wordAt) do self.atWord[at] = i end
    self.wordAt = program.wordAt
  end
  self.attackerIsPlayer = attackerIsPlayer and true or false
  -- KEPT because the particle seeds are a function of it: `duration()` runs
  -- every program twice and the two passes have to agree, so nothing in the
  -- emitters may depend on anything but the move and the order of creation.
  self.moveId = moveId
  -- !! THE REPORT IS PER RUN, AND FOR A LONG TIME IT WAS NOT.
  --
  -- `self.unsupported` was cleared in `new()` alone, so it accumulated for the
  -- life of the player: every program's gaps piled onto every later program's.
  -- In a battle that is merely untidy -- one player, one report -- but as a
  -- MEASUREMENT it is useless, and the queue it exists to produce was wrong by
  -- three orders of magnitude: walking all 501 programs twice reported 499,840
  -- uses of `setextraparams`, a command the cartridge contains 742 times, and
  -- made every gap look as though it touched nearly every move, because once a
  -- row appeared it was still there for all the moves after it.
  --
  -- `duration()` ALREADY CARRIED THE COMPENSATION for the behaviour intended
  -- here: it saves the report across its second `start` and restores it, which
  -- is a no-op unless `start` clears it. That line pair is what says this is the
  -- fix rather than a change of mind.
  self.unsupported = {}
  self.skipped = {}
  self.pc = 1
  self.frames = 0
  self.delay = 0
  self.vars = {}
  self.loops = {}
  self.calls = {}
  self.tasks = {}
  self.playing = true
  self.finished = false
  self.sounds = {}
  -- `loadparticlesystem` fills a slot with a RESOURCE SET; the emitter commands
  -- instantiate one resource out of it. Both are cleared per run so a move
  -- cannot inherit the previous move's slots.
  self.slots = {}
  self.emitters = {}
  -- The same emitters, by the SLOT the cartridge files them under. `createemitter`
  -- and its two cousins all write slot 0; `createemitterex` names its own.
  self.emitterAt = {}
  self.emitterSeq = 0
  -- The 2D sprite managers (ids 0-3; the cartridge only ever uses 0) and the
  -- sprites in them. Cleared per run like the particle slots.
  self.managers = {}
  -- NAMED `sprites`, NOT `cells`. The accessor below is `Player:cells()`, and an
  -- instance field of the same name SHADOWS THE METHOD: `player:cells()` finds
  -- the table first and raises "attempt to call a table value". Lua's `:` looks
  -- at the instance before the metatable, so a field and a method may not share
  -- a name -- a quieter cousin of the use-before-local fault.
  self.sprites = {}
  -- WHAT WHOLE GROUPS OF PALETTES ARE TINTED, by `fadebg`'s group name. Cleared
  -- per run like everything else: the cartridge's fades come in pairs and end at
  -- zero, so a program that ended mid-fade would otherwise leave the battle
  -- background dimmed for good.
  self.groups = {}
  -- ...and the per-callback contexts that drive them. A callback's state lives
  -- here rather than on its sprites because three callbacks own several sprites
  -- and one state machine between them.
  self.spriteCtxs = {}
  -- HOW MANY FRAMES THE PROGRAM SPENT HELD AT `waitforallemitters`.
  --
  -- Counted because nothing else can see whether that wait blocks. A program
  -- that runs off its end with particles still in the air keeps the player alive
  -- anyway -- which is right, an `end` should not cut the burst off -- and that
  -- makes the TOTAL length the same whether the wait blocks or not. So a check
  -- on total frames cannot tell a working wait from a free one: planting "make
  -- the wait free" against this file passed a section with nine other
  -- assertions in it. This is the number that failed it.
  self.emitterWaits = 0
  -- THE EFFECT BACKGROUND LAYER, and the four things that can be true of it at
  -- once: a switch in progress (`bgSwitchState`, which is what the two waits
  -- read), the picture currently up (`bgLayer`, nil when the ordinary backdrop is
  -- showing), the scroll a MOVE flag started (`bgAnim`) and the shake `shakebg`
  -- drives (`bgShake`). All four are cleared per run for the same reason the
  -- tints are: a program that ended mid-switch would otherwise leave the wrong
  -- background up for the rest of the battle.
  self.bgSwitchState = BG_STATE_NONE
  self.bgLayer = nil
  self.bgAnim = nil
  self.bgShake = nil
  -- HOW MANY FRAMES THE PROGRAM SPENT HELD AT `waitforbgswitch`, counted for
  -- exactly the reason `emitterWaits` is: a switch that never finishes and a wait
  -- that never blocks produce the same total length, so the total cannot tell
  -- them apart and this can.
  self.bgWaits = 0
  -- WHETHER THE BACKGROUND IS GREY. `SetBgGrayscale` is a toggle rather than a
  -- fade: it rewrites the faded palette buffer outright and its partner call puts
  -- the unfaded one back. Nine calls on and nine off in the whole cartridge, so a
  -- program that ended half way would leave the field grey for the rest of the
  -- battle -- hence per-run, like everything else here.
  self.grayscale = false
  -- EVERY SOUND THIS RUN ASKED FOR, in order, each with the frame it happened on.
  -- Kept as well as handed to `onSound` because the frame a sound lands on is the
  -- one thing about this layer that can be measured without an audio device.
  self.soundEvents = {}
  -- HOW MANY FRAMES THE PROGRAM SPENT HELD AT A SOUND WAIT, counted for the same
  -- reason `emitterWaits` and `bgWaits` are.
  self.soundWaits = 0
  self.soundWaitTimer = 0
  self.cryPending = false
  -- ...AND WHETHER TO ACTUALLY MAKE THE NOISE. `duration()` runs the whole program
  -- once to measure it and then starts it again, so a seam wired to the engine
  -- would play every sound in every move TWICE -- once inaudibly early. The
  -- measuring pass sets this.
  self.quiet = false
  -- The two transforms, per SIDE rather than per battler: this port draws one
  -- Pokemon a side in a Sinnoh battle, and `monOffset(isPlayer)` is the shape
  -- the seam already speaks.
  self.state = {
    [true]  = { dx = 0, dy = 0, sx = 1, sy = 1, hidden = false, tint = nil },
    [false] = { dx = 0, dy = 0, sx = 1, sy = 1, hidden = false, tint = nil },
  }
  -- THE MON-SPRITE SLOTS, cleared per run for the reason every other per-run
  -- table is: `freepokemonspritemanager` empties them at the end of a well-formed
  -- program, and a program that ends without one must not leave a copy of the
  -- last Pokemon standing in front of the next move's.
  self.monSprites = {}
  self.monSpriteManager = false
  -- The hardware window, while one is up. See `Player.MON_WINDOW`.
  self.monWindowRect = nil
  -- What `SetPokemonSpritePriority` was asked for and what it actually changed --
  -- the record that lets a check assert the no-op instead of taking a comment's
  -- word for it.
  self.monPriority = {}
  -- THE CARTRIDGE'S LCRNG, SEEDED PER RUN.
  --
  -- Dark Void's sink asks for a coin on six of its frames and for a number in
  -- 0..4 once. The RECURRENCE is the cartridge's exactly -- see `lcrngNext` -- but
  -- the SEQUENCE POSITION cannot be: on the hardware `sLCRNGState` is one global
  -- the whole game draws from, so where in it a move lands depends on everything
  -- that happened before it. Seeding from the move id makes the jitter
  -- reproducible instead, which is what `duration()` needs -- it runs every
  -- program twice and the two passes must agree -- and what lets a check assert
  -- anything about a system otherwise driven by a real die. Same reasoning, and
  -- the same words, as Gen4ParticleSystem's own seeded generator.
  self.rngState = ((tonumber(moveId) or 0) * LCRNG_MUL + LCRNG_ADD) % TWO32
  return true
end

function Player:stop()
  self.playing = false
  self.finished = true
  -- ...BUT THE TRANSFORMS STAY WHILE ANYTHING IS STILL RUNNING. `end` stops the
  -- script, and on the hardware the transform tasks are SysTasks that outlive it
  -- exactly like the emitters do. Clearing here unconditionally snapped a battler
  -- back the instant the last command ran, which matters now that a sprite
  -- callback can hold a battler stretched: ScaryFace's move (137) has the longest
  -- tail in the corpus at 102 frames, and its stretch lives entirely in it.
  -- MEASURED BEFORE CHANGING IT: two of 501 programs reach `end` with a battler
  -- displaced at all (44 and 292, by 12 and 17 frames of tail), so this moves the
  -- reset later for two programs and makes the callbacks possible for the rest.
  if not self:hasLiveEffects() then self:clearTransforms() end
end

-- Put every battler back where it stands. Called when the script ends with
-- nothing left running, and otherwise when the tail finally empties.
function Player:clearTransforms()
  self.groups = {}
  self.grayscale = false
  self.cryPending = false
  self.bgSwitchState = BG_STATE_NONE
  self.bgLayer = nil
  self.bgAnim = nil
  self.bgShake = nil
  -- THE SLOTS AND THE WINDOW GO WITH THE TRANSFORMS. A window left up hides every
  -- sprite in a quarter of the screen for the rest of the battle, and a slot left
  -- live keeps answering `monHidden` for a move that has finished.
  self.monSprites = {}
  self.monSpriteManager = false
  self.monWindowRect = nil
  if not self.state then return end
  for _, s in pairs(self.state) do
    s.dx, s.dy, s.sx, s.sy, s.hidden, s.tint = 0, 0, 1, 1, false, nil
  end
end

-- ---------------------------------------------------------------------------
-- Which side a target mask means
-- ---------------------------------------------------------------------------

local function hasBit(value, bit)
  return floor((value or 0) / bit) % 2 == 1
end

-- sidesFor(mask) -> { [isPlayer] = true, ... }
--
-- ATTACKER and DEFENDER are relative to who is using the move, so a mask has to
-- be resolved against `attackerIsPlayer` rather than read as "player" and
-- "enemy".  Getting that backwards makes every enemy move shake the wrong
-- Pokemon, which looks like a sign error and is a frame-of-reference one.
function Player:sidesFor(mask)
  local out = {}
  mask = mask or 0
  local atk, def = self.attackerIsPlayer, not self.attackerIsPlayer
  if hasBit(mask, Player.ALL_BATTLERS) then
    out[true], out[false] = true, true
    return out
  end
  if hasBit(mask, Player.NOT_ATTACKER) then out[def] = true end
  if hasBit(mask, Player.ATTACKER) then out[atk] = true end
  if hasBit(mask, Player.DEFENDER) then out[def] = true end
  -- The PARTNER bits are a doubles concept and this port fights one a side in
  -- Sinnoh, so they resolve to their own side's single Pokemon rather than
  -- being dropped -- dropping them would silently skip the whole animation on
  -- a move whose script names only the partner.
  if hasBit(mask, Player.ATTACKER_PARTNER) then out[atk] = true end
  if hasBit(mask, Player.DEFENDER_PARTNER) then out[def] = true end
  if not (out[true] or out[false]) then out[def] = true end
  return out
end

-- ---------------------------------------------------------------------------
-- Tasks: the things that take time
-- ---------------------------------------------------------------------------

-- Every script function here starts a TASK rather than changing a transform
-- outright, because `waitforanimtasks` is what the programs use to sequence
-- themselves and it asks exactly one question: is anything still running.
-- A TASK'S DURATION IS CLAMPED, and deliberately rather than defensively: a
-- frame count this player computed wrongly should show up as a short effect
-- and a counted note, not as a battle that never gets its turn back. The cap is
-- the whole program budget, so a legitimate long effect is untouched.
function Player:addTask(task)
  if task.frames ~= nil then
    local n = tonumber(task.frames) or 0
    if n ~= n or n < 0 then n = 0 end            -- NaN and negatives
    if n > Player.FRAME_BUDGET then
      self:note("clamped frames")
      n = Player.FRAME_BUDGET
    end
    task.frames = floor(n)
  end
  task.frame = 0
  self.tasks[#self.tasks + 1] = task
  return task
end

-- WHAT `waitforanimtasks` IS ACTUALLY WAITING FOR, and it is not every task.
-- `system->activeAnimTasks` is incremented by `BattleAnimSystem_StartTask` and by
-- nothing else, so only the tasks started through `StartAnimTask` are counted. The
-- background switch, its scroll and its scanline wave are all started with a plain
-- `SysTask_Start` and are invisible to this wait -- which they have to be: the
-- scroll NEVER ENDS on its own, so a `waitforanimtasks` that counted it would hang
-- the program, and eight of them did until this line was written.
--
-- `shakebg` and `fadebg` DO go through `StartAnimTask` and are counted.
-- ...AND NEITHER ARE THE THREE SOUND TASKS. `BattleAnimSystem_CreateSoundContext`
-- increments `activeSoundTasks`, a separate counter that only
-- `waitforsoundeffects` reads -- so a looped sound never holds a
-- `waitforanimtasks`. Counting them would make every move with a repeating noise
-- as long as the noise.
local TASK_NOT_COUNTED = {
  bgswitch = true, bgmove = true,
  sndrepeat = true, snddelay = true, sndpan = true,
}

local SOUND_TASKS = { sndrepeat = true, snddelay = true, sndpan = true }

function Player:taskCount()
  local n = 0
  for _, t in ipairs(self.tasks) do
    if not t.done and not TASK_NOT_COUNTED[t.kind] then n = n + 1 end
  end
  return n
end

-- `system->activeSoundTasks`, which is what `waitforsoundeffects` waits for.
function Player:soundTaskCount()
  local n = 0
  for _, t in ipairs(self.tasks) do
    if not t.done and SOUND_TASKS[t.kind] then n = n + 1 end
  end
  return n
end

-- A SHAKE IS A FOUR-PHASE CYCLE AND `amount` COUNTS CYCLES, NOT FLIPS.
--
-- This was wrong for a whole session in two ways at once, and both come out of
-- eleven lines of pret. `ShakeContext_FlipPosition` is not a sign flip:
--
--   prevVal = *prev;  *prev = *cur;  *cur = (prevVal == 0) ? 0 : -prevVal;
--
-- Starting from `prev = -extent` and `cur = 0` that produces
-- **+E, 0, -E, 0, +E, 0, ...** -- a square wave THROUGH THE CENTRE, not between
-- the two extremes. And `ShakeContext_Update` only decrements its remaining count
-- once every `MAX_CYCLES_PER_SHAKE` flips, which is FOUR -- so `amount` is the
-- number of complete cycles and a shake lasts FOUR TIMES as long as a port that
-- reads it as a flip count.
--
-- IT MATTERS ON 398 CALLS, which is every `shake` in the cartridge, and the
-- commonest by a distance is `amount = 2` with `interval = 1`: eight frames of
-- shaking where this port did two. A two-frame hit shake is over before it
-- registers, and nothing could see it -- the frames were spent, the offsets were
-- applied, and only the waveform and the count were wrong.
--
-- THE LAST PHASE IS ALWAYS ZERO, because 4 * amount flips ends on the fourth
-- phase of a cycle -- so the offset comes home by arithmetic and the explicit
-- reset this function used to end with was compensating for the wrong waveform.
--
-- The counter starts AT `interval`, so the first flip lands on the first update
-- and the rest every `interval` updates after it.
local SHAKE_FLIPS_PER_CYCLE = 4

local function shakePhase(flips, extent)
  extent = extent or 0
  -- An extent of zero never leaves zero: `prev` starts at -0, so `prevVal == 0`
  -- and the position is pinned. 336 of the 398 calls pass extentY = 0.
  if extent == 0 then return 0 end
  local phase = flips % 4
  if phase == 1 then return extent end
  if phase == 3 then return -extent end
  return 0
end

local function stepShake(self, t)
  -- FRAME 0 IS THE TASK'S INIT STATE. pret's shake task spends its first frame in
  -- SHAKE_STATE_INIT building the context and breaking, so nothing is applied
  -- until the frame after.
  local period = max(1, t.interval or 1)
  local flips = (t.frame >= 1) and (floor((t.frame - 1) / period) + 1) or 0
  if flips > (t.amount or 0) * SHAKE_FLIPS_PER_CYCLE then
    t.done = true
    return
  end
  local x = shakePhase(flips, t.extentX)
  local y = shakePhase(flips, t.extentY)
  if t.group then
    self.groups[t.group] = { x, y }
    return
  end
  for side in pairs(t.sides) do
    local s = self.state[side]
    s.dx, s.dy = x, y
  end
end

-- A move is a linear ramp out and nothing more; the cartridge's own
-- MoveBattler runs the offset to its target over `frames` and leaves it there,
-- and the program that wanted it back puts a second one in with the opposite
-- sign. Easing it would be this port inventing motion the cartridge does not
-- have.
local function stepMove(self, t)
  local n = max(1, t.frames or 1)
  local k = min(1, t.frame / n)
  for side in pairs(t.sides) do
    local s = self.state[side]
    s.dx, s.dy = (t.offsetX or 0) * k, (t.offsetY or 0) * k
  end
  if t.frame >= n then t.done = true end
end

local function stepScale(self, t)
  local n = max(1, t.frames or 1)
  local k = min(1, t.frame / n)
  local sx = (t.startX or 1) + ((t.endX or 1) - (t.startX or 1)) * k
  local sy = (t.startY or 1) + ((t.endY or 1) - (t.startY or 1)) * k
  for side in pairs(t.sides) do
    local s = self.state[side]
    s.sx, s.sy = sx, sy
  end
  if t.frame >= n then t.done = true end
end

local function stepFade(self, t)
  local n = max(1, t.frames or 1)
  local k = min(1, t.frame / n)
  for side in pairs(t.sides) do
    local s = self.state[side]
    s.tint = { t.r or 0, t.g or 0, t.b or 0, (t.alpha or 0) * k }
  end
  if t.frame >= n then t.done = true end
end

local function stepHold(self, t)
  if t.frame >= (t.frames or 0) then t.done = true end
end

-- A WHOLE-GROUP PALETTE FADE, which is what `fadebg` actually is.
--
-- NOT A SCREEN FADE AND NOT A BATTLER FADE: `BattleAnimScriptFunc_FadeBg` calls
-- `PaletteData_StartFade` on a GROUP OF PALETTES inside the main BG buffer, and
-- its first operand picks which group -- the battle background's own palettes
-- (type 0), the Pokemon sprites' (1) or the effect palettes' (2). MEASURED over
-- the cartridge's 272 calls: 270 are type 0 and 2 are type 2, so what this is
-- really for is dimming and flashing the BACKGROUND, and it is used by 108 of the
-- 501 moves. Until now the port held the right number of frames and drew nothing.
--
-- THE ARITHMETIC IS `SetTimedFadeParams` AND IT IS NOT A LERP:
--   * a NON-NEGATIVE delay means step = 2 with that many frames of wait between
--     steps; a NEGATIVE delay means step = 2 + |delay| and NO wait, so it is the
--     same ramp taken in bigger jumps. 227 calls pass 1, 36 pass 0, nine pass -2
--     or -4 -- the negative branch is real, not defensive.
--   * the blend is applied AT `cur` and only then does `cur` advance, so the END
--     VALUE IS ALWAYS APPLIED and the fade finishes on the application where cur
--     was already the end. 0 -> 12 is seven applications, not six.
--   * `BlendColor(src, target, fraction)` is `src + ((target - src) * fraction
--     >> 4)`, so the fraction is out of SIXTEEN like every other blend here.
--
-- AND A SECOND FADE WHILE ONE IS RUNNING IS DROPPED, not queued:
-- `PaletteData_StartFade` skips a buffer already in `selectedBuffers`. The
-- cartridge's own calls come in pairs (0 -> 12 then 12 -> 0, 98 and 99 times) so
-- it should never happen; counted rather than assumed.
local function stepPltFade(self, t)
  -- ONE FRAME OF NOTHING FIRST. `StartFade` applies its first blend inline -- on
  -- the frame the command runs, which `callFunc` has already done -- and then
  -- starts the stepping task at priority 0xFFFFFFFE from inside the animation
  -- task at 1100. `1100 <= 0xFFFFFFFE`, so the new task is marked INACTIVE and
  -- skips a frame, exactly like the alpha fades.
  if t.pending then
    t.pending = false
    return
  end
  if t.waitStep < t.wait then
    t.waitStep = t.waitStep + 1
    return
  end
  t.waitStep = 0
  -- The blend at `cur` was applied when `cur` was set; this is the advance and
  -- the next application in one, which is the order `ApplyBlendStepToPaletteBuffer`
  -- and `UpdateFadeBlendStep` run in.
  if t.cur == t.finish then
    t.done = true
    return
  end
  if t.finish > t.cur then
    t.cur = t.cur + t.step
    if t.cur > t.finish then t.cur = t.finish end
  else
    t.cur = t.cur - t.step
    if t.cur < t.finish then t.cur = t.finish end
  end
  self:applyPaletteFade(t)
end

-- One frame of a travelling emitter. The player owns the arithmetic; this only
-- sequences it, because `startEmitterPath` has to reach `self` and a stepper does
-- not get one.
local function stepEmitterPath(self, t)
  if t.timer < t.startDelay then
    t.timer = t.timer + 1
    return
  end
  if not t.live then
    -- pret deletes the emitter here once its particles are gone too; this port
    -- lets the system end on its own, which is the same thing a frame later and
    -- never cuts a burst off.
    t.done = true
    return
  end
  self:stepEmitterPathOnce(t)
  -- PARKED means `params` named a maxFrames, and then the position is never
  -- updated again -- see the note at `startEmitterPath`.
  if not t.parked then
    if t.curve ~= 0 then t.angle = t.angle + 360 / max(1, t.frames) end
    self:applyEmitterPath(t)
  end
end

-- ---------------------------------------------------------------------------
-- The background switch, one frame at a time
-- ---------------------------------------------------------------------------

-- A coefficient as an alpha. Five-bit field, hardware clamp at 16, sixteenths.
local function bgAlpha(coeff)
  local v = tonumber(coeff) or 0
  if v > BG_BLEND_CLAMP then v = BG_BLEND_CLAMP end
  if v < 0 then v = 0 end
  return v / BG_BLEND_CLAMP
end

-- ONE STEP OF THE CROSS-FADE, and the odd part is pret's, not a transcription
-- slip: each side steps by two until it is NOT LESS THAN its target, which
-- overshoots by one step, and then the frame on which both have overshot writes
-- the exact targets instead. So the rising side reaches 30 before being set to 29.
-- Returns true when both sides are finished.
local function bgBlendStep(t)
  local done = 0
  if t.coeffA < t.targetA then t.coeffA = t.coeffA + BG_BLEND_STEP
  else done = done + 1 end
  if t.coeffB > t.targetB then t.coeffB = t.coeffB - BG_BLEND_STEP
  else done = done + 1 end
  if done == 2 then
    t.coeffA, t.coeffB = t.targetA, t.targetB
    return true
  end
  return false
end

-- The four state machines, in pret's own order in `sBattleBgSwitchFuncs`:
-- modes 0..2 are a switch and 3..5 the matching restore, which is why
-- `restorebg` adds BATTLE_BG_SWITCH_MODE_COUNT to the mode it read.

local function bgSwitchBlend(self, t)
  if t.state == 0 then
    -- `LoadBaseBg` copies the backdrop onto BG2 and both layers are put at the
    -- effect priority. This port draws the field once and dims it, so there is
    -- nothing to copy -- but the frame is real: pret BREAKS here.
    t.state = 1
    return true
  end
  if t.state == 1 then
    self:bgLoadArt(t)
    self:bgApplyFlags(t)
    t.state = 2
    -- ...and falls through into the first blend step on this same frame.
  end
  if t.state == 2 then
    local finished = bgBlendStep(t)
    if finished then t.state = 3 end
    self:bgApplyBlend(t, t.coeffB, t.coeffA)
    return not finished
  end
  return false
end

local function bgRestoreBlend(self, t)
  if t.state == 0 then t.state = 1 end
  if t.state == 1 then
    -- Priorities again, and `G2_SetBlendAlpha` with the two coefficients THE OTHER
    -- WAY ROUND: on a restore the rising side is the BASE and the falling side the
    -- effect layer, so the same walk fades the backdrop back in.
    self:bgApplyFlags(t)
    t.state = 2
  end
  if t.state == 2 then
    local finished = bgBlendStep(t)
    if finished then
      -- THE OVERSHOOT IS PUT BACK, which is not what the switch does: the restore
      -- ends on targetA + 2 and targetB - 2, i.e. 31 and 0 -- the backdrop whole
      -- and the effect layer gone -- rather than on 29 and 2.
      t.coeffA = t.targetA + BG_BLEND_STEP
      t.coeffB = t.targetB - BG_BLEND_STEP
      t.state = 3
    end
    self:bgApplyBlend(t, t.coeffA, t.coeffB)
    -- pret BREAKS here even on the finishing frame, so state 3 costs its own.
    return true
  end
  if t.state == 3 then
    self:bgCancelAnims(t)
    -- The offsets go back to zero and the backdrop is loaded into the effect
    -- layer again, which for this port is the layer ceasing to exist.
    self.bgLayer = nil
    t.state = 4
    return true
  end
  if t.state == 4 then
    -- `Battle_SetDefaultBlend` and `UnloadBaseBg`: nothing this port holds.
    t.state = 5
    return true
  end
  return false
end

local function bgSwitchFade(self, t)
  local colour = BG_FADE_COLOUR[t.fadeType] or 0
  if t.state == 0 then
    -- The backdrop's own palettes fade to black or white over sixteen, and the
    -- effect palette is put there OUTRIGHT -- so when the new picture is loaded a
    -- moment later it is already the fade colour and nothing flashes.
    self:startGroupFade("base", 0, 0, PALETTE_BLEND_MAX, colour, "switchbg")
    self:blendGroupNow("effect", PALETTE_BLEND_MAX, colour)
    t.state = 1
    -- ...and falls through, so the wait below happens on this same frame and sees
    -- the fade it just started.
  end
  if t.state == 1 then
    if self:paletteFadeBusy() then return true end
    self:bgLoadArt(t)
    self:startGroupFade("effect", 0, PALETTE_BLEND_MAX, 0, colour, "switchbg")
    self:bgApplyFlags(t)
    -- THE PARTIAL POINT: the screen is fully black or white and the new picture is
    -- loaded behind it. `waitforpartialbgswitch` releases here, three times in the
    -- cartridge, and that is the whole reason the state exists.
    self.bgSwitchState = BG_STATE_PARTIAL
    t.state = 2
    return true
  end
  if self:paletteFadeBusy() then return true end
  return false
end

local function bgRestoreFade(self, t)
  local colour = BG_FADE_COLOUR[t.fadeType] or 0
  if t.state == 0 then
    self:bgApplyFlags(t)
    t.state = 1
  end
  if t.state == 1 then
    self:startGroupFade("effect", 0, 0, PALETTE_BLEND_MAX, colour, "restorebg")
    self:blendGroupNow("base", PALETTE_BLEND_MAX, colour)
    t.state = 2
  end
  if t.state == 2 then
    if self:paletteFadeBusy() then return true end
    self:bgCancelAnims(t)
    -- Hidden once its palette is out, and the backdrop loaded back into it.
    self.bgLayer = nil
    t.state = 3
  end
  if t.state == 3 then
    self:startGroupFade("base", 0, PALETTE_BLEND_MAX, 0, colour, "restorebg")
    t.state = 4
  end
  if self:paletteFadeBusy() then return true end
  -- pret sets PARTIAL here and then the task wrapper immediately sets NONE, so the
  -- write is dead. Left in because a reader comparing the two files will look for
  -- it, and because `waitforpartialbgswitch` after a restore would otherwise look
  -- like it could pass.
  self.bgSwitchState = BG_STATE_PARTIAL
  return false
end

local function bgSwitchFlagsOnly(self, t)
  self:bgApplyFlags(t)
  return false
end

local function bgRestoreFlagsOnly(self, t)
  self:bgApplyFlags(t)
  self:bgCancelAnims(t, "moveOnly")
  return false
end

local BG_SWITCH_FUNCS = {
  [BG_SWITCH_MODE_BLEND] = bgSwitchBlend,
  [BG_SWITCH_MODE_FADE] = bgSwitchFade,
  [BG_SWITCH_MODE_FLAGS] = bgSwitchFlagsOnly,
  [BG_SWITCH_MODE_BLEND + BG_SWITCH_MODE_COUNT] = bgRestoreBlend,
  [BG_SWITCH_MODE_FADE + BG_SWITCH_MODE_COUNT] = bgRestoreFade,
  [BG_SWITCH_MODE_FLAGS + BG_SWITCH_MODE_COUNT] = bgRestoreFlagsOnly,
}

-- `BattleBgSwitchTask_Start`: run the mode's machine and, the moment it says it is
-- finished, put the system back to NONE -- which is what releases
-- `waitforbgswitch`.
local function stepBgSwitch(self, t)
  -- NOT ON THE FRAME IT WAS CREATED. `SysTaskManager_InternalAddTask` marks a new
  -- task INACTIVE when the task that created it has a priority less than or equal
  -- to the new one's, and the animation script runs in a task at priority 0 while
  -- this one is 1100 -- so `switchbg` costs a frame before its first state runs.
  -- The same rule is why the palette fades and the sprite callbacks skip one.
  if t.pending then t.pending = false; return end
  local fn = BG_SWITCH_FUNCS[t.mode]
  if not fn then
    self:note("switchbg with an unknown mode: " .. tostring(t.mode))
    self.bgSwitchState = BG_STATE_NONE
    t.done = true
    return
  end
  if fn(self, t) == false then
    self.bgSwitchState = BG_STATE_NONE
    t.done = true
  end
end

-- `BattleBgAnimTask_Move`: the layer scrolls by a fixed step per frame and never
-- stops on its own. Nothing eases and nothing wraps here -- the draw side wraps,
-- because the hardware's offset registers do.
local function stepBgMove(self, t)
  -- 0x1001, created from the switch task at 1100, so it skips a frame too.
  if t.pending then t.pending = false; return end
  local anim = t.anim
  if not anim or anim.cancel then t.done = true; return end
  anim.offsetX = anim.offsetX + anim.stepX
  anim.offsetY = anim.offsetY + anim.stepY
end

-- `BattleAnimTask_ShakeBg`, which is NOT the same shape as `shake`: it wraps the
-- shake context in an OUTER loop of `cycles + 1` runs and returns the offset to
-- zero between them.
--
-- WHAT THIS REPLACES. The player used to hold for `cycles` frames and draw
-- nothing, and `cycles` is 0 on 41 of the 42 calls -- so 41 of them held for no
-- frames at all while the comment above them claimed the length was preserved.
-- One inner run of the commonest call (extentY 5, amount 5, interval 0) is 21
-- frames, so `waitforanimtasks` after it was returning twenty-one frames early.
local function stepBgShake(self, t)
  -- 1100 from the script's task at 0: the creating frame is skipped, and pret's
  -- own INIT state then falls straight through into the first flip -- so the first
  -- frame that runs at all is the first frame that moves.
  if t.pending then t.pending = false; return end
  if t.finishing then t.done = true; return end
  local period = max(1, t.interval or 1)
  local total = (t.amount or 0) * SHAKE_FLIPS_PER_CYCLE
  t.inner = (t.inner or 0) + 1
  local flips = floor((t.inner - 1) / period) + 1
  if flips > total then
    -- The update on which `ShakeContext_Update` returns FALSE: the offsets are put
    -- back to zero, and then either the outer loop goes round again or the task
    -- spends one more frame in its done state before ending.
    self:bgShakeApply(t, 0, 0)
    if t.iteration >= (t.cycles or 0) then t.finishing = true
    else t.inner = 0 end
    t.iteration = (t.iteration or 0) + 1
    return
  end
  self:bgShakeApply(t, shakePhase(flips, t.extentX), shakePhase(flips, t.extentY))
end

-- ---------------------------------------------------------------------------
-- The two revolutions
-- ---------------------------------------------------------------------------

-- `BattleAnimTask_RevolveBattler`: a flat ellipse round the battler's own feet.
--
-- THE CENTRE IS NOT THE BATTLER. The script function does
-- `pos.y -= REVOLUTION_CONTEXT_OVAL_RADIUS_Y_INT` -- and that constant is -8, so
-- the orbit's centre is EIGHT PIXELS BELOW home -- and then the finishing frame
-- puts the sprite back at `pos.y + (-8)`, which is home again. So the offset this
-- writes is `8 + rev.y`, the vertical radius is -4, and the battler's first frame
-- is four pixels low rather than on its mark. Reproduced: the little drop at the
-- start and the snap home at the end are both the cartridge's.
local function stepMonRev(self, t)
  -- 1100 from the script task at 0: the creating frame is skipped.
  if t.pending then t.pending = false; return end
  if Gen4AnimMath.revolutionUpdate(t.rev) then
    local dx = t.rev.x
    local dy = -Gen4AnimMath.OVAL_RADIUS_Y_INT + t.rev.y
    for side in pairs(t.sides) do
      local s = self.state[side]
      s.dx, s.dy = dx, dy
    end
    return
  end
  for side in pairs(t.sides) do
    local s = self.state[side]
    s.dx, s.dy = 0, 0
  end
  t.done = true
end

-- `BattleAnimTask_RevolveEmitter`: the same revolution, driving an EMITTER's
-- position instead of a battler's, round whichever battler `mode` names.
--
-- pret ends the task when the revolution is done AND the emitter has no particles
-- left, and then DELETES the emitter. This port ends the task when the revolution
-- is done and lets the system run its particles out on its own -- the same choice
-- the travelling emitters made, and for the same reason: the delete only ever
-- happens after the last particle, so deleting is a frame of bookkeeping rather
-- than a frame of picture, and not doing it never cuts a burst off.
local function stepEmitterRev(self, t)
  if t.pending then t.pending = false; return end
  if not Gen4AnimMath.revolutionUpdate(t.rev) then t.done = true; return end
  self:applyEmitterRev(t)
end

-- ---------------------------------------------------------------------------
-- The three sound tasks
-- ---------------------------------------------------------------------------

-- All three share `BattleAnimSound_Task` at priority 1100 and the counter
-- `activeSoundTasks`, which is a DIFFERENT counter from the one
-- `waitforanimtasks` reads -- so a sound task never gates the animation, only
-- `waitforsoundeffects` waits for one, and no program in the cartridge uses that.
-- Recorded because it is the difference between these being timing and being audio.

-- `BattleAnimSoundFunc_Repeat`: play the same effect `count` times, `interval + 1`
-- frames apart.
--
-- THE PERIOD IS interval + 1 AND THE FIRST PLAY IS IMMEDIATE, and both fall out of
-- the same line: `if (tickCount++ < applyInterval) return TRUE` with `tickCount`
-- INITIALISED TO `applyInterval` by the command. So the first active frame finds
-- the counter already at the limit and fires; every later one counts 0..interval.
local function stepSoundRepeat(self, t)
  if t.pending then t.pending = false; return end
  if t.tick < t.interval then t.tick = t.tick + 1; return end
  t.tick = 0
  t.left = t.left - 1
  self:emitSound({ kind = "play", id = t.id, pan = t.pan, repeatOf = t.total })
  -- pret decrements a u8 and stops at zero, so a count of 0 would wrap to 255 and
  -- play 255 times. No call in the cartridge passes 0 (the range is 1 to 24), so
  -- the wrap is recorded rather than reproduced -- a port that looped 255 times on
  -- a mod's bad operand would be worse than one that stopped.
  if t.left <= 0 then t.done = true end
end

-- `BattleAnimSoundFunc_Delay`: play once, `interval` frames from now.
--
-- `if ((applyInterval--) == 0)` is a POST-decrement, so the test sees the value
-- before the subtraction: an interval of 0 fires on the task's first active frame
-- and an interval of n fires n frames after that.
local function stepSoundDelay(self, t)
  if t.pending then t.pending = false; return end
  if t.interval == 0 then
    self:emitSound({ kind = "play", id = t.id, pan = t.pan, delayed = true })
    t.done = true
    return
  end
  t.interval = t.interval - 1
end

-- `BattleAnimSoundFunc_Pan`: slide the pan of EVERY playing effect from one side to
-- the other, `step` at a time, every `interval + 1` frames.
--
-- `tickCount` is NOT pre-loaded here -- the command memsets the context and does not
-- set it -- so unlike the repeat task this one waits a full interval before its
-- first step. One line apart in pret, one frame apart on screen.
--
-- THE STEP'S SIGN IS RECOMPUTED FROM THE ENDPOINTS. `CorrectStepDirection` takes the
-- absolute value and signs it by whether the start is below the end, so a script
-- that passes a positive step for a right-to-left sweep still sweeps left. 10 of the
-- 113 calls sweep right to left.
--
-- pret also ends the task early when the effect it is panning has stopped playing
-- (`Sound_IsEffectPlaying`). Nothing here knows that, so the task runs its walk out;
-- the difference is inaudible while there is no sequence player, and it is noted
-- rather than guessed at.
local function stepSoundPan(self, t)
  if t.pending then t.pending = false; return end
  if t.tick < t.interval then t.tick = t.tick + 1; return end
  t.tick = 0
  t.pan = t.pan + t.step
  local finished = false
  if t.step == 0 then
    finished = true
  elseif t.startPan < t.endPan then
    if t.pan >= t.endPan then finished = true end
  else
    if t.pan <= t.endPan then finished = true end
  end
  self:emitSound({ kind = "pan", pan = t.pan, id = t.id })
  if finished then t.done = true end
end

-- ONE FRAME OF `BattleAnimTask_SetPokemonSpritePriority`.
--
-- The cartridge's body is four statements in this order: run the Dark Void
-- effects at the CURRENT state, increment the state, and if the state has reached
-- maxFrames tear the whole thing down -- window off, copy hidden, manager
-- rendered one last time so the hide lands on this frame rather than the next.
-- The order matters: the effects see state 0 on the first frame they run, which
-- is the frame the window goes up.
local function stepMonSpritePrio(self, t)
  if t.pending then t.pending = false; return end
  if t.darkVoid then self:darkVoidStep(t) end
  t.state = (t.state or 0) + 1
  if t.state >= (t.maxFrames or 0) then
    -- `GX_SetVisibleWnd(GX_WNDMASK_NONE)` and `G2_SetWnd0Position(0, 0, 0, 0)`:
    -- the window is switched off, not narrowed.
    self.monWindowRect = nil
    local sprite = self.monSprites and self.monSprites[t.slot]
    if sprite then sprite.visible = false end
    t.done = true
  end
end

local STEP = {
  shake = stepShake, move = stepMove, scale = stepScale,
  fade = stepFade, hold = stepHold, pltfade = stepPltFade,
  empath = stepEmitterPath,
  bgswitch = stepBgSwitch, bgmove = stepBgMove, bgshake = stepBgShake,
  monrev = stepMonRev, emrev = stepEmitterRev,
  sndrepeat = stepSoundRepeat, snddelay = stepSoundDelay, sndpan = stepSoundPan,
  monprio = stepMonSpritePrio,
}

-- THE PALETTE FADE STEPS LAST, and that is a priority and not a preference.
-- `SysTask_FadePalette` runs at 0xFFFFFFFE -- the largest priority in the game --
-- and `SysTaskManager` walks tasks in ASCENDING priority, so every other task in a
-- frame sees the palette's state as the previous frame left it. The background
-- switch at 1100 depends on exactly that: it asks "is a fade still running" and
-- must not be answered by a fade that finished a moment ago in the same frame.
--
-- IT CHANGES NOTHING ELSE. `self.groups` is read at draw time, after every task
-- has stepped, so moving the writer later inside the frame is invisible to
-- everything but a reader inside the same frame -- of which the switch is the only
-- one. Ordering by a real priority field would be the general answer; this is the
-- one pair that needs it, and inventing the general answer for one pair is how a
-- port grows machinery nothing measures.
function Player:stepTasks()
  local live = {}
  local deferred = nil
  for _, t in ipairs(self.tasks) do
    if not t.done then
      if t.kind == "pltfade" then
        deferred = deferred or {}
        deferred[#deferred + 1] = t
      else
        local fn = STEP[t.kind]
        if fn then fn(self, t) else t.done = true end
        t.frame = t.frame + 1
        if not t.done then live[#live + 1] = t end
      end
    end
  end
  if deferred then
    for _, t in ipairs(deferred) do
      stepPltFade(self, t)
      t.frame = t.frame + 1
      if not t.done then live[#live + 1] = t end
    end
  end
  self.tasks = live
end

-- ---------------------------------------------------------------------------
-- callfunc
-- ---------------------------------------------------------------------------

-- The operand a function names, by the var index pret's `#define` gives it.
-- `args` here is the `callfunc` row's operand list, which is
-- { funcId, argCount, arg0, arg1, ... } -- so var 0 is args[3].
local function arg(args, index)
  if index == nil then return nil end
  local v = args[index + 3]
  if v == nil then return nil end
  return signed(v)
end

-- ...and the same operand read WITHOUT the sign, for the ones that are packed
-- pairs or bit masks rather than numbers.
local function rawArg(args, index)
  if index == nil then return nil end
  return args[index + 3]
end

-- BGR555 -> three 0-1 channels. The cartridge's fades name a colour in the
-- hardware's own 15-bit form and 0 is black, which is the common case.
-- (`PALETTE_BLEND_MAX` is declared with the other constants at the top of the
-- file, because the background switch's state machines are written above this
-- point and need it -- a name declared later in the file is a GLOBAL inside a
-- function written earlier, which is not an error and not a warning, just a nil.
-- It cost this pass an afternoon: the base fade read its end value as nil, became
-- a fade from 0 to 0, and finished on its first frame, so a twenty-frame switch
-- took five and nothing was ever tinted.)
local function bgr555(value)
  value = value or 0
  local r = (value % 32) / 31
  local g = (floor(value / 32) % 32) / 31
  local b = (floor(value / 1024) % 32) / 31
  return r, g, b
end

function Player:callFunc(args)
  local id = args[1]
  local vars = Player.VARS[id]
  local F = Player.FUNC

  -- AND THESE ARGUMENTS ARE THE SHARED SCRIPT VARS, exactly as
  -- `addspritewithfunc`'s are: `BattleAnimScriptCmd_CallFunc` copies them into
  -- `system->scriptVars[0..n-1]` and zeroes the rest before calling the function.
  -- The handlers below read them out of `args` directly, which is the same
  -- numbers -- but a later `ifvar` reads the VARS, and they have been clobbered.
  local given = tonumber(args[2]) or 0
  for i = 0, VAR_COUNT - 1 do
    local word = (i < given) and args[3 + i] or nil
    self.vars[i] = word and signed(word) or 0
  end

  if id == F.NOP then return end

  if id == F.SHAKE then
    self:addTask({
      kind = "shake",
      extentX = arg(args, vars.extentX) or 0,
      extentY = arg(args, vars.extentY) or 0,
      interval = max(1, arg(args, vars.interval) or 1),
      amount = max(0, min(Player.FRAME_BUDGET, arg(args, vars.amount) or 0)),
      sides = self:sidesFor(arg(args, vars.targets)),
    })
    return
  end

  if id == F.MOVE_BATTLER then
    self:addTask({
      kind = "move",
      frames = arg(args, vars.frames) or 1,
      offsetX = self:signedX(arg(args, vars.offsetX) or 0, arg(args, vars.target)),
      offsetY = arg(args, vars.offsetY) or 0,
      sides = self:sidesFor(arg(args, vars.target)),
    })
    return
  end

  if id == F.MOVE_BATTLER_X2 then
    self:addTask({
      kind = "move",
      frames = arg(args, vars.frames) or 1,
      offsetX = self:signedX(arg(args, vars.offset) or 0, arg(args, vars.target)),
      offsetY = 0,
      sides = self:sidesFor(arg(args, vars.target)),
    })
    return
  end

  if id == F.SCALE_BATTLER_SPRITE then
    -- THE SCALES ARE PERCENTAGES OF `reference`, not FX32 and not pixels: a
    -- program reads `100, 70, 100, 100` against a reference of `100`, which is
    -- "squash to 70% wide and back". Dividing by 4096 instead would shrink
    -- every Pokemon to a fortieth of itself.
    local ref = arg(args, vars.reference)
    if not ref or ref == 0 then ref = 100 end
    local function pc(v) return (v or ref) / ref end
    -- ...and FRAMES is a PACKED PAIR: scale frames in the high half, restore
    -- frames in the low. Only the scale half is a duration here, because the
    -- restore is the second leg the cartridge runs after the hold.
    local packed = rawArg(args, vars.frames)
    local frames = hi16(packed)
    if frames == 0 then frames = lo16(packed) end
    self:addTask({
      kind = "scale",
      frames = max(1, frames),
      startX = pc(arg(args, vars.startX)), endX = pc(arg(args, vars.endX)),
      startY = pc(arg(args, vars.startY)), endY = pc(arg(args, vars.endY)),
      sides = self:sidesFor(arg(args, vars.target)),
    })
    return
  end

  if id == F.FADE_BATTLER_SPRITE then
    local r, g, b = bgr555(arg(args, vars.colour))
    self:addTask({
      kind = "fade",
      frames = max(1, (arg(args, vars.stepFrames) or 1)
                      * max(1, arg(args, vars.alpha) or 1)),
      r = r, g = g, b = b,
      alpha = min(1, (arg(args, vars.alpha) or 0) / 16),
      sides = self:sidesFor(arg(args, vars.target)),
    })
    return
  end

  if id == F.HIDE_BATTLER then
    local hide = (arg(args, vars.hide) or 0) ~= 0
    for side in pairs(self:sidesFor(arg(args, vars.target))) do
      self.state[side].hidden = hide
    end
    return
  end

  if id == F.SET_POKEMON_SPRITE_PRIORITY then
    self:startMonSpritePriority(args, vars)
    return
  end

  if id == F.RENDER_POKEMON_SPRITES then
    -- IT DRAWS THE MON-SPRITE COPIES, which is now a thing this port has: the
    -- task is what makes a copy visible at all (`monSpritesRendered`). What it
    -- costs is TIME, and the frame count is the part a program sequences against.
    --
    -- !! AND ZERO MEANS THREE. `if (GetScriptVar(FRAMES) == 0) ctx->frames =
    -- RENDER_POKEMON_SPRITES_DEFAULT_FRAMES;` with that constant being 3 -- and
    -- 476 of the 477 calls in the corpus pass 0, the odd one out passing 45. This
    -- arm read the operand straight, so for 476 calls it built a task that ended
    -- on its first step: three frames of hold lost every time, and now three
    -- frames in which a copy would not have been drawn.
    local frames = arg(args, vars.frames) or 0
    if frames == 0 then frames = 3 end
    self:addTask({ kind = "hold", frames = frames, renders = true })
    return
  end

  -- !! THE THREE "EXAMPLE" FUNCTIONS ARE REAL CALLS AND DO NOTHING, and both
  -- halves of that are worth writing down. 33 of the 501 programs call each of
  -- them, 66 times apiece -- so they are not dead table entries -- and all three
  -- task bodies are the same three lines: state RUNNING becomes DONE, then the
  -- task ends. No motion, no sound, nothing drawn.
  --
  -- WHAT DIFFERS IS WHICH QUEUE EACH ONE OCCUPIES, and that is the only part a
  -- port can get wrong:
  --   1 AnimExample     an ANIM task, so `waitforanimtasks` waits for it
  --   2 SoundExample    a SOUND task, which nothing in this player waits on
  --   3 GenericExample  a plain SysTask, which nothing waits on at all
  -- So the first costs TIME and the other two cost nothing. Held rather than
  -- ignored for exactly that reason -- and two frames, because the task runs on
  -- the frame after it is created (RUNNING) and ends on the one after that.
  if id == F.ANIM_EXAMPLE then
    self:addTask({ kind = "hold", frames = 2 })
    return
  end
  if id == F.SOUND_EXAMPLE or id == F.GENERIC_EXAMPLE then
    self:note(id == F.SOUND_EXAMPLE and "callfunc:soundexample"
                                     or "callfunc:genericexample")
    return
  end

  if id == F.MOVE_EMITTER_LINEAR or id == F.MOVE_EMITTER_PARABOLIC then
    self:startEmitterPath(id == F.MOVE_EMITTER_PARABOLIC, {
      emitterId = arg(args, vars.emitterId) or 0,
      offsetX = arg(args, vars.offsetX) or 0,
      offsetY = arg(args, vars.offsetY) or 0,
      startDelay = arg(args, vars.startDelay) or 0,
      frames = arg(args, vars.frames) or 0,
      radius = arg(args, vars.radius) or 0,
      mode = arg(args, vars.mode) or 0,
      params = arg(args, vars.params) or 0,
      curve = arg(args, vars.curve) or 0,
    })
    return
  end

  if id == F.REVOLVE_BATTLER then
    local revs = arg(args, vars.revs) or 0
    local frames = arg(args, vars.framesPerRev) or 0
    if revs <= 0 or frames <= 0 then
      self:note("revolvebattler with no turns")
      return
    end
    self:addTask({
      kind = "monrev", pending = true,
      rev = Gen4AnimMath.ovalRevolution(revs, frames, true),
      sides = self:sidesFor(arg(args, vars.target) or 0),
    })
    return
  end

  if id == F.REVOLVE_EMITTER then
    self:startEmitterRevolution({
      emitterId = arg(args, vars.emitterId) or 0,
      startX = arg(args, vars.startX) or 0,
      endX = arg(args, vars.endX) or 0,
      startY = arg(args, vars.startY) or 0,
      endY = arg(args, vars.endY) or 0,
      radiusX = arg(args, vars.radiusX) or 0,
      radiusY = arg(args, vars.radiusY) or 0,
      frames = arg(args, vars.frames) or 0,
      mode = arg(args, vars.mode) or 0,
    })
    return
  end

  if id == F.MOVE_EMITTER_VIEWPORT_TOP then
    self:startEmitterViewportPath({
      emitterId = arg(args, vars.emitterId) or 0,
      mode = arg(args, vars.mode) or 0,
      kind = arg(args, vars.kind) or 0,
      frames = arg(args, vars.frames) or 0,
      startDelay = arg(args, vars.startDelay) or 0,
      params = rawArg(args, vars.params) or 0,
    })
    return
  end

  if id == F.SET_BG_GRAYSCALE then
    -- INSTANT, AND A TOGGLE. `MakeBgPalsGrayscale` writes the FADED palette buffer
    -- directly -- no task, no steps -- and `ReturnBgPalsToNormal` copies the
    -- unfaded buffer back over it. So there is nothing to time here and nothing to
    -- wait for; the only state is on or off.
    self.grayscale = (arg(args, vars.grayscale) or 0) ~= 0
    return
  end

  if id == F.FADE_BG then
    self:startPaletteFade(arg(args, vars.bgType) or 0,
                          arg(args, vars.delay) or 0,
                          arg(args, vars.startValue) or 0,
                          arg(args, vars.endValue) or 0,
                          arg(args, vars.colour) or 0)
    return
  end

  if id == F.SHAKE_BG then
    -- DRAWN NOW, and the shape is not `shake`'s. `BattleAnimTask_ShakeBg` wraps the
    -- shake context in an OUTER loop of `cycles + 1` runs and puts the offset back
    -- to zero between them, so its length is (cycles + 1) inner runs and not
    -- `cycles` frames.
    --
    -- WHAT WAS WRONG, AND IT WAS NOT THE MISSING PICTURE. This was a hold of
    -- `cycles` frames -- and `cycles` is 0 on 41 of the 42 calls, so 41 of them held
    -- for nothing at all while the comment above them said the length was preserved.
    -- The commonest call is extentY 5, amount 5, interval 0: 21 frames of one inner
    -- run, which is how much every `waitforanimtasks` after one was short.
    --
    -- 41 OF THE 42 NAME THE EFFECT LAYER and one names the base. The old comment
    -- said all of them did, on the grounds that every call passes five arguments so
    -- var 5 is zeroed -- but program 87's passes SIX. `shake` (36) can name the
    -- background too and not one of its 398 calls does; that part held up.
    local target = arg(args, (vars or {}).target) or 0
    self:addTask({
      kind = "bgshake", pending = true,
      extentX = arg(args, (vars or {}).extentX) or 0,
      extentY = arg(args, (vars or {}).extentY) or 0,
      interval = arg(args, (vars or {}).interval) or 0,
      amount = arg(args, (vars or {}).amount) or 0,
      cycles = arg(args, (vars or {}).cycles) or 0,
      layer = (target == 1) and "base" or "effect",
      inner = 0, iteration = 0,
    })
    return
  end

  self:note("callfunc:" .. tostring(id))
end

-- WHICH GROUP OF PALETTES A `fadebg` TYPE MEANS. pret's own three cases, named
-- so the draw side reads a word rather than a number.
Player.FADE_GROUPS = { [0] = "base", [1] = "mon", [2] = "effect" }

-- paletteFadeBusy() -> the group that is fading, or nil
--
-- ONE FADE AT A TIME FOR THE WHOLE MAIN BG PALETTE, and the guard is per BUFFER
-- and not per group. `PaletteData_StartFade` walks the buffers it was asked for
-- and skips any that is already in `selectedBuffers`; if that leaves nothing to
-- do it returns FALSE having changed nothing. All three `fadebg` types and both of
-- `switchbg`'s fades name PLTTBUF_MAIN_BG_F, and a buffer holds ONE
-- `PaletteFadeControl` -- so a second fade of any of them, while any of them is
-- running, does nothing at all.
--
-- THIS PORT HAD IT PER GROUP, AND IT DID NOT MATTER UNTIL NOW: measured over the
-- corpus, 0 of the 227 `fadebg` calls that the per-group guard let through would
-- have been refused by the buffer-wide one, because a program that fades the
-- backdrop does not fade the sprite palette at the same time. It matters from here
-- on because `switchbg`'s fade mode -- 127 calls -- takes the same buffer, and
-- program 87 fades the effect palette twice INSIDE its switch.
function Player:paletteFadeBusy()
  for _, other in ipairs(self.tasks) do
    if other.kind == "pltfade" and not other.done then
      return other.group or "a palette"
    end
  end
  return nil
end

-- startPaletteFade(bgType, delay, from, to, colour) -- the `fadebg` command
function Player:startPaletteFade(bgType, delay, from, to, colour)
  local group = Player.FADE_GROUPS[tonumber(bgType) or 0]
  if not group then
    -- pret's `default: GF_ASSERT(FALSE)`. Counted rather than guessed at.
    self:note("fadebg with an unknown bg type: " .. tostring(bgType))
    return false
  end
  return self:startGroupFade(group, delay, from, to, colour, "fadebg") ~= nil
end

-- ...and the same fade named by GROUP rather than by `fadebg`'s type number, so
-- the background switch can start one without pretending to be a script command.
-- Returns the task, or nil when the buffer refused it.
function Player:startGroupFade(group, delay, from, to, colour, why)
  local busy = self:paletteFadeBusy()
  if busy then
    -- Refusing is not queueing: the second call simply does nothing.
    self:note((why or "palette fade") .. " dropped, " .. busy
              .. " is already fading")
    return nil
  end
  delay = tonumber(delay) or 0
  local step, wait
  if delay < 0 then
    step, wait = 2 + (-delay), 0
  else
    step, wait = 2, delay
  end
  local r, g, b = bgr555(colour)
  local task = {
    kind = "pltfade", group = group,
    cur = tonumber(from) or 0, finish = tonumber(to) or 0,
    step = step, wait = wait, waitStep = wait,
    r = r, g = g, b = b,
    pending = true,
  }
  self:addTask(task)
  -- THE FIRST BLEND IS APPLIED INLINE, on this frame, because `StartFade` does
  -- it itself before the stepping task exists.
  self:applyPaletteFade(task)
  return task
end

-- A BLEND THAT IS NOT A FADE. `PaletteData_BlendMulti` writes one blend step and
-- returns -- no task, no buffer taken, no refusal -- which is how the fade mode
-- puts the effect palette at full black on the same frame it starts the backdrop
-- fading. It leaves the group sitting at that level until something else moves it.
function Player:blendGroupNow(group, level, colour)
  if not group then return false end
  local r, g, b = bgr555(colour)
  level = tonumber(level) or 0
  if level <= 0 then
    self.groups[group] = nil
  else
    self.groups[group] = { r, g, b, level / PALETTE_BLEND_MAX }
  end
  return true
end

-- ---------------------------------------------------------------------------
-- switchbg / restorebg
-- ---------------------------------------------------------------------------

-- bgSwitchStart(bgID, param, restoring) -> the task
--
-- `param` is ONE operand carrying two things: `BATTLE_BG_SWITCH_MODE(VAR)` is its
-- low half and `BATTLE_BG_SWITCH_FLAGS(VAR)` its high half. A restore adds
-- BATTLE_BG_SWITCH_MODE_COUNT to the mode, which is how the same three numbers
-- select six different state machines.
--
-- THE VARS ARE SNAPSHOT, not read later. `BattleAnimSystem_CreateBgSwitch` copies
-- all ten script vars into the context, and it has to: `setvar` is free to
-- overwrite them the instant the command returns, and 73 of the programs that
-- switch call `resetvars` between their switch and their restore.
function Player:bgSwitchStart(bgID, param, restoring)
  param = tonumber(param) or 0
  local mode = param % 65536
  local flags = floor(param / 65536)
  local vars = {}
  for i = 0, VAR_COUNT - 1 do vars[i] = signed(self.vars[i] or 0) end
  -- ANY VALUE BUT 1 OR 2 IS THE DEFAULT, and that is pret's shape rather than a
  -- fallback invented here: `CreateBgSwitch` sets the full-cross-fade coefficients
  -- and then has two bare `if`s for PARTIAL and INVERSE_PARTIAL, with no else and
  -- no assert. It matters because var 5 is a SHARED script var: one program reaches
  -- a switch with 60 left in it from an earlier command, and on the hardware that
  -- is simply a full cross-fade.
  local blendType = vars[Player.BG_VAR.blendType] or 0
  local coeffs = BG_BLEND_COEFFS[blendType] or BG_BLEND_COEFFS[0]
  if restoring then mode = mode + BG_SWITCH_MODE_COUNT end
  self.bgSwitchState = BG_STATE_RUNNING
  return self:addTask({
    kind = "bgswitch", state = 0, pending = true,
    bgID = tonumber(bgID) or 0, mode = mode, flags = flags,
    fadeType = vars[Player.BG_VAR.fadeType] or 0,
    vars = vars,
    coeffA = coeffs[1], coeffB = coeffs[2],
    targetA = coeffs[3], targetB = coeffs[4],
    blend = (mode % BG_SWITCH_MODE_COUNT) == BG_SWITCH_MODE_BLEND,
  })
end

-- bgReversed(t, varIndex) -> should the mirrored arrangement be used
--
-- `BattleBgSwitch_ShouldBeReversed`, and the var it reads is the caller's: the
-- SCREEN mode picks the tilemap and the ANIM mode negates the scroll, and a
-- program is free to set them differently (76 calls set the screen mode to 1 and
-- 42 the anim mode).
--
-- ONE OF PRET'S THREE BRANCHES CANNOT BE REACHED HERE. The first asks whether the
-- attacker and the defender are on the SAME side, which needs a partner battler;
-- this port draws one Pokemon a side, so they never are. It is written out anyway,
-- because the day this port grows doubles is not the day to rediscover it, and
-- because in singles both non-zero modes collapse to the same test -- which is a
-- fact worth being able to see rather than a coincidence to lean on silently.
function Player:bgReversed(t, varIndex)
  local mode = (t.vars and t.vars[varIndex]) or 0
  if mode == 0 then return false end          -- BATTLE_BG_ANIM_REVERSE_NEVER
  local attackerIsPlayer = self.attackerIsPlayer and true or false
  local defenderIsPlayer = not attackerIsPlayer
  if mode == 2 then                           -- ..._REVERSE_DEFAULT
    -- pret: same side -> reversed unless the defender is the player. Unreachable
    -- with one battler a side; the else-branch below is the one that runs.
    return defenderIsPlayer
  end
  return defenderIsPlayer                     -- ..._REVERSE_ENEMY_ONLY
end

-- Which of the three tilemaps this switch wants, and then the picture itself.
function Player:bgLoadArt(t)
  local variant = "normal"
  if self.contest then
    variant = "contest"
  elseif self:bgReversed(t, Player.BG_VAR.screenMode) then
    variant = "reversed"
  end
  self.bgLayer = {
    id = t.bgID, variant = variant, blend = t.blend and true or false,
    base = 1, effect = 1,
  }
  return self.bgLayer
end

-- The blend coefficients as the draw side wants them: how much of the field shows
-- and how much of the effect layer does. Called with (base, effect) in that order,
-- which is why the two blend machines pass their two numbers the opposite way
-- round.
function Player:bgApplyBlend(t, baseCoeff, effectCoeff)
  local layer = self.bgLayer
  if not layer then return false end
  layer.base = bgAlpha(baseCoeff)
  layer.effect = bgAlpha(effectCoeff)
  return true
end

local function bgFlagSet(flags, flag)
  return floor((tonumber(flags) or 0) / flag) % 2 == 1
end

-- `BattleBgSwitch_ApplyFlags`, in its own order, with CANCEL absent because pret's
-- array does not list it.
function Player:bgApplyFlags(t)
  for _, flag in ipairs(BG_FLAG_ORDER) do
    if bgFlagSet(t.flags, flag) then
      if flag == BG_FLAG_MOVE then
        -- The scroll. The start offsets are 0 on every call in the cartridge, which
        -- is why pret's "only write the register when the step is non-zero" makes
        -- no difference and this does not reproduce it.
        local anim = {
          offsetX = t.vars[Player.BG_VAR.startX] or 0,
          offsetY = t.vars[Player.BG_VAR.startY] or 0,
          stepX = t.vars[Player.BG_VAR.stepX] or 0,
          stepY = t.vars[Player.BG_VAR.stepY] or 0,
          cancel = false,
        }
        if self:bgReversed(t, Player.BG_VAR.animMode) then
          anim.stepX, anim.stepY = -anim.stepX, -anim.stepY
          anim.offsetX, anim.offsetY = -anim.offsetX, -anim.offsetY
        end
        self.bgAnim = anim
        t.moveActive = true
        self:addTask({ kind = "bgmove", anim = anim, pending = true })
      elseif flag == BG_FLAG_STOP then
        -- `BattleBgSwitch_AnimStop` SETS THE FLAG AND DOES NOTHING ELSE. It does
        -- not stop the scroll; it marks this context so that when the restore
        -- reaches its cancel state it cancels one. Which is why 46 restores carry
        -- STOP and 39 switches carry MOVE: the restore is where the scroll dies.
        t.moveActive = true
      elseif flag == BG_FLAG_WAVE then
        -- `AnimStartWave` builds a sixteen-strip scanline scroll -- sBgWaveScrollSpeeds
        -- over rows 64..192, an H-blank effect this port has no channel for. NO
        -- PROGRAM IN THE CARTRIDGE SETS THIS FLAG, so it is recorded rather than
        -- guessed at, and the restore still knows to cancel.
        t.waveActive = true
        self:note("switchbg wave (no program sets it)")
      elseif flag == BG_FLAG_REGISTER_WAVE then
        t.waveActive = true
      end
    end
  end
end

-- The restore's cancel state. pret calls `CancelBgAnim` once for the move flag and
-- again for the wave flag; the second call is a no-op because the first already
-- set `cancel`, and both are here so the shape matches.
function Player:bgCancelAnims(t, moveOnly)
  if t.moveActive and self.bgAnim then self.bgAnim.cancel = true end
  if not moveOnly and t.waveActive and self.bgAnim then
    self.bgAnim.cancel = true
  end
  if t.moveActive or (not moveOnly and t.waveActive) then self.bgAnim = nil end
end

-- Where `shakebg` puts its offset. The EFFECT layer is the one the backdrop lives
-- on outside a switch, so this is the same field either way and the draw decides
-- whether it is moving the switched picture or the backdrop.
--
-- THE BASE LAYER IS NOT DRAWN BY THIS PORT AT ALL. Exactly one of the 42 calls
-- names it -- program 87, the only call that passes six arguments rather than five
-- -- and it is inside a FADE-mode switch, which never turns BG2 on. So the
-- cartridge moves a layer that is not on the screen, and this records that instead
-- of moving something that is.
function Player:bgShakeApply(t, x, y)
  if t.layer == "base" then
    if not t.noted then
      t.noted = true
      self:note("shakebg on the base layer, which is not drawn")
    end
    return false
  end
  if x == 0 and y == 0 then self.bgShake = nil else self.bgShake = { x, y } end
  return true
end

-- bgLayerState() -> what the screen should draw, or nil
--
-- Read under `alive()` like every other channel, because a switch that is still
-- coming down when the script ends is still on the screen.
function Player:bgLayerState()
  if not self:alive() then return nil end
  local layer = self.bgLayer
  local shake = self.bgShake
  local anim = self.bgAnim
  if not (layer or shake) then return nil end
  local r, g, b, a
  if layer then r, g, b, a = self:groupTint("effect") end
  return {
    id = layer and layer.id or nil,
    variant = layer and layer.variant or nil,
    blend = layer and layer.blend or false,
    base = layer and layer.base or 1,
    effect = layer and layer.effect or 1,
    offsetX = (anim and anim.offsetX or 0) + (shake and shake[1] or 0),
    offsetY = (anim and anim.offsetY or 0) + (shake and shake[2] or 0),
    tint = (a and a > 0) and { r, g, b, a } or nil,
  }
end

-- What the group is wearing this frame. A fraction of zero is the unfaded colour
-- written back, so it is recorded as no tint at all rather than as a tint of
-- nothing -- which keeps the draw path from blending a fully transparent quad
-- over the whole screen sixty times a second.
function Player:applyPaletteFade(t)
  if t.cur <= 0 then
    self.groups[t.group] = nil
  else
    self.groups[t.group] = { t.r, t.g, t.b, t.cur / PALETTE_BLEND_MAX }
  end
end

-- groupTint(name) -> r, g, b, alpha  (or nil)
--
-- The same shape as `monTint`, and read under the same rule: while the player is
-- ALIVE, not while its script is running, because a fade outlives `end` exactly
-- like everything else the script started.
function Player:groupTint(name)
  if not self:alive() then return nil end
  local c = self.groups and self.groups[name]
  if not c then return nil end
  return c[1], c[2], c[3], c[4]
end

-- bgGrayscale() -> is the battle background grey this frame
--
-- Read under `alive()` like every other channel. WHAT IT DOES AND DOES NOT COVER,
-- measured rather than assumed: `ConvertColorsToGrayscale` is called over
-- `PALETTE_SIZE * BATTLE_BG_PALETTE_MON_SPRITE` = 128 colours, which is
-- sub-palettes 0 to 7 of the MAIN BG buffer -- so
--   * the backdrop greys. The highest palette index any of the 23 backdrop tile
--     sheets uses is 111, so all 128 covers every colour they have: measured over
--     the shared tilemap's own tiles, not assumed from the count.
--   * the switched effect background does NOT. Its palette is slot 9, outside the
--     128.
--   * the Pokemon and the terrain platforms do NOT. They are OBJs, in a different
--     palette buffer entirely.
function Player:bgGrayscale()
  if not self:alive() then return false end
  return self.grayscale == true
end

-- ---------------------------------------------------------------------------
-- Sound: the seam, and the two pan corrections
-- ---------------------------------------------------------------------------

-- emitSound(event) -> the event, with its frame filled in
--
-- ONE SEAM FOR ALL TEN COMMANDS, and it hands over a TABLE rather than an id
-- because nine of the ten carry something besides one: a pan, a repeat index, a
-- fade length, a cry's modulation and volume. The old seam took `onSound(id)` and
-- the five commands that are not a bare play had nowhere to put the rest.
--
-- `kind` is one of:
--   "play"      an effect starts. `pan` if it was given one.
--   "pan"       every playing effect moves to `pan`.
--   "stop"      one effect id stops.
--   "cry"       the ATTACKER's cry, with pret's modulation and volume.
--   "stopcries" every cry stops, over `fadeOutFrames`.
-- WHOSE cry it is, this layer does not say and cannot: the player is handed a move
-- and a side, not a party. `side = "attacker"` is the cartridge's own answer --
-- `context->battlerSpecies[context->attacker]` -- and the battle, which knows the
-- Pokemon, resolves it.
function Player:emitSound(event)
  event.frame = self.frames
  self.soundEvents[#self.soundEvents + 1] = event
  -- The old flat list stays: it is what `withSound` counts and what the duration
  -- check reads, and an id is still the most useful single fact about an event.
  if event.id then self.sounds[#self.sounds + 1] = event.id end
  -- SILENT ON THE MEASURING PASS. `duration()` runs the program to the end and then
  -- restarts it, so without this every move would play its whole soundtrack once
  -- before the animation the player can see.
  if not self.quiet and self.onSound then self.onSound(event) end
  return event
end

-- `BattleAnimSound_CorrectPanDirection`: a pan is written for the PLAYER attacking,
-- and mirrored when the enemy is.
--
-- pret has four branches and two of them need a partner battler -- attacker and
-- defender on the same side, where a pan is clamped to one side rather than flipped
-- -- so with one Pokemon a side only the first two can be reached. Written out so
-- a doubles battler does not have to rediscover them.
function Player:correctPan(pan)
  pan = tonumber(pan) or 0
  if self.attackerIsPlayer then return pan end          -- player -> enemy: as written
  return -pan                                            -- enemy -> player: mirrored
  -- same side, player: `if pan > 0 then pan = -pan end`
  -- same side, enemy:  `if pan < 0 then pan = -pan end`
end

-- `BattleAnimSound_CorrectStepDirection`: the step's MAGNITUDE is the script's and
-- its SIGN is the endpoints'. 10 of the 113 moving sounds sweep right to left and
-- still pass a positive step, so a port that used the operand's own sign would run
-- those ten the wrong way -- and, because the walk's end test is written against the
-- endpoints, would never finish either.
function Player:correctPanStep(startPan, endPan, step)
  step = math.abs(tonumber(step) or 0)
  if startPan < endPan then return step end
  if startPan > endPan then return -step end
  return 0
end

-- startMovingSound(args, correct) -- `playmovingsoundeffect*`
--
-- Plays the effect at once, at the START pan, and leaves a task to walk it across.
-- 113 calls, and 101 of them are the same sweep: -117 to +117, four at a time, every
-- other frame -- a noise crossing the screen with the attack.
function Player:startMovingSound(args, correct)
  local startPan = signed(args[2] or 0)
  local endPan = signed(args[3] or 0)
  local step = signed(args[4] or 0)
  if correct then
    startPan, endPan = self:correctPan(startPan), self:correctPan(endPan)
  end
  step = self:correctPanStep(startPan, endPan, step)
  self:emitSound({ kind = "play", id = args[1], pan = startPan, moving = true })
  self:addTask({ kind = "sndpan", pending = true,
                 id = args[1], pan = startPan, startPan = startPan,
                 endPan = endPan, step = step,
                 interval = signed(args[5] or 0), tick = 0 })
  return true
end

-- THE ATTACKER FACES THE OTHER WAY, and the cartridge says so rather than
-- leaving it to the caller: `BattleAnimUtil_GetTransformDirectionX` flips the x
-- offset for one side, so a lunge is toward the opponent on both. Without it
-- every enemy move lunges backwards off its own platform.
function Player:signedX(value, target)
  local sides = self:sidesFor(target)
  -- a mask naming both sides has no single direction; leave it unflipped
  if sides[true] and sides[false] then return value end
  local towardsLeft = sides[false]
  return towardsLeft and -value or value
end

function Player:note(what)
  if Player.NOT_NEEDED[what] then
    self.skipped = self.skipped or {}
    self.skipped[what] = (self.skipped[what] or 0) + 1
    return
  end
  self.unsupported[what] = (self.unsupported[what] or 0) + 1
end

-- ---------------------------------------------------------------------------
-- Jumps
-- ---------------------------------------------------------------------------

-- WHICH OPERAND HOLDS THE TARGET, AND WHETHER THE COMMAND CAN FALL THROUGH.
--
-- `BattleAnimScript_JumpBy(offset)` is `scriptPtr += offset`, and the pointer
-- is sitting on the operand it just read -- so a target is
-- (instruction start + operand index) + that operand's value, NOT the
-- instruction's start. Getting that base wrong lands one word off on every
-- branch in the game.
--
-- `slot` is the operand index the taken branch reads, counting the opcode as 0.
-- `fall` means the untaken branch simply continues; the rest ALWAYS jump, to
-- one of two or three targets.
local JUMPS = {
  ["jump"] = { always = true, slots = { 1 } },
  ["call"] = { always = true, slots = { 1 }, pushes = true },
  ["return"] = { always = true, pops = true },
  -- if contest -> +1, else fall through. There are no contests here.
  ["jumpifcontest"] = { fall = true, slot = 1, taken = false },
  -- if attacker and defender are on the same side -> +1, else fall through.
  ["jumpiffriendlyfire"] = { fall = true, slot = 1, taken = false },
  -- two targets, and it ALWAYS takes one: player side reads operand 2, enemy
  -- side skips a word first and reads operand 3.
  ["jumpifbattlerside"] = { always = true, slots = { 2, 3 }, pick = "side" },
  -- odd effect chance skips a word first; both arms jump.
  ["jumpifeffectchanceodd"] = { always = true, slots = { 1, 2 }, pick = "odd" },
  -- no weather / matching / not matching. This port hands it "no weather"
  -- unless the battle says otherwise, which is the first target.
  ["jumpifweather"] = { always = true, slots = { 1, 2, 3 }, pick = "weather" },
  -- compares a script var this player does keep.
  ["jumpifequal"] = { fall = true, slot = 3, taken = "equal" },
}

-- jump(name, args, row) -> true when the pc was set (or deliberately not)
function Player:jump(name, args, row)
  local spec = JUMPS[name]
  if not spec then return false end

  if spec.pops then
    local top = self.calls[#self.calls]
    if not top then return false end
    self.calls[#self.calls] = nil
    self.pc = top
    return true
  end

  -- Without the word map a target cannot be resolved at all, and guessing one
  -- would run an arbitrary instruction. Say so instead: the note names the
  -- command and a re-import fixes it.
  if not self.atWord then return false end
  local start = self.wordAt and self.wordAt[self.pc - 1]
  if not start then return false end

  local slot
  if spec.always then
    if spec.pick == "side" then
      -- ATTACKER'S SIDE decides, and "enemy" here means the enemy of the
      -- player, not of the attacker.
      slot = self.attackerIsPlayer and spec.slots[1] or spec.slots[2]
    elseif spec.pick == "odd" then
      slot = spec.slots[1]              -- an even effect chance, the common case
    elseif spec.pick == "weather" then
      slot = spec.slots[1]              -- no field weather
    else
      slot = spec.slots[1]
    end
  else
    local take = spec.taken
    if take == "equal" then
      take = (self.vars[args[1] or 0] == (args[2] or 0))
    end
    if not take then return true end    -- fall through: the pc already advanced
    slot = spec.slot
  end

  local offset = signed(args[slot])
  if offset == nil then return false end
  local target = self.atWord[start + slot + offset]
  if not target then return false end
  if spec.pushes then self.calls[#self.calls + 1] = self.pc end
  self.pc = target
  return true
end

-- ---------------------------------------------------------------------------
-- The VM
-- ---------------------------------------------------------------------------

-- (`Gen4MoveAnim.SOUND_OPS` used to be bound here as the catch-all for every
-- sound command. The ten of them have their own arms now, so nothing reads it.)

-- One frame. Returns true while the animation is still running.
--
-- The shape is the cartridge's: run instructions until one says to wait, step
-- the tasks, and come back next frame. `delay` and `waitforanimtasks` are the
-- only two things that end a frame, which is why a program with neither runs to
-- its `end` in a single call rather than hanging.
function Player:update()
  if not self.playing then
    -- THE TAIL, AND IT IS LONGER THAN ONE FRAME.
    --
    -- `end` stops the SCRIPT; it does not stop what the script started. A burst
    -- of particles keeps flying and MetalClaw's four claws keep swiping for
    -- their full forty frames, because on the hardware those are SysTasks with
    -- their own lifetimes and the script's last command has no authority over
    -- them.
    --
    -- THIS WAS WRONG FOR A WHOLE SESSION AND THE CHECKS DID NOT SEE IT. The tail
    -- was granted at the bottom of this function -- "not playing but effects
    -- live, so return true" -- and then this guard, one line, refused the very
    -- next frame. So every program's tail was exactly ONE frame long, which is
    -- long enough to look deliberate in a total and far too short for anything
    -- it was meant to cover: Metal Claw's claws were cut off at eighteen frames
    -- of forty, every burst lost its fall. A total that was merely RECORDED
    -- rather than PREDICTED could not notice -- the fix and the fault produce
    -- equally plausible numbers -- so the check now asserts the tail's LENGTH on
    -- a named program, which the one-frame version fails by construction.
    if self:hasLiveEffects() then
      self.frames = self.frames + 1
      if self.frames > Player.FRAME_BUDGET then
        self:note("frame budget in the tail")
        self:clearTransforms()
        return false
      end
      self:stepTasks()
      self:stepEmitters()
      self:stepSprites()
      -- The frame that empties the screen is the last one: there is nothing left
      -- to draw, so saying otherwise would add a blank frame to every program.
      local live = self:hasLiveEffects()
      if not live then self:clearTransforms() end
      return live
    end
    return false
  end
  self.frames = self.frames + 1
  if self.frames > Player.FRAME_BUDGET then
    self:note("frame budget")
    self:stop()
    return false
  end

  if self.delay > 0 then
    self.delay = self.delay - 1
    self:stepTasks()
    self:stepEmitters()
    self:stepSprites()
    return true
  end

  local steps = 0
  while self.playing do
    steps = steps + 1
    if steps > Player.STEP_BUDGET then
      self:note("step budget")
      self:stop()
      return false
    end
    local row = self.code[self.pc]
    if not row then self:stop(); break end
    local op = row[1]
    local name = Gen4MoveAnim.OPCODES[op]
    local args = {}
    for i = 2, #row do args[i - 1] = row[i] end
    self.pc = self.pc + 1

    if name == "end" then
      self:stop()
      break
    elseif name == "delay" then
      self.delay = max(0, (args[1] or 0) - 1)
      break
    elseif name == "waitforanimtasks" then
      if self:taskCount() > 0 then
        self.pc = self.pc - 1     -- re-execute next frame, as the cartridge does
        break
      end
    elseif name == "waitforallemitters" then
      -- THIS ONE IS NO LONGER FREE, and that is the whole point of the particle
      -- layer: it is what gives a move its length. Nearly every program in the
      -- cartridge ends by loading a system, creating its emitters and waiting
      -- here, stating no duration of its own -- so while this returned
      -- immediately, every move in Platinum was as long as its delays alone.
      if self:emitterCount() > 0 then
        self.emitterWaits = self.emitterWaits + 1
        self.pc = self.pc - 1     -- re-execute next frame, as the cartridge does
        break
      end
    elseif name == "loadparticlesystem" then
      self:loadParticles(args[1], args[2])
    elseif name == "loaddebugparticlesystem" then
      -- (system, narcID, member). The NARC is debug_particle.narc, which is not
      -- in the retail cartridge at all -- pret says so in the macro comment --
      -- so this cannot resolve and is counted rather than pointed at the move
      -- archive, where member N is a different effect entirely.
      self:note("loaddebugparticlesystem")
    elseif name == "unloadparticlesystem" then
      -- The slot's resources go; emitters already running keep running, which
      -- is what `waitforallemitters` waiting on all of them regardless of slot
      -- implies, and what a program that unloads before waiting requires.
      self.slots[tonumber(args[1]) or 0] = nil
    elseif name == "createemitter" then
      self:createEmitter(args[1], args[2], args[3])
    elseif name == "createemitterex" then
      -- (system, emitterIndex, resource, callback). `emitterIndex` IS USED NOW:
      -- it is the slot the cartridge files the running emitter under, and the
      -- emitter-motion functions address one by that number.
      self:createEmitter(args[1], args[3], args[4], args[2])
    elseif name == "createemitterformove" then
      local resource, callback = self:resourceForMove(args)
      self:createEmitter(args[1], resource, callback)
    elseif name == "createemitterforfriendlyfire" then
      -- (system, resPl, resEm, unused, unused, callback), and the two unused
      -- operands are pret's word, not an assumption.
      self:createEmitter(args[1],
                         self.attackerIsPlayer and args[2] or args[3], args[6])
    elseif name == "initspritemanager" then
      self:initSpriteManager(args[1], {
        sprites = args[2], char = args[3], palette = args[4], cell = args[5],
        anim = args[6], multiCell = args[7], multiAnim = args[8],
      })
    elseif name == "loadcharresobj" then
      self:loadSpriteResource("char", args[1], args[2])
    elseif name == "loadplttres" then
      -- (manager, member, paletteIndex). The palette index is 1 on all 34 calls
      -- in the cartridge, and the cell bank's own OAM field is what actually
      -- picks a bank -- see `Gen4CellAnim.paletteFor`.
      self:loadSpriteResource("palette", args[1], args[2])
    elseif name == "loadcellresobj" then
      self:loadSpriteResource("cell", args[1], args[2])
    elseif name == "loadanimresobj" then
      self:loadSpriteResource("anim", args[1], args[2])
    elseif name == "addspritewithfunc" then
      -- (manager, func, char, pltt, cell, anim, multiCell, multiAnim, count,
      --  args...). The trailing arguments are SCRIPT VARS 0..count-1 -- the
      --  handler copies them into `scriptVars` and zeroes the rest -- which is
      --  why this opcode's width is counted rather than fixed.
      --
      -- AND THEY ARE THE SAME TEN SLOTS `setvar` WRITES. pret's handler assigns
      -- `system->scriptVars[i]` and then zeroes i..9, the identical array
      -- `BattleAnimScriptCmd_SetVar` and `resetvars` use. So this command
      -- CLOBBERS anything a `setvar` before it put in those slots, and a port
      -- that kept the sprite's arguments in a private list would read the wrong
      -- numbers the moment a program did both. Signed on the way in: the
      -- cartridge writes these as negative words -- move 333 passes -15, -5, 10,
      -- 32 -- and an unsigned read is the same four-billion bug the pan and fade
      -- operands cost once already.
      local count = tonumber(args[9]) or 0
      for i = 0, VAR_COUNT - 1 do
        local word = (i < count) and args[10 + i] or nil
        self.vars[i] = word and signed(word) or 0
      end
      self:addSprite(args[1], args[2], args[3], args[4], args[5], args[6])
    elseif name == "addsprite" then
      self:addSprite(args[1], nil, args[3], args[4], args[5], args[6])
    elseif name == "freespritemanager" then
      -- The manager's resources go; sprites already made keep playing, the same
      -- way `unloadparticlesystem` leaves running emitters alone.
      self.managers[tonumber(args[1]) or 0] = nil
    elseif name == "waitforbgswitch" then
      -- NO LONGER FREE. 114 calls, and every one of them is what holds a program
      -- still while its background changes -- a fade is sixteen palette steps each
      -- way, so a switch and its restore are about twenty frames apiece. While this
      -- returned immediately every one of those 54 programs played its whole
      -- animation over the unswitched backdrop and then ended.
      if self.bgSwitchState ~= BG_STATE_NONE then
        self.bgWaits = self.bgWaits + 1
        self.pc = self.pc - 1     -- re-execute next frame, as the cartridge does
        break
      end
    elseif name == "waitforpartialbgswitch" then
      -- Releases at the point the screen is fully faded and the new picture is
      -- loaded behind it -- BATTLE_BG_SWITCH_STATE_PARTIAL -- which is a state only
      -- the fade mode ever reaches. Three calls in the cartridge.
      if self.bgSwitchState ~= BG_STATE_PARTIAL then
        self.bgWaits = self.bgWaits + 1
        self.pc = self.pc - 1
        break
      end
    elseif name == "switchbg" then
      self:bgSwitchStart(args[1], args[2], false)
    elseif name == "restorebg" then
      -- The bg id operand IS READ and then not used: pret's own comment on the
      -- macro says so ("not actually used"), and the restore always goes back to
      -- the battle's own backdrop rather than to a named picture.
      self:bgSwitchStart(args[1], args[2], true)
    elseif name == "setbgswitchvar" then
      -- Writes straight into the LIVE scroll, not into the script vars -- which is
      -- why pret's comment says it may only be called after a switch. Nine calls
      -- in the cartridge and all nine write var 1.
      --
      -- AND ONE OF THE FOUR CASES IS A BUG THIS PORT KEEPS. var 3 is
      -- BATTLE_ANIM_VAR_BG_MOVE_START_Y and its handler assigns `offsetX`. No
      -- program uses it, so nothing in the cartridge depends on the bug either way,
      -- but a port that silently corrected it would be a port whose behaviour
      -- cannot be compared with the hardware's.
      local anim = self.bgAnim
      local which = signed(args[1] or 0)
      local value = signed(args[2] or 0)
      if not anim then
        self:note("setbgswitchvar with no scroll running")
      elseif which == Player.BG_VAR.stepX then anim.stepX = value
      elseif which == Player.BG_VAR.stepY then anim.stepY = value
      elseif which == Player.BG_VAR.startX then anim.offsetX = value
      elseif which == Player.BG_VAR.startY then anim.offsetX = value
      else self:note("setbgswitchvar on var " .. tostring(which)) end
    elseif name == "setbg" then
      -- A switch with no transition at all: the picture is just loaded. ZERO
      -- PROGRAMS USE IT, so nothing exercises this and it is here because it is
      -- three lines and because a reader looking for it should find it rather than
      -- find it in the gap report.
      self.bgLayer = { id = signed(args[1] or 0), variant = "normal",
                       blend = false, base = 1, effect = 1 }
    elseif name == "switchbgex" then
      -- Three ids -- player attacking, enemy attacking, contest -- and the mode and
      -- flags operands the other two carry are absent, so it is always a BLEND with
      -- no flags. ZERO PROGRAMS USE IT.
      local pick
      if self.contest then pick = args[3]
      elseif not self.attackerIsPlayer then pick = args[2]
      else pick = args[1] end
      self:bgSwitchStart(pick, 0, false)
    elseif name == "waitforlrx" then
      -- THE LAST FREE WAIT. pret's `WaitForLRX` waits on the two LR registers the
      -- 3D pass uses, which this port has no equivalent of at all -- so it is
      -- satisfied at once and counted, because a wait that is free is a wait whose
      -- subject is missing. `waitforsoundeffects` and `waitforpokemoncries` used to
      -- share this arm and have their own below.
      self:note("wait:" .. tostring(name))
    elseif name == "setvar" then
      -- `if (id < BATTLE_ANIM_SCRIPT_VAR_COUNT)`: there are ten slots and a
      -- write past them is dropped, not stored. Counted, because a program that
      -- addressed an eleventh var would mean the operand is not a var id.
      local id = tonumber(args[1]) or 0
      if id >= 0 and id < VAR_COUNT then
        self.vars[id] = args[2] or 0
      else
        self:note("setvar out of range: " .. tostring(id))
      end
    elseif name == "resetvars" then
      self.vars = {}
    elseif name == "beginloop" then
      self.loops[#self.loops + 1] = { pc = self.pc, left = args[1] or 0 }
    elseif name == "endloop" then
      local top = self.loops[#self.loops]
      if top then
        top.left = top.left - 1
        if top.left > 0 then self.pc = top.pc
        else self.loops[#self.loops] = nil end
      end
    elseif name == "callfunc" then
      self:callFunc(args)
    elseif JUMPS[name] then
      -- 77 OF THE 501 PROGRAMS BRANCH, and the first jump is often the very
      -- first instruction. An earlier draft of this file asserted in a comment
      -- that no program reached one on its main path; the check disagreed, and
      -- the check was right. That is the recurring fault in this port -- a
      -- claim written from an assumption instead of a measurement -- caught
      -- here by a test rather than by a player noticing a move do the wrong
      -- half of its animation.
      if not self:jump(name, args, row) then
        self:note("jump:" .. tostring(name))
      end
    elseif name == "playsoundeffect" then
      self:emitSound({ kind = "play", id = args[1] })
    elseif name == "playpannedsoundeffect" then
      self:emitSound({ kind = "play", id = args[1],
                       pan = self:correctPan(signed(args[2] or 0)) })
    elseif name == "pansoundeffects" then
      -- ZERO USES. Here because it is one line and because a reader looking for it
      -- should find it rather than find it in the gap report.
      self:emitSound({ kind = "pan",
                       pan = self:correctPan(signed(args[1] or 0)) })
    elseif name == "playloopedsoundeffect" then
      -- (id, pan, interval, count). `tickCount` starts AT the interval, so the first
      -- play is on the task's first active frame and the rest are interval + 1 apart.
      local count = signed(args[4] or 0)
      if count <= 0 then
        self:note("playloopedsoundeffect with a count of " .. tostring(count))
      else
        self:addTask({ kind = "sndrepeat", pending = true,
                       id = args[1], pan = self:correctPan(signed(args[2] or 0)),
                       interval = signed(args[3] or 0),
                       tick = signed(args[3] or 0), left = count, total = count })
      end
    elseif name == "playdelayedsoundeffect" then
      -- (id, pan, interval). Fires once, `interval` frames after its first active one.
      self:addTask({ kind = "snddelay", pending = true,
                     id = args[1], pan = self:correctPan(signed(args[2] or 0)),
                     interval = signed(args[3] or 0) })
    elseif name == "playmovingsoundeffectatkdef"
        or name == "playmovingsoundeffectatkdef2" then
      -- (id, startPan, endPan, step, interval). Plays at once AT the start pan and
      -- then a task walks the pan across. `atkdef2` is a second opcode pret marks
      -- "functionally equivalent"; it has zero uses and shares this arm.
      self:startMovingSound(args, true)
    elseif name == "playmovingsoundeffectnocorrection" then
      -- The same, with NO pan correction -- which is the whole difference, and the
      -- reason it is a separate opcode. Zero uses.
      self:startMovingSound(args, false)
    elseif name == "stopsoundeffect" then
      self:emitSound({ kind = "stop", id = args[1] })
    elseif name == "playpokemoncry" then
      -- (modulation, pan, volume). The ATTACKER's cry: pret reads
      -- `context->battlerSpecies[context->attacker]`, and which Pokemon that is, this
      -- layer does not know -- so the event names the SIDE and the battle resolves it.
      self:emitSound({
        kind = "cry", side = "attacker",
        modulation = signed(args[1] or 0),
        pan = self:correctPan(signed(args[2] or 0)),
        volume = signed(args[3] or 0),
      })
      self.cryPending = true
    elseif name == "waitforpokemoncries" then
      -- THE ONLY SOUND COMMAND THAT WAITS, and it waits on something only the engine
      -- knows: `Sound_IsPokemonCryPlaying()`. The seam is asked if it can answer, and
      -- a battle that cannot is not held up -- a wait on an unanswerable question is
      -- a hang, which is strictly worse than a cry that overlaps the next command.
      -- 8 calls over 5 programs.
      local playing = false
      if self.cryPlaying then
        local got, answer = pcall(self.cryPlaying)
        playing = got and answer == true
      elseif self.cryPending then
        self:note("waitforpokemoncries with no way to ask if a cry is playing")
      end
      if playing then
        self.soundWaits = self.soundWaits + 1
        self.pc = self.pc - 1
        break
      end
      self.cryPending = false
      self:emitSound({ kind = "stopcries", fadeOutFrames = signed(args[1] or 0) })
    elseif name == "waitforsoundeffects" then
      -- ZERO USES, and pret's shape is worth having anyway because it is the only
      -- thing that ever reads the sound-task counter: wait while a task lives, then
      -- wait while an effect plays -- but give up after ninety frames.
      if self:soundTaskCount() > 0 then
        self.soundWaits = self.soundWaits + 1
        self.soundWaitTimer = 0
        self.pc = self.pc - 1
        break
      end
      local playing = false
      if self.effectPlaying then
        local got, answer = pcall(self.effectPlaying)
        playing = got and answer == true
      end
      if playing then
        self.soundWaitTimer = (self.soundWaitTimer or 0) + 1
        if self.soundWaitTimer <= SOUND_WAIT_CAP then
          self.soundWaits = self.soundWaits + 1
          self.pc = self.pc - 1
          break
        end
      end
      self.soundWaitTimer = 0

    -- ----------------------------------------------------------------------
    -- The mon-sprite slots. See `Player.MON_SPRITE_SLOTS` for what a slot is
    -- and why six of these eight commands stopped being `NOT_NEEDED`.
    -- ----------------------------------------------------------------------
    elseif name == "initpokemonspritemanager" then
      self.monSpriteManager = true
      self.monSprites = {}
    elseif name == "addpokemonsprite" then
      -- `AddPokemonSprite role, track, slot, res`
      self:addMonSprite(signed(args[3]), signed(args[1]), signed(args[2]))
    elseif name == "removepokemonsprite" then
      if self.monSprites then self.monSprites[signed(args[1])] = nil end
    elseif name == "setpokemonspritevisible" then
      -- `ManagedSprite_SetDrawFlag(pokemonSprites[spriteID], flag)`, and it is
      -- the whole command. 22 calls over 6 programs.
      local rec = self.monSprites and self.monSprites[signed(args[1])]
      if rec then rec.visible = signed(args[2]) ~= 0 end
    elseif name == "startpokemonspritedrawtask" then
      -- ONE HIDE, AND THAT IS THE WHOLE COMMAND OUTSIDE A DOUBLE BATTLE.
      -- `StartPokemonSpriteDrawTask role, ctxSlot, spriteID` fills a draw
      -- context, clears the sprite's draw flag, and then does EVERYTHING ELSE --
      -- the visibility from the battler, the 1/255 priorities and
      -- `SysTask_Start(BattleAnimPokemonSprite_DrawTask, ...)` -- inside
      -- `if (BattleAnimSystem_IsDoubleBattle(system) == TRUE)`. So in a single
      -- battle the copy is hidden and no task ever turns it back on. 28 calls
      -- over 21 programs, and the hide is the observable half.
      local rec = self.monSprites and self.monSprites[signed(args[3])]
      if rec then rec.visible = false end
    elseif name == "freepokemonspritemanager" then
      self.monSpriteManager = false
      self.monSprites = {}

    else
      -- EVERY OTHER COMMAND IS COUNTED, NOT SKIPPED -- the particle commands,
      -- the background commands and the 2D cell-actor commands, which are the
      -- three layers this player does not have. `missing()` is the report.
      self:note(name or ("opcode " .. tostring(op)))
    end
  end

  self:stepTasks()
  self:stepEmitters()
  self:stepSprites()
  -- A PROGRAM THAT HAS RUN OFF ITS END BUT STILL HAS PARTICLES IN THE AIR IS
  -- NOT FINISHED. `end` stops the script; the emitters and sprites it created
  -- outlive it, and stopping the player here would cut the visible burst off at
  -- the exact frame the last command ran. The frames after this one are the tail
  -- at the top of this function.
  if not self.playing and self:hasLiveEffects() then
    return true
  end
  return self.playing
end

-- Anything the script started that is still running: the two are asked together
-- everywhere, and a third layer would be added here rather than at three call
-- sites that could then disagree.
function Player:hasLiveEffects()
  -- A SWITCHED BACKGROUND COUNTS. The layer is drawn from `bgLayer`, which is read
  -- under `alive()` like every other channel, so a program that reached `end` with
  -- a switch still coming down would stop being drawn a frame early and the
  -- backdrop would snap back. It cannot run away: no program in the cartridge
  -- switches without restoring, and the frame budget catches one that did.
  return self:emitterCount() > 0 or self:spriteCount() > 0
    or self.bgLayer ~= nil or self.bgSwitchState ~= BG_STATE_NONE
end

-- ---------------------------------------------------------------------------
-- The mon-sprite slots, and `SetPokemonSpritePriority` (75)
-- ---------------------------------------------------------------------------

-- WHICH SIDE A ROLE NAMES, and none of the eight is "nobody".
--
-- `BattleAnimSystem_GetBattlerWithRole` is longer than it looks and two of its
-- arms are the reason this function exists rather than a two-line table:
--
--  * A PARTNER ROLE IS NOT AN ABSENCE. It goes through
--    `BattleAnimUtil_GetAlliedBattler`, whose FIRST branch is: if the battler's
--    type is SOLO_PLAYER or SOLO_ENEMY, return THE TYPE -- 0 or 1, which are the
--    battler indices of the player and the foe. So in a single battle
--    ATTACKER_PARTNER resolves to the attacker ITSELF and DEFENDER_PARTNER to the
--    defender itself, and `AddPokemonSprite ..._PARTNER` makes a SECOND copy of
--    the same Pokemon. Reading it as "there is no partner" was the obvious guess
--    and would have dropped five of the twelve func-75 calls on the floor.
--
--  * PLAYER_2 AND ENEMY_2 FALL BACK TO THE PLAYER. Each scans for its own slot
--    type, finds none in a single battle, and ends `if (result == BATTLER_NONE)
--    result = BATTLER_PLAYER_1;` -- battler 0. Not the foe, not nothing: the
--    player. Which means the universal four-slot preamble (477 programs add
--    PLAYER_1, ENEMY_1, PLAYER_2, ENEMY_2 into slots 0..3) puts THREE copies of
--    the player's Pokemon and one of the foe's on a Sinnoh single battle. Odd,
--    and measured -- ENEMY_1's own fallback is `BATTLER_PLAYER_1` as well.
function Player:sideForRole(role)
  local R = Player.ROLE
  role = tonumber(role) or 0
  if role == R.ATTACKER or role == R.ATTACKER_PARTNER then
    return self.attackerIsPlayer and true or false
  end
  if role == R.DEFENDER or role == R.DEFENDER_PARTNER then
    -- !! `self.attackerIsPlayer and false or true` IS ALWAYS TRUE, and this line
    -- was written that way first. `x and false` is false, and `false or true` is
    -- true -- so every DEFENDER resolved to the PLAYER'S side and Dark Void's sink
    -- measured its cut-off against the wrong battler's centre (112 instead of 48),
    -- hiding the copy 24 pixels into an 84-pixel fall. FOUND BY TRACING THE
    -- FRAMES, not by reading: the expression is the shape of the idiom used three
    -- lines up, where it is correct because the constant there is `true`.
    return not self.attackerIsPlayer
  end
  if role == R.ENEMY_1 then return false end
  -- PLAYER_1, and PLAYER_2/ENEMY_2 through their shared fallback.
  return true
end

-- `AddPokemonSprite role, track, slot, res` -> a slot record.
--
-- `res` is not kept: it names a placeholder resource in a manager this port does
-- not have, and the picture a slot shows is its side's own. `track` IS kept and
-- is ALWAYS ZERO in the corpus -- all 2,019 calls pass FALSE -- so the tracking
-- task it would start is not a gap, it is unreachable.
function Player:addMonSprite(slot, role, track)
  self.monSprites = self.monSprites or {}
  local rec = {
    role = role, side = self:sideForRole(role),
    track = (tonumber(track) or 0) ~= 0,
    dx = 0, dy = 0, visible = true,
  }
  self.monSprites[slot] = rec
  return rec
end

-- THE LIVE VISIBLE COPY OF ONE SIDE, LOWEST SLOT FIRST.
--
-- Lowest rather than "any" because `pairs` has no order, and a draw that picked a
-- different slot on different frames would be a flicker nobody could reproduce.
function Player:monSpriteFor(isPlayer)
  local side = isPlayer and true or false
  local best, bestSlot = nil, nil
  for slot, rec in pairs(self.monSprites or {}) do
    if rec.side == side and rec.visible
       and (bestSlot == nil or slot < bestSlot) then
      best, bestSlot = rec, slot
    end
  end
  return best, bestSlot
end

-- IS ANYTHING WRITING THE MANAGER'S SPRITES TO OAM THIS FRAME.
--
-- THE QUESTION THAT SETTLES THE WHOLE LAYER, and it is one line of pret:
-- `SpriteSystem_DrawSprites(spriteMan)` is `SpriteList_Update(spriteMan->sprites)`
-- -- the call that puts a sprite list into OAM -- and NOTHING calls it on the
-- Pokemon sprite manager unless a function is running that does. A copy is
-- therefore not on screen because it exists; it is on screen while a RENDERER
-- lives. Without this the 477 programs that add four copies in their preamble
-- would each have a permanently visible copy of the player defeating every
-- `HideBattler` for the rest of the move.
--
-- THE TWO RENDERERS THIS PORT IMPLEMENTS: `RenderPokemonSprites` (78 -- 477
-- calls over 425 programs, three frames when its operand is 0) and
-- `SetPokemonSpritePriority` (75, which renders every frame of its own life).
-- Other functions render the manager too and every one of them is in this port's
-- unimplemented set, so this answer is exactly as complete as the function
-- coverage and no more. That is the bound, stated rather than claimed away.
function Player:monSpritesRendered()
  for _, t in ipairs(self.tasks or {}) do
    if t.renders and not t.done then return true end
  end
  return false
end

-- The hardware window, while one is up. nil is the ordinary state.
function Player:monWindow()
  if not self:alive() then return nil end
  return self.monWindowRect
end

-- One draw from the cartridge's LCRNG. See the seed in `start`.
function Player:lcrng()
  local state, value = lcrngNext(self.rngState or 0)
  self.rngState = state
  return value
end

-- ONE FRAME OF THE SINK. The table is `DARK_VOID_JITTER` above.
function Player:darkVoidStep(t)
  local sprite = self.monSprites and self.monSprites[t.slot]
  local state = t.state or 0

  if state == 0 then
    self.monWindowRect = Player.MON_WINDOW[t.windowType] or Player.MON_WINDOW[0]
    -- `DARK_VOID_SINK_FULLY_MIN_FRAME + (LCRNG_Next() % DARK_VOID_SINK_RNG_FRAME)`
    t.sinkFrom = DARK_VOID_SINK_MIN + (self:lcrng() % DARK_VOID_SINK_RNG)
    return
  end

  local row = DARK_VOID_JITTER[state]
  if row then
    if row.coin then
      -- THE DRAW HAPPENS WHETHER OR NOT THE COUNT MATCHES. pret's shape is
      -- `if (LCRNG_Next() % 2) { if (stepCount == n) { ... } }`, so the outer test
      -- consumes a number every one of those six frames. Lua's `and` would
      -- short-circuit the other way round; this order is the cartridge's.
      local heads = (self:lcrng() % 2) == 1
      if heads and (t.stepCount or 0) == row.need then
        t.stepCount = (t.stepCount or 0) + 1
        if sprite then sprite.dy = (sprite.dy or 0) + row.step end
      end
    elseif (t.stepCount or 0) ~= row.unless then
      t.stepCount = (t.stepCount or 0) + 1
      if sprite then sprite.dy = (sprite.dy or 0) + row.step end
    end
    return
  end

  -- THE `default` ARM, which is every other state -- 1..4, 8, 9, 13, 14, 18..21
  -- included -- and does nothing at all until the rolled frame has passed.
  if state <= (t.sinkFrom or DARK_VOID_SINK_MIN) then return end
  if (t.stepCount or 0) < DARK_VOID_STEP_CAP then
    if sprite then
      sprite.dy = (sprite.dy or 0) + DARK_VOID_STEP_Y
      -- `ManagedSprite_GetPositionXY` then `if (y > DARK_VOID_MAX_Y)`: an
      -- ABSOLUTE y, which is why `BATTLER_CENTRE` is in this file.
      if (t.baseY or 0) + sprite.dy > DARK_VOID_MAX_Y then
        sprite.visible = false
      end
    end
    t.stepCount = (t.stepCount or 0) + 1
  elseif sprite then
    sprite.visible = false
  end
end

-- `SetPokemonSpritePriority` (75) -- 12 calls over 6 programs, and ONE of them
-- does anything on screen in a single battle.
--
-- !! THE PRIORITY HALF IS A MEASURED NO-OP HERE, AND IT IS NOT AN OPINION.
-- Three facts settle it, each read out of pret by name:
--   (1) every one of the twelve ROM calls passes bg = 3 (BATTLE_ANIM_BG_POKEMON)
--       and spritePrio = 0. Measured off we.arc, not off pret's res/.
--   (2) bg 3 resolves through `BattleAnimSystem_GetPokemonSpritePriority` to 1
--       outside a contest, and the mon sprite template's own `bgPriority` IS 1 --
--       so `SetExplicitPriority` writes the value that was already there.
--   (3) `sPriorityByBattlerType[] = { 0, 0, 20, 10, 10, 20 }` gives both
--       SOLO_PLAYER and SOLO_ENEMY a sprite priority of 0, which is exactly the 0
--       every call passes -- and the big switch that would overwrite it with 10
--       or 20 HAS NO CASE FOR EITHER SOLO TYPE. It is written for the four
--       double-battle types only, so in a single battle it falls through and
--       changes nothing.
-- pret's own macro comment calls the function buggy ("the priority being set to
-- default values if you pass anything other than BATTLE_ANIM_DEFAULT_PRIORITY"),
-- and that is right in a double battle. In a single battle the bug cannot fire.
-- The numbers are recorded on `self.monPriority` so a check can assert the
-- no-op rather than this comment asserting it.
--
-- WHAT IS NOT A NO-OP: the task's LIFETIME, which `waitforanimtasks` waits for;
-- the copy being hidden when the task ends; the partner early return; and, on the
-- two Dark Void calls, the window and the sink.
function Player:startMonSpritePriority(args, vars)
  local slot   = arg(args, vars.spriteId) or 0
  local frames = arg(args, vars.maxFrames) or 0
  local bg     = arg(args, vars.bg) or 0
  local asked  = arg(args, vars.spritePriority) or 0
  local role   = arg(args, vars.battler) or 0
  local mode   = arg(args, vars.mode) or 0
  local window = arg(args, vars.windowType) or 0
  local side   = self:sideForRole(role)
  local sprite = self.monSprites and self.monSprites[slot]

  -- The record, in the order the cartridge writes them: explicit priority from
  -- the bg, then the asked-for priority, then the battler-type override.
  local typeIndex = side and Player.BATTLER_TYPE_SOLO_PLAYER
                         or Player.BATTLER_TYPE_SOLO_ENEMY
  self.monPriority = self.monPriority or {}
  self.monPriority[#self.monPriority + 1] = {
    slot = slot, role = role, side = side, bg = bg, asked = asked,
    mode = mode, windowType = window, frames = frames,
    explicit = (bg ~= Player.BATTLE_ANIM_BG_NONE)
               and Player.MON_SPRITE_BG_PRIORITY or nil,
    explicitWas = Player.MON_SPRITE_BG_PRIORITY,
    priority = (asked ~= Player.BATTLE_ANIM_DEFAULT_PRIORITY) and asked or nil,
    priorityWas = Player.SPRITE_PRIORITY_BY_TYPE[typeIndex],
    -- the 10/20 override, and nil BECAUSE the switch has no solo case
    override = nil,
  }

  -- THE EARLY RETURN, AND IT IS FIVE OF THE TWELVE CALLS.
  -- `if (BattleAnimSystem_IsDoubleBattle(system) != TRUE)` and the role is a
  -- partner: hide the sprite, free the context, START NO TASK. This port is
  -- always a single battle, so the branch is taken every time it is reached --
  -- which is why the partner copy Dark Void adds never appears and why nothing
  -- waits eighty frames for it.
  if Player.ROLE_PARTNER[role] then
    if sprite then sprite.visible = false end
    return nil
  end

  local t = self:addTask({
    kind = "monprio", pending = true,
    frames = frames,
    slot = slot, side = side, role = role,
    darkVoid = (mode == Player.MON_SPRITE_PRIORITY_MODE_DARK_VOID),
    windowType = window,
    state = 0, stepCount = 0,
    baseY = (Player.BATTLER_CENTRE[side] or {}).y or 0,
    -- ...and it renders the manager every frame of its life, which is what puts
    -- the copy on screen at all. See `monSpritesRendered`.
    renders = true,
  })
  -- `addTask` clamps `frames` against FRAME_BUDGET; the state limit follows the
  -- clamped value so a clamp cannot leave a task running past what it clamped to.
  t.maxFrames = t.frames
  return t
end

-- ---------------------------------------------------------------------------
-- The seam Emerald's animator already defined
-- ---------------------------------------------------------------------------

-- IS ANYTHING STILL RUNNING. Not `playing`: the script ending does not end the
-- animation, and the four channels below are read every frame the screen draws.
-- Reading `playing` meant a battler snapped back for the whole tail -- invisible
-- until a sprite callback started holding one stretched.
function Player:alive()
  return self.playing == true or self:hasLiveEffects()
end

function Player:monOffset(isPlayer)
  if not self:alive() then return 0, 0 end
  local side = isPlayer and true or false
  local s = self.state[side]
  local dx, dy = s.dx or 0, s.dy or 0
  -- ...AND THE COPY'S OWN DISPLACEMENT, BUT ONLY UNDER A HIDDEN BATTLER.
  --
  -- While the battler is visible the cartridge draws BOTH -- the battler at rest
  -- and the copy where the animation put it -- and this port draws one Pokemon a
  -- side, so adding the copy's offset then would MOVE a Pokemon the cartridge
  -- leaves standing. Adding it only when the battler is hidden costs nothing
  -- measurable: the one program that displaces a copy at all is Dark Void, whose
  -- first sink step is at task state 5 and whose `HideBattler` is one instruction
  -- after the call, so the copy has not moved on any frame this clause skips.
  if s.hidden then
    local copy = self:monSpriteFor(side)
    if copy and self:monSpritesRendered() then
      dx, dy = dx + (copy.dx or 0), dy + (copy.dy or 0)
    end
  end
  return dx, dy
end

function Player:monAffine(isPlayer)
  if not self:alive() then return 1, 1 end
  local s = self.state[isPlayer and true or false]
  return s.sx or 1, s.sy or 1
end

function Player:monTint(isPlayer)
  if not self:alive() then return nil end
  local s = self.state[isPlayer and true or false]
  local t = s.tint
  if not t then return nil end
  return t[1], t[2], t[3], t[4]
end

-- IS THIS SIDE OFF THE SCREEN.
--
-- !! THIS METHOD HAD NO CALLER ANYWHERE IN THE PORT until the draw gained one, so
-- `Func_HideBattler` -- 50 calls over 16 programs, 24 hides and 26 shows -- drew
-- nothing at all. Whirlwind and Roar blow the foe away and never bring it back
-- (both hide with no matching show, which is why `clearTransforms` must reset the
-- flag); Dig, Fly and Dark Void put one away and fetch it. All of them left the
-- Pokemon standing there.
function Player:monHidden(isPlayer)
  if not self:alive() then return false end
  local side = isPlayer and true or false
  if not self.state[side].hidden then return false end
  -- ...BUT A HIDDEN BATTLER WITH A COPY ON SCREEN IS STILL ON SCREEN. Dark Void
  -- hides the real defender one frame after starting the sink on the copy;
  -- answering "hidden" there would blank the very thing the move is about.
  if self:monSpritesRendered() and self:monSpriteFor(side) then return false end
  return true
end

-- ---------------------------------------------------------------------------
-- The particle layer
--
-- `loadparticlesystem <slot> <member>` puts a whole SPA file's resource list in
-- one of sixteen slots; `createemitter <slot> <resource> <callback>` runs ONE
-- resource out of it at a place the callback picks; `waitforallemitters` waits
-- for every one of them, whichever slot it came from -- pret's macro comment is
-- explicit about that last part, and it is what gives nearly every move in the
-- game its length, since the program itself never states one.
-- ---------------------------------------------------------------------------

-- The effect key the `gen4_particles` stage writes. Move programs only ever
-- name the move archive.
--
-- THE OTHER HALF OF THAT STAGE IS NOT THE CATCHING ANIMATION, and this comment
-- used to say it was. Corrected against pokeplatinum, because the wrong version
-- of it sent a whole pass looking in the wrong archive:
--
--   * `ball_particle.narc`'s 117 effects belong to the BALL CAPSULE SEALS.
--     `NARC_INDEX_WAZAEFFECT__EFFECTDATA__BALL_PARTICLE` is opened in exactly
--     one place in the cartridge -- `ov12_02235E94.c`, by
--     `BallCapsuleSealEffect` -- and nothing else reads it.
--   * THE THROW IS NOT A PARTICLE EFFECT AT ALL. It is a 2D cell animation:
--     `sBallThrowGraphics[20][4]` gives each ball its
--     { NCGR, NCLR, NCER, NANR } out of `pl_batt_obj.narc`, which this port
--     already opens (`Gen4Battle.ARCHIVE_OBJ`), and the row is `ballId - 1`
--     with an out-of-range id falling back to row 3, the plain Poke Ball.
--
-- So a catching animation built here would be built on the seals. It belongs
-- with the cell actors and `pl_batt_obj`, not with this file.
function Player:effectKey(member)
  return "move_" .. tostring(member)
end

function Player:loadParticles(slot, member)
  slot = tonumber(slot) or 0
  local entry = self.effects and self.effects[self:effectKey(member)]
  if not entry then
    -- NAMED, not silent. A move whose effect is missing from the cache draws
    -- nothing, and this is the only place that can say which member it wanted.
    self:note("particles:" .. tostring(member))
    self.slots[slot] = nil
    return false
  end
  self.slots[slot] = { member = member, emitters = entry.emitters,
                       art = entry.textures }
  if not entry.emitters then
    -- The art loaded and the motion did not: that is an effect whose emitter
    -- blocks did not tile their own area, which the import stage refuses rather
    -- than guessing at. Counted separately from a missing member.
    self:note("emitterless:" .. tostring(member))
  end
  return true
end

-- createemitter(slot, resource, callback). `resource` is 0-based into the
-- slot's own list; `callback` indexes the 23-entry table above.
function Player:createEmitter(slot, resource, callback, index)
  local set = self.slots[tonumber(slot) or 0]
  if not (set and set.emitters) then
    self:note("createemitter without a loaded system")
    return false
  end
  local sys = Gen4ParticleSystem.resource(set.emitters, resource)
  if not sys then
    self:note("resource " .. tostring(resource) .. " of " .. tostring(set.member))
    return false
  end
  local where = EMITTER_AT[tonumber(callback) or 0] or EMITTER_AT[0]
  self.emitterSeq = self.emitterSeq + 1
  -- A SEED THAT IS A FUNCTION OF THE PROGRAM, not of the clock: `duration()`
  -- runs every program twice and compares nothing if the two passes diverge,
  -- and a battle that replays a move has to look the same both times.
  sys:start(((self.moveId or 0) * 8191) + (self.emitterSeq * 131) + 7)
  local record = {
    system = sys, art = set.art, member = set.member,
    origin = where.origin, axis = where.axis and true or false,
  }
  self.emitters[#self.emitters + 1] = record
  -- ...AND FILED UNDER ITS SLOT, because something addresses one now.
  --
  -- `createemitter`, `createemitterformove` and `createemitterforfriendlyfire`
  -- all write `system->context->emitters[0]` -- pret, three times over -- and only
  -- `createemitterex` names a slot. The emitter-motion functions then ask for a
  -- slot by number, which is why this list exists at all and why the index on
  -- `createemitterex` stopped being "read and not used".
  self.emitterAt[tonumber(index) or 0] = record
  return true
end

-- WHICH OF THE SIX RESOURCES `createemitterformove` MEANT.
--
-- The operands are (system, plParallel, plDiagonal2, plDiagonal1, emParallel,
-- emDiagonal2, emDiagonal1, callback): three orientations for the player
-- attacking and three for the enemy. A Sinnoh battle drawn in two dimensions
-- has ONE orientation, so this takes the parallel resource for the attacking
-- side -- the head-on one -- and says so rather than averaging the three.
function Player:resourceForMove(args)
  local attacker = self.attackerIsPlayer
  self:note("createemitterformove picked the parallel resource")
  return attacker and args[2] or args[5], args[8]
end

-- ---------------------------------------------------------------------------
-- AN EMITTER THAT TRAVELS -- `MoveEmitterA2BLinear` (65) and
-- `MoveEmitterA2BParabolic` (66)
--
-- 119 calls over 37 of the 501 programs, and until now every one of them left its
-- emitter sitting on the spot: a beam that should cross the field, a projectile
-- that should arc. Both functions are the same context with a different path, and
-- both paths are already in `Gen4AnimMath`.
--
-- THE ENDPOINTS ARE THIS PORT'S BATTLERS, NOT THE CARTRIDGE'S 3D TABLE, and that
-- is a decision rather than an omission. pret reads
-- `BattleAnimUtil_GetBattlerWorldPos_Normal` -- a table of 3D world positions per
-- battler type, per position type, per camera projection -- and divides by
-- `BATTLE_PARTICLE_PIXEL_FACTOR` (172) to get screen units. Those numbers describe
-- the 3D scene the DS renders: the solo player comes out near x -55 in a frame
-- centred on the screen, where this port draws that Pokemon at x 64. Transcribing
-- them would put every path somewhere the battlers are not. So the path runs
-- between the positions THIS screen uses, which is the same argument
-- `createemitterformove` already makes about picking one orientation out of three.
--
-- AND THE ARC BOWS THE OTHER WAY HERE, for a reason worth stating. pret passes
-- `radius * -FX32_ONE` to the parabola, and its frame has +Y UP (the world table
-- gives the player -1.33 and the enemy +1.07 while the player stands LOWER on
-- screen). This port's offsets are +Y DOWN, so the same visible arc needs the
-- radius UNNEGATED. A call that passes a negative radius -- and some do -- still
-- flips it, which is the point of keeping the operand's sign.
--
-- WHAT THE OPERANDS DO, all nine:
--   emitterId   which slot's emitter to move (see `emitterAt`)
--   offsetX/Y   added to the END point, times the attacker's direction
--   startDelay  frames to wait before the path starts stepping
--   frames      how long the path takes
--   radius      the parabola's bow; the linear function ignores it, and 35 of its
--               46 calls pass 64 anyway -- a vestige, stated so the next reader
--               does not go looking for the curve it implies
--   mode        0 attacker to defender, 1 defender to attacker
--   params      TWO packed halves: skipFrames in the high 16 bits, maxFrames in
--               the low ones
--   curve       a sine wobble added to Y, one full turn over `frames`
--
-- !! AND `maxFrames` PARKS THE EMITTER RATHER THAN SHORTENING ITS TRIP. When
-- `params` names a non-zero maxFrames, pret sets `frame = maxFrames + 1` at init
-- and NOTHING EVER INCREMENTS `frame` -- so the task's own guard
-- (`maxFrames < frame`) is true from the first step onward and the position is
-- never updated again. The emitter is placed once, after `skipFrames` steps of the
-- path, and stays there. It reads like an idiom for "put this emitter part of the
-- way along the path", and twelve of the 119 calls use it.
function Player:startEmitterPath(parabolic, v)
  local e = self.emitterAt[tonumber(v.emitterId) or 0]
  if not e then
    self:note("moveemitter with no emitter in slot " .. tostring(v.emitterId))
    return false
  end
  local frames = tonumber(v.frames) or 0
  if frames <= 0 then
    self:note("moveemitter with no frames")
    return false
  end
  local dir = Gen4AnimMath.directionX(self.attackerIsPlayer)
  local pos = self:battlerPositions()
  local from = (v.mode == 1) and pos.defender or pos.attacker
  local to = (v.mode == 1) and pos.attacker or pos.defender
  local endX = to.x + (tonumber(v.offsetX) or 0) * dir
  local endY = to.y + (tonumber(v.offsetY) or 0) * dir
  -- WHERE THE OFFSETS ARE MEASURED FROM. The emitter's own origin is what the
  -- screen adds to every particle, so the path has to be expressed as an offset
  -- from it -- and then nothing in the draw path changes at all.
  local baseX, baseY = self:originPixels(e.origin)
  local path
  if parabolic then
    path = Gen4AnimMath.parabolic(from.x, endX, from.y, endY, frames,
                                  (tonumber(v.radius) or 0) * Gen4AnimMath.FX32_ONE)
  else
    path = Gen4AnimMath.posLerp(from.x, endX, from.y, endY, frames)
  end
  local params = tonumber(v.params) or 0
  local skipFrames = floor(params / 65536) % 65536
  local maxFrames = params % 65536
  local task = {
    kind = "empath", emitter = e, path = path, parabolic = parabolic,
    baseX = baseX, baseY = baseY,
    startDelay = tonumber(v.startDelay) or 0, timer = 0,
    skipFrames = skipFrames, maxFrames = maxFrames,
    parked = maxFrames ~= 0,
    curve = tonumber(v.curve) or 0, angle = 0, frames = frames,
    live = true,
  }
  -- THE SKIPPED STEPS HAPPEN AT ONCE, before the emitter is placed: pret loops
  -- `skipFrames` updates in the script function itself.
  for _ = 1, skipFrames do self:stepEmitterPathOnce(task) end
  self:addTask(task)
  self:applyEmitterPath(task)
  return true
end

-- ---------------------------------------------------------------------------
-- The emitter that ORBITS, and the one that falls from the top of the screen
-- ---------------------------------------------------------------------------

-- startEmitterRevolution(v) -- `RevolveEmitter`, 105 calls over TWO programs
--
-- The angles are DEGREES here, not index units, and the radii are PIXELS -- which
-- is why this reads its operands through `degToIdx` and `* FX32_ONE` rather than
-- taking them raw.
--
-- SEVENTY-TWO OF THE 105 CALLS DO NOT ROTATE AT ALL. They pass the same value for
-- the start and the end angle (0, 45, 90, 135, 180, 225, 270 or -90 on both), so
-- the step size is zero and the emitter sits at ONE POINT on the oval for its
-- seven frames. The command is being used to PLACE a ring of emitters round the
-- attacker, not to spin one. A port that special-cased "no rotation" as a mistake
-- would break the commoner of the two uses.
--
-- THE Y RADIUS IS NEGATED ON THE WAY IN, and this is the same frame question the
-- parabolic arc answered the other way round. pret's world frame is +Y UP and it
-- passes `ry * FX32_ONE` unnegated, so a positive radius puts the emitter ABOVE
-- the battler; this port's offsets are +Y DOWN, so the same visible ring needs the
-- sign flipped. (The arc in `startEmitterPath` is the mirror case: pret negates
-- there, so this port does not.)
function Player:startEmitterRevolution(v)
  local e = self.emitterAt[tonumber(v.emitterId) or 0]
  if not e then
    self:note("revolveemitter with no emitter in slot " .. tostring(v.emitterId))
    return false
  end
  local frames = tonumber(v.frames) or 0
  if frames <= 0 then
    self:note("revolveemitter with no frames")
    return false
  end
  local pos = self:battlerPositions()
  -- EMITTER_REVOLUTION_MODE_ATTACKER is 0 and _DEFENDER is 1.
  local at = ((tonumber(v.mode) or 0) == 0) and pos.attacker or pos.defender
  local rev = Gen4AnimMath.revolution(
    Gen4AnimMath.degToIdx(tonumber(v.startX) or 0),
    Gen4AnimMath.degToIdx(tonumber(v.endX) or 0),
    Gen4AnimMath.degToIdx(tonumber(v.startY) or 0),
    Gen4AnimMath.degToIdx(tonumber(v.endY) or 0),
    (tonumber(v.radiusX) or 0) * Gen4AnimMath.FX32_ONE,
    (tonumber(v.radiusY) or 0) * Gen4AnimMath.FX32_ONE,
    frames)
  -- ONE STEP BEFORE THE FIRST PLACEMENT, in the script function itself -- the same
  -- shape as the travelling emitters' `skipFrames` loop. Without it the emitter
  -- spends its first frame at the battler's own centre rather than on the ring.
  Gen4AnimMath.revolutionUpdate(rev)
  local baseX, baseY = self:originPixels(e.origin)
  local task = {
    kind = "emrev", pending = true, emitter = e, rev = rev,
    cx = at.x, cy = at.y, baseX = baseX, baseY = baseY,
  }
  self:addTask(task)
  self:applyEmitterRev(task)
  return true
end

-- Where the orbit has reached, as an offset from the emitter's own origin.
function Player:applyEmitterRev(t)
  t.emitter.system.emitterX = (t.cx + t.rev.x) - t.baseX
  t.emitter.system.emitterY = (t.cy - t.rev.y) - t.baseY
end

-- startEmitterViewportPath(v) -- `MoveEmitterViewportTop`, ONE call in the
-- cartridge (program 19, emitter 0, the defender, ten frames after four of delay).
--
-- IT IS THE LINEAR PATH WITH ONE ENDPOINT MOVED, and it shares pret's own task
-- with the A2B functions -- so everything the travelling-emitter pass established
-- about `startDelay`, `skipFrames` and `maxFrames` applies unchanged. What differs
-- is only where the two ends are: BOTH are the same battler (pret assigns
-- `startBattler` and `endBattler` the same one), and then `type` replaces one end's
-- Y with the top of the viewport and copies the other end's X.
--
-- THE TOP OF THE VIEWPORT IS THE TOP OF THE SCREEN, and that is a derivation
-- rather than a convenience. `BATTLE_PARTICLE_VIEWPORT_TOP` is 16512 world units
-- and `WORLD_TO_SCREEN` divides by 172, giving 96 -- exactly half of the DS's 192
-- rows. In a frame centred on the screen, half the height above centre IS row
-- zero, which is what this port draws at.
function Player:startEmitterViewportPath(v)
  local e = self.emitterAt[tonumber(v.emitterId) or 0]
  if not e then
    self:note("viewportemitter with no emitter in slot " .. tostring(v.emitterId))
    return false
  end
  local frames = tonumber(v.frames) or 0
  if frames <= 0 then
    self:note("viewportemitter with no frames")
    return false
  end
  local pos = self:battlerPositions()
  local at = ((tonumber(v.mode) or 0) == 0) and pos.attacker or pos.defender
  local sx, sy, ex, ey = at.x, at.y, at.x, at.y
  if (tonumber(v.kind) or 0) == 0 then
    sy = Player.VIEWPORT_TOP_Y        -- EMITTER_ANIMATION_FROM_TOP
  else
    ey = Player.VIEWPORT_TOP_Y
  end
  local params = tonumber(v.params) or 0
  local skipFrames = floor(params / 65536) % 65536
  local maxFrames = params % 65536
  local baseX, baseY = self:originPixels(e.origin)
  local task = {
    kind = "empath", emitter = e, parabolic = false,
    path = Gen4AnimMath.posLerp(sx, ex, sy, ey, frames),
    baseX = baseX, baseY = baseY,
    startDelay = tonumber(v.startDelay) or 0, timer = 0,
    skipFrames = skipFrames, maxFrames = maxFrames,
    -- pret turns a maxFrames of 0 into EMITTER_ANIMATION_DEFAULT_FRAMES (0xFF) and
    -- then parks only when it is NOT 0xFF, which comes to the same test the A2B
    -- functions use written the other way round.
    parked = maxFrames ~= 0,
    curve = 0, angle = 0, frames = frames,
    live = true,
  }
  for _ = 1, skipFrames do self:stepEmitterPathOnce(task) end
  self:addTask(task)
  self:applyEmitterPath(task)
  return true
end

-- One step of the path, whichever kind it is.
function Player:stepEmitterPathOnce(t)
  if t.parabolic then
    local live = Gen4AnimMath.parabolicUpdate(t.path)
    t.live = live
    return live
  end
  local live = Gen4AnimMath.posLerpUpdate(t.path)
  t.live = live
  return live
end

-- Where the path has reached, written onto the emitter as an offset from its own
-- origin -- in pixels, +Y down, which is the frame the screen adds it in.
function Player:applyEmitterPath(t)
  local point = t.parabolic and t.path.linear or t.path
  local x = point.x - t.baseX
  local y = point.y - t.baseY
  if t.curve ~= 0 then
    -- `CalcSineDegrees_Wraparound(angle)` with `angle += 360 / frames` a frame:
    -- one full turn over the path, added to Y.
    y = y + sin(t.angle * pi / 180) * t.curve
  end
  t.emitter.system.emitterX = x
  t.emitter.system.emitterY = y
end

-- WHICH PIXEL AN ORIGIN NAME MEANS. The same six names `Gen4Battle.particleOrigin`
-- resolves, resolved here too because a path between two battlers has to be
-- expressed relative to one of them. THE TWO MUST AGREE and the check asserts it
-- rather than trusting this comment -- a drift between them puts every travelling
-- emitter somewhere its own particles are not.
function Player:originPixels(name)
  local pos = self:battlerPositions()
  if name == "player" then return pos.player.x, pos.player.y end
  if name == "enemy" then return pos.enemy.x, pos.enemy.y end
  if name == "attacker" then return pos.attacker.x, pos.attacker.y end
  if name == "defender" then return pos.defender.x, pos.defender.y end
  return (pos.player.x + pos.enemy.x) / 2, (pos.player.y + pos.enemy.y) / 2
end

function Player:stepEmitters()
  local alive = 0
  for _, e in ipairs(self.emitters) do
    if not e.done then
      if e.system:update() then alive = alive + 1 else e.done = true end
    end
  end
  return alive
end

function Player:emitterCount()
  local n = 0
  for _, e in ipairs(self.emitters) do if not e.done then n = n + 1 end end
  return n
end

-- particles() -> a flat draw list, farthest first within each emitter.
--
-- Positions are OFFSETS from the emitter's origin in pixels; the caller knows
-- where the attacker and the defender are on its own screen and adds them. The
-- origin name is passed through rather than resolved here for the same reason
-- `monOffset` returns a delta: this file knows the cartridge, not the layout.
function Player:particles()
  local out = {}
  for _, e in ipairs(self.emitters) do
    if not e.done then
      e.system:draw(0, 0,
        function(texture, x, y, scaleX, scaleY, alpha, rotation, colour)
          out[#out + 1] = {
            origin = e.origin, axis = e.axis,
            art = e.art and e.art[(tonumber(texture) or 0) + 1] or nil,
            texture = texture, member = e.member,
            -- TWO SCALES, because a particle is not square: `aspectRatio` runs
            -- 0.03 to 8.0 across the cartridge and a third of its emitters set
            -- it. `scale` stays as the Y axis so nothing that read it breaks.
            x = x, y = y, scaleX = scaleX, scaleY = scaleY, scale = scaleY,
            alpha = alpha,
            -- CARRIED, NOT DROPPED. The rotation and the colour curve are the
            -- two things the simulation computes that only the screen can use,
            -- and a draw record that left them out would make the animation
            -- blocks look unimplemented from the one place that can see them.
            rotation = rotation, colour = colour,
          }
        end)
    end
  end
  return out
end

-- ---------------------------------------------------------------------------
-- The 2D cell-actor layer
--
-- `initspritemanager` opens a manager, the four `load*resobj` commands put NARC
-- members in it, and `addsprite` / `addspritewithfunc` make a sprite out of one
-- of each. pret's macro is explicit that the resource operands are NARC MEMBER
-- INDICES and not slots -- "Index of the character resource to use. (Same as for
-- LoadCharResObj)" -- which is the one thing here that reads like a slot and is
-- not. Measured over the cartridge, every one of the 38 sprites names a resource
-- its own program loaded first, and `charRes == cellRes == animRes` on all 38.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- THE PER-MOVE SPRITE CALLBACKS' MOTION
--
-- `addspritewithfunc` names one of 33 callbacks; 26 of them occur in the
-- cartridge's 501 programs, 38 uses in all. Each is a bespoke routine -- a state
-- machine in the callback plus a per-frame task, 12 to 89 lines of C apiece --
-- and they share no motion vocabulary, so there is nothing to generalise and
-- each one is its own reading of pret.
--
-- WHAT THEY DO SHARE IS THE ARITHMETIC, and that lives in `Gen4AnimMath`: five
-- fixed-point contexts (PosLerp, ScaleLerp, ValueLerp, Revolution, AlphaFade)
-- and the parabola built from two of them. Nine of the 26 build on PosLerp
-- alone. Porting those once, exactly -- including the three different roundings
-- the cartridge uses -- is what makes a callback a reading rather than a guess.
--
-- APPLIED HERE, with every use in the cartridge:
--
--   22 MetalClaw        3 moves (232 Metal Claw, 306, 337)
--   10 Swagger          3 moves (207 Swagger, 259, 269)
--   17 IcicleSpear      3 uses, all in move 333 Icicle Spear
--    7 ScaryFace        2 moves (137 Scary Face, 184)
--   18 FakeOut          1 move  (252 Fake Out)
--    8 Foresight        1 move  (193 Foresight)
--   25 OffsetAndAnimate 1 move  (265)
--
-- TWO OF THEM REACH A BATTLER, not just their own sprite: ScaryFace stretches
-- the attacker's Pokemon vertically and Foresight flashes the defender white.
-- They go through `ctx.player.state`, which is the same table
-- `scalebattlersprite` and `fadebattlersprite` write, so a callback and a script
-- command cannot hold two disagreeing ideas of where a Pokemon is or what colour.
--
-- NOT APPLIED, and named rather than shrugged at: StringShot, Kinesis, Trick,
-- Metronome, Constrict, Bonemerang, LockOn, MeanLook, Torment, BatonPass, Grudge,
-- Taunt, HelpingHand, Assist, Ingrain, FrenzyPlant, FollowMe, and Fissure's
-- motion (its PLACEMENT is ported, above). Their sprites appear, animate and sit
-- at the defender's position, which is where `addspritewithfunc` puts them before
-- any callback runs; the motion on top is what is missing, and `missing()`
-- reports each one by name every run.
--
-- THE SHAPE OF AN ENTRY. `count` is how many sprites the callback makes out of
-- the one template -- MetalClaw makes four claws from one resource, which no
-- amount of reading the script would reveal. `start` sets them up once; `step`
-- runs one frame and returns false when the callback is finished, which is what
-- deletes its sprites. A callback with no entry keeps the plain behaviour: one
-- sprite whose lifetime is its own animation.
--
-- OFFSETS ARE IN DS SCREEN SPACE, +Y DOWN, because that is what
-- `ManagedSprite_OffsetPositionXY` adds to and what every constant in pret is
-- written in. An earlier version of this file measured Y upwards and drew move
-- 265's sprite twenty-four pixels ABOVE the battler where the cartridge puts it
-- twenty-four below.
--
-- WHO TICKS THE ANIMATION. Two mechanisms, and which one a callback uses is
-- readable: a callback that calls `ManagedSprite_SetAnimateFlag(TRUE)` leaves the
-- sprite system to advance the frame every frame (FakeOut), and one that calls
-- `ManagedSprite_TickFrame` in its task does it itself and can therefore stop
-- (MetalClaw freezes the right pair for ten frames). A sprite whose callback does
-- neither never animates at all, which is Swagger's vein.
-- ---------------------------------------------------------------------------

local SPRITE_MOTION = {}

-- `BattleAnimUtil_TickSpriteIfVisible`: the animation advances only while the
-- sprite is drawn.
local function tickIfVisible(s)
  if s.visible then s.animTick = s.animTick + 1 end
end

local function tick(s)
  s.animTick = s.animTick + 1
end

-- `ManagedSprite_IsAnimated` -- false once the sequence has run out, which is
-- what every callback that waits on an animation waits for.
local function animDone(s)
  return s.animTick >= s.length
end

-- ---------------------------------------------------------------------------
-- 22 MetalClaw -- FOUR claws out of one sprite resource
--
-- The script adds one sprite; the callback clones three more from the same
-- template, flips the left pair horizontally, and places them at the four
-- corners of a 64x32 box around the defender. Nothing in the program says four,
-- so a port that reads only the script draws a quarter of the move.
--
-- THE RIGHT PAIR IS FROZEN FOR TEN FRAMES, not hidden. pret's own comment says
-- "delay in frames before the second claw appears", and what the code does is
-- withhold `TickFrame` -- so the sprite is on screen, showing animation frame 0.
-- That reads as "appears later" only because frame 0 of its bank is a blank cell,
-- which is not a guess: member 17's cell 0 has no OAM entries at all and its
-- animation's first frame names it. The check asserts exactly that, because if
-- the blank were ever lost the delay would become a frozen claw in plain sight.
--
-- THE LIFETIME IS 40 FRAMES AND IS NOT THE ANIMATION'S. Each claw carries a
-- counter; at 40 it stops being drawn, and when all four have stopped the task
-- deletes them. The counters start together and step together, so all four go at
-- once and the 40th frame is the one nothing is drawn on.
-- ---------------------------------------------------------------------------

local METAL_CLAW_COUNT = 4
local METAL_CLAW_OFFSET_X = 32
local METAL_CLAW_OFFSET_Y = 32
local METAL_CLAW_RIGHT_DELAY = 10
local METAL_CLAW_VISIBLE_FRAMES = 40

SPRITE_MOTION[22] = {
  name = "MetalClaw",
  count = METAL_CLAW_COUNT,
  start = function(ctx)
    local s = ctx.sprites
    -- pret's indices: 0 and 1 are the left pair, 2 and 3 the right.
    s[1].flipX, s[2].flipX = true, true
    s[1].sx, s[1].sy = -METAL_CLAW_OFFSET_X, 0
    s[2].sx, s[2].sy = -METAL_CLAW_OFFSET_X, METAL_CLAW_OFFSET_Y
    s[3].sx, s[3].sy = METAL_CLAW_OFFSET_X, 0
    s[4].sx, s[4].sy = METAL_CLAW_OFFSET_X, METAL_CLAW_OFFSET_Y
    ctx.rightDelay = METAL_CLAW_RIGHT_DELAY
    ctx.counters = { 0, 0, 0, 0 }
  end,
  step = function(ctx)
    local s = ctx.sprites
    if ctx.rightDelay <= 0 then
      tickIfVisible(s[3])
      tickIfVisible(s[4])
    else
      ctx.rightDelay = ctx.rightDelay - 1
    end
    tickIfVisible(s[1])
    tickIfVisible(s[2])
    local hidden = 0
    for i = 1, METAL_CLAW_COUNT do
      ctx.counters[i] = ctx.counters[i] + 1
      if ctx.counters[i] >= METAL_CLAW_VISIBLE_FRAMES then
        s[i].visible = false
        hidden = hidden + 1
      end
    end
    if hidden == METAL_CLAW_COUNT then return false end
    return true
  end,
}

-- ---------------------------------------------------------------------------
-- 10 Swagger -- ONE sprite used TWICE, and hidden in between
--
-- The "angry vein" pops in beside the defender, swells, settles, vanishes, waits
-- four frames, then does the whole thing again on the other side and higher up.
-- One sprite, two appearances: a port that assumed two sprites would draw both at
-- once, and one that deleted the sprite after the first pop would drop the
-- second.
--
-- THE SWELL IS A SCALE LERP AND THEN A SETTLE: 10 -> 14 over four frames against
-- a reference of 10 -- 1.0x to 1.398x, because `RELATIVE_SCALE` is integer
-- division and 14 * 256 / 10 is 358 -- then 14 -> 12 over two. `UpdatePop` starts
-- the second lerp on the frame the first reports finished, so there is no gap
-- between them and the pop lasts 4 + 2 + 1 frames, the last being the frame it
-- hides.
--
-- THE SIDE IS THE ATTACKER'S, not the defender's:
-- `GetTransformDirectionX(attacker)` is -1 when the attacker is on the enemy
-- side, and the first pop sits at +24 * dir from the defender.
-- ---------------------------------------------------------------------------

local SWAGGER_START_SCALE = 10
local SWAGGER_REF_SCALE = 10
local SWAGGER_END_SCALE = 14
local SWAGGER_SCALE_FRAMES = 4
local SWAGGER_SETTLE_SCALE = 12
local SWAGGER_SETTLE_FRAMES = 2
local SWAGGER_POP_OFFSET_X = 24
local SWAGGER_POP1_OFFSET_Y = -16
local SWAGGER_POP2_OFFSET_Y = -24
local SWAGGER_POP_DELAY = 4

local function swaggerStartPop(ctx, sx, sy)
  local s = ctx.sprites[1]
  s.visible = true
  s.sx, s.sy = sx, sy
  ctx.scaleStep = 0
  ctx.scale = Gen4AnimMath.scaleLerp(SWAGGER_START_SCALE, SWAGGER_REF_SCALE,
                                     SWAGGER_END_SCALE, SWAGGER_SCALE_FRAMES)
  s.scaleX, s.scaleY = Gen4AnimMath.affineScale(ctx.scale)
end

-- Returns true on the frame the pop is over.
local function swaggerUpdatePop(ctx)
  local s = ctx.sprites[1]
  if Gen4AnimMath.scaleLerpUpdate(ctx.scale) then
    s.scaleX, s.scaleY = Gen4AnimMath.affineScale(ctx.scale)
    return false
  end
  if ctx.scaleStep == 1 then
    s.visible = false
    return true
  end
  ctx.scaleStep = 1
  ctx.scale = Gen4AnimMath.scaleLerp(SWAGGER_END_SCALE, SWAGGER_REF_SCALE,
                                     SWAGGER_SETTLE_SCALE, SWAGGER_SETTLE_FRAMES)
  return false
end

SPRITE_MOTION[10] = {
  name = "Swagger",
  count = 1,
  start = function(ctx)
    -- `SetDrawFlag(FALSE)` before anything else: the vein is invisible until the
    -- first pop starts, which is the frame after this one.
    ctx.sprites[1].visible = false
    ctx.dir = Gen4AnimMath.directionX(ctx.attackerIsPlayer)
    ctx.popState = 0
    ctx.delay = SWAGGER_POP_DELAY
  end,
  step = function(ctx)
    if ctx.popState == 0 then
      swaggerStartPop(ctx, SWAGGER_POP_OFFSET_X * ctx.dir, SWAGGER_POP1_OFFSET_Y)
      ctx.popState = 1
    elseif ctx.popState == 1 then
      if swaggerUpdatePop(ctx) then ctx.popState = 2 end
    elseif ctx.popState == 2 then
      ctx.delay = ctx.delay - 1
      if ctx.delay < 0 then
        ctx.popState = 3
        swaggerStartPop(ctx, -SWAGGER_POP_OFFSET_X * ctx.dir, SWAGGER_POP2_OFFSET_Y)
      end
    elseif ctx.popState == 3 then
      if swaggerUpdatePop(ctx) then ctx.popState = 4 end
    else
      return false
    end
    return true
  end,
}

-- ---------------------------------------------------------------------------
-- 17 IcicleSpear -- a PARABOLA from the attacker to the defender, rotating
--
-- The only callback in the cartridge that reads four script vars, and move 333
-- calls it three times with three different sets: (-15, -5, 10, 32), (-5, -20,
-- 10, 32) and (-10, -15, 10, 32) -- target offset X, target offset Y, frames,
-- arc radius. Three icicles on three paths, which is why the move reads as a
-- volley rather than one shot.
--
-- THE PATH IS `XYTransformContext_InitParabolic`: a straight lerp from the
-- attacker's centre to the defender's centre plus the offset, plus half a
-- revolution of the cosine over the arc radius added into the Y. Both halves get
-- the same frame count, so the sprite dies on the frame the lerp lands.
--
-- BOTH offsets are multiplied by the direction, the Y included. Unusual, and it
-- is what the C says.
--
-- THE ROTATION IS A `ValueLerp` ON THE ANGLE INDEX and its START differs by side:
-- 20 -> 130 degrees flying right, and 90 -> 130 negated flying left -- a
-- different arc, not a mirrored one. The doubles slot-2-to-slot-1 cases flip the
-- direction a second time; singles never reach them.
--
-- THE FIRST STEP HAPPENS IN THE CALLBACK, not the task: pret updates the
-- parabola once and ticks the animation once before starting the task, so the
-- icicle is already one step along its path on the frame it appears.
-- ---------------------------------------------------------------------------

local ICICLE_VAR_TARGET_X = 0
local ICICLE_VAR_TARGET_Y = 1
local ICICLE_VAR_FRAMES = 2
local ICICLE_VAR_ARC_RADIUS = 3
local ICICLE_START_ANGLE = 20
local ICICLE_END_ANGLE = 130
local ICICLE_RSTART_ANGLE = 90
local ICICLE_REND_ANGLE = 130
local ICICLE_ROTATION_FRAMES = 10

SPRITE_MOTION[17] = {
  name = "IcicleSpear",
  count = 1,
  start = function(ctx)
    local s = ctx.sprites[1]
    local vars = ctx.vars
    local targetX = tonumber(vars[ICICLE_VAR_TARGET_X]) or 0
    local targetY = tonumber(vars[ICICLE_VAR_TARGET_Y]) or 0
    local frames = tonumber(vars[ICICLE_VAR_FRAMES]) or 0
    local radius = tonumber(vars[ICICLE_VAR_ARC_RADIUS]) or 0
    local dir = Gen4AnimMath.directionX(ctx.attackerIsPlayer)
    local attacker, defender = ctx.pos.attacker, ctx.pos.defender
    -- ABSOLUTE, because the path runs BETWEEN two battlers and an offset from
    -- either one could not express it.
    ctx.path = Gen4AnimMath.parabolic(attacker.x, defender.x + targetX * dir,
                                      attacker.y, defender.y + targetY * dir,
                                      frames, radius * Gen4AnimMath.FX32_ONE)
    if dir > 0 then
      ctx.angle = Gen4AnimMath.valueLerp(
        Gen4AnimMath.degToIdx(ICICLE_START_ANGLE) * dir,
        Gen4AnimMath.degToIdx(ICICLE_END_ANGLE) * dir, ICICLE_ROTATION_FRAMES)
    else
      ctx.angle = Gen4AnimMath.valueLerp(
        Gen4AnimMath.degToIdx(ICICLE_RSTART_ANGLE) * dir,
        Gen4AnimMath.degToIdx(ICICLE_REND_ANGLE) * dir, ICICLE_ROTATION_FRAMES)
    end
    s.rotation = Gen4AnimMath.radians(ctx.angle.value)
    local live, x, y = Gen4AnimMath.parabolicUpdate(ctx.path)
    ctx.live = live
    s.absoluteX, s.absoluteY = x, y
    tick(s)
  end,
  step = function(ctx)
    local s = ctx.sprites[1]
    if not ctx.live then return false end
    local live, x, y = Gen4AnimMath.parabolicUpdate(ctx.path)
    if not live then
      -- pret deletes the sprite on the frame the parabola reports finished and
      -- does NOT apply that last point, so the icicle never lands a pixel past
      -- where the lerp stopped.
      ctx.live = false
      return false
    end
    s.absoluteX, s.absoluteY = x, y
    if Gen4AnimMath.valueLerpUpdate(ctx.angle) then
      s.rotation = Gen4AnimMath.radians(ctx.angle.value)
    end
    tick(s)
    return true
  end,
}

-- ---------------------------------------------------------------------------
-- 18 FakeOut -- fade in, play, fade out
--
-- The one callback whose whole content is an alpha envelope, and the clearest
-- case of why the scheduler matters. `AlphaFadeContext_Init` starts a task at
-- priority 0 while this callback runs at 1100, and tasks run in ascending
-- priority, so the fade steps BEFORE the state machine reads it: an eight-frame
-- fade holds the machine for nine frames, and the sprite lasts its animation plus
-- twenty rather than plus sixteen. Pumping the fade at the top of `step` and
-- creating it below is that ordering, exactly.
--
-- THE SPRITE IS TRANSLUCENT THROUGHOUT (`SetExplicitOamMode(XLU)`), and the
-- blend's first coefficient is the sprite's own share, so alpha is ev1/16.
--
-- ITS ANIMATION RUNS ON THE SYSTEM'S CLOCK: `SetAnimateFlag(TRUE)` and no
-- `TickFrame` anywhere in the task, so the frame advances every frame including
-- during both fades -- which is why WAIT_ANIM can be over before it is reached.
-- ---------------------------------------------------------------------------

local FAKE_OUT_START_ALPHA = 0
local FAKE_OUT_END_ALPHA = 16
local FAKE_OUT_MAX_ALPHA = 16
local FAKE_OUT_FADE_FRAMES = 8

local function fakeOutFade(fromAlpha, toAlpha)
  return Gen4AnimMath.alphaFade(fromAlpha, toAlpha,
                               FAKE_OUT_MAX_ALPHA - fromAlpha,
                               FAKE_OUT_MAX_ALPHA - toAlpha,
                               FAKE_OUT_FADE_FRAMES)
end

SPRITE_MOTION[18] = {
  name = "FakeOut",
  count = 1,
  start = function(ctx)
    -- `SetSpriteBgBlending(0, 16)` is the starting blend, so the sprite is
    -- invisible on the frame it is created.
    ctx.sprites[1].alpha = FAKE_OUT_START_ALPHA / FAKE_OUT_MAX_ALPHA
    ctx.state = 0
  end,
  step = function(ctx)
    local s = ctx.sprites[1]
    if ctx.fade then
      Gen4AnimMath.alphaFadeUpdate(ctx.fade)
      s.alpha = Gen4AnimMath.blendAlpha(ctx.fade)
    end
    if ctx.state == 0 then
      ctx.fade = fakeOutFade(FAKE_OUT_START_ALPHA, FAKE_OUT_END_ALPHA)
      ctx.state = 1
    elseif ctx.state == 1 then
      if Gen4AnimMath.alphaFadeDone(ctx.fade) then ctx.state = 2 end
    elseif ctx.state == 2 then
      if animDone(s) then
        ctx.state = 3
        ctx.fade = fakeOutFade(FAKE_OUT_END_ALPHA, FAKE_OUT_START_ALPHA)
      end
    elseif ctx.state == 3 then
      if Gen4AnimMath.alphaFadeDone(ctx.fade) then ctx.state = 4 end
    else
      return false
    end
    -- The animate flag, not the task: the frame advances whatever state it is in,
    -- and stops on its own at the end of the sequence.
    if not animDone(s) then tick(s) end
    return true
  end,
}

-- ---------------------------------------------------------------------------
-- 25 OffsetAndAnimate -- the generic one
--
-- Script vars 0 and 1 as an X/Y offset, then nothing but the animation. Move 265
-- passes (0, 24): twenty-four pixels DOWN from the defender's centre.
-- ---------------------------------------------------------------------------

SPRITE_MOTION[25] = {
  name = "OffsetAndAnimate",
  count = 1,
  start = function(ctx)
    local s = ctx.sprites[1]
    s.sx = tonumber(ctx.vars[0]) or 0
    s.sy = tonumber(ctx.vars[1]) or 0
  end,
  step = function(ctx)
    -- The task checks first and ticks second: `if (!IsAnimated) delete` and only
    -- then `TickFrame`, so the last frame is shown once and not twice.
    local s = ctx.sprites[1]
    if animDone(s) then return false end
    tick(s)
    return true
  end,
}

-- ---------------------------------------------------------------------------
-- 7 ScaryFace -- the first callback that touches a BATTLER, not just its sprite
--
-- Two things at once, and only one of them is a cell actor: the face sprite
-- grows, drifts and fades, while the ATTACKER'S OWN POKEMON SPRITE STRETCHES
-- VERTICALLY -- `PokemonSprite_SetAttribute(attacker, MON_SPRITE_SCALE_Y, ...)`
-- from 1.0x to 1.5x over twelve frames and back, with an exact 0x100 written at
-- the end rather than trusted to arrive. That is the `monAffine` channel Emerald
-- already defined, so the callback reaches the battler through `ctx.player`
-- instead of a second draw path.
--
-- ITS SPRITE SPENDS ONE FRAME AT THE DEFENDER AND THE REST AT THE ATTACKER, and
-- that is the cartridge's own artifact rather than a port bug.
-- `addspritewithfunc` builds the template at the DEFENDER; the callback computes
-- its base from the ATTACKER but applies nothing until the first
-- `XYTransformContext_ApplyPosOffsetToSprite`, which is the task's first frame --
-- and the task does not run on the frame it is created. So frame one draws the
-- face on the wrong Pokemon. Reproduced, because a port that "fixed" it would be
-- a frame out for every later one.
--
-- THE INITIAL BLEND IS SET ABOVE THE MAXIMUM. `G2_SetBlendAlpha(..., 31, 26)`
-- with coefficients the hardware clamps at 16, so the face starts fully opaque
-- and the fade begins from there.
-- ---------------------------------------------------------------------------

local SCARY_FACE_ATTACKER_START_SCALE = 10
local SCARY_FACE_ATTACKER_REF_SCALE = 10
local SCARY_FACE_ATTACKER_END_SCALE = 15
local SCARY_FACE_ATTACKER_SCALE_FRAMES = 12
local SCARY_FACE_FACE_START_SCALE = 5
local SCARY_FACE_FACE_REF_SCALE = 10
local SCARY_FACE_FACE_END_SCALE = 12
local SCARY_FACE_FACE_SCALE_FRAMES = 32
local SCARY_FACE_FACE_OFFSET_X = 32
local SCARY_FACE_FACE_MOVE_FRAMES = 32
local SCARY_FACE_FACE_MOVE_Y_ENEMY = -8
local SCARY_FACE_FACE_MOVE_Y_PLAYER = -24
local SCARY_FACE_FADE_EV1_START = 16
local SCARY_FACE_FADE_EV1_END = 0
local SCARY_FACE_FADE_EV2_START = 14
local SCARY_FACE_FADE_EV2_END = 16
local SCARY_FACE_FADE_FRAMES = 8

-- The battler channel a callback writes through: the same table
-- `scalebattlersprite` and `fadebattlersprite` write, so a callback and a script
-- command cannot end up with two disagreeing ideas of where a Pokemon is.
local function battlerState(ctx, isPlayer)
  return ctx.player.state[isPlayer and true or false]
end

SPRITE_MOTION[7] = {
  name = "ScaryFace",
  count = 1,
  start = function(ctx)
    ctx.dir = Gen4AnimMath.directionX(ctx.attackerIsPlayer)
    -- `GetTransformDirectionY` is the same rule as X outside a contest -- -1 on
    -- the enemy side -- so one number serves both.
    ctx.attackerScale = Gen4AnimMath.scaleLerp(SCARY_FACE_ATTACKER_START_SCALE,
                                               SCARY_FACE_ATTACKER_REF_SCALE,
                                               SCARY_FACE_ATTACKER_END_SCALE,
                                               SCARY_FACE_ATTACKER_SCALE_FRAMES)
    ctx.attackerState = 0
    local moveY = (ctx.dir < 0) and SCARY_FACE_FACE_MOVE_Y_ENEMY
                                or SCARY_FACE_FACE_MOVE_Y_PLAYER
    ctx.baseX = SCARY_FACE_FACE_OFFSET_X * ctx.dir
    ctx.baseY = 0
    ctx.facePos = Gen4AnimMath.posLerp(0, 0 * ctx.dir, 0, moveY * ctx.dir,
                                       SCARY_FACE_FACE_MOVE_FRAMES)
    ctx.faceScale = Gen4AnimMath.scaleLerp(SCARY_FACE_FACE_START_SCALE,
                                           SCARY_FACE_FACE_REF_SCALE,
                                           SCARY_FACE_FACE_END_SCALE,
                                           SCARY_FACE_FACE_SCALE_FRAMES)
    ctx.faceState = 0
    local s = ctx.sprites[1]
    s.scaleX, s.scaleY = Gen4AnimMath.affineScale(ctx.faceScale)
    -- and the origin is left at the defender on purpose: see the note above.
  end,
  step = function(ctx)
    local s = ctx.sprites[1]
    -- THE ATTACKER'S STRETCH. Its own little machine, and the outer task ignores
    -- whether it has finished -- the FACE is what ends the callback.
    if ctx.attackerState == 0 then
      if Gen4AnimMath.scaleLerpUpdate(ctx.attackerScale) then
        battlerState(ctx, ctx.attackerIsPlayer).sy =
          ctx.attackerScale.y / Gen4AnimMath.AFFINE_ONE
      else
        ctx.attackerState = 1
        ctx.attackerScale = Gen4AnimMath.scaleLerp(SCARY_FACE_ATTACKER_END_SCALE,
                                                   SCARY_FACE_ATTACKER_REF_SCALE,
                                                   SCARY_FACE_ATTACKER_START_SCALE,
                                                   SCARY_FACE_ATTACKER_SCALE_FRAMES)
      end
    elseif ctx.attackerState == 1 then
      if Gen4AnimMath.scaleLerpUpdate(ctx.attackerScale) then
        battlerState(ctx, ctx.attackerIsPlayer).sy =
          ctx.attackerScale.y / Gen4AnimMath.AFFINE_ONE
      else
        -- EXACTLY 1.0, written rather than assumed: the lerp lands on 256 here,
        -- and pret still assigns MON_SPRITE_SCALE_Y = 0x100 itself.
        battlerState(ctx, ctx.attackerIsPlayer).sy = 1
        ctx.attackerState = 2
      end
    end

    -- THE FACE.
    if ctx.faceState == 0 then
      if Gen4AnimMath.scaleLerpUpdate(ctx.faceScale) then
        s.scaleX, s.scaleY = Gen4AnimMath.affineScale(ctx.faceScale)
      end
      if Gen4AnimMath.posLerpUpdate(ctx.facePos) then
        s.origin = "attacker"
        s.sx = ctx.baseX + ctx.facePos.x
        s.sy = ctx.baseY + ctx.facePos.y
      else
        ctx.faceState = 1
        ctx.fade = Gen4AnimMath.alphaFade(SCARY_FACE_FADE_EV1_START,
                                          SCARY_FACE_FADE_EV1_END,
                                          SCARY_FACE_FADE_EV2_START,
                                          SCARY_FACE_FADE_EV2_END,
                                          SCARY_FACE_FADE_FRAMES)
      end
    elseif ctx.faceState == 1 then
      Gen4AnimMath.alphaFadeUpdate(ctx.fade)
      s.alpha = Gen4AnimMath.blendAlpha(ctx.fade)
      if Gen4AnimMath.alphaFadeDone(ctx.fade) then
        s.visible = false
        ctx.faceState = 2
      end
    elseif ctx.faceState == 2 then
      -- The frame the face reports DONE; the outer task cleans up on the next.
      ctx.faceState = 3
    else
      return false
    end
    tick(s)
    return true
  end,
}

-- ---------------------------------------------------------------------------
-- 8 Foresight -- a six-segment zig-zag, and a WHITE FLASH ON THE DEFENDER
--
-- The sprite starts where the command put it (the defender) and walks six
-- straight segments of eight frames each, pausing five frames between them --
-- `delay++` until `delay > 4`, which is five, not four. Each segment's END
-- BECOMES THE NEXT SEGMENT'S BASE (`baseX += pos.x`), so the six accumulate into
-- a path; their offsets sum to (0, 0), so it finishes where it began.
--
-- THEN TWO FADES AT ONCE: the sprite's own alpha 16 -> 0 over sixteen frames, and
-- `PokemonSprite_StartFade` on the DEFENDER'S POKEMON SPRITE -- a palette blend
-- toward white, one step of 1/16 per frame from 0 to 10 and then back down. That
-- is the `monTint` channel, so this is the second callback to reach a battler.
--
-- THE FLASH IS WHAT ENDS THE CALLBACK, not the sprite: the fade-out hides the
-- sprite when it finishes, but the state machine waits for the defender's flash
-- out AND then its flash back in before cleaning up.
-- ---------------------------------------------------------------------------

local FORESIGHT_MOVE_EXTENT = 80
local FORESIGHT_MOVE_FRAMES = 8
local FORESIGHT_SEGMENT_COUNT = 6
local FORESIGHT_START_DELAY = 4
local FORESIGHT_FADE_EV1_START = 16
local FORESIGHT_FADE_EV1_END = 0
local FORESIGHT_FADE_EV2_START = 0
local FORESIGHT_FADE_EV2_END = 16
local FORESIGHT_FADE_FRAMES = 16
local FORESIGHT_FLASH_START_ALPHA = 0
local FORESIGHT_FLASH_END_ALPHA = 10
local FORESIGHT_FLASH_DELAY = 0
-- `GX_RGB(31, 31, 31)` -- white, and the port's tint channel takes 0..1 per
-- component like `fadebattlersprite` does.
local FORESIGHT_FLASH_R = 1
local FORESIGHT_FLASH_G = 1
local FORESIGHT_FLASH_B = 1

-- The six segments, written out rather than computed, because the C writes them
-- out: half the extent, then whole extents, then half back.
local FORESIGHT_SEGMENTS = {
  { FORESIGHT_MOVE_EXTENT / 2, FORESIGHT_MOVE_EXTENT / 2 },
  { 0, -FORESIGHT_MOVE_EXTENT },
  { -FORESIGHT_MOVE_EXTENT, FORESIGHT_MOVE_EXTENT },
  { 0, -FORESIGHT_MOVE_EXTENT },
  { FORESIGHT_MOVE_EXTENT, FORESIGHT_MOVE_EXTENT },
  { -FORESIGHT_MOVE_EXTENT / 2, -FORESIGHT_MOVE_EXTENT / 2 },
}

local function foresightFlash(ctx, from, to)
  ctx.flash = Gen4AnimMath.monFade(from, to, FORESIGHT_FLASH_DELAY,
                                   FORESIGHT_FLASH_R, FORESIGHT_FLASH_G,
                                   FORESIGHT_FLASH_B)
end

-- The tint the defender is wearing this frame, or nil once the flash is over and
-- has been cleared.
local function foresightApplyFlash(ctx)
  if not ctx.flash then return end
  Gen4AnimMath.monFadeUpdate(ctx.flash)
  local applied = ctx.flash.applied
  if applied == nil then return end
  local state = battlerState(ctx, not ctx.attackerIsPlayer)
  state.tint = { FORESIGHT_FLASH_R, FORESIGHT_FLASH_G, FORESIGHT_FLASH_B,
                 applied / Gen4AnimMath.BLEND_MAX }
end

SPRITE_MOTION[8] = {
  name = "Foresight",
  count = 1,
  start = function(ctx)
    ctx.state = 0
    ctx.segment = 1
    ctx.delay = 0
    ctx.baseX, ctx.baseY = 0, 0
  end,
  step = function(ctx)
    local s = ctx.sprites[1]
    -- THE SPRITE'S OWN FADE IS A SEPARATE TASK AND DOES NOT STOP WITH THE STATE
    -- MACHINE. Sixteen frames of it against eleven of the defender's flash, so the
    -- machine has already moved on to WAIT_FLASH while the sprite is still fading
    -- -- and the `SetDrawFlag(FALSE)` in FADE_OUT is therefore NEVER REACHED on
    -- this move. The sprite simply reaches alpha 0 and is deleted at cleanup.
    -- Pumping here, at the top, is that independence; pumping it inside the
    -- FADE_OUT arm froze the sprite at 5/16 opacity for the rest of its life.
    if ctx.fade then
      Gen4AnimMath.alphaFadeUpdate(ctx.fade)
      s.alpha = Gen4AnimMath.blendAlpha(ctx.fade)
    end
    if ctx.state == 0 then
      -- FIVE frames, not four: `delay++` happens first and the test is `> 4`.
      ctx.delay = ctx.delay + 1
      if ctx.delay > FORESIGHT_START_DELAY then
        local seg = FORESIGHT_SEGMENTS[ctx.segment]
        ctx.pos = Gen4AnimMath.posLerp(0, seg[1], 0, seg[2], FORESIGHT_MOVE_FRAMES)
        ctx.state = 1
        ctx.delay = 0
      end
    elseif ctx.state == 1 then
      if Gen4AnimMath.posLerpUpdate(ctx.pos) then
        s.sx = ctx.baseX + ctx.pos.x
        s.sy = ctx.baseY + ctx.pos.y
      else
        ctx.segment = ctx.segment + 1
        if ctx.segment <= FORESIGHT_SEGMENT_COUNT then
          ctx.state = 0
          ctx.baseX = ctx.baseX + ctx.pos.x
          ctx.baseY = ctx.baseY + ctx.pos.y
        else
          ctx.state = 2
          ctx.fade = Gen4AnimMath.alphaFade(FORESIGHT_FADE_EV1_START,
                                            FORESIGHT_FADE_EV1_END,
                                            FORESIGHT_FADE_EV2_START,
                                            FORESIGHT_FADE_EV2_END,
                                            FORESIGHT_FADE_FRAMES)
          foresightFlash(ctx, FORESIGHT_FLASH_START_ALPHA,
                         FORESIGHT_FLASH_END_ALPHA)
        end
      end
    elseif ctx.state == 2 then
      -- Only this state hides the sprite, and only if its fade finishes first --
      -- which on move 193 it does not.
      if Gen4AnimMath.alphaFadeDone(ctx.fade) then s.visible = false end
      foresightApplyFlash(ctx)
      if not (ctx.flash and ctx.flash.active) then
        ctx.state = 3
        foresightFlash(ctx, FORESIGHT_FLASH_END_ALPHA,
                       FORESIGHT_FLASH_START_ALPHA)
      end
      return true
    elseif ctx.state == 3 then
      foresightApplyFlash(ctx)
      if not (ctx.flash and ctx.flash.active) then
        -- AND THE TINT IS LEFT AT ALPHA ZERO rather than removed. Nothing in the
        -- C takes the blend off: `BlendPalette` with a fraction of 0 writes the
        -- unfaded colour back, so the last frame of the walk IS the restore and a
        -- tint of zero and no tint are the same picture. Removing it here instead
        -- would drop that frame from the walk and make the ramp down one step
        -- shorter than the ramp up, which is a difference only a check would ever
        -- see -- and then only one that counts the steps. `clearTransforms` takes
        -- it off for good when the player finishes.
        ctx.state = 4
      end
    else
      return false
    end
    -- NO `tick` ANYWHERE IN THIS CALLBACK: it neither sets the animate flag nor
    -- calls `TickFrame`, so the eye holds animation frame 0 for its whole flight.
    -- Swagger's vein is the same. A port that ticked it anyway would run the
    -- sequence out and then hold its LAST frame, which is a different picture.
    return true
  end,
}

function Player:spriteKey(char, palette, cell, anim)
  return ("%s_%s_%s_%s"):format(tostring(char), tostring(palette),
                                tostring(cell), tostring(anim))
end

function Player:initSpriteManager(id, limits)
  self.managers[tonumber(id) or 0] = {
    loaded = { char = {}, palette = {}, cell = {}, anim = {} },
    limits = limits,
  }
end

function Player:loadSpriteResource(kind, id, member)
  local manager = self.managers[tonumber(id) or 0]
  if not manager then
    -- The cartridge always opens a manager first; saying so is cheaper than
    -- silently creating one and then wondering why a limit was never applied.
    self:note("load" .. kind .. " without a sprite manager")
    return false
  end
  manager.loaded[kind][member] = true
  return true
end

-- addSprite(managerId, funcId, char, palette, cell, anim)
--
-- `funcId` is nil for `addsprite`, which has no callback at all. The callback's
-- arguments are NOT a parameter: they are script vars 0..n-1 by the time this
-- runs, because that is where the cartridge's handler puts them.
function Player:addSprite(id, funcId, char, palette, cell, anim)
  local manager = self.managers[tonumber(id) or 0]
  local key = self:spriteKey(char, palette, cell, anim)
  local art = self.cellArt and self.cellArt[key]
  if not art then
    self:note("cellactor:" .. key)
    return false
  end
  if manager then
    local loaded = manager.loaded
    if not (loaded.char[char] and loaded.cell[cell] and loaded.anim[anim]) then
      -- pret: "All resource indices specified here must have been previously
      -- loaded into the sprite manager." True on all 38 in the cartridge, so a
      -- failure here means the program is not being read the way it runs.
      self:note("cellactor used before loading: " .. key)
    end
  end
  -- WHICH SEQUENCE. The script never selects one; the CALLBACK does, and for the
  -- three whose rule pret states plainly this port follows it. Everything else
  -- plays the first, which is what a single-sequence bank has anyway.
  local pick = SPRITE_SEQUENCE[funcId]
  local wanted = pick and pick(self.attackerIsPlayer) or 0
  local sequences = art.sequences or {}
  if not sequences[wanted + 1] then
    -- A CLAMP THAT COUNTS ITSELF. Asking for a sequence a bank does not have
    -- means the rule and the data disagree, and falling back silently would hide
    -- exactly that.
    self:note(("sequence %d of %s (only %d)"):format(wanted, key, #sequences))
    wanted = 0
  end
  local frames = sequences[wanted + 1] and sequences[wanted + 1].frames
  if not frames or #frames == 0 then
    self:note("cellactor with no animation: " .. key)
    return false
  end

  -- THE SPRITE STARTS AT THE DEFENDER. `BattleAnimScriptCmd_AddSpriteWithFunc`
  -- builds its template from `BattleAnimUtil_GetBattlerPos(system, defender,
  -- MON_X/MON_Y)` before any callback runs, so that is the generic position and
  -- the callback is the motion on top of it.
  local func = funcId and SPRITE_FUNCS[funcId] or nil
  local motion = funcId and SPRITE_MOTION[funcId] or nil

  -- AND FISSURE'S ABSOLUTE HEIGHT. The record carries the origin name for the X
  -- and an absolute screen Y beside it, because that is what the cartridge does:
  -- the crack opens at a fixed height whichever Pokemon is standing there. Its
  -- MOTION is not ported -- only its placement -- so it is not in SPRITE_MOTION
  -- and still reports itself below.
  local absoluteY = nil
  if funcId == SPRITE_FUNC_FISSURE then
    -- The DEFENDER's side: the player attacking means the defender is the enemy.
    absoluteY = self.attackerIsPlayer and FISSURE_Y_ENEMY or FISSURE_Y_PLAYER
  end

  -- HOW MANY SPRITES. One per `addspritewithfunc` unless the callback clones
  -- more out of the same template, which three of them do and no amount of
  -- reading the script would reveal.
  local count = motion and motion.count or 1
  local made = {}
  for _ = 1, count do
    local record = {
      key = key, art = art, frames = frames,
      animTick = 0,
      length = Gen4CellAnim.length(frames),
      -- DS SCREEN OFFSETS, +Y DOWN -- see the note at SPRITE_MOTION.
      sx = 0, sy = 0,
      origin = "defender",
      absoluteY = absoluteY,
      visible = true,
      alpha = 1,
      scaleX = 1, scaleY = 1,
      rotation = 0,
      flipX = false,
      sequence = wanted,
      func = func,
    }
    self.sprites[#self.sprites + 1] = record
    made[#made + 1] = record
  end

  if motion then
    -- WHERE THE BATTLERS STAND is handed to the callback, not looked up by it:
    -- the two that compute a path between battlers need pixels, and every other
    -- callback wants an offset from one of them.
    local ctx = {
      motion = motion, sprites = made, vars = self.vars,
      attackerIsPlayer = self.attackerIsPlayer,
      pos = self:battlerPositions(),
      -- THE PLAYER ITSELF, because two callbacks move a BATTLER rather than
      -- their own sprite and the battler channels live on it. Handing over the
      -- player rather than four setters keeps the callbacks looking like the C
      -- they are ported from, where the callback holds the system pointer.
      player = self,
      frame = 0, done = false,
      -- THE FRAME IT WAS BORN, because its task does not run on that frame.
      -- `SysTaskManager_InternalAddTask` puts a new task either behind the
      -- cursor (when its priority is lower than the running task's) or straight
      -- into TASK_STATE_INACTIVE (when it is not), and a sprite callback starts
      -- its task from inside the script's own task -- so whichever of the two
      -- applies, the first step is the NEXT frame. What is drawn on this frame is
      -- what `start` set up, which is the point: IcicleSpear's first frame is the
      -- one step along the parabola its callback takes by hand.
      born = self.frames,
    }
    self.spriteCtxs[#self.spriteCtxs + 1] = ctx
    for _, record in ipairs(made) do record.ctx = ctx end
    motion.start(ctx)
  elseif func then
    self:note("sprite motion:" .. func)
  elseif funcId then
    self:note("sprite motion:func " .. tostring(funcId))
  end
  return true
end

-- WHERE THE TWO SINGLES BATTLERS STAND, in the DS's 256x192. The numbers are
-- `BATTLER_POS_*` in include/constants/battle/battle_anim.h, which
-- `gBattlerEncounterX` in ov12_022380BC.c states again independently;
-- `Gen4Battle.BATTLER_POS` holds the same pair for the same reason and
-- `gen4_moveanim_check.lua` asserts the two files agree rather than trusting
-- this comment.
Player.BATTLER_POS = {
  player = { x = 64, y = 112 },
  enemy = { x = 192, y = 48 },
}

-- The top of the screen, which is where `MoveEmitterViewportTop` sends an emitter.
-- Derived rather than chosen: see `startEmitterViewportPath`.
Player.VIEWPORT_TOP_Y = 0

function Player:battlerPositions()
  local me, foe = Player.BATTLER_POS.player, Player.BATTLER_POS.enemy
  if self.attackerIsPlayer then
    return { attacker = me, defender = foe, player = me, enemy = foe }
  end
  return { attacker = foe, defender = me, player = me, enemy = foe }
end

function Player:stepSprites()
  -- THE CALLBACKS FIRST, because a callback owns its sprites' lifetime: it is
  -- the state machine that stops, and its sprites go with it. `step` returning
  -- false is pret's `Sprite_DeleteAndFreeResources` plus `EndAnimTask`.
  for _, ctx in ipairs(self.spriteCtxs) do
    if not ctx.done and ctx.born ~= self.frames then
      ctx.frame = ctx.frame + 1
      if ctx.motion.step(ctx) == false then
        ctx.done = true
        for _, s in ipairs(ctx.sprites) do s.done = true end
      end
    end
  end
  local alive = 0
  for _, s in ipairs(self.sprites) do
    if not s.done then
      if not s.ctx then
        -- NO CALLBACK: pret deletes the sprite the frame
        -- `ManagedSprite_IsAnimated` goes false, which is when its sequence has
        -- run out -- so the animation's own length is the sprite's lifetime and
        -- nothing else needs to say so.
        s.animTick = s.animTick + 1
        if s.animTick >= s.length then s.done = true end
      end
      if not s.done then alive = alive + 1 end
    end
  end
  return alive
end

function Player:spriteCount()
  local n = 0
  for _, s in ipairs(self.sprites) do if not s.done then n = n + 1 end end
  return n
end

-- cells() -> a draw list, one record per live 2D sprite.
--
-- Shaped like `particles()` on purpose: an origin name the screen resolves, a
-- pixel offset, and the art to blit. The cell index comes from the animation, so
-- a sprite mid-sequence hands over the frame it is actually showing.
function Player:cells()
  local out = {}
  for _, s in ipairs(self.sprites) do
    -- `SetDrawFlag(FALSE)` is not death: Swagger's vein is invisible between its
    -- two pops and MetalClaw's claws stop being drawn before the task ends, and
    -- both sprites still exist and still count against the manager.
    if not s.done and s.visible then
      local cell = Gen4CellAnim.at(s.frames, s.animTick)
      local image = cell and s.art.cells and s.art.cells[cell + 1] or nil
      out[#out + 1] = {
        origin = s.origin, x = s.sx, y = s.sy,
        absoluteX = s.absoluteX, absoluteY = s.absoluteY,
        sequence = s.sequence,
        -- WHAT THE CALLBACK HAS DONE TO IT. Every one of these is 1/0/false on a
        -- sprite whose callback is not ported, so the draw path is the same code
        -- either way and a missing callback cannot silently tint or shrink
        -- anything.
        alpha = s.alpha, scaleX = s.scaleX, scaleY = s.scaleY,
        rotation = s.rotation, flipX = s.flipX,
        art = image, cell = cell, key = s.key, func = s.func,
        -- A FRAME WITH NO ART IS A DELIBERATE BLANK, not a missing picture.
        -- Cell 0 of members 17, 19 and 26 has no OAM entries at all and their
        -- animations name it -- a beat of nothing before the sprite appears --
        -- so the record says which of the two it is instead of leaving the
        -- caller to read a nil as a fault.
        blank = image == nil,
      }
    end
  end
  return out
end

-- duration(moveId, attackerIsPlayer) -> how many frames this program will take
--
-- MEASURED BY RUNNING IT, not estimated: the frame count is the sum of the
-- delays AND the task lifetimes, and the tasks are started by script functions
-- whose durations are packed operands. Adding those up outside the VM would be
-- a second implementation of the VM, and the two would drift.
--
-- Safe to run twice because a program is DETERMINISTIC -- nothing here rolls a
-- die -- so the dry pass and the real one take the same path. The caller gets
-- the number and a freshly started program, ready to play.
function Player:duration(moveId, attackerIsPlayer)
  if not self:start(moveId, attackerIsPlayer) then return 0 end
  -- SILENT WHILE MEASURING. This runs the whole program and then starts it again, so
  -- a seam wired to the engine would hear every sound in every move twice -- the
  -- first time all at once, before anything was drawn. `start` clears the flag, so it
  -- is set after it and cleared again below rather than trusted to survive.
  self.quiet = true
  local frames = 0
  while self:update() do
    frames = frames + 1
    if frames > Player.FRAME_BUDGET then break end
  end
  local saved = self.unsupported
  self:start(moveId, attackerIsPlayer)
  self.unsupported = saved      -- keep what the dry pass learned
  self.quiet = false
  return frames
end

-- What this move asked for and did not get, as a sorted list. The diagnostic
-- the "silent skip" note above exists to make possible.
function Player:missing()
  local out = {}
  for what, n in pairs(self.unsupported) do
    out[#out + 1] = { what = what, count = n }
  end
  table.sort(out, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    return a.what < b.what
  end)
  return out
end

Gen4MoveAnimPlayer.Player = Player
return Gen4MoveAnimPlayer
