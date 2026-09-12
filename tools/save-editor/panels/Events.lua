-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped Map Editor License: you may read,
-- build and privately modify this file; you may not redistribute it or use it
-- commercially. See LICENSE at the repository root. Cartridge-derived data is
-- not covered and is not the copyright holder's to license.

-- Events panel: flags, defeated trainers, taken items, and per-map object
-- visibility toggles.  All four sections read/write through Ops so a flip is
-- always dirty + narrated.
--
-- Sub-tabs are pills; the filter is a real Kit.textfield (the old panel
-- edge-detected love.keyboard state every frame because Kit had no input
-- widget, which swallowed every keystroke the rest of the app wanted); and
-- the rows are a two-column grid so twenty fit per page instead of ten.

local Theme = require("Theme")
local Ops = require("Ops")
local Catalog = require("Catalog")
local PAL = Theme.PAL

local M = {}

local SUB_TABS = {
  { id = "flags",    label = "Flags" },
  { id = "trainers", label = "Trainers" },
  { id = "items",    label = "Items taken" },
  { id = "toggles",  label = "Object toggles" },
}

local HINTS = {
  flags    = "Story flags by name: Gen1 EVENT_*, Gen2 pret names mapped from EVENT_G2_#### ids, Hoenn flags named by what they do, plus MOD_ flags.",
  trainers = "One row per trainer the save has beaten, listed by map: checked means that trainer stays beaten.",
  items    = "One row per ground item the save has taken, listed by map: checked means that item is gone.",
  toggles  = "Per-map object visibility overrides (save.objectToggles), grouped by map."
}

local function sortedKeys(t)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys)
  return keys
end

local function contains(haystack, needle)
  if needle == "" then return true end
  return haystack:lower():find(needle:lower(), 1, true) ~= nil
end

-- Each sub-tab reduces to the same shape: a list of rows, where a row knows
-- how to read its checked state, render a label, and write a flip back.
--
-- A ROW'S LABEL IS NOT ITS KEY ANY MORE.
--
-- Reported from play: "ensure the save manager lists emerald maps by in game
-- map name and same with flags/events".  Every list in this panel was showing
-- STORAGE KEYS -- FLAG_G3_0867, MAP_G01_N03_obj_2 -- which are the names the
-- extractor invents, not names anybody has seen in the game.  So a row now
-- carries both: `label` is what it means, `sub` is the key it writes, and the
-- filter matches either so an existing habit of typing the key still works.
local function rowSub(label, key)
  if label == key then return nil end
  return key
end

