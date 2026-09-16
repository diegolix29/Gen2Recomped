local V=...
local FSYS=V.FSYS
local PortableMusyX=V.PortableMusyX
local Fidelity=V.AudioFidelity
local function renderQuality(mod)return Fidelity and Fidelity.resolve(mod) or "fast" end
local A={}
local serial=0

-- Historical loopFrame values are retained only for the non-production Amuse
-- reference helper at the bottom of this file. Canonical v9 renderAll ignores
-- them and derives loop boundaries directly from each GC6E01 SNG header/region.
local THEMES={
  {source="battle5_song",setup=51,loopFrame=7181,intro="assets/audio/themes/normal_battle_intro.wav",loop="assets/audio/themes/normal_battle_loop.wav"},
  {source="battle8_song",setup=4,loopFrame=493908,intro="assets/audio/themes/first_battle_intro.wav",loop="assets/audio/themes/first_battle_loop.wav"},
  {source="battle7_song",setup=72,loopFrame=322765,intro="assets/audio/themes/cipher_peon_intro.wav",loop="assets/audio/themes/cipher_peon_loop.wav"},
  {source="mirrorbo_song",setup=65,loopFrame=9575,intro="assets/audio/themes/miror_b_intro.wav",loop="assets/audio/themes/miror_b_loop.wav"},
  {source="battle9plus_song",setup=49,loopFrame=2311138,intro="assets/audio/themes/cipher_admin_intro.wav",loop="assets/audio/themes/cipher_admin_loop.wav"},
  {source="miraclebo_song",setup=44,loopFrame=9575,intro="assets/audio/themes/mirakle_b_intro.wav",loop="assets/audio/themes/mirakle_b_loop.wav"},
  {source="battle2_song",setup=24,loopFrame=573696,intro="assets/audio/themes/semifinal_intro.wav",loop="assets/audio/themes/semifinal_loop.wav"},
  {source="battle6_song",setup=76,loopFrame=391138,intro="assets/audio/themes/final_battle_intro.wav",loop="assets/audio/themes/final_battle_loop.wav"},
  {source="tool_battle1_song",setup=20,loopFrame=468525,intro="assets/audio/themes/link_1_intro.wav",loop="assets/audio/themes/link_1_loop.wav"},
  {source="tool_battle2_song",setup=21,loopFrame=482190,intro="assets/audio/themes/link_2_intro.wav",loop="assets/audio/themes/link_2_loop.wav"},
  {source="tool_battle3_song",setup=22,loopFrame=444292,intro="assets/audio/themes/link_3_intro.wav",loop="assets/audio/themes/link_3_loop.wav"},
}

-- Field/menu music is intentionally a separate cache from the canonical
-- 24-asset battle soundtrack above.  Adding these rows to THEMES would force
-- every existing v9 soundtrack cache to be discarded and rebuilt just to add
-- two small source songs.  Keep them incremental instead: `pokecen_song` is
-- the user's optional Pokemon Center replacement, while `worldmap_song` is the
-- retail Colosseum main-menu sequence requested for the Battle 100 setup hub.
-- The setup ids are the songs' real bgm_archive.fsys indices.
local ENVIRONMENT_THEMES={
  {id="pokemon_center",source="pokecen_song",setup=60,
    intro="assets/audio/environment/pokemon_center_intro.wav",
    loop="assets/audio/environment/pokemon_center_loop.wav"},
  {id="mt_battle_lobby",source="worldmap_song",setup=5,
    intro="assets/audio/environment/mt_battle_main_menu_intro.wav",
    loop="assets/audio/environment/mt_battle_main_menu_loop.wav"},
}


local ONE_SHOTS={
  -- bgm_archive.fsys index/setup 9 is the retail Colosseum Snag-success jingle.
  -- Render it from the user's own disc exactly like the existing battle themes.
  {source="me_snatch_song",setup=9,output="assets/audio/capture/me_snatch.wav"},
}

local function memberMap(archive)
  local out={}
  for _,entry in ipairs(archive:list()) do out[entry.name:lower()]=entry end
  return out
end

