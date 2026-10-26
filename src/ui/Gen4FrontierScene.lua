-- A BATTLE FRONTIER SCENE (overlay104's BattleFrontier task): the scene's
-- backdrop, the people its script places and walks, the Pokemon picture it
-- shows, and its own script runner -- src/script/Gen4FrontierVM.lua.
--
-- Pushed by the field's `launchbattlefrontierscene`, which yields until the
-- scene exits (FrontierScrCmd_ExitFrontier). A scene change inside the
-- script (ChangeSceneWithinScript) swaps the backdrop and carries on; a
-- script change (ChangeScript) starts the new scene's entry point.
--
-- The screen is the top one, 256 x 192. The backdrop is the scene's main BG,
-- composed whole (src/import/Gen4FrontierArt.lua); the camera follows the
-- player's object, clamped to the backdrop -- the cartridge scrolls its BGs
-- in the scene's own setup and per movement, and this is its effect, not
-- its arithmetic.

local ScriptRunner = require("src.script.ScriptRunner")
local Commands = require("src.script.Commands")
local VM = require("src.script.Gen4FrontierVM")

local Scene = {}
Scene.__index = Scene
Scene.isOpaque = true

-- sFrontierScenes: [scene] = { member, text bank, backdrop key }
Scene.SCENES = {
  [3] = { member = 1, bank = 365, art = "factory_corridor" },  -- FRONTIER_SCENE_FACTORY_CORRIDOR
  [4] = { member = 1, bank = 365, art = "factory_battle_room" }, -- FRONTIER_SCENE_FACTORY_BATTLE_ROOM
  [9] = { member = 3, bank = 549, art = "hall_corridor" },     -- FRONTIER_SCENE_HALL_CORRIDOR
  [10] = { member = 3, bank = 549, art = "hall_battle_room" }, -- FRONTIER_SCENE_HALL_BATTLE_ROOM
  [11] = { member = 0, bank = 200, art = "castle_corridor" },  -- FRONTIER_SCENE_CASTLE_CORRIDOR
  [12] = { member = 0, bank = 200, art = "castle_battle_room" }, -- FRONTIER_SCENE_CASTLE_BATTLE_ROOM
  [13] = { member = 0, bank = 200, art = "castle_passage" },   -- FRONTIER_SCENE_13 (the Pass's way round)
  [15] = { member = 2, bank = 537, art = "arcade_corridor" },  -- FRONTIER_SCENE_ARCADE_CORRIDOR
  [16] = { member = 2, bank = 537, art = "arcade_battle_room" }, -- FRONTIER_SCENE_ARCADE_BATTLE_ROOM
}
-- HEARTGOLD / SOULSILVER's (overlay 80's ov80_0223B724, 0x28 a scene: the
-- /a/1/8/2 member at +0xC, the message bank at +0xE). Same members as
-- Platinum's; the tower's corridor and rooms run here too, since HGSS has no
-- field battle room (src/script/HgssFrontierTower.lua).
Scene.HGSS_SCENES = {
  [3] = { member = 1, bank = 195, art = "factory_corridor" },
  [4] = { member = 1, bank = 195, art = "factory_battle_room" },
  [5] = { member = 6, bank = 96, art = "tower_corridor" },
  [6] = { member = 7, bank = 96, art = "tower_multi_corridor" },
  [7] = { member = 8, bank = 97, art = "tower_battle_room" },
  [8] = { member = 9, bank = 98, art = "tower_multi_battle_room" },
  [9] = { member = 3, bank = 441, art = "hall_corridor" },
  [10] = { member = 3, bank = 441, art = "hall_battle_room" },
  [11] = { member = 0, bank = 32, art = "castle_corridor" },
  [12] = { member = 0, bank = 32, art = "castle_battle_room" },
  [13] = { member = 0, bank = 32, art = "castle_passage" },
  [15] = { member = 2, bank = 426, art = "arcade_corridor" },
  [16] = { member = 2, bank = 426, art = "arcade_battle_room" },
}
function Scene.specFor(id)
  local okB, Bands = pcall(require, "src.import.Gen4ScriptBands")
  if okB and Bands.family == "hgss" then return Scene.HGSS_SCENES[id] end
  return Scene.SCENES[id]
end
Scene.PLAYER_LOCAL = 31   -- `32 - 1`: the object id FrontierScrCmd_24 gives the player
Scene.STEP = 16           -- a walk step, in pixels
Scene.FRAMES = { walk = 8, slow = 16, fast = 4 }

function Scene:uiSize() return 256, 192 end
function Scene:wantsFillScale() return true end

-- opts = { scene, entry (label, default the member's first), onExit }
function Scene.new(game, opts)
  require("src.script.Gen4FrontierScrCmds")
  -- the facilities register their own commands with the engine
  require("src.script.Gen4BattleHall")
  require("src.script.Gen4BattleFactory")
  require("src.script.Gen4BattleCastle")
  require("src.script.Gen4BattleArcade")
  require("src.script.HgssFrontierTower")
  local self = setmetatable({ game = game, data = game.data, objects = {}, order = {},
    images = {}, monPics = {}, onExit = opts.onExit }, Scene)
  self.runner = ScriptRunner.new(game, nil)
  self:setScene(opts.scene)
  local spec = Scene.specFor(opts.scene)
  local entry = opts.entry or (spec and VM.entryLabel(game.data, spec.member, 0))
  local rows = spec and entry and VM.compile(game.data, spec.member, entry, spec.bank)
  if rows then
    self.runner:run(rows, { frontierScene = self, overworld = game.overworld })
  else
    require("src.core.Logger").warn("gen4 frontier: scene %s has no script in this cache "
      .. "(tools/gen4_frontier_scripts_extract.lua) -- leaving it", tostring(opts.scene))
    self.exitPending = true
  end
  return self
end

function Scene:setScene(id)
  self.sceneId = id
  self.spec = Scene.specFor(id) or {}
  self.backdrop = nil
  local index = self.data and self.data.gen4_frontier_art
  local rec = index and self.spec.art and index[self.spec.art]
  if rec then
    local ok, img = pcall(require("src.render.Assets").image, rec.path)
    self.backdrop = ok and img or nil
  end
end

-- ------------------------------------------------------------ the objects --

local FACING = { [0] = "up", "down", "left", "right" }
function Scene:addObject(row, gfx)
  local data = self.data
  local key = require("src.world.OverworldController").gen4SpriteFor(data, gfx)
  local NPC = require("src.world.NPC")
  local SpriteRenderer = require("src.render.SpriteRenderer")
  local sprite
  if key then
    local ok, s = pcall(SpriteRenderer.new, NPC.resolveSpriteDef(data, key), row.id)
    sprite = ok and s or nil
  end
  local o = { id = row.id, gfx = gfx, x = row.x - 8, y = row.y - 16, facing = FACING[row.dir] or "down",
              sprite = sprite, queue = {}, phase = 0, hidden = row.anchor and true or false }
  if self.objects[o.id] == nil then self.order[#self.order + 1] = o.id end
  self.objects[o.id] = o
  return o
end

function Scene:removeObject(id)
  self.objects[id] = nil
  for i = #self.order, 1, -1 do if self.order[i] == id then table.remove(self.order, i) end end
end

local DIRS = { north = { 0, -1, "up" }, south = { 0, 1, "down" }, west = { -1, 0, "left" }, east = { 1, 0, "right" } }
function Scene:move(id, list)
  local o = self.objects[id]
  if not o then return end
  for _, step in ipairs(list or {}) do
    local name = step.name or ""
    local dir = name:match("_(%a+)$")
    local d = DIRS[dir or ""]
    local count = math.max(1, step.count or 1)
    if name:find("^face_") and d then
      o.queue[#o.queue + 1] = { face = d[3] }
    elseif name:find("^walk_on_spot") and d then
      for _ = 1, count do o.queue[#o.queue + 1] = { face = d[3], frames = Scene.FRAMES.walk, spot = true } end
    elseif name:find("^walk") and d then
      local speed = (name:find("slow") and Scene.FRAMES.slow) or (name:find("fast") and Scene.FRAMES.fast)
                    or Scene.FRAMES.walk
      for _ = 1, count do
        o.queue[#o.queue + 1] = { face = d[3], dx = d[1] * Scene.STEP, dy = d[2] * Scene.STEP, frames = speed }
      end
    elseif name:find("delay") then
      local n = tonumber(name:match("(%d+)")) or 1
      o.queue[#o.queue + 1] = { frames = n * count }
    elseif name == "warp_out" then
      o.queue[#o.queue + 1] = { frames = 8 }
      o.queue[#o.queue + 1] = { hide = true }
    elseif name == "warp_in" then
      o.queue[#o.queue + 1] = { show = true }
      o.queue[#o.queue + 1] = { frames = 8 }
    elseif name:find("invisible") then
      o.queue[#o.queue + 1] = { hide = true }
    elseif name:find("visible") then
      o.queue[#o.queue + 1] = { show = true }
    end
  end
end

function Scene:moving()
  for _, o in pairs(self.objects) do
    if o.step or #o.queue > 0 then return true end
  end
  return false
end

function Scene:stepObjects()
  for _, o in pairs(self.objects) do
    if not o.step and #o.queue > 0 then
      local st = table.remove(o.queue, 1)
      if st.face then o.facing = st.face end
      if st.hide then o.hidden = true end
      if st.show then o.hidden = false end
      if st.frames then o.step = { t = 0, n = st.frames, dx = st.dx or 0, dy = st.dy or 0,
                                   x0 = o.x, y0 = o.y, spot = st.spot } end
    end
    local s = o.step
    if s then
      s.t = s.t + 1
      local f = math.min(1, s.t / s.n)
      o.x, o.y = s.x0 + s.dx * f, s.y0 + s.dy * f
      o.phase = (s.dx ~= 0 or s.dy ~= 0 or s.spot) and math.floor(f * 4) % 4 or 0
      if s.t >= s.n then o.step = nil; o.phase = 0 end
    end
  end
end

-- --------------------------------------------------------------- the loop --

function Scene:update(dt)
  self:stepObjects()
  if self.fadeTarget and self.fade ~= self.fadeTarget then
    local step = self.fadeStep or 0.1
    if self.fade < self.fadeTarget then self.fade = math.min(self.fadeTarget, self.fade + step)
    else self.fade = math.max(self.fadeTarget, self.fade - step) end
  end
  self.runner:update()
  if not self.runner:isRunning() and self.pendingRows and not self.exitPending then
    local rows = self.pendingRows
    self.pendingRows = nil
    self.runner:run(rows, { frontierScene = self, overworld = self.game.overworld })
  end
  if not self.runner:isRunning() and not self.exitPending then
    -- a script that stopped without leaving the frontier (End) leaves the scene
    self.exitPending = true
  end
  if self.exitPending and not self.closed then
    self.closed = true
    if self.game.stack:top() == self then self.game.stack:pop() end
    if self.onExit then self.onExit() end
  end
end

function Scene:camera()
  local img = self.backdrop
  local w, h = img and img:getWidth() or 256, img and img:getHeight() or 192
  local p
  for _, o in pairs(self.objects) do if o.isPlayer then p = o end end
  local cx, cy = 128, 96
  if p then cx, cy = p.x + 8, p.y + 16 end
  local x = math.max(0, math.min(w - 256, cx - 128))
  local y = math.max(0, math.min(h - 192, cy - 96))
  return math.floor(x), math.floor(y)
end

function Scene:draw()
  local g = love.graphics
  g.setColor(0, 0, 0, 1)
  g.rectangle("fill", 0, 0, 256, 192)
  g.setColor(1, 1, 1, 1)
  local camX, camY = self:camera()
  if self.backdrop then g.draw(self.backdrop, -camX, -camY) end
  -- people, back to front
  local list = {}
  for _, id in ipairs(self.order) do
    local o = self.objects[id]
    if o and not o.hidden then list[#list + 1] = o end
  end
  table.sort(list, function(a, b) return a.y < b.y end)
  for _, o in ipairs(list) do
    if o.sprite then
      pcall(o.sprite.draw, o.sprite, o.x, o.y, camX, camY, o.facing, o.phase, false)
    end
  end
  for _, pic in pairs(self.monPics) do
    if pic.image then g.draw(pic.image, pic.x - camX - 40, pic.y - camY - 40) end
  end
  -- a facility's own window over the scene (the Castle's CP)
  if self.infoWindow then pcall(self.infoWindow) end
  if self.fade and self.fade > 0 then
    g.setColor(0, 0, 0, self.fade)
    g.rectangle("fill", 0, 0, 256, 192)
    g.setColor(1, 1, 1, 1)
  end
end

return Scene
