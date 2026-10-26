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
local deferred=assert(loadfile('mods/DRAMATIC_SHAPE/lib/RetireQueue.lua'))(V).new()
local owned={};local cpu=false;local gpu=0
local co=coroutine.create(function()
 budget.own({release=function()cpu=true end})
 budget.own({release=function()
  for i=1,8 do gpu=gpu+1;now=now+.0006;budget.check() end
 end},true)
end)
budget.begin(co,1,owned);assert(coroutine.resume(co));budget.finish()
local before=now;budget.release(owned,deferred)
assert(cpu and gpu==0 and now==before and next(owned)==nil and deferred:pending(),
 'cancelled job released GPU resources inline or delayed CPU rollback')
deferred:pump(.001);assert(gpu==2 and deferred:pending(),'partial GPU owner bypassed retirement budget')
deferred:finish();assert(gpu==8 and not deferred:pending(),'cancelled job leaked or repeated GPU releases')
local immediate={};local freed=false
co=coroutine.create(function()budget.own({release=function()freed=true end},true)end)
budget.begin(co,1,immediate);assert(coroutine.resume(co));budget.finish();budget.release(immediate)
assert(freed and next(immediate)==nil,'explicit invalidation no longer releases immediately')
print('Cancelled builds: immediate CPU rollback, sliced GPU ownership and immediate invalidation fallback passed')
