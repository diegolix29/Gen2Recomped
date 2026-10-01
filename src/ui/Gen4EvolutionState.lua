-- Platinum art with the shared evolution transaction and move-learning flow.
local Base = require('src.ui.Gen3EvolutionState')
local Assets = require('src.render.Assets')
local State = {}; State.__index = State
setmetatable(State, { __index = Base }); State.isOpaque = true
function State.new(game, mon, species, onDone, via, evo)
  local self = Base.new(game, mon, species, onDone, via, evo)
  setmetatable(self, State)
  local function front(id)
    local path=require('src.pokemon.Sprites').path(game.data,id,'front',{mon=mon,kind='evolution'})
    if path then local ok,img=pcall(Assets.image,path);if ok then return img end end
  end
  self.oldSprite,self.newSprite=front(mon.species),front(species)
  local rec = (((game.data.gen4_graphics or {}).screens) or {})['evolution/background']
  local path = type(rec) == 'table' and rec.path or rec
  if path then local ok, image = pcall(Assets.image, path); if ok then self.background = image end end
  require('src.core.Sound').playCry(game.data, mon.species)
  return self
end
function State:uiSize() return 256, 192 end
function State:wantsFillScale() return true end
function State:sgbPalettes() return {require('src.render.PaletteFX').trueColorZone(0,0,31,23)} end
function State:draw()
  local g = love.graphics
  g.setColor(0,0,0,1); g.rectangle('fill',0,0,256,192); g.setColor(1,1,1,1)
  if self.background then g.draw(self.background,0,0) end
  local image, scale = self.oldSprite, 1
  if self.phase == 'morph' then
    -- Alternating silhouettes compress and expand; effect timing is reconstructed.
    local p = math.min(1,self.t/150)
    local period = math.max(4,math.floor(24-20*p))
    local beat = self.t % period / period
    image = beat < 0.5 and (self.oldWhite or self.oldSprite) or (self.newWhite or self.newSprite)
    scale = 0.1 + 0.9 * math.abs(beat*2-1)
  elseif self.phase == 'flash' then
    g.setColor(1,1,1,1);g.rectangle('fill',0,0,256,192);return
  elseif self.phase == 'done' then image = self.canceled and self.oldSprite or self.newSprite end
  if image then
    local previous=g.getShader()
    if self.phase=='morph' then
      self.whiteShader=self.whiteShader or g.newShader([[vec4 effect(vec4 colour,Image tex,vec2 uv,vec2 screen){return vec4(1.0,1.0,1.0,Texel(tex,uv).a)*colour;}]])
      g.setShader(self.whiteShader)
    end
    local w,h=image:getDimensions();g.draw(image,128,88,0,scale,scale,w/2,h/2)
    g.setShader(previous)
  end
  g.setColor(1,1,1,1)
end
return State
