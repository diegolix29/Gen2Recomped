-- PerfTest: three PERFORMANCE rows for finding what makes a phone slow.
--
-- Each row switches one suspect off so you can compare FPS with it on and off:
--
--   TILE SWAP  ON / OFF        the mod's ground texture swaps.
--                              Gen 4/5: Gen4Lawn (grass.png / mulch.png on
--                              Platinum's lawn, sand, ... materials, merged
--                              into every engine draw call) and Gen4Sand.
--                              Gen 1-2: data/tile_overrides.lua stamps
--                              (TerrainAtlas reads tilesOff()); takes effect
--                              on the next map load, the atlas is cached.
--   SKY        FULL / FLAT / OFF   Gen 4/5 sky.
--                              FULL: Sky.paint + the pre-terrain 3D layers
--                              (HorizonArt, SkyLayer clouds/birds/planes,
--                              Backdrop, scenery ring).
--                              FLAT: only the 2D banded sky (Sky.paint).
--                              OFF: Gen4Sky stands down, engine horizon back.
--   MESH FX    ON / OFF        Gen 4/5 effects that BUILD meshes: 3D trees,
--                              grass, rocks, fences, ledge piles, flowers,
--                              lamp posts, water. OFF stops their prepare,
--                              build and draw; Gen4Hide then keeps the
--                              native cards, so the world is never empty.
--
-- Nothing here changes how a feature works: it only flips the switches the
-- modules already have (Lawn.enabled, Sand.enabled, Gen4Sky.enabled,
-- Bridge.setEffect). Applied at the top of every Gen4Ground:drawFree, and
-- only when a value changed.

local V = ...

local P = {}

local ModSetting = V.require("ModSetting")

P.tiles = ModSetting.new("perfTestTiles", "TILE SWAP", { "on", "off" }, { "ON", "OFF" })
P.sky = ModSetting.new("perfTestSky", "SKY", { "full", "flat", "off" }, { "FULL", "FLAT", "OFF" })
P.mesh = ModSetting.new("perfTestMesh", "MESH FX", { "on", "off" }, { "ON", "OFF" })

-- Bridge effect names that build meshes (see Gen4Bridge.install and main.lua).
P.MESH_EFFECTS = { "water", "bump", "trees", "rocks", "fence", "flowers", "lamps", "grass" }
P.TILE_EFFECTS = { "sand", "lawn" }

local function optional(name)
  local ok, m = pcall(V.require, name)
  return ok and type(m) == "table" and m or nil
end

function P.tilesOff() return P.tiles:get() == "off" end
function P.skyMode() return P.sky:get() end
function P.meshOff() return P.mesh:get() == "off" end

-- names WE switched off, so turning a row back on never re-enables an effect
-- that Gen4Bridge disabled itself after it failed
local ours = {}

local function setEffects(Bridge, names, on)
  for _, name in ipairs(names) do
    if on then
      if ours[name] then
        Bridge.setEffect(name, true)
        ours[name] = nil
      end
    elseif not Bridge.disabled[name] then
      Bridge.setEffect(name, false)
      ours[name] = true
    end
  end
end

local applied = {}

function P.apply()
  local tiles, sky, mesh = P.tiles:get(), P.sky:get(), P.mesh:get()
  if applied.tiles == tiles and applied.sky == sky and applied.mesh == mesh then return end
  local Bridge = optional("Gen4Bridge")

  if applied.tiles ~= tiles then
    local on = tiles ~= "off"
    local Lawn, Sand = optional("Gen4Lawn"), optional("Gen4Sand")
    if Lawn then Lawn.enabled = on end
    if Sand then Sand.enabled = on end
    if Bridge then setEffects(Bridge, P.TILE_EFFECTS, on) end
  end

  if applied.sky ~= sky then
    local S = optional("Gen4Sky")
    if S then S.enabled = sky ~= "off" end
    if Bridge then
      if sky == "full" then
        if ours.sky then Bridge.setEffect("sky", true); ours.sky = nil end
      elseif not Bridge.disabled.sky then
        Bridge.setEffect("sky", false)
        ours.sky = true
      end
    end
  end

  if applied.mesh ~= mesh and Bridge then
    setEffects(Bridge, P.MESH_EFFECTS, mesh ~= "off")
  end

  applied.tiles, applied.sky, applied.mesh = tiles, sky, mesh
  if V.mod and V.mod.log and V.mod.log.info then
    pcall(V.mod.log.info, V.mod.log, string.format(
      "PerfTest: TILE SWAP %s, SKY %s, MESH FX %s", tiles, sky, mesh))
  end
end

-- Outermost drawFree wrapper: install AFTER Gen4Sky, Gen4Lawn and Gen4Hide
-- so the flags are set before their wrappers read them this frame.
function P.install()
  if P.installed then return true end
  local okG, Ground = pcall(require, "src.render.Gen4Ground")
  if not (okG and type(Ground) == "table" and type(Ground.drawFree) == "function") then
    return false
  end
  local originalFree = Ground.drawFree
  Ground.drawFree = function(self, ...)
    pcall(P.apply)
    return originalFree(self, ...)
  end
  P.installed = true
  pcall(P.apply)
  return true
end

return P
