-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- PLATINUM'S SECOND BYTECODE: what an NPC does while a script watches.
--
-- `applymovement <localID> <offset>` is 3,025 rows across this cartridge --
-- every cutscene walk, every turn-to-face, every "!" over somebody's head --
-- and the port lowered all of them to "make the object face the player",
-- because the movement data itself was never read.
--
-- IT IS NOT IN AN ARCHIVE.  `ScrCmd_ApplyMovement` (scrcmd.c) does
--
--     MapObject_StartAnimation(object, (MapObjectAnimCmd *)(ctx->scriptPtr + movementOffset))
--
-- so the commands sit INSIDE THE SCRIPT MEMBER, at an offset from the byte
-- after the instruction -- the same way a `goto` target does.  That is why
-- there is no archive to find: it was always a few bytes further down the file
-- the script was already in.
--
-- A COMMAND IS FOUR BYTES, `{ u16 movementAction, u16 count }`
-- (`map_object_anim_cmd.h`), and a list ends at `MOVEMENT_ACTION_END`, which
-- `generated/movement_actions.txt` gives explicitly as **254** -- the only
-- entry in that file with a value written beside it, everything else being its
-- own line number minus one.
--
-- MEASURED over all 1,124 members of scr_seq, following `goto` targets as well
-- as entry points: **3,025 applymovement sites, 1,881 distinct lists, and all
-- 3,025 decode to a list that ends at 254** -- no refusals anywhere, 7,028
-- steps between them, 58 distinct actions, lists of 1 to 24 commands, repeat
-- counts from 1 to 38.  A format that terminates cleanly three thousand times
-- out of three thousand is being read correctly; the 162 members that contain
-- any of it are the cutscene members.
--
-- THE COMMONEST ACTIONS, which is what says the table below is pointed at the
-- right things: WALK_FAST_SOUTH (723), WALK_FAST_EAST (656), WALK_FAST_NORTH
-- (641), DELAY_8 (568), WALK_FAST_WEST (543), WALK_ON_SPOT_NORMAL_SOUTH (413),
-- WALK_ON_SPOT_NORMAL_EAST (367), WALK_ON_SPOT_NORMAL_NORTH (351).  Walking,
-- turning on the spot, and waiting -- which is what a cutscene is.
--
-- FOUR ACTIONS IN THE WHOLE CARTRIDGE HAVE NO NAME HERE: 106 (3 steps), 107
-- (2), 117 (11) and 153 (4), twenty steps out of 7,028.  They sit in the
-- unnamed stretch between the player's hand-out animation and the Distortion
-- World's jumps.  `action()` answers nil for them and the executor skips the
-- step, which is the one honest thing to do with an animation nobody decoded.

local Gen4Movement = {}

Gen4Movement.END = 254
Gen4Movement.BYTES = 4

-- Every direction group in this file runs NORTH, SOUTH, WEST, EAST.
local DIR = { [0] = "up", [1] = "down", [2] = "left", [3] = "right" }
Gen4Movement.DIR = DIR

-- action -> { kind, dir, n }
--   walk   n tiles in dir              spot   face dir and mark time n frames
--   face   turn to dir                 wait   n frames
--   hide / show / emote / none
local ACTIONS = {}

-- HOW FAST, as a multiplier on the walker's own step duration.
--
-- A movement action names a SPEED as well as a direction, and the port used to
-- drop it -- the comment here said so outright: "the port has one walk speed".
-- The engine has carried `mv.rate` since the Gen 3 work (where dropping it was
-- what made Birch stroll through a rescue written entirely in walk_fast), so
-- nothing needed building; the value simply was not being read off the Gen 4
-- table.
--
-- One step is one tile.  A normal walk crosses it in the walker's own
-- `stepFrames`, so `rate` is that duration scaled: BIGGER IS SLOWER.  The DS
-- ladder is pixels per frame over a 16-pixel tile -- normal 1, fast 2, faster
-- 4, fastest 8, slow 1/2, slower 1/4 -- which inverts to the multipliers
-- below and matches the halving Gen 3 already uses (`Gen3Commands.MOVE_SPEED`
-- is slow 2.0, walk 1.0, fast 0.5, fastest 0.25).
--
-- THE TWO "SLIGHTLY" CLASSES ARE INTERPOLATED, not measured: they sit between
-- normal and fast in the cartridge's own ordering, and nothing in the frame
-- tables has been read to pin them exactly.  Said plainly here rather than
-- left to look like the rest.
local RATE = {
  slower = 4.0, slow = 2.0, normal = 1.0,
  slightlyFast = 0.75, fast = 0.5, slightlyFaster = 0.375,
  faster = 0.25, fastest = 0.125, run = 0.25,
}

