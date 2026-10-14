-- PLATINUM'S TOWN MAP -- the top screen of pokeplatinum
-- src/applications/town_map, for the Town Map key item and for Fly.
--
-- What it draws, in the cartridge's order:
--   * the region (`top_screen_region_bg`) with the routes over it
--     (`top_screen_region_map`), both composed by the graphics stage;
--   * the twenty town blocks (`sFlyLocations`), each in its shape and in
--     sub-palette 5 + palette + unlocked; Pal Park's and Victory Road's are
--     hidden until unlocked; in FLY mode the one under the cursor blinks
--     between that and 8 + palette every 16 ticks;
--   * the player's icon where the player is (or, indoors, where the player
--     last stood outside), and the cursor;
--   * the location's name on the bar at the bottom -- only on a cell with a
--     `tmap_block.dat` block -- centred, or in FLY mode after "Fly to where?".
--
-- The grid: cell (x, z) of the main map matrix is at 7x + 25, 7z - 34
-- (TOWN_MAP_GRID_X/Y). The cursor keeps to x 1..28, z 6..28 and steps once
-- every three ticks while a direction is held (HandleInput / DoZoomedMapMvt).
--
-- THE BOTTOM SCREEN (graphics.c; `gen4_town_map_art` / `gen4_town_map_ink`
-- from src/import/Gen4TownMapArt.lua), drawn through src/ui/SecondScreen.lua
-- when a second screen is shown: first the zoom-button page (SUB_1
-- bottom_screen_zoom_button_screen, the button's 6 x 7 at tile (13, 10)); a
-- tap there (anywhere SUB_1 is not colour 1 / 4) presses the button -- the
-- shockwave at (128, 108), states 1, 2, 1, 0 on odd frames -- fades the sub
-- screen out and brings up the ZOOMED MAP: SUB_3 / SUB_2 512 x 512 scrolled
-- to (16 x + 8 - 112, 16 z - 96) clamped to x 8..248, y 80..304, sliding 5, 5
-- and 6 pixels a tick as the cursor steps (DoZoomedMapMvt), the header strip
-- at tile (10, 0) with bank 615 line 1, and for a named cell its signpost
-- (field_board's frame and picture, window (9, 3) 21 x 4 for MAP / ARROW,
-- (2, 3) 28 x 4 otherwise, the name in the message font) over the area and
-- landmark descriptions in window (1, 8) at the block's own offsets, each
-- gated by tmap_flags.dat.  A tap on the button's rectangle (104..152,
-- 80..136) goes back.  Item and Fly mode only; the wall map takes no touch.
--
-- THE LOCATION HISTORY: the save's OverworldMapHistory (six cells, a ring)
-- -- `save.gen4MapHistory`, written by `Gen4TownMap.pushHistory`, which
-- `remember` calls on every outdoor map entry -- shows as one history dot at
-- a time, oldest to newest, 26 ticks each (LoadLocationHistory /
-- Task_UpdateShownLocationHistoryIdx).  Optional: no record, no dots.

local Assets = require("src.render.Assets")
local Font = require("src.render.Font")

local Gen4TownMap = {}
Gen4TownMap.__index = Gen4TownMap
Gen4TownMap.isOpaque = true

local W, H = 256, 192
local STEP_FRAMES = 6            -- three 30 Hz ticks
local BLINK_FRAMES = 32          -- sixteen ticks
local EVERYWHERE = 0             -- MAP_HEADER_EVERYWHERE

function Gen4TownMap:uiSize() return W, H end
function Gen4TownMap:wantsFillScale() return true end
function Gen4TownMap:wantsEdgeBleed() return false end

local function record(game) return game and game.data and game.data.gen4_town_map end

-- The main map matrix: header at (x, z), and the cells a header covers.
local function matrix(game)
  local m = game.data.gen4_map_matrices
  return m and m[0]
end

function Gen4TownMap.headerAt(game, x, z)
  local m = matrix(game)
  if not m then return nil end
  if x < 0 or z < 0 or x >= m.width or z >= m.height then return nil end
  return m.headers[z * m.width + x + 1]
end

local function originOf(game, header)
  local m = matrix(game)
  if not m then return nil end
  local bx, bz
  for i, h in ipairs(m.headers) do
    if h == header then
      local x, z = (i - 1) % m.width, math.floor((i - 1) / m.width)
      if not bx or z < bz or (z == bz and x < bx) then bx, bz = x, z end
    end
  end
  return bx, bz
