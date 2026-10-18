-- HEARTGOLD / SOULSILVER POKEDEX: THE SEARCH, THE SIZES, THE FORMS AND THE
-- AREAS AS DATA (no drawing). Used by src/ui/HgssDexSearch.lua and
-- src/ui/HgssDexDetails.lua.
--
-- READ FROM CODE (pokeheartgold asm/overlay_18.s, src/application/pokedex/):
--   * the search is `ov18_021F7ED4`: the dex order (Johto / National) cut to
--     the SEEN species (ov18_021F8198), then in this order: the sort
--     (ov18_021F822C: 0 numerical keeps the list, 1 A-to-Z keeps uncaught
--     ones, 2-5 heaviest / lightest / tallest / smallest keep only CAUGHT
--     ones -- each re-orders to the sort list's own order, ov18_021F8764),
--     the first letter (ov18_021F82CC: 26 = any, else zukan_data member
--     18 + letter, uncaught kept), type 1 and type 2 (ov18_021F831C: 17 =
--     any, else member 62 + type, CAUGHT only), the body style
--     (ov18_021F8468: grid cell -> member, below; uncaught kept), the area
--     (ov18_021F8584: a bit of the per-species zukan_hw_data byte; "unknown"
--     without the National Dex means "not in Johto"), then the height and
--     weight ranges (ov18_021F8640 / 86D0: the stops table, CAUGHT only,
--     skipped when the range is the full 0..152)
--   * the search's defaults (ov18_021F7ED4 calls): order 0, letter 26, types
--     17 / 17, height 0..152, weight 0..152, area 3 (all), body 14 (all)
--   * the body-style grid's cell -> body style (ov18_021F8468's jump table)
--   * the forms list (ov18_021E8254): Castform's four and Cherrim's two
--     always; the tracked species' seen forms; otherwise the seen genders
--   * the area flags: bit 0 Johto, bit 1 Kanto, bit 2 unknown, bit 3 all
--     (zukan_hw_data member 1)
-- FALLBACKS (the installed cache predates the `search` record): heights and
-- weights from constants.dexHeights / dexWeights, else parsed back out of message banks 814 / 812 (the US strings, feet /
-- inches and pounds), the sort lists sorted from those and from the names,
-- the letters from the names, the types from data.pokemon; no body styles
-- (that filter then keeps everything); the area flags from scanning
-- data.encounters (found anywhere = Johto or Kanto by the map's name, else
-- unknown).

local D = {}

local bit = require("bit")
local band, bor = bit.band, bit.bor

local floor = math.floor
D.STOPS = 152
D.DEFAULTS = { order = 0, letter = 26, type1 = 17, type2 = 17, hmin = 0, hmax = 152, wmin = 0, wmax = 152, area = 3, body = 14 }

-- ov18_021F8468: body-style grid cell -> body style (zukan_data 79 + style)
D.BODY_OF_CELL = { [0] = 12, 8, 9, 10, 4, 3, 7, 0, 13, 6, 11, 2, 5, 1 }

function D.copyDefaults()
  local t = {}
  for k, v in pairs(D.DEFAULTS) do t[k] = v end
  return t
end

local function text(game, bank, index)
  local t = ((game.data or {}).text or {})[("TEXT_B%04d_%05d"):format(bank, index)]
  if type(t) ~= "string" then return nil end
  return (t:gsub("{[^}]*}", ""))
end
D.text = text

-- ------------------------------------------------------- height / weight --

-- the US strings back to decimetres / hectograms ("  2'11”", "14.1 lbs.")
local function parseHeight(s)
  if not s then return nil end
  local ft, inch = s:match("(%d+)%D+(%d+)")
  if not ft then return nil end
  local inches = tonumber(ft) * 12 + tonumber(inch)
  return floor(inches * 2.54 / 10 + 0.5)
end
local function parseWeight(s)
  if not s then return nil end
  local lbs = s:match("(%d+%.?%d*)")
  if not lbs then return nil end
  return floor(tonumber(lbs) / 0.220462 + 0.5)
end

function D.height(game, search, species)
  local id = tonumber(species)
  if search and search.height and search.height[id] then return search.height[id] end
  -- the constants record carries zukan_data's own heights (/a/0/7/4)
  local own = ((game.data or {}).constants or {}).dexHeights
  if own and id and own[id] then return own[id] end
  return parseHeight(text(game, 814, id or 0))
end
function D.weight(game, search, species)
  local id = tonumber(species)
  if search and search.weight and search.weight[id] then return search.weight[id] end
  -- the constants record carries zukan_data's own weights (/a/0/7/4)
  local own = ((game.data or {}).constants or {}).dexWeights
  if own and id and own[id] then return own[id] end
  return parseWeight(text(game, 812, id or 0))
