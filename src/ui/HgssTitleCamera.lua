-- title_screen.c: the four camera targets, per-axis five-unit movement,
-- and holds measured by the source's duration * 30 counter.
local C={}
local PATHS={
  heartgold={{180,177,301,10},{335,-293,296,5},{180,177,301,5},{625,152,256,10}},
  soulsilver={{105,162,291,10},{395,432,191,5},{105,162,291,5},{420,87,331,10}},
}
function C.new(version)
  local path=PATHS[version] or PATHS.heartgold;local initial=path[4]
  return {path=path,eye={initial[1],initial[2],initial[3]},index=1,timer=0}
end
function C.step(camera)
  camera.timer=camera.timer+1
  local target=camera.path[camera.index]
  if camera.timer<=target[4]*30 then return end
  local arrived=true
  for axis=1,3 do
    local d=target[axis]-camera.eye[axis]
    if d>1 then camera.eye[axis]=camera.eye[axis]+5;arrived=false
    elseif d< -1 then camera.eye[axis]=camera.eye[axis]-5;arrived=false end
  end
  if arrived then camera.timer=0;camera.index=camera.index%#camera.path+1 end
end
return C
