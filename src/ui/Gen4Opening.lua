local Model=require('src.render.Gen4Model')
local Anim=require('src.import.Gen4CellAnim')
local Opening={}
local flip={1,0,0,0,0,-1,0,0,0,0,1,0,0,0,0,1}
function Opening.scene(f)
 if f<975 then return 'logo' end
 if f<1600 then return 'landscape' end
 if f<1924 then return 'panorama' end
 if f<2222 then return 'galactic' end
 return 'end'
end
function Opening.actor(intro,id,t,x,y)
 local screens=intro.game.data.gen4_graphics.screens
 local rec=screens[('opening/actor_%d_00'):format(id)]
 local frames=rec and rec.sequences and (rec.sequences[0] or rec.sequences['0'])
 local length=Anim.length(frames)
 local cell=length>0 and Anim.at(frames,t%length) or 0
 local key=('actor_%d_%02d'):format(id,cell or 0)
 local image=intro:openingImage(key)
 local info=screens['opening/'..key]
 if image then love.graphics.draw(image,x+(info.originX or 0),y+(info.originY or 0)) end
end
function Opening.models(intro,f)
 if not intro.openingModels then
  intro.openingModels={}
  local sets=intro.game.data.gen4_models and intro.game.data.gen4_models.sets
  for _,rec in ipairs(sets and sets.opening and sets.opening.models or {}) do
   if rec.name:match('^op_map') then intro.openingModels[#intro.openingModels+1]={name=rec.name,model=Model.new(rec)} end
  end
 end
 if #intro.openingModels==0 then return end
 if not intro.movieColour then intro.movieColour,intro.movieDepth=Model.newTarget(256,192) end
 if not intro.movieColour then return end
 local group=f<1191 and '01' or f<1401 and '02' or '03'
 local target,yaw,fov
 if group=='01' then target={0,80,96-(f-975)*2};yaw=0;fov=math.max(0x5c1,0x981-(f-975)*32)
 elseif group=='02' then target={-64+(f-1191)*4,80,-48};yaw=0;fov=0x5c1
 else target={480-(f-1401)*2,80,-112};yaw=0x680*math.pi*2/65536;fov=0x5c1+math.max(0,f-1560)*24 end
 local pitch=-0x29fe*math.pi*2/65536
 local distance=0x29aec1/4096
 local eye={target[1]+distance*math.cos(pitch)*math.sin(yaw),target[2]-distance*math.sin(pitch),target[3]+distance*math.cos(pitch)*math.cos(yaw)}
 local vp=Model.multiply(flip,Model.multiply(Model.perspective(fov*math.pi*4/65536,256/192,1,4000),Model.lookAt(eye,target)))
 local g=love.graphics;local previous={g.getCanvas()}
 g.setCanvas({intro.movieColour,depthstencil=intro.movieDepth});g.clear(1,1,1,1,true,true)
 for _,rec in ipairs(intro.openingModels) do if rec.name:match('^op_map'..group..'_') then rec.model:draw(vp) end end
 g.setCanvas(previous[1] and previous or nil);g.setColor(1,1,1,1);g.draw(intro.movieColour)
end
function Opening.draw(intro,bottom)
 local g=love.graphics;local f=intro.openingFrame or 0
 local scene=Opening.scene(f)
 g.setColor(0,0,0,1);g.rectangle('fill',0,0,256,192);g.setColor(1,1,1,1)
 local function layer(key,x,y)
  local image=intro:openingImage(key)
  if image then g.draw(image,math.floor(x or 0),math.floor(y or 0)) end
 end
 if scene=='logo' then
  layer(f>=790 and 'white' or 'sky')
 elseif scene=='landscape' then
  if not bottom then Opening.models(intro,f) else
   layer('landscape_back',0,-256);layer('landscape_middle',0,-256);layer('landscape_front',0,-256)
   Opening.actor(intro,4,f-975,((f-975)*2)%288-16,64)
  end
 elseif scene=='panorama' then
  local t=f-1600
  layer('panorama_back',0,f>=1830 and -256 or 0)
  layer('panorama_middle',0,-256-math.floor(t*0x280/4096))
  layer('panorama_front',0,-math.floor(t*0x110/4096))
  Opening.actor(intro,bottom and 0 or 2,t,bottom and 80-t/8 or 176+t/8,112)
 elseif scene=='galactic' then
  local t=f-1924;local sign=bottom and 1 or -1
  layer('galactic_back',sign*math.max(0,152-t/2),bottom and -256 or 0)
  layer('galactic_middle',sign*math.max(0,200-t/2),bottom and -256 or 0)
  layer('galactic_front',sign*math.max(0,128-t/2),bottom and -256 or 0)
  if f>=2135 then layer(bottom and 'final_bottom' or 'final_top',0,bottom and -256 or 0) end
 else layer('end',0,-math.min(256,(f-2222)/4)-(bottom and 192 or 0)) end
 local alpha=0
 for _,flash in ipairs({{785,790,4},{975,993,18},{1576,1594,18},{1600,1618,18},{1920,1924,4},{1924,1988,64},{2216,2222,6},{2222,2240,18}}) do
  if f>=flash[1] and f<flash[2] then
   local progress=(f-flash[1])/flash[3]
   alpha=(flash[1]==785 or flash[1]==1576 or flash[1]==1920 or flash[1]==2216) and progress or 1-progress
  end
 end
 if alpha>0 then g.setColor(1,1,1,alpha);g.rectangle('fill',0,0,256,192) end
 if f>=2412 then g.setColor(0,0,0,math.min(1,(f-2412)/18));g.rectangle('fill',0,0,256,192) end
 g.setColor(1,1,1,1)
end
return Opening