end

-- Where the player is on the map: the matrix cell under them on an outdoor
-- map, else the last outdoor cell recorded (TownMapContext_Init's exitLocation
-- arm -- see Gen4TownMap.remember).
function Gen4TownMap.playerCell(game)
  local ow = game.overworld
  local def = ow and ow.map and ow.map.def
  local p = ow and ow.player
  if def and def.layout == 0 and p and p.cellX then
    local ox, oz = originOf(game, def.header)
    if ox then
      return ox + math.floor(p.cellX / 32), oz + math.floor(p.cellY / 32)
    end
  end
  local last = game.save and game.save.gen4TownMapCell
  if last then return last.x, last.z end
  return 3, 27
end

-- Called on every outdoor step-in so an indoor opening has somewhere to point.
function Gen4TownMap.remember(game)
  local ow = game and game.overworld
  local def = ow and ow.map and ow.map.def
  if not (def and def.layout == 0 and game.save) then return end
  local x, z = Gen4TownMap.playerCell(game)
  game.save.gen4TownMapCell = { x = x, z = z }
  local facing = ow.player and ow.player.facing
  Gen4TownMap.pushHistory(game.save, x, z, ({ up = 0, down = 1, left = 2, right = 3 })[facing] or 4)
end

-- OVERWORLD_MAP_HISTORY_LENGTH entries in a ring (overworld_map_history.c):
-- a push only when the cell is not the current one
Gen4TownMap.HISTORY_LENGTH = 6
function Gen4TownMap.pushHistory(save, x, z, face)
  if not save then return end
  local h = save.gen4MapHistory
  if type(h) ~= "table" then
    h = { pointer = 0, items = {} }
    save.gen4MapHistory = h
  end
  if x == h.currentX and z == h.currentZ then return end
  h.items[h.pointer + 1] = { x = x, z = z, face = face or 4, set = true }
  h.currentX, h.currentZ = x, z
  h.pointer = (h.pointer + 1) % Gen4TownMap.HISTORY_LENGTH
end

-- TownMapContext_Init + LoadLocationHistory: the five entries before the
-- current one, newest first, without the player's own cell, one per cell
function Gen4TownMap.historyEntries(save, px, pz)
  local h = save and save.gen4MapHistory
  local out = {}
  if type(h) ~= "table" or type(h.items) ~= "table" then return out end
  local n = Gen4TownMap.HISTORY_LENGTH
  local at = ((h.pointer or 0) - 2 + n) % n
  for _ = 1, n - 1 do
    local e = h.items[at + 1]
    if not (e and e.set) then break end
    if not (e.x == px and e.z == pz) then
      local found
      for _, o in ipairs(out) do if o.x == e.x and o.z == e.z then found = o end end
      if not found then out[#out + 1] = { x = e.x, z = e.z } end
    end
    at = (at - 1 + n) % n
  end
  return out
end

function Gen4TownMap.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, Gen4TownMap)
  self.game = game
  self.mode = opts.mode or "map"           -- "map" or "fly"
  self.onFly = opts.onFly
  self.onCancel = opts.onCancel
  self.rec = record(game)
  self.cache = {}
  self.px, self.pz = Gen4TownMap.playerCell(game)
  self.cx, self.cz = self.px, self.pz
  self.frame, self.moveWait = 0, 0
  -- the bottom screen
  self.zoomed = false
  self.zx, self.zy = self.cx * 16 + 8 - 112, self.cz * 16 - 96
  self.info = self.mode ~= "wall" and self:blockAt(self.cx, self.cz) or nil
  self.history = self.mode ~= "wall" and Gen4TownMap.historyEntries(game.save, self.px, self.pz) or {}
  return self
end

-- ------------------------------------------------------------- the rules --

local function flagOpen(save, firstArrival)
  local flags = save and save.flags
  return type(flags) == "table"
    and flags[("FLAG_G4_%04X"):format(0x9B1 + firstArrival)] == true
end

function Gen4TownMap:locations()
  local out = {}
  local rec = self.rec
  if not rec then return out end
  for i, loc in ipairs(rec.flyLocations or {}) do
    local fa = rec.firstArrival[i] or 0
    out[i] = { loc = loc, firstArrival = fa, unlocked = flagOpen(self.game.save, fa) }
  end
  return out
end

