-- BW's own logo, prompt, developer credit and title dragon, played the way
-- overlay 88 (the title proc) plays it.
--
-- THE SCENE (/a/1/6/0, src/import/Gen5BootArt.lua): three objects --
-- title_b_01 (the dragon), title_b_02 and title_b_03 (the stage) -- each
-- looping its own joint animation, and the camera track (member 233 / 241).
-- 0x021B9DD0 runs once a frame at 60 Hz: the camera advances one record
-- (0x020115C0, FX32_ONE a call; it STOPS on its last record) and each object's
-- animation one frame (0x02047910, looping). The animations store most
-- channels every 2nd frame and the cartridge blends the frames between
-- (src/import/Gen4Anim.lua `stepped`).
--
-- THE CAMERA (0x02011B8C): a record is a rotation in degrees and a position;
-- the eye is the position, the target the position plus R * (0, 0, -1) and
-- the up vector R * (0, 1, 0), R = RotX * RotY * RotZ (0x020520FC). The
-- projection (0x021B9C2C) is a frustum from the sine / cosine table's entry
-- 341 -- 29.97 degrees, half the vertical field of view -- near 0.1 (0x19A),
-- far 2048, 4:3.
--
-- THE FLOW (0x021B95CC / 0x021B965C, counter at +0x8C): the logo comes in at
-- frame 666 with a white fade (0x0204E720: 16 -> 0, a step every 3 frames).
-- A / B / START while it plays jumps every object and the camera to frame
-- 5301 -- the last shot, the dragon's pose for the title -- with the same
-- fade; from there the camera loops 5301..5619 (White 5779; back to 5301 when it reads
-- frame 5619) and A / START opens the menu. The cartridge leaves an untouched
-- title for its opening movie after 4680 frames; here that jumps to the
-- title's own pose instead (the launcher shows this screen as a backdrop).
local Assets=require('src.render.Assets')
local Model=require('src.render.Gen4Model')
local SecondScreen=require('src.ui.SecondScreen')
local Title={};Title.__index=Title;Title.isOpaque=true
-- the old reconstructed framing, for a cache with no camera track
Title.CAM={0.65,0.2,1.5,42,0,0,0}
Title.CAM_SCALE=1
Title.SINGLE_LOGO_SCALE=0.62
-- overlay 88's numbers (see the header)
Title.FOVY=2*341*360/4096 -- 59.94 degrees
Title.NEAR,Title.FAR=410/4096,2048
Title.LOGO_AT=666
Title.POSE_AT=5301
-- the camera record that loops back to POSE_AT (Black ov88 0x021B9650
-- 5619 << 12, White 0x021B9670 5779 << 12)
Title.LAST_CAMERA={black=5619,white=5779}
Title.TIMEOUT=4680
Title.FADE_STEP=3
-- a jump between two records this large is a cut, not a move to blend over
Title.CUT_DISTANCE,Title.CUT_ANGLE=6,20
function Title:uiSize() return 256,192 end
function Title:wantsFillScale() return true end
function Title:wantsEdgeBleed() return false end
function Title:sgbPalettes()
  return {require('src.render.PaletteFX').trueColorZone(0,0,31,23)}
