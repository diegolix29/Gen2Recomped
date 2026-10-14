-- Run:  python tools/run_lua_check.py tools/gen4_frontier_engine_check.lua <platinum cache dir> [pokeplatinum]
--
-- PLATINUM'S BATTLE FRONTIER SCENE ENGINE: the command table generated from
-- frscrcmd.h / frscrcmd.inc (src/import/Gen4FrontierCommands.lua), the
-- fr_script decode (src/import/Gen4FrontierScripts.lua, cache module
-- gen4_frontier_scripts), the lowering (src/script/Gen4FrontierVM.lua) --
-- every row it emits must be a command this engine has -- and the Battle
-- Hall's bookkeeping (src/script/Gen4BattleHall.lua).
--
-- Given a pokeplatinum checkout, every labelled block of the Hall's script
-- source is checked against its decoded twin, command by command.

package.path = './?.lua;./?/init.lua;' .. package.path
love = require('tests.love_stub')
package.loaded['src.core.Sound'] = { play = function() end }
require('src.core.GameVersion').set('platinum')
local PASS, FAIL = 0, 0
local function check(c, l) if c then PASS = PASS + 1 else FAIL = FAIL + 1; print('FAIL: ' .. l) end end
local dir = (arg and arg[1] or 'G:/Gen2Recomped/platinum/data/generated'):gsub('[/\\]$', '')
local pret = arg and arg[2]
local function load(n) local f = loadfile(dir .. '/' .. n .. '.lua') return f and f() end
local function src(p) local f = io.open(p, 'rb'); local s = f and f:read('*a'); if f then f:close() end return s or '' end

