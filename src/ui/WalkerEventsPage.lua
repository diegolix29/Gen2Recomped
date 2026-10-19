-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE WATT SHOP'S EVENTS SHELF (the "Events" tab): the real distributions of
-- src/pokewalker/WalkerEvents.lua, for the game the purchases go to.
--
--   a row of game chips -- every imported game with a save that has events;
--   tapping another game asks which of its saves to deliver to
--   KEY EVENTS     the tickets / cards / keys, with what each one opens
--   EVENT POKEMON  the distributions, with the event they come from
--
-- Installed by src/ui/WalkerEconomyPages.lua (P._shopKit holds its helpers);
-- every purchase asks first, like the rest of the shop.

local E = require("src.pokewalker.WalkerEconomy")
local Strings = require("src.core.Strings")
local Ev = require("src.pokewalker.WalkerEvents")

local M = {}

function M.install(P)
  local C = P.COLORS
  local DIM, GOLD, ACCENT = C.DIM, C.GOLD, C.ACCENT
  local setc = P._setc
  local K = P._shopKit

  -- the games a chip is shown for: imported, with a save, with events
  function P:eventGames()
    local out = {}
    for _, v in ipairs(Ev.games()) do
      local ready = not (self.host and self.host.ready) or self.host.ready[v]
      if ready and self:hasSaves(v) then out[#out + 1] = v end
    end
    return out
  end

  -- the target save's status for every event, read once per target (and
  -- again after a purchase)
  function P:eventStatus(target)
    local key = target.version .. "/" .. target.slot
    local c = self._evStatus
    if not (c and c.key == key) then
      local ok, st = pcall(Ev.statusFor, target.version, target.slot)
      c = { key = key, st = ok and st or {} }
      self._evStatus = c
    end
    return c.st
  end

  local STATE = { claimed = "Claimed", owned = "Owned", ["no save"] = "No save",
                  ["needs the National Pokedex"] = "Needs Dex" }

  local function ticket(g, px, py, ph)
    local cx, cy, s = px + ph / 2, py + ph / 2, ph * 0.3
    setc(GOLD)
    g.rectangle("fill", cx - s * 1.2, cy - s * 0.7, s * 2.4, s * 1.4, 4, 4)
    g.setColor(0.12, 0.12, 0.17, 1)
    g.circle("fill", cx - s * 1.2, cy, s * 0.28)
    g.circle("fill", cx + s * 1.2, cy, s * 0.28)
    g.setLineWidth(2)
    g.line(cx - s * 0.55, cy - s * 0.45, cx - s * 0.55, cy + s * 0.45)
    g.setLineWidth(1)
    setc(ACCENT)
    g.circle("fill", cx + s * 0.25, cy, s * 0.32)
  end

  function P:shopEvents(x, y, w, f, target)
    if not target then return K.needTarget(self, x, y, w, f) end
    local g = love.graphics
    local st = self.st
    local y0 = y
    local bh = f.body:getHeight() + 18
    -- the game chips
    local games = self:eventGames()
    g.setFont(f.body)
    local cx, cy = x, y
    for _, v in ipairs(games) do
      local label = ("%s (%d)"):format(K.gameName(v), #Ev.forGame(v))
      local cw = math.min(w, f.body:getWidth(label) + 36)
      if cx + cw > x + w and cx > x then cx = x; cy = cy + bh + 10 end
      local vv = v
      self:button(cx, cy, cw, bh, label, function()
        if vv == target.version then return end
        -- another game: its events go to one of ITS saves
        self:chooseShopTarget()
        self.pickVersion, self.panel = vv, "pickSlot"
      end, vv == target.version and "accent" or nil, f.body)
      cx = cx + cw + 10
    end
    y = (#games > 0 and (cy + bh + 12)) or y
    local list = Ev.forGame(target.version)
    g.setFont(f.small); setc(DIM)
    local intro = #list > 0
      and ("Real event distributions for %s -- each one once per save, delivered the way the cartridge received it the next time you play."):format(K.gameName(target.version))
      or ("No event distributions for %s."):format(K.gameName(target.version))
    g.printf(intro, x + 4, y, w - 8)
    y = y + K.wrapH(f.small, intro, w - 8) + 10
    if #list == 0 then return y - y0 end
    local status = self:eventStatus(target)
    local n = K.cols(w, 320, 12)
    local cw = (w - (n - 1) * 12) / n
    local ch = 96
    for _, kind in ipairs({ { "key", "Key events" }, { "mon", "Event Pokemon" } }) do
      local k = 0
      for _, ev in ipairs(list) do
        if ev.kind == kind[1] then
          if k == 0 then y = y + K.heading(f, x, y, kind[2]) end
          local px, py = x + (k % n) * (cw + 12), y + math.floor(k / n) * (ch + 12)
          local why = status[ev.id]
          local blocked = why ~= nil
          local about = Ev.about(ev, target.version)
          local sub = about or ev.event
          local e = ev
          K.product(self, f, px, py, cw, ch, {
            name = ev.name, price = ev.price, sub = sub,
            -- claimed / owned need no price; a prerequisite still shows it
            state = blocked and ((why == "claimed" or why == "owned") and STATE[why]
              or ("%s  %d W"):format(STATE[why] or "--", ev.price)) or nil,
            disabled = blocked,
            stateColor = (why == "claimed" or why == "owned") and ACCENT or nil,
            affordable = (st.watts or 0) >= ev.price,
            draw = function(qx, qy, qh)
              if e.kind == "mon" then
                self:drawPortrait(e.mon.species, qx + 8, qy + 8, qh - 16)
              else
                ticket(g, qx, qy, qh)
              end
              return qx + qh + 4
            end,
            onTap = function()
              if blocked then
                self:say(why == "claimed" and "This save already has that event."
                  or why == "owned" and "This save already has it."
                  or ("Not yet: %s."):format(why))
                return
              end
              local how
              if e.kind == "key" then
                how = e.handler == "gen4" and "The deliveryman at any Poke Mart will hand it over."
                  or "It will be in the KEY ITEMS pocket the next time you play."
              elseif Ev.genOf(target.version) == 4 then
                how = "The deliveryman at any Poke Mart will hand it over (keep a party slot free)."
              else
                how = "It joins your party (or the PC) the next time you play."
              end
              local text = Strings("%s for %s.\n%s%s\n%s", e.name, K.gameName(target.version), e.event,
                about and Strings("\nOpens: %s", about) or "", how)
              self:confirmBuy(text, e.price, py, function()
                local ok, err = E.buyEvent(st, e, target)
                self._evStatus = nil
                return ok, err
              end)
            end })
          k = k + 1
        end
      end
      if k > 0 then y = y + math.ceil(k / n) * (ch + 12) + 6 end
    end
    return y - y0
  end
end

return M
