-- Run:  python tools/run_lua_check.py tools/gen4_hgss_import_check.lua <heartgold .nds> [soulsilver .nds] [pokeheartgold]
--
-- HEARTGOLD AND SOULSILVER THROUGH THE GEN 4 EXTRACTOR (src/import/Gen4Versions.lua):
-- the stages whose formats HGSS shares with Platinum -- text, species with
-- their learnsets and evolutions, moves, items, trainers and their lines --
-- run against the real cartridges, their writes captured rather than put in a
-- cache, and what came out compared with what pokeheartgold says is there.
-- Also: Platinum's own paths and banks come back after an HGSS extractor, and
-- the stages HGSS does not run yet are reported as not ported.
--
-- THE FIELD STAGES as well: HGSS's own encounter record (Route 29 by time of
-- day, Route 30's version exclusives), its map header layout in its
-- BLZ-compressed ARM9 (540 headers, EVERYWHERE first, as pokeheartgold's
-- map_headers.h orders them), the land chunks' extra sound section, the events,
-- and the scripts -- decoded with HGSS's own 853-command table, every block
-- ending cleanly, and lowered through Platinum's VM by the alias table.

package.path = './?.lua;./?/init.lua;' .. package.path
love = require('tests.love_stub')
local PASS, FAIL = 0, 0
local function check(c, l) if c then PASS = PASS + 1 else FAIL = FAIL + 1; print('FAIL: ' .. l) end end
local hg = arg and arg[1] or './Pokemon - HeartGold Version (USA).nds'
local ss = arg and arg[2] or './Pokemon - SoulSilver Version (USA, Australia).nds'
local pret = arg and arg[3]

local LuaWriter = require('src.import.LuaWriter')
local captured
LuaWriter.write = function(path, value) captured[path:match('([^/]+)%.lua$')] = value end
-- NOTHING REACHES THE DISK. The terrain stage writes binaries and PNGs under
-- assets/generated/gen4/, a path every Gen 4 cache shares; a check must not
-- leave HeartGold's ground where Platinum's is read from.
local sideFiles = {}
require('src.import.CacheFs').write = function(rel, data) sideFiles[rel] = #data; return true end
local ImageWriter = require('src.import.ImageWriter')
ImageWriter.save = function(_, path) sideFiles[path] = true; return true end
ImageWriter.fromRGBA8 = function(w, h) return { width = w, height = h } end
local X = require('src.import.RomExtractorGen4')
local V = require('src.import.Gen4Versions')

local function extract(path, version)
  captured = {}
  local x, err = X.new(path, version)
  if not x then print('cannot open ' .. tostring(path) .. ': ' .. tostring(err)) return nil end
  local ok, e = pcall(x.run, x)
  if not ok then print('extract failed: ' .. tostring(e)) end
  local out = captured
  out._x = x
  x:close()
  return ok and out or nil
end

