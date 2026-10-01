function love.load(args)
 package.path=love.filesystem.getWorkingDirectory()..'/?.lua;'..package.path
 local ok,err=pcall(function()
  local dataset,output=args[1],args[2]
  local cache={}
  package.loaded['src.render.Assets']={register=function() end,image=function(path)
   if not cache[path] then
    local f=assert(io.open(dataset..'/'..path,'rb'),path);local b=f:read('*a');f:close()
    cache[path]=love.graphics.newImage(love.filesystem.newFileData(b,path))
   end
   return cache[path]
  end}
  package.loaded['src.core.Strings']=function(s) return s end
  local function load(n) return assert(loadfile(dataset..'/data/generated/'..n..'.lua'))() end
  local data={gen4_models=load('gen4_models'),gen4_menus=load('gen4_menus'),gen4_naming=load('gen4_naming')}
  local rom=assert(require('src.import.NdsRom').open('Pokemon - Platinum Version (USA) (Rev 1).nds'))
  local arc=assert(require('src.import.NarcArchive').parse(rom:read('/demo/title/titledemo.narc')))
  local G=require('src.import.Gen4Graphics');local bytes=arc:get(1)
  if G.isCompressed(bytes) then bytes=G.decompress(bytes) end
  local native=assert(require('src.import.Gen4Nsbmd').parse(bytes)).models[1]
  local packed=require('src.import.Gen4ModelPack').pack(native)
  local animBytes=arc:get(2);if G.isCompressed(animBytes) then animBytes=G.decompress(animBytes) end
  local A=require('src.import.Gen4Anim');local anim=assert(A.parse(animBytes)).animations[1]
  local freshTracks=A.jointMatrices(animBytes,anim)
  data.gen4_graphics={screens={}}
  for key,pic in pairs(require('src.import.Gen4UIResources').images(rom)) do
    if key:find('^opening/') then
      cache[key]=love.graphics.newImage(love.image.newImageData(pic.width,pic.height,'rgba8',pic.rgba))
      data.gen4_graphics.screens[key]={path=key}
    end
  end
  local function update(v)
    if type(v)~='table' then return end
    if v.name=='title_gira' and v.shapes then
      v.nodes=packed.nodes;v.ops=packed.ops
      for i,shape in ipairs(v.shapes) do shape.matrixSlots=packed.shapes[i].matrixSlots end
    end
    if v.name=='title_gira' and v.tracks then
      for i,track in ipairs(v.tracks) do track.matrices=A.packTrack(freshTracks[i].track) end
    end
    for _,child in pairs(v) do if type(child)=='table' then update(child) end end
  end
  update(data.gen4_models);rom:close()
  require('src.render.Font').load({font=load('font')})
  local mode='off';local bottom
  package.loaded['src.ui.SecondScreen']={mode=function() return mode end,draw=function(_,fn)
   bottom=love.graphics.newCanvas(256,192);local prev=love.graphics.getCanvas();love.graphics.setCanvas(bottom);fn();love.graphics.setCanvas(prev)
  end}
  local game={data=data,stack={pop=function() end},input={wasPressed=function() return false end}}
  local Title=require('src.ui.Gen4Title');Title.showIntro=false
  local title=Title.new(game)
  title:update(1/60);assert(title.frame==0);title:update(1/60);assert(title.frame==1,'native 30 Hz title clock')
  local function capture(name,fn)
   local w,h=title:uiSize();if name=='title-bottom' or name=='boot-copyright' or name=='name-choices' or name:find('^opening%-studio') then w,h=256,192 end
   local c=love.graphics.newCanvas(w,h);love.graphics.setCanvas(c);love.graphics.origin();fn();love.graphics.setCanvas()
   local f=assert(io.open(output..'/'..name..'.png','wb'));f:write(c:newImageData():encode('png'):getString());f:close()
  end
  local zone=title:sgbPalettes()[1]
  assert(zone.w==512 and zone.h==384,'single-screen title colour region clips the image')
  title.frame=64;capture('title-single',function() title:draw() end)
  title.frame=100;capture('title-single-pulse',function() title:draw() end)
  mode='display';capture('title-top',function() title:draw() end)
  capture('title-bottom',function() love.graphics.setColor(1,1,1,1);love.graphics.draw(bottom) end)
  mode='off';Title.showIntro=true;local opening=Title.new(game)
  opening.frame=90;capture('title-portal',function() opening:draw() end)
  opening.frame=130;capture('title-face',function() opening:draw() end)
  local intro=require('src.ui.Gen4Intro').new(game)
  intro.frame=60;capture('boot-copyright',function() intro:draw() end)
  intro.frame=520;intro.openingFrame=400
  capture('opening-studio-single',function() intro:draw() end)
  mode='display';capture('opening-studio-top',function() intro:draw() end)
  capture('opening-studio-bottom',function() love.graphics.setColor(1,1,1,1);love.graphics.draw(bottom) end)
  mode='off'
  local clock=require('src.ui.Gen4Intro').new(game);clock.frame=120
  clock:update(1/60);assert(clock.openingFrame==0)
  clock:update(1/60);assert(clock.openingFrame==1)
  game.logicSpeed=function() return 2 end
  title.frame=0;title.frameRemainder=0
  for i=1,4 do title:update(1/60) end
  assert(title.frame==1,'title clock must resist accelerated gameplay')
  game.logicSpeed=nil
  local Naming=require('src.ui.Gen4NamingScreen')
  local done;local n=Naming.new(game,{presets={'Barry','Damion','Tyson'},onDone=function(v) done=v end})
  capture('name-choices',function() n:draw() end)
  game.input.wasPressed=function(_,k) return k=='down' end;n:update();assert(n.choice==2)
  game.input.wasPressed=function(_,k) return k=='a' end;n:update();assert(done=='Barry')
  local custom=Naming.new(game,{presets={'Lucas'}});custom:update();assert(not custom.choice and custom:typed()=='')
  local R=require('src.render.Renderer')
  R.uiPresentation={x=10,y=20,w=512,h=384,scaleX=2,scaleY=2}
  local tapped=Naming.new(game,{presets={'Barry'},onDone=function(v) done=v end})
  done=nil;tapped:touchpressed('mouse',10+50*2,20+72*2);assert(done=='Barry')
  local typed=Naming.new(game,{presets={'Lucas'}})
  typed:touchpressed('finger',10+50*2,20+50*2);assert(not typed.choice)
  typed:touchpressed('mouse',10+30*2,20+90*2);assert(#typed:typed()>0)
  assert(title.giraMaterials[1]);local m=require('src.render.Gen4TexAnim')
  assert(m.materials(title.giraMaterials,64).lambert2.uv[6]~=m.materials(title.giraMaterials,100).lambert2.uv[6])
  for _,p in ipairs({'src/render/Renderer.lua','src/ui/Gen4RowanIntro.lua'}) do assert(loadfile(p)) end
 end)
 if not ok then print(err) else print('Title panels, ROM pulse animation, name choices, and syntax passed') end
 love.event.quit(ok and 0 or 1)
end
