-- BLACK / WHITE'S TOWN MAP (the Town Map key item, field use 2).
--
-- The region is the ROM's own painting and the places are the ROM's own
-- table (src/import/Gen5TownMapArt.lua, `gen5_town_map`): 61 places, each a
-- zone and an icon point on the 256 x 192 map. The screen shows where the
-- player is (the place whose zone is the map in hand -- indoors, the last
-- outdoor place stood in), a cursor the D-pad moves to the nearest place in
-- that direction, and the place's name in a bar along the bottom.
--
-- The roads, town rings and landmark squares are the ROM's BG2 layer, baked
-- into the region image; the red arrow on the player's place and the cursor
-- ring are the app's own sprites (cell bank 12, cells 7 and 11).
--
-- FLY (opts.mode == "fly", src/world/Gen5Fly.lua): the cursor walks the
-- open fly points only, and A flies to the one under it (opts.onFly(dest)).
--
-- Not yet the cartridge's: its touch-screen half (the place card and its
-- buildings) and the route highlighting.

local Assets = require("src.render.Assets")
local Font = require("src.render.Font")
local Gen5Fly = require("src.world.Gen5Fly")

local M = {}
M.__index = M
M.isOpaque = true

local W, H = 256, 192

function M:uiSize() return W, H end
function M:wantsFillScale() return true end
function M:wantsEdgeBleed() return false end

local function record(game) return game and game.data and game.data.gen5_town_map end

function M.available(game)
  local r = record(game)
  return r ~= nil and r.image ~= nil and r.locations ~= nil
end

-- the zone number of the map the player is on
local function currentZone(game)
  local ow = game and game.overworld
  local def = ow and ow.map and ow.map.def
  local h = def and tonumber(def.header)
  if h then return h end
  local id = ow and ow.map and ow.map.id
  return id and tonumber(tostring(id):match("^Z(%d+)$"))
end

-- remembered on every outdoor arrival, so an indoor map still has a place
function M.remember(game, zone)
  local r = record(game)
  if not (r and game.save and zone) then return end
  for _, loc in ipairs(r.locations) do
    if loc.zone == zone then
      game.save.gen5TownMapZone = zone
      Gen5Fly.visit(game.save, zone)
      return
    end
  end
end

function M.new(game, opts)
  local self = setmetatable({ game = game, frame = 0, onCancel = opts and opts.onCancel,
                              fly = opts and opts.mode == "fly", onFly = opts and opts.onFly }, M)
  local r = record(game)
  self.locations = r and r.locations or {}
  local here = currentZone(game)
  M.remember(game, here)
  local zone = here
  local found
  for i, loc in ipairs(self.locations) do if loc.zone == zone then found = i end end
  if not found and game.save and game.save.gen5TownMapZone then
    for i, loc in ipairs(self.locations) do if loc.zone == game.save.gen5TownMapZone then found = i end end
  end
  self.here = found
  self.cursor = found or 1
  if self.fly and not self:pickable(self.cursor) then
    for i in ipairs(self.locations) do
      if self:pickable(i) then self.cursor = i break end
    end
  end
  return self
end

function M:nameOf(loc)
  local maps = self.game.data.maps or {}
  local def = maps[("Z%03d"):format(loc.zone)] or maps["Z" .. loc.zone]
  local label = def and (def.label or def.name)
  if type(label) == "string" and label ~= "" then return (label:gsub("\n.*", "")) end
  return ("Zone %d"):format(loc.zone)
end

function M:close()
  self.game.stack:pop()
  if self.onCancel then self.onCancel() end
end

-- in fly mode, only the open fly points take the cursor
function M:pickable(i)
  if not self.fly then return true end
  return Gen5Fly.open(self.game.data, self.game.save, self.locations[i])
end

function M:choose()
  local loc = self.locations[self.cursor]
  local dest = loc and self:pickable(self.cursor) and Gen5Fly.destination(self.game.data, loc)
  if not dest then
    pcall(function() require("src.core.Sound").play(self.game.data, "SEQ_SE_BEEP") end)
    return
  end
  pcall(function() require("src.core.Sound").play(self.game.data, "SEQ_SE_DECIDE1") end)
  self.game.stack:pop()
  if self.onFly then self.onFly(dest, loc) end
end

-- the nearest place lying in a direction from the cursor
function M:step(dx, dy)
  local cur = self.locations[self.cursor]
  if not cur then return end
  local best, bestScore
  for i, loc in ipairs(self.locations) do
    if i ~= self.cursor and self:pickable(i) then
      local ox, oy = loc.x - cur.x, loc.y - cur.y
      local along = ox * dx + oy * dy
      if along > 0 then
        local across = math.abs(ox * dy - oy * dx)
        local score = along + across * 2
        if not bestScore or score < bestScore then best, bestScore = i, score end
      end
    end
  end
  if best then
    self.cursor = best
    pcall(function() require("src.core.Sound").play(self.game.data, "SEQ_SE_SELECT1") end)
  end
end

function M:update()
  self.frame = self.frame + 1
  local input = self.game.input
  if not input then return end
  if input:wasPressed("b") then return self:close() end
  if input:wasPressed("start") then return self:close() end
  if self.fly and input:wasPressed("a") then return self:choose() end
  if input:wasPressed("up") then self:step(0, -1)
  elseif input:wasPressed("down") then self:step(0, 1)
  elseif input:wasPressed("left") then self:step(-1, 0)
  elseif input:wasPressed("right") then self:step(1, 0) end
end

function M:draw()
  local g = love.graphics
  local r = record(self.game)
  g.setColor(0, 0, 0, 1)
  g.rectangle("fill", 0, 0, W, H)
  local img = r and r.image and Assets.image(r.image.path)
  if img then
    g.setColor(1, 1, 1, 1)
    g.draw(img, 0, 0)
  end
  -- the player's place: the red arrow, its tip on the place
  local arrow = r and r.arrow and Assets.image(r.arrow.path)
  local here = self.here and self.locations[self.here]
  if here then
    if arrow then
      g.setColor(1, 1, 1, 1)
      g.draw(arrow, here.x - r.arrow.ox, here.y - r.arrow.oy)
    elseif math.floor(self.frame / 16) % 2 == 0 then
      g.setColor(1, 0.25, 0.2, 1)
      g.circle("fill", here.x, here.y, 3)
    end
  end
  -- the cursor ring, pulsing
  local cur = self.locations[self.cursor]
  if cur then
    local ring = r and r.cursor and Assets.image(r.cursor.path)
    if ring then
      local a = 0.85 + 0.15 * math.sin(self.frame / 6)
      g.setColor(1, 1, 1, a)
      g.draw(ring, cur.x - r.cursor.ox, cur.y - r.cursor.oy)
    else
      local s = 6 + (math.floor(self.frame / 8) % 2)
      g.setColor(1, 0.9, 0.2, 1)
      g.setLineWidth(1)
      g.rectangle("line", cur.x - s + 0.5, cur.y - s + 0.5, s * 2, s * 2)
    end
    -- the name bar
    g.setColor(0.08, 0.1, 0.16, 0.85)
    g.rectangle("fill", 0, H - 18, W, 18)
    g.setColor(1, 1, 1, 1)
    local name = self:nameOf(cur)
    Font.draw(name, math.floor((W - Font.width(name)) / 2), H - 15)
  end
  g.setColor(1, 1, 1, 1)
end

return M
