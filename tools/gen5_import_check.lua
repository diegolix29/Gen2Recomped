-- Run:  python tools/run_lua_check.py tools/gen5_import_check.lua <black .nds> [white .nds]
--
-- BLACK AND WHITE THROUGH src/import/RomExtractorGen5.lua, against values
-- that are not in question: the record layouts in src/import/Gen5Data.lua are
-- the community's (pokeblack has not decompiled the readers yet), so this is
-- where a wrong offset gets caught -- Bulbasaur's stats, types and abilities,
-- Snivy's evolution, Pound and Tackle, the Master Ball and a Potion, the
-- Striaton triplets' teams, and the text decryption (both the plain and the
-- 9-bit compressed strings). Writes are captured, not cached.

package.path = './?.lua;./?/init.lua;' .. package.path
love = require('tests.love_stub')
local PASS, FAIL = 0, 0
local function check(c, l) if c then PASS = PASS + 1 else FAIL = FAIL + 1; print('FAIL: ' .. l) end end
local black = arg and arg[1] or './Pokemon - Black Version (USA, Europe) (NDSi Enhanced).nds'
local white = arg and arg[2] or './Pokemon - White Version (USA, Europe) (NDSi Enhanced).nds'

local LuaWriter = require('src.import.LuaWriter')
local captured
LuaWriter.write = function(path, value) captured[path:match('([^/]+)%.lua$')] = value end
-- nothing reaches the disk: the field stage writes binaries and PNGs
require('src.import.CacheFs').write = function() return true end
local IW = require('src.import.ImageWriter')
IW.save = function() return true end
IW.fromRGBA8 = function(w, h) return { width = w, height = h } end
local X = require('src.import.RomExtractorGen5')

local function extract(path, version)
  captured = {}
  local x, err = X.new(path, version)
  if not x then print('cannot open ' .. tostring(path) .. ': ' .. tostring(err)) return nil end
  local ok, e = pcall(x.run, x)
  if not ok then print('extract failed: ' .. tostring(e)) end
  x:close()
  if ok then captured._x = x end
  return ok and captured or nil
end

