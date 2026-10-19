-- tools/save_safety_check: every way a save used to be lost, simulated against
-- its OWN save identity (never the real saves).  Run with APPDATA pointed at a
-- scratch folder so even that identity stays off the system drive:
--   APPDATA=G:/Gen2Recomped/scratch_claude/save_safety/appdata ROOT=<repo> \
--     lovec tools/save_safety_check
function love.conf(t)
  t.identity = "Gen2Recomp_savesafetycheck"
  t.window = false
  t.modules.audio = false
  t.modules.sound = false
end
