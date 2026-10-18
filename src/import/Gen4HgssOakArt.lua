-- OakSpeech overlay 53: /a/1/2/0, bank 219. No Platinum art or text.
local G=require('src.import.Gen4Graphics')
local A={PATH='/a/1/2/0',BANK=219}
function A.images(rom,version)
  local arc=assert(require('src.import.NarcArchive').parse(rom:read(A.PATH)))
  local function m(i)
    local b=assert(arc:get(i));return G.isCompressed(b) and G.decompress(b) or b
  end
  local out={}
  local function picture(key,map,char,pal,row)
    local tm=assert(G.tilemap(m(map)))
    if row then for _,c in ipairs(tm.cells) do c.palette=row end end
    local colours=assert(G.palette(m(pal)))
    out[key]=assert(G.compose(tm,assert(G.tiles(m(char))),colours))
  end
  local silver=version=='soulsilver' or (rom.header and tostring(rom:header().gameCode):sub(1,3)=='IPG')
  for i=0,5 do picture('background_'..i,3+i,0,silver and 2 or 1) end
  local bottomPalette=silver and 31 or 30
  picture('bottom',43,32,bottomPalette,3)
  picture('topics',44,32,bottomPalette)
  picture('gender',51,32,bottomPalette)
  picture('oak',9,10,11,0)
  for i=1,4 do
    picture('boy_'..i,9,11+i,16,0)
    picture('girl_'..i,9,16+i,21,0)
  end
  for i=1,4 do
    picture('boy_shrink_'..i,9,21+i,16,0)
    picture('girl_shrink_'..i,9,25+i,21,0)
  end
  -- resdat[78] resource set 5 -> char[8], pal[7], cell[5], anim[5].
  -- resdat[24..27] resolve these to intro members 64,63,65,66.
  local C=require('src.import.Gen4Cells');local Anim=require('src.import.Gen4CellAnim')
  local avatarCells=assert(C.parse(m(55),G))
  for _,row in ipairs({{'boy_cursor',12,16},{'girl_cursor',17,21}}) do
    local pic=assert(C.assemble(avatarCells.cells[1],G.tiles(m(row[2])),G.palette(m(row[3])),avatarCells,G))
    pic.originX,pic.originY=C.extent(avatarCells.cells[1]);out[row[1]]=pic
  end
  local cells=assert(C.parse(m(65),G));local animation=assert(Anim.parse(m(66),G))
  local sheet,palette=G.tiles(m(64)),G.palette(m(63))
  local sequences={}
  for seq=0,3 do
    local frames=Anim.frames(animation,seq);sequences[seq]={}
    local row=seq==3 and 1 or 0
    local pal={}
    for i=1,256 do pal[i]=palette[row*16+(i-1)%16+1] end
    for f,frame in ipairs(frames) do
      local cell=assert(cells.cells[frame.cell+1])
      local pic=assert(C.assemble(cell,sheet,pal,cells,G))
      pic.originX,pic.originY=C.extent(cell)
      local key='marill_'..seq..'_'..f;out[key]=pic
      sequences[seq][f]={key=key,duration=frame.duration or 1,x=frame.x,y=frame.y,
        scaleX=frame.scaleX,scaleY=frame.scaleY,rotation=frame.rotation}
    end
  end
  return out,sequences
end
function A.build(x)
  local images,seq=A.images(x.rom,x.version)
  local out={sequences=seq,text={},bank=A.BANK}
  for name,img in pairs(images) do
    out[name]=x:saveImage('hgss_oak/'..name,img,{originX=img.originX,originY=img.originY})
  end
  for i=1,48 do out.text[i]=x:string(A.BANK,i) end
  return out
end
return A
