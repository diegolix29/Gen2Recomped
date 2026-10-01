local report
package.loaded['src.core.Platform']={isNX=function() return true end}
package.loaded['src.core.Logger']={info=function() end}
local count=0
local function source()
 return {play=function() count=1;return true end,stop=function() count=0 end,
 release=function() end,queue=function() return true end}
end
love={audio={getVolume=function() return 1 end,getSourceCount=function() return count end,
 newSource=source,newQueueableSource=source},sound={newSoundData=function() return {} end},
 filesystem={write=function(_,text) report=text;return true end}}
local Check=require('src.core.SwitchAudioCheck')
Check.run();assert(report:find('static backend: OK',1,true) and report:find('queue backend: OK',1,true))
love.audio.getSourceCount=function() return 0 end
Check.run();assert(report:find('static backend: ERROR',1,true) and report:find('queue backend: ERROR',1,true))
print('Switch audio output diagnostic distinguishes active and null backends')
