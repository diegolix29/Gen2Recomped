-- What a map object's script id actually means.
--
-- THE MISTAKE THIS REPLACES was to treat any id past the end of a map's own
-- script list as unclassifiable and record it as `special`.  That was honest
-- but incurious: 2,148 events -- more than the 1,887 that did resolve --
-- carried one, and "what each band means is not claimed here" is not a thing
-- you have to leave standing when the cartridge's own dispatcher is a table.
--
-- ScriptContext_LoadAndOffsetID is that dispatcher, and it is a linear scan
-- from the HIGHEST threshold down:
--
--     if      id >= 10490 -> scratch-off cards,  entry id - 10490
--     else if id >= 10450 -> frontier records,   entry id - 10450
--     ...
--     else if id >=  2000 -> common scripts,     entry id - 2000
--     else if id >=     1 -> THIS MAP's own script file, entry id - 1
--     else                -> the dummy script
--
-- Each band names a file in scr_seq.narc and a text bank, so an id in a band is
-- not "special", it is an ordinary entry point in a shared script file.
--
-- THE TEST THAT SAYS THIS IS RIGHT is not that the arithmetic is copied
-- correctly -- it is that the resulting entry index lands INSIDE the target
-- file every time.  1,885 of 1,920 do.  The 35 that do not are all the single
-- value 65535, which is the "no script" sentinel wearing the top band's
-- clothes, and is reported as a sentinel rather than as a band.
--
-- AND A SECOND TEST, which is the one that mattered.  Cross-tabulating each
-- object's band against its ART made both tables check each other:
--
--     berry_tree_interactions   118 objects, every one drawn as BERRY_SOIL
--     visible_items             331 objects, every one drawn as POKEBALL
--     field_moves               688 objects: ROCK_SMASH, STRENGTH_BOULDER, CUT_TREE
--     tv_reporter_interviews     12 objects, every one drawn as REPORTER
--     mystery_gift_deliveryman   13 objects, every one drawn as MYSTERY_GIFT_DELIVERYMAN
--     follower_partners           4 objects, one of them BARRY
--
-- That agreement is what exposed the graphics indirection this project had
-- missed -- see Gen4ObjectGfx -- because under the old, wrong art the same
-- table read "berry tree scripts on Team Galactic's Mars".

local Gen4ScriptBands = {}

Gen4ScriptBands.SENTINEL = 65535

