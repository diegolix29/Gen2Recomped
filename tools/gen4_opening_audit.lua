local rom=assert(require('src.import.NdsRom').open('Pokemon - Platinum Version (USA) (Rev 1).nds'))
local arc=assert(require('src.import.NarcArchive').parse(rom:read('/demo/title/op_demo.narc')))
local N=require('src.import.Gen4Nsbmd')
local G=require('src.import.Gen4Graphics')
for i=100,112 do
 local bytes=arc:get(i);if G.isCompressed(bytes) then bytes=G.decompress(bytes) end
 if bytes:sub(1,4)=='BMD0' then
  for _,model in ipairs(assert(N.parse(bytes)).models) do
   local count=0;for _,shape in ipairs(model.shapes) do count=count+#shape.vertices end
   print(i,model.name,#model.shapes,count)
  end
 end
end
rom:close()
