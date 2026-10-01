-- HD Reloded 2D cards for roamers and followers in Platinum's own 3D world.
--
-- Gen 4 does not run VoxelScene. This pass is registered on Gen4Bridge so it
-- draws into the still-open Gen4Ground free canvas (colour + depth), depth-
-- tested against NSBMD terrain. Stadium / Colosseum models still win: those
-- are drawn earlier by Gen4WorldHost, which marks Host._drew3d so this pass
-- leaves them alone.

local V = ...

local Voxel3D = V.require("Voxel3D")
local Mat4 = V.require("Mat4")
local SpriteBillboards = V.require("SpriteBillboards")

local Hd = {}

local function hdModule()
  local HD = V.HDPokemonSheets or (V.mod and V.mod.exports and V.mod.exports.hdPokemonSheets)
  if HD then return HD end
  local ok, m = pcall(V.require, "HDPokemonSheets")
  if ok and type(m) == "table" then
    V.HDPokemonSheets = m
    return m
  end
  return nil
end

local function gameOf()
  local ok, Game = pcall(require, "src.core.Game")
  if not (ok and Game) then return nil end
  if type(Game.get) == "function" then
    local inst = Game:get()
    if inst then return inst end
  end
  return Game
end

function Hd.isFollower(e)
  if type(e) ~= "table" then return false end
  return e.isFollower == true or e.wildsFollower == true
    or e.pikachuFollower == true or e.follower == true
    or e._wildsFollowerSpecies ~= nil
end

function Hd.wantsEntity(e, state)
  if type(e) ~= "table" or e.hidden then return false end
  if state and e == state.player then return false end
  if Hd.isFollower(e) or e.roamer or e.overworldWildSpawn then return true end
  if e.species or e._wildsFollowerSpecies then return true end
  local def = e.sprite and e.sprite.def
  return def ~= nil and (def.hdDex ~= nil or def.dsSpecies ~= nil)
end

local function bindOverlay(e, facing, game)
  local HD = hdModule()
  if not (HD and type(HD.bindOverworldDef) == "function") then return nil end
  local sprite = e.sprite
  local base = sprite and sprite.def
  if type(base) ~= "table" then return nil end
  local data = game and game.data
  local dex = tonumber(base.hdDex)
    or (HD.dexOf and (HD.dexOf(e, data) or HD.dexOf(base.dsSpecies, data)
                      or HD.dexOf(base.hdDex, data)))
  if not dex then return nil end
  return HD.bindOverworldDef(e, base, {
    dex = dex,
    facing = HD.sheetFacing(facing, Hd.isFollower(e) and "follower" or "roamer"),
    shiny = e.shiny or e.isShiny,
    game = game,
    key = "g4:" .. tostring(e) .. ":" .. tostring(dex),
  })
end

local function cardMatrix(wx, gy, wz, worldW, ground)
  local Cam = V.require("Gen4ActorCam")
  local yaw = 0
  if Cam and Cam.cardYaw then
    yaw = Cam.cardYaw(wx, wz, ground) or 0
  end
  local half = (worldW or 16) / 2
  local m = Mat4.translate(wx, gy, wz)
  if yaw ~= 0 then m = Mat4.mul(m, Mat4.rotateY(yaw)) end
  return Mat4.mul(m, Mat4.translate(-half, 0, 0))
end

local function spriteKey(mapX, mapY)
  return string.format("%d:%d", math.floor((mapX or 0) + 0.5),
                       math.floor((mapY or 0) + 0.5))
end

local function drawOne(e, mapX, mapY, scene, game, drew3d)
  if not Hd.wantsEntity(e) then return end
  if drew3d and drew3d[spriteKey(mapX, mapY)] then return end
  local overlay = bindOverlay(e, e.facing or "down", game)
  if not overlay or not overlay.hdImage then return end
  local mesh = SpriteBillboards.mesh(overlay, 0)
  if not mesh then return end
  local _, _, worldW, worldH = SpriteBillboards.getSpriteDimensions(overlay, 0)
  local gy = 0
  if scene.groundY then
    gy = scene.groundY((mapX or 0) + 8, (mapY or 0) + 8) or 0
  end
  local wx, wz = scene.toWorld(mapX or 0, mapY or 0)
  Voxel3D.draw(mesh, overlay.hdImage,
               cardMatrix(wx + 8, gy, wz + 8, worldW, scene.ground),
               worldH and 0 or nil)
end

function Hd.draw(scene)
  if not scene or type(scene.toWorld) ~= "function" then return end
  local game = gameOf()
  local ow = game and game.overworld
  if not ow then return end
  local Host
  do
    local ok, h = pcall(V.require, "Gen4WorldHost")
    if ok then Host = h end
  end
  local drew3d = Host and Host._drew3d
  local prevGlass
  if Voxel3D.glass then
    prevGlass = Voxel3D.glass(false)
  end
  scene.opaque()
  for _, e in ipairs(ow.entities or {}) do
    drawOne(e, e.px, e.py, scene, game, drew3d)
  end
  for _, g in ipairs(ow.ghosts or {}) do
    local npc = g and g.npc
    if npc then
      drawOne(npc, (npc.px or 0) + (g.ox or 0), (npc.py or 0) + (g.oy or 0),
              scene, game, drew3d)
    end
  end
  if Voxel3D.glass and prevGlass ~= nil then
    Voxel3D.glass(prevGlass)
  end
end

return Hd
