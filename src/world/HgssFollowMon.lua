-- HEARTGOLD / SOULSILVER'S WALKING POKEMON (pokeheartgold src/follow_mon.c;
-- the full spec with ROM addresses is scratch_claude/follow_mon_spec.md, the
-- data is src/import/Gen4HgssFollowMon.lua's `gen4_follow_mon`).
--
-- WHO: the first party Pokemon that is neither fainted nor an egg
-- (GetFirstAliveMonInParty); nobody when every one has fainted.
--
-- WHERE: the map header's followMode -- 0 never, 1 only a Pokemon that is not
-- too tall (the 31 64x64 followers: Steelix, Lugia, Ho-Oh, Wailord, the
-- Hoenn and Sinnoh legends, Regigigas, Giratina, Arceus), 2 always -- and
-- never Diglett / Dugtrio in the Bell Tower. Hidden (recalled into its ball)
-- while the player bikes or surfs, and while a script has recalled it (600)
-- or set the inhibit flag (783), tracking the player's tile all the while.
--
-- HOW IT MOVES: it is put down on the player's own tile, hidden, and comes
-- out on the player's first step; from then on it walks to the tile the
-- player is leaving, at the player's step length (sub_02065DF4), turning in
-- place moves nothing, and it never blocks the player -- walking into it
-- swaps the two. The trail is Gen4Follower's (the frame the player commits a
-- step the follower is sent to the vacated cell), which is the same rule.
--
-- TALKING TO IT (std 9700, FollowMonInteract): the cartridge's own rules --
-- /a/2/2/0 member mapsec + 1 (thirty for the place) and member 0 (seventy
-- general), evaluated 30..41, 0..29, 42..99, the first whose conditions all
-- hold and whose chance roll passes -- pick a /a/2/2/1 result: up to five
-- steps of hop / line of bank 265 / wait, an optional YES / NO branch, and
-- the friendship and mood deltas. A condition this port cannot read (the
-- tile behaviour under it, the Pokeathlon stars, Shiny Leaves) is a field
-- that holds a value the context does not, so that rule simply does not
-- match -- the general rules always end in a 100% fallback.

local F = {}

F.INDEX = 0x7FFE         -- the npc index the follower takes (out of map range)
F.LOCAL_ID = 253         -- obj_partner_poke
F.BELL_TOWER = { D17R0101 = true, D17R0102 = true, D17R0103 = true, D17R0104 = true,
  D17R0105 = true, D17R0106 = true, D17R0107 = true, D17R0108 = true,
  D17R0109 = true, D17R0110 = true, D17R0111 = true }

local function rec(game)
  local data = game and game.data
  return data and data.gen4_follow_mon
end

function F.active(game)
  return rec(game) ~= nil
end

local function state(save)
  save.hgssFollowMon = save.hgssFollowMon or {}
  return save.hgssFollowMon
end

local function isEgg(mon) return mon.isEgg or mon.egg end

function F.lead(save)
  for i, mon in ipairs((save and save.party) or {}) do
    if not isEgg(mon) and (tonumber(mon.hp) or 0) > 0 then return mon, i end
  end
  return nil
end

local function female(game, mon)
  local ok, Pokemon = pcall(require, "src.pokemon.Pokemon")
  return ok and Pokemon.genderOf and Pokemon.genderOf(game.data, mon) == "female"
end

local function spriteKey(game, mon)
  local r = rec(game)
  local Data = require("src.import.Gen4HgssFollowMon")
  local idx = Data.index(r, tonumber(mon.species), tonumber(mon.form) or 0, female(game, mon))
  local sheet = r.sheets and (r.sheets[idx] or r.sheets[tostring(idx)])
  if not sheet then return nil end
  local shiny = mon.shiny or mon.isShiny
  local key = ("SPRITE_FOLLOW_%03d%s"):format(idx, shiny and "_S" or "")
  local sprites = game.data.sprites
  if sprites and not sprites[key] then
    sprites[key] = {
      id = key, image = shiny and sheet.shiny or sheet.normal,
      frames = sheet.frames or 8, frameWidth = sheet.frameWidth or 32,
      frameHeight = sheet.frameHeight or 32, facings = r.facings,
      walker = true, trueColor = true,
    }
  end
  return key, idx
