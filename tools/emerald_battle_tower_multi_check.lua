-- Run:  python tools/run_lua_check.py tools/emerald_battle_tower_multi_check.lua <emerald cache dir> [pokeemerald]
--
-- EMERALD'S MULTI BATTLE ROOMS (src/script/Gen3BattleFrontier.lua) against
-- battle_tower.c: the partner room's six candidates and their Pokemon
-- (LoadMultiPartnerCandidatesData, its first-Pokemon quirk kept), what they
-- say (ShowPartnerCandidateMessage, sPartnerTrainerTextTables out of the
-- ROM), the fourteen opponents drawn on accepting, the pair each battle
-- meets, the partner's team (FillPartnerParty), and the wiring.

package.path = './?.lua;./?/init.lua;' .. package.path
love = require('tests.love_stub')
package.loaded['src.core.Sound'] = { play = function() end }
require('src.core.GameVersion').set('emerald')
local PASS, FAIL = 0, 0
local function check(c, l) if c then PASS = PASS + 1 else FAIL = FAIL + 1; print('FAIL: ' .. l) end end
local dir = (arg and arg[1] or 'G:/Gen2Recomped/emerald/data/generated'):gsub('[/\\]$', '')
local pret = arg and arg[2]
local function load(n) local f = loadfile(dir .. '/' .. n .. '.lua') return f and f() end
local function src(p) local f = io.open(p, 'rb'); local s = f and f:read('*a'); if f then f:close() end return s or '' end

local Commands = require('src.script.Commands')
local F = require('src.script.Gen3BattleFrontier')
local G3 = require('src.script.Gen3Commands')
local constants = load('constants')
local data = { constants = constants, pokemon = load('pokemon'), moves = load('moves'), items = load('items'),
  trainers = load('trainers') or {}, gen3_frontier_speech = load('gen3_frontier_speech') }
local P = constants and constants.gen3FrontierParties

-- --------------------------------------------------------------- the lines --
local pt = data.gen3_frontier_speech and data.gen3_frontier_speech.partnerTexts
local n = 0
for _ in pairs(pt or {}) do n = n + 1 end
check(n == 50, "sPartnerTrainerTextTables: fifty classes' lines (tools/gen3_frontier_speech_extract.lua)")
check(pt and pt[0x47] and pt[0x47][0]:find('LASS!') and pt[0x47][3]:find('registration'),
  "the LASS: \"I'm {STR_VAR_1}, and I'm a LASS!\" ... \"I'll go do the registration!\"")
local five = true
for _, lines in pairs(pt or {}) do for k = 0, 4 do if not lines[k] or lines[k] == '' then five = false end end end
check(five, 'every class has its five lines')

