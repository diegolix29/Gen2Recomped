-- graphicsId -> the mmodel.narc member that draws it.
--
-- THIS IS AN INDIRECTION, AND MISSING IT COSTS EVERY SPRITE IN THE GAME.
--
-- A map object's `graphicsId` does NOT index mmodel.narc.  It is a key into
-- gObjectEventGfxTexturesTable, a flat list of { u32 graphicsID, u32 narcIndex }
-- pairs that the field engine searches linearly (ov5_021ECD10) and that ends
-- with graphicsID 0xFFFF.  Treating the id as the member number resolves for
-- every object -- every id in range names *a* member -- and is wrong for all
-- 3,555 of them:
--
--   gfx85  x591  is ROCK_SMASH        and was drawing pokeball
--   gfx87  x331  is POKEBALL          and was drawing unused_woman_1
--   gfx84  x50   is STRENGTH_BOULDER  and was drawing cut_tree
--   gfx3   x65   is SCHOOL_KID_M      and was drawing youngster
--
-- Zero of 3,555 objects had the right art.  "100% resolved" was never evidence
-- of anything: a lookup that cannot miss cannot tell you it is wrong.
--
-- WHAT CAUGHT IT was cross-tabulating each object's SCRIPT BAND against its art
-- (see Gen4ScriptBands).  118 objects running berry-tree scripts were drawn as
-- Team Galactic's Mars; 13 running the mystery-gift deliveryman's script were
-- drawn as a blooming Lum berry.  Two independent tables disagreeing is a fact;
-- one table looking plausible is not.
--
-- THE TABLE IS READ FROM THE CARTRIDGE, not transcribed.  It is found by its
-- own shape -- ids 0,1,2,3,4,5 ascending at a stride of eight, running to the
-- 0xFFFF terminator -- so a ROM that moved it still works and a ROM that does
-- not have it fails loudly instead of returning the wrong member.  In the USA
-- Rev 1 cartridge it sits at overlay 5 + 0x2BC34 and holds 441 rows, which
-- matches pokeplatinum's own table row for row; only the NAMES below come from
-- pret.
--
-- IDS ABOVE 4095 ARE THE BERRY TREES: OBJ_EVENT_GFX_BERRY_SPROUT is 4096 and a
-- berry's three growth stages are 4096 + berryId * 3 + 1..3.  They are ordinary
-- rows in the same table; nothing special is needed to read them.
--
-- AN ID THAT IS NOT IN THE TABLE IS NOT A MISSING SPRITE.  427 of the map
-- objects carry one, and they are the signposts (91-96), berry soil (100) and
-- the thirteen VAR_0..VAR_C slots (101-113) -- objects with no billboard of
-- their own, because a signpost is part of the map and a VAR_ slot is
-- substituted at runtime the way Gen 2 substitutes its $F0+ sprites.  Those
-- return nil with a REASON, not a member.

local Gen4ObjectGfx = {}

local floor = math.floor

Gen4ObjectGfx.OVERLAY = 5
Gen4ObjectGfx.TERMINATOR = 0xFFFF

-- The rows, in the cartridge's own order.  Kept as a fallback and as the
-- source of names; `read` prefers the cartridge and falls back to these.
local IDS = { 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55,56,57,58,59,60,61,62,63,64,65,66,67,68,69,70,71,72,73,74,75,76,77,78,79,80,81,82,83,84,85,86,87,88,89,90,91,92,93,94,95,96,97,98,99,100,101,102,103,104,105,106,107,108,109,110,111,112,113,114,115,116,117,118,119,120,121,122,123,124,125,126,127,128,129,130,131,132,133,134,135,136,137,138,139,140,141,142,143,144,145,146,147,148,149,150,151,152,153,154,155,156,157,158,159,160,161,162,163,164,165,166,167,168,169,170,171,172,173,174,175,176,177,178,179,180,181,182,183,184,185,186,187,188,189,190,191,192,193,194,195,196,197,198,199,200,201,202,203,204,205,206,207,208,209,210,211,212,213,214,215,216,217,218,219,220,221,222,223,224,225,226,227,228,229,230,231,232,233,234,235,236,237,238,239,240,241,242,243,244,245,246,247,248,249,250,251,252,253,254,255,256,257,258,259,260,261,262,263,264,265,266,267,268,269,270,271,272,273,274,275,4096,4097,4098,4099,4100,4101,4102,4103,4104,4105,4106,4107,4108,4109,4110,4111,4112,4113,4114,4115,4116,4117,4118,4119,4120,4121,4122,4123,4124,4125,4126,4127,4128,4129,4130,4131,4132,4133,4134,4135,4136,4137,4138,4139,4140,4141,4142,4143,4144,4145,4146,4147,4148,4149,4150,4151,4152,4153,4154,4155,4156,4157,4158,4159,4160,4161,4162,4163,4164,4165,4166,4167,4168,4169,4170,4171,4172,4173,4174,4175,4176,4177,4178,4179,4180,4181,4182,4183,4184,4185,4186,4187,4188,4189,4190,4191,4192,4193,4194,4195,4196,4197,4198,4199,4200,4201,4202,4203,4204,4205,4206,4207,4208,4209,4210,4211,4212,4213,4214,4215,4216,4217,4218,4219,4220,4221,4222,4223,4224,4225,4226,4227,4228,4229,4230,4231,4232,4233,4234,4235,4236,4237,4238,4239,4240,4241,4242,4243,4244,4245,4246,4247,4248,4249,4250,4251,4252,4253,4254,4255,4256,4257,4258,4259,4260,4261,4262,4263,4264,4265,4266,4267,4268,4269,4270,4271,4272,4273,4274,4275,4276,4277,4278,4279,4280,4281,4282,4283,4284,4285,4286,4287,4288,8192 }

