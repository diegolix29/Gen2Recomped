-- Run:  python tools/run_lua_check.py tools/gen5_trades_check.lua [black .nds] [white .nds]
--
-- BLACK AND WHITE'S IN-GAME TRADES (src/import/Gen5Trades.lua), decoded from
-- the cartridge and held against a reference that was not read off it: the
-- seven trades as PKHeX's EncounterTrade5 table (Encounters5BW.cs) lists them
-- -- species, level, form, OT id and gender, the Pokemon's gender, IVs,
-- nature, ability slot and THE FIXED PID (checked against kwsch/PKHeX master,
-- Encounters5BW.cs, 2026-10-17) -- plus the names Bulbapedia gives.
-- The PID is the strongest check: the importer computes it from the OT id,
-- the record's gender and the species' gender ratio (read here from the
-- personal archive, not the cache) with 0x0201862C's rule, and PKHeX's
-- numbers come from captured Pokemon.
--
-- Then the SCRIPTS, relinked with Gen5ScriptLink: every 0x1BF / 0x1BE / 0x120
-- lowers, the five houses pass the record ids the table says they should, and
-- the version branch in Nacrene and Driftveil sends Black (0x0E0 == 21) to
-- the first and White to the second.

package.path = './?.lua;./?/init.lua;' .. package.path
love = require('tests.love_stub')
local PASS, FAIL = 0, 0
local function check(c, l) if c then PASS = PASS + 1 else FAIL = FAIL + 1; print('FAIL: ' .. l) end end
local roms = {
  black = arg and arg[1] or './Pokemon - Black Version (USA, Europe) (NDSi Enhanced).nds',
  white = arg and arg[2] or './Pokemon - White Version (USA, Europe) (NDSi Enhanced).nds',
}

local Narc = require('src.import.NarcArchive')
local Text = require('src.import.Gen5Text')
local T = require('src.import.Gen5Trades')

-- PKHeX Encounters5BW.cs TradeGift_BW (ivs HP/Atk/Def/Spe/SpA/SpD as stored),
-- names from Bulbapedia's "In-game trade" lists
local REF = {
  [0] = { species = 548, level = 15, otId = 39922, otGender = 'girl', gender = 1, nature = 15, ability = 0, form = 0,
          ivs = { 20, 20, 20, 20, 31, 20 }, pid = 0x64000000, request = 546, nick = 'Lillil', ot = 'Dye' },
  [1] = { species = 546, level = 15, otId = 39922, otGender = 'girl', gender = 1, nature = 15, ability = 0, form = 0,
          ivs = { 20, 20, 20, 20, 31, 20 }, pid = 0x6400007E, request = 548, nick = 'Fluffee', ot = 'Dye' },
  [2] = { species = 550, level = 25, otId = 27646, otGender = 'boy', gender = 0, nature = 3, ability = 0, form = 0,
          ivs = { 20, 31, 20, 20, 20, 20 }, pid = 0x9400007F, request = 572, nick = 'Redeye', ot = 'Kyle' },
  [3] = { species = 550, level = 25, otId = 27646, otGender = 'boy', gender = 0, nature = 3, ability = 0, form = 1,
          ivs = { 20, 31, 20, 20, 20, 20 }, pid = 0x9400007F, request = 572, nick = 'Blueeye', ot = 'Kyle' },
  [4] = { species = 587, level = 30, otId = 11195, otGender = 'boy', gender = 0, nature = 9, ability = 0, form = 0,
          ivs = { 20, 20, 31, 20, 20, 20 }, pid = 0xD400007F, request = 525, nick = 'Minipete', ot = 'Manny' },
  [5] = { species = 446, level = 60, otId = 40217, otGender = 'boy', gender = 0, nature = 12, ability = 1, form = 0,
          ivs = { 31, 20, 20, 20, 20, 20 }, pid = 0x6200001F, request = 573, nick = 'Gorge', ot = 'Ander' },
  [6] = { species = 479, level = 60, otId = 54673, otGender = 'girl', gender = 2, nature = 21, ability = 0, form = 0,
          ivs = { 20, 20, 20, 20, 20, 31 }, pid = 0x2A000000, request = 132, nick = 'Eeks', ot = 'Lillian' },
}

