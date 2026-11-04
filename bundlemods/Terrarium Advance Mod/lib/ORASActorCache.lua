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

-- Compact pose banks ("OQ16"), written by lib/ORASActorCache.lua and read
-- back by RuntimeMeshCache.meshFromBytes.  A bank is rows of 44 float32
-- (slot-0 position, uv, normal, slots 1-12 positions); the compact file is
--   "OQ16", u32 rows, f32 posScale, f32 uvScale, u32 zlen, then zlen bytes
--   of zlib, zero-padded so the file size is a multiple of 176 (one float
--   row) -- the size checks that guard plain banks pass unchanged.
-- Inflated: rows * 44 int16, low bytes first (all of them), then high bytes.
-- Per row: position * posScale, uv * uvScale, normal * 32000, then each of
-- slots 1-12 as (quantized position - the previous slot's), wrapped to 16
-- bits (exact: every quantized position fits int16), so the poses of a
-- vertex, which barely move, become small numbers zlib packs well.
local Q16_ROW = 44
local function packQ16(get, n)
  if not (ffi and love and love.data and love.data.compress) then return nil end
  if n <= 0 or n % Q16_ROW ~= 0 then return nil end
  local rows = n / Q16_ROW
  local pmax, umax = 1e-6, 1e-6
  for r = 0, rows - 1 do
    local o = r * Q16_ROW
    for c = 0, Q16_ROW - 1 do
      local a = math.abs(get(o + c))
      if c == 3 or c == 4 then
        if a > umax then umax = a end
      elseif c < 3 or c >= 8 then
        if a > pmax then pmax = a end
      end
    end
  end
  local ps, us = 32000 / pmax, 32000 / umax
  local floor = math.floor
  local buf = ffi.new("uint8_t[?]", n * 2)
  local function put(i, q)
    if q < -32768 or q > 32767 then return false end
    if q < 0 then q = q + 65536 end
    buf[i] = q % 256
    buf[n + i] = floor(q / 256)
    return true
  end
  for r = 0, rows - 1 do
    local o = r * Q16_ROW
    local prev = {}
    for c = 0, 2 do
      local q = floor(get(o + c) * ps + 0.5)
      prev[c] = q
      put(o + c, q)
    end
    for c = 3, 4 do put(o + c, floor(get(o + c) * us + 0.5)) end
    for c = 5, 7 do put(o + c, floor(get(o + c) * 32000 + 0.5)) end
    for c = 8, Q16_ROW - 1 do
      local k = (c - 8) % 3
      local q = floor(get(o + c) * ps + 0.5)
      local d = (q - prev[k]) % 65536
      if d >= 32768 then d = d - 65536 end
      put(o + c, d)
      prev[k] = q
    end
  end
  local okZ, z = pcall(love.data.compress, "string", "zlib", ffi.string(buf, n * 2), 9)
  if not (okZ and type(z) == "string") then return nil end
  local head = ffi.new("uint32_t[5]")
  ffi.copy(head, "OQ16", 4)
  head[1] = rows
  ffi.cast("float*", head)[2] = ps
  ffi.cast("float*", head)[3] = us
  head[4] = #z
  local out = ffi.string(head, 20) .. z
  local pad = (176 - #out % 176) % 176
  return out .. string.rep("\0", pad)
end
C.packQ16 = packQ16

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

-- Read a cache file, packed or loose.  mod.cache only sees loose files; once
-- ORAS PACK has run, base.lua and the banks live in cbe_cache_archive/oras
-- and only the archive can read them.  In game this module is loaded with the
-- mod's main V, which has no GeneratedAssets (that lives in the Colosseum
-- namespace), so the shared archive (mod.exports.cacheArchive) is asked
-- directly.
local function readCache(mod, path)
  local G = V.GeneratedAssets
  if G and type(G.read) == "function" then
    local okG, data = pcall(G.read, path)
    if okG and type(data) == "string" then return data end
  end
  local okL, data = pcall(mod.cache.read, mod.cache, path)
  if okL and type(data) == "string" then return data end
  local A = mod.exports and mod.exports.cacheArchive
  if A and type(A.readEntry) == "function" then
    local okA, packed = pcall(A.readEntry, path)
    if okA and type(packed) == "string" then return packed end
  end
  return nil
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
--
-- All 28 slots, as found over the 721 species of the dump (count = species
-- that have the slot): 0 idle A (721), 1 idle B (342), 2 idle C (2), 3-5 the
-- send-out from the ball: drop / land / recover (517), 6 the flyers'
-- send-out (205), 8-11 physical (683/65/5/-), 12-15 special (706/90/22/-),
-- 16 damage (721), 17 faint (702), 18 a 200-frame loop that moves no bone
-- (fire species, Zygarde: material-only, for effects later), 22-27 rare,
-- 25 the cry: 70 frames that move only the jaw (370).
--
-- `chain` plays several slots back to back; `over` lays a slot's animated
-- channels over the idle loop (the cry moves only the jaw).
local ACTIONS = {
  { name = "physicalA", slot = 8 }, { name = "physicalB", slot = 9 },
  { name = "physicalC", slot = 10 }, { name = "physicalD", slot = 11 },
  { name = "specialA", slot = 12 }, { name = "specialB", slot = 13 },
  { name = "specialC", slot = 14 },
  { name = "damage", slot = 16 },     -- ba30_damageS
  { name = "faint", slot = 17 },      -- ba41_down
  { name = "appear", chain = { 3, 4, 5 }, alt = 6 },
  { name = "cry", slot = 25, over = true },
  { name = "idleB", slot = 1 },
}
local IDLE_SLOT = 0                   -- ba10_waitA
-- action banks are paged so each pose is at most this many source frames
-- apart (30 fps); the idle base bank stays one page of 13 poses
local ACTION_FRAMES_PER_SLOT = 3

-- effect textures that are intensity maps: L8, A8, LA4, L4, A4 (PICA.FORMAT)
local GLOW_FORMATS = { [7] = true, [8] = true, [9] = true, [10] = true, [11] = true }
-- Flame colours.  The outer flame's material constant reads 0x801A32FF
-- (255, 50, 26); the core is drawn white-hot in the game.
local function glowColor(name)
  name = tostring(name or "")
  if name:find("Fire") and name:find("Core") then return { 1.0, 0.82, 0.38 } end
  if name:find("Fire") then return { 1.0, 0.36, 0.12 } end
  return { 1.0, 1.0, 1.0 }
end
-- Is this texture an effect (flame) map?  Shared ones (Charizard: FireCoreA1)
-- carry no species prefix; Gen 4/5 species' own (Chimchar:
-- pm0390_00_FireCoreA1) do, so a prefixed name still counts when it names
-- an effect and is an intensity format.
local EFFECT_WORDS = { "Fire", "Flame", "Sten", "Glow" }
local function effectTexture(prefix, tname, t)
  if not (tname and t and GLOW_FORMATS[t.format]) then return false end
  if tname:sub(1, #prefix) ~= prefix then return true end
  local rest = tname:sub(#prefix + 1)
  for _, w in ipairs(EFFECT_WORDS) do
    if rest:find(w, 1, true) then return true end
  end
  return false
end
C.effectTexture = effectTexture
local FPS = 30
-- bumped whenever the cache layout changes: a species whose rev.txt holds an
-- older stamp is rebuilt, one with this stamp is skipped
-- =7: species-prefixed flame textures became glow groups.
-- =8: paged action banks (ACTION_FRAMES_PER_SLOT), joint positions, the
-- drop/land/recover send-out, cry and idleB.
local ORAS_STAMP = "oras-actor=8\n"
C.STAMP = ORAS_STAMP
-- q16.txt: this species' banks are compact.  "=1" was also written when the
-- in-game listing came back empty and nothing was converted, so only "=2"
-- counts as done.
local Q16_MARK = "oras-q16=2\n"

-- set by a background build (ORASModels) to yield between stages
local function checkpoint() if C.checkpoint then C.checkpoint() end end

-- uv offset (LOVE space: v = 1 - t) of moving texture coordinate 0's
-- translation by dx, dy, per H3D.uvTransform's three transform kinds
local function uvDelta(t, dx, dy)
  local ca, sa = math.cos(t.rot or 0), math.sin(t.rot or 0)
  local du, dt
  if t.kind == 0 then du, dt = -t.sx * dx, -t.sy * dy
  elseif t.kind == 1 then du, dt = t.sx * (-ca * dx - sa * dy), t.sy * (sa * dx - ca * dy)
  elseif t.kind == 2 then du, dt = -t.sx * ca * dx - t.sx * sa * dy, -t.sy * sa * dx + t.sy * ca * dy
  else return 0, 0 end
  return du, -dt
end

-- Eye sheets.  Part 1 of the face-animation member (block slot 2) is
-- pmNNNN_FF_eye01, which walks texture coordinate 0 across the eye sheet's
-- cells in order: the rest cell (open), then half closed, then closed (then
-- expressions).  Returns material name -> { du1, dv1, du2, dv2 }: the uv
-- offsets of cells 1 and 2 from the rest cell, for PokemonActors' blink.
local function eyeBlinks(g, base, model)
  local out = {}
  local okP, pd, ph = pcall(packBch, g, base + 2, 1)
  if not (okP and pd) then return out end
  local okA, anims = pcall(H3D.materialAnimations, pd, ph)
  local anim = okA and anims and anims[1]
  if not (anim and tostring(anim.name or ""):find("eye")) then return out end
  local mats = {}
  for _, m in ipairs(model.materials) do if m.name then mats[m.name] = m end end
  for _, el in ipairs(anim.elements) do
    local mat = mats[el.material or ""]
    local t = mat and mat.uvTransform
    if el.target == H3D.TARGET.texCoord0Trans and t and (el.x or el.y) then
      -- the plateaus the animation steps through, in order
      local cells, last = {}, nil
      for f = 0, math.floor(anim.frames or 0) do
        local x = H3D.sampleCurve(el.x, f) or t.tx
        local y = H3D.sampleCurve(el.y, f) or t.ty
        local key = ("%.3f,%.3f"):format(x, y)
        if key ~= last then cells[#cells + 1] = { x, y }; last = key end
        if #cells >= 3 then break end
      end
      local rest = cells[1]
      if #cells >= 3 and math.abs(rest[1] - t.tx) < 1e-3 and math.abs(rest[2] - t.ty) < 1e-3 then
        local du1, dv1 = uvDelta(t, cells[2][1] - rest[1], cells[2][2] - rest[2])
        local du2, dv2 = uvDelta(t, cells[3][1] - rest[1], cells[3][2] - rest[2])
        out[el.material] = { du1, dv1, du2, dv2 }
      end
    end
  end
  -- eye01 can name one eye only (Pikachu: REye); the other eye on the same
  -- sheet with the same transform blinks with it
  for name, m in pairs(mats) do
    if not out[name] and m.uvTransform and m.textures and m.textures[1] then
      for other, b in pairs(out) do
        local o = mats[other]
        local a, t = m.uvTransform, o and o.uvTransform
        if t and o.textures and o.textures[1] == m.textures[1] and a.kind == t.kind
            and a.sx == t.sx and a.sy == t.sy and a.rot == t.rot then
          out[name] = b
          break
        end
      end
    end
  end
  return out
end

-- Posed size.  The bind pose is a poor guide to how big a Pokemon is drawn:
-- Rayquaza stands straight up in it (about 11 m) but coils far lower in its
-- idle, and some meshes sit away from where the animation puts them
-- (Bulbasaur).  So the size recorded is the extent over every idle slot of
-- the body groups (glows excluded), in cache units, plus the same extent in
-- the model's own units -- Game Freak models are authored at real size, in
-- centimetres.  PokemonActors sizes ORAS species from these (nativeHeight /
-- nativeSpan) instead of the Pokedex number, which for wide or long species
-- (Wingull's wingspan, Rayquaza's length) is not a height at all.
local function newExtent()
  return { lo = { math.huge, math.huge, math.huge }, hi = { -math.huge, -math.huge, -math.huge } }
end
local function grow(ext, x, y, z)
  local lo, hi = ext.lo, ext.hi
  if x < lo[1] then lo[1] = x end; if x > hi[1] then hi[1] = x end
  if y < lo[2] then lo[2] = y end; if y > hi[2] then hi[2] = y end
  if z < lo[3] then lo[3] = z end; if z > hi[3] then hi[3] = z end
end
-- writes the posed size into meta; `s` is cache units per model unit
local function applyExtent(meta, ext, s)
  if not (ext.hi[2] > ext.lo[2]) then return false end
  local h = ext.hi[2] - ext.lo[2]
  local span = math.max(ext.hi[1] - ext.lo[1], ext.hi[3] - ext.lo[3])
  meta.posedHeight = h
  meta.nativeHeight = h / s
  meta.nativeSpan = span / s
  local b = meta.bounds or {}
  meta.bounds = {
    min = { (b.min and b.min[1]) or ext.lo[1], ext.lo[2], (b.min and b.min[3]) or ext.lo[3] },
    max = { (b.max and b.max[1]) or ext.hi[1], ext.hi[2], (b.max and b.max[3]) or ext.hi[3] },
    center = { 0, (ext.lo[2] + ext.hi[2]) / 2, 0 },
  }
  return true
end

-- Mesh-node visibility.  ORAS models carry alternative parts behind show /
-- hide switches (Pidgey's folded wings: LWingCloseSkin / RWingCloseSkin),
-- and each battle motion has a visibility animation, part slot + 3 of the
-- battle-motion member, that turns them on and off by node name.  Pidgey's
-- faint shows the folded wings for frames 0-2 and hides them from frame 3,
-- when the open wings spread; drawn always, the bird had four wings.
--
-- Returns nil when no node of this species is ever hidden (most), else
--   { groupNode = { [group] = node }, nodeNames = { [node] = name },
--     tracks = { [action] = { frames = n, nodes = { [node] = "1110000..." } } } }
-- one character per source frame 0..n ("1" shown); "idle" is the base bank.
-- `groupMeshes[m]` is group m's H3D mesh; `actions` the meta.actions table.
local VIS_SLOT_PART = 3
local VIS_VERSION = 1   -- meta.visibilityVersion: this species has been looked at
local function visibilityFor(g, base, model, motions, groupMeshes, actions)
  local names, default = model.nodeNames or {}, model.nodeVisible or {}
  local anims = {}
  local function animFor(slot)
    if anims[slot] == nil then
      anims[slot] = false
      local okP, pd, ph = pcall(packBch, g, base + 6, slot + VIS_SLOT_PART)
      if okP and pd then
        local okA, list = pcall(H3D.visibilityAnimations, pd, ph)
        if okA and list and list[1] then anims[slot] = list[1] end
      end
    end
    return anims[slot] or nil
  end
  local function framesOf(slot)
    local m = motions[slot]
    local a = animFor(slot)
    return math.max(1, math.floor((m and m.frames) or (a and a.frames) or 1))
  end
  -- `node` over motion `slot`: frames 0..n-1, and n too when it ends the track
  local function slotString(slot, node, withLast)
    local a = animFor(slot)
    local el = a and names[node] and a.elements[names[node]]
    local n = framesOf(slot)
    local out = {}
    for f = 0, withLast and n or n - 1 do
      local v
      if el then v = H3D.sampleVisibility(el, f) end
      if v == nil then v = default[node] ~= false end
      out[#out + 1] = v and "1" or "0"
    end
    return table.concat(out), n
  end
  local function actionTrack(a, nodes)
    local slots = {}
    if a.chain then
      local all = true
      for _, sl in ipairs(a.chain) do
        if not (motions[sl] and motions[sl].frames > 0) then all = false end
      end
      if all then slots = a.chain elseif a.alt and motions[a.alt] then slots = { a.alt } end
    elseif motions[a.slot] then
      slots = { a.slot }
    end
    if #slots == 0 then return nil end
    local track = { frames = 0, nodes = {} }
    for _, node in ipairs(nodes) do
      local parts, total = {}, 0
      for i, sl in ipairs(slots) do
        local str, n = slotString(sl, node, i == #slots)
        parts[i] = str; total = total + n
      end
      track.nodes[node] = table.concat(parts)
      track.frames = total
    end
    return track
  end
  local used, nodes = {}, {}
  for _, mesh in ipairs(groupMeshes) do
    local node = mesh.nodeIndex
    if node and not used[node] then used[node] = true; nodes[#nodes + 1] = node end
  end
  table.sort(nodes)
  local tracks = { idle = actionTrack({ slot = IDLE_SLOT }, nodes) }
  for _, a in ipairs(ACTIONS) do
    if actions[a.name] and not actions[a.name].alias then tracks[a.name] = actionTrack(a, nodes) end
  end
  for name, spec in pairs(actions) do
    if spec.alias and tracks[spec.alias] then tracks[name] = tracks[spec.alias] end
  end
  -- keep only the switch nodes: ones some track turns off
  local switching = {}
  for _, track in pairs(tracks) do
    for node, str in pairs(track.nodes) do
      if str:find("0", 1, true) then switching[node] = true end
    end
  end
  if not next(switching) then return nil end
  for _, track in pairs(tracks) do
    for node in pairs(track.nodes) do
      if not switching[node] then track.nodes[node] = nil end
    end
  end
  local groupNode, nodeNames = {}, {}
  for m, mesh in ipairs(groupMeshes) do
    if switching[mesh.nodeIndex] then groupNode[m] = mesh.nodeIndex end
  end
  for node in pairs(switching) do nodeNames[node] = names[node] end
  return { groupNode = groupNode, tracks = tracks, nodeNames = nodeNames }
end
C.visibilityFor = visibilityFor

-- Does a keyed curve actually move over frames 0..n?  Some cries key a
-- channel at one fixed value (Growlithe's Waist roll, 1.57 throughout), in
-- the cry's own reference pose.  Laid over the idle loop as if it moved, it
-- replaced that one rotation channel and left the idle's others: the body
-- turned 90 degrees onto its side for the whole cry.
local CRY_SLOT = 25
local CRY_FIX = 1        -- meta.cryFix: cry bank built with flat channels left out
local function curveMoves(curve, frames)
  local GF1 = V.require("GF1Motion")
  local lo, hi = math.huge, -math.huge
  for f = 0, math.max(1, math.floor(frames or 1)) do
    local v = GF1.sample(curve, f)
    if v then
      if v < lo then lo = v end
      if v > hi then hi = v end
      if hi - lo > 1e-3 then return true end
    end
  end
  return false
end
-- a species whose cry has a flat keyed channel (its cry bank needs rebuilding)
local function cryHasFlatChannel(motions)
  local cry = motions and motions[CRY_SLOT]
  if not (cry and motions[IDLE_SLOT]) then return false end
  for _, c in pairs(cry.curves) do
    if c.kind ~= "const" and not curveMoves(c, cry.frames) then return true end
  end
  return false
end
local function motionsOf(g, index, dex)
  local rec = (dex - 1) * 4 + 1
  if rec + 3 > #index then return nil end
  local base = FIRST_MEMBER + u16(index, rec) * PER_FORM
  local okPb, pb = pcall(g.member, g, base + 6)
  if not (okPb and pb and #pb >= 12 and u16(pb, 3) > 0) then return nil end
  local okRead, _, mots = pcall(V.require("GF1Motion").readPack, pb:sub(u32(pb, 5) + 1, u32(pb, 9)))
  return okRead and mots or nil
end

-- Haunter's and Gengar's Body_Mask (node MaskSkin): a lid over the open
-- mouth whose UVs point off the texture (plain body purple).  The game never
-- shows it as a surface (a stencil / depth helper); drawn, it hid the mouth
-- and tongue.  Only those two species have one.
local function isMask(mat)
  local n = tostring(mat and mat.name or ""):lower()
  return n:find("_mask$") ~= nil
end

-- SSC_FIX (meta.sscFix): banks posed with segment scale compensation
-- (H3D.compensate).  A species built before it is rebuilt only when that
-- changes its poses: a motion scales a bone whose child compensates, or it
-- has a mask mesh to drop.
local SSC_FIX = 1
local SSC_MARK = "oras-ssc=1"
local function needsScaleFix(g, index, dex)
  local base, _, _, model = findSpecies(g, index, dex)
  if not base then return false end
  for _, mat in ipairs(model.materials) do if isMask(mat) then return true, "mouth mask" end end
  local okPb, pb = pcall(g.member, g, base + 6)
  if not (okPb and pb and #pb >= 12 and u16(pb, 3) > 0) then return false end
  local GF1 = V.require("GF1Motion")
  local okRead, skel, mots = pcall(GF1.readPack, pb:sub(u32(pb, 5) + 1, u32(pb, 9)))
  if not (okRead and skel and mots) then return false end
  -- bones with a compensating child
  local parentOf = {}
  for _, bone in ipairs(model.bones) do
    if bone.parent >= 0 and math.floor((bone.flags or 0) / H3D.SSC_FLAG) % 2 == 1 then
      local p = model.bones[bone.parent + 1]
      if p then parentOf[p.name] = true end
    end
  end
  for gi, b in ipairs(skel) do
    if parentOf[b.name] then
      for _, m in pairs(mots) do
        for c = 6, 8 do
          local cv = m.curves[(gi - 1) * 9 + c]
          if cv then
            for f = 0, m.frames do
              local v = GF1.sample(cv, f)
              if v and math.abs(v - 1) > 1e-3 and math.abs(v) > 1e-6 then return true, "scaled " .. b.name end
            end
          end
        end
      end
    end
  end
  return false
end
C._needsScaleFix = needsScaleFix

-- The bake shared by species and characters (lib/ORASTrainers.lua): one
-- skinned model + its motions -> a PokemonActors cache under A.dir.
--   A.model, A.textures / A.texData (decoded H3D textures + their relocated
--   BCH), A.shinyTextures / A.shinyData (optional), A.motions (GF1Motion
--   slots), A.pose (H3D.poser), A.blinks (eyeBlinks, optional),
--   A.select(mesh, mat) -> nil (skip) or { tname, glow, unit, wrapU, wrapV },
--   A.actions (ACTIONS-shaped list), A.idleSlot, A.stamp, A.dex, A.meta
--   (merged into the metadata), A.visibility(groupMeshes, actions),
--   A.attackAliases (false: no physicalA / specialA stand-ins), A.label.
local function bakeActor(mod, A)
  local model, textures, td = A.model, A.textures, A.texData
  local sd, shinyTextures = A.shinyData, A.shinyTextures or {}
  local motions, pose, blinks = A.motions or {}, A.pose, A.blinks or {}
  local ACTIONS = A.actions or ACTIONS
  local IDLE_SLOT = A.idleSlot or IDLE_SLOT
  local ORAS_STAMP = A.stamp or ORAS_STAMP
  local Q16_MARK = A.q16Mark or Q16_MARK
  -- kept meshes (effect meshes skipped, see below), their bind data and
  -- skinning recipes; bounds from the bind pose normalize every frame alike
  local kept, glows, skipped = {}, {}, 0
  local lo, hi = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
  for _, mesh in ipairs(model.meshes) do
    local mat = model.materials[mesh.materialIndex + 1] or {}
    local pick = A.select(mesh, mat)
    -- Effect meshes (flames, glows: FireCoreA, FireStenA, ...) sample shared
    -- effect textures through the game's additive/stencil shaders.  Drawn as
    -- ordinary surfaces they are black and white blobs.  Those whose texture
    -- is an intensity map (luminance / alpha formats) become GLOW groups:
    -- the intensity is baked into a flame colour and PokemonActors draws them
    -- unlit and additive, after the body.  Anything else is still skipped.
    if pick then
      local tname, glow = pick.tname, pick.glow
      local bind = H3D.bindPose(model, mesh, pick.unit)
      local entry = { mesh = mesh, mat = mat, tname = tname, bind = bind,
                      skin = H3D.skinning(model, mesh),
                      wrapU = pick.wrapU or mat.wrapU, wrapV = pick.wrapV or mat.wrapV }
      if glow then
        entry.glow = true
        entry.glowColor = glowColor(tname)
        glows[#glows + 1] = entry
      else
        kept[#kept + 1] = entry
        -- only the body sizes the model: a tail flame must not shrink it
        for _, v in ipairs(bind) do
          for k = 1, 3 do
            if v.position[k] < lo[k] then lo[k] = v.position[k] end
            if v.position[k] > hi[k] then hi[k] = v.position[k] end
          end
        end
      end
    else
      skipped = skipped + 1
    end
  end
  -- glow groups draw after every body group
  for _, entry in ipairs(glows) do kept[#kept + 1] = entry end
  if #kept == 0 then return nil, "no drawable meshes" end
  local height = hi[2] - lo[2]
  if not (height > 0) then return nil, "model has no height" end
  local s = TARGET_HEIGHT / height
  local cx, cz = (lo[1] + hi[1]) / 2, (lo[3] + hi[3]) / 2

  -- positions[meshIndex][slot][vertex] = { x, y, z }, normalized; joints[slot]
  -- [bone] = { x, y, z } (model bone order, the same space).  A one-shot bank
  -- covers frames f0..f1 (default 0..frames).
  local function sampleBank(motion, frames, looping, f0, f1)
    local out, joints = {}, {}
    for m = 1, #kept do out[m] = {} end
    f0, f1 = f0 or 0, f1 or frames
    for slot = 0, MORPH_SLOTS do
      local frame = motion and (looping and slot * frames / (MORPH_SLOTS + 1) or f0 + slot * (f1 - f0) / MORPH_SLOTS) or 0
      local skin, world = pose(motion, frame)
      local js = {}
      for bi, bone in ipairs(model.bones) do
        local w = motion and world[bi] or bone.world
        js[bi] = { (w[4] - cx) * s, (w[8] - lo[2]) * s, (w[12] - cz) * s }
      end
      joints[slot] = js
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
    return out, joints
  end

  local dir = A.dir
  local rt = dir .. "/runtime_mesh_v1"

  -- textures, normal and shiny
  local texPaths, shinyPaths, texCount = {}, {}, 0
  local function decodeTo(data, t, path, entry)
    local okT, img = pcall(PICA.decodeTexture, data, t.address, t.width, t.height, t.format)
    if not (okT and img) then return nil end
    if entry.glow then
      -- intensity (luminance x alpha) -> the flame colour, with the
      -- intensity as alpha: additive blending adds colour * intensity
      local c = entry.glowColor
      img:mapPixel(function(_, _, r, _, _, a)
        local v = r * a
        return c[1], c[2], c[3], v
      end)
    end
    assert(mod.cache:write(path, img:getString()) ~= false, "texture write failed: " .. path)
    checkpoint()
    return { path = path, w = t.width, h = t.height,
             wrapS = WRAP[entry.wrapU] or 1, wrapT = WRAP[entry.wrapV] or 1 }
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
      local bytes = packQ16(function(i) return values[i + 1] end, n) or packFloats(values, n)
      assert(mod.cache:write(pathOf(m), bytes) ~= false, "bank write failed: " .. pathOf(m))
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

  -- the motion an ACTIONS row plays, and the slot it reports as its clip
  local idle = motions[IDLE_SLOT]
  local function composeAction(a)
    if a.chain then
      local parts, total = {}, 0
      for _, sl in ipairs(a.chain) do
        local m = motions[sl]
        if m and m.frames > 0 then parts[#parts + 1] = { m = m, start = total }; total = total + m.frames end
      end
      if #parts == #a.chain then
        -- every channel any part animates; a part that leaves one out holds
        -- the bind value there, as it would on its own
        local keys = {}
        for _, part in ipairs(parts) do for k in pairs(part.m.curves) do keys[k] = true end end
        local curves = {}
        for k in pairs(keys) do
          local list = {}
          for i, part in ipairs(parts) do
            list[i] = { curve = part.m.curves[k], start = part.start, stop = part.start + part.m.frames }
          end
          curves[k] = { kind = "seq", parts = list }
        end
        return { frames = total, curves = curves }, a.chain[1]
      end
      if a.alt and motions[a.alt] then return motions[a.alt], a.alt end
      return nil
    end
    local m = motions[a.slot]
    if not m then return nil end
    if a.over and idle then
      local curves = {}
      for k, c in pairs(idle.curves) do
        curves[k] = c.kind == "const" and c or { kind = "wrap", inner = c, period = math.max(1, idle.frames) }
      end
      for k, c in pairs(m.curves) do
        if c.kind ~= "const" and curveMoves(c, m.frames) then curves[k] = c end
      end
      return { frames = m.frames, curves = curves }, a.slot
    end
    return m, a.slot
  end

  -- base bank: the idle loop (or the bind pose, static, if there is none)
  local basePositions, baseJoints = sampleBank(idle, idle and idle.frames or 0, true)
  local baseFloor, vertexTotal = writeBank(basePositions, function(m) return ("%s/base_%02d.f32"):format(rt, m) end)
  local baseJointFrames = {}
  for k = 1, MORPH_SLOTS do baseJointFrames[k] = baseJoints[k] end
  local boneNames = {}
  for bi, bone in ipairs(model.bones) do boneNames[bi] = bone.name end
  local posed = newExtent()
  for m, entry in ipairs(kept) do
    if not entry.glow then
      for slot = 0, MORPH_SLOTS do
        local list = basePositions[m][slot]
        for _, vi in ipairs(entry.order) do
          local q = list[vi]
          grow(posed, q[1], q[2], q[3])
        end
      end
    end
  end

  -- action banks, written straight into PokemonActors' runtime sidecar form
  -- One-shot banks are paged (PokemonActors' dense pages: action_<name>.lua
  -- lists them, page i's files are action_<name>_page<i>_NN.f32 / _floor.lua)
  -- so poses are at most ACTION_FRAMES_PER_SLOT source frames apart.
  local actions, baked = {}, {}
  for _, a in ipairs(ACTIONS) do
    local motion, slot = composeAction(a)
    if motion and motion.frames > 0 then
      local duration = motion.frames / FPS
      local pageCount = math.max(1, math.ceil(motion.frames / (ACTION_FRAMES_PER_SLOT * MORPH_SLOTS)))
      local pages = {}
      for pi = 1, pageCount do
        local f0, f1 = motion.frames * (pi - 1) / pageCount, motion.frames * pi / pageCount
        local positions, joints = sampleBank(motion, motion.frames, false, f0, f1)
        local tag = ("%s_page%d"):format(a.name, pi)
        local floor = writeBank(positions, function(m)
          return ("%s/action_%s_%02d.f32"):format(rt, tag, m)
        end)
        writeLua(mod, ("%s/action_%s_floor.lua"):format(rt, tag), {
          runtimeMeshVersion = 1, stamp = ORAS_STAMP, groupCount = #kept, floorMinYSlots = floor,
        })
        local jointFrames = {}
        for k = 1, MORPH_SLOTS do jointFrames[k] = joints[k] end
        pages[pi] = { startPhase = (pi - 1) / pageCount, endPhase = pi / pageCount,
          morphFrames = MORPH_SLOTS, groupCount = #kept,
          jointPositions = joints[0], jointFrames = jointFrames }
      end
      writeLua(mod, ("%s/action_%s.lua"):format(rt, a.name), {
        runtimeMeshVersion = 1, stamp = ORAS_STAMP, clip = slot, duration = duration,
        frameSpacing = 1, totalIntervals = pageCount * MORPH_SLOTS, pages = pages,
      })
      actions[a.name] = { clip = slot, duration = duration }
      baked[#baked + 1] = ("%s %.2fs/%dp"):format(a.name, duration, pageCount)
    end
  end

  -- a species with motions of only one attack family (Caterpie has no
  -- physical one) plays that one for both
  if A.attackAliases ~= false and not actions.physicalA then
    local other = actions.physicalB and "physicalB" or (actions.specialA and "specialA")
    if other then actions.physicalA = { alias = other, clip = actions[other].clip, duration = actions[other].duration } end
  end
  if A.attackAliases ~= false and not actions.specialA and actions.physicalA and not actions.physicalA.alias then
    actions.specialA = { alias = "physicalA", clip = actions.physicalA.clip, duration = actions.physicalA.duration }
  end

  local groups = {}
  for m, entry in ipairs(kept) do
    groups[m] = {
      material = entry.mat.name or ("mesh" .. m), texture = texPaths[entry.tname],
      textureShiny = shinyPaths[entry.tname] or texPaths[entry.tname],
      glow = entry.glow == true,
      blink = blinks[entry.mat.name],
      diffuse = { 1, 1, 1 }, ambient = { 1, 1, 1 }, specular = { 0, 0, 0 }, alpha = 1, shininess = 0,
      xlu = entry.glow == true, noz = false, renderFlags = 0, shadow = false, effect = entry.glow == true, textureSlot = -1,
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
    dex = A.dex, stem = model.name or "", source = "ORAS",
    clip = IDLE_SLOT, clipCount = 0, frameSpacing = 1,
    idleDuration = idle and idle.frames / FPS or 0,
    morphFrames = idle and MORPH_SLOTS or 0, morphSlots = MORPH_SLOTS,
    vertexCount = vertexTotal, groupCount = #groups,
    heightRatio = 1, widthRatio = (hi[1] - lo[1]) / height,
    bounds = { min = { -hx, 0, -hz }, max = { hx, TARGET_HEIGHT, hz }, center = { 0, TARGET_HEIGHT / 2, 0 } },
    floorMinY = minFloor,
    jointPositions = baseJoints[0], jointFrames = baseJointFrames,
    boneNames = boneNames,
    actions = actions, groups = groups, cryFix = CRY_FIX, sscFix = SSC_FIX,
  }
  applyExtent(meta, posed, s)
  do
    local groupMeshes = {}
    for m, entry in ipairs(kept) do groupMeshes[m] = entry.mesh end
    if A.visibility then
      local okV, vis = pcall(A.visibility, groupMeshes, actions)
      if okV then meta.orasVisibility = vis end
    end
    meta.visibilityVersion = VIS_VERSION
  end
  -- ORAS field characters are authored chibi-sized (the player stands 31 cm):
  -- the size PokemonActors reads is scaled to the person's real height
  if A.nativeScale and meta.nativeHeight then
    meta.nativeHeight = meta.nativeHeight * A.nativeScale
    meta.nativeSpan = (meta.nativeSpan or 0) * A.nativeScale
  end
  for k, v in pairs(A.meta or {}) do meta[k] = v end
  -- base.lua is what PokemonActors loads (its stamp matches rev.txt);
  -- model_cache.lua is the same table, which marks the species as present
  assert(writeLua(mod, rt .. "/base.lua", meta), "runtime base write failed")
  assert(writeLua(mod, dir .. "/model_cache.lua", meta), "model cache write failed")
  mod.cache:write(dir .. "/rev.txt", ORAS_STAMP)
  mod.cache:write(dir .. "/q16.txt", Q16_MARK)

  local blinkCount = 0
  for _ in pairs(blinks) do blinkCount = blinkCount + 1 end
  return ("%s: %d groups (%d glow, %d blink), %d verts, %d textures, %d effect meshes skipped, idle %s, actions %s (%s)"):format(
    tostring(model.name), #groups, #glows, blinkCount, vertexTotal, texCount, skipped,
    idle and ("%.2fs"):format(idle.frames / FPS) or "none",
    #baked > 0 and table.concat(baked, ", ") or "none", A.label or "")
end
C.bakeActor = bakeActor

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
  -- composite motions (ACTIONS `chain` / `over`) carry kind "seq" / "wrap"
  -- curves; a nil sample keeps the bone's bind value (H3D.poser)
  local function sampleCurve(curve, f)
    if curve.kind == "wrap" then return GF1.sample(curve.inner, f % curve.period) end
    if curve.kind == "seq" then
      local parts = curve.parts
      local part = parts[#parts]
      for _, q in ipairs(parts) do
        if f <= q.stop then part = q; break end
      end
      if not part.curve then return nil end
      return GF1.sample(part.curve, math.min(f, part.stop) - part.start)
    end
    return GF1.sample(curve, f)
  end
  local pose = H3D.poser(model, sampleCurve, names)
  local blinks = eyeBlinks(g, base, model)

  -- species meshes: their own (pmNNNN-prefixed) textures, plus effect
  -- meshes whose texture is an intensity map (glows); masks and the rest are
  -- skipped
  local prefix = (model.name or ""):match("^(pm%d+)") or "pm"  -- Natu (pm0177) drops the _00
  local function select(mesh, mat)
    local tname = mat.textures and mat.textures[1]
    local t = tname and textures[tname]
    local glow = effectTexture(prefix, tname, t)
    local own = not glow and tname and tname:sub(1, #prefix) == prefix
      and not isMask(mat)
    if own or glow then return { tname = tname, glow = glow } end
    return nil
  end
  return bakeActor(mod, {
    model = model, textures = textures, texData = td,
    shinyTextures = shinyTextures, shinyData = sd,
    motions = motions, pose = pose, blinks = blinks, select = select,
    dir = root(dex), dex = dex, label = ("members %d-%d"):format(base, base + 7),
    visibility = function(groupMeshes, actions)
      return visibilityFor(g, base, model, motions, groupMeshes, actions)
    end,
  })
end

-- A species built before posed sizes were recorded: measure it from its
-- cached base bank (44 floats a row: slot-0 position, uv, normal, then slots
-- 1-12) and the model's bind height (to recover the cache scale), then
-- rewrite its metadata.  No banks are rebuilt.
local function patchSize(mod, g, index, dex)
  if not ffi then return false end
  local rt = root(dex) .. "/runtime_mesh_v1"
  local okS, src = pcall(readCache, mod, rt .. "/base.lua")
  if not (okS and type(src) == "string") then return false end
  local chunk = loadstring(src)
  local okM, meta = pcall(chunk or error)
  if not (okM and type(meta) == "table" and type(meta.groups) == "table") then return false end
  if meta.nativeHeight then return false end
  local okF, base, _, _, model = pcall(findSpecies, g, index, dex)
  if not (okF and base and model) then return false end
  local prefix = (model.name or ""):match("^(pm%d+)") or "pm"
  local lo, hi = math.huge, -math.huge
  for _, mesh in ipairs(model.meshes) do
    local mat = model.materials[mesh.materialIndex + 1] or {}
    local tname = mat.textures and mat.textures[1]
    local fx = false
    if tname then
      for _, w in ipairs(EFFECT_WORDS) do
        if tname:find(w, #prefix + 1, true) then fx = true end
      end
    end
    if tname and tname:sub(1, #prefix) == prefix and not fx then
      for _, v in ipairs(H3D.bindPose(model, mesh)) do
        if v.position[2] < lo then lo = v.position[2] end
        if v.position[2] > hi then hi = v.position[2] end
      end
    end
  end
  if not (hi > lo) then return false end
  local s = TARGET_HEIGHT / (hi - lo)
  local posed = newExtent()
  for _, grp in ipairs(meta.groups) do
    if not grp.glow and grp.runtimeBin then
      local okB, data = pcall(readCache, mod, grp.runtimeBin)
      if okB and type(data) == "string" and #data >= 44 * 4 and data:sub(1, 4) ~= "OQ16" then
        local f = ffi.cast("const float*", data)
        for r = 0, math.floor(#data / (44 * 4)) - 1 do
          local o = r * 44
          grow(posed, f[o], f[o + 1], f[o + 2])
          for k = 0, MORPH_SLOTS - 1 do
            local q = o + 8 + k * 3
            grow(posed, f[q], f[q + 1], f[q + 2])
          end
        end
      end
      checkpoint()
    end
  end
  if not applyExtent(meta, posed, s) then return false end
  assert(writeLua(mod, rt .. "/base.lua", meta), "runtime base write failed")
  assert(writeLua(mod, root(dex) .. "/model_cache.lua", meta), "model cache write failed")
  return true
end

-- A species built before mesh-node visibility was baked: work it out from
-- the ROM and rewrite only its metadata (base.lua, model_cache.lua).  Groups
-- are matched to meshes the way buildSpecies keeps them (own body meshes in
-- order, then glow meshes) and checked by material name.
-- Returns patched, hasSwitches.
local function patchVisibility(mod, g, index, dex)
  local rt = root(dex) .. "/runtime_mesh_v1"
  local okS, src = pcall(readCache, mod, rt .. "/base.lua")
  if not (okS and type(src) == "string") then return false end
  local chunk = loadstring(src)
  local okM, meta = pcall(chunk or error)
  if not (okM and type(meta) == "table" and type(meta.groups) == "table") then return false end
  if meta.visibilityVersion == VIS_VERSION then return false end
  local okF, base, _, _, model = pcall(findSpecies, g, index, dex)
  if not (okF and base and model) then return false end
  local td, th = packBch(g, base + 3, 1)
  local textures = td and H3D.textures(td, th) or {}
  local prefix = (model.name or ""):match("^(pm%d+)") or "pm"
  local bodies, glows = {}, {}
  for _, mesh in ipairs(model.meshes) do
    local mat = model.materials[mesh.materialIndex + 1] or {}
    local tname = mat.textures and mat.textures[1]
    local t = tname and textures[tname]
    if effectTexture(prefix, tname, t) then glows[#glows + 1] = mesh
    elseif tname and tname:sub(1, #prefix) == prefix then bodies[#bodies + 1] = mesh end
  end
  for _, mesh in ipairs(glows) do bodies[#bodies + 1] = mesh end
  if #bodies ~= #meta.groups then return false end
  for m, mesh in ipairs(bodies) do
    local mat = model.materials[mesh.materialIndex + 1] or {}
    if (mat.name or ("mesh" .. m)) ~= meta.groups[m].material then return false end
  end
  local motions = {}
  local okPb, pb = pcall(g.member, g, base + 6)
  if okPb and pb and #pb >= 12 and u16(pb, 3) > 0 then
    local GF1 = V.require("GF1Motion")
    local okRead, _, mots = pcall(GF1.readPack, pb:sub(u32(pb, 5) + 1, u32(pb, 9)))
    if okRead and mots then motions = mots end
  end
  local okV, vis = pcall(visibilityFor, g, base, model, motions, bodies, meta.actions or {})
  if not okV then return false end
  meta.orasVisibility = vis
  meta.visibilityVersion = VIS_VERSION
  assert(writeLua(mod, rt .. "/base.lua", meta), "runtime base write failed")
  assert(writeLua(mod, root(dex) .. "/model_cache.lua", meta), "model cache write failed")
  return true, vis ~= nil
end
C.patchVisibility = patchVisibility

-- A current species built before compact banks: rewrite every plain float
-- bank under its runtime_mesh_v1 as OQ16 (no ROM work; same names, so every
-- manifest stays valid), then mark it.  A file that is already compact, or
-- that does not encode (int16 overflow), is left as it is.
-- Returns banks seen, banks converted; nil + reason when nothing was listed
-- (then no mark, so the next build tries again).

-- the keys under `prefix`: walk the store's folder directly (in game
-- mod.cache:list can come back empty, see lib/CacheArchive.lua listKeys),
-- else mod.cache:list
local function listKeys(mod, prefix)
  local store = mod.cache and mod.cache.storage
  local base = type(store) == "table" and store.root
  local fs = (type(store) == "table" and type(store.fs) == "table" and store.fs)
    or (love and love.filesystem)
  if type(base) == "string" and fs and fs.getDirectoryItems and fs.getInfo then
    local out = {}
    local function walk(dir)
      for _, name in ipairs(fs.getDirectoryItems(dir) or {}) do
        local path = dir .. "/" .. name
        local info = fs.getInfo(path)
        if info and info.type == "directory" then walk(path)
        else
          local key = path:sub(#base + 2)
          local stem = key:match("^(.*)%.bin$") or key:match("^(.*)%.rec$")
          if stem then out[#out + 1] = stem end
        end
      end
    end
    local info = fs.getInfo(base .. "/" .. prefix)
    if info and info.type == "directory" then walk(base .. "/" .. prefix) end
    if #out > 0 then return out end
  end
  local okL, keys = pcall(mod.cache.list, mod.cache, prefix)
  return (okL and type(keys) == "table") and keys or {}
end

local function compactSpecies(mod, dex)
  if not ffi then return nil, "no ffi" end
  local seen, converted = 0, 0
  for _, key in ipairs(listKeys(mod, root(dex) .. "/runtime_mesh_v1")) do
    if key:sub(-4) == ".f32" then
      seen = seen + 1
      local okB, data = pcall(mod.cache.read, mod.cache, key)
      if okB and type(data) == "string" and #data >= 176 and #data % 176 == 0 and data:sub(1, 4) ~= "OQ16" then
        local f = ffi.cast("const float*", data)
        local bytes = packQ16(function(i) return f[i] end, #data / 4)
        if bytes and #bytes < #data then
          assert(mod.cache:write(key, bytes) ~= false, "bank write failed: " .. key)
          converted = converted + 1
        end
      end
      checkpoint()
    end
  end
  if seen == 0 then return nil, "no banks listed" end
  mod.cache:write(root(dex) .. "/q16.txt", Q16_MARK)
  return seen, converted
end
C.compactSpecies = compactSpecies

-- Does every action manifest's first bank exist?  Some caches carry a current
-- stamp over an older layout (action_<name>_NN.f32, no _page<i>_): the
-- manifests name page files that are not there, every action fails to load
-- and the battle plays a procedural lunge.  Such a species is rebuilt.
-- Returns true, or false + the first missing file.
local function speciesComplete(mod, dex)
  local rt = root(dex) .. "/runtime_mesh_v1"
  local have = {}
  for _, key in ipairs(listKeys(mod, rt)) do have[key] = true end
  if not next(have) then return true end   -- nothing listed: cannot tell
  for key in pairs(have) do
    local name = key:match("/action_([%w]+)%.lua$")
    if name then
      local okS, src = pcall(mod.cache.read, mod.cache, key)
      local chunk = okS and type(src) == "string" and loadstring(src)
      local okM, meta = pcall(chunk or error)
      if okM and type(meta) == "table" and not meta.alias and type(meta.pages) == "table" then
        for pi = 1, #meta.pages do
          local first = ("%s/action_%s_page%d_01.f32"):format(rt, name, pi)
          if not have[first] then return false, first end
        end
      end
    end
  end
  return true
end
C.speciesComplete = speciesComplete

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
    local current = okRev and rev == C.STAMP and listed[dex]
    if current then
      local okC, complete, missing = pcall(speciesComplete, mod, dex)
      if okC and not complete then
        current = false
        log("ORAS dex %d: rebuilding, missing %s", dex, tostring(missing))
      end
    end
    if current then
      -- built before CRY_FIX: rebuild only if its cry has a flat channel
      local okS, src = pcall(readCache, mod, root(dex) .. "/runtime_mesh_v1/base.lua")
      local chunk = okS and type(src) == "string" and loadstring(src)
      local okM, meta = pcall(chunk or error)
      if okM and type(meta) == "table" and meta.cryFix ~= CRY_FIX then
        local okF, flat = pcall(function() return cryHasFlatChannel(motionsOf(g, index, dex)) end)
        if okF and flat then
          current = false
          log("ORAS dex %d: rebuilding, cry pose fix", dex)
        end
      end
      -- built before bone scale compensation: rebuild when it changes it
      -- (oras/pokemon/<dex>/ssc.txt: checked, nothing to change -- so the
      -- next press does not decode the model again)
      if current and okM and type(meta) == "table" and meta.sscFix ~= SSC_FIX then
        local okMk, mark = pcall(mod.cache.read, mod.cache, root(dex) .. "/ssc.txt")
        if not (okMk and mark == SSC_MARK) then
          local okS2, need, why = pcall(needsScaleFix, g, index, dex)
          if okS2 and need then
            current = false
            log("ORAS dex %d: rebuilding, bone scale fix (%s)", dex, tostring(why))
          elseif okS2 then
            pcall(mod.cache.write, mod.cache, root(dex) .. "/ssc.txt", SSC_MARK)
          end
        end
      end
    end
    if current and C.compactBanks ~= false then
      local okQ2, q = pcall(mod.cache.read, mod.cache, root(dex) .. "/q16.txt")
      if not (okQ2 and q == Q16_MARK) then
        local okC, seen, converted = pcall(compactSpecies, mod, dex)
        if okC and seen then
          log("ORAS dex %d: banks compacted (%d of %d)", dex, converted, seen)
        else
          log("ORAS dex %d: compact failed: %s", dex, tostring(okC and converted or seen))
        end
      end
    end
    if current then
      skipped = skipped + 1
      local okP, patched = pcall(patchSize, mod, g, index, dex)
      if okP and patched then log("ORAS dex %d: posed size recorded", dex) end
      local okV, patchedV, switches = pcall(patchVisibility, mod, g, index, dex)
      if okV and patchedV and switches then log("ORAS dex %d: mesh visibility recorded", dex) end
    else
      -- pcall does not cross a coroutine yield in plain Lua 5.1, but does in
      -- LuaJIT (which this runs on): yields inside buildSpecies are fine
      local ok, summary, why = pcall(C.buildSpecies, mod, rom, g, index, dex)
      if ok and summary then
        built = built + 1
        listed[dex] = true
        writeIndex()
        -- packed by ORAS MODELS right after the build (lib/ORASModels.lua);
        -- the fresh loose files replace any archived copies
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

-- ------------------------------------------------------------- RenderDump

local FORMAT_NAME = {}
for k, v in pairs(PICA.FORMAT) do FORMAT_NAME[v] = k end

local function hexRows(d, at, len)
  local out = {}
  if not (at and at > 0) then return out end
  for row = 0, len - 1, 16 do
    local p = at + row
    if p + 1 > #d then break end
    local bytes = {}
    for i = 0, 15 do
      local b = d:byte(p + i + 1)
      if not b then break end
      bytes[#bytes + 1] = ("%02X"):format(b)
    end
    out[#out + 1] = ("      +%03X  %s"):format(row, table.concat(bytes, " "))
  end
  return out
end

-- A report of how species `dex`'s model is split into body / glow / skipped
-- meshes and why, with the raw material bytes (blend, stencil, constant
-- colours are not decoded by H3D) and every non-body texture decoded as-is.
-- writePng(name, ImageData) saves a texture next to the report.
-- Read-only: touches neither the cache nor the live scenes.
function C.inspect(mod, dex, writePng)
  local rom, err = N3DSRom.open(mod, IMPORT_ID)
  if not rom then return nil, "ROM: " .. tostring(err) end
  local g, gerr = GARC.open(rom, assert(rom:file(MODEL_GARC), "no " .. MODEL_GARC))
  if not g then return nil, gerr end
  local index = g:member(0)
  local base, md, mh, model = findSpecies(g, index, dex)
  if not base then return nil, md end
  local td, th = packBch(g, base + 3, 1)
  local textures = td and H3D.textures(td, th) or {}
  local prefix = (model.name or ""):match("^(pm%d+)") or "pm"
  local out = {}
  local function p(fmt, ...) out[#out + 1] = fmt:format(...) end
  p("  model %s  (member block %d)  prefix %s  meshes %d  materials %d",
    tostring(model.name), base, prefix, #model.meshes, #model.materials)
  p("  textures in the texture pack:")
  local tnames = {}
  for name in pairs(textures) do tnames[#tnames + 1] = name end
  table.sort(tnames)
  for _, name in ipairs(tnames) do
    local t = textures[name]
    p("    %-28s %4dx%-4d %-8s%s", name, t.width or 0, t.height or 0,
      FORMAT_NAME[t.format] or tostring(t.format),
      GLOW_FORMATS[t.format] and "  (glow format)" or "")
  end
  p("  meshes:")
  local seenMat, exported = {}, {}
  for i, mesh in ipairs(model.meshes) do
    local mat = model.materials[mesh.materialIndex + 1] or {}
    local tname = mat.textures and mat.textures[1]
    local t = tname and textures[tname]
    local glow = effectTexture(prefix, tname, t)
    local own = not glow and tname and tname:sub(1, #prefix) == prefix
    local verdict
    if own then verdict = "BODY"
    elseif glow then verdict = "GLOW (color " .. table.concat(glowColor(tname), ",") .. ")"
    elseif not tname or tname == "" then verdict = "SKIPPED: no texture"
    elseif not t then verdict = "SKIPPED: texture not in this model's pack (shared effect texture?)"
    else verdict = "SKIPPED: not own, format " .. (FORMAT_NAME[t.format] or "?") .. " is not a glow format" end
    local verts = 0
    for _, sm in ipairs(mesh.submeshes or {}) do verts = verts + #(sm.indices or {}) end
    local bone = model.bones and model.bones[(mesh.nodeIndex or 0) + 1]
    p("    mesh %2d  mat %2d %-24s tex %s | %s | %s   -> %s", i, mesh.materialIndex,
      tostring(mat.name), tostring(tname), tostring(mat.textures and mat.textures[2]),
      tostring(mat.textures and mat.textures[3]), verdict)
    p("             node %d (%s)  indices %d  wrap %s/%s", mesh.nodeIndex or -1,
      tostring(bone and bone.name), verts, tostring(mat.wrapU), tostring(mat.wrapV))
    if not own and not seenMat[mesh.materialIndex] then
      seenMat[mesh.materialIndex] = true
      p("      material struct @%s (0x2C bytes):", tostring(mat.at))
      for _, l in ipairs(hexRows(md, mat.at, 0x2C)) do out[#out + 1] = l end
      p("      material params @%s (0x200 bytes):", tostring(mat.paramsAt))
      for _, l in ipairs(hexRows(md, mat.paramsAt, 0x200)) do out[#out + 1] = l end
    end
    -- every non-body texture this mesh names, decoded untouched
    if not own and writePng and td then
      for slot = 1, 3 do
        local n = mat.textures and mat.textures[slot]
        local tt = n and textures[n]
        if tt and not exported[n] then
          exported[n] = true
          local okT, img = pcall(PICA.decodeTexture, td, tt.address, tt.width, tt.height, tt.format)
          if okT and img then pcall(writePng, ("dex%d_%s.png"):format(dex, n:gsub("[^%w_%-]", "_")), img) end
        end
      end
    end
  end
  return table.concat(out, "\n")
end

return C
