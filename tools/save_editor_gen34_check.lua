package.path='tools/save-editor/?.lua;'..package.path
local version='platinum'
package.loaded['src.core.GameVersion']={get=function() return version end,isGen4=function(v) return (v or version)=='platinum' end,isGen3=function(v) return (v or version)=='emerald' end,isGen2=function() return false end}
package.loaded.MonOps={create=function(_,species,level) return {species=species,level=level} end}
local Boxes=require('src.pokemon.Boxes')
local Ops=require('Ops')
local Catalog=require('Catalog')
local Bag=require('src.inventory.Bag')
for _,v in ipairs({'emerald','platinum'}) do
 version=v
 local data={pokemon={[387]={name='Turtwig'}},items={[4]={name='Poke Ball',pocket='POKE_BALLS'}},constants={gen=v=='platinum' and 4 or 3}}
 if v=='emerald' then data.save_layout={fields={storage={boxCount=14,boxCapacity=30}}} end
 Boxes.load(data)
 assert(Boxes.capacity()==30 and Boxes.count()==(v=='platinum' and 18 or 14))
 local s={data=data,cat={species={387}},save={party={},player={name='Test',id=123},inventory={}},selectedBox=Boxes.count(),selectedBoxSlot=30}
 assert(Ops.boxAdd(s));local box=s.save.boxes[s.selectedBox]
 assert(box[30] and not box[1] and Boxes.used(box)==1)
 box[29]={species=387,level=10}
 assert(Ops.withdraw(s));assert(box[29] and not box[30] and #s.save.party==1)
 assert(Catalog.speciesLabel(data,387):find('Turtwig'))
 assert(Catalog.itemLabel(data,4):find('Poke Ball'))
 if v=='platinum' then
  assert(Bag.add(s.save,4,999,data));assert(s.save.inventory[4]==999)
  assert(not Bag.add(s.save,4,1,data))
 end
end
for _,path in ipairs({'src/ui/Gen4Opening.lua','src/ui/Gen4Intro.lua','src/import/RomImporter.lua','src/import/RomExtractorGen4.lua','tools/map-editor/panels/Preview.lua','tools/save-editor/panels/Boxes.lua'}) do assert(loadfile(path)) end
local image={getDimensions=function() return 16,288 end}
package.loaded['src.world.NPC']={resolveSpriteDef=function() return {image='test',frameWidth=16,frameHeight=32} end}
package.loaded['src.render.SpriteRenderer']={new=function() return {tileW=16,tileH=32,resolveImage=function() return image end,poseFrame=function(_,facing) return facing=='up' and 3 or 6,facing=='right' end} end}
love={graphics={newQuad=function(x,y,w,h,iw,ih) return {x=x,y=y,w=w,h=h,iw=iw,ih=ih} end}}
local Preview=require('tools.map-editor.panels.Preview')
local _,quad,w,h,flip=Preview.spriteQuadFor({data={}},1,'RIGHT')
assert(w==16 and h==32 and quad.y==192 and flip==-1,'native NPC frame height and facing must survive editor preview')
print('Gen3/4 editor: labels, box dimensions, sparse slot 30, withdrawal, item limits and full-height NPC facing passed')
