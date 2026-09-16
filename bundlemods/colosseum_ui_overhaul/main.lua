local mod=...
local VERSION="3.1.0"
mod.exports.version=VERSION
mod.exports.releaseBuild="colosseum-ui-3.1.0"

local source=mod:read("UIMain.lua")
if not source then error("colosseum_ui_overhaul: missing UIMain.lua",0) end
local chunk,err=load(source,"@"..tostring(mod.path or mod.id).."/UIMain.lua")
if not chunk then error(err,0) end
local install=chunk(mod)
if type(install)=="function" then install(mod) end
