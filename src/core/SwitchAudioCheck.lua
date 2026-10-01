-- Test the native output backend separately from ROM decoding and synthesis.
local Check={}
function Check.run()
  if not require('src.core.Platform').isNX() then return end
  local lines={}
  local function record(label,fn)
    local ok,value=pcall(fn)
    lines[#lines+1]=label..': '..(ok and tostring(value) or ('ERROR '..tostring(value)))
  end
  record('audio module',function() return love.audio~=nil end)
  record('master volume',function() return love.audio.getVolume() end)
  -- Null-audio Sources accept construction and play but never register with
  -- getSourceCount. Silence tests that without playing an unsolicited tone.
  record('static backend',function()
    local data=love.sound.newSoundData(4800,48000,16,2)
    local source=love.audio.newSource(data,'static')
    local playing=source:play()
    local count=love.audio.getSourceCount()
    source:stop();source:release()
    assert(count>0,'native backend registered no playing source (null audio or unavailable device)')
    return 'OK; play='..tostring(playing)..'; count='..count
  end)
  record('queue backend',function()
    local source=love.audio.newQueueableSource(48000,16,2,4)
    local queued=source:queue(love.sound.newSoundData(4800,48000,16,2))
    source:play()
    local count=love.audio.getSourceCount()
    source:stop();source:release()
    assert(count>0,'native queue registered no playing source')
    return 'OK; queue='..tostring(queued)..'; count='..count
  end)
  local report=table.concat(lines,'\n')..'\n'
  love.filesystem.write('switch-audio-check.txt',report)
  require('src.core.Logger').info('Switch audio backend check: %s',report)
end
return Check
