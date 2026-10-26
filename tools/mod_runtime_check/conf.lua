function love.conf(t)
 t.identity='Love12ModRuntimeCheck';t.window.visible=false;t.modules.audio=false;t.modules.sound=false
 if love.getVersion()>=12 then t.graphics.renderers={'opengl'} end
end
