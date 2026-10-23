-- CrossGenUI: the Terrarium presentation for Gen 3 / 4 / 5 screens.
--
-- UIMain's screens were written against the Game Boy states (src.ui.StartMenu,
-- PartyMenu, ...). Hoenn, Sinnoh and Unova push their own state classes
-- (src.ui.Gen3StartMenu, Gen4PartyMenu, ...), so on those games the native
-- cartridge screens showed with none of the Terrarium look.
--
-- WHAT THIS OWNS: drawing only. Every screen keeps its own update(), input,
-- cursor walk, actions and words; this reads them (rows, index, party(),
-- actions(), prompt()...) and draws a window-resolution Terrarium version.
-- The drawing follows each screen's real cursor grid, so the d-pad always
-- moves where it looks like it moves:
--
--   Gen3StartMenu / Gen4StartMenu   vertical list
--   Gen5StartMenu                   2-column tab grid (+ full-width extras)
--   HgssStartMenu                   two columns of four, filled column-first
--   Gen3PartyMenu                   lead on the left, five down the right
--   Gen4PartyMenu (Gen 4 and 5)     2 x 3 grid, CONFIRM / CANCEL bottom right
--   Summary (Gen3/Gen4/Hgss/Gen5)   INFO / SKILLS / MOVES pages; contest,
--                                   memo, condition and ribbons stay native
--   Bag (Gen3/Gen4/Gen5 list, HGSS 2 x 3 pages); toss count / moving native
--   PC boxes (Gen3/Gen4/Hgss/Gen5)  header, 6 x 5 grid, buttons, party panel
--   Pokedex list (Gen3/Gen4/Gen5 list, HGSS 5 x 3 pages); entries native
--
-- HOW IT HIDES THE NATIVE SCREEN, safely: the class draw() is wrapped and
-- skipped only while this module's HUD pass is alive (it ran within
-- LIVE_WINDOW seconds) and the screen has not failed. A draw error marks that
-- class failed for the session and the cartridge screen comes straight back.

local deps = ...
local GoldCompat = deps.GoldCompat
local mod = deps.mod

local CG = { LIVE_WINDOW = 0.25, failed = {}, frame = 0, hudAt = -1 }

local function now()
  return (love.timer and love.timer.getTime and love.timer.getTime()) or os.clock()
end

local function clamp(v, lo, hi) if v < lo then return lo end if v > hi then return hi end return v end

local function log(level, fmt, ...)
  local l = mod and mod.log
  if l and type(l[level]) == "function" then pcall(l[level], l, fmt, ...) end
end

-- ------------------------------------------------------------ design tokens
--
-- One scale for every screen, from the window: 1.0 at 1280x720, clamped so a
-- phone and a 4K monitor both get readable, proportionate chrome.
function CG.tokens()
  local sw, sh = love.graphics.getDimensions()
  local u = clamp(math.min(sw / 1280, sh / 720), 0.62, 2.4)
  return {
    sw = sw, sh = sh, u = u,
    pad = 18 * u, gap = 10 * u, radius = 12 * u,
    title = 22 * u, body = 18 * u, small = 14 * u, tiny = 12 * u,
    rowH = 44 * u,
  }
end

local PALETTE = {
  surface   = { 0.050, 0.068, 0.078, 0.94 },
  surface2  = { 0.085, 0.110, 0.122, 0.92 },
  trim      = { 0.30, 0.64, 0.66, 0.90 },
  selection = { 0.12, 0.31, 0.32, 0.95 },
  accent    = { 0.26, 0.80, 0.77, 1.00 },
  text      = { 0.93, 0.96, 0.94, 1.00 },
  dim       = { 0.62, 0.70, 0.68, 1.00 },
  shade     = { 0.00, 0.00, 0.00, 0.30 },
}

local function color(role)
  local c = PALETTE[role] or PALETTE.text
  if GoldCompat and type(GoldCompat.setUIColor) == "function"
      and (role == "surface" or role == "surface2" or role == "trim"
           or role == "selection" or role == "accent") then
    local base = role == "surface2" and "surface" or role
    return GoldCompat.setUIColor(base, c[1], c[2], c[3], c[4])
  end
  love.graphics.setColor(c)
end

-- ------------------------------------------------------------- primitives

local fonts = {}
local function font(size)
  size = math.max(7, math.floor(size + 0.5))
  if deps.font then
    local ok, f = pcall(deps.font, size)
    if ok and f then return f end
  end
  fonts[size] = fonts[size] or love.graphics.newFont(size)
  return fonts[size]
end

local function fit(str, size, maxW, minSize)
  str = tostring(str or "")
  local f = font(size)
  local w = f:getWidth(str)
  if w <= maxW or maxW <= 0 then return size end
  return math.max(minSize or size * 0.6, size * maxW / w)
end

local function text(str, x, y, size, role, align, width)
  local g = love.graphics
  str = tostring(str or "")
  local f = font(size)
  g.setFont(f)
  local c = type(role) == "table" and role or (PALETTE[role] or PALETTE.text)
  g.setColor(0, 0, 0, 0.45 * (c[4] or 1))
  if align then g.printf(str, x + 1, y + 1, width, align) else g.print(str, x + 1, y + 1) end
  g.setColor(c)
  if align then g.printf(str, x, y, width, align) else g.print(str, x, y) end
  return f:getHeight()
end

local function card(x, y, w, h, r, role, lineRole)
  local g = love.graphics
  g.setColor(PALETTE.shade)
  g.rectangle("fill", x + 3, y + 4, w, h, r, r)
  color(role or "surface")
  g.rectangle("fill", x, y, w, h, r, r)
  if lineRole ~= false then
    color(lineRole or "trim")
    g.setLineWidth(math.max(1, r * 0.11))
    g.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, r, r)
  end
end

local function selectedRow(x, y, w, h, r, u)
  local g = love.graphics
  color("selection")
  g.rectangle("fill", x, y, w, h, r, r)
  color("accent")
  local bh = h * 0.56
  g.rectangle("fill", x + 6 * u, y + (h - bh) / 2, 4 * u, bh, 2 * u, 2 * u)
end

local function hpColor(ratio)
  if ratio > 0.5 then return 0.30, 0.86, 0.48 end
  if ratio > 0.2 then return 0.96, 0.80, 0.24 end
  return 0.94, 0.32, 0.28
end

local function hpBar(x, y, w, h, hp, max)
  local g = love.graphics
  local ratio = max > 0 and clamp(hp / max, 0, 1) or 0
  g.setColor(0, 0, 0, 0.55)
  g.rectangle("fill", x, y, w, h, h / 2, h / 2)
  if ratio > 0 then
    g.setColor(hpColor(ratio))
    g.rectangle("fill", x + 1, y + 1, math.max(h - 2, (w - 2) * ratio), h - 2, (h - 2) / 2, (h - 2) / 2)
  end
end

-- the full-window backdrop behind an opaque screen (party): the native screen
-- painted the whole canvas, so something has to replace it
local function backdrop(t)
  local g = love.graphics
  g.setColor(0.030, 0.042, 0.050, 1)
  g.rectangle("fill", 0, 0, t.sw, t.sh)
  g.setColor(0.10, 0.22, 0.24, 0.35)
  g.circle("fill", t.sw * 0.82, t.sh * 0.10, t.sh * 0.55)
  g.setColor(0.06, 0.12, 0.16, 0.45)
  g.circle("fill", t.sw * 0.08, t.sh * 0.96, t.sh * 0.48)
end

-- ------------------------------------------------------------ mon helpers

local function monName(game, mon)
  local name = tostring(mon.nickname or mon.name or "")
  if name == "" then
    local def = game and game.data and game.data.pokemon and game.data.pokemon[mon.species]
    name = (def and def.name) or tostring(mon.species or "?")
  end
  return name:upper()
end

local function isEgg(mon)
  if mon.isEgg or mon.egg then return true end
  local ok, Party = pcall(require, "src.pokemon.Party")
  if ok and type(Party) == "table" and type(Party.isEgg) == "function" then
    local okE, egg = pcall(Party.isEgg, mon)
    return okE and egg == true
  end
  return false
end

local function hpOf(mon)
  local hp = tonumber(mon.hp) or 0
  local max = tonumber(mon.maxHp) or tonumber(mon.maxhp) or tonumber(mon.stats and mon.stats.hp) or 0
  return hp, max
end

local STATUS = { PAR = "PAR", PARALYSIS = "PAR", FRZ = "FRZ", FREEZE = "FRZ", SLP = "SLP",
  SLEEP = "SLP", PSN = "PSN", POISON = "PSN", TOX = "PSN", TOXIC = "PSN", BRN = "BRN", BURN = "BRN" }
local STATUS_COLOR = { PAR = { 0.86, 0.74, 0.20 }, FRZ = { 0.45, 0.78, 0.92 }, SLP = { 0.62, 0.62, 0.70 },
  PSN = { 0.66, 0.38, 0.80 }, BRN = { 0.92, 0.42, 0.24 }, FNT = { 0.80, 0.24, 0.24 } }

local function statusOf(mon)
  local hp, max = hpOf(mon)
  if max > 0 and hp <= 0 then return "FNT" end
  local s = mon.status
  if type(s) == "table" then s = s.id or s.name end
  return STATUS[tostring(s or ""):upper()]
end

