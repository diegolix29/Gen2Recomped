-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- The POKETCH, which is the thing the bottom screen mostly shows -- and the
-- first line of the original brief: "Instead of having two screens for the
-- poketch and bottom screen allow users to switch between the two with a
-- button".  `SecondScreen` answers where it goes; this is what goes there.
--
-- TWENTY-FIVE APPS, SEVEN OF THEM ALIVE, and the difference is visible on
-- screen rather than hidden.  The `menus` stage already pairs every app's name
-- with its description and its face, and marks the seven this port does
-- something with; the other eighteen still appear and still wear their own
-- picture, because an app that is drawn and inert is a thing a player can see
-- is unfinished, and an app that is silently missing from the list is not.
--
-- WHY THE SEVEN ARE THE SEVEN: each one needs only what this port already has
-- -- a clock, the party, a step count, a number to keep.  The Marking Map
-- wants the Sinnoh map and roamer positions; the Berry Searcher wants the
-- berry plots; the Dowsing Machine wants hidden-item placement; the Matchup
-- Checker wants the type chart applied to a live opponent.  Those are not
-- drawing problems, and starting them here would put four half-features on the
-- watch instead of seven whole ones.
--
-- THE KEYS ARE THE PORT'S, and that is stated rather than implied.  Platinum
-- changes app by tapping the arrows on the touch screen; there is no L/R
-- binding to copy.  Here the second screen is raised with one button and the
-- app cycles with another, both ordinary actions, so both are rebindable
-- through the controls menu like everything else.

local Assets = require("src.render.Assets")
local Font = require("src.render.Font")
local Logger = require("src.core.Logger")
local SecondScreen = require("src.ui.SecondScreen")
local Strings = require("src.core.Strings")

local Gen4Poketch = {}
Gen4Poketch.__index = Gen4Poketch

local W, H = 256, 192

-- The watch face inside the bottom screen.  The cartridge's own `poketch_border`
-- is a full-screen picture with the face cut out of it, so the apps draw into
-- the hole rather than being placed against nothing.
local FACE = { x = 48, y = 40, w = 160, h = 112 }

-- Where the digital watch's four digits sit, and the colon between them.
local DIGIT = { x = 66, y = 74, w = 24, h = 32, gap = 4, colon = 12 }

-- NOT OPAQUE.  The Poketch is a second screen, not a screen that replaces the
-- first: on the corner mode the world is still there behind it, and on swap the
-- world is what the main screen is still showing.
Gen4Poketch.isOpaque = false

function Gen4Poketch:uiSize() return W, H end
function Gen4Poketch:wantsFillScale() return true end
function Gen4Poketch:wantsEdgeBleed() return false end

