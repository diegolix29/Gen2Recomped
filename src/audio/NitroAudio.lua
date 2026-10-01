-- Nintendo DS SSEQ transport over the ROM's SBNK/SWAR instruments.
-- PCM/ADPCM mixing is local; no replacement MIDI soundfont is used.
local Sdat=require('src.import.Gen4Sdat')
local Audio={};local Player={};Player.__index=Player
local archives,players={},setmetatable({}, {__mode="k"})
local RATE,BLOCK=32768,512
local function u8(s,o) return s:byte(o+1) end
local function u16(s,o) local a,b=s:byte(o+1,o+2);return b and a+b*256 end
local function u32(s,o) local a,b,c,d=s:byte(o+1,o+4);return d and a+b*256+c*65536+d*16777216 end
local function track(at) return {at=at,wait=0,program=0,volume=127,expression=127,pan=64,transpose=0,bend=0,bendRange=2,noteWait=true,calls={},loops={}} end
function Audio.new(data,def)
 local path=assert(data.audio.ndsArchive,'missing imported SDAT')
 local arc=archives[path]
 if not arc then
  local bytes=assert(love.filesystem.read(require('src.render.Assets').resolve(path)))
  arc=assert(Sdat.open(bytes));archives[path]=arc
 end
 local seq=assert(Sdat.sequence(arc,assert(def.nds)),'missing SDAT sequence')
 local at,size=Sdat.fileAt(arc,seq.file);local bytes=arc.data:sub(at+1,at+size)
 assert(bytes:sub(1,4)=='SSEQ','not a native SSEQ')
 local start=assert(u32(bytes,24),'truncated sequence')
 local self=setmetatable({arc=arc,seq=seq,bytes=bytes,start=start,tracks={[0]=track(start)},
  voices={},samples={},tempo=120,tickPhase=0,master=(seq.volume or 127)/127,
  queue=love.audio.newQueueableSource(RATE,16,2,4),looping=true,running=false},Player)
 players[self]=true
 return self
