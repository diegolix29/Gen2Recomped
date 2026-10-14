-- tools/gen4_sound_effects_check.lua
--
-- PLATINUM SOUND EFFECTS, BY THE CARTRIDGE'S OWN NAMES.
--
--   python tools/run_lua_check.py tools/gen4_sound_effects_check.lua [rom] [decomp]
--
-- 1. Every sequence the ROM's SDAT SYMB block names resolves through
--    Sound.seDef by name and by id.
-- 2. With a pokeplatinum checkout (default C:/Users/cedri/AppData/Local/Temp/ppt),
--    every decomp `<file>_sseq[_N]` constant (nitrosfx -naix numbering over
--    res/sound/pl_sound_data.json) resolves to the same sequence the decomp
--    builds it as -- SE_CONFIRM_sseq_3 is SEQ_SE_DP_SELECT, and so on.
-- 3. Every "SEQ_SE_*" literal in the rebuilt Platinum screens resolves, and
--    Sound.playSe reaches a NitroAudio player that starts and renders
--    non-silent PCM (the audio device is stubbed; the synth is real).
-- 4. SE player slots: two effects on a one-sequence SE player cut each other
--    off; an explicit handle lets one effect ring on several players.
package.path = './?.lua;' .. package.path

local romPath = arg and arg[2] or 'Pokemon - Platinum Version (USA) (Rev 1).nds'
local decomp = arg and arg[3] or 'C:/Users/cedri/AppData/Local/Temp/ppt'

local R = assert(require('src.import.NdsRom').open(romPath))
local S = require('src.import.Gen4Sdat')
local raw = assert(R:read(S.PATH)); local arc = assert(S.open(raw))
local audio = require('src.import.Gen4Audio').catalogue(arc)
audio.ndsArchive = 'test-platinum-sdat'
local data = { audio = audio }

-- the audio device, stubbed: a queueable source that "plays" whatever it is
-- handed, and SoundData that measures what the synth wrote into it
local energy = 0
local function queue()
  local q = { playing = false, vol = 1 }
  function q:setVolume(v) self.vol = v end
  function q:getVolume() return self.vol end
  function q:setFilter() end
  function q:stop() self.playing = false end
  function q:pause() self.playing = false end
  function q:play() self.playing = true end
  function q:isPlaying() return self.playing end
  function q:getFreeBufferCount() return 0 end -- the check renders blocks itself
  function q:queue() end
  return q
end
love = {
  filesystem = { read = function(path) if path == 'test-platinum-sdat' then return raw end end },
  audio = { newQueueableSource = queue },
  sound = { newSoundData = function()
    return { setSample = function(_, _, _, v) energy = energy + math.abs(v) end }
  end },
}
package.loaded['src.render.Assets'] = { resolve = function(p) return p end, register = function() end }

