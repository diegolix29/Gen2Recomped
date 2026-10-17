-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE NEXT-GEN POKEWALKER, a full-screen app in the launcher (the sidebar's
-- Pokewalker section). Everything is a touch / click target; arrow keys and
-- Enter work too.
--
--   the course    a wide scene of the course with the walking Pokemon on it
--                 (its own step cycle from HeartGold / SoulSilver), today's
--                 steps and the watts; a bubble when it found something
--   the tiles     WALK, POKE RADAR (10 W), DOWSING (3 W), BAG, TRAINER CARD,
--                 SETTINGS -- the original's menu, as big buttons
--   below         what the tile opens: the walk (bring it home, receive
--                 presents), the radar's bushes and battle, dowsing's six
--                 bushes, the catches and items, the week's steps, settings;
--                 and the send flow: game -> save -> course -> Pokemon
--
-- Rules: src/pokewalker/Walker.lua. Saves: WalkerLink. Courses: WalkerCourses.
-- Pictures: WalkerArt. Steps: WalkerSteps (the phone's step counter).

local W = require("src.pokewalker.Walker")
local Courses = require("src.pokewalker.WalkerCourses")
local Link = require("src.pokewalker.WalkerLink")
local Art = require("src.pokewalker.WalkerArt")
local Steps = require("src.pokewalker.WalkerSteps")

local P = {}
P.__index = P

P.TILES = {
  { id = "walk", label = "Walk" }, { id = "radar", label = "Poke Radar", cost = W.RADAR_COST },
  { id = "dowse", label = "Dowsing", cost = W.DOWSE_COST }, { id = "bag", label = "Bag" },
  { id = "card", label = "Trainer Card" }, { id = "settings", label = "Settings" },
}

-- ------------------------------------------------------------ the look

local INK = { 0.96, 0.95, 0.92 }
local DIM = { 0.75, 0.74, 0.72 }
local GOLD = { 1.00, 0.82, 0.38 }
local CARD = { 0.10, 0.10, 0.14 }
local ACCENT = { 0.25, 0.70, 0.48 }
local RED = { 0.86, 0.26, 0.30 }

local function theme(name)
  name = tostring(name or ""):lower()
  if name:find("cave") then return "cave" end
  if name:find("beach") or name:find("sea") or name:find("resort") then return "beach" end
  if name:find("lake") then return "lake" end
  if name:find("forest") or name:find("treehouse") then return "forest" end
  if name:find("volcano") then return "volcano" end
  if name:find("icy") or name:find("mountain") then return "snow" end
  if name:find("night") then return "night" end
  if name:find("town") or name:find("suburban") or name:find("sightseeing") or name:find("rally") then return "town" end
  if name:find("road") or name:find("path") then return "road" end
  return "field"
end

local THEMES = {
  field  = { sky = { 0.42, 0.70, 0.98 }, sky2 = { 0.86, 0.94, 1.00 }, far = { 0.55, 0.78, 0.55 }, near = { 0.40, 0.70, 0.34 }, ground = { 0.52, 0.80, 0.40 }, deco = "grass", sun = true },
  forest = { sky = { 0.38, 0.62, 0.62 }, sky2 = { 0.78, 0.90, 0.80 }, far = { 0.22, 0.45, 0.30 }, near = { 0.16, 0.38, 0.22 }, ground = { 0.32, 0.56, 0.26 }, deco = "trees", sun = true },
  beach  = { sky = { 0.36, 0.70, 0.98 }, sky2 = { 0.92, 0.97, 1.00 }, far = { 0.22, 0.55, 0.85 }, near = { 0.30, 0.68, 0.92 }, ground = { 0.97, 0.88, 0.62 }, deco = "palms", sun = true },
  lake   = { sky = { 0.48, 0.70, 0.95 }, sky2 = { 0.88, 0.94, 1.00 }, far = { 0.45, 0.66, 0.50 }, near = { 0.30, 0.58, 0.85 }, ground = { 0.46, 0.74, 0.40 }, deco = "reeds", sun = true },
  cave   = { sky = { 0.10, 0.09, 0.12 }, sky2 = { 0.26, 0.22, 0.24 }, far = { 0.22, 0.19, 0.20 }, near = { 0.30, 0.26, 0.26 }, ground = { 0.42, 0.36, 0.32 }, deco = "crystals" },
  volcano= { sky = { 0.55, 0.20, 0.16 }, sky2 = { 0.98, 0.66, 0.36 }, far = { 0.35, 0.18, 0.16 }, near = { 0.28, 0.16, 0.15 }, ground = { 0.40, 0.26, 0.22 }, deco = "rocks", sun = true },
  snow   = { sky = { 0.62, 0.78, 0.95 }, sky2 = { 0.96, 0.98, 1.00 }, far = { 0.80, 0.86, 0.95 }, near = { 0.90, 0.94, 1.00 }, ground = { 0.96, 0.98, 1.00 }, deco = "pines", sun = true },
  night  = { sky = { 0.04, 0.05, 0.18 }, sky2 = { 0.18, 0.16, 0.40 }, far = { 0.12, 0.18, 0.28 }, near = { 0.10, 0.22, 0.20 }, ground = { 0.16, 0.30, 0.24 }, deco = "stars" },
  town   = { sky = { 0.50, 0.75, 1.00 }, sky2 = { 0.92, 0.95, 1.00 }, far = { 0.70, 0.72, 0.80 }, near = { 0.80, 0.55, 0.45 }, ground = { 0.72, 0.72, 0.70 }, deco = "houses", sun = true },
  road   = { sky = { 0.55, 0.75, 0.95 }, sky2 = { 0.94, 0.95, 1.00 }, far = { 0.62, 0.66, 0.58 }, near = { 0.52, 0.62, 0.42 }, ground = { 0.74, 0.64, 0.46 }, deco = "grass", sun = true },
}

local function setc(c, a) love.graphics.setColor(c[1], c[2], c[3], a or 1) end

local function card(x, y, w, h, r, c, a)
  local g = love.graphics
  g.setColor(0, 0, 0, 0.30)
  g.rectangle("fill", x + 3, y + 5, w, h, r, r)
  setc(c or CARD, a or 0.88)
  g.rectangle("fill", x, y, w, h, r, r)
  g.setColor(1, 1, 1, 0.06)
  g.rectangle("fill", x, y, w, h * 0.45, r, r)
  g.setColor(1, 1, 1, 0.10)
  g.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, r, r)
end

-- ------------------------------------------------------------- the app

