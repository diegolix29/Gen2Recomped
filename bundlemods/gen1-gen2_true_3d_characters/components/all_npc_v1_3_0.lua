-- All NPCs Misc-Pack TRUE 3D Placeholder v1.3.1 (stability pass)
--
-- Uses a single stable placeholder model from the user's Miscellaneous NPC
-- pack for every ordinary NPC. This avoids the per-archetype render issues some
-- models were still hitting in the combined package.
--
-- Explicitly excluded: player (SPRITE_RED), Professor Oak, Nurse Joy.

return function(mod)
  local PLACEHOLDER = {
    key = "fat",
    meshPath = "assets/fat_mesh.lua",
    texPath = "assets/fat_atlas.png",
  }

  local SPRITES = {
    "SPRITE_BLUE","SPRITE_YOUNGSTER","SPRITE_MONSTER","SPRITE_COOLTRAINER_F",
    "SPRITE_COOLTRAINER_M","SPRITE_LITTLE_GIRL","SPRITE_BIRD","SPRITE_MIDDLE_AGED_MAN",
    "SPRITE_GAMBLER","SPRITE_SUPER_NERD","SPRITE_GIRL","SPRITE_HIKER",
    "SPRITE_BEAUTY","SPRITE_GENTLEMAN","SPRITE_DAISY","SPRITE_BIKER",
    "SPRITE_SAILOR","SPRITE_COOK","SPRITE_BIKE_SHOP_CLERK","SPRITE_MR_FUJI",
    "SPRITE_GIOVANNI","SPRITE_ROCKET","SPRITE_CHANNELER","SPRITE_WAITER",
    "SPRITE_SILPH_WORKER_F","SPRITE_MIDDLE_AGED_WOMAN","SPRITE_BRUNETTE_GIRL","SPRITE_LANCE",
    "SPRITE_UNUSED_SCIENTIST","SPRITE_SCIENTIST","SPRITE_ROCKER","SPRITE_SWIMMER",
    "SPRITE_SAFARI_ZONE_WORKER","SPRITE_GYM_GUIDE","SPRITE_GRAMPS","SPRITE_CLERK",
    "SPRITE_FISHING_GURU","SPRITE_GRANNY","SPRITE_LINK_RECEPTIONIST","SPRITE_SILPH_PRESIDENT",
    "SPRITE_SILPH_WORKER_M","SPRITE_WARDEN","SPRITE_CAPTAIN","SPRITE_FISHER",
    "SPRITE_KOGA","SPRITE_GUARD","SPRITE_UNUSED_GUARD","SPRITE_MOM",
    "SPRITE_BALDING_GUY","SPRITE_LITTLE_BOY","SPRITE_UNUSED_GAMEBOY_KID","SPRITE_GAMEBOY_KID",
    "SPRITE_FAIRY","SPRITE_AGATHA","SPRITE_BRUNO","SPRITE_LORELEI","SPRITE_SEEL",
  }

  PLACEHOLDER.marker = mod.assets:path("assets/fat_marker.png")
  for _, spriteId in ipairs(SPRITES) do
    mod.content.sprites:patch(spriteId, {
      image = PLACEHOLDER.marker,
      trueColor = true,
    })
  end

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
    if PLACEHOLDER.mesh and PLACEHOLDER.texture then return true end
    if PLACEHOLDER.failed then return false end

    local data, err = loadMeshAsset(PLACEHOLDER.meshPath)
    if not data then
      mod.log:error("all-npc placeholder mesh load failed: %s", tostring(err))
      PLACEHOLDER.failed = true
      return false
    end

    PLACEHOLDER.mesh = Voxel3D.newMesh(data.vertices or {}, data.indices or {})
    if not PLACEHOLDER.mesh then
      mod.log:error("all-npc placeholder GPU mesh creation failed")
      PLACEHOLDER.failed = true
      return false
    end

    local okTex, tex = pcall(mod.assets.image, mod.assets, PLACEHOLDER.texPath)
    if not (okTex and tex) then
      mod.log:error("all-npc placeholder texture atlas creation failed")
      PLACEHOLDER.failed = true
      return false
    end
    PLACEHOLDER.texture = tex
    pcall(tex.setFilter, tex, "linear", "linear", 8)
    pcall(tex.setWrap, tex, "clamp", "clamp")

    local shadowVerts = {}
    local su, sv = 8.5 / 16.0, 8.5 / 48.0
    for i, vert in ipairs(data.vertices or {}) do
      shadowVerts[i] = { vert[1], vert[2], vert[3], su, sv, 1.0 }
    end
    PLACEHOLDER.shadowMesh = Voxel3D.newMesh(shadowVerts, data.indices or {})

    data.vertices, data.indices = nil, nil
    collectgarbage("step")
    return true
  end

  local function isPlaceholder(spriteOrDef)
    local def = spriteOrDef and (spriteOrDef.def or spriteOrDef)
    return def and def.image == PLACEHOLDER.marker
  end

  local function idle()
    local t = (love and love.timer and love.timer.getTime and love.timer.getTime()) or os.clock()
    return {
      x = math.sin(t * 0.78) * 0.035,
      y = math.sin(t * 1.42) * 0.025,
      z = math.sin(t * 0.63) * 0.020,
      yaw = math.sin(t * 0.71) * math.rad(1.0),
    }
  end

  local function modelMatrix(px, py, y, facing, idle)
    local m = Mat4.translate(px + 8 + idle.x, y + idle.y, py + 8 + idle.z)
    local yaw = ((VoxelScene.YAW and VoxelScene.YAW[facing]) or 0) + idle.yaw
    if yaw ~= 0 then m = Mat4.mul(m, Mat4.rotateY(yaw)) end
    return Mat4.mul(m, Mat4.translate(-8, 0, 0)), yaw
  end

  local function sunMatrix(px, py, y, yaw, idle)
    local m = Voxel3D.casterMatrix(px + idle.x, py + idle.z, y + idle.y, false)
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

  if VoxelScene._allNpcMiscDirect3DInstalled then
    mod.log:warn("All NPC Misc-Pack direct TRUE 3D renderer was already installed")
    return
  end

  local function drawEntity(sprite, px, py, facing, phase, flip, gh, colors, lift)
    if not isPlaceholder(sprite) then
      return originalDrawEntity(sprite, px, py, facing, phase, flip, gh, colors, lift)
    end
    if not ensureModel() then
      return originalDrawEntity(sprite, px, py, facing, phase, flip, gh, colors, lift)
    end

    local sway = idle()
    local y = (gh or 0) + (lift or 0)
    local model, yaw = modelMatrix(px, py, y, facing, sway)
    Voxel3D.draw(PLACEHOLDER.mesh, PLACEHOLDER.texture, model, 0,
                 sunMatrix(px, py, y, yaw, sway))
    return true
  end

  local setupName = debug.setupvalue(drawCast, entityIndex, drawEntity)
  if not setupName then
    mod.log:error("Could not install direct All NPC TRUE 3D draw hook")
    return
  end

  local originalShadowQuad = SpriteBillboards.shadowQuad
  SpriteBillboards.shadowQuad = function(def, frame)
    if isPlaceholder(def) and ensureModel() and PLACEHOLDER.shadowMesh then
      return PLACEHOLDER.shadowMesh
    end
    return originalShadowQuad(def, frame)
  end

  VoxelScene._allNpcMiscDirect3DInstalled = true
  VoxelScene._allNpcMiscDirect3DOriginalDrawEntity = originalDrawEntity
  mod.log:info("All NPC Misc-Pack TRUE 3D v1.3.1 installed as a universal stable placeholder")
end
