-- BW's boot cards and title. The international title logo is /a/0/2/6,
-- not titledemo's unused Japanese logo or prototype dragon meshes.
local A={PATH='/a/0/2/6'}
function A.build(x)
  local G=require('src.import.Gen4Graphics')
  local Lz=require('src.import.Gen5Lz')
  local Narc=require('src.import.NarcArchive')
  local out={source='ROM:/a/0/2/6, /a/1/6/4, /a/1/6/0'}
  local function arc(path) return assert(Narc.parse(assert(x.rom:read(path)))) end
  local function member(a,i)
    local b=assert(a:get(i))
    if Lz.isCompressed(b) then return assert(Lz.decompress(b)) end
    if G.isCompressed(b) then return assert(G.decompress(b)) end
    return b
  end
  local function picture(a,key,map,char,pal)
    local palette=assert(G.palette(member(a,pal)))
    local pic=assert(G.compose(assert(G.tilemap(member(a,map))),
      assert(G.tiles(member(a,char))),palette))
    out[key]=assert(x:saveImage('bw_boot/'..key,pic))
  end
  local title=arc(A.PATH)
  picture(title,'logo',1,0,2)
  picture(title,'background',3,0,2)
  picture(title,'developer',10,9,8)
  picture(title,'company',13,12,11)
  picture(title,'studio_white',14,12,11)
  local credits=arc('/a/1/6/4')
  picture(credits,'copyright',2,1,0)
  local Cells=require('src.import.Gen4Cells')
  local bank=assert(Cells.parse(member(title,6),G))
  local cell=assert(bank.cells[2]) -- cell 0 is the blink's empty frame
  local pic=assert(Cells.assemble(cell,assert(G.tiles(member(title,5))),
    assert(G.palette(member(title,4))),bank,G))
  local ox,oy=Cells.extent(cell)
  out.prompt=assert(x:saveImage('bw_boot/prompt',pic,{originX=ox,originY=oy}))
  -- Animated title meshes, not the battle sprites. Preserve each shape's
  -- material palette: the dragons include translucent flame/glow surfaces.
  local movies=arc('/a/1/6/0')
  local white=x.version=='white'
  local Models=require('src.import.Gen4Models')
  local Anim=require('src.import.Gen4Anim')
  -- one model of the title scene, packed with its textures, and the joint
  -- tracks of its animation (the BCA0 before it in the archive)
  local function scenePart(modelMember,animMember,prefix)
    local bytes=member(movies,modelMember)
    local parsed=assert(require('src.import.Gen4Nsbmd').parse(bytes))
    local packed=require('src.import.Gen4ModelPack').pack(assert(parsed.models[1]))
    local tex=assert(Models.parse(bytes,assert(bytes:find('TEX0',1,true))-1))
    local written={}
    for _,shape in ipairs(packed.shapes) do
      local key=tostring(shape.texture)..'/'..tostring(shape.palette)
      if shape.texture then
        if not written[key] then
          local ti,pi
          for k,t in ipairs(tex.textures) do if t.name==shape.texture then ti=k end end
          for k,p in ipairs(tex.palettes) do if p.name==shape.palette then pi=k end end
          local image=assert(Models.decode(tex,bytes,assert(ti),pi or 1))
          written[key]=assert(x:saveImage('bw_boot/'..prefix..shape.texture..'_'..tostring(pi or 1),image)).path
        end
        shape.image=written[key]
      end
    end
    local motionBytes=member(movies,animMember)
    local animation=assert(Anim.parse(motionBytes)).animations[1]
    local motion={frames=animation.frames,tracks={}}
    for _,joint in ipairs(Anim.jointMatrices(motionBytes,animation)) do
      motion.tracks[joint.index]=Anim.packTrack(joint.track)
    end
    return packed,motion
  end
  -- the dragon (Black 227 / title_b_01, White 235 / title_w_01) ...
  out.dragon,out.motion=scenePart(white and 235 or 227,white and 234 or 226,'dragon_')
  -- ... the scene's second skinned object (Black 230 / title_b_02, White 238
  -- / title_w_02): overlay 88 builds three objects (0x021B9E7C sets the
  -- frame of all three), title_b_01, _02 and _03
  local okM,mid,midMotion=pcall(scenePart,white and 238 or 230,white and 237 or 229,'mid_')
  if okM then out.middle,out.middleMotion=mid,midMotion end
  -- ... and the stage behind it: the checkered floor, the glow and the rays
  -- (Black 232 / title_b_03, White 240 / title_w_03)
  local okB,bg,bgMotion=pcall(scenePart,white and 240 or 232,white and 239 or 231,'stage_')
  if okB then out.stage,out.stageMotion=bg,bgMotion end
  -- THE TITLE CAMERA (/a/1/6/0): u32 frame count, bytes 4..6 the channel
  -- flags (0, 1, 1), then per frame six IEEE floats: the ROTATION in degrees
  -- (x, y, z) and the POSITION. ARM9 0x0201183C reads them (x 4096, fx32);
  -- 0x02011B8C turns the angles into MTX_RotX * RotY * RotZ (0x020520FC) and
  -- sets the eye at the position, the target at position + R(0, 0, -1) and
  -- the up vector R(0, 1, 0) (src/ui/Gen5Title.lua: Title.cameraAt). Black's is member
  -- 233, 5,620 frames like its dragon's `title_b_01` (226); White's is 241,
  -- 5,781 like `title_w_01` (234). (224, 451 frames, is the riza_bridge
  -- scene's, with 217 / 221.)
  local cam=member(movies,x.version=='white' and 241 or 233)
  local function f32(at)
    local a,b,c,d=cam:byte(at+1,at+4)
    local bits=a+b*256+c*65536+d*16777216
    local sign=bits>=2^31 and -1 or 1
    local e=math.floor(bits/2^23)%256;local m=bits%2^23
    if e==0 then return sign*m*2^-149 end
    return sign*(1+m/2^23)*2^(e-127)
  end
  local n=cam:byte(1)+cam:byte(2)*256+cam:byte(3)*65536
  if #cam>=8+n*24 then
    local data={}
    for i=0,n*6-1 do data[#data+1]=f32(8+i*4) end
    out.titleCamera={frames=n,data=data}
  end
  return out
end
return A
