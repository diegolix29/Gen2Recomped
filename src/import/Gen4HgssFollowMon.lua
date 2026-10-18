-- HEARTGOLD / SOULSILVER'S WALKING POKEMON: the data the follower needs, out of
-- the cartridge (pokeheartgold src/follow_mon.c; the spec, with every address
-- checked against the retail ROM, is scratch_claude/follow_mon_spec.md).
--
--   ARM9 0x020FF088  sModelIndexLUT  494 u16 by species -> follower index
--   ARM9 0x020FE8D4  sFormMaxLUT     493 u16 by species - 1
--   ARM9 0x020FECAE  sFemaleFlagLUT  493 u16 by species - 1 (a female sprite)
--   /a/1/4/1         tp_param        566 x 4 bytes by index; byte 1 too_tall
--   /a/0/8/1         mmodel          member 297 + index: a BTX0 of 8 textures,
--                                    up x2, down x2, left x2, right x2, and two
--                                    palettes -- tsure_poke0 normal, 1 shiny
--   /a/2/2/0..2, /a/2/3/1, bank 265  the talk tables (rules, results, hops,
--                                    species groups) and their lines
--
-- FollowMon_GetSpriteID: idx = LUT[species]; a female-sprite species adds 1
-- for a female (form ignored), otherwise the form when it is within formMax.

local F = {}

F.ARM9_BASE = 0x02000000
F.LUT = 0x020FF088
F.FORM_MAX = 0x020FE8D4
F.FEMALE = 0x020FECAE
F.MMODEL = "/a/0/8/1"
F.FIRST_MEMBER = 297
F.COUNT = 566
F.TP_PARAM = "/a/1/4/1"
F.RULES = "/a/2/2/0"
F.RESULTS = "/a/2/2/1"
F.ANIMS = "/a/2/2/2"
F.GROUPS = "/a/2/3/1"
F.FACINGS = { up = { 0, 1, 0 }, down = { 2, 3, 2 }, left = { 4, 5, 4 }, right = { 6, 7, 6 } }

local function u16(s, at) local a, b = s:byte(at, at + 1) return a and b and (a + b * 256) or nil end

local function members(arc)
  local out = {}
  for i = 0, arc.count - 1 do out[i] = arc:get(i) end
  return out
end

-- build(x) -> the gen4_follow_mon record
function F.build(x)
  local rom = x.rom
  local arm9 = rom:arm9()
  local function at(ram, i) return u16(arm9, ram - F.ARM9_BASE + i * 2 + 1) end
  local out = { lut = {}, formMax = {}, female = {}, tooTall = {}, sheets = {}, facings = F.FACINGS }
  for s = 0, 493 do out.lut[s] = at(F.LUT, s) or 0 end
  for s = 1, 493 do
    local fm = at(F.FORM_MAX, s - 1)
    if fm and fm > 0 then out.formMax[s] = fm end
    if (at(F.FEMALE, s - 1) or 0) ~= 0 then out.female[s] = true end
  end

  local Narc = require("src.import.NarcArchive")
  local tp = Narc.parse(rom:read(F.TP_PARAM) or "")
  for i = 0, F.COUNT - 1 do
    local b = tp and tp:get(i)
    if b and (b:byte(2) or 0) ~= 0 then out.tooTall[i] = true end
  end

  local Models = require("src.import.Gen4Models")
  local G = require("src.import.Gen4Graphics")
  local mm = Narc.parse(rom:read(F.MMODEL) or "")
  local written = 0
  for i = 0, F.COUNT - 1 do
    local bytes = mm and mm:get(F.FIRST_MEMBER + i)
    if bytes and G.isCompressed(bytes) then bytes = G.decompress(bytes) end
    if bytes and bytes:sub(1, 4) == "BTX0" then
      local rec = {}
      for _, which in ipairs({ { "normal", 1 }, { "shiny", 2 } }) do
        local sheet = Models.sheet(bytes, { palette = which[2], color0Transparent = true })
        local entry = sheet and x:saveImage(("follow/%s_%03d"):format(which[1], i), sheet)
        if entry then
          rec[which[1]] = entry.path
          rec.frameWidth, rec.frameHeight, rec.frames = sheet.frameWidth, sheet.frameHeight, sheet.frames
          written = written + 1
        end
      end
      out.sheets[i] = rec
    end
  end

  -- the talk system's tables, raw: rules (20 bytes), results (52), hops (80)
  local function raw(path)
    local arc = Narc.parse(rom:read(path) or "")
    return arc and members(arc) or nil
  end
  local rules = raw(F.RULES)
  local results = raw(F.RESULTS)
  local anims = raw(F.ANIMS)
  local groups = raw(F.GROUPS)
  local function hex(s) return s and (s:gsub(".", function(c) return ("%02x"):format(c:byte()) end)) or nil end
  out.talk = { rules = {}, results = {}, anims = {}, groups = groups and hex(groups[0]) or nil, bank = 265 }
  for k, v in pairs(rules or {}) do out.talk.rules[k] = hex(v) end
  for k, v in pairs(results or {}) do out.talk.results[k] = hex(v) end
  for k, v in pairs(anims or {}) do out.talk.anims[k] = hex(v) end

  out.counts = { sheets = written }
  out.source = "ROM: ARM9 0x020FF088 / 0x020FE8D4 / 0x020FECAE, /a/1/4/1, /a/0/8/1 297..862, /a/2/2/0..2, /a/2/3/1"
  return out
end

-- FollowMon_GetSpriteID, on the imported tables
function F.index(rec, species, form, female)
  species = tonumber(species) or 0
  if species < 1 or species > 493 then return 0 end
  local idx = rec.lut[species] or 0
  if rec.female[species] then
    if female then idx = idx + 1 end
  else
    form = tonumber(form) or 0
    if form > (rec.formMax[species] or 0) then form = 0 end
    idx = idx + form
  end
  if idx > F.COUNT - 1 then idx = 0 end
  return idx
end

return F
