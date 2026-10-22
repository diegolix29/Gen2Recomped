-- Run from the mod root with: texlua tools/test_gen4_npcmodels.lua
-- Stubs LOVE and the engine (no ROM) and drives the REAL Gen4NpcModels,
-- SpriteSolid, Gen4Budget, Gen4ActorCam, Mat4 and Gen4WorldHost through the
-- same wrapper chain main.lua installs.
local fails, passes = 0, 0
local function check(c, m) if c then passes = passes + 1 else fails = fails + 1; print("FAIL: " .. m) end end

local Fx = assert(loadfile("tools/spritesolid_fixture.lua"))()
local rgba, imgW, imgH = Fx.makeSheet()

-- ------------------------------------------------------------------ LOVE --
local now = 0
local meshes, images, imageDatas = {}, {}, {}
love = {
  timer = { getTime = function() return now end },
  system = { getOS = function() return "Linux" end },
  image = {
    newImageData = function(w, h, fmt, str)
      local d = { w = w, h = h, str = str }
      imageDatas[#imageDatas + 1] = d
      return d
    end,
  },
  graphics = {
    newImage = function(d) local i = { data = d, released = false }
      function i:setFilter(a, b) self.filter = a .. "/" .. b end
      function i:release() self.released = true end
      images[#images + 1] = i; return i end,
    getShader = function() end, getCanvas = function() end, setDepthMode = function() end,
  },
}

-- --------------------------------------------------------------- engine --
local drawn = {}              -- Voxel3D.draw calls
local Voxel3D = {
  FORMAT = {}, camera = nil,
  newMesh = function(verts, map)
    if #verts == 0 then return nil end
    local m = { verts = #verts, tris = #map / 3, released = false }
    function m:release() self.released = true end
    meshes[#meshes + 1] = m
    return m
  end,
  draw = function(mesh, tex, model) drawn[#drawn + 1] = { mesh = mesh, tex = tex, model = model } end,
  beginScene = function() return true end, endScene = function() end,
}
local sheetReads = 0
package.loaded["src.render.Assets"] = {
  imageData = function(path)
    sheetReads = sheetReads + 1
    if path == "missing.png" then error("no such file") end
    return {
      getDimensions = function() return imgW, imgH end,
      getFormat = function() return "rgba8" end,
      getString = function() return rgba end,
    }
  end,
  register = function(fn) package.loaded["__assets_invalidate"] = fn end,
}

-- ------------------------------------------------------------------ mod --
local V
V = { mod = { log = { warn = function(_, m) V.warnings[#V.warnings + 1] = m end } }, warnings = {} }
V.PM = {}            -- the PlayerModel stub: {} = no character model loaded
local real, cache = {}, {}
V.require = function(name)
  if name == "Voxel3D" then return Voxel3D end
  if name == "ModSetting" then error("no settings in this test") end
  if name == "VoxelState" then return { active = function() return true end } end
  if name == "PlayerModel" then return V.PM end
  if name == "FirstPerson" then
    return cache["FirstPerson"] or { cardBlend = function() return 0 end }
  end
  for _, n in ipairs({ "OverworldColosseum", "OverworldStadium", "StadiumFollower", "Gen4HdPokemon", "Wind", "Grass3D" }) do
    if name == n then return {} end
  end
  if not cache[name] then cache[name] = assert(loadfile("lib/" .. name .. ".lua"))(V) end
  return cache[name]
end
V.engineRequire = function(n) return package.loaded[n] end

-- ---------------------------------------------------------------- sprite --
local function mkSprite(over)
  local def = { id = "S1", image = "sheet.png", frames = Fx.frames, walker = true,
                facings = { down = { 0, 1, 2 }, up = { 3, 4, 5 }, left = { 6, 7, 8 }, right = { 9, 10, 11 } } }
  for k, v in pairs(over or {}) do def[k] = v end
  return { def = def, tileW = 32, tileH = 32 }
end
local function mkNpc(sprite, over)
  local e = { sprite = sprite, px = 160, py = 96, facing = "down", phase = 0, flip = false }
  function e:pose() return self.sprite, self.px, self.py, self.facing, self.phase, self.flip end
  for k, v in pairs(over or {}) do e[k] = v end
  return e
end
local function posed(e, over)
  local p = { entity = e, sprite = e.sprite, px = e.px, py = e.py, gh = 20, facing = e.facing,
              phase = e.phase, flip = e.flip, isPlayer = false }
  for k, v in pairs(over or {}) do p[k] = v end
  return p
end

local Npc = V.require("Gen4NpcModels")
Npc.install()
check(package.loaded["__assets_invalidate"] == Npc.invalidate, "install registers the sheet-change invalidator")

-- ----------------------------------------------------------- eligibility --
local state = { player = {} }
local good = mkNpc(mkSprite())
check(Npc.wants(good, state), "a walker with all four sides is wanted")
check(not Npc.wants(mkNpc(mkSprite(), { hidden = true }), state), "hidden NPC is not wanted")
check(not Npc.wants(mkNpc(mkSprite(), { fixedFrame = 3 }), state), "a fixed-frame NPC keeps its sprite")
check(not Npc.wants(mkNpc(mkSprite(), { isFollower = true }), state), "followers keep their own path")
check(not Npc.wants(mkNpc(mkSprite(), { species = 25 }), state), "wild Pokemon keep their own path")
check(not Npc.wants(mkNpc(mkSprite({ facings = false })), state), "a prop with no sides is not wanted")
do
  local half = mkSprite(); half.def.facings = { down = { 0 }, up = { 1 } }
  check(not Npc.wants(mkNpc(half), state), "a sheet missing a side is not wanted")
end
do
  local run = mkSprite({ fullCycle = true, facings = { down = { 0, 1, 2, 1 }, up = { 3, 4, 5, 4 }, left = { 6, 7, 8, 7 }, right = { 9, 10, 11, 10 } } })
  check(Npc.wants(mkNpc(run), state), "a full-cycle (run) sheet is wanted, so the player does not flicker running")
end
do local tinted = mkSprite(); tinted.palColors = { 1 }
  check(not Npc.wants(mkNpc(tinted), state), "a recoloured sprite keeps its card (the body would show the wrong colours)") end
do local big = mkSprite(); big.tileW, big.tileH = 128, 128
  check(not Npc.wants(mkNpc(big), state), "an oversize cell is not a person") end
do local pl = mkNpc(mkSprite()); state.player = pl
  check(Npc.wants(pl, state), "the player is wanted by default")
  Npc.includePlayer = false; check(not Npc.wants(pl, state), "includePlayer = false leaves the player flat")
  Npc.includePlayer = true
  pl.freeFlyAlt = 30; check(not Npc.wants(pl, state), "a free-flying player keeps its own mount path")
  pl.freeFlyAlt = 0; state.player = {} end
Npc.forced = false
check(not Npc.wants(good, state), "the setting off turns everything off")
Npc.forced = nil

-- the frame each side shows mirrors SpriteRenderer.facingFrames
do
  local function key(f) return table.concat({ f.down, f.up, f.left, f.right }, ",") end
  local d = mkSprite().def
  check(key(Npc._framesFor(d, 0, false)) == "0,3,6,9", "standing -> every side's first frame")
  check(key(Npc._framesFor(d, 1, false)) == "1,4,7,10", "stepping -> the first step")
  check(key(Npc._framesFor(d, 1, true)) == "2,5,8,11", "stepping with the flip -> the second step")
  local two = mkSprite().def; two.facings.down = { 0, 1 }
  check(Npc._framesFor(two, 1, true).down == 1, "a two-entry cycle repeats its step")
  local run = mkSprite({ fullCycle = true, facings = { down = { 0, 1, 2, 1 }, up = { 3, 4, 5, 4 }, left = { 6, 7, 8, 7 }, right = { 9, 10, 11, 10 } } }).def
  check(key(Npc._framesFor(run, 0, false)) == "0,3,6,9" and key(Npc._framesFor(run, 2, false)) == "2,5,8,11",
    "a full-cycle sheet indexes each side's cycle by phase")
  check(key(Npc._framesFor(run, 5, false)) == "1,4,7,10", "...and wraps")
  d.walker = false
  check(key(Npc._framesFor(d, 1, true)) == "0,3,6,9", "a non-walker never steps")
end

-- ------------------------------------------------- draw: sprite until ready --
local npc = mkNpc(mkSprite())
local p = posed(npc)
check(Npc.drawPose(p, nil) == false, "first sight: no body yet, the sprite keeps drawing")
check(Npc.pending() == 1, "...and the sheet is queued")
Npc.pump()
check(sheetReads == 1 and #images == 0, "pump reads the sheet once and uploads nothing yet (bodies bake their own)")
check(Npc.drawPose(p, nil) == false, "sheet ready, body not built: still the sprite")
check(Npc.pending() >= 1, "...and the body is queued")
local frames = 0
while Npc.pending() > 0 and frames < 2000 do now = now + 0.016; Npc.pump(); frames = frames + 1 end
check(Npc.pending() == 0 and #meshes == 1, "the body finishes building (" .. frames .. " frames)")
check(#images == 1 and images[1].filter == "linear/linear", "the body uploads one linear-filtered atlas (it is baked smooth)")
local ATLAS_K = V.require("SpriteSolid").DEFAULT.texScale
check(#imageDatas == 1 and imageDatas[1].w == 32 * ATLAS_K and imageDatas[1].h == 160 * ATLAS_K
      and #imageDatas[1].str == 32 * 160 * ATLAS_K * ATLAS_K * 4,
      "the atlas is four picture cells and a top cell at " .. ATLAS_K .. "x (" .. 32 * ATLAS_K .. " x " .. 160 * ATLAS_K .. ")")
Npc.FILTER = "nearest"; check(Npc.FILTER == "nearest", "(the filter is a knob)"); Npc.FILTER = "linear"
check(frames >= 1, "builds are spread over frames, not one hitch")
drawn = {}
check(Npc.drawPose(p, nil) == true, "once built the body draws")
check(#drawn == 1 and drawn[1].mesh == meshes[1] and drawn[1].tex == images[1], "with its mesh and padded sheet")
local m = drawn[1].model
check(m[4] == 168 and m[8] == 20 and m[12] == 104, "placed on the tile centre at ground height (got " .. m[4] .. "," .. m[8] .. "," .. m[12] .. ")")
check(m[1] == 1 and m[3] == 0, "facing south needs no rotation")

-- a second NPC on the same sheet shares the body and the image
local npc2 = mkNpc(npc.sprite, { px = 200 })
drawn = {}
check(Npc.drawPose(posed(npc2), nil) == true, "a second NPC on the same sheet draws at once")
check(#meshes == 1 and #images == 1 and sheetReads == 1, "...sharing one body, one atlas and one sheet read")

-- facing: first sight snaps, then eases
do
  local e = mkNpc(npc.sprite, { facing = "right" })
  drawn = {}
  Npc.drawPose(posed(e), nil)
  local c, s = drawn[1].model[1], drawn[1].model[3]
  check(math.abs(s - 1) < 1e-6 and math.abs(c) < 1e-6, "facing east on first sight is exactly a quarter turn")
  e.facing = "up"; now = now + 0.016; drawn = {}
  Npc.drawPose(posed(e), nil)
  local yaw = math.atan(drawn[1].model[3], drawn[1].model[1])
  check(yaw > math.pi / 2 + 0.05 and yaw < math.pi - 0.05, "a turn is eased, not snapped (yaw " .. string.format("%.2f", yaw) .. ")")
  for _ = 1, 30 do now = now + 0.016; drawn = {}; Npc.drawPose(posed(e), nil) end
  check(math.abs(drawn[1].model[1] + 1) < 1e-3, "and settles facing north")
end

-- walking picks the step pose and builds it on demand
do
  local e = mkNpc(npc.sprite, { phase = 1, flip = false, px = 240 })
  drawn = {}
  check(Npc.drawPose(posed(e), nil) == false, "a pose not built yet falls back to the sprite")
  local f = 0
  while Npc.pending() > 0 and f < 2000 do now = now + 0.016; Npc.pump(); f = f + 1 end
  check(Npc.drawPose(posed(e), nil) == true and #meshes == 2, "the step pose gets its own body")
  e.flip = true
  Npc.drawPose(posed(e), nil)
  while Npc.pending() > 0 and f < 4000 do now = now + 0.016; Npc.pump(); f = f + 1 end
  check(Npc.drawPose(posed(e), nil) == true and #meshes == 3, "and the other step its own")
  e.phase = 0
  drawn = {}
  Npc.drawPose(posed(e), nil)
  check(drawn[1] and drawn[1].mesh == meshes[1], "back to standing reuses the stand body")
end

-- includePlayer = false: drawPose refuses the player too
do
  local e = mkNpc(mkSprite({ id = "S2" }))
  Npc.includePlayer = false
  check(Npc.drawPose(posed(e, { isPlayer = true }), nil) == false, "drawPose refuses the player when opted out")
  Npc.includePlayer = true
end

-- ================================================================ the player
-- Player:pose() ADVANCES the surf bob / spinner / acro-hop clocks every call, so
-- the body must call it once per drawn frame, and never from wants().
do
  local poseCalls = 0
  local walk = mkSprite({ id = "PWALK" })
  local bike = mkSprite({ id = "PBIKE" })
  local surf = mkSprite({ id = "PSURF", facings = false })        -- a sheet with no sides
  local run = mkSprite({ id = "PRUN", fullCycle = true,
    facings = { down = { 0, 1, 2, 1 }, up = { 3, 4, 5, 4 }, left = { 6, 7, 8, 7 }, right = { 9, 10, 11, 10 } } })
  local pl = { sprite = walk, bikeSprite = bike, runSprite = run, surfSprite = surf,
               px = 160, py = 96, facing = "down", ph = 0, fl = false }
  function pl:pose()
    poseCalls = poseCalls + 1
    local sp = (self.surfing and self.surfSprite) or (self.onBike and self.bikeSprite)
               or (self.running and self.runSprite) or self.sprite
    return sp, self.px + (self.dx or 0), self.py - (self.hop or 0), self.facing, self.ph, self.fl, false
  end
  local st = { player = pl }
  local function drawPlayer()
    return Npc.drawPose(posed(pl, { isPlayer = true, phase = pl.ph, flip = pl.fl }), nil)
  end
  local function settle()
    local f = 0
    while f < 3000 do
      now = now + 0.5                                       -- a fresh budget each "frame"
      Npc.pump()
      if drawPlayer() then return f end
      f = f + 1
    end
    return nil
  end

  check(Npc.wants(pl, st) and poseCalls == 0, "wants() asks about the player without calling pose()")
  check(settle() ~= nil, "the player's walk sheet gets a body")
  poseCalls = 0
  drawn = {}
  check(drawPlayer() == true and poseCalls == 1, "a drawn frame calls pose() exactly once (" .. poseCalls .. ")")
  check(drawn[#drawn].model[8] == 20, "and stands on the ground")

  -- a sheet with no sides (surf here) is predicted WITHOUT calling pose()
  pl.surfing = true
  poseCalls = 0
  check(not Npc.wants(pl, st), "a state whose sheet has no sides is not wanted")
  check(drawPlayer() == false and poseCalls == 0, "...and costs no pose() call (the engine's own draw is the only one)")
  pl.surfing = false

  -- the bike sheet
  pl.onBike = true
  check(Npc.wants(pl, st), "on the bike the bike sheet is used")
  check(settle() ~= nil, "...and gets its own body")
  pl.onBike = false

  -- running: a full-cycle sheet, a different body per phase
  pl.running = true
  local before = #meshes
  pl.ph = 0; check(settle() ~= nil, "the run sheet draws")
  pl.ph = 2; check(settle() ~= nil and #meshes > before + 1, "...with a different body at another phase")
  pl.running = false; pl.ph = 0

  -- hop / spin height comes back from pose() as a smaller py: it lifts the body
  settle()
  pl.hop = 6; drawn = {}
  drawPlayer()
  check(drawn[#drawn].model[8] == 26, "a hop of 6 px lifts the body 6 (got " .. tostring(drawn[#drawn].model[8]) .. ")")
  pl.hop = 0
  -- a slide offset (stairs, ship) moves it in the world
  pl.stairExit = true; pl.dx = 3; pl.hop = -4; drawn = {}   -- hop < 0 = pose py is BELOW the entity's
  drawPlayer()
  check(drawn[#drawn].model[4] == 171 and drawn[#drawn].model[12] == 104 + 4,
    "a stairs slide moves the body sideways and along z, not up")
  pl.stairExit, pl.dx, pl.hop = nil, 0, 0

  -- third person: the body follows the continuous heading, like PlayerModel
  local realCam = V.require("Gen4ActorCam")
  cache["Gen4ActorCam"] = { worldYaw = realCam.worldYaw, freeRoam = function() return true end,
                            modelYaw = function() return 0.9 end }
  pl.facing = "down"; now = now + 5
  drawn = {}; drawPlayer()
  check(math.abs(drawn[#drawn].model[1] - math.cos(0.9)) < 1e-6, "in free roam the player turns by the continuous body yaw")
  local npcE = mkNpc(walk, { px = 400 }); drawn = {}
  Npc.drawPose(posed(npcE), nil)
  check(drawn[#drawn] and drawn[#drawn].model[1] == 1, "...but an NPC still turns by its compass facing")
  -- voxel 1ST/3RD: only the player follows the camera; NPCs keep their walk facing
  cache["Gen4ActorCam"] = { worldYaw = realCam.worldYaw, freeRoam = function() return false end }
  cache["FirstPerson"] = { cardBlend = function() return 1 end,
                           cardYaw = function() return 0.4 end }
  now = now + 5
  pl.facing = "down"; drawn = {}; drawPlayer()
  check(math.abs(drawn[#drawn].model[1] - math.cos(0.4)) < 1e-6,
    "in voxel 3rd person the player body follows camera yaw")
  npcE.facing = "down"; drawn = {}
  Npc.drawPose(posed(npcE), nil)
  check(drawn[#drawn] and drawn[#drawn].model[1] == 1,
    "...but an NPC still faces its own movement direction")
  cache["FirstPerson"] = nil
  cache["Gen4ActorCam"] = realCam

  -- a recoloured sprite falls back to the card
  walk.palColors = { 1 }
  check(not Npc.wants(pl, st), "a recoloured player sprite keeps the flat card")
  walk.palColors = nil
end

-- failures stay quiet and keep the sprite
do
  V.warnings = {}
  local bad = mkNpc(mkSprite({ id = "BAD", image = "missing.png" }))
  local pb = posed(bad)
  now = now + 1                      -- the shared budget forgets a stale frame
  Npc.drawPose(pb, nil); Npc.pump()
  check(Npc.drawPose(pb, nil) == false, "an unreadable sheet never draws")
  check(not Npc.wants(bad, state), "...and is not asked about again")
  check(#V.warnings == 1 and V.warnings[1]:find("BAD"), "...and is reported once")
  local short = mkNpc(mkSprite({ id = "SHORT", facings = { down = { 0, 1, 2 }, up = { 3, 4, 5 }, left = { 6, 7, 8 }, right = { 9, 10, 40 } } }))
  now = now + 1
  Npc.drawPose(posed(short), nil); Npc.pump()
  check(not Npc.wants(short, state), "a pose beyond the sheet is refused")
end

-- eviction and invalidate
-- A long session collects garbage; the body count must not depend on what the
-- collector did (it used to: a dropped sprite def left the count over the cap
-- forever, and every finished body was evicted at once, so nothing ever drew).
collectgarbage(); collectgarbage()
do
  local before = #meshes
  Npc.MAX_BODIES = 2
  local e = mkNpc(mkSprite({ id = "S3" }), { px = 300 })   -- a fresh sheet: a 4th body
  local f = 0
  while f < 3000 and not (e.sprite.def and Npc.drawPose(posed(e), nil)) do
    now = now + 0.016; Npc.pump(); f = f + 1
  end
  check(f < 3000, "a full cache still lets a new body through (no build/evict thrash, " .. f .. " frames)")
  local released = 0
  for _, mm in ipairs(meshes) do if mm.released then released = released + 1 end end
  check(released >= 1, "past the cap the least recently used body is released")
  local imgReleased = 0
  for _, im in ipairs(images) do if im.released then imgReleased = imgReleased + 1 end end
  check(imgReleased == released, "...and its atlas goes with it (" .. imgReleased .. " of " .. released .. ")")
  Npc.MAX_BODIES = 120
  Npc.invalidate()
  released = 0
  for _, mm in ipairs(meshes) do if mm.released then released = released + 1 end end
  imgReleased = 0
  for _, im in ipairs(images) do if im.released then imgReleased = imgReleased + 1 end end
  check(released == #meshes and imgReleased == #images, "invalidate releases every mesh and every atlas")
  check(Npc.pending() == 0, "...and clears the queue")
  drawn = {}
  check(Npc.drawPose(posed(npc), nil) == false and Npc.pending() == 1, "after a reset an NPC falls back and rebuilds")
  Npc.invalidate()
end

-- ===================================================== through Gen4WorldHost --
do
  Npc.invalidate(); meshes, drawn = {}, {}
  local calls = { freeEntity = 0 }
  local Ground = {}
  function Ground:drawFree() return true end
  function Ground:endFree() end
  function Ground:freeEntity() calls.freeEntity = calls.freeEntity + 1; return true end
  function Ground:groundY() return 20 end
  Ground.offsetX, Ground.offsetY, Ground.freeW, Ground.freeH = 0, 0, 256, 192
  function Ground:freeMode() return "third" end
  Ground.view3d = {
    x = 0, y = 50, z = 0, isFree = function() return true end,
    forward = function() return 0, -0.5, -0.86 end,
    effectiveFovY = function() return 50 end,
    matrix = function() return { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 } end,
  }
  package.loaded["src.render.Gen4Ground"] = Ground
  package.loaded["src.render.TileRenderer"] = {}
  local hostNpc = mkNpc(mkSprite({ id = "HOST" }), { px = 64, py = 48 })
  local other = mkNpc(mkSprite({ id = "HOST" }), { px = 112, py = 48, hidden = true })
  package.loaded["src.core.Game"] = { overworld = { entities = { hostNpc, other }, ghosts = {}, player = {} } }
  package.loaded["src.core.GameVersion"] = { generation = function() return 4 end }
  cache["Gen4WorldHost"] = nil
  local Host = V.require("Gen4WorldHost")
  Host.install()
  check(Host.isGen4(), "host sees a Gen 4 game")

  -- frame 1: sheet read (no body, no skip)
  Ground:drawFree(256, 192)
  check(#drawn == 0, "frame 1: nothing 3D yet")
  Ground:freeEntity(64, 48, 0, 0, 0, function() end)
  check(calls.freeEntity == 1, "frame 1: the flat sprite is drawn while the body builds")
  local f = 0
  while f < 3000 and #drawn == 0 do now = now + 0.016; Ground:drawFree(256, 192); f = f + 1 end
  check(#drawn >= 1 and drawn[#drawn].mesh == meshes[1], "the host draws the body once built (" .. f .. " frames)")
  check(Host.isSkipped(64, 48), "the host now skips that NPC's flat sprite")
  check(not Host.isSkipped(112, 48), "a hidden NPC is neither drawn nor skipped")
  local before = calls.freeEntity
  Ground:freeEntity(64, 48, 0, 0, 0, function() end)
  check(calls.freeEntity == before, "the flat sprite no longer reaches the engine")
  Ground:freeEntity(64, 48, 0, 0, 14, function() end, 40)
  check(calls.freeEntity == before + 1, "but the '!' bubble (depthLift) over that NPC still draws")
  local m2 = drawn[#drawn].model
  check(m2[4] == 72 and m2[8] == 20 and m2[12] == 56, "the body stands on the NPC's tile (got " .. m2[4] .. "," .. m2[8] .. "," .. m2[12] .. ")")
  -- the setting off puts the sprites back
  Npc.forced = false
  drawn = {}
  Ground:drawFree(256, 192)
  check(#drawn == 0 and not Host.isSkipped(64, 48), "turning it off restores the flat sprite the same frame")
  Npc.forced = nil
end

-- ===================================================== the player, through the host
do
  Npc.invalidate(); meshes, drawn = {}, {}
  local pmDraws = 0
  local Ground = package.loaded["src.render.Gen4Ground"]
  local mode = "third"
  function Ground:freeMode() return mode end
  local calls = 0
  function Ground:freeEntity() calls = calls + 1; return true end
  local poseCalls = 0
  local walk = mkSprite({ id = "PHOST" })
  local player = { sprite = walk, px = 80, py = 64, facing = "down", ph = 0, fl = false }
  function player:pose() poseCalls = poseCalls + 1; return self.sprite, self.px, self.py, self.facing, 0, false, false end
  package.loaded["src.core.Game"] = { overworld = { entities = { player }, ghosts = {}, player = player } }
  cache["Gen4WorldHost"] = nil
  local Host = V.require("Gen4WorldHost")
  Host.install()
  local f = 0
  while f < 3000 and #drawn == 0 do now = now + 0.016; Ground:drawFree(256, 192); f = f + 1 end
  check(#drawn >= 1, "the host draws the player as a body (" .. f .. " frames)")
  check(Host.isSkipped(80, 64), "and skips the player's flat sprite")
  poseCalls = 0
  Ground:drawFree(256, 192)
  check(poseCalls == 1, "each frame the host's draw calls the player's pose() once (" .. poseCalls .. ")")

  -- first person: the camera is inside the head, nothing is drawn
  mode = "first"; drawn = {}
  Ground:drawFree(256, 192)
  check(#drawn == 0 and not Host.isSkipped(80, 64), "first person draws no body and keeps the sprite path")
  mode = "third"

  -- a loaded character model wins: no body from here
  V.PM = { loaded = function() return true end, draw = function() pmDraws = pmDraws + 1; return true end }
  drawn = {}
  Ground:drawFree(256, 192)
  check(pmDraws >= 1 and #drawn == 0, "a loaded PlayerModel keeps the player (no sprite body)")
  V.PM = {}
  Npc.includePlayer = false; drawn = {}
  Ground:drawFree(256, 192)
  check(#drawn == 0 and not Host.isSkipped(80, 64), "includePlayer = false restores the flat player")
  Npc.includePlayer = true
end

print(string.format("%d passed, %d failed", passes, fails))
os.exit(fails == 0 and 0 or 1)
