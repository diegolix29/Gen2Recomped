local V={}
local function clip(x,y,w,h,draw)
  if w<=0 or h<=0 then return end
  local g=love.graphics;local old={g.getScissor()}
  local x1,y1=g.transformPoint(x,y);local x2,y2=g.transformPoint(x+w,y+h)
  g.intersectScissor(math.min(x1,x2),math.min(y1,y2),math.abs(x2-x1),math.abs(y2-y1))
  draw();g.setScissor(unpack(old))
end
-- Native HBlank edge: 127 + y*cot(angle), with either inside or outside
-- the window visible. The source names this its circle-wipe effect.
function V.wipe(progress,reveal,colour)
  if (reveal and progress>=1) or (not reveal and progress<=0) then return end
  local g=love.graphics;colour=colour or {0,0,0};g.setColor(colour[1],colour[2],colour[3],1)
  local angle=progress*math.pi
  for y=0,191 do
    local edge=progress<=0 and 256 or progress>=1 and 0
      or math.max(0,math.min(255,math.floor(127+y*math.cos(angle)/math.sin(angle))))
    if reveal then g.rectangle('fill',0,y,edge,1) else g.rectangle('fill',edge,y,256-edge,1) end
  end
end
function V.draw(intro,sub,s)
  if not sub then
    if s.city then
      if not intro.cities then intro.cities=require('src.ui.HgssOpeningCities').new(intro.game.data) end
      intro.cities:draw(s.city,s.cityFrame)
      V.wipe(s.reveal,true,s.colour);V.wipe(s.cover,false)
    end
    return
  end
  if s.tick<211 then return end
  if s.tick<365 then
    intro:picture('montage_46')
    if s.silhouette then intro:actor('rival',0,0,128,96) end
    if s.section then intro:picture('montage_'..s.section) end
    if s.letterbox>0 then
      local g=love.graphics;g.setColor(0,0,0,1)
      g.rectangle('fill',0,0,256,s.letterbox);g.rectangle('fill',0,192-s.letterbox,256,s.letterbox)
    end
    V.wipe(s.rivalReveal,true)
    return
  end
  local function bg(key,x,y) intro:background('montage_'..key,x,y) end
  if s.rockets then
    local p=s.expand
    clip(70*(1-p),64*(1-p),115+140*p,64+128*p,function()
      bg(52,0,-8*s.rocketScroll);bg(51,0,-32*s.rocketScroll);bg(50,0,-48*s.rocketScroll)
    end)
  end
  local left,right=70*s.narrow,256-71*s.narrow
  clip(left,0,right-left,192,function()
    if not s.rockets then bg(46,0,0) end
    if s.suicune>0 and s.suicuneExit<1 then
      local sx=s.suicune<1 and 0 or s.tick>=630 and 70 or 0
      local ex=s.suicune<1 and 255*s.suicune or s.tick>=630 and 185-115*s.suicuneExit or 256
      clip(sx,64,ex-sx,64,function() bg(47,-256*s.suicune+116*s.suicuneExit,0) end)
    end
    if s.entei>0 and s.enteiExit<1 then
      local sx=s.entei<1 and 254*(1-s.entei) or s.tick>=570 and 70+115*s.enteiExit or 0
      clip(sx,0,256-sx,64,function() bg(48,256*s.entei-116*s.enteiExit,0) end)
    end
    if s.raikou>0 and s.raikouExit<1 then
      local sx=s.tick>=590 and 70+115*s.raikouExit or 0
      clip(sx,128,256*s.raikou-sx,64,function() bg(49,-256*s.raikou-116*s.raikouExit,0) end)
    end
  end)
  if s.eusine then intro:actor('eusine_unown',0,s.eusine,32,96) end
  for i,y in ipairs({32,160,96}) do
    local tick=s['unown'..i]
    if tick then intro:actor('eusine_unown',i,tick,128,y) end
  end
end
return V
