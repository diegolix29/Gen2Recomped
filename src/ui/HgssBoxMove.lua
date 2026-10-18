-- HEARTGOLD / SOULSILVER'S "MOVE POKEMON": the party panel as a place the
-- hand goes, mixed into src/ui/HgssBoxMenu.lua (install(HG, PC) below).
--
-- On the cartridge (overlay 14) the party panel stands down the right of the
-- touch screen in every mode; the cursor walks off the box's sixth column into
-- it, and a Pokemon is moved by picking it up (A / the MOVE button, or a
-- touch) and putting it down, or by dragging it with the stylus.  Positions
-- there are 0..29 for the box and 30..35 for the party.
--
-- WHAT MAY GO WHERE is ov14_021E690C (asm/overlay_14.s:2067), the drop check
-- every drag runs (its caller at :2619 flies the Pokemon back when it says
-- no), with ov14_021E6480 (:1465) -- "another party Pokemon that is not an
-- Egg and has HP" -- as its party test:
--   * a party Pokemon put into the box: refused while it holds Mail
--     (ItemIdIsMail on MON_DATA_HELD_ITEM) or a Ball Capsule
--     (MON_DATA_BALL_CAPSULE_ID), and refused when nothing else in the party
--     could fight -- unless what it changes places with could (a box Egg
--     cannot, so swapping the last fighter for an Egg is refused too)
--   * a box Pokemon put onto a party Pokemon: the party one goes to the box,
--     so the same Mail / Capsule test on it, and an Egg may not replace the
--     last one that can fight
--   * party to party is always allowed, the last fighter included
-- The words are bank 25 (TEXT_BANK_BOX_MESSAGES on HGSS), as ov14_021EBF9C /
-- ov14_021F685C print them (:13300, :34440 jump table): 6 "That's your last
-- Pokemon!", 30 "Please remove the Mail.", 29 "Please detach the Ball
-- Capsule.", 39 "Your party is full!".  The refusal also goes in a message
-- bar on the touch screen, since a one-screen window only shows that one.

local Party = require("src.pokemon.Party")

local M = {}

local PARTY_ROW_TO_BOX = { 1, 3, 5 }   -- party rows 1..3 -> the box row beside them
local EXIT = 7                         -- the party cursor's EXIT stop
local DRAG_START = 4                   -- pixels the stylus moves before a press is a drag

local function usable(mon)
  return mon ~= nil and not (mon.egg or mon.isEgg) and (mon.hp == nil or mon.hp > 0)
end