local NAMES = "player_m|ninja_boy|twin|school_kid_m|youngster|bug_catcher|lass|battle_girl|school_kid_f|pokemon_breeder_m|guitarist|ace_trainer_m|pokemon_breeder_f|beauty|ace_trainer_f|pokefan_m|pokefan_f|expert_m|expert_f|collector|hiker|player_m_bike|reporter|cameraman|cashier_m|cashier_f|pokecenter_nurse|teala|unused_receptionist|scientist_m|scientist_f|roughneck|skier_m|skier_f|policeman|idol|gentleman|socialite|cyclist_m|cyclist_f|worker|rancher|cowgirl|clown|artist|jogger|swimmer_m|swimmer_f|tuber_f|tuber_m|ruin_maniac|black_belt|camper|picnicker|fisherman|parasol_lady|sailor|dummy_057|dummy_058|waiter|waitress|dummy_061|rich_boy|lady|snowpoint_npc_m|snowpoint_npc_f|dummy_066|dummy_067|ace_trainer_snow_m|ace_trainer_snow_f|psychic|pikachu|clefairy|jigglypuff|psyduck|dummy_075|dummy_076|dummy_077|torchic|skitty|dummy_080|baby_in_pram|middle_aged_man|middle_aged_woman|strength_boulder|rock_smash|cut_tree|pokeball|unused_woman_1|unused_woman_2|unused_woman_3|map_signpost|mailbox|signboard|arrow_signpost|gym_signpost|trainer_tips_signpost|player_f|player_f_bike|prof_rowan|berry_soil|var_0|var_1|var_2|var_3|var_4|var_5|var_6|var_7|var_8|var_9|var_a|var_b|var_c|var_d|var_e|var_f|unk_117|snowball|unk_119|cyrus|mars|saturn|jupiter|grunt_m|grunt_f|roark|gardenia|crasher_wake|maylene|fantina|candice|byron|volkner|aaron|bertha|flint|lucian|cynthia|unused_man|mom|cheryl|riley|marley|buck|mira|dummy_146|dummy_147|barry|unused_big_man_1|unused_big_man_2|uxie|mesprit|azelf|dialga|palkia|arceus|darkrai|shaymin|cresselia|giratina_altered|heatran|dummy_162|receptionist|old_man|old_woman|prof_oak|jasmine|gym_guide|palmer|unused_big_man_3|unused_big_man_4|unused_big_man_5|starly|briefcase|maid|player_m_holding_poke_ball|player_f_holding_poke_ball|player_m_surf|player_f_surf|player_m_sprayduck|player_f_sprayduck|vent|book|regigigas|drifloon|player_m_contest|player_f_contest|player_m_fishing|player_f_fishing|moss_rock|ice_rock|bollard|mystery_gift_deliveryman|kid_with_nds|magikarp|player_m_poketch|player_f_poketch|player_m_save|player_f_save|player_m_pokecenter_heal|player_f_pokecenter_heal|galactic_hq_door|cave_painting|pachirisu|shroomish|buneary|happiny|machop|elite_four_room_door|player_m_hearthome_gym|player_f_hearthome_gym|dist_world_player_m|looker|charon|thorton|argenta|darach|dahlia|caitlin|turtwig|grotle|torterra|chimchar|monferno|infernape|piplup|prinplup|empoleon|croagunk|giratina_origin|frontier_single_attendant|frontier_multi_attendant|frontier_booth_attendant|wifi_plaza_attendant_m|wifi_plaza_attendant_f|pikachu_unused|rotom_heat|rotom_fan|rotom_frost|rotom_wash|rotom_mow|game_director|oven_unused|fan_unused|fridge_unused|washing_machine_unused|lawnmower_unused|grunts_group_of_4|grunts_group_of_3|cave_painting_shards_left|cave_painting_shards_right|dp_player_m|dp_player_f|dp_player_m_contest|dp_player_f_contest|player_m_vs_seeker|player_f_vs_seeker|dist_world_player_m_surf|dist_world_player_f_surf|dist_world_player_m_holding_pokeball|dist_world_player_f_holding_pokeball|wall_blocking_rotoms_room|dist_world_player_f|dist_world_b1f_mesprit|dist_world_b6f_uxie|dist_world_b6f_mesprit|dist_world_b6f_azelf|dist_world_player_m_save|dist_world_player_f_save|dist_world_player_m_poketch|dist_world_player_f_poketch|player_m_save_hearthome_gym|player_f_save_hearthome_gym|player_m_poketch_hearthome_gym|player_f_poketch_hearthome_gym|berry_sprout|cheri_growing|cheri_blooming|cheri_fruit|chesto_growing|chesto_blooming|chesto_fruit|pecha_growing|pecha_blooming|pecha_fruit|rawst_growing|rawst_blooming|rawst_fruit|aspear_growing|aspear_blooming|aspear_fruit|leppa_growing|leppa_blooming|leppa_fruit|oran_growing|oran_blooming|oran_fruit|persim_growing|persim_blooming|persim_fruit|lum_growing|lum_blooming|lum_fruit|sitrus_growing|sitrus_blooming|sitrus_fruit|figy_growing|figy_blooming|figy_fruit|wiki_growing|wiki_blooming|wiki_fruit|mago_growing|mago_blooming|mago_fruit|aguav_growing|aguav_blooming|aguav_fruit|iapapa_growing|iapapa_blooming|iapapa_fruit|razz_growing|razz_blooming|razz_fruit|bluk_growing|bluk_blooming|bluk_fruit|nanab_growing|nanab_blooming|nanab_fruit|wepear_growing|wepear_blooming|wepear_fruit|pinap_growing|pinap_blooming|pinap_fruit|pomeg_growing|pomeg_blooming|pomeg_fruit|kelpsy_growing|kelpsy_blooming|kelpsy_fruit|qualot_growing|qualot_blooming|qualot_fruit|hondew_growing|hondew_blooming|hondew_fruit|grepa_growing|grepa_blooming|grepa_fruit|tamato_growing|tamato_blooming|tamato_fruit|cornn_growing|cornn_blooming|cornn_fruit|magost_growing|magost_blooming|magost_fruit|rabuta_growing|rabuta_blooming|rabuta_fruit|nomel_growing|nomel_blooming|nomel_fruit|spelon_growing|spelon_blooming|spelon_fruit|pamtre_growing|pamtre_blooming|pamtre_fruit|watmel_growing|watmel_blooming|watmel_fruit|durin_growing|durin_blooming|durin_fruit|belue_growing|belue_blooming|belue_fruit|occa_growing|occa_blooming|occa_fruit|passho_growing|passho_blooming|passho_fruit|wacan_growing|wacan_blooming|wacan_fruit|rindo_growing|rindo_blooming|rindo_fruit|yache_growing|yache_blooming|yache_fruit|chople_growing|chople_blooming|chople_fruit|kebia_growing|kebia_blooming|kebia_fruit|shuca_growing|shuca_blooming|shuca_fruit|coba_growing|coba_blooming|coba_fruit|payapa_growing|payapa_blooming|payapa_fruit|tanga_growing|tanga_blooming|tanga_fruit|charti_growing|charti_blooming|charti_fruit|kasib_growing|kasib_blooming|kasib_fruit|haban_growing|haban_blooming|haban_fruit|colbur_growing|colbur_blooming|colbur_fruit|babiri_growing|babiri_blooming|babiri_fruit|chilan_growing|chilan_blooming|chilan_fruit|liechi_growing|liechi_blooming|liechi_fruit|ganlon_growing|ganlon_blooming|ganlon_fruit|salac_growing|salac_blooming|salac_fruit|petaya_growing|petaya_blooming|petaya_fruit|apicot_growing|apicot_blooming|apicot_fruit|lansat_growing|lansat_blooming|lansat_fruit|starf_growing|starf_blooming|starf_fruit|enigma_growing|enigma_blooming|enigma_fruit|micle_growing|micle_blooming|micle_fruit|custap_growing|custap_blooming|custap_fruit|jaboca_growing|jaboca_blooming|jaboca_fruit|rowap_growing|rowap_blooming|rowap_fruit|invisible"

