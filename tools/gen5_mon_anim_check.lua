package.path='./?.lua;./?/init.lua;'..package.path
local Decoder=require('src.import.Gen5MonAnim')
local Nds=require('src.import.NdsRom')
local Narc=require('src.import.NarcArchive')
local checks=0
for _,filename in ipairs({'Pokemon - Black Version (USA, Europe) (NDSi Enhanced).nds','Pokemon - White Version (USA, Europe) (NDSi Enhanced).nds'})do
 local rom=assert(Nds.open(filename));local arc=assert(Narc.parse(rom:read(Decoder.PATH)))
 for species=1,649 do
  local packed=Decoder.pack(arc,species)
  local copy=assert(Decoder.unpack(packed))
  for _,side in ipairs({'front','back'})do
   local set,why=Decoder.load(copy,species,side)
   assert(set,filename..' species '..species..' '..side..': '..tostring(why))
   local player=assert(Decoder.machine(set,0))
   for tick=1,120 do
    for _,part in ipairs(player.state())do assert(set.cells.cells[part.cell],'invalid cell reference')end
    player.tick()
   end
   checks=checks+1
  end
  assert(not Decoder.unpack(packed:sub(1,-2)))
  checks=checks+1
 end
 print(filename..': all 649 front/back animation bundles validated')
end
print(checks..' animation checks, 0 failed')
