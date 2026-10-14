-- PLATINUM'S TOWN MAP, THE BOTTOM SCREEN'S PICTURES (pokeplatinum
-- src/applications/town_map/main.c, graphics.c), from /graphic/tmap_gra.narc
-- (member names in src/import/Gen4Archives.lua) and /graphic/field_board.narc:
--
--   zoom_screen     SUB_1 bottom_screen_zoom_button_screen (28) over
--                   bottom_screen_button_tiles (21), the whole 256 x 192 the
--                   zoom-button page shows (DrawZoomButton(.., TRUE))
--   zoom_button_N   zoom_button_states (27): the 6 x 7 tiles at (6 N, 0) laid
--                   at tile (13, 10) -- N 0 up, 1 / 2 the press frames
--   header          zoom_button_states (0, 7) 12 x 2, laid at tile (10, 0) on
--                   the zoomed page (PrintBottomScreenHeader)
--   zoom_bg         SUB_3 bottom_screen_region_bg_tilemap (25), 512 x 512
--   zoom_map        SUB_2 bottom_screen_region_map_tilemap (26), 512 x 512,
--                   both over bottom_screen_map_tiles (20); all BG under
--                   bottom_screen_bg.NCLR (1) at sub BG palette 0
--   hidden          hidden_location_bottom_screen (29), the pieces
--                   ShowHiddenLocation copies onto those two
--   shockwave_N     zoom_button_shockwave (4/5/6) cells over its NCLR (3):
--                   sequence 0 = cells 0, 1, 2 four frames each
--   sign_frame_T    field_board signpost_frame (0), its 18 frame tiles in a
--                   row, under signpost.NCLR (1) row T (LoadSignpostContent-
--                   Graphics loads row signpostType into BG palette 14)
--   sign_T_M        the 6 x 4 signpost picture: city_map_empty + M for a MAP
--                   signpost (T 0), route_map_00 + M for an ARROW one (T 1)
--
-- `data(rom)` (gen4_town_map_ink): the full tmap_block records (with the
-- description offsets the top-screen importer leaves out), tmap_flags.dat's
-- description checks, and the text colours: palette 14's (1, 2) per
-- signpost type and the sub font palette's.
--
-- Written to assets/generated/gen4/town_map_art/<key>.png, indexed in
-- `gen4_town_map_art`.

local Gen4TownMapArt = {}

Gen4TownMapArt.PATH = "/graphic/tmap_gra.narc"
Gen4TownMapArt.BOARD = "/graphic/field_board.narc"
Gen4TownMapArt.BLOCKS = "/data/tmap_block.dat"
Gen4TownMapArt.FLAGS = "/data/tmap_flags.dat"
Gen4TownMapArt.CITY_MAP_EMPTY = 33
Gen4TownMapArt.ROUTE_MAP_00 = 2

local floor = math.floor

local function opener(rom, path)
  local G = require("src.import.Gen4Graphics")
  local bytes = rom:read(path)
  if not bytes then return nil end
  local narc = require("src.import.NarcArchive").parse(bytes)
  if not narc then return nil end
  return function(i)
    local b = narc:get(i)
    if b and G.isCompressed(b) then b = G.decompress(b) end
    return b
  end
end

local function member(path, name, fallback)
  local A = require("src.import.Gen4Archives")
  return A.find(path, name) or fallback
end

local function u16(b, at) local x, y = b:byte(at + 1, at + 2) return (x or 0) + (y or 0) * 256 end

-- every tmap_block record, all twelve fields
function Gen4TownMapArt.parseBlocks(b)
  if type(b) ~= "string" or #b < 4 then return nil end
  local n = u16(b, 0)
  local out = {}
  for i = 0, n - 1 do
    local o = 4 + i * 24
    if o + 24 > #b then break end
    out[#out + 1] = {
      x = u16(b, o), z = u16(b, o + 2), signpostType = u16(b, o + 4), signpost = u16(b, o + 6),
      areaDesc = u16(b, o + 8), landmarkDesc = u16(b, o + 10),
      areaX = u16(b, o + 12), areaY = u16(b, o + 14), landmarkX = u16(b, o + 16), landmarkY = u16(b, o + 18),
      hidden = u16(b, o + 20), index = i,
    }
  end
  return out
