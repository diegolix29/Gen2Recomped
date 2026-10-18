package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local Nds=require('src.import.NdsRom')
local E=require('src.import.Gen4EvolutionArt')
local platinum=assert(Nds.open('Pokemon - Platinum Version (USA) (Rev 1).nds'))
local reference=assert(E.images(platinum))
local checks=0
for _,filename in ipairs({'Pokemon - HeartGold Version (USA).nds','Pokemon - SoulSilver Version (USA, Australia).nds'})do
 local rom=assert(Nds.open(filename))
 local art=assert(E.images(rom,E.HGSS));local ink=assert(E.data(rom,E.HGSS))
 for key,pic in pairs(reference)do assert(art[key].rgba==pic.rgba,key..' differs from identical Platinum resource');checks=checks+1 end
 assert(art.bottom.rgba:find(string.char(255,255,255,255),1,true));checks=checks+1
 assert(ink.bank==197 and ink.count==13);checks=checks+1
 local s=assert(require('src.import.Gen4Sdat').open(rom:read('/data/sound/gs_sound_data.sdat')))
 local audio=require('src.import.Gen4Audio').catalogue(s,{})
 assert(audio.special.evolution==1011 and audio.special.evolved==1188);checks=checks+1
end
local state=require('src.ui.Gen4EvolutionState')
local text=state.text({data={text={TEXT_B0197_00915='HGSS {STRVAR_1 1 0 0}'},gen4_evolution_ink={bank=197}}},'evolving','CHIKORITA')
assert(text=='HGSS CHIKORITA');checks=checks+1
print(checks..' HGSS evolution parity checks, 0 failed')