local b = extract(black, 'black')
check(b ~= nil, 'Black: the stages run')
if b then
  local mons = b.pokemon or {}
  local bulba = mons[1] or {}
  local s = bulba.baseStats or {}
  check(bulba.name == 'Bulbasaur' and s.hp == 45 and s.attack == 49 and s.defense == 49 and s.speed == 45
    and s.spatk == 65 and s.spdef == 65, 'Bulbasaur: 45/49/49/45/65/65')
  check(bulba.types and bulba.types[1] == 'GRASS' and bulba.types[2] == 'POISON', '...Grass/Poison')
  check(bulba.abilityIds and bulba.abilityIds[1] == 65 and bulba.abilityIds[3] == 34, '...Overgrow (65), hidden Chlorophyll (34)')
  check(bulba.catchRate == 45 and bulba.growthRate == 'MEDIUM_SLOW' and bulba.genderRatio == 31, '...catch rate 45, medium slow, 7:1')
  local snivy = mons[495] or {}
  check(snivy.name == 'Snivy' and snivy.evolutions and snivy.evolutions[1] and snivy.evolutions[1].species == 496
    and snivy.evolutions[1].param == 17, 'Snivy evolves into Servine (496) at 17')
  check(snivy.learnset and snivy.learnset[1] and snivy.learnset[1].move == 33, "Snivy's first move is Tackle (33)")
  check(mons[649] and mons[649].name == 'Genesect', 'all 649, Genesect last')
  local moves = b.moves or {}
  local pound = moves[1] or {}
  check(pound.name == 'Pound' and pound.type == 'NORMAL' and pound.class == 'physical' and pound.power == 40
    and pound.accuracy == 100 and pound.pp == 35, 'Pound: Normal, physical, 40, 100, 35 PP')
  local qa = moves[98] or {}
  check(qa.name == 'Quick Attack' and qa.priority == 1, 'Quick Attack: priority +1')
  check(moves[557] and moves[557].name == 'V-create' and moves[559] and moves[559].name == 'Fusion Bolt',
    'V-create (557) to Fusion Bolt (559)')
  local items = b.items or {}
  check(items[1] and items[1].name == 'Master Ball' and items[1].price == 0, 'the Master Ball, price 0')
  check(items[17] and items[17].name == 'Potion' and items[17].price == 300 and items[2].price == 1200,
    'prices stored in tens: a Potion 300, an Ultra Ball 1200')
  check(items[1].bwPocket == 0 and items[17].bwPocket == 1 and items[328] and items[328].bwPocket == 2
      and items[149] and items[149].bwPocket == 3 and items[621] and items[621].bwPocket == 4,
    'pockets (bits 7..10 at 0x08): Master Ball 0, Potion 1, TM01 2, Cheri 3, Xtransceiver 4')
  local trainers = b.trainers or {}
  local leaders = {}
  for _, t in pairs(trainers) do
    if t.className == 'Leader' and (t.name == 'Cilan' or t.name == 'Chili' or t.name == 'Cress') then leaders[#leaders + 1] = t end
  end
  local okLeaders = #leaders >= 3
  for _, t in ipairs(leaders) do
    local p = t.party or {}
    if #p ~= 2 or (p[1].species ~= 506 and p[1].species ~= 510) then okLeaders = false end
  end
  check(okLeaders, 'the Striaton triplets: Leaders, each opening with Lillipup (506) or Purrloin (510)')
  local names = b.gen5_text and b.gen5_text.system and b.gen5_text.system[190]
  check(names and names[1] == 'Jimmy', 'the compressed trainer names decode (bank 190)')
  check(b.text and b.text['TEXT_G5S_0070_00001'] == 'Bulbasaur', 'the flat label TEXT_G5S_0070_00001')
  -- THE FIELD (Gen5Maps / Gen5Field), drawn by the Gen 4 renderer
  local zones = b.gen5_zones or {}
  local nz = 0 for _ in pairs(zones) do nz = nz + 1 end
  check(nz == 427 and zones[6] and zones[6].matrix == 0 and zones[317] and zones[317].encounters == 77,
    '427 zones: Striaton (6) and Route 1 (317) on matrix 0, Route 1 on encounter table 77')
  local terrain = b.gen4_terrain or {}
  local nc, nr = 0, 0
  for _ in pairs(terrain.chunks or {}) do nc = nc + 1 end
  for _ in pairs(terrain.refused or {}) do nr = nr + 1 end
  check(nc == 649 and nr == 0, 'all 649 map chunks (WB, GC, NG, RD) pack through the Gen 4 model pipeline')
  local grid = terrain.matrices and terrain.matrices[0]
  check(grid and grid.width == 29 and grid.height == 27, "matrix 0 is Unova's 29 x 27 overworld")
  local striaton = b.maps and b.maps.Z006
  local st = terrain.maps and terrain.maps.Z006
  local stSet = st and terrain.sets[st.texture]
  check(striaton and striaton.label == 'Striaton City' and striaton.width == 96 and st
    and (st.texture == 6 or (stSet and stSet.merged and stSet.merged[1] == 6)),
    "Striaton City: 96 tiles wide, wearing texture set 6 (its area) first")
  -- buildings: the area's pack (Gen5Field.packFor), models by building id
  local fr = b._x and b._x.fieldReport or {}
  local F5 = require('src.import.Gen5Field')
  local k6, p6 = F5.packFor(6)
  local k217, p217 = F5.packFor(217)
  check(k6 == 'outdoor' and p6 == 1 and k217 == 'indoor' and p217 == 7,
    'building packs: Striaton (area 6) outdoor pack 1, area 217 indoor pack 7')
  check((fr.buildingModels or 0) > 4000 and (fr.placementsFound or 0) > 3900
    and (fr.placementsFound or 0) / ((fr.placementsFound or 0) + (fr.placementsMissing or 1)) > 0.85,
    ('%s building models; %s of %s placements resolve in their pack'):format(tostring(fr.buildingModels),
      tostring(fr.placementsFound), tostring((fr.placementsFound or 0) + (fr.placementsMissing or 0))))
  local s6 = b.gen4_models and b.gen4_models.sets and b.gen4_models.sets.bwOutdoor
  local striatonPack = s6 and s6.packs and s6.packs[1]
  check(striatonPack and striatonPack.models[0 + 1] and striatonPack.models[152 + 1],
    "Striaton's placed ids 0 and 152 are models in outdoor pack 1")
  -- a map whose box takes in a neighbour's chunks wears both sets
  local r1t = terrain.maps and terrain.maps.Z317
  check(r1t and terrain.sets[r1t.texture] and terrain.sets[r1t.texture].merged
    and terrain.sets[r1t.texture].merged[1] == 2,
    "Route 1 wears a merged set, its own (2) first")
  -- events and people (Gen5Events, Gen5Overworld)
  local st6 = b.maps and b.maps.Z006
  local realWarps = 0
  for _, w in ipairs(st6 and st6.warps or {}) do if not w.extentOf then realWarps = realWarps + 1 end end
  check(st6 and #st6.objects == 15 and realWarps == 7 and #st6.signs == 7 and #st6.coordEvents == 2,
    "Striaton's events: 15 NPCs, 7 warps, 7 signs, 2 triggers")
  check(st6 and st6.objects[1].x == 772 - st6.originX and st6.warps[1].destMap == 'Z008',
    'NPC positions taken back to the map; the first door leads to zone 8')
  check((fr.npcsWithSprite or 0) / math.max(fr.npcs or 1, 1) > 0.95 and (fr.sprites or 0) > 700,
    ('%s sprite sheets from /a/0/4/9; %s of %s NPCs have one'):format(tostring(fr.sprites),
      tostring(fr.npcsWithSprite), tostring(fr.npcs)))
  -- a new game starts in the player's room (zone 391's header spot), the
  -- first blackout point the floor below
  local boot = b.field and b.field.boot
  local z391 = (b.gen5_zones or {})[391] or {}
  check(boot and boot.startMap == 'Z391' and boot.startX == 5 and boot.startY == 6 and z391.spawnX == 5
    and boot.lastHeal and boot.lastHeal.map == 'Z390' and boot.screens and boot.screens.newGame == 'Gen5JuniperIntro',
    ('new game: %s (%s,%s), first blackout %s'):format(tostring(boot and boot.startMap), tostring(boot and boot.startX),
      tostring(boot and boot.startY), tostring(boot and boot.lastHeal and boot.lastHeal.map)))
  local forms=b.field and b.field.playerForms
  check(forms and forms.girl and forms.girl.walk=='SPRITE_G4_009' and forms.boy.walk=='SPRITE_G4_006'
    and forms.girl.bike=='SPRITE_G4_010' and forms.boy.bike=='SPRITE_G4_007'
    and forms.girl.surf=='SPRITE_G4_011' and forms.boy.surf=='SPRITE_G4_008',
    'native male/female walking, bicycle (rows 2/5) and surf (rows 3/6) forms')
  -- the field effects (/a/0/7/5, Gen5FieldEffects): the "!" is member 50
  -- (ov21 0x21D9A6C), the phenomena / lure pictures and the surf mount model
  local em, fe = b.gen4_emotes, b.gen5_field_effects
  check(em and em.exclamation and em.exclamation.member == 50 and em.question and em.question.member == 51
    and em.exclamation.width == 16 and #em.exclamation.rgba == 1024,
    ('field effects: "!" member %s'):format(tostring(em and em.exclamation and em.exclamation.member)))
  check(fe and fe.textures and fe.textures['94/mv_kusa.1'] == nil and fe.textures['84/fishing_lure.1']
    and fe.textures['60/ee_kusa_sp'] and fe.anims and fe.anims[115] and fe.anims[115].frames == 81
    and fe.anims[134] and fe.anims[134].frames == 45,
    'field effects: lure, shaking grass and ripple pictures with their animation tracks')
  local fset = b.gen4_models and b.gen4_models.sets and b.gen4_models.sets.fldeff
  check(fset and fset.byMember and fset.byMember[49], 'field effects: the sea_ride surf mount (member 49) in the fldeff set')
  -- the zones' field permissions (+0x1E): the bike bit 0x0400 (ARM9 0x2013C20)
  local zm = b.maps or {}
  local U = require('src.inventory.Gen5ItemUse')
  check(zm.Z391 and zm.Z391.gen5Flags == 0x4921 and zm.Z006 and zm.Z006.gen5Flags == 0xEC40
    and not U.allowBike(zm.Z391) and U.allowBike(zm.Z006),
    ('zone flags: Z391 %s, Z006 %s'):format(tostring(zm.Z391 and zm.Z391.gen5Flags), tostring(zm.Z006 and zm.Z006.gen5Flags)))
  check(b.gen5_juniper_art and b.gen5_juniper_art.text[6]:find('Welcome to the world',1,true),
    'Juniper art and message bank are written with the import')
  -- BW's own keyboard (overlay 194): /a/1/1/9's pages and /a/1/1/8's boards
  local nm = b.gen5_naming_art
  check(nm and nm.pages and nm.pages[1].rows[1][1] == 'A' and nm.pages[2].rows[3][12] == '\u{2642}'
    and nm.qwerty and nm.qwerty.upper.rows[1][1] == 'Q' and nm.qwerty.lower.rows[3][8] == '-'
    and nm.keys_dark and nm.qwerty_lit and nm.obj_cursor_l_0 and nm.text and nm.text[0] == 'Your name?',
    'naming keyboard: BW pages, qwerty rows, boards and bank 81')
  -- placements' z is stored negated: Nuvema's living room (zone 390, land
  -- 504) has its floor at z -250..-72 and its 16 pieces inside it
  local liv = ((b.gen4_terrain or {}).chunks or {})[504]
  local inside = liv and #liv.objects == 16
  for _, o in ipairs((liv and liv.objects) or {}) do if not (o.z <= -72 and o.z >= -250) then inside = false end end
  check(inside, "Nuvema's living-room furniture stands on its own floor (placement z negated)")
  local cheren = b.sprites and b.sprites.SPRITE_G4_012
  check(cheren ~= nil, "Cheren's sheet (member 12) is written, colour 0 clear like every character's")
  local hero = b.field and b.field.playerSprites and b.sprites and b.sprites[b.field.playerSprites.walk]
  check(hero and hero.frames == 32 and hero.facings and hero.facings.down[1] == 3,
    "the player (sprite id 1): 32 frames, three a direction, down from frame 3")
  -- scripts: widths from the cartridge's own handlers (Gen5ScriptOps)
  local sc = b.gen5_scripts or {}
  local w = sc.widths or {}
  check(sc.offset == 15 and w[0x02] == 0 and w[0x05] == 0 and w[0x04] == 4 and w[0x1E] == 4 and w[0x1F] == 5,
    'script commands: End/Return 0, Call/Jump a u32, If a u8 + u32 (table slot = opcode + 15)')
  check(w[0x3D] == 8 and w[0xA6] == 2 and w[0x2E] == 0 and w[0x74] == 0,
    "...and a Striaton conversation's own: message 8 bytes, sound 2, lock and face-player none")
  local rep = sc.report or {}
  check((rep.clean or 0) / math.max(rep.entries or 1, 1) > 0.95 and (rep.secondBestOffset or 1e9) < (rep.clean or 0) / 2,
    ('%s of %s script entries decode to an end; the alignment is unambiguous'):format(tostring(rep.clean), tostring(rep.entries)))
  check(sc.widths and sc.widths[0x38] == 3 and sc.widths[0x2E] == 0 and (rep.clean or 0) >= 3340,
    ('tail-jump stubs followed: 0x38 is 3 bytes, lockall still 0; %s clean entries'):format(tostring(rep.clean)))
  check(sc.widths and sc.widths[0xB2] == 7,
    ('the menu opener 0xB2 is 7 bytes (a reader-shaped handler whose two calls also read) -- got %s')
      :format(tostring(sc.widths and sc.widths[0xB2])))
  -- the script pool the Gen 4 engine runs (Gen5ScriptLink)
  local lr = b._x and b._x.linkReport or {}
  local ms = b.map_scripts or {}
  local label = ms.maps and ms.maps.Z006 and ms.maps.Z006.objects and ms.maps.Z006.objects[1]
  local talk = label and ms.scripts[label]
  local names = {}
  for _, ins in ipairs(talk and talk.instructions or {}) do names[#names + 1] = ins.name end
  local joined = table.concat(names, ',')
  check(joined:find('lockall,playse,faceplayer,message', 1, true) and joined:find('waitabpress,closemessage', 1, true)
    and talk.instructions[4].args[1] == 9,
    "Striaton's first NPC: lock, sound, face, message 9, wait, close ... (" .. joined:sub(1, 80) .. ")")
  check((lr.linked or 0) > 1400 and (lr.named or 0) / math.max(lr.instructions or 1, 1) > 0.5,
    ('%s NPCs and signs linked; %s of %s instructions named'):format(tostring(lr.linked), tostring(lr.named), tostring(lr.instructions)))
  check(b.text and b.text['TEXT_B' .. ('%04d'):format(zones[6].messages) .. '_00009'], "the story line answers to the Gen 4 label")
  -- BW's stack conditionals, rewritten into Platinum's compare + gotoif
  local Link = require('src.import.Gen5ScriptLink')
  local function mk(op, hex) local s = '' for byte in hex:gmatch('%x%x') do s = s .. string.char(tonumber(byte, 16)) end return { op = op, operands = s, at = 1, width = #s } end
  local flagIsClear = Link.rewriteStack({ mk(0x10, '4e01'), mk(0x08, '0000'), mk(0x11, '0100'), mk(0x1F, 'ff10000000') })
  local varAtLeast = Link.rewriteStack({ mk(0x09, '2180'), mk(0x08, '1027'), mk(0x11, '0400'), mk(0x1F, 'ff9d000000') })
  local Cmd = require('src.script.Gen4Commands')
  local function jumps(cond, result) return Cmd.holds({ g4Compare = result }, cond) end
  check(flagIsClear[1].name == 'checkflag' and flagIsClear[1].args[1] == 0x14E and flagIsClear[2].name == 'gotoif'
    and jumps(flagIsClear[2].args[1], 1) and not jumps(flagIsClear[2].args[1], 0),
    'push flag 0x14E, push 0, ==, 0x1F 0xFF (jump if false): jumps when the flag is set, not when clear')
  check(varAtLeast[1].name == 'comparevartovalue' and varAtLeast[1].args[1] == 0x8021 and varAtLeast[1].args[2] == 10000
    and varAtLeast[2].args[1] == 0,
    'push var 0x8021, push 10000, >=, jump if false: compare the var and jump on <')
  local lr2 = b._x and b._x.linkReport or {}
  check((lr2.named or 0) / math.max(lr2.instructions or 1, 1) > 0.7,
    ('%s of %s script instructions named once the conditionals are lowered'):format(tostring(lr2.named), tostring(lr2.instructions)))
  -- scripted movement: 0x64's lists are Gen 4's, decoded into the instruction
  local moved, playerMoves = 0, 0
  for _, sc2 in pairs(ms.scripts or {}) do
    for _, ins in ipairs(sc2.instructions) do
      if ins.name == 'applymovement' and ins.movement and #ins.movement > 0 then
        moved = moved + 1
        if ins.args[1] == 0xFF then playerMoves = playerMoves + 1 end
      end
    end
  end
  check((lr2.movements or 0) > 3000 and moved > 3000 and playerMoves > 500,
    ('%s movement lists decoded (%d reached, %d move the player)'):format(tostring(lr2.movements), moved, playerMoves))
  -- the script id table and the shared files it names
  local rows = b.gen5_version and b.gen5_version.scriptBands or {}
  local common
  for _, row in ipairs(rows) do if row[1] == 2000 then common = row end end
  check(#rows == 46 and common and common[3] == 854 and common[4] == 158,
    ('the script id table: %d bands, 2000 -> member 854, text bank 158'):format(#rows))
  local cb = ms.bands and ms.bands.common_scripts
  check(cb and cb.member == 854 and #cb.entries >= 5 and ms.scripts[cb.entries[1]], 'the common scripts (member 854) are in the pool by entry')
  -- a shared file's `end` returns to its caller (0x1C runs it in a context
  -- of its own): the give-item script's closing `end`, member 862
  local gi = ms.scripts['M0862/S0130']
  local last = gi and gi.instructions[#gi.instructions]
  check(last and last.name == 'return', "a shared file's end is a return (give-item, member 862: " .. tostring(last and last.name) .. ')')
  -- a common-script call: save 0x8000/0x8001, set them, call, restore
  local Link2 = require('src.import.Gen5ScriptLink')
  local saved = Link2.rewritePushPop(Link2.rewriteStack({ mk(0x09, '0080'), mk(0x09, '0180'), mk(0x2A, '00800c00'),
    mk(0x1C, '7e27'), mk(0x0A, '0180'), mk(0x0A, '0080') }))
  local seq = {} for _, ins in ipairs(saved) do seq[#seq + 1] = ins.name end
  check(table.concat(seq, ',') == 'setvarfromvar,setvarfromvar,setvarfromvalue,callcommonscript,setvarfromvar,setvarfromvar'
    and saved[1].args[1] == 0x8100 and saved[2].args[1] == 0x8101 and saved[5].args[1] == 0x8001 and saved[5].args[2] == 0x8101
    and saved[6].args[2] == 0x8100 and saved[4].args[1] == 0x277E,
    'push/pop around a common-script call become copies into slot vars and back (' .. table.concat(seq, ',') .. ')')
  -- a compound condition: var 0x408A == 3 AND flag 0x80 == 0
  local both = Link2.rewriteStack({ mk(0x09, '8a40'), mk(0x08, '0300'), mk(0x11, '0100'), mk(0x10, '8000'),
    mk(0x08, '0000'), mk(0x11, '0100'), mk(0x11, '0700'), (function() local j = mk(0x1F, 'ff1c000000'); j.target = 99; return j end)() })
  check(#both == 4 and both[1].name == 'comparevartovalue' and both[2].args[1] == 5 and both[2].target == 99 and both[4].target == 99 and both[3].name == 'checkflag'
    and jumps(both[4].args[1], 1) and not jumps(both[4].args[1], 0),
    'NOT (var == 3 AND flag clear): jump when the var is not 3, or when the flag is set')
  -- yes/no: 0x47 is Platinum's showyesnomenu, YES = 0 in both
  local yn = Link2.name(mk(0x47, '1080'))
  check(yn.name == 'showyesnomenu' and yn.args[1] == 0x8010, '0x47 is the yes/no box into its var')
  -- the party menu and the Egg check expand into Platinum's rows
  local function mkw(op, hex, at) local i = mk(op, hex); i.at = at; return i end
  local party = Link2.rewriteCompound({ Link2.name(mkw(0x107, '228021800000', 11)), Link2.name(mkw(0x102, '20802180', 19)) })
  local pn = {} for _, ins in ipairs(party) do pn[#pn + 1] = ins.name end
  check(table.concat(pn, ',') == 'openpartymenufortrade,getselectedpartyslot,setvarfromvalue,comparevartovalue,gotoif,setvarfromvalue,'
      .. 'getpartymonspecies,setvarfromvalue,comparevartovalue,gotoif,setvarfromvalue'
    and party[2].args[1] == 0x8021 and party[3].args[1] == 0x8022 and party[5].target == 19 and party[7].args[1] == 0x8021
    and party[8].args[1] == 0x8020 and party[10].target == 25,
    'party menu (0x107) and Egg check (0x102): ' .. table.concat(pn, ','))
  -- after a trainer battle: 0x8D leaves 1 for a win (the bedroom battle's
  -- "awesome Trainer" line runs on var == 1), 0x8E returns to the field
  local res = Link2.rewriteCompound({ Link2.name(mk(0x8D, '1080')) })
  local G4b = require('src.script.Gen4Commands')
  local Cmdb = require('src.script.Commands')
  local function after(result)
    local save = { vars = {} }
    local ctx = { save = save, lastBattleResult = result }
    Cmdb.g4_check_won_battle(ctx, res[1].args[1])
    return G4b.getVar(save, 0x8010)
  end
  check(#res == 1 and res[1].name == 'checkwonbattle' and after('win') == 1 and after('lose') == 0
      and Link2.ALIASES[0x8E][1] == 'returntofield' and Link2.ALIASES[0x8C][1] == 'blackoutfrombattle',
    ('0x8D: 1 after a win, 0 after a loss (%s / %s)'):format(tostring(after('win')), tostring(after('lose'))))
  -- the gift box: 0x153 the starter app, 0x10C the gift, 0x057 the name
  local box = Link2.rewriteCompound({ Link2.name(mk(0x153, '2080')),
    Link2.name(mk(0x10C, '1080218000000500')), Link2.name(mk(0x057, '01ef01')) })
  check(box[1].name == 'bwchoosestarter' and box[1].args[1] == 0x8020
      and box[2].name == 'givepokemon' and box[2].args[1] == 0x8021 and box[2].args[2] == 5
      and box[2].args[4] == 0x8010 and box[3].name == 'bufferspeciesnamefromvar'
      and box[3].args[1] == 1 and box[3].args[2] == 495,
    'gift box: 0x153 starter app, 0x10C givepokemon, 0x057 species name')
  local bagOps = Link2.rewriteCompound({ Link2.name(mk(0xB5, '008001801080')), Link2.name(mk(0xB7, '008001801080')),
    Link2.name(mk(0xBB, '08801080')), Link2.name(mk(0x04E, '000880098000')), Link2.name(mk(0x052, '021080')) })
  check(bagOps[1].name == 'additem' and bagOps[1].args[3] == 0x8010 and bagOps[2].name == 'canfititem'
      and bagOps[3].name == 'getitempocket' and bagOps[3].args[2] == 0x8010
      and bagOps[4].name == 'bufferitemname' and bagOps[4].args[1] == 0 and bagOps[4].args[2] == 0x8008
      and bagOps[5].name == 'bufferpocketname' and bagOps[5].args[1] == 2 and bagOps[5].args[2] == 0x8010,
    'the bag: 0xB5 add, 0xB7 fits, 0xBB pocket, 0x04E item name, 0x052 pocket name')
  -- Juniper's nickname loop (0x105 / 0x110 / 0x054) and her Route 1
  -- catching demonstration (0x17D)
  local lab = Link2.rewriteCompound({ Link2.name(mk(0x105, '108000000000')), Link2.name(mk(0x110, '228000007500')),
    Link2.name(mk(0x054, '000000')), Link2.name(mk(0x053, '010000')), Link2.name(mk(0x17D, '')) })
  check(lab[1].name == 'openpokemonnamingscreen' and lab[1].args[1] == 0 and lab[1].args[2] == 0x8010
      and lab[2].name == 'bwmonhasnickname' and lab[2].args[1] == 0x8022 and lab[3].name == 'bufferpartymonnickname'
      and lab[4].name == 'bufferpartymonspecies' and lab[4].args[1] == 1 and lab[5].name == 'bwcatchingtutorial',
    'the lab and Route 1: naming screen, nickname test, party name buffers, catching demo')
  local Cm = require('src.script.Commands')
  local Gx = require('src.script.Gen4Commands')
  local nsave = { vars = {}, party = { { species = 495, nickname = 'Leafy', hp = 9, stats = { hp = 19 } } } }
  local nctx = { save = nsave, game = { data = { pokemon = { [495] = { name = 'Snivy' } } } } }
  Cm.g4_mon_has_nickname(nctx, 0x8022, 0)
  local nick = Gx.getVar(nsave, 0x8022)
  nsave.party[1].nickname = 'Snivy'
  Cm.g4_mon_has_nickname(nctx, 0x8022, 0)
  Cm.g4_mon_hp_full(nctx, 0x8010, 0)
  local hurt = Gx.getVar(nsave, 0x8010)
  nsave.party[1].hp = 19
  Cm.g4_mon_hp_full(nctx, 0x8010, 0)
  check(nick == 1 and Gx.getVar(nsave, 0x8022) == 0 and hurt == 0 and Gx.getVar(nsave, 0x8010) == 1,
    '0x110 answers a nickname, 0x101 full HP')
  -- a new game's hide flags (the shared script of nothing but setflags)
  local ng = b.constants and b.constants.gen4NewGame
  local hasPlasma = false
  for _, f in ipairs(ng and ng.flags or {}) do if f == 'FLAG_G4_0205' then hasPlasma = true end end
  check(ng and #ng.flags == 131 and #ng.vars == 1 and ng.vars[1].id == 0x4116 and hasPlasma,
    ('the new-game script: %s flags, %s var(s)'):format(tostring(ng and #ng.flags), tostring(ng and #ng.vars)))
  -- triggers: the value is the second halfword (Accumula's speech at 0x407A == 2)
  local acc = b.maps and b.maps.Z397
  local speech = acc and acc.coordEvents and acc.coordEvents[3]
  check(speech and speech.var == 0x407A and speech.value == 2 and speech.x == 19 and speech.y == 17 and speech.width == 6,
    "Accumula's speech trigger: var 0x407A == 2 at (19, 17), six wide")
  local accScripts = ms.maps and ms.maps.Z397
  check(accScripts and accScripts.coords and accScripts.coords[3], "Accumula's triggers are linked")
  local pc = ms.maps and ms.maps.Z398
  local nurse = pc and pc.shared and pc.shared.objects and pc.shared.objects[2]
  check(nurse and nurse.entry == 0 and ms.bands[nurse.band] and ms.bands[nurse.band].member == 855,
    'the nurse (script 2100) links to the shared band, member 855')
  local nurseOps = Link2.rewriteCompound({ Link2.name(mk(0x0D0, '23802480')), Link2.name(mk(0x0D4, '25802680')),
    Link2.name(mk(0x0CE, '2180')), Link2.name(mk(0x100, '2080')), Link2.name(mk(0x0BE, '8e01070013000000')),
    Link2.name(mk(0x03A, '0a0014000a000100')) })
  check(nurseOps[1].name == 'bwgetdate' and nurseOps[2].name == 'bwgetbirthday' and nurseOps[3].name == 'gettimeofday'
      and nurseOps[4].name == 'checkpartypokerus' and nurseOps[5].name == 'warp' and nurseOps[5].args[1] == 398
      and nurseOps[5].args[3] == 7 and nurseOps[5].args[4] == 19 and nurseOps[6].name == 'message' and nurseOps[6].args[1] == 10,
    'the nurse (date, birthday, time, Pokerus), 0x0BE warp, 0x03A floating message')
  -- stubs whose jump is the second load: 0x4D / 0x4F read 3 bytes (the
  -- gym's TM gift decoded askew at 6), and the scripts end cleanly more often
  local W = b.gen5_scripts and b.gen5_scripts.widths or {}
  check(W[0x4D] == 3 and W[0x4F] == 3 and W[0x50] == 3 and W[0x61] == 3 and W[0x62] == 3,
    ('stub widths: 4D %s, 4F %s, 61 %s, 62 %s'):format(tostring(W[0x4D]), tostring(W[0x4F]), tostring(W[0x61]), tostring(W[0x62])))
  -- GC chunks carry permissions in their second section (the Dreamyard)
  local M5 = require('src.import.Gen5Maps')
  local gc = M5.chunk(table.concat({ 'GC', string.char(4, 0), string.char(24, 0, 0, 0, 28, 0, 0, 0, 32, 0, 0, 0, 36, 0, 0, 0, 40, 0, 0, 0),
    'MDL.', 'PRM.', 'LYR.', 'BLD.' }))
  check(gc and gc.permissions == 'PRM.' and gc.layer2 == 'LYR.' and gc.buildings == 'BLD.', 'a GC chunk: model, permissions, second layer, buildings')
  local dy = b.maps and b.maps.Z152
  local walk = dy and dy.blocks and dy.blocks:byte((26 * dy.width + 12) * 2 + 2)
  check(walk and walk < 0x80, "the Dreamyard's ground is walkable (permissions read from its GC chunks)")
  -- the gym's curtains: invisible blockers seven wide
  local gym = b.maps and b.maps.Z007
  local curtain
  for _, o in ipairs(gym and gym.objects or {}) do if o.localId == 4 then curtain = o end end
  check(curtain and curtain.gen5Blocker and curtain.buried and curtain.footprintW == 7 and curtain.footprintH == 1,
    "Striaton gym's curtain: a 7 x 1 invisible blocker")
  local Col = require('src.world.Collision')
  local wall = { cellX = 9, cellY = 34, def = curtain }
  check(Col.occupied({ wall }, 15, 34, {}) == wall and Col.occupied({ wall }, 16, 34, {}) == nil, 'the footprint blocks (9..15, 34) and no further')
  -- the machines: TM01 Hone Claws, HM01 Cut, TM95 Snarl
  local it = b.items or {}
  check(it[328] and it[328].machine and it[328].machine.move == 468 and it[420].machine.move == 15
      and it[620] and it[620].machine and it[620].machine.move == 555,
    'machine moves: TM01 Hone Claws, HM01 Cut, TM95 Snarl')
  local misc = Link2.rewriteCompound({ Link2.name(mk(0x116, '10800f00')), Link2.name(mk(0x0C2, '0900070000000a00')),
    Link2.name(mk(0x056, '000a00')), Link2.name(mk(0x068, '20802180')) })
  check(misc[1].name == 'findpartyslotwithmove' and misc[1].args[2] == 15 and misc[2].name == 'warp' and misc[2].args[1] == 9
      and misc[3].name == 'buffertypename' and misc[3].args[2] == 10 and misc[4].name == 'getplayermappos',
    '0x116 slot with move, 0x0C2 warp, 0x056 type name, 0x068 position')
  -- trainers: what they say, and the object records that make them trainers
  local tm = b.gen4_trainer_messages
  check(tm and tm[9] and tm[9][0] == 135 and tm[9][1] == 136 and tm[9][2] == 137,
    "trainer lines: Waiter Maxwell's challenge, defeat and after-battle are bank 189's 135..137")
  local waiter
  for _, o in ipairs(gym and gym.objects or {}) do if o.localId == 7 then waiter = o end end
  check(waiter and waiter.trainer and waiter.trainer.id == 9 and waiter.sightRange == 6 and waiter.sightWays == 1,
    "Striaton gym's waiter: trainer 9 by its script's band, sight 6 along its facing")
  local tr = Link2.rewriteCompound({ Link2.name(mk(0x084, '2080')), Link2.name(mk(0x097, '20801080')),
    Link2.name(mk(0x087, '208021801180')), Link2.name(mk(0x088, '218022802380')) })
  check(tr[1].name == 'gettrainerid' and tr[2].name == 'bwtrainerbeaten' and tr[3].name == 'printtrainerdialogue'
      and tr[3].args[2] == 0x8021 and tr[4].name == 'gettrainermessagetypes',
    'the shared trainer script: trainer id, beaten, dialogue, message types')
  local more = Link2.rewriteCompound({ Link2.name(mk(0x086, '38003e003f000000')), Link2.name(mk(0x025, '20001080')),
    Link2.name(mk(0x095, '2080')), Link2.name(mk(0x006, '0100')) })
  check(more[1].name == 'multibattle' and more[1].args[1] == 56 and more[1].args[3] == 63
      and more[2].name == 'bwflagtovar' and more[2].args[1] == 0x20 and more[3].name == 'settrainerflag'
      and more[4].name == 'noop',
    "0x086 tag battle (Cheren 56 with 62 / 63), 0x025 flag into a var, 0x095 trainer flag, 0x006 no-op")
  -- warps: 1-based destWarp (the engine reads warps[destWarp]) and extents
  local house = b.maps and b.maps.Z401
  local mat = house and house.warps and house.warps[1]
  local acc2 = b.maps and b.maps.Z397
  local back = mat and acc2 and acc2.warps[mat.destWarp]
  check(mat and mat.width == 3 and back and back.x == 17 and back.y == 6,
    "Accumula house's exit mat (3 wide) leads back to its own door at (17, 6)")
  local extra = 0
  for _, w in ipairs(house and house.warps or {}) do if w.extentOf == 1 then extra = extra + 1 end end
  check(extra == 2 and house.warps[2].destMap == 'Z402', "the mat's other two cells follow the real warps")
  -- seams: Route 1's north edge meets Route 2 and Accumula, and the matrix
  -- names Accumula as the owner of its chunk inside Route 2's box
  local r1 = b.maps and b.maps.Z317
  local north = r1 and r1.connections and r1.connections.north
  local hasAcc = false
  for _, c in ipairs(north and north.list or {}) do if c.map == 'Z397' and c.offset == 32 then hasAcc = true end end
  check(hasAcc, "Route 1's north seam reaches Accumula (offset 32)")
  local mxs = b.gen4_map_matrices or {}
  local acc3 = b.maps and b.maps.Z397
  local m0 = acc3 and mxs[acc3.layout]
  local owner = m0 and m0.headers and m0.headers[math.floor(acc3.originY / 32) * m0.width + math.floor(acc3.originX / 32) + 1]
  check(owner == 397, ('the matrix names zone 397 the owner of its chunk (%s)'):format(tostring(owner)))
  local HP = require('src.world.Gen4HiddenPaths')
  check(HP.applyToDef({}, { generation = 4, gen5 = true, layout = 0, blocks = '', behaviorCells = '' }, {}) == false,
    "Platinum's hidden paths leave Black and White's maps alone")
  local cas = b.maps and b.maps.Z028
  local ct = cas and cas.coordEvents and cas.coordEvents[1]
  -- 1 step along x 8 tiles across line 4 -- the street's width -- which
  -- on the map is the 7 x 3 box at (17, 36)
  check(ct and ct.rail and ct.rail.line == 4 and ct.rail.along == 24 and ct.rail.across == -5
      and ct.x == 17 and ct.y == 36 and ct.width == 7 and ct.height == 3,
    ("a trigger's rail shape (+8 = 1: line, along, across, 1 along x 8 across): Castelia's on line 4, step 24, placed at (%s, %s) %s x %s")
      :format(tostring(ct and ct.x), tostring(ct and ct.y), tostring(ct and ct.width), tostring(ct and ct.height)))
  -- a hybrid map: Z030's plaza grid grown to take its rails, its exits across
  -- the streets' ends, and its Burgh trigger on the map
  local z30 = b.maps and b.maps.Z030
  local zt = z30 and z30.coordEvents and z30.coordEvents[1]
  check(z30 and z30.height > 32 and zt and zt.rail and zt.x == 3 and zt.y == 20,
    ("hybrid rail map: Z030 grown past its 32 x 32 chunk (%s tall), its trigger at (%s, %s)")
      :format(tostring(z30 and z30.height), tostring(zt and zt.x), tostring(zt and zt.y)))
  -- Nimbasa Gym's coaster: nine docks, track 0 joining the middle island
  -- (dock 1, 22,39) to the entrance (dock 0) with its switch at 0
  local co = b.maps and b.maps.Z063 and b.maps.Z063.gen5Coaster
  local d1 = co and (co.docks[1] or co.docks['1'])
  local p0 = co and (co.pairs[0] or co.pairs['0'])
  local p00 = p0 and (p0[0] or p0['0'])
  check(d1 and d1.x == 22 and d1.y == 39 and p00 and p00[1] == 1 and p00[2] == 0,
    "Nimbasa Gym's coaster tables read from its overlay (dock 1 at (22, 39), track 0 joins docks 1 and 0)")
  -- Driftveil Gym's lifts: six lifts and eight walkways from its overlay,
  -- and where the lifts stand on arrival (the entry script's flag run)
  local gl = b.maps and b.maps.Z097 and b.maps.Z097.gen5Lifts
  local l6 = gl and gl.lifts and gl.lifts[6]
  local init = gl and gl.initial
  check(l6 and l6.x == 14 and l6.z == 20 and l6.a == 50 and l6.b == -59 and #gl.strips == 8
      and init and init[11] == true and init[15] == false,
    "Driftveil Gym's lifts read from its overlay (lift 6 at (14, 20) from 50 down to Clay's -59; flag 0x0B set on arrival)")
  -- Mistralton Gym's cannons: ten, each with its landings by direction
  local cn = b.maps and b.maps.Z108 and b.maps.Z108.gen5Cannons
  local c0 = cn and cn[1]
  local up = c0 and c0.landings and (c0.landings[1] or c0.landings['1'])
  check(cn and #cn == 10 and c0.x == 15.5 and c0.z == 28.5 and up and up.x == 15 and up.z == 19,
    "Mistralton Gym's cannons read from its overlay (cannon 0 at (15.5, 28.5) fires up to (15, 19))")
  -- Icirrus Gym: its rails stay inside the grid (no hybrid growth); the
  -- trigger-started chains are gated rides, the gate table from its overlay
  local ic = b.maps and b.maps.Z114
  local t1 = ic and ic.gen5RailTracks and ic.gen5RailTracks[1]
  local g6 = ic and ic.gen5RailGates and (ic.gen5RailGates[6] or ic.gen5RailGates['6'])
  check(ic and ic.width == 64 and t1 and t1.x == 17 and t1.y == 61 and t1.toX == 11 and t1.toY == 60
      and g6 and g6.group == 2 and g6.state == 1,
    "Icirrus Gym: 64 x 64 kept, ride 0 from (17, 61) to (11, 60), ride 6 gated on switch group 2 at 1")
  local pv = b.constants and b.constants.gen5ParkVisitors
  check(pv and (pv[0] or pv['0']) == 15 and (pv[2] or pv['2']) == 64,
    "0x232's park-visitor table read off its handler (15, 55, 64, ...)")
  -- rail-placed warps, and the NG chunk size per rail map
  local gate
  for _, w in ipairs(cas and cas.warps or {}) do if w.index == 10 then gate = w end end
  check(gate and gate.destMap == 'Z252' and gate.x == 71 and gate.y == 31 and gate.rail and gate.rail.line == 1,
    ("rail warps: Castelia's warp 10 (line 1) to the bridge gate Z252 at (71, 31) -- got (%s, %s)")
      :format(tostring(gate and gate.x), tostring(gate and gate.y)))
  check(cas and cas.gen5ChunkScale == 1 and b.maps.Z249 and b.maps.Z249.gen5ChunkScale == 4,
    "NG chunk size per rail map: Castelia the normal 512 units, Skyarrow 2,048")
  -- the cameras: /a/0/6/0 records by the zone header's +0x1C bits 9..15
  local cam = b.maps and b.maps.Z006 and b.maps.Z006.gen5Camera
  local pc = b.maps and b.maps.Z398 and b.maps.Z398.gen5Camera
  check(cam and cam.id == 'bw_0' and cam.distance == 237 and math.abs(cam.pitch - 53.22) < 0.01
      and math.abs(cam.halfFov - 20.0) < 0.01 and pc and pc.id == 'bw_3' and pc.distance == 229,
    ('cameras: Striaton the default (237 at 53.2 degrees), a Pokemon Center record 3 (%s)'):format(tostring(pc and pc.id)))
  -- the rails: zone -> ARM9 index table -> /a/1/0/9 -> /a/0/7/9
  local rails = b.gen5_rails or {}
  local cz = b.maps and b.maps.Z028 and b.maps.Z028.gen5Rail
  local bz = b.maps and b.maps.Z249 and b.maps.Z249.gen5Rail
  local bridge = rails[11]
  check(cz and cz.file == 5 and bz and bz.file == 11 and bridge and bridge.points[0]
      and bridge.points[0].name == 'RE_POINT_0' and bridge.lines[0].name:match('^RE_LINE_0')
      and math.abs(bridge.points[0].x - 1552) < 0.01 and rails[5] and rails[5].curves[0].kind == 1,
    "rails: Castelia's centre is file 5 (a ring about a curve centre), Skyarrow Bridge file 11 (RE_POINT_0 at x 1552)")
  -- the cutscene camera: 0x143's look-at point becomes Platinum's free camera
  local cam = Link2.rewriteCompound({ Link2.name(mk(0x143, 'de2500002bd00e000080840200000000008047021800')) })
  check(#cam == 1 and cam[1].name == 'addfreecamera' and cam[1].args[1] == 644 and cam[1].args[2] == 583
    and Link2.name(mk(0x147, '1e00')).name == 'restorecamera',
    ('0x143 looks at absolute tile (%s, %s); 0x147 hands the camera back'):format(tostring(cam[1] and cam[1].args[1]), tostring(cam[1] and cam[1].args[2])))
  -- tile heights: the gym's dais tiles carry value 14, which NAMES 16 world
  -- units (src/import/Gen5Heights.lua: 119 people stand on it at 16); its
  -- floor 0 (written only beside a raised tile)
  local gym = b.maps and b.maps.Z007
  local he = gym and gym.gen4HeightEdits or {}
  check(he['12,3'] == 16 and (he['12,9'] == nil or he['12,9'] == 0) and he['9,1'] == 16,
    ('Z007 heights: dais %s, floor %s'):format(tostring(he['12,3']), tostring(he['12,9'])))
  local r1 = b.encounters and b.encounters[77]
  check(r1 and r1.grass[1].species == 504 and r1.grass[2].species == 506 and r1.grass[1].minLevel == 2,
    'Route 1 grass: Patrat (504) and Lillipup (506) from level 2')
  local tc = b.type_chart
  local fightNormal
  for _, m in ipairs(tc and tc.matchups or {}) do
    if m.attacker == 'FIGHTING' and m.defender == 'NORMAL' then fightNormal = m.multiplier end
  end
  check(fightNormal == 20, 'type chart (17 x 17): Fighting is x2 against Normal')
  local font = b.font
  check(font and font.pages and font.pages.message and #font.charmap > 4000,
    'the NFTR message font and its charmap (Gen5Font)')
  do
    local Narc, F = require('src.import.NarcArchive'), require('src.import.Gen5Font')
    local rom = require('src.import.NdsRom').open(black)
    local f = rom and F.parse(Narc.parse(rom:read('/a/0/2/3')):get(0))
    local blankTop = true
    if f then
      local g = F.glyph(f, f.codes[32])
      for _, role in ipairs(g) do if role ~= 0 then blankTop = false end end
    end
    check(f and f.recordBytes == 3 and f.widths[f.codes[84]] == 6 and f.widths[f.codes[32]] == 4 and blankTop,
      "each glyph slot opens with its width record: 'T' advances 6, the space 4 and draws nothing")
  end
  local rep = b.gen5_version or {}
  check(rep.family == 'bw' and #(rep.notPorted or {}) > 0, 'what is not ported yet is reported')
  -- THE MAPS PASS (Gen5Warps, Gen5DynamicCity): the Marvelous Bridge copy's
  -- deck warps are step-onto warps (transition 6), and Black City has floor
  -- and its shops' doors
  do
    local maps = b.maps or {}
    local W = require('src.world.Gen5Warps')
    local function cellMap(def)
      local warpAt = {}
      for i, wp in ipairs(def.warps or {}) do warpAt[wp.y * def.width + wp.x] = { index = i, def = wp } end
      return { def = def, warpAtCell = function(_, x, y) return warpAt[y * def.width + x] end }
    end
    local z303 = maps.Z303
    local m303 = z303 and cellMap(z303)
    check(m303 and W.stepWarpAt(m303, 14, 33) and W.stepWarpAt(m303, 161, 33)
      and W.stepWarpAt(m303, 14, 33).destMap == 'Z314' and W.stepWarpAt(m303, 161, 33).destMap == 'Z313',
      "Marvelous Bridge (Z303): its deck warps (14,33) and (161,33) are step-onto warps (transition 6) to Routes 16 and 15")
    local z263 = maps.Z263
    check(z263 and not W.stepWarpAt(cellMap(z263), 14, 31), "the real bridge's gate doors (Z263) stay press warps")
    local z0 = maps.Z000
    local function blocked(def, x, y) return def.blocks:byte((y * def.width + x) * 2 + 1) == 0xFF end
    local open = 0
    if z0 then for y = 0, z0.height - 1 do for x = 0, z0.width - 1 do if not blocked(z0, x, y) then open = open + 1 end end end end
    local doors = z0 and blocked(z0, 43, 36) and not blocked(z0, 43, 37) and blocked(z0, 11, 37) and not blocked(z0, 11, 38)
      and blocked(z0, 27, 38) and blocked(z0, 19, 45) and blocked(z0, 35, 45)
    check(z0 and open > 1000 and doors,
      ('Black City (Z000): RD floor (%d open cells) with its pieces -- every shop door (43,36) (11,37) (27,38) (19,45) (35,45) a wall to press'):format(open))
    local t = b.gen4_terrain or {}
    local objs = t.chunks and t.chunks[232] and t.chunks[232].objects or {}
    local pieces = 0
    for _, o in ipairs(objs) do if o.gen5Piece then pieces = pieces + 1 end end
    check(pieces >= 4, ("Black City chunk 232 carries the pieces' buildings (%d)"):format(pieces))
  end
end

local w = extract(white, 'white')
check(w ~= nil and w.pokemon and w.pokemon[644] and w.pokemon[644].name == 'Zekrom'
  and w.pokemon[643] and w.pokemon[643].name == 'Reshiram', 'White: the stages run (Reshiram, Zekrom)')
-- White shows White Forest where Black shows Black City: the Black Gate's
-- warps lead to Z424 (ARM9 0x20A72A8's swap, Gen5DynamicCity.remap)
if w then
  local to = {}
  for _, id in ipairs({ 'Z375', 'Z379' }) do
    for _, wp in ipairs((w.maps or {})[id] and w.maps[id].warps or {}) do to[wp.destMap] = true end
  end
  check(to.Z424 and not to.Z000, 'White: the Black Gate leads to White Forest (Z424), not Black City')
end
-- the season's texture set: the area's record + season (Gen5Seasons)
do
  local S = require('src.render.Gen5Seasons')
  local sets = {}
  for k = 6, 9 do sets[k] = { textures = { grass = 'set' .. k } } end
  sets[14] = { textures = { gate = 'gate14' } }
  sets[10006] = { textures = { grass = 'set6', gate = 'gate14' }, merged = { 6, 14 } }
  for k = 15, 17 do sets[k] = { textures = { gate = 'gate' .. k } } end
  local terrain = { sets = sets }
  local plain, merged = { texture = 6, area = 6 }, { texture = 10006, area = 6 }
  check(S.setFor(terrain, plain, 0).textures.grass == 'set6' and S.setFor(terrain, plain, 3).textures.grass == 'set9'
    and S.setFor(terrain, merged, 2).textures.grass == 'set8' and S.setFor(terrain, merged, 2).textures.gate == 'gate16'
    and S.setFor(terrain, { texture = 250, area = 250 }, 2) == nil and S.areaFor(220, 3) == 220,
    'seasons: a place wears its area + season set (merged sets per area), indoor areas (210+) never change')
end

-- third person: the eye stops in front of a wall behind the player, not over water
do
  local Ground = require('src.render.Gen4Ground')
  local function fake(word)
    return { offsetX = 0, offsetY = 0,
      permissionWordAt = function(_, tx, ty) if tx == 10 and ty == 13 then return word end return 0 end,
      groundY = function() return 0 end }
  end
  local function view() return { pivotX = 168, pivotY = 16, pivotZ = 168, x = 168, y = 40, z = 264 } end
  local wall, v1 = fake(0x8001), view()
  Ground.clearCameraLine(wall, v1)
  local lake, v2 = fake(0x8000 + 0x10), view()
  Ground.clearCameraLine(lake, v2)
  local surf = require('src.import.Gen4Behaviors').isSurfable(0x10)
  check(v1.z < 208 and v1.z > 168 and math.abs((v1.y - 16) / (v1.z - 168) - 24 / 96) < 1e-6
    and (not surf or v2.z == 264),
    ('third person pulls in to z %.1f in front of a wall two tiles back (along its own line), not over water (%s)'):format(v1.z, tostring(v2.z)))
end

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
