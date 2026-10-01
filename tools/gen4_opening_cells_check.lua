local G=require('src.import.Gen4Graphics')
local C=require('src.import.Gen4Cells')
local rom=assert(require('src.import.NdsRom').open('Pokemon - Platinum Version (USA) (Rev 1).nds'))
local arc=assert(require('src.import.NarcArchive').parse(rom:read('/demo/title/op_demo.narc')))
for _,id in ipairs({48,51}) do
 local raw=arc:get(id);raw=G.isCompressed(raw) and G.decompress(raw) or raw
 local container=G.container(raw);local b=container.sections.KBEC.body
 local bank=assert(C.parse(raw,G))
 local at=b+136
 for j=at,at+47 do io.write(('%02x '):format(raw:byte(j) or 0)) end;print()
 local t=arc:get(id==48 and 46 or 50);t=G.isCompressed(t) and G.decompress(t) or t
 local sheet=assert(G.tiles(t));print('tiles',sheet.count,sheet.tilesX,sheet.tilesY,sheet.bitmap,#sheet.pixels)
 local ar=arc:get(id==48 and 47 or 52);ar=G.isCompressed(ar) and G.decompress(ar) or ar
 local anim=assert(require('src.import.Gen4CellAnim').parse(ar,G))
 for _,sequence in ipairs(anim.sequences) do for _,f in ipairs(sequence.frames) do print('frame',f.cell,f.duration,f.x,f.y) end end
 print('bank',id,'boundary',bank.boundary,'cells',#bank.cells)
 for at=b,b+31 do io.write(('%02x '):format(raw:byte(at))) end;print()
 for i,cell in ipairs(bank.cells) do
  print('cell',i,C.extent(cell));print('transfer',cell.transfer and cell.transfer.offset,cell.transfer and cell.transfer.size)
  for _,o in ipairs(cell.oam) do print(o.x,o.y,o.width,o.height,o.tile) end
 end
end
rom:close()

