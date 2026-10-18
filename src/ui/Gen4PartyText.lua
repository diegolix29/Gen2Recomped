-- src/ui/Gen4PartyText.lua -- HEARTGOLD / SOULSILVER'S PARTY-SCREEN LINES FOR
-- AN ITEM USED ON A POKEMON, AND THE BAG BANK'S RENUMBERING.
--
-- Reported from play: "weird text when using an item on a Pokemon" and on the
-- bag's other screen. Two causes, both a Platinum bank number read on an HGSS
-- cache:
--
--   * The port's item lines were the Game Boy's ("CYNDAQUIL's HP / was
--     restored!") and its party lines were read from bank 453 -- Platinum's
--     party bank, which on HeartGold is two lines of a Viridian NPC. The
--     cartridge's party screen (pokeheartgold src/party_menu_items.c,
--     PartyMenu_GetItemUseMessage and PartyMenu_ItemUseFunc_HPRestore) prints
--     msg_0300 lines with the nickname in slot 0 and the amount / stat / move in
--     slot 1: 65 "{0}'s HP was restored by {1} point(s).", 71 "regained
--     health", 72 "became healthy", 66-69 / 92 / 74 / 75 the status cures, 76
--     "base {stat} rose!", 104-106 the EV-down berries, 73 "{move}'s PP
--     increased.", 70 "PP was restored.", 102 "It won't have any effect."
--   * Platinum's bag bank is 7 (TEXT_BANK_BAG); HeartGold's is 10, renumbered,
--     and HeartGold's bank 7 is the save-delete screen ("Delete all saved
--     data?"). Every bank-7 reader goes through `bagIndex` here.
--
-- The item's kind is ItemId_GetPartyUseType's, read from the item's own
-- ItemPartyParam bytes (include/item.h):
--   byte 0  slp psn brn frz prz cfs inf guard_spec   (bits 0..7)
--   byte 1  revive revive_all level_up evolve, atk stages
--   byte 4  ... pp_up (6) pp_max (7)
--   byte 5  pp_restore pp_restore_all hp_restore hp_ev atk_ev def_ev spe_ev spa_ev
--   bytes 7..12  the six signed EV params (HP ATK DEF SPEED SPATK SPDEF)

local M = {}

M.HGSS_PARTY_BANK = 300
M.HGSS_BAG_BANK = 10
M.HGSS_STAT_BANK = 443   -- BufferStatName: msg_0443 (HP Attack Defense Speed Sp. Atk Sp. Def)

function M.isHgss(data)
  local v = data and data.gen4_version
  return v and v.family == "hgss" or false
end

-- Platinum's bank 7 entry -> HeartGold's bank 10 entry (each pair checked
-- line for line against both caches). nil: HeartGold has no such line (CHECK
-- TAG, CLOSE BAG, PLANT, OPEN, Yes / No are not bag words on HeartGold).
M.BAG_ENTRY = {
  [0] = 0, [1] = 1, [2] = 2, [3] = 3, [5] = 5, [6] = 6, [8] = 8, [16] = 16, [18] = 18,
  [24] = 25, [42] = 43, [45] = 46, [46] = 47,
  [52] = 53, [53] = 54, [54] = 55, [56] = 57, [57] = 58, [58] = 59, [59] = 60,
  [60] = 61, [61] = 62, [62] = 63, [63] = 64, [64] = 65,
  [74] = 76, [75] = 77, [76] = 78, [77] = 79, [78] = 80, [79] = 81, [84] = 87,
  [86] = 89, [87] = 90, [88] = 91, [89] = 92, [90] = 93, [91] = 94,
  [92] = 95, [93] = 96, [97] = 100, [98] = 101, [99] = 102, [111] = 118,
}

-- (bank, index) for a Platinum bag-bank line on this cache; nil when absent
function M.bagIndex(data, index)
  if not M.isHgss(data) then return 7, index end
  local hg = M.BAG_ENTRY[index]
  if hg == nil then return nil end
  return M.HGSS_BAG_BANK, hg
end

-- a bag line, slots filled from `...`; nil when this cache has none
function M.bagLine(data, game, index, ...)
  local bank, n = M.bagIndex(data, index)
  if not bank then return nil end
  local T = require("src.import.Gen4Text")
  if game and select("#", ...) > 0 then pcall(T.buffer, game, ...) end
  local s = game and T.resolve(data, bank, n, game) or nil
  if type(s) ~= "string" or not s:find("%S") then return nil end
  return s
end

-- Platinum's bank 453 entry -> HeartGold's bank 300 entry, for the lines the
-- party screen prints itself (Gen4PartyMenu:bankLine)
M.PARTY_ENTRY = {
  [64] = 65, [76] = 77, [102] = 100, [104] = 101, [105] = 102, [107] = 103,
  [131] = 120, [138] = 127, [196] = 180,
}
function M.partyIndex(data, index)
  if not M.isHgss(data) then return 453, index end
  local hg = M.PARTY_ENTRY[index]
  if hg == nil then return nil end
  return M.HGSS_PARTY_BANK, hg
end

local function byte(def, i)
  local p = def and def.partyUseParam
  if type(p) ~= "string" then return 0 end
  return p:byte(i + 1) or 0
end
local function bit(v, b) return math.floor(v / 2 ^ b) % 2 == 1 end
local function signed(v) return v >= 128 and v - 256 or v end

