-- In-game Colosseum character walk-rig viewer / vertex painter.
--
-- OPTIONS → CHARACTER MODEL (set a trainer) → CHARACTER VIEWER → OPEN.
-- Limb colors show gait buckets. Paint fixes a bad auto-classify, then
-- START writes cache/trainers/<id>/walk_overrides.lua so the overworld
-- player keeps the fix. tools/paint_walk_override.py reads the sibling
-- walk_debug.txt dump for the same edit on a desktop.

local V = ...
local CharacterWalkCycle = V.require("CharacterWalkCycle")
local PlayerModel = V.require("PlayerModel")
local CharacterModelPick = V.require("CharacterModelPick")

local Viewer = {}
Viewer.__index = Viewer
Viewer.SCREEN = "DRAMATIC_SHAPE:characterWalkViewer"
Viewer.isOpaque = true

local W, H = 160, 144
local BRUSHES = {
  { label = "TORSO", bucket = "torso", side = 1, weight = 0 },
  { label = "ARM L", bucket = "arm", side = -1, weight = 1 },
  { label = "ARM R", bucket = "arm", side = 1, weight = 1 },
  { label = "THIGH L", bucket = "thigh", side = -1, weight = 1 },
  { label = "THIGH R", bucket = "thigh", side = 1, weight = 1 },
  { label = "SHIN L", bucket = "shin", side = -1, weight = 1 },
  { label = "SHIN R", bucket = "shin", side = 1, weight = 1 },
}

local Font = nil
local function font()
  if Font then return Font end
  local ok, F = pcall(require, "src.render.Font")
  if ok then Font = F end
  return Font
end

local function text(str, x, y)
  local F = font()
  if not F then return end
  love.graphics.setColor(0, 0, 0, 1)
  F.draw(str, math.floor(x), math.floor(y))
end

function Viewer.new(game)
  local self = setmetatable({
    game = game,
    yaw = 0.35,
    brush = 2,
    walking = true,
    phase = 0,
    status = "",
    cx = 80,
    cy = 78,
    scale = 55,
    paintRadius = 0.055,
  }, Viewer)
  local id = CharacterModelPick.getCurrentCharacterId()
  if id and id ~= "off" then
    pcall(PlayerModel.loadColosseumCharacter, id)
  end
  self.id = PlayerModel.getCharacterId()
  return self
end

local function pop(self)
  if self.game and self.game.stack and self.game.stack:top() == self then
    self.game.stack:pop()
  end
end

function Viewer:bounds()
  local groups = PlayerModel.getCharacterGroups()
  local minY, maxY, maxR = 0, 1, 0.4
  for _, g in ipairs(groups or {}) do
    for _, v in ipairs(g.baseVertices or {}) do
      local y = v[2] or 0
      if y < minY then minY = y end
      if y > maxY then maxY = y end
      local r = math.abs(v[1] or 0) + math.abs(v[3] or 0)
      if r > maxR then maxR = r end
    end
  end
  local h = math.max(0.01, maxY - minY)
  self.scale = math.min(70, (H - 36) / h)
  self.cy = 20 + (maxY) * self.scale
  self.minY, self.maxY = minY, maxY
end

function Viewer:project(x, y, z)
  local c, s = math.cos(self.yaw), math.sin(self.yaw)
  local rx = x * c + z * s
  local rz = -x * s + z * c
  return self.cx + rx * self.scale, self.cy - y * self.scale, rz
end

function Viewer:paintAt(sx, sy)
  local rig = PlayerModel.getWalkRig()
  local groups = PlayerModel.getCharacterGroups()
  if not (rig and groups) then return 0 end
  local brush = BRUSHES[self.brush]
  local best, bestD = nil, 12
  for gi, g in ipairs(groups) do
    for vi, v in ipairs(g.baseVertices or {}) do
      local px, py = self:project(v[1] or 0, v[2] or 0, v[3] or 0)
      local dx, dy = px - sx, py - sy
      local d = dx * dx + dy * dy
      if d < bestD then
        bestD = d
        best = v
      end
    end
  end
  if not best then return 0 end
  return CharacterWalkCycle.paint(
    rig, groups, best[1] or 0, best[2] or 0, best[3] or 0,
    self.paintRadius, brush.bucket, brush.side, brush.weight
  )
end

