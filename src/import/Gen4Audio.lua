local S=require('src.import.Gen4Sdat')
local A={}
function A.catalogue(sdat,headers)
 local out={songs={},sfx={},mapSongs={},mapNightSongs={},outdoorSongs={},special={},battle={}}
 local symbols={}
 for i=0,S.count(sdat,S.SEQ)-1 do
  local seq=S.sequence(sdat,i);local name=S.name(sdat,S.SEQ,i)
  if seq and name then
   local def={nds=i,name=name};out.songs[i]=def;out.songs[name]=def;out.sfx[i]=def;out.sfx[name]=def;symbols[name]=i
  end
 end
 for _,h in pairs(headers or {}) do
  if h.internalName then
   out.mapSongs[h.internalName]=h.dayMusic;out.mapNightSongs[h.internalName]=h.nightMusic
   if h.allowFly then out.outdoorSongs[h.dayMusic]=true;out.outdoorSongs[h.nightMusic]=true end
  end
 end
 out.special={bike=symbols.SEQ_BICYCLE,surf=symbols.SEQ_NAMINORI,evolution=symbols.SEQ_SHINKA,
  title=symbols.SEQ_TITLE01,opening=symbols.SEQ_TITLE00,heal=symbols.SEQ_FANFA5}
 out.battle={wild=symbols.SEQ_BA_POKE,trainer=symbols.SEQ_BA_TRAIN,gym=symbols.SEQ_BA_GYM,
  champion=symbols.SEQ_BA_CHANP,final=symbols.SEQ_BA_CHANP,rival=symbols.SEQ_BA_RIVAL,
  wildWin=symbols.SEQ_WINPOKE,trainerWin=symbols.SEQ_WINTRAIN,gymWin=symbols.SEQ_WINTGYM,
  finalWin=symbols.SEQ_WINCHAMP,championWin=symbols.SEQ_WINCHAMP}
 for role,name in pairs({Press_AB='SEQ_SE_PL_BUTTON',Ball_Toss='SEQ_SE_DP_BOWA',PC_On='SEQ_SE_DP_PC_ON',
  PkmnHealed='SEQ_FANFA5'}) do if symbols[name] then out.sfx[role]=out.sfx[symbols[name]] end end
 return out
end
return A
