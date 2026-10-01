function love.load(args)
 package.path=love.filesystem.getWorkingDirectory()..'/?.lua;'..package.path
 local ok,why=pcall(function()
  local dataset,output=assert(args[1]),assert(args[2])
  local function load(name) return assert(loadfile(dataset..'/data/generated/'..name..'.lua'))() end
  local images={};package.loaded['src.render.Assets']={register=function() end,resolve=function(p) return p end,image=function(path)
   if images[path] then return images[path] end
   local f=assert(io.open(dataset..'/'..path,'rb'));local bytes=f:read('*a');f:close()
   images[path]=love.graphics.newImage(love.filesystem.newFileData(bytes,path));return images[path]
  end}
  package.loaded['src.core.Strings']=function(s) return s end
  package.loaded['src.core.Logger']={warn=function() end,info=function() end}
  package.loaded['src.core.Sound']={play=function() end,playCry=function() end}
  package.loaded['src.core.GameVersion']={isGen4=function() return true end,isGen3=function() return false end,isGen2=function() return false end}
  require('src.render.Font').load({font=load('font')})
  local rom=assert(require('src.import.NdsRom').open('Pokemon - Platinum Version (USA) (Rev 1).nds'))
  local resources=require('src.import.Gen4UIResources').images(rom)
  local data={pokemon=load('pokemon'),items=load('items'),constants=load('constants'),gen4_graphics=load('gen4_graphics'),gen4_dex=load('gen4_dex'),gen4_menus=load('gen4_menus'),icons=load('gen4_species_sprites').icons}
  data.gen4_models={sets={opening={models={}}}}
  local G=require('src.import.Gen4Graphics')
  local B=require('src.import.Gen4Nsbmd')
  local T=require('src.import.Gen4Models')
  local arc=assert(require('src.import.NarcArchive').parse(rom:read('/demo/title/op_demo.narc')))
  local function member(i) local b=arc:get(i);return G.isCompressed(b) and G.decompress(b) or b end
  local textureCount=0
  for _,i in ipairs({100,101,103,104,105,106,107,108,110,111}) do
   local bytes=member(i)
   local textureBytes=member(i<103 and 102 or i<110 and 109 or 112)
   local bank=assert(T.parse(textureBytes))
   for _,model in ipairs(assert(B.parse(bytes)).models) do
    local packed=require('src.import.Gen4ModelPack').pack(model)
    for _,shape in ipairs(packed.shapes) do
     if shape.texture then
      local ti,pi
      for n,t in ipairs(bank.textures) do if t.name==shape.texture then ti=n end end
      for n,p in ipairs(bank.palettes) do if p.name==shape.palette then pi=n end end
      assert(ti,'unbound opening texture '..shape.texture)
      local pic=assert(T.decode(bank,textureBytes,ti,pi or 1))
      local key='opening-model/'..model.name..'/'..shape.texture
      images[key]=love.graphics.newImage(love.image.newImageData(pic.width,pic.height,'rgba8',pic.rgba))
      shape.image=key;textureCount=textureCount+1
     end
    end
    table.insert(data.gen4_models.sets.opening.models,packed)
   end
  end
  assert(textureCount>100,'opening textures not bound')
  local count=0
  local P=require('src.import.Gen4Particle')
  local particleArc=assert(require('src.import.NarcArchive').parse(rom:read(P.ARCHIVE_FIELD)))
  local particleBytes=particleArc:get(4)
  local particles={textures={},emitters=assert(P.emitters(particleBytes))}
  assert(#particles.emitters>=12,'opening particle resources missing')
  for index,texture in ipairs(assert(P.textures(particleBytes))) do
   local pic=assert(P.rgba(texture));local key='opening-particle/'..index
   images[key]=love.graphics.newImage(love.image.newImageData(pic.width,pic.height,'rgba8',pic.rgba))
   particles.textures[index]={path=key,width=pic.width,height=pic.height}
  end
  data.gen4_particles={effects={opening_4=particles}}
  for key,pic in pairs(resources) do
   images[key]=love.graphics.newImage(love.image.newImageData(pic.width,pic.height,'rgba8',pic.rgba));data.gen4_graphics.screens[key]={path=key,originX=pic.originX,originY=pic.originY,sequences=pic.sequences};count=count+1
  end
  assert(count>=546,'missing native supplementary UI resources: '..count)
  for _,key in ipairs({'shop/cursor_00','shop/scroll_00','shop/scroll_01'}) do assert(resources[key],key) end
  local function capture(name,fn)
   local c=love.graphics.newCanvas(256,192);love.graphics.setCanvas(c);love.graphics.clear();love.graphics.origin();fn();love.graphics.setCanvas()
   local f=assert(io.open(output..'/'..name..'.png','wb'));f:write(c:newImageData():encode('png'):getString());f:close()
  end
  for _,key in ipairs({'storage/main','storage/wallpaper_00','evolution/background','dex/footprint_387','opening/first_top','opening/first_bottom','opening/first_overlay'}) do
   capture(key:gsub('/','-'),function() love.graphics.setColor(1,1,1,1);love.graphics.draw(images[key],0,0) end)
  end
  for key in pairs(resources) do
   if key:find('^opening/') then
    capture(key:gsub('/','-'),function() love.graphics.setColor(1,1,1,1);love.graphics.draw(images[key],0,0) end)
   end
  end
  local game={data=data,save={party={{species=387,level=5,hp=20,stats={hp=20}}},inventory={},money=3000,pokedex={seen={[387]=true},owned={[387]=true}}},stack={pop=function() end},input={wasPressed=function() return false end}}
  local intro=require('src.ui.Gen4Intro').new(game)
  for _,frame in ipairs({640,710,740,800,900,945,975,1100,1189,1193,1250,1450,1650,1950,2025,2035,2100,2140,2150,2252,2300,2342,2424}) do
   intro.openingFrame=frame
   capture('montage-top-'..frame,function() require('src.ui.Gen4Opening').draw(intro,false) end)
   if frame==740 then
    assert(#intro.movieParticles.systems==3)
    local alive=0;for _,system in ipairs(intro.movieParticles.systems) do alive=alive+system:total() end
    assert(alive>0,'logo particles must be alive')
   end
   local before=intro.movieParticles.frame
   capture('montage-bottom-'..frame,function() require('src.ui.Gen4Opening').draw(intro,true) end)
   capture('montage-pair-'..frame,function() require('src.ui.Gen4Opening').drawPair(intro) end)
   assert(intro.movieParticles.frame==before,'dual/single rendering must not advance simulation twice')
  end
  local pc=require('src.ui.Gen4BoxMenu').new(game,{mode='move'})
  game.save.boxes[1][1]={species=390,level=8};game.save.boxes[1][30]={species=393,level=8}
  capture('storage-screen',function() pc:draw() end)
  local shop=require('src.ui.Gen4ShopMenu').new(game,{4,17})
  shop:choose();assert(shop:description()==data.items[4].description);capture('shop-screen',function() shop:draw() end)
  shop.stock={4,17,18,19,20,21,22,23};shop:step(6)
  assert(shop.cursor==7 and shop.scroll==0);capture('shop-seventh-row',function() shop:draw() end)
  shop:step(1);assert(shop.scroll==1);capture('shop-scrolled',function() shop:draw() end)
  shop.cursor=1;shop.scroll=0;shop:choose();capture('shop-quantity',function() shop:draw() end)
  local dex=require('src.ui.Gen4Pokedex').new(game);dex.page='entry'
  for i,id in ipairs(dex.entries) do if id==387 then dex.index=i end end
  for i=1,5 do dex.tab=i;capture('dex-page-'..i,function() dex:draw() end) end
  local evolution=require('src.ui.Gen4EvolutionState').new(game,game.save.party[1],388)
  capture('evolution-opening',function() evolution:draw() end)
  evolution.phase='morph';evolution.t=75
  capture('evolution-morph',function() evolution:draw() end)
  rom:close()
  print(count..' ROM UI resources, shop icon/quantity/scroll layouts, seven menu pages and two evolution frames rendered')
 end)
 love.graphics.setCanvas();if not ok then print(why) end
 love.event.quit(ok and 0 or 1)
end
