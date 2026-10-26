-- The maps Emerald 3DS has not modelled yet, stood up by this mod.
--
-- Emerald 3DS raises terrain only where it was modelled or read off its
-- drawing (relief.bin); everything else it leaves flat.  This fills that gap
-- with the same machinery: it writes a relief lattice for the map -- 25
-- heights a cell, in pixels, a point's depth its height -- exactly as
-- relief.bin would, so the builder's relief, cliff walls, the characters'
-- lift and the camera all treat it as Emerald 3DS's own.
--
-- What stands up comes from Emerald 3DS's own reading of every cell
-- (regions.bin, voxel_cells.py's roles) and the 45-degree rule its relief is
-- built on: a point lifted h is drawn h further south, so a band of rock
-- drawn k cells tall is a face k levels high when each of its cells drops a
-- level from its north edge to its south edge -- the drop and the move south
-- cancel, the face stands vertical, and the picture stays where the GBA drew
-- it.
--
--   * a run of CLIFF cells just north of open ground is a face, a level a
--     cell, standing on that ground; the rock behind it (SHELF, CLIFF) is
--     its top, at the face's height; rock with no face of its own takes its
--     neighbours' height.  Caves (Meteor Falls), the sea floor under the
--     water, Mt. Pyre, and the rocks of outdoor maps without relief.
--   * an unmodelled building (WALL) stands the same way: its lowest rows a
--     front face, the rest its roof.
--   * Fortree's tree houses: the plank decks and the walkways between them
--     (behaviours NO_RUNNING and FORTREE_BRIDGE) are raised as high as their
--     ladders are long, the ladders drop straight down to the ground, and a
--     hut on a deck stands on it (its roof and front read as rock, its door
--     part of the front).
--
-- Used only where Emerald 3DS has no relief and no model for the layout (and
-- in Fortree); a cell one of its models owns is left to the model.

local V = ...
local Data = V.require("Data")

local Generic = {}

local R = Data.ROLE
local MB_NO_RUNNING, MB_FORTREE_BRIDGE = 0x0A, 0x78
local FACE_CAP = 3      -- the tallest face read off one band of cliff, levels
local LEVEL_CAP = 8     -- the highest any floor is stood

local function isDoor(b)
  return b >= 0x60 and b <= 0x6F and b ~= 0x63 and b ~= 0x64
end

-- Should this map be stood up here?  Only where Emerald 3DS has neither
-- relief nor a single model for the layout -- a map it has started on is its
-- to finish -- and Fortree, whose tree houses it has not modelled (its
-- Pokemon Center and Mart, which it has, keep their models).
-- Emerald 3DS's relief for a layout that is drawn with cliffs but stands no
-- point more than a level up is its first pass, not yet on terraces
-- (Sootopolis' crater, VOXEL_STATUS): stood up here instead.
local function shallow(layout)
  local L = Data.relief and Data.relief.layouts[layout]
  if not (L and L.drawn) or Data.reliefTop(layout) > 16 then return false end
  local R0 = Data.regions and Data.regions.layouts[layout]
  if not R0 then return false end
  local cliffs = 0
  for y = 0, R0.h - 1 do
    for x = 0, R0.w - 1 do
      if Data.roleAt(layout, x, y) == R.CLIFF then cliffs = cliffs + 1 end
    end
  end
  return cliffs >= 100
end

-- Switched off (2026-10-24, at the player's request): every map is drawn
-- with Emerald 3DS's own data only, the maps it has not modelled flat as on
-- the 3DS.  true stands them up again.
Generic.ENABLED = false

-- Decide, once a layout, whether its relief is stood up here instead.
function Generic.checkOverride(layout)
  if not Generic.ENABLED then Data.override[layout] = false return end
  if Data.override[layout] == nil then Data.override[layout] = shallow(layout) end
end

function Generic.applies(layout, fortree, cave)
  Generic.checkOverride(layout)
  if not Generic.ENABLED then return false end
  if Data.reliefLayout(layout) then return false end
  if not Data.regions or not Data.regions.layouts[layout] then return false end
  local P = Data.placements(layout)
  -- (a cave it has placed a few models in but whose rock it has not stood
  -- up -- Meteor Falls 1F -- has its rock stood up here around them)
  if P and #P > 0 and not fortree and not cave and not Data.override[layout] then return false end
  return true
end

-- THE BATTLE PYRAMID'S FLOOR is put together while the game runs, from
-- sixteen of its 8x8 squares (src/script/Gen3BattlePyramid.lua), so its own
-- layout says nothing of what is drawn.  Each quarter of the live floor is
-- matched, tile by tile, against the squares, and reads its roles from the
-- square it is.  nil for every other map.
function Generic.pyramidRoles(map, W, H)
  local def = map and map.def
  if not (def and def.id == "MAP_G26_N26" and W == 32 and H == 32) then return nil end
  local okG, Game = pcall(require, "src.core.Game")
  local data = okG and Game and Game.data
  if not (data and data.maps) then return nil end
  local squares = {}
  for i = 0, 15 do
    local sq = data.maps[("MAP_G25_N%02d"):format(44 + i)]
    if sq and type(sq.blocks) == "string" then squares[#squares + 1] = sq end
  end
  local function tile(str, k) return (str:byte(k * 2 + 1) + str:byte(k * 2 + 2) * 256) % 1024 end
  local pick = {}
  for q = 0, 15 do
    local qx, qy = (q % 4) * 8, math.floor(q / 4) * 8
    local best, bestN = nil, -1
    for _, sq in ipairs(squares) do
      local n = 0
      for y = 0, 7 do
        for x = 0, 7 do
          local ok, id = pcall(map.blockAt, map, qx + x, qy + y)
          if ok and id and #sq.blocks >= (y * 8 + x + 1) * 2 and id % 1024 == tile(sq.blocks, y * 8 + x) then n = n + 1 end
        end
      end
      if n > bestN then best, bestN = sq, n end
    end
    pick[q] = best
  end
  return function(x, y)
    local sq = pick[math.floor(y / 8) * 4 + math.floor(x / 8)]
    if not (sq and sq.layoutId) then return R.FLOOR end
    return Data.roleAt(sq.layoutId, x % 8, y % 8)
  end
end

-- The lattice of a cell whose north edge stands at level n and south edge
-- at level s (levels of 16 pixels): heights and depths, as Data.reliefCell
-- returns them.
local function lattice(n, s)
  local g = {}
  for c = 0, 4 do
    local h = (n + (s - n) * c / 4) * 16
    for a = 0, 4 do g[c * 5 + a] = h end
  end
  return g
end

-- Build the lattice table for one map: y * 256 + x -> { g, d }.
-- `block(x, y)` the metatile, `behaviour(id)` its behaviour,
-- `walkable(x, y)`, `owned(x, y, id)` a model's cell.
function Generic.build(layout, W, H, opts)
  local block, behaviour, walkable, owned = opts.block, opts.behaviour, opts.walkable, opts.owned
  local fortree = opts.fortree
  local role, beh = {}, {}
  -- the cartridge's own elevation of every cell: floors at different
  -- elevations are different floors even where they touch (a bridge over a
  -- path, the corridor running under it); 15 is the bridge's own (it counts
  -- with the upper floor, 4), 0 is none
  local elevOf = opts.elevation or function() return 0 end
  local function elevClass(x, y)
    local e = elevOf(x, y) or 0
    if e == 15 then return 4 end
    return e
  end
  local inPlace = {}     -- walls stood straight up where drawn (the Pyramid's)
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local k = y * 256 + x
      local id = block(x, y)
      local r = opts.roleAt and opts.roleAt(x, y) or Data.roleAt(layout, x, y)
      local b = id and behaviour(id) or 0
      if id and owned(x, y, id) then r = R.FLOOR end
      if opts.inPlaceWalls and (r == R.FENCE or r == R.CLIFF or r == R.SHELF) and not walkable(x, y) then
        r = R.FENCE
        inPlace[k] = true
      end
      role[k], beh[k] = r, b
    end
  end
  local function at(x, y) return role[y * 256 + x] end

  -- ---- Fortree's decks and ladders
  local deck, ladder = {}, {}
  if fortree then
    local net = {}
    for y = 0, H - 1 do
      for x = 0, W - 1 do
        local k = y * 256 + x
        if (beh[k] == MB_NO_RUNNING or beh[k] == MB_FORTREE_BRIDGE) and walkable(x, y) then net[k] = true end
      end
    end
    -- a ladder: one cell wide, walls either side, the rest of the net north
    for k in pairs(net) do
      local x, y = k % 256, math.floor(k / 256)
      local west = x > 0 and walkable(x - 1, y)
      local east = x < W - 1 and walkable(x + 1, y)
      if beh[k] == MB_NO_RUNNING and not west and not east then ladder[k] = true end
    end
    for k in pairs(net) do if not ladder[k] then deck[k] = true end end
  end
  -- each deck's height: as long as the ladders that climb it
  local deckLevel = {}
  local seen = {}
  for k in pairs(deck) do
    if not seen[k] then
      local comp, queue, longest = {}, { k }, 0
      seen[k] = true
      while #queue > 0 do
        local c = table.remove(queue)
        comp[#comp + 1] = c
        local x, y = c % 256, math.floor(c / 256)
        for _, o in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
          local nk = (y + o[2]) * 256 + (x + o[1])
          if deck[nk] and not seen[nk] then seen[nk] = true; queue[#queue + 1] = nk end
          -- a ladder hanging off it: count its run south
          if ladder[nk] and o[2] == 1 then
            local n, yy = 0, y + 1
            while ladder[yy * 256 + x] do n = n + 1; yy = yy + 1 end
            longest = math.max(longest, n)
          end
        end
      end
      for _, c in ipairs(comp) do deckLevel[c] = longest end
    end
  end
  -- Fortree's walkways all run at one height, however short the ladder up
  -- to a given deck is drawn: the tallest of them (two at least)
  local deckHeight = 2
  for _, v in pairs(deckLevel) do deckHeight = math.max(deckHeight, v) end
  for k in pairs(deckLevel) do deckLevel[k] = deckHeight end

  -- ---- levels
  local north, south = {}, {}      -- per cell, levels at its edges
  local function set(k, n, s) north[k], south[k] = n, s end
  -- open ground: level 0, decks their own
  local function isRock(k)
    local r = role[k]
    if deck[k] or ladder[k] then return false end
    return r == R.SHELF or r == R.CLIFF or r == R.WALL
  end
  local floorLevel = {}   -- open cell -> its floor's level (raised floors)
  local function openLevel(k)
    if deckLevel[k] then return deckLevel[k] end
    return floorLevel[k] or 0
  end
  -- a door in a front (a hut's on its deck, a house's) is part of the face
  for y = 1, H - 1 do
    for x = 0, W - 1 do
      local k = y * 256 + x
      if isDoor(beh[k]) and isRock((y - 1) * 256 + x) then role[k] = R.CLIFF end
    end
  end

  -- ---- raised floors and the stairs up to them
  --
  -- A run of CLIFF cells with open floor both north and south of it is the
  -- face of a raised floor: the floor north stands as many levels higher as
  -- the run is long.  Where that band is walkable instead -- open cells in
  -- the rows of a neighbouring column's face, with floor north and south --
  -- it is a stair.  The floors, split at the stairs, are given their levels
  -- by walking those links from the largest of them (level 0); a link that
  -- disagrees with an answer already given is left out.
  local function open(x, y)
    if x < 0 or y < 0 or x >= W or y >= H then return false end
    local k = y * 256 + x
    return not isRock(k) and not deck[k] and not ladder[k]
  end
  -- water that lies at the bottom: the surfable kinds; a puddle or a
  -- shallow stream is the floor it lies on (Meteor Falls' stair of ledges)
  local DEEP = { [0x10] = true, [0x11] = true, [0x12] = true, [0x13] = true, [0x14] = true,
                 [0x15] = true, [0x19] = true, [0x1A] = true }
  local function water(x, y)
    return at(x, y) == R.WATER and DEEP[beh[y * 256 + x]] == true
  end
  -- A CLIFF cell is part of a face when its band runs sideways (a cliff
  -- beside it); a column of cliff with none either side is the side wall
  -- down a plateau's edge, rock and not a step.
  local function cliff(x, y)
    return x >= 0 and y >= 0 and x < W and y < H and at(x, y) == R.CLIFF and isRock(y * 256 + x)
  end
  local function faceCell(x, y)
    if not cliff(x, y) then return false end
    if cliff(x - 1, y) or cliff(x + 1, y) then return true end
    return not (cliff(x, y - 1) or cliff(x, y + 1))
  end
  local bands = {}      -- x -> list of { y1, y2 } face bands with floor both sides
  for x = 0, W - 1 do
    local y = 0
    while y < H do
      if faceCell(x, y) then
        local y1 = y
        while y + 1 < H and faceCell(x, y + 1) do y = y + 1 end
        local y2 = y
        if y2 - y1 < FACE_CAP and open(x, y1 - 1) and open(x, y2 + 1)
           and not water(x, y1 - 1) and not water(x, y2 + 1) then
          bands[x] = bands[x] or {}
          table.insert(bands[x], { y1, y2 })
        end
      end
      y = y + 1
    end
  end
  -- stairs: open runs lying across a neighbour's band, spread sideways
  local stair = {}      -- k -> { y1, y2 }
  local stairCols = {}  -- x -> list of { y1, y2 }
  local function tryStair(x, b)
    local y1, y2 = b[1], b[2]
    if not (open(x, y1 - 1) and open(x, y2 + 1)) then return false end
    for y = y1, y2 do
      if not open(x, y) or stair[y * 256 + x] then return false end
    end
    for y = y1, y2 do stair[y * 256 + x] = b end
    stairCols[x] = stairCols[x] or {}
    table.insert(stairCols[x], b)
    return true
  end
  for x, list in pairs(bands) do
    for _, b in ipairs(list) do
      for _, dir in ipairs({ -1, 1 }) do
        local xx = x + dir
        while xx >= 0 and xx < W and tryStair(xx, b) do xx = xx + dir end
      end
    end
  end
  -- the floors, split at the stairs
  local comp, compSize, nComp = {}, {}, 0
  local compWater
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local k = y * 256 + x
      if open(x, y) and not stair[k] and not comp[k] then
        nComp = nComp + 1
        local queue, n = { k }, 0
        local cls = elevClass(x, y)
        comp[k] = nComp
        while #queue > 0 do
          local c = table.remove(queue)
          n = n + 1
          local cx, cy = c % 256, math.floor(c / 256)
          for _, o in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
            local nx, ny = cx + o[1], cy + o[2]
            local nk = ny * 256 + nx
            local ec = elevClass(nx, ny)
            if open(nx, ny) and not stair[nk] and not comp[nk] and water(nx, ny) == water(cx, cy)
               and (ec == 0 or cls == 0 or ec == cls) then
              if cls == 0 then cls = ec end
              comp[nk] = nComp
              queue[#queue + 1] = nk
            end
          end
        end
        compSize[nComp] = n
        if water(x, y) then compWater = compWater or {}; compWater[nComp] = true end
      end
    end
  end
  -- the links: north floor minus south floor, in levels
  local links = {}
  local function link(x, y1, y2)
    local a, b = comp[(y1 - 1) * 256 + x], comp[(y2 + 1) * 256 + x]
    local wet = compWater or {}
    if a and b and a ~= b and not wet[a] and not wet[b] then
      links[a] = links[a] or {}
      links[b] = links[b] or {}
      table.insert(links[a], { b, -(y2 - y1 + 1) })
      table.insert(links[b], { a, y2 - y1 + 1 })
    end
  end
  for x, list in pairs(bands) do for _, b in ipairs(list) do link(x, b[1], b[2]) end end
  for x, list in pairs(stairCols) do for _, b in ipairs(list) do link(x, b[1], b[2]) end end
  local level = {}
  local order = {}
  for c = 1, nComp do order[#order + 1] = c end
  table.sort(order, function(a, b) return compSize[a] > compSize[b] end)
  for _, root in ipairs(order) do
    if level[root] == nil then
      level[root] = 0
      local queue = { root }
      while #queue > 0 do
        local c = table.remove(queue, 1)
        for _, l in ipairs(links[c] or {}) do
          if level[l[1]] == nil then
            level[l[1]] = level[c] + l[2]
            queue[#queue + 1] = l[1]
          end
        end
      end
    end
  end
  local lowest = 0
  for _, v in pairs(level) do lowest = math.min(lowest, v) end
  -- water lies at the bottom, whatever floor it was found beside
  for k, c in pairs(comp) do
    local v = (compWater and compWater[c]) and 0 or math.min(LEVEL_CAP, (level[c] or 0) - lowest)
    if v ~= 0 then floorLevel[k] = v end
  end
  -- the stairs: a ramp from the floor north to the floor south, run on over
  -- the first cell south so it is a slope and not a wall (a level a row is
  -- vertical on the 45-degree rule)
  for k, b in pairs(stair) do
    local x, y = k % 256, math.floor(k / 256)
    local hi = openLevel((b[1] - 1) * 256 + x)
    local lo = openLevel((b[2] + 1) * 256 + x)
    local rows = b[2] - b[1] + 2
    local i = y - b[1]
    set(k, hi + (lo - hi) * i / rows, hi + (lo - hi) * (i + 1) / rows)
    if y == b[2] then
      local sk = (y + 1) * 256 + x
      set(sk, hi + (lo - hi) * (rows - 1) / rows, lo)
    end
  end
  -- every raised floor cell (the stairs' feet already have theirs)
  for k, v in pairs(floorLevel) do
    if north[k] == nil then set(k, v, v) end
  end

  -- faces: a run of CLIFF (or of a building's lowest rows) standing on open
  -- ground south of it, on Emerald 3DS's 45-degree rule: a point lifted h is
  -- drawn h further south, so every part stands where the GBA draws it.
  local top = {}
  local topArt = {}     -- k -> the cell whose drawing its top shows
  local wallArts = {}   -- k -> its south wall's drawings, bottom up
  local thin, noTop = {}, {}
  local ladders = {}
  local fills = {}
  local function key(x, y) return y * 256 + x end
  for x = 0, W - 1 do
    local y = H - 1
    while y >= 0 do
      local k = y * 256 + x
      if isRock(k) then
        -- the run of rock ending at y, and what it stands on
        local y2 = y
        local y1 = y
        while y1 - 1 >= 0 and isRock((y1 - 1) * 256 + x) do y1 = y1 - 1 end
        local below = (y2 + 1 < H) and (y2 + 1) * 256 + x or nil
        if below and not isRock(below) then
          local ground = openLevel(below)
          -- the face: the CLIFF cells at the run's south end; a building's
          -- front: half its rows (at least one)
          local f = 0
          while y2 - f >= y1 and faceCell(x, y2 - f) and f < FACE_CAP do f = f + 1 end
          if f == 0 and at(x, y2) == R.WALL then
            f = math.min(FACE_CAP, math.max(1, math.floor((y2 - y1 + 1) / 2)))
          end
          if f == 0 then f = 1 end
          local high = ground + f
          -- the face: a level a row, each row dropping a level north to
          -- south -- vertical on the 45-degree rule, where the GBA draws it
          for i = 0, f - 1 do
            set((y2 - i) * 256 + x, ground + i + 1, ground + i)
          end
          for yy = y1, y2 - f do top[yy * 256 + x] = high end
        end
        y = y1 - 1
      else
        if ladder[k] then
          -- a ladder: hung straight down the front of its deck, its cells
          -- the ground at its foot (lifted as a ramp, so who climbs it rises)
          local y2 = y
          local y1 = y
          while y1 - 1 >= 0 and ladder[(y1 - 1) * 256 + x] do y1 = y1 - 1 end
          local n = y2 - y1 + 1
          local high = deckLevel[(y1 - 1) * 256 + x] or n
          for yy = y1, y2 do
            local i = yy - y1
            set(yy * 256 + x, high * (1 - i / n), high * (1 - (i + 1) / n))
            fills[#fills + 1] = { x = x, y = yy, level = 0, fromX = x, fromY = math.min(H - 1, y2 + 1) }
          end
          y = y1 - 1
        else
          if deckLevel[k] then
            set(k, deckLevel[k], deckLevel[k])
            thin[k] = true
            -- the ground under the planks: the nearest ground south
            local fy = y
            for yy = y + 1, math.min(H - 1, y + 6) do
              local kk = yy * 256 + x
              if not deck[kk] and not ladder[kk] and not isRock(kk) then fy = yy break end
            end
            fills[#fills + 1] = { x = x, y = y, level = 0, fromX = x, fromY = fy }
          end
          y = y - 1
        end
      end
    end
  end
  for k, h in pairs(top) do set(k, h, h) end

  -- rock with no face of its own: each such mass, as one, at the height
  -- most of the rock round it stands (1 when none does)
  local seenP = {}
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local k = y * 256 + x
      if isRock(k) and north[k] == nil and not seenP[k] then
        local region, queue, tally = {}, { k }, {}
        seenP[k] = true
        while #queue > 0 do
          local c = table.remove(queue)
          region[#region + 1] = c
          local cx, cy = c % 256, math.floor(c / 256)
          for _, o in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
            local nx, ny = cx + o[1], cy + o[2]
            if nx >= 0 and ny >= 0 and nx < W and ny < H then
              local nk = ny * 256 + nx
              if isRock(nk) then
                if north[nk] == nil then
                  if not seenP[nk] then seenP[nk] = true; queue[#queue + 1] = nk end
                else
                  local h = math.max(north[nk], south[nk])
                  tally[h] = (tally[h] or 0) + 1
                end
              end
            end
          end
        end
        local best, bestN = 1, 0
        for h, n in pairs(tally) do
          if n > bestN or (n == bestN and h < best) then best, bestN = h, n end
        end
        for _, c in ipairs(region) do set(c, best, best) end
      end
    end
  end
  -- nothing stands higher than the cap
  for k, n in pairs(north) do
    north[k], south[k] = math.min(LEVEL_CAP, n), math.min(LEVEL_CAP, south[k])
  end

  -- the floor under every raised cell, at the ground: moved south by its
  -- height, the rock leaves its own cells' floor bare, and the ends of a
  -- band show it -- the nearest ground south of it (north, else its own)
  for k, n in pairs(north) do
    if not deck[k] and not ladder[k] and (n > 0 or south[k] > 0) then
      local x, y = k % 256, math.floor(k / 256)
      local fy
      for yy = y + 1, math.min(H - 1, y + 8) do
        if not isRock(yy * 256 + x) and not deck[yy * 256 + x] then fy = yy break end
      end
      if not fy then
        for yy = y - 1, math.max(0, y - 8), -1 do
          if not isRock(yy * 256 + x) then fy = yy break end
        end
      end
      fills[#fills + 1] = { x = x, y = y, level = 0, fromX = x, fromY = fy or y }
    end
  end
  -- posts under the decks: at each corner of a deck's front edge (and every
  -- other cell along it), straight down from the planks to the ground drawn
  -- below them
  local posts = {}
  for k in pairs(deck) do
    local x, y = k % 256, math.floor(k / 256)
    if not deck[(y + 1) * 256 + x] and not ladder[(y + 1) * 256 + x] then
      local westEnd = not deck[y * 256 + x - 1]
      local eastEnd = not deck[y * 256 + x + 1]
      if westEnd or x % 2 == 0 then posts[#posts + 1] = { x = x + 0.12, y = y + 0.85, high = deckLevel[k], art = block(x, y) } end
      if eastEnd then posts[#posts + 1] = { x = x + 0.88, y = y + 0.85, high = deckLevel[k], art = block(x, y) } end
    end
  end

  -- bridges by their shape (Victory Road's are drawn floor, no behaviour of
  -- their own): a raised walkable cell lower on both sides across it -- north
  -- and south, or west and east -- is a plank over the drop
  local function lvl(x, y)
    if x < 0 or y < 0 or x >= W or y >= H then return nil end
    local kk = y * 256 + x
    return north[kk] and math.max(north[kk], south[kk]) or 0
  end
  for k, n in pairs(north) do
    local x, y = k % 256, math.floor(k / 256)
    if n > 0 and n == south[k] and not isRock(k) and not deck[k] and walkable(x, y) then
      local ln, ls, lw, le = lvl(x, y - 1), lvl(x, y + 1), lvl(x - 1, y), lvl(x + 1, y)
      local across = (ln and ls and ln < n and ls < n) or (lw and le and lw < n and le < n)
      if across then
        thin[k] = true
        local fx, fy = x, y + 1
        if not (ln and ls and ln < n and ls < n) then fx, fy = x - 1, y end
        fills[#fills + 1] = { x = x, y = y, level = math.min(lvl(fx, fy) or 0, n), fromX = fx, fromY = math.min(H - 1, fy) }
      end
    end
  end
  -- where a bridge crosses over a path (elevation 15): planks, the path's
  -- floor laid under them at its own level
  for k, n in pairs(north) do
    local x, y = k % 256, math.floor(k / 256)
    if (elevOf(x, y) or 0) == 15 and n > 0 and not isRock(k) then
      thin[k] = true
      local low, fx, fy = n, x, y
      for _, o in ipairs({ { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } }) do
        local ex = elevOf(x + o[1], y + o[2]) or 0
        local l = lvl(x + o[1], y + o[2])
        if ex == 3 and l and l < low then low, fx, fy = l, x + o[1], y + o[2] end
      end
      if low < n then fills[#fills + 1] = { x = x, y = y, level = low, fromX = fx, fromY = fy } end
    end
  end
  -- the Pyramid's walls: a level high, standing where they are drawn
  for k in pairs(inPlace) do set(k, 1, 1) end

  -- bridges (the bridge behaviours, 0x70-0x7F): planks over the drop, not
  -- a block standing on it, the ground drawn beside them laid under
  for k, n in pairs(north) do
    local b = beh[k] or 0
    if b >= 0x70 and b <= 0x7F and not deck[k] and (n > 0 or south[k] > 0) then
      thin[k] = true
      local x, y = k % 256, math.floor(k / 256)
      local fy
      for yy = y + 1, math.min(H - 1, y + 6) do
        local bb = beh[yy * 256 + x] or 0
        if not (bb >= 0x70 and bb <= 0x7F) and not isRock(yy * 256 + x) then fy = yy break end
      end
      fills[#fills + 1] = { x = x, y = y, level = 0, fromX = x, fromY = fy or y }
    end
  end

  local cells = {}
  local count = 0
  for k, n in pairs(north) do
    local s = south[k]
    if n ~= 0 or s ~= 0 then
      local g = lattice(n, s)
      -- a point's depth is its height: the 45-degree rule
      cells[k] = { g, inPlace[k] and lattice(0, 0) or g, thin = thin[k] }
      count = count + 1
    end
  end
  cells.fills = fills
  cells.posts = posts
  -- the map's own cliff face, the commonest metatile its face cells are
  -- drawn with: the texture of every wall this stands up
  local tally, best, bestN = {}, nil, 0
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      if faceCell(x, y) then
        local id = block(x, y)
        if id then
          tally[id] = (tally[id] or 0) + 1
          if tally[id] > bestN then best, bestN = id, tally[id] end
        end
      end
    end
  end
  cells.faceArt = best
  return cells, count
end

return Generic