function Viewer:save()
  local id = PlayerModel.getCharacterId()
  local rig = PlayerModel.getWalkRig()
  local groups = PlayerModel.getCharacterGroups()
  if not (id and rig) then
    self.status = "NO RIG"
    return
  end
  local ok = select(1, PlayerModel.saveWalkOverrides(id))
  pcall(CharacterWalkCycle.writeDebug, id, groups, rig)
  self.status = ok and "SAVED" or "SAVE FAIL"
end

function Viewer:update()
  local input = self.game and self.game.input
  if not (input and input.wasPressed) then return end
  if input:wasPressed("b") then pop(self); return end
  if input:wasPressed("start") then self:save(); return end
  if input:wasPressed("select") then
    self.walking = not self.walking
    return
  end
  if input:wasPressed("up") then
    self.brush = self.brush - 1
    if self.brush < 1 then self.brush = #BRUSHES end
  elseif input:wasPressed("down") then
    self.brush = self.brush + 1
    if self.brush > #BRUSHES then self.brush = 1 end
  end
  if input:isDown("left") then self.yaw = self.yaw - 0.06 end
  if input:isDown("right") then self.yaw = self.yaw + 0.06 end
  if input:wasPressed("a") then
    local n = self:paintAt(self.cx, self.cy)
    self.status = ("PAINT %d"):format(n)
  end
  if self.walking then
    self.phase = self.phase + 0.12
  end
  if love and love.mouse and love.mouse.isDown then
    local downOk, down = pcall(love.mouse.isDown, 1)
    if downOk and down then
      local gw, gh = love.graphics.getWidth(), love.graphics.getHeight()
      local mx, my = love.mouse.getPosition()
      if gw and gh and gw > 0 and gh > 0 then
        local sx, sy = mx * W / gw, my * H / gh
        if sx >= 0 and sx <= W and sy >= 0 and sy <= H then
          self:paintAt(sx, sy)
          self.status = "PAINT"
        end
      end
    end
  end
end

function Viewer:draw()
  love.graphics.setColor(0.93, 0.94, 0.90, 1)
  love.graphics.rectangle("fill", 0, 0, W, H)
  self:bounds()

  local rig = PlayerModel.getWalkRig()
  local groups = PlayerModel.getCharacterGroups()
  local id = PlayerModel.getCharacterId() or "?"
  if not (rig and groups) then
    text("NO CHARACTER", 24, 64)
    text("SET MODEL FIRST", 16, 80)
    love.graphics.setColor(1, 1, 1, 1)
    return
  end

  local blend = self.walking and 1 or 0
  for gi, g in ipairs(groups) do
    local posed = nil
    if blend > 0 then
      posed = CharacterWalkCycle.apply(rig, gi, g, self.phase, blend, nil)
    end
    local src = posed or g.baseVertices
    local buckets = rig.groups[gi]
    for vi, v in ipairs(src or {}) do
      local b = buckets and buckets[vi]
      local col = CharacterWalkCycle.bucketColor(b and b.bucket, b and b.side)
      local px, py = self:project(v[1] or 0, v[2] or 0, v[3] or 0)
      love.graphics.setColor(col[1], col[2], col[3], 1)
      love.graphics.rectangle("fill", math.floor(px), math.floor(py), 1, 1)
    end
  end

  love.graphics.setColor(0.06, 0.05, 0.09, 1)
  love.graphics.rectangle("fill", self.cx - 2, self.cy - 2, 5, 1)
  love.graphics.rectangle("fill", self.cx, self.cy - 3, 1, 5)

  local brush = BRUSHES[self.brush]
  text((id):upper(), 4, 2)
  text(brush.label, 4, 12)
  text(self.walking and "WALK" or "IDLE", 120, 2)
  if self.status ~= "" then text(self.status, 100, 12) end
  text("A PAINT  START SAVE", 4, 128)
  text("B BACK  SEL WALK", 4, 136)
  love.graphics.setColor(1, 1, 1, 1)
end

function Viewer.row()
  return {
    id = Viewer.SCREEN,
    label = "CHARACTER VIEWER",
    value = function()
      local id = CharacterModelPick.getCurrentCharacterId()
      if not id or id == "off" then return "SET MODEL" end
      return "OPEN"
    end,
    activate = function(game)
      local id = CharacterModelPick.getCurrentCharacterId()
      if not id or id == "off" then return end
      pcall(PlayerModel.loadColosseumCharacter, id)
      if game and game.stack then
        game.stack:push(Viewer.new(game))
      end
    end,
  }
end

return Viewer
