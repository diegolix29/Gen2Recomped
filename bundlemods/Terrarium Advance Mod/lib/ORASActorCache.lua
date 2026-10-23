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
-- Geometry is the bind pose (lib/H3D.lua), normalized like the Colosseum
-- extractor's: 16 units tall, feet on y = 0, centred on x/z.  Each 44-float
-- row is position, uv, normal, then twelve morph-frame positions -- copies
-- of the bind pose until battle motions are baked in (morphFrames = 0, so
-- PokemonActors draws the base pose).

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

local function findSpecies(g, index, dex)
  local want = ("pm%04d_00"):format(dex)
  local rec = (dex - 1) * 4 + 1
  local guess = rec + 1 <= #index and u16(index, rec) or (dex - 1)
  local tried = {}
  local function try(form)
    local base = FIRST_MEMBER + form * PER_FORM
    if form < 0 or tried[form] or base + PER_FORM > g.count then return nil end
    tried[form] = true
    local name, d, h, model = modelName(g, base)
    if name == want then return base, d, h, model end
    return nil, name
  end
  local base, d, h, model = try(guess)
  if base then return base, d, h, model end
  for step = 1, 40 do
    for _, f in ipairs({ guess + step, guess - step }) do
      base, d, h, model = try(f)
      if base then return base, d, h, model end
    end
  end
  return nil, "no block named " .. want .. " near form " .. guess
end