end

-- tmap_flags.dat: an int count, then { areaType, areaFlag, landmarkType,
-- landmarkFlag } bytes per block (TOWN_MAP_DESC_FLAG_NONE / FIRST_ARRIVAL /
-- GENERAL)
function Gen4TownMapArt.parseFlags(b)
  if type(b) ~= "string" or #b < 4 then return nil end
  local n = u16(b, 0)
  local out = {}
  for i = 0, n - 1 do
    local o = 4 + i * 4
    if o + 4 > #b then break end
    local a, af, l, lf = b:byte(o + 1, o + 4)
    out[i + 1] = { areaType = a, areaFlag = af, landmarkType = l, landmarkFlag = lf }
  end
  return out
end

function Gen4TownMapArt.images(rom)
  local G = require("src.import.Gen4Graphics")
  local Cells = require("src.import.Gen4Cells")
  local P = Gen4TownMapArt.PATH
  local m = opener(rom, P)
  if not m then return nil, "tmap_gra.narc missing" end
  local out = {}
  local pal = G.palette(m(member(P, "bottom_screen_bg.NCLR", 1)))
  local mapTiles = G.tiles(m(member(P, "bottom_screen_map_tiles.NCGR", 20)))
  local btnTiles = G.tiles(m(member(P, "bottom_screen_button_tiles.NCGR", 21)))
  if not (pal and mapTiles and btnTiles) then return nil, "tmap_gra bottom screen unreadable" end
  local zoomScreen = G.tilemap(m(member(P, "bottom_screen_zoom_button_screen.NSCR", 28)))
  local states = G.tilemap(m(member(P, "zoom_button_states.NSCR", 27)))
  if zoomScreen then out.zoom_screen = G.compose(zoomScreen, btnTiles, pal) end
  if states then
    local cols = floor(states.width / 8)
    local function rect(sx, sy, w, h)
      local cells = {}
      for y = 0, h - 1 do
        for x = 0, w - 1 do
          cells[#cells + 1] = states.cells[(sy + y) * cols + sx + x + 1] or { tile = 0, palette = 0 }
        end
      end
      return G.compose({ width = w * 8, height = h * 8, cells = cells }, btnTiles, pal)
    end
    for n = 0, 2 do out["zoom_button_" .. n] = rect(n * 6, 0, 6, 7) end
    out.header = rect(0, 7, 12, 2)
  end
  for key, name in pairs({ zoom_bg = "bottom_screen_region_bg_tilemap.NSCR", zoom_map = "bottom_screen_region_map_tilemap.NSCR",
                           hidden = "hidden_location_bottom_screen.NSCR" }) do
    local map = G.tilemap(m(member(P, name, ({ zoom_bg = 25, zoom_map = 26, hidden = 29 })[key])))
    if map then out[key] = G.compose(map, mapTiles, pal) end
  end
  -- the zoom button's shockwave
  local sh = G.tiles(m(member(P, "zoom_button_shockwave.NCGR", 4)))
  local bank = Cells.parse(m(member(P, "zoom_button_shockwave_cell.NCER", 5)), G)
  local spal = G.palette(m(member(P, "zoom_button_shockwave.NCLR", 3)))
  if sh and bank and spal then
    for i, cell in ipairs(bank.cells) do
      local use = { oam = {} }
      for k, v in pairs(cell) do if k ~= "oam" then use[k] = v end end
      for j, o in ipairs(cell.oam) do
        local c = {}
        for k, v in pairs(o) do c[k] = v end
        c.palette = 0
        use.oam[j] = c
      end
      local pic = Cells.assemble(use, sh, spal, bank, G)
      if pic then pic.originX, pic.originY = Cells.extent(use) end
      out["shockwave_" .. (i - 1)] = pic
    end
  end
  -- the signposts
  local B = Gen4TownMapArt.BOARD
  local fb = opener(rom, B)
  if fb then
    local frame = G.tiles(fb(member(B, "signpost_frame.NCGR", 0)))
    local bpal = G.palette(fb(member(B, "signpost.NCLR", 1)))
    if frame and bpal then
      local function row(r)
        local c = {}
        for i = 1, 16 do c[i] = bpal[r * 16 + i] or { 0, 0, 0 } end
        return c
      end
      for t = 0, 3 do
        local cells = {}
        for i = 0, 17 do cells[i + 1] = { tile = i, palette = 0 } end
        out["sign_frame_" .. t] = G.compose({ width = 18 * 8, height = 8, cells = cells }, frame, row(t))
      end
      local seen = {}
      for _, blk in ipairs(Gen4TownMapArt.parseBlocks(rom:read(Gen4TownMapArt.BLOCKS)) or {}) do
        local t = blk.signpostType
        if (t == 0 or t == 1) and not seen[t .. "_" .. blk.signpost] then
          seen[t .. "_" .. blk.signpost] = true
          local idx = blk.signpost + (t == 0 and Gen4TownMapArt.CITY_MAP_EMPTY or Gen4TownMapArt.ROUTE_MAP_00)
          local tiles = G.tiles(fb(idx))
          if tiles then
            local cells = {}
            for i = 0, 23 do cells[i + 1] = { tile = i, palette = 0 } end
            out[("sign_%d_%d"):format(t, blk.signpost)] = G.compose({ width = 48, height = 32, cells = cells }, tiles, row(t))
          end
        end
      end
    end
  end
  for k, v in pairs(out) do if not v then out[k] = nil end end
  return out
end

function Gen4TownMapArt.data(rom)
  local G = require("src.import.Gen4Graphics")
  local out = {
    blocks = Gen4TownMapArt.parseBlocks(rom:read(Gen4TownMapArt.BLOCKS)),
    descFlags = Gen4TownMapArt.parseFlags(rom:read(Gen4TownMapArt.FLAGS)),
    signInk = {},
  }
  local fb = opener(rom, Gen4TownMapArt.BOARD)
  local bpal = fb and G.palette(fb(member(Gen4TownMapArt.BOARD, "signpost.NCLR", 1)))
  if bpal then
    for t = 0, 3 do
      local function c(i) local x = bpal[t * 16 + i + 1] return x and { x[1], x[2], x[3] } end
      out.signInk[t] = { text = c(1), shadow = c(2), paper = c(15) }
    end
  end
  local P = Gen4TownMapArt.PATH
  local m = opener(rom, P)
  local pal = m and G.palette(m(member(P, "bottom_screen_bg.NCLR", 1)))
  if pal and pal[1] then out.backdrop = { pal[1][1], pal[1][2], pal[1][3] } end
  -- GetTouchedZone on the zoom-button page: a tap anywhere is the button
  -- unless SUB_1's pixel there is colour 1 or 4 (Bg_DoesPixelAtXYMatchVal,
  -- mask 0x0012).  Kept as runs { y, x0, x1 } of the pixels that DO count.
  local tiles = m and G.tiles(m(member(P, "bottom_screen_button_tiles.NCGR", 21)))
  local screen = m and G.tilemap(m(member(P, "bottom_screen_zoom_button_screen.NSCR", 28)))
  if tiles and screen then
    -- an identity palette: red = 16 * palette row + colour index
    local id = {}
    for i = 0, 255 do id[i + 1] = { i, 0, 0 } end
    local pic = G.compose(screen, tiles, id)
    if pic then
      local runs = {}
      for y = 0, math.min(pic.height, 192) - 1 do
        local start
        for x = 0, 256 do
          local hit = false
          if x < 256 and x < pic.width then
            local at = (y * pic.width + x) * 4
            local r, a = pic.rgba:byte(at + 1), pic.rgba:byte(at + 4)
            local c = (a ~= 0) and (r % 16) or 0
            hit = c ~= 1 and c ~= 4
          end
          if hit and not start then start = x end
          if not hit and start then runs[#runs + 1] = { y, start, x - 1 }; start = nil end
        end
      end
      out.zoomHit = runs
    end
  end
  return out
end

return Gen4TownMapArt
