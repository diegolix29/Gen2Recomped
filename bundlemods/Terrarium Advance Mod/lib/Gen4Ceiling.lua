-- Gen4Ceiling: interior CEILINGS for the native Gen 4 / Gen 5 world.
--
-- WHY A SEPARATE MODULE
--
-- lib/Ceiling.lua builds a room's lid and risers out of the TILEMAP: wall
-- tiles, border filler, the atlas the voxel mesher draws with. Platinum,
-- HGSS and Black/White have none of that -- src/render/Gen4Ground.lua draws
-- the cartridge's own room MODELS, which were made for a camera looking down
-- from the south and so stop where that camera stops looking: no lid, and
-- the walls end a little above head height. From a free camera (1ST / 3RD /
-- the tilt rungs) the void shows over every wall.
--
-- So the room is read from what IS there for every Gen 4/5 map, the
-- permission grid: the walkable cells are the floor, and one ring of cells
-- around them is where the model's walls stand. The lid covers that
-- footprint at the floor plus HEADROOM-GEN4 / HEADROOM-GEN5, and plain
-- plaster walls stand on its outer edge from the floor to the lid -- behind
-- the model's own walls, so they only show ABOVE them, closing the gap to
-- the lid. Drawn through Gen4Bridge (depth-tested against the real scene).
--
-- MODES match lib/Ceiling.lua: first person gets the sealed room, third
-- person whatever 3RD CEILING says (FULL / CUTAWAY / NONE), the tilt rungs a
-- cutaway when CUTAWAY is on: a hole round the player and the walls on and
-- south of the player's row left out, so the camera sees in.
--
-- THE CAMERA. The engine places the 3RD eye (Gen4View) and pulls it off
-- blocked cells only up to 32 units above the ground (clearCameraLine), so a
-- taller lid let it rise over the walls and out of the room. This wraps
-- Gen4Ground.drawFree (engine untouched): before the frame draws, the eye is
-- pulled in along the pivot line to stay inside the footprint and held under
-- the lid.

local V = ...
local Voxel3D = V.require("Voxel3D")

local G = {
  enabled = true,
  HOLE_RADIUS = 4,     -- cutaway hole, in cells round the player
  PAD = 5,             -- eye clearance under the lid
  MARGIN = 6,          -- eye clearance short of a wall
  NEAREST = 12,        -- never pull the 3RD eye closer than this
  LIVE_STALE = 0.5,
  -- plaster: the lid a shade darker than the walls
  WALL_RGB = { 0.80, 0.76, 0.70 },
  LID_SHADE = { 0.80, 0.86 },          -- checker pair, so it reads as a surface
  WALL_SHADE = { pz = 0.92, nz = 0.70, px = 0.85, nx = 0.76 },
}

local cache = nil      -- { ground, key, mesh, room, lidY }
local live = nil       -- { ground, room, lidY, t }
local texture = nil

local function status(s) _G.__ds_gen4_ceiling_status = s end

local function now()
  local ok, t = pcall(function() return love.timer.getTime() end)
  return ok and t or os.clock()
end

local function plaster()
  if texture then return texture end
  local ok, img = pcall(function()
    local d = love.image.newImageData(2, 2)
    local c = G.WALL_RGB
    for y = 0, 1 do for x = 0, 1 do d:setPixel(x, y, c[1], c[2], c[3], 1) end end
    local i = love.graphics.newImage(d)
    i:setFilter("nearest", "nearest")
    return i
  end)
  texture = ok and img or nil
  return texture
end

local function config()
  local pub = rawget(_G, "__ds_ceiling_config")
  if type(pub) == "function" then
    local ok, cfg = pcall(pub)
    if ok and type(cfg) == "table" then return cfg end
  end
  return { ceiling = true, headroom = 64, cutaway = true, third = "CUTAWAY" }
end

local function outdoors(ground)
  if ground.outdoors == false then return false end
  local map = ground.terrariumMap
  local okS, Spawn = pcall(V.require, "Gen4Spawn")
  if map and okS and type(Spawn) == "table" and Spawn.isOutdoor then
    local ok, r = pcall(Spawn.isOutdoor, map)
    if ok then return r and true or false end
  end
  return ground.outdoors == true
end

local function player()
  local okG, Game = pcall(require, "src.core.Game")
  local me = okG and Game and Game.overworld and Game.overworld.player
  if me and tonumber(me.px) and tonumber(me.py) then
    return math.floor((me.px + 8) / 16), math.floor((me.py + 8) / 16)
  end
  return nil
end

