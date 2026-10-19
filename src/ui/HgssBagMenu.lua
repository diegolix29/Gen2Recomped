-- HEARTGOLD / SOULSILVER'S BAG (overlay 15; scratch_claude/hgss_ui_screens_map.md
-- "Bag"), over Platinum's (src/ui/Gen4BagMenu.lua) whose item logic it keeps:
-- the pockets and their contents, the action list (USE / GIVE / TRASH /
-- REGISTER / CHECK TAG ...), trashing with its count and question, the battle
-- and "pick an item" bags. The art is /a/0/1/5's (Gen4HgssBagArt).
--
-- THE TOUCH SCREEN IS WHERE YOU CHOOSE (`Bag_Init` swaps the engines):
--   * eight pocket tabs along the top (`ov15_02200B0C`: x 16 + 32 p, y 16,
--     each in its own palette row), the chosen one framed (anim 8);
--   * the pocket's items SIX AT A TIME, two columns of three: icons at
--     (22 | 152, 59 / 100 / 139), slots {y 32-73 / 74-117 / 118-153} x
--     {0-127 | 128-255} (`ov15_02200684`), the panel and buttons tinted in
--     the pocket's colour (member 41 row p);
--   * along the bottom: previous page (24, 176), next page (64, 176), the
--     page counter, back (224, 176).
-- Choosing an item puts its actions on the touch screen as a 2 x 2 of buttons
-- {y 128-159 | 160-191} x {x 0-93 | 96-191} with back as CANCEL (`02200550`,
-- screen 45).
--
-- THE TOP SCREEN SHOWS: the backdrop (blue for a boy, pink for a girl), the
-- 3D bag (model 55 / 74) playing the pocket's animation as the pocket opens,
-- the chosen item's name and its description on the grey panel.
--
-- KEYS: the pad moves over the grid, left / right past its edge turns the
-- page and then the pocket; A chooses, B goes back.
--
-- NOT YET: the texture swap per pocket (BTP0 57+p), the TM type / category
-- icons, the quantity screen's art (screens 52 / 53 -- the count is drawn as
-- text), moving items. MEASURED rather than read: where an item's name and
-- count sit in its slot, and the bag's camera.

local Gen4BagMenu = require("src.ui.Gen4BagMenu")
local Font = require("src.render.Font")
local SecondScreen = require("src.ui.SecondScreen")

local HgssBagMenu = setmetatable({}, { __index = Gen4BagMenu })
HgssBagMenu.__index = HgssBagMenu
HgssBagMenu.isOpaque = true

local W, H = 256, 192
local floor = math.floor
local PER_PAGE = 6
local ICON_AT = { { 22, 59 }, { 152, 59 }, { 22, 100 }, { 152, 100 }, { 22, 139 }, { 152, 139 } }
local SLOT_RECTS = { -- top, bottom, left, right
  { 32, 73, 0, 127 }, { 32, 73, 128, 255 }, { 74, 117, 0, 127 },
  { 74, 117, 128, 255 }, { 118, 153, 0, 127 }, { 118, 153, 128, 255 },
}
local TAB_RECT_Y, TAB_W = { 0, 31 }, 32
local PREV_RECT, NEXT_RECT, BACK_RECT = { 168, 191, 0, 39 }, { 168, 191, 40, 79 }, { 168, 191, 192, 255 }
local ACTION_RECTS = { { 128, 159, 0, 93 }, { 128, 159, 96, 191 }, { 160, 191, 0, 93 }, { 160, 191, 96, 191 } }
local PAGE_AT = { 80, 172 }
local LIST_INK = { { 0.29, 0.29, 0.33 }, { 0.75, 0.77, 0.82 } }
local TOP_INK = { { 1, 1, 1 }, { 0.35, 0.35, 0.40 } }
-- from behind, as the cartridge shows him: the bag is on his back
local BAG_CAMERA = { fov = 0.55, pitch = -0.12, yaw = math.pi, at = { 128, 70 }, zoom = 1.6 }
local POCKET_ANIM_SPEED = 0.5   -- the field's 30 Hz animation clock

function HgssBagMenu.new(game, opts)
  local self = Gen4BagMenu.new(game, opts)
  setmetatable(self, HgssBagMenu)
  self.hg = (game.data or {}).gen4_hgss_bag_art or {}
  self.slot = 1
  self.page = 0
  self.animT = 0
  return self
end

