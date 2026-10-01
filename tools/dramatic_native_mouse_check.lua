local relative=false
local changes=0
local total=0
local focused=true
love={mouse={getRelativeMode=function() return relative end,
 setRelativeMode=function(value) relative=value;changes=changes+1 end},
 window={hasFocus=function() return focused end},
 mousemoved=function(_,_,dx) total=total+dx end}
local state={map={def={generation=4}}}
local game={overworld=state,stack={top=function() return state end}}
package.loaded['src.core.Game']=game
package.loaded['src.core.TouchControls']={}
local voxel={level=6,ready=true,isFreeCam=function(level) return level==6 or level==7 end}
local modules={Mat4={},VoxelState=voxel,Voxel3D={available=function() return true end},
 WorldCurve={},ThirdPerson={update=function() end}}
local fp=assert(loadfile('mods/DRAMATIC_SHAPE/lib/FirstPerson.lua'))({require=function(name) return assert(modules[name],name) end})
fp.install()
for _,mode in ipairs({6,7}) do
 voxel.level=mode;relative=true;local before=changes
 fp.update(1/60)
 assert(relative and changes==before,'mod released native mouse capture')
 for i=1,100 do love.mousemoved(9999,100,40,0,false) end
end
assert(total==8000,'native relative deltas must reach the engine even past the window edge')
state.map.def.generation=3;relative=false
fp.update(1/60);assert(relative,'voxel free camera lost mouse capture')
focused=false;fp.update(1/60);assert(not relative,'unfocused voxel camera must release capture')
state.map.def.generation=4;relative=false;local before=changes
fp.update(1/60);assert(changes==before,'native menu capture belongs to the engine')
assert(loadfile('src/core/Game.lua'))
print('Native first/third-person relative capture and delta pass-through; voxel focus release passed')
