-- Terrarium effects on Platinum's own 3D world.
--
-- Gen 1-3 voxelize tilesets into a diorama. Gen 4 already IS a 3D world:
-- NSBMD chunks, BDHC height, and Gen4View / Gen4Camera. Replacing that
-- pass with VoxelScene would throw the cartridge's meshes away. This module
-- therefore never owns the world: it declines the drawWorld pipeline so
-- Gen4Ground keeps the frame, then paints Terrarium grass / wind / weather
-- / VFX into the engine's live colour+depth target using that camera.
--
-- Glass panes on Sinnoh houses are already in the NSBMD textures. The
-- tileset GlassMask scan is for 8px GB art and is not run here.

local V = ...

local Host = {
  installed = false,
}

local GRASS_BEHAVIOURS = {
  TALL_GRASS = true,
  VERY_TALL_GRASS = true,
  MUD_WITH_GRASS = true,
  MUD_DEEP_WITH_GRASS = true,
}

local grassCache = { mapId = nil, mesh = nil, at = -1 }

local function engineRequire(name)
  local req = (V and V.engineRequire) or require
  local ok, mod = pcall(req, name)
  return ok and mod or nil
end

local function game()
  return engineRequire("src.core.Game")
end

function Host.generation()
  local GameVersion = engineRequire("src.core.GameVersion")
  if GameVersion and type(GameVersion.generation) == "function" then
    local ok, n = pcall(GameVersion.generation)
    if ok and tonumber(n) then return tonumber(n) end
  end
  return nil
end

function Host.isGen4()
  if Host.generation() == 4 then return true end
  local g = game()
  local data = g and g.data
  return data and data.gen4_terrain ~= nil
end

function Host.groundOf(state)
  state = state or (game() and game().overworld)
  local map = state and state.map
  local renderer = map and map.renderer
  return renderer and renderer.gen4Ground or nil
end

function Host.isState(state)
  return Host.groundOf(state) ~= nil
end

function Host.isMap(map)
  return map and map.renderer and map.renderer.gen4Ground ~= nil
end

-- Permission / behaviour byte for a 16px cell. Gen 4 stores that in
-- def.blocks (255 is the reserved blocked cell, not a behaviour).
function Host.behaviourAt(map, cx, cy)
  if not (map and map.def) then return nil end
  local def = map.def
  local w = tonumber(def.width) or 0
  local h = tonumber(def.height) or 0
  cx, cy = tonumber(cx), tonumber(cy)
  if not (cx and cy and w > 0) then return nil end
  if cx < 0 or cy < 0 or cx >= w or cy >= h then return nil end
  if def.blocks then
    local v = def.blocks[cy * w + cx + 1]
    if v == nil or v == 255 then return nil end
    return v
  end
  if type(map.cellBehaviour) == "function" then
    local ok, b = pcall(map.cellBehaviour, map, cx, cy)
    if ok then return b end
  end
  return nil
end

function Host.behaviourName(value)
  local Gen4Behaviors = engineRequire("src.import.Gen4Behaviors")
  if Gen4Behaviors and type(Gen4Behaviors.name) == "function" then
    local ok, name = pcall(Gen4Behaviors.name, value)
    if ok then return name end
  end
  return nil
end

function Host.isTallGrass(map, cx, cy)
  local name = Host.behaviourName(Host.behaviourAt(map, cx, cy))
  return name and GRASS_BEHAVIOURS[name] == true
end

-- World-pixel project through the camera that actually drew this frame.
-- Matches Voxel3D.project's (sx, sy, scale) contract so WindFX / Weather /
-- AmbientLife / Vfx can run unchanged.
function Host.project(wx, wy, wz)
  local ground = Host._drawGround
  if not ground then return nil end
  wy = tonumber(wy) or 0
  wx, wz = tonumber(wx) or 0, tonumber(wz) or 0
  local view = ground.view3d
  if view and view.isFree and view:isFree() and type(view.project) == "function" then
    local vw = ground.freeW or Host._vw or 1
    local vh = ground.freeH or Host._vh or 1
    local sx, sy, scale = view:project(
      wx + (ground.offsetX or 0), wy, wz + (ground.offsetY or 0), vw, vh)
    return sx, sy, scale
  end
  local Gen4Camera = engineRequire("src.render.Gen4Camera")
  if not (Gen4Camera and Gen4Camera.project) then return nil end
  local cam = ground.camera or Gen4Camera.forMap(ground.def)
  local ow = game() and game().overworld
  local c = ow and ow.camera
  local camX = (c and c.x or 0) + (ground.offsetX or 0)
  local camY = (c and c.y or 0) + (ground.offsetY or 0)
  local dx = wx + (ground.offsetX or 0) - camX
  local dz = wz + (ground.offsetY or 0) - camY
  local sx, sy = Gen4Camera.project(cam, dx, wy, dz)
  return sx, sy, 1
