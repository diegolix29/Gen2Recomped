-- Release-only activation for launcher touch input. Every control, including
-- sidebar actions, participates in the same tap-versus-scroll gesture.
local T={}
function T.pressed(ui,id,x,y)
 if ui._touchGesture then ui._touchGesture.cancelled=true;return end
 ui._touchGesture={id=id,x=x,y=y,lastX=x,lastY=y}
end
function T.moved(ui,id,x,y)
 local p=ui._touchGesture
 if not p or p.id~=id then return end
 local threshold=8*(ui._s or 1)
 if math.abs(x-p.x)>threshold or math.abs(y-p.y)>threshold then p.moved=true end
 if p.moved and not p.cancelled then
  -- Anchor hit-testing to the region where the drag began.
  ui._mx,ui._my=p.x,p.y
  local band=ui._tabBand
  if band and (ui._tabMax or 0)>0 and p.x>=band[1] and p.x<=band[2] and p.y>=band[3] and p.y<=band[4] then
   ui.tabScroll=math.max(0,math.min(ui._tabMax,(ui.tabScroll or 0)-(x-p.lastX)))
  else
   local previous=p.scrolling and p.lastY or p.y
   ui:wheelmoved(0,(y-previous)/(48*(ui._s or 1)))
  end
  p.scrolling=true
 end
 p.lastX,p.lastY=x,y
end
function T.released(ui,id,x,y)
 local p=ui._touchGesture
 if not p or p.id~=id then return end
 T.moved(ui,id,x,y) -- catches a fast swipe with no intermediate move event
 ui._touchGesture=nil
 if p.moved or p.cancelled then return end
 ui._mx,ui._my=x,y
 ui._touchResolving=true
 local ok,err=pcall(function()
  ui:mousepressed(p.x,p.y,1)
  ui:_updateSlotDrag() -- resolve legacy release-armed list/settings rows now
 end)
 ui._touchResolving=nil
 if not ok then error(err) end
end
return T
