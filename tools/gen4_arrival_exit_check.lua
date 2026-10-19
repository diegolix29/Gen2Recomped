-- tools/gen4_arrival_exit_check.lua
--
-- EVERY WARP LANDING ON A DS MAP HAS A WAY OUT, IN EVERY CAMERA MODE.
--
--   python tools/run_lua_check.py tools/gen4_arrival_exit_check.lua \
--     G:/Gen2Recomped/heartgold/data/generated \
--     G:/Gen2Recomped/platinum/data/generated \
--     G:/Gen2Recomped/black/data/generated
--
-- Reported from play (Android, HeartGold): stuck upstairs in Elm's lab --
-- T20R0102, reached by the outdoor stairs to the right of the lab. The room
-- has one warp, (12,6), and it is both where you land and the only way out
-- (WARP_ENTRANCE_EAST: press right into the wall). The press worked. What
-- trapped the player was the other side: the exit lands on New Bark (16,8),
-- which carries the coordinate trigger that IS the stairs' way in
-- (scr_seq_T20_010, VAR_TEMP_x4003 == 0, `Warp MAP_NEW_BARK_ELMS_LAB_2F`).
-- The overworld asked coord events on any cell change, a warp landing
-- included, so every exit put the player straight back inside -- in every
-- camera mode alike. The cartridge asks coord events only after a completed
-- step (pokeheartgold FieldSystem_ProcessStep -> FieldSystem_CheckCoordEvent).
--
-- What this checks, per cache given:
--
--   1. THE ENGINE RULES the answer depends on, asked of the source: a DS warp
--      landing does not ask its coord trigger; the free (third / first person)
--      walk asks the same press exits as the grid walk; DRAMATIC_SHAPE's own
--      free walk stands aside on Gen 4/5 maps (where it would skip them).
--   2. EVERY CAMERA MODE TURNS THE FOUR KEYS INTO ALL FOUR WORLD DIRECTIONS:
--      cartridge, every tilt rung, third and first person, orbited or not, at
--      every quarter of yaw -- so any exit reachable by a direction is
--      reachable by a key in that mode.
--   3. EVERY LANDING (each warp some other warp points at) reaches an exit:
--      a breadth-first walk over the engine's own Collision verdict (the grid
--      walk's canMove and the free walk's mayEnter are the same verdict)
--      from the landing, until a cell offers one of the engine's ways out --
--      a press warp with the wall ahead, a door ahead, a ladder, a step-onto
--      warp other than the landing, a map edge with a connection, or a
--      coordinate trigger to step onto (a scene: counted, not judged).
--   4. THE TRAP CLASS ITSELF: landings that sit inside a coordinate trigger.
--      Listed (these are what the old arrival ask set off), not failed --
--      the rule in 1 is what keeps them inert until the player steps.

package.path = './?.lua;./?/init.lua;' .. package.path
love = love or require('tests.love_stub')

local PASS, FAIL = 0, 0
local function check(cond, label)
  if cond then PASS = PASS + 1 else FAIL = FAIL + 1; print('FAIL: ' .. label) end
end