local Sound = require('src.core.Sound')
local checks, failures = 0, {}
local function check(ok, msg) checks = checks + 1; if not ok then failures[#failures + 1] = msg end end

-- 1. the ROM's names and ids
local named = 0
for i = 0, S.count(arc, S.SEQ) - 1 do
  local name = S.name(arc, S.SEQ, i)
  if name and S.sequence(arc, i) then
    named = named + 1
    local a, b = Sound.seDef(data, name), Sound.seDef(data, i)
    check(a and a.nds == i and b and b.nds == i, ('%s (%d) does not resolve'):format(name, i))
  end
end
check(named > 1000, 'SDAT SYMB names too few sequences: ' .. named)
print(('%d ROM sequences resolve by SYMB name and id'):format(named))

-- the SE players the INFO block declares
local se1 = S.player(arc, S.sequence(arc, Sound.seDef(data, 'SEQ_SE_DP_SELECT').nds).player)
check(se1 and se1.maxSequences == 1, 'SEQ_SE_DP_SELECT is not on a one-sequence SE player')
print(('SEQ_SE_DP_SELECT plays on %s (max %d sequence)'):format(tostring(se1 and se1.name), se1 and se1.maxSequences or -1))

-- 2. the decomp's file constants
local p = io.popen(('git -C "%s" show HEAD:res/sound/pl_sound_data.json 2>nul'):format(decomp))
local json = p and p:read('*a') or ''
if p then p:close() end
if #json > 0 then
  local section = json:match('"seqInfo"%s*:%s*(%b[])') or ''
  local idx, hits, aliases = -1, {}, 0
  for entry in section:gmatch('%b{}') do
    idx = idx + 1
    local file = entry:match('"fileName"%s*:%s*"([^"]+)"')
    if file then
      local n = hits[file] or 0; hits[file] = n + 1
      local alias = file:gsub('[^%w_]', '_') .. (n > 0 and ('_' .. n) or '')
      local def = Sound.seDef(data, alias)
      aliases = aliases + 1
      check(def and def.nds == idx, ('decomp %s should be sequence %d, resolves to %s')
        :format(alias, idx, tostring(def and def.nds)))
    end
  end
  check(aliases > 1000, 'decomp seqInfo parsed too few entries: ' .. aliases)
  print(('%d decomp <file>_sseq[_N] constants resolve to the decomp\'s own sequence ids'):format(aliases))
else
  print('decomp checkout not found; skipped the <file>_sseq constant cross-check')
end
check((Sound.seDef(data, 'SE_CONFIRM_sseq_3') or {}).name == 'SEQ_SE_DP_SELECT', 'SE_CONFIRM_sseq_3 ~= SEQ_SE_DP_SELECT')

-- 3. the screens
local SCREENS = {
  'Gen4ContestDance', 'Gen4ContestActing', 'Gen4ContestScreen', 'Gen4PoffinCooking',
  'Gen4PoffinCase', 'Gen4PoffinFeed', 'Gen4Poketch', 'Gen4EvolutionState',
  'Gen4MiningScreen', 'Gen4TrainerCard', 'Gen4BagMenu', 'Gen4SummaryMenu',
  'Gen4NamingScreen', 'Gen4Options', 'Gen4StartMenu', 'Gen4ShopMenu',
  'Gen4Pokedex', 'Gen4HallOfFame',
}
local used, perScreen = {}, {}
for _, screen in ipairs(SCREENS) do
  local f = assert(io.open('src/ui/' .. screen .. '.lua', 'rb'))
  local src = f:read('*a'); f:close()
  local n = 0
  for name in src:gmatch('"(SEQ_SE_[%w_]+)"') do
    if not used[name] then used[name] = screen end
    n = n + 1
  end
  perScreen[#perScreen + 1] = ('%s %d'):format(screen, n)
end
local names = {}
for name in pairs(used) do names[#names + 1] = name end
table.sort(names)
local audible = 0
for _, name in ipairs(names) do
  local def = Sound.seDef(data, name)
  check(def ~= nil, ('%s (used by %s) is not a ROM sequence'):format(name, used[name]))
  if def then
    local src = Sound.playSe(data, name)
    check(src and src:isPlaying(), name .. ': playSe did not start a player')
    if src then
      local before = energy
      for _ = 1, 120 do
        if not src.running then break end
        src:render()
        if energy > before then break end
      end
      check(energy > before, name .. ': rendered silence')
      if energy > before then audible = audible + 1 end
      src:stop()
    end
  end
end
print(('%d distinct SEQ_SE names in the screens (%s); %d render audible PCM')
  :format(#names, table.concat(perScreen, ', '), audible))

-- 4. players
local a = Sound.playSe(data, 'SEQ_SE_DP_SELECT')
local b = Sound.playSe(data, 'SEQ_SE_DP_DECIDE')
local sameSlot = S.sequence(arc, Sound.seDef(data, 'SEQ_SE_DP_DECIDE').nds).player
  == S.sequence(arc, Sound.seDef(data, 'SEQ_SE_DP_SELECT').nds).player
if sameSlot then
  check(a and b and not a:isPlaying() and b:isPlaying(), 'a second effect on PLAYER_SE_x did not take the slot')
end
local h1 = Sound.playSe(data, 'SEQ_SE_DP_BADGE_C', { handle = 1, pitch = 1.5 })
local h2 = Sound.playSe(data, 'SEQ_SE_DP_BADGE_C', { handle = 2 })
check(h1 and h2 and h1 ~= h2 and h1:isPlaying() and h2:isPlaying(), 'handled effects did not ring together')
check(h1 and h1:getPitch() == 1.5 and Sound.isSePlaying(data, 'SEQ_SE_DP_BADGE_C', 1), 'handle pitch/state lost')
check(Sound.playSe(data, 'SEQ_SE_NOT_A_SOUND') == nil, 'an unknown name played something')

if #failures > 0 then error(#failures .. ' of ' .. checks .. ' checks failed:\n  ' .. table.concat(failures, '\n  ')) end
print(checks .. ' sound effect checks passed')
