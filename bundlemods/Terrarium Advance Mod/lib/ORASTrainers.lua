-- ORASTrainers: the people of Omega Ruby / Alpha Sapphire -- the player,
-- the named characters and every trainer class -- baked from the player's own
-- decrypted dump into PokemonActors caches (the same format as the ORAS
-- Pokemon, lib/ORASActorCache.lua bakeActor), so the overworld player model
-- and the 3D battles can draw them with the actor code they already have.
--
-- Two sets, both with GF1Motion packs (lib/GF1Motion.lua):
--   FIELD  a/0/2/1: "MM" packs, part 0 = the model BCH (trNNNN_00_fi,
--          rstrNNNN_00_fi; also pm / ob / it / monsball / dummy, not people),
--          part 1 = its motion pack.  rstr0001 / rstr0002 are the ORAS player
--          pair, rstr0003-0053 named characters, rstr0101-0225 the trainer
--          classes / townsfolk (23-bone rig), tr00NN the XY-era cast.
--          Slots: 0 stand (1 frame), 2 walk (14), 4 run (16), 5 jump,
--          8 / 9 / 12 bike.  Nodes sw_parts01-05 (dive goggles, snorkel,
--          rod, ...) and bicycle are switch parts the game shows only for
--          those moves: never drawn here.  Texture unit 0 is a projection
--          dummy; the character's own texture sits in unit 1 (on uv0).
--   BATTLE a/1/3/3: five members per character: +0 model BCH (bt0001_00 =
--          Serena, bt0002, ..., rsbt00NN the ORAS cast; bt0110 is a 3-bone
--          dummy), +1 "BB" face anims, +2..+4 "BS" packs whose part 0 is a
--          motion pack.  +2 slots: 0 idle, 1 ball throw, 2 command / point,
--          4 idle B, 6 big intro throw.  Bchara_hlight* (unit 1) are rim
--          highlight maps, not the surface.
--
-- BUILD (row "ORAS TRAINERS") into mod cache oras/trainers/:
--   index.lua   { stamp, list = { { id, kind = "field" | "battle", name,
--                 member, actions = { ... } }, ... } }
--   <id>/...    a PokemonActors species cache (runtime_mesh_v1/base.lua +
--               banks, model_cache.lua, rev.txt, tex_NN.rgba); meta.trainer
--               = kind, meta.trainerId = id.
-- A character whose rev.txt already holds T.STAMP is not rebuilt.

local V = ...
local mod = V and V.mod

local T = { ID = "oras_trainers", LABEL = "ORAS TRAINERS" }
T.ROOT = "oras/trainers"
T.INDEX = T.ROOT .. "/index.lua"
T.STAMP = "oras-trainer=2\n"   -- 2: field heights scaled to real size (FIELD_SCALE)
T.IMPORT_ID = "pokemon_oras"
T.FIELD_GARC = "a/0/2/1"
T.BATTLE_GARC = "a/1/3/3"
T.BATTLE_STRIDE = 5
-- field models are chibi-sized: the ORAS player is 31 cm on the field and
-- 133 cm as a battle model, so field heights are scaled by this to read as
-- people next to the Pokemon
T.FIELD_SCALE = 4.3

-- action banks (PokemonActors one-shots); the base bank is slot 0
T.FIELD_ACTIONS = {
  { name = "walk", slot = 2 }, { name = "run", slot = 4 }, { name = "jump", slot = 5 },
}
T.BATTLE_ACTIONS = {
  { name = "throw", slot = 1 }, { name = "command", slot = 2 },
  { name = "throwB", slot = 6 }, { name = "idleB", slot = 4 },
}

local FRAME_BUDGET = 0.010

local function log(level, fmt, ...)
  local l = mod and mod.log
  if l and type(l[level]) == "function" then pcall(l[level], l, fmt, ...) end
end

local function now()
  return (love and love.timer and love.timer.getTime and love.timer.getTime()) or os.clock()
end

local function u16(s, p) local a, b = s:byte(p, p + 1); return a + b * 256 end
local function u32(s, p)
  local a, b, c, d = s:byte(p, p + 3)
  return a + b * 256 + c * 65536 + d * 16777216
end

