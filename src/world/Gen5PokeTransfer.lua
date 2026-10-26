-- POKE TRANSFER (Black / White, the lab on Route 15, Z381).
--
-- On the cartridge a second DS running a Generation IV game sends six of its
-- PC's Pokemon; on this one they hop about a field and are caught with a
-- slingshot (src/ui/Gen5PokeTransferScreen.lua). Here the "second DS" is one
-- of this port's own Diamond / Pearl / Platinum / HeartGold / SoulSilver saves
-- -- or the six chosen beforehand on the Monster Walker's Transfer page
-- (`save.gen5PokeTransfer.pending`) -- and the Monster Walker's own catches
-- can fill places too.
--
-- The cartridge's rules: six at once, no Egg, nothing holding an item, nothing
-- knowing an HM move; they cannot go back. What is not caught when the time
-- runs out is caught anyway. The score (0x4000) and the outcome (0x8024) are
-- what the lab's script reads to rank the attempt (src/script/
-- Gen5PokeTransferCommands.lua).

local T = {}

T.MONS = 6
T.LAB = { Z381 = true }
T.GEN4_VERSIONS = { "diamond", "pearl", "platinum", "heartgold", "soulsilver" }
-- Generation IV's HMs: Cut, Fly, Surf, Strength, Waterfall, Rock Smash,
-- Whirlpool (HGSS), Rock Climb, Defog (Diamond / Pearl / Platinum)
T.HM_MOVES = { [15] = true, [19] = true, [57] = true, [70] = true, [127] = true,
               [249] = true, [250] = true, [431] = true, [432] = true }
-- the outcome codes M0878 branches on
T.STATUS = { caught = 0, none = 2, error = 3, cancelled = 4 }

function T.isLab(mapId) return T.LAB[mapId] == true end

function T.store(save)
  if type(save) ~= "table" then return nil end
  save.gen5PokeTransfer = save.gen5PokeTransfer or {}
  return save.gen5PokeTransfer
end

-- what the last transfer came to (0x1C1)
function T.result(save)
  local st = T.store(save)
  local last = st and st.last
  if not last then return T.STATUS.cancelled, 0 end
  return last.status or T.STATUS.cancelled, last.score or 0
end

-- the Generation IV saves on disk: { { version, slot, title, name } }
function T.sources()
  local SaveData = require("src.core.SaveData")
  local GameVersion = require("src.core.GameVersion")
  local out = {}
  for _, version in ipairs(T.GEN4_VERSIONS) do
    local okI, info = pcall(GameVersion.info, version)
    if okI and info then
      local okL, slots = pcall(SaveData.listSlots, version)
      for _, s in ipairs(okL and slots or {}) do
        if s.exists then
          out[#out + 1] = { version = version, slot = s.id, name = s.name, label = s.label,
                            title = info.title or info.name or version }
        end
      end
    end
  end
  return out
end

-- why a Pokemon may not come, or nil
function T.refusal(src, raw)
  if type(raw) ~= "table" or not raw.species then return "nothing" end
  if raw.isEgg then return "egg" end
  if raw.item and raw.item ~= 0 then return "item" end
  local CG = require("src.pokemon.CrossGen")
  for _, m in ipairs(raw.moves or {}) do
    local n = CG.moveRef(src, m.id)
    if T.HM_MOVES[n or -1] then return "hm" end
  end
  return nil
end

function T.run(game, ow, onDone)
  local Screen = require("src.ui.Gen5PokeTransferScreen")
  game.stack:push(Screen.new(game, onDone))
  return true
end

