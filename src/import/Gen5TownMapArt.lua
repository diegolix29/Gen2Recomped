-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- BLACK / WHITE'S TOWN MAP, out of the ROM.
--
--   /a/0/8/5  the Town Map app (overlay 72) and its graphics:
--             * palette 0 (8,232 bytes, the 8bpp set; bank 0 is the map's),
--               tile sheet 7 (704 tiles, 8bpp) and screen 16 (256 x 256) are
--               the painted region. The screen is laid out with its two
--               128-pixel halves the other way round -- the map is shown with
--               a horizontal scroll of 128 that wraps (Nimbasa's wheel is cut
--               at the left edge of one half and the right edge of the other)
--               -- and the region fills the top 192 rows of it.
--             * screen 17 over tile sheet 5 (256 tiles, 8bpp), same palette,
--               is the ROADS layer -- BG2, the orange routes, the ringed town
--               circles and the green landmark squares -- drawn unscrolled
--               over the region; colour 0 is clear. (Composed through the
--               shared tilemap path it came out in scattered pieces; it is
--               decoded here directly: tile n at byte 64 n of the CHAR data,
--               bit 10 / 11 of a screen entry the flips.)
--             * cell bank 12 over tile sheet 8 (4bpp; the bank maps tiles in
--               128-byte units), palette 2, holds the sprites: cell 7 is the
--               red arrow marking where the player is (its tip at the cell's
--               origin), cell 11 the 32 x 32 cursor ring.
--   /a/0/8/6  the locations: 61 records of 54 bytes (27 u16): the zone, its
--             icon's x, y (map pixels, 256 x 192) and three more points round
--             it, +22 the kind (0 town, 1 route, 2 landmark, 3-5 the special
--             places), +24 a fly point (1), +30 the place-name text id, then
--             a running index of the place's own buildings, +48 the cursor
--             shape and +50 / +52 the cursor's x, y. Nuvema is zone 389 at
--             (232, 158); Castelia (28) sits on the big port at the bottom.
--
-- FLY lands where the zone header says (+0x24 x, +0x2C z: Gen5Maps spawnX /
-- spawnZ) -- matrix-0 coordinates, two tiles below each town's Pokemon
-- Center door. Castelia's own matrix keeps a rail position there instead, so
-- for a zone off the main matrix the landing is that Center's door plus two
-- (the Center's interior is the zones on matrix 13). The record keeps both
-- and src/ui/Gen5TownMap.lua resolves them against the map defs.
--
-- build(x) -> { image, arrow, cursor, locations, pcZones } or nil

local M = {}

M.PATHS = { art = "/a/0/8/5", table = "/a/0/8/6", zones = "/a/0/1/2" }
M.MEMBERS = { palette = 0, tiles = 7, screen = 16, roads = 17, roadTiles = 5,
              cells = 12, objTiles = 8, objPalette = 2 }
M.CELLS = { arrow = 7, cursor = 11 }
M.RECORD = 54
M.SCROLL = 128
M.PC_MATRIX = 13

local function u16(s, o) return s:byte(o + 1) + s:byte(o + 2) * 256 end
local function u32(s, o) return u16(s, o) + u16(s, o + 2) * 65536 end

local function members(x)
  local G = require("src.import.Gen4Graphics")
  local arc = require("src.import.NarcArchive").parse(x.rom:read(M.PATHS.art))
  return function(i)
    local m = arc:get(i)
    if m and G.isCompressed(m) then m = G.decompress(m) end
    return m
  end, G
end

-- a BGR555 entry as four RGBA bytes
local function rgba(pal, base, index)
  local v = u16(pal, base + index * 2)
  local function c(n) n = n % 32 return string.char(n * 8 + math.floor(n / 4)) end
  return c(v) .. c(math.floor(v / 32)) .. c(math.floor(v / 1024)) .. "\255"
end

local function section(data, tag, skip)
  local at = data and data:find(tag, 1, true)
  return at and (at - 1 + skip) or nil
end

-- the ROADS layer as rows of RGBA, nil where clear
local function roads(member)
  local screen, sheet, pal = member(M.MEMBERS.roads), member(M.MEMBERS.roadTiles), member(M.MEMBERS.palette)
  local scr = section(screen, "NRCS", 0x14)
  local chr = section(sheet, "RAHC", 0x20)
  local plt = section(pal, "TTLP", 0x18)
  if not (scr and chr and plt) then return nil end
  local px = {}
  for ty = 0, 23 do
    for tx = 0, 31 do
      local v = u16(screen, scr + (ty * 32 + tx) * 2)
      local t = v % 1024
      local hf, vf = math.floor(v / 1024) % 2 == 1, math.floor(v / 2048) % 2 == 1
      for y = 0, 7 do
        for x = 0, 7 do
          local sx, sy = hf and 7 - x or x, vf and 7 - y or y
          local c = sheet:byte(chr + t * 64 + sy * 8 + sx + 1) or 0
          if c ~= 0 then px[(ty * 8 + y) * 256 + tx * 8 + x] = rgba(pal, plt, c) end
        end
      end
    end
  end
  return px
end

-- the region: the screen composed, its halves swapped, the top 192 rows,
-- the roads over it
local function region(x)
  local member, G = members(x)
  local img = G.compose(G.tilemap(member(M.MEMBERS.screen)), G.tiles(member(M.MEMBERS.tiles)),
                        G.palette(member(M.MEMBERS.palette)))
  if not img then return nil end
  local okR, road = pcall(roads, member)
  if not okR then road = nil end
  local W, H = 256, 192
  local out = {}
  for y = 0, H - 1 do
    for px = 0, W - 1 do
      local over = road and road[y * W + px]
      if over then
        out[#out + 1] = over
      else
        local sx = (px + M.SCROLL) % img.width
        local o = (y * img.width + sx) * 4
        out[#out + 1] = img.rgba:sub(o + 1, o + 4)
      end
    end
  end
  return { width = W, height = H, rgba = table.concat(out) }
end

-- one cell of bank 12 as an image, and where its origin sits in it
local function cell(member, G, index)
  local bank = require("src.import.Gen4Cells").parse(member(M.MEMBERS.cells), G)
  local c = bank and bank.cells[index + 1]
  local sheet, pal = member(M.MEMBERS.objTiles), member(M.MEMBERS.objPalette)
  local chr, plt = section(sheet, "RAHC", 0x20), section(pal, "TTLP", 0x18)
  if not (c and #c.oam > 0 and chr and plt) then return nil end
  local unit = 32 * 2 ^ (tonumber(bank.mappingMode) or 0)
  local minX, minY, maxX, maxY
  for _, o in ipairs(c.oam) do
    minX = math.min(minX or o.x, o.x); minY = math.min(minY or o.y, o.y)
    maxX = math.max(maxX or o.x + o.width, o.x + o.width); maxY = math.max(maxY or o.y + o.height, o.y + o.height)
  end
  local W, H = maxX - minX, maxY - minY
  local px = {}
  for _, o in ipairs(c.oam) do
    local tw = o.width / 8
    for ty = 0, o.height / 8 - 1 do
      for tx = 0, tw - 1 do
        local base = chr + o.tile * unit + (ty * tw + tx) * 32
        for y = 0, 7 do
          for x = 0, 7 do
            local b = sheet:byte(base + y * 4 + math.floor(x / 2) + 1) or 0
            local ci = x % 2 == 0 and b % 16 or math.floor(b / 16)
            if ci ~= 0 then
              px[(o.y - minY + ty * 8 + y) * W + (o.x - minX + tx * 8 + x)] =
                rgba(pal, plt, (tonumber(o.palette) or 0) * 16 + ci)
            end
          end
        end
      end
    end
  end
  local out = {}
  for i = 0, W * H - 1 do out[#out + 1] = px[i] or "\0\0\0\0" end
  return { width = W, height = H, rgba = table.concat(out) }, -minX, -minY
end

function M.locations(x)
  local arc = require("src.import.NarcArchive").parse(x.rom:read(M.PATHS.table))
  local t = arc and arc:get(0)
  if not t or #t % M.RECORD ~= 0 then return nil end
  local out = {}
  for r = 0, #t / M.RECORD - 1 do
    local o = r * M.RECORD
    local subs = {}
    for k = 0, 6 do
      local z = u16(t, o + 34 + k * 2)
      if z ~= 0xFFFF then subs[#subs + 1] = z end
    end
    out[#out + 1] = {
      zone = u16(t, o), kind = u16(t, o + 22),
      flyPoint = u16(t, o + 24) == 1 or nil,
      x = u16(t, o + 4), y = u16(t, o + 6),
      textId = u16(t, o + 30),
      subs = subs,
      cursorShape = u16(t, o + 48),
      cursor = { u16(t, o + 50), u16(t, o + 52) },
    }
  end
  return out
end

-- each fly point's zone header spawn, and the Pokemon Center zones
local function flyData(x, locations)
  local arc = require("src.import.NarcArchive").parse(x.rom:read(M.PATHS.zones))
  local zones = arc and require("src.import.Gen5Maps").zones(arc:get(0))
  if not zones then return nil end
  for _, loc in ipairs(locations) do
    local z = zones[loc.zone]
    if loc.flyPoint and z then
      loc.spawn = { x = z.spawnX, z = z.spawnZ, main = z.matrix == 0 or nil }
    end
  end
  local pc = {}
  for id, z in pairs(zones) do
    if z.matrix == M.PC_MATRIX then pc[#pc + 1] = id end
  end
  table.sort(pc)
  return pc
end

function M.build(x)
  local okR, img = pcall(region, x)
  local locations = M.locations(x)
  if not (okR and img and locations) then return nil, okR and "no map" or tostring(img) end
  local entry = x:saveImage("townmap5/region", img)
  if not entry then return nil, "image not saved" end
  local out = { image = entry, scroll = M.SCROLL, locations = locations,
                source = "ROM:/a/0/8/5 (16, 7, 0; roads 17, 5), /a/0/8/6" }
  local member, G = members(x)
  for name, index in pairs(M.CELLS) do
    local okC, pic, ox, oy = pcall(cell, member, G, index)
    if okC and pic then
      local e = x:saveImage("townmap5/" .. name, pic)
      if e then out[name] = { path = e.path, width = pic.width, height = pic.height, ox = ox, oy = oy } end
    end
  end
  local okF, pc = pcall(flyData, x, locations)
  if okF and pc then out.pcZones = pc end
  return out
end

return M
