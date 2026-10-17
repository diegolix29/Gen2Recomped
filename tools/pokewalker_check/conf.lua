-- tools/pokewalker_check: the Pokewalker's rules and its save link, against a
-- scratch slot in its OWN identity (never the real saves).
function love.conf(t)
  t.identity = "Gen2Recomp_walkercheck"
  t.window = false
  t.modules.audio = false
  t.modules.sound = false
end
