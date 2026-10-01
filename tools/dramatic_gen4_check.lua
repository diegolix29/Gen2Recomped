local Camera=require('src.render.Gen4Camera')
local voxel=assert(loadfile('mods/DRAMATIC_SHAPE/lib/VoxelState.lua'))()
local native=assert(loadfile('mods/DRAMATIC_SHAPE/lib/NativeGen4.lua'))({require=function(name) assert(name=='VoxelState');return voxel end})
local state={map={def={generation=4}}}
Camera.setTilt(6)
assert(native.supports(state) and native.drawWorld(state))
assert(native.update(state,1) and Camera.externalTilt=='cartridge')
local generation=Camera.generation
native.update(state,1);assert(Camera.generation==generation,'same camera must not invalidate terrain every frame')
native.update(state,3);assert(Camera.externalTilt==35 and Camera.mode()=='field3d')
Camera.setTilt(4);native.update(state,3)
assert(Camera.externalTilt==nil and Camera.mode()=='field3d','built-in camera choice must override the mod camera')
native.update(state,6);assert(Camera.mode()=='first')
native.update(state,7);assert(Camera.mode()=='third')
native.update(state,0);assert(Camera.externalTilt==nil and Camera.chosen==4)
native.update(state,1);assert(not native.update({map={def={generation=3}}},1))
assert(Camera.externalTilt==nil and Camera.chosen==4,'native camera preference must survive leaving the mod')
for _,p in ipairs({'mods/DRAMATIC_SHAPE/main.lua','mods/DRAMATIC_SHAPE/lib/FreeMove.lua','mods/DRAMATIC_SHAPE/lib/VoxelScene.lua'}) do assert(loadfile(p)) end
print('Dramatic Shapes Gen4: native renderer routing, camera modes, stable generation and preference restoration passed')
