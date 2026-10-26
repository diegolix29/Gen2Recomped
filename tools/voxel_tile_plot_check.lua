local checks=0
local function check(v,why)assert(v,why);checks=checks+1 end
local ticks=0
local V={require=function(n)assert(n=='BuildBudget');return {check=function()ticks=ticks+1 end}end}
local M=assert(loadfile('mods/DRAMATIC_SHAPE/lib/TilePlotCache.lua'))(V)
local decoded=0
local function tiles()
 return {sheetOrigin=function(_,slot)return slot*16,slot*32 end,
 bakeMetatileInto=function(self,id,layer,slot,plot)
  decoded=decoded+1
  local x,y=self:sheetOrigin(slot)
  plot(x,y,1,2,3);plot(x,y,7,8,9);plot(x+15,y+15,255,0,128)
 end}
end
local function draw(t,id,layer,slot)
 local out={}
 t:bakeMetatileInto(id,layer,slot,function(x,y,r,g,b)
  out[#out+1]=table.concat({x-slot*16,y-slot*32,r,g,b},',')
 end)
 return table.concat(out,';')
end
local a=tiles();check(M.wrap(a,'pair'),'cache enabled')
local before=draw(a,1,1,2)
local b=tiles();M.wrap(b,'pair')
check(draw(b,1,1,8)==before and decoded==1,'replay preserves source order, overdraw, RGB bytes and destination slot')
check(M.hits==1 and M.misses==1,'warm decode avoided')
local ok=pcall(a.bakeMetatileInto,a,2,1,0,function()error('consumer failed')end)
check(not ok,'consumer error propagated')
local n=decoded;draw(b,2,1,0);check(decoded==n+1,'failed callback never publishes partial cache')
local co=coroutine.create(function()a:bakeMetatileInto(3,1,0,function()coroutine.yield()end)end)
check(coroutine.resume(co),'suspend decode')
n=decoded;draw(b,3,1,0);check(decoded==n+1,'abandoned suspended decode never publishes partial cache')
M.clear();M.limit=100
local x=tiles();M.wrap(x,'old');draw(x,1,1,0)
local y=tiles();M.wrap(y,'new');draw(y,1,1,0)
check(M.bytes<=100,'bounded cache evicts older tileset events')
M.clear();check(M.bytes==0 and M.hits==0,'ROM/art invalidation clears cached events')
print('Voxel tile plot cache: '..checks..' checks passed')
