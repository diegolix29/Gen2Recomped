-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- PLATINUM'S SURF MOUNT: the Pokemon-shaped boat under a surfing player.
--
-- Reported from play: "were missing the surf model under the player when
-- surfing".  Gen 3's blob is a sprite (Player:drawSurfBlob); Gen 4's is a 3D
-- model, fldeff member 81 `sea_ride`, drawn by pokeplatinum
-- src/overlay005/surf_mount_renderer.c:
--
--   * it bobs: yOffset from 1 unit, 0x400 (1/4 unit) a frame, between 1 and
--     4, reversing at either end (SurfMountRenderer_AnimTick)
--   * it sits at the player's position, yOffset - 1 units up
--   * it turns with the player: rotated about y by 0 facing south, 180 north,
--     270 west, 90 east (SurfMountRenderer_AnimRender)
--   * and it lifts the player's SPRITE by (0, 7 + yOffset, 4) units -- up
--     onto its back and a little toward the camera
--     (MAP_OBJECT_BASE_POS_OFFSET_*)
-- At the field's 30 frames a second.

local M = {}

M.MODEL = 81
-- HeartGold/SoulSilver's copy of the archive is /a/1/0/3, `sea_ride` at 86
M.HGSS_MODEL = 86
M.MIN_Y, M.MAX_Y, M.DELTA = 1, 4, 0x400 / 4096
M.SPRITE_Y, M.SPRITE_Z = 7, 4
-- HeartGold/SoulSilver's renderer (pokeheartgold overlay 1 ov01_021FE8C8)
-- bobs the same 1..4 by 1/4 and places the mount the same, but lifts the
-- sprite by 4 + yOffset (`lsl r0, #0xe` added to yOffset), not 7
M.HGSS_SPRITE_Y = 4
M.ANGLE = { down = 0, up = 180, left = 270, right = 90 }

local function Game() return package.loaded["src.core.Game"] end

local function isHgss()
  local G = Game()
  local v = G and G.data and G.data.gen4_version
  return v and v.family == "hgss"
end

