local root=love.filesystem.getSource()..'/../../'
package.path=root..'?.lua;'..root..'?/init.lua;'..package.path
local function save(canvas,name)
 local file=assert(io.open(root..'tmp/'..name..'.png','wb'))
 file:write(canvas:newImageData():encode('png'):getString());file:close()
end
local function img(pic)return love.graphics.newImage(require('src.import.ImageWriter').fromRGBA8(pic.width,pic.height,pic.rgba))end
function love.load()
 local ok,why=xpcall(function()
  local Nds=require('src.import.NdsRom');local Decoder=require('src.import.Gen5MonAnim')
  local black=assert(Nds.open(root..'Pokemon - Black Version (USA, Europe) (NDSi Enhanced).nds'))
  local arc=assert(require('src.import.NarcArchive').parse(black:read(Decoder.PATH)))
  local g=love.graphics;local sheet=g.newCanvas(768,720)
  g.setCanvas(sheet);g.clear(0.18,0.21,0.27,1);g.setCanvas()
  love.filesystem.createDirectory('diagnostics/bw-animation')
  local data={pokemon={}}
  local comparison=0
  for row,species in ipairs({1,6,25,495,643,649})do
   local path=('diagnostics/bw-animation/%03d.bin'):format(species)
   assert(love.filesystem.write(path,Decoder.pack(arc,species)))
   data.pokemon[species]={gen5Animation={path=path,species=species}}
   for sideIndex,side in ipairs({'front','back'})do
    local mon={species=species,gender='male'}
    local player=assert(require('src.pokemon.Gen5MonAnimPlayer').new(data,species,mon,side))
    player:start()
    for frame,tick in ipairs({0,20,40,80})do
     if tick>0 then player:update((tick-({0,20,40,80})[frame-1])/60)end
     local picture=player:image()
     local state=player.machine.state()
     local indices=Decoder.render(player.set,state,96,96,player.ox,player.oy,{})
     local reference=Decoder.rgba(indices,96,96,player.set.palette)
     local actual=picture:newImageData():getString()
     local different=0
     for i=4,#reference,4 do
      if reference:byte(i)~=actual:byte(i) then different=different+1 end
     end
     assert(different<100,('CPU/GPU raster mismatch species %d %s frame %d: %d'):format(species,side,tick,different))
     comparison=comparison+1
     g.setCanvas(sheet);g.setColor(1,1,1,1)
     local x=(sideIndex-1)*384+(frame-1)*96;local y=(row-1)*120
     g.print(species..' '..side..' '..tick,x+2,y+2);g.draw(picture,x,y+20);g.setCanvas()
    end
   end
  end
  save(sheet,'bw-animated-sprites')
  local variants=g.newCanvas(384,120);g.setCanvas(variants);g.clear(0.18,0.21,0.27,1);g.setCanvas()
  local variantPixels={}
  for i,variant in ipairs({{gender='male'},{gender='female'},{gender='male',shiny=true},{gender='female',shiny=true}})do
    local mon={species=25,gender=variant.gender}
    if variant.shiny then mon.dvs={attack=2,defense=10,speed=10,special=10}end
    assert(require('src.pokemon.Pokemon').isShiny(mon)==(variant.shiny or false))
    local player=assert(require('src.pokemon.Gen5MonAnimPlayer').new(data,25,mon,'front'))
    player:start();player:update(20/60)
    local picture=player:image()
    variantPixels[i]=picture:newImageData():getString()
    g.setCanvas(variants);g.setColor(1,1,1,1);g.print(variant.gender..(variant.shiny and ' shiny' or ''),(i-1)*96,2)
    g.draw(picture,(i-1)*96,20);g.setCanvas()
  end
  assert(variantPixels[1]~=variantPixels[2],'female Pikachu must use its distinct body-part sheet')
  assert(variantPixels[1]~=variantPixels[3],'shiny Pikachu must use its shiny palette')
  save(variants,'bw-animation-variants')
  local UI=require('src.import.Gen5BattleUi');local pictures={}
  local interface=assert(UI.build({rom=black,saveImage=function(_,name,pic)
    pictures[name]=pic;return {path=name,width=pic.width,height=pic.height}
  end}))
  assert(interface.typeMembers.FIRE==195 and interface.typeMembers.WATER==196)
  local white=assert(Nds.open(root..'Pokemon - White Version (USA, Europe) (NDSi Enhanced).nds'))
  local whiteTypes=assert(UI.typeMembers(white))
  for key,member in pairs(interface.typeMembers)do assert(whiteTypes[key]==member)end
  local types=g.newCanvas(720,450);g.setCanvas(types);g.clear(0.18,0.21,0.27,1)
  for id=0,16 do
    local key=require('src.import.Gen5Data').TYPES[id];local picture=assert(pictures['battle5/move_'..key..'_1'])
    local x,y=(id%4)*180,math.floor(id/4)*90
    g.setColor(1,1,1,1);g.print(key,x+4,y+2);g.draw(img(picture),x+4,y+24)
  end
  g.setCanvas();save(types,'bw-move-types')
  local E=require('src.import.Gen4EvolutionArt')
  local hg=assert(Nds.open(root..'Pokemon - HeartGold Version (USA).nds'))
  local art=assert(E.images(hg,E.HGSS));local ink=assert(E.data(hg,E.HGSS))
  local arcBottom=assert(require('src.import.NarcArchive').parse(hg:read('/a/2/3/7')))
  local G=require('src.import.Gen4Graphics')
  local p0=G.palette(arcBottom:get(0));local p15=G.palette(arcBottom:get(15))
  local map=G.tilemap(arcBottom:get(17));local palettes={}
  for _,cell in ipairs(map.cells)do palettes[cell.palette]=(palettes[cell.palette] or 0)+1 end
  print('HGSS bottom pal0 '..table.concat(p0[1],',')..' pal15 '..table.concat(p15[1],','))
  for p,n in pairs(palettes)do print('bottom uses palette '..p..' cells '..n)end
  assert(ink.bank==197 and ink.count==13)
  local evo=g.newCanvas(768,192);g.setCanvas(evo);g.clear(0.2,0.2,0.2,1)
  g.setColor(1,1,1,1);g.draw(img(art.background),0,0);g.draw(img(art.bottom),256,0);g.draw(img(art.moveButtons),512,0);g.setCanvas()
  save(evo,'hgss-evolution-assets')
  local options=assert(require('src.import.Gen4HgssOptionsArt').images(hg))
  local optionSheet=g.newCanvas(768,640);g.setCanvas(optionSheet);g.clear(0.18,0.21,0.27,1)
  g.setColor(1,1,1,1);g.draw(img(options.hgss_top),0,0);g.draw(img(options.hgss_bottom),256,0);g.draw(img(options.hgss_cursor),512,0)
  local names={};for key in pairs(options)do if key:find('hgss_obj',1,true)then names[#names+1]=key end end;table.sort(names)
  for i,key in ipairs(names)do
   local x,y=((i-1)%6)*128,270+math.floor((i-1)/6)*80
   g.setColor(1,1,1,1);g.print(key,x+2,y);g.draw(img(options[key]),x+2,y+20)
  end
  g.setCanvas();save(optionSheet,'hgss-options-resources')
  print('PASS '..comparison..' live animation CPU/GPU comparisons and HGSS ROM evolution art')
 end,debug.traceback)
 if not ok then print(why)end
 love.event.quit(ok and 0 or 1)
end
