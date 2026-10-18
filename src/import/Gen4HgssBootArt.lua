-- intro_movie_scene_1..5.c: native layers and cell animations.
-- Resources stay separate so scrolling and affine poses use the ROM data.
local A={PATH='/a/2/6/2'}
function A.images(rom)
  local G=require('src.import.Gen4Graphics')
  local arc=assert(require('src.import.NarcArchive').parse(rom:read(A.PATH)))
  local function m(i) local b=assert(arc:get(i));return G.isCompressed(b) and G.decompress(b) or b end
  local silver=rom:header().gameCode:sub(1,3)=='IPG'
  local top=assert(G.palette(m(silver and 2 or 0)))
  local bottom=assert(G.palette(m(silver and 3 or 1)))
  local out={}
  for _,row in ipairs({{'copyright_top',14,4,top},{'studio_top',12,4,top},{'studio_bottom',13,5,bottom}}) do
    out[row[1]]=assert(G.compose(G.tilemap(m(row[2])),G.tiles(m(row[3])),row[4]))
  end
  -- Main BG0 is scrolled down by 128 during the copyright card; DS text
  -- backgrounds wrap at 256, independent of the visible 192 rows.
  local base=out.studio_bottom;local rows={}
  for y=0,191 do
    local sourceY=(y+128)%256
    rows[#rows+1]=sourceY<base.height and base.rgba:sub(sourceY*base.width*4+1,(sourceY*base.width+256)*4)
      or string.rep('\0',256*4)
  end
  out.copyright_bottom={width=256,height=192,rgba=table.concat(rows)}
  local function picture(key,map,char,pal)
    local colours=assert(G.palette(m(pal)))
    out[key]=assert(G.compose(G.tilemap(m(map)),G.tiles(m(char)),colours))
  end
  picture('sky_top',silver and 19 or 15,silver and 8 or 6,silver and 2 or 0)
  for layer=1,3 do
    picture('sky_bottom_'..layer,(silver and 19 or 15)+layer,silver and 9 or 7,silver and 3 or 1)
  end
  picture('grass_top',35,33,32)
  picture('grass_bottom',36,34,31)
  picture('trainers_back',37,33,32)
  picture('trainers_front',38,33,32)
  for i=42,49 do picture('montage_'..i,i,40,39) end
  for i=50,52 do picture('montage_'..i,i,41,39) end
  for i=55,58 do picture('starter_bg_'..i,i,54,53) end
  picture('final_top_back',61,59,39)
  picture('final_top_front',63,59,39)
  picture('final_bottom_front',62,60,31)
  picture('final_bottom_back',64,60,31)
  local Cells=require('src.import.Gen4Cells')
  local Anim=require('src.import.Gen4CellAnim')
  local sequences={}
  local function sprites(name,pal,char,anim,cell)
    local bank=assert(Cells.parse(m(cell),G))
    local sheet,colours=assert(G.tiles(m(char))),assert(G.palette(m(pal)))
    local animation=assert(Anim.parse(m(anim),G));sequences[name]={}
    for i,c in ipairs(bank.cells) do
      local pic,why=Cells.assemble(c,sheet,colours,bank,G)
      -- Empty cells deliberately hide the hand/sparkle between poses.
      if pic then
        pic.originX,pic.originY=Cells.extent(c)
        out[name..'_'..(i-1)]=pic
      elseif #(c.oam or {})>0 then error(name..' cell '..(i-1)..': '..tostring(why)) end
    end
    for i,seq in ipairs(animation.sequences) do
      sequences[name][i-1]={frames=seq.frames,loopStart=seq.loopStart,playbackMode=seq.playbackMode}
    end
  end
  if silver then sprites('sky_actor',27,28,29,30) else sprites('sky_actor',23,24,25,26) end
  sprites('trainers',73,74,75,76)
  sprites('flowers',77,78,79,80)
  sprites('rival',65,66,67,68)
  sprites('eusine_unown',69,70,71,72)
  sprites('hands_sparkle',81,82,83,84)
  sprites('chikorita',85,86,87,88)
  sprites('cyndaquil',93,94,95,96)
  sprites('totodile',89,90,91,92)
  local Particle=require('src.import.Gen4Particle')
  local arcParticles=assert(require('src.import.NarcArchive').parse(rom:read('/a/0/5/9')))
  local particleFile=assert(arcParticles:get(4))
  local emitters=assert(Particle.emitters(particleFile))
  for i,texture in ipairs(assert(Particle.textures(particleFile))) do out['opening_particle_'..(i-1)]=Particle.rgba(texture) end
  return out,sequences,{emitters=emitters,scene4=true}
end
function A.build(x)
  local images,sequences,metadata=A.images(x.rom)
  local out=metadata or {};out.sequences=sequences
  for key,pic in pairs(images) do
    out[key]=x:saveImage('hgss_boot/'..key,pic,{originX=pic.originX,originY=pic.originY})
  end
  return out
end
return A
