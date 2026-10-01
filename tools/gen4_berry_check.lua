package.path='./?.lua;'..package.path
local B=require('src.world.Gen4BerryPatches')
local checks=0
local function check(v,message) checks=checks+1; assert(v,message) end
local game={save={},data={isGen4Cache=true,constants={
 gen4BerryGrowth={[149]={stageHours=1,baseYield=2,drain=10}},
 gen4BerryInitial={[0]={item=149,yield=1},[1]={item=149,yield=1}},
 gen4BerryPositions={[0]={x=5,y=20},[1]={x=5,y=20}}}}}
local patches=B.sync(game,1000)
check(patches[0].stage==5 and not patches[0].growing,'ROM fruit starts dormant')
B.get(game,0,1000); B.get(game,1,1000)
check(#B.ready(game,1000)==1,'ready locations deduplicate')
local p=B.get(game,2,1000)
check(B.plant(game,p,149) and p.stage==1,'plant empty patch')
check(not B.plant(game,p,149),'occupied patch refuses planting')
B.sync(game,1000+59*60)
check(p.stage==1 and p.remaining==1,'partial stage duration retained')
B.sync(game,1000+60*60)
check(p.stage==2 and p.moisture==90,'stage transition drains moisture')
B.sync(game,1000+240*60)
check(p.stage==5 and p.yield==10,'four stages produce rated yield')
B.sync(game,1000+240*60-120)
check(p.stage==5,'clock reversal does not advance fruit')
package.loaded['src.inventory.Bag']={add=function() return false end}
check(not B.harvest(game,p) and p.stage==5 and p.yield==10,'full bag preserves fruit')
local awarded
package.loaded['src.inventory.Bag']={add=function(_,item,count) awarded={item,count}; return true end}
check(B.harvest(game,p) and p.stage==0 and awarded[2]==10,'successful harvest awards then clears')
p.mulch=95; B.plant(game,p,149)
check(p.remaining==45,'growth mulch shortens stages')
local dry={stage=1,item=149,growing=true,remaining=60,moisture=0,rating=5}
B.elapse(dry,game.data.constants.gen4BerryGrowth[149],240)
check(dry.stage==5 and dry.yield==2,'dry hours reduce fruit yield')
local ripe={stage=5,item=149,growing=true,remaining=1,moisture=100,rating=5,replants=9}
B.elapse(ripe,game.data.constants.gen4BerryGrowth[149],1)
check(ripe.stage==0,'tenth replant expires bush')
ripe={stage=5,item=149,growing=true,remaining=1,moisture=100,rating=5,replants=9,mulch=98}
B.elapse(ripe,game.data.constants.gen4BerryGrowth[149],1)
check(ripe.stage==2 and ripe.replants==10,'gooey mulch extends replant limit')
local P=require('src.import.Gen4Pickups')
local save={}
local sign={script=8000,pickup={kind='hidden',item=17,quantity=2}}
check(P.prepareHidden(save,sign) and save.gen4Vars[0x8002]==730,'hidden script receives ROM flag')
save.flags={FLAG_G4_02DA=true}
check(not P.prepareHidden(save,sign),'collected hidden pickup cannot restart')
check(loadfile('src/import/Gen4BerryData.lua') and loadfile('src/world/Gen4BerryPatches.lua'),'new modules compile')
check(B.graphicsId({stage=1,item=149})==nil,'planted berry has no bush sprite')
check(B.graphicsId({stage=2,item=155})==4096,'all sprouts share ROM graphics')
check(B.graphicsId({stage=5,item=155})==4117,'Oran fruit uses its ROM graphics ID')
local Gfx=require('src.import.Gen4ObjectGfx')
game.data.gen4_overworld={sprites={[Gfx.name(4117)]={member=319}}}
local sheet={image='rom-oran-fruit'}
game.data.sprites={SPRITE_G4_319=sheet}
patches[2]={stage=5,item=155}
local npc={id='berry',def={berryPatch=2}}
local creations=0
local SR={new=function(def) creations=creations+1; return {def=def} end}
B.pose(game,npc,SR)
check(npc.sprite.def==sheet and not npc.berryVisualEmpty,'patch renders extracted fruit sheet')
B.pose(game,npc,SR)
check(creations==1,'unchanged stage reuses sprite renderer')
patches[2].stage=0; B.pose(game,npc,SR)
check(npc.berryVisualEmpty and not npc.hidden,'empty patch suppresses art without hiding script object')
patches[2].stage=5; B.pose(game,npc,SR)
check(not npc.berryVisualEmpty,'returning fruit restores visibility')
if arg[1] then
  local root=arg[1]..'/data/generated/'
  local overworld=assert(loadfile(root..'gen4_overworld.lua'))()
  local sprites=assert(loadfile(root..'sprites.lua'))()
  for gfx=4096,4288 do
    local name=Gfx.name(gfx)
    local record=name and overworld.sprites[name]
    local key=record and ('SPRITE_G4_%03d'):format(record.member)
    check(key and sprites[key] and sprites[key].image,'imported berry sheet '..gfx)
  end
end
print(checks..' berry and hidden-item checks passed')