function Gen4Poketch.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, Gen4Poketch)
  self.game = game
  self.onCancel = opts.onCancel
  self.cache = {}
  self.art = ((game.data or {}).gen4_graphics or {}).screens or {}

  local record = ((game.data or {}).gen4_menus or {}).poketch
  self.apps = (record and record.apps) or nil
  if not self.apps then
    Logger.warn("gen4 poketch: this cache carries no poketch record -- "
                .. "re-import to get the app list")
    self.apps = {}
  end
  self.border = record and record.border or "poketch/poketch_border"
  self.unavailable = record and record.unavailable or "poketch/unavailable"

  -- WHERE IT WAS LAST TIME.  Which app you had up is a thing to keep, and it
  -- is kept on the save rather than on the session for the same reason the
  -- counter is: closing the watch is not meant to reset it.
  local store = self:store()
  self.index = math.max(1, math.min(#self.apps, store.app or 1))
  self.flash = 0
  return self
end

-- The Poketch's own corner of the save.  Created on demand so a save from
-- before this screen existed grows it the first time the watch is opened.
function Gen4Poketch:store()
  local save = self.game.save
  if not save then return {} end
  save.poketch = save.poketch or {}
  return save.poketch
end

-- ---------------------------------------------------------------- pictures --

function Gen4Poketch:img(key)
  local rec = self.art[key]
  local path = (type(rec) == "table" and rec.path) or rec
  if type(path) ~= "string" then return nil end
  if self.cache[path] == nil then
    local ok, image = pcall(Assets.image, path)
    self.cache[path] = ok and image or false
    if self.cache[path] then self.cache[path]:setFilter("nearest", "nearest") end
  end
  return self.cache[path] or nil
end

function Gen4Poketch:app()
  return self.apps[self.index]
end

-- ------------------------------------------------------------------ input --

function Gen4Poketch:close()
  self.game.stack:pop()
  if self.onCancel then self.onCancel() end
end

function Gen4Poketch:cycle(delta)
  local count = #self.apps
  if count == 0 then return end
  self.index = (self.index - 1 + delta) % count + 1
  self:store().app = self.index
end

function Gen4Poketch:update()
  local input = self.game.input
  if not input then return end
  self.flash = (self.flash + 1) % 60

  if input:wasPressed("r") or input:wasPressed("right") then return self:cycle(1) end
  if input:wasPressed("left") then return self:cycle(-1) end
  if input:wasPressed("b") or input:wasPressed("l")
     or input:wasPressed("start") then
    return self:close()
  end

  local app = self:app()
  local name = app and app.name
  if not (app and app.live) then return end

  if input:wasPressed("a") then
    if name == "Counter" then
      local store = self:store()
      store.counter = ((store.counter or 0) + 1) % 10000
    elseif name == "Coin Toss" then
      -- The port's own coin.  `love.math.random` is the engine's generator
      -- everywhere else; using it here keeps one source of randomness.
      self:store().coin = (love.math.random(2) == 1) and "heads" or "tails"
    end
  elseif input:wasPressed("select") then
    if name == "Counter" then self:store().counter = 0
    elseif name == "Pedometer" then self:store().steps = 0 end
  end
end

-- ------------------------------------------------------------------ apps --

local function clockNow()
  local ok, t = pcall(os.date, "*t")
  if ok and type(t) == "table" then return t end
  return { hour = 0, min = 0, day = 1, month = 1, year = 2000, wday = 1 }
end

function Gen4Poketch:drawDigit(value, x, y)
  local image = self:img(("poketch/digits_%02d"):format(value % 10))
  if image then
    local iw, ih = image:getDimensions()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(image, x, y, 0, DIGIT.w / iw, DIGIT.h / ih)
    return
  end
  Font.draw(tostring(value % 10), x + 6, y + 10)
end

function Gen4Poketch:drawDigitalWatch()
  local now = clockNow()
  local x = DIGIT.x
  for _, value in ipairs({ math.floor(now.hour / 10), now.hour % 10 }) do
    self:drawDigit(value, x, DIGIT.y)
    x = x + DIGIT.w + DIGIT.gap
  end
  -- The colon blinks once a second on hardware; the frame clock is what this
  -- port has, so it blinks on the half-second of a sixty-frame cycle.
  if self.flash < 30 then
    Font.draw(":", x + 2, DIGIT.y + 10)
  end
  x = x + DIGIT.colon
  for _, value in ipairs({ math.floor(now.min / 10), now.min % 10 }) do
    self:drawDigit(value, x, DIGIT.y)
    x = x + DIGIT.w + DIGIT.gap
  end
end

function Gen4Poketch:drawAnalogWatch()
  local g = love.graphics
  local now = clockNow()
  local cx, cy = FACE.x + FACE.w / 2, FACE.y + FACE.h / 2
  local radius = math.min(FACE.w, FACE.h) / 2 - 8
  g.setColor(0.18, 0.22, 0.18, 1)
  for tick = 0, 11 do
    local a = tick * math.pi / 6
    g.rectangle("fill", cx + math.sin(a) * radius - 1,
                cy - math.cos(a) * radius - 1, 2, 2)
  end
  -- The minute hand from the minute, and the hour hand from BOTH -- an hour
  -- hand that jumps on the hour instead of creeping is the tell that it was
  -- drawn from the hour alone.
  local minuteAngle = (now.min / 60) * math.pi * 2
  local hourAngle = ((now.hour % 12) / 12 + now.min / 720) * math.pi * 2
  g.setLineWidth(2)
  g.line(cx, cy, cx + math.sin(hourAngle) * radius * 0.55,
         cy - math.cos(hourAngle) * radius * 0.55)
  g.setLineWidth(1)
  g.line(cx, cy, cx + math.sin(minuteAngle) * radius * 0.85,
         cy - math.cos(minuteAngle) * radius * 0.85)
  g.setColor(1, 1, 1, 1)
end

local MONTHS = { "JAN", "FEB", "MAR", "APR", "MAY", "JUN",
                 "JUL", "AUG", "SEP", "OCT", "NOV", "DEC" }

function Gen4Poketch:drawCalendar()
  local g = love.graphics
  local now = clockNow()
  local month = math.max(1, math.min(12, now.month or 1))
  Font.draw(("%s %d"):format(MONTHS[month], now.year or 0), FACE.x + 40, FACE.y + 4)

  -- Which weekday the first of the month falls on, from the weekday of today
  -- and today's date -- no calendar arithmetic of this port's own, because
  -- `os.date` already knows and a hand-rolled day-of-week is a bug waiting for
  -- a leap year.
  local firstCol = ((now.wday or 1) - 1 - ((now.day or 1) - 1) % 7) % 7
  local daysIn = os.date("*t", os.time({ year = now.year, month = month % 12 + 1,
                                         day = 1, hour = 12 }) - 86400).day

  local cw, ch = 20, 14
  local ox, oy = FACE.x + 12, FACE.y + 22
  for day = 1, daysIn do
    local cell = firstCol + day - 1
    local col, row = cell % 7, math.floor(cell / 7)
    local x, y = ox + col * cw, oy + row * ch
    if day == now.day then
      g.setColor(0.98, 0.83, 0.30, 0.8)
      g.rectangle("fill", x - 1, y - 1, cw - 2, ch - 2)
      g.setColor(1, 1, 1, 1)
    end
    Font.draw(tostring(day), x + (day < 10 and 5 or 1), y)
  end
  g.setColor(1, 1, 1, 1)
end

function Gen4Poketch:drawCounter()
  local value = self:store().counter or 0
  local x = DIGIT.x
  for _, place in ipairs({ 1000, 100, 10, 1 }) do
    self:drawDigit(math.floor(value / place) % 10, x, DIGIT.y)
    x = x + DIGIT.w + DIGIT.gap
  end
  Font.draw(Strings("A +   SELECT 0"), FACE.x + 16, FACE.y + FACE.h - 16)
end

function Gen4Poketch:drawCoinToss()
  local face = self:store().coin
  local label = (face == "heads") and Strings("HEADS")
    or (face == "tails") and Strings("TAILS") or Strings("A TO TOSS")
  local width = Font.width(label)
  Font.draw(label, FACE.x + math.floor((FACE.w - width) / 2),
            FACE.y + FACE.h / 2 - 6)
end

function Gen4Poketch:drawPedometer()
  local value = math.floor(self:store().steps or 0)
  local x = DIGIT.x
  for _, place in ipairs({ 1000, 100, 10, 1 }) do
    self:drawDigit(math.floor(value / place) % 10, x, DIGIT.y)
    x = x + DIGIT.w + DIGIT.gap
  end
  Font.draw(Strings("SELECT 0"), FACE.x + 48, FACE.y + FACE.h - 16)
end

function Gen4Poketch:drawPartyStatus()
  local g = love.graphics
  local party = (self.game.save or {}).party or {}
  local mons = (self.game.data or {}).pokemon or {}
  for i = 1, 6 do
    local mon = party[i]
    local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
    local x = FACE.x + 8 + col * 76
    local y = FACE.y + 8 + row * 32
    if mon then
      local def = mons[mon.species]
      Font.draw(((def and def.name) or tostring(mon.species)):sub(1, 9), x, y)
      local hp = math.max(0, tonumber(mon.hp) or 0)
      local max = math.max(1, tonumber((mon.stats or {}).hp) or hp)
      local ratio = math.min(1, hp / max)
      g.setColor(0.12, 0.14, 0.12, 1)
      g.rectangle("fill", x, y + 12, 64, 6)
      -- Green, amber, red at the cartridge's own thresholds: a bar that is
      -- one colour is a bar that tells you nothing at a glance, which is the
      -- entire point of this app.
      if ratio > 0.5 then g.setColor(0.36, 0.82, 0.36, 1)
      elseif ratio > 0.2 then g.setColor(0.94, 0.78, 0.24, 1)
      else g.setColor(0.90, 0.30, 0.28, 1) end
      g.rectangle("fill", x, y + 12, math.floor(64 * ratio), 6)
      g.setColor(1, 1, 1, 1)
    end
  end
  g.setColor(1, 1, 1, 1)
end

local DRAW = {
  ["Digital Watch"] = Gen4Poketch.drawDigitalWatch,
  ["Analog Watch"] = Gen4Poketch.drawAnalogWatch,
  ["Calendar"] = Gen4Poketch.drawCalendar,
  ["Counter"] = Gen4Poketch.drawCounter,
  ["Coin Toss"] = Gen4Poketch.drawCoinToss,
  ["Pedometer"] = Gen4Poketch.drawPedometer,
  ["Pokémon List"] = Gen4Poketch.drawPartyStatus,
}

-- ------------------------------------------------------------------- draw --

function Gen4Poketch:drawWatch()
  local g = love.graphics
  local app = self:app()

  -- APP LCD FIRST. The extracted Poketch app tilemaps are full 256x192
  -- compositions and may contain opaque pixels outside the LCD. Drawing one
  -- after the shell used to cover the cartridge's bezel and buttons entirely.
  local face = app and app.art and self:img(app.art)
  if face then
    -- App tilemaps are composed as full 256x192 screens. Only the LCD hole
    -- belongs to the app; pixels outside it must never cover the device shell.
    g.setScissor(FACE.x, FACE.y, FACE.w, FACE.h)
    g.setColor(1, 1, 1, 1)
    g.draw(face, 0, 0)
  else
    -- Only apps which genuinely have no composed face use the cartridge's
    -- unavailable screen. Do not put this over an existing app merely because
    -- its interactive behaviour has not been implemented yet.
    local blank = self:img(self.unavailable)
    if blank then
      g.setColor(1, 1, 1, 1)
      g.draw(blank, 0, 0)
    else
      g.setColor(0.55, 0.72, 0.42, 1)
      g.rectangle("fill", FACE.x, FACE.y, FACE.w, FACE.h)
    end
  end

  -- Live overlays belong on the LCD, above the app's cartridge background.
  if app then
    local body = app.name and DRAW[app.name]
    if body then
      body(self)
    elseif not face then
      -- Only a truly missing face gets a textual fallback. A valid extracted
      -- app remains visually faithful even before its behaviour is emulated.
      local label = app.name or Strings("APP")
      Font.draw(label, FACE.x + 8, FACE.y + 8)
      Font.draw(Strings("NOT BUILT YET"), FACE.x + 8, FACE.y + 24)
    end
  end

  g.setScissor()

  -- SHELL LAST. Platinum composes the Poketch device around the LCD; this
  -- extracted full-screen border contains the bezel and physical app-change
  -- buttons and must mask the edges of every app tilemap.
  local border = self:img(self.border)
  if border then
    g.setColor(1, 1, 1, 1)
    g.draw(border, 0, 0)
  else
    -- Keep a visible frame if an old cache predates border extraction.
    g.setColor(0.10, 0.13, 0.18, 1)
    g.setLineWidth(2)
    g.rectangle("line", FACE.x - 2, FACE.y - 2, FACE.w + 4, FACE.h + 4)
    g.setLineWidth(1)
  end

  g.setColor(1, 1, 1, 1)
end

function Gen4Poketch:draw()
  if SecondScreen.mode(self.game) == "off" then return self:drawWatch() end
  SecondScreen.drawFrame(self.game)
  SecondScreen.draw(self.game, function() self:drawWatch() end)
end

return Gen4Poketch
