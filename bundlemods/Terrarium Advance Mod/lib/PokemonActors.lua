local V=...
local function platformOS()
  if love and love.system and type(love.system.getOS)=="function" then
    local ok,v=pcall(love.system.getOS);if ok and v then return tostring(v) end
  end
  return "Unknown"
end
local PLATFORM_OS=platformOS()
local ANDROID_RUNTIME=PLATFORM_OS=="Android"
local MOBILE_RUNTIME=ANDROID_RUNTIME or PLATFORM_OS=="iOS"
-- Mobile doubles can need six player-party identities plus two live opponents.
-- Keep one additional recent scene as a churn buffer, but do not retain the old
-- 12-scene GPU working set on devices where RAM/VRAM is shared. Persistent f32
-- sidecars make a later reload cheap without changing any visual asset quality.
local ANDROID_POKEMON_SOFT_LIMIT=9
local ANDROID_POKEMON_RECENT=3
local mod,Mat4=V.mod,V.Mat4
local GeneratedAssets=V.GeneratedAssets
local RuntimeMeshCache=V.RuntimeMeshCache
local WorkBudget=V.WorkBudget
local function workCheckpoint(label)
  if WorkBudget then WorkBudget.checkpoint(label) end
end
local Dex=V.ColosseumDex
local Shiny=V.ShinySupport
local IDENTITY_MAT=Mat4 and Mat4.identity and Mat4.identity() or {1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1}
local function modelKey(dex,variant)
  return Dex.modelKey and Dex.modelKey(dex,variant) or tonumber(dex)
end
local function dexNumber(dex) return Dex.number and Dex.number(dex) or tonumber(dex) end
local function cacheRoot(dex)
  return Dex.cacheRoot and Dex.cacheRoot(dex) or ("cache/pokemon/%d"):format(tonumber(dex) or 0)
end
local function monVariant(mon)
  return Shiny and Shiny.variant(mon) or (mon and (mon.shiny or (mon.mon and mon.mon.shiny)) and "shiny" or "normal")
end
local function validFilter(f) return Shiny and Shiny.validFilter(f) or false end
local A={version=1}

-- CBE's own Colosseum-sourced battle actors.
--
-- This publishes the SAME `battleActors` v1 capability that CurrentSpriteModels
-- already arbitrates for third-party providers (see PORTABLE_BATTLE_ACTORS.md).
-- CBE therefore consumes its own Pokemon models through the documented public
-- seam rather than through a private back door: an external provider with a
-- higher priority still wins, and a species we cannot supply still falls back
-- to the resolved 2D sprite for that side alone.
--
-- Everything drawn here is source geometry in a source-authored pose. The only
-- runtime-authored motion is the blend WEIGHT between two authored frames.

-- Base position/UV/normal plus twelve authored-frame positions.  The twelve
-- vec3 frame streams are losslessly packed into nine vec4 attributes so the
-- shader stays comfortably below the generic vertex-attribute limit on the
-- Gen1Recomp/LÃƒâ€“VE backends. 1.5.32 used one attribute per frame and could fail
-- shader linking at Frame12, which made the actor provider fail open to 2D.
-- STRIDE remains compact at 44 floats: 8 base + 9*4 packed-frame floats.
local FORMAT={
  {"VertexPosition","float",3},
  {"VertexTexCoord","float",2},
  {"VertexNormal","float",3},
  {"FramePack1","float",4},
  {"FramePack2","float",4},
  {"FramePack3","float",4},
  {"FramePack4","float",4},
  {"FramePack5","float",4},
  {"FramePack6","float",4},
  {"FramePack7","float",4},
  {"FramePack8","float",4},
  {"FramePack9","float",4},
}

local VERTEX=[[
uniform mat4 vp;
uniform mat4 model;
uniform mat4 reflectionView;
uniform mat4 reflectionTexMtx;
uniform float textureCoordMode;
// w[0] weights the base (frame 0) stream; w[1..12] weight authored frames.
// Exactly two are non-zero at any time, so this is a linear interpolation
// between two real Colosseum frames -- never a synthesized pose.
uniform float w0;
uniform float w1;
uniform float w2;
uniform float w3;
uniform float w4;
uniform float w5;
uniform float w6;
uniform float w7;
uniform float w8;
uniform float w9;
uniform float w10;
uniform float w11;
uniform float w12;
uniform float hitFlash;
attribute vec3 VertexNormal;
attribute vec4 FramePack1;
attribute vec4 FramePack2;
attribute vec4 FramePack3;
attribute vec4 FramePack4;
attribute vec4 FramePack5;
attribute vec4 FramePack6;
attribute vec4 FramePack7;
attribute vec4 FramePack8;
attribute vec4 FramePack9;
varying vec3 worldPos;
varying vec3 worldNormal;
varying vec2 sourceTexCoord;

vec4 position(mat4 transform_projection, vec4 vertex_position) {
  // Losslessly unpack 12 authored vec3 poses from 9 vec4 attributes.
  vec3 f1  = FramePack1.xyz;
  vec3 f2  = vec3(FramePack1.w, FramePack2.x, FramePack2.y);
  vec3 f3  = vec3(FramePack2.z, FramePack2.w, FramePack3.x);
  vec3 f4  = FramePack3.yzw;
  vec3 f5  = FramePack4.xyz;
  vec3 f6  = vec3(FramePack4.w, FramePack5.x, FramePack5.y);
  vec3 f7  = vec3(FramePack5.z, FramePack5.w, FramePack6.x);
  vec3 f8  = FramePack6.yzw;
  vec3 f9  = FramePack7.xyz;
  vec3 f10 = vec3(FramePack7.w, FramePack8.x, FramePack8.y);
  vec3 f11 = vec3(FramePack8.z, FramePack8.w, FramePack9.x);
  vec3 f12 = FramePack9.yzw;
  vec3 p = vertex_position.xyz * w0
         + f1 * w1 + f2 * w2 + f3 * w3 + f4 * w4
         + f5 * w5 + f6 * w6 + f7 * w7 + f8 * w8
         + f9 * w9 + f10 * w10 + f11 * w11 + f12 * w12;
  vec4 world = model * vec4(p,1.0);
  worldPos = world.xyz;
  worldNormal = normalize((model * vec4(normalize(VertexNormal),0.0)).xyz);
  // LOVE exposes the built-in VertexTexCoord attribute as a vec4 even when the
  // mesh only supplies UV.xy. Assign only the authored UV components to our
  // vec2 varying; assigning the whole attribute is a GLSL type error on strict
  // desktop drivers and prevented the Pokemon actor shader from compiling.
  sourceTexCoord = VertexTexCoord.xy;
  if (textureCoordMode > 0.5 && textureCoordMode < 1.5) {
    // HSD_TObj TEX_COORD_REFLECTION: GX_TG_NRM feeds the view-space normal
    // through the exact source 3x4 texture matrix.  The third component is Q.
    vec3 vn = normalize((reflectionView * vec4(worldNormal,0.0)).xyz);
    vec4 tc = reflectionTexMtx * vec4(vn,1.0);
    float q = abs(tc.z) > 0.000001 ? tc.z : 1.0;
    sourceTexCoord = tc.xy / q;
  }
  return vp * world;
}
]]

local PIXEL=[[
uniform vec3 cameraEye;
uniform vec4 tintColor;
uniform float releaseFlash;
uniform vec4 materialColor;
uniform float useTexture;
uniform float opacity;
uniform float hitFlash;
uniform float spawnFlash;
uniform float shinyEnabled;
uniform vec4 shinyRouteR;
uniform vec4 shinyRouteG;
uniform vec4 shinyRouteB;
uniform vec3 shinyGain;
varying vec3 worldPos;
varying vec3 worldNormal;
varying vec2 sourceTexCoord;

// Native PKX channel routing + brightness, not a universal hue rotation.
// Rare-model species use their separate source texture and bypass this filter.
// RGB only: alpha remains the source texture/material transparency.
vec4 effect(vec4 color, Image texture, vec2 uv, vec2 screen) {
  vec4 texel = Texel(texture,sourceTexCoord);
  float texAlpha = mix(1.0, texel.a, useTexture);
  float a = texAlpha * materialColor.a * tintColor.a * opacity * color.a;
  if (a < 0.08) discard;
  vec3 base = mix(materialColor.rgb, texel.rgb, useTexture);
  if (shinyEnabled > 0.5) {
    vec4 source = vec4(base, mix(materialColor.a, texel.a, useTexture));
    base = clamp(vec3(dot(source,shinyRouteR),dot(source,shinyRouteG),
      dot(source,shinyRouteB))*shinyGain,0.0,1.0);
  }
  vec3 n = normalize(worldNormal);
  vec3 lightDir = normalize(vec3(-0.42,0.82,0.38));
  float key = abs(dot(n,lightDir));
  float hemi = clamp(n.y*0.5+0.5,0.0,1.0);
  vec3 viewDir = normalize(cameraEye-worldPos);
  float rim = pow(1.0-clamp(abs(dot(n,viewDir)),0.0,1.0),2.4);
  float light = 0.72 + key*0.24 + hemi*0.07;
  vec3 rgb = base * light;
  rgb += vec3(0.055,0.075,0.10)*rim;
  rgb = clamp((rgb-vec3(0.5))*1.035+vec3(0.5),vec3(0.0),vec3(1.0));
  rgb = mix(rgb, vec3(1.0), spawnFlash);
  rgb = mix(rgb, vec3(1.0,0.86,0.86), hitFlash);
  return vec4(mix(rgb*tintColor.rgb,vec3(1.0),releaseFlash),a);
}
]]

local shader
local scenes={}          -- [dex] = {groups,bounds,clip,morphFrames,...}
local sceneErrors={}     -- transient diagnostic, never a permanent negative cache
local sessionPinned={}
local sessionPrepared={}
local requiredSessionPrepared={}
local sessionEpoch=0
local extractor,discOpener
local sourceBusy=false
function A.sourceBusy() return sourceBusy end
function A.cancelSourceWork() sourceBusy=false end
local function extractSource(...)
  if sourceBusy then return nil,"source extraction in progress" end
  sourceBusy=true
  local committed=WorkBudget and WorkBudget.onCancel(function() sourceBusy=false end) or function() end
  local ok,value,why=pcall(extractor.extractSpecies,...)
  sourceBusy=false;committed()
  if not ok then return nil,tostring(value) end
  return value,why
end
local function extractSourceActions(...)
  if sourceBusy then return nil,"source extraction in progress" end
  if not (extractor and type(extractor.extractActions)=="function") then
    return nil,"selective source-action extractor unavailable"
  end
  sourceBusy=true
  local committed=WorkBudget and WorkBudget.onCancel(function() sourceBusy=false end) or function() end
  local ok,value,why=pcall(extractor.extractActions,...)
  sourceBusy=false;committed()
  if not ok then return nil,tostring(value) end
  return value,why
end
local metadataReader
local pendingExtract={}
local function retryClock()
  return (love and love.timer and love.timer.getTime and love.timer.getTime()) or os.clock()
end
local function extractionFailed(key,reason)
  pendingExtract[key]={retryAt=retryClock()+2,reason=tostring(reason or "source extraction failed")}
end
local sourceMetadata={}
local selectiveActionSpecs={}
-- Gen II stores move ids in a retail-order array. Required-model readiness is
-- queried repeatedly while a battle is preparing; rescanning that array for
-- every move on every poll is needless O(moves*order) work. Memoize one reverse
-- index per immutable host order table; weak keys discard it when the game data
-- registry is replaced. Keep it on A rather than adding another top-level local:
-- this file intentionally runs close to Lua 5.1's 200-local chunk limit.
A._sourceMoveOrderIndex=setmetatable({}, {__mode="k"})
local requiredActionNames
local ensureRequiredActionInventory
local sceneUseSerial=0
local idleWarmQueue={}
local idleWarmSeen={}
local idleWarmGame=nil
local idleWarmNextAt=0
local actionWarmQueue={}
local actionWarmSeen={}
local actionWarmNextAt=0
local battleWarmQueue={}
local battleWarmSeen={}
local battleWarmTask=nil
local battleWarmCurrent=nil
local hardCacheQueue={}
local hardCacheGame=nil
local hardCacheState={running=false,total=0,done=0,failed=0,bases=0,actions=0,last=nil,head=1,tail=0}
local perf={sceneLoads=0,sceneHits=0,actionBuilds=0,actionPrewarms=0,actorAcquires=0,residentAcquireHits=0,reactionClamps=0,reactionFallbacks=0,actionDrawFallbacks=0,floorClamps=0,idleWarmLoads=0,idleWarmMs=0,residentTrimKept=0,residentTrimReleased=0,runtimeBaseHits=0,runtimeBaseWrites=0,runtimeActionHits=0,runtimeActionWrites=0}

local function log(level,fmt,...)
  local l=mod and mod.log
  if l and type(l[level])=="function" then pcall(l[level],l,"[ColosseumActors] "..fmt,...) end
end
local function readLua(path)
  local src,err=GeneratedAssets.read(path)
  if not src then return nil,err or ("missing "..path) end
  local chunk,lerr=load(src,"@"..tostring(mod.path or mod.id).."/"..path)
  if not chunk then return nil,lerr end
  local ok,value=pcall(chunk)
  if not ok then return nil,value end
  return value
end
local function runtimeRoot(dex) return cacheRoot(dex).."/runtime_mesh_v1" end
local function runtimeBasePath(dex) return runtimeRoot(dex).."/base.lua" end
local function runtimeBaseBinPath(dex,i) return runtimeRoot(dex)..("/base_%02d.f32"):format(tonumber(i) or 0) end
local function runtimeActionTag(name) return tostring(name or "action"):gsub("[^%w_%-]","_") end
local function runtimeActionManifestPath(dex,name) return runtimeRoot(dex).."/action_"..runtimeActionTag(name)..".lua" end
local function runtimeActionBinPath(dex,name,i) return runtimeRoot(dex).."/action_"..runtimeActionTag(name)..("_%02d.f32"):format(tonumber(i) or 0) end
local function runtimeActionFloorPath(dex,name) return runtimeRoot(dex).."/action_"..runtimeActionTag(name).."_floor.lua" end
-- Quick/legacy cache inventory is an acceleration question, not an integrity
-- boundary. Older builds answered it by running persistentModelState() for all
-- 386 normal species, which deliberately invalidates/reloads every runtime-base,
-- metadata and action descriptor before it answers. That deep validator remains
-- authoritative before a model is actually loaded/reused; this tiny positive
-- certificate merely remembers which NORMAL full-action units have already
-- passed it for the exact current source stamp. One cold read replaces hundreds
-- of descriptor reads on later Quick Cache selections, especially on Android.
local FULL_INVENTORY_PATH="build/pokemon_full_inventory_v1.lua"
local FULL_INVENTORY_VERSION=1
local fullInventoryMemo=nil
local fullInventoryLoaded=false
local fullInventoryDirty=false
local inventoryStats={reads=0,hits=0,deep=0,writes=0}
local function sourceRevision(dex)
  if not (extractor and type(extractor.revPath)=="function") then return nil end
  local body=GeneratedAssets.read(extractor.revPath(dex))
  return type(body)=="string" and body or nil
end
local speciesCacheValidity={}
-- Legacy rev37/38 caches predate source texture-coordinate metadata.  Only
-- species whose old canonical body contains a textured all-zero-UV stage need
-- a source refresh; ordinary cached species remain reusable.  This list is a
-- compatibility repair boundary, NOT a material guess: re-extraction reads the
-- real HSD coordinateMode/SRT and can still fail closed for unsupported modes.
local LEGACY_TEXGEN_REPAIR_DEX={
  [13]=true,[64]=true,[65]=true,[81]=true,[82]=true,[120]=true,[121]=true,[132]=true,[140]=true,[148]=true,
  [179]=true,[180]=true,[181]=true,[184]=true,[185]=true,[193]=true,[197]=true,[198]=true,[200]=true,[201]=true,
  [208]=true,[212]=true,[214]=true,[215]=true,[227]=true,[228]=true,[229]=true,[233]=true,[238]=true,[244]=true,
  [245]=true,[302]=true,[304]=true,[329]=true,[330]=true,[347]=true,[359]=true,[362]=true,[378]=true,[379]=true,
}
local function materialTexgenReady(dex)
  local n=dexNumber(dex)
  if not (n and LEGACY_TEXGEN_REPAIR_DEX[n]) then return true end
  if not (extractor and type(extractor.materialTexgenPath)=="function" and GeneratedAssets and type(GeneratedAssets.info)=="function") then
    return false
  end
  local info=GeneratedAssets.info(extractor.materialTexgenPath(dex))
  return type(info)=="table" and (info.type==nil or info.type=="file")
end
local function expectedSpeciesStamp()
  if not (extractor and type(extractor.stamp)=="function") then return nil end
  return extractor.stamp({skinFix=A.skinFix,renderPassFilter=true,decodeMode=A.decodeMode})
end
local function loadFullInventory()
  if fullInventoryLoaded then return fullInventoryMemo end
  fullInventoryLoaded=true
  local value
  if RuntimeMeshCache and type(RuntimeMeshCache.readLua)=="function" then
    inventoryStats.reads=inventoryStats.reads+1
    value=select(1,RuntimeMeshCache.readLua(FULL_INVENTORY_PATH))
  end
  if type(value)~="table" or tonumber(value.version)~=FULL_INVENTORY_VERSION
      or type(value.complete)~="table" then
    value={version=FULL_INVENTORY_VERSION,stamp=nil,complete={}}
  end
  fullInventoryMemo=value
  return value
end
local function noteFullInventory(dex,stamp)
  local n=dexNumber(dex)
  if not (n and n>=1 and n<=386 and type(stamp)=="string" and stamp~="") then return false,"invalid inventory identity" end
  local value=loadFullInventory()
  if value.stamp~=stamp then
    -- A compatibility-only extractor revision must not erase a proven 386-model
    -- inventory.  Rev37/38 deliberately share the same geometry/pose contract;
    -- promote the tiny certificate in place and keep every per-species proof.
    -- Truly incompatible stamps still reset only this accelerator, never payload.
    if type(value.stamp)=="string" and A._speciesStampCompatible and A._speciesStampCompatible(value.stamp) then
      value.stamp=stamp
      fullInventoryDirty=true
    else
      value={version=FULL_INVENTORY_VERSION,stamp=stamp,complete={}}
      fullInventoryMemo=value
    end
  end
  if value.complete[n]==true then return true,"unchanged" end
  value.complete[n]=true
  fullInventoryDirty=true
  return true,"dirty"
end
local function flushFullInventory()
  if not fullInventoryDirty then return true,"unchanged" end
  local value=fullInventoryMemo
  if not (type(value)=="table" and tonumber(value.version)==FULL_INVENTORY_VERSION
      and type(value.stamp)=="string" and type(value.complete)=="table") then
    return false,"inventory proof unavailable"
  end
  if not (RuntimeMeshCache and type(RuntimeMeshCache.writeLua)=="function") then return false,"inventory writer unavailable" end
  local ok,why=RuntimeMeshCache.writeLua(FULL_INVENTORY_PATH,value)
  if ok then fullInventoryDirty=false;inventoryStats.writes=inventoryStats.writes+1 end
  return ok,why
end
A._speciesStampCompatible=function(raw)
  if type(raw)~="string" then return false end
  local opts={skinFix=A.skinFix,renderPassFilter=true,decodeMode=A.decodeMode}
  if extractor and type(extractor.isCompatibleStamp)=="function" then
    local ok,value=pcall(extractor.isCompatibleStamp,raw,opts)
    return ok and value==true
  end
  return raw==expectedSpeciesStamp()
end
local function speciesCacheReady(dex,allowLegacyMaterialBody)
  dex=modelKey(dex)
  if not (dex and extractor) then return false,nil end
  -- Selective texgen repair must never turn a previously-generated Pokemon into
  -- an invisible/stuck battle slot.  A handful of rev37/38 species (including
  -- Sneasel/Steelix) need one source refresh for exact generated-coordinate
  -- material metadata, but their cached body geometry/idle remain usable.  The
  -- ordinary/full-cache validators stay strict; only an explicit battle-body
  -- caller may reuse that compatible legacy body while the repair is scheduled.
  if not materialTexgenReady(dex) and allowLegacyMaterialBody~=true then
    return false,expectedSpeciesStamp()
  end
  local expected=expectedSpeciesStamp()
  if type(expected)=="string" and speciesCacheValidity[dex]==expected then return true,expected end

  -- Route cache validity through GeneratedAssets so Hard Cache Save's persisted
  -- positive metadata registry is actually used by information menus after a
  -- relaunch. PokemonExtractor.isCached() talks to mod.cache directly; calling
  -- it from every PC/Pokedex selection bypassed that registry and reintroduced
  -- host filesystem/cache probes on the latency-sensitive UI path.
  if GeneratedAssets and type(GeneratedAssets.info)=="function"
      and type(GeneratedAssets.read)=="function"
      and type(extractor.cachePath)=="function" and type(extractor.revPath)=="function" then
    local info=GeneratedAssets.info(extractor.cachePath(dex))
    if type(info)=="table" and (info.type==nil or info.type=="file") then
      local raw=GeneratedAssets.read(extractor.revPath(dex))
      if type(expected)=="string" and A._speciesStampCompatible(raw) then
        speciesCacheValidity[dex]=expected
        return true,expected
      end
    end
    return false,expected
  end

  if type(extractor.isCached)=="function" and mod then
    local ok,value=pcall(extractor.isCached,mod,dex,{skinFix=A.skinFix,renderPassFilter=true,decodeMode=A.decodeMode})
    if ok and value==true then
      if type(expected)=="string" then speciesCacheValidity[dex]=expected end
      return true,expected
    end
  end
  return false,expected
end

local function cachedActionProfile(dex)
  dex=modelKey(dex)
  if not dex then return "full",true end
  local cache
  if RuntimeMeshCache and type(RuntimeMeshCache.readLua)=="function" then
    cache=select(1,RuntimeMeshCache.readLua(runtimeBasePath(dex)))
  end
  if type(cache)~="table" and extractor and type(extractor.cachePath)=="function" then
    cache=select(1,readLua(extractor.cachePath(dex)))
  end
  -- Legacy caches predate the profile field and were always full-action builds.
  if type(cache)~="table" then return "full",true end
  local profile=tostring(cache.actionProfile or "full")
  local complete=cache.actionInventoryComplete~=false and profile~="storage"
  return profile,complete
end

local function discardResidentForActionUpgrade(key)
  local scene=scenes[key]
  if not scene then return false end
  local live=false
  for _,actor in pairs(A._liveActors or {}) do if actor and actor.scene==scene then live=true;break end end
  scenes[key]=nil;sceneErrors[key]=nil;sessionPinned[key]=nil;sessionPrepared[key]=nil;requiredSessionPrepared[key]=nil
  if live then return false end -- detached; old information actor is not invalidated mid-frame
  local seen={}
  local function release(obj)
    if not obj or seen[obj] then return end;seen[obj]=true
    pcall(function() if type(obj.release)=="function" then obj:release() end end)
  end
  local function groups(rows)
    for _,g in ipairs(type(rows)=="table" and rows or {}) do if type(g)=="table" then release(g.mesh);release(g.image) end end
  end
  groups(scene.groups)
  for _,image in pairs(scene.textures or {}) do release(image) end
  for _,entry in pairs(scene.actions or {}) do
    if type(entry)=="table" then groups(entry.groups);for _,page in ipairs(entry.pages or {}) do groups(page and page.groups) end end
  end
  return true
end

