-- Run:  python tools/run_lua_check.py tools/gen4_battle_tower_multi_check.lua <platinum cache dir>
--
-- THE BATTLE TOWER'S MULTI BATTLE ROOMS (src/pokemon/Gen4BattleTower.lua,
-- src/script/Gen4BattleTowerCommands.lua) against unk_02049D08.c
-- (sub_0204A4C8, sub_0204A97C, sub_0204A378), unk_0204AEE8.c (sub_0204B470)
-- and overlay104 (BattleTower_CreateOpponentParties, BattleTower_GetPartnerParam):
-- fourteen trainers drawn in pairs, two opponents a battle with the second
-- kept clear of the first, the Battle Salon's five partners and their teams,
-- what the multi rooms' scripts ask of the partner, and the partner carried
-- through Rest.  Also the two lookups this round found picking at random.

package.path = './?.lua;./?/init.lua;' .. package.path
love = require('tests.love_stub')
package.loaded['src.core.Sound'] = { play = function() end }
require('src.core.GameVersion').set('platinum')
local PASS, FAIL = 0, 0
local function check(c, l) if c then PASS = PASS + 1 else FAIL = FAIL + 1; print('FAIL: ' .. l) end end
local dir = (arg and arg[1] or 'G:/Gen2Recomped/platinum/data/generated'):gsub('[/\\]$', '')
local function load(n) local f = loadfile(dir .. '/' .. n .. '.lua') return f and f() end
local function src(p) local f = io.open(p, 'rb'); local s = f and f:read('*a'); if f then f:close() end return s or '' end

local BT = require('src.pokemon.Gen4BattleTower')
local rec = load('gen4_battle_tower')
check(rec, 'the cache has gen4_battle_tower')
local data = { gen4_battle_tower = rec }

-- ------------------------------------------------------- the partners' data --
local names = { [0] = 'Cheryl', 'Mira', 'Riley', 'Marley', 'Buck' }
for i = 0, 4 do
  local tr = rec and rec.trainers[300 + i]
  check(tr and tr.class == BT.PARTNER_CLASSES[i] and #tr.sets > 0,
    ('pl_btdtr %d is %s (class %d) with sets'):format(300 + i, names[i], BT.PARTNER_CLASSES[i]))
end
-- OBJ_EVENT_GFX_CHERYL..MIRA in generated/object_events_gfx.txt order
local gfx = { [0] = 141, 145, 142, 143, 144 }
for i = 0, 4 do
  check(BT.CLASS_GFX[BT.PARTNER_CLASSES[i]] == gfx[i], names[i] .. "'s field sprite")
end

-- ------------------------------------------------------- fourteen in pairs --
local save = { party = {}, player = { gender = 1 } }
local bt = BT.init(save, 0, BT.MULTI)
check(bt.size == 2 and BT.isMulti(bt.mode), 'multi: two each')
bt.seed, bt.roomNum = 99, 2
BT.chooseTrainers(bt)
local uniq, seen, inRange = true, {}, true
for n = 0, 13 do
  local id = bt.trainers[n]
  if not id or seen[id] then uniq = false end
  seen[id or -1] = true
  local r = (math.floor(n / 2) == 6) and BT.BOSS_RANGES[3] or BT.RANGES[3]
  if not id or id < r[1] or id > r[2] then inRange = false end
end
check(uniq, 'sub_0204A4C8: fourteen, none twice')
check(inRange, 'each pair from opponent n / 2\'s range -- the seventh pair from the boss range')
check(bt.trainers[14] == nil, 'and no more')
local btS = BT.init({ party = {}, player = {} }, 0, BT.SINGLE)
btS.seed = 99
BT.chooseTrainers(btS)
check(btS.trainers[7] == nil, 'singles still draw seven')

-- ------------------------------------------------------------ two opponents --
bt.next = 3
BT.setOpponent(bt, data)
local a, b = bt.opponents and bt.opponents[0], bt.opponents and bt.opponents[1]
check(a and b and a.id == bt.trainers[4] and b.id == bt.trainers[5],
  'BattleTower_CreateOpponentParties: pair no. 3 is trainers 4 and 5')
