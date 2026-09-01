-- Nurse Joy TRUE 3D companion mod for Gen1Recomp + Dramatic Shape.
--
-- This version uses several baked mesh frames so Nurse Joy's arms can sway in
-- a cute fashion pose while still using the user-supplied model.

return function(mod)
  local markerPath = mod.assets:path("assets/nurse_joy_fallback.png")

  mod.content.sprites:patch("SPRITE_NURSE", {
    image = markerPath,
    trueColor = true,
  })

  local ds = mod.find("DRAMATIC_SHAPE")
  if not (ds and ds.exports and ds.exports.lib) then
    mod.log:error("Dramatic Shape is required but its companion API was not available")
    return
  end

  local V = ds.exports.lib
  local VoxelScene = V.require("VoxelScene")
  local Voxel3D = V.require("Voxel3D")
  local Mat4 = V.require("Mat4")
  local ShadowMap = V.require("ShadowMap")
  local SpriteBillboards = V.require("SpriteBillboards")

  local nurseMeshes, nurseShadowMesh, nurseTexture
  local meshFailed = false

  local function loadMeshAsset(path)
    local src, err = mod:read(path)
    if not src then return nil, err end
    local loader = loadstring or load
    local chunk, loadErr = loader(src, "@" .. mod.path .. "/" .. path)
    if not chunk then return nil, loadErr end
    local okData, data = pcall(chunk)
    if not okData or type(data) ~= "table" then return nil, data end
    return data
  end

  local function ensureModel()
    if nurseMeshes or meshFailed then return nurseMeshes ~= nil end
    if not (love and love.graphics and love.graphics.newMesh) then return false end

    nurseMeshes = {}
    nurseShadowMesh = nil

    for i = 1, 60 do
      local data, err = loadMeshAsset("assets/nurse_mesh_" .. i .. ".lua")
      if not data then
        mod.log:error("Could not load Nurse mesh frame %d: %s", i, tostring(err))
        meshFailed = true
        nurseMeshes, nurseShadowMesh = nil, nil
        return false
      end

      local mesh = Voxel3D.newMesh(data.vertices or {}, data.indices or {})
      if not mesh then
        mod.log:error("Dramatic Shape could not create Nurse 3D mesh frame %d", i)
        meshFailed = true
        nurseMeshes, nurseShadowMesh = nil, nil
        return false
      end
      nurseMeshes[i] = mesh

      -- One neutral shadow mesh is enough; the hands move only a few pixels,
      -- and avoiding 60 duplicate shadow meshes keeps the smoother animation light.
      if i == 30 then
        local shadowVerts = {}
        local su, sv = 8.5 / 16.0, 8.5 / 48.0
        for vi, vert in ipairs(data.vertices or {}) do
          shadowVerts[vi] = { vert[1], vert[2], vert[3], su, sv, 1.0 }
        end
        nurseShadowMesh = Voxel3D.newMesh(shadowVerts, data.indices or {})
      end

      data.vertices, data.indices = nil, nil
    end

    local okTex, tex = pcall(mod.assets.image, mod.assets, "assets/nurse_joy_atlas.png")
    if not (okTex and tex) then
      mod.log:error("Could not create Nurse Joy texture atlas")
      meshFailed = true
      nurseMeshes, nurseShadowMesh = nil, nil
      return false
    end
    nurseTexture = tex
    pcall(nurseTexture.setFilter, nurseTexture, "linear", "linear")
    pcall(nurseTexture.setWrap, nurseTexture, "clamp", "clamp")

    collectgarbage("step")
    return true
  end

  local function isNurse(spriteOrDef)
    local def = spriteOrDef and (spriteOrDef.def or spriteOrDef)
    return def and def.image == markerPath
  end

  local function armFrameIndex()
    local timer = (love and love.timer and love.timer.getTime and love.timer.getTime()) or os.clock()
    -- 60 pose changes per second. The 60 baked poses are one half-sway and
    -- this ping-pongs them, giving a ~2-second natural cycle without a 30 Hz step.
    local step = math.floor(timer * 60.0) % 118
    local idx
    if step < 60 then
      idx = step + 1
    else
      idx = 119 - step
    end
    return idx, timer
  end

  local function idleSway(timer)
    local hip = math.sin(timer * 1.35)
    local shoulder = math.sin(timer * 1.35 + 0.55)
    local bob = math.sin(timer * 2.70 + 1.10)
    local drift = math.sin(timer * 0.68 + 0.40)
    return {
      x = hip * 0.28,
      y = bob * 0.06,
      z = drift * 0.08,
      yaw = math.rad(5.0) * shoulder,
    }
  end

  local function modelMatrix(px, py, y, facing, idle)
    local m = Mat4.translate(px + 8 + idle.x, y + idle.y, py + 8 + idle.z)
    local yaw = ((VoxelScene.YAW and VoxelScene.YAW[facing]) or 0) + idle.yaw
    if yaw ~= 0 then m = Mat4.mul(m, Mat4.rotateY(yaw)) end
    return Mat4.mul(m, Mat4.translate(-8, 0, 0))
  end

  local function sunMatrix(px, py, y, facing, idle)
    local m = Voxel3D.casterMatrix(px + idle.x, py + idle.z, y + idle.y, false)
    local yaw = ((VoxelScene.YAW and VoxelScene.YAW[facing]) or 0) + idle.yaw
    if yaw ~= 0 then
      local localYaw = Mat4.mul(Mat4.translate(8, 0, 0),
                        Mat4.mul(Mat4.rotateY(yaw), Mat4.translate(-8, 0, 0)))
      m = Mat4.mul(m, localYaw)
    end
    return ShadowMap.snug(m)
  end

  local function findUpvalue(fn, wantedName, wantedValue)
    if type(fn) ~= "function" or not debug or not debug.getupvalue then return nil end
    for i = 1, 96 do
      local name, value = debug.getupvalue(fn, i)
      if not name then break end
      if name == wantedName or (wantedValue ~= nil and value == wantedValue) then
        return i, value, name
      end
    end
    return nil
  end

  local castIndex, drawCast = findUpvalue(VoxelScene.render, "drawCast")
  if not castIndex or type(drawCast) ~= "function" then
    mod.log:error("Dramatic Shape renderer layout changed: drawCast was not found")
    return
  end

  local entityIndex, originalDrawEntity = findUpvalue(drawCast, "drawEntity", VoxelScene.drawEntity)
  if not entityIndex or type(originalDrawEntity) ~= "function" then
    mod.log:error("Dramatic Shape renderer layout changed: drawEntity was not found")
    return
  end

  if VoxelScene._nurseJoyTrue3DInstalled then
    mod.log:warn("Nurse Joy TRUE 3D renderer was already installed")
    return
  end

  local function drawEntity(sprite, px, py, facing, phase, flip, gh, colors, lift)
    if not isNurse(sprite) then
      return originalDrawEntity(sprite, px, py, facing, phase, flip, gh, colors, lift)
    end
    if not ensureModel() then
      return originalDrawEntity(sprite, px, py, facing, phase, flip, gh, colors, lift)
    end

    local idx, timer = armFrameIndex()
    local idle = idleSway(timer)
    local y = (gh or 0) + (lift or 0)
    local model = modelMatrix(px, py, y, facing, idle)
    Voxel3D.draw(nurseMeshes[idx], nurseTexture, model, 0,
                 sunMatrix(px, py, y, facing, idle))
    return true
  end

  local setupName = debug.setupvalue(drawCast, entityIndex, drawEntity)
  if not setupName then
    mod.log:error("Could not install Nurse Joy TRUE 3D draw hook")
    return
  end

  local originalShadowQuad = SpriteBillboards.shadowQuad
  SpriteBillboards.shadowQuad = function(def, frame)
    if isNurse(def) and ensureModel() and nurseShadowMesh then
      return nurseShadowMesh
    end
    return originalShadowQuad(def, frame)
  end

  VoxelScene._nurseJoyTrue3DInstalled = true
  VoxelScene._nurseJoyTrue3DOriginalDrawEntity = originalDrawEntity
  mod.log:info("TRUE 3D Nurse Joy installed with 60 Hz baked arm sway: %s", markerPath)
end
