-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE MONSTER WALKER'S ECONOMY PAGES, added to src/ui/PokewalkerScreen.lua
-- (install(P) at its end):
--
--   WATT SHOP     Items / Pokemon / Mystery Gifts (into a chosen game's save)
--                 and Cosmetics (the walker's own look, sound, event courses);
--                 every purchase asks first
--   AWARDS        the login streak, today's open-app watts, the achievements
--   LEADERBOARD   each minigame's top 10 -- P:openPage("leaderboard", gameId)
--
-- and the hooks the screen calls: P:openPage, P:openMinigames, P:sceneName,
-- P:shellColor, P:chirp, P:econTick. Every page returns the height it drew
-- (the launcher pages its column and places its footer on that number).

local W = require("src.pokewalker.Walker")
local Strings = require("src.core.Strings")
local E = require("src.pokewalker.WalkerEconomy")
local Shop = require("src.pokewalker.WalkerShop")

local M = {}

function M.install(P)
  local C = P.COLORS
  local INK, DIM, GOLD, CARD, ACCENT, RED = C.INK, C.DIM, C.GOLD, C.CARD, C.ACCENT, C.RED
  local card, setc, hovered = P._card, P._setc, P._hovered

  -- ------------------------------------------------------------ hooks

  -- open a page of the walker from anywhere (the minigames' "Leaderboard"
  -- button: screen:openPage("leaderboard", gameId))
  function P:openPage(name, arg)
    self.panel = nil
    self.shopConfirm = nil
    self.pickFor = nil
    if name == "leaderboard" then self.boardGame = arg or self.boardGame end
    if name == "shop" and arg then self.shopTab = arg end
    self.tab = name
  end

  -- the minigames (another module: src/ui/WalkerMinigames.lua, open(screen, st))
  function P:minigames()
    if self._mg == nil then
      local ok, mod = pcall(require, "src.ui.WalkerMinigames")
      self._mg = (ok and type(mod) == "table") and mod or false
    end
    return self._mg or nil
  end

  function P:openMinigames()
    local mg = self:minigames()
    if not (mg and mg.open) then self:say("Minigames are coming soon!") return end
    local ok, err = pcall(mg.open, self, self.st)
    if not ok then self:say("Minigames: " .. tostring(err)) end
  end

  -- the hero's scene: the bought background, else the course's own
  function P:sceneName(courseName)
    local id = E.using(self.st, "theme")
    local c = id and id ~= "auto" and Shop.cosmetic("theme", id)
    return c and c.scene or courseName
  end

  -- the shell colour, and whether it is the default one
  function P:shellColor()
    local id = E.using(self.st, "shell")
    local c = Shop.cosmetic("shell", id) or Shop.COSMETICS.shell[1]
    return c.color, id == Shop.COSMETICS.shell[1].id
  end

  -- a button's beep, in the sound set in use (or `preview`), at the walker's
  -- Sound setting (Mute / Medium / Loud)
  local chirps = {}
  function P:chirp(preview)
    local vol = ({ [0] = 0, 0.25, 0.6 })[tonumber(self.st.settings and self.st.settings.sound) or 1]
    if preview and (not vol or vol <= 0) then vol = 0.4 end
    if not vol or vol <= 0 or not (love.audio and love.sound) then return end
    local id = preview or E.using(self.st, "sound")
    local src = chirps[id]
    if src == nil then
      src = false
      local c = Shop.cosmetic("sound", id) or Shop.COSMETICS.sound[1]
      pcall(function()
        local rate, per = 22050, 0.05
        local n = math.floor(rate * per)
        local sd = love.sound.newSoundData(n * #c.notes, rate, 16, 1)
        for k, hz in ipairs(c.notes) do
          for i = 0, n - 1 do
            local t = i / rate
            local env = 1 - i / n
            local v = c.wave == "sine" and math.sin(2 * math.pi * hz * t)
              or ((math.floor(2 * hz * t) % 2 == 0) and 0.6 or -0.6)
            sd:setSample((k - 1) * n + i, v * env * 0.5)
          end
        end
        src = love.audio.newSource(sd, "static")
      end)
      chirps[id] = src
    end
    if src then pcall(function() src:stop(); src:setVolume(vol); src:play() end) end
  end

  -- once a frame from P:update: the day's login bonus on the first open of a
  -- day, and the achievements the steps reached (Walker.addSteps knows
  -- nothing of them)
  function P:econTick(dt)
    local st = self.st
    local d = E.day()
    if self._loginDay ~= d then
      self._loginDay = d
      if E.dailyLogin(st) then W.save(st) end
    end
    self._checkT = (self._checkT or 0) + dt
    if self._checkT > 2 then
      self._checkT = 0
      if #E.check(st) > 0 then W.save(st) end
    end
  end

  -- the economy's tile icons (tileIcon falls through to this)
  function P.econIcon(id, cx, cy, r, t)
    local g = love.graphics
    if id == "shop" then
      -- a price tag with a W
      g.polygon("line", cx - r * 0.7, cy - r * 0.35, cx + r * 0.25, cy - r * 0.35, cx + r * 0.7, cy,
                cx + r * 0.25, cy + r * 0.35, cx - r * 0.7, cy + r * 0.35)
      g.circle("fill", cx + r * 0.32, cy, r * 0.09)
      setc(GOLD)
      g.line(cx - r * 0.55, cy - r * 0.15, cx - r * 0.45, cy + r * 0.18, cx - r * 0.35, cy - r * 0.02,
             cx - r * 0.25, cy + r * 0.18, cx - r * 0.15, cy - r * 0.15)
      return true
    elseif id == "awards" then
      -- a trophy
      g.arc("fill", "pie", cx, cy - r * 0.35, r * 0.45, 0, math.pi)
      g.rectangle("fill", cx - r * 0.45, cy - r * 0.5, r * 0.9, r * 0.16)
      g.arc("line", "open", cx - r * 0.45, cy - r * 0.25, r * 0.2, math.pi * 0.5, math.pi * 1.5)
      g.arc("line", "open", cx + r * 0.45, cy - r * 0.25, r * 0.2, -math.pi * 0.5, math.pi * 0.5)
      g.rectangle("fill", cx - r * 0.08, cy + r * 0.05, r * 0.16, r * 0.3)
      g.rectangle("fill", cx - r * 0.35, cy + r * 0.35, r * 0.7, r * 0.15)
      setc(GOLD, 0.5 + 0.5 * math.abs(math.sin(t * 2)))
      g.circle("fill", cx + r * 0.6, cy - r * 0.7, r * 0.1)
      return true
    end
    return false
  end

  -- -------------------------------------------------------- shared bits

  local function gameName(v)
    local ok, GV = pcall(require, "src.core.GameVersion")
    local info = ok and GV.info(v)
    return info and (info.launcherName or info.displayName) or tostring(v)
  end

  local function slotName(v, id)
    local SaveData = require("src.core.SaveData")
    for _, s in ipairs(SaveData.listSlots(v) or {}) do
      if s.id == id then return s.label or s.name or id end
    end
    return id
  end

  -- does a game have a save to deliver to (cached for one pick)
  function P:hasSaves(v)
    self._hasSaves = self._hasSaves or {}
    if self._hasSaves[v] == nil then
      local ok = false
      pcall(function()
        for _, s in ipairs(require("src.core.SaveData").listSlots(v) or {}) do if s.exists then ok = true end end
      end)
      self._hasSaves[v] = ok
    end
    return self._hasSaves[v]
  end

  -- where purchases go: the last chosen, else the walking Pokemon's game
  function P:shopTarget()
    local src=self.st.walking and self.st.walking.source
    if src and src.version and src.slot then return {version=src.version,slot=src.slot} end
    local e = E.econ(self.st)
    local t = e.shopTarget
    if not (t and t.version and t.slot) then
      local src = self.st.walking and self.st.walking.source
      t = src and src.version and src.slot and { version = src.version, slot = src.slot } or nil
    end
    return t
  end

  function P:chooseShopTarget()
    if self.st.walking and self.st.walking.source then
      self:say("Purchases go to the walking Pokemon's game and save. Bring it home before choosing another save.")
      return
    end
    self._hasSaves = {}
    self.pickFor = function(version, slot)
      E.econ(self.st).shopTarget = { version = version, slot = slot }
      self._targetLabel = nil
      W.save(self.st)
      self.tab = "shop"
      self:say(("Purchases go to %s."):format(gameName(version)))
    end
    self.panel = "pickGame"
  end

  local function wrapH(font, text, w)
    local _, lines = font:getWrap(text, w)
    return math.max(1, #lines) * font:getHeight()
  end

  local function cols(w, min, gap) return math.max(1, math.floor((w + gap) / (min + gap))) end

  -- a product card: name, sub line, price; `state` nil (buyable), or a short
  -- word in place of the price ("Sold out", "Owned", "In use")
  local function product(self, f, x, y, w, h, o)
    local g = love.graphics
    local hot = hovered(x, y, w, h)
    card(x, y, w, h, 14, (o.selected and { 0.18, 0.34, 0.28 }) or (hot and not o.disabled and { 0.18, 0.18, 0.24 }) or CARD, 0.9)
    local tx = x + 14
    if o.draw then tx = o.draw(x, y, h) or tx end
    local right = o.state or ((o.price or 0) .. " W")
    g.setFont(f.body)
    local pw = f.body:getWidth(right) + 20
    local nameW = x + w - tx - pw - 12
    -- a name too long beside the price takes the whole line; the price
    -- drops to the bottom row instead
    local low = f.body:getWidth(o.name) > nameW
    g.setFont(f.body); setc(o.disabled and DIM or INK)
    g.printf(o.name, tx, y + 10, math.max(40, low and (x + w - tx - 12) or nameW))
    if o.sub then
      g.setFont(f.small); setc(DIM)
      g.printf(o.sub, tx, y + h - f.small:getHeight() - 10, x + w - tx - 12 - (low and pw or 0))
    end
    -- the price pill
    local py = low and (y + h - f.body:getHeight() - 10) or (y + 10)
    g.setColor(0, 0, 0, 0.35)
    g.rectangle("fill", x + w - pw - 10, py - 2, pw, f.body:getHeight() + 6, 10, 10)
    g.setFont(f.body)
    setc(o.state and (o.stateColor or DIM) or ((o.affordable == false) and RED or GOLD))
    g.printf(right, x + w - pw - 10, py + 1, pw, "center")
    self:rect(x, y, w, h, o.onTap)
  end

  -- ask before spending
  function P:confirmBuy(text, price, y, fn)
    if (self.st.watts or 0) < price then
      self:say(("You need %d W -- you have %d W."):format(price, self.st.watts or 0))
      return
    end
    self.shopConfirm = { text = text, price = price, y = y, fn = fn }
  end

  local function drawConfirm(self, f, x, y0, w, used)
    local c = self.shopConfirm
    if not c then return end
    local g = love.graphics
    g.setColor(0, 0, 0, 0.55)
    g.rectangle("fill", x, y0, w, used, 18, 18)
    -- swallow taps around the box
    self:rect(x, y0, w, used, function() end)
    local mw = math.min(w - 20, 520)
    local bh = f.body:getHeight() + 24
    local body = Strings("%s\n\nYou have %d W; after this, %d W.", c.text, self.st.watts or 0, (self.st.watts or 0) - c.price)
    local th = wrapH(f.body, body, mw - 40)
    local mh = 20 + f.head:getHeight() + 10 + th + 20 + bh + 20
    local mx = x + (w - mw) / 2
    local my = math.max(y0 + 10, math.min((c.y or y0) - 20, y0 + used - mh - 10))
    card(mx, my, mw, mh, 18, { 0.12, 0.12, 0.17 }, 0.98)
    g.setFont(f.head); setc(GOLD)
    g.printf(("Spend %d W?"):format(c.price), mx + 20, my + 20, mw - 40)
    g.setFont(f.body); setc(INK)
    g.printf(body, mx + 20, my + 30 + f.head:getHeight(), mw - 40)
    local bw = (mw - 60) / 2
    local by = my + mh - bh - 20
    self:button(mx + 20, by, bw, bh, "Cancel", function() self.shopConfirm = nil end, nil, f.body)
    self:button(mx + 40 + bw, by, bw, bh, "Buy", function()
      self.shopConfirm = nil
      local ok, why = c.fn()
      if ok then self:say(why or ("Done! " .. (c.done or ""))) else self:say("Could not: " .. tostring(why)) end
    end, "accent", f.body)
  end

  -- ----------------------------------------------------------- the shop

  P.SHOP_TABS = { { id = "items", label = "Items" }, { id = "pokemon", label = "Pokemon" },
                  { id = "gifts", label = "Mystery Gifts" }, { id = "events", label = "Events" },
                  { id = "cosmetics", label = "Cosmetics" } }

  function P:pageShop(x, y, w, h, f)
    local g = love.graphics
    local st = self.st
    local y0 = y
    local narrow = w < 640
    local bh = f.body:getHeight() + 22
    -- the header: watts and where purchases go
    local target = self:shopTarget()
    if target and (not self._targetLabel or self._targetLabel.key ~= target.version .. "/" .. target.slot) then
      self._targetLabel = { key = target.version .. "/" .. target.slot,
                            text = gameName(target.version) .. " -- " .. tostring(slotName(target.version, target.slot)) }
    end
    local headH = narrow and (16 + f.head:getHeight() + 10 + f.small:getHeight() + 4 + f.body:getHeight() + 12 + bh + 16)
      or (16 + math.max(f.head:getHeight() + f.small:getHeight() + 4, bh) + 16)
    card(x, y, w, headH, 18)
    g.setFont(f.head); setc(GOLD)
    g.print(("%d W"):format(st.watts or 0), x + 20, y + 16)
    g.setFont(f.small); setc(DIM)
    g.print("to spend", x + 20, y + 18 + f.head:getHeight())
    local deliverText = target and self._targetLabel.text or "No game chosen yet"
    local cbw = math.max(130, f.body:getWidth("Change game") + 30)
    if narrow then
      local ty = y + 16 + f.head:getHeight() + 10 + f.small:getHeight() + 4
      g.setFont(f.small); setc(DIM); g.print("Deliver to", x + 20, ty - f.small:getHeight() - 2)
      g.setFont(f.body); setc(INK); g.printf(deliverText, x + 20, ty, w - 40)
      self:button(x + 20, ty + f.body:getHeight() + 12, w - 40, bh, target and "Change game" or "Choose a game",
        function() self:chooseShopTarget() end, nil, f.body)
    else
      local lx = x + 40 + math.max(f.head:getWidth(("%d W"):format(st.watts or 0)), f.small:getWidth("to spend")) + 30
      g.setFont(f.small); setc(DIM); g.print("Deliver to", lx, y + 16)
      g.setFont(f.body); setc(INK)
      g.printf(deliverText, lx, y + 18 + f.small:getHeight(), x + w - cbw - 40 - lx)
      self:button(x + w - cbw - 20, y + (headH - bh) / 2, cbw, bh, target and "Change game" or "Choose a game",
        function() self:chooseShopTarget() end, nil, f.body)
    end
    y = y + headH + 14
    -- the shelves
    local tab = self.shopTab or "items"
    local per = narrow and 2 or (w < 860 and 3 or #P.SHOP_TABS)
    local tbw = (w - (per - 1) * 10) / per
    for i, t in ipairs(P.SHOP_TABS) do
      local tx = x + ((i - 1) % per) * (tbw + 10)
      local ty = y + math.floor((i - 1) / per) * (bh + 10)
      local id = t.id
      self:button(tx, ty, tbw, bh, t.label, function() self.shopTab = id; self.shopConfirm = nil end,
        tab == id and "accent" or nil, f.body)
    end
    y = y + math.ceil(#P.SHOP_TABS / per) * (bh + 10) + 6
    local fn = ({ items = P.shopItems, pokemon = P.shopPokemon, gifts = P.shopGifts, cosmetics = P.shopCosmetics,
                  events = P.shopEvents })[tab] or P.shopItems
    local used = fn(self, x, y, w, f, target)
    local total = math.max(h, (y + used) - y0)
    drawConfirm(self, f, x, y0, w, total)
    return total
  end

  local function needTarget(self, x, y, w, f)
    local g = love.graphics
    card(x, y, w, 120, 18)
    g.setFont(f.body); setc(DIM)
    g.printf("Choose the game and save that should receive what you buy.", x + 20, y + 20, w - 40, "center")
    local bw = math.min(320, w - 40)
    self:button(x + (w - bw) / 2, y + 120 - f.body:getHeight() - 42, bw, f.body:getHeight() + 22, "Choose a game",
      function() self:chooseShopTarget() end, "accent", f.body)
    return 120
  end

  local function heading(f, x, y, text)
    love.graphics.setFont(f.head); setc(GOLD)
    love.graphics.print(text, x + 4, y)
    return f.head:getHeight() + 8
  end

  function P:shopItems(x, y, w, f, target)
    if not target then return needTarget(self, x, y, w, f) end
    local st = self.st
    local gen = Shop.genOf(target.version)
    local list = Shop.items(gen)
    local y0 = y
    local n = cols(w, 250, 12)
    local cw = (w - (n - 1) * 12) / n
    local ch = 20 + f.body:getHeight() + f.small:getHeight() + 8
    for _, cat in ipairs(Shop.CATEGORIES) do
      local k = 0
      for _, it in ipairs(list) do
        if it.cat == cat then
          if k == 0 then y = y + heading(f, x, y, cat) end
          local cx, cy = x + (k % n) * (cw + 12), y + math.floor(k / n) * (ch + 12)
          local entry = it
          local label = it.count > 1 and ("%s x%d"):format(it.name, it.count) or it.name
          product(self, f, cx, cy, cw, ch, {
            name = label, price = it.price, sub = cat, affordable = (st.watts or 0) >= it.price,
            onTap = function()
              self:confirmBuy(("%s for %s. It goes into that save's bag."):format(label, gameName(target.version)),
                entry.price, cy, function() return E.buyItem(st, entry, target) end)
            end })
          k = k + 1
        end
      end
      if k > 0 then y = y + math.ceil(k / n) * (ch + 12) + 6 end
    end
    return y - y0
  end

  function P:shopPokemon(x, y, w, f, target)
    if not target then return needTarget(self, x, y, w, f) end
    local g = love.graphics
    local st = self.st
    local y0 = y
    local stock = Shop.stock(target.version, E.day())
    g.setFont(f.small); setc(DIM)
    g.printf(("Today's Pokemon for %s -- new ones every day at midnight. Each goes straight into that save's PC."):format(gameName(target.version)), x + 4, y, w - 8)
    y = y + wrapH(f.small, "x", w) * 2 + 10
    if #stock == 0 then
      g.setFont(f.body); setc(DIM)
      g.print("No Pokemon data yet -- import a game first.", x + 4, y)
      return y - y0 + f.body:getHeight() + 10
    end
    local n = cols(w, 300, 12)
    local cw = (w - (n - 1) * 12) / n
    local ch = 96
    for i, o in ipairs(stock) do
      local cx, cy = x + ((i - 1) % n) * (cw + 12), y + math.floor((i - 1) / n) * (ch + 12)
      local sold = E.taken(st, E.stockKey(target.version, o.dex))
      local offer = o
      product(self, f, cx, cy, cw, ch, {
        name = o.name, price = o.price, sub = ("Lv %d  %s"):format(o.level, table.concat(o.types or {}, "/")),
        state = sold and "Sold out" or nil, disabled = sold, affordable = (st.watts or 0) >= o.price,
        draw = function(px, py, ph)
          self:drawPortrait(offer.dex, px + 8, py + 8, ph - 16)
          return px + ph + 4
        end,
        onTap = function()
          if sold then self:say("Sold out until tomorrow.") return end
          self:confirmBuy(("%s (Lv %d) for %s's PC."):format(offer.name, offer.level, gameName(target.version)),
            offer.price, cy, function() return E.buyPokemon(st, offer, target) end)
        end })
    end
    return (y + math.ceil(#stock / n) * (ch + 12)) - y0
  end

  function P:shopGifts(x, y, w, f, target)
    if not target then return needTarget(self, x, y, w, f) end
    local g = love.graphics
    local st = self.st
    local y0 = y
    local gen = Shop.genOf(target.version)
    local week = E.week()
    local nextDay = (week + 1) * 7 - 3
    local daysLeft = math.max(1, nextDay - E.day())
    g.setFont(f.small); setc(DIM)
    g.printf(("This week's Mystery Gifts -- each can be claimed once. New gifts in %d day%s."):format(daysLeft, daysLeft == 1 and "" or "s"), x + 4, y, w - 8)
    y = y + wrapH(f.small, "x", w) + 12
    local list = Shop.gifts(week)
    local n = cols(w, 300, 12)
    local cw = (w - (n - 1) * 12) / n
    local ch = 96
    local species = require("src.pokewalker.WalkerCourses").species()
    for i, gift in ipairs(list) do
      local cx, cy = x + ((i - 1) % n) * (cw + 12), y + math.floor((i - 1) / n) * (ch + 12)
      local claimed = E.taken(st, E.giftKey(gift.id, week))
      local can = gen >= (gift.gen or 1)
      local name, sub
      if gift.kind == "mon" then
        local sp = species[gift.dex]
        name = ("%s  Lv%d"):format(sp and sp.name or ("#" .. gift.dex), gift.level)
        sub = "Special Pokemon -- to the PC"
      else
        name = gift.count > 1 and ("%s x%d"):format(gift.name, gift.count) or gift.name
        sub = "Rare item -- to the bag"
      end
      local gg = gift
      product(self, f, cx, cy, cw, ch, {
        name = name, price = gift.price, sub = can and sub or ("Not in " .. gameName(target.version)),
        state = claimed and "Claimed" or (not can and "--" or nil), disabled = claimed or not can,
        affordable = (st.watts or 0) >= gift.price,
        draw = function(px, py, ph)
          if gg.kind == "mon" then self:drawPortrait(gg.dex, px + 8, py + 8, ph - 16)
          else
            -- a wrapped present
            local cx2, cy2, s = px + ph / 2, py + ph / 2, ph * 0.28
            g.setColor(0.85, 0.25, 0.35, 1); g.rectangle("fill", cx2 - s, cy2 - s * 0.7, s * 2, s * 1.7, 4, 4)
            setc(GOLD); g.rectangle("fill", cx2 - s * 0.15, cy2 - s * 0.7, s * 0.3, s * 1.7)
            g.rectangle("fill", cx2 - s, cy2 - s * 0.1, s * 2, s * 0.25)
            g.circle("line", cx2 - s * 0.3, cy2 - s * 0.85, s * 0.25); g.circle("line", cx2 + s * 0.3, cy2 - s * 0.85, s * 0.25)
          end
          return px + ph + 4
        end,
        onTap = function()
          if claimed then self:say("Already claimed this week.") return end
          if not can then self:say(("%s cannot receive that one."):format(gameName(target.version))) return end
          self:confirmBuy(("Mystery Gift: %s, for %s."):format(name, gameName(target.version)), gg.price, cy,
            function() return E.buyGift(st, gg, target) end)
        end })
    end
    return (y + math.ceil(#list / n) * (ch + 12)) - y0
  end

  -- the Events shelf, drawn by src/ui/WalkerEventsPage.lua with these helpers
  P._shopKit = { product = product, needTarget = needTarget, heading = heading, gameName = gameName,
                 slotName = slotName, wrapH = wrapH, cols = cols }
  do
    local okEv, EvPage = pcall(require, "src.ui.WalkerEventsPage")
    if okEv and EvPage and EvPage.install then EvPage.install(P) end
  end

  function P:shopCosmetics(x, y, w, f)
    local g = love.graphics
    local st = self.st
    local y0 = y
    local n = cols(w, 230, 12)
    local cw = (w - (n - 1) * 12) / n
    local ch = 20 + f.body:getHeight() + f.small:getHeight() + 30
    for _, kind in ipairs(Shop.COSMETIC_KINDS) do
      y = y + heading(f, x, y, kind.label)
      local list
      if kind.id == "course" then list = Shop.eventCourses(self.courses)
      else list = Shop.COSMETICS[kind.id] end
      local inUse = kind.id ~= "course" and E.using(st, kind.id)
      for i, c in ipairs(list) do
        local cx, cy = x + ((i - 1) % n) * (cw + 12), y + math.floor((i - 1) / n) * (ch + 12)
        local owned = E.owns(st, kind.id, c.id)
        local using = inUse == c.id
        local item, k = c, kind.id
        local sub = (k == "theme" and "Walk scene") or (k == "shell" and "Walker colour") or (k == "sound" and "Tap to hear it")
          or "Event course"
        product(self, f, cx, cy, cw, ch, {
          name = c.name, price = c.price, sub = sub, selected = using,
          state = using and "In use" or (owned and (k == "course" and "Unlocked" or "Owned") or nil),
          stateColor = using and ACCENT or nil,
          affordable = (st.watts or 0) >= (c.price or 0),
          draw = function(px, py, ph)
            local sw = ph - 16
            if k == "theme" or k == "course" then
              g.stencil(function() g.rectangle("fill", px + 8, py + 8, sw * 1.3, sw, 10, 10) end, "replace", 1)
              g.setStencilTest("greater", 0)
              self:scene(px + 8, py + 8, sw * 1.3, sw, k == "theme" and (item.scene or (self:course() or {}).name) or item.name, 0)
              g.setStencilTest()
              return px + 16 + sw * 1.3
            elseif k == "shell" then
              setc(item.color); g.rectangle("fill", px + 8, py + 8, sw, sw, 12, 12)
              g.setColor(1, 1, 1, 0.25); g.rectangle("fill", px + 8, py + 8, sw, sw * 0.45, 12, 12)
              return px + 16 + sw
            else
              setc(INK)
              for b = 0, 2 do
                local bhh = sw * (0.3 + 0.2 * ((b + #item.notes) % 3))
                g.rectangle("fill", px + 12 + b * sw * 0.3, py + 8 + (sw - bhh) / 2, sw * 0.18, bhh, 3, 3)
              end
              return px + 16 + sw
            end
          end,
          onTap = function()
            if k == "sound" then self:chirp(item.id) end
            if using then return end
            if owned then
              if k ~= "course" then E.use(st, k, item.id); self:say(("Now using %s."):format(item.name)) end
              return
            end
            self:confirmBuy(k == "course" and ("Unlock the %s course for your walks."):format(item.name)
                              or ("%s for your walker."):format(item.name), item.price, cy,
              function() return E.buyCosmetic(st, k, item.id) end)
          end })
      end
      y = y + math.ceil(#list / n) * (ch + 12) + 6
    end
    return y - y0
  end

  -- ---------------------------------------------------------- awards

  local function bar(x, y, w, h, frac, col)
    local g = love.graphics
    g.setColor(1, 1, 1, 0.08)
    g.rectangle("fill", x, y, w, h, h / 2, h / 2)
    if frac > 0 then
      setc(col or ACCENT)
      g.rectangle("fill", x, y, math.max(h, w * math.min(1, frac)), h, h / 2, h / 2)
    end
  end

  function P:pageAwards(x, y, w, h, f)
    local g = love.graphics
    local st = self.st
    local e = E.econ(st)
    local y0 = y
    local narrow = w < 640
    local bh = f.body:getHeight() + 22
    -- the streak and today's open-app watts
    local L = e.login
    local p = e.passive
    local pw = (p.day == E.day()) and (p.watts or 0) or 0
    local lines = {
      ("Login streak: %d day%s  (best %d)"):format(L.streak or 0, (L.streak or 0) == 1 and "" or "s", L.best or 0),
      ("Tomorrow's bonus: +%d W -- open the walker every day to grow it (up to %d W)."):format(
        math.min(E.STREAK_MAX, E.STREAK_STEP * ((L.streak or 0) + 1)), E.STREAK_MAX),
      ("Watts for keeping the app open today: %d / %d W  (5 W an hour)"):format(pw, E.PASSIVE_DAILY_CAP),
    }
    local tw = narrow and w - 40 or w - 40 - 240
    local th = 0
    for i, l in ipairs(lines) do th = th + wrapH(i == 1 and f.head or f.small, l, tw) + 6 end
    local topH = 18 + th + 14 + 10 + 18 + (narrow and bh + 14 or 0)
    topH = math.max(topH, narrow and 0 or (bh * 2 + 46))
    card(x, y, w, topH, 18)
    local ly = y + 18
    for i, l in ipairs(lines) do
      local fnt = i == 1 and f.head or f.small
      g.setFont(fnt); setc(i == 1 and GOLD or (i == 3 and INK or DIM))
      g.printf(l, x + 20, ly, tw)
      ly = ly + wrapH(fnt, l, tw) + 6
    end
    bar(x + 20, ly + 4, tw, 10, pw / E.PASSIVE_DAILY_CAP, GOLD)
    local bw = narrow and w - 40 or 220
    local bx = narrow and x + 20 or x + w - 240
    local by = narrow and (ly + 28) or (y + 18)
    self:button(bx, by, bw, bh, "Leaderboards", function() self:openPage("leaderboard") end, "accent", f.body)
    if not narrow then
      self:button(bx, by + bh + 10, bw, bh, "Watt Shop", function() self:openPage("shop") end, "gold", f.body)
    end
    y = y + topH + 14
    -- the achievements
    local prog = E.progress(st)
    local doneN = 0
    for _, a in ipairs(prog) do if a.done then doneN = doneN + 1 end end
    g.setFont(f.head); setc(INK)
    g.print(("Achievements  %d / %d"):format(doneN, #prog), x + 4, y)
    y = y + f.head:getHeight() + 10
    local n = cols(w, 300, 12)
    local cw = (w - (n - 1) * 12) / n
    local ch = 16 + f.body:getHeight() + 4 + f.small:getHeight() + 10 + 10 + 14
    for i, a in ipairs(prog) do
      local cx, cy = x + ((i - 1) % n) * (cw + 12), y + math.floor((i - 1) / n) * (ch + 12)
      card(cx, cy, cw, ch, 14, a.done and { 0.16, 0.30, 0.24 } or CARD, 0.88)
      local reward = a.done and "Done" or ("+%d W"):format(a.def.reward)
      g.setFont(f.small)
      local rw = f.small:getWidth(reward) + 18
      g.setFont(f.body); setc(a.done and INK or INK)
      g.printf(a.def.name, cx + 14, cy + 14, cw - rw - 30)
      g.setFont(f.small); setc(DIM)
      g.printf(a.def.desc, cx + 14, cy + 18 + f.body:getHeight(), cw - 28)
      g.setColor(0, 0, 0, 0.35)
      g.rectangle("fill", cx + cw - rw - 12, cy + 12, rw, f.small:getHeight() + 6, 8, 8)
      setc(a.done and ACCENT or GOLD)
      g.printf(reward, cx + cw - rw - 12, cy + 15, rw, "center")
      local by2 = cy + ch - 20
      local label = ("%d / %d"):format(a.value, a.def.goal)
      local lw = f.small:getWidth(label) + 10
      bar(cx + 14, by2 + 2, cw - 28 - lw, 8, a.value / a.def.goal, a.done and ACCENT or { 0.40, 0.72, 0.98 })
      g.setFont(f.small); setc(DIM)
      g.print(label, cx + cw - 14 - lw + 8, by2 - 3)
    end
    y = y + math.ceil(#prog / n) * (ch + 12)
    return math.max(h, y - y0)
  end

  -- ------------------------------------------------------ leaderboards

  -- the minigames to list: WalkerMinigames.GAMES (or .games(), a list of
  -- { id, name }) when that module is in, plus every board with scores
  function P:boardGames()
    local out, seen = {}, {}
    local mg = self:minigames()
    local list = mg and (type(mg.games) == "function" and select(2, pcall(mg.games)) or mg.GAMES or mg.games)
    for _, gm in ipairs(type(list) == "table" and list or {}) do
      local id = type(gm) == "table" and (gm.id or gm[1]) or gm
      if id and not seen[id] then
        seen[id] = true
        out[#out + 1] = { id = tostring(id), name = type(gm) == "table" and (gm.name or gm.label or gm.title) or tostring(id) }
      end
    end
    local extra = {}
    for id in pairs(E.econ(self.st).scores) do if not seen[id] then extra[#extra + 1] = id end end
    table.sort(extra)
    for _, id in ipairs(extra) do
      local name = id:gsub("[_%-]", " "):gsub("(%a)(%w*)", function(a, b) return a:upper() .. b end)
      out[#out + 1] = { id = id, name = name }
    end
    return out
  end

  function P:pageLeaderboard(x, y, w, h, f)
    local g = love.graphics
    local st = self.st
    local y0 = y
    local bh = f.body:getHeight() + 22
    self:button(x, y, 120, bh, "Back", function() self:openPage("awards") end, nil, f.body)
    g.setFont(f.head); setc(INK)
    g.print("Leaderboards", x + 140, y + (bh - f.head:getHeight()) / 2)
    y = y + bh + 14
    local games = self:boardGames()
    if #games == 0 then
      card(x, y, w, 120, 18)
      g.setFont(f.body); setc(DIM)
      g.printf("No scores yet. Play the minigames (the Minigames button on the Walk page) and your best ten for each show up here.", x + 20, y + 24, w - 40, "center")
      return math.max(h, y + 120 - y0)
    end
    local sel = self.boardGame
    local found = false
    for _, gm in ipairs(games) do if gm.id == sel then found = true end end
    if not found then sel = games[1].id end
    -- the game chips, wrapping
    g.setFont(f.body)
    local cx, cy = x, y
    for _, gm in ipairs(games) do
      local cw = f.body:getWidth(gm.name) + 36
      if cx + cw > x + w and cx > x then cx = x; cy = cy + bh + 10 end
      local id = gm.id
      self:button(cx, cy, math.min(cw, w), bh, gm.name, function() self.boardGame = id end, sel == id and "accent" or nil, f.body)
      cx = cx + cw + 10
    end
    y = cy + bh + 14
    -- the board
    local board = E.econ(st).scores[sel] or {}
    local rowH = f.body:getHeight() + 14
    local ch = 20 + f.head:getHeight() + 10 + E.BOARD_SIZE * rowH + 16
    card(x, y, w, ch, 18)
    local name = sel
    for _, gm in ipairs(games) do if gm.id == sel then name = gm.name end end
    g.setFont(f.head); setc(GOLD)
    g.print(name .. " -- top " .. E.BOARD_SIZE, x + 20, y + 18)
    local ry = y + 28 + f.head:getHeight()
    local colRank, colScore, colDate = x + 24, x + 90, x + math.max(w < 520 and 200 or 220, w * 0.5)
    for i = 1, E.BOARD_SIZE do
      local s = board[i]
      if i % 2 == 1 then g.setColor(1, 1, 1, 0.04); g.rectangle("fill", x + 12, ry - 4, w - 24, rowH, 8, 8) end
      g.setFont(f.body)
      setc(i == 1 and GOLD or (i <= 3 and INK or DIM))
      g.print(("#%d"):format(i), colRank, ry)
      if s then
        setc(INK); g.print(tostring(s.score), colScore, ry)
        setc(DIM); g.print(os.date(w < 520 and "%b %d" or "%b %d %Y  %H:%M", s.t or 0), colDate, ry)
      else
        setc(DIM); g.print("--", colScore, ry)
      end
      ry = ry + rowH
    end
    y = y + ch
    return math.max(h, y - y0)
  end
end

return M
