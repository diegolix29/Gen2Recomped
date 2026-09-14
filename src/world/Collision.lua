-- Movement permission checks: tile passability (from generated collision
-- data), map bounds, and entity occupancy.

local Runtime = require("src.mods.Runtime")

local Collision = {}

local DELTA = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
Collision.DELTA = DELTA

function Collision.target(cx, cy, dir)
  local d = DELTA[dir]
  return cx + d[1], cy + d[2]
end

-- entities: array of anything with cellX/cellY (and optional targetX/targetY
-- while mid-step, so nobody walks into a cell being entered).
-- e.passable entities never block (Yellow's companion Pikachu: the player
-- walks straight through and it re-trails, pikachu_follow.asm).
-- Big objects (Snorlax, Lapras doll) occupy a 2x2 footprint on the grid.
-- Exposed because a seam proxy has to answer this the same way its owner
-- does (OverworldState:updateCast): two spellings of "big" would put a
-- Snorlax's second cell on one side of a connection and not the other.
function Collision.isBig(e)
  return (e.big or (e.sprite and e.sprite.big)
          or (e.def and e.def.big)
          or (e.def and (e.def.sprite == "SPRITE_BIG_SNORLAX"
                         or e.def.sprite == "SPRITE_BIG_LAPRAS"))) and true
         or false
end

local function entityBlocks(e, cx, cy)
  local x, y = e.cellX, e.cellY
  if not (x and y) then return false end
  if Collision.isBig(e) then
    -- Origin cell is the top-left of the 2x2 (pret big object_event)
    return cx >= x and cx <= x + 1 and cy >= y and cy <= y + 1
  end
  if x == cx and y == cy then return true end
  if e.targetX == cx and e.targetY == cy then return true end
  return false
end

-- `e.of` is a SEAM PROXY'S owner: a body standing on a connected map, put
-- into these cells so that the two casts can see each other (see
-- OverworldState:updateCast).  A mover meeting its own proxy is meeting
-- itself, which is why the owner is tested alongside the entity.
function Collision.occupied(entities, cx, cy, ignore)
  for _, e in ipairs(entities) do
    if e ~= ignore and e.of ~= ignore and not e.passable then
      if entityBlocks(e, cx, cy) then
        return e
      end
    end
  end
  return nil
end

-- Tile-pair (elevation) collisions: certain tile pairs can't be crossed
-- in a given tileset (cave/forest ledges).  data set via Collision.load.
local tilePairs = nil

function Collision.load(data)
  tilePairs = data.field and data.field.tilePairs or { land = {}, water = {} }
end

-- WHICH PAIR LIST APPLIES, and whether its rows still need naming.
--
-- The global list is the running game's, keyed by the plain tileset name. An
-- ADOPTED tileset carries its own -- brought across from the cartridge it came
-- out of, already filtered to itself (see AdoptedTileset) -- and its rows must
-- NOT be name-matched: the map's tileset is `CAVERN@red` and every row in it
-- says `CAVERN`, which is the mismatch that made an imported Cerulean Cave's
-- ledges walkable from every side.
--
-- The record's own list wins where it has one. A Gen 2 build has no global
-- pair list at all -- Crystal's `field.lua` has no `tilePairs` key, because
-- Gen 2 fences elevation with collision classes instead -- so for these maps
-- there is nothing to fall back TO.
local function pairList(map, mover)
  local key = mover.surfing and "water" or "land"
  local own = map.tileset and map.tileset.tilePairs
  local ownList = own and own[key]
  if ownList and #ownList > 0 then return ownList, true end
  if not tilePairs then return nil, false end
  return tilePairs[key], false
end

local function pairBlocked(map, mover, sx, sy, tx, ty)
  local list, preFiltered = pairList(map, mover)
  if not list or #list == 0 then return false end
  local tileset = map.def.tileset
  local a = map:cellTile(sx, sy)
  local b = map:cellTile(tx, ty)
  for _, p in ipairs(list) do
    if (preFiltered or p.tileset == tileset)
       and ((p.a == a and p.b == b) or (p.a == b and p.b == a)) then
      return true
    end
  end
  return false
end

-- One-way (directional) walls: Gen2 collision classes $b0-$b7 / $c0-$c7.
-- They are LAND/WATER in CollisionPermissionTable, so the passability test
-- above waves them through; what actually fences them is
-- GetMovementPermissions (home/map.asm), which reads the class of the cell
-- the mover is on plus the four around it and clears the direction bit for
-- whichever side is walled.  Skipping that is why the player could walk off
-- the north ledge of an Ice Path cliff instead of being stopped at its lip.
--
-- Two halves, matching the ROM: the standing tile blocks stepping OUT over
-- its walled side, and the destination tile blocks stepping IN through it.
local OPPOSITE = { up = "down", down = "up", left = "right", right = "left" }