-- part k (0-based) of a two-letter mini pack ("MM", "BS", ...); a member
-- that is not a pack is its own part 0
local function part(s, k)
  if type(s) ~= "string" or #s < 8 then return nil end
  local n = u16(s, 3)
  if not s:sub(1, 2):match("^%u%u$") or n == 0 or n > 64 then return k == 0 and s or nil end
  if k >= n then return nil end
  return s:sub(u32(s, 5 + 4 * k) + 1, u32(s, 9 + 4 * k))
end
T._part = part

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

-- ------------------------------------------------------------ the models

-- textures that are not the character's surface
local function skipTexture(n)
  return n == nil or n == "" or n == "projection_dummy" or n:find("^Bchara_hlight") ~= nil
end
-- switch parts shown only for one move (dive gear, rod, ...).  The bike is
-- kept: only the riding variants (rstr0050 / rstr0051) carry one.
local function hiddenNode(name)
  name = tostring(name or "")
  return name:find("^sw_parts") ~= nil
end
T._hiddenNode = hiddenNode

-- the mesh-selection rule bakeActor asks for: the first real texture unit
function T.selectFor(model)
  return function(mesh, mat)
    if hiddenNode(model.nodeNames and model.nodeNames[mesh.nodeIndex]) then return nil end
    local tex = mat.textures or {}
    for k = 1, 3 do
      if not skipTexture(tex[k]) then
        local unit = mat.units and mat.units[k] or {}
        return { tname = tex[k], unit = k, wrapU = unit.wrapU, wrapV = unit.wrapV }
      end
    end
    return nil
  end
end

-- id from the model name: rstr0001_00_fi -> rstr0001, bt0001_00 -> bt0001
local function idOf(name)
  return tostring(name or ""):match("^(%a+%d+)") or tostring(name)
end
local function isPerson(name)
  name = tostring(name or "")
  return name:match("^rstr%d+") ~= nil or name:match("^tr%d+") ~= nil
      or name:match("^rsbt%d+") ~= nil or name:match("^bt%d+") ~= nil
end

local function decodeModel(raw)
  local B, H = V.require("BCH"), V.require("H3D")
  if not (raw and B.is(raw)) then return nil, "not a BCH" end
  local h, why = B.header(raw)
  if not h then return nil, why end
  local d = B.relocate(raw, h)
  local models = H.models(d, h)
  local model = models and models[1]
  if not model then return nil, "no model" end
  return model, d, h
end

