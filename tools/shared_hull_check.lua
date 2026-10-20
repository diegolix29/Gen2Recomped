local n=0
local function check(v,msg)assert(v,msg);n=n+1 end
local built,released,buffers,draws=0,0,0,0
local Budget={own=function(o)return o end,disown=function()end,tick=function()end,check=function()end}
local Mat4=assert(loadfile('mods/DRAMATIC_SHAPE/lib/Mat4.lua'))({})
local bounds=setmetatable({}, {__mode='k'})
local Bounds={get=function(o)return bounds[o] end,set=function(o,b)bounds[o]=b end,hidden=function()return false end,hiddenCurved=function()return false end}
local source,variant={},{}
local current
love={graphics={newMesh=function(_,offsets)
 buffers=buffers+1
 return {release=function()buffers=buffers-1 end}
end,drawInstanced=function(_,count)draws=draws+count end,setShader=function(s)current=s end}}
local libs={BuildBudget=Budget,Mat4=Mat4,MeshBounds=Bounds,
 ShaderState={copy=function(from,to)check(from==source and to==variant,'shader uniform source preserved')end}}
libs.ChunkMesher={hullTemplate=function()
 built=built+1
 local part={attachAttribute=function()end,setTexture=function()end};bounds[part]={-1,0,-1,1,2,1}
 return {parts={part},getVertexCount=function()return 6 end,release=function()released=released+1 end}
end}
local V={require=function(name)return assert(libs[name],name)end}
local H=assert(loadfile('mods/DRAMATIC_SHAPE/lib/HullBatch.lua'))(V)
local quads={}
local a,b=H.new(),H.new()
a:add(quads,0,0,0);a:add(quads,16,0,16);b:add(quads,32,0,32)
check(built==1,'maps and copies share one immutable template')
a:finish();b:finish();check(buffers==2,'small instance buffers owned per map')
check(H.instanced({hullOwner=a},'atlas',Mat4.identity(),nil,0,0,0,source,variant),'instanced path selected')
check(draws==2 and current==source,'all instances drawn and original shader restored')
local draw=love.graphics.drawInstanced;love.graphics.drawInstanced=function()error('driver rejected instance attribute')end
check(not H.instanced({hullOwner=a},'atlas',Mat4.identity(),nil,0,0,0,source,variant) and current==source,'driver failure restores shader and selects translated fallback')
love.graphics.drawInstanced=draw
a:release();check(released==0 and buffers==1,'live neighbor keeps shared GPU mesh')
a:release();check(released==0 and buffers==1,'owner release is idempotent')
b:release();check(released==1 and buffers==0,'last owner releases template and instance buffer')
local c=H.new();c:add(quads,0,16,0);c:add(quads,0,32,0)
check(built==3,'height/contact-shading variants stay distinct')
c:release();check(released==3,'cancelling before instance upload frees template meshes')
local state=assert(loadfile('mods/DRAMATIC_SHAPE/lib/ShaderState.lua'))({sharedHulls=true})
local calls={};local sh={send=function(_,...)calls[#calls+1]={...}end}
local target={send=function(_,...)calls[#calls+1]={...}end}
state.send(sh,'model','row',{});state.send(sh,'mirror',{1,2});state.copy(sh,target)
check(#calls==4,'instanced shader receives matrix and mirror state')
print('Shared hull ownership and shader state: '..n..' checks passed')