-- ------------------------------------------------------- the command table --
local C = require('src.import.Gen4FrontierCommands')
local n = 0
for _ in pairs(C.ops) do n = n + 1 end
check(n == 204, 'frscrcmd.h: 204 opcodes')
local function op(name) for i, d in pairs(C.ops) do if d[1] == name then return i, d end end end
local _, am = op('applymovement')
check(am and am[3][1] == 'u16' and am[3][2] == 'rel', 'ApplyMovement: an object and a relative list')
local _, sv = op('setvarfromvalue')
check(sv and #sv[3] == 2, "SetVar's operands follow its .if/.else (the generator carries them across)")
local _, bh = op('callbattlehallfunction')
check(bh and bh[3][1] == 'u8' and bh[3][4] == 'u16', 'CallBattleHallFunction: three bytes and a variable')
check(C.movements[0xFD13] == 'end_movement', 'END_MOVEMENT is 0xFD13 (a hex define)')
check(C.movements[39] == 'warp_in' and C.movements[35] == 'delay_8', 'and the movement codes by name')

-- ------------------------------------------------------------ the decode --
local store = load('gen4_frontier_scripts')
check(store and store.members, 'the cache has gen4_frontier_scripts (tools/gen4_frontier_scripts_extract.lua)')
local count = 0
for _ in pairs(store and store.members or {}) do count = count + 1 end
check(count == 11, 'fr_script.narc: eleven members')
for _, m in ipairs({ 0, 1, 2, 3, 6, 7, 8, 9, 10 }) do
  local x = store.members[m]
  check(x and #x.unknown == 0, ('member %d decodes with no unknown opcode'):format(m))
end
local hall = store.members[3]
check(hall.entries[1] == 0x326, 'the Hall starts at _0326')
local entry = hall.blocks['F3/0326']
local names = {}
for i, ins in ipairs(entry.instructions) do names[i] = ins.name end
check(table.concat(names, ' '):find('getsystemvar getsystemvar getsystemvar getsystemvar getplayerobjeventgfx '
  .. 'setvarfromvalue initnewbattlerecording initbattlehall callbattlehallfunction comparevartovalue gotoif', 1, true),
  '_0326 decodes as the source reads')
local objs = hall.data['F3/0038']
check(objs and objs.kind == '24' and #objs.rows == 3 and objs.rows[1].gfx == 0xEEEE and objs.rows[2].gfx == 0x800F,
  "_0038's objects: the camera's 0xEEEE, the attendant (0x800F), the player (0x800A)")
local nm = 0
for _, mv in pairs(hall.movements) do if #mv > 0 and #mv < 40 then nm = nm + 1 end end
check(nm > 20, "the Hall's movement lists end where END_MOVEMENT is")

if pret then
  local s = src(pret .. '/res/field/frontier_scripts/frontier_scripts_battle_hall.s')
  if s == '' then
    local h = io.popen('git -C "' .. pret .. '" show HEAD:res/field/frontier_scripts/frontier_scripts_battle_hall.s')
    s = h:read('*a'); h:close()
  end
  -- the source's commands, block by block, as lowercase names
  local MAC = { FadeScreenOut = { 'fadescreen', 'waitfadescreen' },   -- wrappers
                FadeScreenIn = { 'fadescreen', 'waitfadescreen' } }
  for _, d in pairs(C.ops) do MAC[d[2]] = d[1] end
  local checked, wrong = 0, {}
  for label, body in s:gmatch('\n(_%x%x%x%x):\n(.-)\n\n') do
    local blk = hall.blocks[('F3/%s'):format(label:sub(2):upper())]
    if blk then
      local want = {}
      for line in body:gmatch('[^\n]+') do
        local mac = line:match('^%s+([%w_]+)')
        if mac and not line:find('^%s+%.') then
          if mac:find('^GoToIf') or mac:find('^CallIf') then
            want[#want + 1] = 'comparevartovalue'
            want[#want + 1] = mac:find('^GoTo') and 'gotoif' or 'callif'
          elseif type(MAC[mac]) == 'table' then
            for _, w in ipairs(MAC[mac]) do want[#want + 1] = w end
          else
            want[#want + 1] = MAC[mac] or mac:lower()
          end
        end
      end
      local got = {}
      for _, ins in ipairs(blk.instructions) do if not ins.implicit then got[#got + 1] = ins.name end end
      checked = checked + 1
      for i = 1, math.min(#want, #got) do
        if want[i] ~= got[i] and not (want[i] == 'comparevartovalue' and got[i] == 'comparevartovar')
           and not (want[i] == 'setvarfromvalue' and got[i] == 'setvarfromvar') then
          wrong[#wrong + 1] = label .. ':' .. i .. ' ' .. tostring(want[i]) .. '/' .. tostring(got[i])
          break
        end
      end
    end
  end
  check(checked > 50 and #wrong == 0, ('%d Hall blocks match the source (%s)'):format(checked,
    table.concat(wrong, ', '):sub(1, 300)))
end

-- -------------------------------------------------------------- lowering --
local Commands = require('src.script.Commands')
require('src.script.Gen4Commands')
require('src.script.Gen4FrontierScrCmds')
local H = require('src.script.Gen4BattleHall')
local VM = require('src.script.Gen4FrontierVM')
local data = { gen4_frontier_scripts = store }
local rows = VM.compile(data, 3, 'F3/0326', 549)
check(rows and #rows > 500, 'the Hall compiles from its entry point')
local missing, noop = {}, {}
for _, row in ipairs(rows or {}) do
  local name = row[1]
  if name ~= 'label' and name ~= 'jump' and type(Commands[name]) ~= 'function' then missing[name] = true end
  if name == 'g4_noop' and tostring(row[2]):find('^frontier ') then noop[row[2]] = true end
end
local ml, nl = {}, {}
for k in pairs(missing) do ml[#ml + 1] = k end
for k in pairs(noop) do nl[#nl + 1] = k end
check(#ml == 0, 'every row the Hall lowers to is a command (' .. table.concat(ml, ' ') .. ')')
check(#nl == 0, 'no Hall command falls through unlowered (' .. table.concat(nl, ' ') .. ')')

-- ------------------------------------------------------ the Hall's books --
local save = { party = { { species = 445, item = 'LEFTOVERS' } }, player = {} }
H.setRank(save, 0, 4, 7)
H.setRank(save, 0, 5, 3)
check(H.rank(save, 0, 4) == 7 and H.rank(save, 0, 5) == 3 and H.record(save).ranks[0][2] == 3 * 16 + 7,
  'BattleHall_SaveTypeRank: two types to a byte, the odd one high')
check(H.FN_NAMES[30] == 'IS_MULTIPLAYER_CHALLENGE' and H.FN_NAMES[15] == 'GET_PLAYERS_MONS_SPECIES',
  'BH_FUNC_* in the header\'s order')
local h = H.init(save, 0, H.SINGLE, 0, 1)
check(h.streak == 0 and h.ranks[4] == 0, 'a fresh challenge with no live streak zeroes the ranks')
h.round, h.streak = 3, 35
check(H.earnedBP(h) == 1, 'round 3 single: 1 BP')
h.streak = 50
check(H.earnedBP(h) == 20, 'the 50th (Argenta, silver): 20 BP')
check(src('src/import/Gen4Graphics.lua'):find('if not map.linear and', 1, true),
  'an extended affine BG composes linearly (the Hall battle room)')

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
