io.stdout:setvbuf("no")
local root=assert(os.getenv("ROOT")):gsub("\\","/").."/"
package.path=root.."?.lua;"..root.."?/init.lua;"..package.path
function love.load()
 local ok,err=xpcall(function()
  local Art=require("src.pokewalker.WalkerArt");Art._roots={assert(os.getenv("ROM_CACHE_ROOT"))};Art.forget()
  local D=require("src.pokewalker.WalkerDelivery")
  local GV=require("src.core.GameVersion");GV.set("crystal")
  local data=assert(D.dataset("emerald"))
  local save={player={name="TEST",id=123},inventory={},boxes={{}},currentBox=1,
   walkerInbox={items={{name="Potion",count=5},{name="Poke Ball",count=3}},mons={{species=25,level=10}},returning={}}}
  local worked,report=D.apply(save,"emerald",data)
  assert(worked,report)
  assert(report and report.caught==1 and report.items==2,"delivery report missing")
  assert(save.boxes[1][1] and save.boxes[1][1].species,"catch not boxed")
  assert(save.inventory.POTION==5 and save.inventory.POKE_BALL==3,"items not in bag")
  assert(not save.walkerInbox,"successful parcel still queued")
  assert(GV.get()=="crystal","delivery changed preview version")
  local Boxes=require("src.pokemon.Boxes");assert(Boxes.capacity()==20,"delivery changed preview boxes")
  print("PASS real Emerald parcel: boxed Pokemon, Potion x5, Poke Ball x3; preview restored")
  save.inventory.POTION=98
  save.walkerInbox={items={{name="Potion",count=5}},mons={{species=99999,level=5}},returning={}}
  assert(D.apply(save,"emerald",data))
  assert(save.inventory.POTION==99 and save.walkerInbox.items[1].count==4,"stack overflow lost")
  assert(#save.walkerInbox.mons==1,"unknown species lost")
  assert(not save.pcItems,"delivery diverted items into PC")
  save.inventory.POTION=95
  assert(D.apply(save,"emerald",data));assert(save.inventory.POTION==99 and #save.walkerInbox.items==0,"queued stack not retried")
  print("PASS partial stack and unknown species retained, retry fills bag")
  local full={inventory={},boxes={},currentBox=1,player={name="TEST",id=55},
   walkerInbox={mons={{species=1,level=5}},items={},returning={}}}
  for b=1,14 do full.boxes[b]={};for slot=1,30 do full.boxes[b][slot]={species="BULBASAUR"} end end
  assert(D.apply(full,"emerald",data))
  local pending=assert(full.walkerInbox.mons[1].raw,"full PC lost catch")
  local identity=require("src.core.SaveSerializer").encode(pending)
  full.boxes[14][30]=nil
  assert(D.apply(full,"emerald",data))
  assert(not full.walkerInbox and require("src.core.SaveSerializer").encode(full.boxes[14][30])==identity,"full-PC retry changed catch")
  print("PASS full PC retains individual and retry preserves identity")
  -- Real launcher APIs and real isolated slot files, not only an inbox call.
  local SD=require("src.core.SaveData")
  assert(not SD.isPortable(),"test must not use portable player saves")
  local Ser=require("src.core.SaveSerializer")
  local source=assert(SD.createSlot("emerald"));local wrong=assert(SD.createSlot("crystal"))
  assert(SD.slotDiskPath("emerald",source):find(love.filesystem.getSaveDirectory(),1,true)==1,"unsafe fixture path")
  local function fixture()return {player={name="TEST",id=55},party={},inventory={},boxes={{}},currentBox=1}end
  local real=fixture();real.walkerInbox={mons={{species=25,level=10}},items={},returning={}}
  assert(D.apply(real,"emerald",data));local original=real.boxes[1][1]
  real.boxes[1]={[30]=original}
  assert(SD.writeSlot("emerald",source,real));assert(SD.writeSlot("crystal",wrong,fixture()))
  local function disk(v,slot)
   local f=assert(io.open(SD.slotDiskPath(v,slot),"rb"));local bytes=f:read("*a");f:close();return Ser.decode(bytes)
  end
  local Link=require("src.pokewalker.WalkerLink");local W=require("src.pokewalker.Walker")
  local E=require("src.pokewalker.WalkerEconomy")
  local st=W.newState();local list=assert(Link.boxMons("emerald",source))
  assert(#list==1 and list[1].source.index==30,"sparse source slot invisible")
  assert(Link.send(st,list[1],0));assert(not disk("emerald",source).boxes[1][30],"walker not removed from source PC")
  assert(E.grantPokemon(st,1,5,"minigame","Bulbasaur"));assert(Link.sendCaught(st))
  assert(disk("emerald",source).boxes[1][1],"radar catch not materialized")
  st.watts=1000
  assert(E.buyItem(st,{name="Potion",count=5,price=40,gen=1},{version="crystal",slot=wrong}))
  assert(disk("emerald",source).inventory.POTION==5,"Watt purchase missed walking source")
  assert(next(disk("crystal",wrong).inventory)==nil,"purchase reached stale selected save")
  assert(E.grantItem(st,"Potion",3,"minigame"));assert(Link.bringHome(st,true))
  assert(disk("emerald",source).inventory.POTION==8 and st.walking,"bag present not delivered while walking")
  assert(Link.bringHome(st,false));local after=disk("emerald",source)
  assert(after.boxes[1][30] and after.boxes[1][30].personality==original.personality,"original did not return to sparse source slot")
  assert(not after.walkerInbox,"return was left unapplied")
  local before=Ser.encode(after);assert(not require("src.pokewalker.WalkerInbox").apply(after,data));assert(Ser.encode(after)==before,"delivery replayed")
  print("PASS source slot, sparse PC return, radar/minigame presents and Watt Shop disk delivery; no replay")
  local nearlyFull=disk("emerald",source);nearlyFull.inventory.POTION=98
  assert(SD.writeSlot("emerald",source,nearlyFull))
  local writer=SD.writeSlot;SD.writeSlot=function()return false,"simulated disk full"end
  st.walking={source={version="emerald",slot=source}};st.caught={{species=4,level=5}};st.watts=500
  assert(not Link.sendCaught(st) and #st.caught==1,"failed write removed catch")
  assert(not E.buyItem(st,{name="Potion",price=40},{version="emerald",slot=source}) and st.watts==500,"failed write charged watts")
  st.items={{name="Potion",count=5}};st.caught={}
  assert(not Link.bringHome(st,true) and st.items[1].count==5,"failed partial-stack write consumed source items")
  SD.writeSlot=writer
  print("PASS failed disk write retains catches and watts")
  for _,version in ipairs({"red","blue","yellow","gold","silver","crystal","polishedcrystal","prism","firered","emerald","platinum","heartgold","soulsilver","black","white"})do
   local other=D.dataset(version)
   if other then
    local dex
    for key,def in pairs(other.pokemon)do
     if type(def)=="table" then local n=tonumber(def.dex) or (type(key)=="number" and key);if n and n>0 and (not dex or n<dex)then dex=n end end
    end
    assert(dex,"no species in "..version)
    local fixture={inventory={},boxes={{}},currentBox=1,player={name="TEST",id=55},
      walkerInbox={mons={{species=dex,level=5}},items={{name="Potion",count=2}},returning={}}}
    local worked,rep=D.apply(fixture,version,other)
    assert(worked,version..": "..tostring(rep))
    assert(rep and rep.caught==1 and rep.items==1,version.." did not materialize rewards")
    assert(fixture.boxes[1][1] and not fixture.walkerInbox,version.." missing boxed reward")
    assert(GV.get()=="crystal" and Boxes.capacity()==20,"preview changed by "..version)
    assert(fixture.pokedex.owned[fixture.boxes[1][1].species],"delivered catch not registered")
    local previous=GV.get();GV.set(version)
    local report=SD.validate(fixture,other);GV.set(previous)
    assert(#report.lostMons==0 and #report.lostItems==0,version.." validation quarantined a delivered reward")
    Boxes.load(nil) -- the validator intentionally adopts its active cartridge

    print("PASS source definitions and cartridge context",version)
   end
  end

 end,debug.traceback)
 if not ok then print(err) end
 love.event.quit(ok and 0 or 1)
end
