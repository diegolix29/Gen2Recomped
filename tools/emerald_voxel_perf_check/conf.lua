function love.conf(t)
 t.identity=os.getenv("IDENTITY") or "EmeraldVoxelPerfCheck"
 t.window.width=800;t.window.height=650;t.window.visible=false;t.window.vsync=0
 t.modules.audio=false;t.modules.sound=false
 if os.getenv("PERF_BACKEND") then t.graphics.renderers={os.getenv("PERF_BACKEND")} end
end
