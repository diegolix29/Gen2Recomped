local root=love.filesystem.getSource()..'/../../'
package.path=root..'?.lua;'..root..'?/init.lua;'..package.path
local function img(pic) return love.graphics.newImage(require('src.import.ImageWriter').fromRGBA8(pic.width,pic.height,pic.rgba)) end
local function save(canvas,name)
 local f=assert(io.open(root..'tmp/'..name..'.png','wb'));f:write(canvas:newImageData():encode('png'):getString());f:close()
end
function love.load()
 local ok,why=xpcall(function()
  local rom=assert(require('src.import.NdsRom').open(root..'Pokemon - HeartGold Version (USA).nds'))
  local art=require('src.import.Gen4HgssPokegearArt').images(rom)
  local g=love.graphics;local canvas=g.newCanvas(1024,424)
  g.setCanvas(canvas);g.clear(.2,.2,.2,1)
  for i,page in ipairs({'map','phone','radio','config'}) do
   for j,side in ipairs({'top','bottom'}) do
    local x,y=(i-1)*256,(j-1)*212+20
    g.setColor(1,1,1,1);g.rectangle('fill',x,y,256,192)
    g.draw(img(art['frame_'..side..'_0']),x,y)
    if page=='map' and side=='top' then g.draw(img(art.map_world_0),x,y) end
    local pic=art[page..'_'..side..'_0'];if pic then g.draw(img(pic),x,y) end
    g.print(page..' '..side,x+4,y-18)
   end
  end
  g.setCanvas();save(canvas,'hgss-pokegear-panels')
  local G=require('src.import.Gen4Graphics');local T=require('src.import.Gen4Trgra')
  local a=require('src.import.NarcArchive').parse(rom:read('/a/0/0/6'))
  local backs=g.newCanvas(640,110);g.setCanvas(backs);g.clear(.3,.3,.3,1)
  for i=0,7 do
   local sheet=T.sheet(a,G,i,true);local pic=assert(T.frame(sheet,T.palette(a,G,i),1))
   g.draw(img(pic),i*80,20);g.print(tostring(i),i*80,2)
  end
  g.setCanvas();save(backs,'hgss-trainer-backs')
  local oak,seq=require('src.import.Gen4HgssOakArt').images(rom)
  local board=g.newCanvas(1024,384);g.setCanvas(board);g.clear(1,1,1,1)
  for i,key in ipairs({'oak','boy_1','girl_1','gender'}) do
    local x=(i-1)*256;g.draw(img(oak.background_0),x,0);g.draw(img(oak[key]),x,0)
    local pic=oak[(i<3 and 'boy' or 'girl')..'_shrink_'..((i-1)%4+1)]
    g.draw(img(oak.background_0),x,192);g.draw(img(pic),x,192)
  end
  g.setCanvas();save(board,'hgss-oak-art')
  local bg=g.newCanvas(1024,384);g.setCanvas(bg);g.clear(.5,.5,.5,1)
  for i,key in ipairs({'background_0','background_1','background_2','background_3','background_4','background_5','bottom','gender'}) do g.draw(img(oak[key]),(i-1)%4*256,math.floor((i-1)/4)*192) end
  g.setCanvas();save(bg,'hgss-oak-backgrounds')
  local arc=require('src.import.NarcArchive').parse(rom:read('/a/1/2/0'))
  local cells={};for i=0,127 do cells[#cells+1]={tile=i,palette=0} end
  local pic=G.compose({width=128,height=64,cells=cells},G.tiles(arc:get(0)),G.palette(arc:get(1)))
  local atlas=g.newCanvas(128,64);g.setCanvas(atlas);g.clear(.5,.5,.5,1);g.draw(img(pic));g.setCanvas();save(atlas,'hgss-oak-atlas')
  rom:close();print('HGSS Pokegear, trainer back and Oak screenshots saved')
 end,debug.traceback)
 love.graphics.setCanvas()
 if not ok then print(why) end
 love.event.quit(ok and 0 or 1)
end
