-- THE GEN 4 PARTNER -- the character who walks behind you and crosses maps
-- with you (pokeplatinum src/scrcmd.c ScrCmd_SetMovementType +
-- ScrCmd_SetObjectFlagIsPersistent + SystemFlag_SetHasPartner, and
-- src/map_object.c sub_0206184C, which is where the crossing actually
-- happens).
--
-- WHY THIS EXISTS AT ALL, and it is not a nicety.  Platinum's opening does
-- not work without it.  Route 201's `Route201_SetRivalPartner` ends with
--
--     SetHasPartner
--     SetMovementType LOCALID_RIVAL, MOVEMENT_TYPE_FOLLOW_PLAYER
--     SetObjectFlagIsPersistent LOCALID_RIVAL, TRUE
--
-- and from that line Barry IS the follower.  Verity Lakefront's coord event
-- then addresses him as LOCALID_FOLLOWER (0xF2), not by his Route 201 local
-- id, and Verity Lakefront's own event file carries exactly ONE object -- a
-- signpost.  With no follower on the map that `ApplyMovement` walks nobody,
-- the `WaitMovement` behind it never returns, and the input gate stays shut
-- with nothing on screen.  Reported from play as "when we get to lake verity
-- dawn and professor are supposed to be there but they aren't", and named in
-- the log as
--
--   gen4 move: no object with localId 242 on L01 -- the movement is dropped
--   and whatever waits on it will wait forever (live localIds: 0)
--
-- WHAT THE CARTRIDGE DOES, in three separable pieces, because the scripts
-- set them separately and clear them separately:
--
--   * MOVEMENT_TYPE_FOLLOW_PLAYER (48) is what makes an object TRAIL.  It is
--     set by `setmovementtype`, which rewrites the LIVE actor -- a different
--     command from `setobjecteventmovementtype`, which rewrites the map's
--     stored template and is the one this port already had.  Thirty script
--     sites use the live one and none of them were lowered.
--   * MAP_OBJ_STATUS_PERSISTENT is what makes it SURVIVE A MAP CHANGE.
--     `sub_0206184C` deletes every object whose header id is not the new
--     map's unless this bit is on.
--   * FLAG_HAS_PARTNER (0x961) is the SAVE'S memory of it, which other
--     systems read -- and which `ClearHasPartner` alone ends, with no
--     movement-type change behind it.  Lake Verity Low Water does precisely
--     that, so a release keyed only on the movement type would leave Barry
--     trailing through the Cyrus scene.
--
-- Seven partners use this in the finished game -- Barry, Cheryl, Riley,
-- Marley, Mira, Buck and the Amity Square pet -- across 16 `sethaspartner`
-- and 22 `clearhaspartner` sites.
--
-- THE TRAIL ITSELF is PikachuFollower's, which is already proven in this
-- engine: the follower is sent to the cell the player is VACATING the frame
-- the player commits a step, not the frame it lands, so it rests exactly one
-- cell behind instead of two.  What is dropped is everything Yellow-specific
-- -- ledge hops, idle rolls, happiness, the emotion bubbles.
--
-- PASSABLE, and that is a deliberate departure.  The cartridge's partner is
-- a solid map object that shuffles out of the way when you walk into it; the
-- shuffle is a behaviour this engine has no seam for, and without it a solid
-- follower in a corridor is a softlock.  Walk into it and it simply trails
-- to the cell you vacated, exactly as Yellow's Pikachu does.

local GameVersion = require("src.core.GameVersion")
local Logger = require("src.core.Logger")

local Gen4Follower = {}

-- MOVEMENT_TYPE_FOLLOW_PLAYER, read off generated/movement_types.txt as a
-- zero-based enum (MOVEMENT_TYPE_NONE is 0, so line N is N - 1).
Gen4Follower.FOLLOW_PLAYER = 48
-- MOVEMENT_TYPE_FOLLOW_PARTNER_TRAINER -- the double-follow of a partner who
-- has their own partner.  Treated the same here; nothing in the game sets it
-- on a character this engine spawns, and trailing is trailing.
Gen4Follower.FOLLOW_PARTNER = 50

-- FLAG_HAS_PARTNER, from the same enum walk over generated/vars_flags.txt
-- that every other Gen 4 flag id in this port comes from, spelled the way
-- Gen4ScriptVM.flagName spells one so `checkflag` and this agree.
Gen4Follower.PARTNER_FLAG = "FLAG_G4_0961"

