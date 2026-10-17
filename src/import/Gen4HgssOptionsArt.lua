-- HGSS options_app.c: main engine is on the touch screen, SUB on top.
local O={PATH='/a/0/7/2',BANK=45}
O.ROWS={{key='textSpeed',label=1,values={9,10,11}},
 {key='battleScene',label=2,values={12,13}}, {key='battleStyle',label=3,values={14,15}},
 {key='sound',label=4,values={16,17}}, {key='buttonMode',label=5,values={18,19}},
 {key='frame',label=6,values={}}}
for i=20,39 do O.ROWS[6].values[#O.ROWS[6].values+1]=i end
function O.images(rom)
 local G=require('src.import.Gen4Graphics')
 local arc=require('src.import.NarcArchive').parse(rom:read(O.PATH))
 if not arc then return nil end
 local out={}
 for _,r in ipairs({{'hgss_top',8,19,3},{'hgss_bottom',7,17,2},{'hgss_cursor',7,18,2}})do
  out[r[1]]=G.compose(G.tilemap(arc:get(r[3])),G.tiles(arc:get(r[2])),G.palette(arc:get(r[4])))
 end
 local Cells=require('src.import.Gen4Cells')
 for set,r in ipairs({{4,9,0},{5,10,0},{6,11,1},{6,12,1}})do
  local sheet,pal=G.tiles(arc:get(r[1])),G.palette(arc:get(r[3]))
  local bank=Cells.parse(arc:get(r[2]),G)
  if bank then for i,cell in ipairs(bank.cells)do
   local row=cell.oam[1] and cell.oam[1].palette or 0
   local selected={};for c=1,16 do selected[c]=pal[row*16+c]end
   local picture=Cells.assemble(cell,sheet,selected,bank,G)
   if picture then
    picture.originX,picture.originY=Cells.extent(cell)
    out[('hgss_obj_%d_%d'):format(set,i-1)]=picture
   end
  end end
 end
 return out
end
function O.words(stringAt)
 local function word(i)return (stringAt(O.BANK,i) or ''):gsub('{[^}]+}','')end
 local out={title=word(0),rows={},confirm=word(7),quit=word(8),bank=O.BANK}
 for _,r in ipairs(O.ROWS)do
  local row={key=r.key,label=word(r.label),values={}}
  for _,i in ipairs(r.values)do row.values[#row.values+1]=word(i)end
  out.rows[#out.rows+1]=row
 end
 return out
end
return O
