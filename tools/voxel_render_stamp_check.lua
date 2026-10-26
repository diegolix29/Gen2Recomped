local stamp=assert(loadfile('mods/DRAMATIC_SHAPE/lib/RenderStamp.lua'))().new()
local function token(...)
 stamp.begin();for i=1,select('#',...)do stamp.put(select(i,...))end;return stamp.token()
end
local mesh={};local first=token(1,'actor',mesh,nil,0)
stamp.commit();assert(token(1,'actor',mesh,nil,0)==first)
assert(token(2,'actor',mesh,nil,0)~=first)
assert(token(1,'actor',mesh,nil,0)==first,'unrendered changes prevented reuse of the rendered snapshot')
assert(token(1,'actor',{},nil,0)~=first,'changed mesh identity was ignored')
assert(token(1,'actor',mesh,nil)~=first,'field count was ignored')
assert(token(1,'actor',mesh,nil,0,'battle')~=first,'battle animation was ignored')
local nextToken=token(2,'actor',mesh,nil,0);stamp.commit()
assert(token(2,'actor',mesh,nil,0)==nextToken)
local weak=setmetatable({},{__mode='v'})
do local object={};weak[1]=object;token(object);stamp.commit()end
token('new map');stamp.commit();collectgarbage('collect')
assert(not weak[1],'truncated snapshots retained old render objects')
-- Simulate throttled shadows: skipped poses that revert to the rendered
-- state must become reusable, and commits must match a reference value key.
local s=assert(loadfile('mods/DRAMATIC_SHAPE/lib/RenderStamp.lua'))().new()
local committed,version
for frame=1,10000 do
 local a,b=frame%7,math.floor(frame/13)%3
 local key=a..','..b
 s.begin();s.put(a);s.put(b);local v=s.token()
 assert((v~=version)==(key~=committed),'staleness differs from rendered reference')
 if frame%3==0 then s.commit();version=v;committed=key end
end
print('Render stamps: 10,000 throttled frames, reversion, nil fields, mesh identity and reference release passed')
