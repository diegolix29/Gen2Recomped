love=require('tests.love_stub')
local checks=0
local function check(c,msg) assert(c,msg);checks=checks+1 end
local X=require('src.import.RomExtractorGen5')
local Art=require('src.import.Gen5MainMenuArt')
local data
for _,version in ipairs({'black','white'}) do
  local path=version=='black' and 'Pokemon - Black Version (USA, Europe) (NDSi Enhanced).nds'
    or 'Pokemon - White Version (USA, Europe) (NDSi Enhanced).nds'
  local x=assert(X.new(path,version))
  x.saveImage=function(_,path,pic)
    check(#pic.rgba==pic.width*pic.height*4,path..' complete RGBA')
    return {path=path,width=pic.width,height=pic.height}
  end
  local art=Art.build(x)
  check(art.background.width==256 and art.background.height==192,version..' native backdrop')
  check(art.small_idle.width==192 and art.small_idle.height==24,version..' native 24-tile option frame')
  check(art.large_idle.width==208 and art.large_idle.height==112,version..' save summary frame')
  check(art.text[0]=='CONTINUE' and art.text[1]=='NEW GAME',version..' main-menu bank labels')
  check(art.text[9]:find('{CMD ',1,true) and art.text[11]:find('Badges',1,true),version..' summary formats')
  check(math.floor(art.ink.text[1]/8)==29 and math.floor(art.ink.shadow[1]/8)==17,version..' native text palette roles')
  data={gen5_main_menu_art=art,constants={}};x:close()
end
local drawn={}
package.loaded['src.render.Font']={draw=function(t) drawn[#drawn+1]=t end,width=function(s) return #s*6 end,
  pushStyle=function() end,popStyle=function() end}
package.loaded['src.render.Assets']={image=function() return nil end}
package.loaded['src.ui.Theme']={cursor=0}
package.loaded['src.core.GameVersion']={get=function() return 'black' end,isGen4=function() return true end,
  isGen3=function() return false end,isGen2=function() return false end,info=function() return {family='bw'} end}
package.loaded['src.core.Strings']=function(s) return s end
package.loaded['src.core.Sound']={play=function() end}
local sample={player={name='TEST'},pokedex={seen={[1]=true,[2]=true},owned={[1]=true}},party={}}
local haveSave=false
love.filesystem.getInfo=function() return haveSave and {} or nil end
package.loaded['src.core.SaveData']={saveFilename=function() return 'unused' end,load=function() return sample end,
  playSeconds=function() return 2*3600+5*60 end}
package.loaded['src.inventory.Badges']={count=function() return 3 end}
local rect={x=100,y=50,scaleX=2,scaleY=3,w=512,h=576}
package.loaded['src.render.Renderer']={uiPresentation=rect}
local dual=false;local lowerDraws=0
package.loaded['src.ui.SecondScreen']={combined=function() return dual end,separate=function() return dual end,separateMode=function(m) return m=='display' or m=='inset' or m=='vertical' or m=='horizontal' end,mode=function() return 'off' end,
  toLocal=function(_,x,y) if y>=700 then return 0,0 end end,
  draw=function(_,fn) lowerDraws=lowerDraws+1;fn() end}
local pushed={}
package.loaded['src.ui.Screens']={push=function(_,name) pushed[#pushed+1]=name end}
local keys={};local fresh,continued,popped,exited=0,0,0,0
local game={data=data,save=sample,input={wasPressed=function(_,k) return keys[k] end},
  stack={pop=function() popped=popped+1 end},returnToLauncher=function() exited=exited+1 end}
local opts={onNewGame=function() fresh=fresh+1 end,onContinue=function() continued=continued+1 end}
local Menu=require('src.ui.Gen5MainMenu')
local function press(menu,key) keys={[key]=true};menu:update(1/60);keys={} end
local menu=Menu.new(game,opts)
check(#menu.items==3 and menu.items[1].key=='newGame','no Continue without a save')
local boxes=menu:rects()
check(boxes[1].x==32 and boxes[1].y==16 and boxes[2].y==40,'native option positions')
press(menu,'a');check(fresh==1,'New Game callback')
press(menu,'up');check(menu.index==1,'cursor stops at top')
press(menu,'down');press(menu,'a');check(pushed[1]=='OptionsMenu','launcher options remain reachable')
press(menu,'down');press(menu,'down');press(menu,'a');check(exited==1 and menu.index==3,'exit reachable and cursor stops at bottom')
press(menu,'b');check(popped==1,'B returns to title')
menu=Menu.new(game,opts)
check(menu:touchpressed(1,180,110) and fresh==2,'scaled primary-screen tap')
check(not menu:touchpressed(1,120,110),'tap outside frames ignored')
dual=true
check(not menu:touchpressed(1,180,710) and fresh==2,'blank lower-screen taps ignored')
game.secondScreenInjecting=true
check(not menu:touchpressed(1,40,20),'physical lower-display taps ignored')
game.secondScreenInjecting=nil
haveSave=true;menu=Menu.new(game,opts)
check(menu.items[1].key=='continue' and #menu.items==4,'Continue exists with a save')
press(menu,'a');check(continued==1,'Continue callback')
boxes=menu:rects()
check(boxes[1].h==112 and boxes[2].y==128,'expanded save window moves following options')
menu:summary(boxes[1])
check(table.concat(drawn,'|')=='TEST|Time: 2:05|Pokédex: 1|Badges: 3','native summary variables and owned dex count')
for i=1,3 do press(menu,'down') end
check(menu.scrollTarget==8,'off-screen exit scrolls into view')
for i=1,60 do menu:update(1/60) end
check(menu.scrollPos==8,'scroll settles exactly')
check(menu:touchpressed(1,180,50+185*3) and exited==2,'tap selects scrolled row')
menu:draw();check(lowerDraws==1,'dual layout explicitly paints blank lower screen')
print(checks..' main-menu checks passed')
