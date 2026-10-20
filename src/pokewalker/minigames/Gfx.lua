-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE MINIGAMES' PAINTBOX: the Pokewalker app's look (its colours, cards and
-- course scenes, borrowed from src/ui/PokewalkerScreen.lua so the games sit
-- in the same world), fonts that scale with the window, buttons that are
-- also touch targets, and the Pokemon pictures from WalkerArt with a drawn
-- stand-in when no game with that species' art is imported.

local G = {}

G.INK = { 0.96, 0.95, 0.92 }
G.DIM = { 0.75, 0.74, 0.72 }
G.GOLD = { 1.00, 0.82, 0.38 }
G.CARD = { 0.10, 0.10, 0.14 }
G.ACCENT = { 0.25, 0.70, 0.48 }
G.RED = { 0.86, 0.26, 0.30 }
G.BLUE = { 0.40, 0.72, 0.98 }
G.BG = { 0.06, 0.07, 0.10 }

function G.setc(c, a) love.graphics.setColor(c[1], c[2], c[3], a or c[4] or 1) end
local setc = G.setc

-- the UI scale for a w x h area: about 1 at a 800x800-ish window
function G.scale(w, h)
  return math.max(0.7, math.min(2.2, math.sqrt(w * h) / 800))
end

-- fonts by scale, rebuilt only when the scale moves
local fontCache = {}
function G.fonts(s)
  local key = math.floor(s * 20 + 0.5)
  local hit = fontCache[key]
  if hit then return hit end
  local file
  pcall(function() file = require("src.translation.Service").launcherFont end)
  local function f(px)
    px = math.max(8, math.floor(px * key / 20 + 0.5))
    local ok, font = pcall(function() return file and love.graphics.newFont(file, px) or love.graphics.newFont(px) end)
    return ok and font or love.graphics.newFont(px)
  end
  hit = { small = f(13), body = f(16), head = f(20), title = f(28), big = f(40) }
  fontCache[key] = hit
  return hit
end

function G.card(x, y, w, h, r, c, a)
  local g = love.graphics
  g.setColor(0, 0, 0, 0.30)
  g.rectangle("fill", x + 3, y + 5, w, h, r, r)
  setc(c or G.CARD, a or 0.92)
  g.rectangle("fill", x, y, w, h, r, r)
  g.setColor(1, 1, 1, 0.06)
  g.rectangle("fill", x, y, w, math.min(h * 0.45, r * 2.5), r, r)
  g.setColor(1, 1, 1, 0.10)
  g.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, r, r)
end

-- ------------------------------------------------------------ hit areas