-- the people in both archives: { id, kind, name, member, bones }
function T.listSources(R)
  local G = V.require("GARC")
  local out, seen = {}, {}
  local fieldFile, battleFile = R:file(T.FIELD_GARC), R:file(T.BATTLE_GARC)
  local field = fieldFile and G.open(R, fieldFile)
  if field then
    for i = 0, field.count - 1 do
      local okM, s = pcall(field.member, field, i)
      local raw = okM and part(s, 0)
      local okD, model = pcall(decodeModel, raw)
      local name = okD and model and model.name
      if name and isPerson(name) and part(s, 1) then
        local id = idOf(name)
        if not seen[id] then
          seen[id] = true
          out[#out + 1] = { id = id, kind = "field", name = name, member = i, bones = #(model.bones or {}) }
        end
      end
      if T.checkpoint then T.checkpoint() end
    end
  end
  local battle = battleFile and G.open(R, battleFile)
  if battle then
    for i = 0, battle.count - 1, T.BATTLE_STRIDE do
      local okM, raw = pcall(battle.member, battle, i)
      local okD, model = pcall(decodeModel, okM and raw)
      local name = okD and model and model.name
      if name and isPerson(name) and #(model.bones or {}) >= 10 then
        local id = idOf(name)
        if not seen[id] then
          seen[id] = true
          out[#out + 1] = { id = id, kind = "battle", name = name, member = i, bones = #model.bones }
        end
      end
      if T.checkpoint then T.checkpoint() end
    end
  end
  return out, field, battle
end

-- Bake one character.  Returns the summary line, or nil and a reason.
function T.buildOne(cache, src, field, battle)
  local C = V.require("ORASActorCache")
  local H, GF1 = V.require("H3D"), V.require("GF1Motion")
  local raw, pack
  if src.kind == "field" then
    local s = field:member(src.member)
    raw, pack = part(s, 0), part(s, 1)
  else
    raw = battle:member(src.member)
    pack = part(battle:member(src.member + 2), 0)
  end
  local model, d, h = decodeModel(raw)
  if not model then return nil, d end
  local textures = H.textures(d, h)
  local skeleton, motions = nil, {}
  if pack then
    local okP, sk, mo = pcall(GF1.readPack, pack)
    if okP then skeleton, motions = sk, mo or {} end
  end
  local names = {}
  for i, b in ipairs(skeleton or {}) do names[i] = b.name end
  local pose = H.poser(model, function(curve, f) return GF1.sample(curve, f) end, names)
  local actions = src.kind == "field" and T.FIELD_ACTIONS or T.BATTLE_ACTIONS
  local dir = ("%s/%s"):format(T.ROOT, src.id)
  local summary, why = C.bakeActor({ cache = cache }, {
    model = model, textures = textures, texData = d,
    motions = motions, pose = pose, select = T.selectFor(model),
    actions = actions, idleSlot = 0, stamp = T.STAMP,
    dir = dir, attackAliases = false,
    meta = { trainer = src.kind, trainerId = src.id },
    nativeScale = src.kind == "field" and T.FIELD_SCALE or nil,
    label = ("%s member %d"):format(src.kind, src.member),
  })
  if not summary then return nil, why end
  local have = {}
  for _, a in ipairs(actions) do if motions[a.slot] then have[#have + 1] = a.name end end
  return summary, have
end

-- ------------------------------------------------------------------ names
--
-- Who is who, from the contact sheet (2026-11-03).  Field ids are the
-- overworld models, battle ids the detailed battle ones.  "?" in a comment:
-- a guess the user has not confirmed yet.
T.NAMES = {
  -- the player, contest outfits, suits, on the bike
  rstr0001 = "MAY", rstr0002 = "BRENDAN", rstr0003 = "MAY CONTEST", rstr0004 = "BRENDAN CONTEST",
  rstr0005 = "SUIT RED A", rstr0006 = "SUIT BLUE A", rstr0007 = "SUIT RED B", rstr0008 = "SUIT BLUE B",
  rstr0050 = "MAY BIKE", rstr0051 = "BRENDAN BIKE",
  rstr0009 = "PROF. BIRCH", rstr0010 = "WALLY", rstr0011 = "WALLY (BAG)", rstr0012 = "STEVEN",
  -- Elite Four
  rstr0013 = "SIDNEY", rstr0014 = "PHOEBE", rstr0015 = "GLACIA", rstr0016 = "DRAKE",
  -- gym leaders
  rstr0017 = "ROXANNE", rstr0018 = "BRAWLY", rstr0019 = "WATTSON", rstr0020 = "FLANNERY",
  rstr0021 = "NORMAN", rstr0053 = "NORMAN (ALT)", rstr0022 = "WINONA", rstr0023 = "TATE",
  rstr0024 = "LIZA", rstr0025 = "WALLACE",
  -- Team Magma / Team Aqua
  rstr0026 = "MAXIE", rstr0027 = "TABITHA", rstr0028 = "COURTNEY",
  rstr0029 = "MAGMA GRUNT M", rstr0030 = "MAGMA GRUNT F", rstr0043 = "MAGMA GRUNT F2",
  rstr0031 = "ARCHIE", rstr0032 = "MATT", rstr0033 = "SHELLY",
  rstr0034 = "AQUA GRUNT M", rstr0035 = "AQUA GRUNT F", rstr0044 = "AQUA GRUNT F2",
  -- supporting cast
  rstr0040 = "LISIA", rstr0041 = "AARUNE", rstr0042 = "ZINNIA",
  rstr0165 = "MR. STONE",      -- ?
  rstr0114 = "CAPT. STERN",    -- ?
  -- battle models
  rsbt0001 = "MAY", rsbt0002 = "BRENDAN", rsbt0003 = "WALLY", rsbt0004 = "WALLY (MEGA)",
  rsbt0005 = "STEVEN", rsbt0019 = "MAXIE", rsbt0024 = "ARCHIE", rsbt0035 = "ZINNIA",
  bt0001 = "SERENA", bt0002 = "CALEM", bt0003 = "SHAUNA", bt0004 = "TIERNO", bt0005 = "TREVOR",
}
-- the ORAS PLAYER row's choices, in order (field models: they walk and run)
T.PLAYER_ORDER = {
  "rstr0002", "rstr0001", "rstr0004", "rstr0003", "rstr0051", "rstr0050",
  "rstr0005", "rstr0006", "rstr0007", "rstr0008",
  "rstr0010", "rstr0011", "rstr0042", "rstr0009", "rstr0012",
  "rstr0017", "rstr0018", "rstr0019", "rstr0020", "rstr0021", "rstr0022", "rstr0023", "rstr0024", "rstr0025",
  "rstr0013", "rstr0014", "rstr0015", "rstr0016",
  "rstr0031", "rstr0026", "rstr0033", "rstr0028", "rstr0032", "rstr0027",
  "rstr0034", "rstr0035", "rstr0029", "rstr0030",
  "rstr0040", "rstr0041", "rstr0165", "rstr0114",
}
function T.label(id) return T.NAMES[id] or tostring(id):upper() end

-- -------------------------------------------------------------- reading

local indexMemo
function T.index()
  if indexMemo == nil then
    local ok, src = pcall(mod.cache.read, mod.cache, T.INDEX)
    local idx
    if ok and type(src) == "string" then
      local chunk = (loadstring or load)(src, "@" .. T.INDEX)
      if chunk then
        if setfenv then setfenv(chunk, {}) end
        local okR, v = pcall(chunk)
        idx = okR and v or nil
      end
    end
    indexMemo = (type(idx) == "table" and idx.stamp == T.STAMP and type(idx.list) == "table") and idx or false
  end
  return indexMemo or nil
end
function T.built() return T.index() ~= nil end
function T.count() local idx = T.index(); return idx and #idx.list or 0 end
-- the cache folder of a baked character, or nil
function T.dirOf(id)
  local idx = T.index()
  if not idx then return nil end
  for _, e in ipairs(idx.list) do if e.id == id then return T.ROOT .. "/" .. id end end
  return nil
end

function T.imported()
  local imports = mod and mod.imports
  if not imports then return false end
  local ok, info = pcall(imports.info, imports, T.IMPORT_ID)
  return ok and type(info) == "table" and info.ready ~= false
end

-- ------------------------------------------------------------------ build

local job = nil   -- { co, done, total, startedAt, frameStart }

local function checkpoint()
  if job and coroutine.running() == job.co and now() - job.frameStart > FRAME_BUDGET then
    coroutine.yield()
  end
end

local function bake()
  local C = V.require("ORASActorCache")
  local R, why = V.require("N3DSRom").open(mod, T.IMPORT_ID)
  if not R then error("dump: " .. tostring(why)) end
  T.checkpoint = checkpoint
  local sources, field, battle = T.listSources(R)
  job.total = #sources
  local prevCheckpoint = C.checkpoint
  C.checkpoint = checkpoint
  local list, built, kept, failed = {}, 0, 0, 0
  local okAll, err = pcall(function()
    for i, src in ipairs(sources) do
      local dir = T.ROOT .. "/" .. src.id
      local okRev, rev = pcall(mod.cache.read, mod.cache, dir .. "/rev.txt")
      local entry = { id = src.id, kind = src.kind, name = src.name, member = src.member }
      if okRev and rev == T.STAMP then
        local okI, old = pcall(function() return T.index() end)
        local prev
        for _, e in ipairs(okI and old and old.list or {}) do if e.id == src.id then prev = e end end
        entry.actions = prev and prev.actions or nil
        list[#list + 1] = entry
        kept = kept + 1
      else
        local okB, summary, have = pcall(T.buildOne, mod.cache, src, field, battle)
        if okB and summary then
          entry.actions = have
          list[#list + 1] = entry
          built = built + 1
        else
          failed = failed + 1
          log("warn", "ORAS TRAINERS: %s (%s member %d) skipped: %s", src.id, src.kind, src.member,
              tostring(okB and have or summary))
        end
      end
      job.done = i
      checkpoint()
    end
  end)
  C.checkpoint = prevCheckpoint
  T.checkpoint = nil
  if not okAll then error(err) end
  mod.cache:write(T.INDEX, "return " .. literal({ stamp = T.STAMP, list = list }) .. "\n")
  indexMemo = nil
  -- live routing (ColosseumDex trainer numbers) for the instances reachable
  -- from here, as ORAS MODELS does; any other copy reads it on a restart
  local seenDex = {}
  for _, Dex in ipairs({ V.ColosseumDex, (select(2, pcall(V.require, "ColosseumDex"))) }) do
    if type(Dex) == "table" and Dex.loadOrasTrainers and not seenDex[Dex] then
      seenDex[Dex] = true
      pcall(Dex.loadOrasTrainers, mod)
    end
  end
  local Actors = V.PokemonActors
  if Actors and Actors.forgetScene and V.ColosseumDex and V.ColosseumDex.trainerDex then
    for _, e in ipairs(list) do
      local n = V.ColosseumDex.trainerDex(e.id)
      if n then pcall(Actors.forgetScene, n) end
    end
  end
  return #list, built, kept, failed
end

function T.running() return job ~= nil end

function T.startBuild()
  if job then return false end
  job = { done = 0, total = 0, startedAt = now(), frameStart = now() }
  job.co = coroutine.create(bake)
  T.status = { state = "building" }
  log("info", "ORAS TRAINERS: baking the ORAS characters in the background")
  return true
end

-- once a frame (main.lua)
function T.pump()
  if not job then return end
  job.frameStart = now()
  local ok, n, built, kept, failed = coroutine.resume(job.co)
  if not ok then
    log("warn", "ORAS TRAINERS: build failed: %s", tostring(n))
    T.status = { state = "error", error = tostring(n) }
    job = nil
    return
  end
  if coroutine.status(job.co) == "dead" then
    log("info", "ORAS TRAINERS: %d characters (%d baked, %d already built, %d failed) in %.1fs",
        n or 0, built or 0, kept or 0, failed or 0, now() - job.startedAt)
    job = nil
    T.status = { state = "done" }
  end
end

-- -------------------------------------------------------------------- rows

function T.row()
  return {
    id = T.ID,
    label = T.LABEL,
    value = function()
      if job then
        if job.total == 0 then return "LISTING" end
        return ("BUILDING %d/%d"):format(job.done, job.total)
      end
      if T.status and T.status.state == "error" then return "ERROR" end
      if T.built() then return ("BUILT %d"):format(T.count()) end
      return T.imported() and "BUILD" or "NO DUMP"
    end,
    step = function()
      if job then return true end
      if not T.imported() then
        log("info", "ORAS TRAINERS: import a decrypted Omega Ruby / Alpha Sapphire .3ds from the MODS panel first")
        return true
      end
      T.startBuild()
      return true
    end,
  }
end

-- ORAS PLAYER: which ORAS character stands in for the player's overworld
-- figure (OFF, then T.PLAYER_ORDER, built ones only).  Stored like every other
-- player model, in the PlayerModelInstall marker ("oras_character_<id>"), so
-- picking a Pokemon or a Colosseum character elsewhere replaces it.
T.PLAYER_ID = "oras_player"
local function playerChoices()
  local out = {}
  local idx = T.index()
  if not idx then return out end
  local have = {}
  for _, e in ipairs(idx.list) do have[e.id] = true end
  for _, id in ipairs(T.PLAYER_ORDER) do if have[id] then out[#out + 1] = id end end
  return out
end
function T.currentPlayer()
  local okI, Install = pcall(V.require, "PlayerModelInstall")
  local name = okI and Install and Install.modelFilename and Install.modelFilename()
  return type(name) == "string" and name:match("^oras_character_(.+)$") or nil
end
function T.setPlayer(id)
  local PlayerModel = V.require("PlayerModel")
  local Install = V.require("PlayerModelInstall")
  if not id then
    if T.currentPlayer() then
      PlayerModel.clear()
      Install.writeMarker("")
    end
    return true
  end
  PlayerModel.clear()
  local ok, why = PlayerModel.loadORASCharacter(id)
  if not ok then
    log("warn", "ORAS PLAYER: %s", tostring(why))
    return false
  end
  Install.writeMarker("oras_character_" .. id)
  return true
end
function T.playerRow()
  return {
    id = T.PLAYER_ID,
    label = "ORAS PLAYER",
    value = function()
      if not T.built() then return "BUILD TRAINERS" end
      local id = T.currentPlayer()
      return id and T.label(id) or "OFF"
    end,
    step = function(_, dir)
      local list = playerChoices()
      if #list == 0 then return true end
      local cur, at = T.currentPlayer(), 0
      for i, id in ipairs(list) do if id == cur then at = i end end
      at = (at + ((dir or 1) < 0 and -1 or 1)) % (#list + 1)
      T.setPlayer(at > 0 and list[at] or nil)
      return true
    end,
  }
end

return T
