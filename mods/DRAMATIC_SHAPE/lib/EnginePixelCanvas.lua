-- Older hosts bake sheets through a per-pixel string table and one large
-- table.concat. Replace only that known factory; keep the original on hosts
-- without the required seam or RGBA byte access.
local V=...
local M={installed=false}
local hasFFI=pcall(require,"ffi")
function M.install(bake)
 if not (hasFFI and debug and debug.getupvalue and debug.setupvalue and type(bake)=="function") then return false end
 for slot=1,64 do
  local name,original=debug.getupvalue(bake,slot)
  if not name then break end
  if name=="pixelCanvas" and type(original)=="function" then
   local writer=V.require("AtlasPixels").writer
   local floor=math.floor
   local function fast(w,h)
    local ok,image=pcall(love.image.newImageData,w,h,"rgba8")
    local readable,pointer=false,nil
    if ok and image and image.getFFIPointer then readable,pointer=pcall(image.getFFIPointer,image) end
    if not (ok and image and readable and pointer and image.getFormat and image:getFormat()=="rgba8") then
     if ok and image and image.release then image:release() end
     return original(w,h)
    end
    local write=writer(image)
    local function plot(x,y,r,g,b)
     if x>=0 and y>=0 and x<w and y<h then write(x,y,floor(r),floor(g),floor(b),255) end
    end
    return plot,function()return image end
   end
   debug.setupvalue(bake,slot,fast)
   V.require("Rewrap").onUnwind(function()
    local key,value=debug.getupvalue(bake,slot)
    if key==name and value==fast then debug.setupvalue(bake,slot,original) end
    M.installed=false
   end)
   M.installed=true
   return true
  end
 end
 return false
end
return M
