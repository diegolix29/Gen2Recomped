local Model=require('src.render.Gen4Model')
local Anim=require('src.import.Gen4CellAnim')
local Opening={}
local Particles=require('src.battle.Gen4ParticleSystem')
local Assets=require('src.render.Assets')
local flip={1,0,0,0,0,-1,0,0,0,0,1,0,0,0,0,1}
function Opening.scene(f)
 if f<975 then return 'logo' end
 if f<1600 then return 'landscape' end
 if f<1924 then return 'panorama' end
 if f<2222 then return 'galactic' end
 return 'end'
end
function Opening.update(intro,frame)
 local effects=intro.game.data.gen4_particles and intro.game.data.gen4_particles.effects
 local resource=effects and effects.opening_4
 if not resource then return end
 local state=intro.movieParticles
 if not state or frame<state.frame then
  local time=os.date('*t')
  local first=time.sec%3
  local direction=(time.hour*time.min+time.sec)%2==1 and 1 or -1
  state={frame=699,systems={},art=resource.textures,order={first,(first+direction)%3},stage=0};intro.movieParticles=state
 end
 for tick=state.frame+1,frame do
  if tick==700 then
   for _,id in ipairs({9,10,11}) do
    local system=Particles.resource(resource.emitters,id)
    if system then state.systems[#state.systems+1]=system:start(77+id) end
   end
  end
  if tick==945 then state.systems={} end
  if (state.stage==0 and tick>=2018) or (state.stage==1 and state.attackDone and tick>=2130) then
   state.stage=state.stage+1;state.attackDone=false;state.phase='approach';state.age=0
   state.kind=state.order[state.stage];state.x=({92,224,80})[state.kind+1];state.y=192;state.scale=4
  end
  local active=false
  for _,system in ipairs(state.systems) do active=system:update() or active end
  if state.phase=='approach' then
   state.x=state.x+({6,-16,8})[state.kind+1];state.y=state.y-16
   state.scale=math.max(1,state.scale-.5);state.age=state.age+1
   if state.age==6 then
    state.phase='burst';state.age=0;state.systems={}
    local firstId=({6,3,0})[state.kind+1]
    for id=firstId,firstId+2 do
     local system=Particles.resource(resource.emitters,id)
     if system then
      system:start(77+id);system.emitterX=state.x-128;system.emitterY=state.y-96
      state.systems[#state.systems+1]=system
     end
    end
   end
  elseif state.phase=='burst' then
   state.age=state.age+1
   if state.age>1 and not active then state.phase='depart';state.age=0 end
  elseif state.phase=='depart' then
   state.x=state.x+({-3,-6,6})[state.kind+1];state.y=state.y-({18,16,20})[state.kind+1]
   state.age=state.age+1
   if state.age==6 then state.phase='wait';state.age=0 end
  elseif state.phase=='wait' then
   state.age=state.age+1
   if state.age>=20 then state.phase=nil;state.attackDone=true;state.systems={} end
  end
 end
 state.frame=frame
end
function Opening.drawAttack(intro,bottom)
 local state=intro.movieParticles
 if not state or state.stage==0 or (state.stage==2)~=bottom or state.attackDone then return end
 local g=love.graphics
 g.setColor(0,0,0,1);g.rectangle('fill',0,0,256,192);g.setColor(1,1,1,1)
 if state.phase~='wait' then
  local id=({389,392,395})[state.kind+1]
  local path=require('src.pokemon.Sprites').path(intro.game.data,id,'front',{kind='opening'})
  if path then
   intro.movieMonImages=intro.movieMonImages or {}
   local image=intro.movieMonImages[path]
   if not image then image=Assets.image(path);intro.movieMonImages[path]=image end
   local w,h=image:getDimensions()
   -- Native front sheets contain two adjacent 80px frames.
   local quad=g.newQuad(0,0,math.min(80,w),math.min(80,h),w,h)
   g.draw(image,quad,state.x,state.y,0,state.scale,state.scale,math.min(80,w)/2,math.min(80,h)/2)
  end
 end
 Opening.drawParticles(intro)
end
function Opening.drawParticles(intro)
 local state=intro.movieParticles
 if not state then return end
 local g=love.graphics
 intro.movieParticleImages=intro.movieParticleImages or {}
 for _,system in ipairs(state.systems) do
  system:draw(128,96,function(texture,x,y,sx,sy,alpha,rotation,colour)
   local rec=state.art and state.art[texture+1]
   if not rec or not rec.path then return end
   local image=intro.movieParticleImages[rec.path]
   if not image then image=Assets.image(rec.path);intro.movieParticleImages[rec.path]=image end
   local w,h=image:getDimensions()
   local c=colour or {255,255,255}
   g.setColor(c[1]/255,c[2]/255,c[3]/255,alpha)
   g.draw(image,x,y,rotation,sx*32/w,sy*32/h,w/2,h/2)
  end)
 end
 g.setColor(1,1,1,1)
end
function Opening.actor(intro,id,t,x,y)
 local screens=intro.game.data.gen4_graphics.screens
 local rec=screens[('opening/actor_%d_00'):format(id)]
 local frames=rec and rec.sequences and (rec.sequences[0] or rec.sequences['0'])
 local length=Anim.length(frames)
 local cell,index=0,nil
 if length>0 then cell,index=Anim.at(frames,t%length) end
 local frame=index and frames[index]
 local key=('actor_%d_%02d'):format(id,cell or 0)
 local image=intro:openingImage(key)
 local info=screens['opening/'..key]
 if image then love.graphics.draw(image,x+(info.originX or 0)+(frame and frame.x or 0),y+(info.originY or 0)+(frame and frame.y or 0)) end
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
 Opening.update(intro,f)
 local scene=Opening.scene(f)
 g.setColor(0,0,0,1);g.rectangle('fill',0,0,256,192);g.setColor(1,1,1,1)
 local function layer(key,x,y,wrap)
  local image=intro:openingImage(key)
  if not image then return end
  x,y=math.floor(x or 0),math.floor(y or 0)
  if wrap then
   local w,h=image:getDimensions()
   x,y=x%w,y%h
   for dx=x-w,256,w do for dy=y-h,192,h do g.draw(image,dx,dy) end end
  else g.draw(image,x,y) end
 end
 if scene=='logo' then
  if f>=640 then layer(f>=790 and 'white' or 'sky') end
  if not bottom then Opening.drawParticles(intro) end
 elseif scene=='landscape' then
  if not bottom then Opening.models(intro,f) else
   layer('landscape_back',0,-256);layer('landscape_middle',0,-256);layer('landscape_front',0,-256)
   Opening.actor(intro,4,f-975,((f-975)*2)%288-16,64)
  end
 elseif scene=='panorama' then
  local t=f-1600
  layer('panorama_back',0,f>=1830 and -256 or 0,true)
  layer('panorama_middle',0,-256+math.floor(t*0x280/4096),true)
  layer('panorama_front',-256,math.floor(t*0x110/4096),true)
  Opening.actor(intro,bottom and 0 or 2,t,bottom and 80-t/8 or 176+t/8,112)
 elseif scene=='galactic' then
  local t=f-1924;local sign=bottom and 1 or -1
  layer('galactic_back',sign*math.max(0,152-t/2),bottom and -256 or 0)
  layer('galactic_middle',sign*math.max(0,200-t/2),bottom and -256 or 0)
  layer('galactic_front',sign*math.max(0,128-t/2),bottom and -256 or 0)
  if f>=2135 then layer(bottom and 'final_bottom' or 'final_top',0,bottom and -256 or 0) end
  Opening.drawAttack(intro,bottom)
 elseif not bottom and f>=2252 then
  layer('end',0,24-math.floor((f-2222)/4))
 end
 local alpha=0
 for _,flash in ipairs({{785,790,4},{975,993,18},{1576,1594,18},{1600,1618,18},{1920,1924,4},{1924,1988,64},{2216,2222,6},{2222,2252,30}}) do
  if f>=flash[1] and f<flash[2] then
   local progress=(f-flash[1])/flash[3]
   alpha=(flash[1]==785 or flash[1]==1576 or flash[1]==1920 or flash[1]==2216) and progress or 1-progress
  end
 end
 if alpha>0 then g.setColor(1,1,1,alpha);g.rectangle('fill',0,0,256,192) end
 local black=0
 if scene=='logo' and f>=640 and f<648 then black=1-(f-640)/8 end
 if not bottom then
  if f>=1185 and f<1191 then black=math.min(1,(f-1185)/4)
  elseif f>=1191 and f<1198 then black=math.max(0,1-(f-1194)/4)
  elseif f>=1395 and f<1401 then black=math.min(1,(f-1395)/4)
  elseif f>=1401 and f<1405 then black=1-(f-1401)/4 end
  if scene=='end' and f>=2252 and f<2342 then black=1-(f-2252)/90 end
 end
 if black>0 then g.setColor(0,0,0,black);g.rectangle('fill',0,0,256,192) end
 if f>=2420 then g.setColor(0,0,0,math.min(1,(f-2420)/8));g.rectangle('fill',0,0,256,192) end
 g.setColor(1,1,1,1)
end
function Opening.drawPair(intro)
 local g=love.graphics
 intro.moviePanels=intro.moviePanels or {g.newCanvas(256,192),g.newCanvas(256,192)}
 local previous={g.getCanvas()}
 for index,canvas in ipairs(intro.moviePanels) do
  g.setCanvas(canvas);g.clear();Opening.draw(intro,index==2)
 end
 g.setCanvas(previous[1] and previous or nil)
 g.setColor(0,0,0,1);g.rectangle('fill',0,0,256,192);g.setColor(1,1,1,1)
 for index,canvas in ipairs(intro.moviePanels) do g.draw(canvas,64,(index-1)*96,0,.5,.5) end
end
return Opening