local caches = {}
for i = 1, #(arg or {}) do
  if arg[i] and arg[i] ~= '' then caches[#caches + 1] = arg[i] end
end
if #caches == 0 then
  print('usage: python tools/run_lua_check.py tools/gen4_arrival_exit_check.lua <cache dir> [...]')
  os.exit(2)
end
local VERBOSE = os.getenv('VERBOSE')

local function read(path)
  local f = io.open(path, 'rb')
  if not f then return nil end
  local s = f:read('*a'); f:close()
  return s
end

-- ============================================================ 1. the rules
local ow = read('src/world/OverworldController.lua') or ''
check(ow:match('self%.ndsWarpLanding = %(GameVersion%.isNds%(%) and not %(opts and opts%.seamless%)%)'),
      'setMap must remember a DS warp landing (not a seam crossing)')
check(ow:match('if not onLanding then self:checkCoordEventHere%(true%) end'),
      'the arrival ask must skip the coord trigger under a DS warp landing')
-- the orbital (third / first person) walk asks the press exits too
local orbital = ow:match('local freeGround = self:orbitalGroundFor%(%)(.-)self%.player%.freeInput')
check(orbital and orbital:match('checkGen4EntranceWarp%(dir%)') and orbital:match('checkHgssLadder%(dir%)')
      and orbital:match('checkEdgeExit%(dir%)'),
      'the free walk must ask the same press exits as the grid walk')
-- BW's step-onto warps (transition types 0 / 5 / 6) are taken when a step ends
check(ow:match('require%("src%.world%.Gen5Warps"%)%.stepWarpAt%(self%.map, p%.cellX, p%.cellY%)'),
      "a completed step must take BW's step-onto warps (src/world/Gen5Warps.lua)")
local fm = read('mods/DRAMATIC_SHAPE/lib/FreeMove.lua')
if fm then
  check(fm:match('def%.generation%s*==%s*4 then%s+FreeMove%.drop%(%)%s+return inner%(self%)'),
        "DRAMATIC_SHAPE's FreeMove must hand Gen 4/5 maps back to the engine's walk")
end

-- ======================================== 2. every mode reaches every way
local Gen4View = require('src.render.Gen4View')
local Gen4Camera = require('src.render.Gen4Camera')
local MODES = {}
for _, t in ipairs(Gen4Camera.TILTS) do
  local mode = (t == 'third' or t == 'first') and t or (t == 'cartridge' and 'field' or 'field3d')
  MODES[#MODES + 1] = { name = tostring(t), mode = mode }
end
local KEYS = { 'up', 'down', 'left', 'right' }
for _, m in ipairs(MODES) do
  for _, orbiting in ipairs({ false, true }) do
    for q = 0, 7 do
      local v = Gen4View.new(m.mode)
      v.orbiting, v.yaw = orbiting or nil, q * math.pi / 4
      local got = {}
      for _, k in ipairs(KEYS) do got[v:screenToWorld(k) or '?'] = true end
      check(got.up and got.down and got.left and got.right,
            ('mode %s (orbiting %s, yaw %d/8) must turn the keys into all four directions')
              :format(m.name, tostring(orbiting), q))
    end
  end
end

-- ================================================ 3 + 4. every landing
local Map = require('src.world.Map')
local Collision = require('src.world.Collision')
local Gen5Warps = require('src.world.Gen5Warps')
local GameVersion = require('src.core.GameVersion')
local DIRS = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
local ORDER = { 'up', 'down', 'left', 'right' }

-- LANDINGS KNOWN TO HAVE NO WAY OUT, each with the reason it is not a trap the
-- engine can fix (keyed by install folder : map : cell). Anything new fails.
local KNOWN = {
  ['platinum:C04GYM0101:11,0'] = "lands in the gym's back wall from C04GYM0102, a Diamond/Pearl room nothing in Platinum leads into",
  ['platinum:C10R0113:8,15'] = 'the Hall of Fame: the cartridge leaves it by the credits script, not on foot',
}

local LEDGES
local LEDGE_DIR = { east = 'right', west = 'left', north = 'up', south = 'down',
                    right = 'right', left = 'left', up = 'up', down = 'down' }

local function coordAt(def, x, y)
  for i, c in ipairs(def.coordEvents or {}) do
    local w, h = math.max(tonumber(c.width) or 1, 1), math.max(tonumber(c.height) or 1, 1)
    if x >= c.x and x < c.x + w and y >= c.y and y < c.y + h then return i, c end
  end
end

for _, dir in ipairs(caches) do
  local maps = loadfile(dir .. '/maps.lua')
  local tilesets = loadfile(dir .. '/tilesets.lua')
  maps, tilesets = maps and maps(), tilesets and tilesets()
  check(maps and tilesets, dir .. ': maps.lua and tilesets.lua must load')
  if maps and tilesets then
    local gen5, hgss = false, false
    -- a BW cache imported before its warps kept their transition type
    -- (gen5-maps-v1) cannot show the step-onto warps (src/world/Gen5Warps.lua)
    local bwTransitions = false
    for _, def in pairs(maps) do
      if type(def) == 'table' and def.gen5 then gen5 = true end
      if type(def) == 'table' and def.cameraFamily == 'hgss' then hgss = true end
      for _, wp in ipairs(type(def) == 'table' and def.gen5 and def.warps or {}) do
        if wp.transition ~= nil then bwTransitions = true end
      end
    end
    pcall(GameVersion.set, gen5 and 'black' or hgss and 'heartgold' or 'platinum')

    -- the landings: (map, warp index) some warp points at
    local landings, order = {}, {}
    for id, def in pairs(maps) do
      if type(def) == 'table' and def.generation == 4 then
        for _, w in ipairs(def.warps or {}) do
          local dest = w.destMap and maps[w.destMap]
          local k = tonumber(w.destWarp)
          local to = dest and k and dest.warps and dest.warps[k]
          if to and to.x and to.y then
            local key = w.destMap .. '#' .. k
            if not landings[key] then
              landings[key] = { map = w.destMap, x = to.x, y = to.y, from = {} }
              order[#order + 1] = key
            end
            local froms = landings[key].from
            froms[#froms + 1] = id
            local srcs = landings[key].sources or {}
            landings[key].sources = srcs
            srcs[#srcs + 1] = { map = id, x = w.x, y = w.y }
          end
        end
      end
    end
    table.sort(order)

    local matrices = loadfile(dir .. '/gen4_map_matrices.lua')
    matrices = matrices and matrices() or {}
    local function zoneAt(def, x, y)
      local mx = def.layout and matrices[def.layout]
      if not (mx and mx.headers and mx.width) then return nil end
      local wx, wy = (def.originX or 0) + x, (def.originY or 0) + y
      local cx, cy = math.floor(wx / 32), math.floor(wy / 32)
      if cx < 0 or cy < 0 or cx >= mx.width or cy >= (mx.height or 0) then return nil end
      return mx.headers[cy * mx.width + cx + 1]
    end
    local layouts = loadfile(dir .. '/map_layouts.lua')
    layouts = layouts and layouts() or nil
    local standin = tilesets.TILESET_GEN4_STANDIN
    LEDGES = standin and standin.ledgeBehaviours
    local built = {}
    local function mapFor(id)
      if built[id] == nil then
        local def = maps[id]
        -- a header with no layout of its own (no blocks) has no ground to
        -- walk: nothing lands there in play, and nothing here can read it
        -- a map that is a region of a shared grid takes its rows from
        -- map_layouts at load (MapLoader.resolveBlocks); so does this
        if not def.blocks and layouts then
          pcall(require('src.world.MapLoader').resolveBlocks, { map_layouts = layouts }, def)
        end
        if not def.blocks then built[id] = false return nil end
        local ts = tilesets[def.tileset] or tilesets.TILESET_GEN4_STANDIN
        local ok, m = pcall(Map.new, def, ts)
        built[id] = ok and m or false
      end
      return built[id] or nil
    end

    -- the engine's ways out of cell (x, y), standing still; `isLanding` when
    -- this is the cell the warp put the player on (no step has been taken)
    local function exitAt(m, def, x, y, isLanding, elevation)
      local here = m:warpAtCell(x, y)
      for _, d in ipairs(ORDER) do
        local tx, ty = x + DIRS[d][1], y + DIRS[d][2]
        local wall = m:gen4TerrainBlocked(tx, ty)
        if def.gen5 then
          -- BW: a press into a solid cell carrying a warp; a press off the
          -- warp underfoot once the player has stepped off and back
          if wall and m:inBounds(tx, ty) and m:warpAtCell(tx, ty) then return 'press ' .. d .. ' into a door' end
          if wall and here and not isLanding then return 'press ' .. d .. ' off the warp' end
        else
          if wall and m:gen4DoorAt(tx, ty) and m:warpAtCell(tx, ty) then return 'press ' .. d .. ' into a door' end
          if here and wall then
            local named = m:gen4PressWarpDir(x, y)
            if named == d or (not named and m:gen4DoorAt(x, y)) then return 'press ' .. d .. ' on the mat' end
          end
        end
        if here then
          local b = m:cellBehaviour(x, y)
          if hgss and ((b == 0x3C and d == 'up') or (b == 0x3D and d == 'down')) then return 'ladder ' .. d end
        end
        -- a map edge the player can walk over into a connection
        if not m:inBounds(tx, ty) and def.connections and next(def.connections) then
          return 'edge ' .. d
        end
        -- the HM ways on: water to surf, a waterfall or a rock wall to climb
        -- (the cartridge needs the move and the badge too -- so does the port)
        if m:inBounds(tx, ty) then
          local okW, water = pcall(m.gen4WaterAt, m, tx, ty)
          if def.gen5 then okW, water = pcall(m.gen5WaterAt, m, tx, ty) end
          if okW and water then return 'surf ' .. d .. ' (HM)' end
          local bt = m:cellBehaviour(tx, ty)
          if not def.gen5 and (bt == 0x13 or bt == 0x4B or bt == 0x4C) then return 'climb ' .. d .. ' (HM)' end
        end
      end
      if here and not isLanding then
        local arrive = m:gen4ArrivalWarpAt(x, y)
        if arrive or arrive == nil then return 'step onto a warp' end
        -- BW: a warp whose transition type a step takes (0 / 5 / 6 --
        -- src/world/Gen5Warps.lua, ov21 0x218AEAC)
        if def.gen5 and Gen5Warps.stepWarpAt(m, x, y) then return 'step onto a warp (BW transition type)' end
      end
      if not isLanding and coordAt(def, x, y) then return 'step onto a trigger' end
      -- BLACK / WHITE: a zone is a set of matrix chunks, and walking into a
      -- chunk another zone owns hands the player over to it
      -- (OverworldState:gen5ChunkHandoff) -- in the box or just past its edge
      if def.gen5 then
        for _, d in ipairs(ORDER) do
          local zx, zy = x + DIRS[d][1], y + DIRS[d][2]
          if not m:inBounds(zx, zy) or not m:gen4TerrainBlocked(zx, zy) then
            local zone = zoneAt(def, zx, zy)
            if zone and zone ~= 0 and zone ~= def.header and maps[('Z%03d'):format(zone)] then
              return 'walk ' .. d .. ' into zone ' .. zone
            end
          end
        end
        local zone = zoneAt(def, x, y)
        if zone and zone ~= 0 and zone ~= def.header and maps[('Z%03d'):format(zone)] then
          return 'stand in zone ' .. zone
        end
      end
      return nil
    end

    -- A WARP NOTHING CAN TAKE: the unused rooms' dummy warps sit in a map's
    -- walled corner -- Jubilife's (0,0) and (1,0) into the two unused houses,
    -- the condominiums' 2F (0,0) to the unused 3F. A source counts when its
    -- cell or a neighbour is open ground (BW: diagonals too, its side doors).
    local function enterable(src)
      local sdef = maps[src.map]
      if sdef.gen5Rail or sdef.gen5NoGrid then return true end
      local sm = mapFor(src.map)
      if not sm then return true end
      local diag = sdef.gen5
      -- Gen 4: a warp event on a behaviour no rule opens -- plain floor, a
      -- wall -- is a SCRIPT'S destination, never taken on foot (Platinum's
      -- leader room keeps three such warps into Diamond/Pearl's old rooms)
      if not diag then
        local b = sm:cellBehaviour(src.x, src.y)
        local opens = b == nil or sm:gen4PressWarpDir(src.x, src.y) or sm:gen4ArrivalWarpAt(src.x, src.y)
                      or sm:gen4DoorAt(src.x, src.y) or b == 0x3C or b == 0x3D
        if not opens then return false end
      end
      for oy = -1, 1 do
        for ox = -1, 1 do
          if ox == 0 or oy == 0 or diag then
            local x, y = src.x + ox, src.y + oy
            if sm:inBounds(x, y) and not sm:gen4TerrainBlocked(x, y) then return true end
          end
        end
      end
      return false
    end
    -- ...AND A MAP NOBODY REACHES (Platinum's leftover Diamond/Pearl rooms,
    -- the condominiums' unused upper floors). Reached, from the roots out:
    -- a root is a map no warp leads into (a script, Fly or a seam brings
    -- you), one with edge connections, or one of a shared overworld matrix
    -- (its seams); then any map a takeable warp in a reached map leads to.
    local incoming = {}
    for _, key in ipairs(order) do
      local L = landings[key]
      incoming[L.map] = incoming[L.map] or {}
      for _, src in ipairs(L.sources or {}) do table.insert(incoming[L.map], src) end
    end
    -- an overworld matrix names more than one header across its chunks
    local overworld = {}
    for layout, mx in pairs(matrices) do
      local seen, n = {}, 0
      for _, h in ipairs(type(mx) == 'table' and mx.headers or {}) do
        if h ~= 0 and h ~= 0xFFFF and not seen[h] then seen[h] = true; n = n + 1 end
      end
      overworld[layout] = n > 1
    end
    local reached = {}
    for id, def in pairs(maps) do
      if type(def) == 'table' and def.generation == 4
         and (not incoming[id] or (def.connections and next(def.connections))
              or (def.layout and overworld[def.layout])) then
        reached[id] = true
      end
    end
    local changed = true
    while changed do
      changed = false
      for id, srcs in pairs(incoming) do
        if not reached[id] then
          for _, src in ipairs(srcs) do
            if reached[src.map] and enterable(src) then reached[id] = true; changed = true break end
          end
        end
      end
    end
    local unreached = setmetatable({}, { __index = function(_, id) return not reached[id] end })

    local stats = { landings = 0, onTrigger = 0, failed = 0, skipped = 0, rails = 0, known = 0, dummy = 0 }
    for _, key in ipairs(order) do
      local L = landings[key]
      local def = maps[L.map]
      local m = def and def.generation == 4 and mapFor(L.map)
      -- BW's RAIL and NO-GRID zones (Castelia's streets, the bridges,
      -- Victory Road) walk on rails the importer rasterised at load; their
      -- grids here are not the ground the player walks -- not judged
      if m and (def.gen5Rail or def.gen5NoGrid) then
        m = nil
        stats.rails = stats.rails + 1
      end
      -- A LANDING NO WARP CAN REACH: every warp into it is a dummy (walled
      -- in, or a script's destination) -- skipped. One reached only from a
      -- map no warp reaches is still walked; a dead end there is listed
      -- rather than failed (a script, Fly or a leftover room brings you)
      local fromReached = false
      if m then
        local live = false
        for _, src in ipairs(L.sources or {}) do
          if enterable(src) then
            live = true
            if not unreached[src.map] then fromReached = true end
          end
        end
        if not live then
          m = nil
          stats.dummy = stats.dummy + 1
          if VERBOSE then print(('  unreachable: %s (%d,%d) <- %s'):format(L.map, L.x, L.y, table.concat(L.from, ','))) end
        end
      end
      if not m then
        stats.skipped = stats.skipped + 1
      else
        stats.landings = stats.landings + 1
        local ci, coord = coordAt(def, L.x, L.y)
        if ci then
          stats.onTrigger = stats.onTrigger + 1
          print(('  landing on a trigger: %s (%d,%d) <- %s, coord row %d (var 0x%04X == %s)')
                :format(L.map, L.x, L.y, table.concat(L.from, ','), ci, tonumber(coord.var) or 0, tostring(coord.value)))
        end
        -- breadth-first over the engine's own verdict, carrying elevation
        local elevated = def.elevationCells and m.elevationAfter and true or false
        -- keyed with whether a step has been taken: the landing itself comes
        -- round again once the player steps off and back on (a ladder or a
        -- WARP_NORTH you land on is taken by stepping back onto it)
        local function kf(x, y, e, landed)
          return ((x * 4096 + y) * 64 + ((elevated and e) or 0) % 64) * 2 + (landed and 1 or 0)
        end
        local e0 = elevated and m.cellElevation and m:cellElevation(L.x, L.y) or nil
        local seen, q, head = { [kf(L.x, L.y, e0, true)] = true }, { { L.x, L.y, e0, true } }, 1
        local found
        while head <= #q and head < 20000 and not found do
          local c = q[head]; head = head + 1
          found = exitAt(m, def, c[1], c[2], c[4], c[3])
          if not found then
            for _, d in ipairs(ORDER) do
              local mover = { cellX = c[1], cellY = c[2], facing = d, elevation = c[3] }
              local okMove = pcall(function() mover.ok = Collision.canMove(m, {}, mover, d) end)
              local nx, ny = c[1] + DIRS[d][1], c[2] + DIRS[d][2]
              if not (okMove and mover.ok) then
                -- a LEDGE is a refused step the engine turns into a hop
                -- (OverworldState:checkLedgeHop): two cells on, three for
                -- the Distortion World's double jumps
                local lb = m:cellBehaviour(nx, ny)
                local ledge = lb and LEDGES and LEDGE_DIR[LEDGES[lb] or '']
                if ledge == d then
                  local far = (lb >= 0x5A and lb <= 0x5D) and 3 or 2
                  nx, ny = c[1] + DIRS[d][1] * far, c[2] + DIRS[d][2] * far
                  okMove, mover.ok = true, m:inBounds(nx, ny)
                end
              end
              if okMove and mover.ok then
                local ne = elevated and m:elevationAfter(c[3], nx, ny, c[1], c[2]) or nil
                local k = kf(nx, ny, ne, false)
                if not seen[k] then seen[k] = true; q[#q + 1] = { nx, ny, ne, false } end
              end
            end
          end
        end
        -- BLACK / WHITE'S WALLED LANDING: no step at all from the landing,
        -- and a press puts the player on the nearest floor within two cells
        -- (OverworldState:gen5LeaveWalledLanding) -- walked on from there
        if not found and def.gen5 and #q == 1 then
          for r = 1, 2 do
            for oy = -r, r do
              for ox = -r, r do
                local x, y = L.x + ox, L.y + oy
                if not found and math.max(math.abs(ox), math.abs(oy)) == r and m:inBounds(x, y)
                   and m:isWalkableCell(x, y) and not m:warpAtCell(x, y) then
                  found = 'off a walled landing to (' .. x .. ',' .. y .. ')'
                end
              end
            end
          end
        end
        if VERBOSE then print(('  %s (%d,%d): %s'):format(L.map, L.x, L.y, tostring(found))) end
        local known = not found and KNOWN[(dir:gsub('[/' .. string.char(92) .. ']+', '/'):match('([%w_]+)/data/generated') or '') .. ':' .. L.map
                                          .. ':' .. L.x .. ',' .. L.y]
        -- a zone whose cached grid has no floor at all is an import gap, not
        -- a trap (BW's Black City / White Forest in a cache imported before
        -- src/import/Gen5DynamicCity.lua read their RD chunks)
        local floorless = false
        if not found and not known then
          floorless = true
          for y = 0, m.heightCells - 1 do
            for x = 0, m.widthCells - 1 do
              if floorless and m:isWalkableCell(x, y) and not m:warpAtCell(x, y) then floorless = false end
            end
          end
        end
        if not found and not known and not floorless and def.gen5 and not bwTransitions then
          known = 'this cache predates the BW warp transition types (re-import: gen5-maps-v1)'
        end
        if not found and not known and not floorless and not fromReached then
          known = 'reached only from maps no warp leads to (a script, Fly, or a leftover room)'
        end
        if known or floorless then
          stats.known = stats.known + 1
          print(('  known: %s (%d,%d) <- %s -- %s'):format(L.map, L.x, L.y, table.concat(L.from, ','),
                known or 'this cache holds no floor for the zone (an import gap, not a trap)'))
        else
          check(found ~= nil, ('%s: landing %s (%d,%d) <- %s has no way out (%d cells reachable)')
                :format(dir, L.map, L.x, L.y, table.concat(L.from, ','), #q))
          if not found then stats.failed = stats.failed + 1 end
        end
      end
    end
    print(('%s: %d landings checked in %d modes, %d on a trigger, %d known dead ends, %d with no way out, %d skipped (%d BW rail / no-grid zones, %d from warps nothing takes)')
          :format(dir, stats.landings, #MODES, stats.onTrigger, stats.known, stats.failed, stats.skipped, stats.rails, stats.dummy))
  end
end

print(('gen4_arrival_exit_check: %d passed, %d failed'):format(PASS, FAIL))
if FAIL > 0 then os.exit(1) end
