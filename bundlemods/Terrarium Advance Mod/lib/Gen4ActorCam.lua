-- Facing and billboard yaw for actors drawn through Platinum's own camera.
--
-- Voxel FirstPerson.cardBlend / cardYaw key off the free-roam rig and only
-- answer while Voxel3D.camera IS that rig. Gen4WorldHost binds a table from
-- Gen4View instead, so those helpers always report blend 0 and yaw 0 -- the
-- cartridge's south look. This module reads Gen4View (eye, yaw, free mode)
-- and is the only facing source 3D player / follower / battle cards should
-- use on a gen4hostworld map.

local V = ...

local Cam = {}

local function host()
  local ok, H = pcall(V.require, "Gen4WorldHost")
  return ok and H or nil
end

function Cam.ground(state)
  local H = host()
  if H and H.groundOf then return H.groundOf(state) end
  return nil
end

function Cam.view(ground)
  ground = ground or Cam.ground()
  return ground and ground.view3d or nil
end

-- True while Gen4View is drawing a real 3D lens (third, first, or field3d).
function Cam.active(ground)
  local view = Cam.view(ground)
  return view and view.isFree and view:isFree() == true
end

function Cam.eye(ground)
  local view = Cam.view(ground)
  if not (view and view.x) then return nil end
  return { view.x, view.y or 0, view.z or 0 }
end

-- Yaw that turns a +Z (south) card toward the live Gen4View eye.
-- Same convention as FirstPerson.cardYaw and BattleBillboard.yawToward:
-- atan2(east, south) so 0 faces a camera standing south of the actor.
--
-- `wx`/`wz` must be in the SAME space as view.x/view.z (absolute matrix
-- coordinates, including Gen4Ground.offsetX/offsetY).
function Cam.cardYaw(wx, wz, ground)
  local eye = Cam.eye(ground)
  if not eye then return 0 end
  wx, wz = tonumber(wx) or 0, tonumber(wz) or 0
  local dx, dz = eye[1] - wx, eye[3] - wz
  if dx * dx + dz * dz < 1e-9 then return 0 end
  return math.atan2(dx, dz)
end

-- Model rotateY from a WORLD compass facing.
--
-- Gen4's +Z is south. Identity (yaw 0) faces that south look -- the same
-- pose the 2D "down" sheet uses under the cartridge camera. Orbiting the
-- third-person camera must NOT go through view:worldToScreen: that remap
-- is for picking a sprite frame, and feeding it to rotateY locks a mesh
-- onto world-south.
function Cam.worldYaw(facing)
  facing = type(facing) == "string" and string.lower(facing) or facing
  if facing == "right" then return math.pi / 2 end
  if facing == "up" then return math.pi end
  if facing == "left" then return -math.pi / 2 end
  return 0
end

function Cam.facingVector(facing)
  local yaw = Cam.worldYaw(facing)
  return math.sin(yaw), math.cos(yaw)
end

return Cam