end

local function tooTall(game, mon)
  local r = rec(game)
  local Data = require("src.import.Gen4HgssFollowMon")
  -- FollowMon_GetSizeParamBySpecies reads the BASE index, not the form's
  local base = r.lut[tonumber(mon.species)] or r.lut[tostring(mon.species)] or 0
  return r.tooTall[base] or r.tooTall[tostring(base)] or false
end

local function headerOf(game, ow)
  local def = ow.map and ow.map.def
  local header = def and tonumber(def.header)
  local headers = game.data.gen4_map_headers
  return headers and header and (headers[header] or (headers.headers and headers.headers[header])) or nil
end

local function followMode(game, ow)
  local h = headerOf(game, ow)
  return h and tonumber(h.followMode) or 2
end

function F.allowedIndoors(game, mon)
  return not tooTall(game, mon)
end

function F.allowed(game, ow, mon)
  if not mon then return false end
  local s = tonumber(mon.species)
  if (s == 50 or s == 51) and F.BELL_TOWER[ow.map and ow.map.id or ""] then return false end
  local mode = followMode(game, ow)
  if mode == 0 then return false end
  if mode == 1 and tooTall(game, mon) then return false end
  return true
end

function F.current(ow)
  for _, npc in ipairs((ow and ow.npcs) or {}) do
    if npc.hgssFollowMon then return npc end
  end
  return nil
end

local function remove(ow)
  for _, list in ipairs({ ow.npcs or {}, ow.entities or {} }) do
    for i = #list, 1, -1 do
      if list[i].hgssFollowMon then table.remove(list, i) end
    end
  end
end

local function spawn(game, ow, mon)
  local key = spriteKey(game, mon)
  if not key then return nil end
  local p = ow.player
  local NPC = require("src.world.NPC")
  local npc = NPC.new(game.data, ow.map.id, {
    index = F.INDEX, localId = F.LOCAL_ID, sprite = key,
    x = p.cellX, y = p.cellY, movementType = 0, direction = 1,
  })
  npc.facing = p.facing or "down"
  npc.hgssFollowMon = true
  npc.passable = true
  npc.hidden = true
  npc.followSpecies = mon.species
  npc.followKey = key
  table.insert(ow.npcs, npc)
  table.insert(ow.entities, npc)
  ow.hgssFollowTrail = { x = p.cellX, y = p.cellY }
  ow.hgssFollowPending = { x = p.cellX, y = p.cellY }   -- out on the first step
  return npc
end

-- Called from OverworldState:setMap after the map's cast is stood up.
function F.onMapEntered(game, ow)
  if not (ow and ow.map and F.active(game)) then return end
  remove(ow)
  ow.hgssFollowTrail, ow.hgssFollowPending, ow.hgssFollowTalk = nil, nil, nil
  local save = game.save or {}
  -- SaveFollowMon's inhibit flag is cleared on every map change
  state(save).inhibit = nil
  local mon = F.lead(save)
  if not (mon and F.allowed(game, ow, mon)) then return end
  spawn(game, ow, mon)
end

local function hiddenNow(game, ow)
  local save = game.save or {}
  local st = state(save)
  return save.onBike or (ow.player and ow.player.surfing) or st.inhibit or st.recalled
end

-- a different lead (a faint, a switch, an evolution) swaps the picture in place
local function refreshLead(game, ow, npc)
  local mon = F.lead(game.save)
  if not mon or not F.allowed(game, ow, mon) then
    remove(ow)
    return nil
  end
  local key = spriteKey(game, mon)
  if key and key ~= npc.followKey then
    local SpriteRenderer = require("src.render.SpriteRenderer")
    npc.sprite = SpriteRenderer.new(game.data.sprites[key], npc.id)
    npc.followKey, npc.followSpecies = key, mon.species
    -- FieldSystemUnkSub108: a new lead starts at mood 0
    mon.hgssMood = 0
  end
  return npc
