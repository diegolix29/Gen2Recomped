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

return Gen4ScriptBands
