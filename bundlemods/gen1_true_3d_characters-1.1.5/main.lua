-- Gen1 TRUE 3D Characters v1.1.4
-- Unified renderer: ordinary NPCs + Nurse Joy + Professor Oak.
--
-- One drawEntity hook owns all imported characters. This avoids chaining three
-- renderer wrappers together (which could transform Oak twice) and keeps every
-- mesh paired with its own texture atlas in the same draw call.

return function(mod)
  ---------------------------------------------------------------------------
  -- Content markers
  ---------------------------------------------------------------------------
  local nurseMarker = mod.assets:path("assets/nurse_joy_fallback.png")
  local oakMarker = mod.assets:path("assets/professor_oak_fallback.png")

  mod.content.sprites:patch("SPRITE_NURSE", {
    image = nurseMarker,
    trueColor = true,
  })
  mod.content.sprites:patch("SPRITE_OAK", {
    image = oakMarker,
    trueColor = true,
  })

  local MODEL_DEFS = {
    fat =           { meshPath="assets/fat_mesh.lua",           texPath="assets/fat_atlas.png", walkPrefix="assets/fat_walk_", walkFrames=24 },
    middle_man =    { meshPath="assets/middle_man_mesh.lua",    texPath="assets/middle_man_atlas.png", walkPrefix="assets/middle_man_walk_", walkFrames=24 },
    middle_woman =  { meshPath="assets/middle_woman_mesh.lua",  texPath="assets/middle_woman_atlas.png", walkPrefix="assets/middle_woman_walk_", walkFrames=24 },
    elderly_man =   { meshPath="assets/elderly_man_mesh.lua",   texPath="assets/elderly_man_atlas.png", walkPrefix="assets/elderly_man_walk_", walkFrames=24 },
    elderly_woman = { meshPath="assets/elderly_woman_mesh.lua", texPath="assets/elderly_woman_atlas.png", walkPrefix="assets/elderly_woman_walk_", walkFrames=24 },
    kid_boy =       { meshPath="assets/kid_boy_mesh.lua",       texPath="assets/kid_boy_atlas.png", walkPrefix="assets/kid_boy_walk_", walkFrames=24 },
    kid_girl =      { meshPath="assets/kid_girl_mesh.lua",      texPath="assets/kid_girl_atlas.png", walkPrefix="assets/kid_girl_walk_", walkFrames=24 },
    adult_woman =   { meshPath="assets/adult_woman_mesh.lua",   texPath="assets/adult_woman_atlas.png", walkPrefix="assets/adult_woman_walk_", walkFrames=24 },
    cook =          { meshPath="assets/cook_mesh.lua",          texPath="assets/cook_atlas.png", walkPrefix="assets/cook_walk_", walkFrames=24 },
    guard =         { meshPath="assets/guard_mesh.lua",         texPath="assets/guard_atlas.png", walkPrefix="assets/guard_walk_", walkFrames=24 },
    staff_man =     { meshPath="assets/staff_man_mesh.lua",     texPath="assets/staff_man_atlas.png", walkPrefix="assets/staff_man_walk_", walkFrames=24 },
    staff_woman =   { meshPath="assets/staff_woman_mesh.lua",   texPath="assets/staff_woman_atlas.png", walkPrefix="assets/staff_woman_walk_", walkFrames=24 },

    -- Additional models that were present in the user's Miscellaneous NPC ZIP
    -- but were not used in the first placeholder pass.
    adult_man =     { meshPath="assets/adult_man_mesh.lua",      texPath="assets/adult_man_atlas.png", walkPrefix="assets/adult_man_walk_", walkFrames=24 },
    juvenile_boy =  { meshPath="assets/juvenile_boy_mesh.lua",   texPath="assets/juvenile_boy_atlas.png", walkPrefix="assets/juvenile_boy_walk_", walkFrames=24 },
    juvenile_girl = { meshPath="assets/juvenile_girl_mesh.lua",  texPath="assets/juvenile_girl_atlas.png", walkPrefix="assets/juvenile_girl_walk_", walkFrames=24 },
    muscle =        { meshPath="assets/muscle_mesh.lua",         texPath="assets/muscle_atlas.png", walkPrefix="assets/muscle_walk_", walkFrames=24 },
    scientist =     { meshPath="assets/scientist_mesh.lua",      texPath="assets/scientist_atlas.png", walkPrefix="assets/scientist_walk_", walkFrames=24 },
    young_boy =     { meshPath="assets/young_boy_mesh.lua",      texPath="assets/young_boy_atlas.png", walkPrefix="assets/young_boy_walk_", walkFrames=24 },
    young_girl =    { meshPath="assets/young_girl_mesh.lua",     texPath="assets/young_girl_atlas.png", walkPrefix="assets/young_girl_walk_", walkFrames=24 },
  }

  -- Pools let NPCs using the same original Gen 1 sprite choose from several
  -- compatible 3D people. The choice is cached per sprite object, so an NPC
  -- never changes model while walking around.
  local MODEL_POOLS = {
    adult_male   = { "adult_man", "middle_man", "young_boy", "juvenile_boy" },
    adult_female = { "adult_woman", "middle_woman", "young_girl", "juvenile_girl" },
    young_male   = { "young_boy", "juvenile_boy", "adult_man" },
    young_female = { "young_girl", "juvenile_girl", "adult_woman" },
    child_male   = { "kid_boy", "juvenile_boy", "young_boy" },
    child_female = { "kid_girl", "juvenile_girl", "young_girl" },
    heavy_male   = { "fat", "muscle", "middle_man" },
    staff_male   = { "staff_man", "scientist", "adult_man", "middle_man" },
    staff_female = { "staff_woman", "adult_woman", "middle_woman" },
    elder_male   = { "elderly_man", "middle_man" },
    elder_female = { "elderly_woman", "middle_woman" },
    guard_pool   = { "guard", "adult_man", "muscle" },
    cook_pool    = { "cook" },
    scientist_pool = { "scientist", "staff_man" },
    fat_pool     = { "fat" },
    muscle_pool  = { "muscle", "adult_man" },
  }

  -- Trainer-specific 3D models can still replace these later. For now these
  -- use age/job-appropriate pools from the user's Miscellaneous NPC set.
  local SPRITE_POOL = {
    SPRITE_BLUE = "young_male",
    SPRITE_YOUNGSTER = "young_male",
    SPRITE_MONSTER = "heavy_male",
    SPRITE_COOLTRAINER_F = "young_female",
    SPRITE_COOLTRAINER_M = "young_male",
    SPRITE_LITTLE_GIRL = "child_female",
    SPRITE_BIRD = "child_female",
    SPRITE_MIDDLE_AGED_MAN = "fat_pool", -- preserve the chubby NPC mapping requested earlier
    SPRITE_GAMBLER = "adult_male",
    SPRITE_SUPER_NERD = "scientist_pool",
    SPRITE_GIRL = "young_female",
    SPRITE_HIKER = "heavy_male",
    SPRITE_BEAUTY = "adult_female",
    SPRITE_GENTLEMAN = "elder_male",
    SPRITE_DAISY = "young_female",
    SPRITE_BIKER = "muscle_pool",
    SPRITE_SAILOR = "adult_male",
    SPRITE_COOK = "cook_pool",
    SPRITE_BIKE_SHOP_CLERK = "staff_male",
    SPRITE_MR_FUJI = "elder_male",
    SPRITE_GIOVANNI = "adult_male",
    SPRITE_ROCKET = "young_male",
    SPRITE_CHANNELER = "elder_female",
    SPRITE_WAITER = "staff_male",
    SPRITE_SILPH_WORKER_F = "staff_female",
    SPRITE_MIDDLE_AGED_WOMAN = "adult_female",
    SPRITE_BRUNETTE_GIRL = "young_female",
    SPRITE_LANCE = "muscle_pool",
    SPRITE_UNUSED_SCIENTIST = "scientist_pool",
    SPRITE_SCIENTIST = "scientist_pool",
    SPRITE_ROCKER = "young_male",
    SPRITE_SWIMMER = "young_male",
    SPRITE_SAFARI_ZONE_WORKER = "staff_male",
    SPRITE_GYM_GUIDE = "adult_male",
    SPRITE_GRAMPS = "elder_male",
    SPRITE_CLERK = "staff_male",
    SPRITE_FISHING_GURU = "elder_male",
    SPRITE_GRANNY = "elder_female",
    SPRITE_LINK_RECEPTIONIST = "staff_female",
    SPRITE_SILPH_PRESIDENT = "elder_male",
    SPRITE_SILPH_WORKER_M = "staff_male",
    SPRITE_WARDEN = "adult_male",
    SPRITE_CAPTAIN = "elder_male",
    SPRITE_FISHER = "adult_male",
    SPRITE_KOGA = "muscle_pool",
    SPRITE_GUARD = "guard_pool",
    SPRITE_UNUSED_GUARD = "guard_pool",
    SPRITE_MOM = "adult_female",
    SPRITE_BALDING_GUY = "adult_male",
    SPRITE_LITTLE_BOY = "child_male",
    SPRITE_UNUSED_GAMEBOY_KID = "child_male",
    SPRITE_GAMEBOY_KID = "child_male",
    SPRITE_FAIRY = "child_female",
    SPRITE_AGATHA = "elder_female",
    SPRITE_BRUNO = "muscle_pool",
    SPRITE_LORELEI = "adult_female",
    SPRITE_SEEL = "heavy_male",
  }

  local markerToPool = {}
  for poolName, _ in pairs(MODEL_POOLS) do
    local marker = mod.assets:path("assets/pool_" .. poolName .. "_marker.png")
    markerToPool[marker] = poolName
  end
  for spriteId, poolName in pairs(SPRITE_POOL) do
    mod.content.sprites:patch(spriteId, {
      image = mod.assets:path("assets/pool_" .. poolName .. "_marker.png"),
      trueColor = true,
    })
  end

  ---------------------------------------------------------------------------
  -- Dramatic Shape API
  ---------------------------------------------------------------------------
  local ds = mod.find("DRAMATIC_SHAPE")
  if not (ds and ds.exports and ds.exports.lib) then
    mod.log:error("Gen1 TRUE 3D Characters requires Dramatic Shape")
    return
  end

  local V = ds.exports.lib
  local VoxelScene = V.require("VoxelScene")
  local Voxel3D = V.require("Voxel3D")
  local Mat4 = V.require("Mat4")
  local ShadowMap = V.require("ShadowMap")
  local SpriteBillboards = V.require("SpriteBillboards")

  local function readMeshData(path)
    local src, err = mod:read(path)
    if not src then return nil, err end
    local loader = loadstring or load
    local chunk, loadErr = loader(src, "@" .. mod.path .. "/" .. path)
    if not chunk then return nil, loadErr end
    local ok, data = pcall(chunk)
    if not ok or type(data) ~= "table" then return nil, data end
    return data
  end

  local function loadTexture(path)
    local ok, tex = pcall(mod.assets.image, mod.assets, path)
    if not (ok and tex) then return nil end
    pcall(tex.setFilter, tex, "linear", "linear", 8)
    pcall(tex.setWrap, tex, "clamp", "clamp")
    return tex
  end

  ---------------------------------------------------------------------------
  -- Ordinary placeholder models
  ---------------------------------------------------------------------------
  local function ensureGeneric(key)
    local info = MODEL_DEFS[key]
    if not info then return false end
    if info.mesh and info.texture then return true end
    if info.failed then return false end

    local data, err = readMeshData(info.meshPath)
    if not data then
      mod.log:error("%s mesh load failed: %s", key, tostring(err))
      info.failed = true
      return false
    end
    info.mesh = Voxel3D.newMesh(data.vertices or {}, data.indices or {})
    info.texture = loadTexture(info.texPath)
    info.walkMeshes = {}
    if not (info.mesh and info.texture) then
      mod.log:error("%s GPU model creation failed", key)
      info.failed = true
      return false
    end
    data.vertices, data.indices = nil, nil
    collectgarbage("step")
    return true
  end

  -- Walk frames are loaded lazily. Loading all 19 rigs x 12 poses at startup
  -- would waste memory on NPC types that are not present on the current map.
  local function genericWalkMesh(key, frame)
    local info = MODEL_DEFS[key]
    if not info or not ensureGeneric(key) then return nil end
    frame = math.max(1, math.min(info.walkFrames or 1, frame or 1))
    if info.walkMeshes[frame] then return info.walkMeshes[frame] end
    local data, err = readMeshData(info.walkPrefix .. string.format("%02d.lua", frame))
    if not data then
      mod.log:error("%s walk frame %d load failed: %s", key, frame, tostring(err))
      return nil
    end
    local mesh = Voxel3D.newMesh(data.vertices or {}, data.indices or {})
    data.vertices, data.indices = nil, nil
    if mesh then info.walkMeshes[frame] = mesh end
    collectgarbage("step")
    return mesh
  end

  -- `phase == 1` is the same walking flag Dramatic Shape uses to select the
  -- original Game Boy walk frame. Position supplies a continuous gait phase,
  -- so the legs alternate across consecutive 16-pixel steps and reflections
  -- always choose the exact same pose as the visible character.
  local function genericWalkFrame(px, py, facing, count)
    local axis = (facing == "left" or facing == "right") and px or py
    local cycle = (axis / 32) % 1
    if cycle < 0 then cycle = cycle + 1 end
    local frame = math.floor(cycle * count) + 1
    if frame > count then frame = count end
    return frame
  end

  local variantCache = setmetatable({}, { __mode = "k" })
  local variantSerial = 0

  local function genericKey(sprite)
    local def = sprite and (sprite.def or sprite)
    if not def then return nil end
    local poolName = markerToPool[def.image]
    if not poolName then return nil end
    local pool = MODEL_POOLS[poolName]
    if not pool or #pool == 0 then return nil end

    if type(sprite) == "table" then
      local cached = variantCache[sprite]
      if cached then return cached end
      variantSerial = variantSerial + 1
      local sx = tonumber(sprite.x or sprite.px or 0) or 0
      local sy = tonumber(sprite.y or sprite.py or 0) or 0
      local seed = math.abs(math.floor(sx * 17 + sy * 31 + variantSerial * 13))
      local key = pool[(seed % #pool) + 1]
      variantCache[sprite] = key
      return key
    end

    return pool[1]
  end

  local function genericIdle(key)
    local t = (love and love.timer and love.timer.getTime and love.timer.getTime()) or os.clock()
    local seed = 0
    for i = 1, #key do seed = seed + string.byte(key, i) end
    return {
      x = math.sin(t * 0.78 + seed * 0.07) * 0.035,
      y = math.sin(t * 1.42 + seed * 0.11) * 0.025,
      z = math.sin(t * 0.63 + seed * 0.05) * 0.020,
      yaw = math.sin(t * 0.71 + seed * 0.09) * math.rad(1.0),
    }
  end

  local function worldModel(px, py, y, facing, idle, scale)
    idle = idle or { x=0, y=0, z=0, yaw=0 }
    local m = Mat4.translate(px + 8 + (idle.x or 0),
                             y + (idle.y or 0),
                             py + 8 + (idle.z or 0))
    local yaw = ((VoxelScene.YAW and VoxelScene.YAW[facing]) or 0)
                + (idle.yaw or 0)
    if yaw ~= 0 then m = Mat4.mul(m, Mat4.rotateY(yaw)) end
    if scale and scale ~= 1 then
      m = Mat4.mul(m, Mat4.scale(scale, scale, scale))
    end
    return Mat4.mul(m, Mat4.translate(-8, 0, 0))
  end

  -- Put imported models outside the shadow-map lookup for their own draw.
  -- They still carry baked directional shading and day/night tint, but cannot
  -- get the broken black self-shadow bands that the sprite-card shadow pass can
  -- create on arbitrary full 3D geometry.
  local NO_SELF_SHADOW = Mat4.translate(100000, 100000, 100000)

  ---------------------------------------------------------------------------
  -- Nurse Joy (v1.3.4 data / 60 Hz animation)
  ---------------------------------------------------------------------------
  local nurse = { meshes=nil, shadowMesh=nil, texture=nil, failed=false }

  local function ensureNurse()
    if nurse.meshes and nurse.texture then return true end
    if nurse.failed then return false end
    nurse.meshes = {}
    for i = 1, 60 do
      local data, err = readMeshData("assets/nurse_mesh_" .. i .. ".lua")
      if not data then
        mod.log:error("Nurse mesh %d load failed: %s", i, tostring(err))
        nurse.failed = true
        nurse.meshes = nil
        return false
      end
      local mesh = Voxel3D.newMesh(data.vertices or {}, data.indices or {})
      if not mesh then
        mod.log:error("Nurse GPU mesh %d creation failed", i)
        nurse.failed = true
        nurse.meshes = nil
        return false
      end
      nurse.meshes[i] = mesh
      if i == 30 then
        local shadowVerts = {}
        local su, sv = 8.5 / 16.0, 8.5 / 48.0
        for vi, vert in ipairs(data.vertices or {}) do
          shadowVerts[vi] = { vert[1], vert[2], vert[3], su, sv, 1.0 }
        end
        nurse.shadowMesh = Voxel3D.newMesh(shadowVerts, data.indices or {})
      end
      data.vertices, data.indices = nil, nil
    end
    nurse.texture = loadTexture("assets/nurse_joy_atlas.png")
    if not nurse.texture then
      mod.log:error("Nurse texture atlas creation failed")
      nurse.failed = true
      return false
    end
    collectgarbage("step")
    return true
  end

  local function isNurse(sprite)
    local def = sprite and (sprite.def or sprite)
    return def and (def.image == nurseMarker or def.id == "SPRITE_NURSE")
  end

  local function nurseFrame()
    local t = (love and love.timer and love.timer.getTime and love.timer.getTime()) or os.clock()
    local step = math.floor(t * 60.0) % 118
    local idx = (step < 60) and (step + 1) or (119 - step)
    return idx, t
  end

  local function nurseIdle(t)
    return {
      x = math.sin(t * 1.35) * 0.28,
      y = math.sin(t * 2.70 + 1.10) * 0.06,
      z = math.sin(t * 0.68 + 0.40) * 0.08,
      yaw = math.rad(5.0) * math.sin(t * 1.35 + 0.55),
    }
  end

  local function nurseSun(px, py, y, facing, idle)
    local m = Voxel3D.casterMatrix(px + idle.x, py + idle.z, y + idle.y, false)
    local yaw = ((VoxelScene.YAW and VoxelScene.YAW[facing]) or 0) + idle.yaw
    if yaw ~= 0 then
      local localYaw = Mat4.mul(Mat4.translate(8, 0, 0),
                        Mat4.mul(Mat4.rotateY(yaw), Mat4.translate(-8, 0, 0)))
      m = Mat4.mul(m, localYaw)
    end
    return ShadowMap.snug(m)
  end

  ---------------------------------------------------------------------------
  -- Professor Oak (v1.0.5 mesh/texture, now drawn directly)
  ---------------------------------------------------------------------------
  local oak = { mesh=nil, texture=nil, walkMeshes={}, failed=false }

  local function ensureOak()
    if oak.mesh and oak.texture then return true end
    if oak.failed then return false end
    local data, err = readMeshData("assets/professor_oak_mesh.lua")
    if not data then
      mod.log:error("Oak mesh load failed: %s", tostring(err))
      oak.failed = true
      return false
    end
    oak.mesh = Voxel3D.newMesh(data.vertices or {}, data.indices or {})
    oak.texture = loadTexture("assets/professor_oak_atlas.png")
    data.vertices, data.indices = nil, nil
    if not (oak.mesh and oak.texture) then
      mod.log:error("Oak GPU model creation failed")
      oak.failed = true
      return false
    end
    collectgarbage("step")
    return true
  end

  local function oakWalkMesh(frame)
    if not ensureOak() then return nil end
    frame = math.max(1, math.min(12, frame or 1))
    if oak.walkMeshes[frame] then return oak.walkMeshes[frame] end
    local data, err = readMeshData("assets/professor_oak_walk_" .. string.format("%02d.lua", frame))
    if not data then
      mod.log:error("Oak walk frame %d load failed: %s", frame, tostring(err))
      return nil
    end
    local mesh = Voxel3D.newMesh(data.vertices or {}, data.indices or {})
    data.vertices, data.indices = nil, nil
    if mesh then oak.walkMeshes[frame] = mesh end
    collectgarbage("step")
    return mesh
  end

  local function isOak(sprite)
    local def = sprite and (sprite.def or sprite)
    return def and (def.image == oakMarker or def.id == "SPRITE_OAK")
  end

  local function oakIdle()
    local t = (love and love.timer and love.timer.getTime and love.timer.getTime()) or os.clock()
    return {
      x = math.sin(t * 1.05) * 0.06,
      y = 0,
      z = 0,
      yaw = math.sin(t * 0.88 + 0.4) * math.rad(2.0),
    }
  end

  ---------------------------------------------------------------------------
  -- ONE character hook
  ---------------------------------------------------------------------------
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

  local _, drawCast = findUpvalue(VoxelScene.render, "drawCast")
  if type(drawCast) ~= "function" then
    mod.log:error("Dramatic Shape renderer layout changed: drawCast not found")
    return
  end
  local entityIndex, previousDrawEntity = findUpvalue(drawCast, "drawEntity", VoxelScene.drawEntity)
  if not entityIndex or type(previousDrawEntity) ~= "function" then
    mod.log:error("Dramatic Shape renderer layout changed: drawEntity not found")
    return
  end

  local function unifiedDrawEntity(sprite, px, py, facing, phase, flip, gh, colors, lift)
    local y = (gh or 0) + (lift or 0)

    if isNurse(sprite) then
      if not ensureNurse() then
        return previousDrawEntity(sprite, px, py, facing, phase, flip, gh, colors, lift)
      end
      local idx, t = nurseFrame()
      local idle = nurseIdle(t)
      local model = worldModel(px, py, y, facing, idle, 1)
      Voxel3D.draw(nurse.meshes[idx], nurse.texture, model, 0,
                   nurseSun(px, py, y, facing, idle))
      return true
    end

    if isOak(sprite) then
      if not ensureOak() then
        return previousDrawEntity(sprite, px, py, facing, phase, flip, gh, colors, lift)
      end
      -- Oak keeps the hand-tuned standing mesh, but scripted movement now uses
      -- the same weighted shoulder/elbow/hip/knee/ankle walk rig as the NPCs.
      local mesh = oak.mesh
      local idle = oakIdle()
      if phase == 1 then
        local frame = genericWalkFrame(px, py, facing, 12)
        mesh = oakWalkMesh(frame) or mesh
        idle = { x=0, y=0, z=0, yaw=0 }
      end
      local model = worldModel(px, py, y, facing, idle, 1.25)
      Voxel3D.draw(mesh, oak.texture, model, 0, NO_SELF_SHADOW)
      return true
    end

    local key = genericKey(sprite)
    if key then
      if not ensureGeneric(key) then
        return previousDrawEntity(sprite, px, py, facing, phase, flip, gh, colors, lift)
      end
      local info = MODEL_DEFS[key]
      local mesh = info.mesh
      local idle = genericIdle(key)
      if phase == 1 and info.walkFrames and info.walkFrames > 1 then
        local frame = genericWalkFrame(px, py, facing, info.walkFrames)
        mesh = genericWalkMesh(key, frame) or mesh
        -- Walking already contains its own body motion; do not stack the idle
        -- sway on top of it or the feet look like they skate over the floor.
        idle = { x=0, y=0, z=0, yaw=0 }
      end
      local model = worldModel(px, py, y, facing, idle, 1)
      Voxel3D.draw(mesh, info.texture, model, 0, NO_SELF_SHADOW)
      return true
    end

    -- Player and anything not deliberately replaced stays with Dramatic Shape.
    return previousDrawEntity(sprite, px, py, facing, phase, flip, gh, colors, lift)
  end

  local name = debug.setupvalue(drawCast, entityIndex, unifiedDrawEntity)
  if not name then
    mod.log:error("Could not install unified Gen1 TRUE 3D character hook")
    return
  end

  -- Preserve Nurse Joy's working neutral 3D caster. Generic placeholders and
  -- Oak intentionally retain their tiny marker-card caster; their visible 3D
  -- draw ignores self-shadow lookup to avoid the black/banded corruption seen
  -- with arbitrary imported full-body meshes.
  local previousShadowQuad = SpriteBillboards.shadowQuad
  SpriteBillboards.shadowQuad = function(def, frame)
    if isNurse(def) and ensureNurse() and nurse.shadowMesh then
      return nurse.shadowMesh
    end
    return previousShadowQuad(def, frame)
  end

  VoxelScene._gen1UnifiedTrue3DInstalled = true
  VoxelScene._gen1UnifiedTrue3DPreviousDrawEntity = previousDrawEntity
  mod.log:info("Gen1 TRUE 3D Characters v1.1.4 articulated arm rig installed")
end
