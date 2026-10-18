-- WHERE A HEARTGOLD / SOULSILVER GAME STARTS, WHERE A BLACKOUT SENDS YOU, AND
-- WHICH SHEETS THE PLAYER WEARS.
--
-- The same two things Gen4Field finds for Platinum, in HGSS's own shapes:
--
--   sLocation_PlayerRoom, then sLocation_OutsidePlayerHome (src/location_backup.c)
--     Location = { s32 mapId, s32 warpId (-1), s32 x, s32 y, s32 direction }
--     -- the player's bedroom (NEW_BARK_PLAYER_HOUSE_2F, 6, 6, facing down)
--     and the tile outside the front door
--
--   sSpawnMaps (asm/unk_0203BA5C.s), 18 bytes a row, not Platinum's 16:
--     u16 flagIdx:8 isBlackoutSpawn:1 isFlyPoint:1   u16 deathSpawnMap
--     u8 deathX, u8 deathY                           u16 flyMap, flyX, flyY
--     u16 specialWarpMap, specialX, specialY
--
-- BOTH FOUND BY SIGNATURE in the decompressed ARM9, and tied together the way
-- Gen4Field ties Platinum's: the location after the start IS the first spawn
-- row's fly point (New Bark Town, outside the player's house), so two tables
-- have to agree before either is believed. pret's values are what
-- tools/gen4_hgss_import_check.lua expects to come back.
--
-- THE PLAYER'S SHEETS come from PlayerAvatar's state switch (src/player_avatar.c):
-- walking HERO, cycling CYCLEHERO, surfing SWIMHERO, using an HM SPHERO,
-- fishing FISHINGHERO, and the HEROINE of each.

local F = {}

F.SPAWN_BYTES = 18
F.LOCATION_BYTES = 20
F.MIN_SPAWN_ROWS = 20
F.WARP_NONE = 0xFFFFFFFF

-- sprite ids (pokeheartgold include/constants/sprites.h)
F.PLAYER = {
  boy = { label = "BOY", walk = 0, bike = 21, surf = 178, fieldMove = 176, fishing = 188 },
  girl = { label = "GIRL", walk = 97, bike = 98, surf = 179, fieldMove = 177, fishing = 189 },
}

local function u16(s, at) local a, b = s:byte(at + 1, at + 2); return b and a + b * 256 end
local function u32(s, at) local lo, hi = u16(s, at), u16(s, at + 2); return hi and lo + hi * 65536 end

local function row(s, at)
  local flags = u16(s, at)
  if not flags then return nil end
  return {
    flagIdx = flags % 256,
    isBlackoutSpawn = math.floor(flags / 256) % 2 == 1,
    isFlyPoint = math.floor(flags / 512) % 2 == 1,
    high = math.floor(flags / 1024),
    blackOutMap = u16(s, at + 2), blackOutX = s:byte(at + 5), blackOutZ = s:byte(at + 6),
    flyMap = u16(s, at + 6), flyX = u16(s, at + 8), flyZ = u16(s, at + 10),
    specialMap = u16(s, at + 12), specialX = u16(s, at + 14), specialZ = u16(s, at + 16),
  }
end

local function plausible(r, count)
  return r and r.high == 0 and r.blackOutMap and r.blackOutMap > 0 and r.blackOutMap < count
    and r.flyMap and r.flyMap > 0 and r.flyMap < count
    and r.specialMap and r.specialMap > 0 and r.specialMap < count
end

-- spawns(arm9, headerCount) -> rows, offset
function F.spawns(arm9, count)
  local bestAt, bestRows = nil, 0
  local at = 0
  while at <= #arm9 - F.SPAWN_BYTES do
    if plausible(row(arm9, at), count) then
      local n = 0
      while plausible(row(arm9, at + n * F.SPAWN_BYTES), count) do n = n + 1 end
      if n > bestRows then bestAt, bestRows = at, n end
      at = at + math.max(n, 1) * F.SPAWN_BYTES
    else
      at = at + 2
    end
  end
  if not bestAt or bestRows < F.MIN_SPAWN_ROWS then return nil end
  local out = {}
  for i = 0, bestRows - 1 do out[i + 1] = row(arm9, bestAt + i * F.SPAWN_BYTES) end
  return out, bestAt
