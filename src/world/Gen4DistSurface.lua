-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE DISTORTION WORLD'S WALLS AND CEILINGS, and the camera that turns to show
-- them.
--
-- Reported from play: "you can't walk on the sideways and upside-down
-- surfaces" and "the camera doesn't change angle for each platform the way the
-- cartridge does".  Everything below is pret's pokeplatinum, transcribed:
--
--   * A FLOATING PLATFORM is a 32x32 attribute grid glued to a plane (see
--     src/import/Gen4DistWorld.lua for the format).  While the player stands
--     on one, `PlayerAvatar_GetStepDistortionWorldPos` (player_move.c) turns a
--     key into a step along that plane -- the four tables in STEP below -- and
--     `DistWorld_CheckCollisionOnCurrentFloatingPlatform` answers collision
--     out of the grid, with anything outside the platform a wall.
--   * A JUMP POINT (`FindFloatingPlatformJumpPointAt`) fires when the player
--     presses its direction while standing in its bounds: the player is moved
--     by its displacement over `steps` frames with the 16-entry hop arc
--     (`sFloatingPlatformJumpOffsets`), the sprite turns by its angle, and the
--     platform it names becomes current -- kind 4 hands the player back to
--     the ordinary map.
--   * A CAMERA ANGLE (`FindCameraAngleForPlayerPosition`) is matched the same
--     way, by position and pressed direction, and eases the camera towards
--     base + (angleX, angleY) over its step count (`DoCameraTransition`).  The
--     angles are 256ths of a turn (`DISTORTION_WORLD_CAMERA_PERSISTED_ANGLES_
--     FACTOR` 0x100 into a u16 angle); angleZ is 0 in every record.
--
-- Positions here are the cartridge's own: world TILES (x, y, z) with y the
-- altitude, and a floor's map tile is (x - offsetX, z - offsetZ) at height
-- (y - offsetAltitude) * 16 units -- the offsets of tw_arc's map-info file.

local DW = require("src.import.Gen4DistWorld")

local S = {}

local DIRS = { "up", "down", "left", "right" }
local DIR_NAME = { [0] = "up", "down", "left", "right" }

-- sDistortionStepDirection{Floor,WestWall,EastWall,Ceiling}, by key
S.STEP = {
  [0] = { up = { 0, 0, -1 }, down = { 0, 0, 1 }, left = { -1, 0, 0 }, right = { 1, 0, 0 } },
  [1] = { up = { 0, 1, 0 }, down = { 0, -1, 0 }, left = { 0, 0, 1 }, right = { 0, 0, -1 } },
  [2] = { up = { 0, 1, 0 }, down = { 0, -1, 0 }, left = { 0, 0, -1 }, right = { 0, 0, 1 } },
  [3] = { up = { 0, 0, 1 }, down = { 0, 0, -1 }, left = { -1, 0, 0 }, right = { 1, 0, 0 } },
}

-- PlayerAvatar_SetMovement_Turning: which way the SPRITE faces for a key, on a
-- surface whose sprite is rolled (west wall 90, east wall 270, ceiling 180)
S.FACE = {
  [0] = { up = "up", down = "down", left = "left", right = "right" },
  [1] = { up = "left", down = "right", left = "down", right = "up" },
  [2] = { up = "right", down = "left", left = "up", right = "down" },
  [3] = { up = "down", down = "up", left = "right", right = "left" },
}

-- Which way is "up" for a body standing on each kind of plane.
S.NORMAL = {
  [0] = { 0, 1, 0 }, [1] = { 1, 0, 0 }, [2] = { -1, 0, 0 }, [3] = { 0, -1, 0 },
}

-- sFloatingPlatformJumpOffsets, in units: the hop along the jump's axis
S.HOP = { 4, 6, 8, 10, 11, 12, 12, 12, 11, 10, 9, 8, 6, 4, 0, 0 }

-- DISTORTION_WORLD_CAMERA_BASE_ANGLE_X: -10750 of 65536, i.e. 59.05 degrees
-- down; the records add to it.
S.BASE_PITCH = 10750 * 360 / 65536
S.TURN_FRAMES = 4
S.TRACE = os.getenv and os.getenv("DWTRACE") ~= nil
S.NO_CAMERA = os.getenv and os.getenv("DWNOCAM") ~= nil
S.PROBE = os.getenv and os.getenv("DWPROBE") ~= nil
S.HOLES = os.getenv and os.getenv("DWHOLES") ~= nil

-- The camera's current offsets from its base, in 256ths of a turn.
S.cam = { x = 0, y = 0, fromX = 0, fromY = 0, toX = 0, toY = 0, t = 0, n = 0 }

local function dwData()
  local Game = package.loaded["src.core.Game"]
  return Game and Game.data and Game.data.gen4_distortion_world
end

-- The floor record for a map def, or nil when it is not a Distortion World
-- floor with anything for this module to do.
function S.floorFor(def)
  local dw = dwData()
  local h = def and tonumber(def.header)
  if not (dw and dw.maps and h) then return nil end
  local m = dw.maps[h] or dw.maps[tostring(h)]
  if not m then return nil end
  return m, dw
end

local surfableAttr   -- defined with the surface water below
local function inBounds(b, x, y, z)
  return x >= b.x and x <= b.x + b.sizeX and y >= b.y and y <= b.y + b.sizeY
     and z >= b.z and z <= b.z + b.sizeZ
end

local function groundOf(ow)
  local r = ow.map and ow.map.renderer
  return r and r.gen4Ground
end

