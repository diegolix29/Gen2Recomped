function love.load(args)
 package.path=love.filesystem.getWorkingDirectory()..'/?.lua;'..package.path
 local output=assert(args[1])
 local ok,why=pcall(function()
  local G=require('src.import.Gen4Graphics')
  local D=require('src.import.Gen4Dex')
  local A=require('src.import.Gen4Archives')
  local rom=assert(require('src.import.NdsRom').open('Pokemon - Platinum Version (USA) (Rev 1).nds'))
  local arc=assert(require('src.import.NarcArchive').parse(rom:read(D.PATH)))
  local function member(name)
   local b=assert(arc:get(A.find(D.PATH,name)))
   return G.isCompressed(b) and G.decompress(b) or b
  end
  local map=G.tilemap(member('scroll_main_background.NSCR.lz'))
  local sheet=G.tiles(member('scroll_main_background.NCGR.lz'))
  local palette=G.palette(member('background_scroll_sinnoh.NCLR'))
  local min,pal=99999,{}
  for _,c in ipairs(map.cells) do min=math.min(min,c.tile);pal[c.palette]=true end
  local info=assert(io.open(output..'/dex-map-info.txt','w'))
  info:write('min tile '..min..'; sheet bytes '..#sheet.pixels..'; bpp '..sheet.bpp..'; palettes ')
  for p in pairs(pal) do info:write(p..' ') end
  info:close()
  local image=assert(G.compose(map,sheet,G.paletteAtSlot(palette,5)))
  local pixels=love.image.newImageData(image.width,image.height,'rgba8',image.rgba)
  local f=assert(io.open(output..'/dex-list-background.png','wb'))
  f:write(pixels:encode('png'):getString());f:close();rom:close()
  if args[2] then
   local dataset=args[2]
   local function load(name) return assert(loadfile(dataset..'/data/generated/'..name..'.lua'))() end
   local images={['fresh-dex-list']=love.graphics.newImage(pixels)}
   package.loaded['src.render.Assets']={register=function() end,image=function(path)
    if images[path] then return images[path] end
    local file=assert(io.open(dataset..'/'..path,'rb'));local bytes=file:read('*a');file:close()
    images[path]=love.graphics.newImage(love.filesystem.newFileData(bytes,path));return images[path]
   end}
   package.loaded['src.core.Strings']=function(s) return s end
   package.loaded['src.core.Logger']={warn=function() end}
   require('src.render.Font').load({font=load('font')})
   local art=load('gen4_dex');art.list='fresh-dex-list'
   local again=assert(require('src.import.NdsRom').open('Pokemon - Platinum Version (USA) (Rev 1).nds'))
   art.orders=D.orders(again)
   local partyArc=assert(require('src.import.NarcArchive').parse(again:read('/graphic/pl_plist_gra.narc')))
   local partyArt={}
   local S=require('src.import.Gen4Screens')
   for _,recipe in ipairs(S.ARCHIVES) do
    if recipe.out=='party' then
     for _,job in ipairs(S.plan(recipe.path,recipe)) do
      if job.tilemap then
       local function bytes(id) local b=assert(partyArc:get(id));return G.isCompressed(b) and G.decompress(b) or b end
       local rendered=assert(G.compose(G.tilemap(bytes(job.tilemap)),G.tiles(bytes(job.tiles)),G.palette(bytes(job.palette))))
       local key='party/'..job.name;partyArt[key]=key
       images[key]=love.graphics.newImage(love.image.newImageData(rendered.width,rendered.height,'rgba8',rendered.rgba))
       if job.name=='menu_panels' then
        local panelFile=assert(io.open(output..'/party-panels.png','wb'))
        panelFile:write(love.image.newImageData(rendered.width,rendered.height,'rgba8',rendered.rgba):encode('png'):getString());panelFile:close()
       end
      end
     end
    end
   end
   again:close()
   local game={data={pokemon=load('pokemon'),gen4_dex=art,gen4_graphics=load('gen4_graphics'),
    gen4_menus=load('gen4_menus'),icons=load('gen4_species_sprites').icons},
    save={party={},pokedex={seen={[387]=true,[390]=true,[393]=true},owned={[387]=true}}}}
   for key,value in pairs(partyArt) do game.data.gen4_graphics.screens[key]=value end
   for i,id in ipairs({387,390,393,25,133,155}) do game.save.party[i]={species=id,level=5+i,hp=i*10,stats={hp=60}} end
   local dex=require('src.ui.Gen4Pokedex').new(game)
   local party=require('src.ui.Gen4PartyMenu').new(game)
   local canvas=love.graphics.newCanvas(512,192)
   love.graphics.setCanvas(canvas);love.graphics.clear()
   dex:draw();love.graphics.push();love.graphics.translate(256,0);party:draw();love.graphics.pop()
   love.graphics.setCanvas()
   local result=assert(io.open(output..'/platinum-dex-party.png','wb'))
   result:write(canvas:newImageData():encode('png'):getString());result:close()
  end
 end)
 local f=assert(io.open(output..'/dex-render-result.txt','w'));f:write(ok and 'passed' or tostring(why));f:close()
 love.event.quit(ok and 0 or 1)
end
