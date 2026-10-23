-- ORASActorCache: Pokemon models from the player's own Omega Ruby / Alpha
-- Sapphire dump, written as PokemonActors species caches -- the SAME format
-- extract/PokemonExtractor.lua writes from the Colosseum disc, so every
-- consumer of PokemonActors (battles, followers, overworld spawns, roamers,
-- the player model) draws them with no per-feature wiring.
--
-- Placement: oras/pokemon/<dex>/ (model_cache.lua, rev.txt, tex_NN.rgba),
-- listed in oras/pokemon/index.lua.  ColosseumDex.cacheRoot routes a listed
-- dex there for its normal variant (ColosseumDex.isOras), and PokemonActors
-- treats it as ready while the cache exists.  Colosseum's own caches under
-- cache/pokemon/ are never touched.
--
-- Geometry is normalized like the Colosseum extractor's (from the bind pose:
-- 16 units tall, feet on y = 0, centred on x/z) and animated by the species'
-- own battle motions (lib/GF1Motion.lua, skinned by lib/H3D.lua): the base
-- bank is the idle loop, and physicalA / specialA / damage / faint are
-- action banks.  Every bank is written straight into PokemonActors' runtime
-- sidecar form (runtime_mesh_v1/: base.lua + base_NN.f32, action_*.lua,
-- action_*_floor.lua, action_*_NN.f32 -- 44 float32 a row: position, uv,
-- normal, then twelve morph-slot positions), which loadScene prefers, so no
-- multi-megabyte text payload is written or parsed.

local V = ...
local N3DSRom = V.require("N3DSRom")
local GARC = V.require("GARC")
local BCH = V.require("BCH")
local H3D = V.require("H3D")
local PICA = V.require("PICA")

local C = { FORMAT = 1 }

local IMPORT_ID = "pokemon_oras"
local MODEL_GARC = "a/0/0/8"
local FIRST_MEMBER = 2
local PER_FORM = 8
local TARGET_HEIGHT = 16.0
local MORPH_SLOTS = 12
-- PICA wrap (0 clamp edge, 1 clamp border, 2 repeat, 3 mirror) -> the
-- PokemonActors texture spec's wrapS/wrapT (0 clamp, 1 repeat, 2 mirrored)
local WRAP = { [0] = 0, [1] = 0, [2] = 1, [3] = 2 }

local function u16(s, p) local a, b = s:byte(p, p + 1); return a + b * 256 end
local function u32(s, p)
  local a, b, c, d = s:byte(p, p + 3)
  return a + b * 256 + c * 65536 + d * 16777216
end
local function num(x)
  if type(x) ~= "number" or x ~= x or x == math.huge or x == -math.huge then return "0" end
  return ("%.5g"):format(x)
end

local function root(dex) return ("oras/pokemon/%d"):format(dex) end

-- part `n` (1-based) of a mini-pack member, relocated
local function packBch(g, member, n)
  local data = g:member(member)
  if #data < 8 then return nil, "member " .. member .. " is empty" end
  local count = u16(data, 3)
  if n > count then return nil, "member " .. member .. " has no part " .. n end
  local off, nxt = u32(data, 5 + (n - 1) * 4), u32(data, 9 + (n - 1) * 4)
  local bch = data:sub(off + 1, nxt)
  local h, why = BCH.header(bch)
  if not h then return nil, why end
  return BCH.relocate(bch, h), h
end

-- The member base of species `dex`'s first form.  Index member 0 holds one
-- 4-byte record per species (u16 first form, u8 forms, u8 flags) and a form
-- f starts at member 2 + 8f -- right for every species checked so far, but
-- the Gen 6 stretch is known to break it, so the result is always verified
-- against the model's own name (pmNNNN_00), scanning outward if it is wrong.
local function modelName(g, base)
  local ok, d, h = pcall(packBch, g, base + 1, 1)
  if not (ok and d) then return nil end
  local okM, models = pcall(H3D.models, d, h)
  local m = okM and models and models[1]
  return m and m.name, d, h, m
end