-- TownMap_GetFlyLocationAtPos
function Gen4TownMap:flyLocationAt(header, x, z)
  for _, row in ipairs(self:locations()) do
    local loc = row.loc
    if loc.header == header then
      if not loc.special then return row end
      if loc.cell and loc.cell[1] == x and loc.cell[2] == z then return row end
    end
  end
  return nil
end

-- TownMap_GetMapBlockAtPosition
function Gen4TownMap:blockAt(x, z)
  for _, b in ipairs((self.rec and self.rec.blocks) or {}) do
    if b.x == x and b.z == z then
      if (b.hidden or 0) == 0 then return b end
      local H = require("src.world.Gen4HiddenPaths")
      for loc = 0, 3 do
        if math.floor(b.hidden / 2 ^ loc) % 2 == 1 and H.unlocked(self.game.save, loc) then
          return b
        end
      end
      return nil
    end
  end
  return nil
end

-- LoadMapName: the header's name, or for MAP_HEADER_EVERYWHERE the few cells
-- the cartridge names anyway (Mt. Coronet's inside, the Fight Area gate).
function Gen4TownMap:labelFor(header)
  if not self.labels then
    self.labels = {}
    for _, def in pairs(self.game.data.maps or {}) do
      if def.header and def.label and self.labels[def.header] == nil then
        self.labels[def.header] = def.label
      end
    end
  end
  return self.labels[header]
end

function Gen4TownMap:nameAt(x, z)
  local header = Gen4TownMap.headerAt(self.game, x, z)
  if header == EVERYWHERE then
    for _, row in ipairs((self.rec and self.rec.offMatrix) or {}) do
      if row[1] == x and row[2] == z then return self:labelFor(row[3]) end
    end
  end
  return header and self:labelFor(header) or nil
end

-- ------------------------------------------------------------- pictures --

function Gen4TownMap:img(key)
  if self.cache[key] == nil then
    local path = "assets/generated/gen4/town_map/" .. key .. ".png"
    local ok, image = pcall(Assets.image, path)
    self.cache[key] = ok and image or false
    if self.cache[key] then self.cache[key]:setFilter("nearest", "nearest") end
  end
  return self.cache[key] or nil
end

function Gen4TownMap:sprite(key, cell, slot)
  local rec = self.rec
  local im = rec and rec.images[key] and rec.images[key][(cell or 0) + 1]
  if not im then return nil end
  slot = slot or im.bank or 0
  local id = key .. "|" .. (cell or 0) .. "|" .. slot
  if self.cache[id] ~= nil then return self.cache[id] or nil, im end
  local pal = rec.spritePalette or {}
  local data = love.image.newImageData(im.w, im.h)
  for y = 0, im.h - 1 do
    for x = 0, im.w - 1 do
      local at = (y * im.w + x) * 2 + 1
      local v = tonumber(im.idx:sub(at, at + 1), 16) or 0
      if v ~= 0 then
        local c = pal[slot * 16 + v + 1] or { 255, 0, 255 }
        data:setPixel(x, y, c[1] / 255, c[2] / 255, c[3] / 255, 1)
      end
    end
  end
  local img = love.graphics.newImage(data)
  img:setFilter("nearest", "nearest")
  self.cache[id] = img
  return img, im
end

local function gridX(x) return 7 * x + 25 end
local function gridY(z) return 7 * z - 34 end

-- ----------------------------------------------------------------- input --

function Gen4TownMap:close()
  self.game.stack:pop()
  if self.onCancel then self.onCancel() end
end

function Gen4TownMap:update()
  self.frame = self.frame + 1
  self:stepBottom()
  local input = self.game.input
  if not input then return end
  -- zoomedInMapTransitionStage > 1: nothing until the sub screen has switched
  if self.switching then return end
  if input:wasPressed("b") then return self:close() end
  if self.mode == "fly" and input:wasPressed("a") then
    local header = Gen4TownMap.headerAt(self.game, self.cx, self.cz)
    local row = self:blockAt(self.cx, self.cz) and self:flyLocationAt(header, self.cx, self.cz)
    if row and row.unlocked then
      self.game.stack:pop()
      if self.onFly then self.onFly(row.firstArrival, row.loc.header) end
    end
    return
  end
  if self.moveWait > 0 then self.moveWait = self.moveWait - 1 return end
  local down = function(k) return input.isDown and input:isDown(k) end
  local moved = false
  if down("up") and self.cz >= 7 then self.cz = self.cz - 1 moved = true end
  if down("down") and self.cz <= 27 then self.cz = self.cz + 1 moved = true end
  if down("right") and self.cx <= 27 then self.cx = self.cx + 1 moved = true end
  if down("left") and self.cx >= 2 then self.cx = self.cx - 1 moved = true end
  if moved then
    self.moveWait = STEP_FRAMES - 1
    -- DoZoomedMapMvt: three ticks of 5 + 1, 5, 5 toward the new cell; a
    -- second step in a row takes the signpost down until the pad is let go
    local tx, ty = self.cx * 16 + 8 - 112, self.cz * 16 - 96
    if self.mvt or self.held then self.info = nil end
    self.mvt = { dx = tx > self.zx and 1 or (tx < self.zx and -1 or 0),
                 dy = ty > self.zy and 1 or (ty < self.zy and -1 or 0), stage = 3, wait = 0 }
    self.held = true
  elseif not (down("up") or down("down") or down("left") or down("right")) then
    self.held = false
  end
end

-- ------------------------------------------------------- bottom screen --

-- one vblank of the bottom screen: the zoomed map's slide, the zoom
-- button's press and the sub-screen fades, the history dot's turn
function Gen4TownMap:stepBottom()
  local m = self.mvt
  if m then
    m.wait = m.wait + 1
    if m.wait >= 2 then          -- a 30 Hz tick
      m.wait = 0
      local speed = m.stage == 3 and 6 or 5
      self.zx, self.zy = self.zx + m.dx * speed, self.zy + m.dy * speed
      m.stage = m.stage - 1
      if m.stage <= 0 then
        self.zx, self.zy = self.cx * 16 + 8 - 112, self.cz * 16 - 96
        self.mvt = nil
      end
    end
  end
  -- UpdateBottomScreenText once the movement is done and the pad let go
  if not self.mvt and not self.held then self.info = self:blockAt(self.cx, self.cz) end
  local sw = self.switching
  if sw then
    sw.k = sw.k + 1
    if sw.to and sw.k == Gen4TownMap.PRESS_FRAMES + Gen4TownMap.FADE_FRAMES then self.zoomed = true end
    if not sw.to and sw.k == Gen4TownMap.FADE_FRAMES then self.zoomed = false end
    local total = (sw.to and Gen4TownMap.PRESS_FRAMES or 0) + 2 * Gen4TownMap.FADE_FRAMES
    if sw.k >= total then self.switching = nil end
  end
end
Gen4TownMap.PRESS_FRAMES = 10   -- Task_SwitchBottomScreenToZoomedMap cases 0..2
Gen4TownMap.FADE_FRAMES = 8     -- StartScreenFade(.., 8, 1)
Gen4TownMap.ZOOM_STATES = { 1, 2, 1, 0 }
Gen4TownMap.ZOOM_RECT = { 104, 80, 152, 136 }   -- { 13, 10 } 6 x 7 tiles
Gen4TownMap.HISTORY_TICKS = 26

-- the zoom button's state this frame
function Gen4TownMap:zoomButtonState()
  local sw = self.switching
  if not (sw and sw.to) then return 0 end
  -- case 1 redraws on odd frame counts: state[count / 2]
  local n = sw.k - 1
  if n < 1 then return 0 end
  local last = 0
  for c = 1, math.min(n, 7), 2 do last = Gen4TownMap.ZOOM_STATES[math.floor(c / 2) + 1] or 0 end
  return last
end
-- the sub screen's fade to black, 0..1
function Gen4TownMap:bottomFade()
  local sw = self.switching
  if not sw then return 0 end
  local k = sw.k - (sw.to and Gen4TownMap.PRESS_FRAMES or 0)
  if k < 0 then return 0 end
  local F = Gen4TownMap.FADE_FRAMES
  if k <= F then return k / F end
  return math.max(0, 1 - (k - F) / F)
end

function Gen4TownMap:bottomShown()
  local okS, SS = pcall(require, "src.ui.SecondScreen")
  if not okS or not self.game then return false end
  local mode = SS.mode(self.game)
  local combined = SS.combined and SS.combined(self.game)
  return ((mode == "display" or mode == "inset") and not SS.stowed(self.game)) or combined or false, SS
end

-- GetTouchedZone
function Gen4TownMap:zoomHit(x, y)
  local ink = self.game.data.gen4_town_map_ink
  local runs = ink and ink.zoomHit
  if not runs then return true end
  y = math.floor(y)
  x = math.floor(x)
  for _, r in ipairs(runs) do
    if r[1] == y and x >= r[2] and x <= r[3] then return true end
  end
  return false
end
function Gen4TownMap:bottomTouch(x, y)
  if self.mode == "wall" then return true end
  if self.switching or self.mvt or self.touching then return true end
  self.touching = true
  if self.zoomed then
    local r = Gen4TownMap.ZOOM_RECT
    if x >= r[1] and x <= r[3] and y >= r[2] and y <= r[4] then self.switching = { k = 0, to = false } end
  elseif self:zoomHit(x, y) then
    self.switching = { k = 0, to = true }
  end
  return true
end
function Gen4TownMap:touchpressed(id, px, py)
  local shown, SS = self:bottomShown()
  local x, y
  if shown then x, y = SS.toLocal(self.game, px, py) end
  if not x then return self.game.secondScreenInjecting and true or false end
  self.pointer = id
  return self:bottomTouch(x, y)
end
function Gen4TownMap:touchreleased(id)
  if self.pointer ~= id then return false end
  self.pointer, self.touching = nil, false
  return true
end

-- the words of bank 615 (TEXT_BANK_TOWN_MAP)
function Gen4TownMap:townText(n)
  local ok, T = pcall(require, "src.import.Gen4Text")
  local text = ok and T.resolve(self.game.data, 615, n, self.game)
  if type(text) ~= "string" or text == "" then
    text = (self.game.data.text or {})[("TEXT_B0615_%05d"):format(n)]
  end
  return type(text) == "string" and text ~= "" and text or nil
end

-- PerformTownMapDescriptionsChecks for one block's area (or landmark) line
function Gen4TownMap:descShown(block, which)
  local ink = self.game.data.gen4_town_map_ink or {}
  local f = (ink.descFlags or {})[(block.index or 0) + 1]
  if not f then return true end
  local kind, flag
  if which == "area" then kind, flag = f.areaType, f.areaFlag else kind, flag = f.landmarkType, f.landmarkFlag end
  local flags = (self.game.save or {}).flags
  if kind == 1 then return flagOpen(self.game.save, flag) end
  if kind == 2 then return type(flags) == "table" and flags[("FLAG_G4_%04X"):format(flag)] == true end
  return true
end

function Gen4TownMap:artImage(key)
  local rec = (self.game.data.gen4_town_map_art or {})[key]
  local path = type(rec) == "table" and rec.path or rec
  if not path then return nil end
  if self.cache[path] == nil then
    local ok, image = pcall(Assets.image, path)
    self.cache[path] = ok and image or false
    if self.cache[path] then self.cache[path]:setFilter("nearest", "nearest") end
  end
  return self.cache[path] or nil, type(rec) == "table" and rec or {}
end

-- a 512 x 512 layer seen through the 256 x 192 screen at (sx, sy)
local function drawScrolled(self, img, sx, sy)
  if not img then return end
  local g = love.graphics
  local w, h = img:getDimensions()
  self.scrollQuads = self.scrollQuads or {}
  for _, ox in ipairs({ 0, w }) do
    for _, oy in ipairs({ 0, h }) do
      g.draw(img, ox - sx % w, oy - sy % h)
    end
  end
end

-- ShowHiddenLocation's bottom-screen pieces: { srcX, srcY, destX, destY, w, h }
-- in tiles of the 512 x 512 layers, [3] onto SUB_3, [4] onto SUB_2
local HIDDEN_BOTTOM = {
  [0] = { [3] = { 8, 0, 3, 16, 4, 4 }, [4] = { 8, 4, 3, 16, 4, 4 } },
  [1] = { [3] = { 0, 0, 8, 16, 4, 4 }, [4] = { 0, 4, 8, 16, 4, 4 } },
  [2] = { [4] = { 8, 8, 48, 42, 5, 6 } },
  [3] = { [3] = { 4, 0, 57, 12, 4, 4 }, [4] = { 4, 4, 57, 12, 4, 19 } },
}
Gen4TownMap.HIDDEN_BOTTOM = HIDDEN_BOTTOM
function Gen4TownMap:drawHiddenBottom(layer, sx, sy)
  local img = self:artImage("hidden")
  if not img then return end
  local ok, H = pcall(require, "src.world.Gen4HiddenPaths")
  if not ok then return end
  local g = love.graphics
  for loc = 0, 3 do
    local r = HIDDEN_BOTTOM[loc][layer]
    local okU, open = pcall(H.unlocked, self.game.save, loc)
    if r and okU and open then
      local q = g.newQuad(r[1] * 8, r[2] * 8, r[5] * 8, r[6] * 8, img:getDimensions())
      for _, ox in ipairs({ 0, 512 }) do
        for _, oy in ipairs({ 0, 512 }) do
          g.draw(img, q, r[3] * 8 + ox - sx % 512, r[4] * 8 + oy - sy % 512)
        end
      end
    end
  end
end

-- Window_DrawSignpost: field_board's frame tiles round a window, the picture
-- for a MAP / ARROW signpost at x - 7
function Gen4TownMap:drawSignpost(block, name)
  local g = love.graphics
  local t = block.signpostType or 2
  local strip = self:artImage("sign_frame_" .. t)
  local ink = (self.game.data.gen4_town_map_ink or {}).signInk or {}
  local si = ink[t] or {}
  local boardType = (t == 0 or t == 1)
  local wx, wy, ww, wh = boardType and 9 or 2, 3, boardType and 21 or 28, 4
  if strip then
    self.signQuads = self.signQuads or {}
    local function tile(i, tx, ty, n)
      local key = tostring(strip) .. i
      if not self.signQuads[key] then self.signQuads[key] = g.newQuad(i * 8, 0, 8, 8, strip:getDimensions()) end
      for k = 0, (n or 1) - 1 do g.draw(strip, self.signQuads[key], (tx + k) * 8, ty * 8) end
    end
    g.setColor(1, 1, 1, 1)
    local left = boardType and wx - 9 or wx - 2
    local runFrom = boardType and wx - 7 or wx
    local runLen = boardType and ww + 7 or ww
    for _, row in ipairs({ { wy - 1, 0 }, { wy + wh, 12 } }) do
      tile(row[2], left, row[1]); tile(row[2] + 1, left + 1, row[1])
      tile(row[2] + 2, runFrom, row[1], runLen)
      tile(row[2] + 3, wx + ww, row[1]); tile(row[2] + 4, wx + ww + 1, row[1]); tile(row[2] + 5, wx + ww + 2, row[1])
    end
    for y = wy, wy + wh - 1 do
      tile(6, left, y); tile(7, left + 1, y)
      if boardType then tile(8, wx - 1, y) end
      tile(9, wx + ww, y); tile(10, wx + ww + 1, y); tile(11, wx + ww + 2, y)
    end
  end
  if boardType then
    local pic = self:artImage(("sign_%d_%d"):format(t, block.signpost or 0))
    if pic then g.setColor(1, 1, 1, 1); g.draw(pic, (wx - 7) * 8, wy * 8) end
  end
  local paper = si.paper or { 255, 255, 255 }
  g.setColor(paper[1] / 255, paper[2] / 255, paper[3] / 255, 1)
  g.rectangle("fill", wx * 8, wy * 8, ww * 8, wh * 8)
  g.setColor(1, 1, 1, 1)
  if name then
    local faced = Font.pushFace and Font.pushFace("message")
    local tc, sc = si.text or { 82, 82, 90 }, si.shadow or { 165, 165, 173 }
    Font.pushStyle({ text = { tc[1] / 255, tc[2] / 255, tc[3] / 255 }, shadow = { sc[1] / 255, sc[2] / 255, sc[3] / 255 } })
    Font.draw(name, wx * 8, wy * 8)
    Font.popStyle()
    if faced and Font.popFace then Font.popFace() end
  end
end

function Gen4TownMap:drawBottom()
  local g = love.graphics
  local ink = self.game.data.gen4_town_map_ink or {}
  local bd = ink.backdrop or { 41, 90, 66 }
  g.setColor(bd[1] / 255, bd[2] / 255, bd[3] / 255, 1)
  g.rectangle("fill", 0, 0, W, H)
  g.setColor(1, 1, 1, 1)
  if not self.zoomed then
    local screen = self:artImage("zoom_screen")
    if screen then g.draw(screen, 0, 0) end
    local btn = self:artImage("zoom_button_" .. self:zoomButtonState())
    if btn then g.draw(btn, 104, 80) end
    -- the shockwave, cells 0 / 1 / 2 four frames each, while pressed
    local sw = self.switching
    if sw and sw.to and sw.k < Gen4TownMap.PRESS_FRAMES then
      local cell = math.min(2, math.floor(sw.k / 4))
      local img, rec = self:artImage("shockwave_" .. cell)
      if img then g.draw(img, 128 + (rec.originX or -32), 108 + (rec.originY or -32)) end
    end
  else
    -- MoveZoomedInMap's clamp
    local sx = math.max(8, math.min(256 - 8, self.zx))
    local sy = math.max(72 + 8, math.min(240 + 72 - 8, self.zy))
    drawScrolled(self, self:artImage("zoom_bg"), sx, sy)
    self:drawHiddenBottom(3, sx, sy)
    drawScrolled(self, self:artImage("zoom_map"), sx, sy)
    self:drawHiddenBottom(4, sx, sy)
    local header = self:artImage("header")
    if header then g.draw(header, 80, 0) end
    local title = self:townText(1)
    if title then
      local faced = Font.pushFace and Font.pushFace("system")
      local tw = Font.width and Font.width(title) or #title * 6
      Font.draw(title, 88 + math.floor((80 - tw) / 2), 0)
      if faced and Font.popFace then Font.popFace() end
    end
    local block = self.info
    if block then
      local name = self:nameAt(self.cx, self.cz)
      self:drawSignpost(block, name)
      local si = (ink.signInk or {})[block.signpostType or 2] or {}
      local tc, sc = si.text or { 82, 82, 90 }, si.shadow or { 165, 165, 173 }
      local full
      for _, b in ipairs(ink.blocks or {}) do
        if b.x == block.x and b.z == block.z then full = b break end
      end
      full = full or block
      local faced = Font.pushFace and Font.pushFace("system")
      Font.pushStyle({ text = { tc[1] / 255, tc[2] / 255, tc[3] / 255 }, shadow = { sc[1] / 255, sc[2] / 255, sc[3] / 255 } })
      for _, which in ipairs({ "area", "landmark" }) do
        local n = which == "area" and full.areaDesc or full.landmarkDesc
        if n and n ~= 0xFFFF and self:descShown(full, which) then
          local text = self:townText(n)
          if text then
            local x = 8 + (which == "area" and (full.areaX or 0) or (full.landmarkX or 0))
            local y = 64 + (which == "area" and (full.areaY or 0) or (full.landmarkY or 0))
            for line in (text:gsub("[\r\f\v]", "\n") .. "\n"):gmatch("([^\n]*)\n") do
              Font.draw(line, x, y); y = y + 16
            end
          end
        end
      end
      Font.popStyle()
      if faced and Font.popFace then Font.popFace() end
    end
  end
  local fade = self:bottomFade()
  if fade > 0 then g.setColor(0, 0, 0, fade); g.rectangle("fill", 0, 0, W, H); g.setColor(1, 1, 1, 1) end
end

function Gen4TownMap:drawSubscreen()
  local shown, SS = self:bottomShown()
  if not shown then return end
  SS.draw(self.game, function() self:drawBottom() end)
end

-- ------------------------------------------------------------------ draw --

-- ShowHiddenLocation: each unlocked hidden location (Gen4HiddenPaths order --
-- Fullmoon Island, Newmoon Island, Spring Path, Seabreak Path) copies tiles of
-- hidden_locations_top_screen.NSCR into the region BG (layer 1 here, BG3) and
-- the route layer (2, BG2): { srcX, srcY, destX, destY, w, h } in tiles.
local HIDDEN_RECTS = {
  [0] = { { 5, 0, 3, 1, 2, 3 }, { 5, 3, 3, 2, 2, 2 } },
  [1] = { { 0, 0, 6, 1, 2, 3 }, { 0, 3, 6, 2, 2, 2 } },
  [2] = { nil, { 4, 5, 22, 13, 3, 3 } },
  [3] = { { 2, 0, 26, 0, 3, 3 }, { 2, 3, 27, 0, 2, 9 } },
}
Gen4TownMap.HIDDEN_RECTS = HIDDEN_RECTS

function Gen4TownMap:drawHiddenLocations(layer)
  local img = self:img("hidden_locations_top_screen")
  if not img then return end
  local ok, H = pcall(require, "src.world.Gen4HiddenPaths")
  if not ok then return end
  local g = love.graphics
  self.hiddenQuads = self.hiddenQuads or {}
  for loc = 0, 3 do
    local r = HIDDEN_RECTS[loc][layer]
    local okU, open = pcall(H.unlocked, self.game.save, loc)
    if r and okU and open then
      local key = loc .. ":" .. layer
      local q = self.hiddenQuads[key]
      if not q then
        q = g.newQuad(r[1] * 8, r[2] * 8, r[5] * 8, r[6] * 8, img:getDimensions())
        self.hiddenQuads[key] = q
      end
      g.setColor(1, 1, 1, 1)
      g.draw(img, q, r[3] * 8, r[4] * 8)
    end
  end
end

function Gen4TownMap:draw()
  local g = love.graphics
  g.clear(0, 0, 0, 1)
  g.setColor(1, 1, 1, 1)
  local bg, routes = self:img("top_screen_region_bg"), self:img("top_screen_region_map")
  if bg then
    g.draw(bg, 0, 0)
    -- LoadMapGraphics: outside FLY the bar's arrow (between "Fly to where?"
    -- and the name) is covered with the bar's own tiles from (0, 21)
    if self.mode ~= "fly" then
      self.arrowQuad = self.arrowQuad or g.newQuad(0, 168, 16, 24, bg:getDimensions())
      g.draw(bg, self.arrowQuad, 128, 168)
    end
  end
  self:drawHiddenLocations(1)
  if routes then g.draw(routes, 0, 0) end
  self:drawHiddenLocations(2)

  -- the town blocks
  local header = Gen4TownMap.headerAt(self.game, self.cx, self.cz)
  local hovered = self:blockAt(self.cx, self.cz) and self:flyLocationAt(header, self.cx, self.cz)
  local blinkOn = math.floor(self.frame / BLINK_FRAMES) % 2 == 0
  for _, row in ipairs(self:locations()) do
    local loc = row.loc
    local hidden = not row.unlocked and (loc.special == "palPark" or loc.special == "victoryRoad")
    if not hidden then
      local slot = 5 + loc.palette + (row.unlocked and 1 or 0)
      if self.mode == "fly" and hovered == row and row.unlocked and blinkOn then
        slot = 8 + loc.palette
      end
      local img, im = self:sprite("flyBlocks", loc.shape, slot)
      if img then g.draw(img, loc.x + 25 + im.x, loc.y - 34 + im.y) end
    end
  end

  -- the location history: one dot at a time, oldest first, a new one every
  -- 26 ticks (priority 2, under the player and cursor; palette row 2)
  local hist = self.history or {}
  if #hist > 0 then
    local step = math.floor(self.frame / (2 * Gen4TownMap.HISTORY_TICKS))
    local e = hist[#hist - (step % #hist)]
    local dimg, dim = self:sprite("historyDot", 0, 2)
    if e and dimg then g.draw(dimg, gridX(e.x) + dim.x, gridY(e.z) + dim.y) end
  end

  -- the player, then the cursor
  local girl = ((self.game.save or {}).player or {}).gender
  girl = girl == "girl" or girl == "female"
  local pimg, pim = self:sprite("player", girl and 1 or 0)
  if pimg then g.draw(pimg, gridX(self.px) + pim.x, gridY(self.pz) + pim.y) end
  local cimg, cim = self:sprite("cursor", math.floor(self.frame / 16) % 2)
  if cimg then g.draw(cimg, gridX(self.cx) + cim.x, gridY(self.cz) + cim.y) end

  -- the bar: window at tile (3, 21), text at y + 6 (PrintLocationName)
  local faced = Font.pushFace and Font.pushFace("system")
  g.setColor(1, 1, 1, 1)
  local name = self:blockAt(self.cx, self.cz) and self:nameAt(self.cx, self.cz)
  local wx, wy = 24, 21 * 8 + 6 - 4
  if self.mode == "fly" then
    local text = (self.game.data.text or {}).TEXT_B0615_00000 or "Fly to where?"
    Font.draw(text, wx, wy)
    if name then Font.draw(name, wx + 15 * 8 + 2, wy) end
  elseif name then
    local tw = Font.width and Font.width(name) or #name * 6
    Font.draw(name, wx + math.floor((W - 6 * 8 - tw) / 2), wy)
  end
  if faced and Font.popFace then Font.popFace() end
  self:drawSubscreen()
end

return Gen4TownMap