-- ------- the footprint
-- Walkable cells (permission word below 0x8000) are floor; their 8-way ring
-- is where the room's walls stand. Cells whose ground rises to the lid are
-- left out (a cave ledge is rock, not room). The lid rides one height for
-- the whole room: the commonest floor height plus the headroom.
local function footprint(ground, map, H)
  local wc = (map and (map.widthCells or (map.def and map.def.width))) or 0
  local hc = (map and (map.heightCells or (map.def and map.def.height))) or 0
  if wc <= 0 or hc <= 0 then return nil, "map has no size" end
  local floor, heights, counts = {}, {}, {}
  local any = false
  for cy = 0, hc - 1 do
    for cx = 0, wc - 1 do
      local okW, word = pcall(ground.permissionWordAt, ground, cx, cy)
      if okW and word and word < 0x8000 then
        local okY, gy = pcall(ground.groundY, ground, cx * 16 + 8, cy * 16 + 8)
        gy = (okY and tonumber(gy)) or 0
        local k = cy * wc + cx
        floor[k], heights[k] = true, gy
        local r = math.floor(gy + 0.5)
        counts[r] = (counts[r] or 0) + 1
        any = true
      end
    end
  end
  if not any then return nil, "no walkable cells" end
  local base, best = 0, -1
  for r, n in pairs(counts) do
    if n > best or (n == best and r < base) then base, best = r, n end
  end
  local lidY = base + H
  local room = {}
  for k in pairs(floor) do
    if heights[k] < lidY - 8 then room[k] = true end
  end
  local cells = {}
  for k in pairs(room) do
    local cx, cy = k % wc, math.floor(k / wc)
    for dy = -1, 1 do
      for dx = -1, 1 do
        local x, y = cx + dx, cy + dy
        if x >= 0 and y >= 0 and x < wc and y < hc then cells[y * wc + x] = true end
      end
    end
  end
  return { wc = wc, hc = hc, cells = cells, base = base,
           has = function(cx, cy)
             if cx < 0 or cy < 0 or cx >= wc or cy >= hc then return false end
             return cells[cy * wc + cx] == true
           end }, lidY
end

