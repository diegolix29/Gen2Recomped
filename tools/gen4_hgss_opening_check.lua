package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('src.ui.HgssOpeningTimeline')
assert(T.at(219).scene=='credits' and T.at(220).scene=='sky')
local sky=T.at(220+240)
assert(sky.scroll1==-32 and sky.scroll2==-16 and sky.credit==0,
  'native 240-frame parallax completes before the legendary flyby')
assert(T.at(220+367).bird==nil and T.at(220+368).bird==0,
  'bird starts after the 128-frame hold following the scroll')
assert(T.at(220+458).white==0 and T.at(220+523).white==1,
  '90-frame bird hold precedes a 65-frame fade to white')
local ethan=T.at(T.SCENE2+154)
assert(ethan.pan==32 and ethan.enter==192,'Ethan slow-pan lands at its native displacement')
assert(T.at(T.SCENE2+161).pan==96 and T.at(T.SCENE2+227).pan==128,
  'fast pan and Lyra pan preserve their separate durations/displacements')
local Montage=require('src.ui.HgssOpeningMontage')
assert(T.at(T.SCENE3).city=='op_wakaba','city flyovers follow the trainer wipe')
assert(T.at(T.SCENE3+49).city=='op_kogane' and T.at(T.SCENE3+104).city=='op_enju',
  'three dedicated miniature maps keep the native shot order')
assert(T.at(T.SCENE3+211).bottom and not T.at(T.SCENE3+210).bottom,
  'single-screen presentation follows the active montage panel')
assert(Montage.at(275).section==43 and Montage.at(292).section==44 and not Montage.at(311).silhouette,
  'rival panel reveals and silhouette removal retain their source times')
assert(Montage.at(481).eusine==0 and Montage.at(570).unown1==0,
  'Eusine and Unown use their independent delayed animation starts')
assert(Montage.at(640).suicuneExit==1 and Montage.at(894).rocketScroll==1,
  'beast exit completes before the 254-frame Rocket pan finishes')
local Art=require('src.import.Gen4HgssBootArt')
local R=require('src.import.NdsRom')
local birdCells={}
for _,row in ipairs({{'heartgold','Pokemon - HeartGold Version (USA).nds'},
  {'soulsilver','Pokemon - SoulSilver Version (USA, Australia).nds'}}) do
  local rom=assert(R.open(row[2]));local pictures,sequences,metadata=Art.images(rom);rom:close()
  assert(pictures.sky_top.width==256 and pictures.trainers_back.width==512,
    'opening keeps native background dimensions for wrapped scrolling')
  assert(#pictures.trainers_back.rgba==512*512*4,'large tilemap has all four screen blocks')
  local first=T.pose(sequences,'sky_actor',1,0)
  local later=T.pose(sequences,'sky_actor',1,60)
  assert(first.scaleX>0 and first.scaleX<.1 and later.scaleX>first.scaleX,
    'legendary affine animation grows from its native tiny silhouette')
  assert(T.pose(sequences,'sky_actor',1,10000)==sequences.sky_actor[1].frames[#sequences.sky_actor[1].frames],
    'one-shot opening animation clamps rather than restarting')
  birdCells[row[1]]=first.cell
  assert(T.pose(sequences,'flowers',0,0).y==-250 and T.pose(sequences,'flowers',0,29).y==250,
    'flowers retain their complete translation across both panels')
  assert(pictures.trainers_0.originX~=nil and sequences.trainers[5],
    'both trainers retain all native cell parts and their origin offsets')
  assert(pictures.montage_42 and pictures.montage_52 and sequences.eusine_unown[3],
    'rival, beasts, executives, Eusine and three Unown sequences import')
  assert(metadata.scene4 and #metadata.emitters==9 and pictures.opening_particle_0
    and pictures.final_top_front and pictures.final_bottom_front,'starter SPA and final scene layers import')
  metadata.sequences=sequences
  local starters=require('src.ui.HgssOpeningStarters').new(metadata)
  local cyndaquilY=metadata.emitters[4].fields.basePos[2]
  local peak=0
  for tick=0,500 do
    starters:step(tick)
    for _,system in ipairs(starters.systems) do peak=math.max(peak,system:total()) end
    if starters.done then break end
  end
  assert(starters.done and #starters.starts==3 and peak>0 and starters.doneFrame<400,
    'all three attacks emit live particles and finish without a fixed timer')
  assert(starters.starts[2]>starters.starts[1] and starters.starts[3]>starters.starts[2],
    'starter screen swaps follow particle completion')
  assert(metadata.emitters[4].fields.basePos[2]==cyndaquilY,'emitter-position callback cannot mutate cached resource fields')
  assert(starters.systems[1].emitters[1].fields.basePos[3]==1/64,'native SPA callback sets the emitter z position')
  local done=starters.doneFrame;starters:step(1000);assert(starters.doneFrame==done,'completed controller remains stable')
end
assert(birdCells.heartgold~=birdCells.soulsilver,'versions use their own legendary animation')
local ended,popped=0,0
local key
local game={data={gen4_hgss_boot_art={studio_top={},sequences={}}},
 input={wasPressed=function(_,k) return k==key end},stack={pop=function() popped=popped+1 end}}
local Intro=require('src.ui.HgssIntro')
local intro=Intro.new(game,function() ended=ended+1 end)
intro.frame=108;key='a';intro:update(1/30);assert(ended==0,'copyright card cannot be skipped early')
intro.frame=109;key='a';intro:update(1/30);assert(ended==1 and popped==1,'skip becomes available with the studio card')
intro:update(1/30);assert(ended==1,'skip callback runs once')
local full=Intro.new(game,function() ended=ended+1 end)
key=nil;full.frame=219;full:update(1/30);assert(not full.done,'expanded movie must not stop after the credits')
full.frame=T.END-1;full:update(1/30);assert(full.done and ended==2,'movie completion reaches the next boot state')
local resourceRom=assert(R.open('Pokemon - HeartGold Version (USA).nds'))
local _,sequences,metadata=Art.images(resourceRom);resourceRom:close()
metadata.sequences=sequences;metadata.studio_top={};game.data.gen4_hgss_boot_art=metadata
local complete=Intro.new(game,function() ended=ended+1 end)
for tick=1,T.SCENE4+600 do complete:update(1/30);if complete.done then break end end
assert(complete.finalStart and complete.done and ended==3,'full five-scene path reaches the title callback')
print('HGSS opening: both ROMs, native layers/affine results, timing, one-shots, skip and completion passed')
for _,hz in ipairs({30,60,120}) do
  local clock=Intro.new(game,function() end)
  for i=1,hz do clock:update(1/hz) end
  assert(clock.frame==30,'opening advances 30 native ticks per second at '..hz..' Hz')
end
print('HGSS opening 30 Hz clock is independent of update frequency')