local function portrait(game, mon, x, y, w, h, kind)
  if not (GoldCompat and mon) then return false end
  local fn = GoldCompat.drawCleanResolvedPortrait
  if type(fn) ~= "function" then return false end
  local ok, drew = pcall(fn, game, mon, x, y, w, h, kind or "party-card")
  return ok and drew
end

-- One party card: portrait pod, name, level, HP bar + numbers, status chip.
-- `note` replaces the HP line (TM ABLE!/UNABLE!, team-select order words).
local function partyCard(game, mon, x, y, w, h, t, opts)
  local u, r = t.u, t.radius
  opts = opts or {}
  local selected = opts.selected
  card(x, y, w, h, r, selected and "selection" or "surface", selected and "accent" or "trim")
  if not mon then
    text(opts.emptyLabel or "—", x, y + (h - t.small) / 2, t.small, "dim", "center", w)
    return
  end
  local podS = math.min(h - 12 * u, w * 0.36)
  local podX, podY = x + 8 * u, y + (h - podS) / 2
  local g = love.graphics
  g.setColor(0, 0, 0, 0.30)
  g.rectangle("fill", podX, podY, podS, podS, r * 0.7, r * 0.7)
  portrait(game, mon, podX, podY, podS, podS, opts.kind)
  if opts.marked then
    color("accent")
    g.setLineWidth(2 * u)
    g.rectangle("line", podX, podY, podS, podS, r * 0.7, r * 0.7)
  end

  local tx = podX + podS + 12 * u
  local tw = x + w - tx - 12 * u
  local nameSize = fit(monName(game, mon), t.body, tw * 0.72, t.small)
  -- the text block (name, bar, numbers) is centred in the card, so a tall
  -- card does not leave its words stuck to the top edge
  local blockH = font(nameSize):getHeight() + 6 * u + math.max(5, 7 * u) + 6 * u
    + font(t.tiny):getHeight()
  local lineY = y + math.max(8 * u, (h - blockH) / 2)
  text(monName(game, mon), tx, lineY, nameSize, "text")
  local egg = isEgg(mon)
  if not egg then
    text(("Lv %d"):format(tonumber(mon.level) or 1), tx, lineY, t.small, "dim", "right", tw)
  end
  lineY = lineY + font(nameSize):getHeight() + 6 * u

  if egg then return end
  if opts.note then
    text(opts.note, tx, lineY, t.small, opts.noteRole or "accent")
    return
  end
  local hp, max = hpOf(mon)
  if max > 0 then
    local barH = math.max(5, 7 * u)
    hpBar(tx, lineY + 2 * u, tw, barH, hp, max)
    lineY = lineY + barH + 6 * u
    text(("%d / %d"):format(math.floor(hp), math.floor(max)), tx, lineY, t.tiny, "dim", "right", tw)
  end
  local st = statusOf(mon)
  if st then
    local c = STATUS_COLOR[st] or { 0.6, 0.6, 0.6 }
    local cw, ch = 40 * u, 16 * u
    g.setColor(c[1], c[2], c[3], 0.95)
    g.rectangle("fill", tx, lineY, cw, ch, ch / 2, ch / 2)
    text(st, tx, lineY + (ch - font(t.tiny):getHeight()) / 2, t.tiny, { 0.05, 0.05, 0.05, 1 }, "center", cw)
  end
  if mon.item or mon.heldItem then
    g.setColor(0.96, 0.82, 0.32, 1)
    g.circle("fill", x + w - 14 * u, y + h - 14 * u, 5 * u)
  end
end

-- A vertical list panel (start menu rows, submenus). Returns its rect.
-- `bottom`, when given, anchors the panel's bottom edge there instead of
-- placing its top at `y` (submenus sit just above the prompt bar).
local function listPanel(rows, index, x, y, w, t, labelOf, title, bottom)
  local u = t.u
  local headH = title and (t.small + 14 * u) or 0
  local h = headH + #rows * t.rowH + 12 * u
  if bottom then y = bottom - h end
  if y + h > t.sh - t.pad then y = t.sh - t.pad - h end
  if y < t.pad then y = t.pad end
  card(x, y, w, h, t.radius)
  if title then
    text(title, x + 16 * u, y + 9 * u, t.small, "dim")
  end
  local ry = y + headH + 6 * u
  for i, row in ipairs(rows) do
    local label = labelOf(row, i)
    local sel = i == index
    if sel then selectedRow(x + 6 * u, ry, w - 12 * u, t.rowH, t.radius * 0.7, u) end
    local size = fit(label, t.body, w - 44 * u, t.small)
    text(label, x + 24 * u, ry + (t.rowH - font(size):getHeight()) / 2, size, sel and "text" or "dim")
    ry = ry + t.rowH
  end
  return { x = x, y = y, w = w, h = h }
end

local function bottomBar(t, prompt, buttons)
  local u = t.u
  local h = 52 * u
  local y = t.sh - h - t.pad
  local x = t.pad
  local w = t.sw - t.pad * 2
  card(x, y, w, h, t.radius)
  local bx = x + w - 10 * u
  for i = #(buttons or {}), 1, -1 do
    local b = buttons[i]
    local bw = math.max(120 * u, font(t.body):getWidth(b.label) + 40 * u)
    bx = bx - bw
    local by = y + 8 * u
    local bh = h - 16 * u
    if b.selected then selectedRow(bx, by, bw, bh, t.radius * 0.6, u)
    else color("surface2"); love.graphics.rectangle("fill", bx, by, bw, bh, t.radius * 0.6, t.radius * 0.6) end
    text(b.label, bx, by + (bh - font(t.body):getHeight()) / 2, t.body, b.selected and "text" or "dim", "center", bw)
    bx = bx - 8 * u
  end
  if prompt and prompt ~= "" then
    local pw = bx - x - 24 * u
    local size = fit(prompt, t.body, pw, t.small)
    text((tostring(prompt):gsub("\n", " ")), x + 18 * u, y + (h - font(size):getHeight()) / 2, size, "text")
  end
  return y
end

-- ---------------------------------------------------------------- screens

local Screens = {}

-- START MENU, Gen 3 / Gen 4: a vertical list on the right, as the cartridges
-- place it, sized to the window instead of the 240x160 / 256x192 canvas.
function Screens.startList(state, game, t)
  if state.savePanel then return false end   -- Gen 3's save summary stays native
  local rows = state.rows or {}
  if #rows == 0 then return false end
  local w = clamp(300 * t.u, 220, t.sw * 0.34)
  local x = t.sw - w - t.pad
  listPanel(rows, state.index, x, t.pad * 2, w, t, function(row)
    return row.label or row.id or "?"
  end, "MENU")
  if (game.save or {}).safari then
    local st = game.save.safari
    local bw = 240 * t.u
    card(t.pad, t.pad, bw, 64 * t.u, t.radius)
    text("SAFARI BALLS", t.pad + 16 * t.u, t.pad + 10 * t.u, t.small, "dim")
    text(tostring(st.balls or 0), t.pad + 16 * t.u, t.pad + 30 * t.u, t.body, "text")
  end
  return true
end

-- START MENU, Gen 5: the cartridge's tab grid -- two columns for the grid
-- rows, then any rows past gridCount (MODS) full width underneath, exactly
-- the shape Gen5StartMenu:update walks.
function Screens.startGrid(state, game, t)
  local rows = state.rows or {}
  if #rows == 0 then return false end
  local u = t.u
  local grid = state.gridCount or #rows
  local w = clamp(520 * u, 300, t.sw - t.pad * 2)
  local tileH = 58 * u
  local gap = t.gap
  local gridRows = math.ceil(grid / 2)
  local extra = #rows - grid
  local h = 16 * u + gridRows * (tileH + gap) + extra * (tileH * 0.8 + gap) + 8 * u
  local x = t.sw - w - t.pad
  local y = clamp(t.sh - h - t.pad * 2, t.pad, t.sh)
  card(x, y, w, h, t.radius)
  local tileW = (w - 16 * u - gap) / 2
  for i, row in ipairs(rows) do
    local tx, ty, tw, th
    if i <= grid then
      local col, rr = (i - 1) % 2, math.floor((i - 1) / 2)
      tx, ty, tw, th = x + 8 * u + col * (tileW + gap), y + 10 * u + rr * (tileH + gap), tileW, tileH
    else
      tx, tw, th = x + 8 * u, w - 16 * u, tileH * 0.8
      ty = y + 10 * u + gridRows * (tileH + gap) + (i - grid - 1) * (th + gap)
    end
    local sel = i == state.index
    if sel then selectedRow(tx, ty, tw, th, t.radius * 0.7, u)
    else color("surface2"); love.graphics.rectangle("fill", tx, ty, tw, th, t.radius * 0.7, t.radius * 0.7) end
    local label = row.label or row.id or "?"
    local size = fit(label, t.body, tw - 28 * u, t.tiny)
    text(label, tx + 10 * u, ty + (th - font(size):getHeight()) / 2, size, sel and "text" or "dim", "center", tw - 20 * u)
  end
  return true
end

