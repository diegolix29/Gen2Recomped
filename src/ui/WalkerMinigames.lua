-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE POKEWALKER'S MINIGAMES: a hub of five games that earn watts, items and
-- Pokemon without a step counter (src/pokewalker/minigames/*).
--
--   WalkerMinigames.open(screen, st)
--
-- is the one entry point (the Pokewalker screen's "Minigames" button calls
-- it; `screen` is the PokewalkerScreen, `st` the walker state). It takes over
-- the whole window, inside the safe area, until the player backs out:
--   * with the launcher behind the screen (screen.host), the launcher
--     instance's draw / input methods are covered for the duration by
--     instance fields that route to the hub, and put back on close. The
--     launcher's own update keeps running underneath (downloads, cloud,
--     steps), with its background game held still -- the same pause its
--     Settings page uses -- so the backdrop's music never plays over a game
--     and the phone is not rendering a scene nobody sees.
--   * with only a screen, the screen's own draw / input are covered instead;
--   * with neither, the hub is returned for the caller to drive
--     (hub:update(dt), hub:draw(x, y, w, h), hub:pointer(x, y), hub:key(k),
--     hub:pad(button)) -- the screenshot harness does that.
--
-- The hub: a card per game (best score, plays, Play and Scores), today's
-- reward budget, and a leaderboard per game: the economy's own top ten (what
-- E.recordScore keeps) with each run's watts matched in, or -- without the
-- economy -- the top ten minigames/Rewards keeps in st.minigames.

local Rewards = require("src.pokewalker.minigames.Rewards")
local Context = require("src.pokewalker.minigames.Context")
local Base = require("src.pokewalker.minigames.Base")
local Gfx = require("src.pokewalker.minigames.Gfx")

local H = {}
H.__index = H

H.GAME_MODULES = {
  "src.pokewalker.minigames.JumpRunner",
  "src.pokewalker.minigames.CatchTiming",
  "src.pokewalker.minigames.TreasureHunt",
  "src.pokewalker.minigames.MemoryMatch",
  "src.pokewalker.minigames.RhythmTap",
}

local gamesCache
function H.games()
  if not gamesCache then
    gamesCache = {}
    for _, path in ipairs(H.GAME_MODULES) do gamesCache[#gamesCache + 1] = require(path) end
  end
  return gamesCache
end

function H.new(screen, st, opts)
  local self = setmetatable({ screen = screen, st = st, opts = opts or {}, t = 0, view = "list",
                              sel = 1, scoresOf = nil, earned = 0, runs = 0, stickDir = {} }, H)
  Rewards.state(st)
  local A=Gfx.art()
  if A and A.forget then A.forget() end -- imports may have changed since last entry
  pcall(self.context,self)
  return self
end

-- ------------------------------------------------------------ the games

local seedBump = 0
function H:context()
  seedBump = seedBump + 1
  local ctx = Context.build(self.st, (self.opts.seed or os.time()) + seedBump * 7919, self.opts.version)
  ctx.hasArt = function(dex)
    local A = Gfx.art()
    if not A then return true end
    local ok, img = pcall(A.front, dex, false)
    return ok and img ~= nil
  end
  self.sourceError=nil
  self.artVersion=ctx.version
  self.rosterCount=#ctx.wild
  if not self.opts.version then self.opts.version=ctx.version end
  return ctx
end

function H:cycleSource()
  if self.st.walking and self.st.walking.source then return end
  local A=Gfx.art()
  if not (A and A.roster) then return end
  local versions={}
  for _,v in ipairs({"red","blue","yellow","gold","silver","crystal","polishedcrystal","prism","emerald","firered","platinum","heartgold","soulsilver","black","white"})do
    local ok,list=pcall(A.roster,v)
    if ok and #list>0 then versions[#versions+1]=v end
  end
  for i,v in ipairs(versions)do
    if v==self.artVersion then
      self.opts.version=versions[i%#versions+1];self:context();return
    end
  end
  if #versions>0 then self.opts.version=versions[1];self:context() end
end

function H:play(i, skipIntro)
  local mod = H.games()[i]
  if not mod then return end
  self.sel = i
  local ok,ctx=pcall(self.context,self)
  if not ok then self.sourceError=tostring(ctx);return end
  local session
  session = Base.new(mod, ctx, self.st, {
    onExit = function() self.session = nil; self.view = "list" end,
    onAgain = function() self:play(i, true) end,
    onFinish = function(_, result)
      self.earned = self.earned + (result.watts or 0)
      self.runs = self.runs + 1
    end,
  })
  self.session = session
  self.view = "game"
  if skipIntro then session:start() end
  return session
end

-- ------------------------------------------------------------ update / input

function H:update(dt)
  self.t = self.t + math.min(dt or 0, 0.1)
  if self.session then self.session:update(dt) end
end

function H:close()
  if self.session and self.session.phase ~= "results" and self.session.phase ~= "intro" then
    self.session:finish()
  end
  self.session = nil
  if self.onClose then self.onClose(self) end
end

function H:action(a)
  if self.view == "game" and self.session then return self.session:action(a) end
  local n = #H.games()
  if self.view == "scores" then
    if a == "back" or a == "pause" then self.view = "list" return true end
    if a == "a" then self:play(self.scoresOf or self.sel) return true end
    if a == "left" or a == "up" then self.scoresOf = (self.scoresOf - 2) % n + 1 end
    if a == "right" or a == "down" then self.scoresOf = self.scoresOf % n + 1 end
    return true
  end
  local cols = self.cols or 1
  if a == "back" or a == "pause" then self:close() return true end
  if a == "a" then self:play(self.sel) return true end
  if a == "alt" then self.scoresOf, self.view = self.sel, "scores" return true end
  if a == "left" then self.sel = math.max(1, self.sel - 1)
  elseif a == "right" then self.sel = math.min(n, self.sel + 1)
  elseif a == "up" then self.sel = math.max(1, self.sel - cols)
  elseif a == "down" then self.sel = math.min(n, self.sel + cols) end
  return true
end

function H:pointer(x, y)
  self.keyed = false
  if self.view == "game" and self.session then return self.session:pointer(x, y) end
  Gfx.press(self.hits, x, y)
  return true
end

function H:key(k)
  if self.view == "game" and self.session then return self.session:key(k) end
  self.keyed = true
  if k == "tab" then return self:action("alt") end
  local a = Base.KEYS[k]
  if a == "pause" then a = "back" end
  if a then return self:action(a) end
  return false
end

function H:pad(button)
  if self.view == "game" and self.session then return self.session:pad(button) end
  self.keyed = true
  local a = Base.padAction(button)
  if a then return self:action(a) end
  return false
end

-- A CONTROLLER SDL CANNOT MAP arrives as raw joystick events only: axis 1 / 2
-- are its stick, its hat its d-pad (the launcher reads them the same way).
-- A mapped pad sends both kinds, and its gamepad events already counted.
local function rawIgnored(joystick)
  local okI, ignore = pcall(require("src.core.GamepadMap").ignoreRawForJoystick, joystick)
  return okI and ignore
end

function H:rawAxis(joystick, axis, value)
  if rawIgnored(joystick) then return end
  if axis == 1 then self:axis("leftx", value) elseif axis == 2 then self:axis("lefty", value) end
end

H.HAT = { u = "dpup", d = "dpdown", l = "dpleft", r = "dpright", lu = "dpup", ru = "dpup",
          ld = "dpdown", rd = "dpdown" }

function H:rawHat(joystick, _, direction)
  if rawIgnored(joystick) then return end
  local dir = H.HAT[direction]
  if dir and self.hatDir ~= dir then self:pad(dir) end
  self.hatDir = dir
end

-- the left stick as a d-pad (one step per push)
function H:axis(axis, value)
  local dir
  if axis == "leftx" then dir = value > 0.6 and "dpright" or value < -0.6 and "dpleft" or nil
  elseif axis == "lefty" then dir = value > 0.6 and "dpdown" or value < -0.6 and "dpup" or nil
  else return end
  -- (the held direction lives in `stickDir`: a field named `axis` hid this
  -- method, and the first stick push called a table and crashed the app)
  if dir and self.stickDir[axis] ~= dir then self:pad(dir) end
  self.stickDir[axis] = dir
end

-- ------------------------------------------------------------ drawing

local function dateOf(t) return t and os.date("%b %d", t) or "" end

function H:draw(x, y, w, h)
  local g = love.graphics
  Gfx.tick(self.t)
  Gfx.version=self.artVersion
  if self.view == "game" and self.session then
    self.session:draw(x, y, w, h)
    return
  end
  local s = Gfx.scale(w, h)
  local f = Gfx.fonts(s)
  self.hits = Gfx.newHits()
  local pad = math.floor(12 * s)
  -- the header
  local hh = math.floor(math.max(44, f.head:getHeight() + 22 * s))
  local bw = math.max(hh * 1.6, f.body:getWidth("Back") + 36 * s)
  Gfx.button(self.hits, x + pad, y + 6, bw, hh - 12, "Back", function()
    if self.view == "scores" then self.view = "list" else self:close() end
  end, nil, f.body)
  local wtxt = ("%d W"):format(self.st.watts or 0)
  local ww = f.head:getWidth(wtxt) + 30 * s
  g.setColor(0, 0, 0, 0.45)
  g.rectangle("fill", x + w - pad - ww, y + 6, ww, hh - 12, 12)
  Gfx.setc(Gfx.GOLD)
  g.setFont(f.head)
  g.printf(wtxt, x + w - pad - ww, y + (hh - f.head:getHeight()) / 2, ww, "center")
  local title = self.view == "scores" and (H.games()[self.scoresOf].title .. " -- best runs") or "Minigames"
  Gfx.setc(Gfx.INK)
  Gfx.fit(title, x + pad + bw + 14 * s, y + (hh - f.title:getHeight()) / 2, w - 2 * pad - bw - ww - 28 * s, f.title, "left")
  local top = y + hh + 4
  if self.view == "scores" then return self:drawScores(x + pad, top, w - 2 * pad, y + h - top - pad, s, f) end

  -- today's budget
  local left = Rewards.left(self.st)
  local L = Rewards.LIMITS
  local budget = ("Today's prizes left:  %d / %d W   ·   %d / %d items   ·   %d / %d Pokemon"):format(
    left.watts, L.WATTS_PER_DAY, left.items, L.ITEMS_PER_DAY, left.pokemon, L.POKEMON_PER_DAY)
  Gfx.setc(Gfx.DIM)
  Gfx.fit(budget, x + pad, top, w - 2 * pad, f.small, "left")
  top = top + f.small:getHeight() + 10 * s

  if self.artVersion then
    local info=require("src.core.GameVersion").info(self.artVersion)
    local fixed=self.st.walking and self.st.walking.source
    local label=("Pokemon: %s (%d)  %s"):format(info and info.label or self.artVersion,self.rosterCount or 0,
      fixed and "- walking Pokemon's ROM" or "- Change ROM")
    local sh=f.small:getHeight()+20*s
    Gfx.button(self.hits,x+pad,top,w-2*pad,sh,label,function()self:cycleSource()end,nil,f.small)
    top=top+sh+10*s
  end

  if self.sourceError then
    Gfx.setc(Gfx.RED)
    Gfx.fit(self.sourceError,x+pad,top,w-2*pad,f.small,"left")
    top=top+f.small:getHeight()+8*s
  end

  -- the cards: as many columns as fit, each tall enough for its buttons
  local games = H.games()
  local n = #games
  local gap = math.floor(12 * s)
  local availW, availH = w - 2 * pad, y + h - top - pad
  local minW = 300 * s
  local cols = math.max(1, math.min(3, math.floor((availW + gap) / (minW + gap))))
  local rows = math.ceil(n / cols)
  local btnH = math.max(44, f.body:getHeight() + 20 * s)
  local minH = btnH + f.head:getHeight() + f.small:getHeight() * 2 + 34 * s
  local ch = math.floor((availH - gap * (rows - 1)) / rows)
  -- too short (a phone on its side): another column if it helps
  while ch < minH and cols < n do
    cols = cols + 1
    rows = math.ceil(n / cols)
    ch = math.floor((availH - gap * (rows - 1)) / rows)
  end
  ch = math.max(minH, math.min(ch, 170 * s))
  self.cols = cols
  local cw = (availW - gap * (cols - 1)) / cols
  for i, mod in ipairs(games) do
    local c, r = (i - 1) % cols, math.floor((i - 1) / cols)
    local cx, cy = x + pad + c * (cw + gap), top + r * (ch + gap)
    local on = self.keyed and self.sel == i
    Gfx.card(cx, cy, cw, ch, 16 * s, on and { 0.16, 0.30, 0.26 } or Gfx.CARD, 0.95)
    if on then
      Gfx.setc(Gfx.GOLD); g.setLineWidth(3)
      g.rectangle("line", cx - 3, cy - 3, cw + 6, ch + 6, 18 * s)
      g.setLineWidth(1)
    end
    local ir = math.min(ch * 0.26, 40 * s)
    Gfx.gameIcon(mod.id, cx + 14 * s + ir, cy + 14 * s + ir, ir, self.t)
    local tx = cx + 28 * s + ir * 2
    local tw = cx + cw - tx - 12 * s
    Gfx.setc(Gfx.INK)
    Gfx.fit(mod.title, tx, cy + 12 * s, tw, f.head, "left")
    local rec = Rewards.game(self.st, mod.id)
    g.setFont(f.small)
    Gfx.setc(Gfx.DIM)
    local blurbY = cy + 16 * s + f.head:getHeight()
    local blurbH = cy + ch - btnH - 14 * s - f.small:getHeight() - blurbY
    if blurbH >= f.small:getHeight() then
      local _, lines = f.small:getWrap(mod.blurb, tw)
      local fitN = math.max(1, math.floor(blurbH / f.small:getHeight()))
      for k = 1, math.min(#lines, fitN) do g.print(lines[k], tx, blurbY + (k - 1) * f.small:getHeight()) end
    end
    Gfx.setc(Gfx.GOLD)
    Gfx.fit((rec.plays or 0) > 0 and ("Best %d   ·   played %d"):format(rec.best or 0, rec.plays) or "Not played yet",
      tx, cy + ch - btnH - 10 * s - f.small:getHeight(), tw, f.small, "left")
    local bw2 = (cw - 36 * s) / 2
    local idx = i
    Gfx.button(self.hits, cx + 12 * s, cy + ch - btnH - 10 * s, bw2, btnH, "Play", function() self:play(idx) end, "accent", f.body)
    Gfx.button(self.hits, cx + 24 * s + bw2, cy + ch - btnH - 10 * s, bw2, btnH, "Scores", function()
      self.scoresOf, self.view = idx, "scores"
    end, nil, f.body)
  end
end

function H:drawScores(x, y, w, h, s, f)
  local g = love.graphics
  local games = H.games()
  local mod = games[self.scoresOf] or games[1]
  local rec = Rewards.game(self.st, mod.id)
  local btnH = math.max(44, f.body:getHeight() + 20 * s)
  -- the game switcher: one chip per game
  local chipW = (w - 8 * s * (#games - 1)) / #games
  for i, m in ipairs(games) do
    local idx = i
    Gfx.button(self.hits, x + (i - 1) * (chipW + 8 * s), y, chipW, btnH, m.title, function() self.scoresOf = idx end,
      i == self.scoresOf and "blue" or nil, f.small)
  end
  local ly = y + btnH + 12 * s
  local listH = y + h - ly - btnH - 12 * s
  Gfx.card(x, ly, w, listH, 16 * s)
  local rowH = f.body:getHeight() + 10 * s
  g.setFont(f.small); Gfx.setc(Gfx.DIM)
  local cols = { x + 20 * s, x + 80 * s, x + w * 0.45, x + w * 0.70 }
  g.print("#", cols[1], ly + 10 * s); g.print("Score", cols[2], ly + 10 * s)
  g.print("Watts", cols[3], ly + 10 * s); g.print("Day", cols[4], ly + 10 * s)
  local ry = ly + 14 * s + f.small:getHeight()
  local board = Rewards.board(self.st, mod.id)
  if #board == 0 then
    Gfx.setc(Gfx.DIM); g.setFont(f.body)
    g.printf("No runs yet -- play one!", x, ly + listH / 2 - f.body:getHeight() / 2, w, "center")
  end
  for i, e in ipairs(board) do
    if ry + rowH > ly + listH - 6 then break end
    if i % 2 == 1 then g.setColor(1, 1, 1, 0.04); g.rectangle("fill", x + 8, ry - 3 * s, w - 16, rowH) end
    g.setFont(f.body)
    Gfx.setc(i == 1 and Gfx.GOLD or Gfx.INK)
    g.print(tostring(i), cols[1], ry)
    g.print(tostring(e.score or 0), cols[2], ry)
    Gfx.setc(Gfx.DIM)
    g.print(e.watts and ("%d W"):format(e.watts) or "-", cols[3], ry)
    g.print(dateOf(e.t), cols[4], ry)
    ry = ry + rowH
  end
  local by = y + h - btnH
  local info = ("Played %d times, %d W earned in all"):format(rec.plays or 0, rec.totalWatts or 0)
  local bw = math.min(260 * s, w * 0.4)
  Gfx.setc(Gfx.DIM)
  Gfx.fit(info, x, by + (btnH - f.small:getHeight()) / 2, w - bw - 16 * s, f.small, "left")
  local idx = self.scoresOf
  Gfx.button(self.hits, x + w - bw, by, bw, btnH, "Play " .. mod.title, function() self:play(idx) end, "accent", f.body)
end

-- the whole window, inside the safe area (notch, status and gesture bars)
function H:drawFull()
  local g = love.graphics
  local W, Hh = g.getDimensions()
  local sx, sy, sw, sh = 0, 0, W, Hh
  local ok, a, b, c, d = pcall(love.window.getSafeArea)
  if ok and tonumber(c) and tonumber(d) and c > 0 and d > 0 then sx, sy, sw, sh = a, b, c, d end
  g.push("all")
  g.origin()
  g.setScissor()
  Gfx.setc(Gfx.BG)
  g.rectangle("fill", 0, 0, W, Hh)
  -- a soft course-coloured glow behind the hub
  if self.view ~= "game" then
    g.setColor(0.15, 0.35, 0.28, 0.25)
    g.circle("fill", W * 0.85, Hh * 0.1, math.max(W, Hh) * 0.4)
  end
  self:draw(sx, sy, sw, sh)
  g.pop()
end

-- ------------------------------------------------------------ taking over

-- the methods covered while the hub is up
H.HOOKS = { "draw", "update", "mousepressed", "mousereleased", "mousemoved", "wheelmoved", "keypressed",
            "keyreleased", "textinput", "gamepadpressed", "gamepadreleased", "gamepadaxis", "joystickpressed",
            "joystickreleased", "joystickaxis", "joystickhat", "touchpressed", "touchmoved", "touchreleased" }

local NONE = {}

local function lookup(obj, saved, name)
  local v = saved[name]
  if v ~= nil and v ~= NONE then return v end
  local mt = getmetatable(obj)
  local idx = mt and mt.__index
  if type(idx) == "table" then return idx[name] end
  if type(idx) == "function" then return idx(obj, name) end
  return nil
end

local function cover(obj, hub, fns)
  local saved = {}
  for _, name in ipairs(H.HOOKS) do
    local v = rawget(obj, name)
    saved[name] = v == nil and NONE or v
  end
  for _, name in ipairs(H.HOOKS) do
    obj[name] = fns[name] or function() end
  end
  return function()
    for _, name in ipairs(H.HOOKS) do
      local v = saved[name]
      obj[name] = v ~= NONE and v or nil
    end
  end, saved
end

-- the launcher instance (screen.host)
local function coverHost(host, hub)
  local wasSettings = host.settingsOpen
  local restore, saved
  restore, saved = cover(host, hub, {
    draw = function() hub:drawFull() end,
    update = function(self, dt, ...)
      -- the launcher keeps ticking (its work, the step pump); Settings' pause
      -- holds its background game still and silent under the hub
      self.settingsOpen = true
      local orig = lookup(self, saved, "update")
      if orig then
        local ok, err = pcall(orig, self, dt, ...)
        if not ok then pcall(function() require("src.core.Logger").info("walker minigames: launcher update: %s", tostring(err)) end) end
      end
      hub:update(dt)
    end,
    mousepressed = function(_, x, y, button) if button == nil or button == 1 then hub:pointer(x, y) end end,
    touchpressed = function(_, _, x, y) hub:pointer(x, y) end,
    keypressed = function(_, key) hub:key(key) end,
    gamepadpressed = function(_, _, button) hub:pad(button) end,
    gamepadaxis = function(_, _, axis, value) hub:axis(axis, value) end,
    joystickaxis = function(_, joystick, axis, value) hub:rawAxis(joystick, axis, value) end,
    joystickhat = function(_, joystick, hat, direction) hub:rawHat(joystick, hat, direction) end,
    joystickpressed = function(_, joystick, button)
      local GM = require("src.core.GamepadMap")
      local okI, ignore = pcall(GM.ignoreRawForJoystick, joystick)
      if okI and ignore then return end
      local okN, name = pcall(GM.mapRawToGamepadButton, button)
      if okN and name then hub:pad(name) end
    end,
  })
  return function()
    restore()
    host.settingsOpen = wasSettings
  end
end

-- just the Pokewalker screen (no launcher behind it): its own rectangle
local function coverScreen(screen, hub)
  local restore = cover(screen, hub, {
    draw = function(_, x, y, w, h)
      hub:draw(x, y, w, h)
      return h
    end,
    update = function(_, dt) hub:update(dt) end,
    mousepressed = function(_, x, y) hub:pointer(x, y) return true end,
    keypressed = function(_, key) return hub:key(key) end,
    gamepadpressed = function(_, _, button) return hub:pad(button) end,
    gamepadaxis = function(_, _, axis, value) hub:axis(axis, value) return true end,
    joystickaxis = function(_, joystick, axis, value) hub:rawAxis(joystick, axis, value) return true end,
    joystickhat = function(_, joystick, hat, direction) hub:rawHat(joystick, hat, direction) return true end,
  })
  return restore
end

H.active = nil

function H.open(screen, st, opts)
  if H.active then H.active:close() end
  st = st or (screen and screen.st)
  if not st then st = require("src.pokewalker.Walker").load() end
  local hub = H.new(screen, st, opts)
  local host = screen and screen.host
  local uncover
  if host and type(host) == "table" then uncover = coverHost(host, hub)
  elseif screen then uncover = coverScreen(screen, hub) end
  hub.onClose = function(self)
    if uncover then uncover(); uncover = nil end
    if H.active == self then H.active = nil end
    if screen and screen.say and self.runs > 0 then
      pcall(screen.say, screen, ("Minigames: %d run%s, +%d W"):format(self.runs, self.runs == 1 and "" or "s", self.earned))
    end
  end
  H.active = hub
  return hub
end

return H
