-- Render the repaired watch against fresh ROM backgrounds and imported icons.
function love.load(args)
  local root=love.filesystem.getWorkingDirectory()
  package.path=root..'/?.lua;'..package.path
  local dataset,output=assert(args[1]),assert(args[2])
  local ok,why=pcall(function()
    local images={}
    package.loaded['src.render.Assets']={register=function() end,image=function(path)
      if images[path] then return images[path] end
      local f=assert(io.open(dataset..'/'..path,'rb'),path)
      local bytes=f:read('*a'); f:close()
      images[path]=love.graphics.newImage(love.filesystem.newFileData(bytes,path))
      return images[path]
    end}
    package.loaded['src.core.Strings']=function(s) return s end
    package.loaded['src.core.Logger']={warn=function() end}
    local G=require('src.import.Gen4Graphics')
    local S=require('src.import.Gen4Screens')
    local N=require('src.import.NarcArchive')
    local rom=assert(require('src.import.NdsRom').open(root..'/Pokemon - Platinum Version (USA) (Rev 1).nds'))
    local arc=assert(N.parse(rom:read('/graphic/poketch.narc')))
    local function member(id)
      local b=assert(arc:get(id)); return G.isCompressed(b) and assert(G.decompress(b)) or b
    end
    local recipe
    for _,r in ipairs(S.ARCHIVES) do if r.out=='poketch' then recipe=r end end
    local art={}
    local Cells=require('src.import.Gen4Cells')
    local function addImage(key,image)
      local pixels=love.image.newImageData(image.width,image.height,'rgba8',image.rgba)
      images[key]=love.graphics.newImage(pixels); art[key]=key
    end
    for _,job in ipairs(S.plan(recipe.path,recipe)) do
      if job.tilemap then
        local palette=G.palette(member(job.palette))
        if job.paletteSlot then palette=G.paletteAtSlot(palette,job.paletteSlot) end
        local image=assert(G.compose(G.tilemap(member(job.tilemap)),G.tiles(member(job.tiles)),palette,job.firstTile))
        local key='poketch/'..job.name
        addImage(key,image)
      elseif job.cell then
        local bank=assert(Cells.parse(member(job.cell),G))
        local sheet,palette=G.tiles(member(job.tiles)),G.palette(member(job.palette))
        for index,cell in ipairs(bank.cells) do
          local image=Cells.assemble(cell,sheet,palette,bank,G)
          if image then
            local suffix=bank.count>1 and ('_%02d'):format(index-1) or ''
            addImage('poketch/'..job.name..suffix,image)
          end
        end
      end
    end
    local function load(name) return assert(loadfile(dataset..'/data/generated/'..name..'.lua'))() end
    require('src.render.Font').load({font=load('font')})
    local menus=load('gen4_menus')
    local game={data={pokemon=load('pokemon'),icons=load('gen4_species_sprites').icons,
      gen4_menus=menus,gen4_graphics={screens=art},constants={
      gen4PoketchCoin=assert(require('src.import.Gen4PoketchSprites').coin(arc))}},save={party={},poketch={}}}
    game.data.constants.gen4PoketchMapCells=assert(require('src.import.Gen4BerryData').mapCells(arc))
    game.data.constants.gen4PoketchRoutes=assert(require('src.import.Gen4PoketchMap').routes(rom))
    game.save.gen4Roamers={[0]={active=true,route=0}}
    for i,species in ipairs({387,390,393,25,133,155}) do
      game.save.party[i]={species=species,hp=i*10,stats={hp=60},friendship=i*40,level=20+i}
    end
    game.save.daycare={breed={{mon=game.save.party[1]},{mon=game.save.party[2]}}}
    local watch=require('src.ui.Gen4Poketch').new(game)
    local canvas=love.graphics.newCanvas(1280,math.ceil(#watch.apps/5)*192)
    love.graphics.setCanvas(canvas); love.graphics.clear(0.12,0.12,0.12,1)
    local names={}; for _,app in ipairs(watch.apps) do names[#names+1]=app.name end
    for i,name in ipairs(names) do
      local selected
      for index,app in ipairs(watch.apps) do if app.name==name then selected=index end end
      assert(selected,'missing app '..name); watch.index=selected
      love.graphics.push(); love.graphics.translate((i-1)%5*256,math.floor((i-1)/5)*192)
      watch:drawWatch(); love.graphics.pop()
    end
    love.graphics.setCanvas()
    local f=assert(io.open(output..'/poketch-apps.png','wb'))
    f:write(canvas:newImageData():encode('png'):getString()); f:close()
    rom:close()
  end)
  local f=assert(io.open(output..'/poketch-render-result.txt','w'))
  f:write(ok and 'Poketch apps rendered with fresh ROM backgrounds and imported icons' or tostring(why)); f:close()
  love.event.quit(ok and 0 or 1)
end
