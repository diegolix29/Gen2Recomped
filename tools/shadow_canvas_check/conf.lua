function love.conf(t)
 t.identity='VoxelShadowCanvasCheck';t.window.visible=false;t.modules.audio=false
 if love.getVersion()>=12 then t.graphics.renderers={'opengl'} end
end
