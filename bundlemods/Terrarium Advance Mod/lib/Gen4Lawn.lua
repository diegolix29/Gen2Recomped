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
    imped     = { image = "transparent.png", uv = 1, whenBuilt = "Gen4Rocks", noBlend = true },
    hage      = { image = "floor.png",   uv = 1 },
    nsand     = { image = "road.png",    uv = 1 },
    nsandp    = { image = "ground.png",  uv = 1 },
    lgreen    = { image = "sand.png",    uv = 1 },
    lgreenp   = { image = "road.png",    uv = 1 },
    allpeak   = { image = "edges.png",   uv = 1 },

    -- Twinleaf / Route 201 leftover ids (from Gen4Lawn LOG_NAMES). Same swirl
    -- probes already in this folder, plus extra hues for groups that had none.
    nectgr    = { image = "highgrass.png",    uv = 1 },   -- wild-Pokemon grass floor
    nhana     = { image = "flowers.png", uv = 1 },   -- flower beds
    beach     = { image = "sand.png",    uv = 1 },
    beachp    = { image = "sand.png",    uv = 1 },
    hamabe    = { image = "sand.png",    uv = 1 },   -- shore
    seaside3  = { image = "sand.png",    uv = 1 },
    criff     = { image = "edges.png",   uv = 1 },
    criffp    = { image = "edges.png",   uv = 1 },
    searock   = { image = "edges.png",   uv = 1 },
    fenter    = { image = "step.png",    uv = 1 },
    newstep   = { image = "step.png",    uv = 1 },
    cyclestop = { image = "step.png",    uv = 1 },
    ["s_snow"]   = { image = "sdnow.png",   uv = 1 },
    ["s_snow02"] = { image = "sdnow.png",   uv = 1 },
    ["s_snow04"] = { image = "sdnow.png",   uv = 1 },
    ["s_sonwp"]  = { image = "sdnow.png",   uv = 1 },
    puddle    = { image = "waterp.png",  uv = 1 },
    puddlep   = { image = "waterp.png",  uv = 1 },
    puddle_b  = { image = "waterp.png",  uv = 1 },
    sea       = { image = "waterp.png",  uv = 1 },
    lake      = { image = "waterp.png",  uv = 1 },
    ["lakep.1"] = { image = "waterp.png", uv = 1 },
    asasea    = { image = "waterp.png",  uv = 1 },   -- shallows
    tshadow   = { image = "shadow tree.png",  uv = 1 },
    tree01    = { image = "trees.png",   uv = 1 },
    tree04_2  = { image = "trees.png",   uv = 1 },
    conttree_b = { image = "trees.png",  uv = 1 },
    conttree_t = { image = "trees.png",  uv = 1 },

    -- Jubilife (c1_*) from Route 201 land 15/17
    c1_g1     = { image = "floor.png",   uv = 1 },
    c1_r1     = { image = "road.png",    uv = 1 },
    c1_r1_k1  = { image = "road.png",    uv = 1 },
    c1_r1_k2  = { image = "road.png",    uv = 1 },
    c1_r1_ud  = { image = "road.png",    uv = 1 },
    c1_r1_lr  = { image = "road.png",    uv = 1 },
    c1_r1_s1  = { image = "road.png",    uv = 1 },
    c1_d_1    = { image = "ground.png",  uv = 1 },
    c1_d_2    = { image = "ground.png",  uv = 1 },
    c1_d_3    = { image = "ground.png",  uv = 1 },
    c1_d_4    = { image = "ground.png",  uv = 1 },
    c1_f_ud   = { image = "flowers.png", uv = 1 },
    c1_f_l    = { image = "flowers.png", uv = 1 },
    c1_f_r    = { image = "flowers.png", uv = 1 },
    c1_f_k1   = { image = "flowers.png", uv = 1 },
    c1_f_k2   = { image = "flowers.png", uv = 1 },
    c1_o02    = { image = "object.png",  uv = 1 },
    c1_o02b   = { image = "object.png",  uv = 1 },
    c1_lamp01 = { image = "lamp.png",    uv = 1 },
    c1_lamp02 = { image = "lamp.png",    uv = 1 },
  },
  DIR = "/assets/ground/grass/",
  LOG_NAMES = true,      -- log every distinct land/texture/material once (grep "Gen4Lawn:")
  -- Opaque edge treatment baked into every swapped picture (the model shader
  -- discards alpha < 0.5, so real transparency would punch holes in the mesh).
  -- Each texture is one rounded tile: corners curve in, and the rim mixes
  -- toward BLEND_IMAGE so neighbouring lawn ids share a dirt seam.
  ROUND = 0.22,          -- corner radius, 0..0.5 of the tile
  BLEND = 0.18,          -- how far the mix reaches inward from the rim
  TILES = 1,             -- rounded cells across the picture (1 = whole layer)
  BLEND_IMAGE = "ground.png",
}

local logged = {}
local function note(key, fmt, ...)
  if logged[key] then return end
  logged[key] = true
  if V.mod and V.mod.log then V.mod.log:info("Gen4Lawn: " .. fmt:format(...)) end
end

local imagePaths = {}     -- file -> path | false (missing)
local blendPaths = {}     -- file -> processed path | false | nil (untried)

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

local function smoothstep(e0, e1, x)
  if e1 == e0 then return x < e0 and 0 or 1 end
  local t = (x - e0) / (e1 - e0)
  if t < 0 then t = 0 elseif t > 1 then t = 1 end
  return t * t * (3 - 2 * t)
end

