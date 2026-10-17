package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local N=require('src.import.Gen4Nsbmd')
local P=require('src.import.Gen4ModelPack')
local function word(n)
 n=n%4294967296;local s=''
 for i=1,4 do s=s..string.char(n%256);n=math.floor(n/256) end
 return s
end
local function delta(x,y,z) return word(x%1024+(y%1024)*1024+(z%1024)*1048576) end
local dl=string.char(0x40,0x23,0x28,0x41)..word(0)..word(4096+61440*65536)..word(2048)..delta(256,-256,-512)
local vertices=N.decodeDisplayList(dl,0,#dl)
assert(#vertices==2 and vertices[2].x==1.0625 and vertices[2].y==-1.0625 and vertices[2].z==.375,
 'VTX_DIFF must add signed 4.12 register deltas, not deltas divided by eight')
local restore=string.char(0x40,0x23,0x14,0x23)..word(0)..word(0)..word(0)..word(0)..word(0)..word(0)
local v=N.decodeDisplayList(restore,0,#restore)
assert(v[1].matrix==nil and v[2].matrix==0,'inherited transform must differ from explicit slot zero')
local model={name='inherit_and_zero',materials={},shapes={{name='s',vertices=v,triangles={},index=0}}}
local packed=P.pack(model)
assert(packed.shapes[1].matrixSlots==string.char(255,0),'cache retains both matrix sources')
assert(P.verify(model,packed),'matrix sources round-trip without collapsing slot zero')
local function translation(x) return {1,0,0,x,0,1,0,0,0,0,1,0,0,0,0,1} end
local pose=N.pose({{op='node',node=0,store=0},{op='shape',shape=0},
 {op='node',node=1,store=0},{op='shape',shape=1}},function(node) return translation(node==0 and 2 or 7) end)
assert(pose.stacks[0][0][4]==2 and pose.stacks[1][0][4]==9,
 'later slot reuse must not change an earlier display list palette')
local mix=N.pose({{op='node',node=0,store=0},{op='node',node=1,store=1,restore=0},
 {op='mix',slot=2,weights={{slot=0,node=0,weight=128},{slot=1,node=1,weight=128}}},
 {op='shape',shape=0}},function(node) return translation(node==0 and 4 or 2) end,
 {translation(-2),translation(-2)})
assert(mix.stack[2][4]==3 and mix.stacks[0][2][16]==1,'envelope blend combines inverse-bind-adjusted matrices')
local scale={2,0,0,0,0,3,0,0,0,0,4,0,0,0,0,1}
local child={1,0,0,1,0,1,0,2,0,0,1,3,0,0,0,1}
local compensated=N.pose({{op='node',node=0},{op='node',node=1,parent=0,scaleFlags=1},
 {op='shape',shape=0}},function(node) return node==0 and scale or child end,nil,1)[0]
assert(compensated[1]==1 and compensated[6]==1 and compensated[11]==1
 and compensated[4]==2 and compensated[8]==6 and compensated[12]==12,
 'segment compensation preserves scaled bone translation while removing parent scale from axes')
print('DS geometry: relative vertices, inherited/zero slots, palette snapshots, envelopes and segment scale passed')

-- BB flags carry optional store/restore operands, just like NODEDESC.
local commands=string.char(0x67,2,0,1,0x05,3,0x01)
local ops,unknown=N.poseCommands(commands,0,#commands)
assert(not unknown and #ops==2 and ops[1].op=='billboard' and ops[1].store==0
  and ops[1].restore==1 and ops[2].shape==3,'billboard operands cannot desynchronise later draw commands')
local draws=N.renderCommands(commands,0,#commands)
assert(#draws==1 and draws[1].shape==3,'static draw parser also skips billboard matrix operands')
local posed=N.pose({{op='node',node=0,store=1},ops[1],ops[2]},
  function() return translation(4) end,nil,nil,function(m,yOnly)
    assert(not yOnly and m[4]==4);return translation(9)
  end)
assert(posed[3][4]==9 and posed.stacks[3][0][4]==9,'billboard updates the current matrix and its requested slot')
local Model=require('src.render.Gen4Model')
local Cities=require('src.ui.HgssOpeningCities')
local view=Model.lookAt({0,10,10},{0,0,0})
local bill=Cities.billboard({2,0,0,7,0,3,0,8,0,0,4,9,0,0,0,1},view,false)
local facing=Model.multiply(view,bill)
assert(math.abs(facing[1]-2)<1e-8 and math.abs(facing[6]-3)<1e-8 and math.abs(facing[11]-4)<1e-8
  and math.abs(facing[10])<1e-8 and bill[4]==7 and bill[8]==8 and bill[12]==9,
  'full city billboards preserve scale and world position while facing the camera')
print('DS billboards: command widths, slots, camera orientation, scale and translation passed')
