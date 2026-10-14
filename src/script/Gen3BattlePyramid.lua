-- EMERALD'S BATTLE PYRAMID (pokeemerald battle_pyramid.c, CallBattlePyramidFunction
-- = special 243, and the pieces of item.c, wild_encounter.c, battle_setup.c and
-- field_control_avatar.c that ask "are we in the Pyramid?").
--
-- Seven dark floors and a summit. Each floor is FOUR BY FOUR SQUARES of eight
-- by eight tiles, the squares drawn from BattlePyramidSquare01..16 by a floor
-- template (sPyramidFloorTemplates, picked by the floor and a roll), every
-- square's exit tile turned into plain floor but the one in the exit square,
-- and the player put down on the entrance square's. Trainers and item balls go
-- where the squares' own object events stand, placed by the template's rule
-- (uniformly, in and near the entrance or exit square, or near it). All of it
-- falls out of four saved u16s (frontier.pyramidRandoms), so a floor is the
-- same floor every time it is loaded -- this module rebuilds it from them.
--
-- THE FLOOR IN THIS PORT: the Floor map's def (MAP_G26_N26, an 8x8 stand-in on
-- the cartridge too) is rewritten in place as the 32x32 floor each time it is
-- loaded (MapLoader asks P.prepareFloor), its objects are the placed ones, and
-- they talk through the two scripts the squares name (BattlePyramid_TrainerBattle,
-- BattlePyramid_FindItemBall), filed under the floor map.
--
-- What else the Pyramid changes, and where it is done:
--   * the BAG is the Pyramid's own (ten slots, two items to start): save.inventory
--     is swapped for it while you are inside (P.syncBag), and Bag.add holds it to
--     ten (save.gen3PyramidBag)
--   * the DARK: a light radius (32 on arrival, +4 a trainer, 200 at the top)
--     drawn as Gen3Flash's circle
--   * trainers (trainerbattle 9): the floor's own frontier trainers, one Pokemon
--     each, their easy-chat lines, and the battled bits (pyramidTrainerFlags)
--   * the wild Pokemon: gBattlePyramidWildMonHeaders' slots name an index into the
--     round's sLevel50/OpenLevelWildMons, on every tile
--   * the exit tile: BattlePyramid_WarpToNextFloor (P.nextFloor)
--   * after a battle on a Pyramid map the map's ON_RESUME runs again
--     (P.afterBattle), which is where a loss sends you back to the lobby
--
-- NOT PORTED: two trainers spotting you at once (each comes alone), the floor's
-- palette, the run multiplier on fleeing, and the Pyramid bag's own screen (the
-- ordinary bag shows the Pyramid's items).

local Commands = require("src.script.Commands")
local Logger = require("src.core.Logger")
local T = require("src.import.Gen3PyramidTables")

local P = {}

P.FACILITY = 6
P.LOBBY, P.FLOOR, P.TOP = "MAP_G26_N25", "MAP_G26_N26", "MAP_G26_N27"
P.SQUARE_GROUP, P.SQUARE_FIRST = 25, 44
P.EXIT, P.FLOOR_TILE = 0x28E, 0x28D       -- METATILE_BattlePyramid_Exit / _Floor
P.ITEM_BALL = 59                          -- OBJ_EVENT_GFX_ITEM_BALL
P.BAG_SLOTS, P.BAG_CAP = 10, 99           -- PYRAMID_BAG_ITEMS_COUNT, MAX_BAG_ITEM_CAPACITY
P.LOCATION_NONE, P.LOCATION_FLOOR, P.LOCATION_TOP = 0, 1, 2
P.TEXT_TRAINER, P.TEXT_ITEM = "PYRAMID_TRAINER", "PYRAMID_ITEM"
P.SCRIPT_TRAINER, P.SCRIPT_ITEM = "S0252C4F", "S0252C6A"
P.ROUNDS = 20                             -- TOTAL_PYRAMID_ROUNDS
P.MAX_TRAINERS = 8
-- sBattlePointAwards' pyramid column, challenge by challenge
P.BP = { 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13, 14, 14,
         15, 15, 15, 15, 15, 15, 15, 15, 15, 15 }
-- Brandon (sFrontierBrainsMons[FRONTIER_FACILITY_PYRAMID])
P.BRANDON = {
  [0] = {
    { species = "REGIROCK", item = "QUICK_CLAW", iv = 16, nature = 3, evs = { 152, 152, 0, 0, 106, 100 },
      moves = { "EXPLOSION", "SUPERPOWER", "EARTHQUAKE", "ANCIENT_POWER" } },
    { species = "REGISTEEL", item = "LEFTOVERS", iv = 16, nature = 3, evs = { 152, 152, 0, 0, 6, 200 },
      moves = { "EARTHQUAKE", "METAL_CLAW", "TOXIC", "IRON_DEFENSE" } },
    { species = "REGICE", item = "CHESTO_BERRY", iv = 16, nature = 15, evs = { 106, 0, 152, 0, 100, 152 },
      moves = { "ICE_BEAM", "AMNESIA", "THUNDER", "REST" } },
  },
  [1] = {
    { species = "ARTICUNO", item = "SCOPE_LENS", iv = 31, nature = 16, evs = { 6, 0, 252, 252, 0, 0 },
      moves = { "BLIZZARD", "WATER_PULSE", "AERIAL_ACE", "REFLECT" } },
    { species = "ZAPDOS", item = "LUM_BERRY", iv = 31, nature = 16, evs = { 6, 0, 252, 252, 0, 0 },
      moves = { "THUNDER", "DETECT", "DRILL_PECK", "LIGHT_SCREEN" } },
    { species = "MOLTRES", item = "BRIGHTPOWDER", iv = 31, nature = 16, evs = { 6, 0, 252, 252, 0, 0 },
      moves = { "FIRE_BLAST", "HYPER_BEAM", "AERIAL_ACE", "SAFEGUARD" } },
  },
}

