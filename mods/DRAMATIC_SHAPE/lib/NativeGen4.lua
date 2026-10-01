local V=...
local Native={}
local Camera=require('src.render.Gen4Camera')
local Voxel=V.require('VoxelState')
local lastLevel,lastChosen,manualCamera
local battleTime=0
local battleCamera,battleEnabled
function Native.battleLive()
 local game=require('src.core.Game')
 local top=game.stack and game.stack:top()
 return battleEnabled and battleEnabled() and Native.supports(game.overworld)
  and top and top.gen4Layout and top:gen4Layout() or false
end
function Native.tick(dt)
 battleTime=battleTime+(dt or 0)
 if battleCamera and Native.battleLive() then
  battleCamera.steerable=true
  V.require('CamControl').tick(dt)
  battleCamera.update(dt)
 end
end
function Native.supports(state)
 local map=state and state.map
 return map and map.def and map.def.generation==4 or false
end
function Native.update(state,level)
 if not Native.supports(state) then Camera.setExternalTilt(nil);return false end
 level=tonumber(level) or 0
 if level~=lastLevel then manualCamera=false
 elseif lastChosen and Camera.chosen~=lastChosen then manualCamera=true end
 lastLevel,lastChosen=level,Camera.chosen
 local choice
 if level==Voxel.FP_LEVEL then choice='first'
 elseif level==Voxel.TP_LEVEL then choice='third'
 elseif level==Voxel.FULL_LEVEL then choice='cartridge'
 elseif level>0 then choice=Voxel.ANGLES_DEG[level+1] end
 if manualCamera then choice=nil end
 Camera.setExternalTilt(choice)
 local ground=state.map.renderer and state.map.renderer.gen4Ground
 if ground and ground.tiltGeneration~=Camera.generation then
  ground:dropBakes();ground:applyCamera()
 end
 return true
