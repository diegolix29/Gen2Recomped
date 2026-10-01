local rom=assert(require('src.import.NdsRom').open('Pokemon - Platinum Version (USA) (Rev 1).nds'))
local G=require('src.import.Gen4Graphics')
local box=assert(require('src.import.NarcArchive').parse(rom:read('/graphic/box.narc')))
local function member(i) local b=box:get(i);return G.isCompressed(b) and G.decompress(b) or b end
local a,why=require('src.import.Gen4CellAnim').parse(member(14),G)
assert(a,why);assert(#a.sequences==10)
local bank=assert(require('src.import.Gen4Cells').parse(member(13),G))
assert(#bank.cells==7 and #G.palette(member(26))==32)
assert(a.sequences[9].frames[1].x~=nil,'cursor translation must survive decoding')
local title=assert(require('src.import.NarcArchive').parse(rom:read('/demo/title/titledemo.narc')))
local bytes=title:get(1);if G.isCompressed(bytes) then bytes=G.decompress(bytes) end
local N=require('src.import.Gen4Nsbmd');local model=assert(N.parse(bytes)).models[1]
local function word(v)
 v=v%65536;return string.char(v%256,math.floor(v/256))
end
local nodeBytes=word(5)..word(0)..word(4096)..word(0)..word(-4096)..word(0)..word(0)..word(0)..word(0)..word(4096)
local node=N.nodeMatrix(nodeBytes,0)
assert(node[2]==-1 and node[5]==1 and node[11]==1,'native column-major bone rotation')
local P=require('src.import.Gen4ModelPack');local packed=P.pack(model)
assert(P.verify(model,packed))
local pose=N.pose(packed.ops,function(i) return packed.nodes[i+1].matrix end)
local slots={};local count=0
for _,shape in ipairs(packed.shapes) do
 for i=1,#(shape.matrixSlots or '') do
  local slot=shape.matrixSlots:byte(i)
  assert(pose.stack[slot],'missing Giratina joint slot '..slot)
  if not slots[slot] then slots[slot]=true;count=count+1 end
 end
end
assert(count>4,'Giratina must retain separate tentacle joints')
local A=require('src.import.Gen4Anim')
local pivot=A.pivotMatrix(0x20,0.8,0.6)
assert(pivot[1]==1 and pivot[5]==0.8 and pivot[6]==-0.6 and pivot[8]==0.6 and pivot[9]==0.8)
local swapped=A.pivotMatrix(1+0x10,0.8,0.6)
assert(swapped[4]==-1 and swapped[2]==0.8 and swapped[3]==0.6)
local animationBytes=title:get(2)
if G.isCompressed(animationBytes) then animationBytes=G.decompress(animationBytes) end
local animation=assert(A.parse(animationBytes)).animations[1]
local tracks=A.jointMatrices(animationBytes,animation)
local maxError=0
for _,joint in ipairs(tracks) do
 for _,m in ipairs(joint.track) do
  -- The title joints have unit scale. Bad basis packing stretches or detaches
  -- the six tentacles even though every vertex has a valid matrix slot.
  for c=1,3 do
   local length=m[c]^2+m[c+4]^2+m[c+8]^2
   maxError=math.max(maxError,math.abs(length-1))
  end
 end
end
assert(maxError<0.005,'decoded title rotation stretches a joint: '..maxError)
print('Native cursor and Giratina matrix round-trip passed: '..count..' joint slots')
rom:close()
