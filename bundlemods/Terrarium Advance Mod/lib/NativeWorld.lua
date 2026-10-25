-- NativeWorld: Gen 4 and Gen 5 share Gen4Ground / Gen4View. This is the
-- common gate and the per-generation tile-behaviour tables.
--
-- Black/White maps are cut into the same tables Platinum draws, so
-- Gen4Bridge can hook the same endFree seam. Their BEHAVIOUR NUMBERS are
-- not Platinum's: B/W tall grass is 0x04/0x05/0x21/0x08 (and dark-grass
-- 0x06/0x07/0x22/0x09), while Platinum 0x03 is very tall grass and B/W
-- 0x03 is a dirt path. Sand is Platinum 0x21 vs B/W 0x0C/0x23.
--
-- Name-based effects (trees, fences, rocks, lawn, flowers) still key off
-- Platinum texture ids. They run on Gen 5 too, and simply match nothing
-- until Unova names are added.
--
-- Night lights (Gen4Lamps / Gen4Glass -> Gen4Light / Gen4Tint) are ported:
-- see N.GEN5_LIGHTS below. Unova's texture names are NOT known to this
-- file (no ROM data was available when it was written), so the Gen 5 path
-- finds lights by (1) name patterns, (2) the SHAPE of a placed prop (a thin
-- tall post is a lamp), and (3) lit-window pixels, and it logs every
-- candidate it sees (grep "Gen4Lamps:" / "Gen4Glass:") so the tables
-- can be tightened from real names.

local V = ...

local N = {}

-- Platinum (pokeplatinum / Gen4Behaviors): what rustles and what the 3D
-- tufts plant on. Mud-with-grass is encounter grass too.
N.GEN4_GRASS = {
  [0x02] = true, -- TALL_GRASS
  [0x03] = true, -- VERY_TALL_GRASS
  [0xA6] = true, -- MUD_WITH_GRASS
  [0xA7] = true, -- MUD_DEEP_WITH_GRASS
}
N.GEN4_SAND = {
  [0x21] = true, -- SAND
}

-- Black/White (ov21, src/world/Gen5FieldRules.lua).
N.GEN5_GRASS = {
  [0x04] = true, [0x05] = true, [0x21] = true, [0x08] = true,
  [0x06] = true, [0x07] = true, [0x22] = true, [0x09] = true,
}
N.GEN5_SAND = {
  [0x0C] = true, [0x23] = true,
}

function N.generation()
  local ok, GameVersion = pcall(require, "src.core.GameVersion")
  if not (ok and GameVersion and GameVersion.generation) then return nil end
  local okGen, value = pcall(GameVersion.generation)
  return okGen and tonumber(value) or nil
end

function N.isGen4()
  return N.generation() == 4
end

function N.isGen5()
  if N.generation() == 5 then return true end
  return false
end

-- True on the cartridge 3D field (Platinum / HGSS / B/W): Gen4Ground draws
-- it. Also true when the ROM tables are already loaded as gen4_terrain
-- (B/W writes that same table) but GameVersion has not answered yet.
function N.isNative()
  local g = N.generation()
  if g == 4 or g == 5 then return true end
  local ok, Game = pcall(require, "src.core.Game")
  local data = ok and Game and Game.data
  if data and data.gen4_terrain ~= nil then return true end
  if data and data.gen5_version ~= nil then return true end
  return false
end

function N.mapIsGen5(map)
  local def = map and map.def
  if def and def.gen5 then return true end
  return N.isGen5()
end

