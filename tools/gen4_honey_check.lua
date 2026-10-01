package.path='./?.lua;'..package.path
local H=require('src.world.Gen4HoneyTrees');local checks=0
local function check(v,s) assert(v,s);checks=checks+1 end
local rom=assert(require('src.import.NdsRom').open('Pokemon - Platinum Version (USA) (Rev 1).nds'))
local tables=assert(H.tables(rom));check(tables[1][1]==415 and tables[3][6]==446,'actual ROM Honey encounter tables')
local save={player={id=0},party={}}
local rolls={99,99,0};local index=0
local function rng() index=index+1;return rolls[index] end
check(H.treeId(347)==0 and H.treeId(411)==nil,'21 native tree map IDs')
local tree=H.slather(save,4,rng,1000)
check(tree.group==1 and tree.slot==1 and tree.shakes==2,'native group, slot and shaking selection')
check(H.status(save,4,1000)==2,'fresh Honey is slathered')
check(H.status(save,4,1000+359*60)==2,'not ready before six hours')
check(H.status(save,4,1000+360*60)==3,'ready exactly at six hours')
check(H.status(save,4,1000+1439*60)==3,'encounter persists until 24 hours')
check(H.status(save,4,1000+1440*60)==1,'Honey expires at 24 hours')
local species,level=H.consume({constants={gen4HoneyEncounters=tables}},save,4,function() return 10 end,1000+360*60)
check(species==415 and level==10,'Honey starts selected encounter with native level range')
check(H.status(save,4,1000+360*60)==1,'battle consumes Honey')
local rare=H.rareTrees(0);check(rare[1]==0 and rare[4]==3,'trainer-dependent Munchlax trees resolve collisions')
local ground={offsetX=0,offsetY=0,grid={width=1,land={0}},terrain={chunks={[0]={objects={{model=26,x=-248,z=-248}}}}}}
check(H.facingTree(ground,0,0) and not H.facingTree(ground,5,5),'Honey interaction uses native prop location')
package.loaded['src.script.Commands']={meta={}}
package.loaded['src.core.Logger']={warn=function() end}
local VM=require('src.script.Gen4ScriptVM')
for _,name in ipairs({'slatherhoneytree','gethoneytreestatus','starthoneytreebattle','stophoneytreeshaking'}) do check(VM.lowered(name),'lowered '..name) end
rom:close();print(checks..' ROM Honey Tree checks passed')