-- A synthetic object index for the respawned follower, clear of any map's
-- real objects (the largest object count on any Platinum map is 45).
local INDEX = 240

local function isGen4()
  local ok, yes = pcall(GameVersion.isGen4)
  return ok and yes
end

-- ------------------------------------------------------------------
-- the record
-- ------------------------------------------------------------------

-- What the follower needs to be rebuilt on a map that has never heard of it:
-- the art, the local id scripts address it by on its home map, and its home
-- map itself (so re-entering that map can hand the real object back rather
-- than standing a copy next to it).
function Gen4Follower.record(save)
  return save and save.gen4Follower or nil
end

function Gen4Follower.hasPartner(save)
  return not not (save and save.flags and save.flags[Gen4Follower.PARTNER_FLAG])
end

function Gen4Follower.setPartner(save, on)
  if not save then return end
  save.flags = save.flags or {}
  save.flags[Gen4Follower.PARTNER_FLAG] = on and true or false
end

-- ------------------------------------------------------------------
-- finding it
-- ------------------------------------------------------------------

-- The live follower, which is what `LOCALID_FOLLOWER` resolves to.  Marked on
-- the entity rather than derived from the def's movement type: a respawned
-- follower has no map template at all, and the cartridge's own lookup
-- (`MapObjMan_GetLocalMapObjByMovementType`) asks the LIVE object the same
-- way.
function Gen4Follower.current(ow)
  if not ow then return nil end
  for _, e in ipairs(ow.entities or {}) do
    if e.gen4Follower then return e end
  end
  return nil
end

-- ------------------------------------------------------------------
-- becoming, and ceasing to be, the follower
-- ------------------------------------------------------------------
--
-- These three take the SAVE rather than the game, because their caller is
-- `Gen4Commands`, which has no `Game` in scope at all -- it reaches everything
-- through `ctx.save` and `ctx.overworld`.  `onMapEntered` and `update` below
-- take the game, because rebuilding an NPC needs `game.data` and their caller
-- is `OverworldController`, where it is in scope.

local function defOf(entity)
  return entity and entity.def or nil
end

-- `setmovementtype <id>, MOVEMENT_TYPE_FOLLOW_PLAYER`.  The entity is already
-- on the map -- every one of the eight sites sets it on a character standing
-- in front of the player -- so this marks the actor and writes down enough to
-- rebuild it elsewhere.
function Gen4Follower.adopt(save, ow, entity)
  if not (entity and ow) then return end
  local def = defOf(entity)
  local previous = Gen4Follower.current(ow)
  if previous and previous ~= entity then previous.gen4Follower = nil end
  entity.gen4Follower = true
  entity.passable = true
  if not save then return end
  save.gen4Follower = {
    localId = def and def.localId,
    mapId = ow.map and ow.map.id,
    sprite = def and def.sprite,
    spriteName = def and def.spriteName,
    graphicsId = def and def.graphicsId,
    big = entity.big or nil,
    facing = entity.facing or "down",
    -- Not persistent until a script says so.  Barry's script says so on the
    -- next line, and Amity Square's pet never does -- it is a partner that
    -- stays on its one map.
    persistent = save.gen4Follower and save.gen4Follower.persistent or false,
  }
end

-- `setmovementtype <id>, <anything else>`, and `clearhaspartner`.  The ACTOR
-- stays where it is -- `ClearHasPartner` does not delete anybody, and on the
-- map that owns it the object event is still an object event -- so only the
-- trailing stops.
function Gen4Follower.release(save, ow)
  local live = Gen4Follower.current(ow)
  if live then
    live.gen4Follower = nil
    live.goalX, live.goalY = nil, nil
    -- A RESPAWNED follower has no business on the map once it stops
    -- following: it is a copy this engine stood there, not one of the map's
    -- own objects.  One that was adopted from a real object stays.
    if live.gen4FollowerSpawned and ow then
      for _, list in ipairs({ ow.npcs or {}, ow.entities or {} }) do
        for i = #list, 1, -1 do
          if list[i] == live then table.remove(list, i) end
        end
      end
    end
  end
  if ow then ow.gen4FollowTrail = nil end
  if save then save.gen4Follower = nil end
