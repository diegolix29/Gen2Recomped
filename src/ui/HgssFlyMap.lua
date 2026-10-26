-- HEARTGOLD / SOULSILVER'S FLY MAP AND TOWN MAP (pokeheartgold
-- src/application/pokegear/map/fly_map.c + overlay_101_021E9270.c /
-- 021EB568.c / 021EDCE0.c): the Pokegear's map without the Pokegear --
-- PGMAP_TYPE_FLY from the party menu's Fly, PGMAP_TYPE_TOWN_MAP from the
-- `TownMap` script command (a Pokemon Center's wall map).
--
-- READ FROM CODE:
--   * the touch screen: the map (pgmap NSCR 11) at centerX 32 / centerY 8,
--     24 x 17 cells of 8 px, under its own frame (NSCR 67 over char 66,
--     palette 63); no zoom, no markings (FlyMap_HandleKeyInput); the cursor
--     moves as on the Pokegear map, one cell per two frames, and the view
--     follows it (ov101_021EC304)
--   * the towns not yet flown to are drawn over from the map's spare blocks
--     (ov101_021EAF40: gMapFlypointParams' src / dest rectangles), Kanto
--     covered by the map card's unlock level, the Safari Zone's corner by
--     whether Goldenrod is open
--   * FLY: each fly point whose FLYPOINT flag is set shows its marker
--     (map OBJ set B: seq 9, 10 where it can be flown to from here, 11 the
--     one under the cursor -- ov101_021EA4D0 / 021EA8A8); one can be flown to
--     from the same region, from the Indigo Plateau, or when it is the Indigo
--     Plateau or Route 26 (ov101_021EA804 / Pokegear_RegionFromCoords); A on
--     it (or a tap) asks "Fly to {place}?" (bank 273 #5) with FLY / CANCEL
--     (#7 / #8) in a touch list menu at tile (11, 4) -- (3, 4) when the
--     cursor is in columns 8-15 (PokegearMap_SpawnFlyContextMenu); the bar
--     says "Where do you want to fly?" (#4) otherwise
--   * CLOSE (#6) at the bottom right (152-184, 194-254), its pressed tiles
--     from rows 24-27; B or CLOSE leaves
--   * the top screen: NSCR 65's back, NSCR 69's panel rows 8-23 (the town
--     map: 8-13, with the panel's layers 81 px down), the region (bank 273
--     #1 Johto / #0 Kanto), the landmark, its flavour text and picture as on
--     the Pokegear (ov101_021EAA0C; the town map shows only the names)
--
-- One screen: L / SELECT shows the top screen, as on the Pokegear.

local Font = require("src.render.Font")
local SecondScreen = require("src.ui.SecondScreen")

local M = {}
M.__index = M
M.isOpaque = true

local W, H = 256, 192
local floor = math.floor
local CX, CY = 32, 8
local MAX_Y = 17
local X_LIMIT = { [0] = 26, 29, 45 }
local BANK = 273
local FLYPOINT_FLAG = 0x9B0
local FLYPOINT_GOLDENROD = 15
local INDIGO_PLATEAU, ROUTE_26 = 58, 30
local KANTO, INDIGO, JOHTO = 0, 1, 2

-- gMapFlypointParams: name map, warp map, flypoint, patch id (255 none),
-- x, y, src x, src y, width, height, dest w, dest h, dest dx, dest dy
M.FLYPOINTS = {
  { 49, 49, 0, 0, 32, 11, 0, 20, 1, 1, 3, 3, 1, 1 },
  { 50, 50, 1, 1, 31, 7, 5, 20, 2, 2, 4, 4, 1, 1 },
  { 51, 51, 2, 2, 32, 2, 10, 20, 2, 2, 4, 4, 1, 1 },
  { 52, 52, 3, 3, 40, 3, 15, 20, 2, 2, 4, 4, 1, 1 },
  { 53, 53, 4, 4, 44, 7, 20, 20, 1, 1, 3, 3, 1, 1 },
  { 54, 54, 5, 5, 40, 9, 25, 20, 2, 2, 4, 4, 1, 1 },
  { 55, 55, 6, 6, 37, 7, 30, 20, 2, 2, 4, 4, 1, 1 },
  { 56, 56, 7, 7, 37, 12, 35, 20, 2, 2, 4, 4, 1, 1 },
  { 57, 57, 8, 8, 32, 15, 0, 24, 1, 1, 3, 3, 1, 1 },
  { 58, 58, 9, 255, 28, 6, 0, 0, 1, 1, 0, 0, 0, 0 },
  { 59, 59, 10, 9, 40, 6, 5, 24, 2, 2, 4, 4, 1, 1 },
  { 60, 60, 11, 10, 21, 12, 11, 25, 1, 1, 1, 1, 0, 0 },
  { 67, 67, 12, 11, 16, 12, 15, 24, 2, 1, 4, 3, 1, 1 },
  { 73, 73, 13, 12, 14, 7, 20, 24, 2, 2, 3, 4, 0, 1 },
  { 74, 74, 14, 13, 12, 14, 25, 24, 2, 1, 4, 3, 1, 1 },
  { 75, 75, 15, 14, 5, 10, 30, 24, 1, 2, 3, 4, 1, 1 },
  { 76, 76, 16, 15, 9, 10, 35, 24, 3, 2, 5, 4, 1, 1 },
  { 77, 77, 17, 16, 8, 7, 0, 28, 2, 2, 4, 4, 1, 1 },
  { 78, 78, 18, 17, 11, 4, 5, 28, 2, 2, 4, 4, 1, 1 },
  { 87, 87, 19, 18, 16, 5, 10, 28, 1, 1, 3, 3, 1, 1 },
  { 89, 89, 21, 19, 20, 4, 15, 28, 2, 2, 4, 4, 1, 1 },
  { 88, 88, 20, 255, 15, 1, 0, 0, 3, 2, 0, 0, 0, 0 },
  { 90, 90, 22, 255, 25, 8, 0, 0, 1, 1, 0, 0, 0, 0 },
  { 174, 174, 30, 255, 2, 8, 0, 0, 2, 2, 0, 0, 0, 0 },
  { 272, 411, 27, 255, 6, 6, 0, 0, 2, 2, 0, 0, 0, 0 },
  { 96, 280, 35, 255, 10, 6, 0, 0, 2, 2, 0, 0, 0, 0 },
  { 124, 30, 33, 255, 28, 7, 0, 0, 1, 2, 0, 0, 0, 0 },
}

-- Pokegear_RegionFromCoords
function M.region(x, y)
  if x > 21 then
    if x == 25 and y == 8 then return JOHTO end
    if (x == 28 and y == 6) or (x == 28 and y > 8 and y < 13) then return INDIGO end
    return KANTO
  end
  return JOHTO
end

-- the spawn row a fly lands at: the first whose fly map is that header
function M.destinationFor(data, warp)
  local Fly = require("src.world.Gen4Fly")
  for _, row in ipairs((data and data.field and data.field.healLocations) or {}) do
    if row.fly and tonumber(row.fly.header) == warp then
      local x, y = Fly.localSpot(data, row.fly.map, row.fly.x, row.fly.y)
      return { map = row.fly.map, x = x, y = y, row = row }
    end
  end
  return nil
end

function M.available(game)
  local art = game and game.data and game.data.gen4_hgss_pokegear_art
  return type(art) == "table" and art.fly_frame ~= nil and art.fly_map ~= nil
end

-- opts.kind "fly" | "town"; opts.onFly(warpHeader); opts.onCancel()
function M.new(game, opts)
  opts = opts or {}
  local Gear = require("src.ui.HgssPokegear")
  local gear = Gear.new(game, { app = 2 })         -- for its art, text, cells
  local self = setmetatable({ game = game, gear = gear, kind = opts.kind or "fly",
    onFly = opts.onFly, onCancel = opts.onCancel, t = 0, step = 0, showTop = false }, M)
  local pg = gear:save()
  self.level = math.max(0, math.min(2, tonumber(pg.mapLevel) or 0))
  self.maxX = X_LIMIT[self.level]
  local mx, my = gear:matrixCell()
  self.px, self.py = mx, my + 2
  self.cx = math.max(2, math.min(self.maxX - 1, self.px))
  self.cy = math.max(2, math.min(MAX_Y, self.py))
  local _, here = gear:header()
  self.hereId = here
  self.curRegion = M.region(mx, my)
  -- the Pokegear map's own location rules (specs, hidden places, follow)
  self.map = require("src.ui.HgssGearMap").new(gear)
  self.map.zoomed = false
  self.map.cx, self.map.cy = self.cx, self.cy
  self.map:recenter()
  self.fade = { kind = "in", n = 0 }
  self:select()
  return self
end

function M:uiSize() return W, H end
function M:wantsFillScale() return true end

-- --------------------------------------------------------------- the rules

function M:flagSet(fp)
  local flags = (self.game.save or {}).flags or {}
  return flags[("FLAG_G4_%04X"):format(FLYPOINT_FLAG + fp)] == true
end

-- ov101_021EA804
function M:canReach(warp, x, y)
  if warp == INDIGO_PLATEAU or warp == ROUTE_26 then return true end
  return self.curRegion == INDIGO or M.region(x, y) == self.curRegion
end

-- ov101_021EA81C: the open fly point covering (x, y) (y without the +2)
function M:flypointAt(x, y)
  for i, f in ipairs(M.FLYPOINTS) do
    if x >= f[5] and x < f[5] + f[9] and y >= f[6] and y < f[6] + f[10] and self:flagSet(f[3]) then return i end
  end
  return nil
end

-- PokegearMap_GetFlyDestinationAtCoord: the warp header, or 0
function M:destinationAt(x, y)
  local i = self:flypointAt(x, y)
  if not i then return 0 end
  local f = M.FLYPOINTS[i]
  if not self:canReach(f[2], x, y) then return 0 end
  return f[2]
end

-- ov101_021EA794 / 021EA8A8: the location under the cursor
function M:select()
  local m = self.map
  m.cx, m.cy = self.cx, self.cy
  self.flyIndex = nil
  if self.kind == "fly" then
    local i = self:flypointAt(self.cx, self.cy - 2)
    if i then
      local f = M.FLYPOINTS[i]
      m.spec = nil
      for _, s in ipairs(self.gear:art().locations or {}) do
        if s.mapId == f[1] and not m:hidden(s.mapId) then m.spec = s; break end
      end
      if self:canReach(f[1], self.cx, self.cy - 2) then self.flyIndex = i end
      return
    end
  end
  m:select()
end

-- ----------------------------------------------------------------- input

function M:moveCursor(input)
  if self.step > 0 then return end
  local moved = false
  if input:isDown("up") then
    if self.cy > 2 then self.cy = self.cy - 1; moved = true end
  elseif input:isDown("down") then
    if self.cy < MAX_Y then self.cy = self.cy + 1; moved = true end
  end
  if input:isDown("left") then
    if self.cx > 2 then self.cx = self.cx - 1; moved = true end
  elseif input:isDown("right") then
    if self.cx < self.maxX - 1 then self.cx = self.cx + 1; moved = true end
  end
  if moved then
    self.step = 2
    self.map.cx, self.map.cy = self.cx, self.cy
    self.map:follow()
    self:select()
  end
end

function M:askFly(warp)
  self.gear:se("SEQ_SE_GS_GEARDECIDE")
  local T = require("src.import.Gen4Text")
  local name = self.map.spec and self.map:landmarkName(self.map.spec.mapId) or ""
  local bufs = self.game.stringBuffers
  local saved = bufs and bufs[1]
  T.buffer(self.game, name)
  self.prompt = self.gear:text(BANK, 5)
  if self.game.stringBuffers then self.game.stringBuffers[1] = saved end
  local tileX = floor((CX + (self.cx - self.map.left) * 8) / 8)
  local x = (tileX < 8 or tileX > 15) and 11 or 3
  local items = { self.gear:text(BANK, 7) or "FLY", self.gear:text(BANK, 8) or "CANCEL" }
  self.menu = require("src.ui.HgssTouchList").new(self.gear, items, x, 4, nil)
  self.warp = warp
end

function M:leave()
  self.gear:se("SEQ_SE_GS_GEARCANCEL")
  self.fade = { kind = "out", n = 0 }
end

function M:finish()
  self.game.stack:pop()
  if self.chosen and self.onFly then self.onFly(self.chosen)
  elseif self.onCancel then self.onCancel() end
end

function M:update()
  self.t = self.t + 1
  self.gear.t = self.t
  local input = self.game.input
  local tap = self.tapAt
  self.tapAt = nil
  local fade = self.fade
  if fade then
    fade.n = fade.n + 1
    if fade.n >= 6 then
      self.fade = nil
      if fade.kind == "out" then return self:finish() end
    end
    return
  end
  if self.step > 0 then self.step = self.step - 1 end
  if self.closePressed then self.closePressed = self.closePressed - 1; if self.closePressed <= 0 then self.closePressed = nil end end
  if self.menu then
    local r = self.menu:update(input, tap)
    if r ~= nil then
      self.menu, self.prompt = nil, nil
      if r == 0 then
        self.chosen = self.warp
        self.fade = { kind = "out", n = 0 }
      end
    end
    return
  end
  if not input then return end
  if not SecondScreen.separate(self.game) and (input:wasPressed("l") or input:wasPressed("select")) then
    self.showTop = not self.showTop
    return
  end
  if tap then return self:touch(tap.x, tap.y) end
  if input:wasPressed("b") then return self:leave() end
  if input:wasPressed("a") and self.kind == "fly" then
    local warp = self:destinationAt(self.cx, self.cy - 2)
    if warp > 0 then return self:askFly(warp) end
  end
  self:moveCursor(input)
end

function M:touch(x, y)
  if y >= 152 and y < 184 and x >= 194 and x < 254 then
    self.closePressed = 8
    return self:leave()
  end
  if not (y >= 16 and y < 144 and x >= 40 and x < 224) then return end
  self.gear:se("SEQ_SE_GS_GEARMAPTOUCH")
  local cx = floor((x - CX) / 8) + self.map.left
  local cy = floor((y - CY) / 8) + self.map.top
  self.cx = math.max(2, math.min(self.maxX - 1, cx))
  self.cy = math.max(2, math.min(MAX_Y, cy))
  self.map.cx, self.map.cy = self.cx, self.cy
  self:select()
  if self.kind == "fly" then
    local warp = self:destinationAt(self.cx, self.cy - 2)
    if warp > 0 then return self:askFly(warp) end
  end
end

local function toLocal(game, x, y)
  local px, py = SecondScreen.toLocal(game, x, y)
  if not px then
    if SecondScreen.separate(game) then return nil end
    local rect = require("src.render.Renderer").uiPresentation
    if rect then px, py = (x - rect.x) / rect.scaleX, (y - rect.y) / rect.scaleY else px, py = x, y end
  end
  if px < 0 or py < 0 or px >= W or py >= H then return nil end
  return floor(px), floor(py)
end

function M:touchpressed(_, x, y)
  local px, py = toLocal(self.game, x, y)
  if not px then return false end
  if not SecondScreen.separate(self.game) and self.showTop then self.showTop = false; return true end
  self.tapAt = { x = px, y = py }
  return true
end
function M:touchmoved() return true end
function M:touchreleased() return true end

-- ------------------------------------------------------------------- draw

local function rgb(c, fallback)
  if type(c) ~= "table" then return fallback end
  return { (c[1] or 0) / 255, (c[2] or 0) / 255, (c[3] or 0) / 255 }
end

function M:ink(which, i, fallback)
  local row = ((self.gear:art().flyInk or {})[which]) or {}
  return rgb(row[i], fallback)
end

-- the map's tile rectangle (src) drawn at map cell (dx, dy)
function M:patch(img, sx, sy, w, h, dx, dy)
  local g = love.graphics
  local iw, ih = img:getDimensions()
  local q = g.newQuad(sx * 8, sy * 8, w * 8, h * 8, iw, ih)
  g.draw(img, q, CX + (dx - self.map.left) * 8, CY + (dy - self.map.top) * 8)
end

function M:drawTouch()
  local g = love.graphics
  local gear = self.gear
  local m = self.map
  g.setColor(0, 0, 0, 1)
  g.rectangle("fill", 0, 0, W, H)
  g.setColor(1, 1, 1, 1)
  local full = gear:img("fly_map", true)
  if full then
    g.setScissor(CX, CY, 24 * 8, 17 * 8)
    local iw, ih = full:getDimensions()
    g.draw(full, g.newQuad(m.left * 8, m.top * 8, 25 * 8, 18 * 8, iw, ih), CX, CY)
    -- ov101_021EAF40
    if self.level == 0 then self:patch(full, 48, 0, 6, 20, 22, 0)
    elseif self.level == 1 then self:patch(full, 54, 0, 3, 20, 29, 0) end
    for _, f in ipairs(M.FLYPOINTS) do
      local skip = f[1] == 75 or f[4] == 255
        or (self.level < 2 and M.region(f[5], f[6]) == KANTO) or self:flagSet(f[3])
      if not skip then self:patch(full, f[7], f[8], f[11], f[12], f[5] - f[13], f[6] - f[14] + 2) end
    end
    if not self:flagSet(FLYPOINT_GOLDENROD) then self:patch(full, 48, 27, 5, 6, 1, 9) end
    if self.hereId == 521 then self:patch(full, 55, 20, 3, 4, 19, 1) end
    if self.hereId == 307 then self:patch(full, 55, 24, 3, 3, 24, 15) end
    g.setScissor()
  end
  local frame = gear:img("fly_frame", true)
  if frame then
    gear:tiles(frame, 0, 0, 32, 24, 0, 0)
    if self.closePressed then gear:tiles(frame, 0, 24, 8, 4, 24, 20) end
  end
  -- the fly points (ov101_021EA4D0)
  if self.kind == "fly" then
    for i, f in ipairs(M.FLYPOINTS) do
      if self:flagSet(f[3]) then
        local x = (f[5] - m.left) * 8 + CX + f[9] * 4
        local y = (f[6] + 2 - m.top) * 8 + CY + f[10] * 4
        if x > CX - 8 and x < CX + 200 and y > CY - 8 and y < CY + 144 then
          local seq = (i == self.flyIndex) and 11 or (self:canReach(f[2], f[5], f[6]) and 10 or 9)
          if not gear:obj("mapB", seq, floor(self.t / 8) % 2, x, y) then gear:obj("mapB", seq, 0, x, y) end
        end
      end
    end
  end
  -- the player and the cursor
  local function at(cx, cy) return CX + (cx - m.left) * 8 + 4, CY + (cy - m.top) * 8 + 4 end
  local px, py = at(self.px, self.py)
  if px > CX and px < CX + 192 and py > CY and py < CY + 136 then
    local girl = ((self.game.save or {}).player or {}).gender == "girl"
    gear:obj("mapB", 1, girl and 1 or 0, px, py)
  end
  if not self.menu then
    local x, y = at(self.cx, self.cy)
    gear:obj("mapB", 0, floor(self.t / 16) % 2, x, y)
  end
  -- the bar: window 7 (0, 21) and CLOSE (25, 21)
  Font.pushStyle({ text = self:ink("main", 3, { 1, 1, 1 }), shadow = self:ink("main", 2, { 0.4, 0.4, 0.4 }) })
  local line = self.prompt or (self.kind == "fly" and gear:text(BANK, 4)) or nil
  if line then Font.draw(line, 8, 21 * 8) end
  Font.popStyle()
  Font.pushStyle({ text = self:ink("main", 3, { 1, 1, 1 }), shadow = self:ink("main", 1, { 0.4, 0.4, 0.4 }) })
  local close = gear:text(BANK, 6) or "CLOSE"
  Font.draw(close, 25 * 8 + floor((48 - Font.width(close)) / 2), 21 * 8)
  Font.popStyle()
  if self.menu then self.menu:draw() end
end

function M:drawTop()
  local g = love.graphics
  local gear = self.gear
  local m = self.map
  g.setColor(1, 1, 1, 1)
  local back = gear:img("fly_top", true)
  if back then g.draw(back, 0, 0) else g.setColor(0, 0, 0, 1); g.rectangle("fill", 0, 0, W, H); g.setColor(1, 1, 1, 1) end
  local info = gear:img("fly_info", true)
  local town = self.kind == "town"
  local dy = town and 81 or 0
  g.push()
  g.translate(0, dy)
  if info then gear:tiles(info, 0, 8, 32, town and 6 or 16, 0, 8) end
  local s = m.spec
  if info then gear:tiles(info, (not town and s and s.block ~= 0) and 8 or 0, 0, 8, 7, 23, 11) end
  if not town and s and s.block ~= 0 then
    local pics = gear:img("fly_landmarks", true)
    local b = s.block - 1
    if pics then gear:tiles(pics, (b % 4) * 7, floor(b / 4) * 7, 7, 7, 24, 11) end
  end
  Font.pushStyle({ text = self:ink("sub", 1, { 1, 1, 1 }), shadow = self:ink("sub", 2, { 0.3, 0.3, 0.3 }) })
  local region = M.region(self.cx, self.cy - 2) == JOHTO and 1 or 0
  Font.draw(gear:text(BANK, region) or "", 8 + 2, 64 + 4)
  if s then
    Font.draw(m:landmarkName(s.mapId), 24, 88 + (town and 1 or 0))
    if not town then
      local flavour = gear:text(BANK, s.flavour) or ""
      local y = 112
      for l in (flavour .. "\n"):gmatch("([^\n]*)\n") do Font.draw(l, 8, y); y = y + 16 end
    end
  end
  Font.popStyle()
  g.pop()
end

function M:draw()
  local g = love.graphics
  local k = 0
  local fade = self.fade
  if fade then k = fade.kind == "in" and (1 - fade.n / 6) or (fade.n / 6) end
  local function dim()
    if k > 0 then g.setColor(0, 0, 0, math.min(1, k)); g.rectangle("fill", 0, 0, W, H); g.setColor(1, 1, 1, 1) end
  end
  if SecondScreen.separate(self.game) then
    self:drawTop(); dim()
    SecondScreen.draw(self.game, function() self:drawTouch(); dim() end)
  elseif self.showTop then
    self:drawTop(); dim()
  else
    self:drawTouch(); dim()
  end
end

return M
