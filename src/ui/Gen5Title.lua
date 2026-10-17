-- BW's own logo, prompt, developer credit and title dragon. Camera framing
-- is reconstructed; the cartridge's moving camera/movie is not ported yet.
local Assets=require('src.render.Assets')
local Model=require('src.render.Gen4Model')
local SecondScreen=require('src.ui.SecondScreen')
local Title={};Title.__index=Title;Title.isOpaque=true
Title.CAM={0.65,0.2,1.5,42,0,0,0}
Title.CAM_SCALE=1
Title.SINGLE_LOGO_SCALE=0.62
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
    stage=art.stage and Model.new(Title.stageRecord(art.stage))},Title)
end
function Title:enter()
  self.frame=0;self.opened=false;self.tap=nil
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
function Title:update(dt)
  if self.opened then self.opened=false end
  self.frame=self.frame+(dt or 1/60)*60/math.max(1,self.game.logicSpeed and self.game:logicSpeed() or 1)
  local i=self.game.input
  if i:wasPressed('l') or i:wasPressed('select') then self.bottom=not self.bottom end
  if self.frame>=30 and (self.tap or i:wasPressed('a') or i:wasPressed('start')) then
    self.opened=true;require('src.ui.Screens').push(self.game,'Gen5MainMenu',self.opts)
  end
  self.tap=nil
end
function Title:scene()
  local g=love.graphics
  if not self.model then return end
  if not self.colour then self.colour,self.depth=Model.newTarget(256,192) end
  if not self.colour then return end
  local old={g.getCanvas()}
  local bg=self.white and 1 or 0
  g.push('all');g.setCanvas({self.colour,depthstencil=self.depth});g.clear(bg,bg,bg,1,true,true)
  g.origin();g.setScissor();g.setColor(1,1,1,1)
  local b=self.model.bounds;local scale=self.model.posScale
  local center={(b.minX+b.maxX)*scale/2,(b.minY+b.maxY)*scale/2,(b.minZ+b.maxZ)*scale/2}
  local radius=math.max(b.maxX-b.minX,b.maxY-b.minY,b.maxZ-b.minZ)*scale
  local flip={1,0,0,0,0,-1,0,0,0,0,1,0,0,0,0,1}
  -- the eye as fractions of the model's radius off its centre, and the
  -- look-at point's offset; G5TITLECAM="dx,dy,dz,fov,ax,ay,az" overrides it
  -- while matching Bulbapedia's capture by eye
  local c=Title.CAM
  local env=os.getenv('G5TITLECAM')
  if env then local v={};for n in env:gmatch('[-%d%.]+') do v[#v+1]=tonumber(n) end;c=v end
  local at={center[1]+radius*(c[5] or 0),center[2]+radius*(c[6] or 0),center[3]+radius*(c[7] or 0)}
  local eye={center[1]+radius*c[1],center[2]+radius*c[2],center[3]+radius*c[3]}
  -- the cartridge's own camera track (Gen5BootArt titleCamera), one record a
  -- 30 Hz frame, looping with the dragon's animation (the same length)
  local track=self.art.titleCamera
  if track and not env then
    local k=(math.floor(self.frame/2)%track.frames)*6
    local d=track.data
    local u=tonumber(os.getenv('G5CAMSCALE') or '') or Title.CAM_SCALE
    at={d[k+1]*u,d[k+2]*u,d[k+3]*u};eye={d[k+4]*u,d[k+5]*u,d[k+6]*u}
  end
  local vp=Model.multiply(flip,Model.multiply(Model.perspective(math.rad(c[4]),256/192,1,radius*10),Model.lookAt(eye,at)))
  local fog=Model.depthFog;Model.depthFog=nil
  -- the stage (checkered floor, glow, rays) first, then the dragon, each on
  -- its own animation at the cartridge's 30 Hz
  local function drawPart(model,motion)
    if not model then return end
    local frame=math.floor(self.frame/2)%math.max(1,motion and motion.frames or 1)
    local pose=model:posed(function(node)
      local track=motion and motion.tracks[node]
      return track and require('src.import.Gen4Anim').unpackFrame(track,frame) or nil
    end)
    model:draw(vp,pose)
  end
  drawPart(self.stage,self.art.stageMotion)
  drawPart(self.model,self.art.motion)
  Model.depthFog=fog
  g.setCanvas(old[1] and old or nil);g.pop()
  g.setColor(1,1,1,1);g.draw(self.colour,0,0)
end
function Title:panel(bottom)
  local g=love.graphics;g.setColor(0,0,0,1);g.rectangle('fill',0,0,256,192)
  if bottom then
    self:scene()
    self:picture('developer')
  else
    self:picture('background');self:picture('logo')
    -- PRESS START sits under the logo on the TOP screen (Bulbapedia's
    -- BlackTitle.png: its letters on rows 164-170)
    if self.frame%90<60 then
      local r=self.art.prompt
      if r then self:picture('prompt',math.floor((256-r.width)/2),162) end
    end
  end
end
-- ONE SCREEN: the dragon's 3D scene from the bottom screen behind the top's
-- logo and PRESS START, with the developer line (L shows the bottom alone)
function Title:single()
  local g=love.graphics;g.setColor(0,0,0,1);g.rectangle('fill',0,0,256,192)
  self:scene()
  -- the logo smaller and near the top, so the dragon shows below it, shrunk
  -- through SmoothScale so its outline stays clean
  local r=self.art.logo
  if r then
    if self.cache[r.path]==nil then self.cache[r.path]=Assets.image(r.path) or false end
    local pic=self.cache[r.path]
    if pic then
      local k=Title.SINGLE_LOGO_SCALE
      require('src.render.SmoothScale').draw(pic,(256-pic:getWidth()*k)/2,-16,k)
    end
  end
  if self.frame%90<60 then
    local r=self.art.prompt
    if r then self:picture('prompt',math.floor((256-r.width)/2),162) end
  end
  self:picture('developer')
end
function Title:draw()
  if not SecondScreen.separate(self.game) and not self.bottom then self:single() return end
  local dual=SecondScreen.separate(self.game)
  self:panel(not dual and self.bottom)
  if dual then SecondScreen.draw(self.game,function() self:panel(true) end);self.game.secondScreenPointerOwner=self end
end
function Title:touchpressed() self.tap=true;return true end
return Title
