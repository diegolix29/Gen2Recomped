-- Voxel world mode: WHERE a mesh is, so a pass can decline to draw it.
--
-- Every terrain mesh in this mod is one object per map per slot, and every
-- frame draws all of them: the map the player is standing on AND every
-- connected neighbour, in the camera pass and again in the sun's. Nothing
-- ever asked whether a neighbour was on screen.
--
-- MEASURED, with the frame's own view-projection matrix taken out of a real
-- frame and every neighbour's world box tested against it:
--
--   standing in Lilycove   6 connected neighbours, 6 of 6 off screen,
--                          3,169,482 quads of terrain against the city's
--                          own 237,672 -- THIRTEEN TIMES the map you are
--                          looking at, none of it visible
--   standing on Route 119  5 connected neighbours, 5 of 5 off screen,
--                          4,730,470 quads against the route's 2,979,507
--
-- And of the current map's own mesh, 4.2% to 5.8% of its quads are on
-- screen at all -- so this is the cheap half of a much larger idea (chunked
-- meshes; see NOTES g3-governor-286) that needs none of its machinery: a
-- whole map is already one object, and a whole map is exactly what turns
-- out to be off screen.
--
-- WHAT THE BOX IS. Not measured per vertex -- folding a min/max over every
-- corner costs 8% to 17% of the build, and the build is the hitch this
-- round is cutting. It is the map's own footprint plus a fixed PAD, and the
-- PAD is a MEASURED BOUND rather than a guess: over the 81 outdoor maps the
-- emitted geometry never reaches more than 96 world pixels outside the
-- map's own rectangle (32 on a route, 96 where the border ring is deep),
-- which is what `Structures`' RING of twelve tiles allows and no pass can
-- exceed. PAD is twice that. Measured again at 96, 128, 160, 192 and 224:
-- the same neighbours cull at every one of them, so the slack is free.
--
-- A mesh with no box registered is never culled. That is the whole safety
-- story for the grass, the flowers, the figures, the battle cards and the
-- horde's gun -- none of them registers one, and all of them draw exactly
-- as they always did.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local Mat4 = V.require("Mat4")

local MeshBounds = {}

-- Twice the largest overhang measured over the 81 outdoor maps. See above.
MeshBounds.PAD = 192