end
-- the stage record with the light-ray plane left out. `fx_rays1` wears a
-- translucent texture (alpha 0..255) the DS blends and its material is faded
-- by an animation not yet read; the model shader draws any texel over half
-- alpha solid, so the plane covered the screen in white. G5HIDE names others.
Title.HIDDEN_STAGE='fx_rays1'
function Title.stageRecord(rec)
  local hide=os.getenv('G5HIDE') or Title.HIDDEN_STAGE
  local copy={}
  for k,v in pairs(rec) do copy[k]=v end
  copy.shapes={}
  for _,shape in ipairs(rec.shapes or {}) do
    if not hide:find(tostring(shape.material),1,true) then copy.shapes[#copy.shapes+1]=shape end
  end
  return copy
end
function Title.new(game,opts)
  local art=game.data.gen5_boot_art or {}
  return setmetatable({game=game,opts=opts or {},art=art,cache={},frame=0,
    white=require('src.core.GameVersion').get()=='white',
    model=art.dragon and Model.new(art.dragon),
    middle=art.middle and Model.new(art.middle),
    stage=art.stage and Model.new(Title.stageRecord(art.stage))},Title)
end
function Title:enter()
  self.frame=0;self.scene=0;self.posed=false;self.flashAt=nil
  self.opened=false;self.tap=nil
  -- BW names it SEQ_BGM_TITLE; Gen5Audio files it as special.title
  local Music=require('src.core.Music')
  local song=((self.game.data.audio or {}).special or {}).title
  if song then Music.play(self.game.data,song) end
end
function Title:picture(key,x,y)
  local r=self.art[key];if not r then return end
  if self.cache[r.path]==nil then self.cache[r.path]=Assets.image(r.path) or false end
  if self.cache[r.path] then love.graphics.setColor(1,1,1,1);love.graphics.draw(self.cache[r.path],x or 0,y or 0) end
end
-- the logo is up from frame 666, or once the title's pose has been asked for
function Title:logoShown() return self.posed or (self.frame or 0)>=Title.LOGO_AT end
-- every object and the camera to the title's pose (0x021B9E7C(5301))
function Title:toPose()
  self.scene=Title.POSE_AT;self.posed=true;self.flashAt=self.frame
end
function Title:lastCamera()
  return Title.LAST_CAMERA[self.white and 'white' or 'black']
end
function Title:advance(steps)
  local before=self.frame
  self.frame=self.frame+steps
  self.scene=(self.scene or 0)+steps
  if before<Title.LOGO_AT and self.frame>=Title.LOGO_AT and not self.posed then self.flashAt=Title.LOGO_AT end
  -- in the pose the camera loops its last shot
  local last=self:lastCamera()
  if self.posed and self.scene>=last then
    self.scene=Title.POSE_AT+(self.scene-last)%(last-Title.POSE_AT)
  end
  if not self.posed and self.frame>=Title.TIMEOUT then self:toPose() end
end
function Title:update(dt)
  if self.opened then self.opened=false end
  self:advance((dt or 1/60)*60/math.max(1,self.game.logicSpeed and self.game:logicSpeed() or 1))
  local i=self.game.input
  if i:wasPressed('l') or i:wasPressed('select') then self.bottom=not self.bottom end
  local tap=self.tap;self.tap=nil
  if not self.posed then
    -- A / B / START: the title's pose first (0x021B965C, buttons & 0xB)
    if tap or i:wasPressed('a') or i:wasPressed('b') or i:wasPressed('start') then self:toPose() end
    return
  end
  if (self.frame-(self.flashAt or 0))>=8 and (tap or i:wasPressed('a') or i:wasPressed('start')) then
    self.opened=true;require('src.ui.Screens').push(self.game,'Gen5MainMenu',self.opts)
  end
end
-- the white fade the logo and the pose come in with: brightness 16 -> 0, a
-- step every FADE_STEP frames
function Title:flash()
  if not self.flashAt then return 0 end
  local level=16-math.floor((self.frame-self.flashAt)/Title.FADE_STEP)
  return math.max(0,math.min(16,level))/16
end

-- ------------------------------------------------------------- the camera --

local function angleLerp(a,b,t)
  local d=(b-a+180)%360-180
  return a+d*t
end
-- cameraAt(track, frame) -> eye, target, up, at a fractional record; the
-- fraction is blended unless the two records are a cut
function Title.cameraAt(track,frame)
  local d=track.data
  local n=track.frames
  local f=math.max(0,math.min(frame,n-1))
  local k0=math.floor(f);local t=f-k0
  local k1=math.min(k0+1,n-1)
  local a,b=k0*6,k1*6
  local rx,ry,rz=d[a+1],d[a+2],d[a+3]
  local px,py,pz=d[a+4],d[a+5],d[a+6]
  if t>0 and k1~=k0 then
    local jump=math.sqrt((d[b+4]-px)^2+(d[b+5]-py)^2+(d[b+6]-pz)^2)
    local turn=math.max(math.abs((d[b+1]-rx+180)%360-180),math.abs((d[b+2]-ry+180)%360-180),math.abs((d[b+3]-rz+180)%360-180))
    if jump<Title.CUT_DISTANCE and turn<Title.CUT_ANGLE then
      rx,ry,rz=angleLerp(rx,d[b+1],t),angleLerp(ry,d[b+2],t),angleLerp(rz,d[b+3],t)
      px,py,pz=px+(d[b+4]-px)*t,py+(d[b+5]-py)*t,pz+(d[b+6]-pz)*t
    end
  end
  local sx,cx=math.sin(math.rad(rx)),math.cos(math.rad(rx))
  local sy,cy=math.sin(math.rad(ry)),math.cos(math.rad(ry))
  local sz,cz=math.sin(math.rad(rz)),math.cos(math.rad(rz))
  -- v * RotX * RotY * RotZ (Nitro's row vectors): X first, then Y, then Z
  local function rotate(x,y,z)
    y,z=y*cx-z*sx,y*sx+z*cx
    x,z=x*cy+z*sy,-x*sy+z*cy
    x,y=x*cz-y*sz,x*sz+y*cz
    return x,y,z
  end
  local fx,fy,fz=rotate(0,0,-1)
  local ux,uy,uz=rotate(0,1,0)
  return {px,py,pz},{px+fx,py+fy,pz+fz},{ux,uy,uz}
end

-- one object's pose at a fractional frame of its looping animation
local function poseAt(model,motion,frame)
  local Anim=require('src.import.Gen4Anim')
  local n=math.max(1,motion and motion.frames or 1)
  local f=frame%n
  local k0=math.floor(f);local t=f-k0
  local k1=(k0+1)%n
  return model:posed(function(node)
    local track=motion and motion.tracks[node]
    if not track then return nil end
    local m0=Anim.unpackFrame(track,k0)
    if not m0 or t<=0 then return m0 end
    local m1=Anim.unpackFrame(track,k1)
    if not m1 then return m0 end
    for i=1,12 do m0[i]=m0[i]+(m1[i]-m0[i])*t end
    return m0
  end)
end

function Title:scene3d()
  local g=love.graphics
  if not self.model then return end
  if not self.colour then self.colour,self.depth=Model.newTarget(256,192) end
  if not self.colour then return end
  local bg=self.white and 1 or 0
  g.push('all');g.setCanvas({self.colour,depthstencil=self.depth});g.clear(bg,bg,bg,1,true,true)
  g.origin();g.setScissor();g.setColor(1,1,1,1)
  local flip={1,0,0,0,0,-1,0,0,0,0,1,0,0,0,0,1}
  local track=self.art.titleCamera
  local env=os.getenv('G5TITLECAM')
  local vp
  if track and not env then
    local eye,at,up=Title.cameraAt(track,math.min(self.scene or 0,track.frames-1))
    local u=tonumber(os.getenv('G5CAMSCALE') or '') or Title.CAM_SCALE
    for i=1,3 do eye[i]=eye[i]*u;at[i]=at[i]*u end
    self.cameraNow={eye=eye,at=at,up=up}
    vp=Model.multiply(flip,Model.multiply(Model.perspective(math.rad(Title.FOVY),256/192,Title.NEAR,Title.FAR),Model.lookAt(eye,at,up)))
  else
    -- no track: the eye as fractions of the model's radius off its centre,
    -- and the look-at point's offset; G5TITLECAM="dx,dy,dz,fov,ax,ay,az"
    local b=self.model.bounds;local scale=self.model.posScale
    local center={(b.minX+b.maxX)*scale/2,(b.minY+b.maxY)*scale/2,(b.minZ+b.maxZ)*scale/2}
    local radius=math.max(b.maxX-b.minX,b.maxY-b.minY,b.maxZ-b.minZ)*scale
    local c=Title.CAM
    if env then local v={};for n in env:gmatch('[-%d%.]+') do v[#v+1]=tonumber(n) end;c=v end
    local at={center[1]+radius*(c[5] or 0),center[2]+radius*(c[6] or 0),center[3]+radius*(c[7] or 0)}
    local eye={center[1]+radius*c[1],center[2]+radius*c[2],center[3]+radius*c[3]}
    vp=Model.multiply(flip,Model.multiply(Model.perspective(math.rad(c[4]),256/192,1,radius*10),Model.lookAt(eye,at)))
  end
  local fog=Model.depthFog;Model.depthFog=nil
  -- the stage (checkered floor, glow, rays) first, then the other two
  local frame=self.scene or 0
  for _,part in ipairs({{self.stage,self.art.stageMotion},{self.middle,self.art.middleMotion},{self.model,self.art.motion}}) do
    if part[1] then part[1]:draw(vp,poseAt(part[1],part[2],frame)) end
  end
  Model.depthFog=fog
  g.pop()
  g.setColor(1,1,1,1);g.draw(self.colour,0,0)
end
function Title:drawFlash()
  local w=self:flash()
  if w>0 then love.graphics.setColor(1,1,1,w);love.graphics.rectangle('fill',0,0,256,192);love.graphics.setColor(1,1,1,1) end
end
function Title:prompt()
  if self:logoShown() and self.frame%90<60 then
    local r=self.art.prompt
    if r then self:picture('prompt',math.floor((256-r.width)/2),162) end
  end
end
function Title:panel(bottom)
  local g=love.graphics;g.setColor(0,0,0,1);g.rectangle('fill',0,0,256,192)
  if bottom then
    self:scene3d()
    self:picture('developer')
  else
    self:picture('background')
    if self:logoShown() then self:picture('logo') end
    -- PRESS START sits under the logo on the TOP screen (Bulbapedia's
    -- BlackTitle.png: its letters on rows 164-170)
    self:prompt()
  end
  self:drawFlash()
end
-- ONE SCREEN: the dragon's 3D scene from the bottom screen behind the top's
-- logo and PRESS START, with the developer line (L shows the bottom alone)
function Title:single()
  local g=love.graphics;g.setColor(0,0,0,1);g.rectangle('fill',0,0,256,192)
  self:scene3d()
  -- the logo smaller and near the top, so the dragon shows below it, shrunk
  -- through SmoothScale so its outline stays clean
  local r=self.art.logo
  if r and self:logoShown() then
    if self.cache[r.path]==nil then self.cache[r.path]=Assets.image(r.path) or false end
    local pic=self.cache[r.path]
    if pic then
      local k=Title.SINGLE_LOGO_SCALE
      require('src.render.SmoothScale').draw(pic,(256-pic:getWidth()*k)/2,-16,k)
    end
  end
  self:prompt()
  self:picture('developer')
  self:drawFlash()
end
function Title:draw()
  if not SecondScreen.separate(self.game) and not self.bottom then self:single() return end
  local dual=SecondScreen.separate(self.game)
  self:panel(not dual and self.bottom)
  if dual then SecondScreen.draw(self.game,function() self:panel(true) end);self.game.secondScreenPointerOwner=self end
end
function Title:touchpressed() self.tap=true;return true end
return Title
