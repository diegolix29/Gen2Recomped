-- OVERWORLD TERRAIN / Generic overworld biome arena
-- Procedurally generates terrain resembling typical overworld areas:
-- grass patches, dirt paths, water features, and simple vegetation
local groups={}
local function V(x,y,z,u,v,r,g,b,a) return {x,y,z,u or 0,v or 0,r or 1,g or 1,b or 1,a or 1} end
local function G(tex,w,h,diff,amb,spec,shine,xlu)
  local g={vertices={},alpha=1,xlu=xlu and true or false,noz=false,
    diffuse=diff or {1,1,1},ambient=amb or {.5,.5,.5},specular=spec or {.01,.01,.01},shininess=shine or 1}
  if tex then g.texture={path=tex,w=w,h=h} end
  groups[#groups+1]=g;return g
end
local function T(g,a,b,c) g.vertices[#g.vertices+1]=a;g.vertices[#g.vertices+1]=b;g.vertices[#g.vertices+1]=c end
local function Q(g,a,b,c,d) T(g,a,b,c);T(g,a,c,d) end
local function clamp(v,a,b) if v<a then return a elseif v>b then return b end return v end
local function mix(a,b,t) return a+(b-a)*t end
local function hash01(n)
  local v=math.sin(n*12.9898+78.233)*43758.5453123
  return v-math.floor(v)
end

-- Textures - reuse existing ones from outdoor_wild
local ROOT="cache/stages/wildlands/"
local GRASS=ROOT.."ground_meadow_128.rgba"
local DIRT=ROOT.."ground_forest_128.rgba"
local PATH=ROOT.."bark_128.rgba"
local WATER="cache/stages/water/source/tex_081b60_256x256_f14.rgba"

-- Ground materials
local grass=G(GRASS,128,128,{.68,.79,.61},{.35,.52,.29},{.004,.004,.003},1)
local dirt=G(DIRT,128,128,{.60,.54,.40},{.29,.25,.18},{.002,.002,.002},1)
local path=G(PATH,128,128,{.79,.68,.54},{.42,.34,.26},{.006,.005,.004},1)
local water=G(WATER,256,256,{.22,.55,.69},{.12,.30,.40},{.08,.10,.12},16,true)
water.alpha=.76
water.flow=1

-- Height function for terrain variation
local function terrainH(x,z)
  local r=math.sqrt(x*x+z*z)
  local n=math.sin(x*.025+z*.015)*.35+math.cos(z*.020-x*.010)*.25
  return n*.15
end

-- Generate main ground plane with grass
local N=144
local rings={0,30,60,90,120,150,180,210,240,270,300,330,360,400}
for ri=1,#rings-1 do
  local r0,r1=rings[ri],rings[ri+1]
  for i=0,N-1 do
    local a0=2*math.pi*i/N
    local a1=2*math.pi*(i+1)/N
    local function p(r,a)
      local x=math.cos(a)*r
      local z=math.sin(a)*r
      local y=terrainH(x,z)
      local noise=.5+.5*math.sin(x*.04+math.sin(z*.02)*1.5)*math.cos(z*.03-x*.01)
      local c={.86+.04*noise,.94+.035*noise,.82+.03*noise}
      return V(x,y,z,x*.03,z*.03,c[1],c[2],c[3],1)
    end
    T(grass,p(r0,a0),p(r1,a0),p(r1,a1))
    T(grass,p(r0,a0),p(r1,a1),p(r0,a1))
  end
end

-- Dirt patches (representing clearings or different terrain)
local dirtPatches={{-80,40,35},{90,-50,30},{-40,-90,38},{120,80,32},{-150,-30,42}}
for i,p in ipairs(dirtPatches) do
  local cx,cz,r=p[1],p[2],p[3]
  local seg=24
  for j=0,seg-1 do
    local a0=2*math.pi*j/seg
    local a1=2*math.pi*(j+1)/seg
    local function p(a,t)
      local x=cx+math.cos(a)*r*t
      local z=cz+math.sin(a)*r*t
      local y=terrainH(x,z)+.05
      return V(x,y,z,x*.03,z*.03,.78,.72,.56,1)
    end
    T(dirt,p(a0,0),p(a1,0),p(a1,1))
    T(dirt,p(a0,0),p(a1,1),p(a0,1))
  end
end

-- Dirt path winding through the arena
local pathPoints={}
for i=0,20 do
  local t=i/20
  local a=t*math.pi*2*.3
  local r=80+20*math.sin(t*3)
  local x=math.cos(a)*r
  local z=math.sin(a)*r
  pathPoints[#pathPoints+1]={x,z}
end
for i=1,#pathPoints-1 do
  local p0,p1=pathPoints[i],pathPoints[i+1]
  local dx,dz=p1[1]-p0[1],p1[2]-p0[2]
  local len=math.sqrt(dx*dx+dz*dz)
  local px,pz=-dz/len,dx/len
  local w=8
  local function p(t,side)
    local x=p0[1]+dx*t+px*side*w
    local z=p0[2]+dz*t+pz*side*w
    local y=terrainH(x,z)+.08
    return V(x,y,z,x*.03,z*.03,.79,.68,.54,1)
  end
  Q(path,p(0,-1),p(0,1),p(1,1),p(1,-1))
end

-- Water feature (small pond)
local pondCX,pondCZ,pondR=-100,-120,45
local waterY=-2
local pondRings={0,15,30,45}
for ri=1,#pondRings-1 do
  local r0,r1=pondRings[ri],pondRings[ri+1]
  for i=0,N-1 do
    local a0=2*math.pi*i/N
    local a1=2*math.pi*(i+1)/N
    local function p(r,a)
      local x=pondCX+math.cos(a)*r
      local z=pondCZ+math.sin(a)*r
      return V(x,waterY,z,x*.025,z*.025,.61,.82,.92,.76)
    end
    if r0==0 then
      T(water,V(pondCX,waterY,pondCZ,0,0,.61,.82,.92,.76),p(r1,a1),p(r1,a0))
    else
      Q(water,p(r0,a0),p(r0,a1),p(r1,a1),p(r1,a0))
    end
  end
end

-- Pond edge (grass bank)
local bank=G(GRASS,128,128,{.68,.79,.61},{.35,.52,.29},{.004,.004,.003},1)
for i=0,N-1 do
  local a0=2*math.pi*i/N
  local a1=2*math.pi*(i+1)/N
  local x0,z0=pondCX+math.cos(a0)*pondR,pondCZ+math.sin(a0)*pondR
  local x1,z1=pondCX+math.cos(a1)*pondR,pondCZ+math.sin(a1)*pondR
  local y0=terrainH(x0,z0)+.05
  local y1=terrainH(x1,z1)+.05
  Q(bank,V(x0,y0,z0,x0*.03,z0*.03,.86,.94,.82,1),
        V(x1,y1,z1,x1*.03,z1*.03,.86,.94,.82,1),
        V(x1,waterY+.05,z1,x1*.025,z1*.025,.86,.94,.82,1),
        V(x0,waterY+.05,z0,x0*.025,z0*.025,.86,.94,.82,1))
end

-- Simple grass blades (simplified from outdoor_wild)
local grassBlades=G(nil,nil,nil,{.37,.70,.24},{.19,.40,.13},{.001,.001,.001},1)
for i=1,400 do
  local x=(hash01(i*3.117+7.3)-.5)*300
  local z=(hash01(i*7.931+31.7)-.5)*300
  local r=math.sqrt(x*x+z*z)
  if r>50 and r<350 and hash01(i*11.73+2.1)>.4 then
    local h=1.2+hash01(i*5.27+13.0)*.8
    local a=hash01(i*9.41+4.6)*math.pi*2
    local dx,dz=math.cos(a),math.sin(a)
    local base=terrainH(x,z)+.07
    local c=.88+.10*math.sin(i*2.1)
    local l0=V(x+dx*.3,base,z+dz*.3,0,1,.42*c,.78*c,.27*c,1)
    local r0=V(x-dx*.3,base,z-dz*.3,1,1,.36*c,.71*c,.23*c,1)
    local tip=V(x+dx*.45,base+h,z+dz*.45,.5,0,.52*c,.88*c,.31*c,1)
    Q(grassBlades,l0,r0,V(x-dx*.15,base+h*.55,z-dz*.15,.9,.45,.39*c,.75*c,.24*c,1))
    T(grassBlades,l0,V(x-dx*.15,base+h*.55,z-dz*.15,.9,.45,.39*c,.75*c,.24*c,1),tip)
  end
end

-- Battle pads
local BATTLE_PADS={
  {kind='pokemon',slot='player-left',cx=-19.2,cz=70,r=68},
  {kind='pokemon',slot='player-right',cx=-19.2,cz=70,r=68},
  {kind='pokemon',slot='enemy-left',cx=19.2,cz=-70,r=68},
  {kind='pokemon',slot='enemy-right',cx=19.2,cz=-70,r=68},
  {kind='trainer',slot='player-trainer',cx=56,cz=116,r=24},
  {kind='trainer',slot='enemy-trainer',cx=-56,cz=-116,r=24},
}
local SINGLE_PADS={
  {kind='pokemon',slot='player-single',cx=-19.2,cz=70,r=68},
  {kind='pokemon',slot='enemy-single',cx=19.2,cz=-70,r=68},
}

local total=0
for _,g in ipairs(groups) do total=total+#g.vertices end

return {
  version=7,
  source="Terrarium Advance / Procedural overworld terrain arena",
  prototype=false,
  bounds={min={-450,-5,-450},max={450,20,450}},
  battlePads=BATTLE_PADS,
  singlePads=SINGLE_PADS,
  waterY=waterY,
  groupCount=#groups,
  vertexCount=total,
  groups=groups
}
