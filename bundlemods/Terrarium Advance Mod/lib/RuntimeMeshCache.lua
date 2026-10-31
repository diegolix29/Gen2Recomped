local V=...
local Assets=V.GeneratedAssets
local Persist,mod=V.PayloadPreserver,V.mod
local R={version=2}
local luaMemo={}
local luaMemoHits=0
local luaMemoLoads=0
local unpackArgs=table.unpack or unpack

function R.packSupported()
  return (love and love.data and type(love.data.pack)=="function")
    or type(string.pack)=="function"
end
function R.supported()
  return R.packSupported() and love and love.data and type(love.data.newByteData)=="function"
    and love.graphics and type(love.graphics.newMesh)=="function"
end

local function finite(n)
  n=tonumber(n) or 0
  if n~=n or n==math.huge or n==-math.huge then return 0 end
  return n
end

-- Rows are packed in batches rather than one love.data.pack call (plus one
-- scratch table and one intermediate string) per vertex. A single arena or
-- Pokemon body is tens of thousands of rows, so this removes the dominant
-- allocation cost of writing a runtime sidecar. Output bytes are unchanged.
local PACK_BATCH=64
-- Lua/LuaJIT builds do not all expose the same practical vararg/result ceiling.
-- A Waza morph vertex has 44 floats; PACK_BATCH=64 used to expand that to 2,816
-- scalar call arguments, and unpack() is evaluated *before* pcall(love.data.pack,
-- ...), so a mobile stack-limit failure escaped the pack error guard entirely.
-- Keep batching, but cap scalar arguments well below the common 255-register
-- boundary. This changes only call granularity; emitted f32 bytes are identical.
local PACK_SCALAR_LIMIT=192

function R.packRows(rows,stride,checkpoint)
  stride=math.max(1,math.floor(tonumber(stride) or 0))
  if stride<=0 or not R.packSupported() then return nil,"runtime binary pack API unavailable" end
  rows=rows or {}
  local count=#rows
  if count==0 then return nil,"no vertex rows" end
  local rowFmt=string.rep("f",stride)
  local rowsPerBatch=math.max(1,math.min(PACK_BATCH,math.floor(PACK_SCALAR_LIMIT/stride)))
  local batchFmt=string.rep(rowFmt,rowsPerBatch)
  local buf={}
  local chunks,chunkCount={},0
  local i=1
  while i<=count do
    local take=count-i+1;if take>rowsPerBatch then take=rowsPerBatch end
    local k=0
    for r=i,i+take-1 do
      local row=rows[r]
      if type(row)~="table" then return nil,"vertex row missing" end
      for j=1,stride do
        local v=tonumber(row[j]) or 0
        if v~=v or v==math.huge or v==-math.huge then v=0 end
        k=k+1;buf[k]=v
      end
    end
    local fmt=take==rowsPerBatch and batchFmt or string.rep(rowFmt,take)
    local ok,bytes
    if love and love.data and type(love.data.pack)=="function" then
      ok,bytes=pcall(love.data.pack,"string",fmt,unpackArgs(buf,1,k))
    end
    if (not ok or type(bytes)~="string") and type(string.pack)=="function" then
      ok,bytes=pcall(string.pack,"<"..fmt,unpackArgs(buf,1,k))
    end
    if not ok or type(bytes)~="string" then return nil,tostring(bytes or "float32 pack failed") end
    chunkCount=chunkCount+1;chunks[chunkCount]=bytes
    i=i+take
    if checkpoint then checkpoint() end
  end
  return table.concat(chunks,"",1,chunkCount)
end

function R.writeRows(path,rows,stride,checkpoint,preserveExisting)
  if not (Assets and Assets.write) then return false,"generated cache writer unavailable" end
  local bytes,err=R.packRows(rows,stride,checkpoint);if not bytes then return false,err end
  if preserveExisting and Persist then
    local _,why=Persist.preserve(mod,"runtime_mesh",path,bytes)
    if why then return false,why end
  end
  local ok,why=Assets.write(path,bytes)
  return ok~=false and ok~=nil,why,#bytes
end

