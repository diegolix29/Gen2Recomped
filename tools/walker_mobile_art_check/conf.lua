function love.conf(t)
 t.identity=os.getenv('IDENTITY') or 'WalkerMobileArtRegression'
 t.window.width=640;t.window.height=360;t.window.visible=false;t.window.vsync=0
 t.modules.audio=false;t.modules.sound=false
end
