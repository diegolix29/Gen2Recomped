-- Gen4StartMenuHook: puts the TERRARIUM BATTLES row on Platinum's start menu,
-- and keeps HeartGold / SoulSilver / Black-White from crashing on hooked rows.
--
-- WHY HGSS CRASHED
--
-- The engine's Gen 4 menu now runs `ui.start_menu.items`. Game Boy-style rows
-- from that seam have a label and onSelect, but no `id`. HgssStartMenu.new
-- (and Gen5StartMenu.new) then do `keep[row.id] = true` and Lua throws
-- "table index is nil".
--
-- HGSS / BW also rebuild the list from a cartridge ORDER after Gen4StartMenu.new
-- returns, so a row injected there is dropped unless we inject again afterwards.
--
-- WHAT THIS DOES (engine files untouched)
--
--   * sanitize  give every hooked row a non-nil id before HGSS/BW index it.
--   * new       after Platinum builds the menu, insert TERRARIUM BATTLES
--               before OPTIONS.
--   * hgss/bw   wrap those constructors so the row is put back after they
--               rebuild, using the extra icon slot the way MODS does.
--   * select    the injected row pops the menu and runs its onSelect.
--   * layout    Platinum's panel widens / scrolls when the extra row does not
--               fit. HGSS has eight icon buttons; MODS waits if they are full.
--
-- The dedicated inject is still used (rather than relying only on
-- `ui.start_menu.items`) because HGSS/BW throw away unknown ids.

local Hook = { installed = false, factory = nil }

local SCREEN_H = 192
local HGSS_SLOTS = 8
local ROW_ID = "terrariumBattles"

local function log(level, fmt, ...)
  local ok, Logger = pcall(require, "src.core.Logger")
  if ok and Logger and Logger[level] then pcall(Logger[level], fmt, ...) end
end

local function isGen4()
  local ok, GameVersion = pcall(require, "src.core.GameVersion")
  if not (ok and GameVersion and GameVersion.generation) then return false end
  local okGen, value = pcall(GameVersion.generation)
  return okGen and tonumber(value) == 4
end

local function isTerrariumRow(row)
  return type(row) == "table" and (
    row.id == ROW_ID
    or row.__terrariumBattleEntry == true
    or (type(row.entry) == "table" and row.entry.__terrariumBattleEntry == true)
  )
end

-- HgssStartMenu.new / Gen5StartMenu.new: `keep[row.id] = true`. A nil key
-- raises "table index is nil" and takes down the field menu.
local function sanitize(self)
  for i, row in ipairs(self.rows) do
    if type(row) == "table" and row.id == nil then
      if row.__terrariumBattleEntry then
        row.id = ROW_ID
      else
        row.id = "modrow_" .. i
      end
    end
  end
end

-- How many rows fit below the panel's top edge at this layout.
local function capacity(L)
  local top = math.floor((L.panelY or 8) / 8)
  local rowTiles = L.rowTiles or 3
  return math.max(1, math.floor((SCREEN_H / 8 - top) / rowTiles))
end

-- Grow the panel to the left until the widest label fits between the icon
-- column and the right edge. Copies the layout: the record it came from is the
-- cartridge's own and is shared.
local function widen(self)
  local L0 = self.layout
  local okFont, Font = pcall(require, "src.render.Font")
  if not (okFont and Font and Font.width and L0) then return end
  local widest = 0
  for _, row in ipairs(self.rows) do
    local ok, w = pcall(Font.width, row.label or "")
    if ok and type(w) == "number" and w > widest then widest = w end
  end
  local avail = (L0.panelX + L0.panelW - 6) - (L0.iconX + 14)
  if widest <= avail then return end
  local grow = math.ceil((widest - avail) / 8) * 8
  grow = math.min(grow, math.max(0, math.floor((L0.panelX - 8) / 8) * 8))
  if grow <= 0 then return end
  local L = {}
  for k, v in pairs(L0) do L[k] = v end
  L.panelX = L0.panelX - grow
  L.panelW = L0.panelW + grow
  L.iconX = L0.iconX - grow
  L.cursorX = L0.cursorX - grow
  self.layout = L
end

local function makeRow(entry)
  entry.__terrariumBattleEntry = true
  return {
    id = ROW_ID,
    label = entry.label,
    icon = nil,
    entry = entry,
    onSelect = entry.onSelect,
    __terrariumBattleEntry = true,
  }
end

local function insertBeforeOptions(self, row)
  local at = #self.rows + 1
  for i, existing in ipairs(self.rows) do
    if existing.id == "options" then at = i break end
  end
  table.insert(self.rows, at, row)
end

local function inject(self)
  if not (Hook.factory and isGen4()) then return end
  for _, row in ipairs(self.rows) do
    if isTerrariumRow(row) then return end
  end
  local ok, entry = pcall(Hook.factory, self.game)
  if not (ok and type(entry) == "table" and type(entry.label) == "string"
          and type(entry.onSelect) == "function") then
    log("warn", "gen4 start menu hook: no usable battle entry (%s)", tostring(entry))
    return
  end
  insertBeforeOptions(self, makeRow(entry))
  widen(self)
end

