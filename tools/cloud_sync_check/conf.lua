-- tools/cloud_sync_check: src/import/CloudSync.lua's rules, against a scratch
-- sync folder and its OWN save identity (never the real saves).
function love.conf(t)
  t.identity = "Gen2Recomp_cloudcheck"
  t.window = false
  t.modules.audio = false
  t.modules.sound = false
end