local function requiredMember(archive,map,name,archiveName)
  local entry=map[name:lower()]
  assert(entry,("audio source %s/%s: member missing"):format(archiveName,name))
  local ok,data=pcall(archive.extract,archive,entry,{maxOutput=64*1024*1024})
  assert(ok,("audio source %s/%s: %s"):format(archiveName,name,tostring(data)))
  assert(type(data)=="string" and #data>0,("audio source %s/%s: empty decoded member"):format(archiveName,name))
  return data
end

local function directFile(disc,name)
  local file=disc:file(name)
  assert(file,("audio source disc/%s: file missing"):format(name))
  local ok,data=pcall(disc.readFile,disc,file)
  assert(ok,("audio source disc/%s: %s"):format(name,tostring(data)))
  assert(type(data)=="string" and #data>0,("audio source disc/%s: empty file"):format(name))
  return data
end

local PRESERVED_AUDIO_ROOT="cache/preserved/audio/v1/"
local function preservedAudioFingerprint(bytes)
  -- Two inexpensive deterministic rolling checksums + length keep preservation
  -- names content-addressed without depending on host crypto/bit libraries.
  -- This path is touched only when an automatic fidelity upgrade is about to
  -- replace an already-saved derivative, never during the normal cached path.
  local a,b,c=1,0,0
  for start=1,#bytes,4096 do
    for i=start,math.min(#bytes,start+4095) do
      local v=bytes:byte(i)
      a=(a+v)%65521;b=(b+a)%65521;c=(c*257+v+1)%2147483647
    end
  end
  return string.format("%04x%04x-%08x-%d",b,a,c,#bytes)
end
local function preservedAudioPath(path,bytes)
  local safe=tostring(path or "asset"):gsub("[^%w%._%-]","_")
  return PRESERVED_AUDIO_ROOT..safe.."."..preservedAudioFingerprint(bytes)..".bin"
end
local function preserveExistingAsset(mod,path,incoming)
  if not (mod and mod.cache and type(mod.cache.read)=="function" and type(mod.cache.write)=="function") then return nil,false end
  local ok,old=pcall(mod.cache.read,mod.cache,path)
  if not ok or type(old)~="string" or old==incoming then return nil,false end
  local archive=preservedAudioPath(path,old)
  local rok,retained=pcall(mod.cache.read,mod.cache,archive)
  if rok and retained==old then return archive,false end
  -- The dual checksum makes a collision vanishingly unlikely, but never destroy
  -- a previously preserved byte stream even if one occurs. Allocate a stable
  -- numbered sibling instead of overwriting it.
  if rok and type(retained)=="string" and retained~=old then
    local base=archive;local n=2
    repeat
      archive=base.."."..n;n=n+1
      local cok,current=pcall(mod.cache.read,mod.cache,archive)
      if not cok or current==nil or current==old then retained=current;break end
    until n>10000
    assert(n<=10001,"audio preservation namespace exhausted")
    if retained==old then return archive,false end
  end
  local wok,aerr=pcall(mod.cache.write,mod.cache,archive,old)
  assert(wok and aerr~=false and aerr~=nil,("audio preservation write failed: %s"):format(archive))
  local vok,verify=pcall(mod.cache.read,mod.cache,archive)
  assert(vok and verify==old,("audio preservation readback failed: %s"):format(archive))
  return archive,true
end
local function writeAsset(mod,path,bytes,generated)
  assert(type(bytes)=="string" and #bytes>=44,("audio output %s: renderer returned no WAV data"):format(path))
  assert(bytes:sub(1,4)=="RIFF" and bytes:sub(9,12)=="WAVE",("audio output %s: renderer returned an invalid WAV"):format(path))
  preserveExistingAsset(mod,path,bytes)
  local ok,err=mod.cache:write(path,bytes)
  assert(ok,("audio output %s: cache write failed: %s"):format(path,tostring(err or "unknown error")))
  if generated then generated[#generated+1]=path end
end


local PORTABLE_MARKER="cbe-audio-portable=core2\nsource=GC6E01\ntransition=dsp92\ndecoder=fresh-history\n"
local PORTABLE_FULL_MARKER="cbe-audio-portable=9\nsource=GC6E01\nassets=24\nrate=48000\nrenderer=lua-musyx-canonical-v9-cross-platform-48k\nloop=source-sng-header-plus-region-sentinel\n"
local PORTABLE_RATE=48000
local BOSS_CUE="assets/audio/intro/fanfare00.wav"
local BOSS_MARKER="build/boss_fanfare_v1.complete"
local BOSS_ID="GC6E01:fanfare00_song:setup12:portable-v9:48000"
function A.bossIntroReady(mod)
  local ok,marker=pcall(mod.cache.read,mod.cache,BOSS_MARKER)
  local prefix=BOSS_ID.."\nbytes="
  if not ok or type(marker)~="string" or marker:sub(1,#prefix)~=prefix then return false end
  local size=tonumber(marker:sub(#prefix+1))
  if not size or size<=44 or not (mod.cache and type(mod.cache.info)=="function") then return false end
  -- The completion marker is written only after runBossIntro has read back the
  -- exact rendered WAV bytes. On later boots use file metadata to prove that the
  -- committed object is still present at the same byte count instead of streaming
  -- the whole fanfare through the Android cache bridge. BossIntro.openCue() reads
  -- and validates RIFF/WAVE bytes at actual use, so equal-size external damage
  -- still fails open at the presentation boundary without forcing source render
  -- during startup. Portable backends that expose file presence without a size
  -- retain the same committed-marker contract used by the v9 soundtrack ledger.
  local worked,info=pcall(mod.cache.info,mod.cache,BOSS_CUE)
  if not worked or type(info)~="table" or (info.type and info.type~="file") then return false end
  local actual=tonumber(info.size)
  return actual==nil or actual==size
end
function A.runBossIntro(mod,disc,progress,generated)
  if A.bossIntroReady(mod) then return true end
  generated=generated or {};progress=progress or function()end
  progress("BOSS INTRO / Colosseum fanfare00",0,1)
  local common=FSYS.open(disc,assert(disc:file("common.fsys")))
  local bgm=FSYS.open(disc,assert(disc:file("bgm_archive.fsys")))
  local cm,bm=memberMap(common),memberMap(bgm)
  local ctx=PortableMusyX.prepare({music={
    proj=requiredMember(common,cm,"snd_music_proj","common.fsys"),
    pool=requiredMember(common,cm,"snd_music_pool","common.fsys"),
    sdir=requiredMember(common,cm,"snd_music_sdir","common.fsys"),samp=directFile(disc,"snd_music.samp")}})
  local wav,_,stats=PortableMusyX.renderSong(ctx,requiredMember(bgm,bm,"fanfare00_song","bgm_archive.fsys"),12,nil,48000,nil,{quality=renderQuality(mod)})
  assert(stats.peak>0.00001,"boss intro render produced silence")
  writeAsset(mod,BOSS_CUE,wav,generated)
  assert(mod.cache:read(BOSS_CUE)==wav,"boss intro cache read-back failed")
  assert(mod.cache:write(BOSS_MARKER,BOSS_ID.."\nbytes="..#wav));generated[#generated+1]=BOSS_MARKER
  if Fidelity then Fidelity.record(mod,BOSS_CUE,wav,renderQuality(mod),generated) end
  progress("BOSS INTRO / cached source fanfare",1,1)
  return true
end
local PORTABLE_FULL_PATH=".cbe-audio-portable-v9.complete"
-- Android cache backends have proven less reliable with tiny hidden marker
-- files than with normal generated/build entries. Keep a redundant non-hidden
-- marker and migration journal so a process restart can never turn a valid or
-- partially completed soundtrack into a destructive full recache.
local PORTABLE_FULL_FALLBACK_PATH="build/audio_portable_v9.complete"
local PORTABLE_PENDING_PATH=".cbe-audio-portable-v9.pending"
local PORTABLE_MIGRATION_PATH="build/audio_portable_v9.migrating"
local PORTABLE_LEDGER_PATH="build/audio_portable_v9_assets.lua"
local ENVIRONMENT_MARKER_PATH="build/audio_environment_v1.complete"
local ENVIRONMENT_MARKER="cbe-audio-environment=1\nsource=GC6E01\nassets=4\nrate=48000\nrenderer=lua-musyx-canonical-v9-cross-platform-48k\n"
local LEGACY_V2_PATH=".cbe-audio-portable-v2.complete"
local LEGACY_V3_PATH=".cbe-audio-portable-v3.complete"
local LEGACY_V4_PATH=".cbe-audio-portable-v4.complete"
local LEGACY_V4_FALLBACK_PATH="build/audio_portable_v4.complete"
local LEGACY_V5_PATH=".cbe-audio-portable-v5.complete"
local LEGACY_V5_FALLBACK_PATH="build/audio_portable_v5.complete"
local LEGACY_V6_PATH=".cbe-audio-portable-v6.complete"
local LEGACY_V6_FALLBACK_PATH="build/audio_portable_v6.complete"
local LEGACY_V7_PATH=".cbe-audio-portable-v7.complete"
local LEGACY_V7_FALLBACK_PATH="build/audio_portable_v7.complete"
local LEGACY_V7_PENDING_PATH=".cbe-audio-portable-v7.pending"
local LEGACY_V7_MIGRATION_PATH="build/audio_portable_v7.migrating"

-- The battle-transition cue is a raw GameCube DSP-ADPCM sample, not a MusyX
-- sequence. Decode it directly in portable Lua so Android can generate real
-- Colosseum audio without cmd.exe/amuserender. Keep this path bounded: read
-- only the sample's ADPCM frame range from snd_se_battle.samp.
local function u16be(s,o)local a,b=s:byte(o,o+1);assert(b,"truncated u16be");return a*256+b end
local function u32be(s,o)local a,b,c,d=s:byte(o,o+3);assert(d,"truncated u32be");return a*16777216+b*65536+c*256+d end
local function s16be(s,o)local v=u16be(s,o);return v>=32768 and v-65536 or v end
local function le16(v)v=v%65536;return string.char(v%256,math.floor(v/256)%256)end
local function le32(v)v=v%4294967296;return string.char(v%256,math.floor(v/256)%256,math.floor(v/65536)%256,math.floor(v/16777216)%256)end
local function wav16(raw,rate,channels)
  local n=#raw
  return "RIFF"..le32(36+n).."WAVEfmt "..le32(16)..le16(1)..le16(channels)..le32(rate)
    ..le32(rate*channels*2)..le16(channels*2)..le16(16).."data"..le32(n)..raw
end
local function dspEntry(sdir,sampleId,source)
  for o=1,#sdir-31,32 do
    local id=u16be(sdir,o);if id==65535 then break end
    if id==sampleId then
      local e={offset=u32be(sdir,o+4),rate=u16be(sdir,o+14),rawCount=u32be(sdir,o+16),adpcm=u32be(sdir,o+28)}
      local format=math.floor(e.rawCount/16777216);e.count=e.rawCount%16777216
      assert(format==0 or format==1,source..": sample is not GameCube DSP ADPCM (format "..format..")")
      assert(e.adpcm>0 and e.adpcm+39<=#sdir,source..": DSP coefficient block exceeds SDIR")
      return e
    end
  end
  error(source..": sample id "..sampleId.." missing from SDIR",0)
end
local function decodeDspSlice(sdir,samp,e,source)
  local expected=math.ceil(e.count/14)*8
  assert(#samp>=expected,source..": sample data is truncated")
  local coefs={}
  for i=0,7 do coefs[i]={s16be(sdir,e.adpcm+9+i*4),s16be(sdir,e.adpcm+11+i*4)} end
  -- Fresh DSP playback starts with predictor history (0,0). The SDIR history
  -- belongs to loop turnover state and must not color the first transient.
  local prev2,prev1=0,0
  local parts,bytes,done={},{},0
  while done<e.count do
    local frame=1+math.floor(done/14)*8
    local header=samp:byte(frame);assert(header,source..": missing DSP frame")
    local predictor=math.floor(header/16);local exponent=header%16
    assert(predictor<=7,source..": invalid DSP predictor "..predictor)
    local c1,c2=coefs[predictor][1],coefs[predictor][2]
    local n=math.min(14,e.count-done)
    for i=0,n-1 do
      local packed=samp:byte(frame+1+math.floor(i/2));assert(packed,source..": truncated DSP nibble")
      local nibble=(i%2==0) and math.floor(packed/16) or packed%16;if nibble>=8 then nibble=nibble-16 end
      local sample=math.floor((nibble*2^exponent*2048+1024+c1*prev1+c2*prev2)/2048)
      if sample>32767 then sample=32767 elseif sample< -32768 then sample=-32768 end
      prev2,prev1=prev1,sample;local v=sample%65536
      bytes[#bytes+1]=string.char(v%256,math.floor(v/256))
      if #bytes>=4096 then parts[#parts+1]=table.concat(bytes);bytes={} end
    end
    done=done+n
  end
  if #bytes>0 then parts[#parts+1]=table.concat(bytes) end
  return wav16(table.concat(parts),e.rate,1)
end
local function cacheRead(mod,path)
  if not (mod and mod.cache and type(mod.cache.read)=="function") then return nil end
  local ok,v=pcall(mod.cache.read,mod.cache,path);return ok and type(v)=="string" and v or nil
end
local function cacheWrite(mod,path,data,generated)
  local ok,a,b=pcall(mod.cache.write,mod.cache,path,data)
  assert(ok and a~=false and a~=nil,"audio cache write failed: "..path.." / "..tostring(b or a))
  if generated then generated[#generated+1]=path end
end
local function cacheInfo(mod,path,verifyMissingSize)
  if not (mod and mod.cache and type(mod.cache.info)=="function") then return nil end
  local ok,v=pcall(mod.cache.info,mod.cache,path)
  if not (ok and type(v)=="table") then return nil end
  -- Gen1Recomp portable mode intentionally exposes only {type="file"} from
  -- its io.* filesystem. During a new v9 commit, read the just-written asset
  -- back once so the ledger still records a proven byte count. Completed v9
  -- caches can later use the durable ledger + existence contract without
  -- rereading tens of MiB of soundtrack data on every boot.
  if verifyMissingSize and tonumber(v.size)==nil then
    local bytes=cacheRead(mod,path)
    if type(bytes)~="string" then return nil end
    v.size=#bytes
  end
  return v
end
local function cacheDelete(mod,path)
  if not (mod and mod.cache and type(mod.cache.delete)=="function") then return false end
  local ok,v=pcall(mod.cache.delete,mod.cache,path);return ok and v~=false
end
local PORTABLE_ASSETS={}
for _,theme in ipairs(THEMES) do PORTABLE_ASSETS[#PORTABLE_ASSETS+1]=theme.intro;PORTABLE_ASSETS[#PORTABLE_ASSETS+1]=theme.loop end
for _,shot in ipairs(ONE_SHOTS) do PORTABLE_ASSETS[#PORTABLE_ASSETS+1]=shot.output end
PORTABLE_ASSETS[#PORTABLE_ASSETS+1]="assets/audio/colosseum_battle_transition.wav"
local function readPortableLedger(mod)
  local raw=cacheRead(mod,PORTABLE_LEDGER_PATH)
  local chunk=type(raw)=="string" and load(raw,"@generated/"..PORTABLE_LEDGER_PATH) or nil
  if not chunk then return {version=9,assets={}} end
  local ok,value=pcall(chunk)
  if not ok or type(value)~="table" or tonumber(value.version)~=9 or type(value.assets)~="table" then
    return {version=9,assets={}}
  end
  return value
end
local function encodePortableLedger(ledger)
  local keys={}
  for path,row in pairs((ledger and ledger.assets) or {}) do
    if type(path)=="string" and type(row)=="table" and tonumber(row.size) then keys[#keys+1]=path end
  end
  table.sort(keys)
  local out={"return {version=9,assets={\n"}
  for _,path in ipairs(keys) do
    local row=ledger.assets[path]
    out[#out+1]=(string.format("  [%q]={size=%d},\n",path,math.floor(tonumber(row.size) or 0)))
  end
  out[#out+1]="}}\n"
  return table.concat(out)
end
local function writePortableLedger(mod,ledger)
  cacheWrite(mod,PORTABLE_LEDGER_PATH,encodePortableLedger(ledger),nil)
end
local function recordPortableAsset(mod,ledger,path,size)
  ledger=ledger or readPortableLedger(mod);ledger.assets=ledger.assets or {}
  ledger.assets[path]={size=math.floor(tonumber(size) or 0)}
  writePortableLedger(mod,ledger)
  return ledger
end
local function portableAssetReady(mod,path,ledger,strict)
  ledger=ledger or readPortableLedger(mod)
  local row=ledger.assets and ledger.assets[path]
  local expected=row and tonumber(row.size)
  if not expected or expected<44 then return false end
  local info=cacheInfo(mod,path,strict==true)
  if not info then return false end
  local actual=tonumber(info.size)
  -- A metadata-less portable backend is accepted only for a previously
  -- committed asset whose exact size already lives in the v9 ledger. Strict
  -- generation/promotion paths always force a read-back size verification.
  return actual~=nil and actual==expected or (actual==nil and strict~=true)
end
local function portableAssetsReady(mod,strict)
  local ledger=readPortableLedger(mod)
  for _,path in ipairs(PORTABLE_ASSETS) do if not portableAssetReady(mod,path,ledger,strict) then return false end end
  return true
end
local ENVIRONMENT_ASSETS={}
for _,theme in ipairs(ENVIRONMENT_THEMES) do
  ENVIRONMENT_ASSETS[#ENVIRONMENT_ASSETS+1]=theme.intro
  ENVIRONMENT_ASSETS[#ENVIRONMENT_ASSETS+1]=theme.loop
end
local function environmentAssetsReady(mod,strict)
  local ledger=readPortableLedger(mod)
  for _,path in ipairs(ENVIRONMENT_ASSETS) do
    if not portableAssetReady(mod,path,ledger,strict) then return false end
  end
  return true
end
function A.environmentReady(mod)
  return cacheRead(mod,ENVIRONMENT_MARKER_PATH)==ENVIRONMENT_MARKER
    and environmentAssetsReady(mod,false)
end

-- Incremental source render for the two non-battle themes the overhaul owns.
-- This deliberately reuses the v9 byte-size ledger so interrupted writes are
-- rejected with the same portable-filesystem rules as the main soundtrack,
-- while preserving every already-rendered battle WAV.
function A.runEnvironment(mod,disc,progress,generated)
  progress=progress or function()end
  assert(PortableMusyX and type(PortableMusyX.prepare)=="function"
    and type(PortableMusyX.renderSong)=="function",
    "portable MusyX environment renderer unavailable")
  if A.environmentReady(mod) then
    progress("AUDIO ENVIRONMENT 4/4 / cached Pokemon Center + Mt. Battle main menu",4,4)
    return {ready=true,complete=4,total=4,cached=true,rate=PORTABLE_RATE}
  end

  local common=FSYS.open(disc,assert(disc:file("common.fsys"),"audio source common.fsys: archive missing"))
  local bgm=FSYS.open(disc,assert(disc:file("bgm_archive.fsys"),"audio source bgm_archive.fsys: archive missing"))
  local commonMembers,bgmMembers=memberMap(common),memberMap(bgm)
  local ctx=PortableMusyX.prepare({music={
    proj=requiredMember(common,commonMembers,"snd_music_proj","common.fsys"),
    pool=requiredMember(common,commonMembers,"snd_music_pool","common.fsys"),
    sdir=requiredMember(common,commonMembers,"snd_music_sdir","common.fsys"),
    samp=directFile(disc,"snd_music.samp"),
  }})
  local ledger=readPortableLedger(mod)
  local complete=0
  for _,theme in ipairs(ENVIRONMENT_THEMES) do
    local introReady=portableAssetReady(mod,theme.intro,ledger,false)
    local loopReady=portableAssetReady(mod,theme.loop,ledger,false)
    if introReady and loopReady then
      complete=complete+2
    else
      progress(("AUDIO ENVIRONMENT %d/4 / %s"):format(complete,theme.source),complete,4)
      local intro,loop,stats=PortableMusyX.renderSong(ctx,
        requiredMember(bgm,bgmMembers,theme.source,"bgm_archive.fsys"),
        theme.setup,true,PORTABLE_RATE,function(frame,total)
          local fraction=(tonumber(total) or 0)>0 and (tonumber(frame) or 0)/tonumber(total) or 0
          progress(("AUDIO ENVIRONMENT %d/4 / %s / %d%%"):format(
            complete,theme.source,math.floor(math.max(0,math.min(1,fraction))*100)),
            complete+math.max(0,math.min(.95,fraction))*2,4)
        end,{quality=renderQuality(mod)})
      assert(type(stats)=="table" and (tonumber(stats.peak) or 0)>0.00001,
        theme.source..": portable synthesis produced silence")
      for _,row in ipairs({{path=theme.intro,bytes=intro},{path=theme.loop,bytes=loop}}) do
        writeAsset(mod,row.path,row.bytes,generated)
        local committed=cacheInfo(mod,row.path,true)
        assert(committed and tonumber(committed.size)==#row.bytes,
          "audio output "..row.path..": committed size does not match rendered WAV")
        ledger=recordPortableAsset(mod,ledger,row.path,#row.bytes)
        assert(portableAssetReady(mod,row.path,ledger,true),
          "audio output "..row.path..": committed size does not match v9 asset ledger")
        if Fidelity then Fidelity.record(mod,row.path,row.bytes,renderQuality(mod),generated) end
        complete=complete+1
        progress(("AUDIO ENVIRONMENT %d/4 / %s"):format(complete,theme.source),complete,4)
      end
      intro=nil;loop=nil
      if collectgarbage then pcall(collectgarbage,"step",300) end
    end
  end
  assert(complete==4 and environmentAssetsReady(mod,true),
    "Pokemon Center / Mt. Battle main-menu audio cache did not verify 4/4")
  cacheWrite(mod,ENVIRONMENT_MARKER_PATH,ENVIRONMENT_MARKER,generated)
  return {ready=true,complete=4,total=4,rate=PORTABLE_RATE,
    renderer="portable Lua MusyX canonical v9 / incremental environment source"}
end
local function generatedManifestMentions(mod,path)
  local raw=cacheRead(mod,"build/generated_paths.lua")
  return type(raw)=="string" and raw:find(path,1,true)~=nil
end
local function writePortableFullMarkers(mod,generated)
  cacheWrite(mod,PORTABLE_FULL_PATH,PORTABLE_FULL_MARKER,generated)
  cacheWrite(mod,PORTABLE_FULL_FALLBACK_PATH,PORTABLE_FULL_MARKER,generated)
end
function A.portableCoreReady(mod)
  local marker=cacheRead(mod,".cbe-audio-portable-v1.complete")
  local wav=cacheRead(mod,"assets/audio/colosseum_battle_transition.wav")
  return marker==PORTABLE_MARKER and type(wav)=="string" and #wav>=44 and wav:sub(1,4)=="RIFF" and wav:sub(9,12)=="WAVE"
end
function A.runPortableCore(mod,disc,progress,generated)
  progress=progress or function()end
  if A.portableCoreReady(mod) then
    progress("AUDIO PORTABLE 1/1 / cached Colosseum battle transition",1,1)
    return {ready=true,complete=1,total=1,renderer="portable Lua DSP-ADPCM",cached=true}
  end
  progress("AUDIO PORTABLE 0/1 / locating battle DSP sample",0,1)
  local commonFile=assert(disc:file("common.fsys"),"audio source common.fsys: archive missing")
  local common=FSYS.open(disc,commonFile);local members=memberMap(common)
  local source="common.fsys/snd_se_battle_sdir + disc/snd_se_battle.samp / sample 92 (SFX 0x00CC)"
  local sdir=requiredMember(common,members,"snd_se_battle_sdir","common.fsys")
  local e=dspEntry(sdir,92,source)
  local sampFile=assert(disc:file("snd_se_battle.samp"),"audio source disc/snd_se_battle.samp: file missing")
  local byteCount=math.ceil(e.count/14)*8
  assert(e.offset+byteCount<=sampFile.size,source..": DSP sample exceeds SAMP")
  local samp=disc:readFile(sampFile,e.offset,byteCount)
  local wav=decodeDspSlice(sdir,samp,e,source)
  writeAsset(mod,"assets/audio/colosseum_battle_transition.wav",wav,generated)
  cacheWrite(mod,".cbe-audio-portable-v1.complete",PORTABLE_MARKER,generated)
  progress("AUDIO PORTABLE 1/1 / Colosseum battle transition cached",1,1)
  return {ready=true,complete=1,total=1,renderer="portable Lua DSP-ADPCM",sampleBytes=byteCount}
end

function A.portableFullReady(mod)
  if not A.portableCoreReady(mod) then return false end
  local primary=cacheRead(mod,PORTABLE_FULL_PATH)
  local fallback=cacheRead(mod,PORTABLE_FULL_FALLBACK_PATH)
  if primary==PORTABLE_FULL_MARKER or fallback==PORTABLE_FULL_MARKER then
    if not portableAssetsReady(mod,false) then return false end
    -- Self-heal whichever redundant completion marker disappeared.
    if primary~=PORTABLE_FULL_MARKER then pcall(cacheWrite,mod,PORTABLE_FULL_PATH,PORTABLE_FULL_MARKER,nil) end
    if fallback~=PORTABLE_FULL_MARKER then pcall(cacheWrite,mod,PORTABLE_FULL_FALLBACK_PATH,PORTABLE_FULL_MARKER,nil) end
    return true
  end
  -- A pending journal is promoted only after strict read-back verification of
  -- all 24 assets. This preserves interrupted-write detection even when the
  -- host portable filesystem cannot report file sizes.
  local migrating=cacheRead(mod,PORTABLE_MIGRATION_PATH)==PORTABLE_FULL_MARKER
  local pending=cacheRead(mod,PORTABLE_PENDING_PATH)==PORTABLE_FULL_MARKER
  if (migrating or pending) and portableAssetsReady(mod,true) then
    pcall(writePortableFullMarkers,mod,nil)
    cacheDelete(mod,PORTABLE_PENDING_PATH);cacheDelete(mod,PORTABLE_MIGRATION_PATH)
    return true
  end
  return false
end

local function portablePayload(mod,disc)
  local commonFile=assert(disc:file("common.fsys"),"audio source common.fsys: archive missing")
  local bgmFile=assert(disc:file("bgm_archive.fsys"),"audio source bgm_archive.fsys: archive missing")
  local common=FSYS.open(disc,commonFile);local bgm=FSYS.open(disc,bgmFile)
  local commonMembers,bgmMembers=memberMap(common),memberMap(bgm)
  local ledger=readPortableLedger(mod)
  local songs={}
  for _,theme in ipairs(THEMES) do
    if not portableAssetReady(mod,theme.intro,ledger,false) or not portableAssetReady(mod,theme.loop,ledger,false) then
      songs[#songs+1]={source="bgm_archive.fsys/"..theme.source,setup=theme.setup,
        introPath=theme.intro,loopPath=theme.loop,sequence=requiredMember(bgm,bgmMembers,theme.source,"bgm_archive.fsys")}
    end
  end
  local oneShots={}
  for _,shot in ipairs(ONE_SHOTS) do
    if not portableAssetReady(mod,shot.output,ledger,false) then
      oneShots[#oneShots+1]={source="bgm_archive.fsys/"..shot.source,setup=shot.setup,outputPath=shot.output,
        sequence=requiredMember(bgm,bgmMembers,shot.source,"bgm_archive.fsys")}
    end
  end
  return {quality=renderQuality(mod),sampleRate=PORTABLE_RATE,songs=songs,oneShots=oneShots,music={
    proj=requiredMember(common,commonMembers,"snd_music_proj","common.fsys"),
    pool=requiredMember(common,commonMembers,"snd_music_pool","common.fsys"),
    sdir=requiredMember(common,commonMembers,"snd_music_sdir","common.fsys"),
    samp=directFile(disc,"snd_music.samp"),
  }}
end

function A.runPortableFull(mod,disc,progress,generated)
  progress=progress or function()end
  assert(PortableMusyX and type(PortableMusyX.renderAll)=="function","portable MusyX renderer module unavailable")
  if A.portableFullReady(mod) then
    progress("AUDIO PORTABLE 24/24 / cached Colosseum soundtrack canonical v9",24,24)
    return {ready=true,complete=24,total=24,renderer="portable Lua MusyX canonical v9 / cross-platform / 48 kHz",cached=true,rate=PORTABLE_RATE}
  end

  -- v9 is a one-time audio-only migration. It keeps the corrected 48 kHz source-mix
  -- semantics from v7, but makes this Portable MusyX path the ONLY authoritative
  -- soundtrack renderer on every OS. Migration is transactional: once a v9 journal
  -- exists, a restart resumes missing WAVs and never deletes valid partial work.
  -- Every pre-v9 theme WAV whose provenance cannot be certified is regenerated so
  -- a Windows Amuse/portable mixed cache can never be promoted into the cross-
  -- platform parity contract. Crucially, writeAsset content-addresses and preserves
  -- every previous byte stream before replacing the runtime pathname: fidelity
  -- upgrades are non-destructive and can never force reacquisition of saved output.
  local pendingV9=cacheRead(mod,PORTABLE_PENDING_PATH)==PORTABLE_FULL_MARKER
  local migratingV9=cacheRead(mod,PORTABLE_MIGRATION_PATH)==PORTABLE_FULL_MARKER
  if not pendingV9 and not migratingV9 then
    local legacyV2=cacheRead(mod,LEGACY_V2_PATH)~=nil
    local legacyV3=cacheRead(mod,LEGACY_V3_PATH)~=nil or generatedManifestMentions(mod,LEGACY_V3_PATH)
    local legacyV4=cacheRead(mod,LEGACY_V4_PATH)~=nil or cacheRead(mod,LEGACY_V4_FALLBACK_PATH)~=nil
      or generatedManifestMentions(mod,LEGACY_V4_PATH) or generatedManifestMentions(mod,LEGACY_V4_FALLBACK_PATH)
    local legacyV5=cacheRead(mod,LEGACY_V5_PATH)~=nil or cacheRead(mod,LEGACY_V5_FALLBACK_PATH)~=nil
      or generatedManifestMentions(mod,LEGACY_V5_PATH) or generatedManifestMentions(mod,LEGACY_V5_FALLBACK_PATH)
    local legacyV6=cacheRead(mod,LEGACY_V6_PATH)~=nil or cacheRead(mod,LEGACY_V6_FALLBACK_PATH)~=nil
      or generatedManifestMentions(mod,LEGACY_V6_PATH) or generatedManifestMentions(mod,LEGACY_V6_FALLBACK_PATH)
    local legacyV7=cacheRead(mod,LEGACY_V7_PATH)~=nil or cacheRead(mod,LEGACY_V7_FALLBACK_PATH)~=nil
      or cacheRead(mod,LEGACY_V7_PENDING_PATH)~=nil or cacheRead(mod,LEGACY_V7_MIGRATION_PATH)~=nil
      or generatedManifestMentions(mod,LEGACY_V7_PATH) or generatedManifestMentions(mod,LEGACY_V7_FALLBACK_PATH)
    if legacyV2 or legacyV3 or legacyV4 or legacyV5 or legacyV6 or legacyV7 then
      -- Do not delete the old render, its ledger, or its provenance markers.
      -- If it cannot satisfy the v9 ledger, it is a distinct legacy derivative;
      -- writeAsset archives its exact bytes before the v9 path is committed.
      progress("AUDIO PORTABLE / non-destructive v9 source-fidelity migration",0,24)
    end
    cacheWrite(mod,PORTABLE_PENDING_PATH,PORTABLE_FULL_MARKER,generated)
    cacheWrite(mod,PORTABLE_MIGRATION_PATH,PORTABLE_FULL_MARKER,generated)
  elseif not pendingV9 then
    -- Hidden pending marker vanished but the non-hidden journal survived.
    cacheWrite(mod,PORTABLE_PENDING_PATH,PORTABLE_FULL_MARKER,generated)
  elseif not migratingV9 then
    -- Likewise repair the durable journal from the pending marker.
    cacheWrite(mod,PORTABLE_MIGRATION_PATH,PORTABLE_FULL_MARKER,generated)
  end

  local transition=A.runPortableCore(mod,disc,progress,generated)
  assert(transition and transition.ready,"portable battle transition extraction failed")
  local ledger=readPortableLedger(mod)
  local transitionInfo=cacheInfo(mod,"assets/audio/colosseum_battle_transition.wav",true)
  assert(transitionInfo and (tonumber(transitionInfo.size) or 0)>=44,"portable battle transition cache write missing/truncated")
  if not portableAssetReady(mod,"assets/audio/colosseum_battle_transition.wav",ledger,true) then
    ledger=recordPortableAsset(mod,ledger,"assets/audio/colosseum_battle_transition.wav",transitionInfo.size)
  end
  local ready={};local complete=0
  for _,path in ipairs(PORTABLE_ASSETS) do ready[path]=portableAssetReady(mod,path,ledger,false);if ready[path] then complete=complete+1 end end
  progress(("AUDIO PORTABLE %d/24 / locating MusyX battle sources"):format(complete),complete,24)
  local payload=portablePayload(mod,disc)
  -- A repaired theme is one synthesis unit: commit BOTH halves, never combine
  -- a newly rendered HIGH intro with an older FAST loop (or the converse).
  for _,song in ipairs(payload.songs) do
    for _,path in ipairs({song.introPath,song.loopPath}) do
      if ready[path] then ready[path]=false;complete=complete-1 end
    end
  end
  local expectedEmitted=#payload.songs*2+#payload.oneShots
  local reportPath="build/audio_portable_report.txt"
  local reportRows={
    "cbe_audio_portable_report=1",
    "renderer=lua-musyx-canonical-v9-cross-platform-48k",
    "rate="..tostring(PORTABLE_RATE),
    "quality="..tostring(payload.quality),
    "requested_assets="..tostring(expectedEmitted),
  }
  local function reportAsset(message)
    local st=type(message.stats)=="table" and message.stats or {}
    reportRows[#reportRows+1]=table.concat({
      "asset="..tostring(message.path or ""),
      "source="..tostring(message.source or ""),
      "frames="..tostring(tonumber(st.frames) or 0),
      "voices="..tostring(tonumber(st.voices) or 0),
      "peak="..tostring(tonumber(st.peak) or 0),
      "clipped="..tostring(tonumber(st.clipped) or 0),
      "loop_start_frame="..tostring(tonumber(st.loopStartFrame) or 0),
      "source_loop_start_tick="..tostring(tonumber(st.sourceLoopStartTick) or 0),
      "loop_end_frame="..tostring(tonumber(st.loopEndFrame) or 0),
      "source_loop_end_tick="..tostring(tonumber(st.sourceLoopEndTick) or 0),
    }," ")
  end
  local okRender,result=pcall(PortableMusyX.renderAll,payload,function(message)
    if message.kind=="source" then
      progress(("AUDIO PORTABLE %d/24 / %s"):format(complete,tostring(message.source or "MusyX source")),complete,24)
    elseif message.kind=="heartbeat" then
      local frame,total=tonumber(message.frame) or 0,tonumber(message.total) or 0
      local pct=total>0 and math.floor(frame*100/total) or 0
      progress(("AUDIO PORTABLE %d/24 / %s / %d%%"):format(complete,tostring(message.source or "rendering"),pct),complete,24)
    elseif message.kind=="asset" then
      local path=tostring(message.path)
      if not ready[path] then
        writeAsset(mod,path,message.bytes,generated)
        local committed=cacheInfo(mod,path,true)
        assert(committed and tonumber(committed.size)==#message.bytes,"audio output "..path..": committed size does not match rendered WAV")
        ledger=recordPortableAsset(mod,ledger,path,#message.bytes)
        assert(portableAssetReady(mod,path,ledger,true),"audio output "..path..": committed size does not match v9 asset ledger")
        if Fidelity then Fidelity.record(mod,path,message.bytes,payload.quality,generated) end
        ready[path]=true;complete=complete+1
      end
      reportAsset(message)
      progress(("AUDIO PORTABLE %d/24 / %s"):format(complete,tostring(message.source or path)),complete,24)
    end
  end)
  if not okRender then
    reportRows[#reportRows+1]="render_error="..tostring(result):gsub("[\r\n]+"," ")
    pcall(cacheWrite,mod,reportPath,table.concat(reportRows,"\n").."\n",generated)
    error(result,0)
  end
  reportRows[#reportRows+1]="complete="..tostring(complete)
  cacheWrite(mod,reportPath,table.concat(reportRows,"\n").."\n",generated)
  assert(result and tonumber(result.complete)==expectedEmitted,("portable MusyX renderer completed with %s/%d requested sequence assets"):format(tostring(result and result.complete),expectedEmitted))
  assert(complete==24,("portable audio cache completed with %d/24 assets"):format(complete))
  assert(portableAssetsReady(mod,true),"portable audio cache reached 24/24 but the v9 asset ledger does not match committed WAV sizes")
  if generated then generated[#generated+1]=PORTABLE_LEDGER_PATH end
  writePortableFullMarkers(mod,generated)
  cacheDelete(mod,PORTABLE_PENDING_PATH);cacheDelete(mod,PORTABLE_MIGRATION_PATH)
  -- Keep all historical completion/provenance markers. They are inert once the
  -- exact v9 marker + ledger validates, and retaining them guarantees upgrades
  -- never erase evidence needed to reuse or diagnose an older saved derivative.
  assert(A.portableFullReady(mod),"portable audio completion marker written but generated soundtrack cache failed validation")
  progress("AUDIO PORTABLE 24/24 / 48 kHz canonical cross-platform cache verified",24,24)
  return {ready=true,complete=24,total=24,renderer=result.renderer or "portable Lua MusyX canonical v9 / cross-platform / 48 kHz",rate=PORTABLE_RATE}
end

local function now()
  return love and love.timer and love.timer.getTime and love.timer.getTime() or os.clock()
end

local function render(mod,payload,progress,generated)
  assert(love and love.thread and type(love.thread.newThread)=="function",
    'audio renderer: host sandbox does not expose love.thread to this mod')
  serial=serial+1
  local token=("%d_%d"):format(serial,math.floor(now()*1000000)%1000000000)
  local inputName="cbe_audio_import_in_"..token
  local outputName="cbe_audio_import_out_"..token
  local input=love.thread.getChannel(inputName)
  local output=love.thread.getChannel(outputName)
  input:clear();output:clear()
  local workerPath=tostring(mod.path).."/extract/AudioWorker.lua"
  local okThread,thread=pcall(love.thread.newThread,workerPath)
  assert(okThread and thread,"audio renderer worker "..workerPath..": "..tostring(thread))
  input:push(payload)
  local okStart,startErr=pcall(thread.start,thread,inputName,outputName)
  assert(okStart,"audio renderer worker start: "..tostring(startErr))

  local complete=0
  local active="preparing renderer"
  local activeAt=now()
  local lastHeartbeat=-1
  while true do
    local message=output:pop()
    if message then
      if message.kind=="source" then
        active=tostring(message.source or "audio source")
        activeAt=now()
        progress(("AUDIO %d/24 / %s"):format(complete,active),complete,24)
      elseif message.kind=="asset" then
        writeAsset(mod,tostring(message.path),message.bytes,generated)
        complete=complete+1
        progress(("AUDIO %d/24 / %s"):format(complete,tostring(message.source or message.path)),complete,24)
      elseif message.kind=="error" then
        error(("audio source %s: %s"):format(tostring(message.source or active),tostring(message.error or "conversion failed")),0)
      elseif message.kind=="done" then
        assert(complete==24,("audio renderer completed with %d/24 cached assets"):format(complete))
        input:clear();output:clear()
        return complete
      end
    end
    local workerErr=thread.getError and thread:getError()
    if workerErr then error(("audio source %s: worker crashed: %s"):format(active,tostring(workerErr)),0) end
    local t=now()
    if t-lastHeartbeat>=0.20 then
      lastHeartbeat=t
      progress(("AUDIO %d/24 / %s / %ds"):format(complete,active,math.floor(t-activeAt)),complete,24)
    end
    if love.timer and love.timer.sleep then love.timer.sleep(0.04) end
  end
end


function A.platformSupported()
  local osName=nil
  if love and love.system and type(love.system.getOS)=="function" then
    local ok,v=pcall(love.system.getOS);if ok then osName=tostring(v or "") end
  end
  -- The bundled Amuse renderer is a Windows executable. Android/iOS/macOS/Linux
  -- must never be sent through cmd.exe; those platforms use the portable 24/24 renderer instead.
  if osName=="" or osName==nil then return false,"unknown" end
  return osName=="Windows",osName
end
function A.run(mod,disc,progress,generated)
  progress=progress or function()end
  local supported,osName=A.platformSupported()
  assert(supported,("Windows Amuse conversion is unavailable on %s; use the portable renderer on this platform"):format(tostring(osName or "this platform")))
  progress("AUDIO 0/24 / locating MusyX sources",0,24)
  local commonFile=assert(disc:file("common.fsys"),"audio source common.fsys: archive missing")
  local bgmFile=assert(disc:file("bgm_archive.fsys"),"audio source bgm_archive.fsys: archive missing")
  local common=FSYS.open(disc,commonFile)
  local bgm=FSYS.open(disc,bgmFile)
  local commonMembers,bgmMembers=memberMap(common),memberMap(bgm)

  local renderer=mod:read("third_party/amuse/amuserender.exe")
  assert(type(renderer)=="string" and #renderer>0,
    "audio renderer third_party/amuse/amuserender.exe: bundled converter missing")

  local songs={}
  for _,theme in ipairs(THEMES) do
    songs[#songs+1]={
      source="bgm_archive.fsys/"..theme.source,
      setup=theme.setup,loopFrame=theme.loopFrame,
      introPath=theme.intro,loopPath=theme.loop,
      sequence=requiredMember(bgm,bgmMembers,theme.source,"bgm_archive.fsys"),
    }
  end

  local oneShots={}
  for _,shot in ipairs(ONE_SHOTS) do
    oneShots[#oneShots+1]={source="bgm_archive.fsys/"..shot.source,setup=shot.setup,outputPath=shot.output,
      sequence=requiredMember(bgm,bgmMembers,shot.source,"bgm_archive.fsys")}
  end

  local payload={
    renderer=renderer,sampleRate=48000,songs=songs,oneShots=oneShots,
    music={
      proj=requiredMember(common,commonMembers,"snd_music_proj","common.fsys"),
      pool=requiredMember(common,commonMembers,"snd_music_pool","common.fsys"),
      sdir=requiredMember(common,commonMembers,"snd_music_sdir","common.fsys"),
      samp=directFile(disc,"snd_music.samp"),
    },
    transition={
      source="common.fsys/snd_se_battle_sdir + disc/snd_se_battle.samp / sample 92 (SFX 0x00CC)",
      outputPath="assets/audio/colosseum_battle_transition.wav",sampleId=92,
      sdir=requiredMember(common,commonMembers,"snd_se_battle_sdir","common.fsys"),
      samp=directFile(disc,"snd_se_battle.samp"),
    },
  }
  local complete=render(mod,payload,progress,generated)
  progress("AUDIO 24/24 / generated cache verified",complete,24)
  return {ready=true,complete=complete,total=24,renderer="CBE import worker / Amuse"}
end

-- Used by the optional transactional upgrader; no mutation until its commit.
function A.fidelityLedger(mod,sizes)
  local ledger=readPortableLedger(mod)
  for path,size in pairs(sizes) do ledger.assets[path]={size=size} end
  return encodePortableLedger(ledger)
end
A.bossMarkerPath=BOSS_MARKER
A.bossCuePath=BOSS_CUE
function A.bossMarker(wav)return BOSS_ID.."\nbytes="..#wav end
A.themes=THEMES
A.environmentThemes=ENVIRONMENT_THEMES
A.environmentAssets=ENVIRONMENT_ASSETS
A.environmentMarkerPath=ENVIRONMENT_MARKER_PATH
A.environmentMarker=ENVIRONMENT_MARKER
A.portableMarker=PORTABLE_MARKER
A.portableFullMarker=PORTABLE_FULL_MARKER
A.portableAssets=PORTABLE_ASSETS
A.portableLedgerPath=PORTABLE_LEDGER_PATH
A.preservedAudioRoot=PRESERVED_AUDIO_ROOT
A._test={preserveExistingAsset=preserveExistingAsset,writeAsset=writeAsset,
  preservedAudioFingerprint=preservedAudioFingerprint,preservedAudioPath=preservedAudioPath}
return A
