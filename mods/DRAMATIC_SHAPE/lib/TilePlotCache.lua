-- Replay the ROM decoder's exact opaque-pixel events for static analysis.
-- Preserve duplicates and ordering: covered metatiles paint a second layer
-- over the first, and analysis counts those events as well as their colors.
local V=...
local Budget=V.require("BuildBudget")
local ok,ffi=pcall(require,"ffi")
local M={hits=0,misses=0,bytes=0,limit=8*1024*1024}
local pairsByKey,clock,epoch={},0,0
function M.clear() pairsByKey={};M.bytes=0;M.hits=0;M.misses=0;epoch=epoch+1 end
local function trim(keep)
 while M.bytes>M.limit do
  local victim,age
  for key,pair in pairs(pairsByKey)do
   if key~=keep and (not age or pair.used<age)then victim,age=key,pair.used end
  end
  if not victim then return end
  M.bytes=M.bytes-pairsByKey[victim].bytes;pairsByKey[victim]=nil
 end
end
function M.wrap(tiles,key)
 if not (ok and tiles and tiles.bakeMetatileInto and tiles.sheetOrigin) then return false end
 clock=clock+1
 local pair=pairsByKey[key]
 if not pair then pair={records={},used=clock,bytes=0};pairsByKey[key]=pair end
 pair.used=clock
 local original=tiles.bakeMetatileInto
 local generation=epoch
 tiles.bakeMetatileInto=function(self,id,layer,slot,plot)
  if generation~=epoch then return original(self,id,layer,slot,plot) end
  local recordKey=id*4+layer
  local record=pair.records[recordKey]
  local ox,oy=self:sheetOrigin(slot)
  if record then
   M.hits=M.hits+1
   local src=ffi.cast("const uint8_t*",record)
   for at=0,#record-1,5 do
    plot(ox+src[at],oy+src[at+1],src[at+2],src[at+3],src[at+4])
    if at%640==0 then Budget.check() end
   end
   return
  end
  M.misses=M.misses+1
  -- A 16x16 covered metatile can emit at most two opaque samples per pixel.
  local events=ffi.new("uint8_t[?]",512*5)
  local count,valid=0,true
  original(self,id,layer,slot,function(x,y,r,g,b)
   local dx,dy=x-ox,y-oy
   if count<512*5 and dx>=0 and dx<16 and dy>=0 and dy<16 then
    events[count],events[count+1],events[count+2],events[count+3],events[count+4]=dx,dy,r,g,b
    count=count+5
   else valid=false end
   plot(x,y,r,g,b)
  end)
  -- Publish only after the decoder and consumer both finish. A cancelled
  -- coroutine or failed callback must never leave a partial cached drawing.
  if valid then
   record=ffi.string(events,count)
   pair.records[recordKey]=record
   pair.bytes=pair.bytes+#record+64;M.bytes=M.bytes+#record+64
   trim(key)
  end
 end
 return true
end
return M
