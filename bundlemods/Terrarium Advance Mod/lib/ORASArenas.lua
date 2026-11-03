-- ORAS ARENAS: the Omega Ruby / Alpha Sapphire battle stages, baked from the
-- player's own decrypted dump, and the switch that stages fights in them.
--
-- Independent of the Colosseum disc: own OPTIONS rows (under the ORAS effect
-- rows), own pump, own cache folder. Drawn by lib/ORASArenaStage.lua.
--
-- Data: GARC a/1/3/6 (a/1/5/2 is the cutscene archive: opening, title,
-- ending, evolution and trade demos). Members are a plain BCH or a "BG" pack
-- (u16 magic, u16 count, count + 1 u32 offsets) whose first file is the BCH.
-- Model names say what each piece is:
--   btl_G_<env>     the stage itself, ~32 m across (79 of them: grass, forest,
--                   city, beach, caves, gyms 1-8, Elite Four, champion, ...)
--   btl_F_<env>     a far backdrop ring for 15 outdoor stages (~52 m)
--   btl_O_<env>_m   the round base a Pokemon stands on (2.5 m), per stage
-- ORAS shoots a stage from -Z toward +Z (its trees are cards facing -Z), so
-- the player's side is at -Z and the foe's at +Z, 430 cm apart.
--
-- Materials are tex0 x vertex colour x a combiner constant (stage 0 then
-- stage 1), alpha tested; the bake keeps that (lib/ORASEffectModels.lua
-- bakeModel with opts.const). A pack's other files carry its material
-- animations (file 2 for a stage: the water, the drifting leaf shadows, the
-- light; bases also file 5): texture 0 translation (target 21) and rotation
-- (20), looping. Meshes they animate keep their RAW uvs plus the material's
-- uvt; ORASArenaStage applies the animated matrix per frame (stamp 2).
-- Not decoded yet: fragment lighting (some sand / water floors come out bluish).
--
-- BUILD (row "ORAS ARENAS") into mod cache oras/arenas/:
--   index.lua        { stamp, stages = { [env] = { g =, f =, o = } }, list = { env, ... } }
--   models/<name>.lua  { name, top, uv = { [material] = { frames, x, y, r } } or nil,
--                      meshes = { { tex, blend, cutout, wrapU, wrapV, mat, anim, uvt,
--                      v = { x, y, z, u, v, r, g, b, a, ... } (cm, final UVs; raw
--                      PICA uvs when anim), idx } } }
--   tex/<key>.png
-- PLAY (row "ORAS ARENA": OFF / AUTO / one stage, oras/arenas/choice.txt).

local V = ...
local mod = V and V.mod

local A = { ID = "oras_arenas", LABEL = "ORAS ARENAS" }

A.ROOT = "oras/arenas"
A.INDEX = A.ROOT .. "/index.lua"
A.STAMP = "oras-arena=2"   -- 2: material animations (texture scroll / rotation)
A.CHOICE = A.ROOT .. "/choice.txt"
A.GARC_PATH = "a/1/3/6"
A.IMPORT_ID = "pokemon_oras"

local FRAME_BUDGET = 0.010

local function log(level, fmt, ...)
  local l = mod and mod.log
  if l and type(l[level]) == "function" then pcall(l[level], l, fmt, ...) end
end

local function now()
  return (love and love.timer and love.timer.getTime and love.timer.getTime()) or os.clock()
end

local function Effects() return V.require("ORASEffects") end