-- the transfer done: the six into this game's PC (and Pokedex), out of where
-- they came from, both saves written. `picks` are the screen's entries:
-- { source = { version, slot, box, index }, raw } or { walker = i, entry },
-- or { mon } for the pending six. -> true, or nil + why
-- the picks in this game's shape, and taken out of where they came from
-- (other saves backed up and written first, then the Walker). -> mons or nil, why
local function takePicks(game, picks)
  local CG = require("src.pokemon.CrossGen")
  local SaveData = require("src.core.SaveData")
  local Ser = require("src.core.SaveSerializer")
  local mons, fromSaves, fromWalker = {}, {}, {}
  local srcData = {}
  for i, p in ipairs(picks) do
    local mon, why
    if p.mon then mon = p.mon
    elseif p.walker then mon, why = CG.fromWalker(game, p.entry); fromWalker[#fromWalker + 1] = p.walker
    else
      local v = p.source.version
      srcData[v] = srcData[v] or CG.sourceData(v)
      mon, why = CG.convert(game, v, srcData[v], p.raw)
      local key = v .. "|" .. p.source.slot
      fromSaves[key] = fromSaves[key] or { version = v, slot = p.source.slot, list = {} }
      table.insert(fromSaves[key].list, p.source)
    end
    if not mon then return nil, why end
    mons[i] = mon
  end
  -- the other games first: a failed write leaves this one as it was
  for _, s in pairs(fromSaves) do
    local path = SaveData.slotDiskPath(s.version, s.slot)
    local f = path and io.open(path, "rb")
    if not f then return nil, "noSave" end
    local bytes = f:read("*a"); f:close()
    local ok, other = pcall(Ser.decode, bytes)
    if not (ok and type(other) == "table") then return nil, "noSave" end
    if love and love.filesystem then
      local dir = ("poke_transfer_backups/%s"):format(s.version)
      love.filesystem.createDirectory(dir)
      love.filesystem.write(("%s/%s_%s.lua"):format(dir, s.slot, os.date("%Y%m%d_%H%M%S")), bytes)
    end
    local boxes = other.boxes
    if type(boxes) ~= "table" and type(other.box) == "table" then boxes = other.box.boxes or { other.box } end
    for _, at in ipairs(s.list) do
      local list = boxes and boxes[at.box] and (boxes[at.box].mons or boxes[at.box])
      if list then list[at.index] = nil end
    end
    local okW, err = SaveData.writeSlot(s.version, s.slot, other)
    if not okW then return nil, err or "write" end
  end
  CG.takeWalker(fromWalker)
  return mons
end

function T.finish(game, picks, status, score)
  local Boxes = require("src.pokemon.Boxes")
  local BattleState = require("src.battle.BattleState")
  local st = T.store(game.save)
  local mons, why = takePicks(game, picks)
  if not mons then return nil, why end
  for _, mon in ipairs(mons) do
    mon.metLocation = BattleState.metHere(game) or mon.metLocation
    require("src.pokemon.Gen4Origin").stamp(game, mon, "met", mon.metLocation)
    Boxes.deposit(game.save, mon)
    pcall(BattleState.markOwned, game, mon.species)
  end
  st.pending = nil
  st.last = { status = status or T.STATUS.caught, score = score or 0 }
  st.count = (st.count or 0) + 1
  if game.writeSave then pcall(game.writeSave, game) end
  return true
end

-- THE MONSTER WALKER'S TRANSFER PAGE (src/ui/WalkerTransferPage.lua): the six
-- chosen from the launcher, converted with the destination's records and left
-- in its save as `pending`; the lab then goes straight to the field.
-- stage(destVersion, destSlot, picks) -> true, or nil + why
function T.stage(destVersion, destSlot, picks)
  local CG = require("src.pokemon.CrossGen")
  if type(picks) ~= "table" or #picks ~= T.MONS then return nil, "pick six" end
  local save, bytes = CG.readSlot(destVersion, destSlot)
  if not save then return nil, bytes end
  local st = T.store(save)
  if st.pending and #st.pending > 0 then return nil, "that save already has six waiting at the lab" end
  return CG.withDest(destVersion, function(data)
    local mons, why = takePicks({ data = data, save = save }, picks)
    if not mons then return nil, why end
    CG.backup("poke_transfer_backups", destVersion, destSlot, bytes)
    st.pending = mons
    local ok, err = require("src.core.SaveData").writeSlot(destVersion, destSlot, save)
    if not ok then return nil, err or "write" end
    return true
  end)
end

-- THE MINIGAME'S SCORE (the port's own: Black and White's transfer code is
-- not decompiled; tuned so the script's five rankings -- 400 / 550 / 700 /
-- 800 / 900 -- are reachable and the last takes a quick, clean round):
-- 100 a Pokemon caught by hand, 6 a second left on the clock at the end, and
-- nothing for one the time ran out on
T.SECONDS = 60
T.PER_CATCH = 100
T.PER_SECOND = 6

function T.score(caughtByHand, secondsLeft)
  return caughtByHand * T.PER_CATCH + math.floor(math.max(0, secondsLeft)) * T.PER_SECOND
end

return T
