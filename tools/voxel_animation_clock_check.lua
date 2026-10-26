local frame=0
package.loaded['src.render.Assets']={register=function()end,imageData=function()error('shadow clock prepared art')end}
package.loaded['src.render.TileRenderer']={animFrame=function()return frame end}
package.loaded['src.render.PaletteFX']={}
package.loaded['src.core.GameVersion']={get=function()return 'crystal'end}
love={}
local atlas=assert(loadfile('mods/DRAMATIC_SHAPE/lib/TerrainAtlas.lua'))({require=function(n)assert(n=='Gen3');return {}end})
local animated
for i=1,40 do local name,value=debug.getupvalue(atlas.animate,i);if name=='animated'then animated=value end end
assert(animated)
local map={tileset={image='clock_fixture'}}
local entry={specs={{kind='frames',period=3,sequence={1,2,3,4}},{kind='hshift',period=5,offsets={0,1}}},step=0,image={}}
animated['clock_fixture#a#-;-;-;-']=entry
assert(atlas.animate(map,nil)==entry.image,'fixture did not register its cached animation clock')
for i=0,300 do
 frame=i
 assert(atlas.shadowStep(map)==(math.floor(i/3)%4)*16+(math.floor(i/5)%2)*256,'mixed animation clock lost a boundary')
end
assert(atlas.shadowStep({tileset={}})==0 and atlas.shadowStep(nil)==0,'unknown tileset shadow lookup prepared art')
atlas.invalidate();assert(atlas.shadowStep(map)==0,'invalidation retained old clock metadata')
print('Animation shadow clocks: 301 mixed-period frames, unprepared tilesets, no art access and invalidation passed')
