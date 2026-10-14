-- THE MIRAGE TOWER COMES DOWN (pokeemerald src/mirage_tower.c).
--
-- Five specials, all effects running alongside the script rather than
-- blocking it (none of the scripts waits on them):
--
--   411 DoMirageTowerCeilingCrumble   4F: sixteen crumbs fall from the
--        ceiling over the player while the camera shakes, as the warp out
--        fades
--   484 StartMirageTowerShake         Route 111: the tower is put on BG0 as a
--        picture (constants.gen3MirageTower: 73 tiles, a 6x12 tilemap in the
--        map's BG palette 6), the eighteen metatiles under it become sand,
--        and BG0 rocks two pixels side to side, flipping every third frame
--   483 StartMirageTowerDisintegration  the picture is eaten a pixel a frame
--        per row, a new row starting every second frame from the BOTTOM row
--        up, each row in its own shuffled order; every second finished row
--        sinks it a pixel. When the top row is gone, BG0 is a text layer
--        again and the tower is gone.
--   485 StartMirageTowerFossilFallAndSink  the fossil you did not take drops
--        from the top of the screen a pixel a frame to y 96, then dissolves
--        two pixels a frame
--   413 StartPlayerDescendMirageTower  see the note at Gen3MirageTower.descend
--
-- WHERE: the cartridge draws on the screen, and its camera holds the player
-- at a fixed cell (screen 112, 72) through the whole event -- the tower's
-- screen rectangle (96..144, -24..72) is exactly the eighteen metatiles at
-- (18..20, 53..58) it turns to sand. So everything here is placed in WORLD
-- pixels, which reads the same on this port's wider views.
--
-- THE PIXEL QUIRK, kept: UpdateDisintegrationEffect clears the OTHER nibble
-- of the byte the pick lands in (an even pick clears the pixel to its right,
-- an odd one the pixel to its left). Every pixel still goes, in a slightly
-- different order than the shuffle says.

local M = {}

M.TOWER_CELL_X, M.TOWER_CELL_Y = 18, 53          -- sInvisibleMirageTowerMetatiles' corner
M.SAND = {                                       -- metatile ids, per row 53..58
  0x251, 0x251, 0x251, 0x251, 0x259, 0x121,      -- DeepSand_Center x4, _BottomMid, SandPit_Center
}
M.OUTER, M.INNER = 0x60, 0x30                    -- 96 rows of 48 pixels
M.FOSSIL_PIXELS = 0x100
-- sCeilingCrumblePositions: x offset, y, the y it is destroyed past
M.CRUMBLES = {
  { 0, 10, 65 }, { 17, 3, 50 }, { -12, 0, 75 }, { 10, 15, 90 },
  { 7, 8, 65 }, { -18, 5, 75 }, { 22, -10, 55 }, { -24, -4, 65 },
}

local function bytes(hex)
  local out = {}
  for i = 1, #hex, 2 do out[#out + 1] = tonumber(hex:sub(i, i + 1), 16) end
  return out                                     -- 1-based: byte n is out[n + 1]
end

local function record(game)
  local c = game and game.data and game.data.constants
  return c and c.gen3MirageTower
end

local function rng(n) return love.math.random(0, n - 1) end

-- UpdateDisintegrationEffect(tiles, randId, 0, size, offset)
function M.disintegrate(tiles, randId, size, offset)
  local height, width = math.floor(randId / size), randId % size
  local row, col = height % 8, width % 8
  local var = math.floor(size / 8) * (math.floor(height / 8) * 64) + math.floor(width / 8) * 64
  local base = math.floor((var + row * 8 + col) / 2) + offset * 32
  local flag = (randId % 2 == 0) and 1 or 0
  local mask = (flag == 1) and 0x0F or 0xF0      -- (0 << flag*4) | (15 << (flag^1)*4)
  local i = base + 1
  if tiles[i] then
    -- band of the 4bpp byte, without the bit library
    local lo, hi = tiles[i] % 16, math.floor(tiles[i] / 16)
    if mask == 0x0F then hi = 0 else lo = 0 end
    tiles[i] = lo + hi * 16
  end
end

local function shuffled(n, swaps)
  local t = {}
  for i = 0, n - 1 do t[i] = i end
  for _ = 1, swaps do
    local a, b = rng(n), rng(n)
    t[a], t[b] = t[b], t[a]
  end
  return t
end

local function colorsOf(palette)
  local out = {}
  for i = 1, 16 do
    local c = palette and palette[i]
    out[i] = c and { c[1] / 255, c[2] / 255, c[3] / 255 } or { 0, 0, 0 }
  end
  return out
end

-- The 4bpp tiles through a tilemap into ImageData; colour 0 is clear.
local function paint(tiles, tilemap, cols, rows, paletteOf)
  local img = love.image.newImageData(cols * 8, rows * 8)
  for cy = 0, rows - 1 do
    for cx = 0, cols - 1 do
      local entry = tilemap and tilemap[cy * cols + cx + 1] or (cy * cols + cx)
      local tile = entry % 1024
      local hflip = math.floor(entry / 1024) % 2 == 1
      local vflip = math.floor(entry / 2048) % 2 == 1
      local colors = paletteOf(math.floor(entry / 4096) % 16)
      for py = 0, 7 do
        for px = 0, 7 do
          local sx, sy = hflip and 7 - px or px, vflip and 7 - py or py
          local b = tiles[tile * 32 + sy * 4 + math.floor(sx / 2) + 1] or 0
          local idx = (sx % 2 == 0) and b % 16 or math.floor(b / 16)
          if idx ~= 0 and colors then
            local c = colors[idx + 1]
            img:setPixel(cx * 8 + px, cy * 8 + py, c[1], c[2], c[3], 1)
          end
        end
      end
    end
  end
  return img
end

local function mapPalettes(ow, game)
  local ts = ow.map and ow.map.tileset
  local store = game.data.map_tilesets or {}
  local primary = ts and store[ts.primaryKey]
  local secondary = ts and ts.secondaryKey and store[ts.secondaryKey]
  return function(index)
    -- palettes 0..5 are the primary tileset's, 6.. the secondary's (Gen3Tiles)
    local rec = (index < 6) and primary or (secondary or primary)
    local pal = rec and rec.palettes and rec.palettes[index + 1]
    return pal and colorsOf(pal) or nil
  end
end

local function playerColors(game, rec)
  local g = game.save and game.save.player and game.save.player.gender
  local female = (g == "girl" or g == "female" or g == 1)
  local pals = rec.playerPalettes or {}
  return colorsOf(female and pals.may or pals.brendan or pals.may)
end

local function image(data)
  local ok, img = pcall(love.graphics.newImage, data)
  if ok and img then img:setFilter("nearest", "nearest") return img end
  return nil
end

-- --------------------------------------------------------------- specials --

-- 484
function M.startShake(ow, game)
  local rec = record(game)
  if not (ow and rec) then return end
  for row = 0, 5 do
    for col = 0, 2 do
      local x, y = M.TOWER_CELL_X + col, M.TOWER_CELL_Y + row
      if ow.map and ow.map.setBlock then
        ow.map:setBlock(x, y, M.SAND[row + 1], false)
        if ow.map.setCellShut then ow.map:setCellShut(x, y, false) end
      end
    end
  end
  ow.g3MirageTower = {
    mapId = ow.map and ow.map.id,
    tiles = bytes(rec.tiles), tilemap = rec.tilemap, cols = rec.cols or 6, rows = rec.rows or 12,
    palettes = mapPalettes(ow, game),
    hofs = 2, shakeCount = 0, vofs = 0, dirty = true,
    fossil = nil, crumbles = nil,
  }
end

-- 483
function M.startDisintegration(ow)
  local t = ow and ow.g3MirageTower
  if not t then return end
  t.disint = { state = 0, started = 0, done = 0, wait = 0, rows = {} }
end

-- 485
function M.startFossil(ow, game)
  local rec = record(game)
  if not (ow and rec) then return end
  local t = ow.g3MirageTower
  if not t then
    ow.g3MirageTower = { mapId = ow.map and ow.map.id }
    t = ow.g3MirageTower
  end
  t.fossil = {
    tiles = bytes(rec.fossil), colors = playerColors(game, rec), state = 0,
    y = -16, order = shuffled(M.FOSSIL_PIXELS, M.FOSSIL_PIXELS * 2), idx = 0, dirty = true,
  }
end

-- 411: the crumbs and their camera shake (StartScreenShake(2, 1, 16, 3))
function M.ceilingCrumble(ow, game)
  local rec = record(game)
  if not (ow and rec and ow.player) then return end
  local list = {}
  for i, p in ipairs(M.CRUMBLES) do
    -- CreateSprite takes the CENTRE: the large 16x16 at (120+dx, dy), the
    -- small 8x8 at (115+dx, dy-3); both destroyed once past p[3]
    list[#list + 1] = { x = 120 + p[1], y = p[2], size = 16, limit = p[3], yoff = 0 }
    list[#list + 1] = { x = 115 + p[1], y = p[2] - 3, size = 8, limit = p[3], yoff = 0 }
  end
  ow.g3MirageCrumbles = {
    mapId = ow.map and ow.map.id, sprites = list,
    tiles = bytes(rec.crumbles), colors = playerColors(game, rec),
    -- screen (112, 72) is the player's cell in the cartridge's camera
    originX = ow.player.px - 112, originY = ow.player.py - 72,
  }
  -- StartScreenShake(2, 1, 16, 3): the camera pans 1 across / 2 down, sign
  -- flipping every third frame, sixteen times
  require("src.world.Gen3ScreenFx").shakeCamera(ow, 2, 1, 16, 3, true)
end

-- 413 StartPlayerDescendMirageTower: a task that slides LOCALID_ROUTE111_
-- PLAYER_FALLING down 4 px a frame to the player. The script does not wait for
-- it -- the very next commands show the player and REMOVE that object, the
-- same frame -- so on the cartridge nothing of it is seen. Nothing to draw.
function M.descend() end

-- ------------------------------------------------------------------ frames --

function M.tick(ow)
  local t = ow.g3MirageTower
  if t then
    if ow.map and t.mapId ~= ow.map.id then ow.g3MirageTower = nil; t = nil end
  end
  if t and t.tiles then
    -- UpdateBgShake: flip HOFS, then wait two frames
    if not t.stopped then
      if t.shakeCount == 0 then t.hofs = -t.hofs; t.shakeCount = 2 else t.shakeCount = t.shakeCount - 1 end
    end
    local d = t.disint
    if d then
      d.state = d.state + 1
      if d.state >= 3 and not d.finished then
        if d.started <= M.OUTER - 1 then
          if d.wait > 1 then
            d.rows[d.started] = { order = shuffled(M.INNER, M.INNER), idx = 0 }
            d.started = d.started + 1
            d.wait = 0
          end
          d.wait = d.wait + 1
        end
        local from = d.done
        for i = from, d.started - 1 do
          local r = d.rows[i]
          if r and r.order then
            M.disintegrate(t.tiles, (M.OUTER - 1 - i) * M.INNER + r.order[r.idx], M.INNER, 1)
            r.idx = r.idx + 1
            t.dirty = true
            if r.idx > M.INNER - 1 then
              r.order = nil
              d.done = d.done + 1
              if i % 2 == 1 then t.vofs = t.vofs - 1 end
            end
          end
        end
        if d.done >= M.OUTER then d.finished = true; t.tiles = nil; t.img = nil end
      end
    end
  end
  if t and t.fossil then
    local f = t.fossil
    f.state = f.state + 1
    if f.state > 6 and not f.gone then
      if f.idx >= M.FOSSIL_PIXELS then
        f.gone = true
      elseif f.y >= 96 then
        for _ = 1, 2 do
          if f.idx < M.FOSSIL_PIXELS then
            M.disintegrate(f.tiles, f.order[f.idx], 16, 0)
            f.idx = f.idx + 1
          end
        end
        f.dirty = true
      else
        f.y = f.y + 1
      end
    end
  end
  if t and not t.tiles and (not t.fossil or t.fossil.gone) then ow.g3MirageTower = nil end
  local c = ow.g3MirageCrumbles
  if c then
    if ow.map and c.mapId ~= ow.map.id then ow.g3MirageCrumbles = nil
    else
      local alive = {}
      for _, s in ipairs(c.sprites) do
        s.yoff = s.yoff + 2
        if s.y + math.floor(s.yoff / 2) <= s.limit then alive[#alive + 1] = s end
      end
      c.sprites = alive
      if #alive == 0 then ow.g3MirageCrumbles = nil end
    end
  end
end

-- ------------------------------------------------------------------- draws --

-- Under the sprites: BG0 at priority 2, over the map's middle layer.
function M.drawTower(ow, cam)
  local t = ow.g3MirageTower
  if not (t and t.tiles) then return end
  if t.dirty or not t.img then
    t.img = image(paint(t.tiles, t.tilemap, t.cols, t.rows, t.palettes))
    t.dirty = false
  end
  if not t.img then return end
  love.graphics.setColor(1, 1, 1, 1)
  -- BG0's HOFS moves the picture left, its VOFS (counting down) moves it down
  love.graphics.draw(t.img, M.TOWER_CELL_X * 16 - cam.x - t.hofs, M.TOWER_CELL_Y * 16 - cam.y - t.vofs)
end

-- Over everything: OAM priority 0.
function M.drawAbove(ow, cam)
  local t = ow.g3MirageTower
  local f = t and t.fossil
  -- screen (0, 0) of the tower's event is world (18*16 - 96, 53*16 + 24)
  local ox, oy = M.TOWER_CELL_X * 16 - 96, M.TOWER_CELL_Y * 16 + 24
  if f and f.state > 4 and not f.gone then
    if f.dirty or not f.img then
      f.img = image(paint(f.tiles, { 0, 1, 2, 3 }, 2, 2, function() return f.colors end))
      f.dirty = false
    end
    if f.img then
      love.graphics.setColor(1, 1, 1, 1)
      -- centerToCornerVecX was zeroed: x is the left edge; y is the centre
      love.graphics.draw(f.img, ox + 128 - cam.x, oy + f.y - 8 - cam.y)
    end
  end
  local c = ow.g3MirageCrumbles
  if c then
    if not c.big then
      c.big = image(paint(c.tiles, { 0, 1, 2, 3 }, 2, 2, function() return c.colors end))
      c.small = image(paint(c.tiles, { 0 }, 1, 1, function() return c.colors end))
    end
    love.graphics.setColor(1, 1, 1, 1)
    for _, s in ipairs(c.sprites) do
      local img = (s.size == 16) and c.big or c.small
      if img then
        local half = s.size / 2
        love.graphics.draw(img, c.originX + s.x - half - cam.x, c.originY + s.y + math.floor(s.yoff / 2) - half - cam.y)
      end
    end
  end
end

return M
