-- Preserve uniform state when drawing an instanced variant of a scene shader.
local V=...
local S={}
local values=setmetatable({}, {__mode="k"})
local unpack=table.unpack or unpack
function S.send(shader,name,...)
 if not (V and V.sharedHulls) then return pcall(shader.send,shader,name,...) end
 local record=values[shader]
 if not record then record={};values[shader]=record end
 record[name]={...}
 return pcall(shader.send,shader,name,...)
end
function S.copy(source,target)
 for name,args in pairs(values[source] or {})do pcall(target.send,target,name,unpack(args))end
end
return S
