-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- HEARTGOLD / SOULSILVER'S SMALL FIELD QUERIES: commands that answer into a
-- var, which were unlowered -- and an unlowered var-writer is the dangerous
-- kind, because the script goes on to compare a var nothing wrote.
--
-- Most are Platinum's commands under HGSS's own names and operand orders
-- (pokeheartgold src/field/scrcmd_*.c), lowered onto the rows Platinum's
-- already use:
--
--   CountFossils <dest>                         -> g4_fossil_count
--   GetFossilMinimumAmount <item, index, need>  -> g4_fossil_at_threshold
--   GetEVTotal <dest, slot>                     -> g4_mon_ev_total
--   GetHiddenPowerType <slot, dest>             -> g4_hidden_power_type
--   GetUniqueSealsQuantity <dest>               -> g4_count_unique_seals
--   MonGetMove <dest, slot, moveSlot>           -> g4_mon_move
--   CountPartyMonsOfSpecies <dest, species>     -> g4_count_repeated_species
--     (species 0: 1 if any two share a species -- Platinum's same rule)
--   PartyCountMonsAtOrBelowLevel <dest, level>  -> g4_party_below_level
--
-- and these are HGSS's own (rows below):
--
--   MonGetGender <slot, dest>                   MON_DATA_GENDER: 0 / 1 / 2
--   GetPartySlotWithSpecies <dest, species>     the first non-egg, else 255
--   PartyMonIsMine <slotVar, dest>              TRUE when the OT id DIFFERS
--     (the name reads backwards; the cartridge's comparison is quoted as is)
--   KenyaCheck <dest, slot, compare>            the mon holds mail; with
--     `compare` 1, it is the Route 35 man's (Mail_Compare)
--   LatiCaughtCheck <dest>                      FALSE only when the last
--     battle ended MON_CAUGHT (IsBattleResultLatiCaught)
--   RadioMusicIsPlaying <seq, dest>             GetRadioMusicPlayingSeq == seq
--     (src/world/HgssRadioMusic.lua): Snorlax's Poke Flute
--   GetShinyLeafCount <slot, dest>              the five leaves, 6 with the
--     crown; TryGiveShinyLeafCrown <slot> crowns five
--   CheckKyogreGroudonInParty <dest>            a Kyogre met in HeartGold (7)
--     and a Groudon met in SoulSilver (8), neither from an egg
--   LotoIDGet / LotoIDSearch / LotoIDSet        the Lucky Number Show
--
-- Loaded by Gen4ScriptVM (`install` with the lowering table).

local okCommands, Commands = pcall(require, "src.script.Commands")
if not okCommands then Commands = {} end

local M = {}

local function G4() return require("src.script.Gen4Commands") end
local function valueOf(ctx, n) return math.floor(tonumber(G4().valueOf(ctx, n)) or 0) end
local function setVar(ctx, id, v) G4().setVar(ctx.save, id, v) end
local function party(ctx) return (ctx.save and ctx.save.party) or {} end
local function mon(ctx, slot) return party(ctx)[valueOf(ctx, slot) + 1] end
local function species(m)
  local id = m and m.species
  return tonumber(id) or tonumber(tostring(id or ""):match("(%d+)%s*$")) or 0
end

-- MON_DATA_GENDER: 0 male, 1 female, 2 genderless (the stored answer when
-- the mon carries one, else the personality against the species' ratio)
local GENDER = { male = 0, female = 1, none = 2, genderless = 2 }
function M.gender(data, m)
  if not m then return 0 end
  local g = m.gender
  if type(g) == "number" then return g end
  if type(g) == "string" and GENDER[g] then return GENDER[g] end
  local ok, which = pcall(require("src.pokemon.Gen4DayCare").gender, data, m)
  return ok and GENDER[which] or 0
end

function Commands.g4_hgss_mon_gender(ctx, slot, destVar)
  setVar(ctx, destVar, M.gender(ctx.game and ctx.game.data, mon(ctx, slot)))
end

function Commands.g4_hgss_slot_with_species(ctx, destVar, sp)
  local want = valueOf(ctx, sp)
  local slot = 255
  for i, m in ipairs(party(ctx)) do
    if not m.isEgg and species(m) == want then slot = i - 1 break end
  end
  setVar(ctx, destVar, slot)
end

function Commands.g4_hgss_mon_is_mine(ctx, slotVar, destVar)
  local m = party(ctx)[math.floor(tonumber(G4().getVar(ctx.save, slotVar)) or 0) + 1]
  local player = ctx.save and ctx.save.player or {}
  local mine = math.floor(tonumber(player.id or player.trainerId) or 0) % 0x10000
  local ot = m and math.floor(tonumber(m.otId) or mine) % 0x10000 or mine
  setVar(ctx, destVar, (ot == mine) and 0 or 1)
end

-- ItemIdIsMail: ITEM_GRASS_MAIL (137) .. ITEM_BRICK_MAIL (148)
-- held items come as ids or as the bag's "ITEM_%03d" keys (givepokemon's heldItem)
local function isMail(id)
  id = tonumber(id) or tonumber(tostring(id or ""):match("(%d+)%s*$"))
  return id ~= nil and id >= 137 and id <= 148
end
function Commands.g4_hgss_kenya_check(ctx, destVar, slot, compare)
  local m = mon(ctx, slot)
  if not (m and isMail(m.item or m.heldItem)) then setVar(ctx, destVar, 0) return end
  if (tonumber(compare) or 0) == 0 then setVar(ctx, destVar, 1) return end
  setVar(ctx, destVar, m.kenyaMail and 1 or 0)
end

-- MonGiveMail <slot> (scrcmd_party.c): the mail a Pokemon holds is taken --
-- a blank Mail_Init over MON_DATA_MAIL and no held item (Kenya's delivery)
function Commands.g4_hgss_take_mail(ctx, slot)
  local m = mon(ctx, slot)
  if not (m and isMail(m.item or m.heldItem)) then return end
  m.item, m.heldItem, m.mail, m.kenyaMail = nil, nil, nil, nil
end

-- StatJudge <slot, total, best, bestIv> (scrcmd_pokemon_misc.c): the IV total,
-- the highest IV, and which stat holds it -- searched from where the last
-- judgement left off (fieldSystem->judgeStatPosition, kept for the session),
-- answered as the judge's line for it (D31R0201 #122-127)
M.STAT_JUDGE_LINES = { [0] = 122, 123, 124, 127, 125, 126 }
function Commands.g4_hgss_stat_judge(ctx, slot, totalVar, bestVar, ivVar)
  local m = mon(ctx, slot)
  local ivs = (m and m.ivs) or {}
  local list = {}
  local total, high = 0, 0
  for i, key in ipairs({ "hp", "attack", "defense", "speed", "spatk", "spdef" }) do
    list[i - 1] = tonumber(ivs[key]) or 0
    total = total + list[i - 1]
    if list[i - 1] > high then high = list[i - 1] end
  end
  local game = ctx.game or {}
  local offset = tonumber(game.gen4JudgeStatPosition) or 0
  local best = offset
  for _ = 1, 6 do
    if list[offset] == high then
      best = offset
      game.gen4JudgeStatPosition = (offset + 1) % 6
      break
    end
    offset = (offset + 1) % 6
  end
  setVar(ctx, totalVar, total)
  setVar(ctx, bestVar, M.STAT_JUDGE_LINES[best])
  setVar(ctx, ivVar, high)
end

function Commands.g4_hgss_lati_caught(ctx, destVar)
  setVar(ctx, destVar, (ctx.lastBattleResult == "caught") and 0 or 1)
end

function Commands.g4_hgss_radio_music(ctx, seq, destVar)
  local now = require("src.world.HgssRadioMusic").current(ctx.game)
  setVar(ctx, destVar, (now == valueOf(ctx, seq)) and 1 or 0)
end

-- MonGetShinyLeafCount: MON_DATA_SHINY_LEAF_A..E, and 6 for five with the crown
function M.shinyLeaves(m)
  if not m then return 0 end
  local n = 0
  for i = 1, 5 do
    local leaf = type(m.shinyLeaves) == "table" and m.shinyLeaves[i]
    if leaf == true or (tonumber(leaf) or 0) ~= 0 then n = n + 1 end
  end
  if n == 5 and m.shinyLeafCrown then n = 6 end
  return n
end
function Commands.g4_hgss_shiny_leaves(ctx, slot, destVar)
  setVar(ctx, destVar, M.shinyLeaves(mon(ctx, slot)))
end
function Commands.g4_hgss_shiny_leaf_crown(ctx, slot)
  local m = mon(ctx, slot)
  if m and M.shinyLeaves(m) == 5 then m.shinyLeafCrown = true end
end

-- MON_DATA_MET_GAME: the port keeps `origin` (a version name) on mons it
-- builds; HeartGold is 7 and SoulSilver 8
local GAME_ID = { heartgold = 7, soulsilver = 8 }
local function metGame(ctx, m)
  local g = m.metGame or m.originGame
  if type(g) == "number" then return g end
  local o = m.origin or g
  if type(o) == "string" then return GAME_ID[o:lower()] or 0 end
  -- caught here: this cartridge
  local v = ctx.game and ctx.game.data and ctx.game.data.gen4_version
  local name = type(v) == "table" and (v.version or v.id) or v
  return type(name) == "string" and GAME_ID[name:lower()] or 0
end
function Commands.g4_hgss_kyogre_groudon(ctx, destVar)
  local kyogre, groudon = false, false
  for _, m in ipairs(party(ctx)) do
    if not m.isEgg and not m.eggLocation then
      local sp, g = species(m), metGame(ctx, m)
      if sp == 382 and g == 7 then kyogre = true end
      if sp == 383 and g == 8 then groudon = true end
    end
  end
  setVar(ctx, destVar, (kyogre and groudon) and 1 or 0)
end

-- LotoIDSet (ScrCmd_LotoIDSet -> Save_VarsFlags_RollLotoId): two LCRandom
-- halves, the high one landing in VAR_LOTO_NUMBER_LO (the SetLotoId slip)
function Commands.g4_hgss_loto_roll(ctx)
  local r = love and love.math and love.math.random(0, 65535) or math.random(0, 65535)
  setVar(ctx, 0x403C, r)
end

-- BufferPartyMonSpeciesNameIndef <slot, partySlot>: that mon's species,
-- with its article
function Commands.g4_hgss_buffer_party_species_article(ctx, slot, partySlot)
  local m = mon(ctx, partySlot)
  if Commands.g4_buffer then Commands.g4_buffer(ctx, slot, "speciesArticle", m and species(m) or 0) end
end

-- MonForgetMove <slot, moveSlot> (MonDeleteMoveSlot): the move goes and the
-- ones after it move up
function Commands.g4_hgss_forget_move(ctx, slot, moveSlot)
  local m = mon(ctx, slot)
  local i = valueOf(ctx, moveSlot) + 1
  if m and type(m.moves) == "table" and m.moves[i] then table.remove(m.moves, i) end
end

-- ScrCmd_395 <dest>: the move picked on ScrCmd_394's summary screen
-- (LearnForgetMove_LaunchApp with no move to learn), Cancel's 4 as 255
function Commands.g4_hgss_forget_pick(ctx, destVar)
  local v = ctx.g4TutorForget or 4
  setVar(ctx, destVar, v == 4 and 255 or v)
end

-- CheckCoinsImmediate <dest, u32 amount>: the amount is a LITERAL word (a
-- var-reading valueOf would take 16384+ for a var id)
function Commands.g4_hgss_coins_at_least(ctx, destVar, amount)
  local okGC, GC = pcall(require, "src.import.Gen4GameCorner")
  local coins = okGC and GC.coins and GC.coins(ctx.save) or tonumber(ctx.save and ctx.save.coins) or 0
  setVar(ctx, destVar, coins >= (tonumber(amount) or 0) and 1 or 0)
end

-- SetTrainerHouseSprite <n, hasTrainerVar>: the Trainer House's record-mixed
-- sets; this port mixes no records, so every set is empty -- no trainer, and
-- VAR_OBJ_1 + n (the sprite the room shows) 0
function Commands.g4_hgss_trainer_house_sprite(ctx, n, destVar)
  setVar(ctx, destVar, 0)
  setVar(ctx, 0x4021 + valueOf(ctx, n), 0)
end

-- a var set to a number as written: g4_set_var reads 0x4000+ as a var id
function Commands.g4_hgss_set_literal(ctx, destVar, value)
  setVar(ctx, destVar, tonumber(value) or 0)
end

-- OpenAlphHiddenRoom <n>: the Ruins of Alph wall panel and its inscription
-- (src/ui/HgssAlphInscription.lua), held until A
function Commands.g4_hgss_alph_inscription(ctx, index)
  local game = ctx.game
  if not (game and game.stack) then return end
  local runner = ctx.runner
  game.stack:push(require("src.ui.HgssAlphInscription").new(game, tonumber(index) or 0, function()
    if runner then runner:resume() end
  end))
  if runner then runner:yield() end
end
if Commands.meta then Commands.meta.g4_hgss_alph_inscription = { foreground = true, blocking = true } end

-- GiveRandomSeal <dest1, dest2, dest3> (scrcmd_pokemon_misc.c 1332): every
-- seal below SEAL_MYSTERY (77) weighted by the room left for it in the case
-- (99 - owned); up to three different draws of LCRandom() % total, each
-- landing on the seal whose cumulative threshold it falls under, given one
-- each and written to the three vars (0 for a draw that never happened)
function Commands.g4_hgss_random_seal(ctx, d1, d2, d3)
  local Seals = require("src.import.Gen4Seals")
  local save = ctx.save or {}
  local thresholds, total = {}, 0
  for id = 1, 77 do
    total = total + math.max(0, 99 - (tonumber(Seals.count(save, id)) or 0))
    thresholds[id] = total
  end
  local given, picks, out = math.min(3, total), {}, { 0, 0, 0 }
  local rand = (love and love.math and love.math.random) or math.random
  for i = 1, given do
    local r
    repeat
      r = rand(0, 65535) % total
      local dup = false
      for k = 1, i - 1 do if picks[k] == r then dup = true end end
    until not dup
    picks[i] = r
    for id = 1, 77 do
      if r < thresholds[id] then out[i] = id; Seals.change(save, id, 1); break end
    end
  end
  setVar(ctx, d1, out[1]); setVar(ctx, d2, out[2]); setVar(ctx, d3, out[3])
end

-- ShowLegendaryWing <n> (src/world/HgssLegendCutscene.lua M.showWing): the
-- wing over the player, and the map's third script (QueueScript 3 -- the
-- monk walking over at the Tin Tower, the elder at the Whirl Islands).
-- APPROXIMATE in its order, and said so: the cartridge's command holds the
-- calling script until the wing has played out and queues script 3 when the
-- first set ends; here the wing plays on its own and script 3 runs once the
-- calling script (ReleaseAll / SetVar / End) has finished.
function Commands.g4_hgss_legendary_wing(ctx, variant)
  require("src.world.HgssLegendCutscene").showWing(valueOf(ctx, variant))
  local ow = ctx.overworld
  local data = ctx.game and ctx.game.data
  local mapId = ow and ow.map and ow.map.id
  local ms = data and data.map_scripts
  local entry = ms and ms.maps and mapId and ms.maps[mapId]
  local label = entry and entry.entries and entry.entries[3]
  local rows = label and require("src.script.Gen4ScriptVM").compile(data, label)
  if rows and ow and ow.queueScript then ow:queueScript(rows, { mapId = mapId }) end
end

function M.install(L)
  local function emit(s, row) s.out[#s.out + 1] = row end
  local function rows(name, n)
    return function(ins, s)
      local row = { name }
      for i = 1, n do row[#row + 1] = ins.args[i] end
      emit(s, row)
    end
  end
  L.openalphhiddenroom = L.openalphhiddenroom or rows("g4_hgss_alph_inscription", 1)
  L.giverandomseal = L.giverandomseal or rows("g4_hgss_random_seal", 3)
  L.showlegendarywing = L.showlegendarywing or rows("g4_hgss_legendary_wing", 1)
  -- Platinum's rows, HGSS's names
  L.countfossils = L.countfossils or rows("g4_fossil_count", 1)
  L.getfossilminimumamount = L.getfossilminimumamount or rows("g4_fossil_at_threshold", 3)
  L.getevtotal = L.getevtotal or rows("g4_mon_ev_total", 2)
  L.gethiddenpowertype = L.gethiddenpowertype or rows("g4_hidden_power_type", 2)
  L.getuniquesealsquantity = L.getuniquesealsquantity or rows("g4_count_unique_seals", 1)
  L.mongetmove = L.mongetmove or rows("g4_mon_move", 3)
  L.countpartymonsofspecies = L.countpartymonsofspecies or rows("g4_count_repeated_species", 2)
  L.partycountmonsatorbelowlevel = L.partycountmonsatorbelowlevel or rows("g4_party_below_level", 2)
  -- HGSS's own
  L.mongetgender = L.mongetgender or rows("g4_hgss_mon_gender", 2)
  L.getpartyslotwithspecies = L.getpartyslotwithspecies or rows("g4_hgss_slot_with_species", 2)
  L.partymonismine = L.partymonismine or rows("g4_hgss_mon_is_mine", 2)
  L.kenyacheck = L.kenyacheck or rows("g4_hgss_kenya_check", 3)
  L.mongivemail = L.mongivemail or rows("g4_hgss_take_mail", 1)
  L.statjudge = L.statjudge or rows("g4_hgss_stat_judge", 4)
  -- the DS's sleep-on-close latch and the link party's form clean-up: nothing here
  L.syssetsleepflag = L.syssetsleepflag or function(_, st) st.out[#st.out + 1] = { "g4_noop", "the lid-close sleep latch" } end
  L.commsanitizeparty = L.commsanitizeparty or function(_, st) st.out[#st.out + 1] = { "g4_noop", "the link party clean-up" } end
  L.laticaughtcheck = L.laticaughtcheck or rows("g4_hgss_lati_caught", 1)
  L.radiomusicisplaying = L.radiomusicisplaying or rows("g4_hgss_radio_music", 2)
  L.getshinyleafcount = L.getshinyleafcount or rows("g4_hgss_shiny_leaves", 2)
  L.trygiveshinyleafcrown = L.trygiveshinyleafcrown or rows("g4_hgss_shiny_leaf_crown", 1)
  L.checkkyogregroudoninparty = L.checkkyogregroudoninparty or rows("g4_hgss_kyogre_groudon", 1)
  -- the Radio Tower's Lucky Number: Jubilife's lottery under HGSS's names
  -- (VAR_LOTO_NUMBER_LO is Platinum's 0x403C; the match is the same five
  -- trailing digits of the OT id, party first, then the boxes)
  L.lotoidget = L.lotoidget or rows("g4_lottery_id", 1)
  L.lotoidsearch = L.lotoidsearch or rows("g4_lottery_winner", 4)
  L.lotoidset = L.lotoidset or rows("g4_hgss_loto_roll", 0)
  -- string buffers the same as Platinum's: BufferIntEx <slot, var, mode,
  -- digits> is BufferVarPaddingDigits; BufferBoxMonNick <slot, index> is
  -- BufferMonNicknameFromPC; BufferSpeciesNameIndef <slot, species, -, ->
  -- is the species with its article
  -- Silph Co.'s Rotom room: Platinum's two Rotom commands, same operands
  L.updaterotomform = L.updaterotomform or rows("g4_set_rotom_form", 4)
  L.getownedrotomforms = L.getownedrotomforms or rows("g4_rotom_forms_in_save", 5)
  L.monforgetmove = L.monforgetmove or rows("g4_hgss_forget_move", 2)
  -- Blackthorn's Move Deleter: ScrCmd_394 <slot> opens the summary's move
  -- list to pick one (Platinum's opensummaryscreenteachmove, no new move)
  L.scrcmd_394 = L.scrcmd_394 or function(ins, s) emit(s, { "g4_tutor_forget_menu", ins.args[1], 0 }) end
  L.scrcmd_395 = L.scrcmd_395 or rows("g4_hgss_forget_pick", 1)
  L.checkcoinsimmediate = L.checkcoinsimmediate or rows("g4_hgss_coins_at_least", 2)
  L.settrainerhousesprite = L.settrainerhousesprite or rows("g4_hgss_trainer_house_sprite", 2)
  -- ScrCmd_824 <dest>: is the Safari Zone linked to a friend's? (no link play)
  L.scrcmd_824 = L.scrcmd_824 or function(ins, s) emit(s, { "g4_hgss_set_literal", ins.args[1], 0 }) end
  -- EggHatchAnim (HatchEggInParty): Platinum's hatchegg
  L.egghatchanim = L.egghatchanim or function(_, s) emit(s, { "g4_hatch_egg" }) end
  -- the PC's MAILBOX: ScrCmd_377 <dest> is Mailbox_CountMessages, Platinum's
  -- countmailinmailbox (this port keeps no mailbox: 0, "There's no Mail
  -- here"); ScrCmd_376, the mail screen, is only reached past a nonzero count
  L.scrcmd_377 = L.scrcmd_377 or function(ins, s) return L.countmailinmailbox(ins, s) end
  -- the PC's SEAL CASE entry: ScrCmd_156 is Platinum's opensealcapsuleeditor
  L.scrcmd_156 = L.scrcmd_156 or function(ins, s) return L.opensealcapsuleeditor(ins, s) end
  -- ScrCmd_492 <type, resultVar, wordVar>: the Easy Chat entry screen (std
  -- script 023's greetings). This port has no Easy Chat input, so it answers
  -- as a cancel does -- result 0, word 0xFFFF -- and the script ends there
  -- instead of reading the menu index left in the result as a phrase
  L.scrcmd_492 = L.scrcmd_492 or function(ins, s)
    emit(s, { "g4_hgss_set_literal", ins.args[2], 0 })
    emit(s, { "g4_hgss_set_literal", ins.args[3], 0xFFFF })
  end
  L.bufferintex = L.bufferintex or rows("g4_buffer_padded_var", 4)
  L.bufferboxmonnick = L.bufferboxmonnick or rows("g4_buffer_pc_nickname", 2)
  L.bufferspeciesnameindef = L.bufferspeciesnameindef
    or function(ins, s) emit(s, { "g4_buffer", ins.args[1], "speciesArticle", ins.args[2] }) end
  L.bufferpartymonspeciesnameindef = L.bufferpartymonspeciesnameindef
    or rows("g4_hgss_buffer_party_species_article", 2)
end

return M