-- ------------------------------------------------------------ the candidates --
local Pokemon = require('src.pokemon.Pokemon')
local save = { party = {}, vars = {}, flags = {} }
local ctx = { save = save, game = { data = data, stringBuffers = {} } }
local shown = {}
Commands.show_text = function(c, id) shown[#shown + 1] = c.game.stringBuffers[4] end
local s = F.state(save)
s.data[1] = F.LVL_50
G3.setVar(save, F.VAR_MODE, F.MULTIS)
-- your two: species the partners must avoid
local mine1, mine2 = P.mons[P.trainers[1].set[1]].species, P.mons[P.trainers[2].set[1]].species
save.party = { { species = mine1, level = 50 }, { species = mine2, level = 50 } }
local allOk, classesOk, itemOk, quirkSeen = true, true, true, false
for _ = 1, 60 do
  s.trainerIds = {}
  F.loadPartners(ctx, s, F.MULTIS, F.LVL_50)
  local ids = s.trainerIds
  for a = 0, 5 do
    for b = a + 1, 5 do
      local ta, tb = F.trainerRecord(data, ids[a]), F.trainerRecord(data, ids[b])
      if ids[a] == ids[b] or ta.facilityClass == tb.facilityClass then classesOk = false end
    end
  end
  for k = 8, 19 do
    local row = P.mons[ids[k]]
    if not row then allOk = false end
    for j = 8, k - 1 do
      if k > 8 and P.mons[ids[j]].species == row.species then allOk = false end
    end
    if k > 8 and (row.species == mine1 or row.species == mine2) then allOk = false end
    if k % 2 == 1 and P.mons[ids[k - 1]].item == row.item then itemOk = false end
  end
  local first = P.mons[ids[8]]
  if first.species == mine1 or first.species == mine2 then quirkSeen = true end
end
check(classesOk, 'six candidates, none twice and no two of one class')
check(allOk, 'their twelve: no species twice, and never one of yours -- from the second on')
check(itemOk, "a candidate's second never holds the first's item")
check(G3.getVar(save, F.VAR_GFX0) == F.trainerGfx(data, s.trainerIds[0]), 'VAR_OBJ_GFX_ID_0..5: their sprites')
-- the quirk, forced: the first candidate's set made of your species only
local tr0 = F.trainerRecord(data, 0)
local realSet = tr0.set
local mineId = P.trainers[1].set[1]
tr0.set = { mineId }
local okFirst = true
for i = 1, 20 do
  s.trainerIds = {}
  local calls = 0
  F.loadPartners(ctx, s, F.MULTIS, F.LVL_50, function(a, b)
    calls = calls + 1
    if calls <= 12 then return 0 end         -- trainer 0 first, then anyone
    return math.random(a, b)
  end)
  if s.trainerIds[0] == 0 and s.trainerIds[8] ~= mineId then okFirst = false end
end
tr0.set = realSet
check(okFirst, "the first candidate's first Pokemon is never checked against yours (k runs from 8 to r10)")

-- --------------------------------------------------------------- the talk --
s.trainerIds = {}
F.loadPartners(ctx, s, F.MULTIS, F.LVL_50)
G3.setVar(save, 0x800F, 4)                     -- the third candidate (local id 4)
shown = {}
F.partnerMessage(ctx, s, F.MULTIS, F.LVL_50, F.PARTNER_INTRO)
local tr = F.trainerRecord(data, s.trainerIds[2])
check(shown[1] and shown[1]:find(tr.name, 1, true), 'the intro names the candidate')
F.partnerMessage(ctx, s, F.MULTIS, F.LVL_50, F.PARTNER_MON1)
local row = P.mons[s.trainerIds[12]]
local sname = data.pokemon[row.species].name
check(shown[2] and shown[2]:find(sname, 1, true), "the first Pokemon by species, with its first move")
local chosenId, m1, m2 = s.trainerIds[2], s.trainerIds[12], s.trainerIds[13]
F.partnerMessage(ctx, s, F.MULTIS, F.LVL_50, F.PARTNER_ACCEPT)
local ids = s.trainerIds
check(ids[17] == chosenId, 'the partner kept in trainerIds[17]')
-- copied out before the fourteen opponents are drawn over slots 0-13
check(ids[18] == m1 and ids[19] == m2, 'and their two in 18-19')
local distinct = true
for a = 0, 13 do
  if ids[a] == ids[17] then distinct = false end
  for b = a + 1, 13 do if ids[a] == ids[b] then distinct = false end end
end
check(distinct, 'fourteen opponents, none twice, never the partner')
local hard = true
for a = 12, 13 do local r = F.RANGES_HARD[1]; if ids[a] < r[1] or ids[a] > r[2] then hard = false end end
check(hard, "the seventh pair from the hard range")

-- ----------------------------------------------------------- each battle --
s.data[2] = 3
F.towerFunc(ctx, 3)
check(s.opponent == ids[6] and s.opponentB == ids[7], "SetNextFacilityOpponent's multi branch: trainerIds[n*2], [n*2+1]")
check(G3.getVar(save, F.VAR_GFX0 + 1) == F.trainerGfx(data, ids[7]), 'both on their own sprites')
G3.setVar(save, 0x8005, 1)
F.towerFunc(ctx, 7)
check(ctx.game.stringBuffers[4] ~= nil, 'GetOpponentIntroSpeech: 0x8005 picks the second')
F.towerFunc(ctx, 14)
check(G3.getVar(save, F.VAR_GFX_E) == F.trainerGfx(data, ids[17]), "SetMultiPartnerGfx: VAR_OBJ_GFX_ID_E")
local partner = F.partnerParty(data, s, 50)
check(#partner == 2 and partner[1].level == 50 and partner[1].ivs.hp == F.ivsFor(ids[17]),
  "FillPartnerParty: two at the challenge's level, the partner's own IVs")
local a = F.trainerParty(data, ids[6], 2, 50)
local b = F.trainerParty(data, ids[7], 2, 50, nil, a)
local clash = false
for _, x in ipairs(a) do for _, y in ipairs(b) do
  if x.species == y.species or (x.item and x.item == y.item) then clash = true end
end end
check(#b == 2 and not clash, "the second trainer's two avoid the first's species and items")

-- ------------------------------------------------------------------ wiring --
local fr = src('src/script/Gen3BattleFrontier.lua')
check(fr:find('trainerBKey = keyB', 1, true) and fr:find('ally = ally', 1, true), 'the battle: a partner and two trainers')

if pret then
  local c = src(pret .. '/src/battle_tower.c')
  local tbl = c:match('sPartnerTrainerTextTables%[%] =%s*(%b{})') or ''
  local classes = {}
  for line in src(pret .. '/include/constants/trainers.h'):gmatch('[^\n]+') do
    local nm, v = line:match('#define (FACILITY_CLASS_[%w_]+)%s+0x(%x+)')
    if nm then classes[nm] = tonumber(v, 16) end
  end
  local k, same = 0, true
  for nm in tbl:gmatch('{(FACILITY_CLASS_[%w_]+),') do
    k = k + 1
    if not (pt and pt[classes[nm]]) then same = false end
  end
  check(k == 50 and same, 'every class in sPartnerTrainerTextTables has lines')
end

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