local platinumPersonal = X.PATH.personal
local h = extract(hg, 'heartgold')
check(h ~= nil, 'HeartGold: the core stages run')
if h then
  local opening=h.gen4_models and h.gen4_models.sets.hgssOpening
  check(opening and #opening.models==3 and #opening.animations==6,
    'three native opening city models retain joint and texture animations')
  check(h.gen4_hgss_boot_art and h.gen4_hgss_boot_art.scene4
    and #h.gen4_hgss_boot_art.emitters==9 and h.gen4_hgss_boot_art.opening_particle_0,
    'starter-scene SPA resources survive the importer build/cache boundary')
  check(h.gen4_hgss_boot_art and h.gen4_hgss_boot_art.sky_top
    and h.gen4_hgss_boot_art.trainers_back and h.gen4_hgss_boot_art.sequences.sky_actor[1],
    'HGSS opening imports versioned sky, trainer layers and native legendary affine animation')
  check(h.gen4_menus and h.gen4_menus.hgss and h.gen4_menus.layout.optionWidth==23
    and h.gen4_menus.rows[2].lines==2 and h.gen4_menus.continueRows[4].value=='ownedCount',
    'HGSS main menu keeps native geometry and owned-Pokedex summary')
  check(h.gen4_main_menu_art and h.gen4_main_menu_art.frame_focused and h.gen4_main_menu_art.scroll_down,
    'HGSS main menu frames and arrows extracted from native archives')
  local mons = h.pokemon or {}
  check(h.gen4_move_anims and h.gen4_move_anims.count == 501 and h.gen4_move_anims.skipped == 5,
    '496 HGSS animation programs decode; five using HGSS-only opcodes remain unsupported')
  check(h.gen4_particles and h.gen4_particles.textures > 0, 'HGSS move particles extracted')
  check(h.constants.martCommon and #h.constants.martCommon == 19, 'HGSS badge-tier mart stock extracted')
  check(h.gen4_trainer_sprites.backs[0] and h.gen4_trainer_sprites.backs[1], 'Ethan and Lyra back sprites extracted')
  check(h.gen4_hgss_pokegear_art and h.gen4_hgss_pokegear_art.map_top_0,
    'Pokegear skin backgrounds extracted')
  check(h.gen4_hgss_starter_art and h.gen4_hgss_starter_art.preview,
    'starter preview backgrounds extracted')
  check(mons[1] and mons[1].name == 'BULBASAUR' and mons[152] and mons[152].name == 'CHIKORITA'
    and mons[493] and mons[493].name == 'ARCEUS', 'species 1, 152 and 493 by name (bank 237)')
  local chik = mons[152] or {}
  check(chik.learnset and #chik.learnset > 5 and chik.evolutions and chik.evolutions[1], "Chikorita's learnset and evolution")
  check(chik.dexEntry and chik.dexEntry:find('leaf') ~= nil, "Chikorita's dex entry (bank 803)")
  local moves = h.moves or {}
  check(moves[1] and moves[1].name and moves[1].name:upper() == 'POUND' and moves[467] ~= nil, 'moves: Pound, and 467 of them')
  local items = h.items or {}
  check(items[1] and items[1].name == 'Master Ball', 'items: the Master Ball (bank 222)')
  local trainers = h.trainers or {}
  -- trainer 20 is the gym's Falkner (712 is his rematch, with six)
  local falkner = trainers[20]
  check(falkner and falkner.name == 'Falkner' and falkner.party and #falkner.party == 2
    and trainers[712] and #trainers[712].party == 6, "Falkner (20) with his two Pokemon, and his rematch (712) with six")
  check(falkner and falkner.className == 'Leader', "...and he is a Leader (bank 730)")
  check(h.gen4_trainer_messages ~= nil, "the trainers' lines")
  local rep = h.gen4_version or {}
  check(rep.family == 'hgss' and #(rep.notPorted or {}) > 0, 'the stages not run are reported, not run')

  -- encounters: area 1 is Route 29 -- one level per slot, all three times
  local enc = h.encounters or {}
  local r29 = enc[1] or {}
  check(r29.grassRate == 25 and r29.grass and r29.grass[1].species == 16 and r29.grass[1].level == 2
    and r29.timed and r29.timed.night[1] == 163, 'Route 29: Pidgey at 2 by morning, Hoothoot by night (rate 25)')
  local G4E = require('src.import.Gen4Encounters')
  local night = G4E.timedGrass(r29, 22)
  check(night and night[1].species == 163 and night[1].level == 2 and G4E.timedGrass(r29, 7) == nil,
    'the whole grass table changes with the time; the morning one is the base')
  check(r29.oldRod and r29.oldRod.slots[1].chance == 40 and enc[0].surf.slots[1].minLevel <= enc[0].surf.slots[1].maxLevel,
    'fishing rolls 40/30/15/10/5; water levels read minimum first')
  local hr30 = enc[3] or {}
  check(hr30.grass and hr30.grass[1].species == 16 and hr30.grass[2].species == 10, "HeartGold's Route 30: Pidgey, Caterpie")

  -- map headers, out of the compressed ARM9
  local hdr = h.gen4_map_headers or {}
  local n = 0 for _ in pairs(hdr) do n = n + 1 end
  check(n == 540 and hdr[0].scripts == 139 and hdr[0].matrix == 0 and hdr[2].matrix == 74,
    '540 map headers, EVERYWHERE (scripts 139) first and UNION (matrix 74) third')
  check(hdr[0].mapType == 2 and hdr[0].allowBike and hdr[0].allowEscapeRope and not hdr[0].allowFly,
    "EVERYWHERE's flags: a route, bike and Escape Rope, no Fly (map_headers.h)")
  local maps = h.maps or {}
  check(maps.T20 and maps.T20.label == 'New Bark Town' and maps.R29 and maps.R29.encounters == 1,
    'New Bark Town by name; Route 29 on encounter table 1')
  -- the camera: HGSS's own table under Platinum's camera code
  local C = require('src.render.Gen4Camera')
  local nb = maps.T20 and C.forType(maps.T20.cameraType, maps.T20.cameraFamily)
  check(maps.T20 and maps.T20.cameraFamily == 'hgss' and nb and nb.family == 'hgss'
    and math.abs(nb.pitch - 48.68) < 0.01 and nb.far == 1200,
    "New Bark Town's camera is HGSS's DEFAULT (48.7 degrees, far 1200), not Platinum's")
  local room = C.HGSS_TYPES[4]
  check(room.projection == 'orthographic' and math.abs(room.distance - C.TYPES[4].distance) < 0.001
    and math.abs(room.halfFov - C.TYPES[4].halfFov) < 0.001,
    "HGSS's interior camera is Platinum's orthographic one -- the decode agrees where the games do")
  -- the ground: every land chunk's model, the 106 texture sets, and each
  -- map's set and outdoor/indoor flag out of HGSS's own area record
  local tr = h.gen4_terrain or {}
  local packedChunks, tsets = 0, 0
  for _ in pairs(tr.chunks or {}) do packedChunks = packedChunks + 1 end
  for _ in pairs(tr.sets or {}) do tsets = tsets + 1 end
  check(packedChunks == 676 and next(tr.refused or {}) == nil and tsets == 106,
    'terrain: all 676 chunk models packed, none refused; 106 texture sets (/a/0/4/4)')
  local nbArea, room = tr.maps and tr.maps.T20, tr.maps and tr.maps.T20R0101
  check(nbArea and nbArea.texture == 2 and nbArea.outdoors == true and room and room.outdoors == false,
    "New Bark Town wears set 2 outdoors; Elm's Lab is indoors (area byte +6)")
  local lights = (h.gen4_arealight or {}).members or {}
  check(next(lights) ~= nil and nbArea and nbArea.areaLight == 0 and room and room.areaLight == 1,
    "area light: New Bark reads arealight 0 (outdoors), Elm's Lab 1 (light byte 1 -> 0, 0 -> 1)")
  -- the buildings: both archives, and every prop New Bark's matrix places
  local msets = (h.gen4_models or {}).sets or {}
  local function count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
  check(msets.buildings and count(msets.buildings.models) == 340 and msets.interiorBuildings
    and count(msets.interiorBuildings.models) == 222,
    'buildings: 340 outdoor (/a/0/4/0) and 222 room models (/a/1/4/8)')
  local nbDef = maps.T20
  local nbGrid = nbDef and tr.matrices and tr.matrices[nbDef.layout]
  local placed, unplaced = 0, 0
  for _, landId in pairs(nbGrid and nbGrid.land or {}) do
    for _, o in ipairs((tr.chunks[landId] or {}).objects or {}) do
      placed = placed + 1
      if not (msets.buildings and msets.buildings.models[o.model + 1]) then unplaced = unplaced + 1 end
    end
  end
  check(placed > 0 and unplaced == 0, ('every prop on the Johto overworld resolves to a model (%d)'):format(placed))
  -- the people: pret's sprite table (Gen4HgssObjectGfx), every map object but
  -- the SPRITE_VAR_n ones (filled in at run time) resolving to a sheet
  local sprites = h.sprites or {}
  local objs, withSprite, varOnly = 0, 0, true
  for _, d in pairs(maps) do
    for _, o in ipairs(d.objects or {}) do
      objs = objs + 1
      if o.sprite and sprites[o.sprite] then withSprite = withSprite + 1
      elseif not (tonumber(o.graphicsId) and o.graphicsId >= 100 and o.graphicsId <= 115) then varOnly = false end
    end
  end
  check(objs > 2500 and varOnly, ('%d of %d map objects have a sprite; the rest are SPRITE_VAR_n'):format(withSprite, objs))
  local ow = h._x and h._x.overworldReport or {}
  check((ow.sprites or 0) >= 832 and ow.facings and ow.facings.sequences and ow.facings.sequences.found == 17,
    "832 sprite sheets, and HGSS's 17 animation tables (members 280..296)")
  local OC = require('src.world.OverworldController')
  local hero = OC.gen4SpriteFor({ gen4_version = { family = 'hgss' } }, 0)
  check(hero == 'SPRITE_G4_069', 'at run time SPRITE_HERO (0) is mmodel member 69, as pret has it')
  -- the boot: sLocation_PlayerRoom and sSpawnMaps (pret), found together
  local field = h.field or {}
  local boot = field.boot or {}
  check(boot.startMap == 'T20R0202' and boot.startX == 6 and boot.startY == 6 and boot.startFacing == 'down',
    "a new game starts in the player's bedroom, 6,6, facing down (location_backup.c)")
  check(boot.lastHeal and boot.lastHeal.map == 'T20R0201' and boot.lastHeal.x == 6 and boot.lastHeal.y == 8
    and #(field.healLocations or {}) == 30,
    'blackout to the house downstairs at 6,8; all 30 sSpawnMaps rows')
  local pform = field.playerForms or {}
  check(pform.boy and pform.boy.walk == 'SPRITE_G4_069' and pform.boy.bike == 'SPRITE_G4_071'
    and pform.girl and pform.girl.walk == 'SPRITE_G4_070' and pform.girl.surf == 'SPRITE_G4_074',
    "the player's sheets by state (player_avatar.c): HERO 69, CYCLEHERO 71, HEROINE 70, SWIMHEROINE 74")
  -- constants (Gen4HgssConstants): the type chart out of an overlay NdsRom
  -- had to unpack, the curves, HGSS's TMs and HMs, the new game's flags
  local k = h.constants or {}
  local tr = k.gen4Trades or {}
  check(#tr == 13 and tr[1].species == 95 and tr[1].request == 69 and tr[1].nickname == 'Rocky'
    and tr[1].otName == 'Rudy' and tr[13] and tr[13].species == 374,
    ('in-game trades: %d, the first %s for %s nicknamed %s from %s'):format(#tr, tostring(tr[1] and tr[1].species),
      tostring(tr[1] and tr[1].request), tostring(tr[1] and tr[1].nickname), tostring(tr[1] and tr[1].otName)))
  check(h.type_chart ~= nil and h._x.constantsReport and h._x.constantsReport.chartOverlay == 12,
    "the type chart, found in HGSS's battle overlay 12 once it is BLZ-unpacked")
  check(k.experienceTables and k.experienceTables.MEDIUM_SLOW and k.experienceTables.MEDIUM_SLOW[101] == 1059860,
    'growth curves: medium slow reaches 1,059,860 at 100')
  check(k.tmhmMoves and k.tmhmMoves[1] == 264 and k.tmhmMoves[92] == 433 and k.tmhmMoves[97] == 250,
    'TM01 Focus Punch, TM92 Trick Room, HM05 Whirlpool (not Defog)')
  check(k.gen4NewGame and #k.gen4NewGame.flags > 100 and #k.badges == 16,
    "the new game's SetFlags out of scr_seq 149, and sixteen badges")
  -- battle art: every species and every trainer class
  local spr = h._x.speciesSpriteReport or {}
  local tsr = h._x.trainerSpriteReport or {}
  check((spr.missing == 0) and (spr.images or 0) > 2600 and tsr.written == 129 and tsr.stamped == 738,
    ('species sprites: %s images, none missing; 129 trainer classes on all 738 trainers'):format(tostring(spr.images)))
  -- battle backdrops: 23 x day/evening/night x colour/grey out of /a/0/0/7,
  -- palettes from 0xB0 (overlay 12), named as the battle screen looks them up
  local bgr = h._x.battleGraphicsReport or {}
  local gfxBgs = (h.gen4_graphics or {}).backgrounds or {}
  check(bgr.backgrounds == 138 and gfxBgs.plain_day and gfxBgs.forest_night_gray,
    'battle backdrops: all 138, under the names the battle screen asks for')
  -- the battle interface (Gen4HgssBattleUi): Platinum's importers over
  -- /a/0/0/8, /a/0/0/7, /a/0/7/1, /a/0/7/7 and /a/0/1/6
  local gfx = h.gen4_graphics or {}
  local art = h.gen4_battle_art or {}
  check(bgr.interface and gfx.healthboxParts and gfx.healthboxParts.overlay == 12
    and gfx.healthboxDigits and gfx.subscreen and (gfx.battleObjects or {}).healthbox_player_singles,
    'battle interface: healthboxes, their parts out of overlay 12, the digits and the touch screen')
  check(art.cursor_0_0 and art.stock_player_0 and art.contest_net_1_0 and art.contest_ball_0_0
    and art.bparty_digits and h.gen4_move_buttons ~= nil,
    "battle art: the cursor, the party balls, the contest's net and Sport Ball, the move buttons")
  local icons = (h.gen4_species_sprites or {}).icons
  check(icons and icons.count and icons.count > 500 and icons.bySpecies[123],
    ('party icons out of /a/0/2/0: %s'):format(tostring(icons and icons.count)))
  check(require('src.import.Gen4HgssBattle').background(3, 0).palette == 176 + 9,
    "forest's day palette is member 185 (bg*3 + 0xB0 + time), not Platinum's 181")
  -- the text: HGSS's font archive under the names it shares with Platinum's
  local fpages = (h.gen4_fonts or {}).pages or {}
  check(fpages.font_message and fpages.font_system and fpages.font_unown and h.font
    and h.font.charmap and #h.font.charmap > 400,
    "fonts: message, system and unown pages, and the font definition text is drawn with")
  local wf = h._x and h._x._winFrames or {}
  check(wf.standard and wf.standard.count == 2 and wf.dialogue and wf.dialogue.count == 20
    and h.font and h.font.frames ~= nil,
    'window frames (/a/0/3/8): both standard frames and all 20 message boxes, carried by the font')
  local perms = h.gen4_map_permissions or {}
  local chunks = 0 for _ in pairs(perms) do chunks = chunks + 1 end
  check(chunks == 676, 'all 676 land chunks parse, the sound section skipped')
  local exact = true
  for _, e in pairs(h.gen4_events or {}) do if not e.exact then exact = false end end
  check(exact, 'every event file is consumed to the byte')

  -- scripts
  local pool = h.map_scripts or {}
  local VM = require('src.script.Gen4ScriptVM')
  local total, lowered, badStop = 0, 0, 0
  for _, sc in pairs(pool.scripts or {}) do
    local afterGoto = false
    for _, ins in ipairs(sc.instructions or {}) do
      total = total + 1
      if VM.lowered(ins.name) then lowered = lowered + 1 end
      if ins.op == 0x16 then afterGoto = true end
    end
    if sc.stopped ~= 'end' and not afterGoto then badStop = badStop + 1 end
  end
  check(total > 150000 and badStop == 0, ('%d instructions, every block ends at end/return or after a goto'):format(total))
  check(lowered / math.max(total, 1) >= 0.96, ('%.1f%% lower through the VM'):format(100 * lowered / math.max(total, 1)))
  local resolved = 0 for _ in pairs(pool.bands or {}) do resolved = resolved + 1 end
  check(resolved >= 29, "HGSS's common-script bands resolve to their files (sScriptBankMapping)")
end

-- HGSS's named animation tables are byte for byte Platinum's of that name
do
  local plPath = arg and arg[4] or './Pokemon - Platinum Version (USA) (Rev 1).nds'
  local NdsRom, Narc = require('src.import.NdsRom'), require('src.import.NarcArchive')
  local plRom, hgRom = NdsRom.open(plPath), NdsRom.open(hg)
  if plRom and hgRom then
    local pl = Narc.parse(plRom:read('/data/mmodel/mmodel.narc'))
    local hga = Narc.parse(hgRom:read('/a/0/8/1'))
    local plSeq = require('src.import.Gen4Facings').read(pl)
    local HF = require('src.import.Gen4HgssFacings')
    local bad = {}
    for member, name in pairs(HF.NAMES) do
      local twin = plSeq[name]
      if twin and pl:get(twin.member) ~= hga:get(member) then bad[#bad + 1] = name end
    end
    check(#bad == 0, 'every named HGSS sequence is identical to Platinum\'s: ' .. table.concat(bad, ', '))
  else
    print('(Platinum ROM not found; the sequence identity check is skipped)')
  end
end

-- TRAINER PICTURES DECRYPT IN DIAMOND AND PEARL'S ORDER (UnscanPokepic sends
-- NARC_a_0_5_8 to the _DP variant): a real picture is mostly background,
-- palette index 0, where a wrongly-ordered decrypt spreads evenly over all 16
do
  local Narc, Trgra, G = require('src.import.NarcArchive'), require('src.import.Gen4Trgra'), require('src.import.Gen4Graphics')
  local rom = require('src.import.NdsRom').open(hg)
  local arc = rom and Narc.parse(rom:read('/a/0/5/8'))
  local function zeros(sheet)
    local n, z = 0, 0
    for i = 1, #sheet.pixels do
      local b = sheet.pixels:byte(i)
      n = n + 2
      if b % 16 == 0 then z = z + 1 end
      if math.floor(b / 16) == 0 then z = z + 1 end
    end
    return z / n
  end
  local dp = arc and Trgra.sheet(arc, G, 66, true)
  local fwd = arc and Trgra.sheet(arc, G, 66, false)
  check(dp and fwd and zeros(dp) > 0.4 and zeros(fwd) < 0.15,
    ("Falkner's picture (class 66): %.0f%% background in DP order, %.0f%% in Platinum's")
      :format(100 * (dp and zeros(dp) or 0), 100 * (fwd and zeros(fwd) or 0)))
end

-- the alias table renames only to a command of the same width, or says how
do
  local Aliases = require('src.import.Gen4HgssScriptAliases')
  local H = require('src.import.Gen4HgssScriptOps')
  local P = require('src.import.Gen4ScriptOps')
  local hSpec, pSpec = {}, {}
  for _, e in pairs(H.COMMANDS) do hSpec[e[1]] = e[2] end
  for _, e in pairs(P.COMMANDS) do pSpec[e[1]] = e[2] end
  local bad = {}
  for from, to in pairs(Aliases.TABLE) do
    local name = type(to) == 'table' and to[1] or to
    if hSpec[from] == nil then bad[#bad + 1] = from .. ' is not an HGSS command'
    elseif name ~= Aliases.NOOP and type(to) == 'string' and hSpec[from] ~= pSpec[name] then
      bad[#bad + 1] = ('%s %s -> %s %s'):format(from, hSpec[from], name, tostring(pSpec[name]))
    elseif type(to) == 'table' and pSpec[name] and #pSpec[name] ~= #to[2] then
      bad[#bad + 1] = from .. ' reorders to the wrong count for ' .. name
    end
  end
  check(#bad == 0, 'every alias keeps its operand widths: ' .. table.concat(bad, '; '))
end

local s = extract(ss, 'soulsilver')
check(s ~= nil and s.pokemon and s.pokemon[250] and s.pokemon[250].name == 'HO-OH', 'SoulSilver: the core stages run')
local sr30 = s and s.encounters and s.encounters[3] or {}
check(sr30.grass and sr30.grass[1].species == 165 and sr30.grass[2].species == 13,
  "SoulSilver's Route 30: Ledyba, Weedle -- its own encounter file")

-- Platinum back
V.apply('platinum', X.PATH, X.BANK)
check(X.PATH.personal == platinumPersonal and X.BANK.species == 412, "Platinum's paths and banks are put back")

if pret then
  local function bankFirst(n)
    local f = io.open(('%s/files/msgdata/msg/msg_%04d.json'):format(pret, n), 'rb')
    local t = f and f:read('*a') or ''
    if f then f:close() end
    return t
  end
  check(bankFirst(237):find('"BULBASAUR"', 1, true) and bankFirst(751):find('"POUND"', 1, true)
    and bankFirst(222):find('"Master Ball"', 1, true) and bankFirst(730):find('Leader', 1, true),
    "the banks named in Gen4Versions say what they are named for")
end

-- Elm's turntable: the texture edge modes, the starter commands, the screen
do
  local Pack = require('src.import.Gen4ModelPack')
  local hl = Pack.wrapOf({ texImageParam = 0x00000000 })
  local mirrorT = Pack.wrapOf({ texImageParam = 0x000B0000 })
  check(hl and hl[1] == 'clamp' and hl[2] == 'clamp' and Pack.wrapOf({ texImageParam = 0x00030000 }) == nil
    and mirrorT and mirrorT[1] == 'repeat' and mirrorT[2] == 'mirroredrepeat',
    'texture edges: parameter 0 clamps (the ball highlight), 0x3 repeats, 0xB mirrors T')
  local VM = require('src.script.Gen4ScriptVM')
  check(VM.lowered('choosestarter') and VM.lowered('setstarterchoice') and VM.lowered('getstarterchoice'),
    'ChooseStarter, SetStarterChoice and GetStarterChoice lower')
  local closed
  local Screen = require('src.ui.Gen4HgssStarterSelect')
  local fakeGame = { data = { text = {} }, stack = { pop = function() end } }
  local scr = Screen.new(fakeGame, { onCancel = function() closed = true end })
  scr:update()
  check(scr.unavailable and closed, 'a cache without the turntable models closes the screen instead of hanging')
end

-- PlaceStarterBallsInElmsLab: three balls on a new save, two once you have a Pokemon
do
  local Cmd = require('src.script.Commands')
  require('src.script.Gen4Commands')
  local function balls(party)
    local def = {}
    local ctx = { overworld = { map = { def = def } }, save = { flags = {}, party = party }, game = { data = {} } }
    local ok = pcall(Cmd.g4_place_starter_balls, ctx)
    return ok and def.gen4RuntimeProps and #def.gen4RuntimeProps or -1
  end
  local three, two = balls({}), balls({ {} })
  check(three == 3 and two == 2 and require('src.script.Gen4ScriptVM').lowered('placestarterballsinelmslab'),
    ("Elm's machine holds %d balls, then %d with a Pokemon in the party"):format(three, two))
end

-- NameRival: the naming screen's answer becomes the rival's name; empty asks again
do
  local Cmd = require('src.script.Commands')
  local G4 = require('src.script.Gen4Commands')
  local typed, seenTitle
  local real = package.loaded['src.ui.Screens']
  package.loaded['src.ui.Screens'] = { push = function(_, name, opts) seenTitle = opts.title; opts.onDone(typed) end }
  local function run(answer)
    typed = answer
    local save = { vars = {}, player = {} }
    local game = { stack = {}, data = { text = { [require('src.import.Gen4Text').label(249, 3)] = "This boy's name? {YESNO 0}" } } }
    Cmd.g4_name_rival({ save = save, game = game }, 0x800C)
    return save.player.rival, G4.getVar(save, 0x800C)
  end
  local name, ok = run('SILVER')
  local none, again = run('')
  package.loaded['src.ui.Screens'] = real
  check(name == 'SILVER' and ok == 0 and none == nil and again == 1 and seenTitle and not seenTitle:find('YESNO'),
    ('NameRival: "%s" kept (result %s); empty leaves result %s; title "%s"'):format(tostring(name), tostring(ok), tostring(again), tostring(seenTitle)))
end

-- the Pokegear and Mom's savings are save state
do
  local Cmd = require('src.script.Commands')
  local G4 = require('src.script.Gen4Commands')
  local save = { vars = {}, money = 999999 }
  local ctx = { save = save }
  Cmd.g4_pokegear_card(ctx, 2); Cmd.g4_pokegear_card(ctx, 7)
  Cmd.g4_pokegear_number(ctx, 1); Cmd.g4_pokegear_number(ctx, 80)
  Cmd.g4_pokegear_has_number(ctx, 1, 0x8000); local one = G4.getVar(save, 0x8000)
  Cmd.g4_pokegear_has_number(ctx, 80, 0x8000); local eighty = G4.getVar(save, 0x8000)
  Cmd.g4_bank_or_wallet_full(ctx, 1, 0x8001); local wallet = G4.getVar(save, 0x8001)
  Cmd.g4_bank_balance_at_least(ctx, 0x8002, 1); local balance = G4.getVar(save, 0x8002)
  local pg = save.hgssPokegear
  check(pg.cards[2] and pg.cards[0] and not pg.cards[7] and one == 1 and eighty == 0 and wallet == 1 and balance == 0,
    'Pokegear cards (7 becomes 0), phone numbers below 75, a full wallet, an empty savings account')
end

-- Falkner's lift: init puts the platform down; the elevator carries it to 496
do
  local Cmd = require('src.script.Commands')
  local def = {}
  local ctx = { save = {}, overworld = { map = { def = def } } }
  Cmd.g4_violet_gym_init(ctx)
  local down = def.gen4RuntimeProps and def.gen4RuntimeProps[1] and def.gen4RuntimeProps[1].y
  Cmd.g4_violet_gym_elevator(ctx)   -- no runner: lands at once
  local up = def.gen4RuntimeProps[1].y
  check(down == 32 and up == 496 and def.gen4HeightEdits['15,20'] == 496 and ctx.save.hgssGymmick.violetLift == 1,
    ('Violet gym lift: %s down, %s up, the 3 x 3 tiles follow it'):format(tostring(down), tostring(up)))
end

-- Bugsy's carts: four placed; station 0 rides 1to5 to station 4 along the
-- web, ending on (9,24); station 6 has no route until switch 0 is thrown,
-- then goes to 9 (7to10, length 6), and station 7's cart goes to 11 instead
-- of 9; the backward stations run in reverse
do
  local Cmd = require('src.script.Commands')
  local A = require('src.world.HgssAzaleaGym')
  local def = {}
  local ctx = { save = {}, overworld = { map = { def = def } } }
  Cmd.g4_azalea_gym_init(ctx)
  local placed = #(def.gen4RuntimeProps or {}) == 4 and def.gen4RuntimeProps[1].model == 118
                 and def.gen4RuntimeProps[1].x == 3 * 16 + 8 and def.gen4RuntimeProps[1].z == 31 * 16
  local g = ctx.save.hgssGymmick
  local ride = A.ride(g, 0)
  local frames = 0
  repeat frames = frames + 1 until A.step(ride) or frames > 2000
  local landed = ride.x == 9 * 16 and ride.z == 24 * 16 and ride.destination == 4
  local blocked = A.ride({ spiders = { 6 }, switches = 0 }, 6) == nil
  Cmd.g4_azalea_gym_switch(ctx, 0)
  local r6 = A.ride({ spiders = { 6 }, switches = g.switches }, 6)
  local r7 = A.ride(g, 7)
  local back = A.ride({ spiders = { 4 }, switches = 0 }, 4)
  Cmd.g4_azalea_gym_spinarak(ctx, 0)   -- no runner: the cart is moved at once
  check(placed and landed and blocked and g.switches == 1 and r6 and r6.destination == 9 and #r6.nodes == 6
        and r7 and r7.destination == 11
        and back and back.nodes[1].x == 9 and back.nodes[1].z == 24 and back.playerZOffset == 1
        and g.spiders[1] == 4 and def.gen4RuntimeProps[1].x == 9 * 16 + 8,
    ('Azalea gym carts: placed=%s, station 0 lands on station 4 in %d frames (%s at %s,%s), '
     .. 'switch 0 opens 6 -> 9 (blocked before=%s), 7 -> %s, cart 1 now at %s')
      :format(tostring(placed), frames, tostring(landed), tostring(ride.x), tostring(ride.z),
              tostring(blocked), tostring(r7 and r7.destination), tostring(g.spiders[1])))
end

-- the move tutors: 52 rows, Headbutt last at the Ilex Forest man (NPC 3);
-- Bulbasaur can learn it from him, Caterpie cannot
do
  local T = require('src.import.Gen4MoveTutor')
  local rec = h and h.gen4_move_tutor
  local last = rec and rec.moves[52]
  local bulba = rec and #T.learnable(rec, { species = 1, moves = {} }, 3)
  local cater = rec and #T.learnable(rec, { species = 10, moves = {} }, 3)
  check(rec and #rec.moves == 52 and last.move == 29 and last.location == 3 and rec.moves[1].move == 291
        and bulba == 1 and cater == 0,
    ('HGSS move tutors (sTutorMoves + waza_oshie.bin): Headbutt at NPC 3; Bulbasaur %s, Caterpie %s')
      :format(tostring(bulba), tostring(cater)))
end

-- Apricorns: all 31 trees carry their index; Route 29's is green; a shake
-- empties it until tomorrow; 99 caps the box; Kurt turns Blue into Lure
do
  local A = require('src.world.HgssApricorns')
  local Cmd = require('src.script.Commands')
  local G4 = require('src.script.Gen4Commands')
  local trees, r29 = {}, nil
  for id, m in pairs((h and h.maps) or {}) do
    for _, o in ipairs(m.objects or {}) do
      if o.apricornTree then trees[o.apricornTree] = true; if id == 'R29' then r29 = o.apricornTree end end
    end
  end
  local n = 0 for _ in pairs(trees) do n = n + 1 end
  local save = { vars = {}, inventory = {} }
  local ctx = { save = save, npc = { def = { apricornTree = r29 } } }
  Cmd.g4_apricorn_tree_shake(ctx, 0x8000); local first = G4.getVar(save, 0x8000)
  Cmd.g4_apricorn_tree_shake(ctx, 0x8000); local second = G4.getVar(save, 0x8000)
  Cmd.g4_apricorn_tree_colour(ctx, 0x8001); local colour = G4.getVar(save, 0x8001)
  local tomorrow = A.treeHasFruit(save, r29, os.time() + 86400)
  Cmd.g4_apricorn_give(ctx, colour, 1, 0x8002); local given = G4.getVar(save, 0x8002)
  A.give(save, 2, 98)
  Cmd.g4_apricorn_give(ctx, 2, 2, 0x8003); local refused = G4.getVar(save, 0x8003)
  A.setKurt(save, 2, 3)
  Cmd.g4_kurt_quantity(ctx, 0x8004); Cmd.g4_kurt_ball(ctx, 0x8005)
  local qty, ball, left = G4.getVar(save, 0x8004), G4.getVar(save, 0x8005), A.count(save, 2)
  check(n == 31 and r29 == 5 and first == 1 and second == 0 and colour == 3 and tomorrow and given == 1
        and refused == 0 and qty == 3 and ball == 494 and left == 95,
    ('Apricorns: %d trees, Route 29 #%s green (%s), shaken %s then %s, box caps at 99, Kurt: %s Blue -> ball %s')
      :format(n, tostring(r29), tostring(colour), tostring(first), tostring(second), tostring(qty), tostring(ball)))
end

-- ScreenShake 0, 2, 10, 5 (Ilex Forest): 50 frames, vertical only, at most
-- 2 units, the offset gone at the end
do
  local Cmd = require('src.script.Commands')
  local ow = {}
  local runner = { yield = function() end }
  Cmd.g4_screen_shake({ save = {}, overworld = ow, runner = runner }, 0, 2, 10, 5)
  local frames, peak, sideways = 0, 0, 0
  repeat
    frames = frames + 1
    local done = runner.waitingCheck()
    local o = ow.gen4ShakeOffset
    if o then peak = math.max(peak, math.abs(o[2])); sideways = math.max(sideways, math.abs(o[1])) end
  until done or frames > 500
  check(frames == 50 and peak > 1.8 and peak <= 2 and sideways == 0 and ow.gen4ShakeOffset == nil,
    ('ScreenShake 0,2,10,5: %d frames, peak %.2f, cleared after'):format(frames, peak))
end

-- Battle outcomes as HGSS scripts read them (battle_setup.c): CheckBattleWon
-- is "not lost or drawn", so a caught or fled-from Sudowoodo is no white-out;
-- GetStaticEncounterOutcome is the code; StaticWildWonOrCaughtCheck is TRUE
-- unless it was beaten or caught. And the dept. store's floor names.
do
  local Cmd = require('src.script.Commands')
  local G4 = require('src.script.Gen4Commands')
  local Bands = require('src.import.Gen4ScriptBands')
  local was = Bands.family
  Bands.family = 'hgss'
  local function run(result)
    local save = { vars = {} }
    local ctx = { save = save, lastBattleResult = result }
    Cmd.g4_check_won_battle(ctx, 0x8000)
    Cmd.g4_static_outcome(ctx, 0x8001)
    Cmd.g4_static_not_won(ctx, 0x8002)
    return G4.getVar(save, 0x8000), G4.getVar(save, 0x8001), G4.getVar(save, 0x8002)
  end
  local cw, co, cn = run('caught')
  local rw, ro, rn = run('run')
  local lw, lo, ln = run('lose')
  local ww, wo, wn = run('win')
  local VM = require('src.script.Gen4ScriptVM')
  local hgss = Bands.family == 'hgss'
  Bands.family = was
  check(hgss and cw == 1 and co == 4 and cn == 0 and rw == 1 and ro == 5 and rn == 1
        and lw == 0 and lo == 2 and ln == 1 and ww == 1 and wo == 1 and wn == 0
        and VM.lowered('bufferdeptstorefloorno') and VM.lowered('getstaticencounteroutcome'),
    ('HGSS battle outcomes: caught %d/%d/%d, fled %d/%d/%d, lost %d/%d/%d, won %d/%d/%d')
      :format(cw, co, cn, rw, ro, rn, lw, lo, ln, ww, wo, wn))
end

-- Morty's gym: init fogs the room to black and puts model 128 on the four
-- mediums (objects 2..5); beating one (no runner: at once) puts hers out and
-- leaves three; the lights' material is out of the fog (polyAttr bit 15)
do
  local Cmd = require('src.script.Commands')
  local E = require('src.world.HgssEcruteakGym')
  local def = {}
  local function npc(id, x, y) return { def = { localId = id }, px = x * 16, py = y * 16 } end
  local mediums = { npc(2, 17, 39), npc(3, 19, 30), npc(4, 9, 29), npc(5, 11, 19), npc(6, 16, 49) }
  local ow = { map = { def = def }, npcs = mediums }
  local save = { vars = {} }
  local Game = require('src.core.Game')
  local savedSave = Game.save
  Game.save = save
  Cmd.g4_ecruteak_gym_init({ save = save, overworld = ow })
  local lit = #(def.gen4RuntimeProps or {})
  local first = def.gen4RuntimeProps and def.gen4RuntimeProps[1]
  Cmd.g4_ecruteak_candle_out({ save = save, overworld = ow, npc = mediums[1] })
  local after = #(def.gen4RuntimeProps or {})
  Game.save = savedSave
  local models = h and h.gen4_models
  local spot = models and models.sets and models.sets.interiorBuildings
               and models.sets.interiorBuildings.models[129]
  check(def.gen4Fog and def.gen4Fog[1] == 0 and lit == 4 and first.model == 128 and first.x == 17 * 16 + 8
        and after == 3 and save.hgssGymmick.candles[1] == true and type(def.gen4PropFollow) == 'function'
        and spot and spot.shapes[1].noFog == true,
    ('Morty gym: fog, %d lights then %d, candle 1 out, light model out of the fog (%s)')
      :format(lit, after, tostring(spot and spot.shapes[1].noFog)))
end

-- HGSS's roamers on Platinum's rules: CreateRoamer 0 / 1 release Raikou and
-- Entei at 40; over 200 moves neither leaves Johto's 16 routes; a long hop
-- for Latias stays in Kanto; met one in two on its map
do
  local Bands = require('src.import.Gen4ScriptBands')
  local was = Bands.family
  Bands.family = 'hgss'
  local R = require('src.world.Gen4Roamers')
  local data = { maps = (h and h.maps) or {} }
  local save = {}
  local seed = 1
  local function rng(a, b) seed = (seed * 1103515245 + 12345) % 2147483648; return a + seed % (b - a + 1) end
  local raikou = R.activate(data, save, 0, rng)
  R.activate(data, save, 1, rng)
  local johto = {}
  for i = 0, 15 do johto[R.mapOf(data, i)] = true end
  local stayed = true
  for _ = 1, 200 do
    R.noteMap(save, 'T20')
    R.moveAll(data, save, rng)
    for slot = 0, 1 do if not johto[R.active(save, slot).map] then stayed = false end end
  end
  R.activate(data, save, 2, rng)
  local latias = R.active(save, 2)
  local kanto = (R.ROUTES[latias.route] and latias.route >= 16)
  local met, tries = 0, 400
  local where = R.active(save, 0).map
  for _ = 1, tries do if R.check(data, save, where, math.random) then met = met + 1 end end
  local one = R.encounterFor(0, R.active(save, 0))
  check(raikou and raikou.species == 243 and raikou.level == 40 and stayed and kanto
        and met > tries * 0.3 and one and one.species == 243 and R.SLOT_COUNT == 4 and R.ROUTE_COUNT == 41,
    ('HGSS roamers: Raikou %s, stayed in Johto %s, Latias in Kanto %s (route %s), met %d / %d')
      :format(tostring(raikou and raikou.map), tostring(stayed), tostring(kanto), tostring(latias.route), met, tries))
  Bands.family = was
  R.useFamily()
end

-- Loan Pokemon: Shuckie (trade 6) joins at 20; giving him back is refused
-- while he holds an item (2) or is the last able one (4), refused for
-- someone else's Pokemon (1), allowed otherwise (0); Kenya carries its mail.
-- And Chuck's winch turns once.
do
  local Cmd = require('src.script.Commands')
  local G4 = require('src.script.Gen4Commands')
  local data = { constants = { gen4Trades = h and h.constants and h.constants.gen4Trades },
                 pokemon = h and h.pokemon, moves = h and h.moves }
  local save = { vars = {}, party = {} }
  local ctx = { save = save, game = { data = data } }
  -- the raw cache's species records lack what Data.lua adds at load, so a
  -- minimal Pokemon stands in (the harness gives the real one)
  local P = require('src.pokemon.Pokemon')
  local realNew = P.new
  P.new = function(_, species, level) return { species = species, level = level, hp = 50, moves = {} } end
  Cmd.g4_give_loan_mon(ctx, 6, 20, 75)
  local shuckie = save.party[1]
  Cmd.g4_check_return_loan_mon(ctx, 6, 0, 0x8000); local alone = G4.getVar(save, 0x8000)
  Cmd.g4_give_loan_mon(ctx, 7, 20, 101)
  local kenya = save.party[2]
  Cmd.g4_kenya_mail(ctx, 0x8001); local mail = G4.getVar(save, 0x8001)
  shuckie.item = 1
  Cmd.g4_check_return_loan_mon(ctx, 6, 0, 0x8000); local holding = G4.getVar(save, 0x8000)
  shuckie.item = nil
  Cmd.g4_check_return_loan_mon(ctx, 6, 1, 0x8000); local wrong = G4.getVar(save, 0x8000)
  Cmd.g4_check_return_loan_mon(ctx, 6, 0, 0x8000); local fine = G4.getVar(save, 0x8000)
  Cmd.g4_return_loan_mon(ctx, 0)
  P.new = realNew
  Cmd.g4_cianwood_gym_init(ctx)
  Cmd.g4_cianwood_turn_winch(ctx, 0x8002); local first = G4.getVar(save, 0x8002)
  Cmd.g4_cianwood_turn_winch(ctx, 0x8002); local again = G4.getVar(save, 0x8002)
  check(shuckie and shuckie.species == 213 and shuckie.level == 20 and alone == 4 and holding == 2
        and wrong == 1 and fine == 0 and #save.party == 1 and save.party[1] == kenya
        and kenya.species == 21 and mail == 1 and first == 1 and again == 0,
    ('Loans: Shuckie %s L%s, return answers %s/%s/%s/%s, Kenya %s mail %s; winch %s then %s')
      :format(tostring(shuckie and shuckie.species), tostring(shuckie and shuckie.level), tostring(alone),
              tostring(holding), tostring(wrong), tostring(fine), tostring(kenya and kenya.species),
              tostring(mail), tostring(first), tostring(again)))
end

-- The Rocket disguise (PLAYER_TRANSITION_ROCKET, 1 << 10) goes on and comes
-- off with the avatar bits and re-dresses the player; the hideout's
-- commands lower (traps, the tag battle beside Lance, ScrCmd_530's magic)
do
  local Bands = require('src.import.Gen4ScriptBands')
  local was = Bands.family
  Bands.family = 'hgss'
  local Cmd = require('src.script.Commands')
  local G4 = require('src.script.Gen4Commands')
  local VM = require('src.script.Gen4ScriptVM')
  local refreshed = 0
  local player = { refreshForm = function() refreshed = refreshed + 1 end }
  local save = { vars = {} }
  local ctx = { save = save, overworld = { player = player }, game = { data = {} } }
  Cmd.g4_player_state(ctx, 1024); local on = save.hgssRocketCostume
  Cmd.g4_rocket_costume_flag(ctx, 1); Cmd.g4_rocket_costume_check(ctx, 0x8000)
  local flag = G4.getVar(save, 0x8000)
  Cmd.g4_player_state(ctx, 1); local off = save.hgssRocketCostume
  Bands.family = was
  check(on == true and off == nil and refreshed == 2 and flag == 1
        and VM.lowered('rockettrapbattle') and VM.lowered('multibattle') and VM.lowered('moveperson')
        and VM.lowered('scrcmd_530') and VM.lowered('setavatarbits') and VM.lowered('createroamer')
        and VM.lowered('hofcredits') and VM.lowered('halloffameanim'),
    ('Rocket disguise on %s off %s (re-dressed %d), costume flag %d; hideout and Hall of Fame commands lowered')
      :format(tostring(on), tostring(off), refreshed, flag))
end

-- Clair's platforms (blackthorn.c): on open magma the centre button turns
-- platform 1 a quarter in 16 frames and the side button carries it, and the
-- player, its width (5 tiles) in 10; a wall in the way bonks the move back
-- where it started; the floor is walkable and bare magma is not
do
  local B = require('src.world.HgssBlackthornGym')
  local function world(wallX)
    local map = { def = {} }
    function map:cellBehaviour(x, z) return (wallX and x >= wallX) and 0 or 0x2C end
    function map:cellCollision() return 0 end
    local p = { cellX = 13, cellY = 75, px = 13 * 16, py = 75 * 16 }
    return { map = map, player = p }, map, p
  end
  local ow, map, p = world(nil)
  local save = {}
  B.attach(ow, save)
  local started = map.def.gen4StepHook(ow, 13, 75)
  for _ = 1, 20 do map.def.gen4PropFollow(ow) end
  local turned = save.hgssGymmick.rot[1]
  -- now rotated once (rot 1): the "right" button is (13, 76) and moves +z
  p.cellX, p.cellY, p.px, p.py = 13, 76, 13 * 16, 76 * 16
  map.def.gen4StepHook(ow, 13, 76)
  for _ = 1, 30 do map.def.gen4PropFollow(ow) end
  local movedZ, playerZ = save.hgssGymmick.z[1], p.cellY
  local floorOk = map.def.gen4CollisionHook(map, 13, 80 + 1) == false
  local magmaBlocks = map.def.gen4CollisionHook(map, 30, 10) == true
  -- a wall two tiles east: the east button bonks and the platform stays
  local ow2, map2, p2 = world(17)
  local save2 = {}
  B.attach(ow2, save2)
  p2.cellX, p2.px = 14, 14 * 16
  map2.def.gen4StepHook(ow2, 14, 75)
  for _ = 1, 30 do map2.def.gen4PropFollow(ow2) end
  check(started and turned == 1 and movedZ == 80 and playerZ == 81 and floorOk and magmaBlocks
        and save2.hgssGymmick.x[1] == 13 and p2.cellX == 14 and p2.inputLocked == nil
        and #map.def.gen4RuntimeProps == 3 and map.def.gen4RuntimeProps[1].ground == true,
    ('Blackthorn platforms: turned to %s, moved to z %s carrying the player to %s, bonk kept x %s')
      :format(tostring(turned), tostring(movedZ), tostring(playerZ), tostring(save2.hgssGymmick.x[1])))
end

-- Lt. Surge's cans: the second switch is a neighbour of the first; the can
-- check answers 1/0, then 2/3 with gate 1 open, then 4 with both; Fuchsia,
-- Viridian, the Cycling Road lock and the Latias/Latios picture lower
do
  local Cmd = require('src.script.Commands')
  local G4 = require('src.script.Gen4Commands')
  local VM = require('src.script.Gen4ScriptVM')
  local save = { vars = {} }
  local ctx = { save = save, game = { data = {} } }
  local neighbourOk = true
  for _ = 1, 50 do
    Cmd.g4_vermilion_resample(ctx)
    local g = save.hgssGymmick
    local okN = false
    for _, n in ipairs(G4.VERMILION_CAN_NEIGHBOURS[g.switches[1]]) do if n == g.switches[2] then okN = true end end
    if not okN then neighbourOk = false end
  end
  local g = save.hgssGymmick
  local first, second = g.switches[1], g.switches[2]
  local wrong = (first + 1) % 15
  if wrong == second then wrong = (wrong + 1) % 15 end
  local function ask(can) Cmd.g4_vermilion_can_check(ctx, can, 0x8000); return G4.getVar(save, 0x8000) end
  local a1, a0 = ask(first), ask(wrong)
  Cmd.g4_vermilion_lock_action(ctx, 0, 0)
  local b2, b3 = ask(second), ask(first)
  Cmd.g4_vermilion_lock_action(ctx, 1, 0)
  local c4 = ask(first)
  check(neighbourOk and a1 == 1 and a0 == 0 and b2 == 2 and b3 == 3 and c4 == 4
        and VM.lowered('fuchsiagyminit') and VM.lowered('viridiangyminit') and VM.lowered('setbikestatelock')
        and VM.lowered('scrcmd_452') and VM.lowered('resamplevermiliongymcans'),
    ('Vermilion cans: answers %s/%s, then %s/%s, then %s; switch pairs neighbours %s')
      :format(a1, a0, b2, b3, c4, tostring(neighbourOk)))
end

do
  local V=require('src.core.GameVersion');local previous=V.get();V.set('soulsilver')
  local Alias=require('src.import.Gen4HgssScriptAliases')
  local VM=require('src.script.Gen4ScriptVM')
  local G4=require('src.script.Gen4Commands')
  local Cmd=require('src.script.Commands')
  local ctx={save={party={{species=152,hp=20}},hgssFollowMon={paused=true}}}
  Cmd.g4_release_all(ctx)
  check(not ctx.save.hgssFollowMon.paused,'ReleaseAll unpauses Elm starter follower')
  Cmd.g4_party_pokerus(ctx,0x8006)
  check(G4.getVar(ctx.save,0x8006)==0,'fresh starter does not trigger Pokerus dialogue')
  ctx.save.party[1].pokerus=0x21;Cmd.g4_party_pokerus(ctx,0x8006)
  check(G4.getVar(ctx.save,0x8006)==1,'infected party still triggers ROM Pokerus branch')
  for _,name in ipairs({'martbuy','partyhaspokerus','pokecenanim','gettrcardstars','scrcmd_158'}) do
    local ins={name=name,args={0x8006}};Alias.apply(ins)
    local rows=VM.lower({ins})
    check(rows[1] and rows[1][1]~='g4_unimplemented','HGSS service dispatch '..name)
  end
  local TS=require('src.world.Gen4TileScripts')
  local value=require('src.import.Gen4Behaviors').matching('^PC$')[1]
  local pc=TS.rowFor(value,'up')
  check(pc and pc.band=='common_scripts' and pc.index==10,'HGSS PC selects std_pokecenter_pc 2010')
  local Shop=require('src.ui.Gen4ShopMenu')
  local shop=Shop.new({data={text=h.text},save={money=3000}},{4,17})
  check(shop.mode=='buy' and shop.direct,'HGSS MartBuy opens the purchase list directly')
  local price=shop:line(9,'missing','200')
  check(price:find('200',1,true) and not price:find('anything',1,true),'HGSS shop prices use bank 435 entry 18')
  local Gear=require('src.ui.HgssPokegear')
  local gear=Gear.new({save={hgssPokegear={cards={}}},data={}},{})
  check(gear:canPage(2) and not gear:canPage(1) and not gear:canPage(3),'Pokegear gates map and radio cards')
  local Screen=require('src.ui.Gen4HgssStarterSelect')
  local SS=require('src.ui.SecondScreen');local draw=SS.draw
  local top,bottom=0,0
  local game={data={isGen4Cache=true},save={options={secondScreenMode='vertical'}}}
  local screen=setmetatable({game=game,state='inspect',drawPreview=function() top=top+1 end,
    drawTurntable=function() bottom=bottom+1 end},Screen)
  SS.draw=function(_,body) body() end
  screen:draw()
  check(top==1 and bottom==1,'dual-screen starter renders preview and turntable')
  game.save.options.secondScreenMode='swap';screen:draw()
  check(top==2 and bottom==1,'single-screen starter shows full Pokemon preview')
  SS.draw=draw;V.set(previous)
end

do
  local art=h.gen4_hgss_oak_art
  local title=h.gen4_hgss_title_art
  check(title and title.heartgold_logo and title.soulsilver_logo and title.prompt:find('START',1,true),
    'HGSS title imports both native logos and the cartridge start prompt')
  check(h.field.boot.screens.title=='HgssTitle' and h.field.boot.screens.newGame=='HgssOakIntro',
    'HGSS boot routes to its own title and professor screens')
  local titleSet=((h.gen4_models or {}).sets or {}).hgssTitle
  local named={}
  for _,record in ipairs(titleSet and titleSet.models or {}) do named[record.name]=record end
  check(named.houou_test and named.lugia01_10t and named.houou_efct and named.lugia_efct,
    'HGSS title imports Ho-Oh, Lugia and their native effects')
  check(named.houou_test and named.houou_test.inverseBind and named.houou_test.scalingRule==1,
    'Ho-Oh cache retains native Maya scaling and envelope matrices')
  check(art and art.oak and art.gender and art.boy_cursor and art.girl_cursor
    and art.sequences[1][1].scaleX~=nil,'Oak art includes gender avatars and native Marill SRT frames')
  check(art and art.text[6]:find('Oak',1,true) and art.text[43]:find('adventure',1,true),
    'Oak introduction uses HGSS bank 219')
  local boot=h.gen4_hgss_boot_art
  check(boot and boot.copyright_top and boot.copyright_bottom and boot.studio_top and boot.studio_bottom,
    'HGSS opening credits import both physical DS panels')
  local Intro=require('src.ui.HgssIntro')
  local stopped=0
  local intro=Intro.new({data={gen4_hgss_boot_art=boot},stack={pop=function() stopped=stopped+1 end},
    input={wasPressed=function(_,key) return key=='a' end}})
  for tick=1,109 do intro:update(1/30) end
  check(stopped==0,'HGSS copyright cannot be skipped before the native 110-frame gate')
  intro:update(1/30)
  check(stopped==1,'HGSS studio credit accepts A once skipping is allowed')
  local Oak=require('src.ui.HgssOakIntro')
  local Screens=require('src.ui.Screens');local push=Screens.push
  local refresh,pops,done,naming=0,0,0,0
  local game={data={gen4_hgss_oak_art=art,constants={}},
    save={player={name='Old',rival='Silver'},options={secondScreenMode='swap'}},
    stack={pop=function() pops=pops+1 end},input={wasPressed=function() return false end},
    overworld={player={refreshForm=function() refresh=refresh+1 end}}}
  Screens.push=function(_,id,opts)
    check(id=='NamingScreen' and opts.female,'Oak opens native naming screen for chosen gender')
    naming=naming+1;opts.onDone('Lyra')
  end
  local screen=Oak.new(game,function() done=done+1 end)
  screen:enter();screen.choice=3;screen:advance()
  for n=1,60 do if screen.phase=='gender' then break end
    if screen.phase=='release' then for j=1,90 do screen:update(1/30) end else screen:advance() end
  end
  check(screen.phase=='gender','Oak main path reaches gender selection without skipping dialogue')
  screen.choice=2;screen:advance()
  screen.choice=2;screen:advance()
  check(screen.phase=='genderQuestion','declining gender returns to the ROM gender question')
  for n=1,10 do if screen.phase=='gender' then break end;screen:advance() end
  screen.choice=2;screen:advance()
  for n=1,10 do if screen.phase=='name' then break end;screen:advance() end
  screen:advance()
  check(naming==1 and game.save.player.name=='Lyra' and game.save.player.gender=='girl'
    and refresh==1 and game.save.player.rival=='Silver','Oak saves gender/name and refreshes avatar without renaming rival')
  for n=1,30 do if screen.phase=='shrink' then break end;screen:advance() end
  for n=1,75 do screen:update(1/30) end
  check(done==1 and pops==1,'Oak shrink animation finishes New Game exactly once')
  local SS=require('src.ui.SecondScreen');local draw=SS.draw;local panels={}
  SS.draw=function(_,body) body() end
  screen=Oak.new(game);screen:enter();screen.panel=function(_,sub) panels[#panels+1]=sub end
  screen:draw();check(panels[1]==true,'single-screen Oak exposes tutorial choices automatically')
  screen.bottom=false;screen:draw();check(panels[2]==false,'single-screen Oak can also show the dialogue panel')
  game.data.isGen4Cache=true;game.save.options.secondScreenMode='vertical';screen:draw()
  check(panels[3]==false and panels[4]==true,'dual-screen Oak renders both panels')
  SS.draw=draw;Screens.push=push
end

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