-- ------- the mesh, in WORLD units (map pixels + the ground's offset)
local function build(ground, room, lidY, mode, pcx, pcy)
  local ox, oz = ground.offsetX or 0, ground.offsetY or 0
  local verts, idx, quads = {}, {}, 0
  local function quad(c1, c2, c3, c4, shade)
    verts[#verts + 1] = { c1[1], c1[2], c1[3], 0.25, 0.25, shade, 0 }
    verts[#verts + 1] = { c2[1], c2[2], c2[3], 0.75, 0.25, shade, 0 }
    verts[#verts + 1] = { c3[1], c3[2], c3[3], 0.75, 0.75, shade, 0 }
    verts[#verts + 1] = { c4[1], c4[2], c4[3], 0.25, 0.75, shade, 0 }
    Voxel3D.pushQuad(idx, quads)
    quads = quads + 1
  end
  local cutaway = mode == "cutaway" and pcx ~= nil
  local y0 = room.base - 4      -- a hair below the floor, so no seam shows
  for cy = 0, room.hc - 1 do
    for cx = 0, room.wc - 1 do
      if room.has(cx, cy) then
        local x0, z0 = cx * 16 + ox, cy * 16 + oz
        local lid = true
        if cutaway then
          local d = math.max(math.abs(cx - pcx), math.abs(cy - pcy))
          if d <= G.HOLE_RADIUS then lid = false end
        end
        if lid then
          -- facing down: wound so the underside is the front face
          quad({ x0, lidY, z0 }, { x0 + 16, lidY, z0 },
               { x0 + 16, lidY, z0 + 16 }, { x0, lidY, z0 + 16 },
               G.LID_SHADE[(cx + cy) % 2 + 1])
        end
        local melt = cutaway and cy >= pcy
        if not melt then
          local S = G.WALL_SHADE
          -- one face on each side that looks OUT of the footprint, facing in
          if not room.has(cx, cy + 1) then
            local z = z0 + 16
            quad({ x0 + 16, lidY, z }, { x0, lidY, z }, { x0, y0, z }, { x0 + 16, y0, z }, S.nz)
          end
          if not room.has(cx, cy - 1) then
            quad({ x0, lidY, z0 }, { x0 + 16, lidY, z0 }, { x0 + 16, y0, z0 }, { x0, y0, z0 }, S.pz)
          end
          if not room.has(cx + 1, cy) then
            local x = x0 + 16
            quad({ x, lidY, z0 }, { x, lidY, z0 + 16 }, { x, y0, z0 + 16 }, { x, y0, z0 }, S.nx)
          end
          if not room.has(cx - 1, cy) then
            quad({ x0, lidY, z0 + 16 }, { x0, lidY, z0 }, { x0, y0, z0 }, { x0, y0, z0 + 16 }, S.px)
          end
        end
      end
    end
  end
  if quads == 0 then return nil, 0 end
  return Voxel3D.newMesh(verts, idx), quads
end

local function release()
  if cache and cache.mesh and cache.mesh.release then pcall(cache.mesh.release, cache.mesh) end
  cache = nil
end

-- Which mode this frame wants, or nil for no ceiling.
local function modeFor(ground, cfg)
  local view = ground.view3d
  local m = view and view.mode
  if m == "first" then return "fp" end
  if m == "third" then
    local want = cfg.third or "CUTAWAY"
    if want == "FULL" then return "fp" end
    if want == "CUTAWAY" then return "cutaway" end
    return nil
  end
  if cfg.cutaway then return "cutaway" end
  return nil
end

function G.draw(scene)
  live = nil
  if not G.enabled then return end
  local ground = scene and scene.ground
  if not ground then return end
  local cfg = config()
  if cfg.ceiling == false then status("ceiling switched off") return end
  if outdoors(ground) then status("outdoors -- untouched by design") return end
  local map = ground.terrariumMap or scene.map
  if not map then status("no map") return end
  local mode = modeFor(ground, cfg)
  if not mode then status("this rung has no ceiling by choice") return end
  local H = tonumber(cfg.headroom) or 64
  local pcx, pcy
  if mode == "cutaway" then pcx, pcy = player() end
  local key = table.concat({ mode, H, pcx or "-", pcy or "-" }, ":")
  if not cache or cache.ground ~= ground or cache.key ~= key then
    -- the footprint only depends on the room and the headroom
    local room, lidY
    if cache and cache.ground == ground and cache.H == H and cache.room then
      room, lidY = cache.room, cache.lidY
    else
      local r, l = footprint(ground, map, H)
      room, lidY = r, l
      if not room then
        release()
        cache = { ground = ground, key = key, H = H, note = tostring(l) }
        status("no footprint: " .. tostring(l))
        return
      end
    end
    if cache and cache.mesh and cache.mesh.release then pcall(cache.mesh.release, cache.mesh) end
    local mesh, quads = build(ground, room, lidY, mode, pcx, pcy)
    cache = { ground = ground, key = key, H = H, room = room, lidY = lidY,
              mesh = mesh, note = ("%d quads, lid at %d, %s"):format(quads or 0, lidY, mode) }
  end
  if not cache.mesh then status("nothing built (" .. tostring(cache.note) .. ")") return end
  local tex = plaster()
  if not tex then return end
  live = { ground = ground, room = cache.room, lidY = cache.lidY, t = now() }
  status("DRAWING " .. cache.note)
  pcall(Voxel3D.seams, false)
  pcall(Voxel3D.glass, false)
  -- seen from inside AND (cutaway rungs) from above: no culling
  if love.graphics.setMeshCullMode then pcall(love.graphics.setMeshCullMode, "none") end
  pcall(Voxel3D.draw, cache.mesh, tex, nil, 0, nil, 0, false)
  pcall(Voxel3D.seams, true)
  pcall(Voxel3D.glass, true)
end

-- { room, lidY } for `ground` while its ceiling is on screen
function G.lid(ground)
  if not live or live.ground ~= ground then return nil end
  if now() - (live.t or 0) > G.LIVE_STALE then return nil end
  return live
end

-- ------- the 3RD eye, kept inside the room and under the lid
function G.clampCamera(ground)
  local lid = G.lid(ground)
  local v = ground and ground.view3d
  if not (lid and v and v.mode == "third") then return end
  local cap = math.max(lid.lidY - G.PAD, lid.room.base + 8)
  local px, py, pz = v.pivotX, v.pivotY, v.pivotZ
  if px and py and pz and v.x and v.y and v.z then
    local ox, oz = ground.offsetX or 0, ground.offsetY or 0
    local dx, dy, dz = v.x - px, v.y - py, v.z - pz
    local len = math.sqrt(dx * dx + dy * dy + dz * dz)
    if len > G.NEAREST then
      local hit
      for d = 2, len, 2 do
        local f = d / len
        local tx = math.floor((px + dx * f - ox) / 16)
        local ty = math.floor((pz + dz * f - oz) / 16)
        if not lid.room.has(tx, ty) then hit = d break end
      end
      if hit then
        local keep = math.max(G.NEAREST, hit - G.MARGIN)
        if keep < len then
          local t = keep / len
          v.x, v.y, v.z = px + dx * t, py + dy * t, pz + dz * t
        end
      end
    end
  end
  if v.y > cap then v.y = cap end
end

-- Wrap Gen4Ground.drawFree once: the engine has placed (and ground-clamped)
-- the eye by then, and drawFree builds its matrix from it.
function G.install()
  local ok, Ground = pcall(require, "src.render.Gen4Ground")
  if not (ok and type(Ground) == "table" and type(Ground.drawFree) == "function") then
    return false
  end
  local token = {}
  Ground.__terrariumCeilingToken = token
  local original = Ground.drawFree
  Ground.drawFree = function(self, ...)
    if Ground.__terrariumCeilingToken == token and G.enabled then
      pcall(G.clampCamera, self)
    end
    return original(self, ...)
  end
  return true
end

function G.invalidate()
  release()
  live = nil
  if texture and texture.release then pcall(texture.release, texture) end
  texture = nil
end

status("loaded; awaiting a Gen 4/5 interior")

return G