check(a and #a.party == 2 and b and #b.party == 2, 'two Pokemon each')
local clash = false
for _, p in ipairs(a and a.party or {}) do
  for _, q in ipairs(b and b.party or {}) do
    if p.species == q.species then clash = true end
  end
end
check(not clash, 'the second opponent never shares a species with the first')
check(bt.opponent == a, 'the first is still `opponent` for what reads one')
check(BT.opponentGfx(bt, 1) == (BT.CLASS_GFX[b.class] or BT.GFX_SCHOOL_KID_M), 'GET_OPPONENT_OBJECT_ID 1 is the second')

-- createParty's avoid lists
local tr0 = rec.trainers[0]
local s1 = rec.sets[tr0.sets[1]]
local btA = { seed = 5 }
local avoided = true
for _ = 1, 30 do
  local party = BT.createParty(btA, data, 0, 2, { s1.species }, {})
  for _, p in ipairs(party) do if p.species == s1.species then avoided = false end end
end
check(avoided, 'sub_0204B470: a species in the avoid list is never drawn')

-- ------------------------------------------------------------- the partners --
local btP = BT.init({ party = {}, player = { gender = 0 } }, 0, BT.MULTI)
btP.seed = 4242
local mine = rec.sets[rec.trainers[300].sets[1]].species
btP.chosenSpecies, btP.chosenItems = { mine, 0 }, { 0, 0 }
BT.partnerTeams(btP, data)
local five, clear, ivs = true, true, true
for i = 0, 4 do
  local p = btP.partners[i]
  if not (p and p.id == 300 + i and #p.party == 2) then five = false end
  for _, m in ipairs(p and p.party or {}) do
    if m.species == mine then clear = false end
    if m.ivs ~= 31 then ivs = false end
  end
end
check(five, 'sub_0204A97C: a team of two for each of the five')
check(clear, 'clear of the species the player chose (unk_2E)')
check(ivs, 'BattleTower_GetIVsFromTrainerID: 31 for the partners')
btP.partnerID = 1
check(BT.partner(btP) == btP.partners[1], 'BT_FUNC_SET_PARTNER_ID picks Mira')
check(BT.partnerParam(btP, 2) == 1, 'BT_PARAM_PARTNER_ID')
check(BT.partnerParam(btP, 1) == 145, 'BT_PARAM_PARTNER_GRAPHICS_ID in multi: OBJ_EVENT_GFX_MIRA')
check(BT.partnerParam(btP, 0) == BT.GFX_PLAYER_M, 'BT_PARAM_PLAYER_GRAPHICS_ID: the player')
local btF = BT.init({ party = {}, player = { gender = 1 } }, 0, BT.MULTI)
check(BT.partnerParam(btF, 0) == BT.GFX_PLAYER_F, '...in her own clothes')

-- ---------------------------------------------------------- through Rest --
local restSave = { party = {}, player = {} }
local btR = BT.init(restSave, 0, BT.MULTI)
btR.seed = 77
btR.chosenSpecies, btR.chosenItems = {}, {}
BT.partnerTeams(btR, data)
btR.partnerID = 3
BT.chooseTrainers(btR)
btR.next = 4
BT.suspend(btR)
local back = BT.init(restSave, 1, 0xFFFF)
check(back.mode == BT.MULTI and back.partnerID == 3, 'Rest keeps the mode and who the partner is (field 9)')
local before, after = BT.partner(btR), BT.partner(back)
check(after and after.id == before.id and after.party[1].species == before.party[1].species
  and after.party[2].personality == before.party[2].personality,
  'and their team exactly as drawn (fields 6 and 7, sub_0204B404)')
check(back.trainers[13] == btR.trainers[13], 'and all fourteen trainers')

-- ------------------------------------------------------------ the commands --
local Commands = require('src.script.Commands')
require('src.script.Gen4Commands')
local G4 = require('src.script.Gen4Commands')
local cs = { vars = {}, flags = {}, party = {}, player = {} }
local game = { gen4BattleTower = btP, data = data, save = cs }
local ctx = { game = game, save = cs }
Commands.g4_bt_partner_species_move(ctx, 1, 1, 0x8004, 0x8005)
local m2 = btP.partners[1].party[2]
check(G4.getVar(cs, 0x8004) == m2.species and G4.getVar(cs, 0x8005) == m2.moves[1],
  'getbattletowerpartnerspeciesandmove: pokemon[mon].species and moves[0]')
local warped
local realWarp = Commands.g4_warp
Commands.g4_warp = function(_, header, x, z) warped = { header, x, z } end
local r = Commands.g4_frontier_scene({ game = game, save = cs }, 6)
Commands.g4_warp = realWarp
check(r == 'end' and warped and warped[1] == 331 and warped[2] == 7 and warped[3] == 5,
  'FRONTIER_SCENE_TOWER_MULTI_CORRIDOR: the multi battle room, (7,5)')

local vm = src('src/script/Gen4ScriptVM.lua')
for _, op in ipairs({ 'getbattletowerpartnerspeciesandmove', 'bufferspeciesnamewitharticle', 'getcurnetid',
                      'movecamera', 'clearreceivedtempdataallplayers' }) do
  check(vm:find('L.' .. op .. ' = ', 1, true), op .. ' is lowered')
end
local cmds = src('src/script/Gen4BattleTowerCommands.lua')
check(cmds:find('battle:setAlly(ally)', 1, true) and cmds:find('battle:addOpponentTrainer(keyB)', 1, true),
  'the multi battle: the partner beside the player, two trainers across')

-- ------------------------------------------- the lookups that picked at random --
local maps = {
  D_31R_0207 = { header = 493, sourceId = 'D31R0207' },
  D31R0207 = { header = 493 },
  ONLY_ALIAS = { header = 900, sourceId = 'X' },
}
local okAll = true
for _ = 1, 4 do
  -- a fresh table each time, so `pairs` order and the memo both start over
  local m = {}
  for k, v in pairs(maps) do m[k] = v end
  if G4.mapForHeader({ maps = m }, 493) ~= 'D31R0207' then okAll = false end
  if G4.mapForHeader({ maps = m }, 900) ~= 'ONLY_ALIAS' then okAll = false end
end
check(okAll, "mapForHeader: the cartridge's spelling over Data.lua's alias copy")
check(src('src/core/Data.lua'):find('not (def.sourceId and defByHeader[def.header])', 1, true),
  'the Distortion World lifts are wired onto the real map, not its alias')
check(src('src/core/Game.lua'):find('if type(key) == "string" and type(def) == "table"', 1, true),
  "the new game's PC Potion is the bag's string id, not Gen 4's bare number")

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
