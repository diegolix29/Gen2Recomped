local Font=require('src.render.Font')
local Screens=require('src.ui.Screens')
local Storage={};Storage.__index=Storage;Storage.isOpaque=false
local ROWS={{'DEPOSIT POKEMON','deposit'},{'WITHDRAW POKEMON','withdraw'},{'MOVE POKEMON','move'},{'MOVE ITEMS','items'},{'SEE YA!',false}}
function Storage:uiSize() return 256,192 end
function Storage:wantsFillScale() return true end
function Storage:sgbPalettes() return {require('src.render.PaletteFX').trueColorZone(0,0,31,23)} end
function Storage.new(game,opts) return setmetatable({game=game,opts=opts or {},index=1},Storage) end
function Storage:close() self.game.stack:pop();if self.opts.onCancel then self.opts.onCancel() end;if self.opts.onDone then self.opts.onDone() end end
function Storage:choose() local row=ROWS[self.index];if not row[2] then return self:close() end;Screens.push(self.game,'BoxMenu',{mode=row[2]}) end
function Storage:update()
 local i=self.game.input
 if i:wasPressed('up') then self.index=(self.index-2)%#ROWS+1 elseif i:wasPressed('down') then self.index=self.index%#ROWS+1
 elseif i:wasPressed('a') then self:choose() elseif i:wasPressed('b') then self:close() end
end
function Storage:draw()
 local g=love.graphics;g.setColor(0.9,0.96,1,1);g.rectangle('fill',112,8,140,128);g.setColor(1,1,1,1)
 for i,row in ipairs(ROWS) do local y=16+(i-1)*24
  if self.index==i then g.setColor(0.55,0.75,0.85,1);g.rectangle('fill',116,y-2,132,22);g.setColor(1,1,1,1) end
  Font.draw(Font.fit(row[1],128),120,y)
 end
end
function Storage:touchpressed(_,px,py)
 local r=require('src.render.Renderer').uiPresentation;if not r then return false end
 local x,y=(px-r.x)/r.scaleX,(py-r.y)/r.scaleY;local i=math.floor((y-14)/24)+1
 if x>=112 and x<252 and i>=1 and i<=#ROWS then self.index=i;self:choose();return true end
 return false
end
return Storage