-- Explicit user-requested recovery for one failed Pokemon cache.  This is much
-- narrower than the global CBE cache reset: it deletes only the generated files
-- owned by the selected species/appearance manifest row, plus the handful of
-- core paths that predate manifest coverage.  The imported GC6E01 source,
-- arenas, trainers, audio and MoveFX are never touched.
function A.deleteModelCache(dex,variant)
  local n=dexNumber(dex)
  local key=n and modelKey(n,variant or "normal") or nil
  if not (n and key and extractor and GeneratedAssets and type(GeneratedAssets.delete)=="function") then
    return false,"model cache delete unavailable"
  end

  discardResidentForActionUpgrade(key)
  local paths,seen={},{}
  local function add(path)
    if type(path)=="string" and path~="" and not seen[path] then seen[path]=true;paths[#paths+1]=path end
  end

  -- Sharded manifest is the authoritative ownership list for canonical body,
  -- textures, actions and packed runtime sidecars.  Leave the shard itself in
  -- place; the subsequent source extraction replaces this one row atomically.
  if type(extractor.manifestShardPath)=="function" and type(GeneratedAssets.read)=="function" then
    local shard=extractor.manifestShardPath(n)
    local raw=shard and GeneratedAssets.read(shard) or nil
    if type(raw)=="string" then
      local chunk=load(raw,"@generated/"..tostring(shard))
      local ok,list=false,nil
      if chunk then ok,list=pcall(chunk) end
      if ok and type(list)=="table" then
        for _,entry in ipairs(list) do
          if type(entry)=="table" and modelKey(entry.dex,entry.variant or "normal")==key then
            for _,path in ipairs(entry.paths or {}) do add(path) end
          end
        end
      end
    end
  end

  -- Compatibility coverage for old/unmanifested model caches.
  if type(extractor.cachePath)=="function" then add(extractor.cachePath(key)) end
  if type(extractor.revPath)=="function" then add(extractor.revPath(key)) end
  if type(extractor.materialTexgenPath)=="function" then add(extractor.materialTexgenPath(key)) end
  add(cacheRoot(key).."/metadata_v1.lua");add(runtimeBasePath(key))

  local deleted=0
  for _,path in ipairs(paths) do
    local ok,why=GeneratedAssets.delete(path)
    if ok==false then return false,("model cache delete failed [%s]: %s"):format(path,tostring(why)) end
    deleted=deleted+1
  end
  if type(extractor.invalidateManifestMemo)=="function" then pcall(extractor.invalidateManifestMemo,mod) end
  speciesCacheValidity[key]=nil;sourceMetadata[key]=nil;pendingExtract[key]=nil
  sessionPinned[key]=nil;sessionPrepared[key]=nil;requiredSessionPrepared[key]=nil
  local inventory=fullInventoryMemo
  if type(inventory)=="table" and type(inventory.complete)=="table" then
    inventory.complete[n]=nil;fullInventoryDirty=true
  end
  return true,("Deleted %d generated files for Pokemon #%d / %s; source will rebuild on retry."):format(deleted,n,tostring(variant or "normal")),deleted
end

local function ensureFullActionInventory(dex,variant,progress)
  local n=dexNumber(dex);if not n then return false,"invalid species" end
  local key=modelKey(n,variant or "normal")
  local ready=speciesCacheReady(key)
  local legacyActionRefs=ready and cachedBaseActionRefs(key) or nil
  if not ready then return true,"uncached" end -- normal source path will create a full cache
  local profile,complete=cachedActionProfile(key)
  if complete then
    if A._compactAction and A._compactAction.inventoryReady and A._compactAction.inventoryReady(key) then
      return true,"compact-"..tostring(profile)
    end
    -- Legacy v2 full-action caches are source-complete but disk-exploded. Rebuild
    -- this one species transactionally from the already imported GC6E01 source
    -- into the compact action format. This is an upgrade, not a global cache wipe.
  elseif profile~="storage" then return false,"incomplete action inventory" end
  if not (extractor and type(extractor.extractSpecies)=="function" and discOpener) then return false,"battle action upgrade source unavailable" end
  local opened,disc=pcall(discOpener)
  if not opened or not disc then return false,"battle action upgrade disc unavailable" end
  local result,why=extractSource(mod,disc,n,{variant=variant or "normal",targetHeight=16.0,
    decodeMode=A.decodeMode,skinFix=A.skinFix,renderPassFilter=true,actionProfile="full",preserveExisting=false,
    progress=progress,checkpoint=progress})
  if not result then return false,why or "battle action upgrade failed" end
  speciesCacheValidity[key]=nil
  if RuntimeMeshCache and type(RuntimeMeshCache.invalidateLua)=="function" then RuntimeMeshCache.invalidateLua(runtimeBasePath(key)) end
  discardResidentForActionUpgrade(key)
  local compactScene=loadScene(key,true,progress or workCheckpoint)
  if compactScene and A._compactAction and A._compactAction.cleanupLegacyRuntime then
    A._compactAction.cleanupLegacyRuntime(key,compactScene,legacyActionRefs)
  end
  local ok=speciesCacheReady(key)
  local _,nowComplete=cachedActionProfile(key)
  if not ok or not nowComplete then return false,"battle action upgrade did not produce a complete cache" end
  if not (A._compactAction and A._compactAction.inventoryReady and A._compactAction.inventoryReady(key)) then
    return false,"battle action upgrade did not commit compact action inventory"
  end
  return true,"upgraded"
end

local function validRuntimeMeta(meta,stamp)
  if not (type(meta)=="table" and tonumber(meta.runtimeMeshVersion)==1 and type(stamp)=="string"
      and type(meta.stamp)=="string") then return false end
  if meta.stamp==stamp then return true end
  -- Runtime sidecars from an explicitly compatible extractor revision contain
  -- the same vertex layout/pose data and are reusable acceleration payloads.
  -- Do not turn a capability-only revision bump into a 386-model repack.
  return A._speciesStampCompatible and A._speciesStampCompatible(meta.stamp) or false
end
local function runtimeBinLooksValid(path,stride,verify)
  if not (path and GeneratedAssets and type(GeneratedAssets.info)=="function") then return false end
  local info
  if verify and GeneratedAssets.registered then
    -- Hard Cache Save can touch hundreds of binary group sidecars on every
    -- platform. A persisted positive row has already been validated by a real
    -- CBE read/write; reuse it and host-probe only unknown paths. The eventual
    -- RuntimeMeshCache.read remains authoritative and self-invalidates a stale
    -- registry row, so this removes metadata I/O without weakening payload use.
    info=GeneratedAssets.registered(path)
    if not info and GeneratedAssets.revalidateInfo then info=GeneratedAssets.revalidateInfo(path) end
  elseif verify and GeneratedAssets.revalidateInfo then info=GeneratedAssets.revalidateInfo(path)
  else info=GeneratedAssets.info(path) end
  if not info then return false end
  local size=tonumber(info.size)
  if not size then return true end -- metadata-less cache backend; meshFromBytes validates the read payload
  local bytesPerVertex=(tonumber(stride) or 44)*4
  return size>=bytesPerVertex and size%bytesPerVertex==0
end
local function generatedInfoValidated(path,verify)
  if not (path and GeneratedAssets) then return nil end
  if verify and GeneratedAssets.registered then
    local info=GeneratedAssets.registered(path)
    if info then return info end
  end
  if verify and GeneratedAssets.revalidateInfo then return GeneratedAssets.revalidateInfo(path) end
  if GeneratedAssets.info then return GeneratedAssets.info(path) end
  return nil
end


A._compactAction={version=1,inventoryMemo={}}
function A._compactAction.inventoryReady(key)
  if A._compactAction.inventoryMemo[key] then return true end
  if not (GeneratedAssets and type(GeneratedAssets.read)=="function") then return false end
  local raw=GeneratedAssets.read(cacheRoot(key).."/actions/compact_v1.complete")
  local ready=raw=="pokemon-action-pack=1\npose-guard="..tostring(A._actionPoseGuardVersion).."\n"
  if ready then A._compactAction.inventoryMemo[key]=true end
  return ready
end

function A._compactAction.cleanupLegacyRuntime(key,scene,legacyActionRefs)
  if not (GeneratedAssets and type(GeneratedAssets.delete)=="function") then return 0 end
  local deleted,seen=0,{}
  local function drop(path)
    if type(path)~="string" or path=="" or seen[path] then return end
    seen[path]=true
    local ok=GeneratedAssets.delete(path)
    if ok~=false then deleted=deleted+1 end
    if RuntimeMeshCache and type(RuntimeMeshCache.invalidateLua)=="function" and path:sub(-4)==".lua" then
      RuntimeMeshCache.invalidateLua(path)
    end
  end
  -- Use each tiny runtime manifest to derive the owned sidecar paths. This keeps
  -- compaction O(actions) per species instead of rescanning the complete hard-
  -- cache registry for every one of the 386 Pokemon.
  -- Older builds can have action sidecars that predate the registry; manifests
  -- are therefore a better ownership source for this migration anyway.
  -- derive and delete those paths too without scanning the host cache tree.
  local names={}
  for name in pairs(scene and scene.actionSpecs or {}) do names[name]=true end
  for name in pairs(type(legacyActionRefs)=="table" and legacyActionRefs or {}) do names[name]=true end
  for name in pairs(names) do
    local manifestPath=runtimeActionManifestPath(key,name)
    local meta=RuntimeMeshCache and RuntimeMeshCache.readLua and select(1,RuntimeMeshCache.readLua(manifestPath)) or nil
    if type(meta)=="table" then
      if type(meta.pages)=="table" then
        for pi,page in ipairs(meta.pages) do
          local count=math.max(0,math.floor(tonumber(page and page.groupCount) or 0))
          for i=1,count do drop(runtimeActionBinPath(key,name.."/page"..pi,i)) end
          drop(runtimeActionFloorPath(key,name.."/page"..pi))
        end
      else
        local count=math.max(0,math.floor(tonumber(meta.groupCount) or 0))
        for i=1,count do drop(runtimeActionBinPath(key,name,i)) end
        drop(runtimeActionFloorPath(key,name))
      end
    end
    drop(manifestPath)
  end
  return deleted
end
function A._compactAction.groupInfoReady(spec,verify)
  if type(spec)~="table" or type(spec.binaryPath)~="string" then return false,"packed action path missing" end
  if tonumber(spec.vertexStride)~=44 or (tonumber(spec.vertexCount) or 0)<=0 then return false,"packed action geometry metadata invalid" end
  local rawTotal,storedTotal=tonumber(spec.bundleRawBytes),tonumber(spec.bundleStoredBytes)
  local offset,rawBytes=tonumber(spec.offset) or 0,tonumber(spec.rawBytes) or 0
  if not rawTotal or rawTotal<=0 or not storedTotal or storedTotal<=0 or rawBytes<=0 or offset<0 or offset+rawBytes>rawTotal then
    return false,"packed action bundle metadata invalid"
  end
  local info=generatedInfoValidated(spec.binaryPath,verify)
  if not info then return false,"packed action file missing: "..tostring(spec.binaryPath) end
  local actual=tonumber(info.size)
  if actual and actual~=storedTotal then
    return false,("packed action size mismatch: %s (%d/%d)"):format(tostring(spec.binaryPath),actual,storedTotal)
  end
  return true
end
function A._compactAction.groupsReady(rawGroups,expectedCount,verify)
  if type(rawGroups)~="table" or tonumber(rawGroups._packedActionVersion)~=A._compactAction.version then return false,"not a compact action pack" end
  if tonumber(rawGroups._poseGuardVersion)~=tonumber(A._actionPoseGuardVersion) then return false,"compact action pose guard is stale" end
  if expectedCount and #rawGroups~=expectedCount then return false,"packed action/base material group count mismatch" end
  if type(rawGroups._floorMinYSlots)~="table" or #rawGroups._floorMinYSlots~=13 then return false,"packed action floor metadata missing" end
  for _,spec in ipairs(rawGroups) do local ok,why=A._compactAction.groupInfoReady(spec,verify);if not ok then return false,why end end
  return true
end
function A._compactAction.bundleBytes(spec,memo)
  memo=memo or {}
  local path=spec and spec.binaryPath
  if type(path)~="string" then return nil,"packed action path missing" end
  local cached=memo[path]
  if type(cached)=="string" then return cached end
  local body,err=GeneratedAssets and GeneratedAssets.read and GeneratedAssets.read(path) or nil
  if type(body)~="string" then return nil,err or ("packed action read failed: "..tostring(path)) end
  local expectedStored=tonumber(spec.bundleStoredBytes)
  if expectedStored and expectedStored>0 and #body~=expectedStored then return nil,"packed action stored-size mismatch" end
  local compression=tostring(spec.compression or "raw")
  local raw=body
  if compression=="zlib" then
    if not (love and love.data and type(love.data.decompress)=="function") then return nil,"zlib action decoder unavailable" end
    local ok,value=pcall(love.data.decompress,"string","zlib",body)
    if not ok or type(value)~="string" then return nil,tostring(value or "zlib action decode failed") end
    raw=value
  elseif compression~="raw" then return nil,"unsupported action compression: "..compression end
  local expectedRaw=tonumber(spec.bundleRawBytes)
  if expectedRaw and expectedRaw>0 and #raw~=expectedRaw then return nil,"packed action bundle raw-size mismatch" end
  memo[path]=raw
  return raw
end
function A._compactAction.groupBytes(spec,memo)
  local bundle,why=A._compactAction.bundleBytes(spec,memo);if not bundle then return nil,why end
  local offset,rawBytes=tonumber(spec.offset) or 0,tonumber(spec.rawBytes) or 0
  if rawBytes<=0 or offset<0 or offset+rawBytes>#bundle then return nil,"packed action group range invalid" end
  local raw=bundle:sub(offset+1,offset+rawBytes)
  local stride=tonumber(spec.vertexStride) or 44
  local expectedCount=(tonumber(spec.vertexCount) or 0)*stride*4
  if expectedCount<=0 or #raw~=expectedCount then return nil,"packed action vertex-count mismatch" end
  return raw
end
function A._compactAction.payloadReady(scene,payload,verify)
  if type(payload)~="table" or tonumber(payload.packedActionVersion)~=A._compactAction.version then return false,"not a compact action payload" end
  if tonumber(payload.poseGuardVersion)~=tonumber(A._actionPoseGuardVersion) then return false,"compact action guard revision mismatch" end
  local expected=scene and scene.groups and #scene.groups or nil
  if type(payload.pages)=="table" and #payload.pages>0 then
    for _,page in ipairs(payload.pages) do
      local ok,why=A._compactAction.groupsReady(page and page.groups,expected,verify);if not ok then return false,why end
    end
    return true
  end
  return A._compactAction.groupsReady(payload.groups,expected,verify)
end
function A._compactAction.specReady(scene,key,verify,seen)
  if not (scene and key) then return false,"action scene unavailable" end
  seen=seen or {};if seen[key] then return false,"cyclic action alias" end;seen[key]=true
  local spec=scene.actionSpecs and scene.actionSpecs[key]
  if type(spec)~="table" then return false,"action source unavailable" end
  if spec.alias then return A._compactAction.specReady(scene,tostring(spec.alias),verify,seen) end
  if not spec.path then return false,"action source path missing" end
  local payload,why=readLua(spec.path)
  if type(payload)~="table" then return false,why or "action payload unreadable" end
  if payload.alias then return A._compactAction.specReady(scene,tostring(payload.alias),verify,seen) end
  return A._compactAction.payloadReady(scene,payload,verify)
end

local function selectiveActionRefPath(dex,key,variant)
  if extractor and type(extractor.selectiveActionRefPath)=="function" then
    local ok,path=pcall(extractor.selectiveActionRefPath,dex,key,variant)
    if ok and type(path)=="string" then return path end
  end
  local cacheKey=modelKey(dex,variant)
  if not cacheKey then return nil end
  return cacheRoot(cacheKey).."/actions/selective_"..tostring(key or "action"):gsub("[^%w_%-]","_").."_v1.lua"
end

local function selectiveRefCompatible(ref)
  if type(ref)~="table" or tonumber(ref.version)~=1 or type(ref.stamp)~="string" then return false end
  local options={skinFix=A.skinFix,renderPassFilter=true,decodeMode=A.decodeMode}
  if extractor and type(extractor.isCompatibleStamp)=="function" then
    local ok,value=pcall(extractor.isCompatibleStamp,ref.stamp,options)
    if not (ok and value==true) then return false end
  elseif ref.stamp~=expectedSpeciesStamp() then return false end
  if ref.path and not generatedInfoValidated(ref.path,false) then return false end
  return ref.alias~=nil or ref.path~=nil
end

local function readSelectiveActionRef(dex,variant,key)
  local path=selectiveActionRefPath(dex,key,variant)
  if not path then return nil end
  local ref=select(1,readLua(path))
  return selectiveRefCompatible(ref) and ref or nil
end

local function cachedBaseActionRefs(key)
  local base
  if RuntimeMeshCache and type(RuntimeMeshCache.readLua)=="function" then
    base=select(1,RuntimeMeshCache.readLua(runtimeBasePath(key)))
  end
  if type(base)~="table" and extractor and type(extractor.cachePath)=="function" then
    base=select(1,readLua(extractor.cachePath(key)))
  end
  return type(base)=="table" and type(base.actions)=="table" and base.actions or {}
end

local function mergeSelectiveActionSpecs(scene,names)
  if type(scene)~="table" then return 0 end
  local memo=selectiveActionSpecs[scene.dex]
  if type(memo)~="table" then return 0 end
  scene.actionSpecs=scene.actionSpecs or {}
  scene.actionFailures=scene.actionFailures or {}
  local count=0
  if type(names)=="table" then
    for _,name in ipairs(names) do
      local ref=memo[name]
      if type(ref)=="table" and not scene.actionSpecs[name] then scene.actionSpecs[name]=ref;scene.actionFailures[name]=nil;count=count+1 end
    end
  else
    for name,ref in pairs(memo) do
      if type(ref)=="table" and not scene.actionSpecs[name] then scene.actionSpecs[name]=ref;scene.actionFailures[name]=nil;count=count+1 end
    end
  end
  return count
end

local function ensureActionSubset(dex,variant,names,progress,candidateMap)
  local n=dexNumber(dex)
  if not (n and Dex.supported(n)) then return false,"unsupported species" end
  variant=variant or "normal"
  local key=modelKey(n,variant)
  local ready=speciesCacheReady(key)
  if not ready then return false,"source base cache unavailable" end
  local profile,complete=cachedActionProfile(key)
  if complete then return true,"full-action cache" end
  if profile~="storage" then return false,"incomplete non-storage action profile" end

  local wanted,ordered={},{}
  for _,name in ipairs(type(names)=="table" and names or {}) do
    name=tostring(name or "")
    if name~="" and not wanted[name] then wanted[name]=true;ordered[#ordered+1]=name end
  end
  if #ordered==0 then return true,"no required actions" end

  local baseActions=cachedBaseActionRefs(key)
  local memo=selectiveActionSpecs[key]
  if type(memo)~="table" then memo={};selectiveActionSpecs[key]=memo end
  local missing={}
  for _,name in ipairs(ordered) do
    if not baseActions[name] then
      local ref=memo[name]
      if not selectiveRefCompatible(ref) then ref=readSelectiveActionRef(n,variant,name) end
      if ref then memo[name]=ref else missing[name]=true end
    end
  end

  if next(missing)~=nil then
    for name in pairs(missing) do
      local candidates=candidateMap and candidateMap[name]
      if type(candidates)=="table" and #candidates>0 then missing[name]=candidates end
    end
    if not discOpener then return false,"selective battle action source unavailable" end
    local opened,disc=pcall(discOpener)
    if not opened or not disc then return false,"selective battle action disc unavailable" end
    local result,why=extractSourceActions(mod,disc,n,missing,{variant=variant,targetHeight=16.0,
      decodeMode=A.decodeMode,skinFix=A.skinFix,renderPassFilter=true,progress=progress,checkpoint=progress})
    if not result then return false,why or "selective battle action extraction failed" end
    for name in pairs(missing) do
      local ref=readSelectiveActionRef(n,variant,name)
      if not ref then return false,"required source action was not committed: "..tostring(name) end
      memo[name]=ref
    end
  end

  local resident=scenes[key]
  if resident then mergeSelectiveActionSpecs(resident,ordered) end
  return true,"required-action subset ready"
end

local function runtimeActionSidecarReady(scene,name,seen)
  if not (scene and RuntimeMeshCache and type(RuntimeMeshCache.readLua)=="function") then return false end
  seen=seen or {}
  if seen[name] then return false end
  seen[name]=true
  local meta=select(1,RuntimeMeshCache.readLua(runtimeActionManifestPath(scene.dex,name)))
  if not validRuntimeMeta(meta,scene._runtimeStamp) then return false end
  if meta.alias then return runtimeActionSidecarReady(scene,tostring(meta.alias),seen) end
  local function binsReady(tag,count)
    count=math.max(0,math.floor(tonumber(count) or 0))
    if count==0 or (scene.groups and count~=#scene.groups) then return false end
    local floor=select(1,RuntimeMeshCache.readLua(runtimeActionFloorPath(scene.dex,tag)))
    if not validRuntimeMeta(floor,scene._runtimeStamp) or type(floor.floorMinYSlots)~="table"
        or #floor.floorMinYSlots~=13 then return false end
    -- Deliberately do NOT require poseGuardVersion in this disk-completeness
    -- predicate. Quick/Full cache accounting is allowed to keep an older action
    -- F32 as a reusable payload so a visual-only update never turns into a global
    -- 386-model recache. The live action uploader has the stricter guard and will
    -- repair only a battle-required action from its retained canonical payload.
    for i=1,count do if not runtimeBinLooksValid(runtimeActionBinPath(scene.dex,tag,i),44,scene._diskOnly) then return false end end
    return true
  end
  if type(meta.pages)=="table" and #meta.pages>0 then
    for pi,page in ipairs(meta.pages) do if not binsReady(name.."/page"..pi,page.groupCount) then return false end end
    return true
  end
  return binsReady(name,meta.groupCount)
end

-- Runtime F32 action pages are only an acceleration format. 2.0's compact
-- action bundles intentionally reclaim those duplicate pages after the compact
-- payload is committed, so disk/cache readiness must accept EITHER format.
-- Requiring the legacy runtime sidecar here caused fully cached compact species
-- (Sableye was the first Gen III hit in Mt. Battle) to pause on "idle sidecar".
function A._reusableActionPayloadReady(scene,name,verify)
  if runtimeActionSidecarReady(scene,name) then return true,"runtime-sidecar" end
  if A._compactAction and type(A._compactAction.specReady)=="function" then
    local ok,why=A._compactAction.specReady(scene,name,verify~=false,{})
    if ok then return true,"compact-action" end
    return false,why
  end
  return false,"action acceleration missing"
end

-- Battle-ready certification is stricter than generic disk reuse. Older action
-- F32 payloads stay reusable as migration inputs, but a cache pass that claims
-- battle readiness must prove the sidecar was rebuilt under the CURRENT pose
-- guard. This is intentionally checked per action, not as a 386-model global
-- invalidation.
function A._runtimeActionCurrentGuardReady(scene,name,seen)
  if not runtimeActionSidecarReady(scene,name) then return false end
  local baseName=tostring(name or ""):match("^([^/]+)") or tostring(name or "")
  if baseName=="idle" then return true end
  seen=seen or {}
  if seen[name] then return false end
  seen[name]=true
  local meta=select(1,RuntimeMeshCache.readLua(runtimeActionManifestPath(scene.dex,name)))
  if not validRuntimeMeta(meta,scene._runtimeStamp) then return false end
  if meta.alias then return A._runtimeActionCurrentGuardReady(scene,tostring(meta.alias),seen) end
  local function guarded(tag)
    local floor=select(1,RuntimeMeshCache.readLua(runtimeActionFloorPath(scene.dex,tag)))
    return validRuntimeMeta(floor,scene._runtimeStamp)
      and type(floor.floorMinYSlots)=="table" and #floor.floorMinYSlots==13
      and tonumber(floor.poseGuardVersion)==tonumber(A._actionPoseGuardVersion)
  end
  if type(meta.pages)=="table" and #meta.pages>0 then
    for pi in ipairs(meta.pages) do if not guarded(name.."/page"..pi) then return false end end
    return true
  end
  return guarded(name)
end

local function runtimeBaseUsable(meta,stamp,dex,verify)
  if not validRuntimeMeta(meta,stamp) or type(meta.groups)~="table" or #meta.groups==0 then return false end
  for i,g in ipairs(meta.groups) do
    local path=type(g)=="table" and (g.runtimeBin or runtimeBaseBinPath(dex,i)) or nil
    if not path or not runtimeBinLooksValid(path,44,verify) then return false end
  end
  return true
end
local function copyWithoutVertices(g)
  local out={}
  for k,v in pairs(g or {}) do if k~="vertices" and k~="verticesPacked" then out[k]=v end end
  return out
end
local function writeRuntimeBase(dex,cache,floorMin,stamp,preserveExisting)
  if not (RuntimeMeshCache and RuntimeMeshCache.writeLua and type(stamp)=="string") then return false end
  local out={runtimeMeshVersion=1,stamp=stamp,floorMinY=floorMin}
  for k,v in pairs(cache or {}) do if k~="groups" then out[k]=v end end
  out.groups={}
  for i,g in ipairs(cache.groups or {}) do
    local c=copyWithoutVertices(g);c.runtimeBin=runtimeBaseBinPath(dex,i);out.groups[i]=c
  end
  local ok=RuntimeMeshCache.writeLua(runtimeBasePath(dex),out,preserveExisting)
  if ok then perf.runtimeBaseWrites=(perf.runtimeBaseWrites or 0)+1 end
  return ok
end

local function compactMetadataLua(metadata)
  if type(metadata)~="table" then return nil end
  local function q(v) return string.format("%q",tostring(v)) end
  local function num(v) return string.format("%.9g",tonumber(v) or 0) end
  local bodyKeys={"origin","mouth","chest","tail","eye_left","eye_right","hand_left","hand_right","additional_1","additional_2","additional_3","additional_4","foot_left","foot_right","center","additional_5"}
  local function appendBodyMap(out,map)
    out[#out+1]="bodyMap={"
    for _,key in ipairs(bodyKeys) do out[#out+1]="["..q(key).."]="..tostring(tonumber(map and map[key]) or -1).."," end
    out[#out+1]="},"
  end
  local out={"return {revision=6,"
    .."sequenceKind="..tostring(tonumber(metadata.sequenceKind or metadata.scaleSelector) or 0)..","
    .."scaleSelector="..tostring(tonumber(metadata.scaleSelector or metadata.sequenceKind) or 0)..","
    .."loadMode="..tostring(tonumber(metadata.loadMode) or 0)..","}
  if Shiny then out[#out+1]=Shiny.filterField(metadata.shinyFilter) end
  appendBodyMap(out,metadata.bodyMap)
  out[#out+1]="slots={"
  for key,slot in pairs(metadata.slots or {}) do
    if type(key)=="string" and type(slot)=="table" then
      out[#out+1]="["..q(key).."]={index="..tostring(tonumber(slot.index) or -1)
        ..",animationIndex="..tostring(tonumber(slot.animationIndex) or -1)
        ..",animType="..tostring(tonumber(slot.animType) or 0)
        ..",subAnimCount="..tostring(tonumber(slot.subAnimCount) or #(slot.subAnimations or {}))
        ..",active="..tostring(slot.active==true)
        ..",duration="..num(slot.duration)
        ..",cameraTimingCount="..tostring(tonumber(slot.cameraTimingCount) or 0)
        ..",cameraTimingRate="..tostring(tonumber(slot.cameraTimingRate) or 60)
        ..",cameraTimingExact="..tostring(slot.cameraTimingExact==true)
        ..",cameraTimingRaw={"
      for i=1,3 do out[#out+1]=tostring(tonumber(slot.cameraTimingRaw and slot.cameraTimingRaw[i]) or 0).."," end
      out[#out+1]="},cameraTimingFrames={"
      for i=1,3 do out[#out+1]=tostring(tonumber(slot.cameraTimingFrames and slot.cameraTimingFrames[i]) or 0).."," end
      out[#out+1]="},timing={"
      for i=1,4 do out[#out+1]=num(slot.timing and slot.timing[i]).."," end
      out[#out+1]="},"
      appendBodyMap(out,slot.bodyMap)
      out[#out+1]="subAnimations={"
      for _,sub in ipairs(slot.subAnimations or {}) do
        out[#out+1]="{motionType="..tostring(tonumber(sub.motionType) or 0)
          ..",animationIndex="..tostring(tonumber(sub.animationIndex) or -1)
          ..",active="..tostring(sub.active==true).."},"
      end
      out[#out+1]="}},"
    end
  end
  out[#out+1]="}}\n"
  return table.concat(out)
end
local function metadataCachePath(dex) return cacheRoot(dex).."/metadata_v1.lua" end
local function writeMetadataCache(dex,metadata)
  local src=compactMetadataLua(metadata);if not src then return false end
  -- Keep CBE-owned metadata inside GeneratedAssets' positive registry. Writing
  -- this file directly through mod.cache made Android forget that it existed,
  -- so later hard-cache/party checks crossed the launcher filesystem bridge to
  -- rediscover a file CBE itself had just produced.
  if GeneratedAssets and type(GeneratedAssets.write)=="function" then
    local a=GeneratedAssets.write(metadataCachePath(dex),src)
    return a~=false and a~=nil
  end
  if not (mod and mod.cache and type(mod.cache.write)=="function") then return false end
  local ok,a=pcall(mod.cache.write,mod.cache,metadataCachePath(dex),src)
  return ok and a~=false and a~=nil
end

local function imageFromRaw(spec)
  local bytes,err=GeneratedAssets.read(spec.path)
  if not bytes then return nil,err or ("missing "..tostring(spec.path)) end
  local ok,data=pcall(love.image.newImageData,spec.w,spec.h,"rgba8",bytes)
  if not ok then return nil,data end
  local ok2,img=pcall(love.graphics.newImage,data)
  if not ok2 then return nil,img end
  if img.setFilter then
    if not pcall(img.setFilter,img,"linear","linear",16) then
      pcall(img.setFilter,img,"linear","linear")
    end
  end
  if img.setWrap then
    local function wrapName(v)
      v=tonumber(v) or 0
      if v==1 then return "repeat" end
      if v==2 then return "mirroredrepeat" end
      return "clamp"
    end
    pcall(img.setWrap,img,wrapName(spec.wrapS),wrapName(spec.wrapT))
  end
  return img
end

local function ensureShader()
  if shader then return shader end
  if not (love and love.graphics and love.graphics.newShader) then return nil,"LOVE graphics unavailable" end
  local ok,sh=pcall(love.graphics.newShader,VERTEX,PIXEL)
  if not ok or not sh then return nil,tostring(sh or "shader compile failed") end
  shader=sh
  return shader
end

-- Pokemon cache format v3 stores each dense 44-float vertex group as one
-- newline-delimited string.  Older caches used a gigantic Lua table literal;
-- sufficiently detailed species (Charizard is the first reproduced case) can
-- exceed Lua/LuaJIT's 65,536-constant limit before the chunk even executes.
-- Expand the packed payload only after the tiny metadata chunk has loaded.
local function decodedVertices(group,checkpoint)
  if type(group)~="table" then return nil,"vertex group missing" end
  if type(group.vertices)=="table" then return group.vertices end -- legacy/fail-open
  local packed=group.verticesPacked
  if type(packed)~="string" then return nil,"vertex payload missing" end
  local stride=tonumber(group.vertexStride) or 44
  if stride~=44 then return nil,("unsupported vertex stride %s"):format(tostring(stride)) end
  local vertices={}
  local rowNo=0
  for line in packed:gmatch("[^\r\n]+") do
    rowNo=rowNo+1
    local row={}
    for token in line:gmatch("[^,]+") do
      local value=tonumber(token)
      if value==nil then return nil,("vertex row %d contains non-number %q"):format(rowNo,tostring(token)) end
      row[#row+1]=value
    end
    if #row~=stride then
      return nil,("vertex row %d has %d scalars; expected %d"):format(rowNo,#row,stride)
    end
    vertices[#vertices+1]=row
    if checkpoint and rowNo%128==0 then checkpoint() end
  end
  if #vertices==0 then return nil,"packed vertex payload empty" end
  -- Drop the source string once expanded; scenes keep only the GPU mesh.
  group.vertices=vertices
  group.verticesPacked=nil
  return vertices
end

A._actionPoseGuardVersion=3

-- Inspect a non-reaction PKX action against the already-proven base-body bounds.
-- This is deliberately a pure classifier: it does not edit rows or touch caches,
-- which makes the safety contract regression-testable without a GPU/disc fixture.
-- Return: baseUnsafe, badTargetSlots, reason.
function A._inspectActionPoseRows(rawGroups,bounds,name,checkpoint)
  local baseName=tostring(name or ""):match("^([^/]+)") or tostring(name or "")
  if baseName=="idle" then return false,{},nil end
  local b=bounds or {};local mn,mx=b.min or {0,0,0},b.max or {0,16,0}
  local ref={((mn[1] or 0)+(mx[1] or 0))*.5,((mn[2] or 0)+(mx[2] or 0))*.5,((mn[3] or 0)+(mx[3] or 0))*.5}
  local height=math.max(.001,math.abs((mx[2] or 16)-(mn[2] or 0)))
  local spans={
    math.max(.001,math.abs((mx[1] or 0)-(mn[1] or 0))),
    math.max(.001,math.abs((mx[2] or 0)-(mn[2] or 0))),
    math.max(.001,math.abs((mx[3] or 0)-(mn[3] or 0))),
  }
  local baseDiag=math.max(.001,math.sqrt(spans[1]^2+spans[2]^2+spans[3]^2))
  local slots={}
  for slot=0,12 do
    slots[slot]={min={math.huge,math.huge,math.huge},max={-math.huge,-math.huge,-math.huge},count=0,finite=true}
  end
  for gi,ag in ipairs(rawGroups or {}) do
    local rows,decodeWhy=decodedVertices(ag,checkpoint)
    if not rows then return true,{},("material %d: %s"):format(gi,tostring(decodeWhy)) end
    if rows then for vi,v in ipairs(rows) do
      if checkpoint and vi%128==0 then checkpoint() end
      for slot=0,12 do
        local at=(slot==0) and 1 or (9+(slot-1)*3)
        local x,y,z=tonumber(v[at]),tonumber(v[at+1]),tonumber(v[at+2])
        local s=slots[slot]
        if not (x and y and z) or x~=x or y~=y or z~=z
            or math.abs(x)==math.huge or math.abs(y)==math.huge or math.abs(z)==math.huge then
          s.finite=false
        else
          if x<s.min[1] then s.min[1]=x end;if y<s.min[2] then s.min[2]=y end;if z<s.min[3] then s.min[3]=z end
          if x>s.max[1] then s.max[1]=x end;if y>s.max[2] then s.max[2]=y end;if z>s.max[3] then s.max[3]=z end
          s.count=s.count+1
        end
      end
    end end
  end
  local takeFlight=baseName=="takeFlight"
  local reaction=baseName=="damage" or baseName=="damageHeavy" or baseName=="faint"
  -- Keep the runtime cache-corruption guard inside the authoritative source
  -- extractor's accepted envelope. PokemonExtractor.actionPoseUsable rejects a
  -- true span explosion only beyond 7x the authored template; the old 2.30x
  -- runtime threshold rejected legitimate source motions such as Golbat's
  -- physicalA (2.347x), then re-extracted and rejected the same valid row again.
  local spanLimit=7.0
  -- PokemonExtractor.actionPoseUsable validates ROOT TRAVEL in model heights
  -- using AABB centres, not a triangle-density-weighted vertex mean. The old
  -- runtime used 1.25 body diagonals and another centre statistic, so page 10
  -- could be accepted on source extraction then rejected identically on every
  -- rebuild. Use the same existing 3.5-height source envelope/centre metric.
  -- Span/axis checks below remain independent; travel cannot excuse stretching.
  local centreLimit=(reaction and 6.0 or 3.5)*height
  local function unsafe(slot)
    local s=slots[slot]
    if not s or not s.finite or s.count<3 then return true,"non-finite/empty sample" end
    local dx=s.max[1]-s.min[1];local dy=s.max[2]-s.min[2];local dz=s.max[3]-s.min[3]
    local diag=math.sqrt(dx*dx+dy*dy+dz*dz)
    if diag<math.max(.01,baseDiag*.08) then return true,("collapsed span %.3fx body"):format(diag/baseDiag) end
    if diag>baseDiag*spanLimit then return true,("span %.3fx body"):format(diag/baseDiag) end
    for axis,value in ipairs({dx,dy,dz}) do
      -- Axis-aligned IDLE bounds are not an action envelope. A long body can
      -- turn its long Z axis into X/Y without growing at all (Gyarados, Onix,
      -- Steelix, etc.). Retain the diagonal explosion check above and permit
      -- this rotation; do not mistake the former short axis for a size limit.
      local axisLimit=math.max(spans[axis]*3.10,height*2.25,baseDiag*7.0)
      if value>axisLimit then return true,("axis %d span %.3f > %.3f"):format(axis,value,axisLimit) end
    end
    local cx=(s.min[1]+s.max[1])*.5-ref[1]
    local cy=(s.min[2]+s.max[2])*.5-ref[2]
    local cz=(s.min[3]+s.max[3])*.5-ref[3]
    local distance=math.sqrt(cx*cx+cy*cy+cz*cz)
    if distance>centreLimit+1e-5*height then
      return true,("AABB centre %.3fx body height exceeds source limit 3.500 (%.3fx body diagonal)")
        :format(distance/height,distance/baseDiag)
    end
    return false
  end
  local badBase,reason=unsafe(0)
  if badBase then return true,{},reason end
  local badSlots={}
  for slot=1,12 do
    local broken=unsafe(slot)
    if broken then badSlots[#badSlots+1]=slot end
  end
  return false,badSlots,nil
end

-- Build the GPU scene for one species from its generated cache. Returns nil and
-- an error string on any failure; the caller then declines that side, which
-- CurrentSpriteModels turns into a 2D sprite fallback for that Pokemon only.
local function loadScene(dex,diskOnly,checkpoint)
  checkpoint=checkpoint or workCheckpoint
  -- Hard Cache Save builds the same float32/floor sidecars without an actor,
  -- shader, texture decode, GPU upload, or PKX attachment-metadata inspection.
  -- Do not touch the live resident scene or its lazy-action ownership.
  local hit=not diskOnly and scenes[dex]
  if hit then perf.sceneHits=perf.sceneHits+1;return hit end
  -- A retry may follow source repair; do not latch a transient failure forever.
  if not diskOnly then sceneErrors[dex]=nil end
  if not diskOnly and not (love and love.graphics and love.image and love.graphics.newMesh) then
    return nil,"LOVE mesh API unavailable"
  end
  local path=extractor and extractor.cachePath(dex) or cacheRoot(dex).."/model_cache.lua"
  -- speciesCacheReady() already authoritatively validates the source revision
  -- before Hard Cache enters this disk-only loader. Reuse that exact session
  -- proof instead of rereading rev.txt once per base/action row.
  local expected=expectedSpeciesStamp()
  local stamp=(type(expected)=="string" and speciesCacheValidity[dex]==expected) and expected or sourceRevision(dex)
  local cache,err,fromRuntime
  local preserveRuntimeBase=false
  if RuntimeMeshCache and type(RuntimeMeshCache.readLua)=="function" then
    local rtPath=runtimeBasePath(dex)
    local rt=select(1,RuntimeMeshCache.readLua(rtPath))
    preserveRuntimeBase=rt~=nil or (type(RuntimeMeshCache.exists)=="function" and RuntimeMeshCache.exists(rtPath)) or false
    if runtimeBaseUsable(rt,stamp,dex,diskOnly) then cache=rt;fromRuntime=true;perf.runtimeBaseHits=(perf.runtimeBaseHits or 0)+1 end
  end
  if not cache then cache,err=readLua(path) end
  if not cache then
    if not diskOnly then sceneErrors[dex]=tostring(err) end
    return nil,tostring(err)
  end
  if not diskOnly then
    local sh,serr=ensureShader()
    if not sh then sceneErrors[dex]=tostring(serr);return nil,sceneErrors[dex] end
  end

  local textures,groups={},{}
  -- A scoped repair reads canonical source rows instead of a previously failed
  -- runtime action. Shared with the scene; base meshes/textures stay resident.
  local bypassActionRuntime={}
  local commitResources=function() end
  if not diskOnly and WorkBudget then
    commitResources=WorkBudget.onCancel(function()
      for _,g in ipairs(groups) do if g.mesh and g.mesh.release then pcall(g.mesh.release,g.mesh) end end
      for _,image in pairs(textures) do if image.release then pcall(image.release,image) end end
    end)
  end
  local sceneFloorMinY=tonumber(cache.floorMinY) or math.huge
  local runtimeBaseComplete=(RuntimeMeshCache and RuntimeMeshCache.packSupported and RuntimeMeshCache.packSupported()) and true or false
  if diskOnly and not runtimeBaseComplete then return nil,"runtime binary pack API unavailable" end
  for i,g in ipairs(cache.groups or {}) do
    checkpoint("Uploading model material "..i)
    local img
    if g.texture and not diskOnly then
      img=textures[g.texture.path]
      if not img then
        local ierr
        img,ierr=imageFromRaw(g.texture)
        if not img then sceneErrors[dex]=tostring(ierr);return nil,sceneErrors[dex] end
        textures[g.texture.path]=img
      end
    end
    local mesh,verr,vertices
    local binPath=g.runtimeBin or runtimeBaseBinPath(dex,i)
    if not diskOnly and fromRuntime and RuntimeMeshCache and type(RuntimeMeshCache.meshFromPath)=="function" then
      mesh,verr=RuntimeMeshCache.meshFromPath(FORMAT,binPath,44,"static")
    end
    if not mesh and not (diskOnly and fromRuntime) then
      vertices,verr=decodedVertices(g,checkpoint)
      if not vertices then
        local reason=("dex %s mesh %d vertex cache: %s"):format(dex,i,tostring(verr))
        if not diskOnly then sceneErrors[dex]=reason end
        return nil,reason
      end
      -- Cache the ACTUAL lowest authored vertex, not merely the model origin.
      for _,v in ipairs(vertices) do
        local y=tonumber(v[2])
        if y and y<sceneFloorMinY then sceneFloorMinY=y end
      end
      if not diskOnly then
        local ok,built=pcall(love.graphics.newMesh,FORMAT,vertices,"triangles","static")
        if not ok then
          sceneErrors[dex]=("dex %s mesh %d: %s"):format(dex,i,tostring(built))
          return nil,sceneErrors[dex]
        end
        mesh=built
      end
      if runtimeBaseComplete then
        local wok=RuntimeMeshCache.writeRows(binPath,vertices,44,checkpoint,preserveRuntimeBase)
        if not wok then runtimeBaseComplete=false end
      end
    end
    if img then mesh:setTexture(img) end
    local d=g.diffuse or {1,1,1}
    groups[#groups+1]={
      mesh=mesh,image=img,textured=img~=nil,
      diffuse={tonumber(d[1]) or 1,tonumber(d[2]) or 1,tonumber(d[3]) or 1},
      alpha=tonumber(g.alpha) or 1,
      xlu=g.xlu==true,noz=g.noz==true,
      renderFlags=tonumber(g.renderFlags) or 0,
      shadow=g.shadow==true,effect=g.effect==true,
      textureSlot=tonumber(g.textureSlot) or -1,
      textureCoordMode=tonumber(g.textureCoordMode) or 0,
      textureTexgen=tonumber(g.textureTexgen) or 0,
      reflectionTexMtx=type(g.reflectionTexMtx)=="table" and g.reflectionTexMtx or IDENTITY_MAT,
    }
  end
  if #groups==0 then return nil,"cache contained no drawable groups" end

  -- Build the separately sampled PKX action banks. Reaction banks may contain
  -- multiple overlapping dense pages; each page still uses the same proven
  -- 12-target GPU vertex format and shares the base source material state.
  --
  -- A handful of retail Damage/Faint clips contain large root translations that
  -- are valid in Colosseum's original stage/camera choreography but can cross
  -- the portable camera when transplanted into a different arena. Preserve the
  -- authored body deformation, but clamp only pathological whole-body travel so
  -- a hit can never turn the Pokemon mesh into a camera-filling black/texture
  -- frame. This is presentation-space stabilization, not a different animation.
  local function reactionClass(name)
    name=tostring(name or "")
    if name=="damage" or name:match("^damage/page%d+$") then return "damage" end
    if name=="damageHeavy" or name:match("^damageHeavy/page%d+$") then return "damageHeavy" end
    if name=="faint" or name:match("^faint/page%d+$") then return "faint" end
    return nil
  end
  -- Narrow action-sidecar identity. Keep this inside loadScene so it does not
  -- consume LuaJIT's already-tight top-level local-variable budget.
  local ACTION_POSE_GUARD_VERSION=A._actionPoseGuardVersion
  local function actionBaseName(name)
    return tostring(name or ""):match("^([^/]+)") or tostring(name or "")
  end
  local function stabilizeActionRows(rawGroups,name)
    local reaction=reactionClass(name)
    local b=cache.bounds or {};local mn,mx=b.min or {0,0,0},b.max or {0,16,0}
    local ref={((mn[1] or 0)+(mx[1] or 0))*.5,((mn[2] or 0)+(mx[2] or 0))*.5,((mn[3] or 0)+(mx[3] or 0))*.5}
    local height=math.max(.001,math.abs((mx[2] or 16)-(mn[2] or 0)))

    -- Damage/Faint deliberately retain the established root-motion clamp.  It
    -- preserves the authored body pose and only limits whole-body translation.
    if reaction then
    local centers,counts={},{}
    for slot=0,12 do centers[slot]={0,0,0};counts[slot]=0 end
    for _,ag in ipairs(rawGroups or {}) do
      local rows=decodedVertices(ag,checkpoint)
      if rows then for vi,v in ipairs(rows) do
        if checkpoint and vi%128==0 then checkpoint() end
        for slot=0,12 do
          local at=(slot==0) and 1 or (9+(slot-1)*3)
          local c=centers[slot];c[1]=c[1]+(tonumber(v[at]) or 0);c[2]=c[2]+(tonumber(v[at+1]) or 0);c[3]=c[3]+(tonumber(v[at+2]) or 0);counts[slot]=counts[slot]+1
        end
      end end
    end
    local corr={};local changed=0
    -- Colosseum reaction DATs include root travel that is authored together with
    -- the original stage/camera.  CBE transplants the deforming body into other
    -- arenas, so retain the body pose but keep the whole-body centre near its
    -- field anchor.  The old limits were intentionally permissive and dense
    -- `damage/pageN` banks accidentally bypassed them completely, allowing a
    -- perfectly valid hurt frame to move below the deck or far outside camera.
    local hlim=(reaction=="faint") and .72*height or .40*height
    local up=(reaction=="faint") and .52*height or .28*height
    local down=(reaction=="faint") and .82*height or .30*height
    for slot=0,12 do
      local n=counts[slot];local c=centers[slot]
      if n>0 then c={c[1]/n,c[2]/n,c[3]/n} else c={ref[1],ref[2],ref[3]} end
      local dx,dz=c[1]-ref[1],c[3]-ref[3];local r=math.sqrt(dx*dx+dz*dz)
      local tx,tz=dx,dz;if r>hlim and r>0 then local q=hlim/r;tx,tz=dx*q,dz*q end
      local dy=c[2]-ref[2];local ty=math.max(-down,math.min(up,dy))
      corr[slot]={dx-tx,dy-ty,dz-tz}
      if math.abs(corr[slot][1])+math.abs(corr[slot][2])+math.abs(corr[slot][3])>1e-5 then changed=changed+1 end
    end
    if changed==0 then return 0 end
    for _,ag in ipairs(rawGroups or {}) do
      local rows=decodedVertices(ag,checkpoint)
      if rows then for vi,v in ipairs(rows) do
        if checkpoint and vi%128==0 then checkpoint() end
        for slot=0,12 do local at=(slot==0) and 1 or (9+(slot-1)*3);local c=corr[slot];v[at]=v[at]-c[1];v[at+1]=v[at+1]-c[2];v[at+2]=v[at+2]-c[3] end
      end end
    end
    perf.reactionClamps=(perf.reactionClamps or 0)+changed
      return changed,false
    end

    local baseName=actionBaseName(name)
    if baseName=="idle" then return 0,false end

    -- Attack banks can fail while remaining perfectly drawable: a corrupt HSD
    -- matrix may keep the same vertex count yet stretch a sampled pose several
    -- body lengths.  GPU draw then succeeds, so the old draw-error fallback never
    -- fires; on screen this is the giant/pixelated Pokemon that suddenly fills
    -- the arena the moment a move starts.  Validate the actual cached positions
    -- here, at the one lazy action-build boundary, and fail closed to the resident
    -- base body instead of ever presenting malformed geometry.
    local baseUnsafe,badSlots,reason=A._inspectActionPoseRows(rawGroups,cache.bounds,name,checkpoint)
    if baseUnsafe then
      perf.actionPoseRejects=(perf.actionPoseRejects or 0)+1
      return 0,true,reason
    end
    local changed=0
    for _,slot in ipairs(badSlots or {}) do
      changed=changed+1
      for _,ag in ipairs(rawGroups or {}) do
        local rows=decodedVertices(ag,checkpoint)
        if rows then for _,v in ipairs(rows) do
          local at=9+(slot-1)*3
          v[at]=v[1];v[at+1]=v[2];v[at+2]=v[3]
        end end
      end
    end
    if changed>0 then perf.actionPoseFallbacks=(perf.actionPoseFallbacks or 0)+changed end
    return changed,false
  end
  local function buildRuntimeActionGroups(name,count,floorSlots)
    if bypassActionRuntime[actionBaseName(name)] then return nil end
    if not (RuntimeMeshCache and type(RuntimeMeshCache.meshFromPath)=="function") then return nil end
    -- Runtime F32 files are only trusted after THIS guard revision has inspected
    -- the positions that produced them.  The species stamp cannot express this
    -- narrower action-only invariant: retaining the same species stamp is what
    -- lets users keep their already-valid body cache. Reject an older legacy
    -- sidecar here for both disk validation and live GPU upload; old non-compact
    -- payloads can still be repaired through their canonical action descriptor.
    local fm=select(1,RuntimeMeshCache.readLua(runtimeActionFloorPath(dex,name)))
    local guarded=actionBaseName(name)=="idle"
      or tonumber(fm and fm.poseGuardVersion)==ACTION_POSE_GUARD_VERSION
    if not validRuntimeMeta(fm,stamp) or type(fm.floorMinYSlots)~="table" or not guarded then return nil end
    if type(floorSlots)~="table" then floorSlots=fm.floorMinYSlots end
    -- A disk-ready bank only needs validated compact metadata here. Its mesh
    -- gets uploaded later when a real battle/viewer requests it.
    if diskOnly then
      count=math.floor(tonumber(count) or 0)
      if count<=0 or count~=#groups then return nil end
      local out={_floorMinYSlots=fm.floorMinYSlots}
      for i=1,count do
      checkpoint("Uploading animation material "..i)
        if not runtimeBinLooksValid(runtimeActionBinPath(dex,name,i),44,true) then return nil end
        out[i]={}
      end
      return out
    end
    count=math.floor(tonumber(count) or 0);if count<=0 or count~=#groups then return nil end
    local agroups={}
    local settle=A._watchActionBuild({groups=agroups})
    for i=1,count do
      checkpoint("Uploading animation material "..i)
      local baseg=groups[i];if not baseg then settle(false);return nil end
      local mesh=select(1,RuntimeMeshCache.meshFromPath(FORMAT,runtimeActionBinPath(dex,name,i),44,"static"))
      if not mesh then
        settle(false)
        return nil
      end
      if baseg.image then mesh:setTexture(baseg.image) end
      agroups[i]={mesh=mesh,image=baseg.image,textured=baseg.textured,diffuse=baseg.diffuse,alpha=baseg.alpha,
        xlu=baseg.xlu,noz=baseg.noz,renderFlags=baseg.renderFlags,shadow=baseg.shadow,effect=baseg.effect,textureSlot=baseg.textureSlot,
        textureCoordMode=baseg.textureCoordMode,textureTexgen=baseg.textureTexgen,reflectionTexMtx=baseg.reflectionTexMtx}
    end
    agroups._floorMinYSlots=type(floorSlots)=="table" and floorSlots or nil
    settle(true)
    return agroups
  end

  local function buildActionGroups(rawGroups,name,compactMemo)
    -- One memo per action build guarantees a shared compact bundle is read and
    -- decompressed once even for ordinary (non-paged) multi-material actions.
    compactMemo=compactMemo or {}
    -- Compact action packs are the canonical runtime payload in 2.0 final.
    -- They decompress directly into the GPU upload format and never write a
    -- second action geometry cache. The extraction-time source validator and
    -- guard revision carried by the descriptor are authoritative.
    if type(rawGroups)=="table" and tonumber(rawGroups._packedActionVersion)==A._compactAction.version then
      local ready,readyWhy=A._compactAction.groupsReady(rawGroups,#groups,true)
      if not ready then return nil,readyWhy end
      local agroups={};local settle=A._watchActionBuild({groups=agroups})
      for i,spec in ipairs(rawGroups) do
        checkpoint("Loading compact animation material "..i)
        local baseg=groups[i];if not baseg then settle(false);return nil,"packed action/base material group count mismatch" end
        local mesh
        if not diskOnly then
          local bytes,why=A._compactAction.groupBytes(spec,compactMemo);if not bytes then settle(false);return nil,why end
          local built,bwhy=RuntimeMeshCache and RuntimeMeshCache.meshFromBytes and RuntimeMeshCache.meshFromBytes(FORMAT,bytes,44,"static") or nil,"runtime mesh upload unavailable"
          if not built then settle(false);return nil,bwhy end
          mesh=built;if baseg.image then mesh:setTexture(baseg.image) end
        end
        agroups[i]={mesh=mesh,image=baseg.image,textured=baseg.textured,diffuse=baseg.diffuse,alpha=baseg.alpha,
          xlu=baseg.xlu,noz=baseg.noz,renderFlags=baseg.renderFlags,shadow=baseg.shadow,effect=baseg.effect,textureSlot=baseg.textureSlot,
          textureCoordMode=baseg.textureCoordMode,textureTexgen=baseg.textureTexgen,reflectionTexMtx=baseg.reflectionTexMtx}
      end
      agroups._floorMinYSlots=rawGroups._floorMinYSlots
      settle(true);return agroups
    end
    local floorMeta=RuntimeMeshCache and RuntimeMeshCache.readLua and select(1,RuntimeMeshCache.readLua(runtimeActionFloorPath(dex,name))) or nil
    if validRuntimeMeta(floorMeta,stamp) then
      local direct=buildRuntimeActionGroups(name,tonumber(floorMeta.groupCount) or #groups,floorMeta.floorMinYSlots)
      if direct then return direct end
    end
    if type(rawGroups)~="table" or #rawGroups==0 then return nil,"action group payload missing: "..tostring(name) end
    local _,rejected,guardWhy=stabilizeActionRows(rawGroups,name)
    if rejected then
      log("warn","dex %s native %s rejected by runtime pose guard: %s",tostring(dex),tostring(name),tostring(guardWhy or "unsafe action pose"))
      return nil,"pose guard: "..tostring(guardWhy or "unsafe action pose")
    end
    local agroups={};local valid=true;local failure
    local settle=A._watchActionBuild({groups=agroups})
    local minYSlots={}
    for slot=0,12 do minYSlots[slot+1]=math.huge end
    for i,ag in ipairs(rawGroups or {}) do
      checkpoint("Preparing animation material "..i)
      local baseg=groups[i]
      if not baseg then valid=false;failure="action/base material group count mismatch";break end
      local vertices,verr=decodedVertices(ag,checkpoint)
      if not vertices then
        valid=false;failure="material "..i.." vertex cache: "..tostring(verr)
        log("warn","dex %s native %s mesh %d vertex cache failed: %s",dex,tostring(name),i,tostring(verr))
        break
      end
      -- Each packed action row contains the base position followed by up to
      -- twelve sampled source poses. Record their lower bounds while the rows
      -- are already decoded so floor collision never adds work to draw().
      for vi,v in ipairs(vertices) do
        if checkpoint and vi%128==0 then checkpoint() end
        for slot=0,12 do
          local at=(slot==0) and 1 or (9+(slot-1)*3)
          local y=tonumber(v[at+1])
          if y and y<minYSlots[slot+1] then minYSlots[slot+1]=y end
        end
      end
      local mesh
      if not diskOnly then
        local ok,built=pcall(love.graphics.newMesh,FORMAT,vertices,"triangles","static")
        if not ok or not built then
          valid=false;failure="material "..i.." GPU upload: "..tostring(built)
          log("warn","dex %s native %s mesh %d failed: %s",dex,tostring(name),i,tostring(built))
          break
        end
        mesh=built
        if baseg.image then mesh:setTexture(baseg.image) end
      end
      agroups[i]={
        mesh=mesh,image=baseg.image,textured=baseg.textured,
        diffuse=baseg.diffuse,alpha=baseg.alpha,xlu=baseg.xlu,noz=baseg.noz,
        renderFlags=baseg.renderFlags,shadow=baseg.shadow,effect=baseg.effect,
        textureSlot=baseg.textureSlot,textureCoordMode=baseg.textureCoordMode,
        textureTexgen=baseg.textureTexgen,reflectionTexMtx=baseg.reflectionTexMtx,
      }
    end
    if not valid or #agroups~=#groups then
      -- A retry must not retain half an animation's GPU meshes. Images are
      -- borrowed from the still-valid base and must never be released here.
      settle(false)
      return nil,failure or ("action/base material count "..#agroups.."/"..#groups)
    end
    for i=1,13 do if minYSlots[i]==math.huge then minYSlots[i]=sceneFloorMinY end end
    agroups._floorMinYSlots=minYSlots
    if RuntimeMeshCache and RuntimeMeshCache.packSupported and RuntimeMeshCache.packSupported() and type(stamp)=="string" then
        local all=true
        local preserveActionRuntime=type(RuntimeMeshCache.exists)=="function" and RuntimeMeshCache.exists(runtimeActionManifestPath(dex,name)) or false
      for i,ag in ipairs(rawGroups or {}) do
      checkpoint("Preparing animation material "..i)
        local rows=ag.vertices or decodedVertices(ag,checkpoint)
        local ok=rows and RuntimeMeshCache.writeRows(runtimeActionBinPath(dex,name,i),rows,44,checkpoint,preserveActionRuntime)
        if not ok then all=false;break end
      end
      if all then
        all=RuntimeMeshCache.writeLua(runtimeActionFloorPath(dex,name),{runtimeMeshVersion=1,stamp=stamp,poseGuardVersion=ACTION_POSE_GUARD_VERSION,groupCount=#groups,floorMinYSlots=minYSlots},preserveActionRuntime)
      end
      if diskOnly and not all then settle(false);return nil,"action runtime cache write failed: "..tostring(name) end
    end
    settle(true)
    return agroups
  end

  -- Keep native action banks in their compact generated-cache form until an
  -- action is actually needed. Older builds expanded every attack/status/hurt/
  -- faint bank and uploaded every GPU mesh before the Pokemon could render.
  -- On a detailed species that means millions of scalar parses + many mesh
  -- uploads on the exact battle/menu transition frame. Base body/idle geometry
  -- is enough to present the Pokemon immediately; action banks are materialized
  -- on demand and common battle banks are opportunistically warmed later.
  -- Never let per-scene lazy-action consumption mutate the shared base memo.
  local actionSpecs={}
  for key,spec in pairs(cache.actions or {}) do actionSpecs[key]=spec end
  local actions={}
  local actionFailures={}

  local scene={
    dex=dex,formatVersion=tonumber(cache.formatVersion) or 1,
    actionProfile=tostring(cache.actionProfile or "full"),
    actionInventoryComplete=cache.actionInventoryComplete~=false and tostring(cache.actionProfile or "full")~="storage",
    groups=groups,actions=actions,actionSpecs=actionSpecs,actionFailures=actionFailures,
    _buildActionGroups=buildActionGroups,_bypassActionRuntime=bypassActionRuntime,
    _compactActionInventory=A._compactAction and A._compactAction.inventoryReady and A._compactAction.inventoryReady(dex) or false,
    bounds=cache.bounds,retailWazaOwnerBound=cache.retailWazaOwnerBound,textures=textures,
    floorMinY=(sceneFloorMinY~=math.huge and sceneFloorMinY) or (cache.bounds and cache.bounds.min and tonumber(cache.bounds.min[2])) or 0,
    jointPositions=cache.jointPositions or {},jointFrames=cache.jointFrames or {},
    clip=tonumber(cache.clip) or 0,
    clipCount=tonumber(cache.clipCount) or 0,
    morphFrames=math.max(0,math.min(12,tonumber(cache.morphFrames) or 0)),
    idleDuration=tonumber(cache.idleDuration) or 0,
    stem=cache.stem,source=cache.source,
    vertexCount=tonumber(cache.vertexCount) or 0,
    groupCount=tonumber(cache.groupCount) or #groups,
    requestedDecodeMode=tostring(cache.requestedDecodeMode or "auto"),
    decodePath=tostring(cache.decodePath or "?"),
    heightRatio=tonumber(cache.heightRatio) or 0,
    widthRatio=tonumber(cache.widthRatio) or 0,
    envBlends=tonumber(cache.envBlends) or 0,
    envPobjs=tonumber(cache.envPobjs) or 0,
    envBlendsMulti=tonumber(cache.envBlendsMulti) or 0,
    skinFix=cache.skinFix~=false,
    poseDrift=tonumber(cache.poseDrift) or 0,
    hiddenJobjs=tonumber(cache.hiddenJobjs) or 0,
    quatJobjs=tonumber(cache.quatJobjs) or 0,
    jointCount=tonumber(cache.jointCount) or 0,
    jointScaleMin=tonumber(cache.jointScaleMin) or 0,
    jointScaleMedian=tonumber(cache.jointScaleMedian) or 0,
    jointScaleMax=tonumber(cache.jointScaleMax) or 0,
    jointScaleOutliers=tonumber(cache.jointScaleOutliers) or 0,
    renderPassFilter=cache.renderPassFilter~=false,
    nonRenderJobjs=tonumber(cache.nonRenderJobjs) or 0,
    nonRenderDobjs=tonumber(cache.nonRenderDobjs) or 0,
    shadowDobjs=tonumber(cache.shadowDobjs) or 0,
    semanticRootsOnly=cache.semanticRootsOnly==true,
    semanticRootCount=tonumber(cache.semanticRootCount) or 0,
    envelopeCoordEntries=tonumber(cache.envelopeCoordEntries) or 0,
    singleEnvelopeCoord=tonumber(cache.singleEnvelopeCoord) or 0,
    singleEnvelopeNoCoord=tonumber(cache.singleEnvelopeNoCoord) or 0,
    inverseBindMissing=tonumber(cache.inverseBindMissing) or 0,
    placeholderGroupsRemoved=tonumber(cache.placeholderGroupsRemoved) or 0,
    placeholderVertsRemoved=tonumber(cache.placeholderVertsRemoved) or 0,
  }
  -- Storage bases remain explicitly incomplete. Required battle rows live in a
  -- separately stamped additive cache and are merged only when this process has
  -- proven those exact descriptors; unrelated source actions stay absent.
  if scene.actionInventoryComplete==false then mergeSelectiveActionSpecs(scene) end
  scene._buildRuntimeActionGroups=buildRuntimeActionGroups
  scene._runtimeStamp=stamp
  if not fromRuntime and runtimeBaseComplete and type(stamp)=="string" then
    runtimeBaseComplete=writeRuntimeBase(dex,cache,(sceneFloorMinY~=math.huge and sceneFloorMinY) or (cache.bounds and cache.bounds.min and tonumber(cache.bounds.min[2])) or 0,stamp,preserveRuntimeBase)
  end
  if diskOnly then
    if not runtimeBaseComplete then return nil,"base sidecar write failed" end
    -- Only compact metadata survives between jobs; closures must not retain
    -- expanded source rows for every member of the save's collection.
    if not fromRuntime then
      for _,g in ipairs(cache.groups or {}) do g.vertices=nil;g.verticesPacked=nil end
    end
    scene._diskOnly=true
    return scene
  end
  scenes[dex]=scene
  perf.sceneLoads=perf.sceneLoads+1
  local actionCount=0;for _ in pairs(actionSpecs) do actionCount=actionCount+1 end
  log("info","loaded %s (dex %s): %d groups, %d fallback frames, %d indexed native action slots (lazy GPU)",
    tostring(cache.stem),dex,#groups,scene.morphFrames,actionCount)
  commitResources()
  return scene
end

-- A cancelled cooperative upload owns only its unfinished action meshes,
-- never the resident body's shared textures. Settle once on either outcome.
function A._watchActionBuild(entry)
  local done=false
  local function discard()
    if done then return end;done=true
    A._releaseActionMeshes(entry)
  end
  local detach=WorkBudget and type(WorkBudget.onCancel)=="function"
    and WorkBudget.onCancel(discard) or function() end
  return function(success)
    if success then done=true else discard() end
    detach()
  end
end

-- Materialize one cached native action into GPU meshes. This is intentionally
-- outside loadScene(): information surfaces and battle entry need only the base
-- body immediately, while exact attack/damage/faint banks can be built when
-- they are first requested. The compact packed strings remain untouched until
-- then, which cuts both transition CPU and resident RAM/VRAM substantially.
local function runtimeActionEntry(scene,name,meta)
  if not (validRuntimeMeta(meta,scene and scene._runtimeStamp) and scene._buildRuntimeActionGroups) then return nil end
  if meta.alias then return {alias=tostring(meta.alias),clip=tonumber(meta.clip),duration=tonumber(meta.duration) or 0} end
  if type(meta.pages)=="table" and #meta.pages>0 then
    local pages={}
    local settle=A._watchActionBuild({pages=pages})
    for pi,page in ipairs(meta.pages) do
      local pgroups=scene._buildRuntimeActionGroups(name.."/page"..pi,tonumber(page.groupCount),page.floorMinYSlots)
      if not pgroups then settle(false);return nil end
      pages[#pages+1]={groups=pgroups,startPhase=tonumber(page.startPhase) or 0,endPhase=tonumber(page.endPhase) or 1,
        morphFrames=tonumber(page.morphFrames) or 0,jointPositions=page.jointPositions or {},jointFrames=page.jointFrames or {},
        floorMinYSlots=pgroups._floorMinYSlots,validSlots=page.validSlots,dense=true}
    end
    settle(true)
    return {pages=pages,dense=true,clip=tonumber(meta.clip) or -1,duration=tonumber(meta.duration) or 0,
      frameSpacing=tonumber(meta.frameSpacing) or 1,totalIntervals=tonumber(meta.totalIntervals) or 0}
  end
  local agroups=scene._buildRuntimeActionGroups(name,tonumber(meta.groupCount),meta.floorMinYSlots)
  if not agroups then return nil end
  return {groups=agroups,clip=tonumber(meta.clip) or -1,duration=tonumber(meta.duration) or 0,frameSpacing=tonumber(meta.frameSpacing) or 1,
    morphFrames=tonumber(meta.morphFrames) or 0,jointPositions=meta.jointPositions or {},jointFrames=meta.jointFrames or {},
    floorMinYSlots=agroups._floorMinYSlots,validSlots=meta.validSlots}
end
local function runtimeActionMeta(scene,name,a)
  if not (scene and a and type(scene._runtimeStamp)=="string") then return nil end
  local out={runtimeMeshVersion=1,stamp=scene._runtimeStamp,clip=a.clip,duration=a.duration,frameSpacing=a.frameSpacing,
    totalIntervals=a.totalIntervals,morphFrames=a.morphFrames,jointPositions=a.jointPositions,jointFrames=a.jointFrames,validSlots=a.validSlots}
  if a.alias then out.alias=a.alias
  elseif type(a.pages)=="table" then
    out.pages={}
    for i,p in ipairs(a.pages) do out.pages[i]={startPhase=p.startPhase,endPhase=p.endPhase,morphFrames=p.morphFrames,
      jointPositions=p.jointPositions,jointFrames=p.jointFrames,validSlots=p.validSlots,groupCount=type(p.groups)=="table" and #p.groups or 0} end
  else out.groupCount=type(a.groups)=="table" and #a.groups or 0 end
  return out
end

local function materializeSceneAction(scene,name)
  if not (scene and name) then return nil,"action scene unavailable" end
  scene.actions=scene.actions or {}
  if scene.actions[name] then return scene.actions[name] end
  scene.actionFailures=scene.actionFailures or {}
  if scene.actionFailures[name] then
    return nil,tostring(scene.actionFailures[name])
  end
  local function fail(reason)
    reason=tostring(reason or "action materialization failed")
    scene.actionFailures[name]=reason
    log("warn","dex %s native action %s: %s",tostring(scene.dex),tostring(name),reason)
    return nil,reason
  end
  local a=scene.actionSpecs and scene.actionSpecs[name]

  if not scene._compactActionInventory
      and not (scene._bypassActionRuntime and scene._bypassActionRuntime[name])
      and RuntimeMeshCache and type(RuntimeMeshCache.readLua)=="function" then
    local meta=select(1,RuntimeMeshCache.readLua(runtimeActionManifestPath(scene.dex,name)))
    local runtimeEntry=runtimeActionEntry(scene,name,meta)
    if runtimeEntry then
      scene.actions[name]=runtimeEntry
      if scene.actionSpecs then scene.actionSpecs[name]=nil end
      perf.actionBuilds=perf.actionBuilds+1;perf.runtimeActionHits=(perf.runtimeActionHits or 0)+1
      return runtimeEntry
    end
  end

  -- A committed action-only descriptor can supersede a stale full-cache alias.
  -- This does not rewrite the body inventory or read the imported source.
  local n=Dex and dexNumber(scene.dex)
  local variant=Dex and type(Dex.variant)=="function" and Dex.variant(scene.dex) or "normal"
  local repaired=n and readSelectiveActionRef(n,variant,name)
  if repaired then a=repaired end
  if type(a)~="table" then return fail("action source reference missing: "..tostring(name)) end

  -- Keep path/read/parse/geometry/upload failures distinct all the way to the
  -- preparation controller. Previously every one became the same physicalA
  -- message, hiding whether a retry could do useful work.
  if a.path then
    local payload,perr=readLua(a.path)
    if type(payload)~="table" then
      return fail("action cache "..tostring(a.path)..": "..tostring(perr or "not a table"))
    end
    payload.clip=payload.clip or a.clip
    payload.duration=payload.duration or a.duration
    a=payload
  end

  perf.actionBuilds=perf.actionBuilds+1
  local entry,buildWhy
  if a.alias then
    entry={alias=tostring(a.alias),clip=tonumber(a.clip),duration=tonumber(a.duration) or 0}
  elseif type(a.pages)=="table" and #a.pages>0 then
    local pages={};local valid=true
    local compactMemo={}
    local settle=A._watchActionBuild({pages=pages})
    for pi,page in ipairs(a.pages) do
      local pgroups,why
      if type(page)=="table" and scene._buildActionGroups then
        pgroups,why=scene._buildActionGroups(page.groups,name.."/page"..pi,compactMemo)
      end
      if not pgroups then
        valid=false;buildWhy="page "..pi..": "..tostring(why or "action page missing")
        settle(false);break
      end
      pages[#pages+1]={
        groups=pgroups,
        startPhase=math.max(0,math.min(1,tonumber(page.startPhase) or 0)),
        endPhase=math.max(0,math.min(1,tonumber(page.endPhase) or 1)),
        morphFrames=math.max(0,math.min(12,tonumber(page.morphFrames) or 0)),
        jointPositions=page.jointPositions or {},jointFrames=page.jointFrames or {},
        floorMinYSlots=pgroups._floorMinYSlots,validSlots=page.validSlots,dense=true,
      }
    end
    if valid and #pages>0 then
      entry={pages=pages,dense=true,clip=tonumber(a.clip) or -1,
        duration=tonumber(a.duration) or 0,frameSpacing=tonumber(a.frameSpacing) or 1,
        totalIntervals=tonumber(a.totalIntervals) or 0}
    end
    settle(valid and entry~=nil)
  else
    local agroups
    if scene._buildActionGroups then agroups,buildWhy=scene._buildActionGroups(a.groups,name) end
    if agroups then
      entry={groups=agroups,clip=tonumber(a.clip) or -1,duration=tonumber(a.duration) or 0,
        frameSpacing=tonumber(a.frameSpacing) or 1,morphFrames=math.max(0,math.min(12,tonumber(a.morphFrames) or 0)),
        jointPositions=a.jointPositions or {},jointFrames=a.jointFrames or {},
        floorMinYSlots=agroups._floorMinYSlots,validSlots=a.validSlots}
    end
  end
  if not entry then return fail(buildWhy) end

  scene.actions[name]=entry
  if tonumber(a.packedActionVersion)~=A._compactAction.version
      and RuntimeMeshCache and type(RuntimeMeshCache.writeLua)=="function" then
    local meta=runtimeActionMeta(scene,name,a)
    local preserveManifest=type(RuntimeMeshCache.exists)=="function" and RuntimeMeshCache.exists(runtimeActionManifestPath(scene.dex,name)) or false
    if meta and RuntimeMeshCache.writeLua(runtimeActionManifestPath(scene.dex,name),meta,preserveManifest) then perf.runtimeActionWrites=(perf.runtimeActionWrites or 0)+1 end
  end
  if scene.actionSpecs then scene.actionSpecs[name]=nil end
  return entry
end

local PREWARM_ORDER={"damage","faint","physicalA","specialA"}
local function prewarmScene(scene)
  if not (scene and scene.actionSpecs) then return false end
  local now=(love and love.timer and love.timer.getTime and love.timer.getTime()) or 0
  if now>0 and scene._nextPrewarmAt and now<scene._nextPrewarmAt then return false end
  local start=tonumber(scene._prewarmIndex) or 1
  for i=start,#PREWARM_ORDER do
    scene._prewarmIndex=i+1
    local key=PREWARM_ORDER[i]
    if scene.actionSpecs[key] and not (scene.actionFailures and scene.actionFailures[key]) then
      if WorkBudget and type(A.queueSceneAction)=="function" then
        -- Actor:update can run several times per frame at fast game speeds.
        -- Only enqueue here; the single post-frame worker owns CPU/GPU work.
        A.queueSceneAction(scene,key)
        if now>0 then scene._nextPrewarmAt=now+0.10 end
        return true
      end
      local entry=materializeSceneAction(scene,key)
      local guard=0
      while entry and entry.alias and guard<8 do
        entry=materializeSceneAction(scene,tostring(entry.alias))
        guard=guard+1
      end
      if entry then perf.actionPrewarms=perf.actionPrewarms+1 end
      if now>0 then scene._nextPrewarmAt=now+0.10 end
      return entry~=nil
    end
  end
  return false
end

-- ---------------------------------------------------------------- actor ----

local Actor={}
Actor.__index=Actor

local function clamp(v,a,b) if v<a then return a elseif v>b then return b else return v end end

-- LuaJIT/Lua 5.1 exposes the quadrant-aware function as math.atan2. Passing a
-- second argument to math.atan is silently ignored there. The old code did
-- exactly that, so the straight-ahead arena gave both battlers yaw 0: the
-- enemy happened to be correct while the player never received its pi turn.
-- Keep a small fallback for hosts that expose only the Lua 5.3 math surface.
local function atan2(y,x)
  y=tonumber(y) or 0;x=tonumber(x) or 0
  if type(math.atan2)=="function" then return math.atan2(y,x) end
  if x>0 then return math.atan(y/x) end
  if x<0 then return math.atan(y/x)+(y>=0 and math.pi or -math.pi) end
  if y>0 then return math.pi*.5 end
  if y<0 then return -math.pi*.5 end
  return 0
end

-- Pure and exported for regression tests. Local PKX +Z is aimed at the
-- opponent. This gives enemy=0 and player=pi in the default straight arena,
-- while diagonal recipes retain their authored target line.
function A.facingYaw(towardX,towardZ)
  return atan2(towardX,towardZ)
end

function Actor.new(dex,variant,scene,opts)
  opts=type(opts)=="table" and opts or {}
  local services=opts.context and opts.context.services
  local informationSurface=services and services.informationSurface==true or false
  return setmetatable({
    dex=dex,variant=variant,scene=scene,
    side=opts.side,
    informationSurface=informationSurface,
    informationAnimation=informationSurface and (not services or services.informationAnimation~=false),
    clock=0,state="spawn",stateAge=0,
    action=nil,actionAge=0,spawnScale=0,
    hitAge=nil,hitStrength=1,faintAge=nil,faintKind=nil,pendingFaint=nil,pendingHits=nil,
    pendingAttack=nil,pendingRecall=nil,sourceWazaPoseLock=false,
    recallAge=nil,recallReason=nil,recallScale=nil,
    height=(scene.bounds and scene.bounds.max and scene.bounds.min
      and (scene.bounds.max[2]-scene.bounds.min[2])) or 16,
  },Actor)
end

local SPECIAL_TYPES={FIRE=true,WATER=true,GRASS=true,ELECTRIC=true,ICE=true,PSYCHIC=true,DRAGON=true,DARK=true}
local NUMERIC_SPECIAL_TYPES={
  -- Colosseum/common Gen-III enum.
  [10]=true,[11]=true,[12]=true,[13]=true,[14]=true,[15]=true,[16]=true,[17]=true,
  -- Gen1Recomp's cartridge-native Gen-I/II enum (the elemental block begins at 20).
  [20]=true,[21]=true,[22]=true,[23]=true,[24]=true,[25]=true,[26]=true,[27]=true,
}
local function moveSlot(moveDef)
  -- Colosseum's ordinary body-motion dispatch follows the generation-III
  -- type split: Fire/Water/Grass/Electric/Ice/Psychic/Dragon/Dark use Special-A
  -- (PKX slot 1), while the remaining types use Physical-A (slot 2). This is
  -- source engine behavior, not the later physical/special damage-class field.
  -- Stateful exceptions may explicitly pass nativeSlot through Actor:attack.
  if type(moveDef)=="table" then
    local rawType=moveDef.type
    if type(rawType)=="table" then rawType=rawType.name or rawType.id or rawType.index end
    local numericType=tonumber(rawType)
    if numericType~=nil then return NUMERIC_SPECIAL_TYPES[numericType] and "specialA" or "physicalA" end
    local typ=tostring(rawType or ""):upper():gsub("[^A-Z]","")
    if typ~="" then return SPECIAL_TYPES[typ] and "specialA" or "physicalA" end
  end
  local category=type(moveDef)=="table" and (moveDef.category or moveDef.damageClass or moveDef.class) or nil
  category=tostring(category or ""):lower()
  if category:find("special",1,true) then return "specialA" end
  if category:find("physical",1,true) then return "physicalA" end
  return "physicalA"
end

local NATIVE_FALLBACKS={
  idle={"idle"},
  specialA={"specialA","specialB","specialC"}, specialB={"specialB","specialA","specialC"},
  specialC={"specialC","specialA","specialB"},
  physicalA={"physicalA","physicalB","physicalC","physicalD","physicalE"},
  physicalB={"physicalB","physicalA"},physicalC={"physicalC","physicalA"},
  physicalD={"physicalD","physicalA"},physicalE={"physicalE","physicalA"},
  damage={"damage"},damageHeavy={"damageHeavy"},
  faint={"faint"},takeFlight={"takeFlight"},extra1={"extra1"},extra2={"extra2"},extra3={"extra3"},extra4={"extra4"},
}

local function resolveSceneAction(scene,name,allowBuild,strict)
  if not (scene and scene.actions) then return nil,nil,nil end
  if allowBuild==nil then allowBuild=true end
  local wanted=strict and {name} or (NATIVE_FALLBACKS[name] or {name})
  for _,key in ipairs(wanted) do
    local entry=scene.actions[key]
    if not entry and allowBuild then entry=materializeSceneAction(scene,key) end
    if entry then
      local duration=tonumber(entry.duration) or 0
      local resolved=entry;local guard=0
      while resolved and resolved.alias and guard<8 do
        local alias=tostring(resolved.alias)
        resolved=scene.actions[alias]
        if not resolved and allowBuild then resolved=materializeSceneAction(scene,alias) end
        guard=guard+1
      end
      if resolved and (resolved.groups or (type(resolved.pages)=="table" and #resolved.pages>0)) then
        if duration<=0 then duration=tonumber(resolved.duration) or 0 end
        return resolved,key,duration
      end
    end
  end
  return nil,nil,nil
end

function Actor:selectNativeSlot(name,strict)
  self.requestedNativeSlot=name
  self.nativeSlotStrict=strict==true
  local slot=self.sourceMetadata and self.sourceMetadata.slots and self.sourceMetadata.slots[name]
  self.nativeSlot=slot
  self.nativeClip=slot and slot.animationIndex or nil

  -- Idle is already represented by the base source-authored body bank loaded
  -- with the species. Do not force a second full idle GPU bank onto the battle
  -- entry or Stats-menu frame. If the idle action has been warmed, use it;
  -- otherwise animate the base bank at the authoritative source duration.
  local allowBuild=(name~="idle") or (not self.informationSurface and not WorkBudget)
    or (name=="idle" and self._allowInformationIdleBuild==true)
  local action,resolvedName,duration=resolveSceneAction(self.scene,name,allowBuild,strict==true)
  self.nativeAction=action
  self.nativeActionName=resolvedName
  local slotDuration=slot and tonumber(slot.duration) or 0
  if (not duration or duration<=0.02) and slotDuration>0.02 then duration=slotDuration end
  self.nativeDuration=(duration and duration>0.02) and duration or nil
  self.nativeSlotSampled=action~=nil
  self.clipClock=0
  return self.nativeSlotSampled,slot
end

-- Colosseum's WazaSequence does not store absolute start frames for every
-- entry. It synchronizes against timing points from the Pokemon's currently
-- selected native PKX motion. PKXMetadata stores those four values in seconds;
-- expose the exact 60 Hz source ticks expected by the retail Waza scheduler.
function Actor:wazaTimingPoints()
  local slot=self.nativeSlot
  local src=slot and slot.timing
  local out={}
  for i=1,4 do
    local sec=type(src)=="table" and tonumber(src[i]) or nil
    if sec then out[i]=math.floor(math.max(0,sec)*60+.5) end
  end
  -- Point zero is the sequence origin even for metadata rows whose first timed
  -- event is later in the clip. Preserve the authored PKX value when present;
  -- if an unusual slot omitted it, the scheduler's explicit fallback handles it.
  return out
end

-- Exact camera-specific prefix of the same PKX runtime row.  Do not fold this
-- into wazaTimingPoints(): the existing scheduler field intentionally begins at
-- source +0x10, while retail DoFOV reads countA and +0x0C/+0x10/+0x14.
function Actor:wazaCameraTiming()
  local slot=self.nativeSlot
  if not (type(slot)=="table" and slot.cameraTimingExact==true) then return nil end
  local count=math.max(0,math.floor(tonumber(slot.cameraTimingCount) or 0))
  local frames={}
  for i=1,math.min(3,count) do
    local v=tonumber(slot.cameraTimingFrames and slot.cameraTimingFrames[i])
    if v==nil then return nil end
    frames[i]=v
  end
  -- DoPosition derives its move duration from the SAME runtime 0xD4 row. After
  -- sequenceLoad, words are laid out as countA, countB+1, field08, then the
  -- scaled camera-timing stream at +0x0C. Its duration pointer is
  --   row + countA*4; read +4, falling back to +8 only when zero.
  -- Preserve that exact deterministic duration whenever the referenced words
  -- are inside the prefix we already source-prove. (Mode 0 may still randomize
  -- the duration later in DoDollyPosition; Camera reports that separately.)
  local durationFrames,durationExact
  if count==0 then
    durationFrames=(math.max(0,math.floor(tonumber(slot.subAnimCount) or 0))+1)
    if durationFrames==0 then durationFrames=tonumber(slot.damageFlags) or 0 end
    durationExact=true
  elseif count==1 then
    durationFrames=tonumber(slot.damageFlags) or 0
    if durationFrames==0 then durationFrames=frames[1] or 0 end
    durationExact=true
  elseif count<=3 then
    durationFrames=frames[count-1] or 0
    if durationFrames==0 then durationFrames=frames[count] or 0 end
    durationExact=true
  end
  -- Waza DoFOV chooses its short/long pattern table from ModelSequence+0x32,
  -- which is the currently selected native PKX row index. `slot.index` is that
  -- exact 0..16 row identity; expose it alongside the already-proven timing
  -- prefix so passive battleCameraStartWaza(owner,NULL) can use the same retail
  -- FOV grammar without guessing from move category or host generation.
  return {count=count,frames=frames,rate=tonumber(slot.cameraTimingRate) or 60,
    sequenceKind=tonumber(slot.index),motionDurationFrames=durationFrames,
    motionDurationExact=durationExact==true,exact=true}
end

-- Exact GC6E01 GSmodel bound baked when the Pokemon Waza owner is first loaded.
-- PokemonExtractor preserves both raw retail units (for CalculateParams/DoFOV)
-- and the exact source->normalized-cache affine (for the 0x4000 midpoint). Keep
-- current attack-slot animation out of this accessor: retail does not recalc the
-- owner bound when a later Waza changes the active body animation.
function Actor:retailWazaOwnerBound()
  local b=self.scene and self.scene.retailWazaOwnerBound
  if not (type(b)=="table" and b.exact==true and b.selectorExact==true
      and type(b.source)=="table" and type(b.normalized)=="table") then return nil end
  local n=b.normalized
  local c=n.center
  local e=n.extent
  local src=b.source
  if not (type(c)=="table" and tonumber(c[1]) and tonumber(c[2]) and tonumber(c[3])
      and type(e)=="table" and tonumber(e[1]) and tonumber(e[2]) and tonumber(e[3])
      and type(src.min)=="table" and type(src.max)=="table") then return nil end
  local out={exact=true,frame=0,animationIndex=tonumber(b.animationIndex),selector=b.selector,
    selectorExact=true,source=src,normalized=n,sourceToCache=b.sourceToCache}
  local m=self.worldMatrix
  local scale=tonumber(self.worldScale)
  if type(m)=="table" and tonumber(m[4]) and tonumber(m[8]) and tonumber(m[12]) and scale then
    -- battleCameraStartWaza adds GSbound midpoint directly to GSmodel.position;
    -- it does NOT rotate that midpoint by the current GSmodel rotation. Mirror
    -- that order in CBE presentation space: normalize, apply the actor's uniform
    -- body scale, then add the current model-root translation.
    out.centerWorld={m[4]+c[1]*scale,m[8]+c[2]*scale,m[12]+c[3]*scale}
    out.presentationExtent={e[1]*scale,e[2]*scale,e[3]*scale}
  end
  return out
end

local ATTACK_DURATION=0.85
local HIT_DURATION=0.46
local FAINT_DURATION=0.95
local RECALL_DURATION=0.48
local FAINT_REMOVAL_TAIL=0.28

-- Timing queries are read-only. In particular the faint-return director asks
-- for the upcoming Faint duration while Damage is still active. Resolving with
-- allowBuild=true here used to parse caches and upload the entire Faint bank on
-- the visible update thread, outside the cooperative worker. Source descriptors
-- already carry duration; follow aliases without reading or materializing them.
function A._sceneActionDuration(scene,name)
  local seen={};local duration
  for _=1,8 do
    if not name or seen[name] then break end
    seen[name]=true
    local entry=scene and ((scene.actions and scene.actions[name])
      or (scene.actionSpecs and scene.actionSpecs[name]))
    if type(entry)~="table" then break end
    local d=tonumber(entry.duration)
    if not duration and d and d>0.02 and d<math.huge then duration=d end
    if not entry.alias then break end
    name=tostring(entry.alias)
  end
  return duration
end

function Actor:stateDuration(kind)
  if kind=="recall" then return RECALL_DURATION end
  -- Queries made while Damage is still playing must use the upcoming faint
  -- bank, not the currently selected Damage/attack duration.
  if kind=="faint" and self.state~="faint" then
    local duration=A._sceneActionDuration(self.scene,"faint")
    local slot=self.sourceMetadata and self.sourceMetadata.slots and self.sourceMetadata.slots.faint
    local sourceDuration=slot and tonumber(slot.duration)
    if not duration and sourceDuration and sourceDuration>0.02 and sourceDuration<math.huge then
      duration=sourceDuration
    end
    return duration or FAINT_DURATION
  end
  if self.nativeAction and self.nativeDuration and self.nativeDuration>0 then return self.nativeDuration end
  if kind=="attack" then return ATTACK_DURATION end
  if kind=="hit" then return HIT_DURATION end
  if kind=="faint" then return FAINT_DURATION end
  return RECALL_DURATION
end

function Actor:terminalDuration(kind)
  local base=self:stateDuration(kind)
  if kind=="faint" then return base+FAINT_REMOVAL_TAIL end
  return base
end

function Actor:faintBodyComplete()
  if self.pendingFaint or self.state~="faint" then return false end
  local clock=self.nativeSlotSampled and self.clipClock or self.faintAge
  return (tonumber(clock) or 0)+1e-7>=self:stateDuration("faint")
end

function Actor:update(dt)
  local step=math.max(0,tonumber(dt) or 0)
  self.clock=self.clock+step
  self.clipClock=(self.clipClock or 0)+step
  self.stateAge=(self.stateAge or 0)+step
  -- Advance only terminal states that were already active at this frame's
  -- start. Damage may hand off to Faint/Recall below and reset its clock to
  -- zero; charging that new state the full step again skipped its opening pose
  -- and let the removal tail get ahead of the native animation.
  if self.faintAge then self.faintAge=self.faintAge+step end
  if self.recallAge then self.recallAge=self.recallAge+step end

  -- A live body can precede its exact-action preparation. Pick up the worker's
  -- tiny authoritative timing record without reading the disc or rebuilding a
  -- bank. Promote a warmed idle only while idle and retain its elapsed phase.
  if not self.informationSurface then
    local ready=sourceMetadata[tostring(self.cacheKey or (self.scene and self.scene.dex))]
    if type(ready)=="table" and ready~=self.sourceMetadata then
      self.sourceMetadata=ready
      local slot=ready.slots and ready.slots[self.requestedNativeSlot or "idle"]
      self.nativeSlot=slot;self.nativeClip=slot and slot.animationIndex or nil
    end
    if self.state=="idle" and not self.nativeAction and self.scene
        and self.scene.actions and self.scene.actions.idle then
      local elapsed=self.clipClock
      self:selectNativeSlot("idle")
      self.clipClock=elapsed
    end
  end

  -- Information viewers prioritize first-pixel latency: draw the compact base
  -- scene immediately, then upgrade the already-visible actor to its source idle
  -- bank on a later frame. Do this whenever an idle action is available, even if
  -- the compact base advertises morphFrames: those base morphs are not guaranteed
  -- to be the authored looping idle. 1.9.4's `baseFrames <= 0` gate therefore
  -- left many PC species (including ordinary cached models) completely static.
  if self.informationSurface and self.informationAnimation and self.state=="idle"
      and not self.nativeAction and not self._informationIdleTried
      and (tonumber(self.clock) or 0)>=0.06
      and (not self._informationIdleNextCheck or self.clock>=self._informationIdleNextCheck) then
    local hasIdle=self.scene and ((self.scene.actionSpecs and self.scene.actionSpecs.idle)
      or (self.scene.actions and self.scene.actions.idle))
    if hasIdle then
      -- Never decode/build a large authored idle bank from its source payload on
      -- the active UI thread. Hard Cache Save or the deferred information warm
      -- prepares the compact f32 sidecar first; only then is the lightweight GPU
      -- promotion allowed. Until then the already-visible base bank keeps moving
      -- and the model viewer remains responsive.
      local prepared=(self.scene.actions and self.scene.actions.idle)~=nil
        or runtimeActionSidecarReady(self.scene,"idle")
      if prepared then
        self._informationIdleTried=true
        self._allowInformationIdleBuild=true
        pcall(self.selectNativeSlot,self,"idle")
        self._allowInformationIdleBuild=nil
      else
        self._informationIdleDeferred=true
        self._informationIdleNextCheck=(tonumber(self.clock) or 0)+0.75
      end
    else
      self._informationIdleTried=true
    end
  end
  if self.action then
    self.actionAge=self.actionAge+step
    if self.actionAge>self:stateDuration("attack") then
      self.action=nil;self.actionAge=0;self.sourceWazaPoseLock=false
      if not self.hitAge and not self.faintAge and not self.recallAge then
        self:selectNativeSlot("idle");self:transition("idle")
      end
    end
  end
  if self.hitAge then
    self.hitAge=self.hitAge+step
    if self.hitAge>self:stateDuration("hit") then
      self.hitAge=nil
      -- A lethal hit is still a hit. BattleState can mark the battler fainted
      -- before its later faint presentation event arrives; older CBE builds
      -- therefore destroyed the actor at 0 HP before the Damage bank could
      -- finish. Queue faint behind the complete hurt clip instead of replacing
      -- it, so every impact remains visible and then flows into the authored KO.
      if self.pendingHits and #self.pendingHits>0 then
        local nextHit=table.remove(self.pendingHits,1)
        if type(nextHit)=="table" and nextHit.__cbeQueuedHit==true then
          self:beginHit(nextHit.payload,nextHit.opts)
        else
          self:beginHit(nextHit)
        end
      elseif self.pendingFaint then
        local disposition=self.pendingFaint
        self.pendingFaint=nil
        self:faint(disposition)
      elseif self.pendingRecall then
        local reason=self.pendingRecall
        self.pendingRecall=nil
        self:recall(reason)
      elseif self.pendingAttack then
        local q=self.pendingAttack
        self.pendingAttack=nil
        self:attack(q.moveId,q.moveDef,q.opts)
      elseif not self.action and not self.faintAge and not self.recallAge then
        self:selectNativeSlot("idle");self:transition("idle")
      end
    end
  end
  -- Warm common native battle banks only after the actor is fully visible and
  -- idle. This keeps extraction/cache parsing/GPU uploads off black transition
  -- frames and completely out of read-only Stats showrooms. One bank at most
  -- every 100 ms avoids a single giant startup spike while usually having the
  -- exact attack/damage/faint bank resident before the player uses it.
  if not self.informationSurface and self.state=="idle"
      and (tonumber(self.spawnScale) or 0)>=0.999 and (tonumber(self.stateAge) or 0)>=0.18 then
    prewarmScene(self.scene)
  end
end

function Actor:transition(state)
  state=tostring(state or "idle")
  if self.state~=state then self.state=state;self.stateAge=0 end
end

function Actor:spawn(progress)
  local p=clamp(tonumber(progress) or 1,0,1)
  self.spawnScale=p
  if p<1 then
    if self.state~="faint" and self.state~="removal" then self:transition("spawn") end
  elseif self.state=="spawn" then
    self:selectNativeSlot("idle");self:transition("idle")
  end
end

function Actor:idle()
  -- Native Damage owns the actor until its authored duration is complete.
  -- Text/turn state can request idle on the same frame as impact; accepting that
  -- request used to truncate the source hurt clip. Ignore it and let update()
  -- perform the single deterministic Damage -> next-state handoff.
  if self.hitAge then return false end
  -- Idle is a state notification, not a request to rewind the source clip.
  -- Hosts may publish it repeatedly during commands/text and in both battle
  -- modes; preserve the current loop phase when it is already playing.
  if self.state=="idle" and self.requestedNativeSlot=="idle" and not self.action then return true end
  if self.state~="faint" and self.state~="recall" and self.state~="removal" then
    self.action=nil;self.actionAge=0;self.sourceWazaPoseLock=false;self:selectNativeSlot("idle");self:transition("idle")
    return true
  end
  return false
end

local FRAME_RATE=11

-- Continuous source-pose playback. 1.5.45 only interpolated Damage/Faint;
-- attacks still rounded to one of twelve cached poses, which made otherwise
-- correct Colosseum clips look like stop-motion. Every verified native bank now
-- interpolates on source timing. When all neighbouring samples decoded we use a
-- low-tension cubic Hermite/Catmull path for C1-continuous motion; if extraction
-- left a hole, playback falls back to linear interpolation between the nearest
-- validated source samples instead of ever popping through the frame-0 body.
local function addWeight(w,idx,value,n)
  if math.abs(value)<1e-9 then return end
  if idx<0 then idx=0 elseif idx>n then idx=n end
  w[idx+1]=(w[idx+1] or 0)+value
end

local function slotValid(mask,idx)
  if idx==0 then return true end
  if type(mask)~="table" then return true end
  local v=mask[idx]
  return v==true or v==1
end

local function nearestValid(mask,idx,dir,n)
  local i=idx
  while i>=0 and i<=n do
    if slotValid(mask,i) then return i end
    i=i+dir
  end
  return nil
end

local function linearValidWeights(w,t,n,mask)
  local lo=math.floor(t);local hi=math.ceil(t)
  lo=nearestValid(mask,lo,-1,n) or nearestValid(mask,lo,1,n) or 0
  hi=nearestValid(mask,hi,1,n) or nearestValid(mask,hi,-1,n) or lo
  if hi<lo then lo,hi=hi,lo end
  if hi==lo then w[lo+1]=1;return w end
  local f=clamp((t-lo)/(hi-lo),0,1)
  w[lo+1]=1-f;w[hi+1]=(w[hi+1] or 0)+f
  return w
end

local function loopSeamWeights(w,t,n,mask)
  local last=nearestValid(mask,n,-1,n) or 0
  if t<=last then return nil end
  -- The final source sample may be rejected. Interpolate from the last valid
  -- sample across the complete remaining interval to frame zero; never expose
  -- the invalid stream or hold it until the next loop snaps back to the base.
  local f=clamp((t-last)/(n+1-last),0,1)
  w[last+1]=1-f;w[1]=(w[1] or 0)+f
  return w
end

local function cubicWeights(w,t,n,mask,looping)
  local i=math.floor(t);local f=t-i
  if i>=n then w[n+1]=1;return w end
  local i1=i;local i2=i+1
  -- A cubic segment is only safe when the two segment endpoints themselves are
  -- real samples. Missing samples are handled by nearest-valid linear playback.
  if not slotValid(mask,i1) or not slotValid(mask,i2) then
    return linearValidWeights(w,t,n,mask)
  end
  local function wrap(v)
    if looping then
      local total=n+1
      return ((v%total)+total)%total
    end
    return math.max(0,math.min(n,v))
  end
  local i0=wrap(i-1);local i3=wrap(i+2)
  if not slotValid(mask,i0) or not slotValid(mask,i3) then
    return linearValidWeights(w,t,n,mask)
  end
  local f2,f3=f*f,f*f*f
  -- Hermite form with restrained source tangents. Standard Catmull-Rom uses
  -- gain .5; .38 keeps continuous velocity without overshooting highly
  -- articulated Pokemon limbs between sparse source samples.
  local g=.38
  local h00=2*f3-3*f2+1
  local h10=f3-2*f2+f
  local h01=-2*f3+3*f2
  local h11=f3-f2
  addWeight(w,i0,-h10*g,n)
  addWeight(w,i1,h00-h11*g,n)
  addWeight(w,i2,h01+h10*g,n)
  addWeight(w,i3,h11*g,n)
  return w
end

-- `validSlots` is indexed 1..12 for the authored targets; base frame 0 is
-- always validated. `smoothNative` is true for source-backed action banks.
function A.frameWeights(clock,morphFrames,action,duration,looping,smoothNative,validSlots)
  local w={0,0,0,0,0,0,0,0,0,0,0,0,0}
  local n=math.max(0,math.min(12,tonumber(morphFrames) or 0))
  if n<1 then w[1]=1;return w end
  local dur=tonumber(duration)
  if dur and dur>0.02 then
    local c=math.max(0,tonumber(clock) or 0)
    local t
    if looping then
      local phase=(c%dur)/dur
      t=phase*(n+1)
      local seam=loopSeamWeights(w,t,n,validSlots)
      if seam then return seam end
    else
      t=clamp(c/dur,0,1)*n
    end
    if smoothNative and n>=3 then return cubicWeights(w,t,n,validSlots,looping) end
    return linearValidWeights(w,t,n,validSlots)
  end
  local total=n+1
  local speed=(action=="attack") and (FRAME_RATE*2.1) or FRAME_RATE
  local t=((tonumber(clock) or 0)*speed)%total
  if t<0 then t=t+total end
  local seam=loopSeamWeights(w,t,n,validSlots)
  if seam then return seam end
  return linearValidWeights(w,t,n,validSlots)
end

function Actor:playbackBank()
  local bank=self.nativeAction
  if not bank then
    local duration=self.nativeDuration
    if (self.state=="idle" or self.state=="spawn") and (not duration or duration<=0) then
      duration=self.scene.idleDuration
    end
    return self.scene,self.clipClock or self.clock,duration,false
  end
  if type(bank.pages)=="table" and #bank.pages>0 then
    local duration=math.max(.001,tonumber(self.nativeDuration) or tonumber(bank.duration) or 1)
    local clock=math.max(0,tonumber(self.clipClock) or 0)
    -- Dense PKX action banks are paged only for GPU/cache size; paging must not
    -- turn an authored looping idle into a one-shot. The old clamp pinned every
    -- information-viewer idle to the final page after one duration, which is why
    -- PC models visibly became statues even though Actor:update kept running.
    local phase
    if self.state=="idle" or self.state=="spawn" then phase=(clock%duration)/duration
    else phase=clamp(clock/duration,0,1) end
    local page=bank.pages[#bank.pages]
    for _,candidate in ipairs(bank.pages) do
      if phase<=((tonumber(candidate.endPhase) or 1)+1e-7) then page=candidate;break end
    end
    local a=tonumber(page.startPhase) or 0
    local b=math.max(a+1e-6,tonumber(page.endPhase) or 1)
    local localPhase=clamp((phase-a)/(b-a),0,1)
    return page,localPhase,1,true
  end
  return bank,self.clipClock or self.clock,self.nativeDuration,false
end

function Actor:frameWeights()
  local bank,clock,duration,dense=self:playbackBank()
  local n=bank and bank.morphFrames or self.scene.morphFrames
  local looping=(self.state=="idle" or self.state=="spawn") and not dense
  -- Native playback uses non-negative interpolation between real source poses.
  -- Dense reaction pages make those neighbours tightly spaced; sparse banks are
  -- still kept linear rather than inventing cubic vertex-space overshoot that
  -- does not exist in Colosseum's skeletal evaluator.
  return A.frameWeights(clock,n,self.action,duration,looping,
    false,bank and bank.validSlots)
end

local function weightedFloorMinY(actor)
  local bank=actor and actor:playbackBank()
  local mins=bank and bank.floorMinYSlots
  if type(mins)=="table" then
    local w=actor:frameWeights();local y,total=0,0
    for i=1,13 do
      local weight=tonumber(w and w[i]) or 0
      local v=tonumber(mins[i])
      if weight~=0 and v then y=y+v*weight;total=total+weight end
    end
    if total>1e-7 then return y/total end
  end
  return tonumber(actor and actor.scene and actor.scene.floorMinY)
    or tonumber(actor and actor.scene and actor.scene.bounds and actor.scene.bounds.min and actor.scene.bounds.min[2]) or 0
end

-- Return a conservative local-space lower Y after CBE's fallback pitch/roll.
-- Native HSD actions normally use no extra whole-actor rotation, but fallback
-- recoil/faint motion does.  Clamping only the unrotated minY let a corner of a
-- rotated model pass through the arena even though its origin remained above 0.
local function rotatedFloorMinY(actor,authoredMinY,pitch,roll)
  if math.abs(pitch or 0)<1e-7 and math.abs(roll or 0)<1e-7 then return authoredMinY end
  local b=actor and actor.scene and actor.scene.bounds or nil
  local mn=b and b.min or {-1,authoredMinY,-1}
  local mx=b and b.max or {1,(authoredMinY or 0)+(actor and actor.height or 1),1}
  local minY=math.huge
  local cp,sp=math.cos(pitch or 0),math.sin(pitch or 0)
  local cr,sr=math.cos(roll or 0),math.sin(roll or 0)
  for _,xx in ipairs({tonumber(mn[1]) or -1,tonumber(mx[1]) or 1}) do
    for _,yy in ipairs({tonumber(authoredMinY) or 0,tonumber(mx[2]) or 1}) do
      for _,zz in ipairs({tonumber(mn[3]) or -1,tonumber(mx[3]) or 1}) do
        -- model = Ry * Rz * Rx * S; yaw leaves Y unchanged.
        local y1=yy*cp-zz*sp
        local x1=xx
        local y2=x1*sr+y1*cr
        if y2<minY then minY=y2 end
      end
    end
  end
  return minY~=math.huge and minY or authoredMinY
end

-- Burrowed Pokemon are authored with meaningful geometry below the battle
-- plane. The generic solid-floor clamp previously lifted their ENTIRE source
-- body above ground, which is why Diglett appeared as a complete underground
-- model standing on the arena. Permit the lower source body to remain buried
-- while still clamping every other species/reaction normally.
local BURROWED_GROUND_DEPTH={
  [50]=.46, -- Diglett
  [51]=.38, -- Dugtrio
}

function Actor:matrix(x,groundY,z,towardX,towardZ)
  local s=self.worldScale or 1
  -- Use the portable quadrant-aware helper above; LuaJIT's math.atan ignores a
  -- second argument and was the source of the player-side orientation bug.
  local yaw=A.facingYaw(towardX or 0,towardZ or 1)
  -- Keep the battle-grid/base model rotation separate from the final render
  -- matrix.  Retail battleCameraStartWaza reads GSmodel.rotation, which is the
  -- placement yaw written by battleGridUpdate; it does NOT read reaction/faint
  -- roll that happens inside the animated body.  CBE can add a small fallback
  -- whole-actor roll below, so recovering the Waza owner rotation from
  -- worldMatrix would silently mix two different transform domains.
  self.worldYaw=yaw
  local lift,pitch,roll=0,0,0

  -- Spawn scale comes from BattleState.growInScale. A newly acquired actor
  -- outside a send-out boundary defaults to full size. Keep that authoritative
  -- scale, then add only presentation-space lift/flash around it.
  local spawn=clamp(self.spawnScale==nil and 1 or self.spawnScale,0,1)
  s=s*spawn
  if spawn<1 and not self.recallAge and not self.faintAge then
    lift=lift+(1-spawn)*0.9
  end

  if self.action=="attack" and not self.nativeAction and not self.sourceWazaPoseLock then
    local u=clamp(self.actionAge/self:stateDuration("attack"),0,1)
    local push=math.sin(u*math.pi)*0.9
    x=x+math.sin(yaw)*push;z=z+math.cos(yaw)*push
  end
  if self.hitAge and not self.nativeAction then
    local u=clamp(self.hitAge/self:stateDuration("hit"),0,1)
    local strength=clamp(tonumber(self.hitStrength) or 1,0.65,1.45)
    local kick=math.sin(u*math.pi)*(1-u)*0.72*strength
    local shake=math.sin(u*math.pi*5)*(1-u)*0.12*strength
    x=x-math.sin(yaw)*kick+math.cos(yaw)*shake
    z=z-math.cos(yaw)*kick-math.sin(yaw)*shake
    roll=roll+math.sin(u*math.pi)*0.06
  end
  if self.faintAge then
    local u=clamp(self.faintAge/self:stateDuration("faint"),0,1)
    -- If the exact native faint clip is present, keep the world transform
    -- restrained and let the authored frames speak. Otherwise use a compact
    -- whole-actor collapse as the portable fallback.
    if self.nativeSlotSampled then
      -- The authored Colosseum faint bank owns root/body motion completely.
      -- Do not add a second CBE-authored vertical drift on top of it.
    else
      roll=roll+u*(math.pi*0.46)
      lift=lift-u*0.12*self.height*(self.worldScale or 1)
    end
  end
  if self.recallAge then
    local timerU=clamp(self.recallAge/RECALL_DURATION,0,1)
    local keep=self.recallScale~=nil and clamp(self.recallScale,0,1) or (1-timerU)
    local u=1-keep
    -- Return is distinct from faint: contract toward the field anchor and rise
    -- slightly, giving the later ROM-derived ball/energy FX a stable endpoint.
    -- When Gen1Recomp exposes shrinkOutScale, CurrentSpriteModels feeds that
    -- exact 5/7 -> 3/7 -> 0 contract here; other hosts use the timer fallback.
    s=s*keep
    lift=lift+u*1.25
  end

  -- The arena floor is a SOLID presentation plane. Preserve every authored
  -- vertex/pose, but translate the complete actor upward if its currently
  -- sampled source geometry would penetrate Y=groundY. This handles flying,
  -- serpentine, damage and attack poses uniformly across every species.
  local authoredMinY=weightedFloorMinY(self)
  local collisionMinY=rotatedFloorMinY(self,authoredMinY,pitch,roll)
  self.forceBasePlayback=false
  -- Last-resort reaction guard.  A live battler is more important than a bad
  -- decoded pose: if a source reaction would require lifting the complete model
  -- by an implausible fraction of its own height, hold the resident base body for
  -- that frame instead of launching it above the camera or below the deck.  The
  -- corrected dense-page stabilizer should make this rare; it is an invariant
  -- backstop for older/generated caches and unusual species.
  if (self.hitAge or self.faintAge) then
    local baseMin=tonumber(self.scene and self.scene.floorMinY) or 0
    local h=math.max(.001,tonumber(self.height) or 1)
    if collisionMinY < baseMin-h*.58 then
      self.forceBasePlayback=true
      authoredMinY=baseMin
      collisionMinY=rotatedFloorMinY(self,baseMin,pitch,roll)
      perf.reactionFallbacks=(perf.reactionFallbacks or 0)+1
    end
  end
  -- Include every previously authored presentation lift in the collision
  -- equation. The old clamp solved only `minY * scale`; a fallback faint could
  -- then add a negative whole-body lift afterwards and sink through the deck
  -- despite reporting a successful floor clamp. Final invariant:
  --   groundY + lift + collisionMinY*scale >= groundY.
  local burrowFactor=BURROWED_GROUND_DEPTH[tonumber(self.dex)] or 0
  local allowedBelow=burrowFactor>0 and math.max(0,(tonumber(self.height) or 0)*s*burrowFactor) or 0
  local floorLift=math.max(0,-(collisionMinY*s+lift)-allowedBelow)
  if floorLift>1e-5 then
    lift=lift+floorLift+.002
    perf.floorClamps=(perf.floorClamps or 0)+1
  end
  self.floorLift=floorLift
  self.burrowDepth=allowedBelow
  self.authoredMinY=authoredMinY
  local m=Mat4.translate(x,(groundY or 0)+lift,z)
  m=Mat4.mul(m,Mat4.rotateY(yaw))
  if roll~=0 then m=Mat4.mul(m,Mat4.rotateZ(roll)) end
  if pitch~=0 then m=Mat4.mul(m,Mat4.rotateX(pitch)) end
  m=Mat4.mul(m,Mat4.scale(s,s,s))
  self.worldMatrix=m
  return m
end

function Actor:bodyMap()
  -- The PKX body map is authored per animation entry. WazaSequence::GetPart
  -- resolves attachments against the currently selected battle slot, not the
  -- idle row. Using one idle copy for every action makes mouth/chest/limb-bound
  -- effects detach or collapse toward the wrong joint while attacks animate.
  if self.nativeSlot and type(self.nativeSlot.bodyMap)=="table" then return self.nativeSlot.bodyMap end
  return self.sourceMetadata and self.sourceMetadata.bodyMap or nil
end

local function matrixPoint(m,p)
  if not (type(m)=="table" and type(p)=="table") then return nil end
  local x,y,z=tonumber(p[1]) or 0,tonumber(p[2]) or 0,tonumber(p[3]) or 0
  return {
    (m[1] or 1)*x+(m[2] or 0)*y+(m[3] or 0)*z+(m[4] or 0),
    (m[5] or 0)*x+(m[6] or 1)*y+(m[7] or 0)*z+(m[8] or 0),
    (m[9] or 0)*x+(m[10] or 0)*y+(m[11] or 1)*z+(m[12] or 0),
  }
end

-- Return the current authored HSD joint origin in the actor's normalized local
-- model space. The cache carries the same twelve source frames as the mesh, so
-- attachments remain on the mouth/chest/hands while an authored action plays.
function Actor:jointPosition(bone)
  bone=tonumber(bone)
  if not bone or bone<0 then return nil,"invalid body-map bone" end
  local bank=self:playbackBank()
  local base=bank and bank.jointPositions
  local frames=bank and bank.jointFrames
  local j=base and base[bone+1]
  if not j then return nil,("sampled joint %d unavailable"):format(bone) end
  local w=self:frameWeights()
  local x,y,z=(tonumber(j[1]) or 0)*(w[1] or 0),(tonumber(j[2]) or 0)*(w[1] or 0),(tonumber(j[3]) or 0)*(w[1] or 0)
  local total=w[1] or 0
  for slot=1,12 do
    local weight=w[slot+1] or 0
    if weight~=0 then
      local fj=frames and frames[slot] and frames[slot][bone+1]
      if fj then
        x=x+(tonumber(fj[1]) or 0)*weight
        y=y+(tonumber(fj[2]) or 0)*weight
        z=z+(tonumber(fj[3]) or 0)*weight
        total=total+weight
      else
        x=x+(tonumber(j[1]) or 0)*weight
        y=y+(tonumber(j[2]) or 0)*weight
        z=z+(tonumber(j[3]) or 0)*weight
        total=total+weight
      end
    end
  end
  if total<=1e-9 then return {j[1] or 0,j[2] or 0,j[3] or 0} end
  return {x/total,y/total,z/total}
end

function Actor:attachmentIndex(bone)
  local localPos,err=self:jointPosition(bone)
  if not localPos then return nil,err end
  if not self.worldMatrix then return nil,"actor world matrix unavailable" end
  local world=matrixPoint(self.worldMatrix,localPos)
  if not world then return nil,"joint world transform failed" end
  return {boneIndex=tonumber(bone),localPosition=localPos,position=world,source="pkx-body-map-hsd-joints"}
end

function Actor:attachment(name)
  local map=self:bodyMap();local bone=map and map[name]
  if bone==nil or bone<0 then return nil,"PKX body-map slot unavailable" end
  local out,err=self:attachmentIndex(bone)
  if out then out.name=name end
  return out,err
end

function Actor:build() return true end

-- Morph-weight uniform names. Building these with ("w"..i) meant thirteen
-- string concatenations (and thirteen interning lookups) per actor per frame,
-- for names that never change.
local W_UNIFORM={}
for i=0,12 do W_UNIFORM[i]="w"..i end
-- Reused scratch for the two per-group vector uniforms. love:send copies the
-- values immediately, so a single table is safe and removes two allocations
-- per material group per actor per frame.
local MATERIAL_RGBA={1,1,1,1}
local TINT_WHITE={1,1,1,1}

-- Was a closure defined inside Actor:draw, i.e. allocated every frame.
local function setBaseWeights()
  shader:send(W_UNIFORM[0],1)
  for i=1,12 do shader:send(W_UNIFORM[i],0) end
end

function Actor:draw(matrix)
  local sc=self.scene
  if not (sc and shader) then return false end
  local w=self:frameWeights()
  love.graphics.setShader(shader)
  shader:send("model","row",matrix)
  for i=0,12 do shader:send(W_UNIFORM[i],w[i+1]) end
  local hitU=self.hitAge and clamp(self.hitAge/self:stateDuration("hit"),0,1) or 1
  local spawn=clamp(self.spawnScale==nil and 1 or self.spawnScale,0,1)
  local spawnFlash=(spawn<1 and not self.recallAge and not self.faintAge) and (1-spawn)*0.68 or 0
  local hitFlash=self.hitAge and (1-hitU)*0.72*clamp(tonumber(self.hitStrength) or 1,0.65,1.45) or 0
  shader:send("hitFlash",hitFlash)
  shader:send("spawnFlash",spawnFlash)
  shader:send("shinyEnabled",self.shinyFilter and 1 or 0)
  local rows=self.shinyRows or (Shiny and Shiny.identityRows) or {{1,0,0,0},{0,1,0,0},{0,0,1,0}}
  shader:send("shinyRouteR",rows[1]);shader:send("shinyRouteG",rows[2]);shader:send("shinyRouteB",rows[3])
  shader:send("shinyGain",self.shinyGain or (Shiny and Shiny.identityGain) or {1,1,1})

  local opacity=self.opacity or 1
  if spawn<1 and not self.recallAge and not self.faintAge then
    opacity=opacity*(0.34+spawn*0.66)
  end
  if self.recallAge then
    local u=self.recallScale~=nil and (1-clamp(self.recallScale,0,1))
      or clamp(self.recallAge/RECALL_DURATION,0,1)
    opacity=opacity*(1-u)
  elseif self.faintAge and not self.cbeSourceFaintReturn then
    local clip=self:stateDuration("faint")
    if self.nativeSlotSampled then
      -- Preserve the complete authored faint clip. 1.5.29 began fading the
      -- model at 62% of the native animation, which visually amputated the
      -- death performance before Colosseum's source pose had finished. Only
      -- after the final authored frame do we run CBE's short removal tail.
      local tail=clamp((self.faintAge-clip)/FAINT_REMOVAL_TAIL,0,1)
      opacity=opacity*(1-tail)
    else
      local u=clamp(self.faintAge/clip,0,1)
      if u>0.72 then opacity=opacity*(1-(u-0.72)/0.28) end
    end
  end
  shader:send("opacity",clamp(opacity,0,1))
  -- Spawn uses a brief white materialization flash through spawnFlash above.
  -- This is intentionally a generic lifecycle cue, not mislabeled as a
  -- Colosseum move/GPT1 effect.
  shader:send("tintColor",TINT_WHITE)
  shader:send("releaseFlash",math.max(0,math.min(1,self.releaseFlash or 0)))
  love.graphics.setColor(1,1,1,1)
  -- F5 isolates one group at a time so a stray shape can be identified by
  -- sight instead of guessed at from vertex counts alone.
  local only=A.isolateGroup
  local playback=self:playbackBank()
  local drawGroups=(not self.forceBasePlayback and playback and playback.groups) or sc.groups
  if self.forceBasePlayback then setBaseWeights() end
  local drawFault=false
  for i,grp in ipairs(drawGroups) do
    if not only or only==i then
      -- Preserve the source HSD material state per render group. 1.5.24 threw
      -- this away after extraction, so every untextured material rendered as
      -- opaque white and every alpha-controlled helper surface became solid.
      local d=grp.diffuse
      MATERIAL_RGBA[1]=(d and d[1]) or 1;MATERIAL_RGBA[2]=(d and d[2]) or 1
      MATERIAL_RGBA[3]=(d and d[3]) or 1;MATERIAL_RGBA[4]=grp.alpha or 1
      shader:send("materialColor",MATERIAL_RGBA)
      shader:send("useTexture",grp.textured and 1 or 0)
      shader:send("textureCoordMode",tonumber(grp.textureCoordMode) or 0)
      shader:send("reflectionTexMtx","row",grp.reflectionTexMtx or IDENTITY_MAT)
      if love.graphics.setDepthMode then
        love.graphics.setDepthMode("lequal",not (grp.noz or grp.xlu))
      end
      local okDraw=grp.mesh and pcall(love.graphics.draw,grp.mesh)
      if not okDraw then drawFault=true;break end
    end
  end
  -- A source action GPU bank is optional presentation data. If one group is
  -- malformed on a particular backend, draw the always-resident base body in
  -- the SAME frame. Never convert a damage-animation fault into invisibility.
  if drawFault and drawGroups~=sc.groups then
    setBaseWeights()
    for i,grp in ipairs(sc.groups) do
      if not only or only==i then
        local d=grp.diffuse
        MATERIAL_RGBA[1]=(d and d[1]) or 1;MATERIAL_RGBA[2]=(d and d[2]) or 1
        MATERIAL_RGBA[3]=(d and d[3]) or 1;MATERIAL_RGBA[4]=grp.alpha or 1
        shader:send("materialColor",MATERIAL_RGBA)
        shader:send("useTexture",grp.textured and 1 or 0)
        shader:send("textureCoordMode",tonumber(grp.textureCoordMode) or 0)
        shader:send("reflectionTexMtx","row",grp.reflectionTexMtx or IDENTITY_MAT)
        if love.graphics.setDepthMode then love.graphics.setDepthMode("lequal",not (grp.noz or grp.xlu)) end
        if grp.mesh then pcall(love.graphics.draw,grp.mesh) end
      end
    end
    perf.actionDrawFallbacks=(perf.actionDrawFallbacks or 0)+1
  end
  if love.graphics.setDepthMode then love.graphics.setDepthMode("lequal",true) end
  love.graphics.setShader()
  return true
end

function Actor:attack(moveId,moveDef,opts)
  if self.state=="faint" or self.state=="recall" or self.state=="removal" then return false end
  opts=type(opts)=="table" and opts or {}
  -- A later turn event is allowed to arrive while the target is still inside
  -- its source Damage clip. Queue it; never use an attack event as permission to
  -- cut the reaction short. This is the Colosseum ordering contract:
  -- Damage -> (Faint | Recall | Attack | Idle).
  if self.hitAge then
    self.pendingAttack={moveId=moveId,moveDef=moveDef,opts=opts}
    return true,"queued"
  end
  self.action="attack";self.actionAge=0;self:transition("attack")
  self.lastMove=moveId;self.lastMoveDef=moveDef
  local requested=opts.nativeSlot or moveSlot(moveDef)
  -- A decoded Waza root's sequenceKind is retail's explicit PKX row selector.
  -- It is not permission to substitute another member of the same broad
  -- physical/special family. If that exact row is absent/unreadable, withhold
  -- the source presentation rather than animating a plausible-looking wrong row.
  local strictNative=opts.sourceSequenceKind~=nil
  local sampled=self:selectNativeSlot(requested,strictNative)
  -- The selected PKX bank is part of the retail presentation chain. Older CBE
  -- builds deliberately discarded it whenever a Waza timeline was present,
  -- leaving the Pokemon in its idle bank while particles and camera advanced.
  -- Keep the source-authored action live; root/orientation containment remains
  -- in Actor:matrix and the action-bank validation path.
  self.sourceWazaPoseLock=false
  -- The Waza presentation is bound from this exact native-action start. If the
  -- move was queued behind a Damage reaction, the callback travels with that
  -- pending attack and fires only after Damage completes and the PKX bank begins.
  if type(opts.onStarted)=="function" then pcall(opts.onStarted,self,sampled==true,requested) end
  return true,sampled==true and "started" or "native-action-missing"
end
function Actor:hit(payload,opts)
  opts=type(opts)=="table" and opts or {}
  -- Damage is a reaction, never a visibility state. Keep the actor alive and
  -- let CurrentSpriteModels suppress the engine's stock blink for 3D providers.
  -- Once the authored faint/recall tail has started, a late duplicate damage
  -- event must not pull the actor back out of that terminal presentation.
  if self.state=="faint" or self.state=="recall" or self.state=="removal" then return false end
  local damage=type(payload)=="table" and tonumber(payload.damage) or nil
  local target=type(payload)=="table" and payload.target or nil
  local mon=target and target.mon
  local hp=tonumber(target and (target.hp or target.currentHP or target.currentHp))
    or tonumber(mon and (mon.hp or mon.currentHP or mon.currentHp))
  if hp and hp<=0 then self.pendingFaint=self.pendingFaint or "collapse" end
  -- Some hosts expose the same resolved hit through more than one presentation
  -- wrapper. If HP-after is available it is an authoritative de-duplication key:
  -- replaying the same HP result must not restart Damage at frame zero. Genuine
  -- multi-hit attacks change HP on every strike and therefore remain distinct.
  if hp~=nil then
    local sig=tostring(hp).."|"..tostring(damage or "?")
    local now=tonumber(self.clock) or 0
    self._recentHitSignatures=self._recentHitSignatures or {}
    local seenAt=tonumber(self._recentHitSignatures[sig])
    if seenAt and now-seenAt<0.20 then return true,"duplicate" end
    self._recentHitSignatures[sig]=now
  end

  -- Never snap an in-progress native reaction back to its first source frame.
  -- Queue a genuine next strike and play it after the current Damage clip. This
  -- gives multi-hit moves one complete authored reaction per impact and keeps a
  -- lethal final strike ordered ahead of Faint.
  if self.hitAge then
    self.pendingHits=self.pendingHits or {}
    if #self.pendingHits<5 then
      self.pendingHits[#self.pendingHits+1]={__cbeQueuedHit=true,payload=payload,opts=opts}
      return true,"queued"
    end
    return false,"queue-full"
  end

  return self:beginHit(payload,opts)
end
function Actor:beginHit(payload,opts)
  opts=type(opts)=="table" and opts or {}
  local damage=type(payload)=="table" and tonumber(payload.damage) or nil
  local target=type(payload)=="table" and payload.target or nil
  local mon=target and target.mon
  local maxHp=tonumber(target and (target.maxHP or target.maxHp))
    or tonumber(mon and mon.stats and mon.stats.hp)
    or tonumber(mon and mon.maxHP)
  local ratio=(damage and maxHp and maxHp>0) and damage/maxHp or 0.12
  local strength=0.82+clamp(ratio,0,0.65)*0.9
  if type(payload)=="table" and payload.crit then strength=strength+0.18 end
  if type(payload)=="table" and tonumber(payload.typeMult) and tonumber(payload.typeMult)>10 then
    strength=strength+0.12
  end
  self.hitStrength=clamp(strength,0.65,1.45)
  -- Damage is source-authoritative. Revision-27 extraction keeps the exact PKX
  -- Damage slot's root motion and authored body deformation; only impossible
  -- topology/collapse/explosion samples are rejected. Starting a reaction owns
  -- the model until that source duration completes.
  self.action=nil;self.actionAge=0
  self.hitAge=0
  self:transition("hit")
  local requested=opts.nativeSlot or "damage"
  self.sourceDamageSequenceKind=opts.sourceSequenceKind
  local sampled=self:selectNativeSlot(requested,opts.sourceSequenceKind~=nil)
  if not sampled then
    -- No validated source damage bank: keep the resident body and use the
    -- compact procedural recoil fallback. This is a per-species fail-open,
    -- never a visibility change.
    self.nativeSlot=nil;self.nativeClip=nil;self.nativeAction=nil
    self.nativeActionName=nil;self.nativeDuration=nil;self.nativeSlotSampled=false
    self.clipClock=0
  end
  if type(opts.onStarted)=="function" then pcall(opts.onStarted,self,sampled==true,requested) end
  return true,sampled==true and "started" or "native-action-missing"
end
function Actor:faint(disposition)
  if self.state=="faint" then return true end
  -- Do not let a lethal damage result skip the actual take-damage animation.
  -- Gen1/Gen2 can publish the faint semantic as soon as HP reaches zero while
  -- the visible damage beat is still in progress. Remember the KO and begin it
  -- immediately after the hurt bank completes.
  if self.hitAge then
    self.pendingFaint=disposition or "collapse"
    return true
  end
  self.pendingFaint=nil
  self.pendingHits=nil
  self.pendingAttack=nil;self.pendingRecall=nil
  self.action=nil;self.actionAge=0
  self.hitAge=nil
  self.recallAge=nil
  self.faintAge=0
  self.faintKind=disposition or "collapse"
  self:transition("faint")
  self:selectNativeSlot("faint")
  return true
end
function Actor:recall(reason)
  if self.state=="faint" or self.state=="removal" then return false end
  if self.hitAge then
    self.pendingRecall=reason or "switch"
    return true
  end
  self.action=nil;self.actionAge=0
  self.hitAge=nil
  self.faintAge=nil
  self.pendingFaint=nil;self.pendingHits=nil;self.pendingAttack=nil;self.pendingRecall=nil
  self.recallAge=0
  self.recallScale=nil
  self.recallReason=reason or "switch"
  self:selectNativeSlot("idle")
  self:transition("recall")
  return true
end
function Actor:setRecallScale(scale)
  if self.state~="recall" then return false end
  if type(scale)=="number" then self.recallScale=clamp(scale,0,1) end
  return true
end
function Actor:terminalComplete()
  if self.state=="faint" then
    return (tonumber(self.faintAge) or 0)>=self:terminalDuration("faint")
  end
  if self.state=="recall" then
    if self.recallScale~=nil and self.recallScale<=0 and (tonumber(self.recallAge) or 0)>0.05 then
      return true
    end
    return (tonumber(self.recallAge) or 0)>=RECALL_DURATION
  end
  return self.state=="removal"
end
function Actor:remove(reason)
  self.removeReason=reason or "removed"
  self:transition("removal")
end
function Actor:release()
  -- Meshes are shared per species through `scenes`, so an actor holds no GPU
  -- resource of its own. Releasing must not free the shared scene.
  self.scene=nil
end

-- ------------------------------------------------------------- service ----

-- Height the model is scaled to, expressed in the ACTOR VP's units.
--
-- This is not the same space the trainer path works in, which is what made 6.9
-- wrong. Our service declares worldUnits=false, so drawStadiumActors hands us
-- services.vp rather than services.stageVP, and CurrentSpriteModels states the
-- difference plainly at its targetGeometry helper: "The arena's actor VP
-- includes figureScale" -- roughly 0.38. A 6.9-unit model therefore rendered at
-- about 2.6 effective units while trainers render near 6.4, so every Pokemon
-- came out ~2.4x undersized and read as a fragment rather than a small model.
--
-- The extractor normalizes every species to a height of 16, so a value near 16
-- is very close to 1:1 with the cache and lands in the trainers' size band once
-- figureScale is applied. Tune live with F7/F8; the overlay shows the result.
-- A 1.70 m Pokemon should occupy the same final stage height as a human
-- trainer. Trainers are authored at about 6.9 stage units, while portable
-- actors are drawn through the arena's figureScale VP. 18.16 is the fallback
-- actor-space reference for the default .38 figure scale; acquire() derives the
-- exact reference from the active arena so custom arenas stay calibrated too.
local HUMAN_WORLD_HEIGHT=6.90
local DEFAULT_FIGURE_SCALE=.38
local WORLD_HEIGHT=HUMAN_WORLD_HEIGHT/DEFAULT_FIGURE_SCALE
local HUMAN_REFERENCE_METERS=1.70
-- Physical scale remains the baseline, but battle readability gets a floor. A
-- literal 0.20-0.30 m model can be physically accurate and still be nearly
-- impossible to read at a handheld/1080p battle camera. The floor is a
-- presentation exception only; battle data and PokÃƒÂ©dex height stay untouched.
local MIN_READABLE_RELATIVE=.29
-- Raw PokÃƒÂ©dex height is NOT a literal standing-height multiplier. It mixes
-- height, body length and extreme fantasy proportions (Ekans is the clearest
-- example: 6'7" describes its long body, not a six-foot-tall battle stance).
-- Every species therefore passes through the same soft allometric curve before
-- body-type compensation. Small Pokemon are lifted for readability; giants are
-- compressed progressively instead of linearly taking over the stadium.
local SCALE_CURVE_EXP=.72
local MAX_READABLE_RELATIVE=1.58
-- Species whose canonical measurement is several times human scale should still
-- read as giants after allometric compression. The older hard 1.58 ceiling made
-- tall/coiled Hoenn giants (notably Rayquaza) visually ordinary. This is a
-- physical-size class, not a species override.
-- Width/depth matters as much as height in a battle camera. A normalized body can
-- be only 16 units tall yet four or five body-heights wide (Kyogre is the clearest
-- current source example). The numeric thresholds live inside the policy function
-- below to avoid spending more of LuaJIT's already-tight top-level local budget.
local TINY_SPECIES_FLOOR={
  [10]=.32, -- Caterpie
  [13]=.34, -- Weedle: long/thin silhouette needs a slightly stronger floor
  [50]=.32, -- Diglett
  [19]=.31, -- Rattata
  [21]=.31, -- Spearow
}
-- Long/coiled silhouettes consume substantially more screen area than their
-- standing height suggests, so a few extreme bodies use a slightly tighter
-- visual ceiling while still reading as clearly larger than a human trainer.
local LARGE_SPECIES_CEILING={
  [95]=1.38,  -- Onix
  [130]=1.34, -- Gyarados
  [131]=1.48, -- Lapras
  [143]=1.42, -- Snorlax
  [149]=1.46, -- Dragonite
  [208]=1.42, -- Steelix
  [249]=1.50, -- Lugia
  [250]=1.50, -- Ho-Oh
}

-- Species whose canonical PokÃƒÂ©dex "height" is visually much closer to body
-- LENGTH than standing height. The global curve still applies first; these
-- factors convert the published measurement into the compact/coiled battle
-- silhouette actually authored in Colosseum. This is not an Ekans-only hack:
-- the complete Gen-I/II elongated-body family is handled by the same rule.
local LENGTH_MEASURED_FACTOR={
  [23]=.50,  -- Ekans
  [24]=.54,  -- Arbok
  [95]=.42,  -- Onix
  [130]=.47, -- Gyarados
  [148]=.52, -- Dragonair
  [162]=.62, -- Furret
  [206]=.60, -- Dunsparce
  [208]=.42, -- Steelix
}

local function normalizedPresentationRelative(meters,dex)
  local raw=meters and meters>0 and (meters/HUMAN_REFERENCE_METERS) or .72
  raw=math.max(.04,raw)
  local curved=raw^SCALE_CURVE_EXP
  local body=LENGTH_MEASURED_FACTOR[tonumber(dex)] or 1
  return curved*body,raw,curved,body
end
local scaleTrim=1.0

-- The extractor normalizes every source PKX body for stable cache precision,
-- but records whether sparse HSD outlier vertices inflated that body box. The
-- battle renderer used to ignore that diagnostic, so a single bad envelope
-- vertex could make the complete visible Pokemon look comically tiny. Recover a
-- bounded amount of the trimmed core height without changing source vertices or
-- requiring a recache.
--
-- Source bounds also give a conservative clue for Pokemon whose Pokedex height
-- is really a long body measurement. Only extremely elongated silhouettes are
-- adjusted, and species already covered by the reviewed length-family mapping
-- above are not reduced twice. This gives Gen-III long-bodied models a systemic
-- correction without growing another per-species exception table.
local function geometryPresentation(scene,bodyFactor)
  local b=scene and scene.bounds
  local mn,mx=b and b.min,b and b.max
  if not (mn and mx) then return 1,1,1 end
  local h=math.max(.001,(tonumber(mx[2]) or 0)-(tonumber(mn[2]) or 0))
  local dx=math.max(0,(tonumber(mx[1]) or 0)-(tonumber(mn[1]) or 0))
  local dz=math.max(0,(tonumber(mx[3]) or 0)-(tonumber(mn[3]) or 0))
  local hr=tonumber(scene.heightRatio) or 1
  -- PokemonExtractor labels >1.6 raw/trimmed height as scattered geometry.
  -- Stay neutral below that threshold so legitimate ears/wings/tails remain
  -- part of the authored silhouette.
  local coreCorrection=(hr>1.6) and math.min(math.max(hr,1),1.75) or 1
  local coreH=h/coreCorrection
  local aspect=math.max(dx,dz)/math.max(.001,coreH)
  local stance=1
  if (tonumber(bodyFactor) or 1)>=.995 and aspect>2.35 then
    stance=math.max(.70,math.min(1,math.sqrt(2.35/aspect)))
  end
  return coreCorrection,stance,aspect
end

function A.presentationScalePolicy(meters,dex,scene)
  local normalized,raw,curve,body=normalizedPresentationRelative(meters,dex)
  local floor=TINY_SPECIES_FLOOR[dex] or MIN_READABLE_RELATIVE
  local explicitCeiling=LARGE_SPECIES_CEILING[dex]
  local ceiling=explicitCeiling or ((raw>=3.00) and 1.95 or MAX_READABLE_RELATIVE)
  local relative=math.min(math.max(normalized,floor),ceiling)
  local coreCorrection,stance,aspect=geometryPresentation(scene,body)
  relative=math.max(floor,relative*stance)
  local footprint=math.max(0,tonumber(aspect) or 0)*relative
  local footprintCompression=1
  if footprint>3.45 and aspect>0 then
    local bounded=3.45/aspect
    bounded=math.max(floor,math.min(relative,bounded))
    footprintCompression=relative/math.max(.0001,bounded)
    relative=bounded
    footprint=aspect*relative
  end
  return {
    relative=relative,raw=raw,curve=curve,body=body,floor=floor,ceiling=ceiling,
    coreCorrection=coreCorrection,stance=stance,aspect=aspect,
    footprint=footprint,footprintCompression=footprintCompression,
  }
end

local function actorWorldScale(actor)
  local h=tonumber(actor and actor.height) or 0
  local reference=tonumber(actor and actor.referenceActorHeight) or WORLD_HEIGHT
  local relative=tonumber(actor and actor.physicalScale) or .72
  local target=reference*relative*scaleTrim
  local coreCorrection=math.max(1,tonumber(actor and actor.geometryCoreCorrection) or 1)
  local effectiveH=h/coreCorrection
  return (effectiveH>0.01) and (target/effectiveH) or (relative*scaleTrim)
end

local function encodedFeetInchesMeters(raw)
  raw=tonumber(raw)
  if not raw or raw<=0 then return nil end
  local ft=math.floor(raw/100);local inch=raw%100
  -- Native Gen-II records store printed inches and never exceed 11. Reject a
  -- corrupt/foreign field instead of turning it into an enormous actor.
  if inch<0 or inch>11 then return nil end
  return (ft*12+inch)*0.0254
end

-- National-Dex height fallback for the Hoenn species Colosseum can render but
-- Gen1Recomp does not natively describe. Values are canonical Pokedex heights in
-- decimetres, ordered 252..386. Native host dex metadata always wins above this
-- table; this only prevents the entire Gen-III roster from collapsing onto the
-- old generic .72 actor scale when a rental/import species has no host dexEntry.
-- Long-body Pokedex measurements are subsequently tempered by the extracted PKX
-- silhouette in geometryPresentation(), so Wailord/Milotic/Rayquaza do not turn
-- a length measurement into an absurd standing height.
local GEN3_HEIGHT_DM={
  5,9,17,4,9,19,4,7,15,5,10,4,5,3,6,10,7,12,5,12,15,5,10,13,3,7,6,12,4,8,16,5,8,4,
  12,8,14,20,5,8,8,6,10,15,10,23,2,10,6,11,5,6,4,9,21,6,13,6,15,4,4,7,6,3,4,17,8,18,
  20,145,7,19,5,7,9,11,7,11,20,4,13,4,11,13,27,10,12,4,9,6,11,5,15,10,15,7,15,6,62,3,
  10,6,11,8,16,20,6,12,6,7,15,8,11,14,4,17,18,10,6,6,11,15,6,12,16,17,18,19,14,20,45,35,70,3,17,
}

local function dexHeightMeters(opts,dex)
  local ctx=opts and opts.context
  local game=(ctx and ctx.game) or (ctx and ctx.battle and ctx.battle.game)
  local battler=opts and opts.battler
  local mon=battler and (battler.mon or battler)
  local species=mon and mon.species
  local data=game and game.data
  local def=data and data.pokemon and species and data.pokemon[species]
  local e=def and def.dexEntry
  if e then
    if tonumber(e.heightM) and tonumber(e.heightM)>0 then return tonumber(e.heightM) end
    local ft,inch=tonumber(e.heightFt),tonumber(e.heightIn)
    if ft then return (ft*12+(inch or 0))*0.0254 end
    -- Gold compatibility facades expose the native four printed digits here
    -- (0204 == 2'04"). The scaler previously ignored this exact source value and
    -- silently assigned the generic .72 size to otherwise unrelated species.
    local gen2=encodedFeetInchesMeters(e.gen2Height)
    if gen2 then return gen2 end
  end
  -- Gold/Silver extraction stores the source Pokedex height as the digits the
  -- cart prints (e.g. 204 == 2'04"). Convert that authoritative field here.
  local g2=data and data.gen2Pokedex and data.gen2Pokedex.entries
  local raw=g2 and species and g2[species] and tonumber(g2[species].height)
  local gen2=encodedFeetInchesMeters(raw)
  if gen2 then return gen2 end
  dex=tonumber(dex)
  if dex and dex>=252 and dex<=386 then
    local dm=GEN3_HEIGHT_DM[dex-251]
    if dm and dm>0 then return dm*.1 end
  end
  return nil
end         -- runtime multiplier, adjusted with F7/F8

function A.available(source,dex)
  dex=tonumber(dex)
  if not (dex and Dex.supported(dex)) then return false end
  if scenes[dex] then return true end
  if speciesCacheReady(dex) then return true end
  -- Not yet extracted. Report available only if we can still reach the source
  -- disc to build it on demand; otherwise decline cleanly so the 2D seam runs.
  return discOpener~=nil
end

function A.acquire(source,dex,variant,opts)
  perf.actorAcquires=perf.actorAcquires+1
  variant=(variant==nil and opts and monVariant(opts.battler)) or variant or "normal"
  local cacheKey=modelKey(dex,variant)
  dex=dexNumber(dex)
  if not (dex and Dex.supported(dex)) then return nil,"unsupported dex" end
  local services=opts and opts.context and opts.context.services
  local informationRequest=services and services.informationSurface==true
  local allowLegacyMaterialBody=opts and opts.allowLegacyMaterialBody==true

  -- A resident GPU scene has already passed the extractor stamp check for this
  -- session. Re-reading rev.txt/cache metadata on every Summary reopen or actor
  -- reacquire was pure filesystem churn, especially noticeable on Gen-I menu
  -- transitions. Debug rebuild toggles explicitly clear scenes[cacheKey], so this
  -- fast path cannot hide an intentional re-extraction.
  local resident=scenes[cacheKey]
  if resident then perf.residentAcquireHits=perf.residentAcquireHits+1 end

  -- Storage-profile caches intentionally contain base + idle only.  On mobile we
  -- may still use an ALREADY-RESIDENT storage body as the visible battle actor
  -- while the cooperative worker prepares that battler's exact action subset.
  -- This is not a generic/model substitution: it is the exact GC6E01 species
  -- body and idle bank that Full Cache already put on disk.  Attacks/reactions
  -- remain source-gated until their required action signature is ready.
  local allowStorageBattleBody=opts and opts.allowStorageBattleBody==true
  if not informationRequest and speciesCacheReady(cacheKey,allowLegacyMaterialBody) then
    local _,complete=cachedActionProfile(cacheKey)
    if not complete and not allowStorageBattleBody then
      if opts and opts.noSource==true then return nil,"storage-only model needs battle action upgrade" end
      local game=opts and opts.context and opts.context.game
      local selectiveReady=opts and opts.selectiveActionsReady==true
      if not selectiveReady and opts and opts.battler then
        selectiveReady=A._requiredSignatureReady(cacheKey,A._requiredModelSignature(game,opts.battler))
      end
      if MOBILE_RUNTIME and services and services.cbeStandalone==true and services.prewarm~=true and not selectiveReady then
        return nil,"mobile battle model pending storage-action upgrade"
      end
      if not selectiveReady and not (opts and opts.battler) then
        return nil,"storage-only model requires a concrete battler action plan"
      end
      local upgraded,why=true,nil
      if not selectiveReady then
        upgraded,why=ensureRequiredActionInventory(dex,variant,game,opts and opts.battler,opts and opts.progress)
      end
      if not upgraded then return nil,why end
      resident=scenes[cacheKey]
    end
  end

  -- isCached now also rejects a cache written by a DIFFERENT extractor
  -- revision, so an improved extractor rebuilds species that an older one had
  -- already cached. Drop any GPU scene we built from the stale cache too,
  -- otherwise the old meshes stay resident for the rest of the session.
  if not resident and not speciesCacheReady(cacheKey,allowLegacyMaterialBody) then
    -- Cache-only means no source work on ANY host (including delegated arena
    -- contexts without cbeStandalone). The mobile worker owns that boundary.
    if opts and opts.noSource==true then
      return nil,"model not cached; pending cooperative preparation"
    end
    -- Mobile live battle draw is a render path, not a source-build boundary.
    -- If this identity is genuinely cold, leave it for pumpBattlePrewarm() rather
    -- than opening/extracting the Colosseum source synchronously behind a black
    -- transition or during a switch animation. Information/cache screens and
    -- explicit preparation jobs keep their existing source-backed behavior.
    if MOBILE_RUNTIME and services and services.cbeStandalone==true
        and services.prewarm~=true and services.informationSurface~=true then
      return nil,"mobile battle model pending cooperative preparation"
    end
    if scenes[cacheKey] then scenes[cacheKey]=nil;sceneErrors[cacheKey]=nil end
    local failure=pendingExtract[cacheKey]
    if failure and retryClock()<failure.retryAt then return nil,failure.reason end
    pendingExtract[cacheKey]=nil
    if sourceBusy then return nil,"source extraction in progress" end
    if not discOpener then return nil,"source disc unavailable for on-demand extraction" end
    local okDisc,disc=pcall(discOpener)
    if not okDisc or not disc then
      extractionFailed(cacheKey,"source disc could not be opened: "..tostring(disc))
      return nil,pendingExtract[cacheKey].reason
    end
    -- extractSpecies returns (result) on success and (nil,message) on failure,
    -- so pcall gives us three values. Keep the message: a species that cannot
    -- be built should say why in the log, not just vanish into the 2D fallback.
    local ok,result,extractErr=pcall(extractSource,mod,disc,dex,
      {variant=variant,targetHeight=16.0,decodeMode=A.decodeMode,skinFix=A.skinFix,renderPassFilter=true,progress=opts and opts.progress,checkpoint=opts and opts.progress})
    if not ok then
      extractionFailed(cacheKey,result)
      log("error","extraction raised for dex %s: %s",dex,tostring(result))
      return nil,tostring(result)
    end
    if not result then
      extractionFailed(cacheKey,extractErr)
      log("warn","extraction declined dex %s: %s",dex,tostring(extractErr))
      return nil,tostring(extractErr or "extraction failed")
    end
  end

  local scene,serr=resident,nil
  if not scene then scene,serr=loadScene(cacheKey,false,opts and opts.progress) end
  if not scene then return nil,serr end
  sceneUseSerial=sceneUseSerial+1;scene.__cbeLastUse=sceneUseSerial

  local actor=Actor.new(dex,variant,scene,opts)
  actor.cacheKey=cacheKey
  actor.legacyMaterialBody=allowLegacyMaterialBody and not materialTexgenReady(cacheKey) or false
  local metadataKey=tostring(cacheKey)
  local informationSurface=actor.informationSurface==true
  local metadata=sourceMetadata[metadataKey]
  if metadata==nil then
    -- Runtime metadata is tiny but older builds re-opened the 1.46 GB import,
    -- parsed the species FSYS and inflated the PKX wrapper on the first actor
    -- acquisition of EVERY app session. Persist the body-map/slot subset next
    -- to the model cache so a generated visual cache is actually self-serving.
    local cached=select(1,readLua(metadataCachePath(cacheKey)))
    if type(cached)=="table" and tonumber(cached.revision) and tonumber(cached.revision)>=1 then metadata=cached end
  end
  -- Normal information surfaces only need the generated visual/cache payload.
  -- Shiny viewers may migrate an older metadata sidecar once, through the
  -- cooperative preparation job, to recover its native source colour recipe. That source scan was the main reason a
  -- cold-but-generated model could appear one or two seconds after selecting it.
  -- If a tiny persisted metadata sidecar exists we still consume it; otherwise
  -- leave the global key unresolved so a later real battle actor can perform the
  -- authoritative source metadata read when it actually needs move timing.
  local needsFilter=variant=="shiny" and not Dex.rare[dex]
  local needsScaleSelector=not informationSurface and type(metadata)=="table"
    and metadata.scaleSelector==nil and metadata.sequenceKind==nil
  -- Revision 6 adds the exact GC6E01 FOV timing row only.  Older generated
  -- model/mesh caches remain valid; a battle actor refreshes just this tiny PKX
  -- metadata sidecar once instead of forcing species geometry re-extraction.
  local needsCameraTiming=not informationSurface and type(metadata)=="table"
    and ((tonumber(metadata.revision) or 0)<6)
  if not (opts and opts.noSource==true)
      and ((metadata==nil and not informationSurface) or needsScaleSelector
        or needsCameraTiming
        or (needsFilter and not validFilter(metadata and metadata.shinyFilter)))
      and metadataReader and discOpener then
    local okDisc,disc=pcall(discOpener)
    if okDisc and disc then
      local okMeta,value,metaErr=pcall(metadataReader.inspectSpecies,disc,dex,type(cacheKey)=="string" and "shiny" or "normal",nil,{progress=opts and opts.progress})
      if okMeta and value then metadata=value;pcall(writeMetadataCache,cacheKey,value)
      else log("warn","PKX metadata unavailable for dex %s: %s",dex,tostring(okMeta and metaErr or value)) end
    end
  end
  if metadata~=nil then
    sourceMetadata[metadataKey]=metadata or false
  elseif not informationSurface and not (opts and opts.noSource==true) then
    -- A resident-only presentation attempt did not inspect the source. Do not
    -- poison the later worker's metadata lookup with a negative cache entry.
    sourceMetadata[metadataKey]=false
  end
  if metadata==false then metadata=nil end
  if needsFilter then
    if not validFilter(metadata and metadata.shinyFilter) then
      actor:release()
      return nil,"source shiny parameters unavailable (normal model not substituted)"
    end
    actor.shinyFilter=metadata.shinyFilter
    actor.shinyRows,actor.shinyGain=Shiny.uniforms(actor.shinyFilter)
  end
  actor.sourceMetadata=metadata
  actor:selectNativeSlot("idle")
  A._liveActors=A._liveActors or setmetatable({},{__mode="v"})
  A._liveActors[#A._liveActors+1]=actor
  -- Preserve species-relative physical scale. Previous builds normalized every
  -- Pokemon to effectively the same battle height, turning Weedle into a kaiju
  -- while making large Pokemon such as Arcanine read too small beside trainers.
  -- The cache remains normalized for numerical stability; runtime scale restores
  -- the Pokedex height relative to a ~1.70 m trainer. Extreme giant species are
  -- softly capped only to keep the arena/camera numerically usable.
  local h=actor.height
  local meters=dexHeightMeters(opts,dex)
  local scalePolicy=A.presentationScalePolicy(meters,dex,scene)
  local rawRelative,curveRelative,bodyFactor=scalePolicy.raw,scalePolicy.curve,scalePolicy.body
  local floor,ceiling=scalePolicy.floor,scalePolicy.ceiling
  local relative=scalePolicy.relative
  local coreCorrection,stanceFactor,modelAspect=scalePolicy.coreCorrection,scalePolicy.stance,scalePolicy.aspect
  local ctx=opts and opts.context
  local figureScale=tonumber(ctx and ctx.arena and ctx.arena.figureScale) or DEFAULT_FIGURE_SCALE
  figureScale=math.max(.08,figureScale)
  actor.physicalHeightMeters=meters
  actor.sourcePhysicalScale=rawRelative
  actor.allometricScale=curveRelative
  actor.bodyLengthFactor=bodyFactor
  actor.geometryCoreCorrection=coreCorrection
  actor.geometryStanceFactor=stanceFactor
  actor.geometryAspect=modelAspect
  actor.physicalScale=relative
  actor.presentationScaleFloor=floor
  actor.presentationScaleCeiling=ceiling
  actor.presentationFootprint=scalePolicy.footprint
  actor.footprintCompression=scalePolicy.footprintCompression
  actor.readabilityBoost=(rawRelative>0) and (relative/rawRelative) or 1
  actor.largeBodyCompression=(relative>0 and rawRelative>relative) and (rawRelative/relative) or 1
  actor.referenceActorHeight=HUMAN_WORLD_HEIGHT/figureScale
  actor.worldScale=actorWorldScale(actor)
  -- Species without a source `rare_` model get the runtime recolour instead.
  -- Separate-source shinies already contain their authored palette. Never recolour twice.
  return actor
end

-- CBE draws into the caller's active target. We do not clear, do not touch the
-- canvas, and restore every render state we change -- the contract every
-- battleActors provider is held to.
function A.withRenderer(vp,callback,opts)
  local sh,err=ensureShader()
  if not sh then return false,err end
  local g=love.graphics
  local okPush,pushErr=pcall(g.push,"all")
  if not okPush then return false,pushErr end
  local ok,result=pcall(function()
    g.setDepthMode("lequal",true)
    g.setBlendMode("alpha","alphamultiply")
    if g.setMeshCullMode then g.setMeshCullMode("none") end
    sh:send("vp","row",vp)
    local eye=(opts and opts.eye) or {54,24,13}
    local focus=(opts and opts.focus) or {0,5,0}
    sh:send("cameraEye",eye)
    sh:send("reflectionView","row",(Mat4 and Mat4.lookAt and Mat4.lookAt(eye,focus,(opts and opts.up) or {0,1,0})) or IDENTITY_MAT)
    sh:send("textureCoordMode",0)
    sh:send("reflectionTexMtx","row",IDENTITY_MAT)
    return callback()
  end)
  pcall(g.setShader)
  pcall(g.setDepthMode)
  pcall(g.pop)
  A.drewThisFrame=true
  if not ok then return false,result end
  return result
end

-- ---------------------------------------------------------------- debug ----
--
-- Diagnostics that live in the generated cache are only useful if they can be
-- read, and that cache sits in an application data folder that is genuinely
-- hard to find. This draws the same facts over the battle instead, so a
-- screenshot carries everything needed to diagnose a bad model.
--
-- Toggle with F9. Costs nothing while off.

A.debug=false
A.drewThisFrame=false
-- "auto" applies the duplicate-root rejection. The forced modes exist so the
-- correct decode can be identified in one battle instead of one release: if
-- auto still looks wrong, F10 switches strategy and re-extracts on the spot.
A.decodeMode="auto"
local DECODE_MODES={"auto","single","scene"}
-- Native HSD envelope placement. F6 keeps a legacy comparison path available,
-- but the default now uses each deformer joint's stored inverse-bind matrix and
-- the mesh owner's HSD envelope coordinate system. This matters even when every
-- envelope is 100% single-bone -- exactly the case reported by the broken test
-- species in 1.5.20.
A.skinFix=true
-- Source visibility filter. F4 toggles native JOBJ OPA/XLU/TEXEDGE pass
-- membership. Earlier builds decoded zero-pass helper/proxy geometry as visible
-- white meshes and then tried to remove it with a spatial heuristic.
A.renderPassFilter=true
A._sourceVisibilitySafetyLock=true
A._lastF4Notice=nil
-- Show one render group at a time (F5), cycling through every group present
-- on any currently-live actor, then back to "all". Pure render-time filter --
-- no re-extraction, so it is free to step through and answers "which of these
-- shapes is the stray one" by looking rather than by reasoning about vertex
-- counts and hoping.
A.isolateGroup=nil
local debugKeyHeld=false
local csm=nil   -- CurrentSpriteModels, injected by install()

-- A.rebuildSpecies() only drops the cache -- it does not touch any Actor
-- already on the field, which keeps its own captured `scene` reference from
-- whenever it was last sent out. Without this, F6/F10 only affect the NEXT
-- send-out: the Pokemon currently in battle keeps rendering its pre-toggle
-- geometry, the overlay's per-species block reads the now-empty scene cache
-- and says "no species loaded yet", and it looks exactly like the toggle did
-- nothing when it simply was never exercised on what's on screen. Re-extract
-- and re-load every currently-live actor's species immediately so a toggle is
-- visible on the very next frame, not after a manual withdraw-and-resend.
local function refreshLiveActors()
  if not (extractor and discOpener) then return 0 end
  local dexes,seen={},{}
  for _,rec in pairs(A._liveActors or {}) do
    local key=rec and (rec.cacheKey or rec.dex)
    if key and not seen[key] then seen[key]=true;dexes[#dexes+1]=key end
  end
  for _,dex in ipairs(dexes) do
    -- Do not rely on the caller having cleared the in-memory scene cache
    -- first (A.rebuildSpecies() normally does, but this must be correct on
    -- its own): loadScene() below returns whatever is already cached in
    -- `scenes[dex]` before it looks at the freshly rewritten cache file, so a
    -- stale in-memory hit would silently make this whole refresh a no-op.
    scenes[dex]=nil;sceneErrors[dex]=nil
    local okDisc,disc=pcall(discOpener)
    if okDisc and disc then
      pcall(extractSource,mod,disc,dex,
        {targetHeight=16.0,decodeMode=A.decodeMode,skinFix=A.skinFix,renderPassFilter=true})
    end
  end
  local refreshed=0
  for _,rec in pairs(A._liveActors or {}) do
    if rec and rec.dex then
      local scene=loadScene(rec.cacheKey or rec.dex)
      if scene then
        rec.scene=scene
        local h=(scene.bounds and scene.bounds.max and scene.bounds.min
          and (scene.bounds.max[2]-scene.bounds.min[2])) or rec.height
        rec.height=h
        rec.worldScale=actorWorldScale(rec)
        refreshed=refreshed+1
      end
    end
  end
  A._lastRefresh={dexes=#dexes,refreshed=refreshed}
  return refreshed
end

local trimDownHeld,trimUpHeld,modeKeyHeld,skinKeyHeld,isolateKeyHeld,rigidKeyHeld=false,false,false,false,false,false
local function pollDebugKey()
  if not (love and love.keyboard and love.keyboard.isDown) then return end
  local ok,down=pcall(love.keyboard.isDown,"f9")
  if not ok then return end
  if down and not debugKeyHeld then A.debug=not A.debug end
  debugKeyHeld=down and true or false

  -- Live scale tuning. Coordinate spaces here are easy to reason about wrongly
  -- and expensive to iterate on through a rebuild, so the value is adjustable
  -- in-battle and shown in the overlay: find the number that looks right and it
  -- can be baked in as the default.
  local okM,md=pcall(love.keyboard.isDown,"f10")
  if okM and md and not modeKeyHeld then
    local i=1
    for n,name in ipairs(DECODE_MODES) do if name==A.decodeMode then i=n end end
    A.decodeMode=DECODE_MODES[(i % #DECODE_MODES)+1]
    -- Diagnostic toggles are not cache-clear consent.  Older builds called the
    -- destructive rebuildSpecies() here and silently erased every saved PKX
    -- payload. Keep the acquired bytes and require the explicit rebuild export
    -- if a developer intentionally wants a destructive re-extraction.
    A._lastCacheRetentionNotice="F10 decode mode changed; saved Pokemon cache retained (explicit rebuild required to apply)"
  end
  modeKeyHeld=okM and md or false

  local okS,sk=pcall(love.keyboard.isDown,"f6")
  if okS and sk and not skinKeyHeld then
    A.skinFix=not A.skinFix
    A._lastCacheRetentionNotice="F6 skin mode changed; saved Pokemon cache retained (explicit rebuild required to apply)"
  end
  skinKeyHeld=okS and sk or false

  local okR,rk=pcall(love.keyboard.isDown,"f4")
  if okR and rk and not rigidKeyHeld then
    -- SAFETY LOCK: do not ever re-extract source zero-pass JOBJ geometry from
    -- a live battle keypress. Multiple real runtime tests have shown that the
    -- visibility-OFF path can terminate the host below Lua (pcall cannot catch
    -- a native/GPU crash). The production source-faithful filter therefore
    -- stays ON. F4 is retained only as a visible diagnostic acknowledgement so
    -- an old testing habit cannot kill the game.
    A.renderPassFilter=true
    A._lastF4Notice="BLOCKED: source-visibility filtering is safety-locked ON; no re-extract performed"
  end
  rigidKeyHeld=okR and rk or false

  local okI,ik=pcall(love.keyboard.isDown,"f5")
  if okI and ik and not isolateKeyHeld then
    local maxGroups=0
    for _,rec in pairs(A._liveActors or {}) do
      if rec and rec.scene and rec.scene.groups then maxGroups=math.max(maxGroups,#rec.scene.groups) end
    end
    if maxGroups>0 then
      if not A.isolateGroup then A.isolateGroup=1
      elseif A.isolateGroup>=maxGroups then A.isolateGroup=nil
      else A.isolateGroup=A.isolateGroup+1 end
    end
  end
  isolateKeyHeld=okI and ik or false

  local okD,dn=pcall(love.keyboard.isDown,"f7")
  local okU,up=pcall(love.keyboard.isDown,"f8")
  local changed=false
  if okD and dn and not trimDownHeld then scaleTrim=math.max(0.1,scaleTrim-0.1);changed=true end
  if okU and up and not trimUpHeld then scaleTrim=math.min(6.0,scaleTrim+0.1);changed=true end
  trimDownHeld=okD and dn or false
  trimUpHeld=okU and up or false
  if changed then
    -- Live actors cache worldScale at acquire time; drop them so the next frame
    -- rebuilds at the new trim. Scenes (the meshes) are untouched and shared.
    for _,rec in pairs(A._liveActors or {}) do
      if rec and rec.height and rec.height>0.01 then
        rec.worldScale=actorWorldScale(rec)
      end
    end
  end
end

local function debugLines()
  local modVer=(mod and mod.exports and mod.exports.version) or "?"
  local out={"CBE POKEMON ACTORS  [F9]   MOD VERSION: "..tostring(modVer)}

  -- ARBITRATION comes first. Everything below it is meaningless if this
  -- provider was never selected -- which is precisely the failure that went
  -- undiagnosed for four releases, because the 2D sprite fallback looks
  -- exactly like "the 3D models are broken".
  local mode,modeId,owner,err="?","?","?",nil
  if csm and type(csm.status)=="function" then
    local okS,st=pcall(csm.status)
    if okS and type(st)=="table" then
      mode=tostring(st.presentationMode)
      modeId=tostring(st.presentationId)
      owner=tostring(st.actorOwner or "-")
      err=st.stadiumError
    end
  end
  local selected=(mode=="stadium")
  out[#out+1]=("presentation mode: %s   id: %s"):format(mode,modeId)
  out[#out+1]=("actor owner: %s"):format(owner)
  out[#out+1]=selected and "SELECTED -- this provider is rendering"
    or "NOT SELECTED -- you are seeing 2D sprites, not these models"
  out[#out+1]=("renderer invoked this frame: %s"):format(A.drewThisFrame and "yes" or "no")
  if err then out[#out+1]=("actor error: %s"):format(tostring(err)) end
  out[#out+1]=("species supported %d | on-demand extraction: %s")
    :format(Dex.speciesCount,discOpener and "available" or "NO DISC ACCESS")
  out[#out+1]=("perf scenes %d load / %d hit | actions %d built (%d warm) | acquires %d (%d resident)")
    :format(perf.sceneLoads,perf.sceneHits,perf.actionBuilds,perf.actionPrewarms,perf.actorAcquires,perf.residentAcquireHits)
  out[#out+1]=("SCALE  height %.1f  trim %.2f  =%.1f units   [F7 smaller / F8 bigger]")
    :format(WORLD_HEIGHT,scaleTrim,WORLD_HEIGHT*scaleTrim)
  out[#out+1]=("DECODE MODE  %s   [F10 cycles diagnostics; cache retained]")
    :format(A.decodeMode:upper())
  out[#out+1]=("HSD ENVELOPE FIX  %s   [F6 toggles diagnostics; cache retained]")
    :format(A.skinFix and "ON" or "OFF (legacy CBE placement)")
  out[#out+1]="SOURCE VISIBILITY  ON   [F4 SAFETY-LOCKED: zero-pass source geometry is quarantined]"
  if A._lastF4Notice then out[#out+1]="F4: "..A._lastF4Notice end
  if A._lastCacheRetentionNotice then out[#out+1]=A._lastCacheRetentionNotice end
  if A._lastRefresh then
    out[#out+1]=("last F6/F10 refresh: %d/%d actor(s) currently on the field re-decoded")
      :format(A._lastRefresh.refreshed,A._lastRefresh.dexes)
  end
  out[#out+1]=("ISOLATE GROUP  %s   [F5 cycles through one group at a time -- no re-extract]")
    :format(A.isolateGroup and ("#"..A.isolateGroup) or "OFF (showing all)")
  local any=false
  for dex,sc in pairs(scenes) do
    any=true
    out[#out+1]=("dex %s  %s"):format(dex,tostring(sc.stem))
    out[#out+1]=("   verts %d   groups %d   via %s")
      :format(sc.vertexCount or 0,sc.groupCount or 0,tostring(sc.decodePath))
    -- Per-group counts (and texture presence) make a stray or duplicated mesh
    -- obvious at a glance, and pair with F5 to isolate the suspect visually.
    local parts={}
    for i,g in ipairs(sc.groups or {}) do
      local n=(g.mesh and g.mesh.getVertexCount) and g.mesh:getVertexCount() or 0
      parts[#parts+1]=("g%d=%d%s"):format(i,n,g.textured and "t" or "")
      if i>=8 then break end
    end
    if #parts>0 then out[#out+1]="   groups  "..table.concat(parts,"  ").."   (t = has a texture)" end
    if A.isolateGroup and sc.groups and sc.groups[A.isolateGroup] then
      local ig=sc.groups[A.isolateGroup]
      local d=ig.diffuse or {1,1,1}
      out[#out+1]=("   F5 g%d material  tex=%s slot=%d  diffuse=%.2f,%.2f,%.2f  alpha=%.3f  xlu=%s noz=%s flags=0x%08X%s%s")
        :format(A.isolateGroup,ig.textured and "YES" or "NO",ig.textureSlot or -1,
          d[1] or 1,d[2] or 1,d[3] or 1,ig.alpha or 1,
          ig.xlu and "Y" or "N",ig.noz and "Y" or "N",ig.renderFlags or 0,
          ig.shadow and " SHADOW" or "",ig.effect and " EFFECT" or "")
    end
    local ac,pending=0,0
    for _ in pairs(sc.actions or {}) do ac=ac+1 end
    for _ in pairs(sc.actionSpecs or {}) do pending=pending+1 end
    out[#out+1]=("   fallback clip %d/%d frames %d | PKX native banks %d resident / %d indexed")
      :format(sc.clip or 0,sc.clipCount or 0,sc.morphFrames or 0,ac,ac+pending)
    local b=sc.bounds
    if b and b.min and b.max then
      out[#out+1]=("   bounds  x %.2f..%.2f  y %.2f..%.2f  z %.2f..%.2f")
        :format(b.min[1] or 0,b.max[1] or 0,b.min[2] or 0,b.max[2] or 0,b.min[3] or 0,b.max[3] or 0)
    end
    -- >1.6 means a few stray vertices are inflating the box, which shrinks the
    -- body once the model is normalized to battle height.
    local hr,wr=sc.heightRatio or 0,sc.widthRatio or 0
    out[#out+1]=("   outlier ratio  height %.2f  width %.2f%s")
      :format(hr,wr,(hr>1.6 or wr>1.6) and "   <-- SCATTERED GEOMETRY" or "")
    out[#out+1]=("   skinning  %d envelope matrices (%d multi-bone) across %d enveloped meshes  fix=%s")
      :format(sc.envBlends or 0,sc.envBlendsMulti or 0,sc.envPobjs or 0,sc.skinFix and "ON" or "OFF")
    out[#out+1]=("   joints  %d hidden skipped   %d quaternion%s")
      :format(sc.hiddenJobjs or 0,sc.quatJobjs or 0,
        (sc.quatJobjs or 0)>0 and "  <-- ROTATIONS READ AS EULER" or "")
    -- Per-JOBJ world-scale diagnostic. Useful for spotting a truly degenerate
    -- source transform, but it is not a substitute for envelope placement.
    local jn=sc.jointCount or 0
    if jn>0 then
      out[#out+1]=("   joint world scale  %d contributing  min %.4f  median %.4f  max %.4f  %d outlier(s)%s")
        :format(jn,sc.jointScaleMin or 0,sc.jointScaleMedian or 0,sc.jointScaleMax or 0,
          sc.jointScaleOutliers or 0,
          (sc.jointScaleOutliers or 0)>0 and "  <-- A JOINT IS COLLAPSING OR EXPLODING" or "")
    end
    out[#out+1]=("   source visibility  %d zero-pass JOBJ(s) + %d DOBJ pass mismatch(es) skipped; %d shadow pass(es) quarantined  filter=%s")
      :format(sc.nonRenderJobjs or 0,sc.nonRenderDobjs or 0,sc.shadowDobjs or 0,sc.renderPassFilter and "ON" or "OFF")
    out[#out+1]=("   root selection  %s   semantic roots=%d")
      :format(sc.semanticRootsOnly and "SCENE-MODELSET ONLY" or "LEGACY/SCENE UNION",
        sc.semanticRootCount or 0)
    local cacheMismatch=(sc.renderPassFilter~=A.renderPassFilter)
      or (sc.skinFix~=A.skinFix)
      or (not sc.semanticRootsOnly)
      or (tostring(sc.requestedDecodeMode or "auto")~=tostring(A.decodeMode or "auto"))
    if cacheMismatch then
      out[#out+1]=("   !!! CACHE OPTION MISMATCH: cache skin=%s visibility=%s semanticRoot=%s mode=%s | current skin=%s visibility=%s semanticRoot=ON mode=%s")
        :format(sc.skinFix and "ON" or "OFF",sc.renderPassFilter and "ON" or "OFF",
          sc.semanticRootsOnly and "ON" or "OFF",tostring(sc.requestedDecodeMode or "auto"),
          A.skinFix and "ON" or "OFF",A.renderPassFilter and "ON" or "OFF",tostring(A.decodeMode or "auto"))
    end
    out[#out+1]=("   envelope coord  %d entries  single-bone: %d with coord / %d root-direct  IBM fallbacks %d")
      :format(sc.envelopeCoordEntries or 0,sc.singleEnvelopeCoord or 0,sc.singleEnvelopeNoCoord or 0,sc.inverseBindMissing or 0)
    if (sc.placeholderGroupsRemoved or 0)>0 then
      out[#out+1]=("   legacy placeholder heuristic unexpectedly removed %d group(s) / %d vertices")
        :format(sc.placeholderGroupsRemoved,sc.placeholderVertsRemoved or 0)
    else
      out[#out+1]="   placeholder heuristic OFF -- visibility comes from source JOBJ flags"
    end
    local drift=sc.poseDrift or 0
    out[#out+1]=("   pose  %s   drift from bind %.4f%s")
      :format((sc.clip or 0)==0 and "BIND (static, correctly assembled)" or ("clip "..tostring(sc.clip)),
        drift,drift>0.16 and "  <-- INCOHERENT" or "")
  end
  if not any then
    local live={}
    for _,rec in pairs(A._liveActors or {}) do if rec and rec.dex then live[#live+1]=rec.dex end end
    if #live>0 then
      out[#out+1]=("no species in the scene cache, but %d actor(s) are on the field (dex %s) -- "
        .."re-decode failed silently; check the log")
        :format(#live,table.concat(live,","))
    else
      out[#out+1]="no species loaded yet"
    end
  end
  for dex,err in pairs(sceneErrors) do
    out[#out+1]=("dex %s FAILED: %s"):format(dex,tostring(err))
  end
  for dex in pairs(pendingExtract) do
    out[#out+1]=("dex %s extraction declined this session"):format(dex)
  end
  return out
end

local function drawDebug()
  if not A.debug then return end
  local g=love and love.graphics
  if not g then return end
  local lines=debugLines()
  g.push("all")
  g.setShader()
  g.setDepthMode()
  g.setBlendMode("alpha","alphamultiply")
  -- Positioned clear of the battle HUD. This draws during the world pass, so
  -- the UI composites over it no matter what; the fix is to sit below the HP
  -- panels rather than to fight the draw order.
  local pad,lh=10,15
  local w=600
  local h=pad*2+#lines*lh
  local x,y=8,170
  g.setColor(0,0,0,0.88)
  g.rectangle("fill",x,y,w,h)
  g.setColor(0.35,0.9,0.65,0.5)
  g.rectangle("line",x,y,w,h)
  for i,line in ipairs(lines) do
    if i==1 then g.setColor(1,0.95,0.5,1) else g.setColor(0.78,0.97,0.88,1) end
    g.print(line,x+pad,y+pad+(i-1)*lh)
  end
  g.pop()
end

function A.status()
  local loaded,failed=0,0
  for _ in pairs(scenes) do loaded=loaded+1 end
  for _ in pairs(sceneErrors) do failed=failed+1 end
  return {
    version=1,provider="COLOSSEUM_BATTLE_ENVIRONMENTS:colosseum-pokemon",
    source="GC6E01 pkx battle models + native PKX presentation metadata",
    speciesSupported=Dex.speciesCount,
    scenesLoaded=loaded,scenesFailed=failed,
    pose="source-hsd-authored-frames",nativeMetadataReader=metadataReader~=nil,
    shaderReady=shader~=nil,
    debugOverlay=A.debug,
    diagnostic=debugLines(),
    onDemandExtraction=discOpener~=nil,
    performance={sceneLoads=perf.sceneLoads,sceneHits=perf.sceneHits,actionBuilds=perf.actionBuilds,
      actionPrewarms=perf.actionPrewarms,actorAcquires=perf.actorAcquires,residentAcquireHits=perf.residentAcquireHits,
      battlePrewarms=perf.battlePrewarms or 0,battlePrewarmMs=perf.battlePrewarmMs or 0,
      switchPrewarms=perf.switchPrewarms or 0,floorClamps=perf.floorClamps or 0,
      idleWarmLoads=perf.idleWarmLoads or 0,idleWarmMs=perf.idleWarmMs or 0,idleWarmPending=#idleWarmQueue,
      residentTrimKept=perf.residentTrimKept or 0,residentTrimReleased=perf.residentTrimReleased or 0,
      reactionClamps=perf.reactionClamps or 0,reactionFallbacks=perf.reactionFallbacks or 0,
      actionDrawFallbacks=perf.actionDrawFallbacks or 0,deferredActionWarms=perf.deferredActionWarms or 0,
      deferredActionPending=#actionWarmQueue+(A._actionWarmTask and 1 or 0),
      battleQueue=type(A.battlePrewarmStatus)=="function" and A.battlePrewarmStatus() or nil,
      workBudget=WorkBudget and type(WorkBudget.status)=="function" and WorkBudget.status() or nil,
      battleBodiesPrepared=perf.battleBodiesPrepared or 0,battlePlansPrepared=perf.battlePlansPrepared or 0,
      battlePreemptions=perf.battlePreemptions or 0,runtimeBaseHits=perf.runtimeBaseHits or 0,runtimeBaseWrites=perf.runtimeBaseWrites or 0,
      runtimeActionHits=perf.runtimeActionHits or 0,runtimeActionWrites=perf.runtimeActionWrites or 0,hardCache=A.hardCacheStatus()},
  }
end

local function battlerCacheKey(game,battler)
  if V.ModelIdentity and type(V.ModelIdentity.resolve)=="function" then
    local dex,variant=V.ModelIdentity.resolve(game,battler)
    if dex then return modelKey(dex,variant or monVariant(battler)) end
  end
  local mon=type(battler)=="table" and (battler.mon or battler.pokemon or battler.partyMon or battler) or nil
  local species=mon and mon.species
  local def=species~=nil and game and game.data and game.data.pokemon and game.data.pokemon[species]
  local dex=tonumber(def and (def.dex or def.index or def.number)) or tonumber(species)
  return dex and modelKey(dex,monVariant(battler)) or nil
end

local function releaseLoveObject(obj,seen)
  if obj==nil then return end
  seen=seen or {}
  if seen[obj] then return end
  seen[obj]=true
  pcall(function()
    local release=obj.release
    if type(release)=="function" then release(obj) end
  end)
end

local function releaseGroups(groups,seen)
  if type(groups)~="table" then return end
  for _,g in ipairs(groups) do
    if type(g)=="table" then
      releaseLoveObject(g.mesh,seen)
      releaseLoveObject(g.image,seen)
    end
  end
end

-- Android devices have a smaller shared RAM/VRAM budget than desktop, but
-- purging EVERY Pokemon after EVERY battle turns the generated cache back into
-- a repeated parse/upload tax. Keep a small player-party working set resident
-- and release everything else. Disk caches are never deleted here.
function A.trimRuntimeMemory(opts)
  opts=type(opts)=="table" and opts or {}
  local keep={}
  for key in pairs(sessionPinned) do if scenes[key] then keep[key]=true end end
  for _,actor in pairs(A._liveActors or {}) do
    if actor and actor.scene then keep[actor.cacheKey or actor.dex]=true end
  end
  local game=opts.game
  local keepParty=math.max(0,math.floor(tonumber(opts.keepParty) or 0))
  if game and keepParty>0 and type(game.save)=="table" then
    local party=game.save.party or game.save.pokemon or game.save.team
    local added=0
    if type(party)=="table" then
      for _,mon in ipairs(party) do
        local key=battlerCacheKey(game,mon)
        if key and scenes[key] and not keep[key] then
          keep[key]=true;added=added+1
          if added>=keepParty then break end
        end
      end
    end
  end
  local keepRecent=math.max(0,math.floor(tonumber(opts.keepRecent) or 0))
  if keepRecent>0 then
    local recent={}
    for dex,scene in pairs(scenes) do
      if not keep[dex] and type(scene)=="table" then recent[#recent+1]={dex=dex,use=tonumber(scene.__cbeLastUse) or 0} end
    end
    table.sort(recent,function(a,b)return a.use>b.use end)
    for i=1,math.min(keepRecent,#recent) do keep[recent[i].dex]=true end
  end
  -- Soft resident cap: do not churn GPU scenes at every battle boundary while
  -- the total working set is still modest. 1.7.9 always collapsed immediately
  -- to party+2-recent, which meant routes with 3-5 encounter species could
  -- repeatedly evict/re-upload the same bodies. Keep everything up to the cap;
  -- only when it is exceeded do the party/recent priorities above become an
  -- actual eviction policy. This preserves low-memory boundedness without
  -- manufacturing a reload tax after every battle.
  local softLimit=math.max(0,math.floor(tonumber(opts.softLimit) or 0))
  if softLimit>0 then
    local total,mandatory=0,0
    for dex,scene in pairs(scenes) do
      if type(scene)=="table" then
        total=total+1
        if keep[dex] then mandatory=mandatory+1 end
      end
    end
    if total<=softLimit then
      for dex,scene in pairs(scenes) do if type(scene)=="table" then keep[dex]=true end end
    else
      local fill={}
      for dex,scene in pairs(scenes) do
        if type(scene)=="table" and not keep[dex] then
          fill[#fill+1]={dex=dex,use=tonumber(scene.__cbeLastUse) or 0}
        end
      end
      table.sort(fill,function(a,b)return a.use>b.use end)
      local slots=math.max(0,softLimit-mandatory)
      for i=1,math.min(slots,#fill) do keep[fill[i].dex]=true end
    end
  end
  local seen={};local kept,released=0,0
  local liveScenes={}
  for _,actor in pairs(A._liveActors or {}) do if actor and actor.scene then liveScenes[actor.scene]=true end end
  for dex,scene in pairs(scenes) do
    if keep[dex] then
      if sessionPinned[dex] and not liveScenes[scene] and not opts.preserveActions
          and next(scene.actions or {})~=nil then
        local base=RuntimeMeshCache and select(1,RuntimeMeshCache.readLua(runtimeBasePath(dex)))
        if base and base.actions then
          local shared={}
          for _,g in ipairs(scene.groups or {}) do
            if g.mesh then shared[g.mesh]=true end;if g.image then shared[g.image]=true end
          end
          -- Scene textures are shared across later action rebuilds; releasing
          -- their still-indexed images would leave dangling cached resources.
          for _,image in pairs(scene.textures or {}) do shared[image]=true end
          for _,entry in pairs(scene.actions or {}) do
            releaseGroups(entry.groups,shared)
            for _,page in ipairs(entry.pages or {}) do releaseGroups(page.groups,shared) end
          end
          scene.actionSpecs={}
          for name,spec in pairs(base.actions) do scene.actionSpecs[name]=spec end
          if scene.actionInventoryComplete==false then mergeSelectiveActionSpecs(scene) end
          scene.actions={};scene.actionFailures={}
          requiredSessionPrepared[dex]=nil -- released GPU banks are not ready
        end
      end
      kept=kept+1
    elseif type(scene)=="table" then
      releaseGroups(scene.groups,seen)
      if type(scene.textures)=="table" then
        for _,img in pairs(scene.textures) do releaseLoveObject(img,seen) end
      end
      for _,entry in pairs(scene.actions or {}) do
        if type(entry)=="table" then
          releaseGroups(entry.groups,seen)
          for _,page in ipairs(entry.pages or {}) do if type(page)=="table" then releaseGroups(page.groups,seen) end end
        end
      end
      scenes[dex]=nil;sceneErrors[dex]=nil;pendingExtract[dex]=nil
      requiredSessionPrepared[dex]=nil
      released=released+1
    end
  end
  perf.residentTrimKept=(perf.residentTrimKept or 0)+kept
  perf.residentTrimReleased=(perf.residentTrimReleased or 0)+released
  -- Do not force a full Lua GC here. On mobile that stop-the-world collection
  -- can land immediately before the next battle/menu open. Released GPU objects
  -- are already explicitly released; BattleRuntime advances Lua GC incrementally
  -- during ordinary overworld frames.
  local q={}
  for _,row in ipairs(actionWarmQueue) do if row.scene and scenes[row.scene.dex]==row.scene then q[#q+1]=row else actionWarmSeen[row.id]=nil end end
  actionWarmQueue=q
  return true,{kept=kept,released=released}
end

function A.resetRuntime()
  sessionPinned={};sessionPrepared={};requiredSessionPrepared={};sessionEpoch=sessionEpoch+1
  if A.cancelInformation then A.cancelInformation() end
  if A.cancelBattlePrewarm then A.cancelBattlePrewarm("runtime-reset") end
  A.cancelPartyPrewarm()
  A.cancelHardCache()
  A.trimRuntimeMemory({keepParty=0,keepRecent=0})
  shader=nil;sceneUseSerial=0;sourceMetadata={};selectiveActionSpecs={};speciesCacheValidity={};pendingExtract={}
  if A._compactAction then A._compactAction.inventoryMemo={} end
  actionWarmQueue={};actionWarmSeen={};actionWarmNextAt=0
  perf={sceneLoads=0,sceneHits=0,actionBuilds=0,actionPrewarms=0,actorAcquires=0,residentAcquireHits=0,
    battlePrewarms=0,battlePrewarmMs=0,switchPrewarms=0,floorClamps=0,idleWarmLoads=0,idleWarmMs=0,
    residentTrimKept=0,residentTrimReleased=0,reactionClamps=0,reactionFallbacks=0,actionDrawFallbacks=0,
    runtimeBaseHits=0,runtimeBaseWrites=0,runtimeActionHits=0,runtimeActionWrites=0,deferredActionWarms=0}
  return true
end

function A.invalidateGeneratedManifestMemo()
  if extractor and type(extractor.invalidateManifestMemo)=="function" then
    pcall(extractor.invalidateManifestMemo,mod)
  end
  -- Explicit generated-cache DELETE may occur without restarting the process.
  -- Forget the acceleration proof in memory too; this does not delete anything.
  fullInventoryMemo=nil;fullInventoryLoaded=false
  fullInventoryDirty=false
  if A._compactAction then A._compactAction.inventoryMemo={} end
  if RuntimeMeshCache and type(RuntimeMeshCache.invalidateLua)=="function" then
    pcall(RuntimeMeshCache.invalidateLua,FULL_INVENTORY_PATH)
  end
  return true
end
function A.gcStep(k)
  if type(collectgarbage)~="function" then return false end
  local ok=pcall(collectgarbage,"step",math.max(16,math.floor(tonumber(k) or 64)))
  return ok
end

-- Legacy developer-facing "rebuild" hook. The absolute cache invariant forbids
-- deleting acquired/generated payload outside the explicit DELETE CACHE flow, so
-- this now performs a non-destructive runtime refresh only. It forgets validation
-- memos/GPU residency; stale source stamps are repaired on demand through the
-- preservation-aware extractor path, while valid saved bytes remain reusable.
function A.rebuildSpecies()
  speciesCacheValidity={}
  A.invalidateGeneratedManifestMemo()
  if RuntimeMeshCache and type(RuntimeMeshCache.invalidateLua)=="function" then
    pcall(RuntimeMeshCache.invalidateLua)
  end
  A.resetRuntime()
  return true,0
end

local function battlerDex(game,battler)
  if V.ModelIdentity then return V.ModelIdentity.resolve(game,battler) end
  local mon=type(battler)=="table" and (battler.mon or battler) or nil
  local species=mon and mon.species
  if species==nil then return nil end
  local def=game and game.data and game.data.pokemon and game.data.pokemon[species]
  local dex=tonumber(def and (def.dex or def.index or def.number))
  if not dex and tonumber(species) and Dex.supported(tonumber(species)) then dex=tonumber(species) end
  return dex
end

local function resolveSlotMove(game,slot)
  if type(slot)=="table" then
    if type(slot.move)=="table" then return slot.move end
    if slot.name or slot.power or slot.category or slot.damageClass or slot.type then return slot end
  end
  local id=type(slot)=="table" and (slot.id or slot.moveId or slot.index or slot.move) or slot
  local moves=game and game.data and game.data.moves
  return type(moves)=="table" and id~=nil and (moves[id] or moves[tostring(id)]) or nil
end

local function sourceMoveNumber(game,id,move)
  local n=tonumber(id)
  if not n and type(move)=="table" then n=tonumber(move.index or move.number or move.moveId) end
  if n then return n end
  local order=game and game.data and game.data.gen2Constants and game.data.gen2Constants.moveOrder
  if type(order)=="table" and id~=nil then
    local reverse=A._sourceMoveOrderIndex[order]
    if not reverse then
      reverse={}
      for i,key in ipairs(order) do if reverse[key]==nil then reverse[key]=i end end
      A._sourceMoveOrderIndex[order]=reverse
    end
    return reverse[id]
  end
  return nil
end

local function requiredActionKeys(game,battler)
  local wanted={damage=true,faint=true}
  local mon=type(battler)=="table" and (battler.mon or battler) or nil
  local slots=mon and mon.moves or (type(battler)=="table" and battler.moves)
  if type(slots)=="table" then
    for _,slot in pairs(slots) do wanted[moveSlot(resolveSlotMove(game,slot))]=true end
  end
  local out={}
  for _,key in ipairs({"damage","faint","physicalA","specialA"}) do
    if wanted[key] then out[#out+1]=key end
  end
  return out
end

-- A normal Continue/reload does not need every PKX action bank the species owns.
-- Retail Waza data can select a less-common body row (physicalB, damageHeavy,
-- extra*, etc.), so include those rows when the already-cached move source tells
-- us about them. This remains read-only: a missing MoveFX bank is not extracted
-- merely to decide which Pokemon actions should be warm.
requiredActionNames=function(game,battler)
  local wanted={idle=true};local strict={}
  if battler then
    for _,key in ipairs(requiredActionKeys(game,battler)) do wanted[key]=true end
  else
    -- New Game has no concrete party rows yet. Keep the common retail battle
    -- quartet ready without turning starter setup into an all-actions bake.
    wanted.damage=true;wanted.faint=true;wanted.physicalA=true;wanted.specialA=true
  end
  local mon=type(battler)=="table" and (battler.mon or battler) or nil
  local slots=mon and mon.moves or (type(battler)=="table" and battler.moves)
  local extractorRef=V.MoveFXExtractor
  local models=V.CurrentSpriteModels
  local phasePolicy=V.WazaPhasePolicy
  local dex=battlerDex(game,battler)
  if type(slots)=="table" and extractorRef and type(extractorRef.peek)=="function"
      and models and type(models.sourceNativeSlot)=="function" then
    for _,slot in pairs(slots) do
      local move=resolveSlotMove(game,slot)
      local id=type(slot)=="table" and (slot.id or slot.moveId or (type(slot.move)~="table" and slot.move)) or slot
      if id==nil and type(move)=="table" then id=move.id or move.index or move.number end
      if id~=nil then
        local okSpec,spec=pcall(extractorRef.peek,id,move)
        if okSpec and type(spec)=="table" then
          local selectionId=sourceMoveNumber(game,id,move)
          if phasePolicy and type(phasePolicy.select)=="function" then
            local okSelected,selected=pcall(phasePolicy.select,spec,{moveId=selectionId,dex=dex,stage="attack"})
            if okSelected and type(selected)=="table" then spec=selected end
          end
          for _,role in ipairs({"attack","damage"}) do
            local okSlot,name=pcall(models.sourceNativeSlot,models,spec,role)
            if okSlot and type(name)=="string" and name~="" then
              wanted[name]=true
              -- A Waza sequenceKind is an explicit source row selector. Keep its
              -- preparation strict so a missing extra*/specialC/etc sidecar can
              -- never be masked by a generic family fallback.
              strict[name]=true
            end
          end
        end
      end
    end
  end
  local out={};for name in pairs(wanted) do out[#out+1]=name end;table.sort(out)
  return out,strict
end

ensureRequiredActionInventory=function(dex,variant,game,battler,progress)
  local names,strict=requiredActionNames(game,battler)
  local candidates={}
  for _,name in ipairs(names) do
    if strict and strict[name] then candidates[name]={name}
    else candidates[name]=NATIVE_FALLBACKS[name] or {name} end
  end
  return ensureActionSubset(dex,variant,names,progress,candidates)
end

function A._requiredModelSignature(game,battler)
  local identity=type(A.sessionCacheIdentity)=="function" and A.sessionCacheIdentity()
    or ("required-session|"..tostring(sessionEpoch))
  local names,strict=requiredActionNames(game,battler)
  local keys={}
  for _,name in ipairs(names) do keys[#keys+1]=name..(strict[name] and "!exact" or "") end
  return tostring(identity).."|"..table.concat(keys,",")
end

function A._requiredSignatureReady(key,signature)
  local rec=requiredSessionPrepared[key]
  if rec==signature then return true end -- compatibility with any in-flight v1 state
  return type(rec)=="table" and rec[signature]==true
end

function A._noteRequiredSignature(key,signature)
  local rec=requiredSessionPrepared[key]
  if type(rec)~="table" then
    local prior=type(rec)=="string" and rec or nil
    rec={};requiredSessionPrepared[key]=rec
    if prior then rec[prior]=true end
  end
  rec[signature]=true
end

local function warmActionKey(scene,key)
  if not (scene and key) then return false,"action scene unavailable",key end
  local seen={};local name=key
  while name do
    if seen[name] then return false,"cyclic action alias: "..tostring(name),name end
    seen[name]=true
    local entry,why=materializeSceneAction(scene,name)
    if not entry then return false,why,name end
    if not entry.alias then
      -- An alias stub alone is never readiness. Every page of the actual owner
      -- must exist before startup/battle preparation can certify this selector.
      local ready=type(entry.groups)=="table" and #entry.groups>0
      if type(entry.pages)=="table" and #entry.pages>0 then
        ready=true
        for _,page in ipairs(entry.pages) do
          if not (type(page.groups)=="table" and #page.groups>0) then ready=false;break end
        end
      end
      if not ready then return false,"native action has no drawable groups: "..tostring(name),name end
      perf.actionPrewarms=perf.actionPrewarms+1
      return true,nil,name
    end
    name=tostring(entry.alias)
  end
  return false,"action alias target unavailable",key
end

local function warmRequiredActions(scene,game,battler)
  local warmed=0
  for _,key in ipairs(requiredActionNames(game,battler)) do
    if warmActionKey(scene,key) then warmed=warmed+1 end
  end
  return warmed
end

function A.queueSceneAction(scene,key)
  if not (scene and key and scene.actionSpecs and scene.actionSpecs[key])
      or (scene.actions and scene.actions[key]) then return false end
  local id=tostring(scene.dex or "?")..":"..key
  if actionWarmSeen[id] then return false end
  actionWarmSeen[id]=true
  actionWarmQueue[#actionWarmQueue+1]={scene=scene,key=key,id=id}
  return true
end
local function queueRequiredActions(scene,game,battler)
  if not scene then return 0 end
  local added=0
  for _,key in ipairs(requiredActionNames(game,battler)) do
    if A.queueSceneAction(scene,key) then added=added+1 end
  end
  return added
end

function A.pumpActionPrewarm(maxJobs,milliseconds)
  maxJobs=math.max(1,math.floor(tonumber(maxJobs) or 1))
  if #actionWarmQueue==0 and not A._actionWarmTask then return 0,0 end
  local clock=(love and love.timer and love.timer.getTime) or os.clock
  local now=clock and clock() or 0
  -- An already-started task resumes on consecutive rendered frames. Applying
  -- the job-start cooldown to each 3ms slice turns milliseconds of CPU work
  -- into seconds of wall time on mobile.
  if not A._actionWarmTask and now>0 and now<actionWarmNextAt then return 0,#actionWarmQueue end
  if WorkBudget then
    if not A._actionWarmTask then
      local row=table.remove(actionWarmQueue,1)
      if not row then return 0,0 end
      A._actionWarmCurrent=row
      A._actionWarmTask=WorkBudget.new(function()
        if not (row.scene and scenes[row.scene.dex]==row.scene) then return false,"scene released" end
        return warmActionKey(row.scene,row.key)
      end,"Battle action "..row.id)
    end
    local ok,state,result=WorkBudget.resume(A._actionWarmTask,tonumber(milliseconds) or 3)
    if ok and state~="done" then return 0,#actionWarmQueue+1 end
    if A._actionWarmCurrent then actionWarmSeen[A._actionWarmCurrent.id]=nil end
    A._actionWarmCurrent=nil;A._actionWarmTask=nil
    local done=(ok and result==true) and 1 or 0
    actionWarmNextAt=clock()+(MOBILE_RUNTIME and 0.16 or 0.07)
    perf.deferredActionWarms=(perf.deferredActionWarms or 0)+done
    return done,#actionWarmQueue
  end
  -- Compatibility for hosts which deliberately omit the cooperative module.
  local done=0
  while done<maxJobs and #actionWarmQueue>0 do
    local row=table.remove(actionWarmQueue,1)
    if row then
      actionWarmSeen[row.id]=nil
      if row.scene and scenes[row.scene.dex]==row.scene and warmActionKey(row.scene,row.key) then done=done+1 end
    end
  end
  actionWarmNextAt=clock()+(MOBILE_RUNTIME and 0.16 or 0.07)
  perf.deferredActionWarms=(perf.deferredActionWarms or 0)+done
  return done,#actionWarmQueue
end

-- Forward-declare BOTH worker functions: the cooperative closure below is
-- defined before their bodies. Otherwise a genuinely cold model calls a nil
-- global prewarmBaseBattler (resident-body tests never entered that branch).
local prewarmBattler,prewarmBaseBattler

local function queueBattleWarmRow(battle,side,battler,priority)
  local game=battle and battle.game
  local dex=battlerCacheKey(game,battler)
  if not (game and battler and dex and Dex.supported(dex)) then return false end
  local variant=monVariant(battler)
  local key=tostring(modelKey(dex,variant))
  -- A resident storage-profile body is not battle-ready by itself. Summary/PC
  -- can leave the exact model resident while this battler's damage/faint/move
  -- subset is still absent. Only the exact required-model predicate may suppress
  -- the cooperative battle job.
  if type(A.requiredModelReady)=="function" and A.requiredModelReady(dex,variant,game,battler) then return false end
  -- One model/action plan may be requested first by BattleRuntime's native lead
  -- prewarm and again milliseconds later by DoublesPresenter under its lane id.
  -- Deduplicate by exact model + required-action signature, not by caller-side
  -- label. Same-species battlers with DIFFERENT movesets still get independent
  -- plans; identical plans share one cooperative build/upload job.
  local failure=pendingExtract[modelKey(dex,variant)]
  if failure and retryClock()<failure.retryAt then return false end
  local id=key..":"..A._requiredModelSignature(game,battler)
  -- The incoming slot can be the SAME plan the bench worker is already loading.
  -- Promote that live coroutine in place before considering preemption. Cancelling
  -- it discards its staged meshes/source progress and restarts the exact work the
  -- visible send-out is waiting for. Other critical plans may still preempt it.
  if priority and battleWarmCurrent and battleWarmCurrent.id==id then
    battleWarmCurrent.priority=true
    return false
  end
  if priority and battleWarmTask and battleWarmCurrent and not battleWarmCurrent.priority
      and WorkBudget then
    local displaced=battleWarmCurrent
    WorkBudget.cancel(battleWarmTask)
    battleWarmTask=nil;battleWarmCurrent=nil
    table.insert(battleWarmQueue,displaced)
    perf.battlePreemptions=(perf.battlePreemptions or 0)+1
  end
  if battleWarmSeen[id] then
    -- A switch that is becoming visible outranks speculative bench preparation.
    -- Promote its already-queued row instead of waiting behind the rest of a
    -- six-Pokemon roster. A matching running job was promoted in place above.
    if priority then
      for i,row in ipairs(battleWarmQueue) do
        if row and row.id==id then
          row.priority=true;table.remove(battleWarmQueue,i);table.insert(battleWarmQueue,1,row);break
        end
      end
    end
    return false
  end
  battleWarmSeen[id]=true
  local row={battle=battle,game=game,side=side,battler=battler,dex=dex,variant=variant,id=id,priority=priority==true}
  if priority then table.insert(battleWarmQueue,1,row) else battleWarmQueue[#battleWarmQueue+1]=row end
  return true
end

function A.cancelBattlePrewarm(reason)
  if battleWarmTask and WorkBudget then pcall(WorkBudget.cancel,battleWarmTask) end
  battleWarmTask=nil;battleWarmCurrent=nil;battleWarmQueue={};battleWarmSeen={}
  if A._actionWarmTask and WorkBudget then pcall(WorkBudget.cancel,A._actionWarmTask) end
  A._actionWarmTask=nil;A._actionWarmCurrent=nil
  actionWarmQueue={};actionWarmSeen={};actionWarmNextAt=0
  return true
end

function A.queueBattlePrewarm(battle,side,battler,priority)
  if side then return queueBattleWarmRow(battle,side,battler,priority==true) and 1 or 0 end
  local n=0
  for _,name in ipairs({"player","enemy"}) do
    local b=battle and battle[name]
    if b and queueBattleWarmRow(battle,name,b,priority==true) then n=n+1 end
  end
  return n
end

function A._knownBattleParty(battle,side)
  if type(battle)~="table" then return nil end
  if side=="player" then
    return battle.playerParty or battle.party
      or (type(battle.player)=="table" and battle.player.party)
  end
  return battle.enemyParty
    or (type(battle.trainer)=="table" and battle.trainer.party)
    or (type(battle.enemy)=="table" and battle.enemy.party)
end

-- Android must start preparing every KNOWN participant as soon as the battle
-- owns a stable arena. The previous active-pair-only policy left bench species
-- genuinely cold until battle.battler_switched; Mt. Battle exposes six-member
-- opponent rosters, so a late native species (for example Jynx in Gen I) could
-- hit source extraction on the visible send-out and appear to freeze/crash.
-- This is bounded to the two actual parties (normally <=12 rows), deduplicated by
-- model + exact required-action signature, and never expands to a 386-model bake.
function A.queueBattleRosterPrewarm(battle)
  local n=0
  -- Opponent bench first: the player's party already receives startup/overworld
  -- warming, while an encounter roster is often unknown until battle creation.
  for _,side in ipairs({"enemy","player"}) do
    local party=A._knownBattleParty(battle,side)
    if type(party)=="table" then
      for i=1,math.min(6,#party) do
        local battler=party[i]
        if battler and queueBattleWarmRow(battle,side,battler,false) then n=n+1 end
      end
    end
  end
  return n
end

-- Memory-only failure report for the native readiness boundary. This never
-- probes disk and never consumes/retries the pending source operation.
function A.battlePreparationFailure(dex,variant)
  local row=pendingExtract[modelKey(dex,variant)]
  if not row then return nil end
  return {reason=row.reason,retryAt=row.retryAt}
end

function A.battlePrewarmStatus()
  local current=battleWarmCurrent
  local nextRow=battleWarmQueue[1]
  local criticalBodies=0
  if current and current.priority and current.phase=="body" then criticalBodies=1 end
  for _,row in ipairs(battleWarmQueue) do
    if row.priority and not A.peek("battle-status",row.dex,row.variant).resident then
      criticalBodies=criticalBodies+1
    end
  end
  return {
    pending=#battleWarmQueue+(battleWarmTask and 1 or 0),
    criticalBodies=criticalBodies,
    queued=#battleWarmQueue,
    currentDex=current and current.dex or nil,
    currentSide=current and current.side or nil,
    currentPhase=current and current.phase or nil,
    nextDex=nextRow and nextRow.dex or nil,
    nextSide=nextRow and nextRow.side or nil,
  }
end

-- Select all currently visible BODY jobs before their action banks. A complete
-- action plan for the first opponent must not block the other three send-outs.
-- Visible participants still outrank speculative six-member benches.
function A._nextBattleWarmRow()
  local index,score
  for i,row in ipairs(battleWarmQueue) do
    local body=A.peek("battle-prewarm",row.dex,row.variant).resident
    local rank=(row.priority and 0 or 2)+(body and 1 or 0)
    if not score or rank<score then index,score=i,rank end
  end
  return index and table.remove(battleWarmQueue,index) or nil
end

function A.pumpBattlePrewarm(milliseconds)
  -- Desktop, Android and iOS use the same resumable path. All synchronous
  -- draw/entry promotions are bypassed when the published service advertises it.
  if not WorkBudget then return false,#battleWarmQueue end
  if not battleWarmTask then
    if #battleWarmQueue>0 and A._actionWarmTask then
      WorkBudget.cancel(A._actionWarmTask)
      if A._actionWarmCurrent then
        -- The exact plan will prepare required banks; retry a non-required bank
        -- later, with no source/asset mutations beyond its cancelled staging.
        table.insert(actionWarmQueue,1,A._actionWarmCurrent)
      end
      A._actionWarmTask=nil;A._actionWarmCurrent=nil
    end
    local row=A._nextBattleWarmRow()
    if not row then return false,0 end
    battleWarmCurrent=row
    row.phase=A.peek("battle-prewarm",row.dex,row.variant).resident and "actions" or "body"
    battleWarmTask=WorkBudget.new(function()
      if row.phase=="body" then
        -- This phase publishes only this appearance's authentic body/idle.
        -- Returning here creates a scheduling boundary before ANY action plan.
        return prewarmBaseBattler(row.game,row.battler,row.side,true,WorkBudget.checkpoint)
      end
      if type(A.prepareRequiredModel)=="function" then
        return A.prepareRequiredModel(row.dex,row.variant,row.game,row.battler,
          WorkBudget.checkpoint,{pin=false})
      end
      return prewarmBattler(row.game,row.battler,row.side,true,false,true,WorkBudget.checkpoint)
    end,"Battle "..row.phase.." "..tostring(row.dex).." / "..tostring(row.variant))
  end
  local ok,state,result,why=WorkBudget.resume(battleWarmTask,tonumber(milliseconds) or 3)
  if not ok or state=="done" then
    local row=battleWarmCurrent
    battleWarmTask=nil;battleWarmCurrent=nil
    local success=ok and result~=false and result~=nil
    if success and row then pendingExtract[modelKey(row.dex,row.variant)]=nil end
    if success and row and row.phase=="body" then
      -- Keep the exact-signature dedup reservation through the second phase.
      -- A later send event can promote this same row without duplicating work.
      row.phase="actions";table.insert(battleWarmQueue,row)
      perf.battleBodiesPrepared=(perf.battleBodiesPrepared or 0)+1
    else
      if row then battleWarmSeen[row.id]=nil end
      if not success then
        local err=tostring((not ok and state) or why or "battle model preparation failed")
        if row then pendingExtract[modelKey(row.dex,row.variant)]={retryAt=retryClock()+2,reason=err} end
        log("warn","deferred battle model preparation failed: %s",err)
      else perf.battlePlansPrepared=(perf.battlePlansPrepared or 0)+1 end
    end
    return true,#battleWarmQueue
  end
  return true,#battleWarmQueue+1
end


prewarmBattler=function(game,battler,side,allowExtract,warmActions,queueActions,progress)
  local dex=battlerCacheKey(game,battler)
  if not (dex and Dex.supported(dex)) then return false,"unsupported battler",0 end
  local cached=speciesCacheReady(dex)
  if not cached and not allowExtract then return false,"not cached",0 end
  -- Use the exact acquisition path the visible actor will use. This resolves the
  -- compact cache, GPU meshes, source metadata and idle bank now, so the later
  -- send-out is a resident hash-table hit rather than a multi-megabyte parse.
  local ctx={game=game,battle={game=game},arena={figureScale=DEFAULT_FIGURE_SCALE},services={prewarm=true}}
  local actor,err=A.acquire("cbe-prewarm",dex,monVariant(battler),{context=ctx,battler=battler,side=side,progress=progress,noSource=not allowExtract})
  if not actor then return false,err,0 end
  local actions=0
  if warmActions~=false then actions=warmRequiredActions(actor.scene,game,battler)
  elseif queueActions~=false then actions=queueRequiredActions(actor.scene,game,battler) end
  actor:release()
  return true,nil,actions
end
prewarmBaseBattler=function(game,battler,side,allowExtract,progress)
  local dex=battlerCacheKey(game,battler)
  if not (dex and Dex.supported(dex)) then return false,"unsupported battler",nil end
  if A.peek("cbe-warm",dex,monVariant(battler)).resident then return true,nil,dex end
  local cached=speciesCacheReady(dex)
  if not cached and not allowExtract then return false,"not cached",dex end
  -- Information-surface acquisition intentionally builds only the base/idle
  -- body. Native attack/damage/faint banks remain packed on disk until battle.
  -- This makes the persistent cache useful to party/stats/model screens without
  -- paying the much larger combat-action GPU bill during overworld idle time.
  local ctx={game=game,battle={game=game},arena={figureScale=DEFAULT_FIGURE_SCALE},services={prewarm=true,informationSurface=true}}
  local actor,err=A.acquire("cbe-idle-warm",dex,monVariant(battler),{context=ctx,battler=battler,side=side,progress=progress})
  if actor then actor:release() end
  return actor~=nil,err,dex
end

local informationTask=nil
local informationTaskDex=nil
local informationTaskKind=nil
local informationFailures={}
function A.cancelInformation(identity)
  if informationTask and (not identity or tostring(identity)==informationTaskDex) then
    if WorkBudget then WorkBudget.cancel(informationTask) end
    informationTask=nil;informationTaskDex=nil;informationTaskKind=nil
  end
end
function A.informationWorkStatus(game,battler)
  local key=battlerCacheKey(game,battler)
  local dex=key and (tostring(key)..":"..monVariant(battler))
  local failure=dex and informationFailures[dex]
  return {dex=dexNumber(key),key=key,running=informationTask~=nil and informationTaskDex==dex,
    phase=(informationTaskDex==dex and WorkBudget and WorkBudget.label(informationTask)) or nil,
    error=failure and failure.error or nil}
end

-- Cooperative information-viewer warm seam. This is intentionally separate
-- from acquire(): UI render code can ask the resident scheduler to prepare a
-- model without performing any disk/extractor/GPU work inside draw().
function A.informationWarmStatus(game,battler)
  local key=battlerCacheKey(game,battler);local dex=dexNumber(key)
  local variant=monVariant(battler)
  if not (key and Dex.supported(dex)) then
    return {dex=dex,key=key,variant=variant,resident=false,cached=false,idlePrepared=false,supported=false}
  end
  local scene=scenes[key]
  local resident=A.peek("information",dex,variant).resident
  local cached,stamp=speciesCacheReady(key)
  local idlePrepared=false
  if scene then idlePrepared=(scene.actions and scene.actions.idle)~=nil or runtimeActionSidecarReady(scene,"idle")
  elseif cached and type(stamp)=="string" then idlePrepared=runtimeActionSidecarReady({dex=key,_runtimeStamp=stamp},"idle") end
  return {dex=dex,key=key,variant=variant,resident=resident,cached=cached or scene~=nil,
    idlePrepared=idlePrepared,supported=true}
end

function A.prewarmInformation(game,battler,allowExtract,progress)
  local status=A.informationWarmStatus(game,battler)
  if status.resident then return true,"resident",status.dex end
  local ok,err=prewarmBaseBattler(game,battler,"player",allowExtract,progress)
  if ok then
    A.trimRuntimeMemory({game=game,keepParty=6,keepRecent=MOBILE_RUNTIME and 3 or 6,
      softLimit=MOBILE_RUNTIME and 9 or 16})
  end
  return ok,err,status.dex
end

-- Compatibility eager base-body helper retained for direct diagnostics. Normal
-- runtime startup no longer calls this: ResidentPrewarm queues the same cached
-- base bodies and promotes them one at a time on stable overworld frames. This
-- helper still avoids action banks and never starts ISO extraction.
function A.prewarmPartyBase(game)
  idleWarmQueue={};idleWarmSeen={};idleWarmGame=game;idleWarmNextAt=0
  if type(game)~="table" or type(game.save)~="table" then return 0,0 end
  local party=game.save.party or game.save.pokemon or game.save.team
  if type(party)~="table" then return 0,0 end
  local warmed,failed,seen=0,0,{}
  for _,mon in ipairs(party) do
    local dex=battlerCacheKey(game,mon)
    if dex and Dex.supported(dex) and not seen[dex] then
      seen[dex]=true
      local ok=prewarmBaseBattler(game,mon,"player")
      if ok then warmed=warmed+1 else failed=failed+1 end
    end
  end
  return warmed,failed
end

function A.queuePartyPrewarm(game)
  idleWarmQueue={};idleWarmSeen={};idleWarmGame=game;idleWarmNextAt=0
  if type(game)~="table" or type(game.save)~="table" then return 0 end
  local party=game.save.party or game.save.pokemon or game.save.team
  if type(party)~="table" then return 0 end
  for _,mon in ipairs(party) do
    local dex=battlerCacheKey(game,mon)
    if dex and Dex.supported(dex) and not idleWarmSeen[dex] and not scenes[dex] then
      idleWarmSeen[dex]=true
      idleWarmQueue[#idleWarmQueue+1]={battler=mon,side="player",dex=dex}
    end
  end
  return #idleWarmQueue
end

function A.pumpPartyPrewarm(game)
  game=game or idleWarmGame
  if #idleWarmQueue==0 or type(game)~="table" then return false,#idleWarmQueue end
  local clock=(love and love.timer and love.timer.getTime) or os.clock
  local now=clock and clock() or 0
  if now>0 and now<idleWarmNextAt then return false,#idleWarmQueue end
  local row=table.remove(idleWarmQueue,1)
  if not row then return false,0 end
  local t0=now
  local ok,err=prewarmBaseBattler(game,row.battler,row.side)
  local t1=clock and clock() or t0
  perf.idleWarmLoads=(perf.idleWarmLoads or 0)+(ok and 1 or 0)
  perf.idleWarmMs=(perf.idleWarmMs or 0)+math.max(0,(t1-t0)*1000)
  -- Leave breathing room between species uploads. The work happens while the
  -- overworld is already interactive instead of stacking six models onto one
  -- battle/menu transition frame.
  idleWarmNextAt=(t1>0 and t1 or now)+(MOBILE_RUNTIME and 0.55 or 0.20)
  if not ok and err then log("warn","Cached-party warm dex %s skipped: %s",tostring(row.dex),tostring(err)) end
  return ok,#idleWarmQueue
end

local function releaseActionEntry(entry)
  if type(entry)~="table" then return end
  local seen={}
  local function releaseMeshes(groups)
    for _,g in ipairs(type(groups)=="table" and groups or {}) do
      if type(g)=="table" then releaseLoveObject(g.mesh,seen) end
    end
  end
  -- Action groups borrow the base scene's Image objects. Release only the
  -- temporary meshes created to bake the f32 sidecar; textures stay owned by
  -- the resident base body.
  releaseMeshes(entry.groups)
  for _,page in ipairs(entry.pages or {}) do if type(page)=="table" then releaseMeshes(page.groups) end end
end

A._releaseActionMeshes=releaseActionEntry

-- Validate/cache an action without keeping its large GPU bank resident. Compact
-- action inventories are already direct-upload binary and return immediately;
-- this legacy sidecar path remains only for older/storage-profile caches.
local function bakeActionSidecar(scene,key,seen)
  if not (scene and key) then return false,"scene unavailable" end
  seen=seen or {}
  if seen[key] then return false,"cyclic action alias" end
  seen[key]=true
  local compactOK=select(1,A._compactAction.specReady(scene,key,true,{}))
  if compactOK then return true,"compact-ready" end
  if A._runtimeActionCurrentGuardReady(scene,key) then return true,"ready" end
  local spec=scene.actionSpecs and scene.actionSpecs[key]
  if type(spec)~="table" then return false,"action source unavailable" end
  local entry=materializeSceneAction(scene,key)
  if not entry then return false,"action bake failed" end
  local aliasOk,aliasWhy=true,nil
  if entry.alias then aliasOk,aliasWhy=bakeActionSidecar(scene,tostring(entry.alias),seen) end
  releaseActionEntry(entry)
  if scene.actions then scene.actions[key]=nil end
  scene.actionSpecs=scene.actionSpecs or {};scene.actionSpecs[key]=spec
  if RuntimeMeshCache and RuntimeMeshCache.invalidateLua then RuntimeMeshCache.invalidateLua(runtimeActionManifestPath(scene.dex,key)) end
  if not aliasOk then return false,aliasWhy end
  return A._runtimeActionCurrentGuardReady(scene,key),"baked"
end

function A.bakeInformationIdle(game,battler)
  local dex=battlerCacheKey(game,battler)
  if not (dex and Dex.supported(dex)) then return false,"unsupported battler" end
  local scene=scenes[dex]
  if not scene then
    local ok,why=prewarmBaseBattler(game,battler,"player")
    if not ok then return false,why end
    scene=scenes[dex]
  end
  if not scene then return false,"scene unavailable" end
  if not ((scene.actionSpecs and scene.actionSpecs.idle) or (scene.actions and scene.actions.idle)) then return true,"idle unavailable" end
  if scene.actions and scene.actions.idle then return true,"resident" end
  return bakeActionSidecar(scene,"idle")
end

function A.pumpInformation(game,battler,kind)
  kind=kind or "body"
  if not WorkBudget then
    local ok,why=A.prewarmInformation(game,battler,true)
    return ok,why,false
  end
  local key=battlerCacheKey(game,battler)
  if not (key and Dex.supported(key)) then return false,"unsupported battler",false end
  local identity=tostring(key)..":"..monVariant(battler)
  if kind=="body" and A.peek("information",dexNumber(key),monVariant(battler)).resident then
    return true,"resident",false
  end
  local clock=(love and love.timer and love.timer.getTime) or os.clock
  local failure=informationFailures[identity]
  if failure and clock()<failure.retryAt then return false,failure.error,false end
  if informationTask and (informationTaskDex~=identity or informationTaskKind~=kind) then
    -- The scheduler serializes started requests. Other callers must not cancel
    -- a source writer just to take over its model slot.
    return false,"another model is preparing",true
  end
  if not informationTask then
    informationTaskDex=identity;informationTaskKind=kind
    informationTask=WorkBudget.new(function()
      if kind=="body" then return A.prewarmInformation(game,battler,true,workCheckpoint) end
      -- Never temporarily mutate/release a live actor's idle groups during a
      -- disk bake. Use an independent CPU-only scene and publish valid sidecars.
      local scene,why=loadScene(key,true,workCheckpoint)
      if not scene then return false,why end
      if scene.actionSpecs and scene.actionSpecs.idle then return bakeActionSidecar(scene,"idle") end
      return true,"no source idle"
    end,kind=="idle" and "Preparing source idle" or "Preparing selected model")
  end
  local ok,state,result,why=WorkBudget.resume(informationTask,ANDROID_RUNTIME and 3 or 6)
  if ok and state=="working" then return false,result,true end
  informationTask=nil;informationTaskDex=nil;informationTaskKind=nil
  if ok and result then informationFailures[identity]=nil;return true,why,false end
  local err=tostring(ok and why or state or "model preparation failed")
  informationFailures[identity]={error=err,retryAt=clock()+2}
  log("warn","Information model %s: %s",identity,err)
  return false,err,false
end


local hardCacheTask=nil
local hardDiskScene=nil
local hardDeadline=0
local function hardClock()
  if love and love.timer and love.timer.getTime then return love.timer.getTime() end
  return os.clock()
end
local function hardCheckpoint()
  if hardClock()>=hardDeadline then coroutine.yield("cpu-slice") end
end
local function hardScene(dex,profile)
  profile=profile=="storage" and "storage" or "full"
  if hardDiskScene and hardDiskScene.dex==dex
      and hardDiskScene._runtimeStamp==expectedSpeciesStamp()
      and (profile=="storage" or hardDiskScene.actionInventoryComplete~=false) then return hardDiskScene end
  hardDiskScene=nil
  if not speciesCacheReady(dex) then
    if not (extractor and extractor.extractSpecies and discOpener) then return nil,"source extractor unavailable" end
    local opened,disc=pcall(discOpener)
    if not opened or not disc then return nil,"source disc unavailable: "..tostring(disc) end
    -- Missing source species still require the real extractor. A failed or
    -- cancelled bake is retryable; successful sidecars need not be rebuilt.
    local ok,out,why=pcall(extractSource,mod,disc,dex,
      {targetHeight=16.0,decodeMode=A.decodeMode,skinFix=A.skinFix,renderPassFilter=true,
        actionProfile=profile,
        checkpoint=hardCheckpoint,progress=function(label) hardCacheState.phase=label;hardCheckpoint() end})
    if not ok or not out then return nil,tostring(why or out or "source extraction failed") end
    speciesCacheValidity[dex]=nil
    if RuntimeMeshCache and RuntimeMeshCache.invalidateLua then RuntimeMeshCache.invalidateLua(runtimeBasePath(dex)) end
    if not speciesCacheReady(dex) then return nil,"source revision validation failed" end
    hardCheckpoint()
  elseif profile=="full" then
    local variant=type(dex)=="string" and "shiny" or "normal"
    local upgraded,why=ensureFullActionInventory(dex,variant,hardCheckpoint)
    if not upgraded then return nil,why end
  end
  local scene,why=loadScene(dex,true,hardCheckpoint)
  if scene and profile=="full" and scene.actionInventoryComplete==false then
    return nil,"storage-only action inventory survived full hard-cache preparation"
  end
  hardDiskScene=scene
  return scene,why
end
local function hardPartyMetadata(dex,needsFilter)
  -- Party battle actors still need their authored slot/attachment timings.
  -- Preserve that cache preparation without constructing an Actor. Storage
  -- viewers never consume it, so do not inflate every boxed species' PKX.
  -- Shiny action rows revisit this guard after the base row. Reuse the exact
  -- validated compact metadata from that first check instead of rereading the
  -- same Lua payload once per native action on high-latency cache backends.
  local memoKey=tostring(dex)
  local cached=sourceMetadata[memoKey]
  if not (type(cached)=="table" and (tonumber(cached.revision) or 0)>=6
      and cached.scaleSelector~=nil and (not needsFilter or validFilter(cached.shinyFilter))) then
    cached=select(1,readLua(metadataCachePath(dex)))
  end
  if type(cached)=="table" and (tonumber(cached.revision) or 0)>=6
    and cached.scaleSelector~=nil and (not needsFilter or validFilter(cached.shinyFilter)) then
    sourceMetadata[memoKey]=cached;return true
  end
  if not (metadataReader and type(metadataReader.inspectSpecies)=="function") then
    return not needsFilter,needsFilter and "source shiny metadata reader unavailable" or nil
  end
  if not discOpener then return false,"party metadata source unavailable" end
  local opened,disc=pcall(discOpener)
  if not opened or not disc then return false,"party metadata disc unavailable" end
  local ok,value,why=pcall(metadataReader.inspectSpecies,disc,dexNumber(dex),type(dex)=="string" and "shiny" or "normal",nil,{progress=hardCheckpoint})
  if not ok or not value then return false,tostring(why or value or "party metadata unavailable") end
  if needsFilter and not validFilter(value.shinyFilter) then return false,"source shiny parameters missing" end
  if not writeMetadataCache(dex,value) then return false,"party metadata write failed" end
  sourceMetadata[tostring(dex)]=value
  return true
end
local function runHardRow(row)
  -- Hard Cache Save follows the same bounded ownership as battle entry: keep the
  -- canonical species body on its storage profile, then add only the exact
  -- action rows represented by this queue. Existing legacy/full caches are
  -- accepted unchanged by hardScene("storage").
  --
  -- Catalog tiers are model-library caches: exact source body + authored idle.
  -- Battle action families stay selective/on-demand for the Pokemon that actually
  -- enter battle. This keeps the 386 cache bounded and, critically, preserves a
  -- user's already-complete catalog across releases instead of expanding it into
  -- every possible action bank.
  if row.kind=="catalog" then
    local prepared,why=A.prepareStorageModel(row.dex,"normal",hardCheckpoint)
    if not prepared then return false,why end
    hardCacheState.bases=hardCacheState.bases+1
    hardCacheState.storage=(hardCacheState.storage or 0)+1
    return true,why or "catalog-ready"
  end
  local scene,why=hardScene(row.dex,"storage")
  if not scene then return false,why end
  if row.kind=="base" or row.shiny then
    local prepared,why=hardPartyMetadata(row.dex,row.shiny and not Dex.rare[dexNumber(row.dex)])
    if not prepared then return false,why end
    if row.kind=="base" then hardCacheState.bases=hardCacheState.bases+1;return true,"base-ready" end
  end
  local key=row.kind=="storage" and "idle" or row.key
  local spec=scene.actionSpecs and scene.actionSpecs[key]
  if row.kind=="action" and not spec then
    local variant=type(row.dex)=="string" and "shiny" or "normal"
    local candidateMap={}
    candidateMap[key]=row.strict and {key} or (NATIVE_FALLBACKS[key] or {key})
    local prepared,selectWhy=ensureActionSubset(dexNumber(row.dex),variant,{key},hardCheckpoint,candidateMap)
    if not prepared then return false,selectWhy end
    mergeSelectiveActionSpecs(scene,{key})
    spec=scene.actionSpecs and scene.actionSpecs[key]
  end
  local ok=true
  if spec then ok,why=bakeActionSidecar(scene,key)
  elseif not (row.optional or row.kind=="storage") then ok,why=false,"action source unavailable" end
  if ok then
    hardCacheState.actions=hardCacheState.actions+(spec and 1 or 0)
    if row.kind=="storage" then
      hardCacheState.bases=hardCacheState.bases+1
      hardCacheState.storage=(hardCacheState.storage or 0)+1
    end
  end
  if row.kind=="storage" then hardDiskScene=nil end
  return ok,why
end

-- Build the exact disk-work rows separately from execution so the same plan can
-- be fingerprinted for cross-session reuse without opening the source disc or
-- touching a cache payload. Sorting is used only by the signature below; the
-- execution order remains party-first, then required actions, then box storage.
local function buildHardCacheRows(game,scope)
  local catalogLimits={catalog151=151,catalog251=251,catalog=386}
  scope=(scope=="team" or scope=="full" or catalogLimits[scope]) and scope or "full"
  local rows={}
  local catalogLimit=catalogLimits[scope]
  if catalogLimit then
    for dex=1,catalogLimit do
      if Dex.supported(dex) then rows[#rows+1]={kind="catalog",dex=dex,variant="normal"} end
    end
    return rows
  end
  if type(game)~="table" or type(game.save)~="table" then return rows end
  local save=game.save
  local party=save.party or save.pokemon or save.team
  local byDex,partyOrder,storageOrder={}, {}, {}

  -- Party species receive the full battle-oriented hard cache: compact base,
  -- authored information idle, and the exact damage/faint/move banks required
  -- by the current moveset. This preserves the existing 1.9.17 contract.
  if type(party)=="table" then
    for _,mon in ipairs(party) do
      if type(mon)=="table" then
        local dex=battlerCacheKey(game,mon)
        if dex and Dex.supported(dex) then
          local row=byDex[dex]
          if not row then
            row={dex=dex,battler=mon,actions={},strictActions={},party=true}
            byDex[dex]=row;partyOrder[#partyOrder+1]=row
          else
            row.party=true
            if not row.battler then row.battler=mon end
          end
          row.shiny=row.shiny or monVariant(mon)=="shiny"
          local names,strict=requiredActionNames(game,mon)
          for _,key in ipairs(names) do
            row.actions[key]=true
            if strict and strict[key] then row.strictActions[key]=true end
          end
        end
      end
    end
  end

  -- PC information viewers can traverse dozens/hundreds of species without a
  -- battle ever having made those bodies resident in this process. Hard Cache
  -- Save is the explicit one-time/refresh operation, so include every UNIQUE
  -- boxed species here. Box-only species need only the compact base body plus
  -- authored idle sidecar; do not build battle-only action banks for storage.
  -- A single `storage` queue row owns both CPU-only steps. It never creates
  -- a temporary GPU scene or evicts a model used by the running game.
  local boxes=save.boxes or save.box
  if scope~="team" and type(boxes)=="table" then
    for _,box in pairs(boxes) do
      if type(box)=="table" then
        local mons=box.pokemon or box.mons or box
        if type(mons)=="table" then
          for _,mon in pairs(mons) do
            if type(mon)=="table" then
              local dex=battlerCacheKey(game,mon)
              if dex and byDex[dex] and monVariant(mon)=="shiny" then byDex[dex].shiny=true end
              if dex and Dex.supported(dex) and not byDex[dex] then
                local row={dex=dex,battler=mon,actions={},party=false,shiny=monVariant(mon)=="shiny"}
                byDex[dex]=row;storageOrder[#storageOrder+1]=row
              end
            end
          end
        end
      end
    end
  end

  for _,row in ipairs(partyOrder) do
    rows[#rows+1]={kind="base",dex=row.dex,battler=row.battler,shiny=row.shiny}
  end
  for _,row in ipairs(partyOrder) do
    -- Information surfaces upgrade the compact base body to the authored idle
    -- bank after first pixel. Bake that exact bank during Hard Cache Save too;
    -- otherwise a supposedly hard-cached party can still hitch seconds later
    -- when Summary/PC/Pokedex first asks for idle animation.
    rows[#rows+1]={kind="action",dex=row.dex,key="idle",battler=row.battler,optional=true}
    local actionKeys={};for key in pairs(row.actions) do if key~="idle" then actionKeys[#actionKeys+1]=key end end
    table.sort(actionKeys)
    for _,key in ipairs(actionKeys) do
      rows[#rows+1]={kind="action",dex=row.dex,key=key,battler=row.battler,shiny=row.shiny,
        strict=row.strictActions and row.strictActions[key]==true}
    end
  end
  for _,row in ipairs(storageOrder) do
    rows[#rows+1]={kind="storage",dex=row.dex,battler=row.battler,shiny=row.shiny}
  end
  return rows
end

function A.hardCacheSignature(game,scope)
  local catalogLimits={catalog151=151,catalog251=251,catalog=386}
  scope=(scope=="team" or scope=="full" or catalogLimits[scope]) and scope or "full"
  local catalogLimit=catalogLimits[scope]
  if catalogLimit then
    -- Keep the persisted plan proof compact and save-independent. Changing the
    -- user's party must not turn an already-complete catalog tier into a full
    -- row-by-row revalidation pass on the next launch.
    local contract="normal:storage"
    return "pokemon-hard-cache-plan-v1|stamp="..tostring(expectedSpeciesStamp())
      .."|scope="..scope.."|rows=001-"..tostring(catalogLimit)..":"..contract
  end
  local rows=buildHardCacheRows(game,scope);local keys={}
  for _,row in ipairs(rows) do
    keys[#keys+1]=table.concat({
      tostring(row.kind or ""),tostring(row.dex or ""),tostring(row.key or ""),
      row.shiny and "shiny" or "normal",row.optional and "optional" or "required",
    },":")
  end
  table.sort(keys)
  return "pokemon-hard-cache-plan-v1|stamp="..tostring(expectedSpeciesStamp())
    .."|scope="..scope.."|rows="..table.concat(keys,",")
end

function A.queueHardCache(game,scope)
  local catalogLimits={catalog151=151,catalog251=251,catalog=386}
  scope=(scope=="team" or scope=="full" or catalogLimits[scope]) and scope or "full"
  hardCacheTask=nil;hardDiskScene=nil
  hardCacheQueue=buildHardCacheRows(game,scope);hardCacheGame=game
  hardCacheState={running=false,total=0,done=0,failed=0,bases=0,actions=0,storage=0,fullBattle=0,last=nil,scope=scope,head=1,tail=#hardCacheQueue}

  hardCacheState.total=hardCacheState.tail;hardCacheState.running=hardCacheState.tail>0
  return hardCacheState.tail
end

function A.pumpHardCache(game,maxJobs)
  game=game or hardCacheGame;maxJobs=math.max(1,math.floor(tonumber(maxJobs) or 1))
  -- Cooperative slices keep parsing/floor analysis/binary packing responsive.
  -- A source extractor call or an individual host read/write is indivisible;
  -- this is a CPU target, not a promise of a hard real-time frame bound.
  hardDeadline=hardClock()+(MOBILE_RUNTIME and 0.003 or 0.006)
  local processed=0
  -- Full cache plans can contain hundreds of party/action/storage rows. Advance a
  -- monotonic head instead of table.remove(...,1), which shifts the entire
  -- remaining array on every completed row and turns queue bookkeeping into
  -- O(n^2) work on the devices where extraction/storage is already slowest.
  while processed<maxJobs and hardCacheState.head<=hardCacheState.tail do
    local row=hardCacheQueue[hardCacheState.head]
    if not hardCacheTask then hardCacheTask=coroutine.create(function() return runHardRow(row) end) end
    local resumed,ok,why=coroutine.resume(hardCacheTask)
    if resumed and coroutine.status(hardCacheTask)~="dead" then break end
    hardCacheTask=nil
    hardCacheQueue[hardCacheState.head]=nil;hardCacheState.head=hardCacheState.head+1
    processed=processed+1
    hardCacheState.last=row.kind..":"..tostring(row.dex)..(row.key and (":"..row.key) or "")
    if resumed and ok then hardCacheState.done=hardCacheState.done+1
    else
      hardDiskScene=nil
      local reason=tostring(resumed and why or ok)
      row._hardCacheRetries=(tonumber(row._hardCacheRetries) or 0)+1
      if row._hardCacheRetries<=1 then
        -- Retry only the failed row once. Mobile storage/source bridges can
        -- transiently fail a single host call; successful payload already on
        -- disk is preserved and the retry validators reuse it. This does not
        -- inflate the logical job count and keeps queue bookkeeping O(1).
        hardCacheState.retried=(hardCacheState.retried or 0)+1
        hardCacheState.lastRetry=hardCacheState.last
        hardCacheState.lastRetryError=reason
        hardCacheState.tail=hardCacheState.tail+1
        hardCacheQueue[hardCacheState.tail]=row
        log("warn","Hard Cache Save %s failed once; retrying: %s",hardCacheState.last,reason)
      else
        hardCacheState.failed=hardCacheState.failed+1
        hardCacheState.lastFailed=hardCacheState.last
        hardCacheState.lastError=reason
        log("warn","Hard Cache Save %s failed after retry: %s",hardCacheState.last,hardCacheState.lastError)
      end
    end
    if hardClock()>=hardDeadline then break end
  end
  local pending=math.max(0,hardCacheState.tail-hardCacheState.head+1)
  hardCacheState.running=pending>0
  if not hardCacheState.running then
    if hardCacheState.scope=="catalog" and not hardCacheState.inventoryFlushed then
      -- Acceleration-only metadata: one bounded write after the 386-row pass,
      -- never one write per species. A failure here cannot invalidate the model
      -- payloads themselves; the next catalog pass will simply deep-validate.
      hardCacheState.inventoryFlushed=true
      if type(A.flushInventoryCertificate)=="function" then pcall(A.flushInventoryCertificate) end
    end
    hardDiskScene=nil;hardCacheQueue={};hardCacheState.head=1;hardCacheState.tail=0
  end
  return {processed=processed,pending=pending,running=hardCacheState.running,done=hardCacheState.done,failed=hardCacheState.failed}
end

function A.cancelHardCache()
  if hardCacheTask then sourceBusy=false end
  hardCacheTask=nil;hardDiskScene=nil;hardCacheQueue={};hardCacheGame=nil;hardCacheState.head=1;hardCacheState.tail=0;hardCacheState.running=false
end

function A.hardCacheStatus()
  return {running=hardCacheState.running,pending=math.max(0,(hardCacheState.tail or 0)-(hardCacheState.head or 1)+1),total=hardCacheState.total,done=hardCacheState.done,failed=hardCacheState.failed,bases=hardCacheState.bases,actions=hardCacheState.actions,storage=hardCacheState.storage or 0,fullBattle=hardCacheState.fullBattle or 0,last=hardCacheState.last,
    lastFailed=hardCacheState.lastFailed,lastError=hardCacheState.lastError,retried=hardCacheState.retried or 0,
    lastRetry=hardCacheState.lastRetry,lastRetryError=hardCacheState.lastRetryError,phase=hardCacheState.phase,scope=hardCacheState.scope}
end

function A.cancelPartyPrewarm()
  idleWarmQueue={};idleWarmSeen={};idleWarmGame=nil;idleWarmNextAt=0
end

function A.prewarmParty(game)
  -- Compatibility alias: callers that still use the historical eager API are
  -- redirected to the bounded queue. Never reintroduce a full-party base +
  -- action-bank upload burst through an older integration seam.
  return A.queuePartyPrewarm(game)
end

-- Plan active bodies and the known roster. The normal runtime uses deferCold:
-- entry is memory-only and the post-frame scheduler performs actual preparation.
-- Explicit eager callers/legacy integrations keep the established API below.
function A.prewarmBattle(battle,opts)
  opts=type(opts)=="table" and opts or {}
  local allowExtract=opts.allowExtract~=false
  local deferCold=opts.deferCold==true
  local game=battle and battle.game
  if type(game)~="table" then return {ready=0,failed=0,actions=0,rosterReady=0,elapsedMs=0} end
  local clock=(love and love.timer and love.timer.getTime) or os.clock
  local t0=clock and clock() or 0
  local out={ready=0,failed=0,actions=0,rosterReady=0,rosterActions=0,errors={}}

  -- Active battlers outrank speculative bench jobs, without doing uploads here.
  for _,side in ipairs({"player","enemy"}) do
    local battler=battle and battle[side]
    if battler then
      local dex=battlerCacheKey(game,battler)
      local ok,err,actions
      if deferCold and WorkBudget then
        ok=dex and A.peek("battle-entry",dex,monVariant(battler)).resident or false
        err=not ok and "pending cooperative preparation" or nil
        actions=0
        if queueBattleWarmRow(battle,side,battler,true) then
          out.deferred=(out.deferred or 0)+1
        end
      else
        -- Explicit compatibility/preparation callers retain the old eager API;
        -- ordinary battle runtime always opts into the nonblocking path above.
        ok,err,actions=prewarmBattler(game,battler,side,allowExtract,false)
      end
      if ok then
        out.ready=out.ready+1
        out.deferredActions=(out.deferredActions or 0)+(tonumber(actions) or 0)
      else
        out.failed=out.failed+1;out.errors[side]=tostring(err)
        if deferCold and not WorkBudget and queueBattleWarmRow(battle,side,battler,true) then
          out.deferred=(out.deferred or 0)+1
        end
      end
    end
  end

  -- Do not bulk-upload a six-model bench on the battle.started call itself. On
  -- all deferred targets immediately schedule the complete known roster through
  -- the cooperative worker. That gives Mt. Battle's future switch-ins the whole
  -- preceding fight to finish source extraction/binary preparation instead of
  -- discovering a cold species on its visible PokÃ© Ball release.
  if (MOBILE_RUNTIME or (deferCold and WorkBudget)) and type(A.queueBattleRosterPrewarm)=="function" then
    out.rosterQueued=A.queueBattleRosterPrewarm(battle)
  else out.rosterQueued=0 end
  out.benchDeferred=true

  local t1=clock and clock() or t0
  out.elapsedMs=math.max(0,(t1-t0)*1000)
  perf.battlePrewarms=(perf.battlePrewarms or 0)+1
  perf.battlePrewarmMs=(perf.battlePrewarmMs or 0)+out.elapsedMs
  return out
end

function A.prewarmSwitch(battle,side,battler,opts)
  opts=type(opts)=="table" and opts or {}
  local game=battle and battle.game
  battler=battler or (battle and side and battle[side])
  if not (game and battler) then return false,"missing replacement" end
  if opts.deferCold==true and WorkBudget then
    queueBattleWarmRow(battle,side,battler,true)
    local dex=battlerCacheKey(game,battler)
    local ready=dex and A.peek("battle-switch",dex,monVariant(battler)).resident or false
    return ready,not ready and "pending cooperative preparation" or nil,0
  end
  local ok,err,actions=prewarmBattler(game,battler,side,opts.allowExtract~=false,false)
  if ok then
    perf.switchPrewarms=(perf.switchPrewarms or 0)+1
  elseif opts.deferCold==true then
    -- A replacement is now presentation-critical. If its speculative roster job
    -- is still pending, move it to the head of the cooperative queue.
    queueBattleWarmRow(battle,side,battler,true)
  end
  return ok,err,actions
end

-- Wired from main.lua. `openDisc` is a zero-arg function returning an opened
-- GameCubeDisc, kept as a closure so this module never learns the host path.
function A.install(pokemonExtractor,openDisc,currentSpriteModels,pkxMetadataReader)
  extractor=pokemonExtractor
  discOpener=openDisc
  csm=currentSpriteModels
  metadataReader=pkxMetadataReader
  -- Compile/link the actor shader while the mod is initializing whenever the
  -- graphics context is already available. This moves driver work away from
  -- the exact first-send-out frame; hosts that initialize graphics later still
  -- fall back to the normal lazy ensureShader() path.
  local ok,sh,prewarmErr=pcall(ensureShader)
  if not ok then
    log("warn","Pokemon actor shader prewarm failed: %s",tostring(sh))
  elseif not sh and prewarmErr and tostring(prewarmErr)~="LOVE graphics unavailable" then
    log("warn","Pokemon actor shader prewarm declined: %s",tostring(prewarmErr))
  end
  return true
end

-- Per-frame entry point for the overlay, wrapped around CurrentSpriteModels'
-- own drawWorld. That runs every frame of a CBE battle regardless of which
-- presentation mode won, so the overlay can report being UNSELECTED -- which
-- withRenderer, by definition, never could.
function A.debugFrame()
  pcall(pollDebugKey)
  pcall(drawDebug)
  A.drewThisFrame=false
end

-- Read-only information-surface cache probes. These intentionally answer from
-- live memory only: UI cursor movement must never touch the filesystem merely
-- to discover whether a fast path exists. Game-ready/previous battle/menu
-- prewarm already leaves the compact base scene in `scenes[dex]`.
function A.peek(source,dex,variant)
  local key=modelKey(dex,variant);local n=dexNumber(dex)
  local resident=key and Dex.supported(n) and scenes[key]~=nil or false
  if resident and variant=="shiny" and not Dex.rare[n] then
    local metadata=sourceMetadata[tostring(key)]
    resident=validFilter(metadata and metadata.shinyFilter)
  end
  return {resident=resident,cached=resident,variant=variant,key=key}
end

function A.acquireCached(source,dex,variant,opts)
  if not A.peek(source,dex,variant).resident then return nil,"variant not resident" end
  return A.acquire(source,dex,variant,opts)
end


-- MAIN-MENU SESSION CACHE -------------------------------------------------
-- Required session/disk caching covers the 251 normal species identities only.
-- Exact shiny source variants/colour recipes remain available on-demand.
function A.sessionCacheIdentity()
  return "session-models-v1|"..tostring(expectedSpeciesStamp()).."|"..tostring(sessionEpoch)
end
function A.sessionResidentCount()
  local n=0;for _ in pairs(scenes) do n=n+1 end;return n
end
-- Memory-only readiness for native battle updates, including bodies loaded by
-- another caller after a completed startup/disk preparation. Preview residency
-- alone does not certify the complete authored action set.
function A.sessionModelReady(dex,variant)
  local key=modelKey(dex,variant)
  return key~=nil and sessionPrepared[key]~=nil
    and sessionPrepared[key]==expectedSpeciesStamp() and A.peek('session',dex,variant).resident
end
-- Disk completeness, independent of GPU residency and of any selected save.
-- Only compact manifests/metadata and file sizes are read: no text geometry,
-- extraction, mesh construction or generated writes. Older completed v1.0.8/9
-- units are recognized without a new completion marker or cache invalidation.
function A.persistentModelState(dex,variant,progress)
  local n=dexNumber(dex)
  if not (n and Dex.supported(n) and RuntimeMeshCache) then return false,"unsupported cache" end
  variant=variant or "normal"
  local key=modelKey(n,variant)
  local checkpoint=progress or function()end
  local function missing(why)
    sessionPrepared[key]=nil;speciesCacheValidity[key]=nil
    return false,why
  end
  if not materialTexgenReady(key) then return missing("material texgen compatibility") end
  local stamp=expectedSpeciesStamp()
  if type(stamp)~="string" then return missing("source revision") end
  -- Bypass positive filesystem/Lua memos at an explicit batch selection. A
  -- deleted binary or partial unit must become eligible again after a restart.
  if RuntimeMeshCache.invalidateLua then RuntimeMeshCache.invalidateLua(runtimeBasePath(key)) end
  local base=select(1,RuntimeMeshCache.readLua(runtimeBasePath(key)))
  -- The runtime-base sidecar is committed only after decoding the canonical
  -- species cache and embeds that cache's complete extractor stamp. Checking it
  -- against today's expected stamp proves the same revision/options without a
  -- separate host read of rev.txt for every species in a Quick/Full inventory
  -- scan. A missing/stale sidecar falls through to preparation, whose
  -- speciesCacheReady() still validates rev.txt before any source reuse/repair.
  if not runtimeBaseUsable(base,stamp,key,true) then return missing("base sidecars") end
  -- Box-only Hard Cache units intentionally stop at base + idle. They are valid
  -- information-viewer caches but must never certify Quick/Full battle reuse.
  -- A party/session preparation upgrades them from the source before field use.
  if base.actionInventoryComplete==false or tostring(base.actionProfile or "full")=="storage" then
    return missing("storage-only action profile")
  end
  local metadata=select(1,readLua(metadataCachePath(key)))
  local shinyFilterRequired=variant=="shiny" and not Dex.rare[n]
  if not (type(metadata)=="table" and (tonumber(metadata.revision) or 0)>=4
      and type(metadata.slots)=="table" and (not shinyFilterRequired or validFilter(metadata.shinyFilter))) then
    return missing(shinyFilterRequired and "native/shiny metadata" or "native metadata")
  end
  if type(base.actions)~="table" then return missing("action inventory") end
  local scene={dex=key,_runtimeStamp=stamp,_diskOnly=true,groups=base.groups,actionSpecs=base.actions}
  local names={};for name in pairs(base.actions)do names[#names+1]=name end;table.sort(names)
  -- Refresh action manifests including aliases/pages before existing validators
  -- follow them. These files contain tiny descriptors, never vertex payloads.
  local seen={}
  local function refresh(name)
    if seen[name] then return end;seen[name]=true
    local path=runtimeActionManifestPath(key,name)
    if RuntimeMeshCache.invalidateLua then RuntimeMeshCache.invalidateLua(path) end
    local meta=select(1,RuntimeMeshCache.readLua(path))
    if type(meta)~="table" then return end
    if meta.alias then refresh(tostring(meta.alias)) end
    if RuntimeMeshCache.invalidateLua then
      RuntimeMeshCache.invalidateLua(runtimeActionFloorPath(key,name))
      for pi in ipairs(type(meta.pages)=="table" and meta.pages or {})do
        RuntimeMeshCache.invalidateLua(runtimeActionFloorPath(key,name.."/page"..pi))
      end
    end
  end
  for _,name in ipairs(names)do
    checkpoint("Checking cached action "..n.." / "..tostring(name))
    refresh(name)
    if not A._reusableActionPayloadReady(scene,name,true) then return missing("action "..tostring(name)) end
  end
  for _,g in ipairs(base.groups)do
    if g.texture then
      local t=g.texture
      local expected=(tonumber(t.w) or 0)*(tonumber(t.h) or 0)*4
      local info=t.path and generatedInfoValidated(t.path,true)
      if expected<=0 or not info or tonumber(info.size)~=expected then return missing("texture payload") end
    end
  end
  -- A later required-party warm pass can load just its existing binary scene.
  -- This flag certifies disk preparation, not GPU residency or a shiny actor.
  sourceMetadata[tostring(key)]=metadata;sessionPrepared[key]=stamp
  -- Quick Cache only inventories normal full-action units. Dedicated rare shiny
  -- geometry and ordinary shiny colour recipes remain exact and on-demand.
  if variant=="normal" then pcall(noteFullInventory,n,stamp) end
  return true,"disk-complete"
end

-- Lightweight catalog/storage completeness. Bulk Quick/Full/Mt. Battle cache
-- preparation needs a source-faithful body and authored information idle, not
-- every battle action the species could ever use. Keep this proof separate from
-- persistentModelState(), which remains the strict full-action validator for
-- callers that explicitly need the historical battle-complete contract.
function A.storageModelState(dex,variant,progress)
  local n=dexNumber(dex)
  if not (n and Dex.supported(n) and RuntimeMeshCache) then return false,"unsupported cache" end
  variant=variant or "normal"
  local key=modelKey(n,variant)
  if not materialTexgenReady(key) then return false,"material texgen compatibility" end
  local checkpoint=progress or function()end
  local stamp=expectedSpeciesStamp()
  if type(stamp)~="string" then return false,"source revision" end
  if RuntimeMeshCache.invalidateLua then RuntimeMeshCache.invalidateLua(runtimeBasePath(key)) end
  local base=select(1,RuntimeMeshCache.readLua(runtimeBasePath(key)))
  if not runtimeBaseUsable(base,stamp,key,true) then return false,"base sidecars" end
  local metadata=select(1,readLua(metadataCachePath(key)))
  local shinyFilterRequired=variant=="shiny" and not Dex.rare[n]
  if not (type(metadata)=="table" and (tonumber(metadata.revision) or 0)>=4
      and type(metadata.slots)=="table" and (not shinyFilterRequired or validFilter(metadata.shinyFilter))) then
    return false,shinyFilterRequired and "native/shiny metadata" or "native metadata"
  end
  if type(base.actions)~="table" then return false,"action inventory" end
  local scene={dex=key,_runtimeStamp=stamp,_diskOnly=true,groups=base.groups,actionSpecs=base.actions}
  if base.actions.idle then
    checkpoint("Checking cached idle "..n)
    if RuntimeMeshCache.invalidateLua then
      RuntimeMeshCache.invalidateLua(runtimeActionManifestPath(key,"idle"))
      RuntimeMeshCache.invalidateLua(runtimeActionFloorPath(key,"idle"))
    end
    if not A._reusableActionPayloadReady(scene,"idle",true) then return false,"idle sidecar" end
  end
  for _,g in ipairs(base.groups or {})do
    if g.texture then
      local t=g.texture
      local expected=(tonumber(t.w) or 0)*(tonumber(t.h) or 0)*4
      local info=t.path and generatedInfoValidated(t.path,true)
      if expected<=0 or not info or tonumber(info.size)~=expected then return false,"texture payload" end
    end
  end
  sourceMetadata[tostring(key)]=metadata
  if variant=="normal" then pcall(noteFullInventory,n,stamp) end
  return true,"storage-complete"
end

-- Read-only planning fast path. A matching positive certificate is sufficient
-- only to classify a normal species as "already cached" for batch selection.
-- It is NEVER consumed by actor acquisition/readiness: prepareSessionModel,
-- prepareRequiredModel and loadScene retain their existing authoritative
-- validation/repair semantics. Unknown/stale certificates fall through to the
-- deep validator once and are promoted only after that validator succeeds.
function A.inventoryModelState(dex,variant,progress)
  local n=dexNumber(dex)
  variant=variant or "normal"
  if not (n and Dex.supported(n)) then return false,"unsupported cache" end
  -- Never let a normal-body proof certify a shiny appearance. Shared-body shiny
  -- actors still require their exact GC6E01 colour recipe, while rare shinies
  -- require their separate source archive; both stay on-demand.
  if variant~="normal" then
    inventoryStats.deep=inventoryStats.deep+1
    return A.persistentModelState(n,variant,progress)
  end
  local stamp=expectedSpeciesStamp()
  local value=loadFullInventory()
  -- A positive inventory certificate predates the per-species texgen migration.
  -- Do not let that tiny accelerator hide a missing capability marker forever;
  -- affected old caches must fall through to deep validation/repair on the next
  -- Quick/Full Cache pass.
  local materialReady=materialTexgenReady(modelKey(n,variant))
  local certificateCompatible=type(stamp)=="string" and type(value.stamp)=="string"
    and (value.stamp==stamp or (A._speciesStampCompatible and A._speciesStampCompatible(value.stamp)))
  if certificateCompatible and value.complete[n]==true and materialReady then
    if value.stamp~=stamp then value.stamp=stamp;fullInventoryDirty=true end
    inventoryStats.hits=inventoryStats.hits+1
    return true,"inventory-certified"
  end
  inventoryStats.deep=inventoryStats.deep+1
  local probe=type(A.storageModelState)=="function" and A.storageModelState or A.persistentModelState
  local ready,why=probe(n,variant,progress)
  if ready and type(stamp)=="string" then pcall(noteFullInventory,n,stamp) end
  return ready,why
end

-- Persist accumulated normal-model inventory proof once per successful cache
-- operation rather than once per species. A Full Catalog can validate/prepare
-- 386 models while paying one small metadata write instead of 386 bridge writes.
function A.flushInventoryCertificate()
  return flushFullInventory()
end

-- Disk-only bulk catalog preparation. New/missing species are extracted with
-- the existing storage profile (base + authored idle only). Battle entry later
-- uses prepareRequiredModel() to warm the active battlers' exact action rows, so
-- catalog preparation never expands 135-386 species into thousands of unused
-- canonical action banks. Existing legacy/full caches are accepted and never
-- destructively downgraded here.
function A.prepareStorageModel(dex,variant,progress)
  local n=dexNumber(dex)
  if not (n and Dex.supported(n)) then return false,"unsupported species" end
  variant=variant or "normal"
  local key=modelKey(n,variant)
  local checkpoint=progress or workCheckpoint
  local ready,why=A.storageModelState(n,variant,checkpoint)
  if ready then return true,why end

  if not speciesCacheReady(key) then
    if not discOpener then return false,"source disc unavailable" end
    local opened,disc=pcall(discOpener)
    if not opened or not disc then return false,"source disc could not be opened" end
    local result,extractWhy=extractSource(mod,disc,n,{variant=variant,targetHeight=16,
      decodeMode=A.decodeMode,skinFix=A.skinFix,renderPassFilter=true,actionProfile="storage",
      progress=checkpoint,checkpoint=checkpoint})
    if not result then return false,extractWhy or "storage extraction failed" end
    speciesCacheValidity[key]=nil
    if RuntimeMeshCache and RuntimeMeshCache.invalidateLua then RuntimeMeshCache.invalidateLua(runtimeBasePath(key)) end
    if not speciesCacheReady(key) then return false,"generated storage source revision did not validate" end
  end

  checkpoint("Preparing catalog model "..n.." / "..variant)
  local disk,loadWhy=loadScene(key,true,checkpoint)
  if not disk then return false,loadWhy end
  if disk.actionSpecs and disk.actionSpecs.idle and not A._reusableActionPayloadReady(disk,"idle",true) then
    local idleOK,idleWhy=bakeActionSidecar(disk,"idle")
    if not idleOK then return false,"authored idle: "..tostring(idleWhy) end
  end
  local metadata=select(1,readLua(metadataCachePath(key)))
  local filterRequired=variant=="shiny" and not Dex.rare[n]
  if not (type(metadata)=="table" and (tonumber(metadata.revision) or 0)>=4
      and type(metadata.slots)=="table" and (not filterRequired or validFilter(metadata.shinyFilter))) then
    if not (metadataReader and discOpener) then return false,"native model metadata unavailable" end
    local opened,disc=pcall(discOpener)
    if not opened or not disc then return false,"metadata source unavailable" end
    local ok,value,err=pcall(metadataReader.inspectSpecies,disc,n,
      type(key)=="string" and "shiny" or "normal",nil,{progress=checkpoint})
    if not ok or not value then return false,tostring(err or value or "metadata failed") end
    if filterRequired and not validFilter(value.shinyFilter) then return false,"source shiny colour parameters missing" end
    if not writeMetadataCache(key,value) then return false,"could not persist source metadata" end
    sourceMetadata[tostring(key)]=value
  end
  local final,finalWhy=A.storageModelState(n,variant,checkpoint)
  if not final then return false,finalWhy end
  return true,"storage-saved"
end

-- The 386 "FULL" option is a battle cache, not merely a model gallery. Persist
-- the complete canonical PKX action inventory for every normal species so a
-- later battle never has to reopen GC6E01 just because a move selects an action
-- family that was omitted by the storage profile. Every action is stored once
-- as a compact compressed binary pack; battle entry decompresses only the rows
-- it actually needs and keeps the GPU working set bounded.
function A.prepareFullCatalogModel(dex,variant,progress)
  local n=dexNumber(dex)
  if not (n and Dex.supported(n)) then return false,"unsupported species" end
  variant=variant or "normal"
  local key=modelKey(n,variant)
  local checkpoint=progress or workCheckpoint

  if not speciesCacheReady(key) then
    if not discOpener then return false,"source disc unavailable" end
    local opened,disc=pcall(discOpener)
    if not opened or not disc then return false,"source disc could not be opened" end
    checkpoint("Extracting full battle cache "..n.." / "..variant)
    local result,extractWhy=extractSource(mod,disc,n,{variant=variant,targetHeight=16,
      decodeMode=A.decodeMode,skinFix=A.skinFix,renderPassFilter=true,actionProfile="full",preserveExisting=false,
      progress=checkpoint,checkpoint=checkpoint})
    if not result then return false,extractWhy or "full battle extraction failed" end
    speciesCacheValidity[key]=nil
    if RuntimeMeshCache and RuntimeMeshCache.invalidateLua then RuntimeMeshCache.invalidateLua(runtimeBasePath(key)) end
    if not speciesCacheReady(key) then return false,"generated full source revision did not validate" end
  else
    local _,complete=cachedActionProfile(key)
    if not complete then
      checkpoint("Adding source action inventory "..n.." / "..variant)
      local upgraded,why=ensureFullActionInventory(n,variant,checkpoint)
      if not upgraded then return false,why end
    end
  end

  local profile,complete=cachedActionProfile(key)
  if not complete then return false,"full source action inventory is incomplete: "..tostring(profile) end
  if not (A._compactAction and A._compactAction.inventoryReady and A._compactAction.inventoryReady(key)) then
    return false,"compact action inventory certificate missing"
  end
  checkpoint("Validating full battle model "..n.." / "..variant)
  local disk,loadWhy=loadScene(key,true,checkpoint)
  if not disk then return false,loadWhy end
  if disk.actionInventoryComplete==false then return false,"storage-only action inventory survived full battle cache" end

  -- Battle ownership/attachment selection consumes the compact source metadata.
  -- Certify it during FULL CACHE so a battle never opens the source merely to
  -- recover slot/scale information.
  local metadata=select(1,readLua(metadataCachePath(key)))
  local filterRequired=variant=="shiny" and not Dex.rare[n]
  if not (type(metadata)=="table" and (tonumber(metadata.revision) or 0)>=6
      and metadata.scaleSelector~=nil and type(metadata.slots)=="table"
      and (not filterRequired or validFilter(metadata.shinyFilter))) then
    if not (metadataReader and discOpener) then return false,"native model metadata unavailable" end
    local opened,disc=pcall(discOpener)
    if not opened or not disc then return false,"metadata source unavailable" end
    local ok,value,err=pcall(metadataReader.inspectSpecies,disc,n,
      type(key)=="string" and "shiny" or "normal",nil,{progress=checkpoint})
    if not ok or not value then return false,tostring(err or value or "metadata failed") end
    if filterRequired and not validFilter(value.shinyFilter) then return false,"source shiny colour parameters missing" end
    if not writeMetadataCache(key,value) then return false,"could not persist source metadata" end
    metadata=value
  end
  sourceMetadata[tostring(key)]=metadata

  -- Validate the common action semantics under the current pose guard. Compact
  -- bundles stay compressed on disk; no duplicate runtime geometry is written.
  -- Family fallbacks are source-authored, so certify the first concrete slot.
  local baked=0
  local visited={}
  for _,semantic in ipairs({"idle","damage","faint","physicalA","specialA"}) do
    local candidates=NATIVE_FALLBACKS[semantic] or {semantic}
    for _,name in ipairs(candidates) do
      if not visited[name] and disk.actionSpecs and disk.actionSpecs[name] then
        visited[name]=true
        checkpoint("Validating battle action "..n.." / "..variant.." / "..name)
        local ok,why=bakeActionSidecar(disk,name)
        if not ok then return false,"native action "..name..": "..tostring(why) end
        local compactReady=select(1,A._compactAction.specReady(disk,name,true,{}))
        if not compactReady and not A._runtimeActionCurrentGuardReady(disk,name) then
          return false,"native action "..name.." did not certify compact/current pose guard"
        end
        baked=baked+1
        break
      end
    end
  end

  if variant=="normal" then pcall(noteFullInventory,n,expectedSpeciesStamp()) end
  return true,"full-battle-cache-ready",baked
end

function A.prepareSessionModel(dex,variant,progress)
  local n=dexNumber(dex)
  if not (n and Dex.supported(n)) then return false,"unsupported species" end
  variant=variant or "normal"
  local key=modelKey(n,variant)
  local stamp=expectedSpeciesStamp()
  local checkpoint=progress or workCheckpoint
  local mobile=MOBILE_RUNTIME
  if speciesCacheReady(key) then
    local _,complete=cachedActionProfile(key)
    if not complete then
      checkpoint("Upgrading storage model "..n.." / "..variant.." for battle")
      local upgraded,why=ensureFullActionInventory(n,variant,checkpoint)
      if not upgraded then return false,why end
    end
  end
  -- Session flags are acceleration only. On a fresh startup recognize complete
  -- disk artifacts before entering any extractor/text-geometry/action bake path.
  -- Persistent validation never requires GPU residency or a save-specific list.
  if sessionPrepared[key]~=stamp then A.persistentModelState(n,variant,checkpoint) end
  if sessionPrepared[key]==stamp and A.peek("session",n,variant).resident then return true,"resident" end
  sceneErrors[key]=nil;pendingExtract[key]=nil
  if sessionPrepared[key]~=stamp then
    if not speciesCacheReady(key) then
      if not discOpener then return false,"source disc unavailable" end
      local ok,disc=pcall(discOpener)
      if not ok or not disc then return false,"source disc could not be opened" end
      local result,why=extractSource(mod,disc,n,{variant=variant,targetHeight=16,
        decodeMode=A.decodeMode,skinFix=A.skinFix,renderPassFilter=true,
        progress=checkpoint,checkpoint=checkpoint})
      if not result then return false,why end
      speciesCacheValidity[key]=nil
      if not speciesCacheReady(key) then return false,"generated source revision did not validate" end
    end
    checkpoint("Preparing model "..n.." / "..variant)
    local disk,why=loadScene(key,true,checkpoint)
    if not disk then return false,why end
    local metadata=select(1,readLua(metadataCachePath(key)))
    local filterRequired=variant=="shiny" and not Dex.rare[n]
    if not (type(metadata)=="table" and (tonumber(metadata.revision) or 0)>=4
        and type(metadata.slots)=="table" and (not filterRequired or validFilter(metadata.shinyFilter))) then
      if not (metadataReader and discOpener) then return false,"native model metadata unavailable" end
      local opened,disc=pcall(discOpener)
      if not opened or not disc then return false,"metadata source unavailable" end
      local ok,value,err=pcall(metadataReader.inspectSpecies,disc,n,
        type(key)=="string" and "shiny" or "normal",nil,{progress=checkpoint})
      if not ok or not value then return false,tostring(err or value or "metadata failed") end
      if filterRequired and not validFilter(value.shinyFilter) then return false,"source shiny colour parameters missing" end
      if not writeMetadataCache(key,value) then return false,"could not persist source metadata" end
      metadata=value
    end
    sourceMetadata[tostring(key)]=metadata
    local keys={};for name in pairs(disk.actionSpecs or {}) do keys[#keys+1]=name end;table.sort(keys)
    for _,name in ipairs(keys) do
      checkpoint("Preparing "..n.." / "..variant.." / "..name)
      local ok,err=bakeActionSidecar(disk,name)
      if not ok then return false,"native action "..name..": "..tostring(err) end
    end
    -- Verify textures too: a model marker alone is not a complete cache.
    local base=select(1,RuntimeMeshCache.readLua(runtimeBasePath(key)))
    for _,g in ipairs(base and base.groups or {}) do
      if g.texture then
        local t=g.texture
        -- Validate the same payload length without rereading/allocating every
        -- raw RGBA texture immediately before the GPU loader reads it again.
        local info=generatedInfoValidated(t.path,true)
        local expected=(tonumber(t.w) or 0)*(tonumber(t.h) or 0)*4
        if expected<=0 or not info or tonumber(info.size)~=expected then
          return false,"missing or damaged model texture: "..tostring(t.path)
        end
      end
    end
    sessionPrepared[key]=stamp
    if variant=="normal" then pcall(noteFullInventory,n,stamp) end
  end
  checkpoint("Loading shared model "..n.." / "..variant)
  local scene,err=loadScene(key,false,checkpoint)
  if not scene then return false,err end
  sceneUseSerial=sceneUseSerial+1;scene.__cbeLastUse=sceneUseSerial
  if not mobile then sessionPinned[key]=true
  else A.trimRuntimeMemory({keepRecent=ANDROID_POKEMON_RECENT,softLimit=ANDROID_POKEMON_SOFT_LIMIT}) end
  if not A.peek("session",n,variant).resident then return false,"exact colour variant not ready" end
  return true,"prepared"
end

-- Fast reload path for the player's actually-required battlers. Full
-- persistentModelState remains the authority for Quick/Full catalog accounting;
-- this path deliberately validates/repairs only the base body, exact colour,
-- metadata and action rows the current battler can use. Corrupt runtime binaries
-- still fail through loadScene/materializeSceneAction and are rebuilt from the
-- generated source payload, so this is less work rather than weaker validation.
function A.requiredModelReady(dex,variant,game,battler)
  local n=dexNumber(dex);variant=variant or (battler and monVariant(battler)) or "normal"
  if not (n and Dex.supported(n)) then return false end
  local key=modelKey(n,variant)
  -- A resident/full-session body does not prove the exact move/damage/faint rows
  -- this battler is about to use have crossed the current live action guard. Keep
  -- the narrow per-battler signature authoritative so legacy action F32 sidecars
  -- are repaired during cooperative battle prewarm instead of on first move.
  return A._requiredSignatureReady(key,A._requiredModelSignature(game,battler))
    and A.peek("required",n,variant).resident
end

-- Deliberate RETRY clears only this appearance's transient preparation state.
-- Do not evict its resident body, texture data or any unrelated model cache.
function A.retryModelPreparation(dex,variant)
  local n=dexNumber(dex)
  local key=n and modelKey(n,variant or "normal")
  if not key then return false,"invalid model identity" end
  pendingExtract[key]=nil;sceneErrors[key]=nil;requiredSessionPrepared[key]=nil
  local scene=scenes[key]
  if scene then
    scene.actionFailures={};scene._requiredActionRepairs={}
    for name in pairs(scene._bypassActionRuntime or {}) do scene._bypassActionRuntime[name]=nil end
  end
  return true,"transient model preparation failures cleared"
end

-- Repair the failed native ACTION, not the entire Pokemon or global catalog.
-- The source extractor already supports exact selective action extraction for
-- storage models; full-cache models need the same recovery boundary when an
-- existing action payload is missing, stale, unreadable or fails the pose guard.
function A._repairRequiredAction(scene,n,variant,name,checkpoint)
  if not scene then return false,"action scene unavailable" end
  if scene.actions and scene.actions[name] then
    local ready=warmActionKey(scene,name)
    if ready then return true,"already materialized" end
  end
  scene._requiredActionRepairs=scene._requiredActionRepairs or {}
  local prior=scene._requiredActionRepairs[name]
  if prior and prior.failed then return false,prior.reason end
  local function clearBypass()
    if scene._bypassActionRuntime then scene._bypassActionRuntime[name]=nil end
  end
  local detach=WorkBudget and type(WorkBudget.onCancel)=="function"
    and WorkBudget.onCancel(clearBypass) or function() end
  local oldReason=scene.actionFailures and scene.actionFailures[name]
  local function remember(ok,why,source)
    clearBypass();detach()
    why=tostring(why or (ok and "ready" or "action repair failed"))
    scene._requiredActionRepairs[name]={failed=not ok,reason=why}
    requiredSessionPrepared[scene.dex]=nil
    perf.requiredActionRepairs=(perf.requiredActionRepairs or 0)+(ok and 1 or 0)
    perf.requiredActionRepairFailures=(perf.requiredActionRepairFailures or 0)+(ok and 0 or 1)
    local note=("dex=%s variant=%s action=%s source_rebuild=%s result=%s\nprevious=%s\n%s\n")
      :format(tostring(n),tostring(variant),tostring(name),tostring(source==true),
        ok and "repaired" or "failed",tostring(oldReason or "unresolved action/alias"),why)
    if mod and mod.cache and type(mod.cache.write)=="function" then
      pcall(mod.cache.write,mod.cache,"build/model-action-recovery.txt",note)
    end
    log(ok and "info" or "warn","%s",note)
    return ok,why
  end
  local function reload(ref)
    if type(ref)~="table" then return false,"action source reference missing: "..tostring(name) end
    scene.actions=scene.actions or {};scene.actionSpecs=scene.actionSpecs or {};scene.actionFailures=scene.actionFailures or {}
    -- Only a failed/alias entry reaches this boundary. Valid unrelated action
    -- meshes and the base's borrowed Image objects remain untouched.
    if scene.actions[name] then A._releaseActionMeshes(scene.actions[name]) end
    scene.actions[name]=nil;scene.actionSpecs[name]=ref;scene.actionFailures[name]=nil
    scene._bypassActionRuntime=scene._bypassActionRuntime or {}
    scene._bypassActionRuntime[name]=true
    if RuntimeMeshCache and type(RuntimeMeshCache.invalidateLua)=="function" then
      RuntimeMeshCache.invalidateLua(runtimeActionManifestPath(scene.dex,name))
      RuntimeMeshCache.invalidateLua(runtimeActionFloorPath(scene.dex,name))
      if ref.path then RuntimeMeshCache.invalidateLua(ref.path) end
    end
    checkpoint("Revalidating native action "..n.." / "..variant.." / "..name)
    return warmActionKey(scene,name)
  end

  -- First clear the poisoned in-memory result and read its own canonical bank.
  -- This repairs transient reads/uploads and old runtime files without the disc.
  local refs=cachedBaseActionRefs(scene.dex)
  local ref=scene.actionSpecs and scene.actionSpecs[name]
    or (scene.actions and scene.actions[name] and scene.actions[name].alias and scene.actions[name])
    or refs[name]
  local ok,why=reload(ref)
  if ok then return remember(true,"canonical action revalidated",false) end
  -- A previous selective repair can have replaced a stale full-cache alias.
  -- Reuse that committed descriptor before doing source extraction again.
  local saved=readSelectiveActionRef(n,variant,name)
  if saved then
    ok,why=reload(saved)
    if ok then return remember(true,"saved selective action reused",false) end
  end
  if not (extractor and type(extractor.extractActions)=="function" and discOpener) then
    return remember(false,tostring(why).."; selective source repair unavailable",false)
  end
  local opened,disc=pcall(discOpener)
  if not opened or not disc then
    return remember(false,tostring(why).."; imported source could not be opened",false)
  end
  checkpoint("Repairing native action from source "..n.." / "..variant.." / "..name)
  local result,sourceWhy=extractSourceActions(mod,disc,n,{[name]={name}},
    {variant=variant,targetHeight=16.0,decodeMode=A.decodeMode,skinFix=A.skinFix,
      renderPassFilter=true,progress=checkpoint,checkpoint=checkpoint})
  if not result then
    return remember(false,tostring(why).."; source repair: "..tostring(sourceWhy),true)
  end
  -- extractActions commits payload then descriptor. Invalidate only known
  -- affected metadata, including stale negative host-info rows after recovery.
  local refPath=selectiveActionRefPath(n,name,variant)
  if GeneratedAssets and type(GeneratedAssets.revalidateInfo)=="function" then
    if refPath then GeneratedAssets.revalidateInfo(refPath) end
    local written=result.actions and result.actions[name]
    if written and written.path then GeneratedAssets.revalidateInfo(written.path) end
  end
  if RuntimeMeshCache and type(RuntimeMeshCache.invalidateLua)=="function" and refPath then
    RuntimeMeshCache.invalidateLua(refPath)
  end
  ref=readSelectiveActionRef(n,variant,name)
  if not ref then return remember(false,"source repair did not commit a valid action descriptor: "..name,true) end
  selectiveActionSpecs[scene.dex]=selectiveActionSpecs[scene.dex] or {}
  selectiveActionSpecs[scene.dex][name]=ref
  ok,why=reload(ref)
  if not ok then return remember(false,"rebuilt source action: "..tostring(why),true) end
  return remember(true,"exact source action rebuilt and validated",true)
end

function A._prepareRequiredAction(scene,n,variant,requested,candidates,exact,checkpoint)
  local exists=false;local reasons={}
  for _,name in ipairs(candidates or {requested}) do
    local present=scene and ((scene.actions and scene.actions[name]) or (scene.actionSpecs and scene.actionSpecs[name]))
    if present or exact then
      exists=true
      checkpoint("Preparing required action "..n.." / "..variant.." / "..name)
      local ready,why,failedName=warmActionKey(scene,name)
      if ready then return true end
      -- Follow the alias to its actual failed owner. Rebuilding only an alias
      -- manifest would leave the unreadable underlying action unchanged.
      local repaired,repairWhy=A._repairRequiredAction(scene,n,variant,failedName or name,checkpoint)
      if repaired then
        ready,why=warmActionKey(scene,name)
        if ready then return true end
      end
      reasons[#reasons+1]=tostring(name).." -> "..tostring(repairWhy or why)
    end
  end
  -- Retail species do not all own every generic family. Preserve legitimate
  -- absence, but never label a failed existing bank or exact Waza row ready.
  if not exists and not exact then return true end
  return false,table.concat(reasons,"; ")
end

function A.prepareRequiredModel(dex,variant,game,battler,progress,opts)
  local n=dexNumber(dex)
  if not (n and Dex.supported(n)) then return false,"unsupported species" end
  variant=variant or (battler and monVariant(battler)) or "normal"
  local key=modelKey(n,variant)
  local signature=A._requiredModelSignature(game,battler)
  if A._requiredSignatureReady(key,signature) and A.peek("required",n,variant).resident then return true,"resident" end
  local checkpoint=progress or workCheckpoint
  if speciesCacheReady(key) then
    local _,complete=cachedActionProfile(key)
    if not complete then
      checkpoint("Upgrading required storage model "..n.." / "..variant)
      local upgraded,why=ensureRequiredActionInventory(n,variant,game,battler,checkpoint)
      if not upgraded then return false,why end
    end
  end
  checkpoint("Loading required model "..n.." / "..variant)
  local ctx={game=game,battle={game=game},arena={figureScale=DEFAULT_FIGURE_SCALE},services={prewarm=true}}
  local actor,err=A.acquire("session-required",n,variant,{context=ctx,battler=battler,side="player",progress=checkpoint,selectiveActionsReady=true})
  if not actor then return false,err end
  local released=false
  local function releaseActor()
    if released then return end;released=true
    actor:release()
  end
  local detach=WorkBudget and type(WorkBudget.onCancel)=="function"
    and WorkBudget.onCancel(releaseActor) or function() end
  local scene=actor.scene
  local requiredNames,strictRequired=requiredActionNames(game,battler)
  for _,requested in ipairs(requiredNames) do
    local exact=strictRequired and strictRequired[requested]
    local candidates=exact and {requested} or (NATIVE_FALLBACKS[requested] or {requested})
    local ready,why=A._prepareRequiredAction(scene,n,variant,requested,candidates,exact,checkpoint)
    if not ready then
      releaseActor();detach()
      return false,"required native action "..tostring(requested)..": "..tostring(why)
    end
  end
  releaseActor();detach()
  A._noteRequiredSignature(key,signature)
  local mobile=MOBILE_RUNTIME
  if not mobile and not (opts and opts.pin==false) then sessionPinned[key]=true
  else A.trimRuntimeMemory({game=game,keepParty=6,
    keepRecent=mobile and ANDROID_POKEMON_RECENT or 6,
    softLimit=mobile and ANDROID_POKEMON_SOFT_LIMIT or 16,preserveActions=true}) end
  if not A.peek("required",n,variant).resident then
    requiredSessionPrepared[key]=nil
    return false,"exact colour variant not ready"
  end
  return true,"required-ready"
end

-- Disk-oriented model preparation used by the Mt. Battle cross-generation
-- install. A complete existing cache is accepted without loading a GPU scene.
-- A missing unit is prepared through the exact same source/metadata/action
-- pipeline as prepareSessionModel, then the newly-created scene is unpinned
-- and trimmed so a 150-260 model install cannot balloon session VRAM/RAM.
function A.preparePersistentModel(dex,variant,progress)
  local n=dexNumber(dex)
  if not (n and Dex.supported(n)) then return false,"unsupported species" end
  variant=variant or "normal"
  local ready,why=A.persistentModelState(n,variant,progress)
  if ready then return true,why or "disk-complete" end

  local ok,preparedWhy=A.prepareSessionModel(n,variant,progress)
  if not ok then return false,preparedWhy end

  local key=modelKey(n,variant)
  if key~=nil then sessionPinned[key]=nil end
  -- Preserve live actors and any models that were already pinned by ordinary
  -- gameplay, but release the just-prepared cache-install scene. Mobile already
  -- has its own tighter trim in prepareSessionModel; this second bounded trim
  -- keeps the dedicated install stable on both desktop and handheld devices.
  A.trimRuntimeMemory({keepRecent=2,softLimit=8})
  return true,"saved"
end

-- The published capability. Registering it through CBE's own documented
-- battleCompatibility host keeps discovery order-independent.
A.service={
  version=1,
  cooperativePreparation=WorkBudget~=nil, -- resident-only live acquisition; worker owns uploads
  shinySupportVersion=1, -- source-native variants; older universal-tint providers lack this flag
  portable=true,
  priority=100000,
  worldUnits=false,
  selected=function(context)
    local settings=V.BattleSettings
    if settings and type(settings.pokemonModelsEnabled)=="function" then
      local game=(context and context.game) or (context and context.battle and context.battle.game) or (mod and mod.game)
      local ok,value=pcall(settings.pokemonModelsEnabled,game)
      if ok then return value~=false end
    end
    return true
  end,
  available=function(source,dex) return A.available(source,dex) end,
  peek=function(source,dex,variant) return A.peek(source,dex,variant) end,
  acquireCached=function(source,dex,variant,opts) return A.acquireCached(source,dex,variant,opts) end,
  acquire=function(source,dex,variant,opts) return A.acquire(source,dex,variant,opts) end,
  withRenderer=function(vp,cb,opts) return A.withRenderer(vp,cb,opts) end,
  status=function() return A.status() end,
}

-- Test-only hook. F6/F10 both go through love.keyboard, which a headless test
-- harness doesn't have, so this lets the actual re-decode-in-place logic be
-- exercised directly instead of only through a GUI key press.
A._test={materializeSceneAction=materializeSceneAction,warmActionKey=warmActionKey,refreshLiveActors=refreshLiveActors,moveSlot=moveSlot,Actor=Actor,loadScene=loadScene,bakeActionSidecar=bakeActionSidecar,runtimeActionSidecarReady=runtimeActionSidecarReady,runtimeActionCurrentGuardReady=A._runtimeActionCurrentGuardReady,
  inspectActionPoseRows=A._inspectActionPoseRows,actionPoseGuardVersion=A._actionPoseGuardVersion,
  encodedFeetInchesMeters=encodedFeetInchesMeters,dexHeightMeters=dexHeightMeters,
  normalizedPresentationRelative=normalizedPresentationRelative,geometryPresentation=geometryPresentation,presentationScalePolicy=A.presentationScalePolicy,actorWorldScale=actorWorldScale,
  compactMetadataLua=compactMetadataLua,writeMetadataCache=writeMetadataCache,cachedActionProfile=cachedActionProfile,ensureFullActionInventory=ensureFullActionInventory,
  ensureActionSubset=ensureActionSubset,ensureRequiredActionInventory=ensureRequiredActionInventory,mergeSelectiveActionSpecs=mergeSelectiveActionSpecs,
  compactAction=A._compactAction,
  requiredActionKeys=requiredActionKeys,requiredActionNames=requiredActionNames,sourceMoveNumber=sourceMoveNumber,resolveSceneAction=resolveSceneAction,
  fullInventoryPath=FULL_INVENTORY_PATH,noteFullInventory=noteFullInventory,buildHardCacheRows=buildHardCacheRows,
  flushFullInventory=flushFullInventory,materialTexgenReady=materialTexgenReady,speciesCacheReady=speciesCacheReady,legacyTexgenRepairDex=LEGACY_TEXGEN_REPAIR_DEX,
  ensureShader=ensureShader,vertexShader=VERTEX,pixelShader=PIXEL,
  inventoryStats=function() local out={};for k,v in pairs(inventoryStats)do out[k]=v end;return out end}

return A