-- Sort by what the reader sees, with the key as the tiebreak so rows that
-- share a name (the Frontier's forty-five indoor maps) keep a stable order.
local function byLabel(a, b)
  local la, lb = a.label:lower(), b.label:lower()
  if la ~= lb then return la < lb end
  return tostring(a.sub or a.label) < tostring(b.sub or b.label)
end

local function flagRows(S, filter)
  -- Union of three catalogs: the scraped Gen 1 / Gen 2 / MOD names, every
  -- Hoenn flag the data can explain, and whatever the save itself holds --
  -- the last of those is what keeps orphan bits from an older extract
  -- visible instead of silently unreachable.
  local seen, names = {}, {}
  local function add(name)
    if type(name) == "string" and not seen[name] then
      seen[name] = true
      names[#names + 1] = name
    end
  end
  for _, name in ipairs(S.events or {}) do add(name) end
  for _, name in ipairs(Catalog.gen3Flags(S.data) or {}) do add(name) end
  for name in pairs(S.save.flags or {}) do add(name) end

  local rows = {}
  for _, name in ipairs(names) do
    local label = Catalog.flagLabel(name, S.data)
    -- Prefer pret name as the storage key when the save still uses EVENT_G2_
    -- but Catalog also listed the pret form; toggle the key that is actually
    -- present (or the catalog name if neither is set yet).
    local storage = name
    if S.save.flags[name] == nil then
      local idx = name:match("^EVENT_G2_(%d+)$")
      if idx then
        local pretty = Catalog.flagLabel(name)
        if S.save.flags[pretty] ~= nil then storage = pretty end
      else
        local ok, Gen2Flags = pcall(require, "src.script.Gen2Flags")
        local index = ok and Gen2Flags.EVENT_FLAG_INDEX and Gen2Flags.EVENT_FLAG_INDEX[name]
        if index then
          local g2 = string.format("EVENT_G2_%04d", index)
          if S.save.flags[g2] ~= nil then storage = g2 end
        end
      end
    end
    if contains(label, filter) or contains(storage, filter) or contains(name, filter) then
      rows[#rows + 1] = {
        label = label,
        sub = rowSub(label, storage),
        checked = S.save.flags[storage] == true,
        set = function(on) Ops.setFlag(S, storage, on) end,
      }
    end
  end
  table.sort(rows, byLabel)
  return rows
end

local function keyTableRows(S, filter, key)
  S.save[key] = S.save[key] or {}
  local t = S.save[key]
  local rows = {}
  for _, k in ipairs(sortedKeys(t)) do
    -- "MAP_G05_N01_obj_3" -> "SLATEPORT CITY - Indoor_obj_3": the map half is
    -- the half nobody can read, and the object number has to stay because it
    -- is the only thing separating one trainer in a gym from the next.
    local label = Catalog.mapKeyLabel(S.data, k)
    if contains(label, filter) or contains(k, filter) then
      rows[#rows + 1] = {
        label = label,
        sub = rowSub(label, k),
        checked = t[k] == true,
        set = function(on) Ops.setKey(S, key, k, on) end,
      }
    end
  end
  table.sort(rows, byLabel)
  return rows
end

local function toggleRows(S, filter)
  S.save.objectToggles = S.save.objectToggles or {}
  local toggles = S.save.objectToggles
  local groups = {}
  for _, mapId in ipairs(sortedKeys(toggles)) do
    local mapLabel = Catalog.mapLabel(S.data, mapId)
    local mapRows = {}
    for _, name in ipairs(sortedKeys(toggles[mapId])) do
      if contains(name, filter) or contains(mapId, filter)
         or contains(mapLabel, filter) then
        mapRows[#mapRows + 1] = {
          label = name,
          checked = toggles[mapId][name] == true,
          set = function(on) Ops.setToggle(S, mapId, name, on) end,
        }
      end
    end
    if #mapRows > 0 then
      groups[#groups + 1] = {
        label = mapLabel,
        sub = rowSub(mapLabel, mapId),
        rows = mapRows,
      }
    end
  end
  table.sort(groups, byLabel)
  local rows = {}
  for _, group in ipairs(groups) do
    rows[#rows + 1] = { header = true,
      label = "[" .. group.label .. "]",
      sub = group.sub }
    for _, r in ipairs(group.rows) do rows[#rows + 1] = r end
  end
  return rows
end

local function buildRows(S)
  local tab = S.eventsTab
  local filter = S.eventFilter or ""
  if tab == "flags" then return flagRows(S, filter) end
  if tab == "trainers" then return keyTableRows(S, filter, "defeatedTrainers") end
  if tab == "items" then return keyTableRows(S, filter, "itemsTaken") end
  return toggleRows(S, filter)
end

function M.draw(S, Kit, x, y, w, h)
  local s = Kit.scale
  local pad = 20 * s
  S.eventsTab = S.eventsTab or "flags"
  S.eventFilter = S.eventFilter or ""

  Kit.card(x, y, w, h)
  local cx = x + pad
  local inner = w - 2 * pad

  -- ------------------------------------------------------------ sub-tabs
  local pillH = 32 * s
  local px = cx
  for _, t in ipairs(SUB_TABS) do
    local pw = Kit.textWidth("small", t.label) + 32 * s
    local active = (S.eventsTab == t.id)
    Theme.col(PAL.rowBg, 0.6)
    love.graphics.rectangle("fill", px, y + pad, pw, pillH, pillH / 2, pillH / 2)
    Theme.stroke(px, y + pad, pw, pillH, pillH / 2,
      active and PAL.blue or PAL.cardBorder, active and 0.8 or 0.24,
      active and 1.5 * s or 1)
    Kit.textCenter("small", t.label, px, y + pad + (pillH - Kit.textHeight("small")) / 2,
      pw, active and PAL.heading or PAL.muted)
    if Kit.press(px, y + pad, pw, pillH) then
      S.eventsTab = t.id
      S.eventsOffset = 0
      Ops.disarm(S)
      Ops.say(S, HINTS[t.id])
    end
    px = px + pw + 10 * s
  end

  local clearW = 74 * s
  local fieldW = math.min(280 * s, math.max(140 * s, cx + inner - clearW - 10 * s - px - 10 * s))
  local fieldX = cx + inner - clearW - 10 * s - fieldW
  S.eventFilter = Kit.textfield("event-filter", fieldX, y + pad, fieldW, pillH,
    S.eventFilter, "filter by name or key...")
  if Kit.button(cx + inner - clearW, y + pad, clearW, pillH, "Clear",
      { kind = "accent", font = "small", radius = 8 * s,
        enabled = S.eventFilter ~= "" }) then
    S.eventFilter = ""
    Kit.blur()
    Ops.say(S, "Filter cleared")
  end

  local hintY = y + pad + pillH + 10 * s
  Kit.text("small", HINTS[S.eventsTab] or "", cx, hintY, PAL.caption)

  -- ---------------------------------------------------------- row grid
  local rows = buildRows(S)
  local pagerH = 30 * s
  local pagerY = y + h - pad - pagerH
  local gridTop = hintY + Kit.textHeight("small") + 14 * s
  local rowH = 34 * s
  local rowGap = 8 * s
  local colGap = 20 * s
  local colW = (inner - colGap) / 2
  local perCol = math.max(1, math.floor((pagerY - 12 * s - gridTop) / (rowH + rowGap)))
  local perPage = perCol * 2

  S.eventsOffset = Ops.clamp(S.eventsOffset or 0, 0, math.max(0, #rows - perPage))

  if #rows == 0 then
    Kit.emptyBox(cx, gridTop, inner, 80 * s,
      S.eventFilter ~= "" and "No key matches that filter."
        or "Nothing recorded here yet.")
  end
  for i = 1, math.min(perPage, #rows - S.eventsOffset) do
    local row = rows[S.eventsOffset + i]
    local ci = (i - 1) % 2
    local ri = math.floor((i - 1) / 2)
    local rx = cx + ci * (colW + colGap)
    local ry = gridTop + ri * (rowH + rowGap)
    if row.header then
      -- a map heading inside the toggles list: not a checkbox, so it must
      -- not look clickable
      local headW = colW
      if row.sub then
        local sw = Kit.textWidth("tiny", row.sub)
        if sw <= colW * 0.5 then
          Kit.text("tiny", row.sub, rx + colW - sw,
            ry + (rowH - Kit.textHeight("tiny")) / 2, PAL.faint)
          headW = colW - sw - 10 * s
        end
      end
      Kit.text("mono", Kit.ellipsize("mono", row.label, headW),
        rx + 4 * s, ry + (rowH - Kit.textHeight("mono")) / 2, PAL.caption)
    else
      local newChecked, changed = Kit.checkbox(rx, ry, colW, rowH,
        row.checked, row.label, nil, row.sub)
      if changed then row.set(newChecked) end
    end
  end

  S.eventsOffset = Kit.pager(cx, pagerY, inner, S.eventsOffset, #rows, perPage)

  -- "Clear all" only makes sense for the two key tables the editor owns
  -- wholesale; flags and object toggles are cleared one row at a time.
  local clearKey = (S.eventsTab == "trainers" and "defeatedTrainers")
    or (S.eventsTab == "items" and "itemsTaken") or nil
  if clearKey then
    local label = (S.eventsTab == "trainers") and "Clear all trainers"
      or "Clear all items taken"
    local bw = Kit.textWidth("small", label) + 32 * s
    if Kit.button(cx + inner - bw, pagerY, bw, pagerH,
        Ops.armLabel(S, "clear-" .. clearKey, label),
        { kind = "danger", font = "small", radius = 8 * s }) then
      Ops.clearTable(S, clearKey, label:gsub("^Clear all ", ""))
    end
  end
end

return M