-- START MENU, HGSS: the touch panel's two columns of four, filled column
-- first -- HgssStartMenu:update walks up/down through the list and left /
-- right across to the same row of the other column.
function Screens.startColumns(state, game, t)
  local rows = state.rows or {}
  if #rows == 0 then return false end
  local u = t.u
  local per = 4
  local w = clamp(520 * u, 300, t.sw - t.pad * 2)
  local tileH = 54 * u
  local gap = t.gap
  local h = 20 * u + per * (tileH + gap)
  local x = t.sw - w - t.pad
  local y = clamp(t.sh - h - t.pad * 2, t.pad, t.sh)
  card(x, y, w, h, t.radius)
  local tileW = (w - 16 * u - gap) / 2
  for i, row in ipairs(rows) do
    local col, r = math.floor((i - 1) / per), (i - 1) % per
    local tx, ty = x + 8 * u + col * (tileW + gap), y + 10 * u + r * (tileH + gap)
    local sel = i == state.index
    if sel then selectedRow(tx, ty, tileW, tileH, t.radius * 0.7, u)
    else color("surface2"); love.graphics.rectangle("fill", tx, ty, tileW, tileH, t.radius * 0.7, t.radius * 0.7) end
    local label = row.label or row.id or "?"
    local size = fit(label, t.body, tileW - 28 * u, t.tiny)
    text(label, tx + 10 * u, ty + (tileH - font(size):getHeight()) / 2, size, sel and "text" or "dim", "center", tileW - 20 * u)
  end
  return true
end