end

function F.update(game, ow)
  if not (ow and ow.map and F.active(game)) then return end
  local npc = F.current(ow)
  local p = ow.player
  if not p then return end
  if not npc then
    -- a Pokemon that has come back to the party, or the map now allows it
    local mon = F.lead(game.save)
    if mon and F.allowed(game, ow, mon) and not hiddenNow(game, ow) then spawn(game, ow, mon) end
    return
  end
  if (ow.hgssFollowTick or 0) % 30 == 0 then npc = refreshLead(game, ow, npc) end
  ow.hgssFollowTick = (ow.hgssFollowTick or 0) + 1
  if not npc then return end

  F.tickTalk(game, ow, npc)

  local trail = ow.hgssFollowTrail
  if not trail then
    trail = { x = p.cellX, y = p.cellY }
    ow.hgssFollowTrail = trail
  end
  local destX, destY = p.targetX or p.cellX, p.targetY or p.cellY

  -- RECALLED: invisible, standing on the player's tile, out again on the
  -- first step after the reason ends
  if hiddenNow(game, ow) then
    npc.hidden = true
    npc.cellX, npc.cellY = p.cellX, p.cellY
    npc.px, npc.py = p.cellX * 16, p.cellY * 16
    npc.moving, npc.goalX, npc.goalY = false, nil, nil
    trail.x, trail.y = destX, destY
    ow.hgssFollowPending = { x = p.cellX, y = p.cellY }
    return
  end
  local pending = ow.hgssFollowPending
  if pending then
    if destX == pending.x and destY == pending.y then
      trail.x, trail.y = destX, destY
      return
    end
    ow.hgssFollowPending = nil
    npc.hidden = false
  end

  local st = state(game.save or {})
  if st.paused then
    trail.x, trail.y = destX, destY
    return
  end
  if destX ~= trail.x or destY ~= trail.y then
    npc.goalX, npc.goalY = trail.x, trail.y
    trail.x, trail.y = destX, destY
  end
  if npc.moving or not npc.goalX then return end
  local gx, gy = npc.goalX, npc.goalY
  if npc.cellX == gx and npc.cellY == gy then
    npc.goalX, npc.goalY = nil, nil
    -- arrived and the player is standing: face the way the player faces
    if not p.moving then npc.facing = p.facing or npc.facing end
    return
  end
  local far = math.abs(npc.cellX - gx) + math.abs(npc.cellY - gy)
  if far > 6 then
    npc.cellX, npc.cellY = gx, gy
    npc.px, npc.py = gx * 16, gy * 16
    npc.goalX, npc.goalY = nil, nil
    return
  end
  local dir
  if npc.cellX > gx then dir = "left"
  elseif npc.cellX < gx then dir = "right"
  elseif npc.cellY <= gy then dir = "down"
  else dir = "up" end
  npc.facing = dir
  npc.targetX = npc.cellX + (dir == "right" and 1 or dir == "left" and -1 or 0)
  npc.targetY = npc.cellY + (dir == "down" and 1 or dir == "up" and -1 or 0)
  local stepLen = p.stepFramesCur or p.stepFrames or 16
  if far > 1 then stepLen = math.max(1, math.floor(stepLen / 2)) end
  npc.stepFrames = stepLen
  npc.moving = true
  npc.progress = 0
  npc:update(ow.map, ow.entities)
end

-- ---------------------------------------------------------------- scripts

