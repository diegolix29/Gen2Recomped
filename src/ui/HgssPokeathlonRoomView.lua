-- src/ui/HgssPokeathlonRoomView.lua -- HEARTGOLD / SOULSILVER POKeATHLON DOME:
-- WHAT THE FOUR SIDE-ROOM SCREENS SHARE (ScrCmd_712's overlay-99 apps,
-- src/ui/HgssPokeathlonCourseRecord.lua, HgssPokeathlonMedalList.lua,
-- HgssPokeathlonEventRecord.lua, HgssPokeathlonTrophies.lua). Overlay 98 is
-- their library on the cartridge; this is the port's.
--
-- READ FROM CODE (pokeheartgold asm/overlay_98.s):
--   * ov98_0221F090: engine A on the BOTTOM screen (POWCNT bit 15 cleared),
--     so the cartridge's "main" is the touch screen; drawBottom / drawTop
--     below follow the screens, not the engines
--   * the text (ov98_0221EABC / 0221EBEC / 0221EC08 / 0221EC3C): bank 314,
--     palette row 12 = LoadFontPal0, colour MAKE_TEXT_COLOR(1, 2, 0), the
--     window cleared to 0 first, instant; centring x = ((w * 8 - width) &
--     0xFF) >> 1; numbers BufferIntegerAsString(..., PRINTING_MODE_RIGHT_ALIGN)
--   * the fades (states 0 / 3 of every Main): BeginNormalPaletteFade both
--     screens to / from black, 6 steps of 1 frame; SE 1500 (SEQ_SE_DP_SELECT)
--     as the screen closes
--   * ov98_0221EF24, the shared way out: a new touch in x 192..255, y 160..191
--     (the "Return" plate) or a new B
--   * ov98_0221F120 digit n of v = (v % 10^n) / 10^(n - 1); ov98_0221F150 its
--     digit count (0 has one)
--   * the OBJs animate (SpriteSystem_DrawSprites each frame, animate flag on);
--     an NANR sequence is { cell, ticks } frames, looped here
--
-- STAND-INS, said so:
--   * the right-aligned numbers pad with the port font's space, not the
--     cartridge's CHAR_NARROW_SPACE
--   * FONT_UNK_4 (the "Return" / "Link" plate font) is the port's one font
--   * Pokemon icons are the port's icon sheets (data.icons / def.icon, two
--     frames, 8 ticks each -- poke_icon's NANR is not read), drawn about their
--     centre like the cartridge's 32 x 32 cell; the front pictures are
--     src/pokemon/Sprites' (no 80 x 80 VRAM placeholder)
--   * single screen: the touch screen is shown; SELECT or L held shows the top

local Font = require("src.render.Font")
local T = require("src.import.Gen4Text")

local V = {}

V.BANK = 314
V.NAMES = 313        -- course 0.., medal 15.., event 20..
V.SE = "SEQ_SE_DP_SELECT"
V.FADE = 6
V.RETURN = { 192, 160, 256, 192 }  -- ov98_0221F1E0

function V.art(game) return ((game and game.data) or {}).gen4_hgss_athlon_rooms or {} end

-- a save table's entry keyed by a number (a JSON round trip makes it a string)
function V.at(t, k)
  if type(t) ~= "table" then return nil end
  local v = t[k]
  if v == nil then v = t[tostring(k)] end
  return v
end

-- --------------------------------------------------------------- images --

local cache = setmetatable({}, { __mode = "k" })

