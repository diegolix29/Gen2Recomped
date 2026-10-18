-- tools/launcher_shot: the launcher alone, a few frames, one screenshot.
-- Identity Gen2Recomp so it sees the real install's imported games; W / H set
-- the window (default 1280x800).
function love.conf(t)
  t.identity = os.getenv("IDENTITY") or "Gen2Recomp"
  t.window.width = tonumber(os.getenv("W") or "1280")
  t.window.height = tonumber(os.getenv("H") or "800")
  t.window.visible = false
  t.modules.audio = false
  t.modules.sound = false
end
