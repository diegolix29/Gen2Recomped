local frames,fronts,drawn,quads={},0,{},0
local img={getDimensions=function()return 32,64 end}
local missing=false
package.loaded['src.pokewalker.WalkerArt']={
 walk=function(dex,shiny,version)
  assert(version==nil,'walking art pinned to reward source')
  frames[#frames+1]=dex
  if missing then return nil end
  return img,32,32,{right={99}},'heartgold'
 end,
 front=function()fronts=fronts+1;error('runner must never request battle art')end}
love={graphics={setColor=function()end,ellipse=function()end,circle=function()end,print=function()end,
 getFont=function()return {getWidth=function()return 8 end}end,
 newQuad=function(x,y,w,h,iw,ih)
  assert(x>=0 and y>=0 and x+w<=iw and y+h<=ih,'walking frame outside sheet')
  quads=quads+1;return {}
 end,
 draw=function()drawn[#drawn+1]=true end}}
local G=require('src.pokewalker.minigames.Gfx');G.version='emerald'
for i=1,1000 do G.walker(i%3+1,10,20,32,'right',i,'Pokemon')end
assert(#drawn==1000 and quads==1,'frame quads grow each rendered frame')
assert(frames[1]~=frames[2],'enemy species replaced by walker')
missing=true;assert(not G.walker(649,0,0,32,'right',0,'Genesect'))
assert(fronts==0,'missing walking sprite fell back to Pokedex art')
print('PASS highest-generation art selection, distinct species, bounded frame cache, invalid-frame guard and no portrait fallback')
