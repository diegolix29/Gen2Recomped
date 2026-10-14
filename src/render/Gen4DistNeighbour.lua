-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE DISTORTION WORLD'S INACTIVE FLOOR: the floor below, drawn under this one.
--
-- Reported from play: "there were also some noticeable islands and hoppable
-- tiles missing in the distorted world still".  The islands floating below and
-- beside the walkway are the NEXT floor's terrain.  Overlay 9 keeps a second
-- land manager for it (pokeplatinum ov9_02249960.c, InitialLoadInactiveFloor):
--
--   * sDistWorldMapConnectionList: 1F -> B1F -> B2F -> B3F -> B4F -> B5F ->
--     B6F -> B7F, and the Giratina / Turnback rooms have no neighbour
--   * MapMatrix_Load(nextID), LandDataManager_SetSkipMapProps (no area_build
--     props), LandDataManager_DistortionWorldSetOffsets(the next floor's map
--     info offsets, 16 units a tile)
--   * LandData_CalculateLoadedMapMatrixIndexes in the Distortion World loads
--     matrix cells 0, 1 (and 2, 3 when the matrix is two wide), whatever the
--     player's position
--   * LandDataManager_DistortionWorldRenderInactiveFloor draws each loaded
--     chunk at its rendering position (altitude included) plus the offsets
--   * the floor's ghost props (InitInactiveGhostPropManager, the header's
--     default groups), simple props and moving platforms are all live
--
-- Every floor of this port is its own map in its own local frame (world tile
-- less its offsets), so the neighbour is drawn translated by the difference of
-- the two floors' offsets.  Its ground is an ordinary Gen4Ground for its def,
-- built once and kept while the player stays on this floor.

local Gen4Model = require("src.render.Gen4Model")

local N = {}

-- sDistWorldMapConnectionList's nextID
N.NEXT = { [573] = 574, [574] = 575, [575] = 576, [576] = 577, [577] = 579, [579] = 580, [580] = 581 }

local cache = { header = nil, ground = false }

local function game() return package.loaded["src.core.Game"] end

local function defFor(header)
  local G = game()
  for _, def in pairs((G and G.data and G.data.maps) or {}) do
    if type(def) == "table" and tonumber(def.header) == header and not def.sourceId then return def end
  end
end

local function translation(x, y, z)
  return { 1, 0, 0, x, 0, 1, 0, y, 0, 0, 1, z, 0, 0, 0, 1 }
end

-- the ground for `header`'s floor, built on first use
function N.groundFor(header)
  if cache.header == header then return cache.ground or nil end
  cache.header, cache.ground = header, false
  local G = game()
  local def = defFor(header)
  if not (def and G and G.data) then return nil end
  local Gen4Ground = require("src.render.Gen4Ground")
  local ok, g = pcall(Gen4Ground.forMap, { def = def }, G.data)
  if ok and g then cache.ground = g end
  return cache.ground or nil
end

-- InitInactiveGhostPropManager: the next floor's ghost groups as its header
-- has them, ~defaultVisiblePropGroups
local function ghostDefaults(def, info)
  local vis = tonumber(info.ghostDefaultVisible) or 0
  for _, live in ipairs(def.gen4DistGhosts or {}) do
    local g = tonumber(live.group) or 0
    live.hidden = math.floor(vis / 2 ^ g) % 2 == 0
  end
end

-- draw(ground, vp): the current floor's ground and the pass's view-projection
function N.draw(ground, vp)
  local def = ground and ground.def
  if not (def and def.gen4DistWorld) then return 0 end
  if os.getenv and os.getenv("DWNONEXT") then return 0 end
  local h = tonumber(def.header)
  local nextH = h and N.NEXT[h]
  if not nextH then return 0 end
  local G = game()
  local dw = G and G.data and G.data.gen4_distortion_world
  local here = dw and dw.maps and (dw.maps[h] or dw.maps[tostring(h)])
  local there = dw and dw.maps and (dw.maps[nextH] or dw.maps[tostring(nextH)])
  if not (here and there) then return 0 end
  local nb = N.groundFor(nextH)
  if not (nb and nb.grid) then return 0 end
  ghostDefaults(nb.def, there)
  local grid = nb.grid
  local dx = ((there.offsetX or 0) - (here.offsetX or 0)) * 16 - (nb.offsetX or 0) + (ground.offsetX or 0)
  local dy = ((there.offsetAltitude or 0) - (here.offsetAltitude or 0)) * 16
  local dz = ((there.offsetZ or 0) - (here.offsetZ or 0)) * 16 - (nb.offsetY or 0) + (ground.offsetY or 0)
  local px = nb.chunkPx
  local placement = require("src.render.Gen4Ground").placement
  nb.clock = ground.clock
  local drawn = 0
  -- the matrix cells the quadrant table loads, by matrix index
  local loaded = {}
  local cells = (grid.width >= 2) and { 0, 1, 2, 3 } or ((grid.height >= 2) and { 0, 1 } or { 0 })
  for _, i in ipairs(cells) do loaded[i] = true end
  for cy = 0, grid.height - 1 do
    for cx = 0, grid.width - 1 do
      local land = grid.land[cy * grid.width + cx + 1]
      local mvp = Gen4Model.multiply(vp, translation(cx * px + nb.half + dx, nb:chunkLift(cx, cy) + dy,
                                                     cy * px + nb.half + dz))
      local model = land and loaded[cy * grid.width + cx] and nb:liveModel(land)
      if model then
        model:draw(mvp, nil, nil, nil, nil)
        drawn = drawn + 1
      end
      -- the overlay's props stand in the world whichever chunks are loaded
      if land then
        -- SetSkipMapProps: only the overlay's own props, not the chunk's
        if placement then
          for _, object in ipairs(nb:runtimePropsFor(land) or {}) do
            local building = nb:building(object.model, object.archive)
            if building then
              Gen4Model.drawTint = object.live and object.live.tint or nil
              building:draw(Gen4Model.multiply(mvp, placement(object)), nb:oneShotPose(object, building),
                            nb:propMaterials(object, nb.clock), nil, nil)
              Gen4Model.drawTint = nil
            end
          end
        end
      end
    end
  end
  if os.getenv and os.getenv("DWNBDBG") and not N.said then
    N.said = true
    print(("[next floor] %s -> %s drew %d chunk(s) at (%d,%d,%d) grid %dx%d"):format(tostring(h), tostring(nextH),
      drawn, dx, dy, dz, grid.width, grid.height))
  end
  return drawn
end

return N