-- Permission / behaviour byte for a 16px cell.
-- Gen 4 outdoor: the low byte of the chunk permission word (Map:blockAt
-- happens to be that byte). Gen 5: def.blocks is 0/255 collision, so
-- behaviour lives in behaviorCells / Gen4Ground:behaviourAt.
function N.behaviourAt(map, cx, cy)
  if not map then return nil end
  cx, cy = tonumber(cx), tonumber(cy)
  if not (cx and cy) then return nil end
  -- Gen4Cells reads the live crop, then the ground permission grid, then
  -- B/W behaviorCells. Map:cellBehaviour alone is nil past the crop.
  local okC, Cells = pcall(V.require, "Gen4Cells")
  if okC and Cells and type(Cells.behaviour) == "function" then
    local ok, b = pcall(Cells.behaviour, map, cx, cy)
    if ok and type(b) == "number" then return b end
  end
  if type(map.cellBehaviour) == "function" then
    local ok, b = pcall(map.cellBehaviour, map, cx, cy)
    if ok and type(b) == "number" then return b end
  end
  local ground = map.renderer and map.renderer.gen4Ground
  if ground and type(ground.behaviourAt) == "function" then
    local ok, b = pcall(ground.behaviourAt, ground, cx, cy)
    if ok and type(b) == "number" then return b end
  end
  local def = map.def
  if def and type(def.behaviorCells) == "string" then
    local w = tonumber(def.width) or 0
    local h = tonumber(def.height) or 0
    if w > 0 and cx >= 0 and cy >= 0 and cx < w and cy < h then
      local v = def.behaviorCells:byte(cy * w + cx + 1)
      if v and v ~= 255 then return v end
    end
  end
  return nil
end

local rules5
local function fieldRules()
  if rules5 ~= nil then return rules5 or nil end
  local ok, R = pcall(require, "src.world.Gen5FieldRules")
  rules5 = (ok and type(R) == "table") and R or false
  return rules5 or nil
end

function N.isGrass(map, cx, cy)
  -- Gen5FieldRules.isGrass is false (not nil) off the live crop, so it
  -- cannot be asked for neighbour-map tufts. Use it in-bounds only.
  local inMap = map and map.inBounds and map:inBounds(cx, cy)
  if N.mapIsGen5(map) then
    if inMap then
      local R = fieldRules()
      if R and type(R.isGrass) == "function" then
        local ok, r = pcall(R.isGrass, map, cx, cy)
        if ok and r ~= nil then return r and true or false end
      end
    end
    local b = N.behaviourAt(map, cx, cy)
    return b ~= nil and N.GEN5_GRASS[b] == true
  end
  local b = N.behaviourAt(map, cx, cy)
  return b ~= nil and N.GEN4_GRASS[b] == true
end

function N.isSand(map, cx, cy)
  local b = N.behaviourAt(map, cx, cy)
  if b == nil then return false end
  if N.mapIsGen5(map) then return N.GEN5_SAND[b] == true end
  return N.GEN4_SAND[b] == true
end

function N.behaviourName(value)
  if N.isGen5() then
    if N.GEN5_GRASS[value] then return "TALL_GRASS" end
    if N.GEN5_SAND[value] then return "SAND" end
    return nil
  end
  local ok, Gen4Behaviors = pcall(require, "src.import.Gen4Behaviors")
  if ok and Gen4Behaviors and type(Gen4Behaviors.name) == "function" then
    local okN, name = pcall(Gen4Behaviors.name, value)
    if okN then return name end
  end
  return nil
end

