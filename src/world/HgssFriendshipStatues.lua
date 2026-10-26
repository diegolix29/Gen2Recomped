-- HEARTGOLD / SOULSILVER POKeATHLON DOME, THE "FRIENDSHIP" ROOM'S STATUES
-- (D49R0107; pokeheartgold src/field/scrcmd_pokemon_misc.c
-- ScrCmd_CreatePokeathlonFriendshipRoomStatues, scrcmd 744, and
-- ov01_02201F98).
--
-- The room's map-load script (scr_seq_0128 #6) runs
-- CreatePokeathlonFriendshipRoomStatues once per entry (VAR_TEMP_x400F). The
-- three statues are the team of the last course the player WON
-- (Save_Pokeathlon_FriendshipRecords, written by ov96_021E7F48 at the course's
-- end -- the port's save.hgssPokeathlonStatues, src/pokemon/
-- HgssPokeathlonStats.lua). The plaques are the map's own bg events on the
-- same tiles (#2-#4, "The statue of the Pokemon you've shared your journey
-- with...").
--
-- READ FROM CODE:
--   * for i = 0..2: the object with id 0xF6 + i is deleted if there is one;
--     then, when the record's species is 1..493 (SPECIES_ARCEUS), a map
--     object is made at sFriendshipRoomStatuesPositions[i] = (4, 10), (7, 5),
--     (10, 10), facing south, movement 0, no script, no event flag, id
--     0xF6 + i, the walking-Pokemon sprite of {species, form, gender}
--     (FollowMon_GetSpriteID; sprite object SPRITE_FOLLOWER_MON + 3 x size +
--     i), never shiny (sub_02069F0C's FALSE), range -1 (it never wanders)
--   * species 0 (no course won yet) -> no statue
--
--   * A at a statue reads the plaque (bg event #2-#4 on the same tile), not the
--     object: the field's facing-object test (sub_0203DC64 -> sub_0203DBD4)
--     only answers for an object at the player's height, and the statue
--     stands on its pedestal -- INFERRED from the room's layout (each plaque
--     shares its statue's tile, as "It's your statue!" shares the player
--     statue's), the pedestal heights were not measured
--
-- STAND-INS, said so:
--   * MapObject_SetParam(0, 2) and the object flags (bit 30 set, flag 29
--     clear) are not read; the statue is the Pokemon's ordinary walking
--     sheet, standing still, in its own colours

local S = {}

S.FIRST_ID = 0xF6
S.POSITIONS = { { 4, 10 }, { 7, 5 }, { 10, 10 } }   -- sFriendshipRoomStatuesPositions

local function female(g)
  if g == 1 then return true end
  if type(g) == "string" then
    local l = g:lower()
    return l == "female" or l == "f"
  end
  return false
end

-- the walking-Pokemon sheet's sprite key (registered in game.data.sprites
-- the way src/world/HgssFollowMon.lua registers the follower's), never shiny
function S.spriteKey(game, statue)
  local data = game and game.data
  local r = data and data.gen4_follow_mon
  if not (r and r.sheets) then return nil end
  local Data = require("src.import.Gen4HgssFollowMon")
  local idx = Data.index(r, tonumber(statue.species), tonumber(statue.form) or 0, female(statue.gender))
  local sheet = r.sheets[idx] or r.sheets[tostring(idx)]
  if not sheet then return nil end
  local key = ("SPRITE_FOLLOW_%03d"):format(idx)
  data.sprites = data.sprites or {}
  if not data.sprites[key] then
    data.sprites[key] = {
      id = key, image = sheet.normal,
      frames = sheet.frames or 8, frameWidth = sheet.frameWidth or 32,
      frameHeight = sheet.frameHeight or 32, facings = r.facings,
      walker = true, trueColor = true,
    }
  end
  return key
end

-- ScrCmd_CreatePokeathlonFriendshipRoomStatues on the overworld `ow`
function S.create(game, ow)
  local def = ow and ow.map and ow.map.def
  if not (def and def.objects) then return 0 end
  local save = (game and game.save) or {}
  local records = save.hgssPokeathlonStatues or {}
  -- the previous statues (MapObjectManager_GetFirstActiveObjectByID + Delete)
  for i = #def.objects, 1, -1 do
    local o = def.objects[i]
    if o.hgssStatue then
      o.hidden = true
      if ow.syncObjectVisibility then pcall(function() ow:syncObjectVisibility(o) end) end
      table.remove(def.objects, i)
    end
  end
  local maxIndex = 0
  for _, o in ipairs(def.objects) do maxIndex = math.max(maxIndex, tonumber(o.index) or 0) end
  local made = 0
  for i = 1, 3 do
    local r = records[i]
    local species = r and tonumber(r.species) or 0
    if species ~= 0 and species <= 493 then
      local key = S.spriteKey(game, r)
      if key then
        maxIndex = maxIndex + 1
        local obj = { index = maxIndex, localId = S.FIRST_ID + i - 1, graphicsId = 415 + i - 1,
          sprite = key, spriteName = "follower_mon", x = S.POSITIONS[i][1], y = S.POSITIONS[i][2],
          direction = 1, movementType = 0, movementRangeX = 0, movementRangeY = 0, flag = 0,
          script = 0, scriptKind = "none", elevation = 0, hgssStatue = true,
          -- in the way but never answers A (npcAtCell): the plaque under it does
          gen5Blocker = true }
        def.objects[#def.objects + 1] = obj
        if ow.syncObjectVisibility then pcall(function() ow:syncObjectVisibility(obj) end) end
        made = made + 1
      end
    end
  end
  return made
end

return S
