-- Gen4Hide: switch off Platinum's OWN grass and water where Terrarium draws its
-- 3D versions instead, so the two stop overlapping.
--
-- THE SEAM (engine untouched)
--
-- Terrain is a Gen4Model per land chunk, and Gen4Model:draw walks model.shapes
-- one material at a time. So hiding something native is "don't draw that shape".
-- This wraps Gen4Model.draw and, only while Gen4Ground:drawFree is running (the
-- free cameras -- the only ones Gen4Bridge draws into), hands draw() a filtered
-- copy of the shape list. The model's real list is put back straight after, and
-- every other pass (the CARTRIDGE rung's baked chunks, canopies, buildings'
-- depth passes) sees the world exactly as before.
--
-- WHAT IS HIDDEN
--
--   grass  The standing cards the engine stamps over wild-Pokemon grass
--          (Gen4Model.addGrassCards: a shape named "<shape>Cards", index nil).
--          The flat grass quad under them is LEFT, as the ground: removing it
--          would open a hole in the terrain under your tufts.
--   water  Terrain shapes whose material or texture is a water one: `sea`,
--          `water01`, `water02` (the three the importer measured as translucent
--          water -- see Gen4Terrain.append) plus anything in WATER_NAMES.
--
-- WHEN IT STANDS DOWN (so it can never leave a hole)
--
--   grass  when Grass3D has no bake, or the "grass" effect was disabled.
--   water  when the "water" effect was disabled or failed, or Gen4Water has not
--          finished building the sheet around the camera yet (GW.ready).
--
-- Flip Hide.grass / Hide.water to false to compare against the native look.

local V = ...

local Hide = {
  grass = true,
  water = true,
  active = false,
  installed = false,
  -- exact material/texture names (lower case) that are water
  WATER_NAMES = { sea = true, water01 = true, water02 = true },
  -- Lua patterns tried on the same names
  WATER_PATTERNS = { "^water%d" },
  -- log every distinct material/texture name seen once (to find more water names)
  LOG_NAMES = false,
}

local logged = {}
local function note(key, fmt, ...)
  if logged[key] then return end
  logged[key] = true
  if V.mod and V.mod.log then V.mod.log:info("Gen4Hide: " .. fmt:format(...)) end
end

local function optional(name)
  local ok, mod = pcall(V.require, name)
  return ok and mod or nil
end

-- ------------------------------------------------------------ classifiers --

local function lowered(s) return tostring(s or ""):lower() end

function Hide.isGrassCards(shape)
  local name = shape.name
  return shape.index == nil and type(name) == "string" and name:sub(-5) == "Cards"
end

function Hide.isWater(shape)
  for _, field in ipairs({ shape.material, shape.texture }) do
    local n = lowered(field)
    if n ~= "" then
      if Hide.WATER_NAMES[n] then return true end
      for _, pat in ipairs(Hide.WATER_PATTERNS) do
        if n:find(pat) then return true end
      end
    end
  end
  return false
end

-- ------------------------------------------------------------ per-frame --

local function grassOn()
  if not Hide.grass then return false end
  local Bridge = optional("Gen4Bridge")
  if Bridge and Bridge.disabled and Bridge.disabled.grass then return false end
  local G3 = optional("Grass3D")
  if not (G3 and G3.available) then return false end
  local ok, avail = pcall(G3.available)
  return ok and avail and true or false
end

local function waterOn()
  if not Hide.water then return false end
  local Bridge = optional("Gen4Bridge")
  if Bridge and Bridge.disabled and Bridge.disabled.water then return false end
  local GW = optional("Gen4Water")
  return GW ~= nil and GW.ready == true
end

-- model -> { key = "gw", list = {...} }
local cache = setmetatable({}, { __mode = "k" })

local function filtered(model, hideGrass, hideWater)
  local key = (hideGrass and "g" or "-") .. (hideWater and "w" or "-")
  local rec = cache[model]
  local shapes = model.shapes
  if rec and rec.key == key and rec.source == shapes and rec.count == #shapes then
    return rec.list
  end
  local list, hidden = {}, 0
  for _, shape in ipairs(shapes) do
    local drop = false
    if hideGrass and Hide.isGrassCards(shape) then
      drop = true
      note("g:" .. tostring(shape.name), "hid native grass cards '%s'", tostring(shape.name))
    elseif hideWater and Hide.isWater(shape) then
      drop = true
      note("w:" .. lowered(shape.material) .. "|" .. lowered(shape.texture),
           "hid native water (material '%s', texture '%s')",
           tostring(shape.material), tostring(shape.texture))
    end
    if Hide.LOG_NAMES then
      note("n:" .. lowered(shape.material) .. "|" .. lowered(shape.texture),
           "shape name '%s' material '%s' texture '%s'",
           tostring(shape.name), tostring(shape.material), tostring(shape.texture))
    end
    if drop then hidden = hidden + 1 else list[#list + 1] = shape end
  end
  if hidden == 0 then list = shapes end   -- nothing to hide: draw the real list
  cache[model] = { key = key, source = shapes, count = #shapes, list = list }
  return list
end

-- ---------------------------------------------------------------- install --

function Hide.install()
  if Hide.installed then return true end
  local okM, Model = pcall(require, "src.render.Gen4Model")
  local okG, Ground = pcall(require, "src.render.Gen4Ground")
  if not (okM and type(Model) == "table" and type(Model.draw) == "function"
          and okG and type(Ground) == "table" and type(Ground.drawFree) == "function") then
    return false
  end
  Hide.Model, Hide.Ground = Model, Ground
  Hide.originalDraw, Hide.originalDrawFree = Model.draw, Ground.drawFree

  local drawFilter = { grass = false, water = false }

  local originalDraw = Model.draw
  Model.draw = function(self, ...)
    if not Hide.active then return originalDraw(self, ...) end
    local real = self.shapes
    if type(real) ~= "table" then return originalDraw(self, ...) end
    local list = filtered(self, drawFilter.grass, drawFilter.water)
    if list == real then return originalDraw(self, ...) end
    self.shapes = list
    local ok, a = pcall(originalDraw, self, ...)
    self.shapes = real          -- always put the model's own list back
    if not ok then error(a, 0) end
    return a
  end

  local originalFree = Ground.drawFree
  Ground.drawFree = function(self, ...)
    drawFilter.grass, drawFilter.water = grassOn(), waterOn()
    Hide.active = drawFilter.grass or drawFilter.water
    local ok, a, b = pcall(originalFree, self, ...)
    Hide.active = false
    if not ok then error(a, 0) end
    return a, b
  end

  Hide.installed = true
  return true
end

function Hide.uninstall()
  if not Hide.installed then return end
  Hide.Model.draw = Hide.originalDraw
  Hide.Ground.drawFree = Hide.originalDrawFree
  Hide.active, Hide.installed = false, false
end

return Hide
