-- THE GREAT MARSH LOOKOUT'S BINOCULARS (Platinum), after pokeplatinum
-- src/great_marsh_lookout.c, src/overlay006/great_marsh_binoculars.c and
-- great_marsh_lookout_sprite.c -- the script command `startgreatmarshlookout`.
--
-- FIVE LOOKS (BINOCULARS_CYCLE_COUNT), then home:
--
--   * each look is one of the 36 spots of encdata_ex member 11 (drawn with
--     replacement), a MARSH tile -- the area is whichever of D06R0201..0206
--     holds it in the matrix (`MapMatrix_GetMapHeaderIDAtCoords`), the place
--     on it the tile less the area's origin;
--   * the view goes there with the player hidden (FieldTask_ChangeMapByLocation
--     between FieldTransition fades), and opens through a CIRCLE (StartScreenFade
--     FADE_MAIN_ONLY, FADE_TYPE_CIRCLE_IN, black, 6 steps);
--   * a Pokemon's front picture sits in the middle of the screen: a species
--     drawn uniformly from that area's twelve grass slots, after the marsh's
--     daily pair (slots 7 / 8 -- in or out of a Safari Game), the day / night
--     pair (3 / 4); its gender a coin toss where the species has two;
--   * 60 frames, or A, and the circle closes (FADE_TYPE_CIRCLE_OUT);
--
-- and the sixth "look" is the lookout itself, at the player's own tile,
-- faded in from black with the player shown again.
--
-- TIME: the field's 30 Hz -- one tick every other update, as the field task
-- that runs this does.

local L = {}

L.CYCLES = 5
L.HOLD = 60
L.IRIS_STEPS = 6
L.MARSH_FIRST_HEADER, L.MARSH_AREAS = 504, 6

-- the marsh area holding global tile (gx, gz), and the tile on it
function L.areaAt(data, gx, gz)
  -- the cache's own names (D06R0203); the table also carries an underscored
  -- copy of each (D_06R_0203) that is not the one to warp to
  for id, def in pairs(data and data.maps or {}) do
    local h = tonumber(def.header)
    if h and h >= L.MARSH_FIRST_HEADER and h < L.MARSH_FIRST_HEADER + L.MARSH_AREAS
       and not tostring(def.id or id):find("_", 1, true) then
      local ox, oz = def.originX or 0, def.originY or 0
      if gx >= ox and gz >= oz and gx < ox + (def.width or 32) and gz < oz + (def.height or 32) then
        return def.id or id, gx - ox, gz - oz, def
      end
    end
  end
end

