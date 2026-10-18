-- Cartridge extraction and boot/title navigation without installed-cache writes.
love=require('tests.love_stub')
local count=0
local function check(ok,label) assert(ok,label);count=count+1 end
local Rom=require('src.import.NdsRom')
local Art=require('src.import.Gen5BootArt')
local images={}
for _,version in ipairs({'black','white'}) do
  local file=version=='black' and 'Pokemon - Black Version (USA, Europe) (NDSi Enhanced).nds'
    or 'Pokemon - White Version (USA, Europe) (NDSi Enhanced).nds'
  local rom=assert(Rom.open(file))
  local art=Art.build({rom=rom,version=version,saveImage=function(_,path,pic,extra)
    check(#pic.rgba==pic.width*pic.height*4,path..' complete RGBA')
    images[path]=pic
    local r={path=path,width=pic.width,height=pic.height}
    for k,v in pairs(extra or {}) do r[k]=v end
    return r
  end})
  check(art.logo.width==256 and art.logo.height==256,version..' logo dimensions')
  local logo=images['bw_boot/logo']
  local function alpha(x,y) return logo.rgba:byte((y*256+x)*4+4) end
  -- The secondary result from palette() must not become compose's firstTile;
  -- that shifts the logo out to both edges, leaving its middle empty.
  check(alpha(0,64)==0 and alpha(255,64)==0 and alpha(128,64)==255,version..' intact centered logo')
  check(art.dragon.name==(version=='black' and 'title_b_01' or 'title_w_01'),version..' retail dragon, no prototype')
  check(#art.dragon.nodes>15 and #art.dragon.shapes>5,version..' articulated model')
  local joints=0
  for _,blob in pairs(art.motion.tracks) do
    check(#blob==art.motion.frames*48,version..' complete joint timeline');joints=joints+1
  end
  check(joints>15 and art.motion.frames>60,version..' native joint animation')
  check(art.prompt.width==88 and art.prompt.height==15,version..' prompt NCER extent')
  rom:close()
end
package.loaded['src.render.Gen4Model']={new=function() return {} end}
local pushed={}
package.loaded['src.ui.Screens']={push=function(game,name,opts) pushed[#pushed+1]={name,opts} end}
package.loaded['src.core.Music']={stop=function() end}
local keys={};local pops,done=0,0
local game={data={},input={wasPressed=function(_,k) return keys[k] end},
  stack={pop=function() pops=pops+1 end},logicSpeed=function() return 1 end}
local Title=require('src.ui.Gen5Title')
local options={onNewGame=function() end}
local t=Title.new(game,options)
keys={a=true};t:update(1/60);check(#pushed==0,'startup does not consume held launch press')
keys={l=true};t:update(1/60);check(t.bottom,'single-screen lower panel accessible')
keys={};for i=1,30 do t:update(1/60) end
t:touchpressed();t:update(1/60)
check(#pushed==1 and pushed[1][1]=='Gen5MainMenu' and pushed[1][2]==options,'tap opens menu with boot callbacks')
keys={};t:update(1/60);check(not t.opened,'return from menu allows reopening')
local Intro=require('src.ui.Gen5Intro')
game.data.gen5_boot_art={copyright={}}
local intro=Intro.new(game,function() done=done+1 end)
intro:touchpressed();intro:update(1/60);intro:finish()
check(pops==1 and done==1,'skip completes once')
local function run(hz)
  local s=Intro.new(game,function() done=done+1 end)
  for i=1,hz*4 do s:update(1/hz) end
  check(s.done,'boot cards complete at '..hz..' Hz')
end
run(30);run(60);run(120)
print(count..' boot checks passed')