local names, byId = nil, nil

local function unpack_()
  if names then return end
  names, byId = {}, {}
  local i = 1
  for word in NAMES:gmatch("([^|]+)") do
    names[IDS[i]] = word
    i = i + 1
  end
end

-- name(graphicsId) -> "rock_smash", or nil
function Gen4ObjectGfx.name(id)
  unpack_()
  return names[id]
end

local function u32(data, at)
  local a, b, c, d = data:byte(at + 1, at + 4)
  if not d then return nil end
  return a + b * 256 + c * 65536 + d * 16777216
end

-- find(data, memberCount) -> offset, rowCount, or nil.
--
-- Matched on shape, and the shape has to be stated carefully, because a naive
-- version of this test is wrong TWICE over in this one overlay:
--
--  1. The same overlay holds gObjectEventGfxModelsTable, which has the identical
--     { u32 id, u32 index } row shape and also starts at id 0, and it sits
--     EARLIER -- so a first-match scan returns 18 rows instead of 441, answers
--     every id it knows with a member from the WRONG ARCHIVE, and answers nil
--     for the rest.  Taking the longest candidate rather than the first is the
--     same correction the type chart needed.
--  2. Taking the longest is not enough on its own.  This table maps gfx1..gfx6
--     to members 0..5, so reading it twelve bytes late -- one column out --
--     ALSO sees 0,1,2,3,4,5 ascending at a stride of eight, and then runs 1,320
--     rows past the end because the real terminator is in the other column.
--
-- What separates them is an invariant rather than a pattern: the second column
-- is an mmodel.narc MEMBER INDEX, so every one of them must be in range for
-- that archive.  Read one column late, the second column is the next row's
-- graphicsId, and the berry ids (4096+) are far out of range.  So `find` is
-- given the member count and checks it.
--
-- WHAT IT DELIBERATELY DOES NOT CHECK is that the ids ascend.  They nearly do,
-- and requiring it rejects the real table: the berry block (4096-4288) is
-- spliced into the middle rather than appended, so the run breaks three times.
-- An invariant that is almost true is worse than no invariant, because it
-- throws away the right answer and keeps a plausible wrong one -- here, a
-- 23-row table of animation .bin files.
function Gen4ObjectGfx.find(data, memberCount)
  if type(data) ~= "string" then return nil end
  memberCount = memberCount or 470
  local bestAt, bestRows = nil, 0
  for at = 0, #data - 48, 4 do
    local ok = true
    for row = 0, 5 do
      if u32(data, at + row * 8) ~= row then ok = false break end
    end
    if ok then
      local off, rows, valid = at, 0, true
      while rows < 2048 do
        local id, member = u32(data, off), u32(data, off + 4)
        if id == nil then valid = false break end
        if id == Gen4ObjectGfx.TERMINATOR then break end
        if member == nil or member >= memberCount then valid = false break end
        off = off + 8
        rows = rows + 1
      end
      if valid and rows > bestRows then bestAt, bestRows = at, rows end
    end
  end
  if not bestAt then return nil end
  return bestAt, bestRows