function P.new(host)
  local self = setmetatable({ host = host, st = W.load(), t = 0, tab = "walk", panel = nil,
                              rects = {}, toast = nil, monPage = 0 }, P)
  self.courses = Courses.routes()
  Steps.pump(self.st, self.courses, true)
  self.seenNotices = #self.st.notices
  pcall(require("src.pokewalker.WalkerNotify").watch, self.st, self.courses)
  return self
end

function P:course() return self.courses[self.st.course] end
function P:say(text, secs) self.toast = { text = tostring(text), till = self.t + (secs or 3) } end

function P:update(dt)
  self.t = self.t + dt
  Steps.pump(self.st, self.courses)
  local n = #self.st.notices
  if n > (self.seenNotices or 0) then
    self:say(self.st.notices[n].text, 4)
    self.seenNotices = n
  end
  local r = self.radar
  if r and r.timer then
    r.timer = r.timer - dt
    if r.timer <= 0 then r.timer = nil; self.radar = nil; self:say("The Pokemon got away...") end
  end
end

function P:rect(x, y, w, h, fn) self.rects[#self.rects + 1] = { x = x, y = y, w = w, h = h, fn = fn } end

local function hovered(x, y, w, h)
  local mx, my = love.mouse.getPosition()
  return mx >= x and mx <= x + w and my >= y and my <= y + h
end

-- a big touch button
function P:button(x, y, w, h, label, fn, kind, font)
  local g = love.graphics
  local hot = hovered(x, y, w, h)
  local base = kind == "accent" and ACCENT or kind == "danger" and RED or kind == "gold" and { 0.75, 0.55, 0.15 } or { 0.24, 0.24, 0.30 }
  g.setColor(0, 0, 0, 0.3)
  g.rectangle("fill", x + 2, y + 4, w, h, h * 0.3, h * 0.3)
  setc(base, hot and 1 or 0.9)
  g.rectangle("fill", x, y, w, h, h * 0.3, h * 0.3)
  g.setColor(1, 1, 1, hot and 0.22 or 0.12)
  g.rectangle("fill", x, y, w, h * 0.5, h * 0.3, h * 0.3)
  if font then g.setFont(font) end
  local f = g.getFont()
  setc(INK)
  g.printf(label, x, math.floor(y + (h - f:getHeight()) / 2), w, "center")
  self:rect(x, y, w, h, fn)
end

-- the walking Pokemon: its own step cycle when HeartGold / SoulSilver is in,
-- else the portrait with a bob
function P:drawWalker(dex, x, y, size, facing)
  local g = love.graphics
  local img, fw, fh, facings = Art.walk(dex)
  if img then
    local seq = facings and facings[facing or "right"] or { 6, 7, 6 }
    local frame = seq[(math.floor(self.t * 4) % #seq) + 1]
    -- the sheets stack their eight frames top to bottom
    local iw, ih = img:getDimensions()
    local q = ih > iw and g.newQuad(0, frame * fh, fw, fh, iw, ih) or g.newQuad(frame * fw, 0, fw, fh, iw, ih)
    local s = size / fh
    g.setColor(0, 0, 0, 0.25)
    g.ellipse("fill", x, y, size * 0.32, size * 0.08)
    g.setColor(1, 1, 1, 1)
    g.draw(img, q, x - fw * s / 2, y - fh * s + size * 0.08, 0, s, s)
    return true
  end
  local front = Art.front(dex)
  if front then
    local s = size / front:getHeight()
    local bob = math.abs(math.sin(self.t * 5)) * size * 0.05
    g.setColor(0, 0, 0, 0.25)
    g.ellipse("fill", x, y, size * 0.32, size * 0.08)
    g.setColor(1, 1, 1, 1)
    g.draw(front, x - front:getWidth() * s / 2, y - front:getHeight() * s - bob, 0, s, s)
    return true
  end
  return false
end

function P:drawPortrait(dex, x, y, size)
  local front = Art.front(dex)
  if not front then return self:drawWalker(dex, x + size / 2, y + size, size, "down") end
  -- trimmed to the Pokemon, scaled in whole steps so the pixels stay square
  local b = Art.bounds(front) or { x = 0, y = 0, w = front:getWidth(), h = front:getHeight() }
  local s = size / math.max(b.w, b.h)
  if s >= 1 then s = math.floor(s) end
  local q = love.graphics.newQuad(b.x, b.y, b.w, b.h, front:getDimensions())
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(front, q, x + (size - b.w * s) / 2, y + (size - b.h * s) / 2, 0, s, s)
  return true
end

-- PAINTED ART, when it is there: assets/pokewalker/course_<theme>.png (a
-- horizontally seamless 16:9 background) and icon_<tile>.png (a square
-- icon) -- see docs/pokewalker-art.md. Missing files fall back to the scenes
-- and icons drawn in code below.
local artCache = {}
local function art(name)
  local hit = artCache[name]
  if hit == nil then
    hit = false
    for _, ext in ipairs({ ".png", ".jpg" }) do
      local path = "assets/pokewalker/" .. name .. ext
      if not hit and love.filesystem.getInfo(path) then
        local ok, img = pcall(love.graphics.newImage, path, { mipmaps = true })
        if ok and img then
          img:setFilter("linear", "linear")
          pcall(img.setMipmapFilter, img, "linear")
          hit = img
        end
      end
    end
    artCache[name] = hit
  end
  return hit or nil
end
P._art = art

-- the course as a scene: sky, far hills, near hills, ground, its decoration
function P:scene(x, y, w, h, courseName, scroll)
  local g = love.graphics
  local painted = art("course_" .. theme(courseName))
  if painted then
    -- cover the box by height, then scroll sideways: the art, then its
    -- mirror image, then the art again -- the edges always meet
    local iw, ih = painted:getDimensions()
    local s = h / ih
    local tw = iw * s
    local off = (scroll or 0) % (tw * 2)
    g.setColor(1, 1, 1, 1)
    local px = x - off
    local k = 0
    while px < x + w do
      if k % 2 == 0 then g.draw(painted, px, y, 0, s, s)
      else g.draw(painted, px + tw, y, 0, -s, s) end
      px = px + tw
      k = k + 1
    end
    return
  end
  local th = THEMES[theme(courseName)] or THEMES.field
  local strips = 24
  for i = 0, strips - 1 do
    local t = i / (strips - 1)
    g.setColor(th.sky[1] + (th.sky2[1] - th.sky[1]) * t, th.sky[2] + (th.sky2[2] - th.sky[2]) * t,
               th.sky[3] + (th.sky2[3] - th.sky[3]) * t, 1)
    g.rectangle("fill", x, y + i * h * 0.7 / strips, w, h * 0.7 / strips + 1)
  end
  if th.sun then
    g.setColor(1, 0.97, 0.80, 0.9)
    g.circle("fill", x + w * 0.82, y + h * 0.20, h * 0.09)
    g.setColor(1, 0.97, 0.80, 0.18)
    g.circle("fill", x + w * 0.82, y + h * 0.20, h * 0.16)
    for i = 0, 2 do
      local cx = x + ((i * 0.37 + self.t * 0.01) % 1.2 - 0.1) * w
      g.setColor(1, 1, 1, 0.75)
      g.ellipse("fill", cx, y + h * (0.12 + i * 0.07), h * 0.12, h * 0.035)
      g.ellipse("fill", cx + h * 0.08, y + h * (0.10 + i * 0.07), h * 0.08, h * 0.035)
    end
  elseif th.deco == "stars" then
    for i = 1, 40 do
      local sx, sy = x + ((i * 97) % 1000) / 1000 * w, y + ((i * 53) % 600) / 1000 * h
      g.setColor(1, 1, 0.85, 0.4 + 0.5 * math.abs(math.sin(self.t * 1.5 + i)))
      g.circle("fill", sx, sy, 1.5)
    end
    g.setColor(1, 1, 0.9, 0.95)
    g.circle("fill", x + w * 0.8, y + h * 0.2, h * 0.08)
  end
  -- hills, far then near, scrolling at their own speeds
  local function hills(c, base, amp, period, speed)
    setc(c)
    local pts = {}
    local off = (scroll * speed) % period
    for i = 0, 40 do
      local px = x + i * w / 40
      local yy = y + h * base - math.sin((px - x + off) / period * math.pi * 2) * h * amp
      pts[#pts + 1] = px; pts[#pts + 1] = yy
    end
    pts[#pts + 1] = x + w; pts[#pts + 1] = y + h
    pts[#pts + 1] = x; pts[#pts + 1] = y + h
    local ok, tris = pcall(love.math.triangulate, pts)
    if ok then for _, t in ipairs(tris) do g.polygon("fill", t) end end
  end
  hills(th.far, 0.58, 0.06, w * 0.6, 0.25)
  hills(th.near, 0.66, 0.04, w * 0.35, 0.5)
  setc(th.ground)
  g.rectangle("fill", x, y + h * 0.72, w, h * 0.28)
  g.setColor(0, 0, 0, 0.10)
  g.rectangle("fill", x, y + h * 0.72, w, 3)
  -- the decoration, at the ground's speed
  local step = h * 0.42
  local off = scroll % step
  for i = -1, math.ceil(w / step) + 1 do
    local px = x + i * step - off
    local gy = y + h * 0.72
    if th.deco == "trees" or th.deco == "pines" then
      local c = th.deco == "pines" and { 0.20, 0.42, 0.36 } or { 0.12, 0.36, 0.18 }
      setc(c)
      g.polygon("fill", px, gy, px + step * 0.22, gy - h * 0.42, px + step * 0.44, gy)
      g.polygon("fill", px + step * 0.04, gy - h * 0.14, px + step * 0.22, gy - h * 0.52, px + step * 0.40, gy - h * 0.14)
      if th.deco == "pines" then g.setColor(1, 1, 1, 0.9); g.polygon("fill", px + step * 0.16, gy - h * 0.42, px + step * 0.22, gy - h * 0.52, px + step * 0.28, gy - h * 0.42) end
      g.setColor(0.36, 0.22, 0.12, 1)
      g.rectangle("fill", px + step * 0.20, gy - h * 0.04, step * 0.04, h * 0.05)
    elseif th.deco == "palms" then
      g.setColor(0.5, 0.35, 0.2, 1)
      g.setLineWidth(math.max(2, h * 0.02))
      g.line(px + step * 0.2, gy + h * 0.1, px + step * 0.26, gy - h * 0.28)
      g.setColor(0.2, 0.6, 0.3, 1)
      for a = 0, 4 do
        local ang = math.pi * (1.1 + a * 0.2)
        g.line(px + step * 0.26, gy - h * 0.28, px + step * 0.26 + math.cos(ang) * step * 0.2, gy - h * 0.28 + math.sin(ang) * -h * 0.1)
      end
      g.setLineWidth(1)
      g.setColor(1, 1, 1, 0.55)
      g.arc("line", "open", px + step * 0.6, gy + h * 0.2, step * 0.08, math.pi, 2 * math.pi)
    elseif th.deco == "reeds" then
      g.setColor(0.25, 0.5, 0.25, 1)
      for r = 0, 3 do g.rectangle("fill", px + r * step * 0.05, gy - h * 0.1, 2, h * 0.12) end
    elseif th.deco == "crystals" then
      g.setColor(0.5, 0.75, 1, 0.8)
      g.polygon("fill", px + step * 0.2, gy, px + step * 0.26, gy - h * 0.16, px + step * 0.32, gy)
      g.setColor(0.35, 0.3, 0.3, 1)
      g.ellipse("fill", px + step * 0.65, gy + h * 0.02, step * 0.14, h * 0.05)
    elseif th.deco == "rocks" then
      g.setColor(0.25, 0.20, 0.19, 1)
      g.ellipse("fill", px + step * 0.3, gy + h * 0.02, step * 0.16, h * 0.06)
    elseif th.deco == "houses" then
      g.setColor(0.95, 0.92, 0.85, 1)
      g.rectangle("fill", px + step * 0.1, gy - h * 0.2, step * 0.32, h * 0.2)
      g.setColor(0.80, 0.30, 0.25, 1)
      g.polygon("fill", px + step * 0.05, gy - h * 0.2, px + step * 0.26, gy - h * 0.34, px + step * 0.47, gy - h * 0.2)
      g.setColor(0.45, 0.65, 0.9, 1)
      g.rectangle("fill", px + step * 0.16, gy - h * 0.14, step * 0.07, h * 0.06)
    else
      g.setColor(0.28, 0.58, 0.24, 1)
      for r = 0, 2 do
        local bx = px + r * step * 0.08
        g.polygon("fill", bx, gy + h * 0.06, bx + step * 0.03, gy - h * 0.02, bx + step * 0.06, gy + h * 0.06)
      end
    end
  end
end

-- ------------------------------------------------------------- input

function P:mousepressed(mx, my)
  for i = #self.rects, 1, -1 do
    local r = self.rects[i]
    if mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h then
      if r.fn then r.fn() end
      return true
    end
  end
  return false
end

function P:keypressed(key)
  local i
  for n, t in ipairs(P.TILES) do if t.id == self.tab then i = n end end
  if key == "left" and i and not self.panel then self:openTab(P.TILES[math.max(1, i - 1)].id) return true end
  if key == "right" and i and not self.panel then self:openTab(P.TILES[math.min(#P.TILES, i + 1)].id) return true end
  if key == "escape" or key == "backspace" then
    if self.panel then self.panel = nil return true end
    if self.tab ~= "walk" then self.tab = "walk" return true end
  end
  return false
end

function P:openTab(id)
  self.tab = id
  self.panel = nil
end

-- ------------------------------------------------------------- the hero

function P:drawHero(x, y, w, h, f)
  local g = love.graphics
  local st, wk = self.st, self.st.walking
  local c = self:course()
  g.stencil(function() g.rectangle("fill", x, y, w, h, 18, 18) end, "replace", 1)
  g.setStencilTest("greater", 0)
  self:scene(x, y, w, h, c and c.name, wk and self.t * 60 or 0)
  if wk then
    local size = math.min(h * 0.62, 200)
    local px, py = x + w * 0.36, y + h * 0.86
    self:drawWalker(wk.species, px, py, size, "right")
    -- something found: the bubble, tap to collect
    if #st.finds > 0 then
      local bx, by = px + size * 0.45, py - size * 1.05 + math.sin(self.t * 4) * 4
      local f1 = st.finds[1]
      g.setColor(1, 1, 1, 0.95)
      g.circle("fill", bx, by, 26)
      g.polygon("fill", bx - 12, by + 18, bx - 22, by + 34, bx, by + 24)
      g.setFont(f.head); g.setColor(0.85, 0.2, 0.25, 1)
      local label = f1.watts and (f1.watts .. "W") or "!"
      g.printf(label, bx - 26, by - f.head:getHeight() / 2, 52, "center")
      self:rect(bx - 30, by - 30, 60, 60, function()
        local msg, full = W.collectFind(st)
        self:say(msg or (full == "full" and "Your bag is full -- send items home first." or "Nothing..."))
        W.save(st)
      end)
    end
  else
    g.setFont(f.title); setc(INK)
    g.printf("Nobody is out walking", x, y + h * 0.22, w, "center")
    self:button(x + w / 2 - 150, y + h * 0.22 + f.title:getHeight() + 16, 300, f.body:getHeight() + 26,
      "Send a Pokemon", function() self.tab = "walk"; self.panel = "pickGame" end, "accent", f.body)
  end
  g.setStencilTest()
  -- the counters
  local today = (st.history[1] and st.history[1].day == math.floor(os.time() / 86400)) and st.history[1].steps or 0
  local pills = { { tostring(today), "steps today" }, { tostring(st.watts or 0) .. " W", "watts" } }
  local px = x + w - 16
  for i = #pills, 1, -1 do
    local p = pills[i]
    g.setFont(f.head)
    local pw = math.max(f.head:getWidth(p[1]), f.small:getWidth(p[2])) + 30
    px = px - pw
    g.setColor(0, 0, 0, 0.45)
    g.rectangle("fill", px, y + 14, pw, f.head:getHeight() + f.small:getHeight() + 14, 12, 12)
    setc(i == 2 and GOLD or INK)
    g.printf(p[1], px, y + 20, pw, "center")
    g.setFont(f.small); setc(DIM)
    g.printf(p[2], px, y + 20 + f.head:getHeight(), pw, "center")
    px = px - 10
  end
  if c then
    g.setFont(f.body)
    local cw = f.body:getWidth(c.name) + 30
    g.setColor(0, 0, 0, 0.45)
    g.rectangle("fill", x + 16, y + 14, cw, f.body:getHeight() + 14, 12, 12)
    setc(INK)
    g.print(c.name, x + 31, y + 21)
  end
end

-- ------------------------------------------------------------- the tiles

local function tileIcon(id, cx, cy, r, t)
  local g = love.graphics
  local painted = art("icon_" .. id)
  if painted then
    local s = (r * 2.2) / math.max(painted:getWidth(), painted:getHeight())
    g.setColor(1, 1, 1, 1)
    g.draw(painted, cx - painted:getWidth() * s / 2, cy - painted:getHeight() * s / 2, 0, s, s)
    return
  end
  g.setLineWidth(math.max(2, r * 0.12))
  setc(INK)
  if id == "walk" then
    g.ellipse("fill", cx - r * 0.35, cy + r * 0.2, r * 0.22, r * 0.34)
    g.ellipse("fill", cx + r * 0.35, cy - r * 0.2, r * 0.22, r * 0.34)
  elseif id == "radar" then
    for k = 1, 3 do g.arc("line", "open", cx, cy + r * 0.5, k * r * 0.35, -math.pi * 0.85, -math.pi * 0.15) end
    g.circle("fill", cx, cy + r * 0.5, r * 0.12)
  elseif id == "dowse" then
    g.line(cx - r * 0.6, cy + r * 0.6, cx, cy, cx, cy - r * 0.6)
    g.line(cx + r * 0.6, cy + r * 0.6, cx, cy)
    setc(GOLD, 0.6 + 0.4 * math.sin(t * 6))
    g.circle("fill", cx, cy - r * 0.6, r * 0.18)
  elseif id == "bag" then
    g.rectangle("line", cx - r * 0.6, cy - r * 0.3, r * 1.2, r * 0.9, r * 0.2)
    g.arc("line", "open", cx, cy - r * 0.3, r * 0.3, math.pi, 2 * math.pi)
  elseif id == "card" then
    g.rectangle("line", cx - r * 0.7, cy - r * 0.45, r * 1.4, r * 0.9, r * 0.15)
    g.circle("fill", cx - r * 0.3, cy, r * 0.2)
    g.line(cx + r * 0.05, cy - r * 0.1, cx + r * 0.5, cy - r * 0.1)
    g.line(cx + r * 0.05, cy + r * 0.15, cx + r * 0.5, cy + r * 0.15)
  elseif id == "settings" then
    g.circle("line", cx, cy, r * 0.45)
    for k = 0, 7 do
      local a = k * math.pi / 4 + t * 0.5
      g.line(cx + math.cos(a) * r * 0.45, cy + math.sin(a) * r * 0.45, cx + math.cos(a) * r * 0.7, cy + math.sin(a) * r * 0.7)
    end
  end
  g.setLineWidth(1)
end

function P:drawTiles(x, y, w, h, f)
  local g = love.graphics
  local n = #P.TILES
  local gap = 12
  local tw = (w - gap * (n - 1)) / n
  for i, t in ipairs(P.TILES) do
    local tx = x + (i - 1) * (tw + gap)
    local on = self.tab == t.id
    local hot = hovered(tx, y, tw, h)
    card(tx, y, tw, h, 16, on and { 0.20, 0.48, 0.38 } or CARD, on and 0.95 or (hot and 0.95 or 0.85))
    tileIcon(t.id, tx + tw / 2, y + h * 0.38, h * 0.22, self.t)
    g.setFont(f.small); setc(on and INK or DIM)
    g.printf(t.label .. (t.cost and ("  " .. t.cost .. " W") or ""), tx, y + h * 0.70, tw, "center")
    local id = t.id
    self:rect(tx, y, tw, h, function() self:openTab(id) end)
  end
end

-- ------------------------------------------------------------- the pages

function P:pageWalk(x, y, w, h, f)
  local g = love.graphics
  local st, wk = self.st, self.st.walking
  local lw = math.min(w * 0.5, 560)
  card(x, y, lw, h, 18)
  local yy = y + 18
  if wk then
    self:drawPortrait(wk.species, x + 10, yy - 6, 136)
    g.setFont(f.head); setc(INK)
    g.print(("%s  Lv%d"):format(wk.name or "?", wk.level or 1), x + 150, yy + 4)
    g.setFont(f.body); setc(DIM)
    local c = self:course()
    local GameVersion = require("src.core.GameVersion")
    local info = GameVersion.info(wk.source and wk.source.version)
    local lines = {
      ("%d steps this walk"):format(wk.steps or 0),
      c and ("On " .. c.name) or "",
      "From " .. ((info and (info.launcherName or info.displayName)) or "?"),
    }
    for i, l in ipairs(lines) do g.print(l, x + 150, yy + 8 + f.head:getHeight() + (i - 1) * (f.body:getHeight() + 4)) end
    if wk.advantage then setc(ACCENT); g.print("Type advantage: finds come 25% sooner", x + 150, yy + 8 + f.head:getHeight() + 3 * (f.body:getHeight() + 4)) end
    local bh = f.body:getHeight() + 26
    yy = math.max(yy + 140, y + h - bh - 18)
    local bw = (lw - 54) / 2
    self:button(x + 18, yy, bw, bh, "Bring it home", function()
      local ok, why = Link.bringHome(st, false)
      self:say(ok and "Home! Open the game to see it." or ("Could not: " .. tostring(why)))
      if ok then pcall(require("src.pokewalker.WalkerNotify").watch, st, self.courses) end
    end, "accent", f.body)
    self:button(x + 36 + bw, yy, bw, bh, "Send presents home", function()
      if #st.caught == 0 and #st.items == 0 then self:say("Nothing to send yet."); return end
      local ok, why = Link.bringHome(st, true)
      self:say(ok and "Sent! Open the game to receive them." or ("Could not: " .. tostring(why)))
    end, nil, f.body)
    yy = yy + bh + 14
  else
    g.setFont(f.head); setc(INK)
    g.print("Take a Pokemon for a walk", x + 18, yy)
    g.setFont(f.body); setc(DIM)
    g.printf("Any game's Pokemon can come along. It walks with your steps, earns watts, finds items and meets wild Pokemon you can catch -- then goes home to its own game.", x + 18, yy + f.head:getHeight() + 8, lw - 36)
    yy = yy + f.head:getHeight() + f.body:getHeight() * 4 + 20
    self:button(x + 18, yy, lw - 36, f.body:getHeight() + 26, "Send a Pokemon", function() self.panel = "pickGame" end, "accent", f.body)
    yy = yy + f.body:getHeight() + 40
  end
  local rx, rw = x + lw + 16, w - lw - 16
  local sbw = math.min(220, rw * 0.45)
  card(rx, y, rw, h, 18)
  self:button(rx + rw - sbw - 14, y + 10, sbw, f.small:getHeight() + 18, "Read my steps now", function()
    local n = Steps.pump(st, self.courses, true)
    self:say(n > 0 and ("+%d steps"):format(n) or (Steps.available() and "Reading your phone's step counter..." or "No step counter on this device -- steps come from your phone."))
  end, nil, f.small)
  -- the diary
  g.setFont(f.head); setc(GOLD)
  g.print("Diary", rx + 18, y + 14)
  g.setFont(f.small)
  local ly = y + 20 + f.head:getHeight()
  for i = #st.log, 1, -1 do
    if ly > y + h - f.small:getHeight() - 10 then break end
    local e = st.log[i]
    setc(DIM); g.print(os.date("%b %d  %H:%M", e.t), rx + 18, ly)
    setc(INK); g.printf(e.text, rx + 140, ly, rw - 158)
    ly = ly + f.small:getHeight() + 8
  end
  if #st.log == 0 then setc(DIM); g.print("Nothing yet -- go for a walk!", rx + 18, ly) end
end

function P:bushes(x, y, w, h, n, f, onTap, opts)
  local g = love.graphics
  local cw = w / n
  for i = 1, n do
    local cx = x + (i - 0.5) * cw
    local cy = y + h * 0.62
    local shake = (opts.shake == i) and math.sin(self.t * 45) * 5 or 0
    local opened = opts.opened and opts.opened[i]
    local r = math.min(cw * 0.38, h * 0.36)
    g.setColor(0, 0, 0, 0.25)
    g.ellipse("fill", cx, cy + r * 0.85, r, r * 0.22)
    setc(opened and { 0.40, 0.42, 0.30 } or { 0.16, 0.50, 0.22 })
    g.circle("fill", cx - r * 0.45 + shake, cy, r * 0.62)
    g.circle("fill", cx + r * 0.45 + shake, cy, r * 0.62)
    setc(opened and { 0.50, 0.52, 0.36 } or { 0.24, 0.64, 0.28 })
    g.circle("fill", cx + shake, cy - r * 0.35, r * 0.7)
    if opts.marks and opts.shake == i then
      g.setFont(f.title); setc(GOLD)
      g.printf(("!"):rep(opts.marks), cx - 60, cy - r * 1.7, 120, "center")
    end
    if hovered(cx - r, cy - r, r * 2, r * 2) then g.setColor(1, 1, 1, 0.12); g.circle("fill", cx, cy - r * 0.2, r) end
    local idx = i
    self:rect(cx - cw / 2, y, cw, h, function() onTap(idx) end)
  end
end

function P:pageRadar(x, y, w, h, f)
  local g = love.graphics
  local st = self.st
  card(x, y, w, h, 18)
  local b = self.battle
  if b then return self:pageBattle(x, y, w, h, f) end
  if self.radar then
    g.setFont(f.head); setc(INK)
    g.printf("Which bush is moving? Tap it, quick!", x, y + 16, w, "center")
    self:bushes(x + 20, y + 30, w - 40, h - 40, 4, f, function(i)
      local r = self.radar
      if r and i == r.bush then
        self.battle = W.newBattle(r.encounter)
        self.battle.text = ("A wild %s appeared!"):format(r.encounter.name or "Pokemon")
      else
        self:say("Nothing there... it got away.")
      end
      self.radar = nil
    end, { shake = self.radar.bush, marks = self.radar.marks })
    return
  end
  g.setFont(f.head); setc(INK)
  g.printf("Poke Radar", x, y + 24, w, "center")
  g.setFont(f.body); setc(DIM)
  g.printf(("Spend %d W to search the bushes. The more \"!\" over the moving bush, the rarer the Pokemon. Catches so far: %d / %d."):format(W.RADAR_COST, #st.caught, W.MAX_CAUGHT), x + 40, y + 34 + f.head:getHeight(), w - 80, "center")
  self:button(x + w / 2 - 160, y + h * 0.55, 320, f.body:getHeight() + 30, ("Search  (%d W)"):format(W.RADAR_COST), function()
    local r, why = W.radarStart(st)
    if not r then self:say(why) return end
    self.radar = r
    W.save(st)
  end, "accent", f.body)
end

function P:pageBattle(x, y, w, h, f)
  local g = love.graphics
  local st, b = self.st, self.battle
  local function pips(px, py, n, label)
    g.setFont(f.small); setc(INK); g.print(label, px, py - f.small:getHeight() - 4)
    for i = 1, 4 do
      setc(i <= n and { 0.35, 0.90, 0.45 } or { 0.25, 0.25, 0.28 })
      g.rectangle("fill", px + (i - 1) * 34, py, 30, 10, 4, 4)
    end
  end
  local size = math.min(h * 0.55, 220)
  self:drawPortrait(b.enc.species, x + w * 0.62, y + 20, size)
  pips(x + w * 0.62, y + size + 40, math.max(0, b.wild), ("%s  Lv%d"):format(b.enc.name or "?", b.enc.level or 1))
  if st.walking then
    self:drawWalker(st.walking.species, x + w * 0.22, y + h * 0.62, size * 0.75, "right")
    pips(x + w * 0.10, y + h * 0.70, math.max(0, b.me), st.walking.name or "")
  end
  g.setFont(f.body); setc(INK)
  g.printf(b.text or "", x + 20, y + 20, w * 0.5, "left")
  local bh = f.body:getHeight() + 30
  local by = y + h - bh - 18
  if b.over then
    self:button(x + w / 2 - 140, by, 280, bh, "Continue", function()
      if b.swap then W.swapCaught(st, 1, b.swap); self:say("Bag full -- your first catch was swapped out.") end
      self.battle = nil
      W.save(st)
    end, "accent", f.body)
  else
    local bw = (w - 80) / 3
    for i, a in ipairs({ { "attack", "Attack", "danger" }, { "catch", "Throw a Ball", "accent" }, { "evade", "Evade", nil } }) do
      local action = a[1]
      self:button(x + 20 + (i - 1) * (bw + 20), by, bw, bh, a[2], function()
        local _, text = W.battleTurn(st, b, action)
        b.text = text
        W.save(st)
      end, a[3], f.body)
    end
  end
end

function P:pageDowse(x, y, w, h, f)
  local g = love.graphics
  local st = self.st
  card(x, y, w, h, 18)
  local d = self.dowse
  if d then
    g.setFont(f.head); setc(INK)
    g.printf(d.hint or "Tap a bush to search it.", x, y + 16, w, "center")
    g.setFont(f.body); setc(DIM)
    g.printf(("Tries left: %d"):format(d.tries), x, y + 20 + f.head:getHeight(), w, "center")
    if d.done then
      self:button(x + w / 2 - 140, y + h - f.body:getHeight() - 50, 280, f.body:getHeight() + 30, "Done", function() self.dowse = nil end, "accent", f.body)
    end
    self:bushes(x + 20, y + 40 + f.head:getHeight(), w - 40, h - 120 - f.head:getHeight(), 6, f, function(i)
      if d.done or (d.opened and d.opened[i]) then return end
      d.opened = d.opened or {}
      d.opened[i] = true
      local r = W.dowseTry(st, d, i)
      d.hint = r == "found" and ("Found %s!"):format(d.item) or r == "close" and "It's close -- right next to that one!"
        or r == "far" and "It's far from there..." or ("Nothing... it was %s."):format(d.item)
      if d.swap then W.swapItem(st, 1, d.swap); d.hint = d.hint .. " (bag full: swapped the first item)" end
      W.save(st)
    end, { opened = d.opened })
    return
  end
  g.setFont(f.head); setc(INK)
  g.printf("Dowsing", x, y + 24, w, "center")
  g.setFont(f.body); setc(DIM)
  g.printf(("Spend %d W to search six bushes for an item. Two tries -- a miss tells you whether it is close or far. Items so far: %d / %d."):format(W.DOWSE_COST, #st.items, W.MAX_ITEMS), x + 40, y + 34 + f.head:getHeight(), w - 80, "center")
  self:button(x + w / 2 - 160, y + h * 0.55, 320, f.body:getHeight() + 30, ("Search  (%d W)"):format(W.DOWSE_COST), function()
    local dd, why = W.dowseStart(st, self:course())
    if not dd then self:say(why) return end
    self.dowse = dd
    W.save(st)
  end, "accent", f.body)
end

function P:pageBag(x, y, w, h, f)
  local g = love.graphics
  local st = self.st
  local cw = (w - 2 * 16) / 3
  local ch = h * 0.55
  for i = 1, W.MAX_CAUGHT do
    local cx = x + (i - 1) * (cw + 16)
    card(cx, y, cw, ch, 18)
    local c = st.caught[i]
    if c then
      local ps = math.min(cw - 20, ch - f.body:getHeight() - 30)
      self:drawPortrait(c.species, cx + (cw - ps) / 2, y + 8, ps)
      g.setFont(f.body); setc(INK)
      g.printf(("%s  Lv%d"):format(c.name or "?", c.level or 1), cx, y + ch - f.body:getHeight() - 14, cw, "center")
    else
      g.setFont(f.small); setc(DIM)
      g.printf("Empty -- catch one with the Poke Radar", cx + 10, y + ch / 2 - 10, cw - 20, "center")
    end
  end
  local iy = y + ch + 16
  local ih = h - ch - 16
  for i = 1, W.MAX_ITEMS do
    local cx = x + (i - 1) * (cw + 16)
    card(cx, iy, cw, ih, 18)
    local it = st.items[i]
    g.setFont(f.body); setc(it and INK or DIM)
    g.printf(it and it.name or "No item", cx, iy + ih / 2 - f.body:getHeight() / 2, cw, "center")
  end
end

function P:pageCard(x, y, w, h, f)
  local g = love.graphics
  local st = self.st
  card(x, y, w, h, 18)
  local week, sum = W.lastWeek(st)
  g.setFont(f.head); setc(GOLD)
  g.print("Trainer Card", x + 20, y + 16)
  g.setFont(f.body); setc(INK)
  local c = self:course()
  local info = {
    ("Course: %s"):format(c and c.name or "-"),
    ("Watts: %d   (earned in all: %d)"):format(st.watts or 0, st.lifetimeWatts or 0),
    ("Steps in all: %d over %d days"):format(st.lifetimeSteps or 0, st.days or 0),
    ("Last 7 days: %d steps"):format(sum),
  }
  for i, l in ipairs(info) do g.print(l, x + 20, y + 22 + f.head:getHeight() + (i - 1) * (f.body:getHeight() + 6)) end
  local top = y + 40 + f.head:getHeight() + 4 * (f.body:getHeight() + 6)
  local chartH = y + h - top - 40
  local maxv = 1
  for i = 1, 8 do maxv = math.max(maxv, week[i] or 0) end
  local bw = (w - 40) / 8
  for i = 8, 1, -1 do
    local v = week[i] or 0
    local bh = chartH * v / maxv
    local bx = x + 20 + (8 - i) * bw
    setc(i == 1 and GOLD or { 0.40, 0.72, 0.98 })
    if bh >= 2 then g.rectangle("fill", bx + 8, top + chartH - bh, bw - 16, bh, math.min(6, bh / 2), math.min(6, bh / 2)) end
    g.setFont(f.small); setc(DIM)
    g.printf(i == 1 and "today" or ("-%d"):format(i - 1), bx, top + chartH + 6, bw, "center")
    if v > 0 then setc(INK); g.printf(tostring(v), bx, top + chartH - bh - f.small:getHeight() - 2, bw, "center") end
  end
end

function P:pageSettings(x, y, w, h, f)
  local g = love.graphics
  local st = self.st
  card(x, y, w, h, 18)
  g.setFont(f.head); setc(INK)
  g.print("Sound", x + 20, y + 20)
  local bh = f.body:getHeight() + 22
  for i, label in ipairs({ "Mute", "Medium", "Loud" }) do
    local v = i - 1
    self:button(x + 220 + (i - 1) * 150, y + 16, 140, bh, label, function()
      st.settings.sound = v; W.save(st)
    end, (st.settings.sound or 1) == v and "accent" or nil, f.body)
  end
  g.setFont(f.head); setc(INK)
  g.print("Notifications", x + 20, y + 40 + bh)
  local on = st.settings.notify ~= false
  self:button(x + 220, y + 36 + bh, 140, bh, on and "On" or "Off", function()
    st.settings.notify = not on; W.save(st)
    pcall(require("src.pokewalker.WalkerNotify").watch, st, self.courses)
  end, on and "accent" or nil, f.body)
  g.setFont(f.small); setc(DIM)
  g.printf("Steps come from your phone's step counter (Android asks for the activity permission the first time). With notifications on, the phone tells you -- even with the app closed -- when a new course opens, when something is rustling on your walk, and when you reach the day's step goals.", x + 20, y + 70 + bh * 2, w - 40)
end

-- --------------------------------------------------------- send flow

function P:pickHeader(x, y, w, f, text, back)
  local g = love.graphics
  self:button(x, y, 120, f.body:getHeight() + 20, "Back", back, nil, f.body)
  g.setFont(f.head); setc(INK)
  g.print(text, x + 140, y + 4)
  return y + f.body:getHeight() + 34
end

function P:pickGame(x, y, w, h, f)
  local g = love.graphics
  local yy = self:pickHeader(x, y, w, f, "Which game is it in?", function() self.panel = nil end)
  local GameVersion = require("src.core.GameVersion")
  local list = {}
  for _, v in ipairs(GameVersion.ORDER) do if self.host and self.host.ready and self.host.ready[v] then list[#list + 1] = v end end
  local cols = math.max(1, math.floor(w / 260))
  local cw = (w - (cols - 1) * 14) / cols
  local ch = 120
  for i, v in ipairs(list) do
    local cx, cy = x + ((i - 1) % cols) * (cw + 14), yy + math.floor((i - 1) / cols) * (ch + 14)
    local hot = hovered(cx, cy, cw, ch)
    card(cx, cy, cw, ch, 16, hot and { 0.18, 0.18, 0.24 } or CARD)
    local art = self.host._sbArt and self.host:_sbArt(v)
    local tx = cx + 16
    if art then
      local s = (ch - 20) / art:getHeight()
      g.setColor(1, 1, 1, 1)
      g.draw(art, cx + 10, cy + 10, 0, s, s)
      tx = cx + 20 + art:getWidth() * s
    end
    local info = GameVersion.info(v)
    g.setFont(f.body); setc(INK)
    g.printf(info.launcherName or info.displayName or v, tx, cy + ch / 2 - f.body:getHeight() / 2, cx + cw - tx - 10)
    local vv = v
    self:rect(cx, cy, cw, ch, function() self.pickVersion, self.panel = vv, "pickSlot" end)
  end
end

function P:pickSlot(x, y, w, h, f)
  local g = love.graphics
  local yy = self:pickHeader(x, y, w, f, "Which save?", function() self.panel = "pickGame" end)
  local SaveData = require("src.core.SaveData")
  local ch = f.body:getHeight() + f.small:getHeight() + 30
  for _, s in ipairs(SaveData.listSlots(self.pickVersion) or {}) do
    if s.exists then
      local hot = hovered(x, yy, w, ch)
      card(x, yy, w, ch, 14, hot and { 0.18, 0.18, 0.24 } or CARD)
      g.setFont(f.body); setc(INK)
      g.print(s.label or s.name or s.id, x + 20, yy + 10)
      g.setFont(f.small); setc(DIM)
      local meta = type(s.meta) == "table" and table.concat((function() local t = {} for _, v in pairs(s.meta) do t[#t + 1] = tostring(v) end return t end)(), "  ") or tostring(s.meta or "")
      g.print(meta, x + 20, yy + 14 + f.body:getHeight())
      local id = s.id
      self:rect(x, yy, w, ch, function()
        self.pickSlot, self.panel = id, "pickCourse"
        self.monList = Link.boxMons(self.pickVersion, id) or {}
        self.natDex = Link.hasNatDex(self.pickVersion, id)
        self.monPage = 0
      end)
      yy = yy + ch + 10
    end
  end
end

function P:pickCourse(x, y, w, h, f)
  local g = love.graphics
  local yy = self:pickHeader(x, y, w, f, "Where should it walk?", function() self.panel = "pickSlot" end)
  local open = {}
  for _, id in ipairs(W.unlocked(self.st, self.courses, self.natDex)) do open[id] = true end
  local cols = math.max(1, math.floor(w / 230))
  local cw = (w - (cols - 1) * 12) / cols
  local ch = 112
  local n = 0
  for id = 0, 26 do
    local c = self.courses[id]
    if c and (open[id] or not c.event) then
      n = n + 1
      local cx, cy = x + ((n - 1) % cols) * (cw + 12), yy + math.floor((n - 1) / cols) * (ch + 12)
      if cy + ch > y + h then break end
      g.stencil(function() g.rectangle("fill", cx, cy, cw, ch, 14, 14) end, "replace", 1)
      g.setStencilTest("greater", 0)
      self:scene(cx, cy, cw, ch, c.name, 0)
      g.setColor(0, 0, 0, open[id] and 0.30 or 0.65)
      g.rectangle("fill", cx, cy + ch - f.body:getHeight() - f.small:getHeight() - 16, cw, f.body:getHeight() + f.small:getHeight() + 16)
      g.setStencilTest()
      g.setFont(f.body); setc(open[id] and INK or DIM)
      g.print(c.name, cx + 12, cy + ch - f.body:getHeight() - f.small:getHeight() - 10)
      g.setFont(f.small); setc(open[id] and DIM or GOLD)
      g.print(open[id] and table.concat(c.types or {}, " / ")
        or (c.natDex and not self.natDex and ("%d W + National Dex"):format(c.watts or 0) or ("%d W"):format(c.watts or 0)),
        cx + 12, cy + ch - f.small:getHeight() - 6)
      if open[id] then
        local cid = id
        self:rect(cx, cy, cw, ch, function() self.pickCourse_, self.panel = cid, "pickMon" end)
      end
    end
  end
end

function P:pickMon(x, y, w, h, f)
  local g = love.graphics
  local yy = self:pickHeader(x, y, w, f, "Who's going? (from the PC boxes)", function() self.panel = "pickCourse" end)
  local list = self.monList or {}
  if #list == 0 then
    g.setFont(f.body); setc(DIM)
    g.print("No Pokemon in this save's PC boxes -- deposit one in the game first.", x, yy)
    return
  end
  local cell = 128
  local cols = math.max(1, math.floor((w + 12) / (cell + 12)))
  local rows = math.max(1, math.floor((y + h - yy - 70) / (cell + 12)))
  local per = cols * rows
  local pages = math.max(1, math.ceil(#list / per))
  self.monPage = math.min(self.monPage or 0, pages - 1)
  for k = 1, per do
    local i = self.monPage * per + k
    local m = list[i]
    if not m then break end
    local cx, cy = x + ((k - 1) % cols) * (cell + 12), yy + math.floor((k - 1) / cols) * (cell + 12)
    local hot = hovered(cx, cy, cell, cell)
    card(cx, cy, cell, cell, 14, hot and { 0.18, 0.18, 0.24 } or CARD)
    if m.species then self:drawWalker(m.species, cx + cell / 2, cy + cell - 34, 64, "down") end
    g.setFont(f.small); setc(INK)
    g.printf(("%s  Lv%d"):format(m.name or "?", m.level or 1), cx + 4, cy + cell - f.small:getHeight() - 8, cell - 8, "center")
    local entry = m
    self:rect(cx, cy, cell, cell, function()
      local ok, why = Link.send(self.st, entry, self.pickCourse_)
      if ok then self:say(("%s set off!"):format(entry.name)); self.panel = nil; self.tab = "walk"
        pcall(require("src.pokewalker.WalkerNotify").watch, self.st, self.courses)
      else self:say("Could not: " .. tostring(why)) end
    end)
  end
  if pages > 1 then
    local bh = f.body:getHeight() + 20
    local by = y + h - bh
    self:button(x, by, 120, bh, "Previous", function() self.monPage = math.max(0, self.monPage - 1) end, nil, f.body)
    g.setFont(f.body); setc(DIM)
    g.printf(("%d / %d"):format(self.monPage + 1, pages), x + 130, by + 10, 120, "center")
    self:button(x + 260, by, 120, bh, "Next", function() self.monPage = math.min(pages - 1, self.monPage + 1) end, nil, f.body)
  end
end

-- ------------------------------------------------------------- draw

function P:draw(x, y, w, h, fonts)
  self.rects = {}
  local g = love.graphics
  g.push("all")
  local f = fonts
  if self.panel then
    local fn = ({ pickGame = P.pickGame, pickSlot = P.pickSlot, pickCourse = P.pickCourse, pickMon = P.pickMon })[self.panel]
    if fn then fn(self, x, y, w, h, f) end
  else
    local heroH = math.max(180, math.min(h * 0.38, 320))
    self:drawHero(x, y, w, heroH, f)
    local tilesY = y + heroH + 16
    local tileH = math.max(76, math.min(104, h * 0.13))
    self:drawTiles(x, tilesY, w, tileH, f)
    local py = tilesY + tileH + 16
    local ph = math.max(220, y + h - py)
    local page = ({ walk = P.pageWalk, radar = P.pageRadar, dowse = P.pageDowse, bag = P.pageBag,
                    card = P.pageCard, settings = P.pageSettings })[self.tab]
    if page then page(self, x, py, w, ph, f) end
  end
  if self.toast and self.t < self.toast.till then
    g.setFont(f.body)
    local tw = math.min(w - 40, f.body:getWidth(self.toast.text) + 40)
    local tx, ty = x + (w - tw) / 2, y + 12
    g.setColor(0.06, 0.06, 0.08, 0.94)
    g.rectangle("fill", tx, ty, tw, f.body:getHeight() + 20, 14, 14)
    setc(GOLD)
    g.printf(self.toast.text, tx + 20, ty + 10, tw - 40, "center")
  end
  g.pop()
  return h
end

return P