end

-- `setobjectflagispersistent <id>, <flag>` -- the bit that decides whether
-- the object survives a map change.  Only meaningful for the follower here:
-- every other object this engine spawns is rebuilt from its own map's
-- template anyway, so a persistence bit on one of those has nothing to do.
function Gen4Follower.setPersistent(save, ow, entity, on)
  local record = save and save.gen4Follower
  local live = Gen4Follower.current(ow)
  if not (record and live and entity == live) then return end
  record.persistent = on and true or false
end

-- ------------------------------------------------------------------
-- crossing a map seam
-- ------------------------------------------------------------------

-- The cell the follower appears on when it arrives on a new map: directly
-- behind the player, or the player's own cell when that is blocked -- it
-- trails out on the next step either way.  Same rule PikachuFollower uses,
-- and for the same reason: the player has just walked in, so the cell they
-- came from is the one the follower was standing on.
local function spawnCell(ow)
  local p = ow.player
  local dx = p.facing == "left" and 1 or p.facing == "right" and -1 or 0
  local dy = p.facing == "up" and 1 or p.facing == "down" and -1 or 0
  local bx, by = p.cellX + dx, p.cellY + dy
  if ow.map and ow.map:inBounds(bx, by) and ow.map:isWalkableCell(bx, by) then
    return bx, by
  end
  return p.cellX, p.cellY
end

local warnedNoArt = false

local function spawnFollower(game, ow, record)
  local NPC = require("src.world.NPC")
  local x, y = spawnCell(ow)
  if not record.sprite then
    -- No art means no follower, and standing an invisible body behind the
    -- player would be worse than none: it would answer `LOCALID_FOLLOWER`
    -- and walk scenes nobody can see.
    if not warnedNoArt then
      warnedNoArt = true
      Logger.warn("gen4 follower: the partner recorded on %s carries no "
                  .. "sprite, so it cannot be rebuilt on %s -- any scene "
                  .. "addressing LOCALID_FOLLOWER there will find nobody",
                  tostring(record.mapId), tostring(ow.map and ow.map.id))
    end
    return nil
  end
  local npc = NPC.new(game.data, ow.map.id, {
    index = INDEX,
    localId = record.localId,
    sprite = record.sprite,
    spriteName = record.spriteName,
    graphicsId = record.graphicsId,
    big = record.big,
    x = x, y = y,
    -- MOVEMENT_TYPE_NONE rather than FOLLOW_PLAYER: the template's movement
    -- type is what NPC:update reads to decide what to do when nobody is
    -- driving, and this file drives it -- a wander type here would fight the
    -- trail.  It is moot in practice: NPC.new reads the type through
    -- `constants.gen3MovementTypes`, which a Gen 4 cache does not carry at
    -- all, so every Gen 4 NPC already falls through to standing still.
    movementType = 0,
    direction = 1,
  })
  npc.facing = record.facing or "down"
  npc.gen4Follower = true
  npc.gen4FollowerSpawned = true
  npc.passable = true
  table.insert(ow.npcs, npc)
  table.insert(ow.entities, npc)
  return npc
end

-- Called from OverworldState:setMap, after rebuildEntities has stood the new
-- map's own cast up.
function Gen4Follower.onMapEntered(game, ow)
  if not (ow and ow.map) then return end
  ow.gen4FollowTrail = nil
  if not isGen4() then return end
  local save = game and game.save
  local record = save and save.gen4Follower
  if not record then return end

  -- THE MAP'S OWN OBJECT WINS.  Lake Verity Low Water carries Barry as a real
  -- object event and its entry scene addresses him by his local id there; so
  -- does Route 201 when you walk back onto it.  Standing a second copy beside
  -- the real one would put two Barrys on screen and let `LOCALID_FOLLOWER`
  -- pick the wrong one.
  if record.localId then
    for _, e in ipairs(ow.entities or {}) do
      local lid = e.localId or (e.def and e.def.localId)
      if lid == record.localId and not e.hidden then
        e.gen4Follower = true
        e.passable = true
        e.gen4FollowerSpawned = nil
        return
      end
    end
  end

  -- Not persistent means it does not cross: Amity Square's pet is a partner
  -- for one map and the cartridge deletes it at the door.
  if not record.persistent then
    save.gen4Follower = nil
    return
  end
  spawnFollower(game, ow, record)
