-- WHERE THE FRAME WENT.
--
-- Reported from play as "currently getting a lot of lag", under a mod that
-- replaces the whole world pass with geometry of its own.  The boot trace says
-- how bad it is and says nothing about why:
--
--   1186 ms  frame 60     <- the launcher, ~50 fps
--   6931 ms  frame 120
--  17394 ms  frame 300    <- 17 fps
--  68153 ms  frame 600    <-  6 fps, and still falling
--
-- Which is a shape worth knowing -- it DEGRADES, so it is not a fixed cost --
-- and nothing else.  From outside the process there is no way to tell the
-- engine's own draw from a mod's world pass from a mod's event handler, and
-- guessing between them is how an afternoon disappears.
--
-- So: named sections, wall clock, accumulated over a window and reported as
-- one table.  Off by default and free when off -- `section` returns a closure
-- that does nothing, and the call sites are two lines each.
--
-- It measures WALL TIME, not GPU time.  A section that ends in a draw call
-- records the time to QUEUE that work, not to execute it; on a GPU-bound frame
-- the wait lands in whatever runs next (usually the present).  That is a real
-- limit and it is stated here rather than discovered later -- but it still
-- separates "a mod's handler is eating the CPU" from "the scene is too big",
-- which is the question a report like this one has to answer first.

local Logger = require("src.core.Logger")

local FrameProfile = {}

local on = false
local frames = 0
local total = {}        -- name -> seconds
local calls = {}        -- name -> count
local order = {}        -- first-seen order, so the report reads like the frame
local windowStart = 0

-- How many frames to gather before saying something.  Two seconds at 60fps,
-- and at 6fps -- the case this exists for -- twenty seconds, which is long
-- enough to be sure and short enough to sit through.
local WINDOW = 120

local clock = os.clock
if love and love.timer and love.timer.getTime then
  clock = love.timer.getTime
end

function FrameProfile.enabled() return on end

function FrameProfile.reset()
  frames, total, calls, order = 0, {}, {}, {}
  windowStart = clock()
end

function FrameProfile.setEnabled(want)
  want = want and true or false
  if want == on then return on end
  on = want
  FrameProfile.reset()
  if on then
    Logger.warn("frame profile: ON -- a report every %d frames. Sections are "
      .. "wall time to QUEUE work, so a GPU-bound frame shows up in whatever "
      .. "runs last, not in the draw that caused it.", WINDOW)
  else
    Logger.warn("frame profile: off")
  end
  return on
end

function FrameProfile.toggle()
  return FrameProfile.setEnabled(not on)
end

-- The measuring primitive.  Returns a function that closes the section; call
-- it, or drop it, and nothing is recorded -- a dropped closure cannot corrupt
-- the totals, which matters because half these call sites sit around a pcall
-- whose failure path is the interesting one.
--
-- The no-op when off is a shared closure rather than a new one per call: this
-- runs a few hundred times a second and must not be the thing it measures.
local function noop() end

function FrameProfile.section(name)
  if not on then return noop end
  local t0 = clock()
  return function()
    local dt = clock() - t0
    if total[name] == nil then
      total[name] = 0
      calls[name] = 0
      order[#order + 1] = name
    end
    total[name] = total[name] + dt
    calls[name] = calls[name] + 1
  end
end

-- The raw clock and a direct deposit, for a caller that cannot express its
-- measurement as one bracketed span.
--
-- The case that needs it is a HOOK CHAIN: each link calls `next` into the rest
-- of the chain, so a timer around one link charges it with everything
-- downstream.  What a reader wants is each link's OWN time, which is its total
-- minus whatever it spent below -- two numbers, subtracted, and no bracket can
-- do that on its own.
function FrameProfile.now()
  return clock()
end

function FrameProfile.add(name, seconds)
  if not on then return end
  if not (seconds and seconds > 0) then seconds = seconds or 0 end
  if total[name] == nil then
    total[name] = 0
    calls[name] = 0
    order[#order + 1] = name
  end
  total[name] = total[name] + seconds
  calls[name] = calls[name] + 1
end

-- A COUNT WITH NO TIME, for the number a report keeps needing and cannot
-- express: how MANY of something a phase did.  "cast: 114 ms" and "cast: 114
-- ms over 40 entities" are different findings -- the first is a slow pass and
-- the second is a crowd -- and the fix is different for each.  The count shows
-- up in the report's calls-per-frame column, where the reader is already
-- looking.
function FrameProfile.count(name, n)
  if not on then return end
  n = tonumber(n) or 1
  if total[name] == nil then
    total[name] = 0
    calls[name] = 0
    order[#order + 1] = name
  end
  calls[name] = calls[name] + n
end

-- Wrap a call in a section and hand back whatever it returned.  For the sites
-- where the body is one expression and an explicit close would need a local.
function FrameProfile.wrap(name, fn, ...)
  if not on then return fn(...) end
  local close = FrameProfile.section(name)
  local a, b, c, d = fn(...)
  close()
  return a, b, c, d
end

-- Called once per rendered frame, at the end.  Reports and starts over when
-- the window is full.
function FrameProfile.frame()
  if not on then return end
  frames = frames + 1
  if frames < WINDOW then return end
  local span = clock() - windowStart
  if span <= 0 then span = 1e-9 end
  -- sorted by cost, because that is the order the reader cares about, and the
  -- first-seen order is kept only to break ties stably
  local rank = {}
  for i, name in ipairs(order) do rank[name] = i end
  local list = {}
  for name in pairs(total) do list[#list + 1] = name end
  table.sort(list, function(a, b)
    if total[a] ~= total[b] then return total[a] > total[b] end
    return (rank[a] or 0) < (rank[b] or 0)
  end)
  local fps = frames / span
  Logger.report("frame profile: %d frames in %.2fs (%.1f fps, %.1f ms/frame)",
              frames, span, fps, span / frames * 1000)
  for _, name in ipairs(list) do
    local ms = total[name] / frames * 1000
    Logger.report("  %-34s %7.2f ms/frame  %5.1f%%  (%d calls/frame)",
                name, ms, total[name] / span * 100,
                math.floor(calls[name] / frames + 0.5))
  end
  -- WHAT IS NOT IN ANY SECTION, stated rather than left to subtraction.  On a
  -- GPU-bound frame this is most of it, and a reader who does not see the line
  -- assumes the sections add up to the frame and concludes the wrong thing.
  local named = 0
  for _, name in ipairs(list) do
    -- only top-level sections count toward the total; a nested one would be
    -- counted twice.  Nesting is marked with a leading space in the name.
    if name:sub(1, 1) ~= " " then named = named + total[name] end
  end
  Logger.report("  %-34s %7.2f ms/frame  %5.1f%%", "(unmeasured / present / GPU)",
              (span - named) / frames * 1000, (span - named) / span * 100)
  Logger.flush()
  FrameProfile.reset()
end

return FrameProfile
