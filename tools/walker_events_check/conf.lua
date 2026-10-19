-- tools/walker_events_check: the Watt Shop's Events shelf against SCRATCH saves
-- (G:/Gen2Recomped/scratch_claude/walker_events or $SCRATCH), never the real ones.
function love.conf(t)
  t.identity = "Gen2Recomp_walkereventscheck"
  t.window = false
  t.modules.audio = false
  t.modules.sound = false
end
