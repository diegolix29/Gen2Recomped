-- tools/walker_minigames_shot: the Pokewalker minigames, a few seconds of
-- scripted play, one screenshot. Its own identity (nothing real is read or
-- written) unless LAUNCHER=1, which builds the real launcher the way
-- tools/launcher_shot does (identity Gen2Recomp) and opens the hub on it.
function love.conf(t)
  t.identity = os.getenv("IDENTITY") or (os.getenv("LAUNCHER") == "1" and "Gen2Recomp" or "walker_minigames_shot")
  t.window.width = tonumber(os.getenv("W") or "1280")
  t.window.height = tonumber(os.getenv("H") or "800")
  t.window.visible = false
  t.modules.audio = false
  t.modules.sound = false
end
