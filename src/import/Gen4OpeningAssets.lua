local G=require('src.import.Gen4Graphics')
local N=require('src.import.NarcArchive')
local C=require('src.import.Gen4Cells')
local A=require('src.import.Gen4CellAnim')
local O={}
-- Indices used by GameOpening's background and sprite-resource loaders.
O.backgrounds={
 {'sky',95,12,96},{'white',14,12,13},
 {'landscape_front',59,63,61},{'landscape_middle',58,62,61},{'landscape_back',60,64,61},
 {'panorama_front',66,70,68},{'panorama_middle',65,69,68},{'panorama_back',67,71,68},
 {'galactic_front',73,76,72},{'galactic_middle',74,77,72},{'galactic_back',75,78,72},
 {'final_top',79,80,72},{'final_bottom',81,82,72},{'end',98,97,99},
}
O.actors={
 {id=0,tiles=46,palette=49,cells=48,anim=47},
 {id=2,tiles=50,palette=53,cells=51,anim=52},
 {id=3,tiles=87,palette=90,cells=89,anim=88},
 {id=4,tiles=22,palette=20,cells=24,anim=26},
 {id=5,tiles=23,palette=21,cells=25,anim=27},
 {id=6,tiles=91,palette=94,cells=93,anim=92},
 {id=7,tiles=83,palette=86,cells=85,anim=84},
 {id=9,tiles=54,palette=57,cells=55,anim=56},
}
function O.images(rom)
 local raw=rom:read('/demo/title/op_demo.narc')
 local arc=raw and N.parse(raw)
 if not arc then return {} end
 local function member(i)
  local bytes=arc:get(i)
  return bytes and (G.isCompressed(bytes) and G.decompress(bytes) or bytes)
 end
 local out={}
 for _,r in ipairs(O.backgrounds) do
  local tiles,map,palette=G.tiles(member(r[2])),G.tilemap(member(r[3])),G.palette(member(r[4]))
  if tiles and map and palette then out['opening/'..r[1]]=G.compose(map,tiles,palette) end
 end
 for _,r in ipairs(O.actors) do
  local tiles,bank,palette,anim=G.tiles(member(r.tiles)),C.parse(member(r.cells),G),G.palette(member(r.palette)),A.parse(member(r.anim),G)
  if tiles and bank and palette and anim then
   palette=A.paletteFor(palette,A.bankOf(bank) or 0)
   local sequences={}
   for i=0,#anim.sequences-1 do sequences[i]=A.frames(anim,i) end
   for i,cell in ipairs(bank.cells) do
    local pic=C.assemble(cell,tiles,palette,bank,G)
    if pic then
     pic.originX,pic.originY=C.extent(cell)
     if i==1 then pic.sequences=sequences end
     out[('opening/actor_%d_%02d'):format(r.id,i-1)]=pic
    end
   end
  end
 end
 return out
end
return O