local function F() return require("src.script.Gen3BattleFrontier") end
local function G3() return require("src.script.Gen3Commands") end
local function getVar(ctx, id) return math.floor(tonumber(G3().getVar(ctx.save, id)) or 0) end
local function setVar(ctx, id, v) G3().setVar(ctx.save, id, math.floor(tonumber(v) or 0)) end

-- ------------------------------------------------------------- the state --

function P.state(save)
  local s = F().state(save)
  s.pyramid = s.pyramid or {}
  local r = s.pyramid
  r.randoms = r.randoms or { 0, 0, 0, 0 }
  r.trainerFlags = r.trainerFlags or 0
  r.trainerIds = r.trainerIds or {}
  r.records = r.records or {}
  r.bags = r.bags or {}
  r.taken = r.taken or {}
  r.light = r.light or 0
  return s, r
end
local function lvlOf(s) return math.floor(tonumber(s.data[1]) or 0) end
local function floorOf(s) return math.floor(tonumber(s.data[2]) or 0) end
function P.streak(s) return F().streak(s, 0, lvlOf(s), P.FACILITY) end
function P.setStreak(s, n) F().setStreak(s, 0, lvlOf(s), n, P.FACILITY) end
local function round(s) return math.floor(P.streak(s) / 7) % P.ROUNDS end

-- CurrentBattlePyramidLocation
function P.location(mapId)
  if mapId == P.FLOOR then return P.LOCATION_FLOOR end
  if mapId == P.TOP then return P.LOCATION_TOP end
  return P.LOCATION_NONE
end
local function here(game)
  local ow = game and (game.overworld or (game.stack and game.stack.top and nil))
  return ow and ow.map and ow.map.id
end

-- ------------------------------------------------------ the RNGs it uses --

-- Random2 after SeedRng2: ISO_RANDOMIZE1, the top half
function P.rng2(seed)
  local x = math.floor(tonumber(seed) or 0) % 0x100000000
  return function()
    -- 1103515245 * x + 24691, mod 2^32, without losing bits in a double
    local lo = (x % 65536) * 1103515245
    local hi = (math.floor(x / 65536) * 1103515245) % 65536
    x = (lo + hi * 65536 + 24691) % 0x100000000
    return math.floor(x / 65536)
  end
end
local function rand16() return love.math.random(0, 65535) end

-- ---------------------------------------------------------- the template --

-- GetPyramidFloorTemplateId
function P.templateId(s, r)
  local roll = r.randoms[4] % 100
  local start = T.FLOOR_TEMPLATE_OFFSETS[floorOf(s) + 1] or 0
  for i = start + 1, #T.TEMPLATE_OPTIONS do
    if roll < T.TEMPLATE_OPTIONS[i][1] then return T.TEMPLATE_OPTIONS[i][2] end
  end
  return 0
end
function P.template(s, r) return T.FLOOR_TEMPLATES[P.templateId(s, r) + 1] end

-- GetPyramidFloorLayoutOffsets: three bits a square from randoms 0|1<<16, then
-- from (2|3<<16) >> 8 (MOD(a, 8) is a & 7; the shifts never reach the sign)
function P.layoutOffsets(s, r)
  local t = P.template(s, r)
  local out = {}
  local v = r.randoms[1] + r.randoms[2] * 65536
  for i = 0, 15 do
    out[i] = t.layoutOffsets[(v % 8) + 1]
    v = math.floor(v / 8)
    if i == 7 then v = math.floor((r.randoms[3] + r.randoms[4] * 65536) / 256) end
  end
  return out
end

-- GetPyramidEntranceAndExitSquareIds
function P.entranceExit(r)
  local ent, exit = r.randoms[4] % 16, r.randoms[1] % 16
  if ent == exit then
    ent = (r.randoms[4] + 1) % 16
    exit = (r.randoms[1] + 15) % 16
  end
  return ent, exit
end

local function squareDef(data, offset)
  return data.maps[("MAP_G%02d_N%02d"):format(P.SQUARE_GROUP, P.SQUARE_FIRST + offset)]
end
local function u16(s, i) return s:byte(i * 2 + 1) + s:byte(i * 2 + 2) * 256 end

