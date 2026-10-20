io.stdout:setvbuf('no')
local root=assert(os.getenv('ROOT')):gsub('\\','/')..'/'
package.path=root..'?.lua;'..package.path
function love.load()
 require('src.core.GameVersion').set('emerald')
 local data=require('src.core.Data');data:load();require('src.core.Game').data=data
 local libs={};local V={}
 V.require=function(n) if not libs[n] then libs[n]=assert(loadfile(root..'mods/DRAMATIC_SHAPE/lib/'..n..'.lua'))(V) end;return libs[n] end
 local TR=require('src.render.TileRenderer');local ML=require('src.world.MapLoader')
 local ts,def
 for _,d in pairs(data.maps) do
  local t=ML.tilesetFor(data,d)
  if t and t.id=='TILESET_03DF704_03DF74C' then ts,def=t,d;break end
 end
 assert(ts,'missing outdoor tileset fixture')
 local start=love.timer.getTime()
 local reference=assert(TR.gen3SheetsFor(ts,data,data.constants.gen3Layout))
 local function hash(image)
  local c=love.graphics.newCanvas(image:getDimensions());love.graphics.push('all');love.graphics.setCanvas(c);love.graphics.clear();love.graphics.setColor(1,1,1,1);love.graphics.draw(image);love.graphics.pop()
  local d=c:newImageData();local h=love.data.encode('string','hex',love.data.hash('sha256',d:getString()));d:release();c:release();return h
 end
 local hashes={hash(reference.bottom),hash(reference.top),reference.cover and hash(reference.cover)}
 print('cold synchronous sheet seconds',love.timer.getTime()-start)
 TR.releaseGen3Sheets()
 local warm=V.require('EngineSheets')
 local state={map={id='root'},neighbors={{map={def={width=10,height=10,connections={north={list={{map='test'}}}}}},ox=0,oy=0}}}
 local fake={maps={test=def},tilesets=data.tilesets,map_tilesets=data.map_tilesets,constants=data.constants}
 local slices,maxSlice=0,0
 repeat
  local t=love.timer.getTime();warm.pump(state,fake,.001);maxSlice=math.max(maxSlice,love.timer.getTime()-t);slices=slices+1
  assert(slices<10000)
 until not warm.pending()
 assert(slices>1,'did not slice the bake')
 start=love.timer.getTime();local warmed=assert(TR.gen3SheetsFor(ts,data,data.constants.gen3Layout));local duration=love.timer.getTime()-start
 assert(hash(warmed.bottom)==hashes[1] and hash(warmed.top)==hashes[2],'prefetch changed ROM pixels')
 assert(not hashes[3] or hash(warmed.cover)==hashes[3],'prefetch changed reflection cover')
 assert(duration<.02,'warm entry rebuilt sheet')
 print('PASS directed/list connections, sliced preparation, exact bottom/top/reflection pixels',slices,'slices; max',maxSlice,'warm lookup',duration)
 TR.releaseGen3Sheets();warm.pump(state,fake,.000001);assert(warm.pending())
 assert(TR.gen3SheetsFor(ts,data,data.constants.gen3Layout),'consumer saw incomplete sentinel')
 assert(not warm.pending(),'consumer did not finish pending work')
 print('PASS entering early finishes pending bake without missing tiles')
 TR.releaseGen3Sheets();warm.pump(state,fake,.000001);assert(warm.pending());V.require('Rewrap').unwindAll();assert(not warm.pending())
 print('PASS mod reload finishes pending sheet before removing hooks')
 love.event.quit()
end
