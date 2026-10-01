-- Run with LOVE from the repository root: love tools/gen4_lcd_shader_check
function love.load()
  local root = love.filesystem.getWorkingDirectory()
  package.path = root .. '/?.lua;' .. package.path
  package.loaded['src.render.Assets'] = {}
  package.loaded['src.render.Font'] = {}
  package.loaded['src.core.Logger'] = {}
  package.loaded['src.ui.SecondScreen'] = {}
  package.loaded['src.core.Strings'] = function(x) return x end
  local result = 'LCD shader check passed'
  local ok, err = pcall(function()
    local P = require('src.ui.Gen4Poketch')
    local G = require('src.import.Gen4Graphics')
    local source, target = {}, {}
    for i=1,16 do source[i]={115,181,115}; target[i]={181,115,115} end
    local hex = G.paletteHex(source) .. G.paletteHex(source) .. G.paletteHex(target)
    local watch = setmetatable({game={save={poketch={color=1}},data={
      gen4_graphics={palettes={['poketch/generic']=hex}}}}}, {__index=P})
    local canvas = love.graphics.newCanvas(8,8)
    love.graphics.setCanvas(canvas)
    watch:applyLCDPalette()
    love.graphics.setColor(115/255,181/255,115/255,1)
    love.graphics.rectangle('fill',0,0,8,8)
    love.graphics.setShader()
    love.graphics.setCanvas()
    local r,g = canvas:newImageData():getPixel(4,4)
    assert(math.abs(r-181/255)<0.01 and math.abs(g-115/255)<0.01, 'LCD palette did not change')
  end)
  if not ok then result = tostring(err) end
  local f = assert(io.open(root .. '/tools/gen4_lcd_shader_check/result.txt','w'))
  f:write(result); f:close()
  love.event.quit(ok and 0 or 1)
end