end
function Player:setVolume(v) self.queue:setVolume(v) end
function Player:getVolume() return self.queue:getVolume() end
function Player:setFilter(...) return self.queue:setFilter(...) end
function Player:setLooping(v) self.looping=v end
function Player:isPlaying() return self.running and (not self.ended or #self.voices>0 or self.queue:isPlaying()) end
function Player:stop() self.running=false;self.queue:stop();self.voices={} end
function Player:pause() self.paused=true;self.queue:pause() end
function Player:play()
 if self.paused then self.paused=false;self.queue:play();return end
 self.queue:stop();self.tracks={[0]=track(self.start)};self.voices={};self.tickPhase=1
 self.ended=false;self.running=true;self:update();self.queue:play()
end
local function signed(v) return v>=128 and v-256 or v end
function Player:note(t,note,velocity,duration)
 note=note+t.transpose
 local ins=Sdat.instrument(self.arc,self.seq.bank,t.program,note)
 if not ins then return end
 local key=ins.kind..':'..tostring(ins.archive)..':'..tostring(ins.wave)
 local sample=self.samples[key]
 if not sample then
  if ins.kind==1 then
   local list=Sdat.samples(self.arc,ins.archive)
   local swav=list and list[(ins.wave or 0)+1]
   local pcm,loop=Sdat.pcm(self.arc,swav)
   if pcm and #pcm>0 then sample={pcm=pcm,loop=swav.loop,loopAt=loop,rate=swav.rate};self.samples[key]=sample end
  elseif ins.kind==2 or ins.kind==3 then
   local pcm={};local period=ins.kind==2 and 8 or 32767;local lfsr=32767
   for i=1,period do
    if ins.kind==2 then pcm[i]=i<=((ins.wave or 3)+1) and 0.5 or -0.5
    else local bit=(lfsr%2+math.floor(lfsr/2)%2)%2;lfsr=math.floor(lfsr/2)+bit*16384;pcm[i]=lfsr%2==0 and -0.3 or 0.3 end
   end
   sample={pcm=pcm,loop=true,loopAt=0,rate=440*period};self.samples[key]=sample
  end
 end
 if not sample then return end
 if #self.voices>=32 then table.remove(self.voices,1) end
 local root=ins.kind==1 and ins.root or 69
 local pan=math.max(0,math.min(127,t.pan+ins.pan-64))/127
 self.voices[#self.voices+1]={sample=sample,pos=0,step=sample.rate/RATE*2^((note-root+t.bend*t.bendRange/128)/12),
  ticks=math.max(1,duration),gain=velocity/127*t.volume/127*t.expression/127*self.master*0.35,
  left=math.sqrt(1-pan),right=math.sqrt(pan),release=0}
end
function Player:events(t)
 local b=self.bytes
 local function read() local v=assert(u8(b,t.at),'sequence overrun');t.at=t.at+1;return v end
 local function word() local a,c=read(),read();return a+c*256 end
 local function address() local a,c,d=read(),read(),read();return self.start+a+c*256+d*65536 end
 local function variable() local v=0;for _=1,5 do local c=read();v=v*128+c%128;if c<128 then return v end end;error('invalid sequence variable') end
 for _=1,2048 do
  if t.done or t.wait>0 then return end
  local op=read()
  local override,velocityOverride
  if op==160 or op==161 then
   local prefix=op;op=read()
   if op<128 then velocityOverride=read() end
   if prefix==160 then
    local lo,hi=word(),word();lo=lo>=32768 and lo-65536 or lo;hi=hi>=32768 and hi-65536 or hi
    override=math.random(math.min(lo,hi),math.max(lo,hi))
   else local index=read();override=(self.variables or {})[index] or 0 end
  end
  local function parameter(fn) if override~=nil then local v=override;override=nil;return v end return fn() end
  if op<128 then
   local velocity=velocityOverride or read();local duration=parameter(variable);self:note(t,op,velocity,duration)
   if t.noteWait then t.wait=duration end
  elseif op==128 then t.wait=parameter(variable)
  elseif op==129 then t.program=parameter(variable)%128
  elseif op==147 then local id=read();self.tracks[id]=track(address())
  elseif op==148 then local dest=address();if not self.looping and dest<t.at then t.done=true else t.at=dest end
  elseif op==149 then local dest=address();assert(#t.calls<16,'sequence call overflow');t.calls[#t.calls+1]=t.at;t.at=dest
  elseif op==253 then t.at=table.remove(t.calls);if not t.at then t.done=true end
  elseif op==254 then word()
  elseif op==255 then t.done=true
  elseif op==252 then
   local loop=t.loops[#t.loops];if loop then
    loop.count=loop.count-1
    if loop.forever and self.looping or loop.count>0 then t.at=loop.at else table.remove(t.loops) end
   end
  elseif op>=192 and op<=223 then
   local v=parameter(read)
   if op==192 then t.pan=v elseif op==193 then t.volume=v elseif op==194 then self.master=v/127
   elseif op==195 then t.transpose=signed(v) elseif op==196 then t.bend=signed(v)
   elseif op==197 then t.bendRange=v elseif op==199 then t.noteWait=v~=0
   elseif op==212 then t.loops[#t.loops+1]={at=t.at,count=v,forever=v==0}
   elseif op==213 then t.expression=v end
  elseif op==224 or op==227 then parameter(word)
  elseif op==225 then self.tempo=math.max(1,parameter(word))
  else error(('unsupported SSEQ command %02X at %X'):format(op,t.at-1)) end
 end
 error('sequence failed to yield')
end
function Player:tick()
 local live=false
 for _,t in pairs(self.tracks) do
  if not t.done then t.wait=math.max(0,t.wait-1);self:events(t);live=live or not t.done end
 end
 self.ended=not live
 for _,v in ipairs(self.voices) do v.ticks=v.ticks-1;if v.ticks<=0 and v.release==0 then v.release=math.floor(RATE*0.04) end end
end
function Player:render()
 local sound=love.sound.newSoundData(BLOCK,RATE,16,2)
 for i=0,BLOCK-1 do
  self.tickPhase=self.tickPhase+self.tempo*48/60/RATE
  while self.tickPhase>=1 do self.tickPhase=self.tickPhase-1;self:tick() end
  local left,right=0,0
  for n=#self.voices,1,-1 do
   local v=self.voices[n];local s=v.sample;local pcm=s.pcm
   if v.pos>=#pcm then
    if s.loop and #pcm>s.loopAt then v.pos=s.loopAt+(v.pos-s.loopAt)%(#pcm-s.loopAt)
    else table.remove(self.voices,n);v=nil end
   end
   if v then
    local index=math.floor(v.pos)+1;local gain=v.gain
    if v.release>0 then gain=gain*v.release/(RATE*0.04);v.release=v.release-1;if v.release==0 then table.remove(self.voices,n) end end
    local value=(pcm[index] or 0)*gain
    left=left+value*v.left;right=right+value*v.right;v.pos=v.pos+v.step
   end
  end
  sound:setSample(i,1,math.max(-1,math.min(1,left)))
  sound:setSample(i,2,math.max(-1,math.min(1,right)))
 end
 return sound
end
function Player:update()
 if not self.running or self.paused then return end
 if self.ended and #self.voices==0 then
  if not self.queue:isPlaying() then self.running=false end
  return
 end
 while self.queue:getFreeBufferCount()>0 do self.queue:queue(self:render());if self.ended and #self.voices==0 then break end end
 if not self.queue:isPlaying() then self.queue:play() end
end
function Audio.update()
 for p in pairs(players) do
  if p.running then
   local ok,why=pcall(p.update,p)
   if not ok then p:stop();require('src.core.Logger').warn('DS audio: %s',tostring(why)) end
  end
  -- Music keeps its Source and may replay it after a pause; do not evict it.
 end
end
return Audio
