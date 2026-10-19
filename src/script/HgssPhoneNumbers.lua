-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- HEARTGOLD / SOULSILVER: "CAN I HAVE YOUR NUMBER?" -- route trainers offering
-- their Pokegear number after a battle.
--
-- It is all in the shared trainer script (scr_seq_0953, the 738 trainer
-- entries and the sight entry 739). After a win, `_0D9F` asks whether the
-- trainer has a phonebook row (LoadPhoneDat answered something but 255) that
-- is not registered yet (CheckRegisteredPhoneNumber); if so the trainer asks
-- -- GetPhoneContactMsgIds 0 (first time) or 3 (talked to again later) --
-- and on YES: SEQ_ME_POKEGEAR_REGIST, msg_0040 #101, line 1 and
-- RegisterGearNumber; on NO line 2. Talked to after a rematch is fought,
-- the trainer hands over the phonebook row's gift (berries) or the gift a
-- call promised (GetPhoneContactRandomGiftBerry / GetPhoneContactGiftItem,
-- line 4).
--
-- The commands (scrcmd_c.c):
--
--   LoadPhoneDat <trainer, dest>    LoadPhoneBookEntryI: the `tel/pmtel_book.dat`
--                                   row whose trainerId matches -> its contact
--                                   id, else 0xFF; the row is kept as the ring
--                                   manager's caller entry for the commands below
--   GetPhoneContactMsgIds <n, bankVar, msgVar>
--                                   the contact's bank (sPhoneMessageGmm, read
--                                   from the ROM by Gen4HgssPokegearArt into
--                                   `contacts[id].bank`) and line n + 1 (n > 4
--                                   reads as 0); an empty entry answers line 0
--   GetPhoneContactRandomGiftBerry <dest>   the row's gift; a Cheri Berry (149)
--                                   is any of the ten from Cheri (+ LCRandom % 10)
--   GetPhoneContactGiftItem <dest>  the gift a call left with the contact
--                                   (PhoneCallPersistentState, kept here in
--                                   save.hgssPhoneState.gift), cleared as read
--
-- LoadPhoneDat had been aliased at import to `setvarfromvalue dest, 255`
-- (Gen4HgssScriptAliases), losing its trainer operand. An install imported
-- that way still says which instruction it was (`hgssName`), and the operand
-- is the var the instruction before it wrote -- in all six sites of
-- scr_seq_0953: `GetTrainerNum 0x8004`, `CopyVar 0x8004, ...`, or
-- `GetEyeTrainerNum 1, VAR_SPECIAL_RESULT` -- so the lowering below tracks
-- that var and needs no re-import.

local M = {}

M.CHERI_BERRY, M.BERRY_SPREAD = 149, 10
M.NONE = 0xFF

local function G4() return require("src.script.Gen4Commands") end

local function book(game)
  local pc = game and game.data and game.data.gen4_hgss_phone_call
  return pc and pc.book
end

-- LoadPhoneBookEntryI: the row for `trainerId`, or nil
function M.entryForTrainer(bk, trainerId)
  if not bk then return nil end
  local n = tonumber(bk.count) or 0
  for i = 0, n - 1 do
    local e = bk[i]
    if e and e.trainerId == trainerId then return e end
  end
  return nil
end

-- the contact's message bank (sPhoneMessageGmm)
function M.bankFor(game, id)
  local art = game and game.data and game.data.gen4_hgss_pokegear_art
  local c = art and art.contacts and art.contacts[id]
  return c and c.bank or nil
end

-- GetPhoneContactMsgIds' line: n + 1, n past 4 read as 0
function M.messageLine(kind)
  kind = math.floor(tonumber(kind) or 0)
  if kind > 4 or kind < 0 then kind = 0 end
  return kind + 1
end

-- GetPhoneContactRandomGiftBerry
function M.giftBerry(gift, rnd)
  gift = tonumber(gift) or 0
  if gift == M.CHERI_BERRY then
    return M.CHERI_BERRY + ((rnd or math.random)(0, M.BERRY_SPREAD - 1))
  end
  return gift
end

local okCommands, Commands = pcall(require, "src.script.Commands")
if not okCommands then Commands = {} end

function Commands.g4_hgss_load_phone_dat(ctx, trainerVar, destVar)
  local game = ctx.game
  local trainer = math.floor(tonumber(G4().valueOf(ctx, trainerVar)) or 0)
  local e = M.entryForTrainer(book(game), trainer)
  if game then game.hgssPhoneEntry = e or { id = M.NONE } end
  G4().setVar(ctx.save, destVar, e and e.id or M.NONE)
end

function Commands.g4_hgss_phone_contact_msg(ctx, kind, bankVar, msgVar)
  local game = ctx.game
  local e = game and game.hgssPhoneEntry
  if not e or e.id == M.NONE then
    G4().setVar(ctx.save, msgVar, 0)
    return
  end
  G4().setVar(ctx.save, bankVar, M.bankFor(game, e.id) or 0)
  G4().setVar(ctx.save, msgVar, M.messageLine(G4().valueOf(ctx, kind)))
end

function Commands.g4_hgss_phone_gift_berry(ctx, destVar)
  local e = ctx.game and ctx.game.hgssPhoneEntry
  G4().setVar(ctx.save, destVar, M.giftBerry(e and e.gift or 0))
end

function Commands.g4_hgss_phone_gift_item(ctx, destVar)
  local e = ctx.game and ctx.game.hgssPhoneEntry
  local id = e and e.id
  local st = ctx.save and ctx.save.hgssPhoneState
  local gift = id and st and st.gift and st.gift[id] or 0
  if id and st and st.gift then st.gift[id] = nil end
  G4().setVar(ctx.save, destVar, gift)
end

function M.install(L)
  local function emit(s, row) s.out[#s.out + 1] = row end
  -- the var holding the trainer, for an aliased LoadPhoneDat
  local function track(name, at)
    local orig = L[name]
    if not orig then return end
    L[name] = function(ins, s)
      s.hgssTrainerVar = ins.args and ins.args[at]
      return orig(ins, s)
    end
  end
  track("gettrainerid", 1)
  track("getapproachingtrainerid", 2)
  track("setvarfromvar", 1)
  local setValue = L.setvarfromvalue
  L.setvarfromvalue = function(ins, s)
    if ins.hgssName == "loadphonedat" then
      emit(s, { "g4_hgss_load_phone_dat", s.hgssTrainerVar or 0x8004, ins.args[1] })
      return
    end
    return setValue(ins, s)
  end
  -- an install imported after the alias was dropped keeps both operands
  L.loadphonedat = function(ins, s) emit(s, { "g4_hgss_load_phone_dat", ins.args[1], ins.args[2] }) end
  L.getphonecontactmsgids = function(ins, s)
    emit(s, { "g4_hgss_phone_contact_msg", ins.args[1], ins.args[2], ins.args[3] })
  end
  L.getphonecontactrandomgiftberry = function(ins, s) emit(s, { "g4_hgss_phone_gift_berry", ins.args[1] }) end
  L.getphonecontactgiftitem = function(ins, s) emit(s, { "g4_hgss_phone_gift_item", ins.args[1] }) end
end

return M
