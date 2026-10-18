-- tools/walker_art_check: where the Pokewalker finds its Pokemon pictures
-- (WalkerArt), in its OWN identity -- never the real saves.
function love.conf(t)
  t.identity = "Gen2Recomp_walkerartcheck"
  t.window.width, t.window.height = 64, 64
  t.window.title = "walker art check"
  t.modules.audio = false
  t.modules.sound = false
end
