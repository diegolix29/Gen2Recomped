local files={['gold/assets/generated/audio/programs.bin']='gold-pcm',
 ['crystal/assets/generated/audio/programs.bin']='crystal-pcm',
 ['platinum/assets/generated/gen4/cries/387.wav']='cry',
 ['platinum/assets/generated/gen4/sound/pl_sound_data.sdat']='sdat'}
love={filesystem={read=function(p) return files[p] end,
 getInfo=function(p) return files[p] and {type='file'} end},
 audio={newSource=function(p) assert(files[p],'native decoder received unresolved path '..p);return p end},
 sound={newSoundData=function(p) assert(files[p],'SoundData decoder received unresolved path '..p);return p end}}
local W=require('src.core.WorkerFs')
assert(W.read('gold/','assets/generated/audio/programs.bin')=='gold-pcm')
assert(W.read('crystal/','assets/generated/audio/programs.bin')=='crystal-pcm')
local C=require('src.import.CacheFs')
assert(C.installPrefixShim('platinum/'))
assert(love.audio.newSource('assets/generated/gen4/cries/387.wav')=='platinum/assets/generated/gen4/cries/387.wav')
assert(love.sound.newSoundData('assets/generated/gen4/cries/387.wav')=='platinum/assets/generated/gen4/cries/387.wav')
assert(love.filesystem.read('assets/generated/gen4/sound/pl_sound_data.sdat')=='sdat')
assert(C.installPrefixShim('gold/'))
assert(love.filesystem.read('assets/generated/audio/programs.bin')=='gold-pcm')
assert(C.installPrefixShim('crystal/'))
assert(love.filesystem.read('assets/generated/audio/programs.bin')=='crystal-pcm')
print('7 Switch worker and native decoder path checks passed')
