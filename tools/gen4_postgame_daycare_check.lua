package.path='./?.lua;'..package.path
local C=require('src.script.Commands')
local G=require('src.script.Gen4Commands')
local VM=require('src.script.Gen4ScriptVM')
local ctx={save={flags={},hallOfFame={}},g4Compare=2,lastCheck=false}
C.g4_game_completed(ctx,0x8000);assert(ctx.save.gen4Vars[0x8000]==0)
C.g4_set_game_completed(ctx)
assert(ctx.save.flags.FLAG_G4_0964==true,'completion must share the ROM flag with generic flag commands')
C.g4_game_completed(ctx,0x8000);assert(ctx.save.gen4Vars[0x8000]==1,'completion precedes induction')
assert(#ctx.save.hallOfFame==0 and ctx.g4Compare==2 and ctx.lastCheck==false,'query cannot alter records or comparison state')
ctx.save.flags={};ctx.save.hallOfFame={{}}
C.g4_game_completed(ctx,0x8000);assert(ctx.save.gen4Vars[0x8000]==1,'legacy runtime induction must unlock postgame')
ctx.save.flags.FLAG_G4_0964=false
C.g4_game_completed(ctx,0x8000);assert(ctx.save.gen4Vars[0x8000]==0,'explicit cleared ROM flag must take precedence')
ctx.save.flags={}
ctx.save.hallOfFame={}
-- Daycare_HasEgg is "the offspring personality is non-zero" (src/pokemon/Gen4DayCare.lua)
C.g4_daycare_has_egg(ctx,0x8000);assert(ctx.save.gen4Vars[0x8000]==0 and ctx.save.gen4DayCare==nil,'query cannot create a day care save')
ctx.save.gen4DayCare={mons={},personality=0,counter=0}
C.g4_daycare_has_egg(ctx,0x8000);assert(ctx.save.gen4Vars[0x8000]==0)
ctx.save.gen4DayCare.personality=0x12345678
C.g4_daycare_has_egg(ctx,0x8000);assert(ctx.save.gen4Vars[0x8000]==1)
ctx.save.gen4DayCare.personality=0
C.g4_daycare_has_egg(ctx,0x8000);assert(ctx.save.gen4Vars[0x8000]==0)
assert(ctx.g4Compare==2 and ctx.lastCheck==false)
local root=arg[1] or 'G:/Gen2Recomped/platinum/data/generated/'
local pool=assert(loadfile(root..'map_scripts.lua'))()
local count={checkgamecompleted=0,setgamecompleted=0,checkdaycarehasegg=0}
local handlers={checkgamecompleted='g4_game_completed',setgamecompleted='g4_set_game_completed',checkdaycarehasegg='g4_daycare_has_egg'}
for label,block in pairs(pool.scripts) do
 for _,ins in ipairs(block.instructions or {}) do
  if count[ins.name] then
   count[ins.name]=count[ins.name]+1
   local row=VM.lower({ins})[1]
   assert(row[1]==handlers[ins.name],'wrong handler at '..label)
   if ins.args[1] then assert(row[2]==ins.args[1],'destination changed at '..label) end
  end
 end
end
for name,n in pairs(count) do if name~='setgamecompleted' then assert(n>0,'missing ROM corpus coverage for '..name) end; print(name..': '..n..' ROM sites') end
assert(VM.lower({{name='setgamecompleted',args={}}})[1][1]=='g4_set_game_completed')
-- Execute a real check instruction followed by the ROM comparison and branch.
-- This verifies that the destination result, not a leftover comparison, governs dialogue.
local Runner=require('src.script.ScriptRunner')
local function branch(completed)
 local rows=VM.lower({{name='checkgamecompleted',args={0x8000}}})
 rows[#rows+1]={'g4_compare_var_value',0x8000,1}
 rows[#rows+1]={'g4_jump_if',1,'postgame'}
 rows[#rows+1]={'set_field','dialogueBranch','beforeLeague'}
 rows[#rows+1]={'jump','end'}
 rows[#rows+1]={'label','postgame'}
 rows[#rows+1]={'set_field','dialogueBranch','afterLeague'}
 local save={flags={[G.GAME_COMPLETED_FLAG]=completed}}
 local runner=Runner.new({save=save,data={}}, {})
 runner:run(rows)
 assert(not runner:isRunning() and save.dialogueBranch==(completed and 'afterLeague' or 'beforeLeague'))
end
branch(false);branch(true)
print('Postgame persistence, old-save recovery, explicit flag clearing, egg availability and NPC branches passed')

local champion={species=387,hp=0,ribbons={[24]=true}}
local second={species=390,hp=10,ribbons={[32]=true}}
local egg={species=175,isEgg=true,ribbons={[25]=true}}
local incubating={species=490,eggSteps=20}
local save={flags={},party={champion,egg,second,incubating},hallOfFame={}}
-- `cleargame` is ONE row now, `g4_clear_game` (Gen4ScriptVM L.cleargame):
-- ClearGame's whole flow -- flags and ribbons, the Hall of Fame app, the
-- induction, the gift offer, the save lines, the credits -- lives in
-- Gen4Commands.g4_clear_game. Drive it with the screens stubbed and the save
-- write held off, so nothing here touches a real save.
local clearRows=VM.lower({{name='cleargame',args={}}})
assert(#clearRows==1 and clearRows[1][1]=='g4_clear_game','cleargame must lower to the one g4_clear_game row')
local screens={}
local SaveStub={applyPostGameHome=function() end,save=function() error('the check must not write a save') end}
local stubs={
 ['src.core.SaveData']=SaveStub,
 ['src.script.ScriptSave']={write=function() return false end},
 ['src.ui.Gen4Credits']={new=function(_,opts) return {kind='credits',opts=opts} end},
 ['src.render.TextBox']={new=function(_,text,onDone) return {kind='text',text=text,onDone=onDone} end},
 ['src.pokemon.Gen4MysteryGift']={offer=function(_,after) screens[#screens+1]={kind='gift'};after() end},
 ['src.ui.Gen4HallOfFame']={new=function(game,opts)
   local sv=game.save
   assert(sv.flags.FLAG_G4_0964 and sv.flags.FLAG_G4_0966,'Hall of Fame opened before postgame flags')
   assert(champion.ribbons[32] and second.ribbons[32],'championship ribbons missing at induction')
   assert(not egg.ribbons[32] and incubating.ribbons==nil,'eggs cannot receive champion ribbons')
   return {kind='hof',opts=opts}
 end},
}
local saved={}
for name,stub in pairs(stubs) do saved[name]=package.loaded[name];package.loaded[name]=stub end
local game={save=save,data={},stack={push=function(_,screen) screens[#screens+1]=screen end}}
local function win()
 screens={}
 C.g4_clear_game({game=game,save=save})
 local hof=screens[1]
 assert(hof and hof.kind=='hof','ClearGame must open the Hall of Fame first')
 hof.opts.onDone()
 -- the gift offer, then "Saving..." and "<player> saved the game.", then credits
 local i=2
 assert(screens[i].kind=='gift');i=i+1
 assert(screens[i].kind=='text');screens[i].onDone();i=i+1
 assert(screens[i].kind=='text');screens[i].onDone();i=i+1
 assert(screens[i].kind=='credits','credits must follow the save lines')
 return screens[i].opts
end
local first=win()
assert(first.canSkip==false,'the first clear cannot skip the credits')
local again=win()
assert(again.canSkip==true,'a repeat clear may skip the credits')
assert(#save.hallOfFame==2,'repeat induction must still record one entry per win')
assert(#save.hallOfFame[1]==4,'every party member is in the induction, eggs and fainted ones included')
assert(champion.ribbons[24] and egg.ribbons[25],'awarding champion ribbon must preserve existing ribbons')
for name in pairs(stubs) do package.loaded[name]=saved[name] end
local wins=0
for label,block in pairs(pool.scripts) do
 for _,ins in ipairs(block.instructions or {}) do
  if ins.name=='cleargame' then
   wins=wins+1
   assert(VM.lower({ins})[1][1]=='g4_clear_game','missing ClearGame at '..label)
  end
 end
end
assert(wins>0,'championship opcode missing from ROM corpus')
print(wins..' real ClearGame site; fainted members, eggs, ribbon preservation, repeated induction and flag-before-scene order passed')
