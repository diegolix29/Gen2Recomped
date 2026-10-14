-- HEARTGOLD/SOULSILVER SCRIPT COMMANDS IN PLATINUM'S WORDS.
--
-- Gen4ScriptVM lowers a command by its NAME (Platinum's, from pokeplatinum's
-- scrcmd.h). 116,050 of the 181,648 instructions in HeartGold's scripts
-- already carry a name Platinum's table uses with the same operands -- the two
-- games descend from Diamond and Pearl -- and those need nothing. This is the
-- rest: an HGSS command whose HANDLER does what a Platinum one does, read
-- side by side in pokeheartgold and pokeplatinum, renamed to that one so the
-- VM lowers it unchanged.
--
-- An entry is the Platinum name, or { name, order } where `order` lists which
-- HGSS operands the Platinum command takes, in its order -- because a match in
-- meaning is not always a match in operands:
--
--   TrainerBattle (wwbb) reads two trainers then two bytes Platinum's
--     starttrainerbattle (ww) does not have
--   GiveMon (species, level, item, form, ability, destVar) against
--     givepokemon (species, level, item, destVar)
--   WildBattle (species, level, byte) against startwildbattle (species, level)
--
-- Every other entry has the same spec on both sides, which
-- tools/gen4_hgss_import_check.lua asserts for the whole table.
--
-- NOOP is for what this port has no counterpart to and whose absence changes
-- nothing a script then reads: the walking partner Pokemon's movement, and the
-- touch-screen menu being shown or hidden around a message.
--
-- Commands not here and not shared by name are left under their own name;
-- the VM reports them as unimplemented rather than guessing.

local NOOP = "noop"

