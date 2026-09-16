local V=...
local HSD,FSYS=V and V.HSD,V and V.FSYS
local Persist=V and V.PayloadPreserver
local A={arenaRevision=16}
local floor,abs,sin,cos=math.floor,math.abs,math.sin,math.cos
local SPECS={
  ["cache/stages/d2_crater/textures/tex_0f4120_128x128_f14.rgba"]={128,128,"metal"},
  ["cache/stages/d2_crater/textures/tex_07cec0_128x64_f14.rgba"]={128,64,"trim"},
  ["cache/stages/d2_crater/textures/tex_0ce920_256x256_f14.rgba"]={256,256,"rock"},
  ["cache/stages/d2_crater/textures/tex_061ec0_256x256_f14.rgba"]={256,256,"rock_dark"},
  ["cache/stages/d2_crater/textures/tex_0ca920_128x256_f14.rgba"]={128,256,"lava"},
  ["cache/stages/d2_crater/textures/tex_0ea920_128x128_f14.rgba"]={128,128,"lava_hot"},
  ["cache/stages/d2_crater/textures/tex_0fd8e0_256x256_f14.rgba"]={256,256,"truss"},
  ["cache/stages/d2_crater/textures/tex_0c2120_256x256_f14.rgba"]={256,256,"sky"},
  ["cache/stages/d2_crater/textures/tex_0d6920_128x128_f1.rgba"]={128,128,"cloud"},
  ["cache/stages/wildlands/ground_meadow_128.rgba"]={128,128,"meadow"},
  ["cache/stages/wildlands/ground_forest_128.rgba"]={128,128,"forest"},
  ["cache/stages/wildlands/bark_128.rgba"]={128,128,"bark"},
  ["cache/stages/wildlands/leaf_cluster_a_128.rgba"]={128,128,"leaf1"},
  ["cache/stages/wildlands/leaf_cluster_b_128.rgba"]={128,128,"leaf2"},
  ["cache/stages/wildlands/leaf_cluster_c_128.rgba"]={128,128,"leaf3"},
}
local PACKAGED_TEXTURES={
  ["cache/stages/wildlands/ground_meadow_128.rgba"]="assets/cbe/wildlands/ground_meadow_128.rgba",
  ["cache/stages/wildlands/ground_forest_128.rgba"]="assets/cbe/wildlands/ground_forest_128.rgba",
  ["cache/stages/wildlands/bark_128.rgba"]="assets/cbe/wildlands/bark_128.rgba",
  ["cache/stages/wildlands/leaf_cluster_a_128.rgba"]="assets/cbe/wildlands/leaf_cluster_a_128.rgba",
  ["cache/stages/wildlands/leaf_cluster_b_128.rgba"]="assets/cbe/wildlands/leaf_cluster_b_128.rgba",
  ["cache/stages/wildlands/leaf_cluster_c_128.rgba"]="assets/cbe/wildlands/leaf_cluster_c_128.rgba",
}
local ARENAS={
  {cache="cache/M1_water_cache.lua",id="water",label="WATER COLOSSEUM",
    sourceFsys="M1_water_colo.fsys",sourceMember="M1_water_colo.dat",textureRoot="cache/stages/water/source",
    minVertices=40000,minGroups=150,maxVertices=240000,maxDisplayOps=1200000,maxSceneRoots=32,maxJobjs=12000,maxDobjs=36000,maxPobjs=60000,
    crowdOffsets={[0x0d5b60]=true,[0x0ddb60]=true}},
  {recipe="recipes/arenas/open_water.lua",cache="cache/open_water_cache.lua",id="open_water",label="ORRE OPEN SEA"},
  {cache="cache/orre_colosseum_cache.lua",id="orre_colosseum",label="ORRE COLOSSEUM",
    sourceFsys="T1_ancient_colo.fsys",sourceMember="T1_ancient_colo.dat",textureRoot="cache/stages/orre/source",
    minVertices=35000,minGroups=35,maxVertices=280000,maxDisplayOps=1600000,maxSceneRoots=32,maxJobjs=18000,maxDobjs=54000,maxPobjs=90000,
    -- T1_ancient_colo is already a dedicated battle-stage archive.  Preserve
    -- its complete semantic source shell and reject only explicitly identified
    -- no-depth/helper carriers; generic radial trimming was capable of deleting
    -- legitimate upper-bowl / "Colosseum" architecture.
    preserveSourceShell=true,crowdOffsets={[0x10f240]=true,[0x111240]=true}},
  {cache="cache/M3_shrine_1F_bf_cache.lua",id="relic_chamber",label="RELIC CHAMBER",
    sourceFsys="M3_shrine_1F_bf.fsys",sourceMember="M3_shrine_1F_bf.dat",textureRoot="cache/stages/relic_chamber/source",
    -- The retail forest has nested nonuniform scales with inverse child
    -- rotations. HSD parent-scale compensation preserves those authored shapes;
    -- ordinary SRT composition sheared the trees/leaves into giant sheets. Keep
    -- all native scene groups instead of deleting their overlapping bounds.
    honorRenderPass=true,skipShadowMaterials=true,nativeScaleCompensation=true,preserveSourceShell=true,
    minVertices=2000,minGroups=8,maxVertices=360000,maxDisplayOps=1900000,maxSceneRoots=40,maxJobjs=22000,maxDobjs=66000,maxPobjs=110000},
  {cache="cache/M3_cave_1F_1_bf_cache.lua",id="relic_cave",label="RELIC CAVE",
    sourceFsys="M3_cave_1F_1_bf.fsys",sourceMember="M3_cave_1F_1_bf.dat",textureRoot="cache/stages/relic_cave/source",
    nativeScaleCompensation=true,
    minVertices=2000,minGroups=8,maxVertices=280000,maxDisplayOps=1500000,maxSceneRoots=32,maxJobjs=16000,maxDobjs=48000,maxPobjs=80000},
  {cache="cache/S1_out_bf_cache.lua",id="outskirts",label="OUTSKIRTS",
    sourceFsys="S1_out_bf.fsys",sourceMember="S1_out_bf.dat",textureRoot="cache/stages/outskirts/source",
    -- S1_out_bf is already the dedicated retail battle-stage archive. Once HSD
    -- render-pass/shadow filtering has removed dormant carriers, retain every
    -- submitted source group instead of clipping it to a CBE-authored shell.
    honorRenderPass=true,skipShadowMaterials=true,preserveSourceShell=true,
    minVertices=2000,minGroups=8,maxVertices=340000,maxDisplayOps=1800000,maxSceneRoots=36,maxJobjs=20000,maxDobjs=60000,maxPobjs=100000},
  {cache="cache/M2_earth_colo_cache.lua",id="pyrite_colosseum",label="PYRITE COLOSSEUM",
    sourceFsys="M2_earth_colo.fsys",sourceMember="M2_earth_colo.dat",textureRoot="cache/stages/pyrite/source",
    minVertices=8000,minGroups=20,maxVertices=340000,maxDisplayOps=1900000,maxSceneRoots=40,maxJobjs=20000,maxDobjs=60000,maxPobjs=100000},
  {cache="cache/M4_bottom_colo_cache.lua",id="deep_colosseum",label="DEEP COLOSSEUM",
    sourceFsys="M4_bottom_colo.fsys",sourceMember="M4_bottom_colo.dat",textureRoot="cache/stages/deep/source",
    -- Deep is another retail HSD battle scene, not a generic dark room.  Keep
    -- only passes the GameCube would actually submit, otherwise dormant/shadow
    -- carrier geometry fills the outer chamber and reads as the muddy slabs seen
    -- in the 1.9.25-1.9.29 presentation.  Raise the traversal budgets so the
    -- complete rotor/pipe/stand/wall perimeter can survive the canonical cache.
    honorRenderPass=true,skipShadowMaterials=true,
    minVertices=8000,minGroups=20,maxVertices=460000,maxDisplayOps=2600000,maxSceneRoots=64,maxJobjs=30000,maxDobjs=90000,maxPobjs=150000},
  {cache="cache/realgam_colosseum_cache.lua",id="realgam_colosseum",label="REALGAM COLOSSEUM",
    sourceFsys="D4_casino_colo.fsys",sourceMember="D4_casino_colo.dat",textureRoot="cache/stages/realgam/source",
    minVertices=50000,minGroups=100,maxVertices=380000,maxDisplayOps=2100000,maxSceneRoots=40,maxJobjs=22000,maxDobjs=66000,maxPobjs=110000,
    crowdOffsets={[0x0bed60]=true,[0x0c0d60]=true},backdrop={offset=0x09ed60,x=0,y=336,w=512,h=176,path="cache/stages/realgam/source/sky_512x176.rgba"}},
  {cache="cache/D1_labo_B1_bf_cache.lua",id="cipher_lab_underground",label="CIPHER LAB UNDERGROUND",
    sourceFsys="D1_labo_B1_bf.fsys",sourceMember="D1_labo_B1_bf.dat",textureRoot="cache/stages/cipher_lab/source",
    minVertices=30000,minGroups=10,maxVertices=300000,maxDisplayOps=1800000,maxSceneRoots=64,
    maxJobjs=20000,maxDobjs=60000,maxPobjs=100000,honorRenderPass=true,skipShadowMaterials=true},
  {recipe="recipes/arenas/outdoor_wild.lua",cache="cache/outdoor_wild_cache.lua",id="outdoor_wild",label="ORRE WILDLANDS"},
  {cache="cache/D2_mt_battle_platform100_cache.lua",id="mt_battle_summit",label="MT. BATTLE SUMMIT",
    sourceFsys="D2_crater_colo.fsys",sourceMember="D2_crater_colo.dat",textureRoot="cache/stages/d2_crater/textures",
    -- Platform 100 is already the complete retail battle shell. Preserve every
    -- submitted group/triangle in the packed runtime sidecar; later per-fight
    -- presentation rotates this shell rigidly instead of trimming/reassembling it.
    preserveSourceShell=true,
    minVertices=8000,minGroups=20,maxVertices=360000,maxDisplayOps=1900000,maxSceneRoots=40,maxJobjs=18000,maxDobjs=54000,maxPobjs=90000},
}local function clamp(v)return v<0 and 0 or (v>255 and 255 or floor(v+.5)) end
local function rgba(r,g,b,a)return string.char(clamp(r),clamp(g),clamp(b),clamp(a or 255))end
local function hash(s)local h=17;for i=1,#s do h=(h*131+s:byte(i))%104729 end;return h end
local function noise(x,y,seed)return .5+.24*sin((x+seed*.13)*.173)+.16*cos((y-seed*.19)*.137)+.10*sin((x+y+seed)*.071)end
local function checker(x,y,n)return ((floor(x/n)+floor(y/n))%2)==0 and 1 or 0 end
local function makeTexture(path,w,h,kind)
  local out={};local seed=hash(path);local n=0
  local function put(r,g,b,a)n=n+1;out[n]=rgba(r,g,b,a)end
  for y=0,h-1 do for x=0,w-1 do
    local u=x/math.max(1,w-1);local v=y/math.max(1,h-1);local q=noise(x,y,seed);local r,g,b,a=128,128,128,255
    if kind=="metal" then local c=130+55*q+18*checker(x,y,16);r,g,b=c*.88,c*.88,c*.92
    elseif kind=="trim" then local c=115+80*q;r,g,b=c*1.25,c*.82,c*.28
    elseif kind=="truss" then local line=(x%24<4 or y%24<4) and 1 or 0;local c=80+55*q+70*line;r,g,b=c*.75,c*.78,c*.82;a=line==1 and 255 or 0
    elseif kind=="sky" then
      local t=v*v*(3-2*v)
      r=70+(198-70)*t+8*(q-.5);g=80+(205-80)*t+9*(q-.5);b=94+(207-94)*t+11*(q-.5);a=255
    elseif kind=="cloud" then
      local p=.62*q+.24*(.5+.5*sin(x*.055+seed))+.14*(.5+.5*cos(y*.071-seed*.3))
      local c=185+55*p;r,g,b=c,c*.99,c*.97;a=clamp((p-.34)*420)
    elseif kind=="rock" or kind=="rock_dark" then
      -- Organic volcanic relief for Mt. Battle. Keep the texture dense enough
      -- to hold up beside the arena machinery, but avoid any axis-aligned
      -- checker or crossing periodic fields: once this atlas repeats over a
      -- large ridge those patterns read as a literal mesh laid over the rock.
      -- Rotated/warped frequency bands produce strata, mineral breakup and
      -- occasional fissures without a visible square cadence.
      local wx=x+math.sin(y*.031+seed*.017)*9.0+math.sin(y*.009-seed*.023)*5.0
      local wy=y+math.sin(x*.027-seed*.019)*7.0+math.cos(x*.011+seed*.029)*4.0
      local q2=noise(wx*1.37+wy*.23,wy*1.49-wx*.19,seed+37)
      local q3=noise(wx*3.61-wy*.47,wy*3.17+wx*.31,seed+91)
      local mineral=.5+.5*math.sin(wx*.173+wy*.119+math.sin((wx-wy)*.041)*2.1+seed*.071)
      local strata=.5+.5*math.sin(wy*.118+math.sin(wx*.033+seed*.013)*2.55+math.sin((wx+wy)*.014)*1.15)
      local seam=math.abs(math.sin(wx*.052+wy*.021+math.sin(wy*.037)*1.65+seed*.117))
      local fissure=math.max(0,(seam-.905)/.095)
      fissure=fissure*fissure*(3-2*fissure)
      local base=(kind=="rock" and 66 or 43)
      local c=base+45*q+24*q2+12*q3+8*(strata-.5)+5*(mineral-.5)-39*fissure
      local warm=.5+.5*math.sin(wy*.026-wx*.015+seed*.03)
      r=c*(.99+.045*warm);g=c*(.80+.035*strata);b=c*(.77+.032*q3)
    elseif kind=="lava" or kind=="lava_hot" then local wave=.5+.5*sin(x*.11+y*.06+seed);local hot=.55*q+.45*wave;r=190+65*hot;g=45+140*hot;b=8+38*hot
    elseif kind=="meadow" then r,g,b=68+35*q,116+72*q,48+30*q
    elseif kind=="forest" then r,g,b=47+30*q,82+50*q,35+24*q
    elseif kind=="bark" then local stripe=.5+.5*sin(x*.35+seed);r,g,b=72+45*q+20*stripe,48+30*q,30+22*q
    elseif kind:find("leaf",1,true) then
      local dx=(u-.5)*2;local dy=(v-.5)*2;local lobes=.72+.14*sin(math.atan(dy,dx)*5+seed);local d=(dx*dx+dy*dy)^.5;a=d<lobes and clamp(220+35*q) or 0;r,g,b=48+45*q,105+90*q,35+42*q
    else local c=110+80*q;r,g,b=c,c,c end
    put(r,g,b,a)
  end end
  return table.concat(out)
