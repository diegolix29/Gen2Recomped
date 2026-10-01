package.path='./?.lua;'..package.path
local P=require('src.battle.Gen4EffectProjection')
local checks=0
local function near(a,b) assert(math.abs(a-b)<1e-6);checks=checks+1 end
for _,pair in ipairs({{[0]={x=64,y=112},[1]={x=192,y=48}}, {[0]={x=50,y=130},[1]={x=170,y=65}}, {[0]={x=180,y=120},[1]={x=80,y=60}}, {[0]={x=110,y=100},[1]={x=130,y=80}}}) do
 for _,side in ipairs({true,false}) do
  local ax,ay=P.origin('attacker',side)
  local bx,by=P.origin('defender',side)
  local start,finish=pair[side and 0 or 1],pair[side and 1 or 0]
  for _,t in ipairs({0,.25,.5,.75,1}) do
   local x,y=P.point(pair,ax+(bx-ax)*t,ay+(by-ay)*t)
   near(x,start.x+(finish.x-start.x)*t);near(y,start.y+(finish.y-start.y)*t)
  end
 end
end
local Battle=require('src.battle.Gen4Battle')
local battle={dramaticNativePositions={[0]={x=180,y=120},[1]={x=80,y=60}}}
local original=Battle.battlerPos
Battle.battlerPos=function(self,slot) return self.dramaticNativePositions and self.dramaticNativePositions[slot] or original(self,slot) end
local x,y=Battle.effectPosition(battle,'attacker',true,128,-64)
near(x,80);near(y,60)
x,y=Battle.effectPosition(battle,'defender',true,0,0,64,112)
near(x,180);near(y,120)
local flat={};x,y=Battle.effectPosition(flat,'attacker',true,128,-64)
near(x,192);near(y,48)
print(checks..' forward/reverse projectile, orbit and zoom projection checks passed')