-- 600 recall, 606 out on the next step, 607 onto the player, 609 reset,
-- 602 pause / unpause, 783 inhibit, 729 / 730 active, 727 the lead's slot,
-- 596 too tall, 732 mood
function F.command(game, ow, op, a, b)
  local save = game.save or {}
  local st = state(save)
  local npc = ow and F.current(ow)
  local p = ow and ow.player
  if op == "recall" then
    st.recalled = true
  elseif op == "unrecall" then
    st.recalled = nil
  elseif op == "release" or op == "snap" then
    st.recalled = nil
    if npc and p then
      npc.cellX, npc.cellY = p.cellX, p.cellY
      npc.px, npc.py = p.cellX * 16, p.cellY * 16
      npc.moving, npc.goalX, npc.goalY = false, nil, nil
      npc.hidden = true
      ow.hgssFollowPending = { x = p.cellX, y = p.cellY }
      if op == "snap" then npc.facing = "down" end
    end
  elseif op == "reset" then
    if npc then
      npc.moving, npc.goalX, npc.goalY = false, nil, nil
      npc.targetX, npc.targetY, npc.progress = nil, nil, 0
      npc.px, npc.py = npc.cellX * 16, npc.cellY * 16
    end
  elseif op == "pause" then
    st.paused = (tonumber(a) or 0) ~= 0 or nil
  elseif op == "inhibit" then
    st.inhibit = (tonumber(a) or 0) ~= 0 or nil
  elseif op == "faceplayer" then
    if npc and p then npc:facePlayer(p) end
  end
end

function F.isActive(game, ow)
  local npc = ow and F.current(ow)
  return npc ~= nil and not npc.hidden
end

-- ------------------------------------------------------------------ talking

local function bytes(hex)
  if type(hex) ~= "string" then return nil end
  return (hex:gsub("%x%x", function(h) return string.char(tonumber(h, 16)) end))
end
local function u8(s, i) return s:byte(i + 1) or 0 end
local function u16(s, i) return (s:byte(i + 1) or 0) + (s:byte(i + 2) or 0) * 256 end
local function s8(s, i) local v = u8(s, i) return v >= 128 and v - 256 or v end

local TYPE_CODE = { NORMAL = 1, FIGHTING = 7, FLYING = 10, POISON = 8, GROUND = 9, ROCK = 13,
  BUG = 12, GHOST = 14, STEEL = 17, FIRE = 2, WATER = 3, GRASS = 5, ELECTRIC = 4,
  PSYCHIC = 11, ICE = 6, DRAGON = 15, DARK = 16 }
local NATURE_GROUP = { 4, 5, 4, 4, 1, 4, 3, 2, 1, 2, 5, 6, 3, 1, 1, 3, 6, 3, 5, 6, 2, 2, 1, 3, 6 }
local STATUS_CODE = { BRN = 2, FRZ = 3, PAR = 4, PSN = 5, TOX = 5, SLP = 8 }
local FACING_CODE = { up = 3, down = 4, left = 2, right = 1 }

local function timeOfDay(now)
  local h = os.date("*t", now or os.time()).hour
  if h >= 4 and h < 10 then return 1 end
  if h >= 10 and h < 17 then return 2 end
  if h >= 17 and h < 20 then return 3 end
  if h >= 20 then return 4 end
  return 5
end

local function moodBracket(m, want)
  if want == 1 then return m == 127 elseif want == 2 then return m >= 100 and m <= 126
  elseif want == 3 then return m >= 50 and m <= 99 elseif want == 4 then return m >= 30 and m <= 49
  elseif want == 5 then return m >= -29 and m <= 29 elseif want == 6 then return m >= -49 and m <= -30
  elseif want == 7 then return m >= -126 and m <= -50 elseif want == 8 then return m == -127
  elseif want == 9 then return m >= 0 elseif want == 10 then return m < 0 end
  return false
end

local function friendBracket(f, want)
  if want == 1 then return f == 255 elseif want == 2 then return f >= 200 and f <= 254
  elseif want == 3 then return f >= 150 and f <= 199 elseif want == 4 then return f >= 90 and f <= 149
  elseif want == 5 then return f >= 60 and f <= 89 elseif want == 6 then return f >= 30 and f <= 59
  elseif want == 7 then return f >= 1 and f <= 29 elseif want == 8 then return f == 0
  elseif want == 9 then return f >= 90 elseif want == 10 then return f < 60 end
  return false
end