-- Build one species. Returns a summary string, or nil and a reason.
function C.buildSpecies(mod, rom, g, index, dex, stamp)
  local base, md, mh, model = findSpecies(g, index, dex)
  if not base then return nil, md end
  local td, th = packBch(g, base + 3, 1)
  if not td then return nil, th end
  local textures = H3D.textures(td, th)

  -- bind pose for every mesh, then one normalization over all of them
  local meshes, lo, hi = {}, { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
  for _, mesh in ipairs(model.meshes) do
    local bind = H3D.bindPose(model, mesh)
    meshes[#meshes + 1] = { mesh = mesh, bind = bind }
    for _, v in ipairs(bind) do
      for k = 1, 3 do
        if v.position[k] < lo[k] then lo[k] = v.position[k] end
        if v.position[k] > hi[k] then hi[k] = v.position[k] end
      end
    end
  end
  local height = hi[2] - lo[2]
  if not (height > 0) then return nil, "model has no height" end
  local s = TARGET_HEIGHT / height
  local cx, cz = (lo[1] + hi[1]) / 2, (lo[3] + hi[3]) / 2
  local function norm(p) return (p[1] - cx) * s, (p[2] - lo[2]) * s, (p[3] - cz) * s end

  local dir = root(dex)
  local texPaths, texCount = {}, 0
  local groups, vertexTotal = {}, 0

  local prefix = (model.name or ""):match("^(pm%d+_%d+)") or "pm"
  local skipped = 0
  for gi, entry in ipairs(meshes) do
    local mesh, bind = entry.mesh, entry.bind
    local mat = model.materials[mesh.materialIndex + 1] or {}
    local tname = mat.textures and mat.textures[1]
    -- Effect meshes (flames, glows: FireCoreA, FireStenA, ...) sample shared
    -- effect textures through the game's additive/stencil shaders.  Drawn as
    -- ordinary surfaces they are black and white blobs, so only meshes whose
    -- base texture is the species' own (pmNNNN_FF_...) are kept.
    if not (tname and tname:sub(1, #prefix) == prefix) then
      skipped = skipped + 1
      goto continue
    end
    local t = tname and textures[tname]
    local tp = tname and texPaths[tname]
    if t and not tp then
      local okT, img = pcall(PICA.decodeTexture, td, t.address, t.width, t.height, t.format)
      if okT and img then
        texCount = texCount + 1
        tp = { path = ("%s/tex_%02d.rgba"):format(dir, texCount), w = t.width, h = t.height }
        assert(mod.cache:write(tp.path, img:getString()) ~= false, "texture write failed: " .. tp.path)
        texPaths[tname] = tp
      end
    end

    local rows = {}
    local function row(ix)
      local v = bind[ix + 1]
      if not v then return end
      local x, y, z = norm(v.position)
      local uv = v.uv or { 0, 0 }
      local n = v.normal or { 0, 1, 0 }
      -- PICA's t runs up from the bottom of the texture, whose first row in
      -- memory is the TOP of the decoded image (PICA.decodeTexture); LOVE's
      -- v runs down from the top, so v = 1 - t.  Checked by rendering
      -- Ivysaur's and Charizard's caches offline: with t as-is the eye sheet
      -- showed its closed frame and Charizard's wings sampled empty texels.
      local cells = { num(x), num(y), num(z), num(uv[1]), num(1 - (uv[2] or 0)),
                      num(n[1]), num(n[2]), num(n[3]) }
      local px, py, pz = cells[1], cells[2], cells[3]
      for _ = 1, MORPH_SLOTS do
        cells[#cells + 1] = px; cells[#cells + 1] = py; cells[#cells + 1] = pz
      end
      rows[#rows + 1] = table.concat(cells, ",")
    end
    for _, sm in ipairs(mesh.submeshes) do
      local ix = sm.indices
      for k = 1, #ix - 2, 3 do row(ix[k]); row(ix[k + 1]); row(ix[k + 2]) end
    end
    if #rows > 0 then
      vertexTotal = vertexTotal + #rows
      groups[#groups + 1] = { name = mat.name, texture = tp, packed = table.concat(rows, "\n"),
                              wrapS = WRAP[mat.wrapU] or 1, wrapT = WRAP[mat.wrapV] or 1 }
    end
    ::continue::
  end
  if #groups == 0 then return nil, "no drawable meshes" end

  local hx, hz = (hi[1] - lo[1]) * s / 2, (hi[3] - lo[3]) * s / 2
  local out = {
    "-- Generated locally from the player's own Omega Ruby / Alpha Sapphire dump.\n",
    "return {formatVersion=4,poseFormat=\"oras-bind-pose-v1\",oras=true,\n",
    "dex=", tostring(dex), ",stem=", ("%q"):format(model.name or ""), ",source=\"ORAS\",\n",
    "clip=0,clipCount=0,idleDuration=0,frameSpacing=1,morphFrames=0,morphSlots=", tostring(MORPH_SLOTS), ",\n",
    "vertexCount=", tostring(vertexTotal), ",groupCount=", tostring(#groups), ",\n",
    "heightRatio=1,widthRatio=", num((hi[1] - lo[1]) / height), ",\n",
    "bounds={min={", num(-hx), ",0,", num(-hz), "},max={", num(hx), ",", num(TARGET_HEIGHT), ",", num(hz),
    "},center={0,", num(TARGET_HEIGHT / 2), ",0}},\n",
    "jointPositions={},jointFrames={},actions={},\n",
    "groups={\n",
  }
  for _, gr in ipairs(groups) do
    out[#out + 1] = "{material=" .. ("%q"):format(tostring(gr.name))
    if gr.texture then
      out[#out + 1] = (",texture={path=%q,w=%d,h=%d,wrapS=%d,wrapT=%d}"):format(
        gr.texture.path, gr.texture.w, gr.texture.h, gr.wrapS, gr.wrapT)
    end
    out[#out + 1] = ",diffuse={1,1,1},ambient={1,1,1},specular={0,0,0},alpha=1,shininess=0"
    out[#out + 1] = ",xlu=false,noz=false,renderFlags=0,shadow=false,effect=false,textureSlot=-1"
    out[#out + 1] = ",vertexStride=44,verticesPacked=[==[\n" .. gr.packed .. "]==]},\n"
  end
  out[#out + 1] = "}}\n"

  local okW = mod.cache:write(dir .. "/model_cache.lua", table.concat(out))
  if okW == false then return nil, "model cache write failed" end
  mod.cache:write(dir .. "/rev.txt", stamp or "oras-actor=1\n")
  -- a stale runtime sidecar from an earlier build must not outlive this one
  pcall(mod.cache.delete, mod.cache, dir .. "/runtime_mesh_v1/base.lua")
  return ("%s: %d groups, %d verts, %d textures, %d effect meshes skipped (members %d-%d)"):format(
    tostring(model.name), #groups, vertexTotal, texCount, skipped, base, base + 7)
end

-- Build `list` (dex numbers) and register them.  `log(fmt, ...)` reports
-- progress.  Returns built, failed.
function C.build(mod, list, log)
  log = log or function() end
  local rom, err = N3DSRom.open(mod, IMPORT_ID)
  if not rom then return 0, #list, err end
  local g, gerr = GARC.open(rom, assert(rom:file(MODEL_GARC), "no " .. MODEL_GARC))
  if not g then return 0, #list, gerr end
  local index = g:member(0)

  local Actors = V.PokemonActors
  local stamp = Actors and Actors.cacheStamp and Actors.cacheStamp() or nil

  -- existing index, so building a second batch keeps the first
  local Dex = V.ColosseumDex
  local listed = {}
  local okR, src = pcall(mod.cache.read, mod.cache, "oras/pokemon/index.lua")
  if okR and type(src) == "string" then
    local chunk = load(src)
    local ok, old = pcall(chunk or function() end)
    if ok and type(old) == "table" then for _, d in ipairs(old) do listed[tonumber(d)] = true end end
  end

  local built, failed = 0, 0
  for _, dex in ipairs(list) do
    local ok, summary, why = pcall(C.buildSpecies, mod, rom, g, index, dex, stamp)
    if ok and summary then
      built = built + 1
      listed[dex] = true
      log("ORAS dex %d: %s", dex, summary)
    else
      failed = failed + 1
      log("ORAS dex %d FAILED: %s", dex, tostring(ok and why or summary))
    end
  end

  local all = {}
  for d in pairs(listed) do all[#all + 1] = d end
  table.sort(all)
  local parts = {}
  for i, d in ipairs(all) do parts[i] = tostring(d) end
  mod.cache:write("oras/pokemon/index.lua", "return {" .. table.concat(parts, ",") .. "}\n")

  -- live routing for the instances reachable from here; any other copy of
  -- ColosseumDex picks the index up on its next load (a restart)
  if Dex and Dex.loadOras then pcall(Dex.loadOras, mod) end
  local okReq, DexReq = pcall(V.require, "ColosseumDex")
  if okReq and DexReq and DexReq ~= Dex and DexReq.loadOras then pcall(DexReq.loadOras, mod) end
  if Actors and Actors.forgetScene then
    for _, dex in ipairs(list) do pcall(Actors.forgetScene, dex) end
  end
  return built, failed
end

return C