-- PARTY, Gen 4 and Gen 5 (one class): the 2 x 3 grid Gen4PartyMenu.NAV
-- walks, with CONFIRM (team select) and CANCEL at the bottom right.
function Screens.party4(state, game, t)
  local party = state.party and state:party() or {}
  local u = t.u
  backdrop(t)
  local count = (state.count and state:count()) or (#party + 1)
  local onCancel = state.index >= count
  local onConfirm = state.select ~= nil and state.index == #party + 1

  -- prompt line, from the screen's own words
  local prompt = ""
  if state.selectNotice then prompt = state.selectNotice
  elseif type(state.prompt) == "function" then
    local ok, p = pcall(state.prompt, state)
    if ok and p then prompt = p end
  end
  prompt = tostring(prompt):gsub("{[^}]*}", "")
  local buttons = {}
  if state.select then buttons[#buttons + 1] = { label = "CONFIRM", selected = onConfirm } end
  buttons[#buttons + 1] = { label = "CANCEL", selected = onCancel }
  local barY = bottomBar(t, state.submenu and "" or prompt, buttons)

  local areaH = barY - t.pad - t.gap
  local areaW = math.min(t.sw - t.pad * 2, 1180 * u)
  local cw = (areaW - t.gap) / 2
  local ch = math.min((areaH - t.gap * 2) / 3, 132 * u)
  local gridH = ch * 3 + t.gap * 2
  local left = (t.sw - areaW) / 2
  local top = t.pad + (areaH - gridH) / 2
  for i = 1, 6 do
    local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
    local x = left + col * (cw + t.gap)
    local y = top + row * (ch + t.gap)
    local mon = party[i]
    local note
    if mon and state.select and type(state.selectionWord) == "function" then
      local ok, wd = pcall(state.selectionWord, state, i); if ok then note = wd end
    elseif mon and state.tmhm and type(state.learnWord) == "function" then
      local ok, wd = pcall(state.learnWord, state, mon); if ok then note = wd end
    end
    partyCard(game, mon, x, y, cw, ch, t, {
      selected = (state.index == i) and not onCancel and not onConfirm,
      marked = state.switchFrom == i
        or (type(state.hpTransfer) == "table" and mon ~= nil and state.hpTransfer.from == mon),
      note = note and tostring(note):gsub("{[^}]*}", "") or nil,
      kind = "party-card",
    })
  end

  if state.submenu and type(state.actions) == "function" then
    local ok, actions = pcall(state.actions, state)
    if ok and type(actions) == "table" and #actions > 0 then
      local w = clamp(300 * u, 220, t.sw * 0.4)
      local mon = party[state.index]
      local title = mon and monName(game, mon) or nil
      listPanel(actions, state.submenu, t.sw - w - t.pad, 0, w, t, function(action)
        local okL, label = pcall(state.actionLabel, state, action)
        return okL and label or tostring(action)
      end, title, barY - t.gap)
    end
  end
  return true
end

-- PARTY, Gen 3: Emerald's shape -- the lead on the left, the other five down
-- the right, CANCEL (CONFIRM while choosing a team) at the bottom right.
function Screens.party3(state, game, t)
  local party = state.party and state:party() or {}
  local u = t.u
  backdrop(t)
  local onCancel = state.index > #party
  local prompt
  if state.hpTransferFrom then prompt = "Use on which POKéMON?"
  elseif state.chooseOrder then prompt = "Choose POKéMON and confirm."
  elseif state.tmhm then prompt = "Teach which POKéMON?"
  elseif state.switchFrom then prompt = "Move to where?"
  else prompt = "Choose a POKéMON." end
  local barY = bottomBar(t, state.submenu and "" or prompt, {
    { label = state.chooseOrder and "CONFIRM" or "CANCEL", selected = onCancel },
  })

  local areaH = barY - t.pad - t.gap
  local areaW = math.min(t.sw - t.pad * 2, 1180 * u)
  local leftX = (t.sw - areaW) / 2
  local leftW = areaW * 0.38
  local rightW = areaW - leftW - t.gap
  local rowH = math.min((areaH - t.gap * 4) / 5, 104 * u)
  local colH = rowH * 5 + t.gap * 4
  local top = t.pad + (areaH - colH) / 2
  local leadH = math.min(colH * 0.62, rowH * 2.6)
  for n = 1, 6 do
    local mon = party[n]
    local x, y, w, h
    if n == 1 then
      x, y, w, h = leftX, top + (colH - leadH) / 2, leftW, leadH
    else
      x, y, w, h = leftX + leftW + t.gap, top + (n - 2) * (rowH + t.gap), rightW, rowH
    end
    local note
    if mon and state.tmhm and type(state.learnWord) == "function" then
      local ok, wd = pcall(state.learnWord, state, mon); if ok then note = wd end
    end
    partyCard(game, mon, x, y, w, h, t, {
      selected = state.index == n and not onCancel,
      marked = state.switchFrom == n or (mon ~= nil and mon == state.hpTransferFrom),
      note = note and tostring(note) or nil,
      kind = n == 1 and "party-lead" or "party-card",
    })
  end

  if state.submenu then
    local w = clamp(300 * u, 220, t.sw * 0.4)
    local mon = party[state.index]
    listPanel(state.submenu, state.subIndex or 1, t.sw - w - t.pad, 0, w, t,
      function(row) return row.label or row.action or "?" end,
      mon and monName(game, mon) or nil, barY - t.gap)
  end
  return true
end

-- ------------------------------------------------------------ data helpers

local TYPE_COLORS = {
  NORMAL = { 0.66, 0.66, 0.48 }, FIRE = { 0.94, 0.50, 0.19 }, WATER = { 0.41, 0.56, 0.94 },
  ELECTRIC = { 0.97, 0.82, 0.19 }, GRASS = { 0.47, 0.78, 0.31 }, ICE = { 0.60, 0.85, 0.85 },
  FIGHTING = { 0.75, 0.19, 0.16 }, POISON = { 0.63, 0.25, 0.63 }, GROUND = { 0.88, 0.75, 0.41 },
  FLYING = { 0.66, 0.56, 0.94 }, PSYCHIC = { 0.97, 0.35, 0.53 }, BUG = { 0.66, 0.72, 0.13 },
  ROCK = { 0.72, 0.63, 0.22 }, GHOST = { 0.44, 0.35, 0.60 }, DRAGON = { 0.44, 0.22, 0.97 },
  DARK = { 0.44, 0.35, 0.28 }, STEEL = { 0.72, 0.72, 0.82 }, FAIRY = { 0.93, 0.60, 0.68 },
}

local NATURES = { "HARDY", "LONELY", "BRAVE", "ADAMANT", "NAUGHTY", "BOLD", "DOCILE",
  "RELAXED", "IMPISH", "LAX", "TIMID", "HASTY", "SERIOUS", "JOLLY", "NAIVE", "MODEST",
  "MILD", "QUIET", "BASHFUL", "RASH", "CALM", "GENTLE", "SASSY", "CAREFUL", "QUIRKY" }

local function upperWords(v)
  v = tostring(v or ""):gsub("^TYPE_", ""):gsub("^MOVE_", ""):gsub("^ITEM_", ""):gsub("^ABILITY_", "")
  v = v:gsub("_+", " ")
  return v:upper()
end

local function speciesDef(game, species)
  local mons = game and game.data and game.data.pokemon
  return mons and species ~= nil and (mons[species] or mons[tostring(species)]) or nil
end

local function speciesName(game, species)
  local def = speciesDef(game, species)
  return tostring((def and def.name) or species or "?"):upper()
end

local function dexNumber(game, species)
  local def = speciesDef(game, species)
  return tonumber(def and (def.nationalDex or def.dex or def.number)) or tonumber(species)
end

local function typesOf(game, species)
  local def = speciesDef(game, species) or {}
  local out = {}
  local list = def.types
  if type(list) == "table" then
    for _, t in ipairs(list) do out[#out + 1] = upperWords(type(t) == "table" and (t.name or t.id) or t) end
  else
    for _, t in ipairs({ def.type1 or def.type, def.type2 }) do
      local w = upperWords(t)
      if w ~= "" and w ~= out[1] then out[#out + 1] = w end
    end
  end
  return out
end

local function typeChip(label, x, y, h, t)
  local u = t.u
  label = upperWords(label)
  local c = TYPE_COLORS[label] or { 0.45, 0.50, 0.52 }
  local w = math.max(58 * u, font(t.tiny):getWidth(label) + 18 * u)
  love.graphics.setColor(c[1], c[2], c[3], 0.95)
  love.graphics.rectangle("fill", x, y, w, h, h / 2, h / 2)
  text(label, x, y + (h - font(t.tiny):getHeight()) / 2, t.tiny, { 1, 1, 1, 1 }, "center", w)
  return w
end

local function itemRecord(game, id)
  local items = game and game.data and game.data.items
  if not (items and id ~= nil and id ~= 0) then return nil end
  return items[id] or items[tonumber(id) or false] or items[tostring(id)]
end

local function itemName(game, id)
  if id == nil or id == 0 or id == "" then return nil end
  local rec = itemRecord(game, id)
  return tostring((rec and rec.name) or upperWords(id))
end

local function moveRecord(game, entry)
  local id = type(entry) == "table" and (entry.id or entry.move) or entry
  if id == nil or id == 0 then return nil, nil end
  local moves = game and game.data and game.data.moves
  return moves and (moves[id] or moves[tostring(id)]) or nil, id
end

local function natureName(mon)
  if type(mon.nature) == "string" and mon.nature ~= "" then return upperWords(mon.nature) end
  local p = tonumber(mon.personality or mon.pid)
  if p then return NATURES[(p % 25) + 1] end
  return nil
end

local function abilityInfo(game, mon)
  local def = speciesDef(game, mon.species) or {}
  local ability = mon.ability or (type(def.abilities) == "table" and def.abilities[1])
  if ability == nil then return nil end
  local list = game.data and game.data.abilities
  local rec = list and (list[ability] or list[tostring(ability)])
  local name = rec and rec.name or upperWords(ability)
  return tostring(name):upper(), rec and (rec.description or rec.desc)
end

local function wrapLines(str, f, width, maxLines)
  local lines, line = {}, ""
  for word in tostring(str or ""):gsub("[\n\v\f]", " "):gmatch("%S+") do
    local cand = line == "" and word or (line .. " " .. word)
    if f:getWidth(cand) > width and line ~= "" then
      lines[#lines + 1] = line; line = word
      if maxLines and #lines >= maxLines then return lines end
    else line = cand end
  end
  if line ~= "" then lines[#lines + 1] = line end
  return lines
end

local function infoRow(label, value, x, y, w, t)
  text(label, x, y, t.small, "dim")
  text(value or "—", x, y, t.small, "text", "right", w)
  return font(t.small):getHeight() + 8 * t.u
end

local function tabs(labels, active, x, y, w, t)
  local u = t.u
  local h = 34 * u
  local n = math.max(1, #labels)
  local tw = (w - (n - 1) * 6 * u) / n
  for i, label in ipairs(labels) do
    local tx = x + (i - 1) * (tw + 6 * u)
    if i == active then selectedRow(tx, y, tw, h, t.radius * 0.6, u)
    else color("surface2"); love.graphics.rectangle("fill", tx, y, tw, h, t.radius * 0.6, t.radius * 0.6) end
    local size = fit(label, t.small, tw - 22 * u, t.tiny)
    text(label, tx + 8 * u, y + (h - font(size):getHeight()) / 2, size, i == active and "text" or "dim", "center", tw - 16 * u)
  end
  return h
end

-- the left column every Pokemon screen shares: big portrait + identity
local function monColumn(game, mon, x, y, w, h, t, portraitFn)
  local u = t.u
  card(x, y, w, h, t.radius)
  local podS = math.min(w - 24 * u, h * 0.62)
  local podX, podY = x + (w - podS) / 2, y + 14 * u
  love.graphics.setColor(0, 0, 0, 0.30)
  love.graphics.rectangle("fill", podX, podY, podS, podS, t.radius, t.radius)
  if portraitFn then pcall(portraitFn, podX, podY, podS, podS) end
  local ty = podY + podS + 12 * u
  local name = monName(game, mon)
  local size = fit(name, t.title, w - 32 * u, t.small)
  text(name, x + 16 * u, ty, size, "text")
  if not isEgg(mon) then
    text(("Lv %d"):format(tonumber(mon.level) or 1), x + 16 * u, ty + 4 * u, t.small, "dim", "right", w - 32 * u)
    ty = ty + font(size):getHeight() + 8 * u
    local cx = x + 16 * u
    for _, ty_ in ipairs(typesOf(game, mon.species)) do
      cx = cx + typeChip(ty_, cx, ty, 20 * u, t) + 6 * u
    end
    ty = ty + 28 * u
    local item = itemName(game, mon.item or mon.heldItem)
    if item then text("ITEM  " .. item:upper(), x + 16 * u, ty, t.tiny, "dim") end
  end
end

-- SUMMARY. One layout for Emerald / Platinum / HGSS / Black & White: the
-- shared mon column on the left, the page on the right. Which page is shown
-- comes from the screen's own page state; pages this does not redraw
-- (contest, condition, memo, ribbons) are declined and stay native.
local function summaryView(state)
  local mt = getmetatable(state)
  local mon = state.mon
  if type(mon) ~= "table" then return nil end
  local function hg(pages)
    local shown = {}
    if type(state.pagesShown) == "function" then
      local ok, list = pcall(state.pagesShown, state); if ok then shown = list end
    end
    local labels, active = {}, 1
    for i, p in ipairs(shown) do
      labels[i] = pages[p] or "?"
      if p == state.hgPage then active = i end
    end
    local kind = state.hgPage == 1 and "overview" or state.hgPage == 2 and "moves" or nil
    if state.ribbonMode then kind = nil end
    return { kind = kind, labels = labels, active = active }
  end
  if state.hgPage ~= nil then
    return hg({ "INFO", "MOVES", "RIBBONS" })
  end
  if type(state.pageKey) == "function" then          -- Platinum
    local okK, key = pcall(state.pageKey, state)
    local kinds = { info = "info", skills = "skills", moves = "moves" }
    local labels, active = {}, 1
    local okV, visible = pcall(state.visiblePages, state)
    for _, i in ipairs(okV and visible or {}) do
      local page = state.pages[i] or {}
      local title = ({ info = "INFO", memo = "MEMO", skills = "SKILLS", moves = "MOVES",
        condition = "CONDITION", contestMoves = "CONTEST", ribbons = "RIBBONS", exit = "EXIT" })[page.key]
      labels[#labels + 1] = title or tostring(page.title or page.key or "?"):upper()
      if i == state.page then active = #labels end
    end
    return { kind = okK and kinds[key] or nil, labels = labels, active = active }
  end
  -- Emerald / FireRed: 1 INFO, 2 SKILLS, 3 MOVES, 4 CONTEST (Emerald only)
  local labels = {}
  for i, name in ipairs(state.pages or {}) do labels[i] = tostring(name):upper() end
  local kind = ({ "info", "skills", "moves" })[state.page]
  if type(state.choose) == "table" then kind = "moves" end
  return { kind = kind, labels = labels, active = state.page or 1 }
end

local STAT_ROWS = {
  { "ATTACK", { "attack", "atk" }, "attack" },
  { "DEFENSE", { "defense", "def" }, "defense" },
  { "SP. ATK", { "spAttack", "spatk", "specialAttack", "spAtk" }, "spatk" },
  { "SP. DEF", { "spDefense", "spdef", "specialDefense", "spDef" }, "spdef" },
  { "SPEED", { "speed", "spe" }, "speed" },
}

local function natureEffect(game, mon)
  local name = type(mon.nature) == "string" and mon.nature or natureName(mon)
  local list = game.data and game.data.constants and game.data.constants.natures
  local rec = type(list) == "table" and name and (list[name] or list[tostring(name):upper()]
    or list[tostring(name):sub(1, 1):upper() .. tostring(name):sub(2):lower()])
  if type(rec) ~= "table" then return nil, nil end
  return rec.raises, rec.lowers
end

local function drawSkills(game, mon, x, y, w, t)
  local u = t.u
  local hp, max = hpOf(mon)
  text("HP", x, y, t.small, "dim")
  text(("%d / %d"):format(math.floor(hp), math.floor(max)), x, y, t.small, "text", "right", w)
  y = y + font(t.small):getHeight() + 4 * u
  hpBar(x, y, w, math.max(6, 8 * u), hp, max)
  y = y + 18 * u
  local raises, lowers = natureEffect(game, mon)
  local stats = mon.stats or {}
  for _, row in ipairs(STAT_ROWS) do
    local v
    for _, k in ipairs(row[2]) do v = v or stats[k] end
    local role = (row[3] == raises) and { 0.98, 0.52, 0.46, 1 } or (row[3] == lowers) and { 0.50, 0.70, 0.98, 1 } or "dim"
    text(row[1], x, y, t.small, role)
    text(tostring(v or "—"), x, y, t.small, "text", "right", w)
    y = y + font(t.small):getHeight() + 8 * u
  end
  local ability, desc = abilityInfo(game, mon)
  if ability then
    y = y + 6 * u
    text("ABILITY", x, y, t.tiny, "dim")
    text(ability, x, y, t.small, "accent", "right", w)
    y = y + font(t.small):getHeight() + 4 * u
    if desc then
      for _, line in ipairs(wrapLines(desc, font(t.tiny), w, 3)) do
        text(line, x, y, t.tiny, "dim"); y = y + font(t.tiny):getHeight() + 2 * u
      end
    end
  end
  return y
end

local function drawInfo(game, mon, x, y, w, t)
  local u = t.u
  local player = (game.save or {}).player or {}
  y = y + infoRow("No.", ("%03d"):format(dexNumber(game, mon.species) or 0), x, y, w, t)
  y = y + infoRow("SPECIES", speciesName(game, mon.species), x, y, w, t)
  y = y + infoRow("OT", tostring(mon.otName or mon.ot or player.name or "—"):upper(), x, y, w, t)
  y = y + infoRow("ID No.", ("%05d"):format((tonumber(mon.otId or player.id) or 0) % 65536), x, y, w, t)
  y = y + infoRow("ITEM", (itemName(game, mon.item or mon.heldItem) or "NONE"):upper(), x, y, w, t)
  y = y + infoRow("NATURE", natureName(mon) or "—", x, y, w, t)
  local ability = abilityInfo(game, mon)
  if ability then y = y + infoRow("ABILITY", ability, x, y, w, t) end
  local ratio = GoldCompat.experienceRatio and GoldCompat.experienceRatio(game.data, mon, "gen3") or nil
  y = y + 4 * u
  text("EXP", x, y, t.tiny, "dim")
  text(tostring(mon.exp or mon.experience or 0), x, y, t.tiny, "dim", "right", w)
  y = y + font(t.tiny):getHeight() + 4 * u
  local g = love.graphics
  g.setColor(0, 0, 0, 0.55); g.rectangle("fill", x, y, w, 6 * u, 3 * u, 3 * u)
  if ratio and ratio > 0 then
    g.setColor(0.32, 0.62, 0.98, 1); g.rectangle("fill", x, y, w * ratio, 6 * u, 3 * u, 3 * u)
  end
  return y + 14 * u
end

local function moveCategory(rec)
  local c = rec and (rec.category or rec.damageClass or rec.split or rec.kind)
  if c == nil then return nil end
  c = upperWords(c)
  if c == "0" then return "PHYSICAL" elseif c == "1" then return "SPECIAL" elseif c == "2" then return "STATUS" end
  return c
end

local function drawMoves(game, state, mon, x, y, w, t)
  local u = t.u
  local moves = mon.moves or {}
  local rowH = 52 * u
  local rows = 4
  local choose = type(state.choose) == "table" and state.choose or nil
  local chooseEntry = choose and (choose.move or choose.id or choose.newMove)
  if chooseEntry then rows = 5 end
  local cursor = (state.moveMode or state.moveSelect or choose) and tonumber(state.moveIndex) or nil
  for i = 1, rows do
    local entry = (i == 5) and chooseEntry or moves[i]
    local rec, id = moveRecord(game, entry)
    local ry = y + (i - 1) * (rowH + 6 * u)
    if cursor == i then selectedRow(x, ry, w, rowH, t.radius * 0.6, u)
    else color("surface2"); love.graphics.rectangle("fill", x, ry, w, rowH, t.radius * 0.6, t.radius * 0.6) end
    if id then
      local chipW = 0
      if rec and rec.type then chipW = typeChip(rec.type, x + 18 * u, ry + (rowH - 20 * u) / 2, 20 * u, t) end
      local name = tostring((rec and rec.name) or upperWords(id)):upper()
      local nx = x + 26 * u + chipW
      text(name, nx, ry + (rowH - font(t.body):getHeight()) / 2, fit(name, t.body, w * 0.5, t.small), cursor == i and "text" or "dim")
      local maxPp = rec and tonumber(rec.pp)
      if maxPp and type(entry) == "table" then
        maxPp = maxPp + math.min(3, math.max(0, tonumber(entry.ppUps) or 0)) * math.floor(maxPp / 5)
      end
      local pp = type(entry) == "table" and tonumber(entry.pp) or maxPp
      text(("PP %s/%s"):format(tostring(pp or "—"), tostring(maxPp or "—")), x, ry + (rowH - font(t.small):getHeight()) / 2,
        t.small, "dim", "right", w - 16 * u)
    else
      text("—", x + 22 * u, ry + (rowH - font(t.body):getHeight()) / 2, t.body, "dim")
    end
    if i == 5 then
      text("NEW", x, ry - 2 * u, t.tiny, "accent", "right", w - 8 * u)
    end
  end
  y = y + rows * (rowH + 6 * u) + 8 * u
  -- the selected move's details, the way every cartridge shows them
  local entry = cursor and ((cursor == 5 and chooseEntry) or moves[cursor]) or nil
  local rec = entry and moveRecord(game, entry)
  if rec then
    local col = w / 3
    local function stat(label, value, cx)
      text(label, cx, y, t.tiny, "dim")
      text(value, cx, y + font(t.tiny):getHeight() + 2 * u, t.body, "text")
    end
    stat("CATEGORY", moveCategory(rec) or "—", x)
    local power, acc = tonumber(rec.power), tonumber(rec.accuracy)
    stat("POWER", (power and power > 1) and tostring(power) or "—", x + col)
    stat("ACCURACY", (acc and acc > 0) and tostring(acc) or "—", x + col * 2)
    y = y + font(t.tiny):getHeight() + font(t.body):getHeight() + 12 * u
    local desc = rec.description or rec.desc
    if desc then
      for _, line in ipairs(wrapLines(desc, font(t.small), w, 3)) do
        text(line, x, y, t.small, "dim"); y = y + font(t.small):getHeight() + 2 * u
      end
    end
  end
  return y
end

function Screens.summary(state, game, t)
  local view = summaryView(state)
  if not (view and view.kind) then return false end
  local mon = state.mon
  local u = t.u
  backdrop(t)
  local leftW = clamp(t.sw * 0.34, 260 * u, 420 * u)
  local h = t.sh - t.pad * 2
  local maxW = math.min(t.sw - t.pad * 2, 1240 * u)
  local x0 = (t.sw - maxW) / 2
  monColumn(game, mon, x0, t.pad, leftW, h, t, function(px, py, pw, ph)
    local fn = GoldCompat.drawStatsInformationPortrait
    if type(fn) == "function" then return fn(game, mon, px, py, pw, ph) end
    return portrait(game, mon, px, py, pw, ph, "summary")
  end)
  local rx = x0 + leftW + t.gap
  local rw = maxW - leftW - t.gap
  card(rx, t.pad, rw, h, t.radius)
  local ix, iw = rx + 20 * u, rw - 40 * u
  local y = t.pad + 16 * u
  y = y + tabs(view.labels, view.active, ix, y, iw, t) + 18 * u
  if view.kind == "info" then drawInfo(game, mon, ix, y, iw, t)
  elseif view.kind == "skills" then drawSkills(game, mon, ix, y, iw, t)
  elseif view.kind == "overview" then
    local half = (iw - 24 * u) / 2
    drawInfo(game, mon, ix, y, half, t)
    drawSkills(game, mon, ix + half + 24 * u, y, half, t)
  else
    drawMoves(game, state, mon, ix, y, iw, t)
  end
  text("LEFT / RIGHT  PAGE        UP / DOWN  POKéMON", rx, t.pad + h - 26 * u, t.tiny, "dim", "center", rw)
  return true
end

local function summaryAccepts(state)
  if type(state.mon) ~= "table" or isEgg(state.mon) then return false end
  local view = summaryView(state)
  return view ~= nil and view.kind ~= nil
end

-- BAG. Emerald / Platinum / Black & White read as a vertical list; HGSS is a
-- 2 x 3 grid of six a page -- each drawn in the shape its update() walks.
-- The toss counter and the move-an-item mode are declined (native).
local function bagView(state, variant)
  local v = { pockets = {}, pocket = state.pocket or 1, rows = {}, index = 1, layout = "list" }
  for i, p in ipairs(state.pockets or {}) do
    v.pockets[i] = tostring(type(p) == "table" and (p.name or p.key) or p):upper()
  end
  if state.lockPocket then v.pockets = { v.pockets[v.pocket] or "BAG" }; v.pocket = 1 end
  if variant == "gen3" then
    v.rows = state.rows or {}
    v.index = state.index or 1
    v.message = state.resultMessage
  elseif variant == "hgss" then
    local ok, items = pcall(state.items, state)
    v.rows = ok and items or {}
    v.index = (state.page or 0) * 6 + (state.slot or 1)
    v.layout, v.page = "grid", state.page or 0
  elseif variant == "gen5" then
    v.rows = state.rows or {}
    v.index = state.cursor or 1
  else
    -- Platinum's rows carry header sentinels at both ends
    local rows, at = {}, 1
    for i, row in ipairs(state.rows or {}) do
      if not row.header then
        rows[#rows + 1] = row
        if i == state.index then at = #rows end
      end
    end
    v.rows, v.index = rows, at
  end
  if variant ~= "gen3" then
    v.message = (state.message ~= nil and state.message ~= "") and state.message or nil
    local m = state.menu
    if type(m) == "table" and type(m.rows) == "table" then
      local labels = {}
      for i, r in ipairs(m.rows) do
        if m.kind == "yesno" then labels[i] = tostring(r):upper()
        else
          local ok, l = pcall(state.actionLabel, state, r)
          labels[i] = tostring(ok and l or r):upper()
        end
      end
      v.menu = { labels = labels, index = m.index or 1 }
    end
  end
  return v
end

local function bagAccepts(state)
  if state.moving or state.dial then return false end
  if state.trash and not (type(state.menu) == "table" and state.menu.kind == "yesno") then return false end
  return true
end

function Screens.bag(state, game, t, variant)
  local v = bagView(state, variant)
  local u = t.u
  backdrop(t)
  local maxW = math.min(t.sw - t.pad * 2, 1240 * u)
  local x0 = (t.sw - maxW) / 2
  local y = t.pad
  -- pocket tabs
  y = y + tabs(v.pockets, v.pocket, x0, y, maxW, t) + t.gap
  local hint = #v.pockets > 1 and "LEFT / RIGHT  POCKET" or ""
  if v.layout == "grid" then hint = "LEFT / RIGHT  PAGE" end
  local barY = bottomBar(t, v.message and tostring(v.message):gsub("{[^}]*}", "") or hint, nil)
  local areaH = barY - y - t.gap
  local listW = maxW * 0.58
  local selected = v.rows[v.index]

  if v.layout == "grid" then
    card(x0, y, listW, areaH, t.radius)
    local cw = (listW - 30 * u) / 2
    local ch = math.min((areaH - 50 * u) / 3, 96 * u)
    local first = v.page * 6
    for s = 1, 6 do
      local row = v.rows[first + s]
      local cx = x0 + 10 * u + ((s - 1) % 2) * (cw + 10 * u)
      local cy = y + 10 * u + math.floor((s - 1) / 2) * (ch + 10 * u)
      local sel = (first + s) == v.index
      if sel then selectedRow(cx, cy, cw, ch, t.radius * 0.6, u)
      else color("surface2"); love.graphics.rectangle("fill", cx, cy, cw, ch, t.radius * 0.6, t.radius * 0.6) end
      if row then
        local label = tostring(row.label or itemName(game, row.id) or "?"):upper()
        text(label, cx + 16 * u, cy + ch / 2 - font(t.small):getHeight(), fit(label, t.small, cw - 32 * u, t.tiny), sel and "text" or "dim")
        if row.qty and not row.important then text("x" .. tostring(row.qty), cx, cy + ch / 2 + 2 * u, t.small, "dim", "right", cw - 16 * u) end
      end
    end
    local pages = math.max(1, math.ceil(#v.rows / 6))
    text(("PAGE %d / %d"):format(v.page + 1, pages), x0, y + areaH - 26 * u, t.tiny, "dim", "center", listW)
  else
    card(x0, y, listW, areaH, t.radius)
    local rowH = 40 * u
    local visible = math.max(1, math.floor((areaH - 20 * u) / rowH))
    local top = clamp(v.index - math.floor(visible / 2), 1, math.max(1, #v.rows - visible + 1))
    for k = 0, visible - 1 do
      local i = top + k
      local row = v.rows[i]
      if not row then break end
      local ry = y + 10 * u + k * rowH
      local sel = i == v.index
      if sel then selectedRow(x0 + 8 * u, ry, listW - 16 * u, rowH - 4 * u, t.radius * 0.6, u) end
      local label = tostring(row.label or itemName(game, row.id) or "?"):upper()
      if row.number then label = (row.hm and "HM" or "No.") .. ("%02d  "):format(row.number) .. label end
      local size = fit(label, t.body, listW * 0.7, t.small)
      text(label, x0 + 26 * u, ry + (rowH - 4 * u - font(size):getHeight()) / 2, size, sel and "text" or "dim")
      if row.qty and not row.important and not row.close then
        text("x" .. tostring(row.qty), x0, ry + (rowH - 4 * u - font(t.small):getHeight()) / 2, t.small, "dim", "right", listW - 26 * u)
      end
      if row.registered then
        color("accent"); love.graphics.circle("fill", x0 + listW - 14 * u, ry + rowH / 2 - 2 * u, 3 * u)
      end
    end
    if #v.rows > visible then
      local trackH = areaH - 20 * u
      local thumb = math.max(20 * u, trackH * visible / #v.rows)
      local ty = y + 10 * u + (trackH - thumb) * ((top - 1) / math.max(1, #v.rows - visible))
      color("accent"); love.graphics.rectangle("fill", x0 + listW - 6 * u, ty, 3 * u, thumb, 1.5 * u, 1.5 * u)
    end
  end

  -- details of the selected item
  local dx, dw = x0 + listW + t.gap, maxW - listW - t.gap
  card(dx, y, dw, areaH, t.radius)
  if selected and not selected.close then
    local rec = itemRecord(game, selected.id)
    local name = tostring(selected.label or itemName(game, selected.id) or "?"):upper()
    local iy = y + 18 * u
    text(name, dx + 18 * u, iy, fit(name, t.title, dw - 36 * u, t.small), "text")
    iy = iy + font(t.title):getHeight() + 6 * u
    if selected.qty and not selected.important then
      text("IN BAG  x" .. tostring(selected.qty), dx + 18 * u, iy, t.small, "accent")
      iy = iy + font(t.small):getHeight() + 10 * u
    end
    local desc = selected.description or (rec and (rec.description or rec.desc))
    if desc then
      for _, line in ipairs(wrapLines((tostring(desc):gsub("{[^}]*}", "")), font(t.small), dw - 36 * u, 8)) do
        text(line, dx + 18 * u, iy, t.small, "dim"); iy = iy + font(t.small):getHeight() + 3 * u
      end
    end
  elseif selected then
    text(tostring(selected.label or "CLOSE BAG"):upper(), dx, y + areaH / 2 - 10 * u, t.body, "dim", "center", dw)
  else
    text("NO ITEMS", dx, y + areaH / 2 - 10 * u, t.body, "dim", "center", dw)
  end

  if v.menu then
    local w = clamp(260 * u, 200, dw - 20 * u)
    listPanel(v.menu.labels, v.menu.index, dx + dw - w - 10 * u, 0, w, t,
      function(label) return label end, selected and tostring(selected.label or ""):upper() or nil, barY - t.gap)
  end
  return true
end

-- PC BOXES. Emerald / FireRed / Platinum / HGSS / Black & White all keep the
-- same cursor fields -- row 0 the box name, rows 1-5 the 6-wide grid, then
-- the buttons, and partyOpen / partyIndex for the party panel -- so one
-- layout draws them all: details left, box centre, party right.
local function sprite2d(game, mon, x, y, w, h)
  local fn = GoldCompat.drawResolvedSpritePortrait
  if type(fn) ~= "function" then return false end
  local ok, drew = pcall(fn, game, mon, x, y, w, h, "pc-cell")
  return ok and drew
end

function Screens.pc(state, game, t, variant)
  local u = t.u
  backdrop(t)
  local okB, box = pcall(state.box, state)
  box = okB and type(box) == "table" and box or {}
  local okN, boxName = pcall(state.boxName, state)
  local party = (game.save or {}).party or {}
  local maxW = math.min(t.sw - t.pad * 2, 1280 * u)
  local x0 = (t.sw - maxW) / 2
  local message = state.message
  if message == "" then message = nil end
  local barY = bottomBar(t, message and tostring(message):gsub("{[^}]*}", "") or "", nil)
  local top = t.pad
  local areaH = barY - top - t.gap

  local detailW = maxW * 0.26
  local partyW = maxW * 0.22
  local boxW = maxW - detailW - partyW - t.gap * 2
  local bx = x0 + detailW + t.gap
  local px = bx + boxW + t.gap

  -- which mon the details show: the held one, else the one under the cursor
  local onButtons = state.onButtons or (variant ~= "gen3" and state.row == 6)
  local slot = (state.row or 1) >= 1 and (state.row or 1) <= 5
    and ((state.row - 1) * 6 + (state.col or 1)) or nil
  local focus
  if type(state.held) == "table" then focus = state.held.mon
  elseif state.partyOpen then focus = party[state.partyIndex or 1]
  elseif slot and not onButtons then focus = box[slot] end

  -- details
  if type(focus) == "table" then
    monColumn(game, focus, x0, top, detailW, areaH, t, function(qx, qy, qw, qh)
      local fn = GoldCompat.drawPcInformationPortrait
      if type(fn) == "function" then return fn(game, focus, qx, qy, qw, qh) end
      return portrait(game, focus, qx, qy, qw, qh, "pc")
    end)
  else
    card(x0, top, detailW, areaH, t.radius)
    text("—", x0, top + areaH / 2 - 10 * u, t.body, "dim", "center", detailW)
  end

  -- box: header, grid, buttons
  card(bx, top, boxW, areaH, t.radius)
  local hh = 44 * u
  local hy = top + 10 * u
  if state.row == 0 and not state.partyOpen then
    selectedRow(bx + 10 * u, hy, boxW - 20 * u, hh, t.radius * 0.6, u)
  else
    color("surface2"); love.graphics.rectangle("fill", bx + 10 * u, hy, boxW - 20 * u, hh, t.radius * 0.6, t.radius * 0.6)
  end
  text("<", bx + 22 * u, hy + (hh - font(t.body):getHeight()) / 2, t.body, "accent")
  text(">", bx, hy + (hh - font(t.body):getHeight()) / 2, t.body, "accent", "right", boxW - 22 * u)
  text(tostring(okN and boxName or "BOX"):upper(), bx, hy + (hh - font(t.body):getHeight()) / 2, t.body, "text", "center", boxW)

  local btnH = 40 * u
  local gy = hy + hh + 10 * u
  local gridH = areaH - (gy - top) - btnH - 20 * u
  local cell = math.min((boxW - 20 * u - 5 * 6 * u) / 6, (gridH - 4 * 6 * u) / 5)
  local gw = cell * 6 + 5 * 6 * u
  local gx = bx + (boxW - gw) / 2
  for r = 1, 5 do
    for c = 1, 6 do
      local cx = gx + (c - 1) * (cell + 6 * u)
      local cy = gy + (r - 1) * (cell + 6 * u)
      local here = not state.partyOpen and not onButtons and state.row == r and state.col == c
      if here then selectedRow(cx, cy, cell, cell, t.radius * 0.5, u)
      else color("surface2"); love.graphics.rectangle("fill", cx, cy, cell, cell, t.radius * 0.5, t.radius * 0.5) end
      local mon = box[(r - 1) * 6 + c]
      if type(mon) == "table" then sprite2d(game, mon, cx + 2 * u, cy + 2 * u, cell - 4 * u, cell - 4 * u) end
    end
  end
  local by = top + areaH - btnH - 10 * u
  local labels = { "PARTY POKéMON", "CLOSE BOX" }
  local which = variant == "gen3" and (state.onButtons and state.buttonIndex or nil)
    or (state.row == 6 and not state.partyOpen and ((state.col or 1) <= 3 and 1 or 2) or nil)
  local bw2 = (boxW - 30 * u) / 2
  for i, label in ipairs(labels) do
    local qx = bx + 10 * u + (i - 1) * (bw2 + 10 * u)
    if which == i then selectedRow(qx, by, bw2, btnH, t.radius * 0.6, u)
    else color("surface2"); love.graphics.rectangle("fill", qx, by, bw2, btnH, t.radius * 0.6, t.radius * 0.6) end
    text(label, qx, by + (btnH - font(t.small):getHeight()) / 2, fit(label, t.small, bw2 - 16 * u, t.tiny), which == i and "text" or "dim", "center", bw2)
  end

  -- party panel: Platinum-family pairs (odd left, even right) + EXIT;
  -- Emerald's single column + CANCEL
  card(px, top, partyW, areaH, t.radius)
  text("PARTY", px, top + 10 * u, t.small, "dim", "center", partyW)
  local slotsY = top + 36 * u
  local exitH = 40 * u
  local slotH = (areaH - (slotsY - top) - exitH - 24 * u)
  local cursorIn = state.partyOpen
  if variant == "gen3" then
    local rh = (slotH - 5 * 6 * u) / 6
    for i = 1, 6 do
      local qy = slotsY + (i - 1) * (rh + 6 * u)
      local sel = cursorIn and state.partyIndex == i
      if sel then selectedRow(px + 8 * u, qy, partyW - 16 * u, rh, t.radius * 0.5, u)
      else color("surface2"); love.graphics.rectangle("fill", px + 8 * u, qy, partyW - 16 * u, rh, t.radius * 0.5, t.radius * 0.5) end
      if party[i] then
        sprite2d(game, party[i], px + 10 * u, qy + 2 * u, rh - 4 * u, rh - 4 * u)
        text(monName(game, party[i]), px + rh + 12 * u, qy + (rh - font(t.tiny):getHeight()) / 2,
          fit(monName(game, party[i]), t.tiny, partyW - rh - 28 * u, 8), sel and "text" or "dim")
      end
    end
  else
    local cw = (partyW - 22 * u) / 2
    local rh = (slotH - 2 * 6 * u) / 3
    for i = 1, 6 do
      local qx = px + 8 * u + ((i - 1) % 2) * (cw + 6 * u)
      local qy = slotsY + math.floor((i - 1) / 2) * (rh + 6 * u)
      local sel = cursorIn and state.partyIndex == i
      if sel then selectedRow(qx, qy, cw, rh, t.radius * 0.5, u)
      else color("surface2"); love.graphics.rectangle("fill", qx, qy, cw, rh, t.radius * 0.5, t.radius * 0.5) end
      if party[i] then
        local s = math.min(cw, rh) - 6 * u
        sprite2d(game, party[i], qx + (cw - s) / 2, qy + 3 * u, s, s)
      end
    end
  end
  local ey = top + areaH - exitH - 10 * u
  local exitSel = cursorIn and (state.partyIndex or 0) >= 7
  if exitSel then selectedRow(px + 8 * u, ey, partyW - 16 * u, exitH, t.radius * 0.6, u)
  else color("surface2"); love.graphics.rectangle("fill", px + 8 * u, ey, partyW - 16 * u, exitH, t.radius * 0.6, t.radius * 0.6) end
  text(variant == "gen3" and "CANCEL" or "EXIT", px, ey + (exitH - font(t.small):getHeight()) / 2, t.small, exitSel and "text" or "dim", "center", partyW)

  -- the held Pokemon floats over the box, the way every PC shows a carry
  if type(state.held) == "table" and type(state.held.mon) == "table" then
    local s = cell * 1.1
    local hx = gx + ((state.col or 1) - 1) * (cell + 6 * u) - s * 0.15
    local hy2 = gy + math.max(0, (state.row or 1) - 1) * (cell + 6 * u) - s * 0.45
    love.graphics.setColor(0, 0, 0, 0.35)
    love.graphics.ellipse("fill", hx + s / 2, hy2 + s * 0.95, s * 0.35, s * 0.1)
    sprite2d(game, state.held.mon, hx, hy2, s, s)
  end

  -- a slot / header action menu (Platinum family: state.menu + state.action)
  if type(state.menu) == "table" and #state.menu > 0 then
    local w = clamp(260 * u, 200, partyW + 40 * u)
    listPanel(state.menu, state.action or 1, px + partyW - w, 0, w, t,
      function(row) return tostring(type(row) == "table" and (row.label or row.key) or row):upper() end,
      nil, barY - t.gap)
  end
  return true
end

-- POKeDEX: the list view of each cartridge (entry pages, search and HGSS's
-- lid stay native). Emerald / Platinum / Black & White are lists; HGSS is a
-- 5 x 3 grid of fifteen a page, the shape HgssPokedex:move walks.
local function dexStatus(state, game, species)
  if species == nil then return nil end
  if type(state.status) == "function" then
    local ok, s = pcall(state.status, state, species)
    if ok then return s end
  end
  local dex = (game.save or {}).pokedex or {}
  if (dex.owned or {})[species] then return "owned" end
  if (dex.seen or {})[species] then return "seen" end
  return nil
end

local function dexView(state, variant)
  if variant == "gen3" then
    return { list = state.list or {}, count = state.count or #(state.list or {}), index = state.index or 1 }
  elseif variant == "gen4" then
    return { list = state.entries or {}, index = state.index or 1, numbers = state.numbers }
  elseif variant == "hgss" then
    local list = {}
    for i = 1, state.count or 0 do list[i] = state.order and state.order[i] end
    local okI, idx = pcall(state.index, state)
    return { list = list, index = okI and idx or 1, grid = true, page = state.page or 0, cursor = state.cursor or 0 }
  end
  return { list = state.entries or {}, index = state.cursor or 1 }
end

local function dexAccepts(state, variant)
  if variant == "gen4" then return state.page == "list" end
  if variant == "hgss" then return state.state == "list" end
  if variant == "gen5" then return state.mode == "list" end
  return true
end

function Screens.dex(state, game, t, variant)
  local v = dexView(state, variant)
  local u = t.u
  backdrop(t)
  local count = v.count or #v.list
  local maxW = math.min(t.sw - t.pad * 2, 1240 * u)
  local x0 = (t.sw - maxW) / 2
  local h = t.sh - t.pad * 2
  local leftW = maxW * 0.36
  local species = v.list[v.index]
  local status = dexStatus(state, game, species)

  -- totals
  local seen, owned = 0, 0
  for i = 1, count do
    local s = dexStatus(state, game, v.list[i])
    if s then seen = seen + 1 end
    if s == "owned" then owned = owned + 1 end
  end

  -- the selected species
  local function number(i, sp)
    if variant == "hgss" and type(state.number) == "function" then
      local ok, n = pcall(state.number, state, i); if ok and n then return n end
    end
    if v.numbers and v.numbers[sp] then return v.numbers[sp] end
    if variant == "gen3" or variant == "gen5" then return i end
    return dexNumber(game, sp) or i
  end
  card(x0, t.pad, leftW, h, t.radius)
  local podS = math.min(leftW - 40 * u, h * 0.52)
  local podX, podY = x0 + (leftW - podS) / 2, t.pad + 18 * u
  love.graphics.setColor(0, 0, 0, 0.30)
  love.graphics.rectangle("fill", podX, podY, podS, podS, t.radius, t.radius)
  if species and status then
    local mon = { species = species, level = 50 }
    local fn = GoldCompat.drawPokedexInformationPortrait
    if type(fn) == "function" then pcall(fn, game, mon, podX, podY, podS, podS)
    else portrait(game, mon, podX, podY, podS, podS, "dex") end
  else
    text("?", podX, podY + podS / 2 - font(t.title * 2):getHeight() / 2, t.title * 2, "dim", "center", podS)
  end
  local ty = podY + podS + 14 * u
  local nameStr = status and speciesName(game, species) or "-----"
  text(("No. %03d"):format(number(v.index, species) or 0), x0 + 20 * u, ty, t.small, "dim")
  if status == "owned" then text("CAUGHT", x0 + 20 * u, ty, t.tiny, "accent", "right", leftW - 40 * u) end
  ty = ty + font(t.small):getHeight() + 4 * u
  text(nameStr, x0 + 20 * u, ty, fit(nameStr, t.title, leftW - 40 * u, t.small), "text")
  ty = ty + font(t.title):getHeight() + 10 * u
  if status then
    local cx = x0 + 20 * u
    for _, ty_ in ipairs(typesOf(game, species)) do cx = cx + typeChip(ty_, cx, ty, 22 * u, t) + 6 * u end
  end
  local sy = t.pad + h - 60 * u
  infoRow("SEEN", tostring(seen), x0 + 20 * u, sy, leftW - 40 * u, t)
  infoRow("OWNED", tostring(owned), x0 + 20 * u, sy + font(t.small):getHeight() + 8 * u, leftW - 40 * u, t)

  -- the list
  local lx, lw = x0 + leftW + t.gap, maxW - leftW - t.gap
  card(lx, t.pad, lw, h, t.radius)
  if v.grid then
    local cols, rows = 5, 3
    local first = v.page * 15
    local cw = (lw - 20 * u - (cols - 1) * 8 * u) / cols
    local ch = math.min((h - 70 * u - (rows - 1) * 8 * u) / rows, cw * 1.1)
    for k = 0, 14 do
      local i = first + k + 1
      local cx = lx + 10 * u + (k % cols) * (cw + 8 * u)
      local cy = t.pad + 14 * u + math.floor(k / cols) * (ch + 8 * u)
      local sp = v.list[i]
      local sel = k == v.cursor
      if sel then selectedRow(cx, cy, cw, ch, t.radius * 0.5, u)
      else color("surface2"); love.graphics.rectangle("fill", cx, cy, cw, ch, t.radius * 0.5, t.radius * 0.5) end
      if i <= count then
        local s = dexStatus(state, game, sp)
        if s then sprite2d(game, { species = sp, level = 50 }, cx + 6 * u, cy + 4 * u, cw - 12 * u, ch - 26 * u) end
        text(("%03d"):format(number(i, sp) or i), cx, cy + ch - font(t.tiny):getHeight() - 4 * u, t.tiny,
          s == "owned" and "accent" or "dim", "center", cw)
      end
    end
    local pages = math.max(1, math.ceil(count / 15))
    text(("PAGE %d / %d"):format(v.page + 1, pages), lx, t.pad + h - 30 * u, t.tiny, "dim", "center", lw)
  else
    local rowH = 40 * u
    local visible = math.max(1, math.floor((h - 20 * u) / rowH))
    local top = clamp(v.index - math.floor(visible / 2), 1, math.max(1, count - visible + 1))
    for k = 0, visible - 1 do
      local i = top + k
      if i > count then break end
      local sp = v.list[i]
      local ry = t.pad + 10 * u + k * rowH
      local sel = i == v.index
      if sel then selectedRow(lx + 8 * u, ry, lw - 16 * u, rowH - 4 * u, t.radius * 0.6, u) end
      local s = dexStatus(state, game, sp)
      local mid = ry + (rowH - 4 * u - font(t.body):getHeight()) / 2
      text(("%03d"):format(number(i, sp) or i), lx + 26 * u, mid, t.body, sel and "text" or "dim")
      text(s and speciesName(game, sp) or "-----", lx + 100 * u, mid, t.body, sel and "text" or (s and "dim" or { 0.40, 0.46, 0.46, 1 }))
      if s == "owned" then
        local bx, by = lx + lw - 30 * u, ry + (rowH - 4 * u) / 2
        love.graphics.setColor(0.94, 0.32, 0.28, 1); love.graphics.arc("fill", bx, by, 7 * u, math.pi, 2 * math.pi)
        love.graphics.setColor(0.95, 0.95, 0.95, 1); love.graphics.arc("fill", bx, by, 7 * u, 0, math.pi)
        love.graphics.setColor(0.1, 0.1, 0.1, 1); love.graphics.circle("line", bx, by, 7 * u)
      end
    end
  end
  return true
end

-- class module -> screen renderer
CG.CLASSES = {
  { module = "src.ui.Gen3StartMenu", draw = Screens.startList },
  { module = "src.ui.Gen4StartMenu", draw = Screens.startList },
  { module = "src.ui.Gen5StartMenu", draw = Screens.startGrid },
  { module = "src.ui.HgssStartMenu", draw = Screens.startColumns },
  { module = "src.ui.Gen3PartyMenu", draw = Screens.party3 },
  { module = "src.ui.Gen4PartyMenu", draw = Screens.party4 },

  { module = "src.ui.Gen3SummaryMenu", draw = Screens.summary, accepts = summaryAccepts },
  { module = "src.ui.Gen4SummaryMenu", draw = Screens.summary, accepts = summaryAccepts },
  { module = "src.ui.HgssSummaryMenu", draw = Screens.summary, accepts = summaryAccepts },
  { module = "src.ui.Gen5SummaryMenu", draw = Screens.summary, accepts = summaryAccepts },
}

local function variantOf(name, fn, variant, accepts)
  return { module = name, accepts = accepts and function(s) return accepts(s, variant) end or nil,
    draw = function(s, g, t) return fn(s, g, t, variant) end }
end
for _, e in ipairs({
  variantOf("src.ui.Gen3BagMenu", Screens.bag, "gen3", bagAccepts),
  variantOf("src.ui.Gen4BagMenu", Screens.bag, "gen4", bagAccepts),
  variantOf("src.ui.HgssBagMenu", Screens.bag, "hgss", bagAccepts),
  variantOf("src.ui.Gen5BagMenu", Screens.bag, "gen5", bagAccepts),
  variantOf("src.ui.Gen3BoxMenu", Screens.pc, "gen3"),
  variantOf("src.ui.Gen4BoxMenu", Screens.pc, "gen4"),
  variantOf("src.ui.HgssBoxMenu", Screens.pc, "hgss"),
  variantOf("src.ui.Gen5BoxMenu", Screens.pc, "gen5"),
  variantOf("src.ui.Gen3Pokedex", Screens.dex, "gen3", dexAccepts),
  variantOf("src.ui.Gen4Pokedex", Screens.dex, "gen4", dexAccepts),
  variantOf("src.ui.HgssPokedex", Screens.dex, "hgss", dexAccepts),
  variantOf("src.ui.Gen5Pokedex", Screens.dex, "gen5", dexAccepts),
}) do CG.CLASSES[#CG.CLASSES + 1] = e end

-- ------------------------------------------------------------- ownership

function CG.enabled()
  if type(deps.enabled) == "function" then
    local ok, on = pcall(deps.enabled)
    if ok then return on ~= false end
  end
  return true
end

local function hudAlive() return now() - CG.hudAt <= CG.LIVE_WINDOW end

-- which renderer serves this exact state (by its class, not a parent's)
local byClass = setmetatable({}, { __mode = "k" })
local function rendererFor(state)
  local mt = getmetatable(state)
  local entry = mt and byClass[mt]
  if entry and not CG.failed[entry.module] then return entry end
  return nil
end

function CG.owns(state)
  if not (CG.enabled() and hudAlive()) then return false end
  local entry = rendererFor(state)
  if not entry then return false end
  -- a screen may decline a sub-state it does not redraw (contest pages,
  -- ribbon views, the toss counter...): the cartridge screen draws instead
  if entry.accepts then
    local ok, yes = pcall(entry.accepts, state)
    if not (ok and yes) then return false end
  end
  return true
end

function CG.install()
  local count = 0
  for _, entry in ipairs(CG.CLASSES) do
    local ok, Class = pcall(require, entry.module)
    if ok and type(Class) == "table" then
      byClass[Class] = entry
      -- wrap the class's OWN draw (Gen5StartMenu inherits Gen4's otherwise)
      local own = rawget(Class, "draw")
      if type(own) == "function" and not rawget(Class, "__terrariumCrossGen") then
        rawset(Class, "__terrariumCrossGen", true)
        rawset(Class, "draw", function(self, ...)
          if CG.owns(self) then
            self.__terrariumCrossGenFrame = CG.frame
            return
          end
          return own(self, ...)
        end)
        count = count + 1
      end
    end
  end
  log("info", "Terrarium Gen 3-5 screens installed (%d classes)", count)
  return count
end

-- render.hud: draw every owned state the engine drew this frame, bottom to
-- top, at window resolution.
function CG.hud(game)
  CG.hudAt = now()
  local frame = CG.frame
  CG.frame = frame + 1
  if not CG.enabled() then return end
  local states = game and game.stack and game.stack.states
  if type(states) ~= "table" then return end
  local t
  for _, state in ipairs(states) do
    if type(state) == "table" and state.__terrariumCrossGenFrame == frame then
      local entry = rendererFor(state)
      if entry then
        t = t or CG.tokens()
        local g = love.graphics
        g.push("all")
        g.origin()
        g.setScissor()
        local ok, err = pcall(entry.draw, state, game, t)
        g.pop()
        if not ok then
          CG.failed[entry.module] = true
          log("warn", "Terrarium %s screen failed, native screen restored: %s",
            entry.module, tostring(err))
        end
      end
    end
  end
end

CG.Screens = Screens
return CG
