-- tools/walker_econ_check: the Monster Walker's economy (WalkerEconomy,
-- WalkerShop) against scratch saves in its OWN identity -- never the real saves.
function love.conf(t)
  t.identity = "Gen2Recomp_walkeconcheck"
  t.window = false
  t.modules.audio = false
  t.modules.sound = false
end