-- Compact pose banks ("OQ16"), written by lib/ORASActorCache.lua and read
-- back by RuntimeMeshCache.meshFromBytes.  A bank is rows of 44 float32
-- (slot-0 position, uv, normal, slots 1-12 positions); the compact file is
--   "OQ16", u32 rows, f32 posScale, f32 uvScale, u32 zlen, then zlen bytes
--   of zlib, zero-padded so the file size is a multiple of 176 (one float
--   row) -- the size checks that guard plain banks pass unchanged.
-- Inflated: rows * 44 int16, low bytes first (all of them), then high bytes.
-- Per row: position * posScale, uv * uvScale, normal * 32000, then each of
-- slots 1-12 as (quantized position - the previous slot's), wrapped to 16
-- bits (exact: every quantized position fits int16), so the poses of a
-- vertex, which barely move, become small numbers zlib packs well.
local okFfi,ffi=pcall(require,"ffi");if not okFfi then ffi=nil end
function R.decodeQ16(bytes)
  if not (ffi and type(bytes)=="string" and #bytes>=20 and bytes:sub(1,4)=="OQ16") then return nil,"not an OQ16 bank" end
  local head=ffi.new("uint32_t[5]");ffi.copy(head,bytes,20)
  local rows=tonumber(head[1]);local zlen=tonumber(head[4])
  local ps=tonumber(ffi.cast("float*",head)[2]);local us=tonumber(ffi.cast("float*",head)[3])
  if not (rows and rows>0 and zlen and zlen>0 and 20+zlen<=#bytes and ps>0 and us>0) then return nil,"bad OQ16 header" end
  local ok,raw=pcall(love.data.decompress,"string","zlib",bytes:sub(21,20+zlen))
  local n=rows*44
  if not (ok and type(raw)=="string" and #raw==n*2) then return nil,"OQ16 inflate failed" end
  local src=ffi.cast("const uint8_t*",raw)
  local out=ffi.new("float[?]",n)
  local ip,iu,inr=1/ps,1/us,1/32000
  for r=0,rows-1 do
    local o=r*44
    local p0,p1,p2
    for c=0,43 do
      local i=o+c
      local q=src[i]+src[n+i]*256
      if q>=32768 then q=q-65536 end
      if c<3 then
        if c==0 then p0=q elseif c==1 then p1=q else p2=q end
        out[i]=q*ip
      elseif c<5 then out[i]=q*iu
      elseif c<8 then out[i]=q*inr
      else
        local k=(c-8)%3
        if k==0 then p0=(p0+q+32768)%65536-32768;out[i]=p0*ip
        elseif k==1 then p1=(p1+q+32768)%65536-32768;out[i]=p1*ip
        else p2=(p2+q+32768)%65536-32768;out[i]=p2*ip end
      end
    end
  end
  return ffi.string(out,n*4)
end

function R.meshFromBytes(format,bytes,stride,usage)
  if type(bytes)=="string" and bytes:sub(1,4)=="OQ16" then
    local plain,err=R.decodeQ16(bytes)
    if not plain then return nil,err end
    bytes=plain
  end
  if not (R.supported() and type(bytes)=="string") then return nil,"runtime binary mesh unavailable" end
  stride=math.max(1,math.floor(tonumber(stride) or 0))
  local bytesPerVertex=stride*4
  if bytesPerVertex<=0 or #bytes<bytesPerVertex or (#bytes%bytesPerVertex)~=0 then
    return nil,"runtime binary mesh byte count/stride mismatch"
  end
  local count=math.floor(#bytes/bytesPerVertex)
  local okMesh,mesh=pcall(love.graphics.newMesh,format,count,"triangles",usage or "static")
  if not okMesh or not mesh then return nil,tostring(mesh or "newMesh failed") end
  local okData,data=pcall(love.data.newByteData,bytes)
  if not okData or not data then pcall(function() if mesh.release then mesh:release() end end);return nil,tostring(data or "newByteData failed") end
  local okSet,setErr=pcall(mesh.setVertices,mesh,data,1,count)
  -- setVertices copies the upload; the staging buffer is not a resident asset.
  if data.release then pcall(data.release,data) end
  if not okSet then pcall(function() if mesh.release then mesh:release() end end);return nil,tostring(setErr) end
  return mesh,nil,count
end

function R.meshFromPath(format,path,stride,usage)
  if not (Assets and Assets.read) then return nil,"generated cache reader unavailable" end
  local bytes,err=Assets.read(path);if type(bytes)~="string" then return nil,err end
  return R.meshFromBytes(format,bytes,stride,usage)
end

local function keySort(a,b)
  local ta,tb=type(a),type(b)
  if ta==tb then return tostring(a)<tostring(b) end
  return ta<tb
end
local function serialize(v,seen,depth)
  local t=type(v)
  if t=="nil" then return "nil" end
  if t=="boolean" then return v and "true" or "false" end
  if t=="number" then return string.format("%.17g",finite(v)) end
  if t=="string" then return string.format("%q",v) end
  if t~="table" then return "nil" end
  depth=(depth or 0)+1;if depth>24 then return "nil" end
  seen=seen or {};if seen[v] then return "nil" end;seen[v]=true
  local keys={};for k in pairs(v) do if type(k)=="string" or type(k)=="number" then keys[#keys+1]=k end end
  table.sort(keys,keySort)
  local out={"{"}
  for _,k in ipairs(keys) do
    local ks=type(k)=="number" and ("["..string.format("%.17g",k).."]") or ("["..string.format("%q",k).."]")
    out[#out+1]=ks.."="..serialize(v[k],seen,depth).."," 
  end
  out[#out+1]="}";seen[v]=nil
  return table.concat(out)
end
function R.writeLua(path,value,preserveExisting)
  if not (Assets and Assets.write) then return false,"generated cache writer unavailable" end
  path=tostring(path or "")
  local bytes="return "..serialize(value).."\n"
  if preserveExisting and Persist then
    local _,why=Persist.preserve(mod,"runtime_mesh",path,bytes)
    if why then return false,why end
  end
  local ok,err=Assets.write(path,bytes)
  if ok~=false and ok~=nil then luaMemo[path]=value end
  return ok~=false and ok~=nil,err
end
function R.readLua(path)
  if not (Assets and Assets.read) then return nil,"generated cache reader unavailable" end
  path=tostring(path or "")
  local memo=luaMemo[path]
  if memo~=nil then luaMemoHits=luaMemoHits+1;return memo end
  local src,err=Assets.read(path);if type(src)~="string" then return nil,err end
  local f,e=load(src,"@generated/"..path);if not f then return nil,e end
  local ok,v=pcall(f);if not ok then return nil,v end
  luaMemo[path]=v;luaMemoLoads=luaMemoLoads+1
  return v
end
function R.invalidateLua(path)
  if path==nil then luaMemo={} else luaMemo[tostring(path)]=nil end
  return true
end
function R.memoStatus()
  local n=0;for _ in pairs(luaMemo) do n=n+1 end
  return {entries=n,hits=luaMemoHits,loads=luaMemoLoads}
end
function R.read(path)
  return Assets and Assets.read and Assets.read(path) or nil
end
function R.exists(path)
  return Assets and Assets.exists and Assets.exists(path) or false
end
return R
