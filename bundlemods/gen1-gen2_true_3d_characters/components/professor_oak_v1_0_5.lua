-- Professor Oak TRUE 3D v1.0.5
--
-- Installs the Dramatic Shape companion hook only AFTER Gen1Recomp has merged
-- all content, then matches the actual merged SPRITE_OAK record by identity/id.
-- This avoids mistaking the 2D fallback asset for the authoritative Oak key.
return function(mod)
  local markerPath = mod.assets:path("assets/professor_oak_fallback.png")

  -- Keep a useful 2D fallback for normal/non-voxel rendering.
  mod.content.sprites:patch("SPRITE_OAK", {
    image = markerPath,
    trueColor = true,
  })

  local installed = false
  local oakDef = nil
  local info = {
    marker = markerPath,
    pendingFrame = 0,
  }

  local MODEL_SCALE = 1.25

  local function install(data)
    if installed then return end

    local ds = mod.find("DRAMATIC_SHAPE")
    if not (ds and ds.exports and ds.exports.lib) then
      mod.log:error("Dramatic Shape companion API is unavailable after mods.loaded")
      return
    end

    local V = ds.exports.lib
    local Voxel3D = V.require("Voxel3D")
    local Mat4 = V.require("Mat4")
    local SpriteBillboards = V.require("SpriteBillboards")

    -- This is the merged record VoxelScene will actually receive at runtime.
    oakDef = data and data.sprites and data.sprites.SPRITE_OAK or nil
    if not oakDef then
      mod.log:error("Merged SPRITE_OAK record was not found")
      return
    end

    local function ensureModel()
      if info.mesh then return true end
      if info.failed then return false end

      local src, err = mod:read("assets/professor_oak_mesh.lua")
      if not src then
        mod.log:error("Oak mesh read failed: %s", tostring(err))
        info.failed = true
        return false
      end

      local loader = loadstring or load
      local chunk, loadErr = loader(src,
        "@" .. mod.path .. "/assets/professor_oak_mesh.lua")
      if not chunk then
        mod.log:error("Oak mesh compile failed: %s", tostring(loadErr))
        info.failed = true
        return false
      end

      local ok, meshData = pcall(chunk)
      if not ok or type(meshData) ~= "table" then
        mod.log:error("Oak mesh data failed: %s", tostring(meshData))
        info.failed = true
        return false
      end

      info.mesh = Voxel3D.newMesh(meshData.vertices or {}, meshData.indices or {})
      if not info.mesh then
        mod.log:error("Oak GPU mesh creation failed (%d vertices / %d indices)",
          #(meshData.vertices or {}), #(meshData.indices or {}))
        info.failed = true
        return false
      end

      local okTex, tex = pcall(mod.assets.image, mod.assets,
                               "assets/professor_oak_atlas.png")
      if not (okTex and tex) then
        mod.log:error("Oak texture atlas creation failed")
        info.failed = true
        return false
      end

      info.texture = tex
      pcall(tex.setFilter, tex, "linear", "linear", 8)
      pcall(tex.setWrap, tex, "clamp", "clamp")

      meshData.vertices, meshData.indices = nil, nil
      collectgarbage("step")
      mod.log:info("Oak 3D GPU mesh ready")
      return true
    end

    local function isOak(def)
      if not def then return false end
      return def == oakDef
          or def.id == "SPRITE_OAK"
          or (oakDef.image and def.image == oakDef.image)
          or def.image == markerPath
    end

    local function determinant3(m)
      if not m then return 1 end
      return m[1] * (m[6] * m[11] - m[7] * m[10])
           - m[2] * (m[5] * m[11] - m[7] * m[9])
           + m[3] * (m[5] * m[10] - m[6] * m[9])
    end

    local function anchorFromBillboard(model)
      if not model then return 8, 0, 8 end
      -- Local feet-centre of a standard character card is (8,0,0).
      return model[1] * 8 + model[4],
             model[5] * 8 + model[8],
             model[9] * 8 + model[12]
    end

    local function yawForFrame(frame, mirrored)
      local pose = (frame or 0) % 3
      if pose == 1 then return math.pi end
      if pose == 2 then
        return mirrored and (math.pi / 2) or (-math.pi / 2)
      end
      return 0
    end

    local oldMesh = SpriteBillboards.mesh
    SpriteBillboards.mesh = function(def, frame)
      if isOak(def) then
        if ensureModel() then
          info.pendingFrame = frame or 0
          return info.mesh
        end
        mod.log:warn("Oak matched but 3D mesh unavailable; using fallback card")
      end
      return oldMesh(def, frame)
    end

    local oldDraw = Voxel3D.draw
    Voxel3D.draw = function(mesh, texture, model, pull, sunModel)
      if mesh ~= info.mesh then
        return oldDraw(mesh, texture, model, pull, sunModel)
      end

      local ax, ay, az = anchorFromBillboard(model)
      local mirrored = determinant3(model) < 0
      local yaw = yawForFrame(info.pendingFrame, mirrored)
      local t = (love and love.timer and love.timer.getTime
                 and love.timer.getTime()) or os.clock()

      -- Small natural idle motion; geometry remains world-oriented, not a card.
      local swayX = math.sin(t * 1.05) * 0.06
      local swayYaw = math.sin(t * 0.88 + 0.4) * math.rad(2.0)

      local m = Mat4.translate(ax + swayX, ay, az)
      m = Mat4.mul(m, Mat4.rotateY(yaw + swayYaw))
      m = Mat4.mul(m, Mat4.scale(MODEL_SCALE, MODEL_SCALE, MODEL_SCALE))
      m = Mat4.mul(m, Mat4.translate(-8, 0, 0))

      -- This mesh is not voxel-grid-authored; prevent stray grid seams if the
      -- user's V-GRID option is enabled.
      if Voxel3D.seams then Voxel3D.seams(false) end
      local out = oldDraw(mesh, info.texture, m, 0, m)
      if Voxel3D.seams then Voxel3D.seams(true) end
      return out
    end

    installed = true
    mod.log:info("Professor Oak TRUE 3D v1.0.5 hook installed on merged SPRITE_OAK")
  end

  -- Registry content does not become authoritative until the merge completes.
  mod.events:on("mods.loaded", function(ev)
    install(ev and ev.data)
  end)
end