local A = {
  -- control and vars
  wait = "waittime",
  callstd = "callcommonscript",
  restartcurrentscript = "returncommonscript",
  setvar = "setvarfromvalue",        -- ScriptGetVarPointer, ScriptReadHalfword
  copyvar = "setvarfromvar",         -- two var pointers
  -- (destVar, ScriptGetVar src): var-or-literal, which is what the VM's copy
  -- row already does with its source (Gen4Commands.valueOf)
  setorcopyvar = "setvarfromvar",
  nopvar490 = NOOP,
  setflagvar = "setflagfromvar",
  checkflagvar = "checkflagfromvar",
  waitfade = "waitfadescreen",
  random = "getrandom",              -- (destVar, modulo)

  -- messages: the NPC / non-NPC pairs differ only in whether the speaker
  -- turns, which Platinum's `message` row already does not model
  npcmsg = "message", nonnpcmsg = "message", scrcmd_048 = "message",
  npcmsgvar = "messagevar", nonnpcmsgvar = "messagevar",
  openmsg = "openmessage", closemsg = "closemessage",
  holdmsg = "closemessagewithouterasing",  -- RemoveWindow, text left as it is
  msgboxextern = "messagefrombank",  -- (bank, entry), both GetVar
  nonnpcmsgextern = "messagefrombank",
  -- GenderMsgBox (male, female): its own row, Gen4ScriptVM's `gendermsgbox`
  yesno = "showyesnomenu",
  -- the touch-screen YES/NO: ov01_021F6ABC mode 3, and the scripts branch on
  -- 0 for yes exactly as after showyesnomenu
  getmenuchoice = "showyesnomenu",

  -- menus: sub_02041770 reads x, y, cursor, cancellable, var -- Platinum's
  -- menu init exactly; NULL message data (the "Std" forms) is the standard
  -- menu bank, as Platinum's global menus are
  menuinitstdgmm = "initglobaltextmenu", menuinit = "initlocaltextmenu",
  scrcmd_064 = "initglobaltextmenu", scrcmd_065 = "initlocaltextmenu",
  scrcmd_068 = "initglobaltextlistmenu", scrcmd_069 = "initlocaltextlistmenu",
  scrcmd_066 = "addmenuentryimm", scrcmd_067 = "showmenu",
  scrcmd_070 = "addlistmenuentry", scrcmd_071 = "showlistmenu",
  scrcmd_072 = "showmenumulticolumn",
  menuitemadd = "addlistmenuentry",  -- (msg, alt, value), all GetVar
  menuexec = "showmenu",
  touchscreenmenushow = NOOP, touchscreenmenuhide = NOOP,

  -- signs (Diamond/Pearl's block, one slot later in HGSS)
  directionsignpost = "drawsignpostinstantmessage",
  setsignpostmap = "drawsignposttextbox",
  setsignpostaction = "setsignpostcommand",
  waitsignpostaction = "waitforsignpostdone",
  trainertips = "drawsignpostscrollingmessage",
  waitsignpost = "getsignpostinput",

  -- objects and camera
  lock = "lockobject", release = "releaseobject",
  showperson = "addobject", hideperson = "removeobject",
  getplayercoords = "getplayermappos",
  getplayerfacing = "getplayerdir",
  movepersonfacing = "setposition",  -- (id, x, y, z, dir), all GetVar
  scrcmd_102 = "addfreecamera", scrcmd_103 = "restorecamera",
  scrcmd_107 = "movecamera",         -- (x, y, z) -> FX32 shift
  scrcmd_108 = "setobjectflagispersistent", scrcmd_109 = "setmovementtype",
  setdynamicwarp = "setspeciallocation",  -- (map, warp, x, y, dir)
  -- the floor the dynamic warp names, as Platinum's elevator panel reads it
  getdynamicwarpfloorno = "getfloorsabove",
  makeobjectvisible = "showobject",
  restoreoverworld = "returntofield",  -- CallTask_RestoreOverworld
  playeronbikecheck = "checkplayeronbike", playeronbikeset = "setplayerbike",

  -- the partner Pokemon walking behind the player
  togglefollowingpokemonmovement = NOOP, waitfollowingpokemonmovement = NOOP,
  followingpokemonmovement = NOOP, setfollowmoninhibitstate = NOOP,
  scrcmd_609 = NOOP,                         -- nudges the partner if active
  -- 605 (face the partner to the player, bb), 606 / 607 (partner permission
  -- on this map), 608 (stop it): every one of them is guarded by
  -- FollowMon_IsActive in scrcmd_c.c, and no partner walks in this port
  scrcmd_605 = NOOP, scrcmd_606 = NOOP, scrcmd_607 = NOOP, scrcmd_608 = NOOP,

  -- DOORS. 307..311 are Platinum's door-animation family under numbers:
  -- 307 (hw, hw, var, var, byte -- matrix cell, tile, slot) loads it, 310
  -- opens, 311 closes, 308 waits, 309 frees. Cherrygrove's guide walks home
  -- through exactly `307 17,12,14,17,77 / 310 77 / 308 77`, then
  -- `311 77 / 308 77 / 309 77` once he is inside.
  scrcmd_307 = "loaddooranimation", scrcmd_308 = "waitforanimation",
  scrcmd_309 = "unloadanimation", scrcmd_310 = "playdooropenanimation",
  scrcmd_311 = "playdoorcloseanimation",

  -- the nickname prompt: (party slot var, result var), Platinum's operands
  nicknameinput = "openpokemonnamingscreen",

  -- ScrCmd_796 (field/headbutt.c) closes the money box ScrCmd_795 opened
  scrcmd_796 = "hidemoney",
  -- A, B or a direction ends it; the message box already waits for the
  -- button, so Platinum's waitbutton is the same row here
  waitbuttonordpad = "waitbutton",
  -- ScrCmd_795 (x, y) opens the money box: Platinum's ShowMoney operands
  scrcmd_795 = "showmoney",
  -- (dest var, amount var): money >= amount, as Platinum's second CheckMoney
  hasenoughmoneyvar = "checkmoney2",
  -- Save_SysInfo_SetMysteryGiftActive(.., 1): Oak's Pokedex scene turns the
  -- title menu's MYSTERY GIFT on, which is Platinum's UnlockMysteryGift
  scrcmd_573 = "unlockmysterygift",

  -- THE SHARED TRAINER SCRIPT. ScrCmd_574 <dest, object> is the object's
  -- movement type, Platinum's GetMovementType in the same order; ScrCmd_454
  -- plays an overlay-26 effect on the last-talked object and changes nothing
  -- a script reads; LoadPhoneDat <trainer, dest> is that trainer's phone-
  -- book entry, and the shared trainer script (scr_seq_0953) tests it
  -- against 255, NONE -- the answer while this port has no phone, which
  -- keeps every trainer off the number-swap path (0 is a real entry: Mom)
  scrcmd_574 = "getmovementtype",
  scrcmd_454 = NOOP,
  loadphonedat = { "setvarfromvalue", { 2, { 255 } } },
  -- clears a rematch's "seeking" flag in the phone state, which nothing
  -- here keeps
  scrcmd_462 = NOOP,
  -- Morty's gym: the candle's light follows its medium every frame
  -- (Gen4Commands' ecruteakFollow), so binding it for her walk is a no-op;
  -- EcruteakGymInit and ExtinguishEcruteakGymCandle lower in Gen4ScriptVM
  bindecruteakgymcandletotrainersprite = NOOP,
  unbindecruteakgymcandlefromtrainersprite = NOOP,

  -- IN-GAME TRADES (Violet's Onix-for-Bellsprout first): the same five
  -- steps as Platinum's, renamed -- load the trade, what they give, what
  -- they want, swap, free; ScrCmd_566 is the party menu for it and
  -- GetPartySelection its answer (255 when cancelled)
  loadnpctrade = "initnpctrade", getofferedspecies = "getnpctradespecies",
  npctradegetreqspecies = "getnpctraderequestedspecies",
  npctradeexec = "startnpctrade", npctradeend = "finishnpctrade",
  scrcmd_566 = "openpartymenufortrade", getpartyselection = "getselectedpartyslot",
  -- Field_SetWarpXYPos / Field_GetTimeOfDay, Platinum's under other names
  movewarp = "setwarpeventpos",
  scrcmd_379 = "gettimeofday",
  -- GetPhoneBookRematch <contact, dest>: whether a registered trainer wants a
  -- rematch today -- no phone is built, so never (0)
  getphonebookrematch = { "setvarfromvalue", { 2, { 0 } } },
  -- GameStats_AddScore: the trainer card's SCORE for a stat (a gym win, ...),
  -- not a game record; this port keeps no score yet
  addspecialgamestat = NOOP,
  -- "is the partner walking": never, in this port, so the answer is a
  -- constant -- { k } in an order is a literal operand
  scrcmd_729 = { "setvarfromvalue", { 1, { 0 } } },  -- TRUE when active
  scrcmd_730 = { "setvarfromvalue", { 1, { 1 } } },  -- TRUE when NOT active

  -- string buffers
  bufferplayersname = "bufferplayername", bufferrivalsname = "bufferrivalname",
  bufferfriendsname = "buffercounterpartname",
  buffermonspeciesname = "bufferpartymonspecies",  -- (idx, partySlot)
  bufferint = "buffernumber", bufferpartymonnick = "bufferpartymonnickname",
  bufferspeciesname = "bufferspeciesnamefromvar", buffermapsecname = "buffermapname",
  bufferpartymonmovename = "bufferpartymovename",

  -- items, money, coins, music
  giveitem = "additem", takeitem = "removeitem", hasspaceforitem = "canfititem",
  hasitem = "checkitem", itemistmorhm = "isitemtmhm",
  getcoinamount = "getcoinsamount", givecoins = "addcoins", takecoins = "subtractcoinsfromvalue",
  submoneyimmediate = "removemoney", hasenoughmoneyimmediate = "checkmoney",
  showmoneybox = "showmoney", hidemoneybox = "hidemoney", updatemoneybox = "updatemoneydisplay",
  playbgm = "playmusic", stopbgm = "stopmusic", resetbgm = "playdefaultmusic", tempbgm = "setbgm",

  -- party and player
  getpartyleadalive = "getfirstnonegginparty",
  checkbadge = "checkbadgeacquired",  -- (badge, destVar)
  getweekday = "getdayofweek",
  savegamenormal = "trysavegame",
  mongetfriendship = "getpartymonfriendship",  -- (destVar, slot)
  playerhasspecies = "checkpartyhasspecies",   -- (destVar, species)
  givemon = { "givepokemon", { 1, 2, 3, 6 } },

  -- trainers and battles
  trainerbattle = { "starttrainerbattle", { 1, 2 } },
  wildbattle = { "startwildbattle", { 1, 2 } },
  trainermessage = "printtrainerdialogue",
  gettrainermsgparams = "gettrainermessagetypes",
  getrematchmsgparams = "gettrainerrematchmessagetypes",
  trainerisdoublebattle = "checkistrainerdoublebattle",
  encountermusic = "playtrainerencounterbgm",
  whiteout = "blackoutfrombattle",
  checkbattlewon = "checkwonbattle",
  gettrainernum = "gettrainerid",
  partycheckfordouble = "checkhastwoalivemons",
  gotoiftrainerdefeated = "gotoiftargettrainerdefeated",
  gettrainerpathtoplayer = "startapproachingtrainertask",
  trainersteptowardsplayer = "checkisapproachingtrainertaskdone",
  gettrainereyetype = "getapproachingtrainertype",
  geteyetrainernum = "getapproachingtrainerid",
}

local M = { NOOP = NOOP, TABLE = A }

-- the Platinum name and the operands it takes, or nil to leave the command be
function M.lookup(name)
  local e = A[name]
  if e == nil then return nil end
  if type(e) == "string" then return e, nil end
  return e[1], e[2]
end

-- Rename an HGSS instruction in place; its own name is kept as `hgssName`.
-- A NOOP keeps no operands (the VM's `noop` reads none).
function M.apply(ins)
  local name, order = M.lookup(ins.name)
  if not name then return false end
  ins.hgssName = ins.name
  ins.name = name
  if name == NOOP then
    ins.args = {}
  elseif order then
    local args = {}
    for i, k in ipairs(order) do
      if type(k) == "table" then args[i] = k[1] else args[i] = ins.args and ins.args[k] end
    end
    ins.args = args
  end
  return true
end

return M