-- ------------------------------------------------------ Gen 5 night lights --
--
-- Everything the lamp / window passes need to know about Black/White that
-- Platinum gets from `Gen4Lawn.lampIds` and Gen4Glass's own tables. Edit
-- here; the passes read it live.
--
-- Units are world units: a tile is 16.
N.GEN5_LIGHTS = {
  -- exact lower-case TEXTURE (or material) names that are street lamps
  lampNames = {},
  -- substrings of a texture / material name that mark a street lamp
  lampPatterns = { "gaitou", "gaito", "streetlamp", "street_lamp", "lamp",
                   "lantern", "touro" },
  -- ...never a lamp, whatever else matches (`clamp`, shadows, water, sky)
  lampDeny = { "clamp", "kage", "shadow", "water", "kumo", "cloud", "yuki" },

  -- substrings of a texture / material name that make the whole texture a
  -- window (every opaque texel lights at night)
  glassPatterns = { "garasu", "glass", "mado", "window" },
  -- exact lower-case names forced to whole-pane glass
  glassNames = {},
  -- never scanned for glass
  glassDeny = { "kage", "shadow", "shade", "water", "sea", "kumo", "cloud",
                "snow", "yuki" },

  -- A prop whose shape is a thin tall post is a lamp even when its texture
  -- name says nothing. Turn off if it lights poles that are not lamps; the
  -- log lists every model it accepted ("Gen4Lamps: model ...").
  geometry = {
    enabled = true,
    maxFoot = 14,        -- widest side of the footprint
    minHeight = 36,      -- shorter than this is a bollard / sign
    maxHeight = 120,
    maxTris = 200,
    maxShapes = 4,
    -- a model wearing any of these is not a lamp post
    deny = { "tree", "kusa", "grass", "hana", "flower", "saku", "fence",
             "kanban", "sign", "hata", "flag", "door", "kabe", "garasu",
             "mado", "glass", "window", "kage", "shadow" },
  },
  -- a lamp-NAMED prop wider than this is a lit building, not a post
  maxNamedFoot = 40,
  minNamedHeight = 12,
  -- model ids (the object's `model`) to accept / refuse regardless of shape
  lampModels = {},
  denyModels = {},

  -- Lit-window pixels on Gen 5 art. Platinum counts texels whose channels
  -- are all >= 0.88 (white). Unova is not painted that way, so this is a bit
  -- looser; a texture with more of its picture than `maxFraction` is a wall.
  white = 0.80,
  maxFraction = 0.30,
  -- Windows baked into the CHUNK (terrain) models: names always count;
  -- the pixel test only counts when the lit part is this small a share.
  terrainByPixel = true,
  terrainMaxFraction = 0.12,
}

local function lowerName(s) return tostring(s or ""):lower() end

local function hasAny(name, list)
  if name == "" then return false end
  for _, sub in ipairs(list or {}) do
    if name:find(sub, 1, true) then return true end
  end
  return false
end

N.hasAny = hasAny

-- True when `tex` or `mat` is one of the Gen 5 street-lamp names.
function N.isLampName(tex, mat)
  local c = N.GEN5_LIGHTS
  tex, mat = lowerName(tex), lowerName(mat)
  if hasAny(tex, c.lampDeny) or hasAny(mat, c.lampDeny) then return false end
  if c.lampNames[tex] or c.lampNames[mat] then return true end
  return hasAny(tex, c.lampPatterns) or hasAny(mat, c.lampPatterns)
end

-- True when `tex` or `mat` is one of the Gen 5 window names.
function N.isGlassName(tex, mat)
  local c = N.GEN5_LIGHTS
  tex, mat = lowerName(tex), lowerName(mat)
  if hasAny(tex, c.glassDeny) or hasAny(mat, c.glassDeny) then return false end
  if c.glassNames[tex] or c.glassNames[mat] then return true end
  return hasAny(tex, c.glassPatterns) or hasAny(mat, c.glassPatterns)
end

function N.isGlassDenied(tex, mat)
  local c = N.GEN5_LIGHTS
  return hasAny(lowerName(tex), c.glassDeny) or hasAny(lowerName(mat), c.glassDeny)
end

-- Is the ground a Black/White one? The ground's own map first (a Gen 5 map
-- can be open while GameVersion has not answered), then the game.
function N.groundIsGen5(ground)
  local map = ground and ground.terrariumMap
  local def = map and map.def
  if def and def.gen5 then return true end
  return N.isGen5()
end

-- Under the open sky? On Gen 5 the importer's own flag (grid matrices are
-- outdoors, single-zone interiors are not) is trusted: Spawn.isOutdoor
-- falls back to a size guess, and B/W defs carry no `outdoor` field, so a
-- small outdoor map would be called indoors and every window left dark.
-- Returns nil when it cannot tell.
function N.outdoors(ground)
  if not ground then return nil end
  if ground.outdoors ~= nil and N.groundIsGen5(ground) then
    return ground.outdoors == true
  end
  return nil
end

return N