end

-- the US conversions the cartridge prints (Chikorita: 9 dm = 2'11", 64 hg =
-- 14.1 lbs.)
function D.fmtHeight(dm)
  if not dm then return "--'--\"" end
  local inches = floor(dm * 10 / 2.54 + 0.5)
  return ("%d'%02d\""):format(floor(inches / 12), inches % 12)
end
function D.fmtWeight(hg)
  if not hg then return "---.- lbs." end
  local tenths = floor(hg * 2.20462 + 0.5)
  return ("%d.%d lbs."):format(floor(tenths / 10), tenths % 10)
end

-- the slider's stops (zukan_hw_data member 0): {height dm, weight hg}
function D.stops(search)
  if search and search.stops and search.stops[D.STOPS] then return search.stops end
  -- fallback: an even spread to the cartridge's last stop (999 / 9999)
  local t = {}
  for k = 0, D.STOPS do
    t[k] = { floor(999 * (k / D.STOPS) ^ 3 + 0.5), floor(9999 * (k / D.STOPS) ^ 3 + 0.5) }
  end
  return t
end

-- ------------------------------------------------------------- the lists --

local function nameOf(game, sp)
  local def = ((game.data or {}).pokemon or {})[sp]
  return def and def.name or ""
end

local function sortedBy(game, search, ids, key, desc)
  local vals = {}
  for _, sp in ipairs(ids) do
    local v
    if key == "name" then v = nameOf(game, sp):upper()
    elseif key == "height" then v = D.height(game, search, sp) or 0
    else v = D.weight(game, search, sp) or 0 end
    vals[sp] = v
  end
  local out = {}
  for i, sp in ipairs(ids) do out[i] = sp end
  table.sort(out, function(a, b)
    if vals[a] == vals[b] then return a < b end
    if desc then return vals[a] > vals[b] end
    return vals[a] < vals[b]
  end)
  return out
end

-- every species the lists can name (1..493)
local function allSpecies()
  local t = {}
  for i = 1, 493 do t[i] = i end
  return t
end

function D.sortList(game, search, order)
  local key = ({ [1] = "alphabetical", [2] = "heaviest", [3] = "lightest", [4] = "tallest", [5] = "shortest" })[order]
  if not key then return nil end
  if search and search.sorts and search.sorts[key] and #search.sorts[key] > 0 then return search.sorts[key] end
  local all = allSpecies()
  if key == "alphabetical" then return sortedBy(game, search, all, "name") end
  if key == "heaviest" then return sortedBy(game, search, all, "weight", true) end
  if key == "lightest" then return sortedBy(game, search, all, "weight") end
  if key == "tallest" then return sortedBy(game, search, all, "height", true) end
  return sortedBy(game, search, all, "height")
end

