-- Native BW boot cards. Movie scenes remain separate work; do not show
-- Platinum's Game Freak/portal sequence for an imported Unova cartridge.
local Title=require('src.ui.Gen5Title')
local SecondScreen=require('src.ui.SecondScreen')
local Intro={};Intro.__index=Intro;Intro.isOpaque=true
Intro.uiSize=Title.uiSize;Intro.wantsFillScale=Title.wantsFillScale
Intro.wantsEdgeBleed=Title.wantsEdgeBleed;Intro.sgbPalettes=Title.sgbPalettes
Intro.picture=Title.picture
function Intro.new(game,onDone)
  return setmetatable({game=game,onDone=onDone,art=game.data.gen5_boot_art or {},cache={},frame=0},Intro)
end
function Intro:enter() require('src.core.Music').stop() end
function Intro:finish()
  if self.done then return end
  self.done=true;self.game.stack:pop()
  -- the opening movies come next (ARM9 boot states 1-3: overlay 179 in
  -- modes 0, 1, 2), then the title -- src/ui/Gen5Opening.lua
  if self.game.data.gen5_opening then
    self.game.stack:push(require('src.ui.Gen5Opening').new(self.game,self.onDone))
    return
  end
  if self.onDone then self.onDone() end
end
function Intro:update(dt)
  self.frame=self.frame+(dt or 1/60)*60/math.max(1,self.game.logicSpeed and self.game:logicSpeed() or 1)
  local i=self.game.input
  if i:wasPressed('l') or i:wasPressed('select') then self.bottom=not self.bottom end
  if self.tap or i:wasPressed('a') or i:wasPressed('start') or self.frame>=240 or not self.art.copyright then self:finish() end
  self.tap=nil
end
function Intro:panel(bottom)
  local g=love.graphics;local studio=self.frame<120
  g.setColor(studio and 1 or 0,studio and 1 or 0,studio and 1 or 0,1);g.rectangle('fill',0,0,256,192)
  if studio then self:picture(bottom and 'studio_white' or 'company')
  elseif not bottom then self:picture('copyright') end
end
function Intro:draw()
  local dual=SecondScreen.separate(self.game)
  self:panel(not dual and self.bottom)
  if dual then SecondScreen.draw(self.game,function() self:panel(true) end);self.game.secondScreenPointerOwner=self end
end
function Intro:touchpressed() self.tap=true;return true end
return Intro
