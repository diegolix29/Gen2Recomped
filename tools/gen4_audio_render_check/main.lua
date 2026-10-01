local player,elapsed
function love.load()
 package.path=love.filesystem.getWorkingDirectory()..'/?.lua;'..package.path
 local ok,why=pcall(function()
  local r=assert(require('src.import.NdsRom').open('Pokemon - Platinum Version (USA) (Rev 1).nds'))
  local S=require('src.import.Gen4Sdat');local raw=r:read(S.PATH);r:close()
  local arc=assert(S.open(raw));local audio=require('src.import.Gen4Audio').catalogue(arc)
  audio.ndsArchive='test-platinum-sdat'
  local read=love.filesystem.read
  love.filesystem.read=function(path,...) if path=='test-platinum-sdat' then return raw end return read(path,...) end
  package.loaded['src.render.Assets']={resolve=function(path) return path end,register=function() end}
  local Sound=require('src.core.Sound');local data={audio=audio,pokemon={[387]={name='TURTWIG'}}}
  local effect=Sound.play(data,1500)
  assert(effect and effect:isPlaying(),'numeric native sound effect failed to start')
  Sound.stop(1500);assert(not effect:isPlaying(),'numeric native sound effect failed to stop')
  local sample=S.samples(arc,S.bank(arc,387).waves[1])[1]
  local wav=assert(S.wav(arc,sample));local source=love.audio.newSource
  love.audio.newSource=function(file,...)
   if file=='test-turtwig.wav' then return source(love.filesystem.newFileData(wav,file),'static') end
   return source(file,...)
  end
  audio.cries={TURTWIG={file='test-turtwig.wav'}}
  local cry=assert(Sound.playCry(data,387),'numeric native species cry failed to resolve')
  assert(cry:isPlaying(),'native cry failed to play');cry:stop()
  player=require('src.audio.NitroAudio').new({audio=audio},audio.songs.SEQ_TITLE01)
  player:setVolume(0.25);player:play();assert(player.queue:isPlaying(),'LOVE audio source failed to play');elapsed=0
 end)
 if not ok then print(why);love.event.quit(1) end
end
function love.update(dt)
 if not player then return end
 elapsed=elapsed+dt;player:update()
 if elapsed>=1 then
  local playing=player.queue:isPlaying();player:stop()
  print(playing and 'Native music, numeric effect start/stop, and numeric species cry passed on real LOVE audio Sources' or 'LOVE playback stopped unexpectedly')
  love.event.quit(playing and 0 or 1)
 end
end
