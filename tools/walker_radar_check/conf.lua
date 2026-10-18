-- tools/walker_radar_check: the Poke Radar's per-game pools, legendaries and
-- their trip home, against a scratch identity (never the real saves).
function love.conf(t)
  t.identity = "Gen2Recomp_walkerradarcheck"
  t.window = false
  t.modules.audio = false
  t.modules.sound = false
end
