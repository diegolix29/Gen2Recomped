io.stdout:setvbuf('no')
local root=assert(os.getenv('ROOT')):gsub('\\','/')
package.path=root..'/?.lua;'..root..'/?/init.lua;'..package.path
function love.load()
 local ok,why=xpcall(function()
  local ffi=require('ffi');pcall(ffi.cdef,'int PHYSFS_mount(const char*,const char*,int);')
  assert(ffi.load('love').PHYSFS_mount(root,'',1)~=0)
  local imported=assert(os.getenv('CACHE_ROOT')):gsub('\\','/')
  local Ser=require('src.core.SaveSerializer')
  local function read(path)
   local f=assert(io.open(imported..'/'..path,'rb'),path);local b=f:read('*a');f:close();return b
  end
  local function record(version,name)return assert((loadstring or load)(read(version..'/data/generated/'..name..'.lua')))()end
  local function write(path,bytes)
   assert(love.filesystem.createDirectory(path:match('^(.*)/')))
   assert(love.filesystem.write(path,bytes))
  end
  local function data(version,name,value)write(version..'/data/generated/'..name..'.lua',Ser.encode(value))end
  local function image(version,path)write(version..'/'..path,read(version..'/'..path))end
  local emerald=record('emerald','pokemon')
  local treecko=assert(emerald.TREECKO)
  assert(treecko.dex==252 and treecko.index~=treecko.dex)
  data('emerald','pokemon',{TREECKO=treecko})
  local icons=record('emerald','icons');data('emerald','icons',{bySpecies={TREECKO=icons.bySpecies.TREECKO}})
  image('emerald',treecko.spriteFront);image('emerald',icons.bySpecies.TREECKO.image)
  -- Save directory only, no custom folder: the common Android installation.
  local osName=love.system.getOS;love.system.getOS=function()return 'Android'end
  local customRoot
  package.loaded['src.import.CacheFs']={root=function()return customRoot end}
  local Save=require('src.core.SaveData');assert(Save.dataDir()==nil and Save.portableBaseDir()==nil)
  local fs=love.filesystem;local saveDir=fs.getSaveDirectory():gsub('\\','/'):gsub('/$','')
  local open=io.open
  io.open=function(path,...)
   local normalized=tostring(path):gsub('\\','/')
   if normalized:sub(1,#saveDir+1)==saveDir..'/' and not normalized:find('/custom_cache/',1,true) then
    return nil,'simulated virtual-only mobile cache'
   end
   return open(path,...)
  end
  local Art=require('src.pokewalker.WalkerArt');Art.forget()
  local Courses=require('src.pokewalker.WalkerCourses');Courses.forget()
  local Link=require('src.pokewalker.WalkerLink')
  local GV=require('src.core.GameVersion');local previous=GV.get()
  assert(Link.dexOf('emerald','TREECKO')==252)
  assert(Link.dexOf('emerald',treecko.index)==252)
  assert(Link.dexOf('emerald','SPECIES_'..treecko.index)==252)
  assert(Courses.species()[252].name==treecko.name,'mobile species facts missing without custom folder')
  local walking,_,_,_,version=Art.walk(252);assert(walking and version=='emerald')
  local portrait,from=Art.front(252);assert(portrait and from=='emerald')
  assert(Art.front(649)==nil,'unimported species unexpectedly available')
  print('PASS Android default/virtual cache: named and internal Emerald IDs, roster, walking and portrait art')
  -- Import newer games after missing-art results have already been cached.
  local followers=record('heartgold','gen4_follow_mon')
  local sheet=assert(followers.sheets[followers.lut[252]])
  data('heartgold','gen4_follow_mon',{sheets={sheet},lut={[252]=1},facings=followers.facings})
  image('heartgold',sheet.normal)
  local black=record('black','pokemon')
  data('black','pokemon',{[252]=black[252],[649]=black[649],[650]=black[649]})
  local sprites=record('black','gen4_species_sprites')
  data('black','gen4_species_sprites',{species={[252]=sprites.species[252],[649]=sprites.species[649]}})
  image('black',sprites.species[252].front);image('black',sprites.species[649].front)
  -- Same invalidation used by successful ROM import completion.
  Art.forget();Courses.forget()
  walking,_,_,_,version=Art.walk(252);portrait,from=Art.front(252)
  assert(walking and version=='heartgold' and portrait and from=='black')
  assert(Art.front(649) and Courses.species()[649] and not Courses.species()[650])
  assert(GV.get()==previous,'art lookup changed the running game version')
  print('PASS later import clears misses; highest supported walk is HGSS and highest portrait is BW; DS form rows excluded')
  local W=require('src.pokewalker.Walker');local st=W.newState()
  local raw={species='TREECKO',nickname='Leaf',level=7,personality=12345}
  st.walking={raw=raw,name='Leaf',level=7,types={},steps=42,friendSteps=3,
   source={version='emerald',slot=1,box=1,index=1}}
  W.live=st
  local Screen=require('src.ui.PokewalkerScreen');local ui=Screen.new({})
  assert(st.walking.species==252 and st.walking.raw==raw and raw.species=='TREECKO' and raw.personality==12345)
  local disk=assert(Ser.decode(fs.read(W.FILE)))
  assert(disk.walking.species==252 and disk.walking.raw.nickname=='Leaf','legacy walk repair was not persisted')
  local canvas=love.graphics.newCanvas(640,360)
  love.graphics.push('all');love.graphics.setCanvas(canvas);love.graphics.clear(.08,.1,.15,1)
  assert(ui:drawWalker(252,180,270,120,'right'))
  assert(ui:drawPortrait(252,350,110,140))
  love.graphics.pop()
  local pixels=canvas:newImageData()
  local out=assert(io.open(root..'/tmp/emerald_perf/round6-mobile-walker.png','wb'))
  out:write(pixels:encode('png'):getString());out:close();pixels:release();canvas:release()
  print('PASS legacy blank walk repaired without replacing its raw Pokemon; screen renders both ROM images')
  assert(Art.dexOf('emerald','ROOT_ONLY')==nil)
  write('custom_cache/emerald/data/generated/pokemon.lua',Ser.encode({ROOT_ONLY={dex=25,index=25,name='Root Only'}}))
  customRoot=saveDir..'/custom_cache'
  assert(Art.refreshRoots(),'changed cache folder was not detected')
  Courses.forget()
  assert(Art.dexOf('emerald','ROOT_ONLY')==25,'old negative source lookup survived folder change')
  assert(not Art.refreshRoots(),'unchanged cache roots repeatedly cleared artwork')
  print('PASS cache folder changes clear source misses without flushing unchanged roots')
  io.open=open;love.system.getOS=osName
 end,debug.traceback)
 if not ok then print('FAIL '..why)end
 love.event.quit(ok and 0 or 1)
end
function love.errorhandler(why)print('FAIL '..tostring(why));return function()return 1 end end