end
local function textureBytes(mod,path,spec)
  local packaged=PACKAGED_TEXTURES[path]
  if packaged then
    local bytes=assert(mod:read(packaged),"missing CBE-authored texture: "..packaged)
    assert(#bytes==spec[1]*spec[2]*4,("bad CBE-authored texture size: %s"):format(packaged))
    return bytes
  end
  return makeTexture(path,spec[1],spec[2],spec[3])
end
local function write(mod,path,data,generated,preserve)
  if preserve and Persist then return Persist.write(mod,"arena",path,data,generated,true) end
  local ok,err=mod.cache:write(path,data);assert(ok,err or ("cache write failed: "..path));if generated then generated[#generated+1]=path end
end
local function num(v)
  v=tonumber(v) or 0
  if v~=v or v==math.huge or v==-math.huge then return "0" end
  if math.abs(v)<0.00000005 then return "0" end
  return string.format("%.8g",v)
end
local function vec(v)
  if type(v)~="table" then return nil end
  local o={"{"};for i=1,#v do if i>1 then o[#o+1]="," end;o[#o+1]=num(v[i]) end;o[#o+1]="}";return table.concat(o)
end
local function sourceAnimKeySort(a,b)
  local ta,tb=type(a),type(b)
  if ta==tb then if ta=="number" then return a<b end;return tostring(a)<tostring(b) end
  return ta<tb
end
local function sourceAnimLiteral(v,depth)
  local t=type(v)
  if t=="nil" then return "nil" elseif t=="boolean" then return v and "true" or "false"
  elseif t=="number" then return num(v) elseif t=="string" then return string.format("%q",v) elseif t~="table" then return "nil" end
  depth=(depth or 0)+1;if depth>12 then return "nil" end
  local keys={};for k in pairs(v) do if type(k)=="string" or type(k)=="number" then keys[#keys+1]=k end end;table.sort(keys,sourceAnimKeySort)
  local out={"{"}
  for _,k in ipairs(keys) do
    local key=type(k)=="number" and ("["..num(k).."]") or ("["..string.format("%q",k).."]")
    out[#out+1]=key.."="..sourceAnimLiteral(v[k],depth)..","
  end
  out[#out+1]="}";return table.concat(out)
end
local function packSourceVertices(rows)
  local out={}
  for ri,v in ipairs(rows or {}) do
    local values={}
    for i=1,#v do values[i]=num(v[i]) end
    out[ri]=table.concat(values,",")
  end
  return table.concat(out,"\n")
end
local function decodeSourceVertices(group)
  if type(group)~="table" then return nil,"arena group missing" end
  if type(group.vertices)=="table" then return group.vertices end
  if type(group.verticesPacked)~="string" then return nil,"arena vertex payload missing" end
  local rows={}
  for line in group.verticesPacked:gmatch("[^\r\n]+") do
    local row={}
    for token in line:gmatch("[^,]+") do
      local value=tonumber(token)
      if value==nil then return nil,"arena packed vertex contains non-number" end
      row[#row+1]=value
    end
    if #row<5 then return nil,"arena packed vertex row is too short" end
    rows[#rows+1]=row
  end
  if #rows==0 then return nil,"arena packed vertex payload empty" end
  group.vertices=rows
  return rows
end
local function materializeSourceArenaVertices(cache)
  if type(cache)~="table" or type(cache.groups)~="table" then return nil,"invalid arena cache" end
  for i,g in ipairs(cache.groups) do
    local rows,why=decodeSourceVertices(g)
    if not rows then return nil,("arena group %d: %s"):format(i,tostring(why)) end
  end
  return cache
end
local function serializeSourceArena(model,source,crowdOriginal)
  -- Keep the canonical cache inspectable without emitting every vertex scalar as
  -- a Lua constant.  Large retail venues such as M2 Earth/Pyrite can exceed
  -- LuaJIT's hard 65,536-constant limit when rows are emitted as nested literals.
  -- One packed string per material group preserves the exact numeric payload and
  -- is expanded only by the build/runtime consumer that actually needs it.
  local out={"-- Generated from the user-supplied Pokemon Colosseum GC6E01 disc.\nreturn {version=33,vertexEncoding=\"packed-csv-v1\",source=",string.format("%q",source),",prototype=false,"}
  if model.textureStateVersion then out[#out+1]="textureStateVersion="..num(model.textureStateVersion).."," end
  local b=model.bounds or {};out[#out+1]="bounds={min="..(vec(b.min) or "{0,0,0}")..",max="..(vec(b.max) or "{0,0,0}").."},"
  out[#out+1]="groupCount="..tostring(#(model.groups or {}))..",vertexCount="..tostring(tonumber(model.vertexCount) or 0)..","
  out[#out+1]="crowdOriginal="..tostring(crowdOriginal or 0)..",crowdPolicy="..string.format("%q",model.crowdPolicy or "source-hsd-crowd")..",groups={\n"
  for _,g in ipairs(model.groups or {}) do
    out[#out+1]="{"
    if g.texture then
      out[#out+1]="texture={path="..string.format("%q",g.texture.path)..",w="..tostring(g.texture.w)..",h="..tostring(g.texture.h)
      if g.texture.wrapS~=nil then out[#out+1]=",wrapS="..tostring(g.texture.wrapS) end
      if g.texture.wrapT~=nil then out[#out+1]=",wrapT="..tostring(g.texture.wrapT) end
      for _,key in ipairs({"coordinateMode","colorMap","alphaMap","blending"}) do
        if g.texture[key]~=nil then out[#out+1]=","..key.."="..num(g.texture[key]) end
      end
      out[#out+1]="},"
    end
    out[#out+1]="alpha="..num(g.alpha or 1)..",xlu="..tostring(g.xlu and true or false)..",noz="..tostring(g.noz and true or false)..","
    out[#out+1]="renderFlags="..tostring(tonumber(g.renderFlags) or 0)..",effect="..tostring(g.effect and true or false)
      ..",useConstant="..tostring(g.useConstant and true or false)..",useVertexColor="..tostring(g.useVertexColor and true or false)
      ..",useDiffuseLighting="..tostring(g.useDiffuseLighting and true or false)..",textureSlot="..tostring(tonumber(g.textureSlot) or -1)..","
    if g.diffuse then out[#out+1]="diffuse="..vec(g.diffuse).."," end
    if g.ambient then out[#out+1]="ambient="..vec(g.ambient).."," end
    if g.specular then out[#out+1]="specular="..vec(g.specular).."," end
    if g.shininess then out[#out+1]="shininess="..num(g.shininess).."," end
    if g.sourceMaterialAnimation then out[#out+1]="sourceMaterialAnimation="..sourceAnimLiteral(g.sourceMaterialAnimation).."," end
    if g.sourceTextureAnimation then out[#out+1]="sourceTextureAnimation="..sourceAnimLiteral(g.sourceTextureAnimation).."," end
    out[#out+1]="verticesPacked="..string.format("%q",packSourceVertices(g.vertices)).."},\n"
  end
  out[#out+1]="}}\n";return table.concat(out)
end
local function cropRGBA(bytes,w,h,x,y,cw,ch)
  x,y,cw,ch=tonumber(x) or 0,tonumber(y) or 0,tonumber(cw) or w,tonumber(ch) or h
  assert(x>=0 and y>=0 and cw>0 and ch>0 and x+cw<=w and y+ch<=h,"invalid source texture crop")
  local rows={};local stride=w*4
  for yy=0,ch-1 do
    local first=(y+yy)*stride+x*4+1
    rows[#rows+1]=bytes:sub(first,first+cw*4-1)
  end
  return table.concat(rows)
end
local function sourceGroupFilter(spec)
  if not spec.sourceRadius then return nil end
  return function(rows,mat)
    local minx,maxx,miny,maxy,minz,maxz=1e30,-1e30,1e30,-1e30,1e30,-1e30
    local sx,sy,sz,n=0,0,0,0
    for _,v in ipairs(rows or {}) do
      local x,y,z=tonumber(v[1]) or 0,tonumber(v[2]) or 0,tonumber(v[3]) or 0
      sx=sx+x;sy=sy+y;sz=sz+z;n=n+1
      minx=math.min(minx,x);maxx=math.max(maxx,x);miny=math.min(miny,y);maxy=math.max(maxy,y);minz=math.min(minz,z);maxz=math.max(maxz,z)
    end
    if n==0 then return false end
    local cx,cy,cz=sx/n,sy/n,sz/n
    local ex,ey,ez=maxx-minx,maxy-miny,maxz-minz
    local span=math.max(ex,ey,ez)

    if spec.keepHighBackdrop and cy>500 and span>3000 then return true end
    if spec.sourceRadius then
      local radial=math.sqrt(cx*cx+cz*cz)
      if radial>spec.sourceRadius or span>(spec.sourceMaxSpan or 1e30) then return false end
    end
    return true
  end
end

-- Runtime arena sidecars are part of the generated cache, not a first-view
-- optimization. The canonical Lua remains the debuggable/authoritative source,
-- but shipping only that source forces a weak device to parse hundreds of
-- thousands of numeric literals, reconstruct normals and rebucket materials at
-- the exact moment a battle scene is opening. Mirror Arena.lua's pure geometry
-- preparation here so every venue can enter from packed float32 on its FIRST
-- runtime load as well as every later one.
local ARENA_RUNTIME_MESH_VERSION=8
local ARENA_RUNTIME_SETTINGS={
  -- Wide source envelopes retain architecture/background depth; runtime still
  -- rejects pathological helper geometry and writes compact f32 sidecars.
  cipher_lab_underground={sceneRadiusRaw=1800,maxGroupSpanRaw=4000,vertexRadiusRaw=1750},
  water={sceneRadiusRaw=1100,maxGroupSpanRaw=2600,vertexRadiusRaw=1050},
  open_water={sceneRadiusRaw=6400,maxGroupSpanRaw=13200,vertexRadiusRaw=6300},
  orre_colosseum={sceneRadiusRaw=3200,maxGroupSpanRaw=7200,vertexRadiusRaw=3100},
  relic_chamber={sceneRadiusRaw=7800,maxGroupSpanRaw=20000,vertexRadiusRaw=7400},
  relic_cave={sceneRadiusRaw=2800,maxGroupSpanRaw=6800,vertexRadiusRaw=2700},
  outskirts={sceneRadiusRaw=16000,maxGroupSpanRaw=42000,vertexRadiusRaw=15000},
  pyrite_colosseum={sceneRadiusRaw=3600,maxGroupSpanRaw=8600,vertexRadiusRaw=3500},
  deep_colosseum={sceneRadiusRaw=12000,maxGroupSpanRaw=32000,vertexRadiusRaw=11500},
  outdoor_wild={sceneRadiusRaw=620,maxGroupSpanRaw=1350,vertexRadiusRaw=610},
  realgam_colosseum={sceneRadiusRaw=4400,maxGroupSpanRaw=9000,vertexRadiusRaw=4300},
  mt_battle_summit={sceneRadiusRaw=7000,maxGroupSpanRaw=15000,vertexRadiusRaw=6900},
}
local runtimeUnpack=table.unpack or unpack
local function runtimeSafeId(id)return tostring(id or "water"):gsub("[^%w_%-]","_")end
local function runtimeRoot(id)return "cache/runtime_mesh_v8/arenas/"..runtimeSafeId(id)end
local function runtimeMetaPath(id)return runtimeRoot(id).."/scene.lua"end
local function runtimeBinPath(id,bucket,i)return runtimeRoot(id)..("/%s_%03d.f32"):format(tostring(bucket),tonumber(i) or 0)end
local SOURCE_ANIMATION_CONTRACT="GC6E01/HSD_MatAnimJoint/clip0/mobj-1-10+tobj-affine/loop-30hz"
local SOURCE_ANIMATION_RUNTIME_MAPPING_REVISION=2
local function sourceAnimationMetaPath(id)return "cache/arena_source_animation/"..runtimeSafeId(id)..".lua"end
local function runtimeRead(mod,path)
  local ok,v=pcall(mod.cache.read,mod.cache,path);if ok and type(v)=="string" then return v end
end
local function runtimeInfo(mod,path)
  local ok,v=pcall(mod.cache.info,mod.cache,path);if ok and type(v)=="table" then return v end
end
local function runtimeReadLua(mod,path)
  local src=runtimeRead(mod,path);if not src then return nil end
  local f=load(src,"@generated/"..path);if not f then return nil end
  local ok,v=pcall(f);if ok then return v end
end
local function sourceAnimationDescriptor(g)
  return {sourceMaterialAnimation=g and g.sourceMaterialAnimation or nil,
    sourceTextureAnimation=g and g.sourceTextureAnimation or nil}
end
local function sourceAnimationDescriptorComplete(g)
  if type(g)~="table" or type(g.sourceMaterialAnimation)~="table" then return false end
  if g.texture and type(g.sourceTextureAnimation)~="table" then return false end
  return true
end
local function sourceAnimationStamp(g)
  if type(g)~="table" then return end
  for _,key in ipairs({"sourceMaterialAnimation","sourceTextureAnimation"}) do
    local a=g[key]
    if type(a)=="table" and a.state=="animated" then a.framesPerSecond=30;a.loop=true end
  end
end
local function sourceAnimationCanonicalMetaUsable(meta,spec,sourceSize,sourceFingerprint)
  return type(meta)=="table" and meta.contract==SOURCE_ANIMATION_CONTRACT
    and tostring(meta.sourceCache or "")==tostring(spec and spec.cache or "")
    and tostring(meta.sourceFsys or "")==tostring(spec and spec.sourceFsys or "")
    and tostring(meta.sourceMember or "")==tostring(spec and spec.sourceMember or "")
    and tonumber(meta.sourceSize)==tonumber(sourceSize)
    and sourceFingerprint~=nil and meta.sourceFingerprint==sourceFingerprint
    and type(meta.canonical)=="table"
end
local function sourceAnimationMetaUsable(meta,spec,sourceSize,sourceFingerprint)
  return sourceAnimationCanonicalMetaUsable(meta,spec,sourceSize,sourceFingerprint)
    and tonumber(meta.runtimeMappingRevision)==SOURCE_ANIMATION_RUNTIME_MAPPING_REVISION
    and type(meta.runtime)=="table" and type(meta.runtimeMapping)=="table"
end
local function applyCanonicalAnimationMetadata(cache,meta,sourceSize,sourceFingerprint,spec)
  if not sourceAnimationMetaUsable(meta,spec,sourceSize,sourceFingerprint) then return false end
  if type(cache)~="table" or type(cache.groups)~="table" or #cache.groups~=#meta.canonical then return false end
  for i,g in ipairs(cache.groups) do
    local row=meta.canonical[i]
    if type(row)~="table" then return false end
    g.sourceMaterialAnimation=row.sourceMaterialAnimation
    g.sourceTextureAnimation=row.sourceTextureAnimation
  end
  return true
end
local function runtimeUsable(mod,meta,spec,sourceSize,sourceFingerprint)
  if type(meta)~="table" or tonumber(meta.runtimeMeshVersion)~=ARENA_RUNTIME_MESH_VERSION then return false end
  if tonumber(meta.sourceSize)~=tonumber(sourceSize) or tostring(meta.sourceCache or "")~=tostring(spec.cache or "") then return false end
  if not sourceFingerprint or meta.sourceFingerprint~=sourceFingerprint then return false end
  -- Source-shell ownership is semantic cache identity, not presentation-only
  -- metadata. Rebuild an older v8 sidecar if a venue moves from radius-clipped
  -- geometry to complete retail shell retention.
  if (meta.preserveSourceShell==true)~=(spec.preserveSourceShell==true) then return false end
  if spec.id=="water" and meta.audienceRevision~=2 then return false end
  local total=0
  for _,bucket in ipairs({"opaque","cutout","crowd","translucent","additive"}) do
    local rows=meta[bucket];if type(rows)~="table" then return false end
    for i,g in ipairs(rows) do
      local path=type(g)=="table" and (g.runtimeBin or runtimeBinPath(spec.id,bucket,i)) or nil
      local info=path and runtimeInfo(mod,path) or nil;if not info then return false end;local size=tonumber(info.size)
      if size and (size<144 or size%48~=0) then return false end
      total=total+1
    end
  end
  return total>0
end
local function runtimeAlphaInfo(bytes)
  local hasZero,hasFraction=false,false
  for i=4,#(bytes or ""),4 do local a=bytes:byte(i);if a==0 then hasZero=true elseif a and a<255 then hasFraction=true;break end end
  return hasZero and not hasFraction,hasFraction
end
local function runtimeGroupStats(vertices)
  local x,y,z,n=0,0,0,0
  local minx,maxx,miny,maxy,minz,maxz=math.huge,-math.huge,math.huge,-math.huge,math.huge,-math.huge
  for _,v in ipairs(vertices or {}) do
    local vx,vy,vz=tonumber(v[1]) or 0,tonumber(v[2]) or 0,tonumber(v[3]) or 0
    x=x+vx;y=y+vy;z=z+vz;n=n+1
    minx=math.min(minx,vx);maxx=math.max(maxx,vx);miny=math.min(miny,vy);maxy=math.max(maxy,vy);minz=math.min(minz,vz);maxz=math.max(maxz,vz)
  end
  if n==0 then return {0,0,0},0,{0,0,0},{0,0,0} end
  local extent={maxx-minx,maxy-miny,maxz-minz}
  return {x/n,y/n,z/n},math.max(extent[1],extent[2],extent[3]),extent,
    {(minx+maxx)*.5,(miny+maxy)*.5,(minz+maxz)*.5}
end
local function runtimeCrowdPhases(vertices)
  local n=#(vertices or {});if n<3 then return nil end
  local parent={};for i=1,n do parent[i]=i end
  local function find(a)while parent[a]~=a do parent[a]=parent[parent[a]];a=parent[a] end;return a end
  local function union(a,b)a,b=find(a),find(b);if a~=b then parent[b]=a end end
  local first={};local function key(v)return ("%.3f|%.3f|%.3f"):format(tonumber(v[1]) or 0,tonumber(v[2]) or 0,tonumber(v[3]) or 0) end
  for i,v in ipairs(vertices or {}) do local k=key(v);if first[k] then union(i,first[k]) else first[k]=i end end
  for i=1,n,3 do if vertices[i+2] then union(i,i+1);union(i,i+2) end end
  local comps={}
  for i,v in ipairs(vertices or {}) do local r=find(i);local c=comps[r];if not c then c={sx=0,sy=0,sz=0,n=0,idx={}};comps[r]=c end
    c.sx=c.sx+(tonumber(v[1]) or 0);c.sy=c.sy+(tonumber(v[2]) or 0);c.sz=c.sz+(tonumber(v[3]) or 0);c.n=c.n+1;c.idx[#c.idx+1]=i end
  local phase={}
  for _,c in pairs(comps) do local cx,cy,cz=c.sx/math.max(1,c.n),c.sy/math.max(1,c.n),c.sz/math.max(1,c.n)
    local h=math.sin(cx*.173+cy*.311+cz*.137)*43758.5453;local q=h-math.floor(h);for _,i in ipairs(c.idx) do phase[i]=q end end
  return phase
end
local function runtimeWithNormals(vertices,mode,vertexRadius)
  local out={};local v=vertices or {};local crowdPhase=(mode==4) and runtimeCrowdPhases(v) or nil
  -- Source audience cards are authored outside the central battle-disc radius.
  -- Once their source atlas identifies the group as crowd, radius clipping is
  -- not a fidelity or safety filter; it simply removes seats.  Group-level
  -- source-shell validation still applies before this function is called.
  local radius=(mode==4) and math.huge or (tonumber(vertexRadius) or math.huge)
  for i=1,#v,3 do local a,b,c=v[i],v[i+1],v[i+2]
    if a and b and c then
      local ar=math.sqrt((a[1] or 0)^2+(a[3] or 0)^2);local br=math.sqrt((b[1] or 0)^2+(b[3] or 0)^2);local cr=math.sqrt((c[1] or 0)^2+(c[3] or 0)^2)
      if math.min(ar,br,cr)<=radius then
        local abx,aby,abz=(b[1] or 0)-(a[1] or 0),(b[2] or 0)-(a[2] or 0),(b[3] or 0)-(a[3] or 0)
        local acx,acy,acz=(c[1] or 0)-(a[1] or 0),(c[2] or 0)-(a[2] or 0),(c[3] or 0)-(a[3] or 0)
        local nx=aby*acz-abz*acy;local ny=abz*acx-abx*acz;local nz=abx*acy-aby*acx;local len=math.sqrt(nx*nx+ny*ny+nz*nz)
        if len<.000001 then nx,ny,nz=0,1,0 else nx,ny,nz=nx/len,ny/len,nz/len end
        for j,src in ipairs({a,b,c}) do
          local r,g,bv,av=1,1,1,1;local vnx,vny,vnz=nx,ny,nz
          if #src>=12 then
            r,g,bv,av=src[6] or 1,src[7] or 1,src[8] or 1,src[9] or 1
            vnx,vny,vnz=src[10] or nx,src[11] or ny,src[12] or nz
            local nl=math.sqrt(vnx*vnx+vny*vny+vnz*vnz)
            if nl>0.000001 then vnx,vny,vnz=vnx/nl,vny/nl,vnz/nl else vnx,vny,vnz=nx,ny,nz end
          elseif #src>=9 then r,g,bv,av=src[6] or 1,src[7] or 1,src[8] or 1,src[9] or 1
          elseif #src==8 then vnx,vny,vnz=src[6] or nx,src[7] or ny,src[8] or nz;local nl=math.sqrt(vnx*vnx+vny*vny+vnz*vnz);if nl>.000001 then vnx,vny,vnz=vnx/nl,vny/nl,vnz/nl else vnx,vny,vnz=nx,ny,nz end end
          if crowdPhase then
            -- Keep source RGBA intact. Normal direction is unchanged; its
            -- length carries card phase, decoded before shader normalization.
            local scale=1+(crowdPhase[i+j-1] or .5)
            vnx,vny,vnz=vnx*scale,vny*scale,vnz*scale
          end
          out[#out+1]={src[1] or 0,src[2] or 0,src[3] or 0,src[4] or 0,src[5] or 0,r,g,bv,av,vnx,vny,vnz}
        end
      end
    end
  end
  return out
end
local function runtimeSourcePath(g)return g and g.texture and tostring(g.texture.path or "") or ""end
local function runtimeSourceGroundShadow(g,arenaId)
  if (arenaId~="outskirts" and arenaId~="orre_colosseum") or g.texture or not g.xlu or not g.noz then return false end
  local rows=g.vertices or {};if #rows<3 then return false end
  for _,v in ipairs(rows) do
    local y=tonumber(v[2]);if not y or y<-.1 or y>3 then return false end
  end
  return true
end
local function runtimeDropGhost(g,arenaId)
  local path=runtimeSourcePath(g)
  if not g.texture and g.xlu and g.noz then return not runtimeSourceGroundShadow(g,arenaId) end
  if path:find("tex_05db60_",1,true) and g.xlu and g.noz then return true end
  if path:find("cache/stages/orre/source/tex_055ec0_",1,true) then return true end
  if path:find("cache/stages/realgam/source/tex_0d4560_",1,true) and g.xlu and g.noz then return true end
  return false
end
local function runtimeMaterialDetail(g)
  local path=runtimeSourcePath(g)
  -- Do not sharpen source-backed HSD atlases: 1:1 texture fidelity is more
  -- important than synthetic close-detail. Wildlands is intentionally authored.
  if path:find("cache/stages/wildlands/ground_",1,true) or path:find("cache/stages/wildlands/bark_",1,true) then return 1 end
  return 0
end
local function runtimeMaterialMode(g,binaryAlpha,arenaId)
  local path=runtimeSourcePath(g)
  if binaryAlpha and path:find("cache/stages/d2_crater/textures/tex_0fd8e0_",1,true) then return 3 end
  if binaryAlpha and (path:find("cache/stages/wildlands/leaf_cluster_",1,true) or path:find("cache/stages/wildlands/grass_tuft_",1,true)) then return 3.25 end
  if path:find("cache/stages/d2_crater/textures/tex_0ca920_",1,true) or path:find("cache/stages/d2_crater/textures/tex_0be120_",1,true) or path:find("cache/stages/d2_crater/textures/tex_0ea920_",1,true) then return 5 end
  if path:find("cache/stages/d2_crater/textures/tex_0ce920_",1,true) or path:find("cache/stages/d2_crater/textures/tex_061ec0_",1,true) or path:find("cache/stages/d2_crater/textures/tex_0f4120_",1,true) or path:find("cache/stages/d2_crater/textures/tex_07cec0_",1,true) then return 0 end
  if path:find("tex_0cbb60_",1,true) then return 2 end
  if path:find("tex_0cdb60_",1,true) or path:find("tex_081b60_",1,true) then return 1 end
  -- Exact arena+offset identity is stronger evidence than an alpha-shape
  -- heuristic. Source crowd atlases can contain fractional antialiasing and are
  -- still retail audience cards.
  if V.ArenaAudienceProfile and V.ArenaAudienceProfile.classifySourceTexture(arenaId,path) then return 4 end
  if binaryAlpha and (path:find("tex_05c560_",1,true) or path:find("/source/",1,true)) then return 3 end
  return 0
end
local function runtimePackRows(rows)
  local lovePack=love and love.data and type(love.data.pack)=="function" and love.data.pack or nil
  local luaPack=type(string.pack)=="function" and string.pack or nil
  if not lovePack and not luaPack then return nil,"float32 pack unavailable" end
  local stride=12
  -- Keep the same packed f32 bytes while avoiding very large Lua/LuaJIT vararg
  -- calls on mobile. 64 rows x 12 floats used to expand to 768 scalar arguments
  -- before pcall() could catch anything; the shared runtime-mesh path already
  -- proved a 192-scalar cap is a safer cross-platform boundary.
  local batch=math.max(1,math.floor(192/stride));local rowFmt=string.rep("f",stride);local batchFmt=string.rep(rowFmt,batch);local buf,chunks={},{};local i=1
  while i<=#rows do local take=math.min(batch,#rows-i+1);local k=0
    for r=i,i+take-1 do local row=rows[r];for j=1,stride do local v=tonumber(row[j]) or 0;if v~=v or v==math.huge or v==-math.huge then v=0 end;k=k+1;buf[k]=v end end
    local fmt=take==batch and batchFmt or string.rep(rowFmt,take);local ok,bytes
    if lovePack then ok,bytes=pcall(lovePack,"string",fmt,runtimeUnpack(buf,1,k)) end
    if (not ok or type(bytes)~="string") and luaPack then ok,bytes=pcall(luaPack,"<"..fmt,runtimeUnpack(buf,1,k)) end
    if not ok or type(bytes)~="string" then return nil,tostring(bytes) end
    chunks[#chunks+1]=bytes;i=i+take
  end
  return table.concat(chunks)
end
local function runtimeKeySort(a,b)local ta,tb=type(a),type(b);if ta==tb then return tostring(a)<tostring(b) end;return ta<tb end
local function runtimeSerialize(v,seen,depth)
  local t=type(v);if t=="nil" then return "nil" elseif t=="boolean" then return v and "true" or "false" elseif t=="number" then return num(v) elseif t=="string" then return string.format("%q",v) elseif t~="table" then return "nil" end
  depth=(depth or 0)+1;if depth>24 then return "nil" end;seen=seen or {};if seen[v] then return "nil" end;seen[v]=true
  local keys={};for k in pairs(v) do if type(k)=="string" or type(k)=="number" then keys[#keys+1]=k end end;table.sort(keys,runtimeKeySort)
  local out={"{"};for _,k in ipairs(keys) do local ks=type(k)=="number" and ("["..num(k).."]") or ("["..string.format("%q",k).."]");out[#out+1]=ks.."="..runtimeSerialize(v[k],seen,depth).."," end
  out[#out+1]="}";seen[v]=nil;return table.concat(out)
end
local function runtimeCompactEntry(g,textureSpec,bin)
  -- Keep the explicit pass bit: compact numeric renderFlags can round below
  -- the XLU boundary (0x40000000). Feathered authored alpha must survive reload.
  return {runtimeBin=bin,texture=textureSpec,alpha=g.alpha,xlu=g.xlu,noz=g.noz,center=g.center,boundsCenter=g.boundsCenter,span=g.span,extent=g.extent,mode=g.mode,flow=g.flow,detail=g.detail,texelStep=g.texelStep,
    diffuse=g.diffuse,ambient=g.ambient,specular=g.specular,shininess=g.shininess,renderFlags=g.renderFlags,effect=g.effect,
    useConstant=g.useConstant,useVertexColor=g.useVertexColor,useDiffuseLighting=g.useDiffuseLighting,textureSlot=g.textureSlot,
    sourceMaterialAnimation=g.sourceMaterialAnimation,sourceTextureAnimation=g.sourceTextureAnimation}
end
local buildSourceArenaFromDisc
local function loadCanonicalArena(mod,spec,src,disc,progress,generated)
  local function parse(bytes)
    local chunk,err=load(bytes,"@generated/"..tostring(spec.cache));if not chunk then return nil,err end
    local ok,cache=pcall(chunk)
    if not ok or type(cache)~="table" then return nil,tostring(cache or "invalid arena cache") end
    local materialized,why=materializeSourceArenaVertices(cache)
    if not materialized then return nil,why end
    return cache
  end
  local cache,why=parse(src)
  if cache then return src,cache,false end
  -- Old source arenas may be perfectly valid data serialized in the historical
  -- nested-number format, yet be impossible for LuaJIT to compile because the
  -- generated chunk exceeds 65,536 constants.  Repair only that canonical arena
  -- from the user's retained GC6E01 source and preserve the old bytes first.
  if spec.sourceFsys and disc and buildSourceArenaFromDisc then
    if progress then progress((spec.label or spec.id:upper()).." / CANONICAL CACHE REBUILD",0,1) end
    buildSourceArenaFromDisc(mod,disc,progress,generated,spec,true)
    local repaired=runtimeRead(mod,spec.cache)
    if type(repaired)~="string" then return nil,nil,false,"source arena rebuild produced no canonical cache" end
    local fixed,after=parse(repaired)
    if fixed then return repaired,fixed,true end
    return nil,nil,false,("arena canonical cache still unreadable after source rebuild: %s"):format(tostring(after))
  end
  return nil,nil,false,tostring(why)
end
local function writeRuntimeSidecarFromCache(mod,spec,cache,sourceSize,generated,progress,sourceFingerprint,preserveExisting)
  local settings=ARENA_RUNTIME_SETTINGS[spec.id] or ARENA_RUNTIME_SETTINGS.water
  local preserveShell=spec.preserveSourceShell==true and cache.crowdPolicy=="source-hsd-crowd"
  local runtimeRows={opaque={},cutout={},crowd={},translucent={},additive={}};local textureAlpha={}
  local culled,oversizeCulled,crowdOutliers,crowdKept=0,0,0,0
  for gi,g in ipairs(cache.groups or {}) do
    if progress and (gi==1 or gi%24==0 or gi==#cache.groups) then progress((spec.label or spec.id:upper()).." / RUNTIME MESH",gi,#cache.groups) end
    local center,span,extent,boundsCenter=runtimeGroupStats(g.vertices);local radial=math.sqrt((center[1] or 0)^2+(center[3] or 0)^2)
    local sourcePath=runtimeSourcePath(g)
    local sourceAudience=V.ArenaAudienceProfile and V.ArenaAudienceProfile.classifySourceTexture
      and V.ArenaAudienceProfile.classifySourceTexture(spec.id,sourcePath)~=nil
    -- Audience banks are authored outside the central fight disc in several
    -- Colosseums (notably Water).  Once the exact arena+atlas identity proves
    -- that a group is source audience, generic shell-radius trimming must not
    -- delete it before the crowd material path even sees it.
    local preserveGroup=preserveShell or sourceAudience
    if ((not preserveGroup) and (radial>settings.sceneRadiusRaw or span>settings.maxGroupSpanRaw)) or runtimeDropGhost(g,spec.id) then culled=culled+1;if (not preserveGroup) and span>settings.maxGroupSpanRaw then oversizeCulled=oversizeCulled+1 end
    else
      local path=g.texture and g.texture.path;local binaryAlpha=false
      if path then
        local known=textureAlpha[path]
        if known==nil then local bytes=runtimeRead(mod,path);known=bytes and select(1,runtimeAlphaInfo(bytes)) or false;textureAlpha[path]=known end
        binaryAlpha=known==true
      end
      local mode=runtimeMaterialMode(g,binaryAlpha,spec.id);local rows=runtimeWithNormals(g.vertices,mode,preserveGroup and math.huge or settings.vertexRadiusRaw)
      if #rows==0 then culled=culled+1
      else
        local detail=runtimeMaterialDetail(g);local tw=(g.texture and tonumber(g.texture.w)) or 1;local th=(g.texture and tonumber(g.texture.h)) or 1
        local maxXZ=math.max((extent and extent[1]) or 0,(extent and extent[3]) or 0);local inferred=((mode==1 or mode==5) and extent and (extent[2] or 0)>math.max(35,maxXZ*1.30)) and 1 or 0
        local flow=(g.flow~=nil) and tonumber(g.flow) or inferred;flow=flow or 0
        if mode>3.10 and mode<3.40 then local wp=tostring(g.texture and g.texture.path or "");flow=wp:find("grass_tuft_",1,true) and 1 or .35 end
        local entry={alpha=tonumber(g.alpha) or 1,xlu=g.xlu,noz=g.noz and true or false,center=center,boundsCenter=boundsCenter,span=span,extent=extent,mode=mode,flow=flow,detail=detail,texelStep={1/math.max(1,tw),1/math.max(1,th)},diffuse=g.diffuse or {1,1,1},ambient=g.ambient or {1,1,1},specular=g.specular or {0,0,0},shininess=tonumber(g.shininess) or 0,renderFlags=tonumber(g.renderFlags) or 0,effect=g.effect and true or false,useConstant=g.useConstant and true or false,useVertexColor=g.useVertexColor and true or false,useDiffuseLighting=g.useDiffuseLighting~=false,textureSlot=tonumber(g.textureSlot) or -1,sourceMaterialAnimation=g.sourceMaterialAnimation,sourceTextureAnimation=g.sourceTextureAnimation}
        local bucket
        if mode==2 then bucket="additive" elseif mode==1 and spec.id=="open_water" and not g.xlu then bucket="opaque" elseif mode==1 then bucket="translucent" elseif mode==4 then
          local cpath=tostring(g.texture and g.texture.path or "");if cache.crowdPolicy=="source-hsd-crowd" or spec.id~="water" or (center[2] or 0)<=84 then bucket="crowd" else culled=culled+1;crowdOutliers=crowdOutliers+1 end
        elseif mode>=3 and mode<3.5 then bucket="cutout" elseif not g.xlu then bucket="opaque" else bucket="translucent" end
        if bucket then
          local ri=#runtimeRows[bucket]+1;local bin=runtimeBinPath(spec.id,bucket,ri);local bytes,perr=runtimePackRows(rows);assert(bytes,perr or "arena runtime pack failed")
          write(mod,bin,bytes,generated,preserveExisting);runtimeRows[bucket][ri]=runtimeCompactEntry(entry,g.texture,bin);if bucket=="crowd" then crowdKept=crowdKept+1 end
        end
      end
    end
  end
  local meta={runtimeMeshVersion=ARENA_RUNTIME_MESH_VERSION,audienceRevision=2,textureStateVersion=cache.textureStateVersion,sourceFingerprint=sourceFingerprint,sourceSize=sourceSize,sourceCache=spec.cache,bounds=cache.bounds,source=cache.source,
    culled=culled,oversizeCulled=oversizeCulled,crowdOutliers=crowdOutliers,crowdOriginal=tonumber(cache.crowdOriginal) or 0,crowdKept=crowdKept,
    crowdPolicy=cache.crowdPolicy or "none",preserveSourceShell=preserveShell,
    opaque=runtimeRows.opaque,cutout=runtimeRows.cutout,crowd=runtimeRows.crowd,translucent=runtimeRows.translucent,additive=runtimeRows.additive}
  write(mod,runtimeMetaPath(spec.id),"return "..runtimeSerialize(meta).."\n",generated,preserveExisting)
  return true
end
function A.runtimeSidecars(mod,progress,generated,disc)
  generated=generated or {};progress=progress or function()end
  local built,kept=0,0
  for i,spec in ipairs(ARENAS) do
    local src=assert(runtimeRead(mod,spec.cache),"missing arena source cache for runtime sidecar: "..tostring(spec.cache));local sourceSize=#src;local sourceFingerprint=assert(V.ArenaCacheIdentity,"arena cache identity module missing").fingerprint(src)
    local prior=runtimeReadLua(mod,runtimeMetaPath(spec.id))
    if runtimeUsable(mod,prior,spec,sourceSize,sourceFingerprint) then kept=kept+1;progress((spec.label or spec.id:upper()).." / RUNTIME MESH REUSED",i,#ARENAS)
    else
      progress((spec.label or spec.id:upper()).." / RUNTIME MESH PREP",i-1,#ARENAS)
      local loaded,cache,_,loadWhy=loadCanonicalArena(mod,spec,src,disc,progress,generated)
      assert(cache,loadWhy or "invalid arena cache")
      if loaded~=src then
        src=loaded;sourceSize=#src;sourceFingerprint=assert(V.ArenaCacheIdentity,"arena cache identity module missing").fingerprint(src)
      end
      local animMeta=runtimeReadLua(mod,sourceAnimationMetaPath(spec.id))
      if animMeta then applyCanonicalAnimationMetadata(cache,animMeta,sourceSize,sourceFingerprint,spec) end
      -- An invalid runtime sidecar is repaired in place, not reset. Preserve
      -- every concrete target byte on the repair path even when scene.lua is
      -- the one missing member of an interrupted transaction: packed .f32
      -- siblings can already exist without a readable metadata root.  This is
      -- bounded point-I/O only on repair; the normal runtimeUsable fast path
      -- above still performs no preservation reads/writes.
      local preserveRuntime=Persist~=nil
      writeRuntimeSidecarFromCache(mod,spec,cache,sourceSize,generated,progress,sourceFingerprint,preserveRuntime);cache=nil;built=built+1
    end
  end
  write(mod,"build/arena_runtime_sidecars.lua",("return {version=%d,built=%d,reused=%d,total=%d}\n"):format(ARENA_RUNTIME_MESH_VERSION,built,kept,#ARENAS),generated)
  return {ready=true,built=built,reused=kept,total=#ARENAS}
end

local function sourceAnimationNear(a,b)
  a,b=tonumber(a),tonumber(b);if not (a and b) then return a==b end
  local scale=math.max(1,math.abs(a),math.abs(b));return math.abs(a-b)<=scale*2e-6
end
local function sourceAnimationVecNear(a,b)
  if type(a)~="table" or type(b)~="table" then return a==b end
  if #a~=#b then return false end
  for i=1,#a do if not sourceAnimationNear(a[i],b[i]) then return false end end
  return true
end
local function expectedSourceTexturePath(spec,t)
  if not (spec and spec.textureRoot and t and t.dataOffset and t.w and t.h) then return nil end
  return ("%s/tex_%06x_%dx%d_f%d.rgba"):format(spec.textureRoot,t.dataOffset,t.w,t.h,t.format or 0)
end
local function sourceAnimationGroupsAligned(spec,cached,source)
  if type(cached)~="table" or type(source)~="table" then return false,"group unavailable" end
  local cv,sv=cached.vertices or {},source.vertices or {}
  if #cv~=#sv then return false,"vertex count changed" end
  if tonumber(cached.renderFlags or 0)~=tonumber(source.renderFlags or 0) then return false,"render flags changed" end
  local cpath=cached.texture and tostring(cached.texture.path or "") or ""
  local spath=expectedSourceTexturePath(spec,source.texture) or ""
  if cpath~=spath then return false,("texture identity changed (%s != %s)"):format(cpath,spath) end
  for _,idx in ipairs({1,math.max(1,math.floor(#cv/2)),#cv}) do
    local a,b=cv[idx],sv[idx]
    if a and b then
      for k=1,math.min(5,#a,#b) do if not sourceAnimationNear(a[k],b[k]) then return false,("vertex sample changed at %d/%d"):format(idx,k) end end
    end
  end
  return true
end
local function runtimeAnimationEntryMatches(g,row)
  if type(g)~="table" or type(row)~="table" then return false end
  local center,span,extent=runtimeGroupStats(g.vertices)
  if not sourceAnimationVecNear(center,row.center or {}) or not sourceAnimationNear(span,row.span) or not sourceAnimationVecNear(extent,row.extent or {}) then return false end
  local gp=g.texture and tostring(g.texture.path or "") or "";local rp=row.texture and tostring(row.texture.path or "") or ""
  -- Runtime scene.lua uses the compact `num()` serializer. Large unsigned HSD
  -- render flags therefore round at the 8-significant-digit boundary (for
  -- example D2's exact 0x60006031/1610637361 persists as 1610637400). Comparing
  -- the unrounded canonical integer to that persisted value made otherwise
  -- identical D2 lava groups fail ownership and deliberately blocked their real
  -- 800-frame HSD_TexAnim. Match the representation that the runtime sidecar
  -- actually owns; every other geometry/material field below still participates
  -- in the immutable signature, so this does not degrade to a texture-only guess.
  local serializedRenderFlags=tonumber(num(g.renderFlags or 0)) or 0
  if gp~=rp or serializedRenderFlags~=tonumber(row.renderFlags or 0) or tonumber(g.textureSlot or -1)~=tonumber(row.textureSlot or -1) then return false end
  if not sourceAnimationNear(g.alpha or 1,row.alpha or 1) or (g.noz and true or false)~=(row.noz and true or false) then return false end
  if (g.useConstant and true or false)~=(row.useConstant and true or false)
      or (g.useVertexColor and true or false)~=(row.useVertexColor and true or false)
      or (g.useDiffuseLighting~=false)~=(row.useDiffuseLighting~=false) then return false end
  if row.diffuse and not sourceAnimationVecNear(g.diffuse or {1,1,1},row.diffuse) then return false end
  if row.ambient and not sourceAnimationVecNear(g.ambient or {1,1,1},row.ambient) then return false end
  if row.specular and not sourceAnimationVecNear(g.specular or {0,0,0},row.specular) then return false end
  return sourceAnimationNear(g.shininess or 0,row.shininess or 0)
end
local function blockedRuntimeAnimationDescriptor()
  -- Legacy runtime sidecars did not persist a canonical group/source-DObj id.
  -- When the complete immutable signature below cannot prove ownership, never
  -- fall back to bucket ordinal/texture-only guesses: mark the optional runtime
  -- animation state as audited-but-unresolved so Arena.lua suppresses synthetic
  -- UV/material motion while leaving the packed runtime mesh usable.
  return {sourceMaterialAnimation={revision=1,state="blocked"},
    sourceTextureAnimation={revision=1,state="blocked"}}
end
local function buildRuntimeAnimationOverlay(cache,canonical,runtimeMeta)
  if type(runtimeMeta)~="table" then return {},{matched=0,blockedMissing=0,blockedAmbiguous=0} end
  local out={};local report={matched=0,blockedMissing=0,blockedAmbiguous=0}
  for _,bucket in ipairs({"opaque","cutout","crowd","translucent","additive"}) do
    out[bucket]={}
    for i,row in ipairs(runtimeMeta[bucket] or {}) do
      local selected,signature,ambiguous=nil,nil,false
      for gi,g in ipairs(cache.groups or {}) do
        if runtimeAnimationEntryMatches(g,row) then
          local desc=canonical[gi];local sig=sourceAnimLiteral(desc)
          if signature and signature~=sig then ambiguous=true;break end
          selected,signature=desc,sig
        end
      end
      if ambiguous then
        out[bucket][i]=blockedRuntimeAnimationDescriptor();report.blockedAmbiguous=report.blockedAmbiguous+1
      elseif not selected then
        out[bucket][i]=blockedRuntimeAnimationDescriptor();report.blockedMissing=report.blockedMissing+1
      else
        out[bucket][i]=selected;report.matched=report.matched+1
      end
    end
  end
  return out,report
end
local function extractSourceAnimationDescriptors(mod,disc,spec,cache,progress)
  assert(HSD and FSYS,"source HSD arena animation extractor unavailable")
  local file=assert(disc:file(spec.sourceFsys),spec.sourceFsys.." missing from GC6E01")
  local arc=FSYS.open(disc,file)
  local entry=arc:member(spec.sourceMember) or arc:member((spec.sourceMember or ""):gsub("%.dat$",""))
  if not (entry and entry.modelKind) then for _,e in ipairs(arc:modelEntries()) do if e.fileType==0x02 then entry=e;break end end end
  assert(entry and entry.modelKind,(spec.sourceMember or spec.id).." model member missing")
  local blob=arc:extract(entry,{maxOutput=64*1024*1024})
  local model,err=HSD.extractSceneModel(blob,{
    preserveVertexColors=true,textures=true,sourceTextureState=true,sourceTextureMetadataOnly=true,
    sourceMaterialAnimation=true,sourceTextureAnimation=true,nativeSceneInstances=true,
    maxSceneRoots=spec.maxSceneRoots or 16,maxVertices=spec.maxVertices or 180000,
    maxDisplayOps=spec.maxDisplayOps or 700000,maxJobjs=spec.maxJobjs or 6000,maxDobjs=spec.maxDobjs or 16000,maxPobjs=spec.maxPobjs or 28000,
    groupFilter=sourceGroupFilter(spec),honorRenderPass=spec.honorRenderPass==true,skipShadowMaterials=spec.skipShadowMaterials==true,
    nativeScaleCompensation=spec.nativeScaleCompensation==true,
    progress=function(c,t) if progress then progress((spec.label or spec.id:upper()).." / ANIMATION MODELSET",c,t) end end,
  })
  assert(model,err or ((spec.label or spec.id).." HSD animation metadata decode failed"))
  assert(#(cache.groups or {})==#(model.groups or {}),("%s animation metadata topology changed (%d != %d groups)"):format(spec.id,#(cache.groups or {}),#(model.groups or {})))
  local canonical={}
  for i,g in ipairs(model.groups or {}) do
    local aligned,why=sourceAnimationGroupsAligned(spec,cache.groups[i],g);assert(aligned,("%s group %d metadata alignment failed: %s"):format(spec.id,i,tostring(why)))
    sourceAnimationStamp(g);canonical[i]=sourceAnimationDescriptor(g)
  end
  return canonical
end
local function augmentSourceAnimationForSpec(mod,disc,spec,generated,progress)
  local src=assert(runtimeRead(mod,spec.cache),"missing arena source cache for animation metadata: "..tostring(spec.cache))
  local identity=assert(V.ArenaCacheIdentity,"arena cache identity module missing")
  local sourceFingerprint=identity.fingerprint(src);local sourceSize=#src
  local prior=runtimeReadLua(mod,sourceAnimationMetaPath(spec.id))
  if sourceAnimationMetaUsable(prior,spec,sourceSize,sourceFingerprint) then return {reused=true,path=sourceAnimationMetaPath(spec.id)} end
  local loaded,cache,rebuilt,loadWhy=loadCanonicalArena(mod,spec,src,disc,progress,generated)
  assert(cache,loadWhy or "invalid arena cache")
  if loaded~=src then
    src=loaded;sourceFingerprint=identity.fingerprint(src);sourceSize=#src
    -- Prior metadata belongs to the unreadable canonical byte stream that was
    -- just replaced from GC6E01. Do not project it onto the repaired topology.
    prior=nil
  end
  local canonical,fromSource=nil,false
  -- Mapping revision 2 only changes how an already-decoded canonical descriptor
  -- is associated with the packed runtime sidecar. If the prior overlay is tied
  -- to the exact same canonical bytes + GC6E01 member, reuse its canonical HSD
  -- descriptors and repair the tiny mapping overlay without reopening/decompressing
  -- the disc. This is the normal 1.3.10 migration path and keeps Android repair
  -- bounded to metadata I/O.
  if sourceAnimationCanonicalMetaUsable(prior,spec,sourceSize,sourceFingerprint)
      and #prior.canonical==#(cache.groups or {}) then
    canonical=prior.canonical
  else
    canonical={};local embedded=true
    for i,g in ipairs(cache.groups or {}) do
      if not sourceAnimationDescriptorComplete(g) then embedded=false;break end
      sourceAnimationStamp(g);canonical[i]=sourceAnimationDescriptor(g)
    end
    if not embedded then canonical=extractSourceAnimationDescriptors(mod,disc,spec,cache,progress);fromSource=true end
  end
  local runtimeRaw=runtimeRead(mod,runtimeMetaPath(spec.id));local runtimeMeta=runtimeRaw and runtimeReadLua(mod,runtimeMetaPath(spec.id)) or nil
  local runtime,runtimeMapping=buildRuntimeAnimationOverlay(cache,canonical,runtimeMeta);assert(runtime,"runtime animation overlay unavailable")
  local meta={contract=SOURCE_ANIMATION_CONTRACT,sourceCache=spec.cache,sourceSize=sourceSize,sourceFingerprint=sourceFingerprint,
    sourceFsys=spec.sourceFsys,sourceMember=spec.sourceMember,canonical=canonical,runtime=runtime,
    runtimeMetaFingerprint=runtimeRaw and identity.fingerprint(runtimeRaw) or nil,runtimeMappingRevision=SOURCE_ANIMATION_RUNTIME_MAPPING_REVISION,runtimeMapping=runtimeMapping}
  -- This overlay is a persisted generated payload too.  A stale/corrupt prior
  -- overlay must survive an ordinary metadata repair just like canonical arena
  -- Lua/RGBA/f32 bytes; only explicit cache DELETE may destroy acquired bytes.
  write(mod,sourceAnimationMetaPath(spec.id),"return "..runtimeSerialize(meta).."\n",generated,true)
  return {reused=false,fromSource=fromSource,canonicalRebuilt=rebuilt==true,path=sourceAnimationMetaPath(spec.id)}
end
function A.sourceAnimationMetadata(mod,disc,progress,generated)
  generated=generated or {};progress=progress or function()end
  local built,reused,sourceDecoded=0,0,0
  for i,spec in ipairs(ARENAS) do
    if spec.sourceFsys then
      progress((spec.label or spec.id:upper()).." / SOURCE ANIMATION METADATA",i-1,#ARENAS)
      local r=augmentSourceAnimationForSpec(mod,disc,spec,generated,progress)
      if r.reused then reused=reused+1 else built=built+1;if r.fromSource then sourceDecoded=sourceDecoded+1 end end
    end
  end
  return {ready=true,built=built,reused=reused,sourceDecoded=sourceDecoded,total=#ARENAS-1,contract=SOURCE_ANIMATION_CONTRACT}
end
function A.sourceAnimationReady(mod)
  for _,spec in ipairs(ARENAS) do if spec.sourceFsys and not runtimeInfo(mod,sourceAnimationMetaPath(spec.id)) then return false end end
  return true
end

buildSourceArenaFromDisc=function(mod,disc,progress,generated,spec,preserveExisting)
  assert(HSD and FSYS,"source HSD arena extractor unavailable")
  local file=assert(disc:file(spec.sourceFsys),spec.sourceFsys.." missing from GC6E01")
  local arc=FSYS.open(disc,file)
  local entry=arc:member(spec.sourceMember) or arc:member((spec.sourceMember or ""):gsub("%.dat$",""))
  if not (entry and entry.modelKind) then
    for _,e in ipairs(arc:modelEntries()) do if e.fileType==0x02 then entry=e;break end end
  end
  assert(entry and entry.modelKind,(spec.sourceMember or spec.id).." model member missing")
  local label=spec.label or spec.id:upper()
  progress(label.." / DECOMPRESS",0,3)
  local blob=arc:extract(entry,{maxOutput=64*1024*1024,progress=function(c,t) progress(label.." / DECOMPRESS",c,t) end})
  progress(label.." / HSD SCENE",1,3)
  local model,err=HSD.extractSceneModel(blob,{
    preserveVertexColors=true,textures=true,sourceTextureState=true,sourceMaterialAnimation=true,sourceTextureAnimation=true,nativeSceneInstances=true,maxSceneRoots=spec.maxSceneRoots or 16,maxVertices=spec.maxVertices or 180000,
    maxDisplayOps=spec.maxDisplayOps or 700000,maxJobjs=spec.maxJobjs or 6000,
    maxDobjs=spec.maxDobjs or 16000,maxPobjs=spec.maxPobjs or 28000,
    groupFilter=sourceGroupFilter(spec),
    honorRenderPass=spec.honorRenderPass==true,
    skipShadowMaterials=spec.skipShadowMaterials==true,
    -- Relic's deeply nested nonuniform scales require native HSD parent-scale
    -- compensation. Naive SRT sheared leaves/trees into enormous foreground
    -- sheets; deleting those groups then removed most of its forest backdrop.
    nativeScaleCompensation=spec.nativeScaleCompensation==true,
    progress=function(c,t) progress(("%s / MODELSET %d"):format(label,c),c,t) end,
  })
  assert(model,err or (label.." HSD scene decode failed"))
  assert((model.vertexCount or 0)>=(spec.minVertices or 1) and #(model.groups or {})>=(spec.minGroups or 1),
    ("%s source scene unexpectedly small (%d vertices / %d groups)"):format(label,model.vertexCount or 0,#(model.groups or {})))
  local written,textureCount,crowdOriginal={},0,0
  local backdropWritten=false
  for _,g in ipairs(model.groups) do
    if type(g.sourceTextureAnimation)=="table" and g.sourceTextureAnimation.state=="animated" then
      -- GC6E01 GSmodelLoad/floorOpenObject uses texture animation index 0,
      -- type 1 (loop), rate 0.5 on the 60 Hz model clock: 30 HSD frames/sec.
      g.sourceTextureAnimation.framesPerSecond=30
      g.sourceTextureAnimation.loop=true
    end
    if type(g.sourceMaterialAnimation)=="table" and g.sourceMaterialAnimation.state=="animated" then
      g.sourceMaterialAnimation.framesPerSecond=30
      g.sourceMaterialAnimation.loop=true
    end
    local t=g.texture
    if t and t.rgba and t.dataOffset then
      local path=("%s/tex_%06x_%dx%d_f%d.rgba"):format(spec.textureRoot,t.dataOffset,t.w,t.h,t.format or 0)
      if not written[path] then
        write(mod,path,t.rgba,generated,preserveExisting);written[path]=true;textureCount=textureCount+1
      end
      if V.ArenaAudienceProfile and V.ArenaAudienceProfile.classifySourceTexture(spec.id,path) then crowdOriginal=crowdOriginal+1 end
      if spec.backdrop and not backdropWritten and t.dataOffset==spec.backdrop.offset then
        local b=spec.backdrop
        write(mod,b.path,cropRGBA(t.rgba,t.w,t.h,b.x,b.y,b.w,b.h),generated,preserveExisting)
        backdropWritten=true
      end
      g.texture={path=path,w=t.w,h=t.h,wrapS=t.wrapS,wrapT=t.wrapT,
        coordinateMode=t.coordinateMode,colorMap=t.colorMap,alphaMap=t.alphaMap,blending=t.blending}
    elseif t then
      g.texture=nil
    end
  end
  if spec.backdrop then assert(backdropWritten,label.." source backdrop texture was not decoded") end
  progress(label.." / SERIALIZE",2,3)
  local source=("Pokemon Colosseum GC6E01 / %s:%s / %d semantic modelsets / %d source textures")
    :format(file.path or spec.sourceFsys,entry.name or spec.sourceMember,model.sceneRoots or 0,textureCount)
  -- Source HSD audience cards retain their exact authored placement. Runtime
  -- depth/cutout handling may animate their pixels, but never re-sectors them.
  model.crowdPolicy="source-hsd-crowd"
  write(mod,spec.cache,serializeSourceArena(model,source,crowdOriginal),generated,preserveExisting)
  progress(label.." / READY",3,3)
  return {groups=#model.groups,vertices=model.vertexCount,source=source,textures=textureCount,crowdOriginal=crowdOriginal}
end
function A.repair(mod,disc,progress,generated,options)
  -- The pipeline may request the proven two-scene Relic or instance migration,
  -- but only a complete venue cache may take that scope. Otherwise restore every retail
  -- scene, retain existing Wildlands, and leave actor/audio/FX caches alone.
  local function cacheExists(path)
    if not (mod and mod.cache and type(mod.cache.info)=="function") then return false end
    local ok,info=pcall(mod.cache.info,mod.cache,path)
    return ok and type(info)=="table" and (info.type==nil or info.type=="file")
  end
  -- Recipe additions do not invalidate expensive retail HSD caches.  Treat the
  -- source venue set independently so an update that only adds an authored arena
  -- can synthesize that one cache from already-retained GC6E01 texture payloads.
  local complete=true
  for _,arena in ipairs(ARENAS) do if arena.sourceFsys and not cacheExists(arena.cache) then complete=false;break end end
  local requestedScope=options and options.scope
  local scope=complete and (requestedScope=="relic-scenes" or requestedScope=="source-instances" or requestedScope=="recipe-open-water") and requestedScope or nil
  local scoped=scope~=nil
  local sourceArenas={}
  for _,arena in ipairs(ARENAS) do if arena.sourceFsys then
    if (not scoped) or (scope=="relic-scenes" and (arena.id=="relic_chamber" or arena.id=="relic_cave"))
        or (scope=="source-instances" and (arena.id=="water" or arena.id=="deep_colosseum")) then sourceArenas[#sourceArenas+1]=arena end
  end end
  local recipeArenas={}
  for _,arena in ipairs(ARENAS) do
    if arena.recipe then
      if scope=="recipe-open-water" then
        -- A recognized Open Sea recipe revision is a deliberate replacement of
        -- that one canonical recipe cache.  Rebuild it even though the v1 file
        -- exists; write(..., preserveExisting=true) archives the old payload.
        if arena.id=="open_water" then recipeArenas[#recipeArenas+1]=arena end
      elseif not scoped and not cacheExists(arena.cache) then
        recipeArenas[#recipeArenas+1]=arena
      end
    end
  end
  local total=#sourceArenas+#recipeArenas
  local mode=complete and "all-source-colors" or "full"
  if scoped then mode=scope end
  local report={"return {revision="..tostring(A.arenaRevision)..",mode="..string.format("%q",mode)..","}
  local repairLabel=scope=="source-instances" and "WATER + DEEP / SOURCE INSTANCE REFRESH"
    or (scope=="recipe-open-water" and "ORRE OPEN SEA / AUTHORED WATER ROUTE"
    or (scoped and "RELIC CHAMBER + CAVE / SOURCE FIDELITY REFRESH" or "ALL ARENAS / SOURCE COLOR AND MATERIAL REFRESH"))
  progress(repairLabel,0,math.max(1,total))
  for step,arena in ipairs(sourceArenas) do
    progress((arena.label or arena.id).." / FULL SOURCE HSD",step-1,math.max(1,total))
    local value=buildSourceArenaFromDisc(mod,disc,progress,generated,arena,true)
    report[#report+1]=string.format("%s={cache=%q,groups=%d,vertices=%d,source=%q,textures=%d},",arena.id,arena.cache,tonumber(value.groups) or 0,tonumber(value.vertices) or 0,tostring(value.source or "GC6E01 source"),tonumber(value.textures) or 0)
  end
  for n,arena in ipairs(recipeArenas) do
    progress((arena.label or arena.id).." / AUTHORED PARITY",#sourceArenas+n-1,math.max(1,total))
    -- Wildlands owns packaged procedural texture assets; Open Sea deliberately
    -- reuses already-extracted Water/D2 source textures and needs no duplicates.
    local keys={}
    if arena.id=="outdoor_wild" then
      for path in pairs(SPECS) do if path:find("cache/stages/wildlands/",1,true) then keys[#keys+1]=path end end;table.sort(keys)
      for _,path in ipairs(keys) do local sp=SPECS[path];write(mod,path,textureBytes(mod,path,sp),generated,true) end
    end
    local src=assert(mod:read(arena.recipe),"missing arena recipe: "..arena.recipe);local chunk,err=load(src,"@"..arena.recipe);assert(chunk,err)
    local ok,recipe=pcall(chunk);assert(ok,recipe);assert(type(recipe)=="table" and type(recipe.groups)=="table" and #recipe.groups>0,"invalid arena recipe: "..arena.id)
    write(mod,arena.cache,src,generated,true)
    report[#report+1]=string.format("%s={cache=%q,groups=%d,vertices=%d,source=%q,textures=%d},",arena.id,arena.cache,#recipe.groups,tonumber(recipe.vertexCount) or 0,tostring(recipe.source or "recipe"),#keys)
  end
  report[#report+1]="}\n";write(mod,"build/arena_repair.lua",table.concat(report),generated)
  progress("ARENA SOURCE FIDELITY READY",math.max(1,total),math.max(1,total));return true
end
function A.run(mod,disc,progress,generated)
  -- Every selectable venue except Wildlands is source-backed; all venue textures are decoded from GC6E01.
  local keys={}
  for p in pairs(SPECS) do
    if p:find("cache/stages/wildlands/",1,true) then keys[#keys+1]=p end
  end
  table.sort(keys)
  for i,p in ipairs(keys)do local sp=SPECS[p];progress("ARENA TEXTURE "..i,i-1,#keys);write(mod,p,textureBytes(mod,p,sp),generated)end
  local report={"return {"}
  for i,a in ipairs(ARENAS)do
    progress("ARENA "..a.id:upper(),i-1,#ARENAS)
    local value
    if a.sourceFsys then
      value=buildSourceArenaFromDisc(mod,disc,progress,generated,a)
    else
      local src=assert(mod:read(a.recipe),"missing arena recipe: "..a.recipe)
      local chunk,err=load(src,"@"..a.recipe);assert(chunk,err);local ok,recipe=pcall(chunk);assert(ok,recipe)
      assert(type(recipe)=="table" and type(recipe.groups)=="table" and #recipe.groups>0,"invalid arena recipe: "..a.id)
      write(mod,a.cache,src,generated);value={groups=#recipe.groups,vertices=tonumber(recipe.vertexCount) or 0,source=tostring(recipe.source or "recipe")}
    end
    report[#report+1]=string.format("%s={cache=%q,groups=%d,vertices=%d,source=%q},",a.id,a.cache,tonumber(value.groups) or 0,tonumber(value.vertices) or 0,tostring(value.source or "recipe"))
  end
  report[#report+1]="}\n";write(mod,"build/arenas.lua",table.concat(report),generated)
  progress("ARENAS READY",#ARENAS,#ARENAS)
  return true
end
A._test={writeRuntimeSidecar=writeRuntimeSidecarFromCache,arenas=ARENAS,runtimeWithNormals=runtimeWithNormals,runtimeMaterialMode=runtimeMaterialMode,runtimeUsable=runtimeUsable,buildSourceArena=buildSourceArenaFromDisc,runtimeDropGhost=runtimeDropGhost,serializeSourceArena=serializeSourceArena,
  runtimePackRows=runtimePackRows,packSourceVertices=packSourceVertices,decodeSourceVertices=decodeSourceVertices,materializeSourceArenaVertices=materializeSourceArenaVertices,
  augmentSourceAnimationForSpec=augmentSourceAnimationForSpec,sourceAnimationMetaPath=sourceAnimationMetaPath,sourceAnimationContract=SOURCE_ANIMATION_CONTRACT,
  applyCanonicalAnimationMetadata=applyCanonicalAnimationMetadata,buildRuntimeAnimationOverlay=buildRuntimeAnimationOverlay,write=write}
return A