-- Signed distance to a rounded square covering 0..1. Negative is inside.
local function roundedBox(px, py, radius)
  local r = radius
  if r < 0 then r = 0 elseif r > 0.49 then r = 0.49 end
  local qx = math.abs(px - 0.5) - 0.5 + r
  local qy = math.abs(py - 0.5) - 0.5 + r
  local mx = qx > 0 and qx or 0
  local my = qy > 0 and qy or 0
  local outside = math.sqrt(mx * mx + my * my)
  local inside = qx > qy and qx or qy
  if inside > 0 then inside = 0 end
  return outside + inside - r
end

local function sampleWrap(data, w, h, x, y)
  x = x % w
  if x < 0 then x = x + w end
  y = y % h
  if y < 0 then y = y + h end
  return data:getPixel(x, y)
end

local function loadImageData(path)
  local okA, Assets = pcall(require, "src.render.Assets")
  local resolved = path
  if okA and Assets and Assets.resolve then
    local okR, got = pcall(Assets.resolve, path)
    if okR and got then resolved = got end
  end
  local ok, data = pcall(love.image.newImageData, resolved)
  if ok and data then return data end
  if okA and Assets and Assets.imageData then
    local okD, pixels = pcall(Assets.imageData, path)
    if okD and pixels then return pixels end
  end
  return nil
end

local function ensureDir(path)
  local win = path:gsub("/", "\\")
  pcall(os.execute, 'if not exist "' .. win .. '" mkdir "' .. win .. '"')
end

local function writePngFile(absPath, fileData)
  if not fileData then return false end
  local bytes = fileData.getString and fileData:getString() or tostring(fileData)
  local f = io.open(absPath, "wb")
  if not f then return false end
  f:write(bytes)
  f:close()
  return true
end

-- Bake rounded corners + a dirt rim into a copy of `file`. Fully opaque.
local function blendPath(file, skip)
  if skip or file == "transparent.png" then return resolvePath(file) end
  local hit = blendPaths[file]
  if hit ~= nil then return hit or resolvePath(file) end
  blendPaths[file] = false
  local srcPath = resolvePath(file)
  if not srcPath then return nil end
  if not (love and love.image and love.image.newImageData) then return srcPath end

  local src = loadImageData(srcPath)
  if not src then return srcPath end
  local w, h = src:getDimensions()
  if not (w and h and w > 4 and h > 4) then return srcPath end

  local mix = nil
  local blendFile = Lawn.BLEND_IMAGE
  if blendFile and blendFile ~= file then
    local mixPath = resolvePath(blendFile)
    if mixPath then mix = loadImageData(mixPath) end
  end
  local mw, mh = 1, 1
  if mix then mw, mh = mix:getDimensions() end

  local tiles = tonumber(Lawn.TILES) or 1
  if tiles < 1 then tiles = 1 end
  local radius = tonumber(Lawn.ROUND) or 0.22
  local band = tonumber(Lawn.BLEND) or 0.18
  if band < 0.02 then band = 0.02 end

  local out = love.image.newImageData(w, h)
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local r, g, b, a = src:getPixel(x, y)
      local u, v = (x + 0.5) / w, (y + 0.5) / h
      local fx, fy = (u * tiles) % 1, (v * tiles) % 1
      local sdf = roundedBox(fx, fy, radius)
      local rim = smoothstep(-band, band, sdf)
      local edge = math.min(fx, fy, 1 - fx, 1 - fy)
      local edgeMix = 1 - smoothstep(0, band, edge)
      local amt = rim
      if edgeMix > amt then amt = amt + (edgeMix - amt) * 0.65 end
      if amt < 0 then amt = 0 elseif amt > 1 then amt = 1 end
      local br, bg, bb = r * 0.72, g * 0.72, b * 0.72
      if mix then
        br, bg, bb = sampleWrap(mix, mw, mh, math.floor(u * mw), math.floor(v * mh))
      end
      r = r + (br - r) * amt
      g = g + (bg - g) * amt
      b = b + (bb - b) * amt
      if a < 1 then a = 1 end
      out:setPixel(x, y, r, g, b, a)
    end
  end

  local safe = tostring(file):gsub("[^%w%.%-_]", "_")
  local encoded = out:encode("png")
  local relDir = Lawn.DIR .. "_blend/"
  local absDir = V.path .. relDir
  ensureDir(absDir)
  local abs = absDir .. safe
  if writePngFile(abs, encoded) then
    blendPaths[file] = abs
    note("blend:" .. file, "rounded + blended %s -> %s", file, relDir .. safe)
    return abs
  end
  if love.filesystem then
    pcall(love.filesystem.createDirectory, "gen4lawn_blend")
    local rel = "gen4lawn_blend/" .. safe
    pcall(function() out:encode("png", rel) end)
    local save = love.filesystem.getSaveDirectory and love.filesystem.getSaveDirectory()
    if save and love.filesystem.getInfo and love.filesystem.getInfo(rel) then
      local saved = save .. "/" .. rel
      blendPaths[file] = saved
      return saved
    end
  end
  note("blendfail:" .. file, "could not write blended %s -- using the raw picture", file)
  blendPaths[file] = srcPath
  return srcPath
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
    local path = cfg and gate and shape.material and blendPath(cfg.image, cfg.noBlend)
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
              local texName = tostring(src.texture)
              local mapped = Lawn.TEXTURES[texName:lower()] and " mapped" or " UNMAPPED"
              note("t:" .. tostring(land) .. "|" .. texName .. "|" .. tostring(src.material),
                   "land %s texture '%s' material '%s' shape '%s'%s",
                   tostring(land), texName, tostring(src.material),
                   tostring(src.name), mapped)
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
  blendPaths = {}
end

function Lawn.uninstall()
  if not Lawn.installed then return end
  Lawn.Model.draw = Lawn.originalDraw
  Lawn.Ground.drawFree = Lawn.originalDrawFree
  Lawn.Ground.modelFor = Lawn.originalModelFor
  Lawn.installed, drawing = false, false
end

return Lawn