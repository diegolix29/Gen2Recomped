-- src/ui/HgssPokeathlonTeamPick.lua -- HEARTGOLD / SOULSILVER POKeATHLON:
-- THE TEAM PICK OVER THE PARTY AND THE PC BOXES.
--
-- On the cartridge the course's first sub-overlay (overlay 97,
-- ov97_0221E700) runs the arm9 picker sub_020932E0 / sub_02093440 on the
-- touch screen and draws src/ui/HgssPokeathlonTeamInfo.lua's panel on the
-- other one. What the picker is handed (ov97_0221E700's call):
--
--   * the PC storage and the party, the box to open first = 0x12 -- "box 18",
--     which the picker reads as THE PARTY (sub_020943EC: box 0x12 lays out
--     the party, sub_02094528; anything else the thirty box slots,
--     sub_02094400) -- then the eighteen PC boxes
--   * ov97_0221E91C, the box-slot callback: an empty slot (MON_DATA 0xAC) is
--     nothing; otherwise species (5), the Egg flag (0x4C), the form (0x70),
--     and zero Aprijuice -- a boxed Pokemon has none (the juice lives in the
--     party's extra block) -- and ov97_0221E97C, the box name
--     (PCStorage_GetBoxName)
--   * the count, 3, and ov97_0221EC14, the cursor callback that redraws the
--     panel on the other screen
--   * sub_02094400: an Egg's icon is drawn translucent (OAM mode 1) and is
--     not a pick
--   * the exit (ov97_0221E98C) copies the three picks (box, slot) into the
--     course's args; [0x28] = 1 when the player backed out (the course
--     ends unplayed)
--
-- STAND-INS, said so: the picker's own screen -- its NARC 0x51 graphics, its
-- touch rectangles, its icon positions and its Yes / No window -- is not
-- read yet; this draws the same content (the box's name between two arrows,
-- the box's thirty icons or the party's six, the three chosen, OK) on the
-- port's font and colours. The pad and the stylus both work: L / R or the
-- arrows turn the box, A picks / unpicks, B takes back the last pick (with
-- none, it asks to quit).

local Font = require("src.render.Font")
local Boxes = require("src.pokemon.Boxes")

local P = {}
P.__index = P
P.isOpaque = true

local W, H = 256, 192
local COLS, ROWS = 6, 5
local GRID_X, GRID_Y, PITCH_X, PITCH_Y = 32, 30, 32, 25
local TEAM_Y = 162
local TEAM_X = { 40, 80, 120 }
local OK_RECT = { 168, 160, 72, 26 }       -- x, y, w, h
local PARTY_PAGE = 0                       -- the cartridge's box 0x12
local ICON_PERIOD = 0.25

local function isEgg(mon) return mon and require("src.pokemon.Party").isEgg(mon) or false end

-- opts: count (3), course, supreme, onDone(mons | nil)
function P.new(game, opts)
  opts = opts or {}
  local self = setmetatable({ game = game, opts = opts, count = opts.count or 3,
                              picks = {}, page = PARTY_PAGE, row = 1, col = 1, t = 0,
                              icons = {} }, P)
  -- the harness / old callers drive the party menu's select mode: keep its
  -- face (select, enterSlot, confirmSelection)
  self.select = { count = self.count }
  self.index = 1
  self.hgssTeamInfo = true
  return self
end

function P:uiSize() return W, H end

function P:boxCount() return Boxes.count() end

-- the Pokemon in each slot of the page on show: the party (box 0x12) or one
-- PC box; holes are nil
function P:slots(page)
  page = page or self.page
  local save = self.game.save or {}
  if page == PARTY_PAGE then return save.party or {}, 6 end
  local boxes = Boxes.ensure(save)
  return boxes[page] or {}, Boxes.capacity()
end

-- TeamInfo.attach reads `party()[index]` for the panel
function P:party()
  local list = self:slots()
  local out = {}
  for i = 1, COLS * ROWS do out[i] = list[i] end
  return out
end

function P:slotAt(row, col)
  if row < 1 or row > ROWS then return nil end
  return (row - 1) * COLS + col
end

function P:monAt(row, col)
  local s = self:slotAt(row, col)
  local list, cap = self:slots()
  if not s or s > cap then return nil end
  return list[s], s
end

-- a PC box (not the party) is on show: its Pokemon carry no Aprijuice
function P:boxPage() return self.page ~= PARTY_PAGE end

function P:pageName(page)
  page = page or self.page
  local T = require("src.import.Gen4Text")
  if page == PARTY_PAGE then
    local s = T.resolve(self.game.data, 24, 60, self.game)
    return (type(s) == "string" and s ~= "") and s:gsub("\n", " ") or "PARTY"
  end
  local names = (self.game.save or {}).boxNames or {}
  local n = names[page]
  if type(n) == "string" and n ~= "" then return n end
  return "BOX " .. page
end

function P:pickedIndex(mon)
  for i, p in ipairs(self.picks) do if p.mon == mon then return i end end
  return nil
end

function P:refreshIndex()
  local s = self:slotAt(self.row, self.col)
  self.index = s or 0
end

function P:sound(which)
  pcall(function() require("src.ui.Gen4SubMenuCursor").sound(which, self.game.data) end)
end

function P:turn(delta)
  local n = self:boxCount() + 1
  self.page = (self.page + delta) % n
  self:sound("cursor")
  self:refreshIndex()
end

function P:toggle(mon, slot)
  if not mon then return end
  if isEgg(mon) then return end
  local i = self:pickedIndex(mon)
  if i then
    table.remove(self.picks, i)
  elseif #self.picks < self.count then
    self.picks[#self.picks + 1] = { mon = mon, page = self.page, slot = slot }
  else
    return
  end
  self:sound("decide")
  if #self.picks == self.count then self.asking = true; self.yes = true end
end

function P:done(mons)
  if self.closed then return end
  self.closed = true
  local stack = self.game.stack
  if stack and stack.top and stack:top() == self then stack:pop() end
  if self.opts.onDone then self.opts.onDone(mons) end
end

function P:confirm()
  local out = {}
  for i, p in ipairs(self.picks) do
    out[i] = p.mon
    -- a boxed Pokemon has no Aprijuice (ov97_0221E91C zeroes it; the
    -- cartridge cleared it when it left its party slot -- the port keeps
    -- the modifiers on the Pokemon, src/pokemon/HgssAprijuice.lua)
    if p.page ~= PARTY_PAGE then p.mon.aprijuice = nil end
  end
  self:sound("decide")
  self:done(out)
end

-- the party menu's face, for the harness beats
function P:enterSlot(k)
  local party = (self.game.save or {}).party or {}
  local mon = party[k]
  if mon and not self:pickedIndex(mon) then
    self.picks[#self.picks + 1] = { mon = mon, page = PARTY_PAGE, slot = k }
  end
end
function P:confirmSelection()
  if #self.picks >= self.count then self:confirm() end
end

function P:update(dt)
  self.t = self.t + (dt or 1 / 60)
  local input = self.game.input
  if not input then return end
  local function pressed(k) return input.wasPressed and input:wasPressed(k) end
  if self.asking then
    if pressed("left") or pressed("right") or pressed("up") or pressed("down") then
      self.yes = not self.yes
      self:sound("cursor")
    elseif pressed("a") then
      if self.yes then return self:confirm() end
      self.asking = nil
      self:sound("decide")
    elseif pressed("b") then
      self.asking = nil
      self:sound("decide")
    end
    return
  end
  if self.quitting then
    if pressed("left") or pressed("right") or pressed("up") or pressed("down") then
      self.yes = not self.yes
      self:sound("cursor")
    elseif pressed("a") then
      if self.yes then return self:done(nil) end
      self.quitting = nil
    elseif pressed("b") then
      self.quitting = nil
    end
    return
  end
  if pressed("l") then return self:turn(-1) end
  if pressed("r") then return self:turn(1) end
  if pressed("up") then
    self.row = self.row - 1
    if self.row < 0 then self.row = ROWS + 1 end
    self:sound("cursor")
  elseif pressed("down") then
    self.row = self.row + 1
    if self.row > ROWS + 1 then self.row = 0 end
    self:sound("cursor")
  elseif pressed("left") then
    if self.row == 0 then return self:turn(-1) end
    self.col = self.col > 1 and self.col - 1 or COLS
    self:sound("cursor")
  elseif pressed("right") then
    if self.row == 0 then return self:turn(1) end
    self.col = self.col < COLS and self.col + 1 or 1
    self:sound("cursor")
  elseif pressed("a") then
    if self.row >= 1 and self.row <= ROWS then
      local mon, slot = self:monAt(self.row, self.col)
      self:toggle(mon, slot)
    elseif self.row == ROWS + 1 and #self.picks == self.count then
      self.asking, self.yes = true, true
    end
  elseif pressed("b") then
    if #self.picks > 0 then
      table.remove(self.picks)
      self:sound("decide")
    else
      self.quitting, self.yes = true, false
    end
  end
  self:refreshIndex()
end

-- the picker is the TOUCH screen: the second screen when there are two,
-- the game screen otherwise (src/ui/HgssHurdleDash.lua's rule)
local function toUi(game, px, py)
  local SS = require("src.ui.SecondScreen")
  local x, y = SS.toLocal(game, px, py)
  if x then return x, y end
  if SS.separate(game) then return nil end
  local r = require("src.render.Renderer").uiPresentation
  if r then return (px - r.x) / r.scaleX, (py - r.y) / r.scaleY end
  return px, py
end

function P:touchpressed(_, px, py)
  local x, y = toUi(self.game, px, py)
  if not x then return false end
  if x < 0 or y < 0 or x >= W or y >= H then return false end
  if self.asking or self.quitting then
    -- the Yes / No pair at the bottom right
    if y >= 120 and y < 150 and x >= 168 then
      self.yes = y < 135
      if self.asking then
        if self.yes then self:confirm() else self.asking = nil end
      elseif self.yes then self:done(nil) else self.quitting = nil end
    end
    return true
  end
  if y < 24 then
    if x < 40 then self:turn(-1) elseif x >= W - 40 then self:turn(1) end
    return true
  end
  if x >= OK_RECT[1] and x < OK_RECT[1] + OK_RECT[3] and y >= OK_RECT[2] and y < OK_RECT[2] + OK_RECT[4] then
    if #self.picks == self.count then self.asking, self.yes = true, true end
    return true
  end
  local col = math.floor((x - GRID_X) / PITCH_X) + 1
  local row = math.floor((y - GRID_Y) / PITCH_Y) + 1
  if col >= 1 and col <= COLS and row >= 1 and row <= ROWS then
    self.row, self.col = row, col
    self:refreshIndex()
    local mon, slot = self:monAt(row, col)
    self:toggle(mon, slot)
  end
  return true
end

-- ----------------------------------------------------------------- draw --

function P:drawIcon(mon, x, y, alpha)
  local PM = require("src.ui.Gen4PartyMenu")
  local img, frameH = PM.iconFor(self, mon)
  local g = love.graphics
  if not img then
    g.setColor(1, 1, 1, alpha or 1)
    g.circle("fill", x + 16, y + 18, 6)
    return
  end
  local iw, ih = img:getDimensions()
  frameH = math.min(frameH or ih, ih)
  local frames = math.max(1, math.floor(ih / frameH))
  local f = (frames > 1 and not isEgg(mon)) and (math.floor(self.t / ICON_PERIOD) % frames) or 0
  local quad = g.newQuad(0, f * frameH, iw, frameH, iw, ih)
  g.setColor(1, 1, 1, alpha or 1)
  g.draw(img, quad, x, y)
end

local function box(x, y, w, h, fill, line)
  local g = love.graphics
  g.setColor(fill)
  g.rectangle("fill", x, y, w, h)
  if line then
    g.setColor(line)
    g.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1)
  end
end

local function centred(s, cx, y)
  Font.draw(s, math.floor(cx - Font.width(s) / 2), y)
end

-- two screens: overlay 97's panel on the top one (the game screen), the
-- picker on the touch screen (the second); one screen: the picker, with the
-- panel over it while SELECT or L is held (TeamInfo.attach)
function P:draw()
  local SS = require("src.ui.SecondScreen")
  if SS.separate(self.game) and not SS.stowed(self.game) then
    require("src.ui.HgssPokeathlonTeamInfo").draw(self.game, { course = self.opts.course,
      supreme = self.opts.supreme, mon = self:party()[self.index or 0], noJuice = self:boxPage() })
    SS.draw(self.game, function() self:drawPicker() end)
    return
  end
  self:drawPicker()
end

function P:drawPicker()
  local g = love.graphics
  box(0, 0, W, H, { 0.33, 0.62, 0.86, 1 })
  -- the header: the box's name between the arrows
  box(32, 3, W - 64, 18, { 0.95, 0.95, 0.90, 1 }, { 0.20, 0.36, 0.60, 1 })
  g.setColor(0.25, 0.25, 0.30, 1)
  centred(self:pageName(), W / 2, 6)
  g.setColor(1, 1, 1, 1)
  g.polygon("fill", 22, 4, 22, 20, 10, 12)
  g.polygon("fill", W - 22, 4, W - 22, 20, W - 10, 12)
  -- the slots
  box(GRID_X - 4, GRID_Y - 4, COLS * PITCH_X + 8, ROWS * PITCH_Y + 6, { 0.80, 0.90, 0.97, 1 }, { 0.20, 0.36, 0.60, 1 })
  local list, cap = self:slots()
  for s = 1, math.min(cap, COLS * ROWS) do
    local mon = list[s]
    local col, row = (s - 1) % COLS, math.floor((s - 1) / COLS)
    local x, y = GRID_X + col * PITCH_X, GRID_Y + row * PITCH_Y - 6
    if mon then
      local picked = self:pickedIndex(mon)
      if picked then
        box(x + 2, y + 6, PITCH_X - 4, PITCH_Y - 1, { 1.0, 0.85, 0.35, 1 })
      end
      self:drawIcon(mon, x, y, isEgg(mon) and 0.5 or 1)
      if picked then
        g.setColor(0.8, 0.1, 0.1, 1)
        Font.draw(tostring(picked), x + PITCH_X - 9, y + 6)
      end
    end
  end
  -- the three chosen and OK
  for i = 1, self.count do
    local x = TEAM_X[i] or (40 * i)
    box(x - 2, TEAM_Y - 2, 34, 28, { 0.95, 0.95, 0.90, 1 }, { 0.20, 0.36, 0.60, 1 })
    local p = self.picks[i]
    if p then self:drawIcon(p.mon, x, TEAM_Y - 6) end
  end
  local ready = #self.picks == self.count
  box(OK_RECT[1], OK_RECT[2], OK_RECT[3], OK_RECT[4], ready and { 0.98, 0.55, 0.20, 1 } or { 0.65, 0.65, 0.65, 1 },
      { 0.20, 0.36, 0.60, 1 })
  g.setColor(1, 1, 1, 1)
  centred("OK", OK_RECT[1] + OK_RECT[3] / 2, OK_RECT[2] + 8)
  -- the cursor
  if not (self.asking or self.quitting) then
    g.setColor(0.9, 0.15, 0.15, 1)
    g.setLineWidth(2)
    if self.row == 0 then
      g.rectangle("line", 30, 1, W - 60, 22)
    elseif self.row == ROWS + 1 then
      g.rectangle("line", OK_RECT[1] - 2, OK_RECT[2] - 2, OK_RECT[3] + 4, OK_RECT[4] + 4)
    else
      g.rectangle("line", GRID_X + (self.col - 1) * PITCH_X, GRID_Y + (self.row - 1) * PITCH_Y,
                  PITCH_X, PITCH_Y)
    end
    g.setLineWidth(1)
  end
  -- Yes / No
  if self.asking or self.quitting then
    box(8, 120, 152, 34, { 0.98, 0.98, 0.98, 1 }, { 0.2, 0.2, 0.25, 1 })
    g.setColor(0.25, 0.25, 0.30, 1)
    Font.draw(self.asking and "Is this team OK?" or "Quit the course?", 14, 130)
    for i, label in ipairs({ "YES", "NO" }) do
      local y = 120 + (i - 1) * 16
      local on = (i == 1) == (self.yes == true)
      box(168, y, 80, 15, on and { 0.98, 0.55, 0.20, 1 } or { 0.95, 0.95, 0.90, 1 }, { 0.2, 0.2, 0.25, 1 })
      g.setColor(0.25, 0.25, 0.30, 1)
      centred(label, 208, y + 3)
    end
  end
  g.setColor(1, 1, 1, 1)
end

return P