end

local function location(s, at)
  local map, warp = u32(s, at), u32(s, at + 4)
  if not warp then return nil end
  return { mapHeaderID = map, warpId = warp, x = u32(s, at + 8), z = u32(s, at + 12),
           facing = u32(s, at + 16) }
end

-- the run of plausible rows starting exactly at `at`
local function runAt(arm9, at, count)
  local n = 0
  while plausible(row(arm9, at + n * F.SPAWN_BYTES), count) do n = n + 1 end
  return n
end

-- find(arm9, headerCount) -> start, respawn, locationOffset, spawns, spawnOffset
--
-- THE LOCATION PAIR FIRST, THEN THE TABLE THAT AGREES WITH IT. Scanning for
-- the longest run of plausible spawn rows on its own finds 56 "rows" of
-- something else (0, 1, 2, 3 ... counting up) ahead of the real 27, because an
-- 18-byte row of small numbers is a weak shape. So each candidate pair is
-- asked for a table whose FIRST row flies to the pair's second location, and
-- exactly one pair, with exactly one such table, has to answer.
function F.find(arm9, count)
  if type(arm9) ~= "string" then return nil, "no arm9" end
  local matches = {}
  for at = 0, #arm9 - F.LOCATION_BYTES * 2, 4 do
    local start = location(arm9, at)
    if start and start.warpId == F.WARP_NONE and start.mapHeaderID > 0 and start.mapHeaderID < count
       and start.facing <= 3 then
      local after = location(arm9, at + F.LOCATION_BYTES)
      if after and after.warpId == F.WARP_NONE and after.mapHeaderID > 0 and after.mapHeaderID < count
         and after.facing <= 3 and after.mapHeaderID ~= start.mapHeaderID then
        -- the spawn row whose fly point is `after`: u16 map, x, y at +6
        local needle = string.char(after.mapHeaderID % 256, math.floor(after.mapHeaderID / 256),
          after.x % 256, math.floor(after.x / 256) % 256, after.z % 256, math.floor(after.z / 256) % 256)
        local from = 1
        while true do
          local i = arm9:find(needle, from, true)
          if not i then break end
          local rowAt = i - 1 - 6
          if rowAt >= 0 then
            local n = runAt(arm9, rowAt, count)
            if n >= F.MIN_SPAWN_ROWS then
              matches[#matches + 1] = { at = at, start = start, respawn = after, spawnAt = rowAt, rows = n }
            end
          end
          from = i + 1
        end
      end
    end
  end
  if #matches ~= 1 then
    return nil, ("expected one start/outside pair with its spawn table, found %d"):format(#matches)
  end
  local m = matches[1]
  local spawns = {}
  for i = 0, m.rows - 1 do spawns[i + 1] = row(arm9, m.spawnAt + i * F.SPAWN_BYTES) end
  return m.start, m.respawn, m.at, spawns, m.spawnAt
end

-- playerSheets(spriteFor) -> playerSprites, playerForms, in Platinum's shape
function F.playerSheets(spriteFor)
  local forms = { order = {} }
  for _, key in ipairs({ "boy", "girl" }) do
    local ids = F.PLAYER[key]
    local form = { label = ids.label }
    form.back = ("assets/generated/gen4/battle/trainer_back/%03d.png"):format(key == "girl" and 1 or 0)
    for _, state in ipairs({ "walk", "bike", "surf", "fieldMove", "fishing" }) do
      form[state] = spriteFor(ids[state])
    end
    if form.walk then forms.order[#forms.order + 1] = key; forms[key] = form end
  end
  local default = forms.boy or forms.girl
  if not default then return nil, nil end
  return { walk = default.walk, bike = default.bike, surf = default.surf,
           fieldMove = default.fieldMove, fishing = default.fishing }, forms
end

return F
