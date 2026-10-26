-- Execute the actual height function with small map fixtures. The full scene
-- loads GPU modules; this isolates its terrain queries for a headless check.
local f=assert(io.open('mods/DRAMATIC_SHAPE/lib/VoxelScene.lua','rb'));local source=f:read('*a');f:close()
local start=assert(source:find('local function groundAt(',1,true))
local finish=assert(source:find('\nVoxelScene.YAW =',start,true))
local code=source:sub(start,finish-1)
local factory=assert((loadstring or load)('return function(Gen3,ChunkMesher,TileShape,Structures)\n'..code..'\nreturn groundAt end'))()
local structures={stairAt=function(map)return map.stair end,terraceAt=function(map)return map.height end,
 flightEnds=function()return 0,64,'x',1,0,1 end}
local shape={forMap=function(map)assert(not map.incoming,'incoming border was sampled');return {}end,
 at=function()return {class='ground',art='flat',h=0}end}
local ground=factory({mapIsGen3=function()return false end,tileAt=function()return 0 end},{},shape,structures)
local function map(height,incoming)
 return {height=height,incoming=incoming,inBounds=function(_,x,y)return x>=0 and y>=0 and x<4 and y<4 end,
 isWalkableCell=function()return true end}
end
local incoming=map(96,true)
local cases={{-1,2,-64,0},{4,2,64,0},{2,-1,0,-64},{2,4,0,64}}
local checks=0
for _,c in ipairs(cases)do
 for _,height in ipairs({0,16,64,-4})do
  local old=map(height);local neighbors={{map=old,ox=c[3],oy=c[4]}}
  assert(ground(incoming,c[1],c[2],3,c[1]*16,c[2]*16,neighbors)==height,'seam lost actual departing floor')
  checks=checks+1
 end
end
local old=map(0);old.stair=true
assert(ground(incoming,-1,2,3,-8,32,{{map=old,ox=-64,oy=0}})==32,'sub-cell stair height was not sampled')
assert(ground(incoming,-1,2,3,-16,32)==0,'no-neighbor fallback changed')
assert(ground(incoming,-1,2,3,-16,32,{{map=old,ox=64,oy=0}})==0,'unrelated neighbor supplied a floor')
print('Seam heights: '..checks..' four-direction floor cases, stair interpolation, border exclusion and fallback passed')
