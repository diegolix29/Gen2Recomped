-- Map cartridge animation coordinates onto the live 3D battler pair.
local Projection={}
function Projection.point(positions,x,y)
 local p,e=positions[0],positions[1]
 if not p or not e then return x,y,1,0 end
 local dx,dy=e.x-p.x,e.y-p.y
 local a=(dx*128-dy*64)/20480
 local b=(dx*64+dy*128)/20480
 local rx,ry=x-64,y-112
 return p.x+a*rx-b*ry,p.y+b*rx+a*ry,math.sqrt(a*a+b*b),math.atan2(b,a)
end
function Projection.origin(name,attacker)
 local p,e={64,112},{192,48}
 if name=='player' then return unpack(p) end
 if name=='enemy' then return unpack(e) end
 if name=='attacker' then return unpack(attacker and p or e) end
 if name=='defender' then return unpack(attacker and e or p) end
 return 128,80
end
return Projection
