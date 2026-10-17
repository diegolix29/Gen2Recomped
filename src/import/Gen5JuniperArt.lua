-- BW's new-game introduction: /a/1/7/0, message bank 44. Juniper is a
-- multi-cell actor on a linear sheet, not a row-major NCGR tile sheet.
local A={PATH='/a/1/7/0',BANK=44}
function A.build(x)
  local G=require('src.import.Gen4Graphics')
  local C=require('src.import.Gen4Cells')
  local M=require('src.import.Gen5MonAnim')
  local N=require('src.import.NarcArchive')
  local arc=assert(N.parse(assert(x.rom:read(A.PATH))))
  local out={source='ROM:/a/1/7/0, system text 44',text={},juniper={}}
  local function save(key,pic,extra)
    local rec=assert(x:saveImage('bw_juniper/'..key,assert(pic),extra))
    out[key]=rec;return rec
  end
  for i=6,26 do out.text[i]=x:string(A.BANK,i) end
  out.namePrompt=x:string(81,0)
  local fonts=assert(N.parse(assert(x.rom:read('/a/0/2/3'))))
  local ink=assert(G.palette(fonts:get(5)))
  out.ink={text=ink[2],shadow=ink[3]}
  local palette=assert(G.palette(arc:get(1)))
  local sheet=assert(G.tiles(arc:get(0)))
  for _,pair in ipairs({{'bottom',2},{'background',3}}) do
    save(pair[1],G.compose(assert(G.tilemap(arc:get(pair[2]))),sheet,palette))
  end
  for _,row in ipairs({{'boy',5,6,7},{'girl',9,10,11},{'cheren',16,17,18},{'bianca',20,21,22}}) do
    local bank=assert(C.parse(arc:get(row[2]),G))
    local cell=assert(bank.cells[1]);local ox,oy=C.extent(cell)
    local pal=assert(G.palette(arc:get(row[4])))
    save(row[1],C.assemble(cell,assert(G.tiles(arc:get(row[3]))),pal,bank,G),{originX=ox,originY=oy})
  end
  local bytes=arc:get(25)
  local Models=require('src.import.Gen4Models')
  local textures=assert(Models.parse(bytes,assert(bytes:find('TEX0',1,true))-1))
  for _,row in ipairs({{'blue',1},{'pink',3},{'girl_dim',5},{'girl_portrait',6},{'boy_dim',7},{'boy_portrait',8}}) do
    save(row[1],Models.decode(textures,bytes,row[2],row[2]))
  end
  local set={cells=assert(M.parseCells(arc:get(33))),sheet=assert(M.parseSheet(arc:get(31))),
    anim=assert(M.parseAnim(arc:get(30))),mcAnim=assert(M.parseAnim(arc:get(35))),
    multiCells=assert(M.parseMultiCells(arc:get(36))),palette=assert(G.palette(arc:get(34)))}
  for sequence=0,2 do
    local anim=assert(M.bake(nil,0,'front',false,{set=set,sequence=sequence,
      origin={128,140},crop='bounds',maxTicks=180}))
    local rec={play=anim.play,origin=anim.origin,frames={},ticks=anim.loopTicks}
    for i,pic in ipairs(anim.frames) do
      rec.frames[i]=assert(x:saveImage(('bw_juniper/juniper_%d_%d'):format(sequence,i),pic))
    end
    out.juniper[sequence]=rec
  end
  -- Minccino uses the cartridge's ordinary 96x96 four-block front picture.
  local battle=assert(N.parse(assert(x.rom:read('/a/0/0/4'))))
  local L=require('src.import.Gen5Lz')
  local chars=assert(L.decompress(battle:get(572*20)))
  local pal=assert(G.palette(battle:get(572*20+18)))
  local cells,t={},0
  for _,b in ipairs(require('src.import.Gen5BattleSprites').BLOCKS) do
    for y=0,b[4]-1 do for xx=0,b[3]-1 do
      cells[(b[2]+y)*12+b[1]+xx+1]={tile=t,palette=0};t=t+1
    end end
  end
  save('minccino',G.compose({width=96,height=96,cells=cells},assert(G.tiles(chars)),pal))
  -- Native intro BG1 loads the nine-tile window at character 16 with
  -- palette 8: /a/0/0/5 member 11, palette 0. The field's eighteen-tile
  -- frame (member 10) has different corners and must not stand in for it.
  local windows=assert(N.parse(assert(x.rom:read('/a/0/0/5'))))
  local frameTiles=assert(G.tiles(windows:get(11)))
  local framePal=assert(G.palette(windows:get(0)))
  local frameCells={}
  for y=0,5 do for xx=0,31 do
    local row=y==0 and 0 or y==5 and 2 or 1
    local col=xx==0 and 0 or xx==31 and 2 or 1
    frameCells[#frameCells+1]={tile=row*3+col,palette=0}
  end end
  save('message_frame',G.compose({width=256,height=48,cells=frameCells},frameTiles,framePal))
  return out
end
return A