-- GenerateBattlePyramidFloorLayout: the 32x32 blocks (and the collision and
-- elevation the squares carry), the entrance cell, and where the exit is
function P.layout(data, s, r)
  local offsets = P.layoutOffsets(s, r)
  local ent, exit = P.entranceExit(r)
  local W = 32
  local blocks, coll, elev = {}, {}, {}
  local entrance, exitAt
  for i = 0, 15 do
    local def = squareDef(data, offsets[i])
    local src = def and def.blocks
    local sx, sy = (i % 4) * 8, math.floor(i / 4) * 8
    for y = 0, 7 do
      for x = 0, 7 do
        local k = y * 8 + x
        local v = (type(src) == "string" and #src >= (k + 1) * 2) and u16(src, k) or P.FLOOR_TILE
        local tile = v % 1024
        if tile == P.EXIT then
          if i ~= exit then
            if i == ent then entrance = { x = sx + x, y = sy + y } end
            v = (v - tile) + P.FLOOR_TILE
          elseif not exitAt then
            exitAt = { x = sx + x, y = sy + y }
          end
        end
        local at = (sy + y) * W + sx + x + 1
        blocks[at] = string.char(v % 256, math.floor(v / 256))
        coll[at] = def and def.collisionCells and def.collisionCells[k + 1] or 0
        elev[at] = def and def.elevationCells and def.elevationCells[k + 1] or 0
      end
    end
  end
  return { blocks = table.concat(blocks), collisionCells = coll, elevationCells = elev,
           entrance = entrance, exit = exitAt, offsets = offsets, entranceSquare = ent, exitSquare = exit }
end

-- --------------------------------------------------------- the objects --

-- GetUniqueTrainerId: a trainer for this challenge and floor not already here
function P.uniqueTrainerId(s, r, n)
  local c = math.floor(P.streak(s) / 7)
  local floor = floorOf(s)
  local id
  for _ = 1, 1000 do
    id = F().trainerFor((floor == 7) and (c + 1) or c, floor)
    local dup = false
    for i = 0, n - 1 do if r.trainerIds[i] == id then dup = true break end end
    if not dup then break end
  end
  return id
end

-- TrySetPyramidObjectEventPositionAtCoords: FALSE (placed) or TRUE (not here)
local function tryAt(data, s, r, out, objType, x, y, offsets, square, idx)
  local def = squareDef(data, offsets[square])
  for _, o in ipairs(def and def.objects or {}) do
    if o.x == x and o.y == y then
      local isBall = (tonumber(o.graphicsId) == P.ITEM_BALL)
      if (objType == 0 and not isBall) or (objType == 1 and isBall) then
        local fx, fy = x + (square % 4) * 8, y + math.floor(square / 4) * 8
        local clash = false
        for j = 0, idx - 1 do
          if out[j] and out[j].x == fx and out[j].y == fy then clash = true break end
        end
        if not clash then
          local c = {}
          for k, v in pairs(o) do c[k] = v end
          c.x, c.y, c.localId, c.index = fx, fy, idx + 1, idx + 1
          c.pyramidObject = true
          if not isBall then
            local id = P.uniqueTrainerId(s, r, idx)
            r.trainerIds[idx] = id
            c.graphicsId = F().trainerGfx(data, id, P.FACILITY)
            c.sprite = ("SPRITE_G3_%03d"):format(c.graphicsId)
            c.text, c.pyramidTrainer = P.TEXT_TRAINER, id
          else
            c.text = P.TEXT_ITEM
          end
          out[idx] = c
          return false
        end
      end
    end
  end
  return true
end

-- TrySetPyramidObjectEventPositionInSquare: the square's cells in order (or
-- backwards, when randoms[0] is odd); FALSE once placed
local function tryInSquare(data, s, r, out, objType, offsets, square, idx)
  if r.randoms[1] % 2 == 1 then
    for y = 7, 0, -1 do
      for x = 7, 0, -1 do
        if not tryAt(data, s, r, out, objType, x, y, offsets, square, idx) then return false end
      end
    end
  else
    for y = 0, 7 do
      for x = 0, 7 do
        if not tryAt(data, s, r, out, objType, x, y, offsets, square, idx) then return false end
      end
    end
  end
  return true
end

local function counts(t, objType)
  if objType == 0 then return t.numTrainers, 0 end
  return t.numItems, t.numTrainers
end

-- SetPyramidObjectPositionsUniformly: walk the squares from randoms[2] % 16,
-- stopping on those whose bit in randoms[3] matches the pass (set first, then
-- clear), wrapping into the second pass and giving up after it
local function uniformly(data, s, r, out, objType, offsets, t)
  local n, start = counts(t, objType)
  local first = r.randoms[3] % 16
  local square = first
  local bits = 0
  local bit3 = r.randoms[4]
  for i = 0, n - 1 do
    repeat
      repeat
        local set = math.floor(bit3 / 2 ^ square) % 2 == 1
        if bits % 2 == 1 then
          if not set then bits = bits + ((math.floor(bits / 2) % 2 == 0) and 2 or 0) end
        else
          if set then bits = bits + ((math.floor(bits / 2) % 2 == 0) and 2 or 0) end
        end
        square = square + 1
        if square >= 16 then square = 0 end
        if square == first then
          if bits % 2 == 1 then
            if math.floor(bits / 4) % 2 == 0 then bits = bits + 4 end
            if math.floor(bits / 2) % 2 == 0 then bits = bits + 2 end
          else
            bits = bits + 1
          end
        end
      until math.floor(bits / 2) % 2 == 1
    until math.floor(bits / 4) % 2 == 1 or not tryInSquare(data, s, r, out, objType, offsets, square, start + i)
    bits = bits % 2
  end
end

local function nextBorder(square, b)
  b = b + 1
  if b >= 4 or T.BORDERED[square + 1][b + 1] == 0xFF then b = 0 end
  return b
end

-- SetPyramidObjectPositionsInAndNearSquare: TRUE when under half were placed
local function inAndNear(data, s, r, out, objType, offsets, t, square)
  local n, start = counts(t, objType)
  local b, r7, placed = 0, 0, 0
  for i = 0, n - 1 do
    if r7 == 0 then
      if tryInSquare(data, s, r, out, objType, offsets, square, start + i) then r7 = 1 else placed = placed + 1 end
    end
    if r7 % 2 == 1 then
      if tryInSquare(data, s, r, out, objType, offsets, T.BORDERED[square + 1][b + 1], start + i) then
        repeat
          b = nextBorder(square, b)
          r7 = r7 + 2
        until math.floor(r7 / 2) == 4
              or not tryInSquare(data, s, r, out, objType, offsets, T.BORDERED[square + 1][b + 1], start + i)
        placed = placed + 1
      else
        b = nextBorder(square, b)
        placed = placed + 1
      end
    end
    if math.floor(r7 / 2) == 4 then break end
    r7 = r7 % 2
  end
  return math.floor(n / 2) > placed
