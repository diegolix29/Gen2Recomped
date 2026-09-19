-- FireRed's V.S. Seeker is separate from Emerald's Match Call rematches.
-- It charges in the bag for 100 steps, then gives nearby defeated trainers a
-- per-object rematch party. The object key matters because the cartridge
-- stores the selected party by the map object's local id.
local VsSeeker = {}

local CHARGE_STEPS, SKIP = 100, 0xFFFF

local function flags(save)
  save.flags = save.flags or {}
  return save.flags
end

local function has(save, flag)
  return flags(save)[("FLAG_G3_%04X"):format(flag)] == true
end

local function owns(save)
  local bag = save.inventory or {}
  return (bag.VS_SEEKER or bag.ITEM_VS_SEEKER or 0) > 0
end

local function state(save)
  save.vsSeeker = save.vsSeeker or { steps = 0, rematches = {} }
  save.vsSeeker.rematches = save.vsSeeker.rematches or {}
  return save.vsSeeker
end

function VsSeeker.step(save)
  if not owns(save) then return false end
  local s = state(save)
  if s.charging then
    s.cooldown = math.min(CHARGE_STEPS, (s.cooldown or 0) + 1)
    if s.cooldown == CHARGE_STEPS then
      s.charging, s.cooldown, s.steps, s.rematches = nil, nil, CHARGE_STEPS, {}
      return true
    end
  else
    s.steps = math.min(CHARGE_STEPS, (s.steps or 0) + 1)
  end
  return false
end

function VsSeeker.remaining(save)
  return math.max(0, CHARGE_STEPS - (state(save).steps or 0))
end

function VsSeeker.ready(save)
  return owns(save) and not state(save).charging and state(save).steps == CHARGE_STEPS
end

local function rowFor(data, trainer)
  local rec = ((data.constants or {}).gen3VsSeeker or {}).rematches or {}
  return rec[trainer] or rec[tostring(trainer)]
end

local function trainerFlag(data, id)
  return require("src.script.Gen3Commands").trainerFlag(id, data)
end

function VsSeeker.beaten(data, save, id)
  local flag = trainerFlag(data, id)
  return flag and flags(save)[flag] == true or false
end

-- The later party rungs unlock at Celadon, Fuchsia, the Hall of Fame and the
-- Ruby/Sapphire link flag, exactly as TryGetRematchTrainerIdGivenGameState.
local function unlocked(save, slot)
  if slot <= 1 then return true end
  if slot == 2 then return has(save, 0x896) end
  if slot == 3 then return has(save, 0x897) end
  if slot == 4 then return has(save, 0x82C) end
  return has(save, 0x844)
end

function VsSeeker.nextTrainer(data, save, trainer)
  local row = rowFor(data, trainer)
  if not row then return nil end
  local parties = row.parties or row
  local best = nil
  for slot = 2, #parties do
    local id = tonumber(parties[slot])
    if id and id ~= 0 and id ~= SKIP and unlocked(save, slot - 1) then
      if not VsSeeker.beaten(data, save, id) then return id end
      best = id
    end
  end
  return best
end

local function visible(ow, npc)
  local p = ow and ow.player
  return p and npc and math.abs((npc.cellX or 0) - (p.cellX or 0)) <= 7
     and math.abs((npc.cellY or 0) - (p.cellY or 0)) <= 5
end

local function key(ow, npc)
  return tostring(ow.map.id) .. ":" .. tostring(npc.def.localId or npc.def.index)
end

function VsSeeker.use(data, save, ow, rng)
  if not VsSeeker.ready(save) then return "charging", VsSeeker.remaining(save) end
  if not (ow and ow.map and ow.player) then return "no_trainers" end
  rng = rng or love.math.random
  local eligible, ready = false, 0
  local s = state(save)
  for _, npc in ipairs(ow.npcs or {}) do
    local id = npc.def and tonumber(npc.def.gen3TrainerId)
    if id and visible(ow, npc) then
      eligible = true
      local nextId = VsSeeker.beaten(data, save, id) and VsSeeker.nextTrainer(data, save, id)
      if nextId and rng(0, 99) >= 30 then
        s.rematches[key(ow, npc)] = nextId
        npc.vsSeekerReady = true
        ready = ready + 1
      elseif not VsSeeker.beaten(data, save, id) then
        npc.vsSeekerUnfought = true
      end
    end
  end
  s.steps = 0
  if ready > 0 then s.charging, s.cooldown = true, 0 end
  if not eligible then return "no_trainers" end
  return ready > 0 and "ready" or "none", ready
end

function VsSeeker.rematchFor(save, ow, npc)
  if not (ow and npc and npc.def) then return nil end
  return state(save).rematches[key(ow, npc)]
end

-- ShouldTryRematchBattle / IsTrainerReadyForRematch are deliberately
-- different in FireRed.  The former stays true after any rematch party on the
-- row has been beaten so the trainer keeps using their rematch/post-battle
-- dialogue branch; the latter is true only while this exact map object is
-- currently armed by the V.S. Seeker.
function VsSeeker.isReady(save, ow, npc)
  return VsSeeker.rematchFor(save, ow, npc) ~= nil
end

function VsSeeker.shouldTry(data, save, ow, npc, trainer)
  if VsSeeker.isReady(save, ow, npc) then return true end
  local row = rowFor(data, tonumber(trainer))
  local parties = row and (row.parties or row)
  if not parties then return false end
  for slot = 2, #parties do
    local id = tonumber(parties[slot])
    if id and id ~= 0 and id ~= SKIP and VsSeeker.beaten(data, save, id) then
      return true
    end
  end
  return false
end

function VsSeeker.clear(save, ow, npc)
  if ow and npc and npc.def then state(save).rematches[key(ow, npc)] = nil end
  if npc then npc.vsSeekerReady = nil end
end

return VsSeeker