-- the pocket's items alone (the list's header and CLOSE BAG rows are
-- Platinum's)
function HgssBagMenu:items()
  local out = {}
  for _, row in ipairs(self.rows or {}) do
    if not row.header and not row.close then out[#out + 1] = row end
  end
  return out
end

function HgssBagMenu:pageCount()
  return math.max(1, math.ceil(#self:items() / PER_PAGE))
end

function HgssBagMenu:selected()
  return self:items()[self.page * PER_PAGE + self.slot]
end

function HgssBagMenu:setPocket(p)
  if self.lockPocket or p == self.pocket then return end
  self.pocket = p
  self.page, self.slot = 0, 1
  self.animT = 0
  self:rebuild()
  self:sound("SEQ_SE_DP_BAG_030")
end

-- HGSS's bag words are bank 10, numbered differently from Platinum's bank
-- 7: Platinum's entry -> HGSS's (the ones that moved; the rest keep theirs)
local HGSS_BANK = 10
local ENTRY = { [42] = 43, [45] = 46, [52] = 53, [53] = 54, [54] = 55,
                [86] = 89, [87] = 90, [88] = 91, [89] = 92 }

function HgssBagMenu:text(index, fallback, ...)
  local Gen4Text = require("src.import.Gen4Text")
  if select("#", ...) > 0 then Gen4Text.buffer(self.game, ...) end
  -- the whole renumbering (src/ui/Gen4PartyText.lua BAG_ENTRY): a Platinum
  -- line HeartGold has not got (PLANT, OPEN, Yes / No...) is the fallback,
  -- never whichever line sits at that number in bank 10
  local hg = require("src.ui.Gen4PartyText").BAG_ENTRY[index]
  if hg == nil then return fallback or "" end
  local s = Gen4Text.resolve(self.game.data, HGSS_BANK, hg, self.game)
  if type(s) ~= "string" or not s:find("%S") then return fallback or "" end
  return (s:gsub("[\v\f]", "\n"))
end

function HgssBagMenu:sound(name)
  local data = self.game and self.game.data
  local ok, Sound = pcall(require, "src.core.Sound")
  if data and ok and type(Sound) == "table" and Sound.playSe then pcall(Sound.playSe, data, name) end
end

function HgssBagMenu:clampSlot()
  local n = #self:items()
  local pages = self:pageCount()
  if self.page >= pages then self.page = pages - 1 end
  local onPage = math.max(1, math.min(PER_PAGE, n - self.page * PER_PAGE))
  if self.slot > onPage then self.slot = onPage end
end

function HgssBagMenu:turnPage(delta)
  local pages = self:pageCount()
  local to = self.page + delta
  if to < 0 or to >= pages then
    if not self.lockPocket then
      local shown = #self.pockets
      self:setPocket((self.pocket - 1 + delta) % shown + 1)
      if delta < 0 then self.page = self:pageCount() - 1 end
    end
    return
  end
  self.page = to
  self:clampSlot()
  self:sound("SEQ_SE_DP_SELECT")
end

function HgssBagMenu:chooseSlot()
  local row = self:selected()
  if not row then return end
  -- Gen4BagMenu:choose reads `self:selected()`, which is this grid's now
  return self:choose()
end

-- --------------------------------------------------------------- input --

function HgssBagMenu:update()
  self.animT = (self.animT or 0) + POCKET_ANIM_SPEED
  local input = self.game.input
  local tap = self.tapAt
  self.tapAt = nil
  if self.message then
    if tap or (input and (input:wasPressed("a") or input:wasPressed("b"))) then self.message = nil end
    return
  end
  if self.trash and self.trash.stage == "count" then
    if input then
      if input:wasPressed("a") then return self:confirmTrash() end
      if input:wasPressed("b") then self.trash = nil; return end
      self:trashCount(input)
    end
    return
  end
  if self.menu then return self:menuInput(input, tap) end
  if tap then return self:gridTap(tap) end
  if not input then return end
  local col, row = (self.slot - 1) % 2, floor((self.slot - 1) / 2)
  local n = #self:items() - self.page * PER_PAGE
  local before = self.slot
  if input:wasPressed("up") then
    if row > 0 then self.slot = self.slot - 2 end
  elseif input:wasPressed("down") then
    if row < 2 and self.slot + 2 <= n then self.slot = self.slot + 2 end
  elseif input:wasPressed("left") then
    if col == 1 then self.slot = self.slot - 1 else self:turnPage(-1) end
  elseif input:wasPressed("right") then
    if col == 0 and self.slot + 1 <= n then self.slot = self.slot + 1 else self:turnPage(1) end
  elseif input:wasPressed("a") then
    return self:chooseSlot()
  elseif input:wasPressed("b") or input:wasPressed("start") then
    self:sound("SEQ_SE_DP_SELECT")
    return self:close()
  end
  if self.slot ~= before then self:sound("SEQ_SE_DP_SELECT") end
end

local function inRect(r, p) return p.y >= r[1] and p.y <= r[2] and p.x >= r[3] and p.x <= r[4] end

function HgssBagMenu:gridTap(p)
  if p.y >= TAB_RECT_Y[1] and p.y <= TAB_RECT_Y[2] then
    local t = floor(p.x / TAB_W) + 1
    if t >= 1 and t <= #self.pockets then self:setPocket(t) end
    return
  end
  if inRect(BACK_RECT, p) then self:sound("SEQ_SE_DP_SELECT"); return self:close() end
  if inRect(PREV_RECT, p) then return self:turnPage(-1) end
  if inRect(NEXT_RECT, p) then return self:turnPage(1) end
  for i, r in ipairs(SLOT_RECTS) do
    if inRect(r, p) and self:items()[self.page * PER_PAGE + i] then
      self.slot = i
      return self:chooseSlot()
    end
  end
end

-- the action menu (and the YES / NO of trashing): the pad walks it, A runs
-- the row, B cancels; on the touch screen the 2 x 2 buttons and back
function HgssBagMenu:menuInput(input, tap)
  local m = self.menu
  local rows = m.rows
  if tap then
    if inRect(BACK_RECT, tap) then
      if m.kind == "yesno" then return self:resolveTrash(false) end
      self.menu = nil
      return
    end
    local buttons = self:menuButtons()
    for i, r in ipairs(ACTION_RECTS) do
      if buttons[i] and inRect(r, tap) then m.index = buttons[i]; return self:runMenuRow() end
    end
    return
  end
  if not input then return end
  if input:wasPressed("up") then m.index = (m.index - 2) % #rows + 1; self:sound("SEQ_SE_DP_SELECT")
  elseif input:wasPressed("down") then m.index = m.index % #rows + 1; self:sound("SEQ_SE_DP_SELECT")
  elseif input:wasPressed("a") then return self:runMenuRow()
  elseif input:wasPressed("b") then
    if m.kind == "yesno" then return self:resolveTrash(false) end
    self.menu = nil
  end
end

function HgssBagMenu:runMenuRow()
  local m = self.menu
  self:sound("SEQ_SE_DP_SELECT")
  if m.kind == "yesno" then return self:resolveTrash(m.rows[m.index] == "yes") end
  return self:runAction(m.rows[m.index])
end

-- the rows that are buttons: everything but CANCEL, which is back
function HgssBagMenu:menuButtons()
  local out = {}
  for i, r in ipairs(self.menu.rows) do
    if r ~= "cancel" and #out < 4 then out[#out + 1] = i end
  end
  return out
end

function HgssBagMenu:touchpressed(id, px, py)
  local x, y
  if self:bottomOnSecond() then
    x, y = SecondScreen.toLocal(self.game, px, py)
  else
    local rect = require("src.render.Renderer").uiPresentation
    x, y = px, py
    if rect then x, y = (px - rect.x) / rect.scaleX, (py - rect.y) / rect.scaleY end
  end
  if not x or x < 0 or y < 0 or x >= W or y >= H then return false end
  self.tapAt = { x = floor(x), y = floor(y) }
  return true
end
function HgssBagMenu:touchmoved() return false end
function HgssBagMenu:touchreleased() return false end

-- ---------------------------------------------------------------- draw --

function HgssBagMenu:hgImg(key)
  local rec = self.hg[key]
  if type(rec) ~= "table" then return nil end
  return self:imgAt(rec.path), rec
end

function HgssBagMenu:imgAt(path)
  if type(path) ~= "string" then return nil end
  if self.cache[path] == nil then
    local ok, img = pcall(require("src.render.Assets").image, path)
    self.cache[path] = ok and img or false
    if self.cache[path] then self.cache[path]:setFilter("nearest", "nearest") end
  end
  return self.cache[path] or nil
end

function HgssBagMenu:hgSprite(key, x, y)
  local img, rec = self:hgImg(key)
  if not img then return false end
  love.graphics.draw(img, x + (rec.originX or 0), y + (rec.originY or 0))
  return true
end

function HgssBagMenu:bottomOnSecond()
  return SecondScreen.mode(self.game) ~= "off" and not SecondScreen.stowed(self.game)
end

-- the 3D bag, posed at the pocket animation's current frame
function HgssBagMenu:drawBag()
  local who = self:female() and "f" or "m"
  local rec = (self.hg.models or {})[who]
  if not rec then return end
  local M = require("src.render.Gen4Model")
  self.bagModels = self.bagModels or {}
  if self.bagModels[who] == nil then
    local ok, model = pcall(M.new, rec)
    self.bagModels[who] = ok and model or false
  end
  local model = self.bagModels[who]
  if not model then return end
  if not self.bagTarget then
    self.bagTarget, self.bagDepth = M.newTarget(W, H)
    if not self.bagTarget then self.bagTarget = false end
  end
  if not self.bagTarget then return end
  local pose
  local anim = rec.pockets and rec.pockets[self.pocket]
  if anim and anim.tracks then
    local Anim = require("src.import.Gen4Anim")
    local frame = math.min(floor(self.animT or 0), (anim.frames or 1) - 1)
    local byJoint = {}
    for _, t in ipairs(anim.tracks) do
      byJoint[t.index] = Anim.unpackFrame(t.matrices, math.min(frame, (t.frames or 1) - 1))
    end
    pose = model:posed(function(node) return byJoint[node] end)
  end
  if not self.bagFrame then self.bagFrame = { model:framing(pose) } end
  local centre, distance = self.bagFrame[1], self.bagFrame[2]
  local g = love.graphics
  local previous = { g.getCanvas() }
  g.push("all")
  g.origin()
  g.setCanvas({ self.bagTarget, depthstencil = self.bagDepth })
  g.clear(0, 0, 0, 0, true, true)
  local c = BAG_CAMERA
  local flipY = { 1, 0, 0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 }
  local vp = M.multiply(flipY, M.multiply(M.perspective(c.fov, W / H, distance * 0.05, distance * 20),
                                          M.orbit(centre, distance * c.zoom, c.yaw, c.pitch)))
  local materials
  if rec.litImage and rec.litMaterial then
    materials = { [rec.litMaterial:format(self.pocket)] = { image = rec.litImage } }
  end
  pcall(model.draw, model, vp, pose, materials)
  g.pop()
  g.setCanvas(previous[1] and previous or nil)
  g.setColor(1, 1, 1, 1)
  g.draw(self.bagTarget, c.at[1] - W / 2, c.at[2] - H / 2)
end

function HgssBagMenu:drawTop()
  local g = love.graphics
  g.setColor(1, 1, 1, 1)
  local back = self:hgImg(self:female() and "top_back_f" or "top_back_m")
  if back then g.draw(back, 0, 0) else g.setColor(0.3, 0.5, 0.9, 1); g.rectangle("fill", 0, 0, W, H); g.setColor(1, 1, 1, 1) end
  self:drawBag()
  local panel = self:hgImg("top_panel")
  if panel then g.draw(panel, 0, 0) end
  Font.pushStyle({ text = TOP_INK[1], shadow = TOP_INK[2] })
  local pocket = tostring(self.pockets[self.pocket] or "")
  Font.draw(pocket, 8, 4)
  local row = self:selected()
  local body
  if self.message then
    body = self.message
  elseif self.trash and self.trash.stage == "count" then
    body = ("%s\nx%03d"):format(self:trashName(), self.trash.n)
  elseif row then
    Font.draw(tostring(row.label or ""), 8, 122)
    if row.qty then
      local q = ("x%d"):format(row.qty)
      Font.draw(q, W - 8 - Font.width(q), 122)
    end
    body = row.description
  end
  if body then
    local y = 146
    for line in (tostring(body) .. "\n"):gmatch("([^\n]*)\n") do
      Font.draw(line, 8, y)
      y = y + 16
      if y > 178 then break end
    end
  end
  Font.popStyle()
end

function HgssBagMenu:drawTouch()
  local g = love.graphics
  local p = self.pocket - 1
  g.setColor(1, 1, 1, 1)
  local panel = self:hgImg("touch_panel_" .. p)
  if panel then g.draw(panel, 0, 0) else g.setColor(0.85, 0.55, 0.7, 1); g.rectangle("fill", 0, 0, W, H); g.setColor(1, 1, 1, 1) end
  if self.menu then return self:drawActions() end
  local grid = self:hgImg("touch_grid_" .. p)
  local items = self:items()
  if grid then
    -- the buttons only where there is an item: the empty dotted slot shows
    for i = 1, PER_PAGE do
      if items[self.page * PER_PAGE + i] then
        local r = SLOT_RECTS[i]
        self.gridQuads = self.gridQuads or {}
        self.gridQuads[i] = self.gridQuads[i] or g.newQuad(r[3], r[1], r[4] - r[3] + 1, r[2] - r[1] + 1, grid:getDimensions())
        g.draw(grid, self.gridQuads[i], r[3], r[1])
      end
    end
  end
  for t = 0, #self.pockets - 1 do self:hgSprite("sprite_" .. t, 16 + 32 * t, 16) end
  self:hgSprite("sprite_8", 16 + 32 * p, 16)
  Font.pushStyle({ text = LIST_INK[1], shadow = LIST_INK[2] })
  for i = 1, PER_PAGE do
    local row = items[self.page * PER_PAGE + i]
    if row then
      local at = ICON_AT[i]
      local icon = row.iconId and self:img(("items/icon_%03d"):format(row.iconId))
      g.setColor(1, 1, 1, 1)
      if icon then g.draw(icon, at[1] - icon:getWidth() / 2, at[2] - icon:getHeight() / 2) end
      Font.draw(tostring(row.label or ""), at[1] + 20, at[2] - 14)
      if row.qty then
        local q = ("x%d"):format(row.qty)
        Font.draw(q, at[1] + 98 - Font.width(q), at[2] - 2)
      end
    end
  end
  Font.popStyle()
  -- the cursor round the chosen slot
  local r = SLOT_RECTS[self.slot]
  if r and items[self.page * PER_PAGE + self.slot] then
    g.setColor(0.95, 0.25, 0.25, 1)
    g.setLineWidth(2)
    g.rectangle("line", r[3] + 3, r[1] + 3, r[4] - r[3] - 5, r[2] - r[1] - 5, 4, 4)
    g.setColor(1, 1, 1, 1)
  end
  self:hgSprite("sprite_12", 24, 176)
  self:hgSprite("sprite_13", 64, 176)
  self:hgSprite("sprite_16", 224, 176)
  Font.pushStyle({ text = LIST_INK[1], shadow = LIST_INK[2] })
  Font.draw(("%d/%d"):format(self.page + 1, self:pageCount()), PAGE_AT[1], PAGE_AT[2])
  Font.popStyle()
end

-- screen 45: the chosen item in the grey box (x 68..188, y 56..92), its
-- actions on the 2 x 2 of dotted buttons, back as CANCEL
local ITEM_BOX = { 68, 56, 120, 36 }
function HgssBagMenu:drawActions()
  local g = love.graphics
  local m = self.menu
  local panel = self:hgImg("touch_actions_" .. (self.pocket - 1))
  g.setColor(1, 1, 1, 1)
  if panel then g.draw(panel, 0, 0) end
  local grid = self:hgImg("touch_grid_" .. (self.pocket - 1))
  Font.pushStyle({ text = LIST_INK[1], shadow = LIST_INK[2] })
  local row = self:selected()
  if row then
    local icon = row.iconId and self:img(("items/icon_%03d"):format(row.iconId))
    g.setColor(1, 1, 1, 1)
    if icon then g.draw(icon, ITEM_BOX[1] + 18 - icon:getWidth() / 2, ITEM_BOX[2] + 18 - icon:getHeight() / 2) end
    Font.draw(tostring(row.label or ""), ITEM_BOX[1] + 38, ITEM_BOX[2] + 10)
  end
  local labels = {}
  if m.kind == "yesno" then
    local Strings = require("src.core.Strings")
    labels = { { 1, Strings("YES") }, { 2, Strings("NO") } }
  else
    for _, i in ipairs(self:menuButtons()) do labels[#labels + 1] = { i, self:actionLabel(m.rows[i]) } end
  end
  for k, l in ipairs(labels) do
    local r = ACTION_RECTS[k]
    local w, h = r[4] - r[3] - 4, r[2] - r[1] - 3
    if grid then
      self.actionQuad = self.actionQuad or g.newQuad(0, 32, 128, 42, grid:getDimensions())
      g.setColor(1, 1, 1, 1)
      g.draw(grid, self.actionQuad, r[3] + 2, r[1] + 2, 0, w / 128, h / 42)
    end
    local text = tostring(l[2] or "")
    Font.draw(text, r[3] + 2 + floor((w - Font.width(text)) / 2), r[1] + 9)
    if l[1] == m.index then
      g.setColor(0.95, 0.25, 0.25, 1)
      g.setLineWidth(2)
      g.rectangle("line", r[3] + 2, r[1] + 2, w, h, 4, 4)
      g.setColor(1, 1, 1, 1)
    end
  end
  Font.popStyle()
  self:hgSprite("sprite_16", 224, 176)
end

function HgssBagMenu:draw()
  local g = love.graphics
  if self:bottomOnSecond() then
    self:drawTop()
    SecondScreen.draw(self.game, function() self:drawTouch() end)
  else
    -- one screen: the touch screen is the one you choose on
    self:drawTouch()
  end
  g.setColor(1, 1, 1, 1)
end

return HgssBagMenu