-- GreatMarshBinoculars_GetMonSpecies
function L.species(game, mapDef, rng, hour)
  local data = game and game.data
  local all = data and data.encounters
  local def = all and mapDef and all[mapDef.encounters]
  local grass = def and def.grass
  if type(grass) ~= "table" or #grass == 0 then return nil end
  local list = {}
  for i, slot in ipairs(grass) do list[i] = slot.species end
  -- the marsh's daily pair, whether or not a game is running
  local Daily = require("src.world.Gen4DailySlots")
  local save = game.save or {}
  local probe = setmetatable({ safari = save.safari or true }, { __index = save })
  local daily = Daily.slotsFor(data, probe, mapDef)
  if daily then
    if daily[7] then list[7] = daily[7] end
    if daily[8] then list[8] = daily[8] end
  end
  -- the day / night pair
  local okE, E = pcall(require, "src.import.Gen4Encounters")
  if okE and E.timedGrass then
    local timed = E.timedGrass(def, hour or tonumber(os.date("%H")))
    if timed then
      for n = 3, 4 do if timed[n] then list[n] = timed[n].species end end
    end
  end
  rng = rng or function(n) return love.math.random(0, n - 1) end
  return list[rng(#list) + 1]
end

-- ---------------------------------------------------------------------------
-- The view: black, the circle opening, the Pokemon, the circle closing
-- ---------------------------------------------------------------------------

local View = {}
View.__index = View

function View.new()
  return setmetatable({ iris = 0, mode = "black", image = nil, frame = 0 }, View)
end

-- see-through: the marsh is the picture (StateStack reads this as a field)
View.isOpaque = false

-- The view's own update, at the field's 30 Hz (every other frame). While a
-- warp runs its Transition is on top and the view waits -- black, as it
-- should be.
function View:update()
  self.frame = self.frame + 1
  if self.frame % 2 == 0 then self:tick() end
end

L.active = nil

function View:tick()
  if self.mode == "opening" then
    self.iris = math.min(L.IRIS_STEPS, self.iris + 1)
    if self.iris >= L.IRIS_STEPS then self.mode = "open"; self.timer = 0 end
  elseif self.mode == "open" then
    self.timer = self.timer + 1
    local input = self.game and self.game.input
    local pressed = input and input.wasPressed and input:wasPressed("a")
    if self.timer >= L.HOLD or pressed then self.mode = "closing" end
  elseif self.mode == "closing" then
    self.iris = math.max(0, self.iris - 1)
    if self.iris <= 0 then
      self.mode = "black"
      if self.onClosed then local f = self.onClosed; self.onClosed = nil; f() end
    end
  elseif self.mode == "fading" then
    self.fade = (self.fade or 1) - 1 / 8
    if self.fade <= 0 then
      if self.onFaded then local f = self.onFaded; self.onFaded = nil; f() end
    end
  end
end

function View:draw()
  local g = love.graphics
  -- the surface being drawn on (the UI canvas the stack draws into)
  local W, H = 256, 192
  local canvas = g.getCanvas()
  if canvas then
    local okR, Renderer = pcall(require, "src.render.Renderer")
    local ok, w, h = pcall(Renderer.uiSize, Renderer)
    if okR and ok and w then W, H = w, h end
  end
  if self.mode == "fading" then
    g.setColor(0, 0, 0, math.max(0, self.fade or 0))
    g.rectangle("fill", 0, 0, W, H)
    g.setColor(1, 1, 1, 1)
    return
  end
  local cx, cy = W / 2, H / 2
  -- the circle: its radius steps from nothing to past the corners
  local full = math.sqrt(cx * cx + cy * cy)
  local r = full * (self.iris / L.IRIS_STEPS)
  if r < full then
    -- everything outside the circle black: a ring of quads from the circle
    -- out past the corners (no stencil -- the UI canvas carries none)
    g.setColor(0, 0, 0, 1)
    local R, n = full * 2 + 8, 48
    for i = 0, n - 1 do
      local a0, a1 = i / n * 2 * math.pi, (i + 1) / n * 2 * math.pi
      g.polygon("fill", cx + math.cos(a0) * r, cy + math.sin(a0) * r,
                cx + math.cos(a0) * R, cy + math.sin(a0) * R,
                cx + math.cos(a1) * R, cy + math.sin(a1) * R,
                cx + math.cos(a1) * r, cy + math.sin(a1) * r)
    end
  end
  if self.image and self.iris > 0 then
    g.setColor(1, 1, 1, 1)
    local iw, ih = self.image:getDimensions()
    g.draw(self.image, math.floor(cx - iw / 2), math.floor(cy - ih / 2))
  end
  g.setColor(1, 1, 1, 1)
end

function View:open(image, onClosed)
  self.image, self.onClosed = image, onClosed
  self.iris, self.mode = 0, "opening"
end

-- ---------------------------------------------------------------------------
-- The run
-- ---------------------------------------------------------------------------

local function frontImage(game, species)
  local Sprites = require("src.pokemon.Sprites")
  local okP, path = pcall(Sprites.path, game.data, species, "front", { kind = "battle" })
  if not (okP and path) then return nil end
  local okI, img = pcall(require("src.render.Assets").image, path)
  return okI and img or nil
end

-- run(game, ow, onDone, rng)
function L.run(game, ow, onDone, rng)
  local data = game and game.data
  local coords = data and data.gen4_special_encounters and data.gen4_special_encounters.lookoutCoords
  if not (ow and coords and #coords > 0) then
    if onDone then onDone() end
    return false
  end
  rng = rng or function(n) return love.math.random(0, n - 1) end
  local home = { map = ow.map and ow.map.id, x = ow.player.cellX, y = ow.player.cellY,
                 facing = ow.player.facing }
  local picks = {}
  -- LCRNG_RandMod(36), with replacement
  for i = 1, L.CYCLES do picks[i] = coords[rng(math.min(36, #coords)) + 1] end
  local view = View.new()
  view.game = game
  L.active = view
  game.stack:push(view)
  local cycle = 0
  local function finish()
    ow.player.hidden = nil
    view.mode, view.fade = "fading", 1
    view.onFaded = function()
      L.active = nil
      -- the view, wherever it sits now
      if game.stack:top() == view then game.stack:pop()
      else
        for i = #game.stack.states, 1, -1 do
          if game.stack.states[i] == view then table.remove(game.stack.states, i) break end
        end
      end
      if onDone then onDone() end
    end
  end
  local look
  look = function()
    cycle = cycle + 1
    if cycle > L.CYCLES then
      ow:startWarpTo(home.map, home.x, home.y, home.facing, finish)
      return
    end
    local spot = picks[cycle]
    local mapId, x, y, def = L.areaAt(data, spot.x, spot.z)
    if not mapId then return look() end
    ow.player.hidden = true
    ow:startWarpTo(mapId, x, y, "down", function()
      ow.player.hidden = true
      local species = L.species(game, def, rng)
      view:open(species and frontImage(game, species), look)
    end)
  end
  look()
  return true
end

L.View = View
return L
