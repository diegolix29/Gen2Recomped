-- Fast logic/worker regression checks, with tiny synthetic identities. The
-- native harness separately hashes all four real full and trimmed cartridges.
love=require('tests.love_stub')
local checks=0
local function check(ok,label) assert(ok,label);checks=checks+1 end
local chunkSize=256
local header=string.rep('\0',12)..'IPKE'..string.rep('\0',4)..string.char(10)..string.rep('\0',491)
local bytes=header..'retained game bytes'..string.rep('\255',20)
local contentSize=#bytes-20
local function digest(s) -- deterministic fixture digest, never used on ROMs
  local n=0;for i=1,#s do n=(n+s:byte(i)*i)%1000000007 end
  return #s..':'..n
end
local rec={code='IPKE',capacity=128*1048576,contentSize=contentSize,sha1='canonical',chunks={}}
for start=1,contentSize,chunkSize do rec.chunks[#rec.chunks+1]=digest(bytes:sub(start,math.min(start+chunkSize-1,contentSize))) end
package.loaded['src.import.NdsTrimIdentity']={chunkSize=chunkSize,games={heartgold=rec}}
local realGV=require('src.core.GameVersion')
package.loaded['src.core.GameVersion']={forSha1=function(h) return h=='canonical' and 'heartgold' end,
 info=function() return {generation=5} end}
local V=require('src.import.RomVerification')
check(V.isCandidate(256*1048576),'full BW capacity admitted')
check(not V.isCandidate(122.89*1048576),'size alone does not admit trimmed files')
check(V.isCandidate(#bytes,bytes),'known trimmed header and retained extent admitted for verification')
check(not V.isCandidate(contentSize-1,header),'missing real content is not trimmed padding')
local identity=V.identify(bytes,digest)
check(identity.trimmed and identity.version=='heartgold' and identity.hash=='canonical','retained bytes and FF padding match')
check(identity.sourceHash==digest(bytes),'actual selected-file hash retained')
check(V.identify(bytes:sub(1,contentSize),digest).version=='heartgold','all trailing FF can be omitted')
check(not V.identify(bytes:sub(1,contentSize-1),digest).version,'truncated content rejected')
check(not V.identify(bytes:sub(1,50)..'X'..bytes:sub(52),digest).version,'altered header byte rejected')
check(not V.identify(bytes:sub(1,contentSize-1)..'X'..bytes:sub(contentSize+1),digest).version,'altered last chunk rejected')
check(not V.identify(bytes..'\0',digest).version,'non-FF trailer rejected')
check(not V.identify(bytes:sub(1,12)..'IPKP'..bytes:sub(17),digest).version,'different region cannot pass by header')
local changedCapacity=bytes:sub(1,20)..string.char(11)..bytes:sub(22)
check(not V.identify(changedCapacity,digest).version,'mismatched header capacity rejected')

-- Drive the actual worker entry point, not a parallel copy of its dispatch.
for _,name in ipairs({'filesystem','data','image','timer','system'}) do
 package.preload['love.'..name]=function() return love[name] end
end
package.loaded['src.import.ImportRecovery']={resume=function() end,stage=function() end}
local files={}
package.loaded['src.import.CacheFs']={write=function(p,b) files[p]=b;return true end,
 read=function(p) return files[p] end,remove=function(p) files[p]=nil end}
love.timer={getTime=function() return 1 end}
local newPath,newVersion,ran,closed
package.loaded['fixture.nds.extractor']={new=function(path,version)
 newPath,newVersion=path,version
 return {run=function() ran=true end,close=function() closed=true end}
end}
local messages={};local channel={push=function(_,m) messages[#messages+1]=m end}
for _,generation in ipairs({4,5}) do
 messages={};ran=false;closed=false
 assert(loadfile('src/import/rom_import_worker.lua'))({action='extract',generation=generation,
  module='fixture.nds.extractor',path='fixture.nds',version='black',root='unused'},channel)
 check(newPath=='fixture.nds' and newVersion=='black' and ran and closed,'generation '..generation..' worker opens cartridge path')
 check(messages[#messages].kind=='complete','generation '..generation..' worker completes')
end
-- Gen 5 verification must not copy a 256-MiB string back to the UI thread.
local oldIdentify=V.identify
V.identify=function() return {version='black',hash='canonical',sourceHash='actual',trimmed=true} end
messages={}
assert(loadfile('src/import/rom_import_worker.lua'))({action='verify',path='fixture.nds',bytes=bytes},channel)
local verified=messages[#messages]
check(verified.kind=='verified' and verified.bytes=='' and verified.trimmed,'BW worker returns identity without cartridge bytes')
check(verified.sourceHash=='actual' and verified.size==#bytes,'BW source identity/length retained')
V.identify=oldIdentify
package.loaded['src.core.GameVersion']=realGV
package.loaded['src.import.ImportRecovery'].begin=function() return {} end
local Importer=require('src.import.RomImporter')
local function launcher(version)
 return setmetatable({tab=version,workState='idle',
  _acknowledgeInterruptedImport=function() end,_beginRomProbe=function() return false end,
  setError=function(self,why) self.workState='error';self.detail=why end},Importer)
end
for _,case in ipairs({{'heartgold',math.floor(122.89*1048576)},{'soulsilver',math.floor(122.89*1048576)},
 {'black',256*1048576},{'white',200*1048576}}) do
 local version,size=case[1],case[2];local view=launcher(version)
 view:startData('',version..'.nds',version..'.nds',{hash=realGV.info(version).sha1,version=version,size=size})
 check(view.workState=='working' and view.importing==version and coroutine.status(view.worker)=='suspended',
  version..' verified worker result reaches extraction even without retained bytes')
end
local view=launcher('heartgold')
view:startData('','bad.nds','bad.nds',{hash='not accepted',version='heartgold',size=math.floor(122.89*1048576)})
check(view.workState=='error','a claimed version cannot bypass the canonical hash gate')
view=launcher('heartgold')
local eu=header:sub(1,12)..'IPKP'..header:sub(17,348)..'\x56\xCF'..header:sub(351)
view:startData(eu,'europe.nds','europe.nds',{hash='unrecognized',size=math.floor(122.89*1048576)})
check(view.workState=='error' and view.detail:find('IPKP',1,true),
 'trimmed unsupported region reports its game code/revision instead of a misleading size error')
print(('nds_import_verification_check: %d passed'):format(checks))