function D.letterList(game, search, letter)
  if search and search.letters and search.letters[letter] then return search.letters[letter] end
  local want = string.char(65 + letter)
  local t = {}
  for i = 1, 493 do if nameOf(game, i):sub(1, 1):upper() == want then t[#t + 1] = i end end
  return t
end

local TYPE_NAMES = { "NORMAL", "FIGHTING", "FLYING", "POISON", "GROUND", "ROCK", "BUG", "GHOST", "STEEL",
  "FIRE", "WATER", "GRASS", "ELECTRIC", "PSYCHIC", "ICE", "DRAGON", "DARK" }
D.TYPE_NAMES = TYPE_NAMES
function D.typeList(game, search, t)
  if search and search.types and search.types[t] then return search.types[t] end
  local want = TYPE_NAMES[t + 1]
  local out = {}
  for i = 1, 493 do
    local def = ((game.data or {}).pokemon or {})[i]
    for _, ty in ipairs((def and def.types) or {}) do
      if tostring(ty):upper() == want then out[#out + 1] = i; break end
    end
  end
  return out
end

function D.bodyList(search, cell)
  local style = D.BODY_OF_CELL[cell]
  if style and search and search.bodies and search.bodies[style] then return search.bodies[style] end
  return nil -- no data: the filter keeps everything
end

-- ------------------------------------------------------------- the areas --

-- the Kanto half of the cartridge's map (for the encounter-scan fallback)
local KANTO = {}
for _, n in ipairs({ "Pallet Town", "Viridian City", "Pewter City", "Cerulean City", "Vermilion City", "Lavender Town",
  "Celadon City", "Fuchsia City", "Saffron City", "Cinnabar Island", "Indigo Plateau", "Mt. Moon", "Rock Tunnel",
  "Viridian Forest", "Seafoam Islands", "Cerulean Cave", "Power Plant", "Victory Road", "Mt. Silver", "Mt. Silver Cave",
  "Route 28" }) do KANTO[n] = true end
for r = 1, 25 do KANTO["Route " .. r] = true end
local function isKanto(label)
  if KANTO[label] then return true end
  return tostring(label):find("^DIGLETT") ~= nil
end
D.isKanto = isKanto

local function slotsHave(list, species)
  for _, s in pairs(list or {}) do
    if type(s) == "table" then
      if s.species == species then return true end
    elseif s == species then return true end
  end
  return false
end

-- where `species` is met, by map name: { {label=, kanto=, times={morning=,
-- day=, night=}} }, sorted by name (the cartridge sorts by
-- sMapIDs_Alphabetical, ov18_021E8A00)
function D.areas(game, species)
  local data = game.data or {}
  local byLabel, out = {}, {}
  for id, map in pairs(data.maps or {}) do
    local area = map.encounters and (data.encounters or {})[map.encounters]
    if type(area) == "table" then
      local times = {}
      local anyTime = false
      if (tonumber(area.grassRate) or 0) > 0 then
        local timed = area.timed or {}
        local hasTimed = false
        for _, t in ipairs({ "morning", "day", "night" }) do
          for _, v in pairs(timed[t] or {}) do if (tonumber(v) or 0) ~= 0 then hasTimed = true end end
        end
        if hasTimed then
          for _, t in ipairs({ "morning", "day", "night" }) do
            if slotsHave(timed[t], species) then times[t] = true end
          end
        elseif slotsHave(area.grass, species) then anyTime = true end
      end
      for _, method in ipairs({ "surf", "oldRod", "goodRod", "superRod", "rockSmash" }) do
        local block = area[method]
        if type(block) == "table" and (tonumber(block.rate) or 0) > 0 and slotsHave(block.slots, species) then anyTime = true end
      end
      if slotsHave(area.hgssSwarm, species) then anyTime = true end
      if anyTime then times.morning, times.day, times.night = true, true, true end
      if times.morning or times.day or times.night then
        local label = map.label or tostring(id)
        local rec = byLabel[label]
        if not rec then
          rec = { label = label, kanto = isKanto(label), times = {} }
          byLabel[label] = rec
          out[#out + 1] = rec
        end
        for t in pairs(times) do rec.times[t] = true end
      end
    end
  end
  table.sort(out, function(a, b) return a.label < b.label end)
  return out
end

function D.areaFlags(game, search, species)
  if search and search.areaFlags and search.areaFlags[species] then return search.areaFlags[species] end
  local flags = 8
  for _, rec in ipairs(D.areas(game, species)) do
    flags = bor(flags, rec.kanto and 2 or 1)
  end
  if flags == 8 then flags = bor(flags, 4) end
  return flags
end

-- ------------------------------------------------------------ the search --

local function filter(list, keep)
  local out = {}
  for _, sp in ipairs(list) do if keep(sp) then out[#out + 1] = sp end end
  return out
end
-- ov18_021F8764: the members of `list` (the current results) in `by`'s
-- order, uncaught ones only when keepUncaught
-- (the sort passes its list as the outer one, so the results take the sort's
-- order; the letter / type / body filters pass the current results, which
-- keep theirs -- see keepOrder)
local function intersectInOrder(list, by, keepUncaught, owned)
  local inList = {}
  for _, sp in ipairs(list) do inList[sp] = true end
  local out = {}
  for _, sp in ipairs(by) do
    if inList[sp] and (keepUncaught or owned(sp)) then out[#out + 1] = sp; inList[sp] = nil end
  end
  return out
end

local function keepOrder(list, by, keepUncaught, owned)
  local inBy = {}
  for _, sp in ipairs(by) do inBy[sp] = true end
  return filter(list, function(sp) return inBy[sp] and (keepUncaught or owned(sp)) end)
end

-- dex: the HgssPokedex (status(), order, hasNational); c: the criteria.
-- Returns the result list (species ids) and whether some data was missing.
function D.results(dex, c)
  local game = dex.game
  local search = (dex.art or {}).search
  local function owned(sp) return dex:status(sp) == "owned" end
  local out = {}
  for _, sp in ipairs(dex.baseOrder or dex.order or {}) do
    if dex:status(sp) then out[#out + 1] = sp end
  end
  local missing = false
  if c.order and c.order > 0 then
    out = intersectInOrder(out, D.sortList(game, search, c.order) or out, c.order == 1, owned)
  end
  if c.letter and c.letter < 26 then
    out = keepOrder(out, D.letterList(game, search, c.letter), true, owned)
  end
  for _, t in ipairs({ c.type1, c.type2 }) do
    if t and t < 17 then out = keepOrder(out, D.typeList(game, search, t), false, owned) end
  end
  if c.body and c.body < 14 then
    local list = D.bodyList(search, c.body)
    if list then out = keepOrder(out, list, true, owned) else missing = true end
  end
  if c.area and c.area < 3 then
    local mask = bit.lshift(1, c.area)
    if not dex.hasNational and c.area == 2 then
      out = filter(out, function(sp) local f = D.areaFlags(game, search, sp); return band(f, 6) ~= 0 and band(f, 1) == 0 end)
    else
      out = filter(out, function(sp) return band(D.areaFlags(game, search, sp), mask) ~= 0 end)
    end
  end
  local stops = D.stops(search)
  if not (c.hmin == 0 and c.hmax == D.STOPS) then
    local lo, hi = stops[c.hmin][1], stops[c.hmax][1]
    out = filter(out, function(sp)
      local h = D.height(game, search, sp)
      return owned(sp) and h and h >= lo and h <= hi
    end)
  end
  if not (c.wmin == 0 and c.wmax == D.STOPS) then
    local lo, hi = stops[c.wmin][2], stops[c.wmax][2]
    out = filter(out, function(sp)
      local w = D.weight(game, search, sp)
      return owned(sp) and w and w >= lo and w <= hi
    end)
  end
  return out, missing
end

-- ------------------------------------------------------------- the forms --

local FORM_LABEL = {
  [201] = { base = 69, exc = "!", que = "?" },
  [351] = { base = 160, sunny = 161, rainy = 162, snowy = 163 },
  [421] = { base = 164, sunny = 165 },
  [386] = { base = 145, attack = 146, defense = 147, speed = 148 },
  [412] = { base = 118, sandy = 119, trash = 120 },
  [413] = { base = 118, sandy = 119, trash = 120 },
  [422] = { base = 116, east_sea = 117 },
  [423] = { base = 116, east_sea = 117 },
  [479] = { base = 153, heat = 154, wash = 155, frost = 156, fan = 157, mow = 158 },
  [487] = { base = 151, origin = 152 },
  [492] = { base = 149, sky = 150 },
}
for i = 1, 25 do FORM_LABEL[201][string.char(97 + i)] = 69 + i end

-- the forms the FORMS page lists: { {key=, label=, female=bool} }
function D.forms(game, species)
  local id = tonumber(species)
  local data = game.data or {}
  local def = (data.pokemon or {})[id] or {}
  local Forms = require("src.pokemon.Gen4Forms")
  local labels = FORM_LABEL[id]
  local function label(key)
    local v = labels and labels[key]
    if type(v) == "number" then return text(game, 802, v) or key end
    return v or key
  end
  local out = {}
  if id == 351 or id == 421 then
    for _, key in ipairs(id == 351 and { "base", "sunny", "rainy", "snowy" } or { "base", "sunny" }) do
      out[#out + 1] = { key = key, label = label(key) }
    end
    return out
  end
  if labels then
    local seen = Forms.seen((game.save or {}).pokedex, id)
    for _, key in ipairs(seen) do
      if def.forms and def.forms[key] then out[#out + 1] = { key = key, label = label(key) } end
    end
    if #out == 0 then out[1] = { key = "base", label = label("base") } end
    return out
  end
  -- every other species: the genders seen (the port keeps no per-gender
  -- sightings, so a species with both genders lists both)
  local ratio = tonumber(def.genderRatio)
  if ratio == 255 or ratio == nil then
    out[1] = { key = "base", label = text(game, 802, 121) or "One form" }
  elseif ratio == 254 then
    out[1] = { key = "base", label = text(game, 802, 115) or "Female", female = true }
  elseif ratio == 0 then
    out[1] = { key = "base", label = text(game, 802, 114) or "Male" }
  else
    out[1] = { key = "base", label = text(game, 802, 114) or "Male" }
    out[2] = { key = "base", label = text(game, 802, 115) or "Female", female = true }
  end
  return out
end

-- a form's front / back picture
function D.formPicture(game, species, form, side)
  local data = game.data or {}
  local def = (data.pokemon or {})[species]
  if not def then return nil end
  if form and form.female then
    local p = side == "back" and def.spriteBackFemale or def.spriteFrontFemale
    if p then return p end
  end
  local rec = form and form.key ~= "base" and def.forms and def.forms[form.key]
  if rec then
    local p = side == "back" and (rec.spriteBack or rec.back) or (rec.spriteFront or rec.front)
    if p then return p end
  end
  return side == "back" and def.spriteBack or def.spriteFront
end

return D
