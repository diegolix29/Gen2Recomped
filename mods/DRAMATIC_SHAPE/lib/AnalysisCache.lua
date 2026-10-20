-- A rebuilding coroutine sees its private analysis; rendering keeps the
-- published version until that rebuild commits with its mesh.
local A={}
function A.new()
 local published,working={},{}
 local proxy=setmetatable({}, {
  __index=function(_,key)
   local scope=working[coroutine.running()]
   if scope and scope.key==key then return scope.value or nil end
   return published[key]
  end,
  __newindex=function(_,key,value)
   local scope=working[coroutine.running()]
   if scope and scope.key==key then scope.value=value else published[key]=value end
  end})
 local function begin(key)
  local co=assert(coroutine.running(),"analysis rebuild requires a coroutine")
  assert(not working[co],"nested analysis rebuild")
  local scope={key=key};working[co]=scope
  local token={}
  function token.release() if working[co]==scope then working[co]=nil end end
  function token.commit()
   assert(working[co]==scope,"cancelled analysis rebuild")
   published[key]=scope.value;working[co]=nil
  end
  return token
 end
 local function clear()published={};working={}end
 return proxy,begin,clear
end
return A