-- Collision.lua
local function sideWallBlocked(map, mover, dir, tx, ty)
  if not map.sideWallAt then return false end
  local out = map:sideWallAt(mover.cellX, mover.cellY)
  if out and out[dir] then return true end
  -- only examine the destination cell when it actually exists
  if not map:inBounds(tx, ty) then return false end
  local into = map:sideWallAt(tx, ty)
  return (into and into[OPPOSITE[dir]]) == true
end

local function verdict(map, entities, mover, dir, tx, ty)
  -- directional walls must be tested before the bounds short-circuit;
  -- otherwise an Ice Path cliff that faces the map edge is treated as a
  -- pure “bounds” case and the connection/edge-warp logic can fire.
  if sideWallBlocked(map, mover, dir, tx, ty) then
    return false, "tile"
  end
  if not map:inBounds(tx, ty) then
    return false, "bounds"
  end
  if not map:isWalkableCell(tx, ty) then
    if not (mover.surfing and map:isWaterCell(tx, ty)) then
      return false, "tile"
    end
  end
  -- THE OTHER HALF OF A GEN 3 MAP CELL.
  --
  -- Collision alone does not keep anyone out of the water in Hoenn: the sea
  -- is passable ground with an elevation of 1, and dry land is elevation 3.
  -- The cartridge refuses a step between two different non-zero elevations,
  -- and that is the whole of "you cannot walk onto water", "you cannot step
  -- off a cliff" and "the bridge and the river beneath it are different
  -- places".  Maps that carry no elevation -- every Gen 1 and Gen 2 map --
  -- answer nil here and nothing changes for them.
  if map.elevationBlocks and map:elevationBlocks(mover.elevation, tx, ty) then
    -- ...except getting OFF the water.  The cartridge turns exactly this
    -- mismatch into COLLISION_STOP_SURFING when the cell ahead is land the
    -- surfer can stand on, which is how you come ashore anywhere along a
    -- coast rather than only where the map says so.
    local landing = mover.surfing and map.isWaterCell
                    and map:isWalkableCell(tx, ty) and not map:isWaterCell(tx, ty)
    if not landing then
      return false, "elevation"
    end
  end
  -- THE ACRO BIKE TILES ARE WALLS TO EVERYONE ELSE.
  --
  -- Emerald's CheckAcroBikeCollision runs only where the ordinary collision
  -- came back NONE -- which is why it sits here, after the walkable and
  -- elevation tests -- and turns five behaviours into a collision code.  On
  -- foot, PlayerNotOnBikeMoving bumps on every one of them; the trick that
  -- passes each is the rider's, and the port has no Acro Bike yet, so today
  -- this is always a wall.  That IS the cartridge's answer for a player on
  -- foot, which is every player the port can currently be.
  if map.acroObstacleAt then
    local obstacle = map:acroObstacleAt(tx, ty)
    if obstacle and not Collision.acroTrickPasses(mover, obstacle, dir) then
      return false, "tile"
    end
  end
  if pairBlocked(map, mover, mover.cellX, mover.cellY, tx, ty) then
    return false, "tile"
  end
  if Collision.occupied(entities, tx, ty, mover) then
    return false, "entity"
  end
  return true
end

