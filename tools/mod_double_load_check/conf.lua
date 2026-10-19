-- tools/mod_double_load_check: see main.lua.  Never the real identity: the
-- runner sets IDENTITY (and APPDATA, so the save directory is a scratch
-- folder) for every scenario.
function love.conf(t)
  t.identity = os.getenv("IDENTITY") or "Gen2ModDoubleLoadCheck"
  t.window.width, t.window.height = 960, 600
  t.window.visible = false
  t.modules.audio = false
  t.modules.sound = false
end
