-- main.c waits for two VBlanks per application frame. FixedStep runs at
-- 60 Hz, so these overlays need their own 30 Hz animation clock.
local C={}
function C.step(state,game,dt)
  local speed=game.logicSpeed and game:logicSpeed() or 1
  state.nativeRemainder=(state.nativeRemainder or 0)+(dt or 1/60)*30/math.max(1,speed)
  local ticks=math.floor(state.nativeRemainder+1e-9)
  state.nativeRemainder=state.nativeRemainder-ticks
  return ticks
end
return C
