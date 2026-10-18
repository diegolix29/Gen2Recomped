package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local V=require('src.core.GameVersion'); V.set('heartgold')
local S=require('src.ui.SecondScreen')
local mode='swap'
S.mode=function() return mode end
S.combined=function() return mode=='vertical' end
S.toLocal=function(_,x,y) if y>=192 then return x,y-192 end end
local Renderer=require('src.render.Renderer')
Renderer.uiPresentation={x=10,y=20,scaleX=2,scaleY=2}
local Menu=require('src.ui.Gen4MainMenu')
local M=require('src.import.Gen4HgssMainMenu')
local opened,newGames,continued=0,0,0
local game={data={gen4_menus=M.words(function(_,i) return 'word'..i end)},
  input={wasPressed=function() return false end},stack={pop=function() end}}
local menu=Menu.new(game,{onNewGame=function() newGames=newGames+1 end,
  onContinue=function() continued=continued+1 end})
menu.items={{key='continue',lines=5},{key='newGame',lines=2}}
menu.scrollPos=0
menu.save={pokedex={seen={[1]=true,[2]=true},owned={[1]=true}}}
assert(menu:value('ownedCount')=='1','HGSS summary counts caught, not merely seen')
assert(menu:touchpressed(1,10+30*2,20+110*2) and newGames==1,
  'single-screen taps use the scaled primary UI rectangle')
mode='vertical'; menu.scrollPos=0
assert(not menu:touchpressed(1,30,30) and continued==0,'top-screen taps must not choose lower-screen rows')
assert(menu:touchpressed(1,30,192+30) and continued==1,'lower-screen taps choose Continue')
local Screens=require('src.ui.Screens')
Screens.push=function(_,id,opts)
  assert(id=='Gen4MainMenu' and opts.onNewGame,'title preserves Game boot callbacks')
  opened=opened+1
end
local Title=require('src.ui.HgssTitle')
local key
game.input.wasPressed=function(_,k) return k==key end
local title=Title.new(game,{onNewGame=function() end})
title:touchpressed(1,20,20);title:update(1/30)
assert(opened==0,'early taps cannot skip the title lockout')
title.frame=29; key='l'; title:update(1/30)
assert(title.bottom,'L exposes the legendary panel on a single screen')
key=nil; title:touchpressed(1,20,20); title:update(1/30)
assert(opened==1,'tap opens main menu after title lockout')
title:openMenu();assert(opened==1,'title cannot push duplicate menus')
key='a';title:update(1/30);assert(opened==2,'returning from menu restores title input without a stack resume callback')
print('HGSS title/menu: callbacks, panel switch, tap lockout, scaled single/dual touches and caught count passed')

local Camera=require('src.ui.HgssTitleCamera')
for _,version in ipairs({'heartgold','soulsilver'}) do
  local c=Camera.new(version);local x=c.eye[1]
  for i=1,300 do Camera.step(c) end
  assert(c.eye[1]==x,'first title camera position holds for 10*30 ticks')
  Camera.step(c);assert(c.eye[1]==x-5,'camera moves per axis at the source speed')
  for i=1,1500 do Camera.step(c) end
  assert(c.index>=1 and c.index<=4,'camera cycles its four targets without the sentinel')
end
local replayed,callback=0
Screens.push=function(_,id,done) assert(id=='HgssIntro');replayed=replayed+1;callback=done end
local idle=Title.new(game,{})
key=nil;idle.frame=Title.IDLE_FRAMES;idle:update(1/30)
assert(idle.transition==0,'native 2340-tick idle timer starts the audio fade')
for i=1,65 do idle:update(1/30) end
assert(replayed==0,'replay waits for its sound and screen fades')
idle:update(1/30);assert(replayed==1,'timeout replays the opening exactly once')
callback();assert(idle.frame==0 and idle.transition==nil,'completed replay resets the title camera/clock')
print('HGSS title camera holds, movement, cycling and idle replay passed')
for _,hz in ipairs({30,60,120}) do
  local clock=Title.new(game,{})
  for i=1,hz do clock:update(1/hz) end
  assert(clock.frame==30,'title advances 30 native ticks per second at '..hz..' Hz')
end
print('HGSS title 30 Hz clock is independent of update frequency')
local Oak=require('src.ui.HgssOakIntro')
for _,hz in ipairs({30,60,120}) do
  local oak=Oak.new(game);oak.phase='release';oak.elapsed=0
  for i=1,hz do oak:update(1/hz) end
  assert(oak.frame==30 and oak.elapsed==30,'Oak/Marill reveal keeps native timing at '..hz..' Hz')
end
print('HGSS professor/Marill 30 Hz timing passed')
