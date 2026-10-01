package.path='./?.lua;'..package.path
package.loaded['src.core.GameVersion']={isGen4=function() return true end,isGen3=function() return false end,isGen2=function() return false end}
package.loaded['src.core.Strings']=function(s) return s end
package.loaded['src.core.Sound']={play=function() end}
package.loaded['src.core.Logger']={warn=function() end}
local Boxes=require('src.pokemon.Boxes');Boxes.load({})
local PC=require('src.ui.Gen4BoxMenu')
local game={data={pokemon={[1]={name='ONE'},[2]={name='TWO'}},constants={}},save={party={{species=1,hp=10},{species=2,hp=10}}},stack={push=function() end,pop=function() end}}
local pc=PC.new(game,{mode='move'});local checks=0
local function check(v,s) assert(v,s);checks=checks+1 end
check(#game.save.boxes==18 and Boxes.capacity()==30,'native capacity')
local first,second={species=1},{species=2}
game.save.boxes[1][30]=first;game.save.boxes[2][30]=second
pc:carry(30);pc:changeBox(1);pc:carry(30)
check(game.save.boxes[1][30]==second and game.save.boxes[2][30]==first,'cross-box swap conserves both Pokemon')
pc:carry(30);pc:changeBox(1);pc:returnHeld()
check(game.save.boxes[2][30]==first and not pc.held,'cancel restores original box')
game.save.boxes[3][30]=second;pc:withdraw(30)
check(game.save.party[3]==second and not game.save.boxes[3][30],'withdraw sparse final slot')
pc:changeBox(-1);pc:carry(30);pc:carryFromParty(4)
check(game.save.party[4]==first and not game.save.boxes[2][30],'box to empty party slot')
pc:carryFromParty(4);pc:changeBox(1);pc:carry(29)
check(game.save.boxes[3][29]==first and #game.save.party==3,'party to another box')
pc:changeBox(15);check(game.save.currentBox==18,'all boxes accessible')
pc:changeBox(1);check(game.save.currentBox==1,'box wrap')
game.save.party={{species=1,hp=10},{species=2,hp=0},{species=2,egg=true,hp=10}}
pc:carryFromParty(1);check(not pc.held and #game.save.party==3,'cannot deposit last usable party member')
local F=require('src.world.Gen4FieldMoves')
local data={constants={badges={{id='COAL'},{id='FOREST'},{id='COBBLE'},{id='FEN'},{id='RELIC'},{id='MINE'},{id='ICICLE'},{id='BEACON'}}}}
local save={party={{moves={{id=57},{id=91}}}},badges={},inventory={}}
check(not F.partyMember(data,save,'SURF'),'Surf requires native badge')
save.badges.FEN=true;check(F.partyMember(data,save,'SURF')==save.party[1],'numeric native Surf move works')
check(F.partyMember(data,save,'DIG')==save.party[1],'Dig needs no badge')
save.party[1].egg=true;check(not F.partyMember(data,save,'DIG'),'egg cannot use field move')
check(F.recordsEscape({allowFly=true},{allowEscapeRope=true}),'record native cave entrance for Dig')
check(not F.recordsEscape({allowFly=false},{allowEscapeRope=true}),'nested cave leaves original Dig entrance intact')
local teleports,pops={},0
local partyGame={data={pokemon={[1]={name='ONE'}},constants=data.constants},save={party={{species=1,moves={{id=91},{id=100}}}},lastHeal={}},
 stack={pop=function() pops=pops+1 end,push=function() end},overworld={map={def={allowEscapeRope=true,allowFly=true}},escapePoint=function() return {} end,
 beginTeleportOut=function(_,_,opts) teleports[#teleports+1]=opts and 'dig' or 'teleport' end}}
local menu=require('src.ui.Gen4PartyMenu').new(partyGame)
check(menu:actions()[2]=='field:DIG' and menu:actions()[3]=='field:TELEPORT','numeric field moves appear in party actions')
menu:useFieldMove(partyGame.save.party[1],'DIG');menu:useFieldMove(partyGame.save.party[1],'TELEPORT')
check(teleports[1]=='dig' and teleports[2]=='teleport' and pops==2,'Dig and Teleport close party and start warp flow')
for _,path in ipairs({'src/ui/Gen4EvolutionState.lua','src/ui/Gen4Intro.lua','src/ui/Gen4Pokedex.lua','src/script/Gen4Commands.lua','src/world/OverworldController.lua'}) do check(loadfile(path),path..' syntax') end
print(checks..' storage and field-move checks passed')