local function context(game, ow, npc, mon)
  local data = game.data
  local def = data.pokemon and data.pokemon[tonumber(mon.species)] or {}
  local hp, max = tonumber(mon.hp) or 0, math.max(1, tonumber(mon.maxHp) or 1)
  local c = {}
  c.hp = hp >= max and 1 or (hp * 4 >= max * 3 and 2) or (hp * 2 >= max and 3) or (hp * 4 >= max and 4) or 5
  c.status = STATUS_CODE[mon.status] or 1
  c.item = (tonumber(mon.item or mon.heldItem) or 0) ~= 0
  c.types = {}
  for _, t in ipairs(def.types or {}) do c.types[#c.types + 1] = TYPE_CODE[t] or 0 end
  c.friendship = tonumber(mon.happiness or mon.friendship) or 0
  c.nature = NATURE_GROUP[((tonumber(mon.personality) or 0) % 25) + 1]
  c.gender = female(game, mon) and 2 or 1
  local groups = bytes(rec(game).talk and rec(game).talk.groups)
  c.group = groups and u8(groups, (tonumber(mon.species) or 1) - 1) or 0
  local near = 0
  local p = ow.player
  for _, e in ipairs(ow.npcs or {}) do
    if e ~= npc and not e.hidden and math.abs(e.cellX - p.cellX) <= 1 and math.abs(e.cellY - p.cellY) <= 1 then
      near = near + 1
    end
  end
  c.near = near
  c.hiddenItems = 0
  c.weather = 1
  c.encounter = 2
  c.time = timeOfDay()
  c.mood = tonumber(mon.hgssMood) or 0
  c.facing = FACING_CODE[npc.facing] or 4
  c.map = tonumber(ow.map.def and ow.map.def.header) or 0
  return c
end

-- one 20-byte rule against the context: the result id, or nil
local function evaluate(r, c, roll)
  local result = math.floor(u16(r, 10) / 64)
  if result == 0 then return nil end
  local function eq(field, value) return field == 0 or field == value end
  if not eq(u8(r, 0), c.hp) then return nil end
  local b1 = u8(r, 1)
  if b1 % 16 ~= 0 and not moodBracket(c.mood, b1 % 16) then return nil end
  if math.floor(b1 / 16) ~= 0 and not friendBracket(c.friendship, math.floor(b1 / 16)) then return nil end
  local b2 = u8(r, 2)
  if not eq(b2 % 8, c.nature) then return nil end
  if not eq(math.floor(b2 / 8) % 4, c.gender) then return nil end
  local st = math.floor(b2 / 32)
  if st == 7 then if c.status == 1 then return nil end
  elseif st ~= 0 and st ~= c.status then return nil end
  local item = u8(r, 3) % 32
  if item == 9 then if not c.item then return nil end
  elseif item ~= 0 then return nil end   -- the pocket class is not read here
  local b4 = u8(r, 4)
  local ty = b4 % 32
  if ty ~= 0 and ty ~= c.types[1] and ty ~= c.types[2] then return nil end
  if math.floor(b4 / 32) ~= 0 then return nil end   -- Pokeathlon stars
  if not eq(u8(r, 5), c.encounter) then return nil end
  local grp = u8(r, 6)
  if grp ~= 0 then
    local g = c.group
    local ok = (grp <= 0xF9 and g == grp) or (grp == 0xFA and g <= 0x13) or (grp == 0xFB and g <= 0x82)
      or (grp == 0xFC and g >= 0x8C and g <= 0x95) or (grp == 0xFD and g >= 0xA0) or (grp == 0xFE and g >= 0xDC)
    if not ok then return nil end
  end
  -- +7 Shiny Leaf n: passes while the Pokemon does not have it (none here)
  local w8 = u16(r, 8)
  if not eq(w8 % 8, c.weather) then return nil end
  if not eq(math.floor(w8 / 8192), c.facing) then return nil end
  local w10 = u16(r, 10)
  local near = w10 % 8
  if near ~= 0 and not (near == 5 and c.near >= 5 or near == c.near) then return nil end
  if not eq(math.floor(w10 / 8) % 8, c.time) then return nil end
  local map = u16(r, 12)
  if map ~= 0 and map ~= c.map + 1 then return nil end
  if u16(r, 14) ~= 0 then return nil end   -- the tile behaviour under it
  local b16 = u8(r, 16)
  if math.floor(b16 / 2) % 4 ~= 0 then return nil end
  if math.floor(b16 / 8) % 4 ~= 0 then return nil end
  local hid = math.floor(b16 / 32)
  if hid ~= 0 and not (hid == 4 and c.hiddenItems >= 4 or hid == c.hiddenItems) then return nil end
  local flag = u16(r, 18)
  if flag ~= 0 then return nil end   -- an event flag (gifts already given)
  local chance = u8(r, 17)
  if roll(100) >= chance then return nil end
  return result
end

function F.pickResult(game, ow, npc, mon, roll)
  roll = roll or function(n) return love.math.random(0, n - 1) end
  local talk = rec(game).talk or {}
  local general = bytes(talk.rules and (talk.rules[0] or talk.rules["0"]))
  local h = headerOf(game, ow)
  local mapsec = tonumber(h and h.mapsec) or -1
  local place = mapsec >= 0 and bytes(talk.rules and (talk.rules[mapsec + 1] or talk.rules[tostring(mapsec + 1)])) or nil
  local c = context(game, ow, npc, mon)
  local function rule(n)
    if n < 30 then return place and #place >= (n + 1) * 20 and place:sub(n * 20 + 1, n * 20 + 20) end
    local k = n - 30
    return general and #general >= (k + 1) * 20 and general:sub(k * 20 + 1, k * 20 + 20)
  end
  local order = {}
  for n = 30, 41 do order[#order + 1] = n end
  for n = 0, 29 do order[#order + 1] = n end
  for n = 42, 99 do order[#order + 1] = n end
  for _, n in ipairs(order) do
    local r = rule(n)
    local result = r and evaluate(r, c, roll)
    if result then return result, n end
  end
  return nil
end

local function line(game, msg)
  local T = require("src.import.Gen4Text")
  local text = game.data.text and game.data.text[T.label(265, msg - 1)]
  local Commands = require("src.script.Commands")
  if Commands.gen4Markup then text = Commands.gen4Markup(text, game) end
  return type(text) == "string" and text or nil
end

local function buffers(game, ow, mon)
  local data = game.data
  local def = data.pokemon and data.pokemon[tonumber(mon.species)] or {}
  game.stringBuffers = game.stringBuffers or {}
  local b = game.stringBuffers
  b[1] = mon.nickname or mon.name or def.name or ""
  b[2] = def.name or ""
  b[3] = (game.save and game.save.player and game.save.player.name) or ""
  local h = headerOf(game, ow)
  b[4] = (h and h.label) or ""
  local item = tonumber(mon.item or mon.heldItem)
  local idef = item and data.items and data.items[item]
  b[5] = idef and idef.name or ""
end

-- A on the follower: face the player, pick a rule, play its result
function F.talk(game, ow, npc)
  local mon = F.lead(game.save)
  if not mon then return end
  if npc.moving then
    npc.cellX, npc.cellY = npc.targetX or npc.cellX, npc.targetY or npc.cellY
    npc.px, npc.py = npc.cellX * 16, npc.cellY * 16
    npc.targetX, npc.targetY, npc.moving, npc.progress = nil, nil, false, 0
  end
  npc:facePlayer(ow.player)
  local result = F.pickResult(game, ow, npc, mon)
  buffers(game, ow, mon)
  F.play(game, ow, npc, mon, result)
end

-- the result's steps, one at a time: the hop runs in update, a line pushes a
-- text box, and the deltas land when the last step is done
function F.play(game, ow, npc, mon, result)
  local talk = rec(game).talk or {}
  -- one 52-byte member per result, result id 1-based (ov02_0224F880)
  local r = result and talk.results and bytes(talk.results[result - 1] or talk.results[tostring(result - 1)])
  if not r then
    local text = line(game, 1)
    if text then game.stack:push(require("src.render.TextBox").new(game, text)) end
    return
  end
  local steps = {}
  for i = 0, 4 do
    local anim = u16(r, i * 8)
    if anim == 0xFFFF then break end
    steps[#steps + 1] = { anim = anim, msg = u16(r, i * 8 + 2), wait = u8(r, i * 8 + 7) }
  end
  ow.hgssFollowTalk = {
    npc = npc, mon = mon, steps = steps, at = 1, phase = "start",
    ask = u16(r, 0x28) + u16(r, 0x2A) * 65536 ~= 0,
    yes = u16(r, 0x2C), no = u16(r, 0x2E),
    friendship = s8(r, 0x30), mood = s8(r, 0x31),
  }
  ow.hgssFollowFrozen = true
end

local function finish(game, ow, t)
  local mon = t.mon
  local f = (tonumber(mon.happiness or mon.friendship) or 0) + t.friendship
  mon.happiness = math.max(0, math.min(255, f))
  mon.hgssMood = math.max(-127, math.min(127, (tonumber(mon.hgssMood) or 0) + t.mood))
  t.npc.spriteOffset = nil
  ow.hgssFollowTalk, ow.hgssFollowFrozen = nil, nil
end

function F.tickTalk(game, ow, npc)
  local t = ow.hgssFollowTalk
  if not t then return end
  if t.phase == "box" then return end
  local step = t.steps[t.at]
  if not step then
    if t.ask and (t.yes ~= 0 or t.no ~= 0) and not t.asked then
      t.asked = true
    end
    return finish(game, ow, t)
  end
  if t.phase == "start" then
    t.frames = {}
    local anims = rec(game).talk and rec(game).talk.anims
    local a = anims and step.anim > 0 and bytes(anims[step.anim - 1] or anims[tostring(step.anim - 1)])
    if a and #a == 80 then
      for k = 0, 9 do
        if u8(a, k * 8) == 0xFF then break end
        t.frames[#t.frames + 1] = { dur = math.max(1, u8(a, k * 8 + 1)), dy = s8(a, k * 8 + 3) }
      end
    end
    t.fi, t.ft, t.lift = 1, 0, 0
    t.phase = "anim"
  end
  if t.phase == "anim" then
    local fr = t.frames[t.fi]
    if fr then
      if t.ft == 0 then
        local s = tonumber(npc.followSpecies)
        if s ~= 50 and s ~= 51 then t.lift = t.lift + fr.dy end
        npc.spriteOffset = { lift = t.lift, y = -t.lift }
      end
      t.ft = t.ft + 1
      if t.ft >= fr.dur then t.fi, t.ft = t.fi + 1, 0 end
      return
    end
    npc.spriteOffset = nil
    t.phase = "msg"
  end
  if t.phase == "msg" then
    local text = step.msg > 0 and line(game, step.msg)
    local last = t.at == #t.steps
    if text then
      t.phase = "box"
      local opts
      if last and t.ask then
        opts = { choice = function(yes)
          t.phase = "wait"
          t.waitLeft = 0
          local nextResult = yes and t.yes or t.no
          finish(game, ow, t)
          if nextResult and nextResult ~= 0 then F.play(game, ow, t.npc, t.mon, nextResult) end
        end }
      end
      game.stack:push(require("src.render.TextBox").new(game, text, function()
        t.phase = "wait"
        t.waitLeft = step.wait
      end, opts))
      return
    end
    t.phase = "wait"
    t.waitLeft = step.wait
  end
  if t.phase == "wait" then
    if (t.waitLeft or 0) > 0 then t.waitLeft = t.waitLeft - 1 return end
    t.at, t.phase = t.at + 1, "start"
  end
end

-- a step taken while the follower is out: its mood drifts one toward zero
function F.onStep(game, ow)
  if not F.isActive(game, ow) then return end
  local mon = F.lead(game.save)
  local m = mon and tonumber(mon.hgssMood) or 0
  if mon and m ~= 0 then mon.hgssMood = m > 0 and m - 1 or m + 1 end
end

return F