-- Vertical span, likewise generous: the tallest geometry measured over the
-- same 81 maps reaches y = 208 (Sootopolis' rim) and the lowest is the
-- sea's -16, against a shadow pass whose own frustum is 160 tall.
MeshBounds.Y0 = -128
MeshBounds.Y1 = 512

-- WEAK KEYS. A mesh released by the cache (setLive evicting a far map, a
-- slot swapped for a rebuilt one) must not be kept alive by its own
-- bounding box, and a box for a dead mesh must not accumulate over a
-- cross-region walk.
local boxes = setmetatable({}, { __mode = "k" })

function MeshBounds.set(mesh, box)
  if mesh and box then boxes[mesh] = box end
end

function MeshBounds.get(mesh)
  return mesh and boxes[mesh] or nil
end

-- Streamed bounds are measured before double coordinates become GPU floats.
-- Enclose float rounding so a corner on the view edge cannot disappear.
function MeshBounds.encloseFloats(b)
  local largest=0
  for i=1,6 do largest=math.max(largest,math.abs(b[i])) end
  local e=1e-5+largest*1.2e-7
  return {b[1]-e,b[2]-e,b[3]-e,b[4]+e,b[5]+e,b[6]+e}
end

-- The box for a map's own mesh, in that map's local coordinates (a
-- neighbour is drawn through a translate, which is handed in separately).
function MeshBounds.forMap(map)
  local def = map and map.def
  if not def then return nil end
  local px = tonumber(def.blockPx)
             or ((tonumber(map.tileset and map.tileset.blockTiles) or 4) * 8)
  local w = (tonumber(def.width) or 0) * px
  local h = (tonumber(def.height) or 0) * px
  if w <= 0 or h <= 0 then return nil end
  local p = MeshBounds.PAD
  return { -p, MeshBounds.Y0, -p, w + p, MeshBounds.Y1, h + p }
end

-- Is this mesh's box entirely outside `vp`'s clip volume?
--
-- The standard conservative test: the box is hidden only when all eight
-- corners fall outside the SAME clip plane. A box that straddles two planes
-- without being inside is reported visible, which costs a draw and can
-- never cost a pixel.
--
-- No bitwise operators: LOVE ships LuaJIT 5.1 and `&` is a parse error
-- there, whatever a newer standalone build accepts.
function MeshBounds.hiddenBox(b, vp, model)
  if not (b and vp) then return false end
  local m = model and Mat4.mul(vp, model) or vp
  -- A plane's maximum over an AABB is at its positive support vertex.
  -- Testing that vertex gives the same conservative six-plane result as
  -- transforming all eight corners, with no per-corner perspective work.
  for row=1,9,4 do
    for sign=-1,1,2 do
      local a=m[13]+sign*m[row]
      local c=m[14]+sign*m[row+1]
      local d=m[15]+sign*m[row+2]
      local e=m[16]+sign*m[row+3]
      local x=a>=0 and b[4] or b[1]
      local y=c>=0 and b[5] or b[2]
      local z=d>=0 and b[6] or b[3]
      -- Keep boxes exactly on a plane visible despite round-off.
      if a*x+c*y+d*z+e < -1e-7 then return true end
    end
  end
  return false
end

function MeshBounds.hidden(mesh, vp, model)
  return MeshBounds.hiddenBox(mesh and boxes[mesh],vp,model)
end

-- Terrain parts share a camera/model transform. Extract its planes once
-- per submission rather than rebuilding six planes for every spatial part.
function MeshBounds.planes(vp, out)
  if not vp then return nil end
  out=out or {}
  local at=1
  for row=1,9,4 do
    for sign=-1,1,2 do
      local a,c,d=vp[13]+sign*vp[row],vp[14]+sign*vp[row+1],vp[15]+sign*vp[row+2]
      out[at],out[at+1],out[at+2],out[at+3]=a,c,d,vp[16]+sign*vp[row+3]
      out[at+4],out[at+5],out[at+6]=a>=0 and 4 or 1,c>=0 and 5 or 2,d>=0 and 6 or 3
      at=at+7
    end
  end
  return out
end
function MeshBounds.hiddenPlanes(mesh, planes)
  local b=mesh and boxes[mesh]
  if not (b and planes) then return false end
  for at=1,36,7 do
    if planes[at]*b[planes[at+4]]+planes[at+1]*b[planes[at+5]]
       +planes[at+2]*b[planes[at+6]]+planes[at+3] < -1e-7 then return true end
  end
  return false
end

-- Curvature changes only world Y: y -= k * distance(xz, center)^2.
-- Bound its minimum/maximum drop over the whole rectangle, rather than
-- testing the unbent box or turning off culling for the entire world.
local bent = {}
function MeshBounds.hiddenCurved(mesh, vp, model, k, cx, cz)
  local b=mesh and boxes[mesh]
  if not (b and vp) then return false end
  local tx,ty,tz=0,0,0
  if model then
    if model[1]~=1 or model[6]~=1 or model[11]~=1 or model[16]~=1
      or model[2]~=0 or model[3]~=0 or model[5]~=0 or model[7]~=0
      or model[9]~=0 or model[10]~=0 or model[13]~=0 or model[14]~=0 or model[15]~=0 then
      return false -- unfamiliar transforms draw conservatively
    end
    tx,ty,tz=model[4],model[8],model[12]
  end
  local x0,x1,z0,z1=b[1]+tx,b[4]+tx,b[3]+tz,b[6]+tz
  local dx=math.max(x0-cx,0,cx-x1)
  local dz=math.max(z0-cz,0,cz-z1)
  local fx=math.max(math.abs(x0-cx),math.abs(x1-cx))
  local fz=math.max(math.abs(z0-cz),math.abs(z1-cz))
  bent[1],bent[3],bent[4],bent[6]=x0,z0,x1,z1
  bent[2]=b[2]+ty-k*(fx*fx+fz*fz)
  bent[5]=b[5]+ty-k*(dx*dx+dz*dz)
  return MeshBounds.hiddenBox(bent,vp)
end

return MeshBounds