end
-- Decline the voxel override so OverworldController draws native terrain,
-- props, characters and field effects together, with its shared depth pass.
function Native.drawWorld(state) return Native.supports(state) end
-- Native battles keep Platinum's healthboxes, menus and animation handlers.
-- The terrain uses a native camera; actors retain Platinum's battle layout.
function Native.installBattles(enabled,controls)
 battleEnabled,battleCamera=enabled,controls
 local Battle=require('src.battle.Gen4Battle')
 local View=require('src.render.Gen4View')
 local Ground=require('src.render.Gen4Ground')
 local fullDraw=Battle.draw
 function Battle.draw(battle)
  local scale=Ground.syncRenderScale(battle.game)
  if not enabled() or not Native.supports(battle.game and battle.game.overworld) or scale<=1 then return fullDraw(battle) end
  local w=Battle.width(battle);local h=select(2,battle:uiSize())
  local canvas=battle.dramaticNativeSurface
  if not canvas or canvas:getWidth()~=w*scale or canvas:getHeight()~=h*scale then
   canvas=love.graphics.newCanvas(w*scale,h*scale);canvas:setFilter('nearest','nearest');battle.dramaticNativeSurface=canvas
  end
  local g=love.graphics;local previous=g.getCanvas()
  g.push('all');g.setCanvas(canvas);g.clear(0,0,0,0);g.origin();g.scale(scale)
  local ok,err=pcall(fullDraw,battle)
  g.pop();g.setCanvas(previous)
  if not ok then error(err,0) end
  g.setColor(1,1,1,1);g.draw(canvas,0,0,0,1/scale,1/scale)
  local renderer=battle.game.renderer
  if renderer then renderer.uiOverride=canvas end
 end
 local field,position=Battle.drawField,Battle.battlerPos
 local actors,trainer=Battle.drawBattlers,Battle.drawTrainerBack
 local function anchor(view,ground,map,x,z,target,w)
  local originX,originZ=x,z
  -- Solve a terrain point beneath the desired screen-space feet. Keep it
  -- for this battle so orbiting moves the actors with the world.
  for i=1,12 do
   local function project(a,b)
    return view:project(a+(ground.offsetX or 0),ground:groundY(a,b),b+(ground.offsetY or 0),w,192)
   end
   local sx,sy=project(x,z)
   if not sx then break end
   local dx,dy=target.x-sx,target.y+32-sy
   if math.abs(dx)+math.abs(dy)<0.1 then break end
   local ax,ay=project(x+1,z);local bx,by=project(x,z+1)
   if not ax or not bx then break end
   ax,ay,bx,by=ax-sx,ay-sy,bx-sx,by-sy
   local det=ax*by-bx*ay
   if math.abs(det)<1e-6 then break end
   x=x+math.max(-64,math.min(64,(dx*by-bx*dy)/det))
   z=z+math.max(-64,math.min(64,(ax*dy-dx*ay)/det))
  end
  if map.isWalkableCell and not map:isWalkableCell(math.floor(x/16),math.floor(z/16)) then
   local best,bestDistance
   local cx,cy=math.floor(x/16),math.floor(z/16)
   for dy=-12,12 do for dx=-12,12 do
    if map:isWalkableCell(cx+dx,cy+dy) then
     local nx,nz=(cx+dx)*16+8,(cy+dy)*16+8
     local distance=(nx-x)^2+(nz-z)^2
     if not bestDistance or distance<bestDistance then best={x=nx,z=nz};bestDistance=distance end
    end
   end end
   if best then return best end
   return {x=originX,z=originZ}
  end
  return {x=x,z=z}
 end
 local function context(battle)
  local game=battle and battle.game
  local state=game and game.overworld
  if not enabled() or not Native.supports(state) then return nil end
  return state,state.map.renderer and state.map.renderer.gen4Ground
 end
 function Battle.drawField(battle)
  battle.dramaticNativePositions=nil
  battle.dramaticNativeActors=false
  local state,ground=context(battle)
  if not ground or ground.noDepth or battle.blankForAskName then return field(battle) end
  Ground.syncRenderScale(battle.game)
  local px=(state.player.cellX or 0)*16+8
  local py=(state.player.cellY or 0)*16+8
  battle.dramaticNativeView=battle.dramaticNativeView or View.new('third')
  local view=battle.dramaticNativeView
  -- Keep this rig separate from the player's saved overworld orbit.
  local look=View.look
  View.look={orbiting=true,yaw=0.25+(controls and controls.orbit or 0)+math.sin(battleTime*0.15)*0.08,
   rise=0.16+(controls and controls.pitch or 0),zoom=1.5*(controls and controls.zoom or 1)}
  view:follow(px+(ground.offsetX or 0),py+(ground.offsetY or 0),0,ground:groundY(px,py))
  View.look=look
  local previous=ground.view3d
  local publish=ground.suppressWorldOverride
  ground.suppressWorldOverride=true
  ground.view3d=view
  local ok,err=pcall(function()
   if not ground:drawFree(Battle.width(battle),192) then return end
   local marks={}
   local depths={}
   local sizes={}
   if battle.dramaticNativeAnchorWidth~=Battle.width(battle) then
    battle.dramaticNativeAnchors={};battle.dramaticNativeAnchorWidth=Battle.width(battle)
   end
   for slot=0,5 do
    -- Native slots include the extra width on the opponent's side. Trainer
    -- backs, send-outs and move effects all read these same positions.
    local target=position(battle,slot)
    if target then
     if slot==1 then target={x=target.x-12,y=target.y+8} end
     local at=battle.dramaticNativeAnchors[slot]
     if not at then at=anchor(view,ground,state.map,px,py,target,Battle.width(battle));battle.dramaticNativeAnchors[slot]=at end
     local x,y,scale,depth=view:project(at.x+(ground.offsetX or 0),ground:groundY(at.x,at.z),at.z+(ground.offsetY or 0),Battle.width(battle),192)
     at.baseScale=at.baseScale or scale
     local playerAnchor=battle.dramaticNativeAnchors[0]
     local reference=playerAnchor and playerAnchor.baseScale or at.baseScale
     sizes[slot]=scale and reference and scale/reference or 1
     marks[slot]=x and {x=x,y=y-32} or target
     depths[slot]=depth and depth-0.00002
    end
   end
   battle.dramaticNativeScales=sizes
   battle.dramaticNativePositions=marks
   local own=rawget(battle,'drawBattlerPic')
   local draw=battle.drawBattlerPic
   battle.drawBattlerPic=function(self,mon,...)
    local args={...};local slot=mon==self.player and 0 or 1
    if not depths[slot] then return end
    return ground:withFreeDepth(depths[slot],function()
     local g=love.graphics;local mark=marks[slot];local k=sizes[slot] or 1
     g.push();g.origin();g.scale(Ground.renderScale());g.translate(mark.x,mark.y+32);g.scale(k,k);g.translate(-mark.x,-mark.y-32)
     local picture=self.battlerPic and self:battlerPic(mon)
     if picture then g.translate(0,32-picture:getHeight()/2-Battle.spriteYOffset(self,mon)) end
     local ok,err=pcall(draw,self,mon,unpack(args));g.pop()
     if not ok then error(err,0) end
    end)
   end
   local okActors,actorError=pcall(actors,battle)
   battle.drawBattlerPic=own
   if not okActors then error(actorError,0) end
   if depths[0] and battle.showPlayerBack and battle.playerBackPic then
    ground:withFreeDepth(depths[0],function()
     local image=battle.picImage and battle:picImage(battle.playerBackPic) or battle.playerBackPic
     if image and image.getDimensions then
      local iw,ih=image:getDimensions();local mark=marks[0]
      local k=64/math.max(iw,ih)*(sizes[0] or 1)
      love.graphics.setColor(1,1,1,1)
      love.graphics.push();love.graphics.origin();love.graphics.scale(Ground.renderScale())
      love.graphics.draw(image,mark.x,mark.y+32,0,k,k,iw/2,ih)
      love.graphics.pop()
     end
    end)
   end
   battle.dramaticNativeActors=true
   ground:endFree()
  end)
  ground:endFree();ground.view3d=previous;ground.suppressWorldOverride=publish
  if not ok then error(err,0) end
  if not battle.dramaticNativePositions then return field(battle) end
 end
 function Battle.battlerPos(battle,slot)
  return battle.dramaticNativePositions and battle.dramaticNativePositions[slot] or position(battle,slot)
 end
 function Battle.drawBattlers(battle)
  if not battle.dramaticNativeActors then return actors(battle) end
 end
 function Battle.drawTrainerBack(battle)
  if not battle.dramaticNativeActors then return trainer(battle) end
 end
end
return Native