-- ORAS ARENA PACK packs oras/arenas/<folder>/* (models, tex) into
-- cbe_cache_archive/orasarena (lib/CacheArchive.lua kind "orasarena");
-- index.lua and choice.txt stay loose.  Loaded as ORASEffects does when
-- nothing else has loaded it.
local function archive()
  local Ar = mod and mod.exports and mod.exports.cacheArchive
  if Ar then return Ar end
  local okS, src = pcall(function() return mod:read("lib/CacheArchive.lua") end)
  local chunk = okS and type(src) == "string" and load(src, "@lib/CacheArchive.lua")
  if not chunk then return nil end
  local okW, WorkBudget = pcall(V.require, "WorkBudget")
  local okA, arch = pcall(chunk, { mod = mod, WorkBudget = okW and WorkBudget or nil })
  if not (okA and type(arch) == "table") then return nil end
  if mod.exports then mod.exports.cacheArchive = arch end
  return arch
end

-- one baked file: loose first (a fresh bake), else from the packed unit
local function readFile(path)
  local ok, bytes = pcall(mod.cache.read, mod.cache, path)
  if ok and type(bytes) == "string" then return bytes end
  local Ar = archive()
  if not (Ar and Ar.readEntry) then return nil end
  local okA, packed = pcall(Ar.readEntry, path)
  return okA and type(packed) == "string" and packed or nil
end
A.readFile = readFile

local function readLua(path)
  local src = readFile(path)
  if type(src) ~= "string" then return nil end
  local chunk = (loadstring or load)(src, "@" .. path)
  if not chunk then return nil end
  if setfenv then setfenv(chunk, {}) end
  local okRun, value = pcall(chunk)
  return okRun and value or nil
end
A.readLua = readLua


-- ------------------------------------------------------------------ names

-- What the OPTIONS row shows; anything not here shows its code name.
A.LABELS = {
  kusa = "GRASS", mori = "FOREST", city = "CITY", town = "TOWN", hama = "BEACH",
  mizu = "POND", sea = "SEA", saba = "DESERT", yama = "MOUNTAIN", hai = "ASH",
  volc = "VOLCANO", kaza = "WATER CAVE", heya = "ROOM", fact = "FACTORY",
  ship = "SHIP", sky1 = "SKY", reku = "SKY PILLAR", deo = "SPACE",
  bike = "CYCLE ROAD", haka = "MT PYRE", cham = "CHAMPION",
  ["4aku"] = "E4 DARK", ["4gst"] = "E4 GHOST", ["4ice"] = "E4 ICE", ["4dor"] = "E4 DRAGON",
  do_i = "CAVE", do_0 = "CAVE 2", do_m = "CAVE 3", do_s = "WATER CAVE 2", do_t = "ICE CAVE", do_y = "CAVE 4",
  gym1 = "GYM ROCK", gym2 = "GYM FIGHT", gym3 = "GYM ELECTRIC", gym4 = "GYM FIRE",
  gym5 = "GYM NORMAL", gym6 = "GYM FLYING", gym7 = "GYM PSYCHIC", gym8 = "GYM WATER",
}

function A.label(env)
  return A.LABELS[env] or tostring(env):upper():gsub("_", " ")
end

-- ------------------------------------------------------------------ index

local indexMemo
function A.index()
  if indexMemo == nil then
    local idx = readLua(A.INDEX)
    indexMemo = (type(idx) == "table" and idx.stamp == A.STAMP and type(idx.stages) == "table") and idx or false
  end
  return indexMemo or nil
end

function A.built() return A.index() ~= nil end

function A.imported()
  local imports = mod and mod.imports
  if not imports then return false end
  local ok, info = pcall(imports.info, imports, A.IMPORT_ID)
  return ok and type(info) == "table" and info.ready ~= false
end

-- ---------------------------------------------------------------- setting

local choiceValue
function A.choice()
  if choiceValue == nil then
    local ok, s = pcall(mod.cache.read, mod.cache, A.CHOICE)
    choiceValue = ok and type(s) == "string" and s:match("^%s*([%w_]+)") or "off"
  end
  return choiceValue
end

function A.setChoice(v)
  choiceValue = v or "off"
  pcall(mod.cache.write, mod.cache, A.CHOICE, choiceValue .. "\n")
end

-- staging fights in an ORAS arena right now: built and not OFF
function A.active()
  return A.choice() ~= "off" and A.built()
end

-- the row's stops: OFF, AUTO, then every built stage except the contest
-- halls' many colour variants (c_a1 .. c_d5; c_op / c_ed stay)
function A.stops()
  local out = { "off", "auto" }
  local idx = A.index()
  for _, env in ipairs(idx and idx.list or {}) do
    if not env:match("^c_[a-d]%d$") then out[#out + 1] = env end
  end
  return out
end

function A.step(dir)
  local stops, cur = A.stops(), A.choice()
  local at = 1
  for i, v in ipairs(stops) do if v == cur then at = i end end
  at = (at - 1 + (dir or 1)) % #stops + 1
  A.setChoice(stops[at])
end

-- ------------------------------------------------------------------- AUTO

-- Gym leaders and the League by trainer class (the keys StadiumBattleFXPort
-- normalises: upper case, runs of other characters to "_"). Leaders from the
-- other regions get the Hoenn gym of their type.
local BY_CLASS = {
  ROXANNE = "gym1", BRAWLY = "gym2", WATTSON = "gym3", FLANNERY = "gym4",
  NORMAN = "gym5", WINONA = "gym6", TATE_LIZA = "gym7", TATE_AND_LIZA = "gym7", LIZA = "gym7", TATE = "gym7",
  WALLACE = "gym8", JUAN = "gym8",
  BROCK = "gym1", MISTY = "gym8", LT_SURGE = "gym3", LTSURGE = "gym3", ERIKA = "gym5",
  KOGA = "4aku", JANINE = "gym5", SABRINA = "gym7", BLAINE = "gym4", GIOVANNI = "gym1",
  FALKNER = "gym6", BUGSY = "gym5", WHITNEY = "gym5", MORTY = "4gst", CHUCK = "gym2",
  JASMINE = "gym1", PRYCE = "4ice", CLAIR = "4dor",
  SIDNEY = "4aku", PHOEBE = "4gst", GLACIA = "4ice", DRAKE = "4dor",
  LORELEI = "4ice", BRUNO = "4aku", AGATHA = "4gst", WILL = "4gst", KAREN = "4aku",
  LANCE = "cham", STEVEN = "cham", CHAMPION = "cham",
}

local function classKey(battle)
  local trainer = battle and (battle.trainer or (battle.battle and battle.battle.trainer))
  local key = tostring(trainer and (trainer.classId or trainer.class) or (battle and battle.oppClass) or ""):upper()
  return (key:gsub("[^A-Z0-9]+", "_"):gsub("^_+", ""):gsub("_+$", ""))
end

-- map id / tileset keywords, first match wins
local BY_NAME = {
  { "sky_pillar", "reku" }, { "pyre", "haka" }, { "tower", "haka" },
  { "desert", "saba" }, { "ash", "hai" }, { "volcan", "volc" }, { "chimney", "volc" },
  { "cinnabar", "volc" }, { "ship", "ship" }, { "anne", "ship" }, { "ferry", "ship" },
  { "factory", "fact" }, { "power", "fact" }, { "silph", "fact" },
  { "forest", "mori" }, { "wood", "mori" }, { "safari", "kusa" },
  -- caves: do_i / do_t keep the battle camera clear (do_0 and do_s have a
  -- rock column across the player's side of the shot)
  { "ice", "do_t" }, { "seafoam", "do_t" }, { "cave", "do_i" }, { "tunnel", "do_i" },
  { "cavern", "do_i" }, { "mt_", "do_i" }, { "mount", "do_i" }, { "victory", "do_i" },
  { "beach", "hama" }, { "league", "cham" }, { "indigo", "cham" }, { "plateau", "cham" },
  { "city", "city" }, { "town", "town" }, { "route", "kusa" },
}

local function surfing(map)
  local okBC, BC = pcall(V.require, "BattleCanvas")
  if okBC and BC and BC.onWater then
    local ok, wet = pcall(BC.onWater, map, nil)
    if ok and wet then return true end
  end
  local okG, Game = pcall(require, "src.core.Game")
  local p = okG and Game and Game.overworld and Game.overworld.player
  return p and p.surfing and true or false
end

-- ------- Gen 4 / Gen 5 native maps
--
-- Their map ids (Z123, C01R0201) and the shared Gen4 tileset say nothing, and
-- Map.isOutdoor reads every one of them as indoors, so before this every
-- fight there that was not on water got the indoor room (heya). What they DO
-- carry:
--   Gen 4: the map header's battle background byte (Gen4Battle.backgroundFor)
--          and the terrain of the tile under the player (Gen4Battle.terrainFor,
--          the cartridge's CalcTerrain), the same pair Platinum picks its own
--          battle backdrop from.
--   Gen 5: the tile behaviour under the player (Gen5FieldRules: grass, sand,
--          cave floor, water), the place name (def.label: "Pinwheel Forest")
--          and the zone's Fly permission (outdoors; caves and buildings deny it).

local GEN4_BACKGROUND = {
  plain = "kusa", water = "sea", city = "city", forest = "mori", mountain = "yama", snow = "do_t",
  indoors_1 = "heya", indoors_2 = "heya", indoors_3 = "heya",
  cave_1 = "do_i", cave_2 = "do_i", cave_3 = "do_m",
  aaron = "4aku", bertha = "4dor", flint = "4gst", lucian = "4ice", cynthia = "cham",
  distortion_world = "deo",
  battle_tower = "vs1", battle_factory = "fact", battle_arcade = "vs2", battle_castle = "vs3", battle_hall = "vs1",
}
-- tile terrains that beat the map's background (Platinum asks the tile first)
local GEN4_TERRAIN = {
  sand = "hama", ice = "do_t", snow = "do_t", great_marsh = "mizu", cave = "do_i", water = "sea",
}

local function gameRef()
  local ok, Game = pcall(require, "src.core.Game")
  return ok and Game or nil
end

-- name keywords that are only a fallback (anything more specific wins first)
local GENERIC = { city = true, town = true, route = true }

local function nameRule(id, have, generic)
  for _, rule in ipairs(BY_NAME) do
    if (GENERIC[rule[1]] or false) == generic and id:find(rule[1], 1, true) and have(rule[2]) then
      return rule[2]
    end
  end
  return nil
end

-- Gen 4: (stage, why) or nil. `plain` false: only a tile terrain or a
-- background that says something (indoors, cave, city, forest ...); true:
-- the plain background too (after the name keywords had their turn).
local function gen4Pick(map, have, plain)
  local def = map and map.def
  if not def or def.gen5 then return nil end
  if def.battleBackground == nil and not (def.generation == 4) then return nil end
  local okB, B = pcall(require, "src.battle.Gen4Battle")
  if not (okB and B and B.backgroundFor) then return nil end
  local game = gameRef()
  local okT, terrain = pcall(B.terrainFor, game)
  local okG, bg = pcall(B.backgroundFor, game)
  terrain, bg = okT and terrain or nil, okG and bg or nil
  local pick = have(GEN4_TERRAIN[terrain or ""] or "")
  if pick then return pick, "gen4 terrain " .. tostring(terrain) end
  if (bg or "plain") == "plain" and not plain then return nil end
  pick = have(GEN4_BACKGROUND[bg or "plain"] or "")
  if pick then return pick, "gen4 background " .. tostring(bg or "plain") end
  return nil
end

-- Gen 5: (stage, why) or nil
local function gen5Pick(map, have, id)
  local def = map and map.def
  if not (def and def.gen5) then return nil end
  local okR, R = pcall(require, "src.world.Gen5FieldRules")
  local game = gameRef()
  local p = game and game.overworld and game.overworld.player
  local b = nil
  if okR and R and p then
    local okb, v = pcall(R.behaviour, map, p.cellX or p.x, p.cellY or p.y)
    b = okb and v or nil
  end
  if b then
    if okR and R.CAVE_FLOOR[b] then return have("do_i"), "gen5 cave floor" end
    if b == 0x0C or b == 0x23 then return have("saba"), "gen5 sand" end
    if okR and (R.WATER_ENCOUNTER[b] or b == 0x02) then return have("sea"), "gen5 water" end
  end
  local pick = nameRule(id, have, false)
  if pick then return pick, "gen5 name" end
  local okF, Fly = pcall(require, "src.world.Gen5Fly")
  local outdoor = okF and Fly and Fly.allowed(def) or false
  if outdoor then
    if okR and b and R.GRASS[b] then return have("kusa"), "gen5 grass" end
    return nameRule(id, have, true) or have("kusa"), "gen5 outdoors (fly allowed)"
  end
  return have("heya"), "gen5 indoors (no fly)"
end

A.lastPickWhy = nil

-- the stage AUTO picks for this map / battle (always one that was built)
function A.autoPick(map, battle)
  local stages = (A.index() or {}).stages or {}
  local function have(env) return stages[env] and env or nil end
  local function done(pick, why) A.lastPickWhy = why; return pick end
  local pick = have(BY_CLASS[classKey(battle)] or "")
  if pick then return done(pick, "trainer class " .. classKey(battle)) end
  if surfing(map) then pick = have("sea") if pick then return done(pick, "surfing") end end
  local def = map and map.def
  local id = (tostring(map and map.id or "") .. " " .. tostring(def and def.tileset or "") .. " "
              .. tostring(def and (def.label or def.name) or "")):lower():gsub("[%s%-%.]+", "_")
  local why
  pick, why = gen5Pick(map, have, id)
  if pick then return done(pick, why) end
  pick, why = gen4Pick(map, have, false)
  if pick then return done(pick, why) end
  pick = nameRule(id, have, false)
  if pick then return done(pick, "name " .. id) end
  pick = nameRule(id, have, true)
  if pick then return done(pick, "name " .. id) end
  pick, why = gen4Pick(map, have, true)
  if pick then return done(pick, why) end
  if id:find("gym", 1, true) and have("gym5") then return done("gym5", "name gym") end
  local outdoor = true
  pcall(function() outdoor = require("src.world.Map").isOutdoor(def) and true or false end)
  return done(have(outdoor and "kusa" or "heya") or have("kusa") or (A.index() and A.index().list[1]),
              outdoor and "outdoors" or "indoors")
end

-- the stage for this fight, or nil when the row is OFF / nothing is built
function A.pick(map, battle)
  if not A.active() then return nil end
  local c = A.choice()
  local stages = A.index().stages
  if c ~= "auto" and stages[c] then return c end
  return A.autoPick(map, battle)
end

-- -------------------------------------------------------------------- bake

local job = nil   -- { co, done, total, startedAt, frameStart }

local function checkpoint()
  if job and coroutine.running() == job.co and now() - job.frameStart > FRAME_BUDGET then
    coroutine.yield()
  end
end

local function u32(s, p)
  local a, b, c, d = s:byte(p, p + 3)
  return a + b * 256 + c * 65536 + d * 16777216
end

-- every BCH of a member, in pack order (a plain BCH is a pack of one)
local function packFiles(d)
  local out = {}
  if type(d) ~= "string" then return out end
  if d:sub(1, 2) == "BG" and #d >= 12 then
    local n = d:byte(3) + d:byte(4) * 256
    for k = 0, n - 1 do
      local a, b = u32(d, 5 + k * 4), u32(d, 9 + k * 4)
      local f = (b > a and b <= #d) and d:sub(a + 1, b) or ""
      out[#out + 1] = f:sub(1, 4) == "BCH\0" and f or false
    end
  elseif d:sub(1, 4) == "BCH\0" then
    out[1] = d
  end
  return out
end

-- the looping material animations in a pack's other files:
-- { [material] = { frames, x, y, r } } (curves or constants), or nil
local function packUV(files)
  local B, H = V.require("BCH"), V.require("H3D")
  local mats, any = {}, false
  for k = 2, #files do
    local f = files[k]
    if f then
      local okA, anims = pcall(function()
        local h = B.header(f)
        return H.materialAnimations(B.relocate(f, h), h)
      end)
      for _, a in ipairs(okA and anims or {}) do
        for _, el in ipairs(a.elements) do
          local m = el.material
          if m and el.target == H.TARGET.texCoord0Trans and (el.x ~= nil or el.y ~= nil) then
            mats[m] = mats[m] or {}
            mats[m].x, mats[m].y = el.x, el.y
            mats[m].frames = math.max(mats[m].frames or 0, tonumber(a.frames) or 0)
            any = true
          elseif m and el.target == H.TARGET.texCoord0Rot and el.v ~= nil then
            mats[m] = mats[m] or {}
            mats[m].r = el.v
            mats[m].frames = math.max(mats[m].frames or 0, tonumber(a.frames) or 0)
            any = true
          end
        end
      end
    end
  end
  return any and mats or nil
end
A._packFiles, A._packUV = packFiles, packUV

-- baked compact model -> the runtime layout: colours always present, the
-- texture matrix applied and v flipped for LOVE (PICA's v runs bottom-up)
local function finish(m, uvMats)
  local H3D = V.require("H3D")
  local top = -math.huge
  local out = { name = m.name, meshes = {} }
  local used = {}
  for _, ms in ipairs(m.meshes) do
    local st = ms.colors and 9 or 5
    -- animated: raw uvs, the stage shader applies the live matrix
    local anim = uvMats and ms.mat and ms.uvt and uvMats[ms.mat] and true or nil
    if anim then used[ms.mat] = uvMats[ms.mat] end
    local t = (not anim) and ms.uvt and H3D.uvMatrix(ms.uvt[1], ms.uvt[2], ms.uvt[3], ms.uvt[4], ms.uvt[5], ms.uvt[6]) or nil
    local v = {}
    for i = 0, #ms.v / st - 1 do
      local o = i * st
      local x, y, z = ms.v[o + 1], ms.v[o + 2], ms.v[o + 3]
      if y > top then top = y end
      local uv = { ms.v[o + 4], ms.v[o + 5] }
      if t then uv = H3D.applyUV(t, uv) end
      v[#v + 1], v[#v + 2], v[#v + 3] = x, y, z
      if anim then v[#v + 1], v[#v + 2] = uv[1], uv[2]
      else v[#v + 1], v[#v + 2] = uv[1], 1 - uv[2] end
      if ms.colors then
        for k = 6, 9 do v[#v + 1] = ms.v[o + k] end
      else
        v[#v + 1], v[#v + 2], v[#v + 3], v[#v + 4] = 1, 1, 1, 1
      end
    end
    out.meshes[#out.meshes + 1] = {
      tex = ms.tex, blend = ms.blend, cutout = ms.cutout, wrapU = ms.wrapU, wrapV = ms.wrapV,
      kc = ms.kc, mat = ms.mat, v = v, idx = ms.idx, colors = true,
      anim = anim, uvt = anim and ms.uvt or nil,
    }
  end
  if next(used) then out.uv = used end
  out.top = top > -math.huge and top or 0
  return out
end
A._finish = finish

local function bake()
  local literal = Effects()._literal
  local EM = V.require("ORASEffectModels")
  local R, why = V.require("N3DSRom").open(mod, A.IMPORT_ID)
  if not R then error("dump: " .. tostring(why)) end
  local file = R:file(A.GARC_PATH)
  if not file then error("no " .. A.GARC_PATH .. " in this dump") end
  local g = assert(V.require("GARC").open(R, file))
  job.total = g.count

  local written, pieces, failed = {}, {}, 0
  for i = 0, g.count - 1 do
    local okM, raw = pcall(g.member, g, i)
    local files = okM and packFiles(raw) or {}
    local bch = files[1] or nil
    if bch then
      local function writeTexture(name, w, h, img)
        local key = ("%d_%s_%dx%d"):format(i, name, w, h)
        if not written[key] then
          local okP, png = pcall(function() return img:encode("png"):getString() end)
          if not okP then return nil end
          mod.cache:write(A.ROOT .. "/tex/" .. key .. ".png", png)
          written[key] = true
        end
        return key
      end
      local okB, m, whyB = pcall(EM.bakeModel, bch, writeTexture, { raw = true, maxSpan = math.huge, const = true })
      local name = okB and m and m.name
      if name and name:match("^btl_[GFO]_") then
        local okU, uv = pcall(packUV, files)
        mod.cache:write(("%s/models/%s.lua"):format(A.ROOT, name),
                        "return " .. literal(finish(m, okU and uv or nil)) .. "\n")
        pieces[name] = true
      elseif not okB then
        failed = failed + 1
        log("warn", "ORAS ARENAS: member %d skipped (%s)", i, tostring(m))
      elseif not m and whyB ~= "no model" then
        log("info", "ORAS ARENAS: member %d: %s", i, tostring(whyB))
      end
    end
    job.done = i + 1
    checkpoint()
  end

  local stages, list = {}, {}
  for name in pairs(pieces) do
    local env = name:match("^btl_G_(.+)$")
    if env then
      stages[env] = { g = name, f = pieces["btl_F_" .. env] and ("btl_F_" .. env) or nil,
                      o = pieces["btl_O_" .. env .. "_m"] and ("btl_O_" .. env .. "_m") or nil }
      list[#list + 1] = env
    end
  end
  table.sort(list)
  mod.cache:write(A.INDEX, "return " .. literal({ stamp = A.STAMP, stages = stages, list = list }) .. "\n")
  indexMemo = nil
  local nTex = 0
  for _ in pairs(written) do nTex = nTex + 1 end
  pcall(function() V.require("ORASArenaStage").invalidate() end)
  return #list, nTex, failed
end

function A.running() return job ~= nil end

-- -------------------------------------------------------------------- pack

local packJob = nil   -- { Ar, started, startedAt, fresh }
local PACK_BUDGET_MS = 12

-- fresh: the bake just wrote every file loose again, so the old units are
-- dropped first (they would keep members the new bake left out)
local function startPack(fresh)
  local Ar = archive()
  if not (Ar and Ar.beginPack) then
    log("warn", "ORAS ARENA PACK: cache packing unavailable (lib/CacheArchive.lua did not load); stages stay loose")
    return false
  end
  packJob = { Ar = Ar, started = false, startedAt = now(), fresh = fresh }
  return true
end
A.startPack = startPack

-- status() lists the archive folders: the row asks every frame
local packStatusMemo, packStatusAt, packStatusStale = nil, -1, false
function A.packStatus()
  local t = now()
  if packStatusMemo and not packJob and not packStatusStale and t - packStatusAt < 1 then return packStatusMemo end
  packStatusStale = false
  local Ar = archive()
  local okS, s = pcall(function() return Ar and Ar.status and Ar.status() or nil end)
  s = okS and s or nil
  packStatusMemo = s and { packed = s.orasarenaPacked, entries = s.orasarenaEntries,
                           original = s.orasarenaOriginalLabel, archive = s.orasarenaArchiveLabel } or {}
  packStatusAt = t
  return packStatusMemo
end

local function pumpPack()
  local Ar = packJob.Ar
  if not packJob.started then
    -- another pack job (ORAS MODELS / FX PACK, Colosseum auto-pack) holds the
    -- archive: drive it to its end, then start ours
    if Ar.running and Ar.running() then Ar.pump(PACK_BUDGET_MS); return end
    if packJob.fresh and Ar.wipeKind then Ar.wipeKind("orasarena") end
    local ok, why = Ar.beginPack("orasarena")
    if not ok then
      packJob = nil
      A.packError = tostring(why)
      log("warn", "ORAS ARENA PACK: packing could not start: %s", tostring(why))
      return
    end
    packJob.started = true
    log("info", "ORAS ARENA PACK: packing the battle stages in the background")
    return
  end
  local state, err = Ar.pump(PACK_BUDGET_MS)
  if state == "working" then return end
  local seconds = now() - packJob.startedAt
  packJob = nil
  packStatusStale = true
  -- meshes / images reload from the units (the loose files are gone)
  pcall(function() V.require("ORASArenaStage").invalidate() end)
  if state == "error" then
    A.packError = tostring(err)
    log("warn", "ORAS ARENA PACK: packing failed (loose files kept): %s", tostring(err))
    return
  end
  A.packError = nil
  local st = A.packStatus()
  log("info", "ORAS ARENA PACK: packed in %.0fs -- %s of stages in %s (cbe_cache_archive/orasarena)",
      seconds, tostring(st.original), tostring(st.archive))
end

function A.startBuild()
  if job then return false end
  job = { done = 0, total = 158, startedAt = now(), frameStart = now() }
  job.co = coroutine.create(bake)
  A.status = { state = "building" }
  log("info", "ORAS ARENAS: baking the battle stages in the background")
  return true
end

-- once a frame (main.lua)
function A.pump()
  if packJob then return pumpPack() end
  if not job then return end
  job.frameStart = now()
  local ok, nStages, nTex, failed = coroutine.resume(job.co)
  if not ok then
    log("warn", "ORAS ARENAS: build failed: %s", tostring(nStages))
    A.status = { state = "error", error = tostring(nStages) }
    job = nil
    return
  end
  if coroutine.status(job.co) == "dead" then
    log("info", "ORAS ARENAS: %d stages, %d textures baked in %.1fs (%d unreadable)",
        nStages or 0, nTex or 0, now() - job.startedAt, failed or 0)
    job = nil
    A.status = { state = "done" }
    -- once the player has packed, a new bake is packed right after it
    if A.packStatus().packed then startPack(true) end
  end
end

-- -------------------------------------------------------------------- rows

function A.row()
  return {
    id = A.ID,
    label = A.LABEL,
    value = function()
      if job then return ("BUILDING %d/%d"):format(job.done, job.total) end
      if A.status and A.status.state == "error" then return "ERROR" end
      if A.built() then return "BUILT" end
      return A.imported() and "BUILD" or "NO DUMP"
    end,
    step = function()
      if job or packJob then return true end
      if not A.imported() then
        log("info", "ORAS ARENAS: import a decrypted Omega Ruby / Alpha Sapphire .3ds from the MODS panel first")
        return true
      end
      A.startBuild()
      return true
    end,
  }
end

-- ORAS ARENA: which stage battles are staged in (OFF / AUTO / one stage).
-- On, it stages every fight in that arena with its own camera, whatever the
-- 3D-BTL row says (that row still picks what stands there).
function A.choiceRow()
  return {
    id = "oras_arena",
    label = "ORAS ARENA",
    value = function()
      if not A.built() then return job and "AFTER BUILD" or "BUILD FIRST" end
      local c = A.choice()
      if c == "off" then return "OFF" end
      if c == "auto" then return "AUTO" end
      return A.label(c)
    end,
    step = function(_, dir)
      if not A.built() then
        log("info", "ORAS ARENA: build the stages first (ORAS ARENAS)")
        return true
      end
      A.step(dir)
      return true
    end,
  }
end

-- ORAS ARENA PACK: the row under ORAS ARENA.  Packs the baked stages
-- (models, textures) into cbe_cache_archive/orasarena, one file per folder;
-- pressing it again packs whatever is loose.
function A.packRow()
  return {
    id = "oras_arena_pack",
    label = "ORAS ARENA PACK",
    value = function()
      if packJob then
        local Ar = packJob.Ar
        local label = Ar and Ar.stage and Ar.stage()
        return packJob.started and tostring(label or "PACKING"):gsub("^PACK ORASARENA ", "") or "WAITING"
      end
      if job then return "AFTER BUILD" end
      if A.packError then return "ERROR" end
      local st = A.packStatus()
      if st.packed then return "PACKED " .. tostring(st.archive or "") end
      return A.built() and "LOOSE FILES" or "BUILD FIRST"
    end,
    step = function()
      if job or packJob then return true end
      if not A.built() then
        log("info", "ORAS ARENA PACK: build the stages first (ORAS ARENAS)")
        return true
      end
      startPack(false)
      return true
    end,
  }
end

return A