-- Highest threshold first, because that is the order the cartridge tests them
-- in and any other order silently assigns an id to the wrong band.
-- { threshold, name, the scr_seq member's name }
Gen4ScriptBands.BANDS = {
  { 10490, "scratch_off_cards", "scripts_scratch_off_cards" },
  { 10450, "battle_frontier_records", "scripts_battle_frontier_records" },
  { 10400, "pokemon_center_daily_trainers", "scripts_pokemon_center_daily_trainers" },
  { 10300, "counterpart_talk", "scripts_counterpart_talk" },
  { 10200, "mystery_gift_deliveryman", "scripts_mystery_gift_deliveryman" },
  { 10150, "tv_reporter_interviews", "scripts_tv_reporter_interviews" },
  { 10100, "tv_broadcast", "scripts_tv_broadcast" },
  { 10000, "field_moves", "scripts_field_moves" },
  {  9950, "pokedex_ratings", "scripts_pokedex_ratings" },
  {  9900, "unused_0397", "scripts_unused_0397" },
  {  9800, "contests", "scripts_contests" },
  {  9700, "follower_partners", "scripts_follower_partners" },
  {  9600, "init_new_game", "scripts_init_new_game" },
  {  9500, "day_care_common", "scripts_day_care_common" },
  {  9400, "poffin_common", "scripts_poffin_common" },
  {  9300, "group_connection", "scripts_group_connection" },
  {  9200, "pokemon_center_b1f_common", "scripts_pokemon_center_b1f_common" },
  {  9100, "communication_club", "scripts_communication_club" },
  {  9000, "pokemon_center_2f_common", "scripts_pokemon_center_2f_common" },
  {  8970, "poke_radar", "scripts_poke_radar" },
  {  8950, "vs_seeker", "scripts_vs_seeker" },
  {  8900, "record_chatot_cry", "scripts_record_chatot_cry" },
  {  8800, "safari_game", "scripts_safari_game" },
  {  8000, "hidden_items", "scripts_hidden_items" },
  {  7000, "visible_items", "scripts_visible_items" },
  {  5000, "double_battles", "scripts_battles" },
  {  3000, "single_battles", "scripts_battles" },
  {  2800, "berry_tree_interactions", "scripts_berry_tree_interaction" },
  {  2500, "bg_events", "scripts_bg_events" },
  {  2000, "common_scripts", "scripts_common" },
}

-- ...AND THE TEXT BANK EACH ONE READS FROM, which is the third column of the
-- same dispatcher and was the half this table left out.
--
-- `SCRIPT_RANGE_TABLE` (script_manager.c:36) is `Entry(offset, scriptFile,
-- textBank)`: `ScriptContext_Load` takes BOTH, so a script in a band does not
-- read the current map's message archive -- it reads the band's.  A common
-- script's `message 3` is entry 3 of TEXT_BANK_COMMON_STRINGS and has nothing
-- to do with the town the player is standing in.
--
-- The numbers are `generated/text_banks.txt` line minus one, checked against
-- two the port already knew independently: TEXT_BANK_ROWAN_INTRO is line 390
-- and `Gen4IntroScene.BANK` is 389, and the move-name banks are lines 648 and
-- 649 against the 647 and 648 the move stage uses.
Gen4ScriptBands.TEXT_BANK = {
  scratch_off_cards = 541,
  battle_frontier_records = 16,
  pokemon_center_daily_trainers = 203,
  counterpart_talk = 552,
  mystery_gift_deliveryman = 379,
  tv_reporter_interviews = 621,
  tv_broadcast = 622,
  field_moves = 381,
  pokedex_ratings = 383,
  unused_0397 = 213,
  contests = 217,
  follower_partners = 429,
  init_new_game = 213,
  day_care_common = 547,
  poffin_common = 432,
  group_connection = 374,
  pokemon_center_b1f_common = 430,
  communication_club = 11,
  pokemon_center_2f_common = 221,
  poke_radar = 7,
  vs_seeker = 539,
  record_chatot_cry = 431,
  safari_game = 538,
  hidden_items = 380,
  visible_items = 369,
  double_battles = 213,
  single_battles = 213,
  berry_tree_interactions = 397,
  bg_events = 17,
  common_scripts = 213,
}

-- THE BANK A *MENU* READS WHEN IT IS NOT READING THE SCRIPT'S OWN.
--
-- `initlocaltextmenu` hands FieldMenuManager `ctx->loader` -- the script's own
-- bank, which is what everything above is about.  `initglobaltextmenu` hands it
-- NULL, and the manager then opens TEXT_BANK_MENU_ENTRIES itself
-- (field_menu.c).  90 of the cartridge's 151 field menus are the global kind,
-- so a port that used the script's bank for all of them would print the wrong
-- word nearly two times in three.
--
-- 361 is `generated/text_banks.txt` line 362 minus one, the same derivation as
-- the table above, and reading the bank out of the cartridge says it plainly:
-- entry 5 is "EXIT", 17-21 are COOL/BEAUTY/CUTE/TOUGH/SMART, 22 is "TRADE",
-- 23 is "CANCEL".
Gen4ScriptBands.MENU_ENTRIES_BANK = 361

-- The file an id of 0 reaches.  Named so the "no script" case is a fact rather
-- than a hole.
Gen4ScriptBands.DUMMY_MEMBER_NAME = "scripts_unk_0402"

-- THE TWO BATTLE BANDS SHARE ONE FILE, and that is not a transcription slip:
-- scripts_battles is reached from both 3000 and 5000, and which one an id came
-- through is what tells the engine whether this trainer fights singles or is
-- the second half of a double.  Script_GetTrainerID subtracts the band's own
-- threshold and adds one either way, so the trainer number is the same and the
-- BAND carries the battle kind.
function Gen4ScriptBands.trainerId(id)
  if id >= 5000 and id < 7000 then return id - 5000 + 1, 1 end
  if id >= 3000 and id < 5000 then return id - 3000 + 1, 0 end
  return nil
end

-- classify(id) -> kind, bandName, entryIndex, memberName
--   kind is "none", "sentinel", "map", or "band"
function Gen4ScriptBands.classify(id)
  if id == nil or id == 0 then return "none" end
  if id == Gen4ScriptBands.SENTINEL then return "sentinel" end
  for _, band in ipairs(Gen4ScriptBands.BANDS) do
    if id >= band[1] then return "band", band[2], id - band[1], band[3] end
  end
  return "map", nil, id - 1, nil
end

-- ---------------------------------------------------------------------------
-- HEARTGOLD AND SOULSILVER
-- ---------------------------------------------------------------------------
--
-- The same dispatcher with its own table: pokeheartgold's sScriptBankMapping
-- (src/script_manager.c), thresholds from include/constants/std_script.h. The
-- scr_seq member and the text bank are NUMBERS there (scr_seq_0263_bin,
-- msg_0433), so the member is carried directly rather than looked up by name.
-- An id below every band and above 0 is the map's own; 0 is scr_seq 140 with
-- bank 184. The battle bands are Platinum's thresholds, 3000 and 5000, so
-- `trainerId` answers for both.
Gen4ScriptBands.HGSS = {
  BANDS = {
    { 10490, "scratch_card", 263, 433 },
    { 10450, "frontier_records", 264, 19 },
    { 10440, "frontier_move_tutor", 2, 748 },
    { 10400, "bug_contest", 151, 246 },
    { 10350, "trainer_house", 952, 726 },
    { 10300, "std_10300", 734, 444 },
    { 10200, "mystery_gift", 144, 209 },
    { 10150, "std_10150", 955, 732 },
    { 10100, "tv", 954, 733 },
    { 10000, "field_move", 146, 211 },
    {  9950, "dex_evaluation", 148, 666 },
    {  9900, "std_9900", 136, 40 },
    {  9850, "pokeathlon", 167, 312 },
    {  9800, "std_9800", 166, 43 },
    {  9700, "following_mon", 163, 266 },
    {  9600, "init", 149, 40 },
    {  9500, "daycare", 265, 439 },
    {  9300, "group", 143, 204 },
    {  9200, "wifi_reception", 164, 267 },
    {  9100, "colosseum", 0, 14 },
    {  9000, "comm_reception", 4, 46 },
    {  8900, "chatot", 165, 268 },
    {  8800, "safari", 262, 427 },
    {  8000, "hidden_items", 145, 210 },
    {  7000, "visible_items", 141, 199 },
    {  5000, "double_battles", 953, 40 },
    {  3000, "single_battles", 953, 40 },
    {  2800, "apricorn_tree", 150, 23 },
    {  2500, "bookshelves", 1, 20 },
    {  2000, "common_scripts", 3, 40 },
  },
  -- ov01_021EDAFC opens msg_0191 when a menu is given no bank
  MENU_ENTRIES_BANK = 191,
  DUMMY_MEMBER = 140, DUMMY_TEXT_BANK = 184,
}

-- PLATINUM'S TABLES, kept so `setFamily` can put them back
Gen4ScriptBands.PLATINUM = {
  BANDS = Gen4ScriptBands.BANDS, TEXT_BANK = Gen4ScriptBands.TEXT_BANK,
  MENU_ENTRIES_BANK = Gen4ScriptBands.MENU_ENTRIES_BANK,
}

-- setFamily("hgss" | anything else): which cartridge's dispatcher `classify`
-- and the menu bank answer for. HGSS's BANDS rows carry the member number as
-- their third field and the text bank as their fourth; TEXT_BANK is
-- rebuilt by name so every existing reader keeps working.
--
-- "bw" takes its rows from the cartridge (Gen5ScriptLink.findBands, written
-- to gen5_version.scriptBands) in the same { first, name, member, bank } shape.
function Gen4ScriptBands.setFamily(family, rows)
  local src = family == "hgss" and Gen4ScriptBands.HGSS
    or family == "bw" and { BANDS = rows or {}, MENU_ENTRIES_BANK = Gen4ScriptBands.PLATINUM.MENU_ENTRIES_BANK }
    or Gen4ScriptBands.PLATINUM
  Gen4ScriptBands.family = (family == "hgss" or family == "bw") and family or "platinum"
  Gen4ScriptBands.BANDS = src.BANDS
  Gen4ScriptBands.MENU_ENTRIES_BANK = src.MENU_ENTRIES_BANK
  if family == "hgss" or family == "bw" then
    local tb = {}
    for _, band in ipairs(src.BANDS) do tb[band[2]] = band[4] end
    Gen4ScriptBands.TEXT_BANK = tb
  else
    Gen4ScriptBands.TEXT_BANK = src.TEXT_BANK
  end
end

return Gen4ScriptBands
