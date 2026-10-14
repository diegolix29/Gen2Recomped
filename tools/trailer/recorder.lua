-- tools/trailer/recorder.lua -- stream rendered frames into ffmpeg, one MP4 per
-- segment, off the main thread. The same writer capture.lua carries inline,
-- as a module for drivers that record something other than the overworld.
--
--   local Rec = dofile("tools/trailer/recorder.lua")({ out = OUT, ffmpeg = FFMPEG })
--   Rec.start("editor_open")    -- later frames go to <out>/editor_open.mp4
--   Rec.frame()                 -- call once per logic step; keeps every STEPth
--   Rec.stop()                  -- segment over; the next start opens a new file
--   Rec.finish()                -- drain and close ffmpeg (end of the run)
--
-- Also pins love.timer.getTime to a 1/60-per-update frame clock, so animation
-- in the footage is even however slowly the window renders.
return function(opts)
  opts = opts or {}
  local OUT = assert(opts.out, "recorder: out folder")
  local FFMPEG = opts.ffmpeg or "ffmpeg"
  local CRF = tostring(opts.crf or 14)
  local STEP = opts.step or 2

  local realGetTime = love.timer.getTime
  local clock = realGetTime()
  local realUpdate = love.update
  love.update = function(dt) clock = clock + 1 / 60; return realUpdate(dt) end
  love.timer.getTime = function() return clock end

  local WRITER = [[
    local ch, ffmpeg, crf, fps = ...
    require("love.image")
    local pipe, current
    local function close()
      if pipe then pipe:close(); pipe = nil end
      current = nil
    end
    while true do
      local job = ch:demand()
      if job == "stop" then close(); return end
      if job.path ~= current then
        close()
        local w, h = job.img:getDimensions()
        local cmd = ('"%s" -y -loglevel error -f rawvideo -pix_fmt rgba -s %dx%d -r %d -i - '
          .. '-c:v libx264 -preset slow -crf %s -pix_fmt yuv420p -movflags +faststart "%s.mp4"')
          :format(ffmpeg, w, h, fps, crf, job.path)
        if package.config:sub(1, 1) == "\\" then cmd = '"' .. cmd .. '"' end
        pipe = io.popen(cmd, "wb")
        current = job.path
      end
      if pipe then pipe:write(job.img:getString()) end
      job.img:release()
    end
  ]]
  local queue = love.thread.getChannel("recorder_frames")
  local thread = love.thread.newThread(WRITER)
  thread:start(queue, FFMPEG, CRF, math.floor(60 / STEP))

  local R = { frames = 0 }
  local path, f = nil, 0
  function R.start(name)
    path, f, R.frames = OUT .. "/" .. name, 0, 0
  end
  function R.stop()
    if path then print(("[recorder] %s: %d frames"):format(path, R.frames)) end
    path = nil
  end
  function R.frame()
    if not path then return end
    f = f + 1
    if f % STEP ~= 0 then return end
    R.frames = R.frames + 1
    while queue:getCount() > 24 do realGetTime(); love.timer.sleep(0.004) end
    local p = path
    love.graphics.captureScreenshot(function(img) queue:push({ path = p, img = img }) end)
  end
  function R.finish()
    R.stop()
    queue:push("stop")
    thread:wait()
    love.timer.getTime, love.update = realGetTime, realUpdate
  end
  return R
end
