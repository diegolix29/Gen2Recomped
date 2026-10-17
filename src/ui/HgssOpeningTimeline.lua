-- Durations/displacements from intro_movie_scene_1.c / scene_2.c.
-- State-transition overhead is omitted; application ticks run at 30 Hz.
local T={SKY=220,SCENE2=745,SCENE3=990,END=990+require('src.ui.HgssOpeningMontage').LENGTH}
T.SCENE4=T.END
T.FINAL_LENGTH=106
local function clamp(n,lo,hi) return math.max(lo,math.min(hi,n)) end
T.clamp=clamp
function T.at(frame)
  if frame>=T.SCENE3 then return require('src.ui.HgssOpeningMontage').at(frame-T.SCENE3) end
  if frame<T.SKY then return {scene='credits',bottom=frame>=110} end
  if frame<T.SCENE2 then
    local t=frame-T.SKY
    return {scene='sky',tick=t,scroll1=-32*clamp(t/240,0,1),
      scroll2=-16*clamp(t/240,0,1),credit=1-clamp(t/80,0,1),
      bird=t>=368 and t-368 or nil,white=clamp((t-458)/65,0,1),bottom=true}
  end
  local t=frame-T.SCENE2
  -- fly-in 56, transition 8, Ethan 90, fast pan 7, Lyra 66,
  -- downward pan 10, circular wipe 8. The grass continues behind them.
  local pan=32*clamp((t-64)/90,0,1)+64*clamp((t-154)/7,0,1)+32*clamp((t-161)/66,0,1)
  return {scene='trainers',tick=t,pan=pan,enter=192*clamp((t-56)/5,0,1),
    dropBack=128*clamp((t-227)/10,0,1),dropFront=64*clamp((t-227)/5,0,1),
    bottomBlack=clamp((t-56)/8,0,1),white=1-clamp(t/3,0,1),
    wipe=clamp((t-237)/8,0,1),bottom=false}
end
-- NANR playback mode 1 is forward once (clamp to the last result).
-- These opening resources all use that mode; don't loop their flybys.
function T.pose(sequences,name,index,tick)
  local seq=sequences and sequences[name] and sequences[name][index]
  if not seq then return nil end
  local frames=seq.frames or {};local elapsed=0
  for _,frame in ipairs(frames) do
    elapsed=elapsed+(frame.duration or 1)
    if tick<elapsed then return frame end
  end
  return frames[#frames]
end
return T
