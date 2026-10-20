local now=0
love={timer={getTime=function()return now end}}
local budget=assert(loadfile('mods/DRAMATIC_SHAPE/lib/BuildBudget.lua'))()
local V={require=function(n)assert(n=='BuildBudget');return budget end}
local q=assert(loadfile('mods/DRAMATIC_SHAPE/lib/RetireQueue.lua'))(V).new()
local released={}
local function release(n)
 for i=1,n do
  released[#released+1]=n*10+i
  now=now+.0006
  budget.check()
 end
end
q:add(4,release);q:pump(.001)
assert(#released==2 and q:pending(),'retirement did not yield within its slice')
q:add(1,release);q:pump(.001)
assert(#released==4 and q:pending(),'pending append changed in-flight release')
q:finish()
assert(#released==5 and released[5]==11 and not q:pending(),'retirement lost or repeated buffers')
q:add(1,release);q:finish();assert(#released==6,'empty queue cannot be reused')
print('Voxel GPU retirement: sliced release, pending append, drain and reuse passed')