-- HGSS's touch panel has eight icon buttons. MODS already takes the spare
-- slot; if RETIRE (or this row) fills the grid, MODS waits, same as the
-- engine's own HgssStartMenu.new.
local function capHgss(self)
  if #self.rows <= HGSS_SLOTS then return end
  for i = #self.rows, 1, -1 do
    if self.rows[i] and self.rows[i].id == "mods" then
      table.remove(self.rows, i)
      if #self.rows <= HGSS_SLOTS then return end
    end
  end
  while #self.rows > HGSS_SLOTS do table.remove(self.rows) end
end

local function injectHgss(self)
  if not (Hook.factory and isGen4()) then return end
  for _, row in ipairs(self.rows) do
    if isTerrariumRow(row) then capHgss(self) return end
  end
  local ok, entry = pcall(Hook.factory, self.game)
  if not (ok and type(entry) == "table" and type(entry.label) == "string"
          and type(entry.onSelect) == "function") then
    return
  end
  insertBeforeOptions(self, makeRow(entry))
  capHgss(self)
end

local function wrapNew(Menu, after)
  local original = Menu.new
  Menu.new = function(...)
    local self = original(...)
    if type(self) == "table" and type(self.rows) == "table" then
      local okRun, err = pcall(after, self)
      if not okRun then log("warn", "gen4 start menu hook failed: %s", tostring(err)) end
    end
    return self
  end
  return original
end

-- Draw TERRARIUM BATTLES with the same spare-button art MODS uses (HGSS has
-- no cartridge icon for it). Temporarily treat the row as mods for drawPanel.
local function wrapHgssDraw(Hgss)
  local original = Hgss.drawPanel
  if type(original) ~= "function" then return nil end
  Hgss.drawPanel = function(self, ...)
    local restored = {}
    for _, row in ipairs(self.rows or {}) do
      if row.id == ROW_ID then
        row.id = "mods"
        restored[#restored + 1] = row
      end
    end
    local ok, err = pcall(original, self, ...)
    for _, row in ipairs(restored) do row.id = ROW_ID end
    if not ok then error(err, 0) end
  end
  return original
end

function Hook.install(factory)
  Hook.factory = factory
  if Hook.installed then return true end
  local ok, Menu = pcall(require, "src.ui.Gen4StartMenu")
  if not (ok and type(Menu) == "table" and type(Menu.new) == "function") then
    return false      -- not a Gen 4 build of the engine
  end
  Hook.Menu = Menu
  Hook.original = { new = Menu.new, select = Menu.select, drawPanel = Menu.drawPanel }

  Menu.new = function(...)
    local self = Hook.original.new(...)
    if type(self) == "table" and type(self.rows) == "table" then
      sanitize(self)
      local okInject, err = pcall(inject, self)
      if not okInject then log("warn", "gen4 start menu hook failed: %s", tostring(err)) end
    end
    return self
  end

  Menu.select = function(self, ...)
    local row = self.rows and self.rows[self.index]
    if not (row and row.entry) then return Hook.original.select(self, ...) end
    -- Same contract as Gen 1's generic StartMenu: pop first, then run the row.
    self.game.stack:pop()
    local okRun, err = pcall(row.entry.onSelect)
    if not okRun then
      log("warn", "gen4 start menu: '%s' failed: %s", tostring(row.label), tostring(err))
      pcall(self:reopen())
    end
  end

  -- More rows than the panel can hold: draw a window of them that follows the
  -- cursor. drawPanel reads self.rows / self.index, so swap in the window for
  -- the call and put the real ones back.
  Menu.drawPanel = function(self, ...)
    local total = #self.rows
    local cap = capacity(self.layout or {})
    if total <= cap then return Hook.original.drawPanel(self, ...) end
    local scroll = self.terrariumScroll or 0
    if self.index <= scroll then scroll = self.index - 1 end
    if self.index > scroll + cap then scroll = self.index - cap end
    scroll = math.max(0, math.min(scroll, total - cap))
    self.terrariumScroll = scroll
    local rows, index, window = self.rows, self.index, {}
    for i = 1, cap do window[i] = rows[scroll + i] end
    self.rows, self.index = window, index - scroll
    local ok, err = pcall(Hook.original.drawPanel, self, ...)
    self.rows, self.index = rows, index
    if not ok then error(err, 0) end
  end

  local okH, Hgss = pcall(require, "src.ui.HgssStartMenu")
  if okH and type(Hgss) == "table" and type(Hgss.new) == "function" then
    Hook.Hgss = Hgss
    Hook.original.hgssNew = wrapNew(Hgss, injectHgss)
    Hook.original.hgssDrawPanel = wrapHgssDraw(Hgss)
  end

  Hook.installed = true
  return true
end

function Hook.uninstall()
  if not Hook.installed then return end
  local M, o = Hook.Menu, Hook.original
  M.new, M.select, M.drawPanel = o.new, o.select, o.drawPanel
  if Hook.Hgss and o.hgssNew then Hook.Hgss.new = o.hgssNew end
  if Hook.Hgss and o.hgssDrawPanel then Hook.Hgss.drawPanel = o.hgssDrawPanel end
  Hook.installed = false
end

return Hook
