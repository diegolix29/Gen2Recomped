-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- HEARTGOLD / SOULSILVER'S HEADBUTT TREES AND ROCK SMASH ITEMS, per map
-- header (the archives are indexed by mapId):
--
--   /a/2/5/2  NARC_arc_headbutt (field/headbutt.h HeadbuttEncounterData):
--             u16 numRegularTrees, u16 numSecretTrees, then common[6],
--             rare[6], secret[6] slots { u16 species, u8 min, u8 max }, then
--             (regular + secret) * 6 tree cells { s16 x, s16 z } -- six cells
--             per tree. A map with no trees is the 4-byte header alone.
--             Found by that shape: 60 records exact, the other 480 empty.
--   /a/2/5/3  the rock smash item odds (rock_smash_item.c ROCK_SMASH):
--             u16 odds (percent), u16 type (0 default, 1 Ruins of Alph,
--             2 Cliff Cave)

local A = { HEADBUTT = "/a/2/5/2", ROCK_SMASH = "/a/2/5/3", SLOTS = 6 }

local function u16(d, o) return (d:byte(o + 1) or 0) + (d:byte(o + 2) or 0) * 256 end
local function s16(d, o) local v = u16(d, o); return v >= 0x8000 and v - 0x10000 or v end

function A.parseHeadbutt(d)
  if type(d) ~= "string" or #d < 4 then return nil end
  local nr, ns = u16(d, 0), u16(d, 2)
  if nr + ns == 0 then return nil end
  if #d ~= 4 + 3 * A.SLOTS * 4 + (nr + ns) * 6 * 4 then return nil end
  local function slots(at)
    local t = {}
    for i = 0, A.SLOTS - 1 do
      local o = at + i * 4
      t[i + 1] = { species = u16(d, o), minLevel = d:byte(o + 3), maxLevel = d:byte(o + 4) }
    end
    return t
  end
  local rec = { regular = nr, secret = ns, common = slots(4), rare = slots(4 + 24), secretSlots = slots(4 + 48), trees = {} }
  local at = 4 + 72
  for i = 0, (nr + ns) * 6 - 1 do
    rec.trees[i + 1] = { s16(d, at + i * 4), s16(d, at + i * 4 + 2) }
  end
  return rec
end

function A.build(x)
  local Narc = require("src.import.NarcArchive")
  local out = { source = "ROM:" .. A.HEADBUTT .. ", " .. A.ROCK_SMASH, headbutt = {}, rockSmash = {} }
  local hb = Narc.parse(assert(x.rom:read(A.HEADBUTT)))
  for i = 0, (hb and hb.count or 0) - 1 do
    local rec = A.parseHeadbutt(hb:get(i))
    if rec then out.headbutt[i] = rec end
  end
  local rs = Narc.parse(assert(x.rom:read(A.ROCK_SMASH)))
  for i = 0, (rs and rs.count or 0) - 1 do
    local d = rs:get(i)
    if d and #d >= 4 and u16(d, 0) > 0 then out.rockSmash[i] = { odds = u16(d, 0), type = u16(d, 2) } end
  end
  return out
end

return A
