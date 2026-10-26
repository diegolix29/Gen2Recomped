io.stdout:setvbuf('no')
local root=assert(os.getenv('ROOT')):gsub('\\','/')..'/'
package.path=root..'?.lua;'..package.path
function love.load()
 local ok,why=xpcall(function()
  local ffi=require('ffi');pcall(ffi.cdef,'int PHYSFS_mount(const char*,const char*,int);')
  local lib=ffi.load('love');assert(lib.PHYSFS_mount(root,'',1)~=0)
  assert(lib.PHYSFS_mount(assert(os.getenv('EMERALD_CACHE')),'',1)~=0)
  require('src.core.GameVersion').set('emerald')
  if os.getenv('PERF_HOST_BASE')=='1' then
   package.loaded['src.render.TileRenderer']=assert(loadfile(root..'tmp/emerald_perf/round7-TileRenderer-before.lua'))()
  end
  local Game=require('src.core.Game');local Data=require('src.core.Data');Data:load();Game.data=Data
  Game.save=require('src.core.SaveData').newGame({version='emerald'})
  Game.renderer={worldViewSize=function()return 800,650 end,setWorldBounds=function()end}
  local OW=require('src.world.OverworldController')
  local ML=require('src.world.MapLoader');local TR=require('src.render.TileRenderer')
  local stats={}
  local function wrap(t,k,label)
   label=label or k
   local f=t[k];if not f then return end
   t[k]=function(...)
    local start=love.timer.getTime();local r={f(...)};local dt=love.timer.getTime()-start
    local s=stats[label] or {n=0,total=0,max=0};stats[label]=s;s.n=s.n+1;s.total=s.total+dt;s.max=math.max(s.max,dt)
    return unpack(r)
   end
  end
  -- The same faster private pixel writer used by the live voxel mod.
  local libs,files={},{};local V={sharedHulls=true}
  V.data=function(n)
   if not files[n] then files[n]=assert(loadfile(root..'mods/DRAMATIC_SHAPE/data/'..n..'.lua'))() end
   return files[n]
  end
  V.mod={options={get=function()return false end}}
  V.require=function(n)
   if not libs[n] then libs[n]=assert(loadfile((os.getenv('PERF_MOD_LIB') or root..'mods/DRAMATIC_SHAPE/lib')..'/'..n..'.lua'))(V) end
   return libs[n]
  end
  local warm=V.require('EngineSheets')
  for _,k in ipairs({'load','trim'})do wrap(ML,k)end
  for _,k in ipairs({'new','gen3SheetsFor','rebuild'})do wrap(TR,k)end
  for _,k in ipairs({'computeNeighbors','rebuildNeighbors','setMap'})do wrap(OW,k)end
  wrap(require('src.world.NPC'),'new','NPC.new')
  wrap(require('src.render.SpriteRenderer'),'new','Sprite.new')
  require('src.core.Music').playMap=function()end
  local start=love.timer.getTime();OW:enter(os.getenv('PERF_MAP') or 'MAP_G00_N30',5,5,'down')
  OW.neighborReachW,OW.neighborReachH=800,650;OW:rebuildNeighbors()
  print('BOOT',love.timer.getTime()-start)
  local scene,mesher,baseRender
  local function upvalue(fn,wanted)
   for i=1,80 do local name,value=debug.getupvalue(fn,i);if name==wanted then return value end end
  end
  if os.getenv('PERF_VOXELS')=='1' then
   scene=V.require('VoxelScene');mesher=V.require('ChunkMesher')
   local drawing=false
   local render=scene.render
   baseRender=render
   scene.render=function(...)
    drawing=true;local result=render(...);drawing=false;return result
   end
   local function wrapSpan(t,k,label)
    local f=t[k]
    t[k]=function(...)
     local at=love.timer.getTime();local values={f(...)}
     print('VOXEL_SPAN',label,love.timer.getTime()-at)
     return unpack(values)
    end
   end
   wrapSpan(mesher,'setLive','setLive')
   local atlas=V.require('TerrainAtlas');local atlasFor=atlas.forMap
   atlas.forMap=function(map,...)
    if drawing and os.getenv('PERF_EXPECT_EAGER')~='1' then
     assert(mesher.peek(map,false) or mesher.peek(map,true),'draw eagerly prepared a texture before its terrain: '..map.id)
    end
    local at=love.timer.getTime();local image=atlasFor(map,...);local dt=love.timer.getTime()-at
    if dt>.002 then print('VOXEL_SPAN','animatedAtlas',dt)end
    return image
   end
  end
  local path={'MAP_G00_N29','MAP_G00_N13','MAP_G00_N28','MAP_G00_N26','MAP_G00_N27','MAP_G00_N12'}
  for step,id in ipairs(path) do
   if step>(tonumber(os.getenv('PERF_VOXEL_STEPS')) or #path)then break end
   if scene then
    scene.prefetch(OW,true)
    local pumps=0
    while mesher.pending()>0 do
     mesher.pump(false);pumps=pumps+1;assert(pumps<20000,'voxel warmup stalled')
     collectgarbage('step',1)
    end
    assert(mesher.peek(ML.load(Data,id),false),'destination full voxels not ready before crossing')
    print('PASS destination full mesh loaded before engine crossing',id,pumps)
    if os.getenv('PERF_SEAM_HEIGHT_CHECK')=='1' then V.require('VoxelState').angle=math.rad(35)end
    assert(scene.render(OW,800,650,800,650,function()return nil end),'warm source render failed')
    if os.getenv('PERF_SEAM_HEIGHT_CHECK')=='1' then
     local source=OW.map;local p=OW.player;local chosen
     local vectors={up={0,-1},down={0,1},left={-1,0},right={1,0}}
     for dir,d in pairs(vectors)do
      for c=0,((d[1]==0 and source.widthCells or source.heightCells)-1)do
       local x=d[1]<0 and 0 or d[1]>0 and source.widthCells-1 or c
       local y=d[2]<0 and 0 or d[2]>0 and source.heightCells-1 or c
       p.cellX,p.cellY,p.px,p.py=x,y,x*16,y*16
       p.elevation=source:cellElevation(x,y)
       local dest,_,dx,dy,conn=OW:connectionLanding(dir)
       if dest and source:isWalkableCell(x,y) then
        local target=ML.load(Data,conn.map)
        if target:isWalkableCell(dx,dy) and mesher.peek(target,false) then
         local height=scene.groundAt(source,x,y,p.elevation,x*16,y*16)
         if height>0 then chosen={dir=dir,d=d,x=x,y=y,conn=conn,height=height};break end
        end
       end
      end
      if chosen then break end
     end
     assert(chosen,'no raised walkable seam found in fixture')
     local c=chosen
     p.cellX,p.cellY,p.px,p.py=c.x,c.y,c.x*16,c.y*16
     p.elevation=source:cellElevation(c.x,c.y)
     assert(OW:crossConnection(c.dir,c.conn,true),'real connection crossing failed')
     assert(not OW.map:inBounds(p.cellX,p.cellY),'fixture did not start outside the incoming map')
     local pose=assert(upvalue(baseRender,'posesOf'))
     local startX,startY=p.px,p.py
     for i=0,3 do
      p.px,p.py=startX+c.d[1]*i*4,startY+c.d[2]*i*4
      local expected=scene.groundAt(source,c.x,c.y,p.elevation,c.x*16+c.d[1]*i*4,c.y*16+c.d[2]*i*4)
      local _,me=pose(OW,function()return nil end)
      print('SEAM_HEIGHT',source.id,OW.map.id,i,expected,me.gh)
      if os.getenv('PERF_EXPECT_ZERO_SEAM')=='1' then assert(me.gh==0,'baseline seam height changed')
      else assert(me.gh==expected,'player dipped below the departed map during seam step')end
     end
     local canvas=scene.render(OW,800,650,800,650,function()return nil end)
     if os.getenv('PERF_EXPECT_ZERO_SEAM')~='1' then
      assert(V.require('Voxel3D').groundY==c.height,'camera snapped down during seam step')
     end
     if os.getenv('PERF_CROSSING_TAG')then
      local image=canvas:newImageData()
      local file=assert(io.open(root..'tmp/emerald_perf/'..os.getenv('PERF_CROSSING_TAG')..'.png','wb'))
      file:write(image:encode('png'):getString());file:close();image:release()
     end
     print(os.getenv('PERF_EXPECT_ZERO_SEAM')=='1' and 'REPRO baseline places player at zero under raised ground' or 'PASS raised-map connection uses departed floor for player and camera')
     return
    end
   end
   local choice
   for _,nb in ipairs(OW.neighbors)do
    if nb.map.id==id then choice=nb;break end
   end
   assert(choice,'target was not already a loaded neighbour: '..id)
   if os.getenv('PERF_WARM')~='0' then
    local npcBefore=stats['NPC.new'] and stats['NPC.new'].n or 0
    local px,py=OW.player.cellX,OW.player.cellY
    local maxPump,maxGC=0,0
    for _=1,tonumber(os.getenv('PERF_WARM_FRAMES')) or 2000 do
     local t=love.timer.getTime();warm.pump(OW,Data,.001);maxPump=math.max(maxPump,love.timer.getTime()-t)
     t=love.timer.getTime();collectgarbage('step',1);maxGC=math.max(maxGC,love.timer.getTime()-t)
    end
    print('PREFETCH_MAX',maxPump,'GC_MAX',maxGC)
    assert((stats['NPC.new'] and stats['NPC.new'].n or 0)==npcBefore,'prefetch spawned gameplay NPCs')
    assert(OW.player.cellX==px and OW.player.cellY==py,'prefetch moved the player')
   end
   stats={}
   local t=love.timer.getTime();OW:setMap(id,5,5,'down',{seamless=true,keepMusic=true})
   print('SEAM',step,id,love.timer.getTime()-t)
   for k,s in pairs(stats)do print('SPAN',k,s.n,s.total,s.max)end
   if scene then
    local stages={
     {'voxelPrefetch',function()scene.prefetch(OW,true)end},
     {'voxelPump',function()mesher.pump(false)end},
     {'sheetPump',function()warm.pump(OW,Data,.001)end},
     {'firstRender',function()assert(scene.render(OW,800,650,800,650,function()return nil end))end},
     {'secondRender',function()assert(scene.render(OW,800,650,800,650,function()return nil end))end},
    }
    for _,stage in ipairs(stages)do
     local at=love.timer.getTime();stage[2]();print('CROSSING_STAGE',step,stage[1],love.timer.getTime()-at)
    end
    local canvas=scene.render(OW,800,650,800,650,function()return nil end)
    local pixels=canvas:newImageData()
    local hash=love.data.encode('string','hex',love.data.hash('sha256',pixels:getString()))
    print('CROSSING_IMAGE',step,hash)
    if os.getenv('PERF_CROSSING_TAG')then
     local file=assert(io.open(root..'tmp/emerald_perf/'..os.getenv('PERF_CROSSING_TAG')..'-'..step..'.png','wb'))
     file:write(pixels:encode('png'):getString());file:close()
    end
    pixels:release()
   end
  end
  if scene and os.getenv('PERF_POSE_CHECK')=='1' then
   local pose=assert(upvalue(baseRender,'posesOf'))
   local colors=function()return nil end
   local list,me=pose(OW,colors);local saved={}
   for i,p in ipairs(list)do saved[i]=p end
   local count=#list
   collectgarbage('collect');collectgarbage('stop');local before=collectgarbage('count')
   local start=love.timer.getTime()
   for _=1,400 do pose(OW,colors)end
   print('POSE_COST',count,love.timer.getTime()-start,collectgarbage('count')-before)
   collectgarbage('restart')
   if os.getenv('PERF_EXPECT_ALLOCATED_POSES')~='1' then
    local again=pose(OW,colors);assert(list==again and saved[count]==again[count],'pose records were not reused')
    local entities,ghosts=OW.entities,OW.ghosts;OW.entities={OW.player};OW.ghosts={}
    local short,player=pose(OW,colors);assert(#short==1 and player==short[1] and player.isPlayer)
    for i=2,#saved do assert(next(saved[i])==nil,'unused record retained old scene resources')end
    OW.entities,OW.ghosts=entities,ghosts
    local full=pose(OW,colors);local players=0
    for _,p in ipairs(full)do if p.isPlayer then players=players+1 end end
    assert(#full==count and players==1,'pose reuse kept a stale player flag')
    print('PASS pose records reuse, shrink, reference release and player flag isolation')
   end
  end
  if scene and os.getenv('PERF_RENDER_SAMPLES') then
   local perf=V.require('Perf');perf.enabled=true;perf.reset()
   local pixels=V.require('PixelCanvas');local create=pixels.new;local allocations=0
   pixels.new=function(...)allocations=allocations+1;return create(...)end
   local samples={};local profile={}
   local cameraX=OW.camera.x
   if os.getenv('PERF_JIT_PROFILE')=='1' then
    require('jit.profile').start('li1',function(thread,n)
     local stack=require('jit.profile').dumpstack(thread,'pl',12)
     profile[stack]=(profile[stack] or 0)+n
    end)
   end
   for i=1,tonumber(os.getenv('PERF_RENDER_SAMPLES')) do
    if os.getenv('PERF_RENDER_MOTION')=='1' then OW.camera.x=cameraX+(i%80)*.25 end
    local at=love.timer.getTime();scene.render(OW,800,650,800,650,function()return nil end)
    samples[i]=love.timer.getTime()-at
   end
   if os.getenv('PERF_JIT_PROFILE')=='1' then
    require('jit.profile').stop()
    local rows={};for stack,n in pairs(profile)do rows[#rows+1]={stack=stack,n=n}end
    table.sort(rows,function(a,b)return a.n>b.n end)
    for i=1,math.min(20,#rows)do print('RENDER_PROFILE',rows[i].n,rows[i].stack)end
   end
   table.sort(samples)
   print('RENDER_SAMPLES',#samples,'median',samples[math.ceil(#samples*.5)],'p95',samples[math.ceil(#samples*.95)],'max',samples[#samples])
   print('RENDER_CANVAS_ALLOCATIONS',allocations)
   pixels.new=create
   perf.printReport('warmed crossing render')
   OW.camera.x=cameraX
   if os.getenv('PERF_ANIMATION_SHADOW_CHECK')=='1' then
    local shadow=V.require('ShadowMap');local begin=shadow.begin;local casts=0
    shadow.begin=function(...)casts=casts+1;return begin(...)end
    local performance=require('src.core.Performance');local oldTier=performance.tier
    local daylight=V.require('DayNight');local time=daylight.time;local fixedTime=time()
    daylight.time=function()return fixedTime end
    local function renderPixels()
     scene.render(OW,800,650,800,650,function()return nil end)
     local image=shadow.texture():newImageData();local bytes=image:getString();image:release();return bytes
    end
    for _,tier in ipairs({'high','balanced'})do
     performance.tier=tier;renderPixels()
     for frame=1,8 do
      local before=casts;renderPixels();assert(casts==before,'still frame redrew shadows')
      for _=1,16 do TR.tick(1/60)end
      local current=renderPixels();assert(casts==before+1,'animation did not force one shadow redraw')
      local vp=table.concat(shadow.clipVP,',')
      shadow.invalidate();local fresh=renderPixels()
      if current~=fresh then
       local first,n
       n=0;for i=1,math.min(#current,#fresh)do if current:byte(i)~=fresh:byte(i)then n=n+1;first=first or i end end
       print('SHADOW_DIFFERENCE',tier,frame,#current,#fresh,n,first,shadow.res,'sameVP',vp==table.concat(shadow.clipVP,','))
      end
      assert(current==fresh,'animated cached shadow differs from freshly rendered shadow')
     end
     print('PASS animation shadow clock, stationary reuse and fresh-frame pixels',tier)
    end
    performance.tier=oldTier;shadow.begin=begin;daylight.time=time
   end
  end
  print('PASS native map entry trace')
 end,debug.traceback)
 if not ok then print('FAIL '..why)end
 love.event.quit(ok and 0 or 1)
end
function love.errorhandler(why)print('FAIL '..tostring(why));return function()return 1 end end
