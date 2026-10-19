-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- TOOLS -> RESTORE A SAVE (docs/save-safety.md).
--
-- Every copy of a slot the game keeps -- the current file, the staged .tmp,
-- the previous .bak, the stamped snapshots, unreadable files kept aside, the
-- Pokewalker's and the cloud sync's backups, the same slot in another storage
-- location -- listed with its date and what is in it, and a Restore button.
-- Deleted slots (moved to saves/<version>/deleted/ by the launcher's Delete)
-- come back as new slots.  Restoring snapshots the current file first, so a
-- restore can itself be undone from this same list.
--
-- Installed onto RomImporter after LauncherSidebar (RomImporter's tail): adds
-- the tool card and takes over the tool flow's slot / copy steps for it.

local SaveData = require("src.core.SaveData")
local Strings = require("src.core.Strings")

local R = {}

R.TOOL = { id = "restore", label = "Restore a Save",
           note = "Bring a save back from its backups, or undelete a slot.", needsSlot = true }

local function isRestore(self)
  local f = self.section == "tools" and self.toolFlow
  return f and type(f.tool) == "table" and f.tool.id == "restore" and f.version ~= nil and f or nil
end

local function when(t)
  if not t then return "date unknown" end
  return os.date("%Y-%m-%d %H:%M", t)
end

local function summary(row)
  if not row.ok then return Strings("does not read as a save") end
  local m = row.meta
  local who = row.name or "?"
  if m then
    return ("%s - %d badges - %s - %d caught"):format(who, m.badges or 0, m.timeText or "0:00", m.dexCount or 0)
  end
  return who
end

function R.install(RI)
  local Sidebar = require("src.import.LauncherSidebar")
  local present = false
  for _, t in ipairs(Sidebar.TOOLS or {}) do if t.id == R.TOOL.id then present = true end end
  if not present and Sidebar.TOOLS then table.insert(Sidebar.TOOLS, 6, R.TOOL) end

  -- One row per slot / copy: a title, a status line that wraps, and an action
  -- pill on the right (under the text when the column is too narrow for both).
  -- The whole row is the hit target; the pill says what a press does.
  local function draw(self, f, x, y, w)
    local s, g = self._s or 1, love.graphics
    local P = RI.palette and RI.palette() or {}
    -- the launcher palette is 0-255
    local function col(c, a)
      if type(c) == "table" then g.setColor(c[1] / 255, c[2] / 255, c[3] / 255, a or 1)
      else g.setColor(1, 1, 1, a or 1) end
    end
    local RED = P.chooseTop or { 255, 83, 97 }
    local touch = self.android and true or false
    local top = y
    self._sb.restoreRows = {}
    local font = self.hintFont or g.getFont()
    local big = self.slotNameFont or self.detailFont or font
    local pad = 16 * s
    local pillH = math.max(touch and 44 * s or 0, font:getHeight() + 12 * s)
    local minH = touch and 64 * s or 56 * s
    local function ellipsize(fnt, text, maxW)
      text = tostring(text)
      if maxW <= 0 or fnt:getWidth(text) <= maxW then return text end
      local cut = text
      while #cut > 0 and fnt:getWidth(cut .. "...") > maxW do cut = cut:sub(1, -2) end
      return cut .. "..."
    end
    local function para(text, color)
      g.setFont(font); col(color)
      local _, lines = font:getWrap(text, w)
      g.printf(text, x, y, w, "left")
      y = y + #lines * font:getHeight() + 12 * s
    end
    -- row = { title, sub, subColor, pill, pillKind, dim, alert, rect }
    local function drawRow(row)
      local pillW = row.pill and (font:getWidth(row.pill) + 28 * s) or 0
      local textW = w - 2 * pad - (row.pill and (pillW + pad) or 0)
      local stacked = row.pill and textW < 200 * s
      if stacked then textW = w - 2 * pad end
      local _, lines = font:getWrap(row.sub or "", textW)
      local textH = big:getHeight() + 4 * s + math.max(1, #lines) * font:getHeight()
      local h = math.max(minH, textH + 2 * 12 * s)
      if stacked then h = textH + 2 * 12 * s + pillH + 10 * s end
      local rect = row.rect
      rect.x, rect.y, rect.width, rect.height = x, y, w, h
      local hot = row.clickable and self._hover and self:_hover(rect)
      col(P.slotBg or { 9, 14, 34 }, row.dim and 0.45 or 0.75)
      g.rectangle("fill", x, y, w, h, 12 * s, 12 * s)
      g.setLineWidth(math.max(1, 1.2 * s))
      if row.armed then col(P.gold or { 255, 203, 5 }, 0.9)
      elseif row.alert then col(RED, 0.75)
      else col(P.cardBorder or { 120, 150, 220 }, hot and 0.5 or 0.22) end
      g.rectangle("line", x, y, w, h, 12 * s, 12 * s)
      if hot then col(P.white, 0.06); g.rectangle("fill", x, y, w, h, 12 * s, 12 * s) end
      if row.alert then
        -- a red edge on the left: this one needs attention
        col(RED, 0.95)
        g.rectangle("fill", x + 1, y + 10 * s, 4 * s, h - 20 * s, 2 * s, 2 * s)
      end
      local ty = y + 12 * s
      if not stacked then ty = y + (h - textH) / 2 end
      g.setFont(big); col(row.titleColor or P.ink, row.dim and 0.6 or 1)
      g.print(ellipsize(big, row.title, textW), x + pad, ty)
      g.setFont(font); col(row.subColor or P.detail, row.dim and 0.8 or 1)
      g.printf(row.sub or "", x + pad, ty + big:getHeight() + 4 * s, textW, "left")
      if row.pill then
        local px = x + w - pad - pillW
        local py = stacked and (y + h - 12 * s - pillH) or (y + (h - pillH) / 2)
        if self._chipButton then
          self:_chipButton(px, py, row.pill, { w = pillW, h = pillH, kind = row.pillKind or "neutral" })
        end
      end
      if row.clickable then self._sb.restoreRows[#self._sb.restoreRows + 1] = rect end
      y = y + h + 10 * s
    end
    local again = touch and Strings("Tap again to confirm") or Strings("Click again to confirm")
    if f.notice then
      para(f.notice, f.noticeOk and (P.green or { 62, 224, 138 }) or RED)
    end
    if not f.slot then
      para(Strings("Choose the save slot to restore"), P.detail)
      local okL, slots = pcall(SaveData.listSlots, f.version)
      local okD, deleted = pcall(SaveData.deletedSlots, f.version)
      local rows = {}
      for _, r in ipairs(okL and slots or {}) do rows[#rows + 1] = { kind = "slot", slot = r } end
      for _, r in ipairs(okD and deleted or {}) do rows[#rows + 1] = { kind = "deleted", row = r } end
      if #rows == 0 then
        para(Strings("No saves or backups for this game."), P.warning)
        return y - top
      end
      for i, e in ipairs(rows) do
        local armed = f.armed == ("deleted:" .. i)
        local row = { rect = { entry = e, index = i }, clickable = true, armed = armed }
        if e.kind == "slot" then
          local r = e.slot
          if r.unreadable then
            row.title = tostring(r.label or r.name or r.id) .. "  -  " .. Strings("SAVE NEEDS RESTORE")
            row.sub = Strings("No copy of this slot reads as a save. Open it to pick a backup.")
            row.subColor, row.alert = RED, true
            row.pill, row.pillKind = Strings("Restore"), "danger"
          elseif r.recoveredFrom then
            row.title = tostring(r.label or r.name or r.id)
            row.sub = Strings("Main file lost - a backup is in use. Open it to put a copy back.")
            row.subColor = P.gold
            row.pill = Strings("Copies")
          else
            row.title = tostring(r.label or r.name or r.id)
            row.sub = (r.exists and r.meta)
              and ("%d badges - %s - %d caught"):format(r.meta.badges or 0, r.meta.timeText or "0:00", r.meta.dexCount or 0)
              or Strings("empty slot")
            row.pill = Strings("Copies")
          end
        else
          local r = e.row
          row.title = Strings("Deleted: ") .. tostring(r.name or r.slot)
          row.sub = armed and again
            or (when(r.when) .. "  -  " .. summary(r))
          row.subColor = armed and P.gold or nil
          row.pill, row.pillKind = armed and Strings("Bring back") or Strings("Undelete"), armed and "dangerArmed" or "accent"
        end
        drawRow(row)
      end
      return y - top
    end
    para(Strings("Copies of %s, newest first. Restoring keeps the current file as a snapshot, so it can be undone here.", f.slot),
      P.detail)
    f.rows = f.rows or SaveData.slotBackups(f.version, f.slot)
    if #f.rows == 0 then
      para(Strings("No copies of this slot were found."), P.warning)
      return y - top
    end
    for i, r in ipairs(f.rows) do
      local armed = f.armed == ("copy:" .. i)
      local row = { rect = { copy = r, index = i }, armed = armed,
                    clickable = r.ok and not r.current, dim = not r.ok }
      -- the date leads the status line: a narrow phone ellipsizes the title,
      -- and the date is what tells two snapshots apart
      row.title = Strings(r.label)
      local stamp = when(r.when) .. "  -  "
      if r.current then
        row.sub = stamp .. (r.ok and Strings("in use now: ") or Strings("in use now, but ")) .. summary(r)
        row.subColor = not r.ok and RED or nil
        row.alert = not r.ok
        row.dim = false
      elseif not r.ok then
        row.sub = stamp .. summary(r)
        row.subColor = RED
      else
        row.sub = stamp .. (armed and again or summary(r))
        row.subColor = armed and P.gold or nil
        row.pill = armed and Strings("Restore it") or Strings("Restore")
        row.pillKind = armed and "dangerArmed" or "accent"
      end
      drawRow(row)
    end
    if #self._sb.restoreRows == 0 then
      y = y + 6 * s
      para(Strings("No copy of this slot reads as a save, so there is nothing to put back. The files are kept as they are."),
        P.warning)
    end
    return y - top
  end

  local origTools = RI._sbTools
  RI._sbTools = function(self, x, y, w, h, ...)
    local f = isRestore(self)
    if f then return draw(self, f, x, y, w) end
    return origTools(self, x, y, w, h, ...)
  end

  local origPress = RI._sbMousepressed
  RI._sbMousepressed = function(self, x, y, ...)
    local f = isRestore(self)
    local sb = self._sb
    if f and sb and not (sb.back and x >= sb.back.x and x <= sb.back.x + sb.back.width
                          and y >= sb.back.y and y <= sb.back.y + sb.back.height) then
      for _, r in ipairs(sb.restoreRows or {}) do
        if x >= r.x and x <= r.x + r.width and y >= r.y and y <= r.y + r.height then
          R.press(self, f, r)
          return true
        end
      end
    end
    return origPress(self, x, y, ...)
  end

  -- the game page's save list: an unreadable slot's Restore chip
  -- (RomImporter's slot rows fill slotRestoreRects) opens its copies here
  local origDown = RI.mousepressed
  RI.mousepressed = function(self, x, y, button, ...)
    for _, r in ipairs(self.slotRestoreRects or {}) do
      if x >= r.x and x <= r.x + r.width and y >= r.y and y <= r.y + r.height then
        if self._sbGo then self:_sbGo("tools") end
        self.toolFlow = { tool = R.TOOL, label = R.TOOL.label, version = r.version, slot = r.id }
        self.pageScroll = 0
        self.slotRestoreRects = nil
        return true
      end
    end
    return origDown(self, x, y, button, ...)
  end

  local origBack = RI._sbBack
  RI._sbBack = function(self, ...)
    local f = isRestore(self)
    if f then
      if f.slot then f.slot, f.rows, f.armed = nil, nil, nil
      else f.version, f.armed = nil, nil end
      f.notice = nil
      self.pageScroll = 0
      return true
    end
    return origBack(self, ...)
  end
end

-- a click on a row: open a slot, or arm / confirm a restore
function R.press(self, f, r)
  if not f.slot then
    local e = r.entry
    if e.kind == "slot" then
      f.slot, f.rows, f.armed, f.notice = e.slot.id, nil, nil, nil
      self.pageScroll = 0
      return
    end
    local key = "deleted:" .. r.index
    if f.armed ~= key then f.armed = key; return end
    f.armed = nil
    local id, why = SaveData.restoreAsNewSlot(f.version, e.row,
      (e.row.name or e.row.slot) .. " (restored)")
    f.notice = id and Strings("Brought back as %s.", id) or (Strings("Could not restore: ") .. tostring(why))
    f.noticeOk = id ~= nil
  else
    local key = "copy:" .. r.index
    if f.armed ~= key then f.armed = key; return end
    f.armed = nil
    local ok, why = SaveData.restoreBackup(f.version, f.slot, r.copy)
    f.notice = ok and Strings("Restored %s from the %s copy.", f.slot, r.copy.label)
      or (Strings("Could not restore: ") .. tostring(why))
    f.noticeOk = ok and true or false
    f.rows = nil
  end
  if self._refreshSlots then pcall(self._refreshSlots, self, f.version) end
end

return R
