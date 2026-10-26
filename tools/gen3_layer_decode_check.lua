local Tiles=require('src.render.Gen3Tiles')
local function reference(self,metatile,layer,ox,oy,plot)
 local entries=self:entries(metatile);local first=(layer-1)*4
 for q=0,3 do
  local e=entries[first+q+1]
  if e then
   local pixels,pal=self:tilePixels(e.tile),self:palette(e.palette)
   for y=0,7 do for x=0,7 do
    local sx,sy=e.flipX and 7-x or x,e.flipY and 7-y or y
    local v=pixels[sy*8+sx+1];local c=v~=0 and pal and pal[v+1]
    if c then plot(ox+(q%2)*8+x,oy+math.floor(q/2)*8+y,c[1],c[2],c[3])end
   end end
  end
 end
end
math.randomseed(804)
local function bytes(n)
 local t={};for i=1,n do t[i]=string.char(math.random(0,255))end;return table.concat(t)
end
local function bank()
 local pals={}
 for p=1,16 do local colors={};pals[p]=colors;for c=1,16 do colors[c]={p*9,c*11,(p+c)%16*15}end end
 pals[4]=nil
 return {tiles=bytes(512*32),metatiles=bytes(64*16),palettes=pals}
end
local pair={primary=bank(),secondary=bank()}
local t=Tiles.new(pair,{metatilesInPrimary=64})
local function events(fn,id,layer)
 local out={}
 fn(t,id,layer,-7,19,function(x,y,r,g,b)
  out[#out+1]=table.concat({x,y,r,g,b},',')
 end)
 return table.concat(out,';')
end
for _,frame in ipairs({0,1,5})do
 t.tileOverride={[7]=bytes(32),[515]=bytes(32)};t.tileCache={}
 for id=0,127 do for _,layer in ipairs({0,1,2,3,1.5})do
  assert(events(Tiles.drawLayer,id,layer)==events(reference,id,layer),('pixel/plot order mismatch %d/%s'):format(id,layer))
 end end
end
for _,broken in ipairs({{}, {metatiles=''}, {metatiles=string.rep('\0',15)}})do
 local b=Tiles.new({primary=broken})
 b:drawLayer(0,1,0,0,function()error('truncated entry painted pixels')end)
end
-- Warm decoded pixels before measuring only layer-call allocations.
for id=0,127 do Tiles.drawLayer(t,id,1,0,0,function()end)end
local function allocated(fn)
 collectgarbage('collect');collectgarbage('stop')
 local before=collectgarbage('count');local sum=0
 local plot=function(_,_,r)sum=sum+r end
 for i=1,2000 do fn(t,i%128,i%2+1,0,0,plot)end
 local amount=collectgarbage('count')-before
 collectgarbage('restart')
 return amount,sum
end
local old,a=allocated(reference);local direct,b=allocated(Tiles.drawLayer)
assert(a==b and direct<old*.1,'direct decode still allocates per-layer entry tables')
print(('PASS 1,920 ROM-layer comparisons, flips, palettes, transparency, overrides and truncation; allocation %.1f -> %.1f KiB'):format(old,direct))
