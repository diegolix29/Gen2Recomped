-- A template is reusable while a live map retains its quad array. Avoid a
-- session-long strong cache retaining every forest/rock drawing ever visited.
local C={}
function C.new()
 return setmetatable({}, {
  __mode="v",
  __newindex=function(cache,key,template)
   if template and template.quads then
    -- Keep the wrapper (including its ground art) alive with its geometry.
    -- Once no map holds the array, this cycle is collectible as a unit.
    template.quads._templateOwner=template
   end
   rawset(cache,key,template)
  end,
 })
end
return C