end

-- SetPyramidObjectPositionsNearSquare
local function near(data, s, r, out, objType, offsets, t, square)
  local n, start = counts(t, objType)
  local b, r8, placed = 0, 0, 0
  for i = 0, n - 1 do
    if tryInSquare(data, s, r, out, objType, offsets, T.BORDERED[square + 1][b + 1], start + i) then
      repeat
        b = nextBorder(square, b)
        r8 = r8 + 1
      until r8 == 4 or not tryInSquare(data, s, r, out, objType, offsets, T.BORDERED[square + 1][b + 1], start + i)
      placed = placed + 1
    else
      b = nextBorder(square, b)
      placed = placed + 1
    end
    if r8 == 4 then break end
  end
  return math.floor(n / 2) > placed
end

-- LoadBattlePyramidObjectEventTemplates: trainers first, then the items
function P.placeObjects(data, s, r)
  for i = 0, P.MAX_TRAINERS - 1 do r.trainerIds[i] = 0xFFFF end
  local t = P.template(s, r)
  local offsets = P.layoutOffsets(s, r)
  local ent, exit = P.entranceExit(r)
  local out = {}
  for objType = 0, 1 do
    local rule = (objType == 0) and t.trainerPositions or t.itemPositions
    if rule == 0 then uniformly(data, s, r, out, objType, offsets, t)
    elseif rule == 1 then
      if inAndNear(data, s, r, out, objType, offsets, t, ent) then uniformly(data, s, r, out, objType, offsets, t) end
    elseif rule == 2 then
      if inAndNear(data, s, r, out, objType, offsets, t, exit) then uniformly(data, s, r, out, objType, offsets, t) end
    elseif rule == 3 then
      if near(data, s, r, out, objType, offsets, t, ent) then uniformly(data, s, r, out, objType, offsets, t) end
    elseif rule == 4 then
      if near(data, s, r, out, objType, offsets, t, exit) then uniformly(data, s, r, out, objType, offsets, t) end
    end
  end
  local list = {}
  local i = 0
  while out[i] do list[#list + 1] = out[i]; i = i + 1 end
  return list
end

local function seedKey(s, r)
  return ("%d:%d:%d:%d:%d"):format(floorOf(s), r.randoms[1], r.randoms[2], r.randoms[3], r.randoms[4])
end

-- the floor's objects, made once per seed (and kept in the save, as the
-- cartridge keeps them in its object event templates)
function P.objects(data, s, r)
  if r.objects and r.objectsKey == seedKey(s, r) then return r.objects end
  r.objects = P.placeObjects(data, s, r)
  r.objectsKey = seedKey(s, r)
  return r.objects
end

-- --------------------------------------------------------- the floor map --

