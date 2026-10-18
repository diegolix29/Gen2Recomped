love=require('tests.love_stub')
local checks=0
local function check(c,msg) assert(c,msg);checks=checks+1 end
local X=require('src.import.RomExtractorGen5')
local Art=require('src.import.Gen5JuniperArt')
local art
for _,version in ipairs({'black','white'}) do
  local path=version=='black' and 'Pokemon - Black Version (USA, Europe) (NDSi Enhanced).nds'
    or 'Pokemon - White Version (USA, Europe) (NDSi Enhanced).nds'
  local x=assert(X.new(path,version))
  local pictures={}
  x.saveImage=function(_,path,pic,extra)
    check(#pic.rgba==pic.width*pic.height*4,path..' RGBA complete')
    pictures[path]=pic
    local out={path=path,width=pic.width,height=pic.height}
    for k,v in pairs(extra or {}) do out[k]=v end
    return out
  end
  art=Art.build(x)
  check(art.text[6]:find('Welcome to the world',1,true),version..' native introduction words')
  check(art.text[23]:find('Cheren',1,true) and art.text[24]:find('Bianca',1,true),version..' fixed friend names')
  check(art.boy_portrait.width==128 and art.girl_portrait.height==256,version..' full portraits')
  check(math.floor(art.ink.text[1]/8)==11 and math.floor(art.ink.shadow[3]/8)==21,
    version..' native NFTR ink and shadow palette')
  check(art.juniper[0].ticks==116 and #art.juniper[0].frames>1,version..' animated Juniper idle')
  check(art.juniper[2].ticks==148 and #art.juniper[2].frames>25,version..' complete Pokeball release')
  check(art.minccino.width==96 and art.minccino.height==96,version..' reveal Pokemon')
  local box=pictures['bw_juniper/message_frame']
  check(box.width==256 and box.height==48 and box.rgba:byte(4)==0
    and box.rgba:byte((10*256+128)*4+4)==255,version..' rounded native intro frame')
  local bg=pictures['bw_juniper/background']
  check(bg.rgba:byte(1)==255 and bg.rgba:byte((140*256)*4+1)==41,version..' native white/gray stage')
  x:close()
end
local draw={}
package.loaded['src.render.Font']={width=function(s) return #s*6 end,draw=function(t) draw[#draw+1]=t end,
  drawDialogueBox=function() end,pushStyle=function() end,popStyle=function() end}
package.loaded['src.render.Assets']={image=function() return nil end}
local named
package.loaded['src.ui.Screens']={push=function(_,key,opts) named={key=key,opts=opts} end}
local dual=false
package.loaded['src.ui.SecondScreen']={combined=function() return dual end,separate=function() return dual end,separateMode=function(m) return m=='display' or m=='inset' or m=='vertical' or m=='horizontal' end,mode=function() return 'off' end,
  toLocal=function(_,x,y) if dual and y>=700 then return 0,0 end end,draw=function(_,fn) fn() end}
package.loaded['src.render.Renderer']={uiPresentation={x=100,y=50,scaleX=2,scaleY=3}}
package.loaded['src.core.Sound']={playCry=function() end}
local keys={};local finished,popped,refreshed=0,0,0
local game={data={gen5_juniper_art=art},save={player={},options={}},
 input={wasPressed=function(_,k) return keys[k] end},stack={pop=function() popped=popped+1 end},
 overworld={player={refreshForm=function() refreshed=refreshed+1 end}}}
local Intro=require('src.ui.Gen5JuniperIntro')
local s=Intro.new(game,function() finished=finished+1 end);s:enter()
local function press(k) keys={[k]=true};s:update(1/60);keys={} end
local function exhaust() while s.page<#s.pages do press('a') end end
check(s.phase=='welcome' and #s.pages==2,'native welcome has two pages')
press('a');check(s.phase=='welcome','A advances page before next message')
press('a');check(s.phase=='professor','professor introduction follows welcome')
exhaust();press('a');check(s.phase=='release','Pokemon release after introduction')
s:update(160/60);check(s.phase=='inhabited','release waits for animation')
for _,phase in ipairs({'pokemon','yourself','gender'}) do exhaust();press('a');check(s.phase==phase,'progress to '..phase) end
press('right');press('a');check(s.gender=='girl' and s.phase=='confirmGender','girl selection')
press('b');check(s.phase=='gender','gender rejection returns to selection')
press('right');press('a');press('a');check(s.phase=='name','accepted gender asks name')
exhaust();press('a')
check(named.key=='NamingScreen' and named.opts.female and named.opts.maxLen==7,'naming receives female and length')
check(named.opts.title=='Your name?' and not named.opts.presets,'native naming prompt opens keyboard directly')
check(game.save.player.gender=='girl' and refreshed==1,'chosen avatar applied')
named.opts.onDone('TEST');check(s.phase=='confirmName' and s.pages[1]:find('TEST',1,true),'name token replaced')
press('b');check(s.phase=='name','rejected name can be edited')
exhaust();press('a');named.opts.onDone('HILDA');press('a')
check(s.phase=='wonderful' and game.save.player.name=='HILDA','confirmed name retained')
for _,phase in ipairs({'friends','cheren','bianca','gift','journey','shrink'}) do
 exhaust();press('a');check(s.phase==phase,'progress to '..phase)
end
s:update(90/60);s:finish();check(finished==1 and popped==1,'finish callback and pop once')
s=Intro.new(game);s:enter();s:say(11,'gender')
check(s:touchpressed(1,500,200),'scaled upper-screen gender touch')
s:update(1/60);check(s.gender=='girl' and s.phase=='confirmGender','touch selects girl in single-screen mode')
dual=true;check(not s:touchpressed(1,500,710),'blank lower screen cannot advance dialogue')
s:say(17,'confirmName');check(not s:touchpressed(1,200,200),'confirmation ignores touches outside choices')
check(s:touchpressed(1,500,440),'touch on No accepted');s:update(1/60)
check(s.phase=='name','touch No reopens naming')
print(('gen5_juniper_check: %d passed'):format(checks))