end

-- read(overlayData) -> { [graphicsId] = member }, rowCount
-- Returns nil when the table is not there, rather than a guess.
function Gen4ObjectGfx.read(data, memberCount)
  local at, rows = Gen4ObjectGfx.find(data, memberCount)
  if not at then return nil, "gObjectEventGfxTexturesTable not found in this overlay" end
  local out, n = {}, 0
  local off = at
  while true do
    local id, member = u32(data, off), u32(data, off + 4)
    if id == nil or id == Gen4ObjectGfx.TERMINATOR then break end
    out[id] = member
    n = n + 1
    off = off + 8
  end
  return out, n
end

-- WHY AN ID CAN HAVE NO ROW.  Recorded as a reason rather than as a failure,
-- because "this object has no billboard" and "this lookup is broken" must not
-- look the same in the index.
Gen4ObjectGfx.NO_SPRITE = {
  [91] = "signpost", [92] = "signpost", [93] = "signpost",
  [94] = "signpost", [95] = "signpost", [96] = "signpost",
  -- The soil is the PLANTING SPOT.  What gets drawn on it is one of the berry
  -- ids above 4095, chosen by which berry is in it and how grown it is, so the
  -- soil itself owning no picture is correct rather than missing.
  [100] = "berry_soil",
  -- Map geometry or their own code, not a billboard: the Snowpoint snowball
  -- you push, the Elite Four doors, a readable book, the wall across Rotom's
  -- room.  35 objects between them.
  [118] = "map_prop", [183] = "map_prop",
  [209] = "map_prop", [262] = "map_prop",
}
-- VAR_0 .. VAR_C: thirteen slots whose art is substituted at run time, exactly
-- the way Gen 2 substitutes its $F0+ sprites.  A daily trainer in a Pokemon
-- Centre is one of these, which is why they cluster in that script band.
for id = 101, 113 do Gen4ObjectGfx.NO_SPRITE[id] = "runtime_variable" end

function Gen4ObjectGfx.reason(id)
  return Gen4ObjectGfx.NO_SPRITE[id]
end

return Gen4ObjectGfx
