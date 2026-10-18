-- BLACK AND WHITE'S OPENING: the Game Freak logo, N's coronation and the
-- "Hopes! Dreams! ..." reel, between the boot cards and the title -- the
-- cartridge's overlay 179 (cdemo_main.c) run in modes 0, 1 and 2 by the ARM9's
-- boot state machine. See src/import/Gen5OpeningArt.lua for where every
-- number here comes from.
--
-- Each mode runs its own script from the overlay (op: 0 wait n frames, 1 / 2
-- fade in / out, 5 wait for the fade, 14 play a sequence, 18 play the movie
-- to its end, 19 a marker, 20 end). The movie is one LZ11 member a frame, a
-- 256-wide RGB555 bitmap, at 15 frames a second, on the top screen; the
-- coronation is letterboxed (170 lines, 11 down). A or START skips to the
-- title, as the boot machine's skip flag does.
local Lz=require('src.import.Gen5Lz')
local SecondScreen=require('src.ui.SecondScreen')
local Opening={};Opening.__index=Opening;Opening.isOpaque=true
Opening.FADE=16 -- frames of a divisor-1 brightness fade
function Opening:uiSize() return 256,192 end
function Opening:wantsFillScale() return true end
function Opening:wantsEdgeBleed() return false end
function Opening:sgbPalettes() return {require('src.render.PaletteFX').trueColorZone(0,0,31,23)} end

function Opening.new(game,onDone,modes)
  local rec=game.data.gen5_opening or {}
  return setmetatable({game=game,onDone=onDone,rec=rec,modes=modes or {0,1,2},
    modeIndex=0,archives={},brightness=0,fade=nil},Opening)
end

-- the cached movie archive for a mode, opened once
local function readBytes(path)
  local resolved=require('src.render.Assets').resolve(path)
  local bytes=love.filesystem.read(resolved)
  if not bytes then
    local root=os.getenv('POKEPORT_ASSET_ROOT')
    local f=root and io.open(root..'/'..resolved,'rb')
    if f then bytes=f:read('*a');f:close() end
  end
  return bytes
end
function Opening:archive(mode)
  if self.archives[mode]==nil then
    local m=self.rec.modes and self.rec.modes[mode]
    local bytes=m and m.movie and readBytes(m.movie)
    self.archives[mode]=bytes and require('src.import.NarcArchive').parse(bytes) or false
  end
  return self.archives[mode] or nil
end

function Opening:enter() self:nextMode() end

function Opening:nextMode()
  self.modeIndex=self.modeIndex+1
  local mode=self.modes[self.modeIndex]
  local m=mode and self.rec.modes and self.rec.modes[mode]
  if not m then return self:finish() end
  self.mode,self.def,self.pc,self.wait=mode,m,1,0
  self.movieFrame,self.movieClock,self.playing=nil,0,false
  self.showing=false
end

function Opening:finish()
  if self.done then return end
  self.done=true;self.game.stack:pop()
  if self.onDone then self.onDone() end
end

-- one RGB555 frame into an image (only the lines the cartridge copies)
function Opening:loadFrame(index)
  local arc=self:archive(self.mode)
  local raw=arc and arc:get(index)
  if not raw then return end
  if Lz.isCompressed(raw) then raw=Lz.decompress(raw) end
  local lines=self.def.lines or 192
  local data=self.imageData
  if not data then data=love.image.newImageData(256,192);self.imageData=data end
  local ffi=require('ffi')
  local px=ffi.cast('uint8_t*',data:getFFIPointer())
  local src=ffi.cast('const uint8_t*',raw)
  local top=self.def.top or 0
  for i=0,256*192*4-1 do px[i]=0 end
  for y=0,math.min(lines,192-top)-1 do
    local row=(y+top)*256*4
    for x=0,255 do
      local o=(y*256+x)*2
      local v=src[o]+src[o+1]*256
      local p=row+x*4
      px[p]=math.floor(v%32*255/31)
      px[p+1]=math.floor(math.floor(v/32)%32*255/31)
      px[p+2]=math.floor(math.floor(v/1024)%32*255/31)
      px[p+3]=255
    end
  end
  if self.image then self.image:replacePixels(data) else self.image=love.graphics.newImage(data) end
end

-- the script, a step at a time (60 Hz, the overlay's own loop)
function Opening:step()
  local script=self.def.script or {}
  while true do
    if self.wait>0 then self.wait=self.wait-1 return end
    if self.waitFade and self.fade then return end
    self.waitFade=nil
    if self.playing then
      self.movieClock=self.movieClock+1
      -- 15 frames a second against the 60 Hz loop
      if self.movieClock>=4 then
        self.movieClock=0
        self.movieFrame=self.movieFrame+1
        if self.movieFrame>=self.def.frames then self.playing=false
        else self:loadFrame(self.movieFrame) return end
      else return end
    end
    local row=script[self.pc]
    if not row then return self:nextMode() end
    self.pc=self.pc+1
    local op=row.op
    if op==0 then self.wait=row[1] or 0
    elseif op==1 or op==3 then self.fade={from=0,to=1,t=0}
    elseif op==2 or op==4 then self.fade={from=1,to=0,t=0}
    elseif op==5 then self.waitFade=true
    elseif op==14 then
      if row[1] then require('src.core.Music').play(self.game.data,row[1]) end
    elseif op==18 then
      self.movieFrame,self.movieClock,self.playing=0,0,true
      self.showing=true
      self:loadFrame(0)
      return
    elseif op==20 then return self:nextMode()
    end
  end
end

function Opening:update(dt)
  local i=self.game.input
  if self.tap or i:wasPressed('a') or i:wasPressed('start') then self.tap=nil return self:finish() end
  self.tick=(self.tick or 0)+(dt or 1/60)*60
  while self.tick>=1 and not self.done do
    self.tick=self.tick-1
    if self.fade then
      self.fade.t=self.fade.t+1
      local k=math.min(1,self.fade.t/Opening.FADE)
      self.brightness=self.fade.from+(self.fade.to-self.fade.from)*k
      if k>=1 then self.fade=nil end
    end
    self:step()
  end
end

function Opening:panel(bottom)
  local g=love.graphics
  g.setColor(0,0,0,1);g.rectangle('fill',0,0,256,192)
  if bottom then return end
  if self.image and self.showing then
    g.setColor(self.brightness,self.brightness,self.brightness,1)
    g.draw(self.image,0,0)
    g.setColor(1,1,1,1)
  end
end
function Opening:draw()
  local dual=SecondScreen.separate(self.game)
  self:panel(false)
  if dual then SecondScreen.draw(self.game,function() self:panel(true) end);self.game.secondScreenPointerOwner=self end
end
function Opening:touchpressed() self.tap=true;return true end
return Opening
