-- tools/gen4_sound_effects_render/main.lua
--
-- PLATINUM SOUND EFFECTS, RENDERED TO WAV through the real NitroAudio synth
-- (LOVE SoundData, the ROM's SBNK/SWAR instruments), reached the way a screen
-- reaches them: Sound.playSe by SYMB name or decomp constant.  Each effect is
-- written to the LOVE save directory (bt_gen4/se_<name>.wav) and must be
-- non-silent; then one is played on a real LOVE audio Source for a moment.
--
--   "C:/Program Files/LOVE/love.exe" tools/gen4_sound_effects_render [rom]
--   (run from the repo root, which holds the Platinum ROM by default)

local EFFECTS = { "SEQ_SE_DP_SELECT", "SE_CONFIRM_sseq_3", "SEQ_SE_DP_DECIDE",
  "SEQ_SE_DP_CARD5", "SEQ_SE_DP_BADGE_C", "SEQ_SE_DP_CON_021", "SEQ_SE_DP_UG_002",
  "SEQ_SE_DP_KIRAKIRA4", "SEQ_SE_DP_W025" }

local live, elapsed, failed

local function le(v, n)
  local out = {}
  for i = 1, n do out[i] = string.char(v % 256); v = math.floor(v / 256) end
  return table.concat(out)
end

local function wav(frames, rate)
  local pcm = {}
  for i, s in ipairs(frames) do
    local v = math.floor(math.max(-1, math.min(1, s)) * 32767 + 0.5)
    if v < 0 then v = v + 65536 end
    pcm[i] = le(v, 2)
  end
  local body = table.concat(pcm)
  return "RIFF" .. le(36 + #body, 4) .. "WAVEfmt " .. le(16, 4) .. le(1, 2) .. le(2, 2)
    .. le(rate, 4) .. le(rate * 4, 4) .. le(4, 2) .. le(16, 2) .. "data" .. le(#body, 4) .. body
end

function love.load(args)
  package.path = love.filesystem.getWorkingDirectory() .. "/?.lua;" .. package.path
  local ok, why = pcall(function()
    local rom = args and args[1] or "Pokemon - Platinum Version (USA) (Rev 1).nds"
    local R = assert(require("src.import.NdsRom").open(rom))
    local S = require("src.import.Gen4Sdat")
    local raw = R:read(S.PATH); R:close()
    local audio = require("src.import.Gen4Audio").catalogue(assert(S.open(raw)))
    audio.ndsArchive = "test-platinum-sdat"
    local read = love.filesystem.read
    love.filesystem.read = function(path, ...)
      if path == "test-platinum-sdat" then return raw end
      return read(path, ...)
    end
    package.loaded["src.render.Assets"] = { resolve = function(p) return p end, register = function() end }
    local Sound = require("src.core.Sound")
    local data = { audio = audio }
    for _, key in ipairs(EFFECTS) do
      local src = assert(Sound.playSe(data, key), key .. ": playSe started nothing")
      src:stop()
      -- render it ourselves, block by block, to its end (or 4 s)
      src.queue:stop(); src.running = true; src.ended = false; src.voices = {}
      src.tracks = { [0] = { at = src.start, wait = 0, program = 0, volume = 127, expression = 127,
        pan = 64, transpose = 0, bend = 0, bendRange = 2, noteWait = true, calls = {}, loops = {} } }
      src.tickPhase = 1
      local frames, peak, sum = {}, 0, 0
      for _ = 1, 256 do
        local block = src:render()
        for i = 0, block:getSampleCount() - 1 do
          local l, r = block:getSample(i, 1), block:getSample(i, 2)
          frames[#frames + 1], frames[#frames + 2] = l, r
          peak = math.max(peak, math.abs(l), math.abs(r)); sum = sum + l * l + r * r
        end
        if src.ended and #src.voices == 0 then break end
      end
      local seconds = #frames / 2 / 32768
      local rms = math.sqrt(sum / math.max(1, #frames))
      local file = ("se_%s.wav"):format(key)
      love.filesystem.write(file, wav(frames, 32768))
      print(("%-22s -> %-20s %.2fs peak %.3f rms %.4f  %s/%s"):format(key, Sound.seName(data, key),
        seconds, peak, rms, love.filesystem.getSaveDirectory(), file))
      assert(peak > 0.01, key .. " rendered silence")
    end
    live = assert(Sound.playSe(data, "SEQ_SE_DP_CARD5"))
    assert(live.queue:isPlaying(), "LOVE audio source failed to play the effect")
    elapsed = 0
  end)
  if not ok then print(why); failed = true; love.event.quit(1) end
end

function love.update(dt)
  if not live or failed then return end
  elapsed = elapsed + dt
  require("src.audio.NitroAudio").update()
  if elapsed >= 0.5 then
    print("SEQ_SE_DP_CARD5 sounded on a real LOVE queueable Source; " .. #EFFECTS .. " effects rendered non-silent")
    live:stop()
    love.event.quit(0)
  end
end
