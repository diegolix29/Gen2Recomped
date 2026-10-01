local E={}
function E.new(_,_,progress)
 return {run=function()
  progress(0,1,'Heavy extraction',0,1)
  local endAt=love.timer.getTime()+0.25
  local sum=0
  while love.timer.getTime()<endAt do for i=1,10000 do sum=sum+i end end
  assert(sum>0)
  progress(1,1,'Heavy extraction',1,1)
 end}
end
return E
