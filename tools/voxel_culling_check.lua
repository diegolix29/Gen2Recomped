-- Compare support-plane culling with an independent eight-corner reference.
local libs={}
local V={require=function(n)
 if not libs[n] then libs[n]=assert(loadfile('mods/DRAMATIC_SHAPE/lib/'..n..'.lua'))() end
 return libs[n]
end}
local M=V.require('Mat4')
local Bounds=assert(loadfile('mods/DRAMATIC_SHAPE/lib/MeshBounds.lua'))(V)
local function reference(b,m)
 local outside={true,true,true,true,true,true}
 for i=0,7 do
  local x=i%2==0 and b[1] or b[4]
  local y=math.floor(i/2)%2==0 and b[2] or b[5]
  local z=i<4 and b[3] or b[6]
  local p={}
  for row=1,4 do
   local a=(row-1)*4
   p[row]=m[a+1]*x+m[a+2]*y+m[a+3]*z+m[a+4]
  end
  for axis=1,3 do
   if not(p[axis]<-p[4])then outside[axis*2-1]=false end
   if not(p[axis]>p[4])then outside[axis*2]=false end
  end
 end
 for i=1,6 do if outside[i]then return true end end
 return false
end
math.randomseed(7241)
local count=0
for i=1,10000 do
 local x,y,z=math.random(-3000,3000),math.random(-80,300),math.random(-3000,3000)
 local b={x,y,z,x+math.random(1,300),y+math.random(1,150),z+math.random(1,300)}
 local view=M.lookAt({140,170,350},{0,0,0},{0,1,0})
 local proj=i%2==0 and M.perspective(math.rad(45),1.4,.1,5000) or M.ortho(-250,250,-200,200,.1,5000)
 local vp=M.mul(proj,view)
 local model=M.mul(M.translate(math.random(-100,100),0,math.random(-100,100)),M.rotateY(i*.07))
 local expected=reference(b,M.mul(vp,model))
 local actual=Bounds.hiddenBox(b,vp,model)
 assert(actual==expected,'culling changed at case '..i)
 local object={};Bounds.set(object,b)
 assert(Bounds.hiddenPlanes(object,Bounds.planes(M.mul(vp,model)))==expected,
  'shared plane culling changed at case '..i)
 count=count+1
end
assert(not Bounds.hiddenBox({-1,-1,-1,1,1,1},M.identity()),'clip plane contact was culled')
local contact={};Bounds.set(contact,{-1,-1,-1,1,1,1})
assert(not Bounds.hiddenPlanes(contact,Bounds.planes(M.identity())),'shared plane contact was culled')
assert(not Bounds.hiddenPlanes({},Bounds.planes(M.identity())),'unbounded mesh was culled')
print('Voxel culling: '..count..' perspective/orthographic/rotated boxes match the reference')