-- a frame's touch targets, newest drawn on top
function G.newHits() return { list = {} } end
function G.hit(hits, x, y, w, h, fn, id)
  if hits then hits.list[#hits.list + 1] = { x = x, y = y, w = w, h = h, fn = fn, id = id } end
end
function G.press(hits, mx, my)
  if not hits then return false end
  for i = #hits.list, 1, -1 do
    local r = hits.list[i]
    if mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h then
      if r.fn then r.fn() end
      return true, r
    end
  end
  return false
end

local function hovered(x, y, w, h)
  if not (love.mouse and love.mouse.getPosition) then return false end
  local os = love.system and love.system.getOS and love.system.getOS()
  if os == "Android" or os == "iOS" then return false end
  local mx, my = love.mouse.getPosition()
  return mx >= x and mx <= x + w and my >= y and my <= y + h
end
G.hovered = hovered

-- a big button; `focus` draws the keyboard / gamepad ring
function G.button(hits, x, y, w, h, label, fn, kind, font, focus)
  local g = love.graphics
  local hot = hovered(x, y, w, h)
  local base = kind == "accent" and G.ACCENT or kind == "danger" and G.RED or kind == "gold" and { 0.75, 0.55, 0.15 }
    or kind == "blue" and { 0.22, 0.45, 0.75 } or { 0.24, 0.24, 0.30 }
  local r = math.min(h * 0.3, 18)
  g.setColor(0, 0, 0, 0.3)
  g.rectangle("fill", x + 2, y + 4, w, h, r, r)
  setc(base, hot and 1 or 0.92)
  g.rectangle("fill", x, y, w, h, r, r)
  g.setColor(1, 1, 1, hot and 0.22 or 0.12)
  g.rectangle("fill", x, y, w, h * 0.5, r, r)
  if focus then
    setc(G.GOLD)
    g.setLineWidth(3)
    g.rectangle("line", x - 4, y - 4, w + 8, h + 8, r + 3, r + 3)
    g.setLineWidth(1)
  end
  if font then g.setFont(font) end
  local f = g.getFont()
  setc(G.INK)
  g.printf(label, x + 4, math.floor(y + (h - f:getHeight()) / 2), w - 8, "center")
  G.hit(hits, x, y, w, h, fn)
end

-- text that shrinks to one line in `w`
function G.fit(text, x, y, w, font, align)
  local g = love.graphics
  g.setFont(font)
  local tw = font:getWidth(text)
  if tw <= w or tw == 0 then g.printf(text, x, y, w, align or "left") return end
  local s = w / tw
  local ax = align == "center" and x + (w - tw * s) / 2 or align == "right" and x + w - tw * s or x
  g.print(text, ax, y + font:getHeight() * (1 - s) / 2, 0, s, s)
end

-- ------------------------------------------------------------ the scene

local Screen
local function screen()
  if Screen == nil then
    local ok, P = pcall(require, "src.ui.PokewalkerScreen")
    Screen = ok and P or false
  end
  return Screen or nil
end

local proxy = { t = 0, rects = {} }
function G.tick(t) proxy.t = t end

-- the course backdrop, the same one the Pokewalker's walk page shows
function G.scene(x, y, w, h, courseName, scroll)
  local P = screen()
  if P and P.scene then
    local ok = pcall(P.scene, proxy, x, y, w, h, courseName, scroll or 0)
    if ok then return end
  end
  local g = love.graphics
  g.setColor(0.42, 0.70, 0.98, 1); g.rectangle("fill", x, y, w, h * 0.72)
  g.setColor(0.52, 0.80, 0.40, 1); g.rectangle("fill", x, y + h * 0.72, w, h * 0.28)
end

-- the art module, or nil headless
local Art
local function art()
  if Art == nil then
    local ok, A = pcall(require, "src.pokewalker.WalkerArt")
    Art = ok and A or false
  end
  return Art or nil
end
G.art = art

local function initialBlob(dex, name, cx, cy, size)
  local g = love.graphics
  local hue = ((tonumber(dex) or 0) * 47 % 360) / 360
  local r, gg, b = 0.5 + 0.4 * math.cos(hue * 6.28), 0.5 + 0.4 * math.cos((hue - 0.33) * 6.28), 0.5 + 0.4 * math.cos((hue - 0.66) * 6.28)
  g.setColor(r, gg, b, 1)
  g.circle("fill", cx, cy, size * 0.42)
  g.setColor(0, 0, 0, 0.25)
  g.circle("line", cx, cy, size * 0.42)
  g.setColor(1, 1, 1, 0.9)
  g.circle("fill", cx - size * 0.13, cy - size * 0.08, size * 0.07)
  g.circle("fill", cx + size * 0.13, cy - size * 0.08, size * 0.07)
  g.setColor(0.1, 0.1, 0.1, 1)
  g.circle("fill", cx - size * 0.13, cy - size * 0.08, size * 0.035)
  g.circle("fill", cx + size * 0.13, cy - size * 0.08, size * 0.035)
  local fnt = g.getFont()
  local label = tostring(name or ("#" .. tostring(dex))):sub(1, 1):upper()
  g.setColor(1, 1, 1, 0.9)
  g.print(label, cx - fnt:getWidth(label) / 2, cy + size * 0.05)
end

-- the walking sprite, its feet at (x, y) and `size` tall, stepping at `t`
-- Highest-generation available overworld art; never a battle/Pokedex portrait.
local walkQuads=setmetatable({}, {__mode="k"})
function G.walker(dex, x, y, size, facing, t, name, noShadow)
  local g = love.graphics
  local A = art()
  local img, fw, fh, facings
  if A then
    local ok, a, b, c, d = pcall(A.walk, dex, false)
    if ok then img, fw, fh, facings = a, b, c, d end
  end
  if not noShadow then
    g.setColor(0, 0, 0, 0.22)
    g.ellipse("fill", x, y, size * 0.32, size * 0.08)
  end
  if img then
    local seq = facings and (facings[facing or "right"] or facings.down) or {0}
    if type(seq)~="table" or #seq==0 then seq={0} end
    local frame=tonumber(seq[(math.floor((t or 0)*6)%#seq)+1]) or 0
    local iw,ih=img:getDimensions()
    fw,fh=math.max(1,tonumber(fw) or iw),math.max(1,tonumber(fh) or ih)
    local cols,rows=math.floor(iw/fw),math.floor(ih/fh)
    if cols<1 or rows<1 then initialBlob(dex,name,x,y-size*.45,size);return false end
    frame=math.max(0,math.floor(frame))%(cols*rows)
    local byImage=walkQuads[img]
    if not byImage then byImage={};walkQuads[img]=byImage end
    local key=fw..":"..fh..":"..frame
    local q=byImage[key]
    if not q then q=g.newQuad((frame%cols)*fw,math.floor(frame/cols)*fh,fw,fh,iw,ih);byImage[key]=q end
    local s = size / fh
    g.setColor(1, 1, 1, 1)
    g.draw(img, q, x - fw * s / 2, y - fh * s + size * 0.08, 0, s, s)
    return true
  end
  initialBlob(dex, name, x, y - size * 0.45, size)
  return false
end

-- the front portrait in a size x size box at (x, y), trimmed, whole-step scaled
function G.portrait(dex, x, y, size, name)
  local g = love.graphics
  local A = art()
  local front
  if A then
    local ok, img = pcall(A.front, dex, false)
    if ok then front = img end
  end
  if not front then
    -- the overworld sheet's first frame will do
    local img, fw, fh
    if A then
      local ok, a, b, c = pcall(A.walk, dex, false)
      if ok then img, fw, fh = a, b, c end
    end
    if img then return G.walker(dex, x + size / 2, y + size * 0.92, size * 0.9, "down", 0, name) end
    initialBlob(dex, name, x + size / 2, y + size / 2, size)
    return false
  end
  local b = A.bounds(front) or { x = 0, y = 0, w = front:getWidth(), h = front:getHeight() }
  local s = size / math.max(b.w, b.h)
  if s >= 1 then s = math.floor(s) end
  local q = g.newQuad(b.x, b.y, b.w, b.h, front:getDimensions())
  g.setColor(1, 1, 1, 1)
  g.draw(front, q, x + (size - b.w * s) / 2, y + (size - b.h * s) / 2, 0, s, s)
  return true
end

-- ------------------------------------------------------------ small icons

-- an item, drawn: balls are balls, berries are berries, the rest a bag
function G.item(name, cx, cy, r)
  local g = love.graphics
  name = tostring(name or ""):lower()
  if name:find("ball") then
    local top = name:find("great") and { 0.25, 0.45, 0.95 } or name:find("ultra") and { 0.20, 0.20, 0.22 }
      or name:find("net") and { 0.20, 0.70, 0.75 } or { 0.90, 0.20, 0.22 }
    setc(top); g.arc("fill", cx, cy, r, math.pi, 2 * math.pi)
    g.setColor(0.97, 0.97, 0.97, 1); g.arc("fill", cx, cy, r, 0, math.pi)
    g.setColor(0.1, 0.1, 0.1, 1); g.setLineWidth(math.max(1, r * 0.14))
    g.line(cx - r, cy, cx + r, cy); g.circle("line", cx, cy, r)
    g.setColor(0.97, 0.97, 0.97, 1); g.circle("fill", cx, cy, r * 0.3)
    g.setColor(0.1, 0.1, 0.1, 1); g.circle("line", cx, cy, r * 0.3)
    g.setLineWidth(1)
  elseif name:find("berry") then
    local c = name:find("oran") and { 0.25, 0.45, 0.95 } or name:find("pecha") and { 1.0, 0.65, 0.75 }
      or name:find("cheri") and { 0.92, 0.22, 0.25 } or name:find("chesto") and { 0.45, 0.30, 0.70 } or { 0.95, 0.55, 0.20 }
    setc(c); g.circle("fill", cx, cy + r * 0.15, r * 0.8)
    g.setColor(1, 1, 1, 0.35); g.circle("fill", cx - r * 0.3, cy - r * 0.1, r * 0.22)
    g.setColor(0.25, 0.65, 0.30, 1)
    g.ellipse("fill", cx - r * 0.25, cy - r * 0.68, r * 0.35, r * 0.16)
    g.ellipse("fill", cx + r * 0.25, cy - r * 0.68, r * 0.35, r * 0.16)
  else
    g.setColor(0.55, 0.85, 0.95, 1)
    g.rectangle("fill", cx - r * 0.5, cy - r * 0.55, r, r * 1.2, r * 0.25)
    g.setColor(0.9, 0.3, 0.6, 1)
    g.rectangle("fill", cx - r * 0.5, cy - r * 0.15, r, r * 0.35)
    g.setColor(0.4, 0.4, 0.45, 1)
    g.rectangle("fill", cx - r * 0.3, cy - r * 0.8, r * 0.6, r * 0.28, r * 0.08)
  end
end

-- a watt orb: gold, glowing, a W on it
function G.orb(cx, cy, r, t)
  local g = love.graphics
  local glow = 0.25 + 0.15 * math.sin((t or 0) * 6)
  g.setColor(1, 0.85, 0.3, glow); g.circle("fill", cx, cy, r * 1.5)
  g.setColor(1, 0.82, 0.25, 1); g.circle("fill", cx, cy, r)
  g.setColor(1, 1, 0.8, 0.8); g.circle("fill", cx - r * 0.3, cy - r * 0.3, r * 0.3)
  g.setColor(0.55, 0.35, 0.05, 1)
  g.setLineWidth(math.max(1.5, r * 0.18))
  g.line(cx - r * 0.55, cy - r * 0.35, cx - r * 0.3, cy + r * 0.4, cx, cy - r * 0.1, cx + r * 0.3, cy + r * 0.4, cx + r * 0.55, cy - r * 0.35)
  g.setLineWidth(1)
end

-- an icon per game for the hub's cards
function G.gameIcon(id, cx, cy, r, t)
  local g = love.graphics
  t = t or 0
  g.setLineWidth(math.max(2, r * 0.12))
  if id == "runner" then
    setc(G.INK)
    g.arc("line", "open", cx, cy + r * 0.3, r * 0.75, math.pi * 1.1, math.pi * 1.9)
    local k = (t * 0.6) % 1
    local a = math.pi * (1.1 + 0.8 * k)
    G.orb(cx + math.cos(a) * r * 0.75, cy + r * 0.3 + math.sin(a) * r * 0.75, r * 0.22, t)
    g.setColor(0.6, 0.45, 0.3, 1)
    g.rectangle("fill", cx - r * 0.2, cy + r * 0.45, r * 0.4, r * 0.35, r * 0.06)
  elseif id == "catch" then
    local p = (t * 0.8) % 1
    setc(G.ACCENT); g.circle("line", cx, cy, r * (1 - p * 0.65))
    setc(G.GOLD); g.circle("line", cx, cy, r * 0.4)
    G.item("poke ball", cx, cy, r * 0.25)
  elseif id == "treasure" then
    for i = 0, 2 do for j = 0, 2 do
      g.setColor(0.25 + 0.05 * ((i + j) % 2), 0.6, 0.3, 1)
      g.rectangle("fill", cx - r + i * r * 0.68, cy - r + j * r * 0.68, r * 0.62, r * 0.62, r * 0.08)
    end end
    G.item("oran berry", cx, cy, r * 0.28)
    g.setColor(1, 0.4, 0.2, 0.6 + 0.4 * math.sin(t * 5)); g.circle("line", cx, cy, r * 0.4)
  elseif id == "memory" then
    for i = 0, 1 do
      local flip = math.max(0.15, math.abs(math.sin(t * 1.5 + i)))
      setc(i == 0 and G.BLUE or G.RED)
      local cw = r * 0.76 * flip
      g.rectangle("fill", cx - r * 0.85 + i * r * 0.95 + (r * 0.76 - cw) / 2, cy - r * 0.6, cw, r * 1.2, math.min(r * 0.12, cw / 2))
    end
  elseif id == "rhythm" then
    setc(G.INK)
    local beat = (t * 2) % 1
    g.circle("line", cx, cy + r * 0.4, r * (0.35 + 0.15 * (1 - beat)))
    g.line(cx + r * 0.3, cy + r * 0.35, cx + r * 0.3, cy - r * 0.7, cx + r * 0.75, cy - r * 0.5)
    setc(G.GOLD); g.circle("fill", cx - r * 0.55, cy - r * 0.5, r * 0.12 * (1 + beat))
  end
  g.setLineWidth(1)
end

return G
