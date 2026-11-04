-- ORASBattleTrainers: ORAS trainers standing in battle (row ORAS BTL TRAINERS
-- on the ORAS.. menu), in place of the flat trainer pic on every 3D-BTL rung
-- (2D-3D A/B, STADIUM A/B, COLOSSEUM A/B and the ORAS arena: all of them are
-- staged by lib/OverworldBattle.lua and drawn by lib/BattleScene.lua).
--
-- Who stands where (T.pick):
--   player side  the ORAS PLAYER character (its battle model when it has
--                one), else Brendan / May by the save's gender
--   named foe    a principal character replaces its own trainer directly by
--                NAME (Emerald's Roxanne, Wally, Steven, Maxie ...)
--   rival        the other one of Brendan / May
--   boss         gym leaders, Elite Four, champions in the other games: a
--                random principal character (the same one every time for
--                the same trainer; a girl for a girl when that is known)
--   grunts       Rocket / Magma / Aqua / Galactic / Plasma / Flare grunts: a
--                Magma or Aqua grunt of the trainer's gender
--   anyone else  an NPC by KEYWORDS in the trainer class (SWIMMER, HIKER,
--                LASS, BEAUTY ...), else a random NPC of the class's gender
--                and age.  Field models have no throw: they just stand.
--
-- Each trainer stands behind its own Pokemon, a little to the side, facing
-- the other side.  Battle models (which have them) throw at the send-out
-- and point when their side uses a move.  The flat trainer pic is hidden on
-- a side only while its ORAS trainer actually draws (fails open).
--
-- Independent of Colosseum: own row, own file; it only reaches the shared
-- actor runtime (ColosseumMon.actor on ColosseumDex trainer numbers).

local V = ...
local mod = V and V.mod

local B = { ID = "oras_btl_trainers", LABEL = "ORAS BTL TRAINERS" }
B.SETTING = "oras/trainers/battle.txt"

-- world pixels: a cell is 16, a mid-size Pokemon about 14
B.HEIGHT = 20          -- how tall a trainer stands
B.BACK = 22            -- behind its own Pokemon, along the line between the two
B.SIDE = 10            -- and this far to its own right

local function log(level, fmt, ...)
  local l = mod and mod.log
  if l and type(l[level]) == "function" then pcall(l[level], l, fmt, ...) end
end

local function Trainers() return V.require("ORASTrainers") end
local function Dex() return V.require("ColosseumDex") end
local function Mon() return V.require("ColosseumMon") end

-- ------------------------------------------------------------- the setting

local settingValue
function B.enabled()
  if settingValue == nil then
    local ok, s = pcall(mod.cache.read, mod.cache, B.SETTING)
    -- off until the user turns it on
    settingValue = ok and type(s) == "string" and s:find("on", 1, true) ~= nil or false
  end
  return settingValue
end
function B.setEnabled(on)
  settingValue = on and true or false
  pcall(mod.cache.write, mod.cache, B.SETTING, on and "on\n" or "off\n")
end

function B.row()
  return {
    id = B.ID,
    label = B.LABEL,
    value = function()
      local okT, T = pcall(Trainers)
      if not (okT and T and T.built()) then return "BUILD TRAINERS" end
      return B.enabled() and "ON" or "OFF"
    end,
    step = function()
      local okT, T = pcall(Trainers)
      if not (okT and T and T.built()) then
        log("info", "ORAS BTL TRAINERS: build the characters first (ORAS TRAINERS)")
        return true
      end
      B.setEnabled(not B.enabled())
      return true
    end,
  }
end

-- ------------------------------------------------------------- the casting

-- battle model for a field character, where one exists
B.BATTLE_OF = {
  rstr0001 = "rsbt0001", rstr0002 = "rsbt0002",
  rstr0003 = "rsbt0001", rstr0004 = "rsbt0002",
  rstr0050 = "rsbt0001", rstr0051 = "rsbt0002",
  rstr0010 = "rsbt0003", rstr0011 = "rsbt0003",
  rstr0012 = "rsbt0005", rstr0026 = "rsbt0019", rstr0031 = "rsbt0024",
  rstr0042 = "rsbt0035",
}

-- principal characters by trainer NAME (Emerald's own trainers)
B.BY_NAME = {
  ROXANNE = "rstr0017", BRAWLY = "rstr0018", WATTSON = "rstr0019",
  FLANNERY = "rstr0020", NORMAN = "rstr0021", WINONA = "rstr0022",
  TATE = "rstr0023", LIZA = "rstr0024", ["TATE&LIZA"] = "rstr0023", ["TATE & LIZA"] = "rstr0023",
  WALLACE = "rstr0025", SIDNEY = "rstr0013", PHOEBE = "rstr0014",
  GLACIA = "rstr0015", DRAKE = "rstr0016", STEVEN = "rstr0012",
  WALLY = "rstr0010", MAXIE = "rstr0026", ARCHIE = "rstr0031",
  TABITHA = "rstr0027", COURTNEY = "rstr0028", MATT = "rstr0032",
  SHELLY = "rstr0033", ZINNIA = "rstr0042", LISIA = "rstr0040",
  AARUNE = "rstr0041", BIRCH = "rstr0009", ["PROF. BIRCH"] = "rstr0009",
  BRENDAN = "rstr0002", MAY = "rstr0001",
}

-- the random pick for a boss in the other games (gym leaders, E4, champions)
B.PRINCIPALS_F = { "rstr0017", "rstr0020", "rstr0022", "rstr0024", "rstr0014",
                   "rstr0015", "rstr0028", "rstr0033", "rstr0040", "rstr0042" }
B.PRINCIPALS_M = { "rstr0018", "rstr0019", "rstr0021", "rstr0023", "rstr0025",
                   "rstr0013", "rstr0016", "rstr0012", "rstr0010", "rstr0026",
                   "rstr0031", "rstr0027", "rstr0032", "rstr0041" }

B.GRUNTS_M = { "rstr0029", "rstr0034" }
B.GRUNTS_F = { "rstr0030", "rstr0035", "rstr0043", "rstr0044" }

-- NPC field models (rstr0101-0225, named from the contact sheet), by look
B.NPC = {
  kid_m   = { "rstr0110", "rstr0151", "rstr0167", "rstr0212" },
  kid_f   = { "rstr0111", "rstr0149", "rstr0150", "rstr0152", "rstr0155", "rstr0168", "rstr0213" },
  young_m = { "rstr0101", "rstr0103", "rstr0104", "rstr0106", "rstr0128", "rstr0131",
              "rstr0158", "rstr0187", "rstr0189", "rstr0197", "rstr0199", "rstr0219" },
  young_f = { "rstr0102", "rstr0105", "rstr0107", "rstr0109", "rstr0120", "rstr0153",
              "rstr0154", "rstr0185", "rstr0186", "rstr0188", "rstr0198", "rstr0200", "rstr0202" },
  adult_m = { "rstr0112", "rstr0115", "rstr0116", "rstr0119", "rstr0121", "rstr0122",
              "rstr0129", "rstr0130", "rstr0132", "rstr0138", "rstr0143", "rstr0159",
              "rstr0172", "rstr0178", "rstr0180", "rstr0184", "rstr0191", "rstr0196",
              "rstr0201", "rstr0205", "rstr0209", "rstr0216", "rstr0217" },
  adult_f = { "rstr0113", "rstr0126", "rstr0135", "rstr0136", "rstr0137", "rstr0139",
              "rstr0144", "rstr0147", "rstr0160", "rstr0163", "rstr0179", "rstr0183",
              "rstr0194", "rstr0204", "rstr0206", "rstr0210", "rstr0218", "rstr0225" },
  old_m   = { "rstr0114", "rstr0145", "rstr0166", "rstr0169", "rstr0193", "rstr0207",
              "rstr0211", "rstr0214" },
  old_f   = { "rstr0146", "rstr0170", "rstr0208", "rstr0215" },
}

-- class keywords -> models, first match wins.  { words, male, female }
-- (female nil = the male list for both)
B.CLASS_KEYWORDS = {
  { { "TUBER" }, { "rstr0110" }, { "rstr0111" } },
  { { "SWIMMER", "SWIMMER♂", "SWIMMER♀" }, { "rstr0112" }, { "rstr0113" } },
  { { "BUG CATCHER", "BUG MANIAC", "BUG" }, { "rstr0103", "rstr0124" } },
  { { "BLACK BELT", "BLACKBELT", "KARATE" }, { "rstr0119" }, { "rstr0120" } },
  { { "BATTLE GIRL", "CRUSH GIRL" }, { "rstr0120" }, { "rstr0120" } },
  { { "HIKER", "MOUNTAINEER" }, { "rstr0116", "rstr0203" } },
  { { "SAILOR" }, { "rstr0115" } },
  { { "FISHERMAN", "FISHER" }, { "rstr0122" } },
  { { "RUIN MANIAC", "RUIN" }, { "rstr0125" } },
  { { "HEX MANIAC", "HEX" }, { "rstr0126" }, { "rstr0126" } },
  { { "POKEMANIAC", "POKE MANIAC", "POKÉMANIAC", "MANIAC", "COLLECTOR", "SUPER NERD", "NERD" }, { "rstr0123", "rstr0121" } },
  { { "PSYCHIC", "CHANNELER", "MEDIUM", "SAGE" }, { "rstr0127" }, { "rstr0126" } },
  { { "KINDLER", "FIREBREATHER", "FIRE BREATHER", "BURGLAR" }, { "rstr0128", "rstr0129" } },
  { { "GUITARIST", "ROCKER", "JUGGLER" }, { "rstr0132" } },
  { { "POKEFAN", "POKÉFAN", "POKEMON FAN" }, { "rstr0138" }, { "rstr0139" } },
  { { "SCIENTIST", "ENGINEER", "RESEARCHER" }, { "rstr0190", "rstr0193" } },
  { { "GENTLEMAN", "RICH BOY", "RICHBOY", "AROMA", "GAMBLER" }, { "rstr0108", "rstr0114" }, { "rstr0109" } },
  { { "LADY", "SOCIALITE", "MADAME" }, { "rstr0108" }, { "rstr0109" } },
  { { "PARASOL" }, { "rstr0136" }, { "rstr0136" } },
  { { "BEAUTY" }, { "rstr0135", "rstr0137" }, { "rstr0135", "rstr0137" } },
  { { "EXPERT", "VETERAN", "ELDER", "OLD" }, { "rstr0145" }, { "rstr0146" } },
  { { "TRIATHLETE", "CYCLIST", "BIKER", "ATHLETE" }, { "rstr0140" } },
  { { "SCHOOL KID", "SCHOOLKID", "SCHOOLBOY", "SCHOOLGIRL" }, { "rstr0106" }, { "rstr0107" } },
  { { "NINJA" }, { "rstr0131" } },
  { { "COOLTRAINER", "COOL TRAINER", "ACE TRAINER", "VETERAN", "DRAGON TAMER" }, { "rstr0130", "rstr0143" }, { "rstr0144" } },
  { { "POKEMON RANGER", "POKÉMON RANGER", "RANGER" }, { "rstr0159" }, { "rstr0160" } },
  { { "TWINS", "TWIN" }, { "rstr0149", "rstr0150" }, { "rstr0149", "rstr0150" } },
  { { "NURSE", "CLERK", "WAITER", "WAITRESS", "MAID" }, { "rstr0117" }, { "rstr0118", "rstr0181" } },
  { { "INTERVIEWER", "REPORTER", "CAMERAMAN" }, { "rstr0148" }, { "rstr0147" } },
  { { "YOUNGSTER", "CAMPER", "BACKPACKER", "BIRD KEEPER" }, { "rstr0101", "rstr0158" }, { "rstr0105" } },
  { { "LASS", "PICNICKER", "JR TRAINER" }, { "rstr0105" }, { "rstr0102", "rstr0105" } },
}

-- grunt / team words
local TEAM_WORDS = { "ROCKET", "MAGMA", "AQUA", "GALACTIC", "PLASMA", "FLARE", "GRUNT" }
-- a girl, an old one, a child: words in the class
local FEMALE_WORDS = { "F", "FEMALE", "GIRL", "LASS", "LADY", "BEAUTY", "MISS", "WOMAN",
  "PICNICKER", "AROMA", "PARASOL", "NURSE", "KIMONO", "MEDIUM", "CHANNELER", "TWINS",
  "SIS", "HEX", "MAID", "WAITRESS", "SCHOOLGIRL", "IDOL", "SOCIALITE", "DANCER",
  "MADAME", "SWIMMER♀", "♀", "COWGIRL", "BATTLE GIRL", "SISTER", "QUEEN", "PRINCESS" }
local OLD_WORDS = { "OLD", "ELDER", "SAGE", "EXPERT", "GENTLEMAN", "GRAMPS", "GRANNY",
  "VETERAN", "MASTER", "ELDERLY" }
local KID_WORDS = { "TUBER", "KID", "PRESCHOOL", "PRESCHOOLER", "INFANT", "TODDLER", "TWINS" }
local YOUNG_WORDS = { "YOUNGSTER", "BUG", "CAMPER", "PICNICKER", "SCHOOL", "LASS",
  "SCHOOLBOY", "SCHOOLGIRL", "JR", "BOY", "GIRL", "NINJA", "KINDLER" }
-- bosses by name (Gen 1 / 2 classes are their names), and which are girls
local BOSS_NAMES = { "BROCK", "MISTY", "LT SURGE", "SURGE", "ERIKA", "KOGA",
  "JANINE", "SABRINA", "BLAINE", "GIOVANNI", "LORELEI", "BRUNO", "AGATHA", "LANCE",
  "FALKNER", "BUGSY", "WHITNEY", "MORTY", "CHUCK", "JASMINE", "PRYCE", "CLAIR",
  "WILL", "KAREN", "RED", "BLUE", "JUAN" }
local GIRL_NAMES = { MISTY = true, ERIKA = true, JANINE = true, SABRINA = true,
  LORELEI = true, AGATHA = true, WHITNEY = true, JASMINE = true, CLAIR = true,
  KAREN = true, ROXANNE = true, FLANNERY = true, WINONA = true, LIZA = true,
  PHOEBE = true, GLACIA = true, CYNTHIA = true, GARDENIA = true, FANTINA = true,
  CANDICE = true, BERTHA = true, ELESA = true, SKYLA = true, IRIS = true,
  SHAUNTAL = true, CAITLIN = true, LENORA = true, MAY = true, DAWN = true,
  LYRA = true, LEAF = true, HILDA = true, ROSA = true }

local function upper(s) return tostring(s or ""):upper() end
local function words(s)
  local out = {}
  for w in upper(s):gsub("[_%-%./]", " "):gmatch("%S+") do out[#out + 1] = w end
  return out
end
local function hasWord(list, wanted)
  for _, w in ipairs(list) do
    for _, x in ipairs(wanted) do if w == x then return true end end
  end
  return false
end
local function hasPhrase(text, wanted)
  for _, x in ipairs(wanted) do
    if (" " .. text .. " "):find(" " .. x .. " ", 1, true) then return true end
  end
  return false
end

-- stable "random": the same trainer always gets the same model
local function hash(s)
  local h = 5381
  s = tostring(s or "")
  for i = 1, #s do h = (h * 33 + s:byte(i)) % 2147483647 end
  return h
end

local function built()
  local okT, T = pcall(Trainers)
  local idx = okT and T and T.index()
  if not idx then return nil end
  local have = {}
  for _, e in ipairs(idx.list) do have[e.id] = true end
  return have
end

local function pickFrom(list, key, have)
  local ok = {}
  for _, id in ipairs(list or {}) do if have[id] then ok[#ok + 1] = id end end
  if #ok == 0 then return nil end
  return ok[hash(key) % #ok + 1]
end

-- the battle model if there is one
local function withBattle(id, have)
  local bt = id and B.BATTLE_OF[id]
  if bt and have[bt] then return bt end
  return id
end

local function playerIsGirl(game)
  local p = game and game.save and game.save.player
  local g = p and p.gender
  return g == "girl" or g == "female" or g == 1 or (p and p.female == true) or false
end

-- the player's own trainer
function B.playerModel(game, have)
  have = have or built()
  if not have then return nil end
  local okT, T = pcall(Trainers)
  local id = okT and T and T.currentPlayer and T.currentPlayer()
  if id and have[id] then return withBattle(id, have) end
  local fallback = playerIsGirl(game) and "rstr0001" or "rstr0002"
  return have[fallback] and withBattle(fallback, have) or nil
end

-- the foe's trainer for a battle (nil = none: wild, link, unknown)
function B.foeModel(battle, have)
  have = have or built()
  if not (have and battle and battle.kind == "trainer") then return nil end
  local tr = battle.trainer or {}
  local name = upper(tr.translationSourceName or tr.name or battle.trainerName or battle.oppName)
  local class = upper(tr.className or battle.trainerClass or battle.oppClass or tr.id)
  local key = class .. "|" .. name .. "|" .. tostring(battle.partyIndex or "")
  local girl = tr.female == true or tr.gender == "female" or GIRL_NAMES[name] == true
  local cw = words(class)
  -- phrases are matched on the words ("OPP_BUG_CATCHER" -> "OPP BUG CATCHER")
  local classText = table.concat(cw, " ")
  local nameText = table.concat(words(name), " ")
  if not girl and hasWord(cw, FEMALE_WORDS) then girl = true end

  -- 1. a principal character by name
  local named = B.BY_NAME[name]
  if named and have[named] then return withBattle(named, have) end

  -- 2. the rival: the other one of Brendan / May
  local game = battle.game or (mod and mod.game)
  local rivalName = game and game.save and game.save.player and upper(game.save.player.rival)
  local isRival = class:find("RIVAL", 1, true) ~= nil or (rivalName and rivalName ~= "" and name == rivalName)
  if isRival then
    local id = playerIsGirl(game) and "rstr0002" or "rstr0001"
    if have[id] then return withBattle(id, have) end
  end

  -- 3. grunts
  if hasPhrase(classText, TEAM_WORDS) and not class:find("LEADER", 1, true)
     and not class:find("BOSS", 1, true) and not class:find("ADMIN", 1, true) then
    return pickFrom(girl and B.GRUNTS_F or B.GRUNTS_M, key, have)
  end

  -- 4. bosses: a random principal character
  local boss = battle.isGymLeader == true or class:find("LEADER", 1, true) ~= nil
    or class:find("ELITE", 1, true) ~= nil or class:find("CHAMPION", 1, true) ~= nil
    or class:find("ADMIN", 1, true) ~= nil or class:find("BOSS", 1, true) ~= nil
    or hasPhrase(nameText, BOSS_NAMES) or hasPhrase(classText, BOSS_NAMES)
  if boss then
    local id = pickFrom(girl and B.PRINCIPALS_F or B.PRINCIPALS_M, key, have)
      or pickFrom(girl and B.PRINCIPALS_M or B.PRINCIPALS_F, key, have)
    if id then return withBattle(id, have) end
  end

  -- 5. an NPC by the class's keywords
  for _, row in ipairs(B.CLASS_KEYWORDS) do
    if hasPhrase(classText, row[1]) then
      local id = pickFrom(girl and (row[3] or row[2]) or row[2], key, have)
      if id then return id end
    end
  end

  -- 6. a random NPC of that gender and age
  local age = (hasWord(cw, KID_WORDS) and "kid") or (hasWord(cw, OLD_WORDS) and "old")
    or (hasWord(cw, YOUNG_WORDS) and "young") or "adult"
  return pickFrom(B.NPC[age .. (girl and "_f" or "_m")], key, have)
    or pickFrom(B.NPC[girl and "adult_f" or "adult_m"], key, have)
end

-- ------------------------------------------------------------- the actors

local cast = { battle = nil, player = nil, enemy = nil }   -- per side: { id, n, drew, wasCard, cmd }

local function numberOf(id)
  local D = Dex()
  local n = D.trainerDex and D.trainerDex(id)
  if not n and D.loadOrasTrainers and not cast.reloaded then
    cast.reloaded = true
    pcall(D.loadOrasTrainers, mod)
    n = D.trainerDex(id)
  end
  return n
end

local function sideEntry(battle, side)
  if cast.battle ~= battle then
    cast = { battle = battle, reloaded = cast.reloaded }
  end
  local e = cast[side]
  if e == nil then
    local have = built()
    local id
    if have then
      local game = (battle and battle.game) or (mod and mod.game)
      if side == "player" then id = B.playerModel(game, have) else id = B.foeModel(battle, have) end
    end
    local n = id and numberOf(id)
    e = n and { id = id, n = n } or false
    cast[side] = e
    if e then log("info", "ORAS BTL TRAINERS: %s side = %s (%s)", side, id, tostring(Trainers().label(id))) end
  end
  return e or nil
end

local function actorOf(e)
  local okA, actor = pcall(Mon().actor, e.n, "normal")
  return okA and actor or nil
end

-- advance a trainer's actor once per frame (several draws a frame share it);
-- true on the first call of a new frame
local function clock()
  return (love and love.timer and love.timer.getTime and love.timer.getTime()) or os.clock()
end
local function advance(e, actor, height)
  local t = clock()
  local dt = e.lastT and (t - e.lastT) or (1 / 60)
  if e.lastT and dt < 0.004 then return false end
  e.lastT = t
  local h = tonumber(actor.height) or 0
  if h > 0.01 then actor.worldScale = height / h end
  pcall(actor.update, actor, math.min(math.max(dt, 0), 0.1))
  return true
end

local function play(e, action)
  local actor = e and actorOf(e)
  if actor and actor.startOrasExtra then pcall(actor.startOrasExtra, actor, action) end
end

-- the send-out throw, once per send-out (the card edge and the engine's
-- sendingOut flag can both report the same one)
local function throwOnce(e)
  local t = clock()
  if e.thrownAt and t - e.thrownAt < 1.5 then return end
  e.thrownAt = t
  play(e, "throw")
end

-- whether this side's flat trainer pic should give way (its ORAS trainer drew
-- last frame)
function B.covers(side)
  if not B.enabled() then return false end
  local e = cast[side]
  return e and e.drew == true or false
end

-- BattleScene.render, inside the 3D pass, after the Pokemon
function B.draw(arena, groundY, textures)
  if not (B.enabled() and arena and arena.player and arena.enemy) then return false end
  local okO, OB = pcall(V.require, "OverworldBattle")
  local battle = okO and OB and OB.battle and OB.battle()
  if not battle then return false end
  local any = false
  for _, side in ipairs({ "enemy", "player" }) do
    local e = (side == "player" or battle.kind == "trainer") and sideEntry(battle, side) or nil
    if e then
      e.drew = false
      local actor = actorOf(e)
      local own = side == "player" and arena.player or arena.enemy
      local other = side == "player" and arena.enemy or arena.player
      if actor and own and other then
        -- the send-out: the side's card stops being the trainer pic
        local tex = textures and textures[side]
        local card = tex and tex.trainer == true or false
        if advance(e, actor, B.HEIGHT) then
          local sending = (side == "player" and battle.sendingOut or battle.enemySendingOut) and true or false
          if (e.wasCard and not card) or (sending and not e.wasSending) then throwOnce(e) end
          e.wasCard = card
          e.wasSending = sending
        end
        local dx, dz = other[1] - own[1], other[2] - own[2]
        local len = math.sqrt(dx * dx + dz * dz)
        if len > 1e-6 then
          dx, dz = dx / len, dz / len
          -- behind, and to its own right (right of facing (dx, dz) is (-dz, dx))
          local x = own[1] - dx * B.BACK - dz * B.SIDE
          local z = own[2] - dz * B.BACK + dx * B.SIDE
          local m = Mon().matrix(e.n, "normal", x, groundY or 0, z, dx, dz)
          if m and Mon().draw(e.n, "normal", m) then
            e.drew = true
            any = true
          end
        end
      end
    end
  end
  return any
end

-- ------------------------------------------------ the Colosseum battle arena
--
-- The CBE arena (lib/Arena.lua) draws its own Colosseum trainers
-- (lib/Trainer.lua foe, lib/PlayerTrainer.lua player) at their arena
-- anchors, in arena units, with the arena's own camera.  With ORAS BTL
-- TRAINERS on, the ORAS trainer takes that place: Arena asks
-- B.drawArena first and skips the Colosseum trainer (and its ball) on every
-- side this drew.
B.ARENA_HEIGHT = 6.9   -- the Colosseum trainers' enemyWorldHeight

local arenaDrew = {}

function B.drewArena(side)
  return arenaDrew[side] == true
end

function B.drawArena(ctx, vp, pose, playerAnchor, enemyAnchor)
  arenaDrew = {}
  if not (B.enabled() and vp and playerAnchor and enemyAnchor) then return false end
  local battle = type(ctx) == "table" and (ctx.battle or (ctx.kind and ctx)) or nil
  if not battle then return false end
  local svc = mod and mod.exports and mod.exports.pokemonActorsOverworld
  if not (svc and type(svc.withRenderer) == "function") then return false end
  local a = ctx.arena
  local groundY = (a and a.liveField and tonumber(a.groundY)) or 0
  local jobs = {}
  for _, side in ipairs({ "enemy", "player" }) do
    local e = (side == "player" or battle.kind == "trainer") and sideEntry(battle, side) or nil
    local actor = e and actorOf(e)
    if actor then
      local sending = side == "player" and battle.sendingOut or battle.enemySendingOut
      if advance(e, actor, B.ARENA_HEIGHT) then
        if sending and not e.wasSending then throwOnce(e) end
        e.wasSending = sending and true or false
      end
      local own = side == "player" and playerAnchor or enemyAnchor
      local other = side == "player" and enemyAnchor or playerAnchor
      local dx, dz = other[1] - own[1], other[3] - own[3]
      local len = math.sqrt(dx * dx + dz * dz)
      if len > 1e-6 then dx, dz = dx / len, dz / len else dx, dz = 0, 1 end
      local okM, m = pcall(actor.matrix, actor, own[1], groundY, own[3], dx, dz)
      if okM and m then jobs[#jobs + 1] = { side = side, actor = actor, matrix = m } end
    end
  end
  if #jobs == 0 then return false end
  local any = false
  pcall(svc.withRenderer, vp, function()
    for _, job in ipairs(jobs) do
      if type(job.actor.build) ~= "function" or job.actor:build() ~= false then
        local okD, v = pcall(job.actor.draw, job.actor, job.matrix, 0)
        if okD and v ~= false then arenaDrew[job.side] = true; any = true end
      end
    end
    return true
  end, { eye = pose and pose.eye })
  for _, job in ipairs(jobs) do
    local e = cast[job.side]
    if e then e.drew = arenaDrew[job.side] == true end
  end
  return any
end

-- a side used a move: its trainer points (battle models only have it)
function B.command(side)
  if not B.enabled() then return end
  local e = cast[side]
  if e then play(e, "command") end
end

function B.reset()
  cast = { reloaded = cast.reloaded }
end

-- performMove: the user's side points
function B.install()
  -- lib/Arena.lua runs in the Colosseum namespace (no V.require): it finds
  -- this module here
  if mod and type(mod.exports) == "table" and mod.exports.orasBattleTrainers ~= B then
    mod.exports.orasBattleTrainers = B
  end
  local okB, BattleState = pcall(require, "src.battle.BattleState")
  if not okB or type(BattleState) ~= "table" or BattleState.orasBattleTrainersHook then return end
  local inner = BattleState.performMove
  if type(inner) == "function" then
    function BattleState:performMove(user, ...)
      pcall(function()
        if not B.enabled() then return end
        local side = (user == self.player or (type(user) == "table" and user.isPlayer)) and "player" or "enemy"
        B.command(side)
      end)
      return inner(self, user, ...)
    end
  end
  BattleState.orasBattleTrainersHook = true
end

return B
