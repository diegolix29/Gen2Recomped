local C=assert(loadfile('mods/DRAMATIC_SHAPE/lib/HullCache.lua'))()
local cache=C.new()
local live={}
do
 local q={{1,2,3}}
 local template={quads=q,bg=71}
 cache.tree=template
 live[1]={quads=q}
end
collectgarbage('collect');collectgarbage('collect')
assert(cache.tree and cache.tree.bg==71,'live stamp lost its template/ground texture')
local first=cache.tree
assert(first.quads==live[1].quads,'live geometry no longer shares its cached template')
first=nil;live=nil
collectgarbage('collect');collectgarbage('collect')
assert(cache.tree==nil,'departed map geometry retained for the entire session')
print('Voxel hull cache: live stamps retain templates; unused geometry is collectible')