local tables = {}
for _, version in ipairs({ 'black', 'white' }) do
  local rom = require('src.import.NdsRom').open(roms[version])
  check(rom ~= nil, version .. ': the cartridge opens')
  if rom then
    local system = Narc.parse(rom:read('/a/0/0/2'))
    local banks = {}
    local x = { rom = rom }
    function x:string(bank, i)
      banks[bank] = banks[bank] or Text.bank(system:get(bank)) or false
      return banks[bank] and banks[bank][i]
    end
    local rows = T.build(x)
    tables[version] = rows
    check(rows and #rows == 13, version .. ': 13 records of 108 bytes')
    local personal = Narc.parse(rom:read('/a/0/1/6'))
    local items = Text.bank(system:get(54)) or {}
    for id = 0, 6 do
      local r, e = rows and rows[id + 1], REF[id]
      local tag = ('%s #%d'):format(version, id)
      check(r ~= nil, tag .. ' present')
      if r then
        for _, k in ipairs({ 'species', 'level', 'otId', 'otGender', 'gender', 'nature', 'form' }) do
          check(r[k] == e[k], ('%s %s %s, expected %s'):format(tag, k, tostring(r[k]), tostring(e[k])))
        end
        check(r.abilitySlot == e.ability, tag .. ' ability slot')
        check(r.request == e.request, tag .. ' requested species')
        check(r.requestGender == 2, tag .. ' either gender accepted')
        for i = 1, 6 do check(r.ivs[i] == e.ivs[i], ('%s IV %d'):format(tag, i)) end
        check(r.nickname == e.nick, ('%s nickname %s, expected %s'):format(tag, tostring(r.nickname), e.nick))
        check(r.otName == e.ot, ('%s OT %s, expected %s'):format(tag, tostring(r.otName), e.ot))
        check(r.language == 2, tag .. ' language English')
        local p = personal:get(r.species)
        local ratio = p and p:byte(0x12 + 1)
        local pid = T.pid(r.otId, ratio, r.gender)
        check(pid == e.pid, ('%s PID %08X, expected %08X'):format(tag, pid, e.pid))
        print(('%s  %-7s %3d %-9s Lv%-2d for %3d  nick %-8s OT %-7s (%s) id %5d  nature %2d  ability %d  item %3d %s  PID %08X')
          :format(version, '#' .. id, r.species, tostring(r.form ~= 0 and ('form ' .. r.form) or ''), r.level, r.request,
            r.nickname, r.otName, r.otGender, r.otId, r.nature, r.abilitySlot, r.item, tostring(items[r.item]), pid))
      end
    end
    for id = 7, 12 do
      local r = rows and rows[id + 1]
      check(r and r.unused, ('%s #%d is an unnamed placeholder'):format(version, id))
    end
    -- the scripts
    local Ops = require('src.import.Gen5ScriptOps')
    local Link = require('src.import.Gen5ScriptLink')
    local Script = require('src.import.Gen4Script')
    local arc = Narc.parse(rom:read('/a/0/5/7'))
    local derived = Ops.derive(rom, arc)
    local function decodeMember(m)
      local d = arc:get(m)
      local all, queue, seen = {}, {}, {}
      for _, at in ipairs(Script.entries(d)) do queue[#queue + 1] = at end
      local i = 1
      while i <= #queue do
        local at = queue[i]; i = i + 1
        if not seen[at] then
          seen[at] = true
          local decoded = Ops.decode(d, at, derived.widths)
          local list = Link.rewriteCompound(Link.rewritePushPop(Link.rewriteStack(decoded)))
          for _, ins in ipairs(list) do
            if ins.target and ins.target >= 1 and ins.target <= #d then queue[#queue + 1] = ins.target end
            all[#all + 1] = ins
          end
        end
      end
      table.sort(all, function(a, b) return a.at < b.at end)
      return all
    end
    local WANT = { [46] = { 0, 1 }, [202] = { 2, 3 }, [686] = { 4 }, [830] = { 5 }, [764] = { 6 } }
    for m, want in pairs(WANT) do
      local list = decodeMember(m)
      local ids, sets, raw = {}, {}, 0
      for _, ins in ipairs(list) do
        if ins.op == 0x1BE or ins.op == 0x1BF or ins.op == 0x120 then
          if ins.name:match('^bw_') then raw = raw + 1 end
        end
        if ins.name == 'setvarfromvalue' and ins.args[1] == 0x8020 then sets[#sets + 1] = ins.args[2] end
        if ins.name == 'bwnpctrade' then
          local t = ins.args[1]
          if t >= 0x4000 then for _, v in ipairs(sets) do if v == 0 or v == 1 then ids[v] = true end end
          else ids[t] = true end
        end
      end
      check(raw == 0, ('%s member %d: every trade command lowers (%d raw)'):format(version, m, raw))
      for _, v in ipairs(want) do check(ids[v], ('%s member %d passes trade %d'):format(version, m, v)) end
      -- the version branch: the first record assigned after 0x0E0 is Black's
      if #want == 2 then
        -- (the last 0x0E0 whose following run assigns a record: the
        -- instructions up to the next 0x0E0, in address order)
        local first, block
        for _, ins in ipairs(list) do
          if ins.name == 'bwgetversion' then block = { open = true } end
          if block and block.open and block.first == nil then
            if ins.name == 'setvarfromvalue' and ins.args[1] == 0x8020 then block.first = ins.args[2] end
            if ins.name == 'bwnpctradecheck' and ins.args[2] < 0x4000 then block.first = ins.args[2] end
            if block.first ~= nil then first = block.first end
          end
        end
        check(first == want[1], ('%s member %d: the version-21 path takes trade %s'):format(version, m, tostring(first)))
      end
    end
    rom:close()
  end
end
-- the two versions ship the same table
if tables.black and tables.white then
  local same = true
  for i = 1, 13 do
    for k, v in pairs(tables.black[i] or {}) do
      if type(v) ~= 'table' and tables.white[i][k] ~= v then same = false end
    end
  end
  check(same, 'Black and White carry the same trade table')
end
print(('gen5 trades: %d passed, %d failed'):format(PASS, FAIL))
