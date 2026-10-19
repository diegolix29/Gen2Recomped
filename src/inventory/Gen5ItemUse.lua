-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- BLACK AND WHITE'S BAG "USE", by the item record's own `fieldUse`.
--
-- A BW item record (/a/0/2/4, Gen5Data) carries `fieldUse`, numbered as
-- Platinum's sItemUseFuncs are (1 medicine, 4 bicycle, 6 TM, 18 the Super
-- Rod, 19 the Repels, 21 the Escape Rope, 25 the Dowsing MCHN ...), but under
-- its own name, so Platinum's `fieldUseFunc` dispatch never saw one and every
-- key item answered with the refusal. This answers first for a BW cache.
--
-- Lines: system bank 3 (the bag): 56 Juniper's words (VAR1 the player), 57
-- "You can't dismount your Bike here.", 63 "{VAR1} used the {VAR2}.", 64 a
-- Repel still lingering. Story bank 263: 0 "Repel's effect wore off..." (Black
-- and White ask nothing more -- the "use another?" prompt is Black 2 /
-- White 2's).

local Strings = require("src.core.Strings")

local U = {}

U.BAG_BANK = 3
U.LINE = { juniper = 56, cantDismount = 57, used = 63, linger = 64 }
U.REPEL_STEPS = { ["Repel"] = 100, ["Super Repel"] = 200, ["Max Repel"] = 250 }

-- THE ZONE'S FIELD PERMISSIONS: the u16 at +0x1E of the zone header
-- (Gen5Maps `fieldFlags`, on the map def as `gen5Flags`). Houses carry
-- 0x4921, towns and routes 0xEC40 / 0xEC00, Relic Castle 0x5D23. ARM9's
-- accessors: 0x2013C20 reads bit 0x0400 -- the Bicycle's use check (ov10
-- 0x2164508) and the forced dismount on a map load (ov21 0x2188418);
-- 0x2013C30 reads 0x4000 -- whether the bike / surf theme may replace the
-- zone's BGM (0x2029EB4: SEQ_BGM_BICYCLE 1012, SEQ_BGM_NAMINORI 1013).
U.FLAG_BIKE = 0x0400
U.FLAG_THEME = 0x4000

local function bit(flags, b) return math.floor(flags / b) % 2 == 1 end

local function Game() return package.loaded["src.core.Game"] end

local function numeric(id)
  if type(id) == "number" then return id end
  local n = type(id) == "string" and id:match("(%d+)$")
  return n and tonumber(n) or nil
end

-- a BW line with {VARn} filled from `vars` and the control codes dropped
function U.line(data, key, vars, fallback)
  local text = data and data.text and data.text[key]
  if type(text) ~= "string" or text == "" then text = fallback or "" end
  text = text:gsub("{VAR(%d+)}", function(n) return tostring((vars or {})[tonumber(n)] or "") end)
  text = text:gsub("{CMD[^}]*}", "")
  -- a page break (three newlines) is the text box's own
  text = text:gsub("\n\n\n", "\f"):gsub("[\n\f]+$", "")
  return text
end

function U.bagLine(data, index, vars, fallback)
  return U.line(data, ("TEXT_G5S_%04d_%05d"):format(U.BAG_BANK, index), vars, fallback)
end

function U.storyLine(data, bank, index, vars, fallback)
  return U.line(data, ("TEXT_B%04d_%05d"):format(bank, index), vars, fallback)
end

function U.juniper(data, save)
  local name = save and save.player and save.player.name or ""
  return U.bagLine(data, U.LINE.juniper, { name },
    Strings("Juniper's words echoed...\n%s! There's a time and\fplace for everything! But not now.", name))
end

-- may the bike be ridden on this map?
function U.allowBike(def)
  if not def then return false end
  local f = tonumber(def.gen5Flags)
  if f then return bit(f, U.FLAG_BIKE) end
  -- a cache imported before the flags were kept: outdoors on the main matrix
  return tonumber(def.layout) == 0
end

function U.isGen5(data) return data ~= nil and require("src.core.GameVersion").isGen5() end

-- (kind, messages, extra), or nil to let ItemEffects carry on
function U.use(data, save, id, itemDef, target, battle, ow)
  if not (U.isGen5(data) and itemDef) or battle then return nil end
  local f = tonumber(itemDef.fieldUse) or 0
  local n = numeric(id)
  local name = itemDef.name or tostring(id)
  if f == 4 then return "bw_bike", nil, { item = n } end
  if f == 18 then return "fish", id end
  if f == 25 then return "bw_dowsing", nil, { item = n } end
  if f == 19 and U.REPEL_STEPS[name] then
    if (tonumber(save.repelSteps) or 0) > 0 then
      return "failed", { U.bagLine(data, U.LINE.linger, nil,
        Strings("Since a Repel's effects still linger,\nyou can't use this now.")) }
    end
    save.repelSteps = U.REPEL_STEPS[name]
    pcall(function() require("src.core.Sound").play(data, "SEQ_SE_SPRAY") end)
    return "consumed", { U.bagLine(data, U.LINE.used, { save.player and save.player.name or "", name },
      Strings("%s used the\n%s.", save.player and save.player.name or "", name)) }
  end
  return nil
end

-- songs that the bike / surf themes replace: every map song of a zone a
-- bike may be ridden in (Black and White's audio stage writes no
-- `outdoorSongs`, so neither theme ever played)
function U.markOutdoorSongs(data)
  local audio = data and data.audio
  if not (audio and U.isGen5(data)) or audio._gen5Outdoor then return end
  audio._gen5Outdoor = true
  audio.outdoorSongs = audio.outdoorSongs or {}
  local songs = audio.mapSongs or {}
  for id, def in pairs(data.maps or {}) do
    local f = type(def) == "table" and tonumber(def.gen5Flags)
    local themed = f and bit(f, U.FLAG_THEME) or (f == nil and type(def) == "table" and U.allowBike(def))
    if type(def) == "table" and def.gen5 and themed and songs[id] ~= nil then
      audio.outdoorSongs[songs[id]] = true
    end
  end
end

-- the bike, mounted or put away (UseBicycleFromMenu's BW twin: silent)
function U.toggleBike(game, ow)
  local data, save = game.data, game.save
  local Music = require("src.core.Music")
  U.markOutdoorSongs(data)
  local p = ow and ow.player
  if save.onBike then
    save.onBike, save.bikeKind = false, nil
    Music.playMap(data, ow and ow.map and ow.map.id, false, p and p.surfing)
    return true
  end
  local def = ow and ow.map and ow.map.def
  if not (p and def and U.allowBike(def)) or p.surfing then return false end
  save.onBike = true
  pcall(function() require("src.core.Sound").play(data, "SEQ_SE_BICYCLE") end)
  Music.playMap(data, ow.map.id, true)
  return true
end

-- BagMenu's arm for the "bw_" results
function U.handle(game, list, id, result, payload, extra, showMessages)
  if result == "bw_bike" then
    if not U.toggleBike(game, game.overworld) then
      showMessages(game, { U.juniper(game.data, game.save) })
      return
    end
    list:close()
    return
  end
  if result == "bw_dowsing" then
    list:close()
    local ow = game.overworld
    if ow then require("src.world.Gen5Dowsing").toggle(game, ow) end
    return
  end
end

return U
