-- Voxel world mode: the cooperative build budget.
--
-- Mesh building runs inside a plain coroutine that ChunkMesher pumps for
-- a few milliseconds a frame (there is no worker thread: LOVE's graphics
-- objects are main-thread only, and the build is pure Lua that slices
-- cleanly). The long loops in Structures and ChunkMesher call tick() as
-- they go; when the frame's slice is spent, tick() suspends the build
-- coroutine and the frame carries on rendering whatever is already
-- cached.
--
-- tick() is deliberately safe to call from ANY context: outside the pump
-- (headless tests, the pure geometry API, a driver poking a build
-- function directly) it recognises it is not inside the build coroutine
-- and does nothing, so synchronous callers keep their synchronous
-- behavior.

local B = { n = 0 }

local clock = (love and love.timer and love.timer.getTime) or os.clock

local deadline = math.huge
local buildCo = nil
local resources = nil

-- Enter/leave a pumped slice. `co` is the coroutine being resumed, so
-- tick() can tell the build apart from any other coroutine the engine
-- happens to be running (drivers are coroutines too).
function B.begin(co, seconds, owned)
  buildCo = co
  resources = owned
  deadline = clock() + seconds
end

function B.finish()
  buildCo = nil
  resources = nil
  deadline = math.huge
end

-- GPU buffers allocated by a suspended job need explicit cancellation
-- ownership. Waiting for userdata GC can exhaust handheld memory mid-walk.
function B.own(object)
  if resources and coroutine.running() == buildCo then resources[object] = true end
  return object
end
function B.disown(object)
  if resources then resources[object] = nil end
end
function B.release(owned)
  for object in pairs(owned or {}) do
    if object.release then pcall(object.release, object) end
    owned[object] = nil
  end
end

function B.expired()
  return clock() > deadline
end

-- Cheap enough to sprinkle through inner loops: one modulo most calls,
-- a clock read every fourth active call. Coarse rows must yield too.
function B.tick()
  local n = B.n + 1
  B.n = n
  if not buildCo or n % 4 ~= 0 then return end
  if buildCo and coroutine.running() == buildCo and clock() > deadline then
    coroutine.yield("budget")
  end
end

-- Like tick() but consults the clock every call -- for coarse loops
-- whose single iteration already costs milliseconds (mesh upload
-- slices), where tick()'s sampled clock checks would never fire.
function B.check()
  if buildCo and coroutine.running() == buildCo and clock() > deadline then
    coroutine.yield("budget")
  end
end

-- Being above the overworld is not evidence that the world is hidden:
-- battles and menus still draw it. Only a fully opaque warp fade qualifies.
function B.covered(top, transition)
  return type(top) == "table" and getmetatable(top) == transition
    and type(top.alpha) == "function" and top:alpha() >= 1 or false
end

-- A paced frame includes present/VSync wait. When it is keeping pace, use
-- measured world submission work plus room for the host's UI/update work.
-- Over-budget frames retain the conservative elapsed-time estimate.
function B.frameCost(dt,lastSpend,drawCost,target)
  local elapsed=math.max(0,dt-lastSpend)
  if drawCost and dt<=target*1.08 then
    return math.max(0,drawCost)+0.003
  end
  return elapsed
end

return B