end

-- A connection crossing translates every cell rather than rebuilding the map,
-- so the trail's remembered cell has to move with it -- the same rebase
-- PikachuFollower needs, and for the same reason.
function Gen4Follower.rebase(ow, dx, dy)
  local trail = ow and ow.gen4FollowTrail
  if not trail then return end
  trail.x, trail.y = trail.x + dx, trail.y + dy
  local npc = Gen4Follower.current(ow)
  if npc and npc.goalX then
    npc.goalX, npc.goalY = npc.goalX + dx, npc.goalY + dy
  end
end

-- ------------------------------------------------------------------
-- the trail
-- ------------------------------------------------------------------

function Gen4Follower.update(game, ow)
  if not (ow and ow.map and isGen4()) then return end
  local npc = Gen4Follower.current(ow)
  if not npc then return end
  local p = ow.player
  if not p then return end

  -- A SCRIPT OWNS THE FOLLOWER WHILE IT RUNS.  Every scene that addresses
  -- LOCALID_FOLLOWER walks it deliberately -- Verity Lakefront marches it
  -- north into the lake -- and a trail running underneath would drag it back
  -- toward the player mid-cutscene.  The record of where the player is stays
  -- current so the trail resumes without a lurch.
  local scripted = (ow.runner and ow.runner:isRunning())
                   or #(ow.scriptMoves or {}) > 0
  local trail = ow.gen4FollowTrail
  if not trail then
    trail = { x = p.cellX, y = p.cellY }
    ow.gen4FollowTrail = trail
  end
  if scripted then
    trail.x, trail.y = p.targetX or p.cellX, p.targetY or p.cellY
    npc.goalX, npc.goalY = nil, nil
    return
  end

  -- The step is handed over the frame the player COMMITS it, not the frame it
  -- lands: targetX/Y is the committed destination while a step is in flight
  -- and nil while standing, so the follower walks into the cell the player is
  -- vacating during that same step and rests exactly one cell behind.
  local destX = p.targetX or p.cellX
  local destY = p.targetY or p.cellY
  if destX ~= trail.x or destY ~= trail.y then
    npc.goalX, npc.goalY = trail.x, trail.y
    trail.x, trail.y = destX, destY
  end

  if npc.moving then return end
  if not npc.goalX then return end
  local gx, gy = npc.goalX, npc.goalY
  if npc.cellX == gx and npc.cellY == gy then
    npc.goalX, npc.goalY = nil, nil
    return
  end

  -- Fell more than a screen behind -- a warp, a scripted teleport, a scene
  -- that moved the player without a step.  Snap rather than walk a diagonal
  -- staircase across the map.
  local far = math.abs(npc.cellX - gx) + math.abs(npc.cellY - gy)
  if far > 6 then
    npc.cellX, npc.cellY = gx, gy
    npc.px, npc.py = gx * 16, gy * 16
    npc.goalX, npc.goalY = nil, nil
    return
  end

  local dir
  if npc.cellX < gx then dir = "right"
  elseif npc.cellX > gx then dir = "left"
  elseif npc.cellY < gy then dir = "down"
  else dir = "up" end
  npc.facing = dir
  npc.targetX = npc.cellX + (dir == "right" and 1 or dir == "left" and -1 or 0)
  npc.targetY = npc.cellY + (dir == "down" and 1 or dir == "up" and -1 or 0)
  -- The player's own step length, halved while more than one cell behind so a
  -- gap opened by a run or a scene closes again.
  local stepLen = p.stepFramesCur or p.stepFrames or 16
  if far > 1 then stepLen = math.max(1, math.floor(stepLen / 2)) end
  npc.stepFrames = stepLen
  npc.moving = true
  npc.progress = 0
  -- This frame's npc:update loop already ran (OverworldState:update walks
  -- self.npcs, then calls here), so burn the step's first frame now --
  -- otherwise the step costs a frame more than the player's and the follower
  -- trails a pixel further every tile.
  npc:update(ow.map, ow.entities)
end

-- The record has to follow the save, and a save written before this stage
-- simply has no partner -- which is correct for every point in the game
-- except the seven escort scenes.
function Gen4Follower.serialize(save)
  return save and save.gen4Follower or nil
end

return Gen4Follower