-- THE ORDINARY MAP'S HEIGHT, kept as the cartridge keeps it: a map object
-- over a tile with no BDHC plate keeps the height it had.  The lifts' pockets
-- are exactly that -- 1F's is a 5x5 block of walkable, unplated tiles under a
-- platform one tile up -- and reading them as height 0 sank the player into
-- the platform's model, where the depth test hid them.
local function mapHeight(ow)
  local g = groundOf(ow)
  local p = ow.player
  if not (g and g.heightsAtPixel) then return ow.dwMapY or 0 end
  local ok, list = pcall(g.heightsAtPixel, g, p.cellX * 16 + 8, p.cellY * 16 + 8)
  if ok and type(list) == "table" and #list > 0 then
    local best, prev = list[1], ow.dwMapY
    if prev then
      for _, h in ipairs(list) do
        if math.abs(h - prev) < math.abs(best - prev) then best = h end
      end
    end
    ow.dwMapY = best
  elseif ow.dwMapY == nil then
    local ok2, h = pcall(g.groundY, g, p.cellX * 16 + 8, p.cellY * 16 + 8)
    ow.dwMapY = ok2 and tonumber(h) or 0
  end
  return ow.dwMapY
end

-- The player's world tile.  On a platform it is the tracked one; on the
-- ordinary map it is the cell plus the floor's offsets, at the ground's height.
function S.position(ow, m)
  local st = ow.dwSurface
  if st then return st.x, st.y, st.z end
  local p = ow.player
  local y = (m.offsetAltitude or 0) + math.floor(mapHeight(ow) / 16 + 0.5)
  return p.cellX + (m.offsetX or 0), y, p.cellY + (m.offsetZ or 0)
end

-- The template for (x, y, z, key) in a list, matched as the cartridge does --
-- first record whose direction and bounds both match.  The ordinary-map height
-- is read off the drawn ground, so it is allowed to be one tile out.
local function match(list, x, y, z, dir, loose)
  for _, t in ipairs(list or {}) do
    if DIR_NAME[t.playerDir] == dir and inBounds(t.bounds, x, y, z) then return t end
  end
  if loose then
    for _, dy in ipairs({ -1, 1 }) do
      for _, t in ipairs(list or {}) do
        if DIR_NAME[t.playerDir] == dir and inBounds(t.bounds, x, y + dy, z) then
          return t, dy
        end
      end
    end
  end
end

-- DoCameraTransition: ease from where the camera is to the record's angles.
local function wrap(d)
  d = d % 256
  if d > 128 then d = d - 256 end
  return d
end

function S.aimCamera(t)
  if S.NO_CAMERA then return end
  local c = S.cam
  local tx, ty = tonumber(t.angleX) or 0, tonumber(t.angleY) or 0
  if c.x == tx and c.y == ty then return end
  c.fromX, c.fromY = c.x, c.y
  c.toX, c.toY = c.x + wrap(tx - c.x), c.y + wrap(ty - c.y)
  -- the record's steps are 30-a-second field frames: twice as many here
  c.t, c.n = 0, math.max(1, (tonumber(t.steps) or 16) * 2)
end

-- What `Gen4View` adds to the field camera, in degrees, or nil when the
-- camera is at its base.
function S.cameraAngles()
  local c = S.cam
  if c.x == 0 and c.y == 0 then return nil end
  return { pitch = c.x * 360 / 256, yaw = c.y * 360 / 256 }
end

local function cellOf(m, x, z)
  return x - (m.offsetX or 0), z - (m.offsetZ or 0)
end

-- Where a body standing in a world tile has its FEET, in the map's own units:
-- the middle of the tile, pushed half a tile against the plane's normal.  On a
-- floor that is the tile's base (y * 16, which is how every floor here is
-- drawn); a west wall's face is the tile's west edge (measured off B1F's wall,
-- whose face draws at x = 11 * 16 for platform x 11), and the east wall and
-- the ceiling are the mirror images.
local function units(m, x, y, z, kind)
  local n = S.NORMAL[kind or 0] or S.NORMAL[0]
  return (x - (m.offsetX or 0)) * 16 + 8 - 8 * n[1],
         (y - (m.offsetAltitude or 0)) * 16 + 8 - 8 * n[2],
         (z - (m.offsetZ or 0)) * 16 + 8 - 8 * n[3]
end

-- FindAndPrepareNewCurrentFloatingPlatform: the first platform (of a kind, or
-- any) whose bounds hold the tile.
local function platformAt(m, x, y, z, kind)
  for i, p in ipairs(m.platforms or {}) do
    if (kind == nil or p.kind == kind) and inBounds(p.bounds, x, y, z) then return i, p end
  end
end

local function attrOn(dw, p, x, y, z)
  local grid = dw.attrs and (dw.attrs[p.attr] or dw.attrs[tostring(p.attr)])
  if not grid then return nil end
  return DW.attrAt(p, grid, x, y, z)
end

-- Entering a floor: the cartridge finds the platform under the player once,
-- when the floor loads (InitPlayer), and keeps it until a jump changes it.
function S.enter(ow)
  local def = ow.map and ow.map.def
  local m = S.floorFor(def)
  ow.dwSurface, ow.dwAnim, ow.dwPose = nil, nil, nil
  ow.dwMapY, ow.dwLastTile = nil, nil
  ow.dwFloor = def
  -- every entry is a new visit for the cast and the lifts (Gen4DistPlatforms)
  local Moving = package.loaded["src.world.Gen4DistPlatforms"]
  if Moving then Moving.refreshedFor, Moving.refreshedFlags = nil, nil end
  if not m then
    S.cam.x, S.cam.y, S.cam.n = 0, 0, 0
    return
  end
  local x, y, z = S.position(ow, m)
  -- a cascade up lands on B4F's ceiling, not on the floor beneath it
  -- DWSTART="x,y,z,kind" (a harness switch): start on that surface tile
  if os.getenv and os.getenv("DWSTART") and not S.startUsed then
    S.startUsed = true
    local sx, sy, sz, sk = os.getenv("DWSTART"):match("(%-?%d+),(%-?%d+),(%-?%d+),(%d+)")
    if sx then ow.dwPendingSurface = { x = tonumber(sx), y = tonumber(sy), z = tonumber(sz), kind = tonumber(sk) } end
  end
  local pend = ow.dwPendingSurface
  ow.dwPendingSurface = nil
  if pend then
    local i, p = platformAt(m, pend.x, pend.y, pend.z, pend.kind)
    if i then
      ow.dwSurface = { index = i, kind = p.kind, x = pend.x, y = pend.y, z = pend.z, moveDir = "left" }
      return
    end
  end
  for _, dy in ipairs({ 0, -1, 1 }) do
    local i, p = platformAt(m, x, y + dy, z)
    if i then
      ow.dwSurface = { index = i, kind = p.kind, x = x, y = y + dy, z = z,
                       moveDir = ow.player.facing or "down" }
      break
    end
  end
