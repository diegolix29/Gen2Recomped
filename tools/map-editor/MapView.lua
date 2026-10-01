local View={}
function View.draw(S,map,key,camX,camY,w,h)
 local g=love.graphics
 w,h=math.max(1,math.ceil(w)),math.max(1,math.ceil(h))
 S._editorViews=S._editorViews or {}
 local canvas=S._editorViews[key]
 if not canvas or canvas:getWidth()~=w or canvas:getHeight()~=h then
  if canvas then canvas:release() end
  canvas=g.newCanvas(w,h);S._editorViews[key]=canvas
 end
 -- Terrain baking switches render targets. Panel scissor coordinates and
 -- transforms must never leak into those model/tileset canvases.
 g.push('all');g.setCanvas(canvas);g.origin();g.setScissor();g.setShader();g.setColor(1,1,1,1);g.clear()
 local ok,why=pcall(function()
  map.renderer:draw(camX,camY,w,h)
  map.renderer:drawAbove(camX,camY,w,h)
 end)
 g.pop()
 if not ok then error(why) end
 g.setColor(1,1,1,1);g.draw(canvas)
end
return View
