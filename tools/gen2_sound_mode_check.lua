local Synth=require('src.core.ChipSynth')
local engine=Synth.newEngine({audio={}},{chip={channels={},waves={}}},{allowLoops=false})
engine.channels={{event={panLeft=true,panRight=false},sample=function() return 1 end}}
Synth.setStereo(true)
local l,r=engine:sampleStereo();assert(l==.25 and r==0,'stereo must preserve hardware panning')
Synth.setStereo(false)
l,r=engine:sampleStereo();assert(l==.25 and r==.25,'mono must send every channel to both speakers')
Synth.setStereo(true)
print('Gen2 mono/stereo hardware panning passed')
