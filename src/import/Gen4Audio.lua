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
 out.special={bike=symbols.SEQ_BICYCLE,surf=symbols.SEQ_NAMINORI,evolution=symbols.SEQ_SHINKA or symbols.SEQ_GS_SHINKA,
  evolved=symbols.SEQ_ME_SHINKAOME,
  title=symbols.SEQ_TITLE01 or symbols.SEQ_GS_TITLE,
  opening=symbols.SEQ_TITLE00 or symbols.SEQ_GS_TITLE,
  heal=symbols.SEQ_FANFA5 or symbols.SEQ_ME_ASA}
 out.battle={wild=symbols.SEQ_BA_POKE,trainer=symbols.SEQ_BA_TRAIN,gym=symbols.SEQ_BA_GYM,
  champion=symbols.SEQ_BA_CHANP,final=symbols.SEQ_BA_CHANP,rival=symbols.SEQ_BA_RIVAL,
  wildWin=symbols.SEQ_WINPOKE,trainerWin=symbols.SEQ_WINTRAIN,gymWin=symbols.SEQ_WINTGYM,
  finalWin=symbols.SEQ_WINCHAMP,championWin=symbols.SEQ_WINCHAMP}
 -- HeartGold / SoulSilver spell them SEQ_GS_VS_* / SEQ_GS_WIN* (pokeheartgold
 -- sndseq.h; WIN2 wild, WIN1 trainer, WIN3 leaders / Elite Four / Champion,
 -- battle_controller_player.c). Per-class themes: Gen4BattleMusic.
 if not out.battle.wild and symbols.SEQ_GS_VS_NORAPOKE then
  out.battle={wild=symbols.SEQ_GS_VS_NORAPOKE,trainer=symbols.SEQ_GS_VS_TRAINER,gym=symbols.SEQ_GS_VS_GYMREADER,
   champion=symbols.SEQ_GS_VS_CHAMP,final=symbols.SEQ_GS_VS_CHAMP,rival=symbols.SEQ_GS_VS_RIVAL,
   rocket=symbols.SEQ_GS_VS_ROCKET,kantoWild=symbols.SEQ_GS_VS_NORAPOKE_KANTO,
   kantoTrainer=symbols.SEQ_GS_VS_TRAINER_KANTO,kantoGym=symbols.SEQ_GS_VS_GYMREADER_KANTO,
   wildWin=symbols.SEQ_GS_WIN2,trainerWin=symbols.SEQ_GS_WIN1,gymWin=symbols.SEQ_GS_WIN3,
   finalWin=symbols.SEQ_GS_WIN3,championWin=symbols.SEQ_GS_WIN3,brainWin=symbols.SEQ_GS_WINBRAIN}
 end
 for role,name in pairs({Press_AB='SEQ_SE_PL_BUTTON',Ball_Toss='SEQ_SE_DP_BOWA',PC_On='SEQ_SE_DP_PC_ON',
  PkmnHealed='SEQ_FANFA5'}) do if symbols[name] then out.sfx[role]=out.sfx[symbols[name]] end end
 if symbols.SEQ_SE_DP_BOWA then out.sfx.Healing_Machine=out.sfx[symbols.SEQ_SE_DP_BOWA] end
 if not out.sfx.PkmnHealed and symbols.SEQ_ME_ASA then out.sfx.PkmnHealed=out.sfx[symbols.SEQ_ME_ASA] end
 return out
end
return A