end

local function setPose(ow, m)
  local st, a = ow.dwSurface, ow.dwAnim
  if not (st or a) then
    local y = mapHeight(ow)
    local carry = ow.dwCarry
    ow.dwPose = { y = y + (carry and carry[2] or 0), nx = 0, ny = 1, nz = 0 }
    return
  end
  local ux, uy, uz, nx, ny, nz
  if a then
    local f = a.t / a.n
    if f > 1 then f = 1 end
    local ax, ay, az = units(m, a.fx, a.fy, a.fz, a.fromKind)
    local bx, by, bz = units(m, a.tx, a.ty, a.tz, a.toKind ~= 4 and a.toKind or 0)
    ux, uy, uz = ax + (bx - ax) * f, ay + (by - ay) * f, az + (bz - az) * f
    if a.jump then
      local hop = S.HOP[math.min(#S.HOP, math.floor(a.t * 16 / a.n) + 1)] or 0
      if a.inverted then hop = -hop end
      if a.axis == 0 then ux = ux + hop elseif a.axis == 2 then uz = uz + hop else uy = uy + hop end
    end
    local n0, n1 = S.NORMAL[a.fromKind] or S.NORMAL[0], S.NORMAL[a.toKind] or S.NORMAL[0]
    nx, ny, nz = n0[1] + (n1[1] - n0[1]) * f, n0[2] + (n1[2] - n0[2]) * f, n0[3] + (n1[3] - n0[3]) * f
  else
    ux, uy, uz = units(m, st.x, st.y, st.z, st.kind)
    local n = S.NORMAL[st.kind] or S.NORMAL[0]
    nx, ny, nz = n[1], n[2], n[3]
  end
  -- a raft carrying the player (Gen4DistPlatforms, EVENT_CMD_MOVE_PLATFORM)
  local carry = ow.dwCarry
  if carry then ux, uy, uz = ux + carry[1], uy + carry[2], uz + carry[3] end
  -- the ordinary map, standing still, needs nothing from here
  if not a and st and st.kind == 0 then
    ow.dwPose = { y = uy, nx = 0, ny = 1, nz = 0 }
  else
    ow.dwPose = { y = uy, nx = nx, ny = ny, nz = nz }
    -- WHICH WAY THE BODY IS GOING, in the world: the step the held key makes
    -- on this plane.  The renderer turns it into a sprite facing on screen
    -- (Gen4Ground:freeEntity), because the cartridge's turning tables only
    -- read right from the cartridge's own camera angle -- from any other view
    -- "walked left, faces right" (reported from play).
    local k = st and st.kind or (a and a.toKind) or 0
    local d = S.STEP[k] and S.STEP[k][(a and a.dir) or (st and st.moveDir) or "down"]
    if d and k ~= 0 and k ~= 4 then
      ow.dwPose.mx, ow.dwPose.my, ow.dwPose.mz = d[1], d[2], d[3]
      ow.dwPose.entity = ow.player
    end
  end
  local p = ow.player
  p.px, p.py = ux - 8, uz - 8
end

-- Called every frame before the player moves.
function S.update(ow)
  -- the cartridge's field runs at 30 frames a second: its per-frame motion
  -- (cascades, events, rides) steps on every other engine frame
  ow.dwDsFrame = not ow.dwDsFrame
  local def = ow.map and ow.map.def
  if ow.dwFloor ~= def then S.enter(ow) end
  local m, dw = S.floorFor(def)
  local Camera = package.loaded["src.render.Gen4Camera"]
  local View = package.loaded["src.render.Gen4View"]
  if Camera and Camera.setForceField3d then
    local st, an = ow.dwSurface, ow.dwAnim
    local onPlane = (st and st.kind ~= 0) or (an and an.jump and (an.fromKind ~= 0 or (an.toKind ~= 0 and an.toKind ~= 4)))
    Camera.setForceField3d(m and (onPlane and "surface" or true) or nil)
  end
  if View then View.surfaceAngles = m and S.cameraAngles() or nil end
  local ground = groundOf(ow)
  if not m then
    if ground then ground.surfaceBaseY = nil end
    return
  end
  -- THE SKY (Gen4DistSkyView): its clouds and darkness, on the cartridge's frames
  local Sky = require("src.render.Gen4DistSkyView")
  if not Sky.state or Sky.state.def ~= def then
    Sky.enter(def, require("src.world.Gen4DistPlatforms").progress())
  end
  if ow.dwDsFrame then
    local py = (ow.dwPose and ow.dwPose.y) or (ground and ground.surfaceBaseY)
    Sky.frame(py and (py + (m.offsetAltitude or 0) * 16) or nil)
  end
  local c = S.cam
  if c.n > 0 then
    c.t = c.t + 1
    local f = c.t / c.n
    if f >= 1 then f = 1; c.n = 0 end
    c.x = c.fromX + (c.toX - c.fromX) * f
    c.y = c.fromY + (c.toY - c.fromY) * f
    if c.n == 0 then c.x, c.y = c.toX % 256, c.toY % 256 end
  end
  if ow.dwCascade then
    S.tickCascade(ow, m)
    -- the walk off the end runs as ordinary steps
    if ow.dwCascade and not ow.dwCascade.away then return end
  end
  local a = ow.dwAnim
  if a then
    a.t = a.t + 1
    if a.t >= a.n then
      ow.dwAnim = nil
      if a.toKind == 4 or a.toIndex == nil then
        ow.dwSurface = nil
      else
        ow.dwSurface = { index = a.toIndex, kind = a.toKind }
      end
      local st = ow.dwSurface
      local p = ow.player
      if st then st.x, st.y, st.z = a.tx, a.ty, a.tz end
      if st and p.surfing then
        local plat = m.platforms[st.index]
        if plat and not surfableAttr(attrOn(dw, plat, a.tx, a.ty, a.tz)) then p.surfing = false end
      end
      p.cellX, p.cellY = cellOf(m, a.tx, a.tz)
      p.px, p.py = p.cellX * 16, p.cellY * 16
      if a.finalFace then
        p.facing = a.finalFace
        if st then
          for _, k in ipairs(DIRS) do
            if S.FACE[st.kind][k] == a.finalFace then st.moveDir = k end
          end
        end
      elseif st and a.dir then
        st.moveDir = a.dir
        p.facing = S.FACE[st.kind][a.dir]
      end
    end
  end
  if ow.dwSurface and ow.dwSurface.hold and ow.dwSurface.hold > 0 then
    ow.dwSurface.hold = ow.dwSurface.hold - 1
  end
  setPose(ow, m)
  if S.HOLES and not S.holesDone then
    -- every walkable cell with no BDHC plate and no prop within a tile
    S.holesDone = true
    local g, def = ground, ow.map.def
    local covered = {}
    for _, pr in ipairs(def.gen4RuntimeProps or {}) do
      local cx, cz = math.floor(((pr.x or 0)) / 16), math.floor(((pr.z or 0) + 6) / 16)
      for dz = -2, 2 do for dx = -2, 2 do covered[(cx + dx) .. "," .. (cz + dz)] = true end end
    end
    local holes = {}
    for yy = 0, (def.height or 0) - 1 do
      for xx = 0, (def.width or 0) - 1 do
        if ow.map:isWalkableCell(xx, yy) then
          local ok, list = pcall(g.heightsAtPixel, g, xx * 16 + 8, yy * 16 + 8)
          local okb, b = pcall(g.behaviourAt, g, xx, yy)
          local jump = okb and b and b >= 0x5A and b <= 0x5D
          if ok and #list == 0 and not jump and not covered[xx .. "," .. yy] then holes[#holes + 1] = xx .. "," .. yy end
        end
      end
    end
    print(("[holes] %s %d: %s"):format(def.id, #holes, table.concat(holes, " ")))
  end
  local nprops = #(ow.map.def.gen4RuntimeProps or {})
  if os.getenv("DWOBJS") and S.objsDone ~= nprops then
    S.objsDone = nprops
    local g = ground
    local grid = g.grid
    for cy = 0, grid.height - 1 do for cx = 0, grid.width - 1 do
      local land = grid.land[cy * grid.width + cx + 1]
      local record = g.terrain and g.terrain.chunks[land]
      local ok, list = pcall(g.objectsFor, g, land, record)
      for _, o in ipairs(ok and list or {}) do
        local okb, b = pcall(g.building, g, o.model, o.archive)
        print(("[obj] chunk %d,%d land %s model %s arch %s at %.0f,%.0f,%.0f loaded=%s"):format(cx, cy, tostring(land),
          tostring(o.model), tostring(o.archive), (o.x or 0) + cx * 512 + 256, o.y or 0, (o.z or 0) + cy * 512 + 256, tostring(okb and b ~= nil)))
      end
    end end
  end
  if S.PROBE and not S.probed then
    S.probed = true
    local g = ground
    for yy = ow.player.cellY - 10, ow.player.cellY + 14 do
      local row = {}
      for xx = ow.player.cellX - 6, ow.player.cellX + 6 do
        local ok, h = pcall(g.groundY, g, xx * 16 + 8, yy * 16 + 8)
        local walk = ow.map:isWalkableCell(xx, yy)
        local okb, b = pcall(g.behaviourAt, g, xx, yy)
        local okl, l = pcall(g.heightsAtPixel, g, xx * 16 + 8, yy * 16 + 8)
        local hs = (okl and #l > 0) and tostring(math.floor(l[1])) or "-"
        row[#row + 1] = (walk and "" or "#") .. ((okb and b and b ~= 0) and ("%02x"):format(b) or "") .. "/" .. hs
      end
      print(("[probe] %3d %s"):format(yy, table.concat(row, " ")))
    end
  end
  if S.TRACE then
    local st = ow.dwSurface
    local line = st and ("surface %d kind %d at %d,%d,%d move %s"):format(st.index, st.kind,
      st.x or -1, st.y or -1, st.z or -1, tostring(st.moveDir))
      or ("map cell %d,%d y %d"):format(ow.player.cellX, ow.player.cellY, select(2, S.position(ow, m)))
    line = line .. (" cam %.1f,%.1f"):format(S.cam.x, S.cam.y)
    if line ~= S.lastTrace then print("[dwsurface] " .. line); S.lastTrace = line end
  end
  if ground then ground.surfaceBaseY = ow.dwPose and ow.dwPose.y or nil end
  -- the elevator shuttles and the B2F rafts follow their own clock
  local Moving = require("src.world.Gen4DistPlatforms")
  -- the first frame on a floor only records where the player stands; events
  -- fire from stepEnded (the overworld's onStepComplete) and from a surface
  -- step landing
  if ow.dwLastTile == nil and not ow.dwAnim then
    local x, y, z = S.position(ow, m)
    ow.dwLastTile = ("%d,%d,%d"):format(x, y, z)
  end
  Moving.update(ow, m, dw)
end

-- HandleEventAt where a step ENDS (DistWorld_HandlePlayerPositionChanged)
function S.stepEnded(ow)
  local m, dw = S.floorFor(ow.map and ow.map.def)
  if not m then return end
  local x, y, z = S.position(ow, m)
  local key = ("%d,%d,%d"):format(x, y, z)
  if ow.dwLastTile == key then return end
  ow.dwLastTile = key
  require("src.world.Gen4DistPlatforms").onPosition(ow, m, dw, x, y, z)
end

-- EventCmdMovePlatform_EndMovement: the player's tile moves by the raft's
-- offset, and the platform under them is found again (any kind).
function S.relocate(ow, dx, dy, dz)
  local m = S.floorFor(ow.map and ow.map.def)
  if not m then return end
  local x, y, z = S.position(ow, m)
  x, y, z = x + dx, y + dy, z + dz
  local p = ow.player
  p.cellX, p.cellY = cellOf(m, x, z)
  p.px, p.py = p.cellX * 16, p.cellY * 16
  local i, plat = platformAt(m, x, y, z)
  if i then
    local st = ow.dwSurface or {}
    st.index, st.kind, st.x, st.y, st.z = i, plat.kind, x, y, z
    st.moveDir = st.moveDir or p.facing
    ow.dwSurface = st
  else
    ow.dwSurface = nil
  end
  ow.dwLastTile = ("%d,%d,%d"):format(x, y, z)
end

-- MOVEMENT_ACTION_JUMP_DISTORTION_WORLD_*: the two-tile hop, on the plane the
-- player is on.  Returns true when it started.
function S.hop(ow, dx, dz, face)
  local m = S.floorFor(ow.map and ow.map.def)
  if not m then return false end
  local x, y, z = S.position(ow, m)
  local st = ow.dwSurface
  local kind = st and st.kind or 0
  local tx, tz = x + dx, z + dz
  local i = platformAt(m, tx, y, tz, st and kind or nil)
  ow.dwAnim = { jump = true, fx = x, fy = y, fz = z, tx = tx, ty = y, tz = tz,
                t = 0, n = 48, axis = 1, inverted = false,   -- 24 field frames
                fromKind = kind, toKind = st and kind or 4, toIndex = st and (i or st.index) or nil,
                finalFace = face, dir = face }
  local p = ow.player
  p.facing = face
  p.moving, p.marching, p.progress = true, true, 0
  p.stepFramesCur = ow.dwAnim and ow.dwAnim.n or 16
  return true
end

local function startStep(ow, m, st, dir, nx, ny, nz, frames)
  local p = ow.player
  ow.dwAnim = { fx = st.x, fy = st.y, fz = st.z, tx = nx, ty = ny, tz = nz,
                t = 0, n = frames, fromKind = st.kind, toKind = st.kind,
                toIndex = st.index, dir = dir }
  p.moving, p.marching, p.progress = true, true, 0
  p.stepFramesCur = frames
  p.facing = S.FACE[st.kind][dir]
end

local function startJump(ow, m, j, x, y, z, dir)
  local p = ow.player
  local st = ow.dwSurface
  local steps = math.max(1, tonumber(j.steps) or 16) * 2   -- field frames -> engine frames
  ow.dwAnim = {
    jump = true, fx = x, fy = y, fz = z,
    tx = x + (j.displaceX or 0), ty = y + (j.displaceY or 0), tz = z + (j.displaceZ or 0),
    t = 0, n = steps, axis = j.axis, inverted = (j.inverted or 0) ~= 0,
    fromKind = st and st.kind or 0, toKind = j.targetKind,
    toIndex = (j.targetKind ~= 4 and j.targetIndex and j.targetIndex < 0xFFFF)
              and (j.targetIndex + 1) or nil,
    finalFace = DIR_NAME[j.finalDir], dir = dir,
  }
  -- from the ordinary map the walk-on-spot is the player's own
  if not st then
    ow.dwSurface = nil
  end
  p.moving, p.marching, p.progress = true, true, 0
  p.stepFramesCur = steps
  local ok, Sound = pcall(require, "src.core.Sound")
  if ok and Sound and Sound.play then pcall(Sound.play, require("src.core.Game").data, "Jump") end
end

-- The direction-key hook.  Returns nil to let the ordinary overworld handle
-- the press, or true when this module has taken it.
function S.input(ow, input)
  local def = ow.map and ow.map.def
  if ow.dwFloor ~= def then S.enter(ow) end
  local m, dw = S.floorFor(def)
  if not m then return nil end
  local p = ow.player
  local st = ow.dwSurface
  if ow.dwAnim then return true end
  if p.moving or p.inputLocked then return st and true or nil end
  local dir
  for _, d in ipairs(DIRS) do
    if input:isDown(d) then dir = d; break end
  end
  if not dir then return st and true or nil end
  -- on the ground, the same orbit-turned direction the ordinary walk takes, so
  -- a jump point or camera record is matched against the step actually made;
  -- on a wall or ceiling the keys are the cartridge's own (STEP tables)
  if not (st and st.kind ~= 0) and ow.walkDirection then dir = ow:walkDirection(dir) end
  if st then
    if st.hold and st.hold > 0 then return true end
    if st.moveDir ~= dir then
      -- turning in place (AVATAR_MOVE_STATE_TURNING) compares the MOVING
      -- direction on a wall, not the sprite's facing
      st.moveDir = dir
      p.facing = S.FACE[st.kind][dir]
      st.hold = S.TURN_FRAMES
      return true
    end
  elseif p.facing ~= dir then
    return nil
  end
  local x, y, z = S.position(ow, m)
  -- HandleGhostPropTriggerAt runs on the same press, before the camera
  require("src.world.Gen4DistPlatforms").ghostTrigger(ow, m, x, y, z, dir)
  local cam, dyc = match(m.cameras, x, y, z, dir, not st)
  if cam then S.aimCamera(cam) end
  if S.cascade(ow, m, x, y, z, dir) then return true end
  local jump, dyj = match(m.jumps, x, y, z, dir, not st)
  if jump then
    startJump(ow, m, jump, x, y + (dyj or 0), z, dir)
    return true
  end
  if not st then
    local Moving = require("src.world.Gen4DistPlatforms")
    if Moving.teleport(ow, m, x, z, dir) then return true end
    -- the overlay's own wall beyond a teleport tile
    local d = S.STEP[0][dir]
    if Moving.blocked(ow.map.def, m, p.cellX + d[1], p.cellY + d[3]) then
      if (ow.bumpCooldown or 0) <= 0 then
        pcall(function() require("src.core.Sound").play(require("src.core.Game").data, "Collision") end)
        ow.bumpCooldown = 16
      end
      return true
    end
    return nil
  end
  local d = S.STEP[st.kind][dir]
  local nx, ny, nz = x + d[1], y + d[2], z + d[3]
  local plat = m.platforms[st.index]
  local attr = plat and attrOn(dw, plat, nx, ny, nz)
  if attr == nil and st.kind == 0 then
    -- PlayerAvatar_CheckStartMoveInternal: on a FLOOR, a tile past this grid
    -- may belong to the next floor platform, and then it is that one's answer
    local i, q = platformAt(m, nx, ny, nz, 0)
    if i then
      attr = attrOn(dw, q, nx, ny, nz)
      if DW.passable(attr) then st.index = i end
    end
  end
  -- water on a surface is a wall to a walker (PlayerAvatar_WillBeOnWaterDistortion)
  if DW.passable(attr) and not p.surfing and surfableAttr(attr) then attr = 0x8000 end
  if not DW.passable(attr) then
    p.facing = S.FACE[st.kind][dir]
    if (ow.bumpCooldown or 0) <= 0 then
      pcall(function() require("src.core.Sound").play(require("src.core.Game").data, "Collision") end)
      ow.bumpCooldown = 16
    end
    return true
  end
  startStep(ow, m, st, dir, nx, ny, nz, p.stepFrames or 16)
  return true
end

-- The screen roll for a body standing along (nx, ny, nz), given where the
-- feet project: the angle from screen-up to the projected normal.
function S.roll(project, gx, gy, gz, pose)
  if not (pose and pose.nx) then return 0 end
  if pose.ny > 0.999 then return 0 end
  local ax, ay = project(gx, gy, gz)
  local bx, by = project(gx + pose.nx * 16, gy + pose.ny * 16, gz + pose.nz * 16)
  if not (ax and bx) then return 0 end
  local dx, dy = bx - ax, by - ay
  if dx * dx + dy * dy < 1e-6 then return 0 end
  return (math.atan2 or math.atan)(dx, -dy)
end


-- ------------------------------------------------- water on a surface

function surfableAttr(attr)
  local b = attr and (attr % 0x100)
  return b ~= nil and require("src.world.Map").G4_SURFABLE[b] == true
end

-- the tile ahead on the current surface, for the key the player faces with
local function surfaceAhead(ow, m, dw)
  local st = ow.dwSurface
  if not st then return nil end
  local d = S.STEP[st.kind][st.moveDir or "up"]
  local x, y, z = st.x + d[1], st.y + d[2], st.z + d[3]
  local plat = m.platforms[st.index]
  return plat and attrOn(dw, plat, x, y, z), x, y, z
end

-- Field_TileBehaviorToScript's Surf row, asked of the platform's own grid
-- (PlayerAvatar_GetDistortionCurrTileBehaviour): facing water on a wall or a
-- ceiling with a Surfer and the badge runs FIELD_MOVES 4 like any shore.
function S.pressA(ow)
  local m, dw = S.floorFor(ow.map and ow.map.def)
  if not (m and ow.dwSurface) or ow.player.surfing then return false end
  local attr = surfaceAhead(ow, m, dw)
  if not surfableAttr(attr) then return false end
  local Game = package.loaded["src.core.Game"]
  local F = require("src.world.Gen4FieldMoves")
  if not (Game and F.partyMember(Game.data, Game.save, "SURF")) then return false end
  local TS = require("src.world.Gen4TileScripts")
  local rows = TS.compile(Game.data, "field_moves", 4)
  if not rows then return false end
  ow.runner:run(rows, { mapId = ow.map.id })
  return true
end

-- UseSurf on a surface: the hop onto the water ahead, along the plane
function S.surfMount(ow)
  local m = S.floorFor(ow.map and ow.map.def)
  local st = ow.dwSurface
  if not (m and st) then return false end
  local d = S.STEP[st.kind][st.moveDir or "up"]
  ow.player.surfing = true
  ow.dwAnim = { jump = true, fx = st.x, fy = st.y, fz = st.z,
    tx = st.x + d[1], ty = st.y + d[2], tz = st.z + d[3], t = 0, n = 16, axis = 1,
    fromKind = st.kind, toKind = st.kind, toIndex = st.index, dir = st.moveDir }
  local p = ow.player
  p.moving, p.marching, p.progress = true, true, 0
  p.stepFramesCur = ow.dwAnim and ow.dwAnim.n or 16
  return true
end

-- -------------------------------------------- the waterfall cascades

-- DistWorld_HandlePlayerMoved: B4F's and B5F's waterfall, pressed into facing
-- right from x 104 at z 76..79, rides the player down to B5F (EVENT_CMD_
-- CASCADE_DOWN) or up to B4F's ceiling (CASCADE_UP).  The overlay's own
-- numbers (sMapEventCmdParamsB4F/B5F_Waterfall, CmdRunDataCascadeBase_*):
--   * final offset 0x298 UNITS (FX32_ONE * the field, not a tile count),
--     the next floor loaded at 0x15 (down) / 0x14 (up) tiles, the player
--     set down 0x2A tiles from where it set off
--   * posDelta 1 unit a frame down, 8 up -- HALVED for the opening sprite
--     turn (32 frames down, 4 up)
--   * the camera: down, (245, 239) over 72 frames at 20 tiles, back to its
--     base over 32 at 36 tiles; up, (55, 240) over 16 at 20 tiles
-- All in the cartridge's 30-a-second field frames.
S.CASCADES = {
  -- B4F's ceiling down to B5F's pool (sMapEventCmdParamsB4F_Waterfall,
  -- EventCmdCascadeDown_*): turned +90 over the 32-frame opening, -32 with the
  -- first camera (72 frames) and back +32 with the second (31), +90 over the
  -- last 16; facing left, up 32 frames after the first camera, left again at
  -- the second; then two tiles west, slow then slower
  [577] = { x = 104, y = 170, z0 = 76, z1 = 79, dir = -1, final = 0x298, load = 0x15 * 16, fix = 0x2A,
            delta = 1, turn = 32, to = 579, startRoll = 180, startTurn = 90,
            bob = 1024 / 4096, endTurn = 90, endTurnSteps = 16,
            startFace = "left", endFace = "left", faceAfter = { frames = 32, face = "up" },
            cams = { { at = -20, x = 245, y = 239, steps = 72, rotate = -32, rotateSteps = 72, bobFix = -4 },
                     { at = -36, x = 0, y = 0, steps = 32, rotate = 32, rotateSteps = 31, face = "left", bobFix = 4 } },
            liftFlag = 7,   -- DIST_WORLD_PLATFORM_FLAG_B5F_1
            moveAway = { { dir = "left", frames = 16 }, { dir = "left", frames = 32 } } },
  -- B5F's pool up to B4F's ceiling (EventCmdCascadeUp_*): -90 over the
  -- 4-frame opening and -90 over the last 2, facing right; the camera at 20
  -- tiles; then three tiles west on the ceiling at 8, 4 and 2 units a frame
  -- (MOVEMENT_ACTION_151, 147, 115)
  [579] = { x = 104, y = 128, z0 = 76, z1 = 79, dir = 1, final = 0x298, load = 0x14 * 16, fix = 0x2A,
            delta = 8, turn = 4, to = 577, ceiling = true, startRoll = 0, startTurn = -90,
            bob = 512 / 4096, endTurn = -90, endTurnSteps = 2,
            startFace = "right", endFace = "right",
            cams = { { at = 20, x = 55, y = 240, steps = 16 } },
            moveAway = { { dir = "left", frames = 2 }, { dir = "left", frames = 4 }, { dir = "left", frames = 8 } } },
}

function S.cascade(ow, m, x, y, z, dir)
  local c = S.CASCADES[tonumber(ow.map.def.header)]
  -- the height off the ordinary map's ground may be a tile out (the pool's
  -- surface reads 129 where the overlay names 128)
  if not (c and dir == "right" and x == c.x and math.abs(y - c.y) <= 1 and z >= c.z0 and z <= c.z1) then return false end
  if not ow.player.surfing then return false end
  -- the world height in units, which carries across the change of floor
  local startY = ((ow.dwPose and ow.dwPose.y) or ((c.y - (m.offsetAltitude or 0)) * 16)) + (m.offsetAltitude or 0) * 16
  local cs = { c = c, t = 0, off = 0, z = z, worldY = startY, cam = 1,
                rotFinal = c.startRoll, rotCur = c.startRoll, rotLeft = 0, bobFix = 0 }
  ow.dwCascade = cs
  S.cascadeRotate(cs, c.startTurn, c.turn)
  ow.player.inputLocked = true
  ow.player.facing = c.startFace
  -- SEQ_SE_PL_FW463, the rushing water, for the length of the ride
  cs.sound = S.cascadeSound("SEQ_SE_PL_FW463")
  if not cs.sound then
    pcall(function() require("src.core.Sound").play(package.loaded["src.core.Game"].data, "Waterfall") end)
  end
  return true
end

local function findDef(header)
  local Game = package.loaded["src.core.Game"]
  for id, def in pairs(Game.data.maps or {}) do
    if type(def) == "table" and tonumber(def.header) == header and not def.sourceId then return id, def end
  end
end

-- the overlay's sprite rotator (RotateMapObject): from where the last turn
-- ended, `angle` degrees over `steps` frames
local function rotate(cs, angle, steps)
  cs.rotCur = cs.rotFinal
  cs.rotDelta = angle / steps
  cs.rotLeft = steps
  cs.rotFinal = cs.rotFinal + angle
end

-- (fx >> 4) / FX32_ONE on a signed offset in units: whole tiles toward zero
local function tilesOf(v)
  local q = math.floor(v * 256)
  if q >= 0 then return math.floor(q / 4096) end
  return -math.floor(-q / 4096)
end

-- a forced step on the ordinary map (CascadeDown_MoveAway's walks)
local function forceWalk(ow, dir, frames)
  local p = ow.player
  local tx, ty = require("src.world.Collision").target(p.cellX, p.cellY, dir)
  p.facing = dir
  p.targetX, p.targetY = tx, ty
  p.moving, p.progress = true, 0
  p.stepFramesCur = frames
end

local function soundSe(key)
  local G = package.loaded["src.core.Game"]
  local ok, src = pcall(function() return require("src.core.Sound").playSe(G.data, key) end)
  return ok and src or nil
end

-- the walk off the end (EventCmdCascadeDown/Up_MoveAway), a step at a time
local function tickMoveAway(ow, m)
  local cs = ow.dwCascade
  local p = ow.player
  if p.moving or ow.dwAnim then return end
  local nextStep = cs.away[cs.awayAt]
  if not nextStep then
    ow.dwCascade = nil
    p.inputLocked = false
    return
  end
  cs.awayAt = cs.awayAt + 1
  local st = ow.dwSurface
  if st then
    -- on B4F's ceiling: ceiling "left" is world -x (S.STEP[3])
    local d = S.STEP[st.kind][nextStep.dir]
    startStep(ow, m, st, nextStep.dir, st.x + d[1], st.y + d[2], st.z + d[3], nextStep.frames * 2)
  else
    forceWalk(ow, nextStep.dir, nextStep.frames * 2)
  end
end

-- one cartridge frame of the ride
local function cascadeFrame(ow, m)
  local cs = ow.dwCascade
  local c = cs.c
  local p = ow.player
  if cs.away then return tickMoveAway(ow, m) end
  cs.t = cs.t + 1
  -- CmdRunDataCascadeBase_Update: the offset, then the bob
  local step = c.delta * ((cs.t <= c.turn) and 0.5 or 1)
  cs.off = math.min(c.final, cs.off + step)
  if cs.bobDelta then
    cs.bob = cs.bob + cs.bobDelta
    if cs.bob >= 4 then cs.bob, cs.bobDelta = 4, -cs.bobDelta
    elseif cs.bob <= 1 then cs.bob, cs.bobDelta = 1, -cs.bobDelta end
  end
  -- the rotator
  if cs.rotLeft > 0 then
    cs.rotCur = cs.rotCur + cs.rotDelta
    cs.rotLeft = cs.rotLeft - 1
    if cs.rotLeft == 0 then cs.rotCur = cs.rotFinal end
  end
  -- ...RotatePlayer's end: full speed, and the bob begins
  if cs.t == c.turn then
    cs.bob, cs.bobDelta = 1, c.bob
  end
  -- the camera (UpdateCascadeDown/UpCamera), on the exact tile offset
  local yOff = tilesOf(cs.off * c.dir)
  local cam = c.cams[cs.cam]
  if cam and yOff == cam.at then
    S.aimCamera({ angleX = cam.x, angleY = cam.y, steps = cam.steps })
    if cam.rotate then rotate(cs, cam.rotate, cam.rotateSteps) end
    if cam.face then p.facing = cam.face end
    if cs.cam == 1 and c.faceAfter then cs.faceDelay = 0 end
    -- the bob's drift while the camera swings (down only)
    if cam.bobFix then cs.bobFixDelta, cs.bobFixLeft = cam.bobFix / (cam.steps - 2), cam.steps - 2 end
    cs.cam = cs.cam + 1
  end
  if cs.faceDelay then
    cs.faceDelay = cs.faceDelay + 1
    if cs.faceDelay >= c.faceAfter.frames then p.facing, cs.faceDelay = c.faceAfter.face, nil end
  end
  if cs.bobFixLeft and cs.bobFixLeft > 0 then
    cs.bobFix = cs.bobFix + cs.bobFixDelta
    cs.bobFixLeft = cs.bobFixLeft - 1
  end
  -- FINISHING_POS_REACHED, 16 units short: the closing turn
  if not cs.finishing and c.final - cs.off == 16 then
    cs.finishing = true
    rotate(cs, c.endTurn, c.endTurnSteps)
  end
  -- the surf mount turns with the ride (Gen4SurfMount.cascadeFrame)
  pcall(require("src.world.Gen4SurfMount").cascadeFrame, cs)
  -- LoadFloor at the map-load offset: the ride goes on in the next floor
  if not cs.loaded and cs.off >= c.load then
    cs.loaded = true
    local Game = package.loaded["src.core.Game"]
    local dw = Game.data.gen4_distortion_world
    local info = dw.maps[c.to] or dw.maps[tostring(c.to)]
    local destId = findDef(c.to)
    if info and destId then
      local keep = ow.dwCascade
      ow:setMap(destId, c.x - (info.offsetX or 0), cs.z - (info.offsetZ or 0), p.facing)
      ow.dwCascade = keep
      p.surfing = true
      p.inputLocked = true
    end
  end
  if cs.off < c.final then return end
  -- set down 0x2A tiles from the start: B5F's pool, or B4F's ceiling
  if cs.sound then pcall(cs.sound.stop, cs.sound) end
  p.facing = c.endFace
  local mm = S.floorFor(ow.map and ow.map.def)
  if c.ceiling and mm then
    local y = c.y + c.fix
    local i, pl = platformAt(mm, c.x, y, cs.z, 3)
    if i then ow.dwSurface = { index = i, kind = pl.kind, x = c.x, y = y, z = cs.z, moveDir = "left" } end
  end
  -- SetPersistedMovingPlatformFlag(B5F_1): B5F's lift is back for the trip down
  if c.liftFlag then
    local P = require("src.world.Gen4DistPlatforms")
    if P.setFlag then P.setFlag(c.liftFlag, true) end
  end
  ow.dwMapY = nil
  ow.dwPose = nil
  cs.away, cs.awayAt = c.moveAway, 1
end

local function tickCascade(ow, m)
  local cs = ow.dwCascade
  if ow.dwDsFrame then cascadeFrame(ow, m) end
  cs = ow.dwCascade
  if not cs or cs.away then return end
  -- the player rides the fall in world units, wherever the floor's origin is
  local mm = S.floorFor(ow.map and ow.map.def) or m
  local y = cs.worldY + cs.c.dir * cs.off - (mm.offsetAltitude or 0) * 16
  -- the sprite's roll is the rotator's angle (counter-clockwise on the DS's
  -- y-up screen, so negated for LOVE's y-down one), its bob a jump offset in x
  ow.dwPose = { y = y, rollDeg = -cs.rotCur, ox = (cs.bob or 0) + (cs.bobFix or 0) }
  local ground = groundOf(ow)
  if ground then ground.surfaceBaseY = y end
end
S.tickCascade = tickCascade
S.cascadeRotate = rotate
S.cascadeSound = soundSe

return S