end

local function bindVoxelCamera(ground)
  local Voxel3D = V.require("Voxel3D")
  local view = ground.view3d
  if not (view and view.isFree and view:isFree()) then
    Voxel3D.camera = nil
    return false
  end
  local fx, fy, fz = 0, 0, -1
  if type(view.forward) == "function" then
    fx, fy, fz = view:forward()
  end
  local fov = tonumber(view.fovY) or 50
  if type(view.effectiveFovY) == "function" then
    fov = view:effectiveFovY(ground.freeH or 192) or fov
  end
  Voxel3D.camera = {
    eye = { view.x, view.y, view.z },
    focus = { view.x + fx, view.y + fy, view.z + fz },
    fov = math.rad(fov),
  }
  Voxel3D.eye = Voxel3D.camera.eye
  Voxel3D.focus = Voxel3D.camera.focus
  local vw = ground.freeW or 1
  local vh = ground.freeH or 1
  Voxel3D.vp = view:matrix(vw, vh)
  return true
end

local function rebuildGrass(state, ground)
  local map = state and state.map
  if not map then return nil end
  local Grass3D = V.require("Grass3D")
  if not (Grass3D and Grass3D.available and Grass3D.available()) then
    grassCache.mesh = nil
    return nil
  end
  local player = state.player
  local now = love and love.timer and love.timer.getTime() or 0
  local cx = player and math.floor((player.px or 0) / 16) or 0
  local cy = player and math.floor((player.py or 0) / 16) or 0
  local key = (map.id or "") .. ":" .. cx .. ":" .. cy
  if grassCache.mapId == key and grassCache.mesh and (now - (grassCache.at or 0)) < 0.35 then
    return grassCache.mesh
  end
  local instances = {}
  local radius = 12
  local x0 = math.max(0, cx - radius)
  local y0 = math.max(0, cy - radius)
  local x1 = math.min((map.widthCells or map.def.width or 0) - 1, cx + radius)
  local y1 = math.min((map.heightCells or map.def.height or 0) - 1, cy + radius)
  for ty = y0, y1 do
    for tx = x0, x1 do
      if Host.isTallGrass(map, tx, ty) then
        local gz = 0
        if ground.groundY then
          gz = ground:groundY(tx * 16 + 8, ty * 16 + 8) or 0
        end
        local inst = Grass3D.instanceForTile(tx * 2, ty * 2, gz)
        inst.wx = tx * 16
        inst.wz = ty * 16
        inst.gz = gz
        instances[#instances + 1] = inst
      end
    end
  end
  local mesh = nil
  if #instances > 0 then
    mesh = Grass3D.meshFromInstances(instances)
  end
  grassCache.mapId, grassCache.mesh, grassCache.at = key, mesh, now
  return mesh
end

local function drawGrass(state, ground)
  local mesh = rebuildGrass(state, ground)
  if not mesh then return end
  local Voxel3D = V.require("Voxel3D")
  if not bindVoxelCamera(ground) then return end
  local view = ground.view3d
  local vw = ground.freeW or Host._vw or 1
  local vh = ground.freeH or Host._vh or 1
  local player = state and state.player
  local cx = (player and player.px or 0) + 8 + (ground.offsetX or 0)
  local cz = (player and player.py or 0) + 8 + (ground.offsetY or 0)
  local Wind = V.require("Wind")
  local sway = (Wind.amount and Wind.amount()) or 0
  local Grass3D = V.require("Grass3D")
  if Grass3D and Grass3D.meta then
    local okm, m = pcall(Grass3D.meta)
    if okm and m and tonumber(m.height) then Voxel3D.grassH = m.height end
  end
  pcall(function()
    if not Voxel3D.beginScene(vw, vh, cx, cz, vw, vh, nil, "current") then
      return
    end
    -- beginScene rebuilds vp from Voxel3D.camera. Restore Gen4View's matrix
    -- so tufts sit in the same space as the NSBMD chunks already in this
    -- framebuffer.
    if view and type(view.matrix) == "function" then
      Voxel3D.vp = view:matrix(vw, vh)
    end
    Voxel3D.draw(mesh, Grass3D.texture and Grass3D.texture() or nil,
                 nil, 0, nil, sway)
    Voxel3D.endScene()
  end)
end

-- Cartridge / oblique field camera: no Gen4View matrix, so stamp tufts as
-- projected billboards on the world canvas after sprites.
local function drawGrassBillboards(state, ground, project)
  if not (state and state.map and project) then return end
  local Grass3D = V.require("Grass3D")
  local tex = Grass3D and Grass3D.texture and Grass3D.texture() or nil
  if not tex then return end
  local g = love.graphics
  local player = state.player
  local cx = player and math.floor((player.px or 0) / 16) or 0
  local cy = player and math.floor((player.py or 0) / 16) or 0
  local radius = 8
  local map = state.map
  local x0 = math.max(0, cx - radius)
  local y0 = math.max(0, cy - radius)
  local x1 = math.min((map.widthCells or map.def.width or 0) - 1, cx + radius)
  local y1 = math.min((map.heightCells or map.def.height or 0) - 1, cy + radius)
  g.setColor(1, 1, 1, 1)
  for ty = y0, y1 do
    for tx = x0, x1 do
      if Host.isTallGrass(map, tx, ty) then
        local gz = ground.groundY and ground:groundY(tx * 16 + 8, ty * 16 + 8) or 0
        local sx, sy, ps = project(tx * 16 + 8, gz + 8, ty * 16 + 8)
        if sx then
          local s = math.max(8, 16 * (ps or 1))
          g.draw(tex, sx, sy, 0, s / tex:getWidth(), s / tex:getHeight(),
                 tex:getWidth() * 0.5, tex:getHeight())
        end
      end
    end
  end
end

-- 2D field FX through Host.project. Called while the gen4 colour target is
-- still bound (free pass) or after sprites on the world canvas (field).
function Host.overlayFx(state, ground, sw, sh, scale)
  if not Host.effectsOn() then return end
  Host._drawGround = ground
  Host._vw, Host._vh = sw, sh
  local Voxel3D = V.require("Voxel3D")
  local prevVp = Voxel3D.vp
  -- Weather / WindFX / AmbientLife call Voxel3D.project when given that
  -- function. Hand Host.project so the engine camera is the only lens.
  local project = Host.project
  local view = ground.view3d
  local free = view and view.isFree and view:isFree()
  if not free then
    pcall(drawGrassBillboards, state, ground, project)
  end
  pcall(function() V.require("AmbientLife").draw(project, scale or 1) end)
  pcall(function() V.require("Vfx").draw(project, scale or 1) end)
  pcall(function() V.require("WindFX").draw(project, scale or 1) end)
  pcall(function() V.require("Interiors").draw(project, scale or 1) end)
  pcall(function() V.require("HiddenItems").draw(project, scale or 1) end)
  pcall(function()
    V.require("Weather").draw(project, scale or 1, sw, sh)
  end)
  Voxel3D.vp = prevVp
  Host._drawGround = nil
end

function Host.effectsOn()
  local ok, Voxel = pcall(V.require, "VoxelState")
  return ok and Voxel and Voxel.active and Voxel.active() == true
end

-- Called from the voxel pipeline's drawWorld when this is a Gen 4 map.
-- The pipeline returns nil so Gen4Ground keeps the frame; this only
-- installs the overlay wraps and remembers the view size.
function Host.noteFrame(ctx)
  pcall(Host.install)
  if ctx then
    Host._vw = tonumber(ctx.vw) or Host._vw
    Host._vh = tonumber(ctx.vh) or Host._vh
  end
end

-- 3D grass into the still-bound gen4 target, before characters (depth test
-- against houses). Wind/weather wait for endFree, after sprites.
function Host.overlay3D(ground)
  if not Host.effectsOn() then return end
  local ow = game() and game().overworld
  if not (ground and ow) then return end
  Host._drawGround = ground
  pcall(drawGrass, ow, ground)
  Host._drawGround = nil
end


-- Battle: draw Sinnoh from the staged BattleCam, then let Stadium /
-- Colosseum actors paint into the same framebuffer via Voxel3D "current".
function Host.renderBattle(state, arena, textures, token)
  local ground = Host.groundOf(state) or Host.groundOf(state and { map = arena.map })
  if arena and arena.map and arena.map.renderer and arena.map.renderer.gen4Ground then
    ground = arena.map.renderer.gen4Ground
  end
  if not ground then return nil end
  if arena and arena.discs and not arena.showTerrain then return nil end

  local BattleScene = V.require("BattleScene")
  local BattleCam = V.require("BattleCam")
  local Voxel3D = V.require("Voxel3D")
  local lx, ly, s, pw, ph = BattleScene.letterbox()
  if not (pw and ph and pw > 0 and ph > 0) then return nil end

  local hostMap = (arena and arena.map) or (state and state.map)
  local ox = ground.offsetX or 0
  local oz = ground.offsetY or 0
  local groundY = 0
  if ground.groundY and arena and arena.mid then
    groundY = ground:groundY(arena.mid[1], arena.mid[2]) or 0
  elseif BattleScene.groundY then
    groundY = BattleScene.groundY(hostMap, arena) or 0
  end

  -- The telephoto rig stands five tiles back, which on a Sinnoh interior
  -- is through a wall. Wide is the same composition at a distance the room
  -- can actually hold.
  if arena and arena.cam == nil then arena.cam = "wide" end

  local cam = nil
  if BattleCam and BattleCam.rig then
    cam = select(1, BattleCam.rig(arena, groundY))
  end
  if not (cam and cam.eye and cam.focus) then return nil end
  cam.fov = BattleScene.letterboxFov(cam.fov, ph, s)

  -- Gen4View / NSBMD chunks live in origin-offset world units. BattleCam
  -- and Stadium cells are map-local. One space for the lens and the actors.
  local worldCam = {
    eye = { cam.eye[1] + ox, cam.eye[2] + 18, cam.eye[3] + oz },
    focus = { cam.focus[1] + ox, cam.focus[2], cam.focus[3] + oz },
    fov = cam.fov,
    curve = 0,
  }

  local Gen4View = engineRequire("src.render.Gen4View")
  if not Gen4View then return nil end
  local view = ground.view3d
  if not view then
    view = Gen4View.new("third")
    ground.view3d = view
  end
  local savedMode = view.mode
  -- field3d derives fov from the cartridge camera distance, which is not
  -- this fight's lens. Third-person uses view.fovY as-is.
  view.mode = "third"
  view.x, view.y, view.z = worldCam.eye[1], worldCam.eye[2], worldCam.eye[3]
  local dx = worldCam.focus[1] - worldCam.eye[1]
  local dy = worldCam.focus[2] - worldCam.eye[2]
  local dz = worldCam.focus[3] - worldCam.eye[3]
  local flat = math.sqrt(dx * dx + dz * dz)
  view.yaw = math.atan2(dx, -dz)
  view.pitch = math.deg(math.atan2(-dy, math.max(flat, 1e-6)))
  view.fovY = math.deg(worldCam.fov or view.fovY or 50)
  ground.cameraPlaced = true

  Host._inBattle = true
  local drawFree = Host._drawFree or ground.drawFree
  local endFree = Host._endFree or ground.endFree
  local painted = drawFree(ground, pw, ph)
  if not painted then
    view.mode = savedMode
    if endFree then pcall(endFree, ground) end
    Host._inBattle = false
    return nil
  end
  pcall(Host.overlay3D, ground)

  Voxel3D.camera = worldCam
  local cx, cz = arena.mid[1] + ox, arena.mid[2] + oz
  local vh = (BattleCam.frameH and BattleCam.frameH(arena)) or 34
  vh = vh * ph / (select(2, BattleScene.surface()) * s)
  local vw = vh * pw / ph
  local fw = ground.freeW or pw
  local fh = ground.freeH or ph
  local Mat4 = V.require("Mat4")
  local worldShift = (ox ~= 0 or oz ~= 0) and Mat4.translate(ox, 0, oz) or nil
  pcall(function()
    local St = V.require("Stadium")
    if St and St.update then
      -- Same floor the NSBMD mesh is standing on, not the voxel 0 that
      -- buried every actor in the terrain.
      pcall(St.update, 0, state, groundY)
    end
  end)
  pcall(function()
    if not Voxel3D.beginScene(fw, fh, cx, cz, vw, vh, nil, "current") then
      return
    end
    -- beginScene uploads its own vp. The terrain was drawn with
    -- Gen4View.matrix into this same target; replace AND re-send or
    -- Pokemon/trainers project through the old lens (inside the mesh,
    -- or off the camera entirely).
    if view and type(view.matrix) == "function" then
      Voxel3D.vp = view:matrix(fw, fh)
    end
    Voxel3D.eye = worldCam.eye
    Voxel3D.focus = worldCam.focus
    local sh = love.graphics.getShader()
    if sh then
      pcall(sh.send, sh, "vp", "row", Voxel3D.vp)
      pcall(sh.send, sh, "eye", Voxel3D.eye)
    end
    local pull = V.require("BattleBillboard").PULL
    pcall(function()
      for _, card in ipairs(BattleScene.monCards(arena, groundY, textures) or {}) do
        local model = card.model
        if worldShift then model = Mat4.mul(worldShift, model) end
        Voxel3D.draw(V.require("BattleBillboard").mesh(), card.tex, model,
                     pull)
      end
    end)
    pcall(function()
      V.require("Stadium").draw(pull, worldShift)
    end)
    pcall(function()
      local CSM = V.CurrentSpriteModels
      if CSM and type(CSM.drawWorld) == "function" then
        CSM:drawWorld({
          width = pw, height = ph, arena = arena, battle = state,
          originX = ox, originZ = oz,
        })
      end
    end)
    Voxel3D.endScene()
  end)

  local Gen4Ground = engineRequire("src.render.Gen4Ground")
  local src = Gen4Ground and Gen4Ground.freeColour
  local colour = nil
  if src and love and love.graphics then
    local g = love.graphics
    local okNew, dest = pcall(g.newCanvas, pw, ph)
    if okNew and dest then
      local prev = { g.getCanvas() }
      pcall(g.setCanvas, dest)
      g.setColor(1, 1, 1, 1)
      local sw, sh = src.getWidth and src:getWidth() or pw,
                     src.getHeight and src:getHeight() or ph
      if sw ~= pw or sh ~= ph then
        pcall(g.draw, src, 0, 0, 0, pw / sw, ph / sh)
      else
        pcall(g.draw, src, 0, 0)
      end
      pcall(g.setCanvas, prev[1] or nil)
      colour = dest
    else
      colour = src
    end
  end
  if endFree then pcall(endFree, ground) end
  Host._inBattle = false
  if not colour then
    view.mode = savedMode
    return nil
  end

  local vp = (view and view.matrix) and view:matrix(pw, ph) or Voxel3D.vp
  local pmx, pmy = BattleScene.toGB(vp, arena.player[1] + ox, groundY,
                                    arena.player[2] + oz, lx, ly, s, pw, ph)
  local emx, emy = BattleScene.toGB(vp, arena.enemy[1] + ox, groundY,
                                    arena.enemy[2] + oz, lx, ly, s, pw, ph)
  view.mode = savedMode
  if not (pmx and emx) then
    pmx, pmy = 40, 100
    emx, emy = 120, 40
  end
  return {
    canvas = colour,
    player = { pmx, pmy },
    enemy = { emx, emy },
    playerSpan = 16,
    enemySpan = 16,
    lx = lx, ly = ly, scale = s, pw = pw, ph = ph,
    eye = { worldCam.eye[1], worldCam.eye[2], worldCam.eye[3] },
    focus = { worldCam.focus[1], worldCam.focus[2], worldCam.focus[3] },
    vp = vp,
    gen4World = true,
  }
end

function Host.install()
  if Host.installed then return true end
  local Gen4Ground = engineRequire("src.render.Gen4Ground")
  if not (Gen4Ground and Gen4Ground.drawFree) then return false end

  local innerDrawFree = Gen4Ground.drawFree
  function Gen4Ground:drawFree(vw, vh)
    Host._vw, Host._vh = vw, vh
    local ok = innerDrawFree(self, vw, vh)
    if ok then pcall(Host.overlay3D, self) end
    return ok
  end

  local innerEndFree = Gen4Ground.endFree
  if type(innerEndFree) == "function" then
    function Gen4Ground:endFree()
      if not Host._inBattle then
        local ow = game() and game().overworld
        local sw = self.freeW or Host._vw
        local sh = self.freeH or Host._vh
        if ow and sw and sh then
          pcall(Host.overlayFx, ow, self, sw, sh, 1)
        end
      end
      return innerEndFree(self)
    end
  end

  local TileRenderer = engineRequire("src.render.TileRenderer")
  if TileRenderer and type(TileRenderer.drawAbove) == "function" then
    local innerAbove = TileRenderer.drawAbove
    function TileRenderer:drawAbove(camX, camY, vw, vh)
      local r = innerAbove(self, camX, camY, vw, vh)
      -- Field (non-free) camera: sprites are already on the world canvas.
      if self.gen4Ground and not (self.gen4Ground.freeMode
          and self.gen4Ground:freeMode()) then
        local ow = game() and game().overworld
        if ow then
          pcall(Host.overlayFx, ow, self.gen4Ground, vw, vh, 1)
        end
      end
      return r
    end
  end

  Host._drawFree = innerDrawFree
  Host._endFree = innerEndFree
  Host.installed = true
  return true
end

return Host
