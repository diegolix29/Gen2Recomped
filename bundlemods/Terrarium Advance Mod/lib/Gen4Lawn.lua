-- Gen4Lawn: wear the mod's own ground pictures (grass.png, roads.png...) on chosen
-- Platinum terrain textures -- and only those. Edit Lawn.TEXTURES below.
--
-- WHY Gen4GreenGround CHANGED THE WHOLE GROUND
--
-- It asked "is this cell not tall grass, not sand, not water?" using the
-- tile behaviour byte. That byte is a MOVEMENT fact (walkable, ledge, tall
-- grass, sand...). Roads, paths, plazas, flower beds and lawn are ALL plain
-- walkable behaviour 0, so "everything that is not X" is every floor in the
-- map. Behaviour can never mean "green".
--
-- HOW THE ENGINE KNOWS WHAT IS LAWN
--
-- Terrain chunks are Gen4Models whose shapes are separate polygon layers, each
-- with its own MATERIAL/TEXTURE name (Gen4Model.lua, GRASS_MATERIALS notes):
--     ngrass      lawn            (224 shapes)
--     bf_ngrass   lawn, another area's prefix (9)
--     nectgr      wild-Pokemon grass (kept native; Gen4Grass owns it)
--     s_grass     red-soil grass clump
--     l_grass_*   standing grass wall columns
-- Roads/paths are other textures, so they are never touched.
--
-- HOW IT IS APPLIED (no overlay, no lift, no z-fight)
--
-- Gen4Model:draw(vp, pose, materials) already accepts
--     materials[<shape.material>] = { image = <path>, uv = {a,b,c,d,tx,ty} }
-- (it is how the engine animates textures). Inside Gen4Ground:drawFree this
-- wraps Model.draw and adds that entry for every lawn shape, so the SAME
-- polygons the cartridge paints as lawn are drawn with grass.png instead.
-- Cells follow the real terrain height and shape, and nothing else changes.
--
-- Install AFTER/alongside Gen4Hide (main.lua, next to Gen4Hide.install()).

local V = ...

local Lawn = {
  enabled = true,
  installed = false,
  -- texture name (lower case) -> { image = <file under assets/ground/grass/>, uv = scale }
  -- uv: 1 = one repeat per whatever the native tile covered; 0.5 = twice as large.
  TEXTURES = {
    ngrass    = { image = "grass.png", uv = 1 },     -- lawn
    bf_ngrass = { image = "grass.png", uv = 1 },     -- lawn, another area's prefix
    -- imped = the little route rocks. Native card hidden (transparent picture)
    -- ONLY on lands where Gen4Rocks has built its voxel rocks.
    imped     = { image = "transparent.png", uv = 1, whenBuilt = "Gen4Rocks" },
    hage      = { image = "floor.png",   uv = 1 },
    nsand     = { image = "road.png",    uv = 1 },
    nsandp    = { image = "ground.png",  uv = 1 },
    lgreen    = { image = "sand.png",    uv = 1 },
    lgreenp   = { image = "road.png",    uv = 1 },
    allpeak   = { image = "edges.png",   uv = 1 },
  },
  DIR = "/assets/ground/grass/",
  LOG_NAMES = false,     -- log every distinct terrain texture/material once (grep "Gen4Lawn:")
}

local logged = {}
local function note(key, fmt, ...)
  if logged[key] then return end
  logged[key] = true
  if V.mod and V.mod.log then V.mod.log:info("Gen4Lawn: " .. fmt:format(...)) end
end

local imagePaths = {}     -- file -> path | false (missing)
local function resolvePath(file)
  local hit = imagePaths[file]
  if hit ~= nil then return hit or nil end
  imagePaths[file] = false
  local okA, Assets = pcall(require, "src.render.Assets")
  if okA and Assets then
    local path = V.path .. Lawn.DIR .. file
    local okE, exists = pcall(Assets.exists, path)
    if okE and exists then imagePaths[file] = path end
  end
  if not imagePaths[file] then
    note("img:" .. file, "no %s%s -- that texture keeps its native look", Lawn.DIR, file)
  end
  return imagePaths[file] or nil
end

-- model -> { source = shapes, count = n, mats = table|false }
local cache = setmetatable({}, { __mode = "k" })

local function builtVersion()
  local ok, R = pcall(V.require, "Gen4Rocks")
  return (ok and type(R) == "table") and R.version or 0
end