local function span(first, last, kind, tiles, rate)
  for a = first, last do
    ACTIONS[a] = { kind = kind, dir = DIR[(a - first) % 4], tiles = tiles,
                   rate = rate }
  end
end

span(0, 3, "face")
-- FIVE WALKING SPEEDS, four directions each, and the speed is kept now.  The
-- ids are the cartridge's own order, checked name by name against
-- `generated/movement_actions.txt`: 4 WALK_SLOWER, 8 WALK_SLOW, 12
-- WALK_NORMAL, 16 WALK_FAST, 20 WALK_FASTER, north/south/west/east in each.
span(4, 7, "walk", 1, RATE.slower)
span(8, 11, "walk", 1, RATE.slow)
span(12, 15, "walk", 1, RATE.normal)
span(16, 19, "walk", 1, RATE.fast)
span(20, 23, "walk", 1, RATE.faster)
-- On the spot: the sprite animates without moving, which a cutscene uses as a
-- pause with a facing.  Same five speeds, and the speed decides how long the
-- beat lasts rather than how far anything goes.
span(24, 27, "spot", nil, RATE.slower)
span(28, 31, "spot", nil, RATE.slow)
span(32, 35, "spot", nil, RATE.normal)
span(36, 39, "spot", nil, RATE.fast)
span(40, 43, "spot", nil, RATE.faster)
span(44, 51, "spot")           -- jump on the spot
span(52, 55, "walk", 1)        -- jump to the near tile
span(56, 59, "walk", 2)        -- jump two tiles
ACTIONS[60] = { kind = "wait", frames = 1 }
ACTIONS[61] = { kind = "wait", frames = 2 }
ACTIONS[62] = { kind = "wait", frames = 4 }
ACTIONS[63] = { kind = "wait", frames = 8 }
ACTIONS[64] = { kind = "wait", frames = 15 }
ACTIONS[65] = { kind = "wait", frames = 16 }
ACTIONS[66] = { kind = "wait", frames = 32 }
ACTIONS[67] = { kind = "none" }   -- warp out: the script's own warp does this
ACTIONS[68] = { kind = "none" }   -- warp in
ACTIONS[69] = { kind = "hide" }
ACTIONS[70] = { kind = "show" }
ACTIONS[71] = { kind = "none" }   -- lock facing
ACTIONS[72] = { kind = "none" }   -- unlock facing
ACTIONS[73] = { kind = "none" }   -- pause animation
ACTIONS[74] = { kind = "none" }   -- resume animation
ACTIONS[75] = { kind = "emote", emote = "exclamation" }
-- 76 WALK_SLIGHTLY_FAST, 80 WALK_SLIGHTLY_FASTER, 84 WALK_FASTEST, 88 RUN.
span(76, 79, "walk", 1, RATE.slightlyFast)
span(80, 83, "walk", 1, RATE.slightlyFaster)
span(84, 87, "walk", 1, RATE.fastest)
span(88, 91, "walk", 1, RATE.run)
ACTIONS[92] = { kind = "walk", dir = "left",  tiles = 1 }   -- jump near slow
ACTIONS[93] = { kind = "walk", dir = "right", tiles = 1 }
ACTIONS[94] = { kind = "walk", dir = "left",  tiles = 2 }   -- jump farther
ACTIONS[95] = { kind = "walk", dir = "right", tiles = 2 }
-- 96 WALK_EVER_SO_SLIGHTLY_FAST -- between normal and slightly fast.
span(96, 99, "walk", 1, 0.875)
ACTIONS[100] = { kind = "none" }  -- the nurse's bow
ACTIONS[101] = { kind = "none" }  -- a trainer standing up
ACTIONS[102] = { kind = "none" }  -- the player holding something out
ACTIONS[103] = { kind = "emote", emote = "double_exclamation" }
ACTIONS[104] = { kind = "none" }  -- the player taking something
span(118, 121, "walk", 1)      -- the Distortion World's jumps