-- a saved path (Assets) or, from a harness's ROM read, an in-memory ImageData
-- (HgssSummaryMenu:hgImg's pattern)
function V.img(rec)
  if type(rec) ~= "table" then return nil end
  if cache[rec] == nil then
    local out = false
    if rec.image then
      local ok, i = pcall(love.graphics.newImage, rec.image)
      out = ok and i or false
    elseif rec.path then
      local ok, i = pcall(require("src.render.Assets").image, rec.path)
      out = ok and i or false
    end
    if out then out:setFilter("nearest", "nearest") end
    cache[rec] = out
  end
  return cache[rec] or nil
end

-- a whole-screen layer at (x, y)
function V.layer(game, key, x, y)
  local i = V.img(V.art(game)[key])
  if not i then return false end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(i, x or 0, y or 0)
  return true
end

-- an OBJ cell image about its anchor
function V.cell(game, key, x, y)
  local rec = key and V.art(game)[key]
  local i = V.img(rec)
  if not i then return false end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(i, math.floor(x + (tonumber(rec.originX) or 0)), math.floor(y + (tonumber(rec.originY) or 0)))
  return true
end

-- the cell sequence `seq` ("o0_8") shows at `tick`, looping: its key (nil
-- for a blank frame) and the frame's translation
function V.frame(game, seq, tick)
  local list = (V.art(game).seqs or {})[seq]
  if type(list) ~= "table" or #list == 0 then return nil end
  local total = 0
  for _, f in ipairs(list) do total = total + (tonumber(f[2]) or 1) end
  local t = (math.floor(tonumber(tick) or 0)) % math.max(1, total)
  local pick = list[#list]
  for _, f in ipairs(list) do
    t = t - (tonumber(f[2]) or 1)
    if t < 0 then pick = f; break end
  end
  return pick[1] or nil, tonumber(pick[3]) or 0, tonumber(pick[4]) or 0
end

-- a sprite: set `set` sequence `seq` at (x, y), `tick` frames into it
function V.sprite(game, set, seq, x, y, tick)
  local key, dx, dy = V.frame(game, ("o%d_%d"):format(set, seq), tick)
  if key then return V.cell(game, key, x + dx, y + dy) end
  return false
end

-- ----------------------------------------------------------------- text --

local INK_FALLBACK = { { 90, 90, 82 }, { 173, 189, 189 }, { 239, 33, 16 }, { 255, 173, 189 },
  [7] = { 0, 115, 255 }, [8] = { 123, 189, 239 } }

local function unit(c, fb)
  c = c or fb or { 0, 0, 0 }
  return { c[1] / 255, c[2] / 255, c[3] / 255, 1 }
end

function V.ink(game)
  local t = V.art(game).ink or {}
  return unit(t[1], INK_FALLBACK[1]), unit(t[2], INK_FALLBACK[2])
end

-- one line of text in two-tone ink (fg, shadow: 0..1 colours)
function V.say(game, s, x, y, fg, sh)
  if not s or s == "" then return end
  if not fg then fg, sh = V.ink(game) end
  love.graphics.setColor(1, 1, 1, 1)
  local two = Font.beginTwoTone(fg, sh)
  if not two then love.graphics.setColor(fg) end
  Font.draw(s, math.floor(x), math.floor(y))
  if two then Font.endTwoTone() end
  love.graphics.setColor(1, 1, 1, 1)
end

-- a bank line, its placeholders filled from `args` (slot 0 first): a list of
-- printed lines, each { center = bool, parts = { {x or nil, text} } } --
-- {ALN_CENTER} and {CURSOR_X n} are layout, kept here; the rest goes through
-- the script markup like every other bank line
function V.lines(game, bank, n, args)
  local raw = game.data and game.data.text and game.data.text[T.label(bank, n)]
  if type(raw) ~= "string" then return nil end
  T.buffer(game, unpack(args or {}))
  local okC, Commands = pcall(require, "src.script.Commands")
  local function markup(s)
    if okC and Commands and Commands.gen4Markup then
      local ok, p = pcall(Commands.gen4Markup, s, game)
      if ok and type(p) == "string" then s = p end
    end
    return (s:gsub("[\v\f]", ""):gsub("{[^}]*}", ""))
  end
  local out = {}
  for l in (raw:gsub("[\v\f]", "\n") .. "\n"):gmatch("(.-)\n") do
    local row = { center = l:find("{ALN_CENTER}", 1, true) ~= nil, parts = {} }
    l = l:gsub("{ALN_CENTER}", "")
    local at, x = 1, nil
    while true do
      local s, e, cx = l:find("{CURSOR_X (%d+)[^}]*}", at)
      if not s then break end
      row.parts[#row.parts + 1] = { x, markup(l:sub(at, s - 1)) }
      at, x = e + 1, tonumber(cx)
    end
    row.parts[#row.parts + 1] = { x, markup(l:sub(at)) }
    out[#out + 1] = row
  end
  while #out > 1 and out[#out].parts[1][2] == "" and #out[#out].parts == 1 do out[#out] = nil end
  return out
end

function V.text(game, bank, n, args, fallback)
  local l = V.lines(game, bank, n, args)
  if not l then return fallback end
  local t = {}
  for _, row in ipairs(l) do
    local s = ""
    for _, p in ipairs(row.parts) do s = s .. p[2] end
    t[#t + 1] = s
  end
  local s = table.concat(t, "\n")
  return s ~= "" and s or fallback
end

-- print bank `bank` line `n` into a window at pixel (wx, wy), `ww` tiles wide:
-- opts.x / opts.y the print offset, opts.center (ov98_0221EC3C), opts.args,
-- opts.fallback (when the cache has no text), opts.fg / opts.sh
function V.print(game, bank, n, wx, wy, ww, opts)
  opts = opts or {}
  local l = V.lines(game, bank, n, opts.args)
  if not l and opts.fallback then l = { { parts = { { nil, opts.fallback } } } } end
  if not l then return end
  for i, row in ipairs(l) do
    local y = wy + (opts.y or 0) + 16 * (i - 1)
    if opts.center or row.center then
      local s = ""
      for _, p in ipairs(row.parts) do s = s .. p[2] end
      local w = Font.width(s)
      V.say(game, s, wx + math.floor(((ww * 8 - w) % 256) / 2), y, opts.fg, opts.sh)
    else
      local x = wx + (opts.x or 0)
      for _, p in ipairs(row.parts) do
        if p[1] then x = wx + p[1] end
        V.say(game, p[2], x, y, opts.fg, opts.sh)
        x = x + Font.width(p[2])
      end
    end
  end
end

-- BufferIntegerAsString(..., digits, PRINTING_MODE_RIGHT_ALIGN)
function V.num(v, digits)
  local s = tostring(math.floor(tonumber(v) or 0))
  if digits and #s > digits then s = s:sub(-digits) end
  return (" "):rep(math.max(0, (digits or 0) - #s)) .. s
end

-- ov98_0221F120 / 0221F150
function V.digit(v, n) return math.floor((v % 10 ^ n) / 10 ^ (n - 1)) end
function V.digits(v)
  local n = 1
  while v >= 10 ^ n do n = n + 1 end
  return n
end

function V.name(game, bank, n, fallback)
  local t = T.resolve(game.data, bank, n, game)
  t = t and t:gsub("{[^}]*}", "")
  return (t and t ~= "") and t or fallback
end

-- a species' name as the cartridge prints it: bank 237 (BufferSpeciesName)
function V.species(game, species)
  local def = game.data and game.data.pokemon and game.data.pokemon[species]
  return V.name(game, 237, species, (def and def.name) or tostring(species))
end

-- ------------------------------------------------------------- Pokemon --

local pics = {}
local function asset(path)
  if pics[path] == nil then
    local ok, i = pcall(require("src.render.Assets").image, path)
    pics[path] = ok and i or false
    if pics[path] then pics[path]:setFilter("nearest", "nearest") end
  end
  return pics[path] or nil
end

-- the Pokemon's icon (frame 0 / 1) about (x, y)
function V.icon(game, species, form, x, y, frame)
  local data = game.data or {}
  local icons = data.icons
  local def = data.pokemon and data.pokemon[species]
  local entry = (icons and icons.bySpecies and icons.bySpecies[species]) or (def and def.icon)
  local path = type(entry) == "table" and entry.image or entry
  local img = type(path) == "string" and asset(path)
  if not img then return end
  local fh = (type(entry) == "table" and tonumber(entry.frameHeight)) or 32
  local iw, ih = img:getDimensions()
  local frames = math.max(1, math.floor(ih / fh))
  local f = (frame or 0) % frames
  local q = love.graphics.newQuad(0, f * fh, iw, math.min(fh, ih), iw, ih)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, q, math.floor(x - iw / 2), math.floor(y - fh / 2))
end

-- the front picture about (x, y); mon = { species, form, gender, shiny, personality }
function V.front(game, mon, x, y)
  local okS, Sprites = pcall(require, "src.pokemon.Sprites")
  if not okS or not mon or not mon.species or mon.species == 0 then return end
  local ok, path = pcall(Sprites.path, game.data, mon.species, "front", { mon = mon, kind = "summary" })
  local img = ok and type(path) == "string" and asset(path)
  if not img then return end
  local w, h = img:getDimensions()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, math.floor(x - w / 2), math.floor(y - h / 2))
end

-- ---------------------------------------------------------------- input --

function V.pressed(game, b)
  local input = game.input
  return input and input:wasPressed(b) or false
end

-- a pad direction pressed now or repeating (delay, then every `rate`)
function V.repeating(self, b, delay, rate)
  local input = self.game.input
  self.held = self.held or {}
  if input and input:wasPressed(b) then self.held[b] = 1; return true end
  if not (input and input.isDown and input:isDown(b)) then self.held[b] = nil; return false end
  local n = (self.held[b] or 0) + 1
  self.held[b] = n
  if n == 1 then return true end
  return n > delay and (n - delay - 1) % rate == 0
end

function V.playSe(game)
  pcall(function() require("src.core.Sound").playSe(game.data, V.SE) end)
end

function V.separate(game)
  local ok, SS = pcall(require, "src.ui.SecondScreen")
  return ok and SS.separate(game) and not (SS.stowed and SS.stowed(game)) and SS or nil
end

-- a touch's point on the touch screen (nil when it is not there)
function V.toLocal(game, x, y)
  local SS = require("src.ui.SecondScreen")
  local px, py = SS.toLocal(game, x, y)
  if not px then
    if SS.separate(game) then return nil end
    local rect = require("src.render.Renderer").uiPresentation
    if rect then px, py = (x - rect.x) / rect.scaleX, (y - rect.y) / rect.scaleY else px, py = x, y end
  end
  return px, py
end

function V.inRect(px, py, r) return px >= r[1] and py >= r[2] and px < r[3] and py < r[4] end

-- ------------------------------------------------------- the app's frame --

-- the fade / input / close cycle every Main has: states 0 (fade in), 2
-- (`self:step()` until it asks to close), 3 (fade out), then pop + onDone
function V.update(self)
  self.tick = (self.tick or 0) + 1
  if self.phase == nil then self.phase, self.fade = "in", V.FADE end
  if self.everyFrame then self:everyFrame() end
  if self.phase == "in" then
    self.fade = self.fade - 1
    if self.fade <= 0 then self.phase = "run" end
  elseif self.phase == "run" then
    if self:step() then
      V.playSe(self.game)
      self.phase, self.fade = "out", 0
    end
  elseif self.phase == "out" then
    self.fade = self.fade + 1
    if self.fade >= V.FADE then V.close(self) end
  end
end

function V.close(self)
  if self.closed then return end
  self.closed = true
  self.game.stack:pop()
  if self.onDone then self.onDone() end
end

-- this frame's new touch on the touch screen (touchpressed keeps it for the
-- next update, which is where the cartridge's input functions look)
function V.takeTouch(self)
  local t = self.touchAt
  self.touchAt = nil
  if t then return t[1], t[2] end
  return nil
end

-- ov98_0221EF24: a new B, or a new touch on the Return plate
function V.leaving(self, px, py)
  if px and V.inRect(px, py, V.RETURN) then return true end
  return V.pressed(self.game, "b")
end

local function shade(self)
  local a = (self.fade or 0) / V.FADE
  if a > 0 then
    love.graphics.setColor(0, 0, 0, math.min(1, a))
    love.graphics.rectangle("fill", 0, 0, 256, 192)
    love.graphics.setColor(1, 1, 1, 1)
  end
end

function V.draw(self)
  local game = self.game
  local SS = V.separate(game)
  if SS then
    self:drawTop(); shade(self)
    SS.draw(game, function() self:drawBottom(); shade(self) end)
  else
    local input = game.input
    local held = input and input.isDown and (input:isDown("select") or input:isDown("l"))
    if held then self:drawTop() else self:drawBottom() end
    shade(self)
  end
end

-- the methods every app takes as they are
function V.mixin(M)
  M.isOpaque = true
  function M:uiSize() return 256, 192 end
  function M:wantsFillScale() return true end
  function M:update() V.update(self) end
  function M:draw() V.draw(self) end
  function M:touchmoved() return true end
  function M:touchreleased() return true end
  function M:touchpressed(_, x, y)
    local px, py = V.toLocal(self.game, x, y)
    if not px then return false end
    if self.phase == "run" then self.touchAt = { px, py } end
    return true
  end
end

return V