local function lawnMaterials(model)
  local shapes = model.shapes
  local ver = builtVersion()
  local rec = cache[model]
  if rec and rec.source == shapes and rec.count == #shapes and rec.ver == ver then return rec.mats or nil end
  local mats = false
  for _, shape in ipairs(shapes) do
    local tex = tostring(shape.lawnTexture or ""):lower()
    local cfg = Lawn.TEXTURES[tex]
    local gate = true
    if cfg and cfg.whenBuilt then
      local ok, M = pcall(V.require, cfg.whenBuilt)
      gate = ok and type(M) == "table" and M.isBuilt and M.isBuilt(model.lawnLand) or false
    end
    local path = cfg and gate and shape.material and resolvePath(cfg.image)
    if path then
      local k = cfg.uv or 1
      mats = mats or {}
      mats[shape.material] = { image = path, uv = { k, 0, 0, k, 0, 0 } }
      note("swap:" .. tex, "swapping texture '%s' (material '%s') -> %s", tex, tostring(shape.material), cfg.image)
    end
  end
  cache[model] = { source = shapes, count = #shapes, mats = mats, ver = ver }
  return mats or nil
end

local drawing = false

function Lawn.install()
  if Lawn.installed then return true end
  local okM, Model = pcall(require, "src.render.Gen4Model")
  local okG, Ground = pcall(require, "src.render.Gen4Ground")
  if not (okM and type(Model) == "table" and type(Model.draw) == "function"
          and okG and type(Ground) == "table" and type(Ground.drawFree) == "function"
          and type(Ground.modelFor) == "function") then
    return false
  end
  Lawn.Model, Lawn.Ground = Model, Ground
  Lawn.originalDraw, Lawn.originalDrawFree, Lawn.originalModelFor =
    Model.draw, Ground.drawFree, Ground.modelFor

  -- A built terrain shape keeps its material name but not its texture name.
  -- Copy the cache record's texture on (matched by shape name, in order, like
  -- Gen4Hide does) as `lawnTexture`.
  local originalModelFor = Ground.modelFor
  Ground.modelFor = function(self, land, ...)
    local model = originalModelFor(self, land, ...)
    if model and type(model.shapes) == "table" then
      model.lawnLand = land
      pcall(function()
        local chunks = self.terrain and self.terrain.chunks
        local record = chunks and chunks[land]
        if not (record and record.shapes) then return end
        local queues = {}
        for _, src in ipairs(record.shapes) do
          local key = src.name or ""
          local q = queues[key]
          if not q then q = { at = 1 }; queues[key] = q end
          q[#q + 1] = src
        end
        for _, built in ipairs(model.shapes) do
          local q = queues[built.name or ""]
          local src = q and q[q.at]
          if src then
            q.at = q.at + 1
            built.lawnTexture = src.texture
            if Lawn.LOG_NAMES then
              note("t:" .. tostring(src.texture) .. "|" .. tostring(src.material),
                   "terrain texture '%s' material '%s'", tostring(src.texture), tostring(src.material))
            end
          end
        end
      end)
    end
    return model
  end

  local originalDraw = Model.draw
  Model.draw = function(self, viewProjection, pose, materials, ...)
    if not (drawing and Lawn.enabled) or type(self.shapes) ~= "table" then
      return originalDraw(self, viewProjection, pose, materials, ...)
    end
    local lawn = lawnMaterials(self)
    if not lawn then return originalDraw(self, viewProjection, pose, materials, ...) end
    -- merge with whatever the caller passed; the lawn entry wins only for the
    -- lawn's own material name
    local merged = {}
    if materials then for k, v in pairs(materials) do merged[k] = v end end
    for k, v in pairs(lawn) do merged[k] = v end
    return originalDraw(self, viewProjection, pose, merged, ...)
  end

  local originalFree = Ground.drawFree
  Ground.drawFree = function(self, ...)
    drawing = true
    local ok, a, b = pcall(originalFree, self, ...)
    drawing = false
    if not ok then error(a, 0) end
    return a, b
  end

  Lawn.installed = true
  return true
end

function Lawn.invalidate()
  cache = setmetatable({}, { __mode = "k" })
  imagePaths = {}
end

function Lawn.uninstall()
  if not Lawn.installed then return end
  Lawn.Model.draw = Lawn.originalDraw
  Lawn.Ground.drawFree = Lawn.originalDrawFree
  Lawn.Ground.modelFor = Lawn.originalModelFor
  Lawn.installed, drawing = false, false
end

return Lawn