-- The index is right for every species (checked over all 721 against the
-- dump).  A model's NAME is not a dex number past Gen 5: Gen 6 models carry
-- Game Freak's internal numbers (Chespin, #650, is pm0721) and some species'
-- first form is _11, not _00 (Tornadus) -- so the block is taken from the
-- index and only checked to decode to a model.
local function findSpecies(g, index, dex)
  local rec = (dex - 1) * 4 + 1
  if rec + 3 > #index then return nil, "no index record for dex " .. dex end
  local form = u16(index, rec)
  local base = FIRST_MEMBER + form * PER_FORM
  if base + PER_FORM > g.count then return nil, "index points past the archive for dex " .. dex end
  local name, d, h, model = modelName(g, base)
  if not (name and model) then return nil, "block " .. base .. " holds no model for dex " .. dex end
  return base, d, h, model
end

-- --------------------------------------------------------------- writing

local okFfi, ffi = pcall(require, "ffi")
if not okFfi then ffi = nil end
local unpack = unpack or table.unpack

-- n floats (a Lua array) -> little-endian float32 bytes
local function packFloats(values, n)
  if ffi then
    local buf = ffi.new("float[?]", n)
    for i = 1, n do buf[i - 1] = values[i] end
    return ffi.string(buf, n * 4)
  end
  local parts, row = {}, string.rep("f", 44)
  for i = 1, n, 44 do
    parts[#parts + 1] = love.data.pack("string", row, unpack(values, i, i + 43))
  end
  return table.concat(parts)
end

-- a plain Lua literal, the shape RuntimeMeshCache.readLua loads
local function literal(v)
  local t = type(v)
  if t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then return "0" end
    return ("%.9g"):format(v)
  elseif t == "string" then return ("%q"):format(v)
  elseif t == "boolean" then return v and "true" or "false"
  elseif t ~= "table" then return "nil" end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b)
    if type(a) == type(b) then return tostring(a) < tostring(b) end
    return type(a) == "number"
  end)
  local out = { "{" }
  for _, k in ipairs(keys) do
    local key = type(k) == "number" and ("[" .. k .. "]") or ("[" .. ("%q"):format(k) .. "]")
    out[#out + 1] = key .. "=" .. literal(v[k]) .. ","
  end
  out[#out + 1] = "}"
  return table.concat(out)
end

local function writeLua(mod, path, value)
  return mod.cache:write(path, "return " .. literal(value) .. "\n") ~= false
end

-- Battle-motion slots baked into banks.  The base bank is the idle loop:
-- PokemonActors plays base -> 1..12 -> base, so slot k is idle frame
-- k * frames / 13.  Actions play slot 0 -> 12 once, so slot k is frame
-- k * frames / 12.  GF motions run at 30 frames a second.
-- Slots 8-11 are the physical motions (ba20_buturi01..) and 12-15 the
-- special ones (ba21_tokusyu01..); most species fill only the first of each,
-- some have more (Squirtle: slot 9).  PokemonActors picks among them per move
-- for ORAS scenes (orasAttackVariant).
local ACTIONS = {
  { name = "physicalA", slot = 8 }, { name = "physicalB", slot = 9 },
  { name = "physicalC", slot = 10 }, { name = "physicalD", slot = 11 },
  { name = "specialA", slot = 12 }, { name = "specialB", slot = 13 },
  { name = "specialC", slot = 14 },
  { name = "damage", slot = 16 },     -- ba30_damageS
  { name = "faint", slot = 17 },      -- ba41_down
}
local IDLE_SLOT = 0                   -- ba10_waitA
local FPS = 30
-- bumped whenever the cache layout changes: a species whose rev.txt holds an
-- older stamp is rebuilt, one with this stamp is skipped
local ORAS_STAMP = "oras-actor=4\n"
C.STAMP = ORAS_STAMP

-- set by a background build (ORASModels) to yield between stages
local function checkpoint() if C.checkpoint then C.checkpoint() end end

-- Build one species. Returns a summary string, or nil and a reason.
function C.buildSpecies(mod, rom, g, index, dex)
  local GF1 = V.require("GF1Motion")
  local base, md, mh, model = findSpecies(g, index, dex)
  if not base then return nil, md end
  local td, th = packBch(g, base + 3, 1)
  if not td then return nil, th end
  local textures = H3D.textures(td, th)
  checkpoint()
  -- shiny textures: block slot 4, the same names as the normal set
  local sd, sh = packBch(g, base + 4, 1)
  local shinyTextures = sd and H3D.textures(sd, sh) or {}
  checkpoint()

  -- battle motions: part 0 of the battle-motion member (slot 6 of the block)
  local skeleton, motions = nil, {}
  do
    local okPb, pb = pcall(g.member, g, base + 6)
    if okPb and pb and #pb >= 12 then
      local count = u16(pb, 3)
      if count > 0 then
        local off, nxt = u32(pb, 5), u32(pb, 9)
        local okRead, skel, mots = pcall(GF1.readPack, pb:sub(off + 1, nxt))
        if okRead then skeleton, motions = skel, mots end
      end
    end
  end
  local names = {}
  for i, b in ipairs(skeleton or {}) do names[i] = b.name end
  local pose = H3D.poser(model, GF1.sample, names)

  -- kept meshes (effect meshes skipped, see below), their bind data and
  -- skinning recipes; bounds from the bind pose normalize every frame alike
  local prefix = (model.name or ""):match("^(pm%d+_%d+)") or "pm"
  local kept, skipped = {}, 0
  local lo, hi = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
  for _, mesh in ipairs(model.meshes) do
    local mat = model.materials[mesh.materialIndex + 1] or {}
    local tname = mat.textures and mat.textures[1]
    -- Effect meshes (flames, glows: FireCoreA, FireStenA, ...) sample shared
    -- effect textures through the game's additive/stencil shaders.  Drawn as
    -- ordinary surfaces they are black and white blobs, so only meshes whose
    -- base texture is the species' own (pmNNNN_FF_...) are kept.
    if tname and tname:sub(1, #prefix) == prefix then
      local bind = H3D.bindPose(model, mesh)
      kept[#kept + 1] = { mesh = mesh, mat = mat, tname = tname, bind = bind,
                          skin = H3D.skinning(model, mesh) }
      for _, v in ipairs(bind) do
        for k = 1, 3 do
          if v.position[k] < lo[k] then lo[k] = v.position[k] end
          if v.position[k] > hi[k] then hi[k] = v.position[k] end
        end
      end
    else
      skipped = skipped + 1
    end
  end
  if #kept == 0 then return nil, "no drawable meshes" end
  local height = hi[2] - lo[2]
  if not (height > 0) then return nil, "model has no height" end
  local s = TARGET_HEIGHT / height
  local cx, cz = (lo[1] + hi[1]) / 2, (lo[3] + hi[3]) / 2

  -- positions[meshIndex][slot][vertex] = { x, y, z }, normalized
  local function sampleBank(motion, frames, looping)
    local out = {}
    for m = 1, #kept do out[m] = {} end
    for slot = 0, MORPH_SLOTS do
      local frame = motion and (looping and slot * frames / (MORPH_SLOTS + 1) or slot * frames / MORPH_SLOTS) or 0
      local skin, world = pose(motion, frame)
      checkpoint()
      for m, entry in ipairs(kept) do
        local list = {}
        for vi, rec in ipairs(entry.skin) do
          local x, y, z
          if motion then x, y, z = H3D.skinPoint(rec, skin, world)
          else local p = entry.bind[vi].position; x, y, z = p[1], p[2], p[3] end
          list[vi] = { (x - cx) * s, (y - lo[2]) * s, (z - cz) * s }
        end
        out[m][slot] = list
      end
    end
    return out
  end

  local dir = root(dex)
  local rt = dir .. "/runtime_mesh_v1"

  -- textures, normal and shiny
  local texPaths, shinyPaths, texCount = {}, {}, 0
  local function decodeTo(data, t, path, entry)
    local okT, img = pcall(PICA.decodeTexture, data, t.address, t.width, t.height, t.format)
    if not (okT and img) then return nil end
    assert(mod.cache:write(path, img:getString()) ~= false, "texture write failed: " .. path)
    checkpoint()
    return { path = path, w = t.width, h = t.height,
             wrapS = WRAP[entry.mat.wrapU] or 1, wrapT = WRAP[entry.mat.wrapV] or 1 }
  end
  for _, entry in ipairs(kept) do
    local t = textures[entry.tname]
    if t and not texPaths[entry.tname] then
      texCount = texCount + 1
      texPaths[entry.tname] = decodeTo(td, t, ("%s/tex_%02d.rgba"):format(dir, texCount), entry)
      local st = shinyTextures[entry.tname]
      if st and sd then
        shinyPaths[entry.tname] = decodeTo(sd, st, ("%s/tex_%02d_shiny.rgba"):format(dir, texCount), entry)
      end
    end
  end

  -- one bank -> per-group float32 files (44 floats a row: slot-0 position,
  -- uv, normal, then slots 1-12) and the thirteen per-slot lowest y values
  -- Indexed: each group's rows are its UNIQUE vertices (first-use order),
  -- and one index buffer per group (base_NN.idx, uint32) is shared by every
  -- bank -- PokemonActors applies it with setVertexMap.  A plain triangle
  -- list stored each vertex about three times (~14 MB a species).
  for _, entry in ipairs(kept) do
    local order, at, tris = {}, {}, {}
    for _, sm in ipairs(entry.mesh.submeshes) do
      local ix = sm.indices
      for k = 1, #ix - (#ix % 3) do
        local vi = ix[k] + 1
        if not at[vi] then order[#order + 1] = vi; at[vi] = #order - 1 end
        tris[#tris + 1] = at[vi]
      end
    end
    entry.order, entry.tris = order, tris
  end

  local function packIndices(list)
    if ffi then
      local buf = ffi.new("uint32_t[?]", #list)
      for i = 1, #list do buf[i - 1] = list[i] end
      return ffi.string(buf, #list * 4)
    end
    local parts = {}
    for i = 1, #list do
      local v = list[i]
      parts[i] = string.char(v % 256, math.floor(v / 256) % 256, math.floor(v / 65536) % 256, math.floor(v / 16777216) % 256)
    end
    return table.concat(parts)
  end

  -- one bank -> per-group float32 files (44 floats a row: slot-0 position,
  -- uv, normal, then slots 1-12) and the thirteen per-slot lowest y values
  local function writeBank(positions, pathOf)
    local floor = {}
    for i = 1, MORPH_SLOTS + 1 do floor[i] = math.huge end
    local vertexCount = 0
    for m, entry in ipairs(kept) do
      local values, n = {}, 0
      for _, vi in ipairs(entry.order) do
        local b = entry.bind[vi]
        local uv = b and b.uv or { 0, 0 }
        local nrm = b and b.normal or { 0, 1, 0 }
        local p0 = positions[m][0][vi]
        -- PICA's t runs up from the bottom; LOVE's v runs down: v = 1 - t
        -- (see PICA.decodeTexture; checked by rendering caches offline)
        values[n + 1], values[n + 2], values[n + 3] = p0[1], p0[2], p0[3]
        values[n + 4], values[n + 5] = uv[1], 1 - (uv[2] or 0)
        values[n + 6], values[n + 7], values[n + 8] = nrm[1], nrm[2], nrm[3]
        n = n + 8
        for slot = 0, MORPH_SLOTS do
          local p = positions[m][slot][vi]
          if p[2] < floor[slot + 1] then floor[slot + 1] = p[2] end
          if slot > 0 then
            values[n + 1], values[n + 2], values[n + 3] = p[1], p[2], p[3]
            n = n + 3
          end
        end
      end
      vertexCount = vertexCount + #entry.tris
      assert(mod.cache:write(pathOf(m), packFloats(values, n)) ~= false, "bank write failed: " .. pathOf(m))
      checkpoint()
    end
    for i = 1, MORPH_SLOTS + 1 do if floor[i] == math.huge then floor[i] = 0 end end
    return floor, vertexCount
  end

  for m, entry in ipairs(kept) do
    local path = ("%s/base_%02d.idx"):format(rt, m)
    assert(mod.cache:write(path, packIndices(entry.tris)) ~= false, "index write failed: " .. path)
    entry.vertexMap = path
  end

  -- base bank: the idle loop (or the bind pose, static, if there is none)
  local idle = motions[IDLE_SLOT]
  local basePositions = sampleBank(idle, idle and idle.frames or 0, true)
  local baseFloor, vertexTotal = writeBank(basePositions, function(m) return ("%s/base_%02d.f32"):format(rt, m) end)

  -- action banks, written straight into PokemonActors' runtime sidecar form
  local actions, baked = {}, {}
  for _, a in ipairs(ACTIONS) do
    local motion = motions[a.slot]
    if motion and motion.frames > 0 then
      local duration = motion.frames / FPS
      local floor = writeBank(sampleBank(motion, motion.frames, false), function(m)
        return ("%s/action_%s_%02d.f32"):format(rt, a.name, m)
      end)
      writeLua(mod, ("%s/action_%s.lua"):format(rt, a.name), {
        runtimeMeshVersion = 1, stamp = ORAS_STAMP, clip = a.slot, duration = duration,
        frameSpacing = 1, morphFrames = MORPH_SLOTS, groupCount = #kept,
      })
      writeLua(mod, ("%s/action_%s_floor.lua"):format(rt, a.name), {
        runtimeMeshVersion = 1, stamp = ORAS_STAMP, groupCount = #kept, floorMinYSlots = floor,
      })
      actions[a.name] = { clip = a.slot, duration = duration }
      baked[#baked + 1] = ("%s %.2fs"):format(a.name, duration)
    end
  end

  -- a species with motions of only one attack family (Caterpie has no
  -- physical one) plays that one for both
  if not actions.physicalA then
    local other = actions.physicalB and "physicalB" or (actions.specialA and "specialA")
    if other then actions.physicalA = { alias = other, clip = actions[other].clip, duration = actions[other].duration } end
  end
  if not actions.specialA and actions.physicalA and not actions.physicalA.alias then
    actions.specialA = { alias = "physicalA", clip = actions.physicalA.clip, duration = actions.physicalA.duration }
  end

  local groups = {}
  for m, entry in ipairs(kept) do
    groups[m] = {
      material = entry.mat.name or ("mesh" .. m), texture = texPaths[entry.tname],
      textureShiny = shinyPaths[entry.tname] or texPaths[entry.tname],
      diffuse = { 1, 1, 1 }, ambient = { 1, 1, 1 }, specular = { 0, 0, 0 }, alpha = 1, shininess = 0,
      xlu = false, noz = false, renderFlags = 0, shadow = false, effect = false, textureSlot = -1,
      vertexStride = 44, runtimeBin = ("%s/base_%02d.f32"):format(rt, m),
      vertexMap = entry.vertexMap,
    }
  end
  local minFloor = math.huge
  for _, y in ipairs(baseFloor) do if y < minFloor then minFloor = y end end
  local hx, hz = (hi[1] - lo[1]) * s / 2, (hi[3] - lo[3]) * s / 2
  local meta = {
    runtimeMeshVersion = 1, stamp = ORAS_STAMP,
    formatVersion = 4, poseFormat = "oras-gf1-motion-v1", oras = true,
    dex = dex, stem = model.name or "", source = "ORAS",
    clip = IDLE_SLOT, clipCount = 0, frameSpacing = 1,
    idleDuration = idle and idle.frames / FPS or 0,
    morphFrames = idle and MORPH_SLOTS or 0, morphSlots = MORPH_SLOTS,
    vertexCount = vertexTotal, groupCount = #groups,
    heightRatio = 1, widthRatio = (hi[1] - lo[1]) / height,
    bounds = { min = { -hx, 0, -hz }, max = { hx, TARGET_HEIGHT, hz }, center = { 0, TARGET_HEIGHT / 2, 0 } },
    floorMinY = minFloor,
    jointPositions = {}, jointFrames = {},
    actions = actions, groups = groups,
  }
  -- base.lua is what PokemonActors loads (its stamp matches rev.txt);
  -- model_cache.lua is the same table, which marks the species as present
  assert(writeLua(mod, rt .. "/base.lua", meta), "runtime base write failed")
  assert(writeLua(mod, dir .. "/model_cache.lua", meta), "model cache write failed")
  mod.cache:write(dir .. "/rev.txt", ORAS_STAMP)

  return ("%s: %d groups, %d verts, %d textures, %d effect meshes skipped, idle %s, actions %s (members %d-%d)"):format(
    tostring(model.name), #groups, vertexTotal, texCount, skipped,
    idle and ("%.2fs"):format(idle.frames / FPS) or "none",
    #baked > 0 and table.concat(baked, ", ") or "none", base, base + 7)
end

-- Build `list` (dex numbers) and register them.  `log(fmt, ...)` reports each
-- species; `progress(done, total, dex)` is told after each one.  A species
-- whose rev.txt already holds C.STAMP is skipped (counted as skipped), and the
-- index is rewritten after every species, so a build cut short keeps what it
-- finished.  Runs inside a coroutine when C.checkpoint yields (ORASModels).
-- Returns built, failed, err, skipped.
function C.build(mod, list, log, progress)
  log = log or function() end
  progress = progress or function() end
  local rom, err = N3DSRom.open(mod, IMPORT_ID)
  if not rom then return 0, #list, err end
  local g, gerr = GARC.open(rom, assert(rom:file(MODEL_GARC), "no " .. MODEL_GARC))
  if not g then return 0, #list, gerr end
  local index = g:member(0)

  local Actors = V.PokemonActors

  -- existing index, so building a second batch keeps the first
  local Dex = V.ColosseumDex
  local listed = {}
  local okR, src = pcall(mod.cache.read, mod.cache, "oras/pokemon/index.lua")
  if okR and type(src) == "string" then
    local chunk = load(src)
    local ok, old = pcall(chunk or function() end)
    if ok and type(old) == "table" then for _, d in ipairs(old) do listed[tonumber(d)] = true end end
  end

  local function writeIndex()
    local all = {}
    for d in pairs(listed) do all[#all + 1] = d end
    table.sort(all)
    local parts = {}
    for i, d in ipairs(all) do parts[i] = tostring(d) end
    mod.cache:write("oras/pokemon/index.lua", "return {" .. table.concat(parts, ",") .. "}\n")
  end

  local built, failed, skipped = 0, 0, 0
  for n, dex in ipairs(list) do
    local okRev, rev = pcall(mod.cache.read, mod.cache, root(dex) .. "/rev.txt")
    if okRev and rev == C.STAMP and listed[dex] then
      skipped = skipped + 1
    else
      -- pcall does not cross a coroutine yield in plain Lua 5.1, but does in
      -- LuaJIT (which this runs on): yields inside buildSpecies are fine
      local ok, summary, why = pcall(C.buildSpecies, mod, rom, g, index, dex)
      if ok and summary then
        built = built + 1
        listed[dex] = true
        writeIndex()
        log("ORAS dex %d: %s", dex, summary)
      else
        failed = failed + 1
        log("ORAS dex %d FAILED: %s", dex, tostring(ok and why or summary))
      end
    end
    progress(n, #list, dex)
    checkpoint()
  end
  writeIndex()

  -- live routing for the instances reachable from here; any other copy of
  -- ColosseumDex picks the index up on its next load (a restart)
  if Dex and Dex.loadOras then pcall(Dex.loadOras, mod) end
  local okReq, DexReq = pcall(V.require, "ColosseumDex")
  if okReq and DexReq and DexReq ~= Dex and DexReq.loadOras then pcall(DexReq.loadOras, mod) end
  if Actors and Actors.forgetScene then
    for _, dex in ipairs(list) do pcall(Actors.forgetScene, dex) end
  end
  return built, failed, nil, skipped
end

return C
