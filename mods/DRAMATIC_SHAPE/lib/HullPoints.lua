-- Immutable round hulls share corner coordinates across many faces. Reuse
-- those tiny arrays at creation rather than allocate one per face corner.
-- FFI hosts retain owning numeric buffers with one-based slots; these are
-- private immutable geometry, never mutable camera or gameplay vectors.
local V=...
local ok,ffi=pcall(require,'ffi')
local Point=ok and ffi.typeof('int16_t[4]')
local UV=ok and ffi.typeof('double[3]')
local M={created=0,reused=0,uvCreated=0,uvReused=0,packedCreated=0}
function M.newUV()
 local pool={}
 local packed=ok and (not V or V.packedHullPoints~=false)
 return function(u,v)
  if V and V.internHullUV==false then return {u,v} end
  -- Exact float keys: never quantize atlas coordinates across tile seams.
  local row=pool[u]
  if not row then row={};pool[u]=row end
  local p=row[v]
  if p then M.uvReused=M.uvReused+1;return p end
  if packed then
   p=ffi.new(UV);p[1],p[2]=u,v;M.packedCreated=M.packedCreated+1
  else p={u,v} end
  row[v]=p;M.uvCreated=M.uvCreated+1;return p
 end
end
function M.new()
 local pool={}
 local packed=ok and (not V or V.packedHullPoints~=false)
 return function(x,y,z)
  -- This collision-free key covers the integer voxel lattice used by the
  -- lathe. Preserve unfamiliar/fractional coordinates as ordinary arrays.
  if (not V or V.internHullPoints~=false) and x>=-256 and x<256 and y>=-256 and y<256
   and z>=-256 and z<256 and x%1==0 and y%1==0 and z%1==0 then
   local key=x+256+(y+256)*512+(z+256)*262144
   local point=pool[key]
   if point then M.reused=M.reused+1;return point end
   -- These interned corners are immutable lattice coordinates. An owning
   -- cdata value has no child references for GC to traverse, and int16 is
   -- exact throughout the proven range. Fractional/unfamiliar corners below
   -- keep ordinary arrays. The UV counterpart retains full double precision.
   if packed then
    point=ffi.new(Point);point[1],point[2],point[3]=x,y,z;M.packedCreated=M.packedCreated+1
   else point={x,y,z} end
   pool[key]=point;M.created=M.created+1;return point
  end
  M.created=M.created+1
  return {x,y,z}
 end
end
return M
