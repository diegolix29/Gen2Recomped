-- HOW MANY FRAMES HAVE BEEN DRAWN.
--
-- A number nobody needed until a mod's budgeted background build turned up as
-- 46 ms of every frame.  The build itself was reasonable -- five asset caches,
-- one small step each, the usual way to load something large without a stall.
-- What made it expensive is WHERE it was stepped: on `input.step`, the
-- fixed-step logic seam, which runs as many times per frame as the accumulator
-- has ticks to catch up on.  At 10fps that is five or six steps a frame
-- instead of one, which lowers the frame rate, which buys more catch-up ticks,
-- which steps it more.
--
-- The seam was the right one for input and the wrong one for work measured in
-- frames, and there was no per-frame counter to key that work off -- so this
-- is that counter.  Incremented once in love.run, after the frame is actually
-- on screen, so "the number changed" means "a frame happened" rather than "the
-- logic advanced".
--
-- For a mod the shape is:
--
--   local Frames = mod.engineRequire("src.core.Frames")
--   local lastStep = -1
--   ...
--   if Frames.n ~= lastStep then lastStep = Frames.n; stepMyCaches() end
--
-- Plain field rather than a getter because it is read in hot loops and a
-- function call is the kind of cost this module exists to talk about.

local Frames = { n = 0 }

function Frames.tick()
  Frames.n = Frames.n + 1
  return Frames.n
end

-- True at most once per drawn frame for a given owner's marker.  Sugar over
-- the pattern above, for a caller that would rather not keep its own local:
-- pass any table and a key, and it returns true the first time it is asked in
-- each frame.
function Frames.once(owner, key)
  if type(owner) ~= "table" then return true end
  if owner[key] == Frames.n then return false end
  owner[key] = Frames.n
  return true
end

return Frames