-- ONE TILE OF A TRAINER'S LINE OF SIGHT.
--
-- Asked for directly: "they also see me through each other".  They did, and
-- through the gym wall beside them too: the sight test was a facing, a shared
-- row or column and a pixel range, and nothing at all about what stood in
-- between.
--
-- The cartridge checks the gap tile by tile.  CheckPathBetweenTrainerAndPlayer
-- (0B3FB0) steps from the trainer towards the player, calls
-- GetCollisionFlagsAtCoords (092C8C) on each tile short of the player, and
-- gives up on `collision ~= 0 and (collision & ~1) ~= 0`.  That mask is the
-- whole rule, and it is worth spelling out because the flags are not the
-- collision CODES they look like (092C8C, read bottom-up):
--
--     1  the tile is outside the WATCHER'S OWN movement range
--     2  impassable metatile, off the map, or a wall facing this way
--     4  a different elevation from the one the watcher is standing at
--     8  another object event is standing there
--
-- ...and `& ~1` drops the first: a trainer sees past the edge of its own
-- wander box, which it must, or a trainer with a one-tile range could never
-- spot anybody.  The other three all stop the line, which is the sentence
-- above -- a wall, a ledge to another level, or ANOTHER NPC.
--
-- The player is never one of the tiles this is asked about: the walk covers
-- the tiles strictly between, and the far end is the player by construction
-- (the cartridge's own last step is a separate test for exactly that).
function Collision.sightBlocked(map, entities, watcher, dir, sx, sy, tx, ty)
  if sideWallBlocked(map, watcher, dir, tx, ty) then return true end
  if not map:inBounds(tx, ty) then return true end
  if not map:isWalkableCell(tx, ty) then return true end
  if pairBlocked(map, watcher, sx, sy, tx, ty) then return true end
  if map.elevationBlocks and map:elevationBlocks(watcher.elevation, tx, ty) then
    return true
  end
  if Collision.occupied(entities, tx, ty, watcher) then return true end
  return false
end

-- The whole gap, from the watcher to one tile short of the player.
--
-- `dist` is in cells and is at least 1; a trainer standing next to the player
-- has no gap to walk and is always clear, which is the cartridge's
-- `approachDistance - 1` loop count.
function Collision.sightPathClear(map, entities, watcher, dir, dist)
  local x, y = watcher.cellX, watcher.cellY
  for _ = 1, (tonumber(dist) or 0) - 1 do
    local tx, ty = Collision.target(x, y, dir)
    if Collision.sightBlocked(map, entities, watcher, dir, x, y, tx, ty) then
      return false
    end
    x, y = tx, ty
  end
  return true
end

-- Whether the mover is doing the Acro Bike trick that makes one of the five
-- obstacle behaviours passable.
--
-- BOTH MOVING TRICKS PASS A BUMPY SLOPE.  The rule here used to want a hop
-- for it, but the cartridge's two moving transitions agree:
-- WheelieHoppingMoving carries on through COLLISION_WHEELIE_HOP, and
-- WheelieMoving does too.  What neither of them passes is an ISOLATED rail --
-- the one-cell kind you can only reach with a sideways jump -- so those are a
-- wall to a rider coming at them, trick or no trick.
--
--   a bumpy slope is passable while hopping OR wheelieing
--   a full rail is ridden ALONG ITS AXIS, either way, and is a wall across it
--   an isolated rail is not entered by moving into it at all
--
-- `mover.acroBike` is what the Acro Bike sets and `mover.acroTrick` is the
-- trick in progress -- "wheelie" from the moment B goes down, "hop" only once
-- the wheelie has been held past its own threshold (see
-- OverworldState:updateAcroBike).
local ACRO_AXIS_DIRS = {
  vertical   = { up = true, down = true },
  horizontal = { left = true, right = true },
}

local function tricking(mover)
  return mover.acroTrick == "wheelie" or mover.acroTrick == "hop"
end

function Collision.acroTrickPasses(mover, obstacle, dir)
  if not (mover and mover.acroBike) then return false end
  if not obstacle then return true end
  if obstacle.isolated then return false end
  if not obstacle.axis then
    -- the bumpy slope: no axis to it, and either trick clears it
    return tricking(mover)
  end
  if not tricking(mover) then return false end
  local along = ACRO_AXIS_DIRS[obstacle.axis]
  return (along and along[dir]) == true
end

-- the movement.collision chain sees the boolean; a wrapper that flips it
-- rewrites ctx.reason to say why (the engine's own reasons are bounds /
-- tile / entity), so the hook stays a single-value middleware
local function passthrough(allowed) return allowed end

-- Returns true when the mover may step from (cx,cy) toward dir.
-- Out-of-bounds is blocked here; the OverworldController handles map
-- connections and edge warps before asking.  Per-step hot path: with an
-- empty chain this costs one table lookup and no ctx allocation.
function Collision.canMove(map, entities, mover, dir)
  local tx, ty = Collision.target(mover.cellX, mover.cellY, dir)
  local allowed, why = verdict(map, entities, mover, dir, tx, ty)
  if Runtime.wantsHook("movement.collision") then
    local ctx = { map = map, mover = mover, dir = dir,
                  fromX = mover.cellX, fromY = mover.cellY,
                  toX = tx, toY = ty, reason = why }
    allowed = Runtime.call("movement.collision", passthrough, allowed, ctx)
    why = ctx.reason
  end
  if allowed then return true end
  return false, why
end

return Collision