function M.install(HG, PC)
  local Base = getmetatable(PC).__index

  function HG:itemRecord(item)
    local items = self.game.data and self.game.data.items
    if not items or item == nil or item == 0 then return nil end
    return items[item] or items[tonumber(item)] or items[tonumber(tostring(item):match("(%d+)$") or "")]
  end
  function HG:holdsMail(mon)
    local rec = mon and self:itemRecord(mon.heldItem or mon.item)
    return type(rec) == "table" and (rec.pocket == "MAIL" or rec.fieldPocket == 5) or false
  end
  function HG:holdsCapsule(mon)
    local c = mon and (mon.ballCapsule or mon.capsule)
    return c ~= nil and c ~= false and c ~= 0
  end
  -- ov14_021E6480: a party Pokemon other than `skip` that can fight
  function HG:otherFighter(skip)
    for i, mon in ipairs(self.game.save.party or {}) do
      if i ~= skip and usable(mon) then return true end
    end
    return false
  end
  function HG:refuse(n, fallback)
    self.message = self:say(n, fallback)
    self.alert = self.message
    return false
  end
  -- may `mon` leave the party for the box?  (`staying` is what takes its place)
  function HG:mayLeaveParty(mon, staying, skip)
    if self:holdsMail(mon) then return self:refuse(30, "Please remove the Mail.") end
    if self:holdsCapsule(mon) then return self:refuse(29, "Please detach the Ball Capsule.") end
    if not usable(staying) and not self:otherFighter(skip) then
      return self:refuse(6, "That’s your last Pokémon!")
    end
    return true
  end

  -- THE BOX SLOT: a party Pokemon put down there leaves the party
  function HG:carry(slot)
    local held = self.held
    if held and slot and held.fromParty and not held.from then
      local target = self:box()[slot]
      -- the hand is already out of the party, so every party Pokemon is "other"
      if not self:mayLeaveParty(held.mon, target, nil) then return end
    end
    return PC.carry(self, slot)
  end

  -- THE PARTY SLOT: pick up (the last fighter too -- it may change places in
  -- the party), or put down
  function HG:carryFromParty(index)
    local party = self.game.save.party or {}
    local held = self.held
    if not held then
      local mon = party[index]
      if not mon then return end
      self.held = { mon = mon, fromParty = index }
      table.remove(party, index)
      return
    end
    local target = party[index]
    if held.from and target then
      if not self:mayLeaveParty(target, held.mon, index) then return end
    elseif held.from and #party >= Party.MAX then
      return self:refuse(39, "Your party is full!")
    end
    return Base.carryFromParty(self, index)
  end

  -- EXIT: the box's bottom row and the party's seventh stop are its button
  function HG:choose()
    if (self.partyOpen and self.partyIndex == EXIT) or (not self.partyOpen and self.row == PC.BUTTON_ROW) then
      if self:returnHeld() then return end
      return self:close()
    end
    return PC.choose(self)
  end

  -- THE CURSOR between the box and the party panel.  Returns true when the
  -- pad press was this one's (the caller then steps the frame and stops).
  function HG:moveCursor(input)
    if self.menu or self.jump or self:busy() then return false end
    local s = self.subState
    if s and (s.task or s.dial ~= PC.DIAL_NONE) then return false end
    local function pressed(k) return input:wasPressed(k) end
    if not self.partyOpen then
      if pressed("right") and self.row >= 1 and self.row <= 5 and self.col == 6 then
        self.partyOpen, self.partyIndex = true, (self.row <= 2 and 1) or (self.row <= 4 and 3) or 5
        self.message = ""
        return true
      end
      return false
    end
    local i = self.partyIndex or 1
    local function toBox(col)
      self.partyOpen = nil
      self.row, self.col = PARTY_ROW_TO_BOX[math.floor((math.min(i, 6) - 1) / 2) + 1], col
    end
    if pressed("up") then i = (i == EXIT and 5) or (i <= 2 and EXIT) or i - 2
    elseif pressed("down") then i = (i == EXIT and 1) or (i >= 5 and EXIT) or i + 2
    elseif pressed("left") then
      if i == EXIT then i = 5 elseif i % 2 == 0 then i = i - 1 else toBox(6) end
    elseif pressed("right") then
      if i == EXIT then return true elseif i % 2 == 1 then i = i + 1 else toBox(1) end
    else
      return false
    end
    if self.partyOpen then self.partyIndex = i end
    self.message = ""
    return true
  end

  -- ------------------------------------------------------------ the stylus --
  -- A press on a Pokemon in MOVE mode is a drag once the stylus travels; a
  -- press that does not travel is the tap it always was (HG:touchpressed's).

  function HG:touchTarget(x, y)
    for i, p in ipairs(HG.PARTY_SLOTS) do
      if math.abs(x - p[1]) <= 18 and math.abs(y - p[2]) <= 15 then return "party", i end
    end
    local ix, iy, pitch = HG.ICON_X, HG.ICON_Y, HG.PITCH
    if x >= ix - 12 and x < ix - 12 + 6 * pitch and y >= iy - 12 and y < iy - 12 + 5 * pitch then
      local col = math.floor((x - (ix - 12)) / pitch) + 1
      local row = math.floor((y - (iy - 12)) / pitch) + 1
      return "box", (row - 1) * 6 + col, row, col
    end
    return nil
  end

  function HG:dragBegin(x, y)
    if self.held or (self.opts and self.opts.mode) ~= "move" then return false end
    local kind, n = self:touchTarget(x, y)
    local mon = kind == "party" and self.game.save.party[n] or kind == "box" and self:box()[n]
    if not mon then return false end
    self.drag = { x0 = x, y0 = y, x = x, y = y }
    return true
  end

  local function toLocal(px, py)
    local r = require("src.render.Renderer").uiPresentation
    if r then return (px - r.x) / r.scaleX, (py - r.y) / r.scaleY end
    return px, py
  end

  function HG:touchmoved(_, px, py)
    local d = self.drag
    if not d then return false end
    d.x, d.y = toLocal(px, py)
    if not d.active and math.abs(d.x - d.x0) + math.abs(d.y - d.y0) >= DRAG_START then
      d.active = true
      local kind, n, row, col = self:touchTarget(d.x0, d.y0)
      if kind == "party" then
        self.partyOpen, self.partyIndex = true, n
        self:carryFromParty(n)
      elseif kind == "box" then
        self.partyOpen, self.row, self.col = nil, row, col
        self:carry(n)
      end
      d.mon = self.held and self.held.mon
      if not d.mon then self.drag = nil end
    end
    return true
  end

  function HG:touchreleased(id, px, py)
    local d = self.drag
    if not d then return false end
    self.drag = nil
    local x, y = toLocal(px, py)
    if not d.active then
      -- no travel: a tap, as HG:touchpressed would have handled it
      self.dragTap = true
      local ok = self:touchpressed(id, px, py)
      self.dragTap = nil
      return ok
    end
    local kind, n, row, col = self:touchTarget(x, y)
    if kind == "party" then
      self.partyOpen, self.partyIndex = true, n
      self:carryFromParty(n)
    elseif kind == "box" then
      self.partyOpen, self.row, self.col = nil, row, col
      self:carry(n)
    end
    -- refused, or let go over nothing: it flies back where it came from
    if self.held and self.held.mon == d.mon then self:returnHeld() end
    return true
  end

  -- where the hand is drawn while a drag is on (nil: the cursor's place)
  function HG:dragPoint()
    local d = self.drag
    if d and d.active then return d.x, d.y - 12 end
  end

  -- the refusal on the touch screen: the message bar over the bottom edge
  function HG:drawAlert(put, ink)
    if not self.alert or self.alert == "" then return end
    local g = love.graphics
    local bar = self:hgImg("message")
    g.setColor(1, 1, 1, 1)
    -- the bar's frame is rows 10..42 of its 48: its bottom on the screen's
    if bar then g.draw(bar, 0, 149) else
      g.setColor(1, 0.97, 0.88, 1); g.rectangle("fill", 0, 159, 256, 33, 3, 3); g.setColor(1, 1, 1, 1)
    end
    put((tostring(self.alert):gsub("\n", " ")), 8, 168, ink)
  end
end

return M