-- ItemId_GetPartyUseType
function M.useType(def)
  if not (def and tonumber(def.partyUse) == 1) then return "other" end
  local b1 = byte(def, 1)
  if math.floor(b1 / 16) > 0 or byte(def, 2) > 0 or byte(def, 3) > 0 or byte(def, 4) % 64 > 0 then
    return "stages"
  end
  if bit(b1, 1) then return "revive_all" end
  if bit(b1, 2) then return "level_up" end
  local b0 = byte(def, 0)
  local cure = b0 % 64
  local single = { [1] = "slp", [2] = "psn", [4] = "brn", [8] = "frz", [16] = "prz", [32] = "cfs" }
  if single[cure] then return single[cure] end
  local b5 = byte(def, 5)
  if cure == 63 then return bit(b5, 2) and "hp" or "full_heal" end
  if bit(b0, 6) then return "inf" end
  if bit(b5, 2) then return "hp" end
  for stat = 0, 5 do
    local p = signed(byte(def, 7 + stat))
    if p > 0 then return "ev_up", stat end
    if p < 0 then return "ev_down", stat end
  end
  if bit(b1, 3) then return "evolve" end
  local b4 = byte(def, 4)
  if bit(b4, 6) then return "pp_up" end
  if bit(b4, 7) then return "pp_max" end
  if bit(b5, 0) or bit(b5, 1) then return "pp_restore" end
  return "other"
end

local STATUS_LINE = { slp = 92, psn = 66, brn = 68, frz = 69, prz = 67, cfs = 74, inf = 75, full_heal = 72 }
-- the port's EV keys in the cartridge's stat order (STAT_HP .. STAT_SPDEF)
local EV_KEYS = { [0] = "hp", "atk", "def", "spe", "spatk", "spdef" }

local function evTotal(evs)
  local t = {}
  for k, v in pairs(evs or {}) do t[k] = tonumber(v) or 0 end
  return t
end

-- what the cartridge compares after UseItemOnMonInParty, taken before it
function M.snapshot(game, target)
  local data = game and game.data
  if not (M.isHgss(data) and type(target) == "table") then return nil end
  local moves = {}
  for i, mv in ipairs(target.moves or {}) do
    moves[i] = type(mv) == "table" and { id = mv.id, pp = mv.pp, ppUps = mv.ppUps } or { id = mv }
  end
  return { hp = tonumber(target.hp) or 0, status = target.status, evs = evTotal(target.evs),
           friendship = tonumber(target.happiness or target.friendship) or 0,
           level = target.level, moves = moves }
end

local function nickname(data, mon)
  return mon.nickname or (data.pokemon and data.pokemon[mon.species] and data.pokemon[mon.species].name) or "?"
end

local function line(game, index, ...)
  local T = require("src.import.Gen4Text")
  pcall(T.buffer, game, ...)
  local s = T.resolve(game.data, M.HGSS_PARTY_BANK, index, game)
  if type(s) ~= "string" or not s:find("%S") then return nil end
  return s
end

-- an HGSS party line (msg_0300 entry `index`) with its slots, or `fallback`
-- on any other cache
function M.say(game, index, fallback, ...)
  if not (game and M.isHgss(game.data)) then return fallback end
  return line(game, index, ...) or fallback
end

local function statName(game, stat)
  local T = require("src.import.Gen4Text")
  return T.resolve(game.data, M.HGSS_STAT_BANK, stat, game) or EV_KEYS[stat]
end

-- The party screen's own line for the item just used on `target`, replacing
-- the engine's; `payload` is kept for anything the cartridge would not say
-- here (a level-up's moves, an evolution, a refusal it words elsewhere).
function M.itemUseMessages(game, id, target, before, result, payload, moveIndex)
  local data = game and game.data
  if not (before and data and type(payload) == "table") then return payload end
  local def = data.items and data.items[id]
  local kind, stat = M.useType(def)
  local name = nickname(data, target)
  local out
  if result == "failed" then
    local first = payload[1]
    if type(first) == "string" and (first:find("won't have any effect", 1, true) or first:find("won’t have any effect", 1, true)) then
      out = line(game, 102)
    end
  elseif result == "consumed" or result == "kept" then
    if kind == "hp" then
      local hp = tonumber(target.hp) or 0
      local n = before.hp == 0 and 71 or (before.hp == hp and 72 or 65)
      out = line(game, n, name, tostring(hp - before.hp))
    elseif STATUS_LINE[kind] then
      out = line(game, STATUS_LINE[kind], name)
    elseif kind == "ev_up" then
      out = line(game, 76, name, statName(game, stat))
    elseif kind == "ev_down" then
      local changed = false
      for k, v in pairs(evTotal(target.evs)) do if (before.evs[k] or 0) ~= v then changed = true end end
      for k, v in pairs(before.evs) do if (tonumber((target.evs or {})[k]) or 0) ~= v then changed = true end end
      local param = 2
      if changed then
        local f = tonumber(target.happiness or target.friendship) or 0
        param = f ~= before.friendship and 0 or 1
      end
      out = line(game, 104 + param, name, statName(game, stat))
    elseif kind == "pp_up" or kind == "pp_max" then
      local mv = moveIndex and (target.moves or {})[moveIndex]
      local mid = type(mv) == "table" and mv.id or mv
      local m = mid and data.moves and data.moves[mid]
      out = line(game, 73, m and m.name or "")
    elseif kind == "pp_restore" then
      out = line(game, 70)
    end
  end
  if not out then return payload end
  local msgs = { out }
  for i = 2, #payload do msgs[#msgs + 1] = payload[i] end
  return msgs
end

return M
