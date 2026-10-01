package.path='./?.lua;'..package.path
package.loaded['src.script.Commands']={meta={}}
package.loaded['src.core.Logger']=setmetatable({},{__index=function() return function() end end})
local VM=require('src.script.Gen4ScriptVM')
local S=require('src.import.Gen4Script')
local A=require('src.import.Gen4Archives')
local N=require('src.import.NarcArchive')
local rom=assert(require('src.import.NdsRom').open(arg[1] or 'Pokemon - Platinum Version (USA) (Rev 1).nds'))
local arc=assert(N.parse(rom:read('/fielddata/script/scr_seq.narc')))
local bytes=arc:get(A.find('/fielddata/script/scr_seq.narc','scripts_common'))
local visited,missing={},{}
local instructions=0
local function walk(at)
  if visited[at] then return end
  visited[at]=true
  for _,ins in ipairs(S.decode(bytes,at)) do
    instructions=instructions+1
    if not VM.lowered(ins.name) then missing[ins.name]=(missing[ins.name] or 0)+1 end
    if ins.target then walk(ins.target) end
  end
end
walk(S.entries(bytes)[3])
-- Common-script branch traversal also reaches contest dialogue. Contestants
-- have their own roster and are intentionally not substituted with party mons.
for name,count in pairs(missing) do
  assert(name=='buffercontestantmonname','unimplemented nurse instruction: '..name)
end
assert(instructions>100,'nurse traversal must visit real ROM commands')
assert(VM.lowered('healparty') and VM.lowered('playpokecenterhealinganimation')
 and VM.lowered('showyesnomenu') and VM.lowered('messagevar'),'nurse flow commands available')
print('nurse reachable instructions: '..instructions)
print('service script checks passed; contest roster text remains unsupported')
rom:close()
