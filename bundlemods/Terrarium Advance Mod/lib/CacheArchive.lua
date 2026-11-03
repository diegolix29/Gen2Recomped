-- Packs the two huge Colosseum generated trees -- cache/pokemon/* and
-- cache/movefx/* -- into per-unit zlib blobs under the live game-data root
-- (see unitFs below), then serves files back on demand. Extraction still writes loose files through
-- mod.cache; this module only runs after the user asks to pack, and only
-- deletes a loose original after that file's unit has been written and
-- round-tripped.
--
-- Units match how the runtime actually loads the cache: one Pokemon
-- species/variant, or one MoveFX WZX stem. A packed install is typically an
-- order of magnitude smaller than the loose RGBA/Lua dump (the user's ~30 GB
-- tree compressing under 3 GB) without putting a multi-gigabyte blob through
-- the host's small-file cache API.
--
-- Compression is LÖVE's built-in zlib (love.data.compress). No 7-Zip binary
-- is required. Identity files (Pokemon manifests, MoveFX index/coverage) stay
-- loose so BuildPipeline's launch-time readiness checks do not have to
-- decompress anything.
local V=...
local mod=V.mod
local WorkBudget=V.WorkBudget
local A={schema=1}

local ARCHIVE_ROOT="cbe_cache_archive"
local POKEMON_DIR=ARCHIVE_ROOT.."/pokemon"
local MOVEFX_DIR=ARCHIVE_ROOT.."/movefx"

local INDEX_POKEMON="cache/archive_v1/pokemon.lua"
local INDEX_MOVEFX="cache/archive_v1/movefx.lua"
local HOT_PATH="cache/archive_v1/hot.lua"
local MARKER_POKEMON="build/cache_archive_pokemon_v1.complete"
local MARKER_MOVEFX="build/cache_archive_movefx_v1.complete"

local POKEMON_SPECIES_COUNT=386
local POKEMON_MANIFEST_SHARD_SIZE=32
local POKEMON_MANIFEST_SHARDS=math.ceil(POKEMON_SPECIES_COUNT/POKEMON_MANIFEST_SHARD_SIZE)

local HOT_CAP_BYTES=1536*1024*1024
local MAGIC="CBEUNIT1"
local VERSION=1

-- ORAS models (lib/ORASActorCache.lua): oras/pokemon/<dex>/..., one unit per
-- species (both variants share the folder)
local ORAS_DIR=ARCHIVE_ROOT.."/oras"
local INDEX_ORAS="cache/archive_v1/oras.lua"
local MARKER_ORAS="build/cache_archive_oras_v1.complete"
-- ORAS move effects (lib/ORASEffects.lua bake): oras/movefx/<folder>/...,
-- one unit per folder (fx, tex, models, uv, motions, snd); index.lua and the
-- row settings directly under oras/movefx stay loose
local ORASFX_DIR=ARCHIVE_ROOT.."/orasfx"
local INDEX_ORASFX="cache/archive_v1/orasfx.lua"
local MARKER_ORASFX="build/cache_archive_orasfx_v1.complete"
-- ORAS battle stages (lib/ORASArenas.lua bake): oras/arenas/<folder>/...,
-- one unit per folder (models, tex); index.lua (the bake stamp) and
-- choice.txt directly under oras/arenas stay loose
local ORASARENA_DIR=ARCHIVE_ROOT.."/orasarena"
local INDEX_ORASARENA="cache/archive_v1/orasarena.lua"
local MARKER_ORASARENA="build/cache_archive_orasarena_v1.complete"

-- per kind: loose prefix, unit folder, index, done marker
local KINDS={
  pokemon={prefix="cache/pokemon/",dir=POKEMON_DIR,index=INDEX_POKEMON,marker=MARKER_POKEMON},
  movefx={prefix="cache/movefx/",dir=MOVEFX_DIR,index=INDEX_MOVEFX,marker=MARKER_MOVEFX},
  oras={prefix="oras/pokemon/",dir=ORAS_DIR,index=INDEX_ORAS,marker=MARKER_ORAS},
  orasfx={prefix="oras/movefx/",dir=ORASFX_DIR,index=INDEX_ORASFX,marker=MARKER_ORASFX},
  orasarena={prefix="oras/arenas/",dir=ORASARENA_DIR,index=INDEX_ORASARENA,marker=MARKER_ORASARENA},
}
local KIND_LIST={"pokemon","movefx","oras","orasfx","orasarena"}
A.KINDS=KINDS

local job=nil
local indexMemo={}

local function call(obj,name,...)
  if not obj or type(obj[name])~="function" then return nil,"unavailable" end
  local ok,a,b=pcall(obj[name],obj,...)
  if not ok then return nil,tostring(a) end
  return a,b
end

local function sep() return package.config:sub(1,1) end

-- WHERE UNITS ARE WRITTEN.  love.filesystem always writes the OS save
-- directory, but the index and markers go through mod.cache, which follows
-- the game-data folder the player picked.  Writing units with love.filesystem
-- split a pack in two: units on internal storage, index in the chosen folder,
-- so copying that folder to another device lost
-- every unit.  CacheFs.dataFs() is the engine's seam for exactly this: reads
-- and listing see every home (love.filesystem), writes/creates/removes go to
-- the live root.  With no folder chosen it is love.filesystem in effect.
local function unitFs()
  local ok,CacheFs=pcall(require,"src.import.CacheFs")
  if ok and type(CacheFs)=="table" and type(CacheFs.dataFs)=="function" then
    local okFs,fs=pcall(CacheFs.dataFs)
    if okFs and type(fs)=="table" then return fs,CacheFs end
  end
  return love.filesystem,nil
end

-- True when units are written somewhere other than the save directory.  Then
-- a stale copy of the same unit in the save directory must go: on Android the
-- chosen folder is mounted AFTER the save directory, so the old copy would
-- keep winning every read and the freshly written unit would never be seen.
local function rootIsElsewhere()
  local _,CacheFs=unitFs()
  if not (CacheFs and type(CacheFs.root)=="function") then return false end
  local okRoot,root=pcall(CacheFs.root)
  if not (okRoot and type(root)=="string" and root~="") then return false end
  local okSave,save=pcall(love.filesystem.getSaveDirectory)
  if not (okSave and type(save)=="string") then return true end
  local function norm(p) return (p:gsub("[/\\]+","/"):gsub("/$",""):lower()) end
  return norm(root)~=norm(save)
end

local function ensureDirFor(rel)
  local dir=rel:match("^(.*)/[^/]+$")
  if dir then unitFs().createDirectory(dir) end
end
-- Listing through love.filesystem (every home); removal through unitFs,
-- whose remove clears the live root AND the save directory, so a wipe does
-- not leave units behind in whichever home was used before.
local function rmrf(rel)
  local fs=unitFs()
  local info=love.filesystem.getInfo and love.filesystem.getInfo(rel)
  if not info then return end
  if info.type=="directory" then
    for _,name in ipairs(love.filesystem.getDirectoryItems(rel) or {}) do rmrf(rel.."/"..name) end
    pcall(fs.removeDir or fs.remove,rel)
  else
    pcall(fs.remove,rel)
  end
end

local function u32(n)
  n=math.floor(tonumber(n) or 0)%4294967296
  if n<0 then n=n+4294967296 end
  local b1=n%256;n=math.floor(n/256)
  local b2=n%256;n=math.floor(n/256)
  local b3=n%256;n=math.floor(n/256)
  return string.char(b1,b2,b3,n%256)
end
local function u16(n)
  n=math.floor(tonumber(n) or 0)%65536
  if n<0 then n=n+65536 end
  return string.char(n%256,math.floor(n/256))
end
local function ru32(s,i)
  local a,b,c,d=s:byte(i,i+3);if not d then return nil end
  return a+b*256+c*65536+d*16777216
end
local function ru16(s,i)
  local a,b=s:byte(i,i+1);if not b then return nil end
  return a+b*256
end

function A.available()
  if love and love.data and type(love.data.compress)=="function" and type(love.data.decompress)=="function" then
    return {label="LÖVE zlib",kind="zlib"}
  end
  return nil
end
function A.running()
  return job~=nil
end
-- the running job's progress label, without status()'s folder listing
function A.stage()
  return job and job.label or nil
end

local function compressBytes(raw)
  local tool=A.available()
  if not tool then return raw,0 end
  -- level 6: close to 9 in size, several times faster -- packing runs in
  -- the background while playing (auto-pack), one file is not interruptible
  local ok,out=pcall(love.data.compress,"string","zlib",raw,6)
  if ok and type(out)=="string" and #out>0 then return out,1 end
  return raw,0
end
local function decompressBytes(packed,codec)
  if tonumber(codec)~=1 then return packed end
  local ok,out=pcall(love.data.decompress,"string","zlib",packed)
  if ok and type(out)=="string" then return out end
  return nil
end

local function looseRead(path)
  local v=select(1,call(mod.cache,"read",path))
  return type(v)=="string" and v or nil
end
local function looseExists(path)
  local info=select(1,call(mod.cache,"info",path))
  return type(info)=="table" and (info.type==nil or info.type=="file")
end
local function looseWrite(path,bytes)
  return call(mod.cache,"write",path,bytes)
end
local function looseDelete(path)
  return call(mod.cache,"delete",path)
end

local function loadLua(raw)
  if type(raw)~="string" then return {} end
  local chunk=load(raw,"@generated/cache-archive-index")
  if not chunk then return {} end
  local ok,value=pcall(chunk)
  if not ok or type(value)~="table" then return {} end
  return value
end

local function emptyIndex()
  return {originalBytes=0,entries={},byUnit={},archiveBytes=0}
end

local function readIndex(kind)
  if indexMemo[kind] then return indexMemo[kind] end
  local path=KINDS[kind].index
  local v=loadLua(select(1,call(mod.cache,"read",path)))
  if type(v)~="table" then v=emptyIndex() end
  v.byUnit=v.byUnit or {};v.entries=v.entries or {}
  v.originalBytes=tonumber(v.originalBytes) or 0
  v.archiveBytes=tonumber(v.archiveBytes) or 0
  indexMemo[kind]=v
  return v
end

local function writeIndex(kind,idx)
  local path=KINDS[kind].index
  local out={"return {originalBytes=",tostring(math.floor(idx.originalBytes or 0)),
    ",archiveBytes=",tostring(math.floor(idx.archiveBytes or 0)),",entries={"}
  for p,size in pairs(idx.entries) do
    out[#out+1]=("[%q]=%d,"):format(p,math.floor(tonumber(size) or 0))
  end
  out[#out+1]="},byUnit={"
  for key,paths in pairs(idx.byUnit) do
    out[#out+1]=("[%q]={"):format(key)
    for _,p in ipairs(paths) do out[#out+1]=("%q,"):format(p) end
    out[#out+1]="},"
  end
  out[#out+1]="}}\n"
  indexMemo[kind]=idx
  return call(mod.cache,"write",path,table.concat(out))
end

-- plain prefix test.  (The old checks were find("^x",1,true): with plain
-- matching on, "^" is a literal character, so they never matched -- every
-- path read as "not a cache path", and a packed file could never be read back.)
local function startsWith(s,prefix) return s:sub(1,#prefix)==prefix end

local function pinnedLoose(path)
  if path=="cache/movefx/index.lua" or path=="build/movefx_coverage.txt" then return true end
  if path=="cache/pokemon/manifest.lua" or path=="cache/pokemon/_last_attempt.txt" then return true end
  if path:find("^cache/pokemon/manifest_v2/",1,false) then return true end
  -- per-species identity: PokemonExtractor.isCached reads these through
  -- mod.cache directly (not GeneratedAssets), so an archived one reads as
  -- "not extracted" and the species is extracted again
  local name=path:match("^cache/pokemon/%d+/([^/]+)$") or path:match("^cache/pokemon/%d+/shiny/([^/]+)$")
  if name=="model_cache.lua" or name=="rev.txt" or name=="extract.txt" then return true end
  if startsWith(path,"cache/archive_v1/") then return true end
  if startsWith(path,"build/cache_archive_") then return true end
  -- ORAS: the species list, and what ORASActorCache.build / ORASRuntime read
  -- through mod.cache directly (stamp, compact marker, "is it built")
  if path=="oras/pokemon/index.lua" then return true end
  local oname=path:match("^oras/pokemon/%d+/([^/]+)$")
  if oname=="rev.txt" or oname=="q16.txt" or oname=="ssc.txt" or oname=="model_cache.lua" or oname=="metadata_v1.lua" then return true end
  -- ORAS effects: the bake's index (stamp = "is it built") and the row settings
  if path:match("^oras/movefx/[^/]+$") then return true end
  -- ORAS arenas: the same (index.lua = "is it built", choice.txt = the row)
  if path:match("^oras/arenas/[^/]+$") then return true end
  return false
end

local function kindFor(path)
  if type(path)~="string" then return nil end
  if startsWith(path,"cache/pokemon/") then return "pokemon" end
  if startsWith(path,"cache/movefx/") then return "movefx" end
  if startsWith(path,"oras/pokemon/") then return "oras" end
  if startsWith(path,"oras/movefx/") then return "orasfx" end
  if startsWith(path,"oras/arenas/") then return "orasarena" end
  return nil
end

local function unitKey(kind,path)
  if kind=="oras" then
    return path:match("^oras/pokemon/(%d+)/") or "_meta"
  end
  if kind=="orasfx" then
    return path:match("^oras/movefx/([^/]+)/") or "_meta"
  end
  if kind=="orasarena" then
    return path:match("^oras/arenas/([^/]+)/") or "_meta"
  end
  if kind=="pokemon" then
    local dex,rest=path:match("^cache/pokemon/(%d+)/(.*)$")
    if not dex then return "_meta" end
    return dex..(rest:match("^shiny/") and "/shiny" or "/normal")
  end
  local stem=path:match("^cache/movefx/([^/]+)/")
  return stem or "_meta"
end

local function unitRel(kind,key)
  local safe=tostring(key):gsub("[^%w%-_]+","_")
  return KINDS[kind].dir.."/"..safe..".cbeu"
end

local function pumpEvents()
  if love and love.event and type(love.event.pump)=="function" then pcall(love.event.pump) end
end

----------------------------------------------------------------------
-- Inventory
----------------------------------------------------------------------
local function loadManifestChunk(raw)
  return loadLua(raw)
end

local function pokemonManifestPaths()
  local out={}
  local function take(raw)
    for _,e in ipairs(loadManifestChunk(raw)) do
      if type(e)=="table" and type(e.paths)=="table" then
        for _,path in ipairs(e.paths) do
          if type(path)=="string" then out[#out+1]=path end
        end
      end
    end
  end
  take(select(1,call(mod.cache,"read","cache/pokemon/manifest.lua")))
  for i=1,POKEMON_MANIFEST_SHARDS do
    take(select(1,call(mod.cache,"read",("cache/pokemon/manifest_v2/%02d.lua"):format(i))))
  end
  return out
end

local function generatedPrefixPaths(prefix)
  local out={}
  local raw=select(1,call(mod.cache,"read","build/generated_paths.lua"))
  local list=loadLua(raw)
  if type(list)=="table" then
    for _,path in ipairs(list) do
      if type(path)=="string" and path:find(prefix,1,true) then out[#out+1]=path end
    end
  end
  local registry=select(1,call(mod.cache,"read","build/hard_cache_registry_v1.lua"))
  local parsed=loadLua(registry)
  if type(parsed)=="table" and type(parsed.entries)=="table" then
    for path in pairs(parsed.entries) do
      if type(path)=="string" and path:find(prefix,1,true) then out[#out+1]=path end
    end
  end
  return out
end

local function addRuntimeSidecars(path,add)
  if type(path)~="string" or not path:find("%.lua$") then return end
  -- a sidecar's own base.lua has no sidecars: without this check every
  -- base.lua queued <it>_runtime_v1/base.lua, forever (stack overflow, and
  -- the pack job died before writing a single unit)
  if path:find("_runtime_v1/",1,true) then return end
  local root=path:gsub("%.lua$","").."_runtime_v1"
  add(root.."/base.lua")
  for i=0,48 do add(root..("/base_%02d.f32"):format(i)) end
end

local function collectMovefxFromIndex(add)
  local index=loadLua(select(1,call(mod.cache,"read","cache/movefx/index.lua")))
  local seenStem={}
  for _,row in pairs(type(index)=="table" and index.moves or {}) do
    local stem=type(row)=="table" and tostring(row.stem or "") or ""
    if stem~="" and not seenStem[stem] then
      seenStem[stem]=true
      local effect="cache/movefx/"..stem.."/effect.lua"
      add(effect)
      local raw=select(1,call(mod.cache,"read",effect))
      if type(raw)=="string" then
        for quoted in raw:gmatch('"cache/movefx/[^"]+"') do
          add(quoted:sub(2,-2))
        end
      end
    end
  end
end

-- Every stored key under `prefix`.  Walks the host store's folder directly
-- (mod.cache.storage: root + fs, files are <key>.bin / <key>.rec), which does
-- not depend on mod.cache:list; falls back to that.  Returns keys, method.
local function listKeys(prefix)
  local store=mod.cache and mod.cache.storage
  local root=type(store)=="table" and store.root
  local fs=(type(store)=="table" and type(store.fs)=="table" and store.fs) or love.filesystem
  if type(root)=="string" and fs and fs.getDirectoryItems and fs.getInfo then
    local out={}
    local function walk(dir)
      for _,name in ipairs(fs.getDirectoryItems(dir) or {}) do
        local path=dir.."/"..name
        local info=fs.getInfo(path)
        if info and info.type=="directory" then walk(path)
        else
          local key=path:sub(#root+2)
          local stem=key:match("^(.*)%.bin$") or key:match("^(.*)%.rec$")
          if stem then out[#out+1]=stem end
        end
      end
      if WorkBudget then WorkBudget.checkpoint("PACK: listing "..prefix) end
    end
    local info=fs.getInfo(root.."/"..prefix)
    if info and info.type=="directory" then
      walk(root.."/"..prefix)
      if #out>0 then return out,"store walk" end
    end
  end
  local listed=select(1,call(mod.cache,"list",prefix))
  if type(listed)=="table" then return listed,"mod.cache:list" end
  return {},"none"
end

local function queueFor(kind)
  local seen,queue={},{}
  local function add(path)
    if type(path)~="string" or seen[path] or pinnedLoose(path) then return end
    seen[path]=true
    if looseExists(path) then
      queue[#queue+1]={path=path,key=unitKey(kind,path)}
    end
    addRuntimeSidecars(path,add)
  end
  -- Preferred: the files that are really there (host mod.cache:list).  This
  -- also takes the runtime action sidecars (runtime_mesh_v1/action_*) that
  -- the manifest walk below never named.
  local listed,method=listKeys((KINDS[kind].prefix:gsub("/$","")))
  A.lastListing={kind=kind,method=method,keys=#listed}
  if #listed>0 then
    for _,path in ipairs(listed) do
      if type(path)=="string" and not seen[path] and not pinnedLoose(path) and kindFor(path)==kind then
        seen[path]=true
        queue[#queue+1]={path=path,key=unitKey(kind,path)}
      end
    end
    A.lastListing.queued=#queue
    -- a listing that named nothing usable falls through to the manifest walk
    if #queue>0 then return queue end
    A.lastListing.method=method.." (unusable, manifest walk)"
  end
  if kind=="oras" or kind=="orasfx" or kind=="orasarena" then
    -- no manifest to walk: the store listing is the only source
  elseif kind=="pokemon" then
    for _,path in ipairs(pokemonManifestPaths()) do add(path) end
    for _,path in ipairs(generatedPrefixPaths("cache/pokemon/")) do add(path) end
  else
    for _,path in ipairs(generatedPrefixPaths("cache/movefx/")) do add(path) end
    collectMovefxFromIndex(add)
  end
  return queue
end

----------------------------------------------------------------------
-- Unit codec
----------------------------------------------------------------------
-- The records of an existing unit, still compressed: { {path,rawSize,codec,packed} }.
local function unitRecords(bytes)
  if type(bytes)~="string" or #bytes<16 or bytes:sub(1,8)~=MAGIC then return nil end
  local out,i={},17
  for _=1,ru32(bytes,13) or 0 do
    local plen=ru16(bytes,i);if not plen then break end
    i=i+2
    local path=bytes:sub(i,i+plen-1);i=i+plen
    local rawSize=ru32(bytes,i);local codec=bytes:byte(i+4);local packedSize=ru32(bytes,i+5)
    if not (rawSize and codec and packedSize) then break end
    i=i+9
    out[#out+1]={path=path,rawSize=rawSize,codec=codec,packed=bytes:sub(i,i+packedSize-1)}
    i=i+packedSize
  end
  return out
end

-- Where each entry of a unit sits, read from its headers once (File:seek
-- past the data): unitTables[rel][path] = {pos, rawSize, codec, size}.  A
-- read then fetches and inflates just that entry.
local unitTables={}
local openRel,openFile=nil,nil
local function closeUnit(rel)
  if openFile and (rel==nil or rel==openRel) then pcall(openFile.close,openFile);openFile=nil;openRel=nil end
  if rel then unitTables[rel]=nil else unitTables={} end
end
local function unitTable(rel)
  local t=unitTables[rel];if t then return t end
  local f=love.filesystem.newFile and love.filesystem.newFile(rel)
  if not (f and f:open("r")) then return nil end
  t={}
  local head=f:read(16)
  if type(head)=="string" and #head==16 and head:sub(1,8)==MAGIC then
    local pos=16
    for _=1,ru32(head,13) or 0 do
      local h=f:read(2);if not h or #h<2 then break end
      local plen=ru16(h,1)
      local path=f:read(plen);local meta=f:read(9)
      if not (path and meta and #meta==9) then break end
      pos=pos+2+plen+9
      local size=ru32(meta,6)
      t[path]={pos=pos,rawSize=ru32(meta,1),codec=meta:byte(5),size=size}
      pos=pos+size
      f:seek(pos)
    end
  end
  f:close()
  unitTables[rel]=t
  return t
end
local function readFromUnit(rel,path)
  local t=unitTable(rel);local e=t and t[path]
  if not e then return nil,"entry not in unit file" end
  if openRel~=rel then
    closeUnit(openRel and openRel or nil)
    unitTables[rel]=t
    local f=love.filesystem.newFile(rel)
    if not (f and f:open("r")) then return nil,"unit file unreadable" end
    openFile,openRel=f,rel
  end
  openFile:seek(e.pos)
  local packed=openFile:read(e.size)
  local bytes=decompressBytes(packed,e.codec)
  if type(bytes)~="string" or #bytes~=e.rawSize then return nil,"unit entry inflate failed" end
  return bytes
end

-- Writes `items` into unit `rel`.  An existing unit keeps every entry that
-- `items` does not replace: a second pack used to rewrite the unit with only
-- its new files, losing everything the first pack had put there (whose loose
-- originals were already deleted).
local function writeUnit(rel,items)
  ensureDirFor(rel)
  closeUnit(rel)
  local keep={}
  do
    local replacing={}
    for _,item in ipairs(items) do replacing[item.path]=true end
    local old=love.filesystem.getInfo(rel) and love.filesystem.read(rel)
    for _,r in ipairs(unitRecords(old) or {}) do
      if not replacing[r.path] then keep[#keep+1]=r end
    end
  end
  local fs=unitFs()
  fs.createDirectory(rel:match("^(.*)/") or ARCHIVE_ROOT)
  local f=fs.newFile and fs.newFile(rel)
  if not (f and f.open) then return nil,"newFile unavailable" end
  local okOpen,errOpen=f:open("w")
  if not okOpen then return nil,tostring(errOpen or "could not open unit file") end
  local function emit(s)
    local okw,errw=f:write(s)
    if okw==false or okw==nil then error("unit write failed: "..tostring(errw or "unknown"),0) end
  end
  emit(MAGIC)
  emit(u32(VERSION))
  emit(u32(#items+#keep))
  for _,r in ipairs(keep) do
    emit(u16(#r.path));emit(r.path);emit(u32(r.rawSize));emit(string.char(r.codec));emit(u32(#r.packed));emit(r.packed)
  end
  local original=0
  local packedTotal=16
  for _,item in ipairs(items) do
    local raw=item.bytes
    local packed,codec=compressBytes(raw)
    emit(u16(#item.path))
    emit(item.path)
    emit(u32(#raw))
    emit(string.char(codec))
    emit(u32(#packed))
    emit(packed)
    original=original+#raw
    packedTotal=packedTotal+2+#item.path+4+1+4+#packed
    item.bytes=nil
    if WorkBudget then WorkBudget.checkpoint(("PACK %s"):format(item.path)) end
    pumpEvents()
  end
  f:close()
  -- the merged unit now lives in the live root; a save-directory copy would
  -- shadow it (see rootIsElsewhere) and its entries are already in `keep`
  if rootIsElsewhere() then pcall(love.filesystem.remove,rel) end
  return original,packedTotal
end

local function parseUnit(bytes,wanted)
  if type(bytes)~="string" or #bytes<16 or bytes:sub(1,8)~=MAGIC then return nil,"not a CBE unit" end
  local ver=ru32(bytes,9);if ver~=VERSION then return nil,"unsupported unit version" end
  local count=ru32(bytes,13) or 0
  local i=17
  local files={}
  for _=1,count do
    local plen=ru16(bytes,i);if not plen then return nil,"truncated unit" end
    i=i+2
    local path=bytes:sub(i,i+plen-1);i=i+plen
    local rawSize=ru32(bytes,i);i=i+4
    local codec=bytes:byte(i);i=i+1
    local packedSize=ru32(bytes,i);i=i+4
    local packed=bytes:sub(i,i+packedSize-1);i=i+packedSize
    if wanted==nil or wanted==path then
      local raw=decompressBytes(packed,codec)
      if type(raw)~="string" or (rawSize and #raw~=rawSize) then return nil,"unit decompress failed: "..tostring(path) end
      files[path]=raw
      if wanted then return files end
    end
  end
  return files
end

local function verifyUnit(rel,items)
  local bytes=love.filesystem.read(rel)
  if type(bytes)~="string" then return false,"unit missing after write" end
  local files,err=parseUnit(bytes,items[1] and items[1].path or nil)
  if not files then return false,err end
  local first=items[1]
  if first and files[first.path]~=first.verify then return false,"unit round-trip mismatch" end
  return true
end

----------------------------------------------------------------------
-- Status / public lookup
----------------------------------------------------------------------
function A.contains(path)
  local kind=kindFor(path)
  if not kind or pinnedLoose(path) then return false end
  local idx=readIndex(kind)
  return idx.entries[path]~=nil
end

function A.infoEntry(path)
  local kind=kindFor(path)
  if not kind then return nil end
  local idx=readIndex(kind)
  local size=idx.entries[path]
  if not size then return nil end
  return {type="file",size=tonumber(size) or 0,archived=true}
end

local function archiveBytesOnDisk(kind)
  local dir=KINDS[kind].dir
  local info=love.filesystem.getInfo and love.filesystem.getInfo(dir)
  if not (info and info.type=="directory") then
    local idx=readIndex(kind)
    return tonumber(idx.archiveBytes) or 0
  end
  local total=0
  for _,name in ipairs(love.filesystem.getDirectoryItems(dir) or {}) do
    local row=love.filesystem.getInfo(dir.."/"..name)
    if row and row.size then total=total+row.size end
  end
  return total
end

local function prettyBytes(n)
  n=tonumber(n) or 0
  if n>=1024^3 then return ("%.2f GiB"):format(n/(1024^3)) end
  if n>=1024^2 then return ("%.1f MiB"):format(n/(1024^2)) end
  if n>=1024 then return ("%.1f KiB"):format(n/1024) end
  return tostring(n).." B"
end

function A.status()
  local tool=A.available()
  local p=readIndex("pokemon")
  local m=readIndex("movefx")
  local o=readIndex("oras")
  local x=readIndex("orasfx")
  local pBytes=archiveBytesOnDisk("pokemon")
  local mBytes=archiveBytesOnDisk("movefx")
  local oBytes=archiveBytesOnDisk("oras")
  local xBytes=archiveBytesOnDisk("orasfx")
  local r=readIndex("orasarena")
  local rBytes=archiveBytesOnDisk("orasarena")
  local rCount=0
  for _ in pairs(r.entries) do rCount=rCount+1 end
  -- totals are the Colosseum caches (the PACK CACHE menu); ORAS has its own
  -- fields below (ORAS MODELS reports them)
  local original=(p.originalBytes or 0)+(m.originalBytes or 0)
  local packed=pBytes+mBytes
  local pCount,mCount,oCount,xCount=0,0,0,0
  for _ in pairs(p.entries) do pCount=pCount+1 end
  for _ in pairs(m.entries) do mCount=mCount+1 end
  for _ in pairs(o.entries) do oCount=oCount+1 end
  for _ in pairs(x.entries) do xCount=xCount+1 end
  local pokemonPacked=looseExists(MARKER_POKEMON)
  local movefxPacked=looseExists(MARKER_MOVEFX)
  local orasPacked=looseExists(MARKER_ORAS)
  return {
    toolAvailable=tool and true or false,
    toolLabel=tool and tool.label or "LÖVE zlib unavailable",
    running=job~=nil,
    stage=job and job.label or ((pokemonPacked or movefxPacked) and "READY" or "NOT PACKED"),
    error=(job and job.error) or A.lastError,
    pokemonPacked=pokemonPacked and true or false,
    movefxPacked=movefxPacked and true or false,
    orasPacked=orasPacked and true or false,
    pokemonEntries=pCount,
    movefxEntries=mCount,
    orasEntries=oCount,
    orasArchiveLabel=prettyBytes(oBytes),
    orasOriginalLabel=prettyBytes(o.originalBytes or 0),
    orasfxPacked=looseExists(MARKER_ORASFX) and true or false,
    orasfxEntries=xCount,
    orasfxArchiveLabel=prettyBytes(xBytes),
    orasfxOriginalLabel=prettyBytes(x.originalBytes or 0),
    orasarenaPacked=looseExists(MARKER_ORASARENA) and true or false,
    orasarenaEntries=rCount,
    orasarenaArchiveLabel=prettyBytes(rBytes),
    orasarenaOriginalLabel=prettyBytes(r.originalBytes or 0),
    originalBytes=original,
    archiveBytes=packed,
    savedBytes=math.max(0,original-packed),
    originalLabel=prettyBytes(original),
    archiveLabel=prettyBytes(packed),
    savedLabel=prettyBytes(math.max(0,original-packed)),
    ratio=original>0 and packed/original or nil,
  }
end

----------------------------------------------------------------------
-- Packing
----------------------------------------------------------------------
local function looseStamp(path)
  local info=select(1,call(mod.cache,"info",path))
  if type(info)~="table" then return nil end
  return tostring(info.size).."@"..tostring(info.modtime)
end

-- Pack loose files of `kind` into their units.  `onlyKeys` (set of unit
-- keys, e.g. {["6/normal"]=true}) limits it to those species / moves.  A
-- loose file already archived is deleted when equal to the archived copy and
-- packed again (replacing it in the unit) when it differs -- a species
-- extracted again.  A loose file is deleted only if it did not change while
-- it was being packed (size + modtime).
-- ORAS species built before paged action banks keep the old unpaged files
-- (runtime_mesh_v1/action_<name>_NN.f32, action_<name>_floor.lua) next to the
-- paged ones; once a manifest lists pages, nothing reads them.  Returns the
-- set of such paths among `paths` -- only for actions whose first paged bank
-- is really there (a species missing it is rebuilt by ORAS MODELS instead).
local function orasDeadFiles(paths)
  local have={}
  for _,p in ipairs(paths) do have[p]=true end
  local dead={}
  for _,p in ipairs(paths) do
    local dir,name=p:match("^(oras/pokemon/%d+/runtime_mesh_v1)/action_(%w+)%.lua$")
    if name then
      local meta=loadLua(looseRead(p))
      if type(meta.pages)=="table" and #meta.pages>0 and not meta.alias
          and have[("%s/action_%s_page1_01.f32"):format(dir,name)] then
        local stem=dir.."/action_"..name.."_"
        for _,q in ipairs(paths) do
          if q:sub(1,#stem)==stem then
            local rest=q:sub(#stem+1)
            if rest:match("^%d%d%.f32$") or rest=="floor.lua" then dead[q]=true end
          end
        end
      end
    end
  end
  return dead
end
A._orasDeadFiles=orasDeadFiles   -- offline tests

local function packKind(kind,onlyKeys)
  if not A.available() then error("love.data.compress (zlib) is unavailable on this host",0) end
  unitFs().createDirectory(ARCHIVE_ROOT)
  unitFs().createDirectory(KINDS[kind].dir)
  local idx=readIndex(kind)
  local source
  if onlyKeys then
    source={}
    local root=KINDS[kind].prefix
    local seenPrefix={}
    for key in pairs(onlyKeys) do
      local prefix=root..(kind~="pokemon" and tostring(key) or tostring(key):match("^(%d+)") or tostring(key))
      if not seenPrefix[prefix] then
        seenPrefix[prefix]=true
        for _,path in ipairs((listKeys(prefix))) do
          if not pinnedLoose(path) and kindFor(path)==kind and onlyKeys[unitKey(kind,path)] then
            source[#source+1]={path=path,key=unitKey(kind,path)}
          end
        end
      end
    end
  else
    source=queueFor(kind)
  end
  if kind=="oras" then
    local all={}
    for _,item in ipairs(source) do all[#all+1]=item.path end
    local dead=orasDeadFiles(all)
    if next(dead) then
      local kept,dropped={},0
      for _,item in ipairs(source) do
        if dead[item.path] then
          looseDelete(item.path);dropped=dropped+1
          local G=V.GeneratedAssets
          if G and G.invalidateInfo then G.invalidateInfo(item.path) end
        else kept[#kept+1]=item end
      end
      source=kept
      A.lastDeadDropped=(A.lastDeadDropped or 0)+dropped
    end
  end
  local queue={}
  for _,item in ipairs(source) do
    if idx.entries[item.path] then
      if WorkBudget then WorkBudget.checkpoint(("PACK %s: loose duplicates"):format(kind:upper())) end
      local loose=looseRead(item.path)
      local packed=loose and A.readEntry(item.path)
      if loose~=nil and loose==packed then
        looseDelete(item.path)
        local G=V.GeneratedAssets
        if G and G.invalidateInfo then G.invalidateInfo(item.path) end
      elseif loose~=nil then
        queue[#queue+1]=item
      end
    else
      queue[#queue+1]=item
    end
  end
  local byUnit={}
  for _,item in ipairs(queue) do
    local u=byUnit[item.key];if not u then u={key=item.key,items={}};byUnit[item.key]=u end
    u.items[#u.items+1]=item
  end
  local units={}
  for _,u in pairs(byUnit) do units[#units+1]=u end
  table.sort(units,function(a,b) return tostring(a.key)<tostring(b.key) end)

  for ui,unit in ipairs(units) do
    if WorkBudget then WorkBudget.checkpoint(("PACK %s %d/%d"):format(kind:upper(),ui,#units)) end
    local batch={}
    for _,item in ipairs(unit.items) do
      local stamp=looseStamp(item.path)
      local bytes=looseRead(item.path)
      if type(bytes)=="string" then
        local row={path=item.path,bytes=bytes,key=item.key,size=#bytes,stamp=stamp}
        if #batch==0 then row.verify=bytes end
        batch[#batch+1]=row
      end
      if WorkBudget then WorkBudget.checkpoint(("PACK %s %d/%d"):format(kind:upper(),ui,#units)) end
    end
    if #batch>0 then
      local rel=unitRel(kind,unit.key)
      local original,packedTotal=writeUnit(rel,batch)
      local ok,why=verifyUnit(rel,batch)
      if not ok then error(("archive verify failed [%s/%s], originals kept: %s"):format(kind,tostring(unit.key),tostring(why)),0) end
      local paths=idx.byUnit[unit.key] or {}
      local listed={}
      for _,pth in ipairs(paths) do listed[pth]=true end
      for _,item in ipairs(batch) do
        if idx.entries[item.path] then
          idx.originalBytes=math.max(0,(idx.originalBytes or 0)-(tonumber(idx.entries[item.path]) or 0))
        end
        idx.entries[item.path]=item.size
        if not listed[item.path] then paths[#paths+1]=item.path;listed[item.path]=true end
      end
      idx.byUnit[unit.key]=paths
      idx.originalBytes=(idx.originalBytes or 0)+(tonumber(original) or 0)
      idx.archiveBytes=archiveBytesOnDisk(kind)
      writeIndex(kind,idx)
      for _,item in ipairs(batch) do
        if item.stamp==nil or looseStamp(item.path)==item.stamp then
          looseDelete(item.path)
        end
        local G=V.GeneratedAssets
        if G and G.invalidateInfo then G.invalidateInfo(item.path) end
      end
    end
    pumpEvents()
  end

  writeIndex(kind,idx)
  if not onlyKeys then
    local L=A.lastListing or {}
    looseWrite(("build/cache_archive_%s_report.txt"):format(kind),
      ("listing=%s\nkeys=%s\nqueued=%s\nunits=%d\nfiles=%d\n"):format(tostring(L.method),tostring(L.keys),tostring(L.queued),#units,#queue))
    local marker=KINDS[kind].marker
    local n=0;for _ in pairs(idx.entries) do n=n+1 end
    looseWrite(marker,("cbe-cache-archive=1\nkind=%s\nentries=%d\n"):format(kind,n))
  end
  return true
end

local function packBody(scope)
  scope=scope or "all"
  -- "all" is the Colosseum caches; ORAS is packed only on its own scope, by
  -- ORAS MODELS (lib/ORASModels.lua) -- the two games are independent imports
  if scope=="all" or scope=="pokemon" then packKind("pokemon") end
  if scope=="all" or scope=="movefx" then packKind("movefx") end
  if scope=="oras" then packKind("oras") end
  if scope=="orasfx" then packKind("orasfx") end
  if scope=="orasarena" then packKind("orasarena") end
  return true
end

function A.beginPack(scope)
  if job then return false,"already running" end
  if not WorkBudget then return false,"WorkBudget module unavailable" end
  if not A.available() then return false,"love.data.compress unavailable" end
  scope=scope or "all"
  local label=scope=="pokemon" and "PACKING POKEMON CACHE"
    or (scope=="movefx" and "PACKING MOVEFX CACHE")
    or (scope=="oras" and "PACKING ORAS MODELS")
    or (scope=="orasfx" and "PACKING ORAS EFFECTS")
    or (scope=="orasarena" and "PACKING ORAS ARENAS" or "PACKING POKEMON + MOVEFX")
  A.lastError=nil
  local co=WorkBudget.new(function()
    local ok,err=xpcall(function() packBody(scope) end,debug.traceback)
    if not ok then
      job.error=tostring(err)
      -- kept after the job ends so the menu can show it (status().error)
      A.lastError=job.error
      call(mod.cache,"write","build/cache_archive_error.txt",job.error)
      return false
    end
    return true
  end,label)
  job={co=co,label=label,error=nil}
  return true,"Packing started. Loose files are removed only after each unit verifies."
end

----------------------------------------------------------------------
-- Auto-pack: a species / move whose cache was just written is packed in
-- the background once nothing has written to it for AUTO_SETTLE seconds,
-- so an install never grows the full loose cache.  A.autoPack = false
-- turns it off (PACK CACHE still works by hand).
----------------------------------------------------------------------
A.autoPack=true
local AUTO_SETTLE=20
local dirty={pokemon={},movefx={},oras={},orasfx={},orasarena={}}
local function now()
  if love and love.timer and love.timer.getTime then return love.timer.getTime() end
  return os.clock()
end
-- kind "pokemon": key = dex (number or "<dex>/normal|shiny"); "movefx": stem;
-- "oras": dex
function A.markDirty(kind,key)
  if not dirty[kind] or key==nil then return end
  key=tostring(key)
  if kind=="pokemon" and not key:find("/",1,true) then
    dirty.pokemon[key.."/normal"]=now();dirty.pokemon[key.."/shiny"]=now()
  else
    dirty[kind][key]=now()
  end
end
-- once a frame: start a background pack of the units that have settled
function A.tick()
  if job or not A.autoPack or not WorkBudget or not A.available() then return false end
  local t=now()
  for _,kind in ipairs(KIND_LIST) do
    local ready=nil
    for key,at in pairs(dirty[kind]) do
      if t-at>=AUTO_SETTLE then ready=ready or {};ready[key]=true end
    end
    if ready then
      for key in pairs(ready) do dirty[kind][key]=nil end
      local label="AUTO-PACKING "..kind:upper()
      local co=WorkBudget.new(function()
        local ok,err=xpcall(function() packKind(kind,ready) end,debug.traceback)
        if not ok then
          job.error=tostring(err);A.lastError=job.error
          call(mod.cache,"write","build/cache_archive_error.txt",job.error)
          return false
        end
        return true
      end,label)
      job={co=co,label=label,error=nil,auto=true}
      return true
    end
  end
  return false
end

-- One background pass after an install that used the old reader: the
-- species it unpacked whole (cache/archive_v1/hot.lua) left loose copies of
-- archived files behind; equal ones are deleted.
-- Mark every unit of `kind` that has loose (unpacked) files; returns count.
function A.scanLoose(kind)
  local n=0
  for _,path in ipairs((listKeys((KINDS[kind].prefix:gsub("/$",""))))) do
    if not pinnedLoose(path) and kindFor(path)==kind then
      local key=unitKey(kind,path)
      if dirty[kind] and not dirty[kind][key] then dirty[kind][key]=0;n=n+1 end
    end
  end
  return n
end

function A.dropHotCopies()
  local raw=select(1,call(mod.cache,"read",HOT_PATH))
  if type(raw)~="string" then return false end
  local hot=loadLua(raw)
  for _,name in ipairs(type(hot.order)=="table" and hot.order or {}) do
    local kind,key=tostring(name):match("^([^/]+)/(.*)$")
    if dirty[kind] and key then dirty[kind][key]=0 end
  end
  looseDelete(HOT_PATH)
  return true
end

function A.pump(budgetMs)
  if not job then return "idle" end
  local ok,state=WorkBudget.resume(job.co,budgetMs or 40)
  if not ok then
    local err=job.error or tostring(state);job=nil
    A.lastError=A.lastError or err
    return "error",err
  end
  if state=="done" then
    local finished=job;job=nil
    return finished.error and "error" or "done",finished.error
  end
  job.label=WorkBudget.label(job.co) or job.label
  return "working"
end

function A.cancelPack()
  if not job then return false end
  WorkBudget.cancel(job.co)
  job=nil
  return true
end

----------------------------------------------------------------------
-- Rehydrate
----------------------------------------------------------------------
local function readHotLog()
  local v=loadLua(select(1,call(mod.cache,"read",HOT_PATH)))
  if type(v)~="table" then v={order={},bytes=0} end
  v.order=v.order or {};v.bytes=tonumber(v.bytes) or 0
  return v
end
local function writeHotLog(hot)
  local out={"return {bytes=",tostring(math.floor(hot.bytes or 0)),",order={"}
  for _,key in ipairs(hot.order) do out[#out+1]=("%q,"):format(key) end
  out[#out+1]="}}\n"
  call(mod.cache,"write",HOT_PATH,table.concat(out))
end

local function hotName(kind,key) return kind.."/"..tostring(key) end

local function evictOldest(hot)
  local name=table.remove(hot.order,1)
  if not name then return 0 end
  local kind,key=name:match("^([^/]+)/(.*)$")
  if not kind then return 0 end
  local idx=readIndex(kind)
  local freed=0
  for _,path in ipairs(idx.byUnit[key] or {}) do
    local size=idx.entries[path]
    looseDelete(path)
    local G=V.GeneratedAssets
    if G and G.invalidateInfo then G.invalidateInfo(path) end
    freed=freed+(tonumber(size) or 0)
  end
  return freed
end

-- One archived file, straight from its unit: no loose copy is written (the
-- old reader unpacked the whole species -- ~150 MB of writes, the hitch --
-- and kept up to 1.5 GB of such copies around).
function A.readEntry(path)
  local kind=kindFor(path)
  if not kind then return nil,"not an archived cache path" end
  if pinnedLoose(path) then return nil,"identity file is not archived" end
  local idx=readIndex(kind)
  if not idx.entries[path] then return nil,"path not present in archive" end
  if not A.available() then return nil,"love.data.decompress unavailable" end
  return readFromUnit(unitRel(kind,unitKey(kind,path)),path)
end

-- One pass after an install packed with the old rules: the identity files
-- now pinned loose (pinnedLoose) that sit only inside a unit are written back
-- loose.  Reads unit HEADERS and only the wanted entries (File:seek past the
-- rest), so it does not inflate the archive.  Returns restored, missing.
local PINNED_RESTORE_MARKER="build/cache_archive_pinned_v2.complete"
local function readUnitEntries(rel,wanted)
  local f=love.filesystem.newFile and love.filesystem.newFile(rel)
  if not (f and f:open("r")) then return nil end
  local out={}
  local head=f:read(16)
  if type(head)~="string" or #head<16 or head:sub(1,8)~=MAGIC then f:close();return nil end
  local pos=16
  for _=1,ru32(head,13) or 0 do
    local h=f:read(2);if not h or #h<2 then break end
    local plen=ru16(h,1)
    local path=f:read(plen)
    local meta=f:read(9)
    if not (path and meta and #meta==9) then break end
    local rawSize,codec,packedSize=ru32(meta,1),meta:byte(5),ru32(meta,6)
    pos=pos+2+plen+9
    if wanted[path] then
      local packed=f:read(packedSize)
      local raw=decompressBytes(packed,codec)
      if type(raw)=="string" and #raw==rawSize then out[path]=raw end
    else
      f:seek(pos+packedSize)
    end
    pos=pos+packedSize
  end
  f:close()
  return out
end
function A.restorePinned(force)
  if not force and looseExists(PINNED_RESTORE_MARKER) then return 0,0 end
  local restored,missing=0,0
  for _,kind in ipairs(KIND_LIST) do
    local idx=readIndex(kind)
    for key,paths in pairs(idx.byUnit or {}) do
      local wanted,any={},false
      for _,p in ipairs(paths) do
        if pinnedLoose(p) and not looseExists(p) then wanted[p]=true;any=true end
      end
      if any then
        local files=readUnitEntries(unitRel(kind,key),wanted) or {}
        for p in pairs(wanted) do
          if files[p] then looseWrite(p,files[p]);restored=restored+1 else missing=missing+1 end
        end
      end
    end
  end
  looseWrite(PINNED_RESTORE_MARKER,("restored=%d\nmissing=%d\n"):format(restored,missing))
  return restored,missing
end

-- One pass for an archive damaged by the old writeUnit: a unit missing any
-- entry its index lists is dropped whole (unit file + index rows), and the
-- loose identity that says "built" is removed -- the species' rev.txt, the
-- move's effect.lua -- so it is extracted again from the disc, as on a fresh
-- install.  Returns dropped units, lost entries.
local REPAIR_MARKER="build/cache_archive_repair_v1.complete"
local function unitPaths(rel)
  local f=love.filesystem.newFile and love.filesystem.newFile(rel)
  if not (f and f:open("r")) then return nil end
  local have={}
  local head=f:read(16)
  if type(head)~="string" or #head<16 or head:sub(1,8)~=MAGIC then f:close();return nil end
  local pos=16
  for _=1,ru32(head,13) or 0 do
    local h=f:read(2);if not h or #h<2 then break end
    local plen=ru16(h,1)
    local path=f:read(plen);local meta=f:read(9)
    if not (path and meta and #meta==9) then break end
    have[path]=true
    pos=pos+2+plen+9+ru32(meta,6)
    f:seek(pos)
  end
  f:close()
  return have
end
function A.repairLostEntries(force)
  if not force and looseExists(REPAIR_MARKER) then return 0,0 end
  -- A folder that is not visible is not a damaged archive.  When NOT ONE
  -- listed unit can be opened (the cache was moved to a custom game-data
  -- folder that is not mounted yet, or only the index was copied), dropping
  -- everything would empty the index for good and mark the repair done, so
  -- the packed cache would stay ignored after the folder shows up.  Leave it
  -- alone, keep the repair pending, and say so.
  local listed,readable=0,0
  for _,kind in ipairs(KIND_LIST) do
    for key in pairs(readIndex(kind).byUnit or {}) do
      listed=listed+1
      if readable==0 and unitPaths(unitRel(kind,key)) then readable=1 end
      if readable>0 then break end
    end
    if readable>0 then break end
  end
  if listed>0 and readable==0 then
    if mod and mod.log and mod.log.warn then
      pcall(mod.log.warn,mod.log,"CacheArchive: none of the %d+ packed units in the index can be opened (%s missing or not on the read path); index left untouched",listed,ARCHIVE_ROOT)
    end
    A.unitsUnreadable=true
    return 0,0
  end
  local dropped,lost=0,0
  for _,kind in ipairs(KIND_LIST) do
    local idx=readIndex(kind)
    local changed=false
    for key,paths in pairs(idx.byUnit or {}) do
      local rel=unitRel(kind,key)
      local have=unitPaths(rel) or {}
      local missing=0
      for _,p in ipairs(paths) do if not have[p] then missing=missing+1 end end
      if missing>0 then
        lost=lost+missing;dropped=dropped+1;changed=true
        for _,p in ipairs(paths) do
          idx.originalBytes=math.max(0,(idx.originalBytes or 0)-(tonumber(idx.entries[p]) or 0))
          idx.entries[p]=nil
          local G=V.GeneratedAssets
          if G and G.invalidateInfo then G.invalidateInfo(p) end
        end
        idx.byUnit[key]=nil
        closeUnit(rel)
        pcall(unitFs().remove,rel)
        if kind=="oras" then
          -- ORAS MODELS rebuilds a species whose stamp is gone
          looseDelete(("oras/pokemon/%s/rev.txt"):format(tostring(key)))
        elseif kind=="orasfx" then
          -- no index = not built: ORAS EFFECTS bakes everything again
          looseDelete("oras/movefx/index.lua")
        elseif kind=="orasarena" then
          -- the same for ORAS ARENAS
          looseDelete("oras/arenas/index.lua")
        elseif kind=="pokemon" then
          local dex,variant=tostring(key):match("^(%d+)/(%a+)$")
          if dex then looseDelete(("cache/pokemon/%s%s/rev.txt"):format(dex,variant=="shiny" and "/shiny" or "")) end
        else
          looseDelete(("cache/movefx/%s/effect.lua"):format(tostring(key)))
        end
      end
    end
    if changed then
      idx.archiveBytes=archiveBytesOnDisk(kind)
      writeIndex(kind,idx)
      looseDelete(KINDS[kind].marker)
    end
  end
  -- GeneratedAssets' persisted size registry still lists the lost files as
  -- present; it is only a probe cache (Hard Cache Save writes it again)
  if dropped>0 then looseDelete("build/hard_cache_registry_v1.lua") end
  looseWrite(REPAIR_MARKER,("dropped=%d\nlost=%d\n"):format(dropped,lost))
  return dropped,lost
end

-- Drops one kind's units, index and marker (the loose files are untouched).
-- ORAS EFFECTS calls it after a bake on a packed install: the bake has just
-- written every file loose again, so the old units only hold stale copies.
function A.wipeKind(kind)
  if not KINDS[kind] or job then return false end
  closeUnit(nil)
  rmrf(KINDS[kind].dir)
  looseDelete(KINDS[kind].index);looseDelete(KINDS[kind].marker)
  indexMemo[kind]=nil
  dirty[kind]={}
  return true
end

function A.wipe()
  closeUnit(nil)   -- an open unit cannot be deleted on Windows
  rmrf(ARCHIVE_ROOT)
  for _,kind in ipairs(KIND_LIST) do looseDelete(KINDS[kind].index);looseDelete(KINDS[kind].marker) end
  looseDelete(HOT_PATH)
  indexMemo={}
  job=nil
  return true
end

-- Hooks a GeneratedAssets instance so packed files read like loose ones.
-- Default: the one this module was loaded with (V.GeneratedAssets).  The
-- ORAS-only runtime (lib/ORASRuntime.lua) loads its own copy and passes it.
function A.install(G)
  G=G or V.GeneratedAssets
  if not (G and not G._cacheArchiveInstalled) then return G end
  G._cacheArchiveInstalled=true
  local origRead,origInfo=G.read,G.info
  function G.info(path)
    path=tostring(path or "")
    local hit=origInfo(path)
    if type(hit)=="table" then return hit end
    return A.infoEntry(path)
  end
  -- revalidateInfo asks the host directly (model library texture checks,
  -- runtime bin checks, the disk-cache count): an archived file answers
  -- with its archived size, or every packed species reads as damaged
  local origRevalidate=G.revalidateInfo
  if type(origRevalidate)=="function" then
    function G.revalidateInfo(path)
      local hit=origRevalidate(path)
      if type(hit)=="table" then return hit end
      return A.infoEntry(tostring(path or ""))
    end
  end
  -- every cache write through GeneratedAssets (runtime sidecars, action
  -- bakes) marks its species / move for auto-pack
  local origWrite=G.write
  function G.write(path,data)
    local a,b=origWrite(path,data)
    local p=tostring(path or "")
    local kind=kindFor(p)
    if kind and not pinnedLoose(p) then A.markDirty(kind,unitKey(kind,p)) end
    return a,b
  end
  function G.read(path)
    local data,err=origRead(path)
    if type(data)=="string" then return data end
    local archived,aerr=A.readEntry(tostring(path or ""))
    if type(archived)~="string" then return nil,err or aerr or ("generated asset missing: "..tostring(path)) end
    -- Rehydrate wrote the loose file; read it back so the info registry records
    -- the authoritative size instead of the miss origRead just stored.
    local again=origRead(path)
    return type(again)=="string" and again or archived
  end
  return G
end

A.install()
return A