-- The Floor map's def, rewritten in place as this floor (MapLoader asks for
-- this before every load of P.FLOOR, and rebuilds the map after it)
function P.prepareFloor(data, save)
  local def = data and data.maps and data.maps[P.FLOOR]
  if not (def and save) then return nil end
  local s, r = P.state(save)
  local L = P.layout(data, s, r)
  P.base = P.base or { width = def.width, height = def.height, blocks = def.blocks, objects = def.objects,
                       collisionCells = def.collisionCells, elevationCells = def.elevationCells }
  def.width, def.height = 32, 32
  def.blocks, def.collisionCells, def.elevationCells = L.blocks, L.collisionCells, L.elevationCells
  -- Map caches the decoded blocks on the def itself
  def._blockArray = nil
  def.pyramidEntrance, def.pyramidExit = L.entrance, L.exit
  local objs = {}
  for _, o in ipairs(P.objects(data, s, r)) do
    if not (o.text == P.TEXT_ITEM and r.taken[o.localId]) then objs[#objs + 1] = o end
  end
  def.objects = objs
  P.fileScripts(data)
  return def
end

-- the two scripts the squares' objects name, as the floor's own talk scripts
function P.fileScripts(data)
  if P.filed == data then return end
  local VM = require("src.script.Gen3ScriptVM")
  local talk = {
    [P.TEXT_TRAINER] = VM.compile(data, P.SCRIPT_TRAINER),
    [P.TEXT_ITEM] = VM.compile(data, P.SCRIPT_ITEM),
  }
  if talk[P.TEXT_TRAINER] and talk[P.TEXT_ITEM] then
    require("src.script.MapScripts").attachBase(P.FLOOR, { talk = talk })
    P.filed = data
  else
    Logger.warn("gen3 battle pyramid: the trainer/item ball scripts are not in this cache")
  end
end

-- where a warp onto the floor puts the player: the entrance square's exit tile
function P.entrance(data, save)
  local s, r = P.state(save)
  local L = P.layout(data, s, r)
  return L.entrance and L.entrance.x, L.entrance and L.entrance.y
end

-- ------------------------------------------------------------- the bag --

local function bagFor(save)
  local s, r = P.state(save)
  local lvl = lvlOf(s)
  r.bags[lvl] = r.bags[lvl] or { inventory = {}, order = {} }
  return r.bags[lvl]
end

-- AddPyramidBagItem's rule: ten slots, 99 a slot
function P.bagAdd(bag, item, n)
  n = n or 1
  local inv = bag.inventory
  local slots = 0
  for _ in pairs(inv) do slots = slots + 1 end
  if not inv[item] and slots >= P.BAG_SLOTS then return false end
  if (inv[item] or 0) + n > P.BAG_CAP then return false end
  if not inv[item] then table.insert(bag.order, item) end
  inv[item] = (inv[item] or 0) + n
  return true
end

-- InitPyramidBagItems
function P.initBag(save)
  local bag = bagFor(save)
  bag.inventory, bag.order = {}, {}
  P.bagAdd(bag, "HYPER_POTION", 1)
  P.bagAdd(bag, "ETHER", 1)
end

-- inside the Pyramid the bag IS the Pyramid bag: the real one is put aside
-- while you are on the floor or the summit, and back when you leave
function P.syncBag(save, mapId)
  local inside = P.location(mapId) ~= P.LOCATION_NONE
  if inside and not save.gen3PyramidBag then
    local bag = bagFor(save)
    save.gen3PyramidRealBag = { inventory = save.inventory, order = save.bagOrder }
    save.inventory, save.bagOrder = bag.inventory, bag.order
    save.gen3PyramidBag = true
  elseif not inside and save.gen3PyramidBag then
    local real = save.gen3PyramidRealBag or {}
    local bag = bagFor(save)
    bag.inventory, bag.order = save.inventory, save.bagOrder or {}
    save.inventory, save.bagOrder = real.inventory or {}, real.order
    save.gen3PyramidBag, save.gen3PyramidRealBag = nil, nil
  end
end

-- -------------------------------------------------------------- the light --

function P.lightRadius(game)
  local mapId = here(game)
  if P.location(mapId) == P.LOCATION_NONE then return nil end
  local _, r = P.state(game.save)
  return r.light
end

-- ----------------------------------------------------------- the hints --

local function hintGroup(data, trainerId)
  local Fr = F()
  local tr = Fr.trainerRecord(data, trainerId)
  local cls = tr and tonumber(tr.facilityClass)
  for _, g in ipairs(T.TEXT_GROUPS) do
    if g[1] == cls then return g[2] end
  end
  return 0
end

-- GetPostBattleDirectionHintTextIndex
function P.directionHint(exit, from, minDist, default)
  if not exit then return 0, default end
  local x, y = exit.x - from.x, exit.y - from.y
  if x >= minDist or x <= -minDist or y >= minDist or y <= -minDist or default == 0 then
    local idx
    if x > 0 and y > 0 then idx = (x >= y) and 2 or 3
    elseif x < 0 and y < 0 then idx = (x > y) and 0 or 1
    elseif x == 0 then idx = (y > 0) and 3 or 0
    elseif y == 0 then idx = (x > 0) and 2 or 1
    elseif x < 0 then idx = (x + y > 0) and 3 or 1
    else idx = (x + y >= 0) and 2 or 0 end
    return idx, 0
  end
  return 0, default
end

-- ShowPostBattleHintText: (group, kind, index) for the trainer at `localId`
function P.hint(data, save, localId)
  local s, r = P.state(save)
  local def = data.maps[P.FLOOR]
  local obj
  for _, o in ipairs(P.objects(data, s, r)) do if o.localId == localId then obj = o end end
  local group = hintGroup(data, r.trainerIds[localId - 1])
  local kind = T.HINT_TYPES[localId] or 0
  local from = { x = obj and obj.x or 0, y = obj and obj.y or 0 }
  local exit = def and def.pyramidExit or P.layout(data, s, r).exit
  local MIN = { [3] = 8, [4] = 8, [5] = 16, [6] = 16, [7] = 24, [8] = 24 }
  local index = 0
  if kind >= 3 then
    local default = (kind % 2 == 1) and 2 or 1
    index, kind = P.directionHint(exit, from, MIN[kind], default)
  elseif kind == 0 then
    index = P.directionHint(exit, from, 8, 0)
  end
  if kind == 1 then
    index = 0
    for _, o in ipairs(P.objects(data, s, r)) do
      if o.text == P.TEXT_ITEM and not r.taken[o.localId] then index = index + 1 end
    end
  elseif kind == 2 then
    index = P.template(s, r).numTrainers
    for i = 0, P.MAX_TRAINERS - 1 do
      if math.floor(r.trainerFlags / 2 ^ i) % 2 == 1 then index = index - 1 end
    end
  end
  return group, kind, index
end

function P.hintText(data, group, kind, index)
  local speech = data.gen3_frontier_speech
  local h = speech and speech.pyramidHints
  return h and h[group] and h[group][kind] and h[group][kind][index] or nil
end

-- --------------------------------------------------------- the trainers --

function P.trainerBeaten(save, localId)
  local _, r = P.state(save)
  return math.floor(r.trainerFlags / 2 ^ ((tonumber(localId) or 1) - 1)) % 2 == 1
end

-- trainerbattle TRAINER_BATTLE_PYRAMID: the floor's trainer for the object
-- talked to (LocalIdToPyramidTrainerId), their line, one Pokemon, and the
-- battled bit set as the battle starts (MarkApproachingPyramidTrainersAsBattled).
-- The script goes on after it either way: on to the hint after a win, and the
-- floor's ON_RESUME (run by P.afterBattle) takes a loss to the lobby.
function P.trainerBattle(ctx)
  local Fr = F()
  local data = ctx.game.data
  local s, r = P.state(ctx.save)
  local npc = ctx.npc
  local localId = (npc and npc.def and npc.def.localId) or getVar(ctx, 0x800F)
  if P.trainerBeaten(ctx.save, localId) then return end
  local id = r.trainerIds[localId - 1]
  if not id or id == 0xFFFF then return end
  Fr.bufferSpeech(ctx, id, "before")
  local line = ctx.game.stringBuffers and ctx.game.stringBuffers[4]
  if line and line ~= "" then Commands.show_text(ctx, "{RAM:wStringBuffer4}") end
  r.trainerFlags = r.trainerFlags + 2 ^ (localId - 1)
  local level = Fr.enemyLevel(ctx.save, lvlOf(s))
  local party = Fr.trainerParty(data, id, 1, level)
  local tr = Fr.trainerRecord(data, id) or {}
  local slots = {}
  for i, mon in ipairs(party) do slots[i] = { species = mon.species, level = level, prebuilt = mon } end
  data.trainers[Fr.TRAINER_KEY] = { id = Fr.TRAINER_KEY, name = tr.name or "TRAINER", pic = tr.pic, class = tr.class,
    className = tr.className, party = slots, parties = { slots }, baseMoney = 0 }
  if not slots[1] then
    Logger.warn("gen3 battle pyramid: no Pokemon for trainer %s -- passed over", tostring(id))
    return
  end
  Commands.start_battle(ctx, "trainer", Fr.TRAINER_KEY, 1, { canLose = true, frontier = true, noExp = true })
  s.lastOutcome = (ctx.lastBattleResult == "win") and 1 or 2
  s.lastOutcomeKind = "trainer"
  P.afterBattle(ctx.game, ctx.overworld)
  if s.lastOutcome ~= 1 then return "end" end
end

-- --------------------------------------------------------- the wild ones --

function P.onFloor(mapId) return mapId == P.FLOOR end

-- gBattlePyramidWildMonHeaders[floor], in the shape Encounter rolls
function P.wildTable(save)
  local s = P.state(save)
  local h = T.WILD_HEADERS[math.min(floorOf(s), 6) + 1]
  local slots = {}
  for i, n in ipairs(h.slots) do slots[i] = { species = n, min = 5, max = 5 } end
  return { grass = { bucketSpan = 100, buckets = { 20, 40, 50, 60, 70, 80, 85, 90, 94, 98, 99, 100 },
                     rate = h.rate, rateMax = 180, slots = slots } }
end

local function key(data, order, n)
  local o = data.constants and data.constants[order]
  return o and o[n] or n
end

-- GenerateBattlePyramidWildMon (with the UBFIX reading of the 140-win IVs:
-- the cartridge indexes the streaks with the Pokemon's level there, which
-- reads past the array). nil when the lead's Keen Eye / Intimidate turned
-- the slot's level-5 placeholder away.
function P.wildFor(data, save, enc)
  local s = P.state(save)
  local lvlMode = lvlOf(s)
  local list = (lvlMode ~= 0) and T.WILD_OPEN[round(s) + 1] or T.WILD_50[round(s) + 1]
  local w = list and list[tonumber(enc.species)]
  if not w then return nil end
  local lead = save.party and save.party[1]
  if lead then
    local def = data.pokemon and data.pokemon[lead.species]
    local a = def and def.abilities and def.abilities[(lead.abilitySlot or 1)]
    local ll = tonumber(lead.level) or 0
    if (a == "KEEN_EYE" or a == "INTIMIDATE") and ll > 5 and 5 <= ll - 5 and love.math.random(0, 1) == 0 then
      return nil
    end
  end
  local level
  if lvlMode ~= 0 then
    level = F().enemyLevel(save, lvlMode) - w.lvl - 5 + love.math.random(0, 10)
  else
    level = w.lvl - 5 + love.math.random(0, 10)
  end
  local moves = {}
  for _, m in ipairs(w.moves) do if m ~= 0 then moves[#moves + 1] = key(data, "moveOrder", m) end end
  local ivs = (P.streak(s) >= 140) and (love.math.random(0, 16) + 15) or nil
  return { species = key(data, "speciesOrder", w.species), level = math.max(1, math.min(100, level)),
           pyramidMoves = moves, pyramidAbility = w.ability, pyramidIVs = ivs }
end

-- after newWild: its moves, its ability, and no experience; the bag is open
-- (the Pyramid is the one facility whose battles take items)
function P.prepareWild(battle, enc)
  local mon = battle.enemy and battle.enemy.mon
  if not mon then return end
  local data = battle.data or (battle.game and battle.game.data)
  mon.moves = {}
  for _, id in ipairs(enc.pyramidMoves or {}) do
    local def = data and data.moves and data.moves[id]
    mon.moves[#mon.moves + 1] = { id = id, pp = def and def.pp or 5 }
  end
  local def = data and data.pokemon and data.pokemon[mon.species]
  local two = def and def.abilities and def.abilities[2]
  if enc.pyramidAbility == 0 or enc.pyramidAbility == 1 then
    mon.abilitySlot = enc.pyramidAbility + 1
  else
    mon.abilitySlot = two and ((tonumber(mon.personality) or 0) % 2 + 1) or 1
  end
  if enc.pyramidIVs then
    local v = enc.pyramidIVs
    mon.ivs = { hp = v, attack = v, defense = v, speed = v, spatk = v, spdef = v }
    pcall(function()
      local Stats = require("src.pokemon.Stats")
      mon.stats = Stats.calc(def, mon.level, mon.ivs, nil, mon.evs, mon.nature)
      mon.hp = mon.stats.hp
    end)
  end
  if battle.enemy.refreshFromMon then battle.enemy:refreshFromMon() end
  battle.enemy.curMoves = mon.moves
  battle.noExp, battle.canLose, battle.pyramidWild = true, true, true
end

function P.afterWild(save, res)
  local s = P.state(save)
  s.lastOutcome = (res == "win" and 1) or (res == "run" and 4) or (res == "lose" and 2) or 1
  s.lastOutcomeKind = "wild"
end

-- after any battle on the floor or the summit, the map's ON_RESUME again
-- (CB2_ReturnToField runs it on the cartridge): a loss goes back to the lobby,
-- and anything won -- a trainer or a wild one -- sets VAR_TEMP_D, which the
-- floor's frame table answers by opening the light four pixels
function P.afterBattle(game, overworld)
  local mapId = overworld and overworld.map and overworld.map.id
  if P.location(mapId) == P.LOCATION_NONE then return end
  local VM = require("src.script.Gen3ScriptVM")
  local pool = VM.store(game.data)
  local entry = pool and pool.maps and pool.maps[mapId]
  for _, cb in ipairs(entry and entry.callbacks or {}) do
    if cb.type == 5 then
      local rows = VM.compile(game.data, cb.script)
      if rows and overworld.queueScript then overworld:queueScript(rows, { mapId = mapId }) end
    end
  end
end

-- ------------------------------------------------- the exit (field_control) --

-- BattlePyramid_WarpToNextFloor, which only C names:
--   call BattleFrontier_EventScript_IncrementWinStreak
--   frontier_get BATTLE_NUM; +1; frontier_set; == 7 -> warp to the top (17,17)
--   pyramid_seedfloor; frontier_set CHALLENGE_STATUS 0; VAR_RESULT = 0
--   warp MAP_BATTLE_FRONTIER_BATTLE_PYRAMID_FLOOR, 1, 1
function Commands.g3_pyramid_next_floor(ctx)
  local s, r = P.state(ctx.save)
  P.setStreak(s, math.min(F().MAX_STREAK, P.streak(s) + 1))
  local n = floorOf(s) + 1
  s.data[2] = n
  if n == 7 then
    Commands.warp(ctx, P.TOP, 17, 17)
    return
  end
  P.seed(ctx.save)
  s.data[0] = 0
  setVar(ctx, 0x800D, 0)
  local x, y = P.entrance(ctx.game.data, ctx.save)
  Commands.warp(ctx, P.FLOOR, x or 1, y or 1)
  local _ = r
end

function P.onExitTile(map, cx, cy)
  if not (map and map.id == P.FLOOR and map.blockAt) then return false end
  local ok, b = pcall(map.blockAt, map, cx, cy)
  return ok and tonumber(b) and (b % 1024) == P.EXIT or false
end

-- ---------------------------------------- CallBattlePyramidFunction (243) --

-- SeedPyramidFloor
function P.seed(save)
  local s, r = P.state(save)
  for i = 1, 4 do r.randoms[i] = rand16() end
  r.trainerFlags = 0
  r.taken = {}
  r.objects, r.objectsKey = nil, nil
  -- the floor's objects are new ones: nothing an earlier floor removed stays removed
  if save.gen3Spawned then save.gen3Spawned[P.FLOOR] = nil end
  local _ = s
end

function P.func(ctx, arg)
  local data = ctx.game.data
  local s, r = P.state(ctx.save)
  local lvl = lvlOf(s)
  local a5, a6 = getVar(ctx, 0x8005), getVar(ctx, 0x8006)
  local act = F().actives(s, P.FACILITY)
  local k = ("0:%d"):format(lvl)
  if arg == 0 then              -- InitPyramidChallenge
    s.data[0], s.data[2], s.data[3] = 0, 0, 0
    if not act[k] then
      P.setStreak(s, 0)
      P.initBag(ctx.save)
    end
    s.opponent = nil
    s.lastOutcome = 0
  elseif arg == 1 then          -- GetBattlePyramidData
    local v = 0
    if a5 == 0 then v = r.prize or 0
    elseif a5 == 1 then v = P.streak(s)
    elseif a5 == 2 then v = act[k] and 1 or 0
    elseif a5 == 3 then v = F().streak(s, 0, 0, P.FACILITY)
    elseif a5 == 4 then v = F().streak(s, 0, 1, P.FACILITY)
    elseif a5 == 5 then v = act["0:0"] and 1 or 0
    elseif a5 == 6 then v = act["0:1"] and 1 or 0 end
    setVar(ctx, 0x800D, v)
  elseif arg == 2 then          -- SetBattlePyramidData
    if a5 == 0 then r.prize = a6
    elseif a5 == 1 then P.setStreak(s, a6)
    elseif a5 == 2 then act[k] = (a6 ~= 0) or nil
    elseif a5 == 3 then r.trainerFlags = a6 end
  elseif arg == 3 then          -- SavePyramidChallenge
    s.data[0] = a5
    setVar(ctx, F().VAR_STATUS, 0)
    s.data[3] = 1
    F().saveFrontier(ctx)
  elseif arg == 4 then          -- SetBattlePyramidPrize
    local list = (P.streak(s) > 41) and T.LONG_REWARDS or T.SHORT_REWARDS
    r.prize = list[love.math.random(1, #list)]
  elseif arg == 5 then          -- GiveBattlePyramidPrize
    local item = key(data, "itemOrder", r.prize or 0)
    local Bag = require("src.inventory.Bag")
    if r.prize and r.prize ~= 0 and Bag.add(ctx.save, item, 1, data) then
      local def = data.items and data.items[item]
      ctx.game.stringBuffers = ctx.game.stringBuffers or {}
      ctx.game.stringBuffers[1] = def and def.name or tostring(item)
      r.prize = 0
      setVar(ctx, 0x800D, 1)
    else
      setVar(ctx, 0x800D, 0)
    end
  elseif arg == 6 then P.seed(ctx.save)
  elseif arg == 7 then          -- SetPickupItem
    local t = P.template(s, r)
    local itemIndex = getVar(ctx, 0x800F) - t.numTrainers - 1
    local rng = P.rng2(r.randoms[math.floor(math.max(0, itemIndex) / 2) + 1])
    local roll = 0
    for _ = 0, itemIndex do roll = rng() % 100 end
    local i = (T.PICKUP_OFFSETS[floorOf(s) + 1] or 0) + 1
    while i < #T.PICKUP_SLOTS and roll >= T.PICKUP_SLOTS[i][1] do i = i + 1 end
    local rows = (lvl ~= 0) and T.PICKUP_OPEN or T.PICKUP_50
    local item = rows[round(s) + 1][T.PICKUP_SLOTS[i][2] + 1]
    setVar(ctx, 0x8000, item)
    setVar(ctx, 0x8001, 1)
  elseif arg == 8 then          -- HidePyramidItem
    r.taken[getVar(ctx, 0x800F)] = true
  elseif arg == 9 then          -- SetPyramidFacilityTrainers: the frontier's own, already
  elseif arg == 10 then         -- ShowPostBattleHintText
    local localId = (ctx.npc and ctx.npc.def and ctx.npc.def.localId) or getVar(ctx, 0x800F)
    local text = P.hintText(data, P.hint(data, ctx.save, localId))
    if text then
      ctx.game.stringBuffers = ctx.game.stringBuffers or {}
      ctx.game.stringBuffers[4] = text
      Commands.show_text(ctx, "{RAM:wStringBuffer4}")
    end
  elseif arg == 11 then         -- UpdatePyramidWinStreak
    if P.streak(s) < 999 then P.setStreak(s, P.streak(s) + 1) end
    r.records[lvl] = math.max(r.records[lvl] or 0, P.streak(s))
  elseif arg == 12 then         -- GetCurrentBattlePyramidLocation
    setVar(ctx, 0x800D, P.location(ctx.overworld and ctx.overworld.map and ctx.overworld.map.id))
  elseif arg == 13 then         -- UpdatePyramidLightRadius
    local a7, res = getVar(ctx, 0x8007), getVar(ctx, 0x800D)
    if a6 == 0 then
      r.light = a5
    elseif a6 == 1 then
      if res == 0 then
        if r.light >= 120 then r.light = 120
        else require("src.core.Sound").play(data, a7) end
        setVar(ctx, 0x800D, 1)
      elseif res == 1 then
        if a5 ~= 0 then
          setVar(ctx, 0x8005, a5 - 1)
          r.light = r.light + 1
          if r.light > 120 then r.light = 120; setVar(ctx, 0x800D, 2) end
        else
          setVar(ctx, 0x800D, 2)
        end
      end
    end
  elseif arg == 14 then         -- ClearPyramidPartyHeldItems
    for _, slot in ipairs(s.selectedPartyMons or {}) do
      local mon = slot ~= 0 and ctx.save.party and ctx.save.party[slot]
      if mon then mon.item = nil end
    end
  elseif arg == 15 or arg == 16 then
    -- the floor's palette, and the start menu (which BuildStartMenuActions handles)
  elseif arg == 17 then         -- RestorePyramidPlayerParty: the stash holds the same mons
    local stash = ctx.save.gen3PartyStash
    if stash then
      local order = {}
      for j, mon in ipairs(ctx.save.party or {}) do
        for i, m in ipairs(stash) do if m == mon then order[j] = i end end
      end
      if #order > 0 then s.selectedPartyMons = order end
    end
  end
end

-- ---------------------------------------------------------- the lobby's --

-- DoBattlePyramidMonsHaveHeldItem (451)
function P.monsHaveItems(save)
  for i = 1, 3 do
    local mon = save.party and save.party[i]
    if mon and mon.item then return true end
  end
  return false
end

-- TryStoreHeldItemsInPyramidBag (449): all of the first three's items into the
-- bag, or none of them (VAR_RESULT 1 when it is full)
function P.storeHeldItems(save)
  local bag = bagFor(save)
  local inv, order = {}, {}
  for k2, v in pairs(bag.inventory) do inv[k2] = v end
  for i, v in ipairs(bag.order) do order[i] = v end
  local trial = { inventory = inv, order = order }
  for i = 1, 3 do
    local mon = save.party and save.party[i]
    if mon and mon.item and not P.bagAdd(trial, mon.item, 1) then return false end
  end
  bag.inventory, bag.order = trial.inventory, trial.order
  for i = 1, 3 do
    local mon = save.party and save.party[i]
    if mon then mon.item = nil end
  end
  return true
end

-- GetBattlePyramidHint (516): the round, from the streak in 0x8004
function P.lobbyHint(streak) return math.floor(streak / 7) % P.ROUNDS end

function P.install()
  F().BRAIN_TEAMS[P.FACILITY] = P.BRANDON
  local S = G3().SPECIALS
  local fallback = S[243]
  S[243] = function(ctx)
    if getVar(ctx, F().VAR_FACILITY) == P.FACILITY then
      P.func(ctx, getVar(ctx, 0x8004))
      return
    end
    return fallback and fallback(ctx)
  end
  S[449] = function(ctx) setVar(ctx, 0x800D, P.storeHeldItems(ctx.save) and 0 or 1) end
  S[451] = function(ctx) setVar(ctx, 0x800D, P.monsHaveItems(ctx.save) and 1 or 0) end
  -- 450 / 452, the toss screens a full bag opens: the items that will not fit
  -- are left where they are (held), which is what choosing to keep them does
  S[450] = S[450] or function() end
  S[452] = S[452] or function() end
  S[516] = function(ctx) setVar(ctx, 0x800D, P.lobbyHint(getVar(ctx, 0x8004))) end
end

return P
