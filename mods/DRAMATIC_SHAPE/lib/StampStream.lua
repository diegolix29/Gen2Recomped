-- Flatten a shared hull once per geometry job. Doubles preserve the exact
-- Lua coordinates/shades until the translated final float stream is written.
local V=...
local Budget=V.require("BuildBudget")
local ok,ffi=pcall(require,"ffi")
local M={}
local order={1,2,3,1,3,4}
function M.build(quads)
 local count=#quads*6
 local out=ok and ffi.new("double[?]",math.max(1,count*7)) or {}
 local at=0
 for _,q in ipairs(quads)do
  Budget.tick()
  for _,i in ipairs(order)do
   local c=q[i];local uv=q.uv and q.uv[i]
   out[at],out[at+1],out[at+2]=c[1],c[2],c[3]
   out[at+3],out[at+4]=uv and uv[1] or q.u,uv and uv[2] or q.v
   local flat=type(q.shade)~="table"
   out[at+5]=flat and q.shade or q.shade[i]
   out[at+6]=flat and 1 or 0
   at=at+7
  end
 end
 return {data=out,count=count}
end
return M
