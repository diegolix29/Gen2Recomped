-- ORASOverworldNPCs: ORAS field characters as the PEOPLE of the overworld
-- (row ORAS NPCS on the ORAS.. menu, default OFF).
--
-- Who: every map object whose sprite NAMES a person.  The name is
--   Gen 1 / 2   objDef.sprite      "SPRITE_COOLTRAINER_F", "SPRITE_GRANNY"
--   Gen 3       objDef.sprite      "SPRITE_G3_047" -> the game's gfx id table
--                                  below (Emerald / R/S and FR/LG orders,
--                                  checked against the extracted art)
--   Gen 4       objDef.spriteName  "ace_trainer_f" (Platinum), "oldman1" (HGSS)
--   Gen 5       none (the importer keeps only member numbers): unchanged
-- and is cast by ORASBattleTrainers.personModel (the battle pools, keywords,
-- gender / age words, a stable hash per object).  Anything that is not a
-- person (Pokemon, balls, signs, the player's own bike / surf sheets) keeps
-- the card / NPC 3D body it had.
--
-- How: one actor per NPC (PokemonActors acquire: shared meshes, own clock),
-- stand / walk / run from the NPC's own movement, facing = its own world
-- facing, sized like the ORAS PLAYER (16 world px; Gen 4 / 5 world factor).
-- Only NPCs within N.RADIUS of the player and at most N.MAX_PER_FRAME a frame;
-- the rest (and any NPC whose model is not ready) draw as before.
--
-- Hooks: lib/VoxelScene.lua tryNpcBody / castNpcBody (Gen 1-3, also the
-- patched loop in VoxelScenePatch) and lib/Gen4WorldHost.lua wantFieldActor /
-- drawFieldActors (Gen 4 / 5).  Independent of Colosseum: own row, own file.

local V = ...
local mod = V and V.mod

local N = { ID = "oras_npcs", LABEL = "ORAS NPCS" }
N.SETTING = "oras/trainers/npcs.txt"
N.HEIGHT = 16           -- world px, the ORAS PLAYER's CHARACTER_HEIGHT
N.RADIUS = 14 * 16      -- world px from the player
N.MAX_PER_FRAME = 16
N.STILL_HOLD = 0.15     -- s: between two grid steps the walk keeps going

local function log(level, fmt, ...)
  local l = mod and mod.log
  if l and type(l[level]) == "function" then pcall(l[level], l, fmt, ...) end
end

local function Trainers() return V.require("ORASTrainers") end
local function Casting() return V.require("ORASBattleTrainers") end
local function clock()
  return (love and love.timer and love.timer.getTime and love.timer.getTime()) or os.clock()
end

-- ------------------------------------------------------------- the setting

local settingValue
function N.enabled()
  if settingValue == nil then
    local ok, s = pcall(mod.cache.read, mod.cache, N.SETTING)
    settingValue = ok and type(s) == "string" and s:find("on", 1, true) ~= nil or false
  end
  return settingValue
end
function N.setEnabled(on)
  settingValue = on and true or false
  pcall(mod.cache.write, mod.cache, N.SETTING, on and "on\n" or "off\n")
  N.reset()
end

function N.row()
  return {
    id = N.ID,
    label = N.LABEL,
    value = function()
      local okT, T = pcall(Trainers)
      if not (okT and T and T.built()) then return "BUILD TRAINERS" end
      return N.enabled() and "ON" or "OFF"
    end,
    step = function()
      local okT, T = pcall(Trainers)
      if not (okT and T and T.built()) then
        log("info", "ORAS NPCS: build the characters first (ORAS TRAINERS)")
        return true
      end
      N.setEnabled(not N.enabled())
      return true
    end,
  }
end

-- ------------------------------------------------------ Gen 3 gfx id names
--
-- pokeemerald include/constants/event_objects.h (Ruby / Sapphire share the
-- order for these ids).  Only people; everything else is left out.
N.G3_HOENN = {
  [0] = "BRENDAN", [4] = "FAT MAN", [5] = "NINJA BOY", [6] = "TWIN", [7] = "BOY",
  [8] = "GIRL", [9] = "BOY", [10] = "GIRL", [11] = "LITTLE BOY", [12] = "LITTLE GIRL",
  [13] = "BOY", [14] = "GIRL", [15] = "RICH BOY", [16] = "WOMAN", [17] = "FAT MAN",
  [18] = "POKEFAN F", [19] = "MAN", [20] = "WOMAN", [21] = "EXPERT M", [22] = "EXPERT F",
  [23] = "MAN", [24] = "WOMAN", [25] = "POKEFAN M", [26] = "WOMAN", [27] = "COOK",
  [28] = "RECEPTIONIST", [29] = "OLD MAN", [30] = "OLD WOMAN", [31] = "CAMPER",
  [32] = "PICNICKER", [33] = "MAN", [34] = "WOMAN", [35] = "YOUNGSTER",
  [36] = "BUG CATCHER", [37] = "PSYCHIC M", [38] = "SCHOOL KID M", [39] = "MANIAC",
  [40] = "HEX MANIAC", [42] = "SWIMMER M", [43] = "SWIMMER F", [44] = "BLACK BELT",
  [45] = "BEAUTY", [46] = "SCIENTIST", [47] = "LASS", [48] = "GENTLEMAN",
  [49] = "SAILOR", [50] = "FISHERMAN", [51] = "TRIATHLETE M", [52] = "TRIATHLETE F",
  [53] = "TUBER F", [54] = "TUBER M", [55] = "HIKER", [56] = "CYCLIST M",
  [57] = "CYCLIST F", [58] = "NURSE", [64] = "BIRCH", [65] = "MAN", [66] = "MAN",
  [67] = "REPORTER M", [68] = "REPORTER F", [69] = "BARD", [70] = "ANABEL",
  [71] = "TUCKER", [72] = "GRETA", [73] = "SPENSER", [74] = "NOLAND", [75] = "LUCY",
  [83] = "CLERK M", [84] = "WOMAN", [85] = "TEALA", [89] = "MAY", [99] = "ARTIST",
  [100] = "BRENDAN", [105] = "MAY", [110] = "CAMERAMAN", [115] = "SCIENTIST",
  [116] = "EMPLOYEE MAN", [117] = "AQUA M", [118] = "AQUA F", [119] = "MAGMA M",
  [120] = "MAGMA F", [121] = "SIDNEY", [122] = "PHOEBE", [123] = "GLACIA",
  [124] = "DRAKE", [125] = "ROXANNE", [126] = "BRAWLY", [127] = "WATTSON",
  [128] = "FLANNERY", [129] = "NORMAN", [130] = "WINONA", [131] = "LIZA",
  [132] = "TATE", [133] = "WALLACE", [134] = "STEVEN", [135] = "WALLY",
  [136] = "LITTLE BOY", [139] = "OLD WOMAN", [189] = "DELIVERYMAN", [190] = "OLD MAN",
  [195] = "ARCHIE", [196] = "MAXIE", [215] = "WOMAN", [218] = "OLD MAN",
  [219] = "SCOTT", [223] = "MAN", [234] = "MAN", [239] = "OLD MAN",
}
-- pokefirered include/constants/event_objects.h
N.G3_KANTO = {
  [0] = "RED", [7] = "LEAF GIRL", [14] = "BRENDAN", [15] = "MAY", [16] = "LITTLE BOY",
  [17] = "LITTLE GIRL", [18] = "YOUNGSTER", [19] = "BOY", [20] = "BUG CATCHER",
  [22] = "LASS", [23] = "WOMAN", [24] = "BATTLE GIRL", [25] = "MAN", [26] = "ROCKER",
  [27] = "FAT MAN", [28] = "WOMAN", [29] = "BEAUTY", [30] = "BALDING MAN",
  [31] = "WOMAN", [32] = "OLD MAN", [33] = "OLD MAN", [35] = "OLD WOMAN",
  [37] = "TUBER F", [38] = "TUBER M", [39] = "CAMPER", [40] = "PICNICKER",
  [41] = "COOLTRAINER M", [42] = "COOLTRAINER F", [45] = "SWIMMER M", [46] = "SWIMMER F",
  [47] = "WORKER M", [48] = "WORKER WOMAN", [49] = "ROCKET M", [50] = "ROCKET F",
  [51] = "KID", [52] = "SUPER NERD", [53] = "BIKER", [54] = "BLACK BELT",
  [55] = "SCIENTIST", [56] = "HIKER", [57] = "FISHERMAN", [58] = "CHANNELER",
  [59] = "CHEF", [60] = "POLICEMAN", [61] = "GENTLEMAN", [62] = "SAILOR",
  [63] = "CAPTAIN", [64] = "NURSE", [65] = "RECEPTIONIST", [66] = "RECEPTIONIST",
  [67] = "MAN", [68] = "CLERK M", [69] = "DELIVERYMAN", [70] = "DUDE", [71] = "OAK",
  [72] = "BLUE", [73] = "BILL", [74] = "LANCE", [75] = "AGATHA", [76] = "DAISY",
  [77] = "LORELEI", [78] = "FUJI", [79] = "BRUNO", [80] = "BROCK", [81] = "MISTY",
  [82] = "SURGE", [83] = "ERIKA", [84] = "KOGA", [85] = "SABRINA", [86] = "BLAINE",
  [87] = "GIOVANNI", [88] = "MOM", [89] = "CELIO", [90] = "WOMAN", [91] = "GUIDE MAN",
}

local function gameVersion()
  local ok, GV = pcall(require, "src.core.GameVersion")
  local okG, v = pcall(function() return ok and GV.get() end)
  return okG and v or nil
end

-- the person's name words, or nil
local FUSED = { OLDMAN = "OLD MAN", OLDWOMAN = "OLD WOMAN", MIDDLEMAN = "MAN",
  MIDDLEWOMAN = "WOMAN", BABYBOY = "BABY BOY", BABYGIRL = "BABY GIRL", BIGMAN = "FAT MAN",
  SHOPM = "CLERK M", SHOPW = "CLERK F", BIGFOUR = "ELITE", MOUNT = "HIKER",
  -- HeartGold / SoulSilver's internal names (pokeheartgold sprites.h)
  ASSISTANTM = "SCIENTIST M", ASSISTANTW = "SCIENTIST F", BADMAN = "BURGLAR",
  BOARDER = "SKIER M", BOZU = "SAGE", BRAINS = "ELITE", CAMPBOY = "CAMPER",
  CHOUROU = "OLD MAN", COUNTERM = "CLERK M", CYCLEM = "CYCLIST M", CYCLEW = "CYCLIST F",
  DAIGO = "STEVEN", DANCER = "DANCER GIRL", DELIVERY = "DELIVERYMAN", EXPLORE = "RUIN MANIAC",
  FARMER = "MAN", FIGHTER = "BLACK BELT", FISHING = "FISHERMAN", GANG = "ROUGHNECK",
  GANTETSU = "KURT", GORGGEOUSM = "GENTLEMAN", GORGGEOUSW = "LADY", DSBOY = "KID",
  MAMA = "MOM", REDMAMA = "MOM", RIVEL = "SILVER", ITAKO = "CHANNELER", INSTRUCTOR = "TEACHER",
  JUGGRER = "JUGGLER", MANIA = "MANIAC", MASAKI = "BILL", MINAKI = "GENTLEMAN",
  NANAMI = "DAISY", PCWOMAN = "NURSE", PICNICGIRL = "PICNICKER", PRINCESS = "PRINCESS GIRL",
  RKANBUM = "ROCKET M", RKANBUW = "ROCKET F", ROCKETM = "ROCKET M", ROCKETW = "ROCKET F",
  SAKAKI = "GIOVANNI", SEAMAN = "SAILOR", SEVEN = "KIMONO GIRL", SKIERW = "SKIER F",
  SPORTSMAN = "ATHLETE", SUIT = "MAN", SUNGLASSES = "MAN", THIEF = "BURGLAR",
  THLONOWNER = "MAN", TOWERBOSS = "SAGE", WATARU = "LANCE", WORKMAN = "WORKER",
  SWIMMERM = "SWIMMER M", SWIMMERW = "SWIMMER F", KURUMI = "GIRL", LEADER = "LEADER",
  BIGMAN2 = "FAT MAN" }
local function normalize(s)
  local out = {}
  for w in tostring(s):upper():gsub("[_%-%./]", " "):gmatch("%S+") do
    w = w:gsub("%d+$", "")
    -- HGSS "gs" (the Gold / Silver remakes of a sheet): gsboy1, gsleader3
    local rest = w:match("^GS(%u%u%u+)$")
    if rest and not FUSED[w] then w = rest end
    if w ~= "" then out[#out + 1] = FUSED[w] or w end
  end
  return table.concat(out, " ")
end

function N.nameOf(e)
  local def = type(e) == "table" and e.def
  if type(def) ~= "table" then return nil end
  if type(def.spriteName) == "string" and def.spriteName ~= "" then
    if def.spriteName:match("^bw_%d+$") or def.spriteName:match("^var_") then return nil end
    return normalize(def.spriteName)
  end
  local sp = type(def.sprite) == "string" and def.sprite or nil
  if not sp then return nil end
  local g3 = tonumber(sp:match("^SPRITE_G3_(%d+)$"))
  if g3 then
    if def.varSprite then return nil end
    local v = gameVersion()
    local t = (v == "firered" or v == "leafgreen") and N.G3_KANTO or N.G3_HOENN
    return t[g3]
  end
  if sp:match("^SPRITE_G4_") then return nil end
  return normalize((sp:gsub("^SPRITE_", "")))
end

-- ------------------------------------------------------------- the cast

local entries = setmetatable({}, { __mode = "k" })   -- entity -> entry or false
local haveMemo, haveAt = nil, -1

local function built()
  local t = clock()
  if haveMemo and t - haveAt < 5 then return haveMemo end
  haveAt = t
  local okT, T = pcall(Trainers)
  local idx = okT and T and T.index()
  if not idx then haveMemo = nil; return nil end
  local have = {}
  for _, x in ipairs(idx.list) do
    -- field models only: they own walk / run
    if x.kind == "field" then have[x.id] = true end
  end
  haveMemo = have
  return have
end

local function isPersonEntity(e, isPlayer)
  if isPlayer or type(e) ~= "table" then return false end
  if e.hidden or e.fixedFrame or e.isFollower or e.wildsFollower or e._wildsFollowerSpecies
     or e.roamer or e.overworldWildSpawn or e.species or e.stadiumModel or e.model3d then
    return false
  end
  local def = e.def
  if type(def) == "table" and (def.noSprite or def.big) then return false end
  return true
end

local function entryOf(e)
  local en = entries[e]
  if en ~= nil then
    -- the sprite can change under the object (scripts swap it)
    if not en or en.sprite == (e.def and (e.def.spriteName or e.def.sprite)) then return en or nil end
  end
  local have = built()
  if not have then return nil end
  local name = N.nameOf(e)
  local id
  if name then
    local okC, C = pcall(Casting)
    if okC and C and C.personModel then
      local okP, v = pcall(C.personModel, name, tostring(e.id or "") .. "|" .. name, have)
      id = okP and v or nil
    end
  end
  local n
  if id then
    local D = V.require("ColosseumDex")
    n = D.trainerDex and D.trainerDex(id)
    if not n and D.loadOrasTrainers then pcall(D.loadOrasTrainers, mod); n = D.trainerDex(id) end
  end
  en = n and { id = id, n = n, name = name, sprite = e.def and (e.def.spriteName or e.def.sprite) } or false
  entries[e] = en
  return en or nil
end

-- the player's position, for the radius
local function playerXY()
  local okG, Game = pcall(require, "src.core.Game")
  local p = okG and Game and Game.overworld and Game.overworld.player
  return p and p.px, p and p.py
end

function N.wants(e, isPlayer)
  if not N.enabled() then return false end
  if not isPersonEntity(e, isPlayer) then return false end
  return entryOf(e) ~= nil
end

-- --------------------------------------------------------------- the actors

local function service()
  return mod and mod.exports and mod.exports.pokemonActorsOverworld
end

local function actorOf(en)
  if en.actor ~= nil then return en.actor or nil end
  local svc = service()
  if not (svc and type(svc.acquire) == "function") then return nil end
  local ok, actor = pcall(svc.acquire, "overworld", en.n, "normal", {
    context = { services = { informationSurface = false }, arena = {} },
  })
  if not (ok and actor) then
    -- not loadable now (cold cache): retry in a while, the card draws
    en.retryAt = clock() + 2
    return nil
  end
  pcall(actor.spawn, actor, 1)
  if (tonumber(actor.spawnScale) or 0) < 1 then actor.spawnScale = 1 end
  actor.orasNoAutoIdleB = true
  pcall(actor.selectNativeSlot, actor, "idle")
  pcall(actor.transition, actor, "idle")
  if type(actor.build) == "function" then pcall(actor.build, actor) end
  en.actor = actor
  en.bank = "idle"
  en.fidgetIn = 3 + math.random() * 6
  return actor
end

-- once per frame: stand / walk / run from the NPC's own movement
local function drive(en, actor, e, px, py)
  local t = clock()
  local dt = en.lastT and (t - en.lastT) or (1 / 60)
  en.lastT = t
  dt = math.min(math.max(dt, 0), 0.1)
  local speed = 0
  if en.lastX and px and py then
    local dx, dy = px - en.lastX, py - en.lastY
    speed = math.sqrt(dx * dx + dy * dy)
    if speed > 24 then speed = 0 end   -- a warp, not a step
  end
  en.lastX, en.lastY = px, py
  local moving = speed > 0.01 or e.moving == true
  if moving then en.still = 0 else en.still = (en.still or 0) + dt end
  local want = "idle"
  if moving then
    want = e.running == true and "run" or "walk"
  elseif en.bank ~= "idle" and en.still < N.STILL_HOLD then
    want = en.bank
  end
  if want ~= en.bank then
    actor.action, actor.actionAge = nil, 0
    local ok = actor:selectNativeSlot(want)
    if not ok and want == "run" then ok = actor:selectNativeSlot("walk") end
    if not ok then actor:selectNativeSlot("idle") end
    actor:transition("idle")
    en.bank = want
    en.fidgetIn = 4 + math.random() * 6
  end
  -- standing: the character's own look-around (idle B) now and then
  if want == "idle" and not actor.action then
    en.fidgetIn = (en.fidgetIn or 5) - dt
    if en.fidgetIn <= 0 then
      en.fidgetIn = 5 + math.random() * 8
      if actor.startOrasExtra then pcall(actor.startOrasExtra, actor, "idleB") end
    end
  end
  local h = tonumber(actor.height) or 0
  if h > 0.01 then actor.worldScale = N.HEIGHT / h end
  pcall(actor.update, actor, dt)
end

local frameToken, drawnThisFrame = nil, 0
local drewLast = setmetatable({}, { __mode = "k" })   -- entity -> frame token it drew on

local function worldFactor()
  local okS, S = pcall(function() return V.optional and V.optional("Gen4PokemonScale") end)
  if okS and S and S.factor then
    local ok, f = pcall(S.factor)
    if ok and tonumber(f) then return tonumber(f) end
  end
  -- PlayerModel's own fallback (gen4WorldFactor)
  local okG, Game = pcall(require, "src.core.Game")
  local game = okG and Game and Game.get and Game:get() or nil
  local map = game and game.overworld and game.overworld.map
  local renderer = map and map.renderer
  return (renderer and renderer.gen4Ground) and 1.5 or 1
end

local FACING_BEARING = { down = 0, right = math.pi / 2, up = math.pi, left = -math.pi / 2 }

-- draw entity `e` at (px, py, y) facing world `facing`; true when drawn
local function drawAt(e, px, py, y, facing, gen4)
  if not N.enabled() then return false end
  local en = entryOf(e)
  if not en then return false end
  if en.retryAt and clock() < en.retryAt then return false end
  local Voxel3D, Mat4 = V.require("Voxel3D"), V.require("Mat4")
  local vp = Voxel3D.vp
  if not vp then return false end
  if frameToken ~= vp then frameToken, drawnThisFrame = vp, 0 end
  if drawnThisFrame >= N.MAX_PER_FRAME then return false end
  -- radius in MAP pixels on both sides: the drawn position carries the
  -- ground's world offset on Gen 4 / 5 (Gen4WorldHost adds offsetX / Y), the
  -- player's px does not -- comparing the two put every NPC out of range
  local qx, qy = playerXY()
  local ex, ey = tonumber(e.px), tonumber(e.py)
  if qx and ex and ey then
    local dx, dy = ex - qx, ey - qy
    if dx * dx + dy * dy > N.RADIUS * N.RADIUS then return false end
  end
  local actor = actorOf(en)
  if not actor then return false end
  local svc = service()
  if not (svc and type(svc.withRenderer) == "function") then return false end
  if en.frame ~= vp then
    en.frame = vp
    drive(en, actor, e, px, py)
  end
  local f = type(facing) == "string" and facing:lower() or "down"
  local b = FACING_BEARING[f] or 0
  local fx, fz = math.sin(b), math.cos(b)
  local okM, am = pcall(actor.matrix, actor, 0, 0, 0, fx, fz)
  if not (okM and am) then return false end
  local m = Mat4.translate((px or 0) + 8, y or 0, (py or 0) + 8)
  local g = gen4 and worldFactor() or 1
  if g ~= 1 then m = Mat4.mul(m, Mat4.scale(g, g, g)) end
  m = Mat4.mul(m, am)
  local ok, accepted = pcall(svc.withRenderer, vp, function()
    if type(actor.build) == "function" and actor:build() == false then error("build declined") end
    if actor:draw(m) == false then error("draw declined") end
    return true
  end, { eye = Voxel3D.eye })
  local drew = ok and accepted ~= false
  if drew then
    drawnThisFrame = drawnThisFrame + 1
    drewLast[e] = vp
  elseif not en.warned then
    en.warned = true
    log("warn", "ORAS NPCS: %s (%s) did not draw: %s", tostring(en.id), tostring(en.name), tostring(accepted))
  end
  return drew
end

-- Gen 1-3 (VoxelScene's tryNpcBody): a posed card
function N.drawVoxel(p)
  if not (p and p.entity) or p.isPlayer or (p.waterline or 0) > 0 then return false end
  if not N.wants(p.entity, false) then return false end
  return drawAt(p.entity, p.px, p.py, (p.gh or 0) + (p.lift or 0), p.facing or p.entity.facing, false)
end

-- Gen 1-3 shadow pass: true = this one is ours, cast no card shadow
function N.ownsVoxel(p)
  local e = p and p.entity
  return e ~= nil and frameToken ~= nil and drewLast[e] == frameToken and N.enabled() or false
end

-- Gen 4 / 5 (Gen4WorldHost.drawFieldActors): a posed entity
function N.drawGen4(p)
  if not (p and p.entity) or p.isPlayer then return false end
  if not N.wants(p.entity, false) then return false end
  return drawAt(p.entity, p.px, p.py, p.gh or 0, p.facing or p.entity.facing, true)
end

function N.reset()
  entries = setmetatable({}, { __mode = "k" })
  drewLast = setmetatable({}, { __mode = "k" })
  haveMemo, haveAt = nil, -1
end

-- F12 (RenderDump): who is cast as whom
function N.report(out)
  out[#out + 1] = ""
  out[#out + 1] = ("ORAS NPCS: enabled %s, drawn last frame %d"):format(tostring(N.enabled()), drawnThisFrame)
  local n = 0
  for e, en in pairs(entries) do
    if en and n < 40 then
      n = n + 1
      out[#out + 1] = ("  %s  %-24s -> %s (%s) bank %s drew %s"):format(tostring(e.id),
        tostring(en.name), tostring(en.id), tostring(en.n), tostring(en.bank), tostring(drewLast[e] ~= nil))
    end
  end
end

return N
