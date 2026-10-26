-- Reuse small pixel bands for animated slots instead of uploading the whole
-- terrain atlas. Static pixels between slots come from the original atlas.
local M={}
function M.new(source,patches,perRow)
  local w,h=source:getDimensions()
  local rows,order={},{}
  for i,t in ipairs(patches.slots)do
    local x,y=(t%perRow)*8,math.floor(t/perRow)*8
    if x>=0 and y>=0 and x+8<=w and y+8<=h then
      if not rows[y]then rows[y]={};order[#order+1]=y end
      rows[y][#rows[y]+1]={x=x,index=i}
    end
  end
  table.sort(order)
  local bands,bytes={},0
  local plan={bands=bands,bytes=0}
  function plan:release()
    for _,b in ipairs(bands)do b.data:release() end
    for i=#bands,1,-1 do bands[i]=nil end
  end
  local ok,err=pcall(function()
    for _,y in ipairs(order)do
      local b=bands[#bands]
      -- Bridge at most eight untouched rows to avoid many tiny driver calls.
      if not b or y>b.last+72 then
        b={y=y,last=y,slots={}};bands[#bands+1]=b
      else b.last=y end
      for _,slot in ipairs(rows[y])do
        slot.y=y-b.y;b.slots[#b.slots+1]=slot
      end
    end
    for _,b in ipairs(bands)do
      b.height=b.last-b.y+8
      b.data=love.image.newImageData(w,b.height)
      b.data:paste(source,0,0,0,b.y,w,b.height)
      bytes=bytes+w*b.height*4
    end
  end)
  if not ok then
    for _,b in ipairs(bands)do if b.data then b.data:release() end end
    error(err)
  end
  plan.bytes=bytes
  function plan:apply(image,strip)
    for _,b in ipairs(bands)do
      for _,slot in ipairs(b.slots)do
        b.data:paste(strip,slot.x,slot.y,(slot.index-1)*8,0,8,8)
      end
      image:replacePixels(b.data,1,1,0,b.y,false)
    end
  end
  return plan
end
return M
