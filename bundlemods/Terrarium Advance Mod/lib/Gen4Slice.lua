-- Gen4Slice: one land build spread over several frames.
--
-- WHY THIS EXISTS
--
-- Gen4Rocks, Gen4Fence, Gen4Bump and Gen4Water each built a whole land in one
-- call, after asking Gen4Budget whether there was room. The budget can only
-- say no BEFORE a build starts, so a land that takes 40-60 ms (the PerfOverlay
-- showed rocks 46, fence 60) was one dropped frame however small the budget.
-- Gen4Trees already avoided that with a coroutine; this is the same idea for
-- the others.
--
-- HOW
--
--   local job = Slice.start(buildLand, ground, land)
--   local done, ok, result = Slice.step(job, seconds)
--
-- runs the build in a coroutine until it finishes or `seconds` have passed.
-- The build gives control back at its own `Slice.check()` calls (put in the
-- per-rock / per-post / per-triangle helpers), so the slice boundary falls
-- between small pieces of work. Called outside a job, `check` does nothing,
-- so the helpers behave exactly as before when something builds directly.
--
-- `Slice.newMesh(verts, map)` is Voxel3D.newMesh for a big table mesh: inside a
-- job the vertex tables are copied into a ByteData a few thousand at a time,
-- with checks between, and uploaded in one setVertices(Data). Outside a job, or
-- without the FFI, it is Voxel3D.newMesh itself.

local V = ...
local Voxel3D = V.require("Voxel3D")

local Slice = {}

local clock = (love and love.timer and love.timer.getTime) or os.clock
local current, deadline = nil, math.huge

local okFfi, ffi = pcall(require, "ffi")
if not okFfi or type(ffi) ~= "table" or not ffi.cast then ffi = nil end

-- Yield if this is a job's coroutine and its slice is spent.
function Slice.check()
  if current == nil or clock() < deadline then return end
  local co = coroutine.running()
  if co == current then coroutine.yield() end
end

function Slice.inJob()
  return current ~= nil and coroutine.running() == current
end

function Slice.start(fn, ...)
  local n, args = select("#", ...), { ... }
  return { co = coroutine.create(function() return fn(unpack(args, 1, n)) end) }
end

-- -> done, ok, result. `done` false means "call again next frame".
function Slice.step(job, seconds)
  local prevCurrent, prevDeadline = current, deadline
  current, deadline = job.co, clock() + math.max(0.0005, seconds or 0.002)
  local okR, res = coroutine.resume(job.co)
  current, deadline = prevCurrent, prevDeadline
  if not okR then return true, false, res end
  if coroutine.status(job.co) == "dead" then return true, true, res end
  return false
end

local function ptrOf(data, ctype)
  for _, name in ipairs({ "getFFIPointer", "getPointer" }) do
    local f = data[name]
    if f then
      local ok, p = pcall(f, data)
      if ok and p then return ffi.cast(ctype, p) end
    end
  end
  return nil
end

local CHUNK = 2048
local broken = false

function Slice.newMesh(verts, map)
  local nv = #verts
  if nv == 0 then return nil end
  if not (ffi and not broken and Slice.inJob() and love.data and love.data.newByteData) then
    return Voxel3D.newMesh(verts, map)
  end
  local okV, vd = pcall(love.data.newByteData, nv * 28)
  local out = okV and ptrOf(vd, "float*")
  if not out then broken = true; return Voxel3D.newMesh(verts, map) end
  local o = 0
  for i = 1, nv do
    local v = verts[i]
    out[o], out[o + 1], out[o + 2] = v[1] or 0, v[2] or 0, v[3] or 0
    out[o + 3], out[o + 4] = v[4] or 0, v[5] or 0
    out[o + 5], out[o + 6] = v[6] or 1, v[7] or 0
    o = o + 7
    if i % CHUNK == 0 then Slice.check() end
  end
  local md, itype
  local ni = map and #map or 0
  if ni > 0 then
    local wide = nv > 65535
    itype = wide and "uint32" or "uint16"
    local okM, d = pcall(love.data.newByteData, ni * (wide and 4 or 2))
    local ip = okM and ptrOf(d, wide and "uint32_t*" or "uint16_t*")
    if not ip then broken = true; return Voxel3D.newMesh(verts, map) end
    for i = 1, ni do
      ip[i - 1] = map[i] - 1
      if i % (CHUNK * 3) == 0 then Slice.check() end
    end
    md = d
  end
  local okN, mesh = pcall(love.graphics.newMesh, Voxel3D.FORMAT, nv, "triangles", "static")
  local good = okN and mesh and pcall(mesh.setVertices, mesh, vd)
  if good and md then good = pcall(mesh.setVertexMap, mesh, md, itype) end
  pcall(vd.release, vd)
  if md then pcall(md.release, md) end
  if not good then
    if okN and mesh then pcall(mesh.release, mesh) end
    broken = true
    return Voxel3D.newMesh(verts, map)
  end
  return mesh
end

-- The loop every one of these effects runs per land, made cooperative.
-- `state` is the module's own table (holds the one job in flight);
-- `build(ground, land)` the module's buildLand. Returns the finished entry,
-- or nil while it is still building (or when the budget refused to start).
function Slice.landStep(state, Budget, warm, kind, ground, land, build)
  local job = state.job
  -- a job whose land left the window is no longer stepped by anyone: drop it
  if job and clock() - (job.stepped or 0) > 0.5 and (job.land ~= land or job.ground ~= ground) then
    state.job, job = nil, nil
  end
  if job and (job.land ~= land or job.ground ~= ground) then
    -- only the job for THIS land is stepped here; a job for another land
    -- keeps waiting for its own turn in the loop
    return nil, "busy"
  end
  if not job then
    if not Budget.allow(warm) then return nil, "refused" end
    job = Slice.start(build, ground, land)
    job.land, job.ground = land, ground
    state.job = job
  end
  local room = 0.002
  if type(Budget.remaining) == "function" then
    local okR, r = pcall(Budget.remaining, warm)
    if okR and tonumber(r) then room = math.max(0.001, r) end
  end
  local t0 = clock()
  job.stepped = t0
  local done, ok, result = Slice.step(job, room)
  Budget.charge(t0, kind)
  if not done then return nil, "building" end
  state.job = nil
  if not ok then return false, result end
  return result
end

return Slice
