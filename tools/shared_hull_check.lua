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
state.send(sh,'pull',0);state.send(sh,'pull',0)
check(#calls==5,'unchanged scalar uniforms skip repeated native sends')
local matrix={1,2};state.send(sh,'mutable',matrix);matrix[1]=3;state.send(sh,'mutable',matrix)
check(#calls==7,'mutable tables are sent even when their identity is unchanged')
state.copy(sh,target);local after=#calls;state.copy(sh,target)
check(#calls-after==1,'shader copying reuses numeric snapshots but resends unsupported tables')
local equalBefore=#calls
state.send(sh,'mutable',{3,2})
check(#calls==equalBefore,'equal numeric contents skip sends across distinct table identities')
matrix[2]=9;state.send(sh,'mutable',matrix)
check(#calls==equalBefore+1,'in-place numeric mutation still reaches the shader')
matrix[1]=100
state.copy(sh,target)
local copied=calls[#calls]
-- pairs order is unspecified; inspect the last mutable send explicitly.
for i=#calls,1,-1 do if calls[i][1]=='mutable' then copied=calls[i];break end end
check(copied[2][1]==3 and copied[2][2]==9,'copy retains the last submitted values, not an unsent caller mutation')
state.send(sh,'mutable',{3});state.send(sh,'mutable',{3})
check(calls[#calls][2][2]==nil,'shrinking vector clears stale snapshot components')
local retries=0;local rejected={send=function()retries=retries+1;error('unknown uniform')end}
state.send(rejected,'missing',1);state.send(rejected,'missing',1)
check(retries==2,'failed sends never become cached successes')
-- A group can straddle the view while one immutable template part is fully
-- outside it. The second culling level must skip only that part.
libs.ChunkMesher.hullTemplate=function()
 local p,q={attachAttribute=function()end,setTexture=function()end},{attachAttribute=function()end,setTexture=function()end}
 bounds[p]={-1,0,-1,1,2,1};bounds[q]={-1,20,-1,1,22,1}
 return {parts={p,q},getVertexCount=function()return 12 end,release=function()end}
end
Bounds.hidden=function(o)local b=bounds[o];return b and b[2]>10 end
draws=0;local multi=H.new();multi:add({},0,0,0);multi:finish()
check(H.instanced({hullOwner=multi},'atlas',Mat4.identity(),nil,0,0,0,source,variant) and draws==1,'off-camera template part culled inside a visible instance group')
multi:release()
print('Shared hull ownership and shader state: '..n..' checks passed')