Gen4Movement.ACTIONS = ACTIONS

-- What one action does, or nil when it is one this port has no name for.
-- Unknown is answered rather than guessed: a movement list with an action
-- nobody decoded should skip that step, not invent a walk.
function Gen4Movement.action(id)
  return ACTIONS[tonumber(id) or -1]
end

-- ---------------------------------------------------------------------------

local function u16(data, at)
  local a, b = data:byte(at), data:byte(at + 1)
  if not b then return nil end
  return a + b * 256
end

-- decode(data, at) -> { { action, count }, ... }, or nil plus a reason.
--
-- `at` is ONE-BASED, the way `Gen4Script` counts positions -- its own
-- `entries` refuses a target below 1, which is what says so.
--
-- A list that runs off the end of the member, or past `LIMIT` steps without
-- terminating, is refused rather than truncated: a movement list is read from
-- an offset, and an offset that is wrong produces a plausible-looking list of
-- nonsense.  The longest genuine one in this cartridge is well inside that.
Gen4Movement.LIMIT = 64

function Gen4Movement.decode(data, at)
  if type(data) ~= "string" or type(at) ~= "number" then return nil, "bad arguments" end
  if at < 1 or at + Gen4Movement.BYTES - 1 > #data then return nil, "out of range" end
  local out = {}
  local p = at
  while p + Gen4Movement.BYTES - 1 <= #data do
    local action = u16(data, p)
    local count = u16(data, p + 2)
    if action == nil then return nil, "truncated" end
    if action == Gen4Movement.END then return out end
    if #out >= Gen4Movement.LIMIT then return nil, "runaway" end
    out[#out + 1] = { action = action, count = count }
    p = p + Gen4Movement.BYTES
  end
  return nil, "unterminated"
end

-- WHERE an `applymovement`'s list is, given the decoded instruction and the
-- opcode's width.  The offset is measured from the byte AFTER the instruction,
-- which is `ctx->scriptPtr` at the moment the cartridge reads it, and it is a
-- SIGNED 32-bit displacement -- read unsigned, a backward one becomes four
-- billion and the list is looked for past the end of the file.
function Gen4Movement.addressOf(instruction, size)
  local rel = instruction and instruction.args and instruction.args[2]
  if not (rel and size) then return nil end
  if rel >= 0x80000000 then rel = rel - 0x100000000 end
  return instruction.at + size + rel
end

-- The object id an `applymovement` names.  0xFF is the player
-- (`LOCALID_PLAYER`, constants/scrcmd.h); everything else is an object
-- event's own `localID`.
Gen4Movement.PLAYER = 0xFF

-- ...AND TWO MORE THAT ARE NOT LOCAL IDS EITHER, out of the same three-line
-- block of constants/scrcmd.h:
--
--     #define LOCALID_CAMERA   0xF1
--     #define LOCALID_FOLLOWER 0xF2
--     #define LOCALID_PLAYER   0xFF
--
-- `GetLocalMapObjByIndex` (src/scrcmd.c) branches on all three before it
-- searches the object array at all: 0xF2 resolves to whichever live object is
-- wearing MOVEMENT_TYPE_FOLLOW_PLAYER and 0xF1 to the script camera.  Only
-- 0xFF was known here, so a movement applied to the follower searched for an
-- object with local id 242, found none, and dropped the movement -- with the
-- `waitmovement` behind it holding the input gate for ever.  That is the
-- whole of Verity Lakefront's arrival scene.
Gen4Movement.CAMERA = 0xF1
Gen4Movement.FOLLOWER = 0xF2

return Gen4Movement