-- Platinum and HeartGold/SoulSilver (Black and White's surfing is their own)
local function isGen4()
  local G = Game()
  local GV = require("src.core.GameVersion")
  return G and G.data and G.data.isGen4Cache and not GV.isGen5()
end

-- whether the mount is drawn for this overworld right now: "field" for the
-- ordinary renderer (surf_mount_renderer.c), "dw" for the Distortion World's
-- own (dist_world_surf_mount_renderer.c), or false
local function active(ow)
  local p = ow and ow.player
  if not (p and p.surfing and isGen4()) then return false end
  if p.isUnderwater and p:isUnderwater() then return false end
  local def = ow.map and ow.map.def
  if def and def.gen4DistWorld then
    -- AVATAR_DISTORTION_STATE_WEST/EAST_WALL have rows in its tables, but no
    -- wall in the Distortion World holds water, so nothing reaches them
    local st = ow.dwSurface
    if st and (st.kind == 1 or st.kind == 2) and not ow.dwCascade then return false end
    return "dw"
  end
  return "field"
end
M.active = active

-- DIST_WORLD_SURF_MOUNT: the floor's and the ceiling's rows of
-- sMountPosFixes / sOrbitAngles / sFixedRotAngles.  The mount stands at the
-- player's position + (0, 8, 0) + fix + 20 units round the orbit angle in
-- x-y, bobbing in y; the player's sprite is NOT raised here
-- (sSpriteBasePosOffsets are all zero).
M.DW_ORBIT_DISTANCE, M.DW_BASE_Y = 20, 8
M.DW = {
  floor   = { fix = { 0.25, 6, -5 }, orbit = 270,
              rot = { up = { 0, 180, 0 }, down = { 0, 0, 0 }, left = { 0, 270, 0 }, right = { 0, 90, 0 } } },
  ceiling = { fix = { 0, 0, 6 }, orbit = 90,
              rot = { up = { 180, 180, 0 }, down = { 180, 0, 0 }, left = { 180, 90, 0 }, right = { 180, 270, 0 } } },
}
-- WHERE THE CEILING'S MAP-OBJECT POSITION SITS against the feet this port
-- draws the player at.  The overlay's ceiling row (+28 above it) is relative
-- to a position these tables do not state.  CALIBRATED BY EYE, not read off
-- the cartridge: at 0 the flipped mount sinks into the slab and cannot be
-- seen; at -40 it sits under the hanging player as the floor's sits under a
-- standing one (DWK=n in the harness overrides it).
M.DW_CEILING_K = tonumber(os.getenv and os.getenv("DWK") or "") or -40

-- The waterfall rides' mount (EventCmdCascadeDown/Up_*): rotation angles,
-- orbit and the external position fix, turned through the opening and closing
-- steps; during the ride the bob is the ride's own jump offset in x.
M.CASCADE = {
  [-1] = { from = "ceiling", to = "floor", rot0 = { 180, 90, 0 }, rotD = { -90, 180, 0 }, orbit0 = 90, orbitD = -70,
           fix0 = { 0, 0, 6 }, fixD = { 0, 0, 4 }, rideFix = { 0, 0, 10 },
           cams = { { fixD = { 0, 0, -16 }, steps = 70 }, { fixD = { 0, 0, 6 }, steps = 30 } },
           endRotD = { -90, 0, 0 }, endFixD = { 0, 0, -7 }, endOrbitD = -110, endSteps = 16 },
  [1]  = { from = "floor", to = "ceiling", rot0 = { 0, 90, 0 }, rotD = { -90, 180, 0 }, orbit0 = 270, orbitD = 110,
           fix0 = { 0, 0, -7 }, fixD = { 0, 0, 0 }, rideFix = { 0, 0, -7 },
           -- CASCADE_UP_CASCADE_MOUNT_POSITION_FIX_Z / CASCADE_STEPS a frame
           -- once the camera has swung, until z reaches 10
           upFix = { 0, 0, 17 / 16 }, upFixUntilZ = 10,
           endRotD = { 90, 0, 0 }, endFixD = { 0, 0, -4 }, endOrbitD = 70, endSteps = 2 },
}

local function wrap360(a) a = a % 360; if a < 0 then a = a + 360 end; return a end

-- one cartridge frame of the ride's mount; Gen4DistSurface's cascadeFrame
-- calls it after its own bookkeeping
function M.cascadeFrame(cs)
  local c = cs.c
  local t = M.CASCADE[c.dir]
  if not t then return end
  local mt = cs.mount
  if not mt then
    mt = { rot = { t.rot0[1], t.rot0[2], t.rot0[3] }, orbit = t.orbit0,
           fix = { t.fix0[1], t.fix0[2], t.fix0[3] }, camAt = 0, camLeft = 0 }
    cs.mount = mt
  end
  local function add(v, d, n)
    for i = 1, 3 do v[i] = v[i] + d[i] / n end
  end
  if cs.t <= c.turn then
    -- ...RotatePlayer
    add(mt.rot, t.rotD, c.turn)
    mt.orbit = wrap360(mt.orbit + t.orbitD / c.turn)
    add(mt.fix, t.fixD, c.turn)
    if cs.t == c.turn then mt.fix = { t.rideFix[1], t.rideFix[2], t.rideFix[3] } end
  elseif cs.finishing then
    -- ...FinishCascading: the closing turn
    add(mt.rot, t.endRotD, t.endSteps)
    mt.orbit = wrap360(mt.orbit + t.endOrbitD / t.endSteps)
    add(mt.fix, t.endFixD, t.endSteps)
    mt.ext = nil
  else
    -- ...CascadeDown/Up: the camera's drift, and the bob as an external offset
    local camNow = (cs.cam or 1) - 1
    if t.cams and camNow > mt.camAt then
      mt.camAt = camNow
      local cam = t.cams[camNow]
      if cam then mt.camD, mt.camLeft = cam.fixD, cam.steps end
    end
    if mt.camLeft > 0 then
      add(mt.fix, mt.camD, (t.cams[mt.camAt] or { steps = 1 }).steps)
      mt.camLeft = mt.camLeft - 1
    end
    if t.upFix and camNow >= 1 and mt.fix[3] < t.upFixUntilZ then add(mt.fix, t.upFix, 1) end
    mt.ext = { cs.bob or 0, 0, 0 }
  end
  for i = 1, 3 do mt.rot[i] = wrap360(mt.rot[i]) end
end

-- the Distortion World's mount: its position in world units and its rotation
local function dwPlacement(ow, ground)
  local p = ow.player
  local pose = ow.dwPose or {}
  local x = (p.px or 0) + 8 + (pose.ox or 0)
  local z = (p.py or 0) + 8 + (pose.oz or 0)
  local y = pose.y or ground.surfaceBaseY or ground:groundY(x, z)
  local bob = ow.surfMount.y or 1
  local cs = ow.dwCascade
  local rot, orbit, fix, k, ext
  if cs and cs.mount and not cs.away then
    local t = M.CASCADE[cs.c.dir]
    local mt = cs.mount
    rot, orbit, fix, ext = mt.rot, mt.orbit, mt.fix, mt.ext
    -- the position's offset from the feet, carried across the ride
    local kFrom = t.from == "ceiling" and M.DW_CEILING_K or 0
    local kTo = t.to == "ceiling" and M.DW_CEILING_K or 0
    k = kFrom + (kTo - kFrom) * math.min(1, (cs.off or 0) / cs.c.final)
  else
    local st = ow.dwSurface
    local row = (st and st.kind == 3) and M.DW.ceiling or M.DW.floor
    local dir = (st and st.moveDir) or p.facing or "down"
    rot, orbit, fix = row.rot[dir] or row.rot.down, row.orbit, row.fix
    k = (row == M.DW.ceiling) and M.DW_CEILING_K or 0
  end
  local r = math.rad(orbit)
  local mx = fix[1] + math.cos(r) * M.DW_ORBIT_DISTANCE
  local my = k + M.DW_BASE_Y + fix[2] + math.sin(r) * M.DW_ORBIT_DISTANCE
  local mz = fix[3]
  if ext then mx, my, mz = mx + ext[1], my + ext[2], mz + ext[3]
  else my = my + bob end
  return x + mx, y + my, z + mz, rot
end

-- MTX_Rot33Angles(alpha, beta, gamma): X, then Y, then Z (row vectors,
-- v * Rx * Ry * Rz), as a column-vector 4x4
local function rotXYZ(a, b, g)
  local ca, sa = math.cos(math.rad(a)), math.sin(math.rad(a))
  local cb, sb = math.cos(math.rad(b)), math.sin(math.rad(b))
  local cg, sg = math.cos(math.rad(g)), math.sin(math.rad(g))
  local Rx = { 1, 0, 0, 0, ca, -sa, 0, sa, ca }
  local Ry = { cb, 0, sb, 0, 1, 0, -sb, 0, cb }
  local Rz = { cg, -sg, 0, sg, cg, 0, 0, 0, 1 }
  local function mul(A, B)
    local o = {}
    for i = 0, 2 do for j = 0, 2 do
      o[i * 3 + j + 1] = A[i * 3 + 1] * B[j + 1] + A[i * 3 + 2] * B[3 + j + 1] + A[i * 3 + 3] * B[6 + j + 1]
    end end
    return o
  end
  local M3 = mul(Rz, mul(Ry, Rx))
  return { M3[1], M3[2], M3[3], 0, M3[4], M3[5], M3[6], 0, M3[7], M3[8], M3[9], 0, 0, 0, 0, 1 }
end
M.rotXYZ = rotXYZ

-- every engine frame (OverworldState:update); the bob steps every other one
function M.tick(ow)
  local p = ow and ow.player
  if not p then return end
  local st = ow.surfMount
  if not active(ow) then
    if st then
      -- SurfMountRenderer_AnimExit: the sprite offset back to nothing
      if p.spriteOffset == st.offset then p.spriteOffset = nil end
      ow.surfMount = nil
    end
    return
  end
  if not st then
    st = { y = M.MIN_Y, dy = M.DELTA, half = false, offset = {} }
    ow.surfMount = st
  end
  st.half = not st.half
  if st.half then
    st.y = st.y + st.dy
    if st.y >= M.MAX_Y then st.y, st.dy = M.MAX_Y, -st.dy
    elseif st.y <= M.MIN_Y then st.y, st.dy = M.MIN_Y, -st.dy end
  end
  st.facing = p.facing
  -- the sprite rides on top (a field this module owns: other offsets win);
  -- the Distortion World's renderer leaves it where it is
  local mode = active(ow)
  if p.spriteOffset == nil or p.spriteOffset == st.offset then
    if mode == "field" then
      st.offset.lift, st.offset.oz = (isHgss() and M.HGSS_SPRITE_Y or M.SPRITE_Y) + st.y, M.SPRITE_Z
      p.spriteOffset = st.offset
    else
      p.spriteOffset = nil
    end
  end
end

-- The pose the free camera draws an entity with: the Distortion World's
-- surface pose when it has one, carrying the sprite offset on top of it.
function M.poseFor(e, dwPose)
  local so = e and e.spriteOffset
  if not dwPose then return so end
  if not (so and (so.lift or so.oz or so.ox)) then return dwPose end
  local out = {}
  for k, v in pairs(dwPose) do out[k] = v end
  out.lift = (out.lift or 0) + (so.lift or 0)
  out.oz = (out.oz or 0) + (so.oz or 0)
  out.ox = (out.ox or 0) + (so.ox or 0)
  return out
end

-- the mount's place: the player's feet in map pixels, and its height
local function where(ow, ground)
  local p = ow.player
  local gx = (p.px or 0) + 8
  local gz = (p.py or 0) + 8
  local y = (ow.dwPose and ow.dwPose.y) or ground.surfaceBaseY or ground:groundY(gx, gz)
  return gx, gz, y + (ow.surfMount.y or 1) - 1
end

local function rotY(deg)
  local r = math.rad(deg)
  local c, s = math.cos(r), math.sin(r)
  -- MTX_Rot33Angles(0, deg, 0): x' = c x + s z, z' = -s x + c z
  return { c, 0, s, 0,
           0, 1, 0, 0,
           -s, 0, c, 0,
           0, 0, 0, 1 }
end

local function model(ground)
  return ground:building(isHgss() and M.HGSS_MODEL or M.MODEL, "fldeff")
end

-- the free camera's pass: `vp` is the world's view-projection
function M.drawFree(ground, vp)
  local G = Game()
  local ow = G and G.overworld
  if not (ow and ow.surfMount and active(ow)) then return end
  local mdl = model(ground)
  if not mdl then return end
  local Gen4Model = require("src.render.Gen4Model")
  if active(ow) == "dw" then
    local x, y, z, rot = dwPlacement(ow, ground)
    if os.getenv and os.getenv("SURFDEBUG") then
      local p = ow.player
      print(("[surfmount] dw feet (%.1f,%.1f,%.1f) mount (%.1f,%.1f,%.1f) rot %s,%s,%s surf=%s"):format(
        (p.px or 0) + 8, (ow.dwPose and ow.dwPose.y) or -1, (p.py or 0) + 8, x, y, z, rot[1], rot[2], rot[3],
        tostring(ow.dwSurface and ow.dwSurface.kind)))
    end
    local m = Gen4Model.multiply(vp, { 1, 0, 0, x + (ground.offsetX or 0),
                                       0, 1, 0, y,
                                       0, 0, 1, z + (ground.offsetY or 0),
                                       0, 0, 0, 1 })
    mdl:draw(Gen4Model.multiply(m, rotXYZ(rot[1], rot[2], rot[3])))
    return
  end
  local gx, gz, y = where(ow, ground)
  local m = Gen4Model.multiply(vp, { 1, 0, 0, gx + (ground.offsetX or 0),
                                     0, 1, 0, y,
                                     0, 0, 1, gz + (ground.offsetY or 0),
                                     0, 0, 0, 1 })
  mdl:draw(Gen4Model.multiply(m, rotY(M.ANGLE[ow.surfMount.facing] or 0)))
end

-- the field camera's live pass: `left`/`top` are the view's corner in matrix
-- pixels, as `livePass` has them
function M.drawLive(ground, left, top, vw, vh)
  local G = Game()
  local ow = G and G.overworld
  if os.getenv and os.getenv("SURFDEBUG") and not M.said then
    M.said = true
    print(("[surfmount] ow=%s mount=%s active=%s model=%s set=%s"):format(tostring(ow ~= nil),
      tostring(ow and ow.surfMount ~= nil), tostring(ow and active(ow)), tostring(model(ground) ~= nil),
      tostring(ground.fldeffSet ~= nil)))
  end
  if not (ow and ow.surfMount and active(ow) == "field") then return end
  local mdl = model(ground)
  if not mdl then return end
  local Gen4Model = require("src.render.Gen4Model")
  local gx, gz, y = where(ow, ground)
  local half = ground.half or 0
  local base = ground:screenMatrix(gx + (ground.offsetX or 0) - left - half,
                                   gz + (ground.offsetY or 0) - top - half, vw, vh)
  local Gen4Ground = require("src.render.Gen4Ground")
  local m = Gen4Ground.liftMatrix(base, y)
  local spread = Gen4Ground.liftedSpread and Gen4Ground.liftedSpread(ground.spread, y) or ground.spread
  mdl:draw(Gen4Model.multiply(m, rotY(M.ANGLE[ow.surfMount.facing] or 0)), nil, nil, nil, spread)
end

return M
