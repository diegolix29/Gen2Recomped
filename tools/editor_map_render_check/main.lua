function love.load(args)
 package.path=love.filesystem.getWorkingDirectory()..'/?.lua;tools/save-editor/?.lua;'..package.path
 local dataset,cache='',{}
 local function read(path) local f=assert(io.open(dataset..'/'..path,'rb'),path);local b=f:read('*a');f:close();return b end
 package.loaded['src.render.Assets']={register=function() end,resolve=function(p) return p end,
  image=function(p) if not cache[p] then cache[p]=love.graphics.newImage(love.filesystem.newFileData(read(p),p)) end;return cache[p] end,
  imageData=function(p) return love.image.newImageData(love.filesystem.newFileData(read(p),p)) end}
 love.filesystem.newFile=function(path)
  local f=assert(io.open(dataset..'/'..path,'rb'));return {seek=function(_,n) return f:seek('set',n) end,read=function(_,n) return f:read(n) end,close=function() f:close() end}
 end
 local ok,why=pcall(function()
  local Loader=require('src.world.MapLoader')
  local Renderer=require('src.render.TileRenderer')
  for _,version in ipairs({'emerald','firered','platinum'}) do
   dataset='G:/Gen2Recomped/'..version;cache={}
   require('src.core.GameVersion').set(version);Loader.invalidateAll();Renderer.releaseGen3Sheets()
   local data={}
   for _,name in ipairs({'maps','tilesets','constants','map_tilesets','map_layouts','gen4_terrain','gen4_models','gen4_camera','gen4_area_lights'}) do
    local chunk=loadfile(dataset..'/data/generated/'..name..'.lua');if chunk then data[name]=chunk() end
   end
   local id=version=='platinum' and 'T01' or 'MAP_G00_N00'
   local map=Loader.load(data,id)
   local state={data=data,version=version,mapId=id,mapEdits={games={}}}
   if version~='platinum' then
    local Tiles=require('tools.map-editor.panels.Tiles')
    assert(Tiles.atlasFor(state,map.tileset,map.tileset.id),'native Gen3 palette failed')
    assert(Tiles.paintCell(state,1,1,1))
    assert(require('src.world.Map').blockArray(map.def)[map.def.width+2]==1)
    map=Loader.load(data,id)
   end
   local target=love.graphics.newCanvas(600,400)
   love.graphics.setCanvas(target);love.graphics.clear();love.graphics.setScissor(180,120,320,240)
   love.graphics.push();love.graphics.translate(180,120);love.graphics.scale(1.25)
   require('tools.map-editor.MapView').draw(state,map,'test',0,0,256,192)
   love.graphics.pop();love.graphics.setScissor();love.graphics.setCanvas()
   local pic=state._editorViews.test:newImageData();local colours={};local visible=0
   for y=0,191,4 do for x=0,255,4 do
    local r,g,b,a=pic:getPixel(x,y);if a>.1 and r+g+b>.1 then visible=visible+1;colours[math.floor(r*255)..','..math.floor(g*255)..','..math.floor(b*255)]=true end
   end end
   local count=0;for _ in pairs(colours) do count=count+1 end
   assert(visible>100 and count>15,version..' map preview is blank')
   local f=assert(io.open(args[1]..'/editor-'..version..'.png','wb'));f:write(target:newImageData():encode('png'):getString());f:close()
   if version=='platinum' then
    assert(require('Catalog').mapLabel(data,id)=='Twinleaf Town')
    local voxel=assert(loadfile('mods/DRAMATIC_SHAPE/lib/VoxelState.lua'))()
    local native=assert(loadfile('mods/DRAMATIC_SHAPE/lib/NativeGen4.lua'))({require=function() return voxel end})
    local ground=map.renderer.gen4Ground
    for _,level in ipairs({1,3,6,7}) do
     native.update({map=map},level);ground:applyCamera()
     ground:placeCamera(240,240,0)
     love.graphics.setCanvas(target);love.graphics.clear();love.graphics.origin()
     require('tools.map-editor.MapView').draw(state,map,'native',0,0,256,192)
     love.graphics.setCanvas()
     local image=state._editorViews.native:newImageData();local lit=0
     for yy=0,191,4 do for xx=0,255,4 do local r,g,b,a=image:getPixel(xx,yy);if a>.1 and r+g+b>.1 then lit=lit+1 end end end
     assert(lit>100,'native mod camera '..level..' has no world')
     local f=assert(io.open(args[1]..'/dramatic-platinum-'..level..'.png','wb'));f:write(image:encode('png'):getString());f:close()
    end
    native.update({map=map},0)
    local controls={orbit=0,pitch=0,zoom=1}
    local Battle=require('src.battle.Gen4Battle')
    Battle.draw=function(self)
     Battle.drawField(self)
     love.graphics.setColor(1,0,1,1)
     love.graphics.rectangle('fill',200,180,1/require('src.render.Gen4Ground').renderScale(),1)
    end
    native.installBattles(function() return true end,controls)
    local battle={game={overworld={map=map,player={cellX=14,cellY=14}}}}
    local pic=love.graphics.newImage(love.image.newImageData(8,8))
    battle.showPlayerBack=false;battle.playerBackPic=pic
    local actorCalls=0
    local graphicsDraw=love.graphics.draw
    local trainerCalls=0
    love.graphics.draw=function(image,x,y,...)
     if image==pic then
      trainerCalls=trainerCalls+1
      local mark=battle.dramaticNativePositions[0]
      local tx,ty=love.graphics.transformPoint(x,y)
      local scale=require('src.render.Gen4Ground').renderScale()
      assert(math.abs(tx-mark.x*scale)<.01 and math.abs(ty-(mark.y+32)*scale)<.01,'trainer feet do not match terrain resolution')
     end
     return graphicsDraw(image,x,y,...)
    end
    battle.player={mon={species=387}};battle.enemy={mon={species=390}}
    battle.battlerPic=function() return pic end
    battle.drawBattlerPic=function(self,mon)
     actorCalls=actorCalls+1
     local mode,write=love.graphics.getDepthMode()
     assert(mode=='lequal' and write,'native battle actor was drawn outside the depth pass')
     local mark=self.dramaticNativePositions[mon==self.player and 0 or 1]
     local x,y=love.graphics.transformPoint(mark.x,mark.y+pic:getHeight()/2+Battle.spriteYOffset(self,mon))
     local scale=require('src.render.Gen4Ground').renderScale()
     assert(math.abs(x-mark.x*scale)<.01 and math.abs(y-(mark.y+32)*scale)<.01,'actor feet do not match the terrain resolution')
    end
    local prior=ground.view3d
    love.graphics.setCanvas(target);love.graphics.origin();love.graphics.clear()
    Battle.drawField(battle)
    assert(actorCalls==2,'native depth pass must draw both Pokemon')
    Battle.drawBattlers(battle);assert(actorCalls==2,'UI pass duplicated native Pokemon')
    love.graphics.setCanvas()
    assert(battle.dramaticNativePositions and battle.dramaticNativePositions[0] and battle.dramaticNativePositions[1],'native battle projection missing')
    assert(ground.view3d==prior,'battle changed overworld camera')
    local f=assert(io.open(args[1]..'/dramatic-platinum-battle.png','wb'));f:write(target:newImageData():encode('png'):getString());f:close()
    assert(Battle.battlerPos(battle,0)==battle.dramaticNativePositions[0])
    local p,e=Battle.battlerPos(battle,0),Battle.battlerPos(battle,1)
    assert(p.x<128 and e.x>128 and p.y>e.y,'Platinum battle actors must occupy opposite corners')
    assert(math.abs(p.x-Battle.BATTLER_POS[0].x)<1 and math.abs(p.y-Battle.BATTLER_POS[0].y)<1)
    battle.gen4SurfaceWidth=function() return 384 end
    love.graphics.setCanvas(target);Battle.drawField(battle);love.graphics.setCanvas()
    for _,slot in ipairs({0,1}) do
     local at=battle.dramaticNativeAnchors[slot]
     assert(map:isWalkableCell(math.floor(at.x/16),math.floor(at.z/16)),'battle actor anchor is not walkable')
    end
    local initialScale=battle.dramaticNativeScales[0]
    controls.zoom=1.5
    love.graphics.setCanvas(target);Battle.drawField(battle);love.graphics.setCanvas()
    assert(battle.dramaticNativeScales[0]<initialScale,'zooming out must shrink the trainer and player Pokemon')
    controls.zoom=1
    battle.showPlayerBack=true
    for resolution=1,4 do
     battle.game.save={options={gen4RenderScale=resolution}}
     love.graphics.setCanvas(target);Battle.drawField(battle);love.graphics.setCanvas()
     assert(ground.freeW==384*resolution and ground.freeH==192*resolution,'battle ignored resolution option')
    end
    assert(trainerCalls>=4,'trainer was not rendered at all resolutions')
    love.graphics.draw=graphicsDraw
    battle.uiSize=function() return 384,192 end
    battle.game.renderer={}
    battle.game.save.options.gen4RenderScale=3
    love.graphics.setCanvas(target);Battle.draw(battle);love.graphics.setCanvas()
    local surface=battle.game.renderer.uiOverride
    assert(surface and surface:getWidth()==1152 and surface:getHeight()==576,'full battle surface lost the selected resolution')
    local detail=surface:newImageData()
    local r,g,b=detail:getPixel(600,540)
    local nr,ng,nb=detail:getPixel(602,540)
    assert(r>.9 and b>.9 and g<.1 and not (nr>.9 and nb>.9 and ng<.1),'single high-resolution detail was discarded')
    battle.game.save.options.gen4RenderScale=1
    local beforeX=battle.dramaticNativeView.x
    controls.orbit=.3
    love.graphics.setCanvas(target);Battle.drawField(battle);love.graphics.setCanvas()
    assert(math.abs(battle.dramaticNativeView.x-beforeX)>1,'battle orbit input did not move the native camera')
    local Ground=require('src.render.Gen4Ground')
    local colour,depth=require('src.render.Gen4Model').newTarget(16,16)
    love.graphics.setCanvas({colour,depthstencil=depth});love.graphics.origin();love.graphics.clear(0,0,0,0,true,true)
    Ground.freeOpen=true
    ground:withFreeDepth(-.5,function() love.graphics.setColor(0,1,0,1);love.graphics.rectangle('fill',0,0,16,16) end)
    ground:withFreeDepth(0,function() love.graphics.setColor(1,0,0,1);love.graphics.rectangle('fill',0,0,16,16) end)
    Ground.freeOpen=false;love.graphics.setCanvas();love.graphics.setColor(1,1,1,1)
    local red,green=colour:newImageData():getPixel(8,8)
    assert(green>.9 and red<.1,'foreground depth must obscure a battle billboard')
    print('Dramatic Shapes: native battle terrain, Platinum actor slots, wide layout and camera restoration passed')
    print('Dramatic Shapes: native Platinum field, tilted, first- and third-person render checks passed')
   end
   print(version..' clipped/zoomed editor map and native assets passed: '..count..' colours')
  end
 end)
 love.graphics.setCanvas();if not ok then print(why) end;love.event.quit(ok and 0 or 1)
end

