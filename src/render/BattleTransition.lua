-- The into-battle transition (engine/battle/battle_transitions.asm):
-- one of the original's eight wipes selected by three bits,  trainer
-- battle (bit 0), enemy at least 3 levels above the lead (bit 1),
-- dungeon map (bit 2):
--   %000 DoubleCircle  %001 Spiral(in)  %010 Circle    %011 Spiral(out)
--   %100 HStripes      %101 Shrink      %110 VStripes  %111 Split
-- Only the two circle wipes flash the screen first (only they call
-- BattleTransition_FlashScreen); the spiral runs inward unless the
-- enemy is stronger (wBattleTransitionSpiralDirection).
-- Pushed above the overworld; pops itself and runs onDone at the end.

local Runtime = require("src.mods.Runtime")

local BattleTransition = {}
BattleTransition.__index = BattleTransition
BattleTransition.isOpaque = false -- draws over the frozen overworld

-- BattleTransition_FlashScreenPalettes: fade to black and back, then to
-- white and back; each palette held 2 frames, whole sequence played 3
-- times. Positive = black overlay strength, negative = white.
local FLASH_STEPS = { 1 / 3, 2 / 3, 1, 2 / 3, 1 / 3, 0,
                      -1 / 3, -2 / 3, -1, -2 / 3, -1 / 3, 0 }
local FLASH_HOLD = 2   -- frames per palette step
local FLASH_CYCLES = 3

-- The screen stays black after the wipe lands.  Shrink and Split ask for it
-- outright (BattleTransition_BlackScreen, then `ld c, 10 / jp DelayFrames`:
-- battle_transitions.asm:390-392 and 422-424); the other six get the same gap
-- for free, because BattleTransition_BlackScreen has already set rBGP/rOBP0/
-- rOBP1 to $ff (:168-174) while DoBattleTransitionAndInitBattleVariables
-- reloads the HUD tile patterns and clears the screen (core.asm:6152-6185),
-- InitBattleCommon decompresses the front pic (core.asm:6694-6730), and
-- SlidePlayerAndEnemySilhouettesOnScreen rebuilds the whole tilemap between
-- DisableLCD and EnableLCD (core.asm:9-49) before anything moves.  This port
-- has no load to hide behind, so the hold has to be explicit (#315).  This is
-- a frame budget for that work, not a number pokered states.
--
-- 60 comes from pokered-c (BTRANS_BLACK_HOLD_FRAMES), which itemized the
-- derivable floor at ~13 frames -- LoadHpBarAndStatusTilePatterns 4,
-- LoadHudTilePatterns 2, ClearScreen's Delay3 3, the DisableLCD LY wait 1,
-- Delay3 after EnableLCD 3 -- and then noted that the two sprite
-- decompressors (UncompressSpriteFromDE for the 7x7 front pic,
-- LoadPlayerBackPic's uncompress + ScaleSpriteByTwo) are bit-level RLE/delta
-- decoders whose cost cannot be cycle-counted from the asm at all.  So the
-- derivation bottoms out around 25-30 with an unbounded remainder, and 60
-- was set by ear against the real ROM ("a solid second") and confirmed as
-- ~95% right rather than frame-matched.  The credible range is 30-60; do NOT
-- "correct" this down toward the floor on the strength of the derivation,
-- because the omitted decompressors are exactly the unbounded part.  It
-- wants a frame-by-frame capture against hardware to pin exactly.
local BLACK_HOLD = 60

local TILE = 8
local COLS, ROWS = 160 / TILE, 144 / TILE -- 20 x 18 tiles

-- outward spiral (%011): BattleTransition_OutwardSpiral_ walks from
-- (10,10) counterclockwise (right/up/left/down), turning whenever the
-- tile on its outer side is unfilled; 120 frames x 3 fills = 360 fills
-- on linear tilemap memory. At the screen edges the walk reads (and
-- fills) adjacent WRAM, so the left column and part of the top row stay
-- unfilled until the final blackout,  reproduced here by tracking those
-- cells but not drawing them.
local function outwardSpiralOrder()
  local order, filled = {}, {}
  local addr = 10 * COLS + 10 -- hlcoord 10,10
  local dir = 3               -- 0 up / 1 left / 2 down / 3 right
  local checkOff = { [0] = -1, [1] = COLS, [2] = 1, [3] = -COLS }
  local moveOff = { [0] = -COLS, [1] = -1, [2] = COLS, [3] = 1 }
  for _ = 1, COLS * ROWS do
    local checked = addr + checkOff[dir]
    if not filled[checked] then
      addr = checked
      dir = (dir + 1) % 4
    else
      addr = addr + moveOff[dir]
    end
    if not filled[addr] then
      filled[addr] = true
      if addr >= 0 and addr < COLS * ROWS then
        order[#order + 1] = { addr % COLS, math.floor(addr / COLS) }
      end
    end
  end
  return order
end

-- inward spiral (%001): BattleTransition_InwardSpiral starts at (0,0)
-- and walks the perimeter counterclockwise,  down the left edge, right
-- along the bottom, up the right edge, left along the top,  spiraling
-- in; 359 fills, the center tile is left for the final blackout
local function inwardSpiralOrder()
  local order = {}
  local x, y = 0, 0
  local function run(dx, dy, n)
    for _ = 1, n do
      order[#order + 1] = { x, y }
      x, y = x + dx, y + dy
    end
  end
  run(0, 1, 17) -- SCREEN_HEIGHT - 1
  local c = 18
  while true do
    c = c + 1
    run(1, 0, c)  -- right
    c = c - 2
    run(0, -1, c) -- up
    c = c + 1
    run(-1, 0, c) -- left
    c = c - 2
    if c == 0 then break end
    run(0, 1, c)  -- down
  end
  return order
end

-- sweep order (the Circle wipes): tiles sorted by angle from the center.
-- pokered sweeps counterclockwise starting at the right edge middle
-- (BattleTransition_HalfCircle1 runs (18,6) up over the top to (1,6);
-- HalfCircle2 continues (1,11) down under the bottom back to (18,11)).
-- arms = 1 (Circle, halves in sequence) or 2 (DoubleCircle, both halves
-- at once, so opposite arms)
local function sweepOrder(arms, cols, rows)
  cols, rows = cols or COLS, rows or ROWS
  local cx, cy = cols / 2, rows / 2
  local tiles = {}
  for y = 0, rows - 1 do
    for x = 0, cols - 1 do
      local a = math.atan2(cy - (y + 0.5), x + 0.5 - cx)
      if a < 0 then a = a + 2 * math.pi end
      if arms == 2 then a = a % math.pi end
      tiles[#tiles + 1] = { x, y, a }
    end
  end
  table.sort(tiles, function(p, q) return p[3] < q[3] end)
  return tiles
end

-- ---------------------------------------------------------------------
-- Arbitrary-grid wipes, for the surface OUTSIDE the classic letterbox
-- ---------------------------------------------------------------------
--
-- The builders above reproduce the ROM's exact walks on its 20x18 tilemap,
-- overrun and all, and stay the authority inside the 160x144 box.  A zoomed
-- or windowed surface has more grid than the Game Boy ever had, and no
-- hardware behaviour to be faithful to out there -- but filling it with a
-- generic square cascade made a spiral read as "a spiral in a box, with
-- something else happening around it".  These generalise the same shapes to
-- whatever grid the window works out to so the whole surface wipes as one
-- figure.

-- perimeter inward, counterclockwise, starting down the left edge -- the
-- direction BattleTransition_InwardSpiral walks
local function spiralInGrid(cols, rows)
  local order = {}
  local x0, y0, x1, y1 = 0, 0, cols - 1, rows - 1
  while x0 <= x1 and y0 <= y1 do
    for y = y0, y1 do order[#order + 1] = { x0, y } end
    x0 = x0 + 1
    if x0 > x1 then break end
    for x = x0, x1 do order[#order + 1] = { x, y1 } end
    y1 = y1 - 1
    if y0 > y1 then break end
    for y = y1, y0, -1 do order[#order + 1] = { x1, y } end
    x1 = x1 - 1
    if x0 > x1 then break end
    for x = x1, x0, -1 do order[#order + 1] = { x, y0 } end
    y0 = y0 + 1
  end
  return order
end

-- the outward spiral is the same walk read from the middle out
local function spiralOutGrid(cols, rows)
  local inward = spiralInGrid(cols, rows)
  local order = {}
  for i = #inward, 1, -1 do order[#order + 1] = inward[i] end
  return order
end

-- ---------------------------------------------------------------------------
-- HOENN'S OWN WIPES
--
-- Reported from play: "also seem to be missing a lot of the battle
-- transitions from emerald that play when you start a wild encounter or
-- trainer battle".  They were missing, and deliberately: the pair above this
-- are FADES, because a fade is the one shape that ports exactly, and the note
-- there says the showier ones "are a feature rather than a fix".  This is
-- that feature.
--
-- WHAT THESE ARE AND ARE NOT.  Emerald's transitions are scanline and palette
-- tricks -- a real slice shears the BG registers line by line, a real ripple
-- is a sine table written into BGHOFS every scanline.  This engine composites
-- whole frames, so none of those can be replayed literally.  What CAN be
-- replayed is the FIGURE each one draws: the order the screen goes dark in.
-- That is what the wipe machinery already expresses -- a walk over the tile
-- grid -- and it is why the Game Boy's eight look right here at any window
-- size.  So each of these is Emerald's figure on this engine's wipe, and the
-- name says which cartridge transition it is standing in for.
--
-- Every one is written against an arbitrary cols x rows grid rather than
-- against 20x18, so they are continuous out through the letterbox like the
-- rest (see Renderer:drawBattleWipe).

-- B_TRANSITION_GRID_SQUARES: the screen breaks up into squares rather than
-- being swept.  An ordered (Bayer) threshold is the honest way to write that
-- as a walk -- it scatters without being random, so it looks the same every
-- time, which the cartridge's does too.
local BAYER4 = {
  {  0,  8,  2, 10 },
  { 12,  4, 14,  6 },
  {  3, 11,  1,  9 },
  { 15,  7, 13,  5 },
}

local function gridSquaresOrder(cols, rows)
  local buckets = {}
  for i = 0, 15 do buckets[i] = {} end
  for y = 0, rows - 1 do
    for x = 0, cols - 1 do
      local b = BAYER4[y % 4 + 1][x % 4 + 1]
      buckets[b][#buckets[b] + 1] = { x, y }
    end
  end
  local order = {}
  for i = 0, 15 do
    for _, t in ipairs(buckets[i]) do order[#order + 1] = t end
  end
  return order
end

-- B_TRANSITION_SLICE: every row moves at once, and neighbouring rows move
-- OPPOSITE WAYS -- that counter-shear is the whole look.  Walking one row at
-- a time would read as a set of stripes instead, so the walk is column-major:
-- one tile from every row, then the next, which advances all of them together.
local function sliceOrder(cols, rows)
  local order = {}
  for step = 0, cols - 1 do
    for y = 0, rows - 1 do
      local x = (y % 2 == 0) and step or (cols - 1 - step)
      order[#order + 1] = { x, y }
    end
  end
  return order
end

-- B_TRANSITION_ANGLED_WIPES: a diagonal front crossing the screen.  The band
-- is two tiles of run per tile of drop, which is the slope the cartridge's
-- wipes lean at.
local ANGLE_RUN = 2

local function angledOrder(cols, rows)
  local bands = {}
  local most = cols + rows * ANGLE_RUN
  for i = 0, most do bands[i] = {} end
  for y = 0, rows - 1 do
    for x = 0, cols - 1 do
      local k = x + y * ANGLE_RUN
      bands[k][#bands[k] + 1] = { x, y }
    end
  end
  local order = {}
  for i = 0, most do
    for _, t in ipairs(bands[i] or {}) do order[#order + 1] = t end
  end
  return order
end

-- B_TRANSITION_BIG_POKEBALL: a ball opens out of the middle of the screen.
-- As a walk that is tiles in order of distance from the centre -- a disc
-- growing rather than a sweep going round, which is what tells it apart from
-- `circle` above.
local function pokeballOrder(cols, rows)
  local cx, cy = (cols - 1) / 2, (rows - 1) / 2
  -- the grid is tiles, and a tile is square, so the two axes are already in
  -- the same units; no aspect correction belongs here
  local list = {}
  for y = 0, rows - 1 do
    for x = 0, cols - 1 do
      local dx, dy = x - cx, y - cy
      list[#list + 1] = { x, y, dx * dx + dy * dy }
    end
  end
  table.sort(list, function(a, b)
    if a[3] ~= b[3] then return a[3] < b[3] end
    if a[2] ~= b[2] then return a[2] < b[2] end
    return a[1] < b[1]
  end)
  local order = {}
  for _, t in ipairs(list) do order[#order + 1] = { t[1], t[2] } end
  return order
end

local GRID_BUILDERS = {
  spiralin     = spiralInGrid,
  spiralout    = spiralOutGrid,
  circle       = function(c, r) return sweepOrder(1, c, r) end,
  doublecircle = function(c, r) return sweepOrder(2, c, r) end,
  g3_grid      = gridSquaresOrder,
  g3_slice     = sliceOrder,
  g3_angled    = angledOrder,
  g3_pokeball  = pokeballOrder,
}

-- Tile order for `style` on an arbitrary cols x rows grid, or nil for the
-- styles whose shape is plain geometry (stripes / shrink / split) and which
-- the caller extends with rectangles instead.  Cached per style+size: the
-- window grid only changes on a resize or a zoom step.
local orderFor -- defined below; the authentic 20x18 builders

local gridCache = {}
function BattleTransition.gridOrder(style, cols, rows)
  local build = GRID_BUILDERS[style]
  if not build or cols < 1 or rows < 1 then return nil end
  -- At exactly the Game Boy's grid the ROM's own walk is the answer, overrun
  -- and all -- so an unzoomed window is the classic wipe, not a lookalike.
  --
  -- ...FOR THE STYLES THAT HAVE ONE.  This used to return whatever orderFor
  -- answered, which is nil for any style with no builtin 20x18 walk -- so a
  -- wipe added later (Hoenn's four below) would draw NOTHING at exactly that
  -- grid and be correct at every other size, which is the worst shape a bug
  -- can have.  A style with no classic walk falls through to its builder.
  if cols == COLS and rows == ROWS then
    local classic = orderFor(style, nil)
    if classic then return classic end
  end
  local key = style .. ":" .. cols .. "x" .. rows
  local hit = gridCache[key]
  if hit == nil then
    hit = build(cols, rows) or false
    gridCache[key] = hit
  end
  return hit or nil
end

-- Wipe lengths, taken from pokered-c's battle_transition.c frame budget --
-- derived from battle_transitions.asm and then checked on a live
-- side-by-side against the ROM.  Each wipe is `steps x frames-per-step`:
--
--   DoubleCircle   10 x 3 =  30      SpiralOut  360 fills / 3 per frame = 120
--   Circle         20 x 3 =  60      HStripes    20 x 3 = 60
--   Shrink          9 x 6 =  54      VStripes    18 x 3 = 54
--   Split           9 x 6 =  54      (asm:386-392 and :418-424)
--
-- The port used a flat 40/24 for all eight, which ran every wipe between
-- 1.5x and 3x too fast -- the single biggest reason a battle used to open
-- so much more abruptly here than on hardware.
--
-- The inward spiral is the one that bites.  It writes one tile per
-- iteration and calls BattleTransition_TransferDelay3 every seventh tile
-- (wInwardSpiralUpdateScreenCounter counts 7 down to 0), and that helper is
-- `ld a,1 / ldh [hAutoBGTransferEnabled] / call Delay3 / xor a / ldh [...]`
-- (battle_transitions.asm:619) -- THREE frames, not a one-frame transfer.
-- Reading it as one frame runs the whole spiral 3x too fast; pokered-c
-- caught that against the real ROM.  Deriving the length from the path we
-- actually walk keeps the cadence right if the order ever changes.
local SPIRAL_IN_TILES_PER_STEP = 7
local SPIRAL_IN_STEP_FRAMES = 3 -- TransferDelay3
local SPIRAL_IN_FRAMES = math.ceil(#inwardSpiralOrder()
                                   / SPIRAL_IN_TILES_PER_STEP)
                         * SPIRAL_IN_STEP_FRAMES

-- The eight wipes as records: frames is the wipe length, flash marks the
-- two circle wipes that call BattleTransition_FlashScreen first.  new()
-- reads them, and the transitions registry serves the same table.
-- ---------------------------------------------------------------------------
-- THE TWO THAT ARE NOT THE GAME BOY'S.
--
-- Reported from play: "Gen 1 Battle Transition instead of Gen3s".  Exactly
-- right, and the reason is that there was nothing else to pick: the Gen 3
-- extractor writes no `transitions` table at all, so an Emerald battle fell
-- all the way through styleDef to the eight pokered wipes below, chosen by
-- pokered's own three-bit rule.  Every battle in Hoenn opened with a Game Boy
-- spiral.
--
-- These two are fades, and a fade is the one shape that ports EXACTLY: it is
-- a veil over every pixel the screen shows, which is what Renderer.screenVeil
-- already is -- so they are correct at any window size and any zoom, with no
-- letterbox to escape from. Emerald's showier transitions (the slice, the
-- mosaic, the ripple, the big Poke Ball) are scanline and palette effects and
-- are a feature rather than a fix; they are NOT covered here.
--
-- What this does buy: no Gen 3 battle opens with a Game Boy wipe any more.
local function fadeDraw(shade)
  return function(self, prog)
    local r = self.game and self.game.renderer
    -- out to the shade over the first half, then down to black -- which is
    -- what the screen is holding when the battle draws its first frame
    local a, s
    if prog < 0.5 then a, s = prog / 0.5, shade
    else a, s = 1, shade * (1 - (prog - 0.5) / 0.5) end
    if r then r.screenVeil = { s, a } return end
    love.graphics.setColor(s, s, s, a)
    love.graphics.rectangle("fill", 0, 0, 160, 144)
    love.graphics.setColor(1, 1, 1, 1)
  end
end

-- RECONSTRUCTED LENGTHS.  The Game Boy's eight are derived above -- steps
-- times frames per step, off the routines themselves.  These four cannot be
-- derived the same way: the routines they stand in for count scanlines rather
-- than tiles, so there is no step count to multiply.  They are timed to sit
-- in the same band as the wipes beside them -- about a second -- and they are
-- listed as records so a mod, or a later derivation, can retime them without
-- touching this file.
BattleTransition.STYLES = {
  g3_whitefade = { kind = "fade", frames = 48, draw = fadeDraw(1) },
  g3_blackfade = { kind = "fade", frames = 48, draw = fadeDraw(0) },
  g3_grid      = { kind = "wipe", frames = 48 },
  g3_slice     = { kind = "wipe", frames = 42 },
  g3_angled    = { kind = "wipe", frames = 48 },
  g3_pokeball  = { kind = "wipe", frames = 54, flash = true },
  doublecircle = { kind = "wipe", frames = 30, flash = true },
  spiralin     = { kind = "wipe", frames = SPIRAL_IN_FRAMES },
  circle       = { kind = "wipe", frames = 60, flash = true },
  spiralout    = { kind = "wipe", frames = 120 },
  hstripes     = { kind = "wipe", frames = 60 },
  shrink       = { kind = "wipe", frames = 54 },
  vstripes     = { kind = "wipe", frames = 54 },
  split        = { kind = "wipe", frames = 54 },
}

-- the eight wipes plus Transition's two warp fades: one registrant owns
-- the whole transitions namespace, so Builtins wires it once
function BattleTransition.registerInto(registry, data, owner)
  for id, record in pairs(BattleTransition.STYLES) do
    registry:register(id, record, owner)
  end
  require("src.render.Transition").registerInto(registry, data, owner)
end

-- the merged record; the built-in table is the fallback for headless
-- callers and for any state built before Data:load
local function styleDef(game, style)
  local data = game and game.data
  local record = data and data.transitions and data.transitions[style]
  return record or BattleTransition.STYLES[style]
end

local ORDERS = {} -- cached per style

local BUILTIN_ORDERS = {
  spiralout = outwardSpiralOrder,
  spiralin = inwardSpiralOrder,
  circle = function() return sweepOrder(1) end,
  doublecircle = function() return sweepOrder(2) end,
}

-- A registered style may bring its own tile order (a list of {x, y}, or a
-- function returning one); the four built-in orders are the defaults for
-- the styles that have always had them.
function orderFor(style, def)
  if ORDERS[style] == nil then
    local order = def and def.order
    if type(order) == "function" then
      local ok, built = pcall(order)
      order = ok and built or nil
    end
    if type(order) ~= "table" then
      local build = BUILTIN_ORDERS[style]
      order = build and build() or false
    end
    ORDERS[style] = order or false
  end
  return ORDERS[style] or nil
end

-- the vanilla 3-bit select (battle_transitions.asm), and the default of
-- the transition.style hook a mod wraps to choose its own wipe
local BIT_STYLES = { [0] = "doublecircle", "spiralin", "circle", "spiralout",
                     "hstripes", "shrink", "vstripes", "split" }

-- WHICH GENERATION'S TABLE DECIDES.
--
-- BIT_STYLES is pokered's, and it has no business choosing for Emerald.
-- GetBattleTransitionTypeByMap picks on two things this already has -- whether
-- the encounter is indoors and whether the player's lead outclasses the foe --
-- so the SHAPE of the choice ports even though most of the effects do not:
-- outdoors reads as a bright open transition and a cave as a dark one, which
-- is the distinction the cartridge's table draws.
-- WHICH ONE PLAYS.
--
-- GetBattleTransitionTypeByMap indexes a two-by-two table -- indoors/cave
-- against whether the player's lead outclasses the foe -- and keeps separate
-- tables for a wild encounter and a trainer.  The port has all three of those
-- facts already; what it does NOT have is the table's contents, which are
-- four bytes in the image that nothing here reads.  So the SHAPE of the
-- choice is the cartridge's and the four entries are this file's, chosen to
-- keep the distinction the cartridge draws with them: a trainer gets the
-- showier figure, a cave gets a dark one, and outclassing the foe gets the
-- quicker one.  Said plainly rather than dressed up as derived -- when the
-- table is read, only this function changes.
local function gen3Style(ctx)
  if ctx.trainer then
    if ctx.dungeon then return ctx.stronger and "g3_angled" or "g3_blackfade" end
    return ctx.stronger and "g3_slice" or "g3_pokeball"
  end
  if ctx.dungeon then return ctx.stronger and "g3_grid" or "g3_blackfade" end
  return ctx.stronger and "g3_slice" or "g3_whitefade"
end

local function vanillaStyle(ctx)
  if require("src.core.GameVersion").isGen3() then return gen3Style(ctx) end
  return BIT_STYLES[(ctx.trainer and 1 or 0) + (ctx.stronger and 2 or 0)
                    + (ctx.dungeon and 4 or 0)]
end

-- opts: trainer (bool), stronger (bool), dungeon (bool)
function BattleTransition.new(game, onDone, opts)
  local self = setmetatable({}, BattleTransition)
  self.game = game
  self.onDone = onDone
  self.t = 0
  opts = opts or {}
  local ctx = { trainer = opts.trainer, stronger = opts.stronger,
                dungeon = opts.dungeon, game = game }
  local style = Runtime.call("transition.style", vanillaStyle, ctx)
  local def = styleDef(game, style)
  -- a hook that names an unregistered style falls back to the vanilla bits
  if not def then
    style = vanillaStyle(ctx)
    def = styleDef(game, style)
  end
  self.style = style
  self.def = def
  -- only the circle wipes flash first (battle_transitions.asm:585,628)
  self.phase = def.flash and "flash" or "wipe"
  self.wipeLen = def.frames
  return self
end

function BattleTransition:update(dt)
  self.t = self.t + 1
  if self.phase == "flash" then
    if self.t >= FLASH_CYCLES * #FLASH_STEPS * FLASH_HOLD then
      self.phase = "wipe"
      self.t = 0
    end
  else
    if self.t >= self.wipeLen + BLACK_HOLD then
      self.game.stack:pop()
      if self.onDone then self.onDone() end
    end
  end
end

function BattleTransition:draw()
  if self.phase == "flash" then
    local step = math.floor(self.t / FLASH_HOLD) % #FLASH_STEPS + 1
    local v = FLASH_STEPS[step]
    if v ~= 0 then
      local shade = v > 0 and 0 or 1
      -- The flash is a palette write (rBGP), so on hardware it tints every
      -- pixel the LCD shows.  Hand it to the renderer as a screen-space veil
      -- so it covers the whole surface at any zoom; only the headless and
      -- no-renderer paths fall back to filling the 160x144 box.
      local r = self.game and self.game.renderer
      if r then
        r.screenVeil = { shade, math.abs(v) }
        return
      end
      love.graphics.setColor(shade, shade, shade, math.abs(v))
      love.graphics.rectangle("fill", 0, 0, 160, 144)
      love.graphics.setColor(1, 1, 1, 1)
    end
    return
  end

  local prog = math.min(1, self.t / self.wipeLen)
  local style = self.style

  -- a registered style may draw itself; the eight built-ins do not.  A custom
  -- draw owns the 160x144 UI canvas as it always has.
  if self.def and self.def.draw then
    love.graphics.setColor(0, 0, 0, 1)
    self.def.draw(self, prog)
    love.graphics.setColor(1, 1, 1, 1)
    return
  end

  -- With a renderer the wipe is drawn ONCE over the whole surface in screen
  -- space (Renderer:drawBattleWipe), on a tile grid anchored to the letterbox
  -- and extended outward at the same tile size.  That makes it a single
  -- continuous figure: the spiral starts at the outermost edge of the window
  -- and works inward, instead of one spiral inside the letterbox running
  -- alongside a second one outside it.  Nothing is stretched -- the pattern is
  -- continued with more tiles, not scaled-up pixels -- so at 1x the grid works
  -- out to exactly 20x18 and this is the classic wipe unchanged.
  local renderer = self.game and self.game.renderer
  if renderer then
    renderer.battleWipe = { style = style, prog = prog }
    return
  end

  -- headless / no renderer: the classic 160x144 path
  love.graphics.setColor(0, 0, 0, 1)

  local order = orderFor(style, self.def)
  if order then
    -- tile-order wipes: spiral / circle sweeps
    local n = math.floor(#order * prog)
    for i = 1, n do
      local c = order[i]
      love.graphics.rectangle("fill", c[1] * TILE, c[2] * TILE, TILE, TILE)
    end
  elseif style == "hstripes" then
    -- interlaced rows wipe from alternating sides
    local w = math.floor(160 * prog)
    for row = 0, ROWS - 1 do
      local y = row * TILE
      if row % 2 == 0 then
        love.graphics.rectangle("fill", 0, y, w, TILE)
      else
        love.graphics.rectangle("fill", 160 - w, y, w, TILE)
      end
    end
  elseif style == "vstripes" then
    -- interlaced columns wipe from alternating ends
    local h = math.floor(144 * prog)
    for col = 0, COLS - 1 do
      local x = col * TILE
      if col % 2 == 0 then
        love.graphics.rectangle("fill", x, 0, TILE, h)
      else
        love.graphics.rectangle("fill", x, 144 - h, TILE, h)
      end
    end
  elseif style == "shrink" then
    -- the image squashes toward the middle: the asm shifts rows and
    -- columns inward in the same loop, so bars close from all four
    -- edges at once
    local h = math.floor(72 * prog)
    local w = math.floor(80 * prog)
    love.graphics.rectangle("fill", 0, 0, 160, h)
    love.graphics.rectangle("fill", 0, 144 - h, 160, h)
    love.graphics.rectangle("fill", 0, 0, w, 144)
    love.graphics.rectangle("fill", 160 - w, 0, w, 144)
  else -- split: the quarters tear apart from the middle; the asm shifts
    -- rows and columns outward each loop, so a black cross grows from
    -- the center in both axes at once
    local h = math.floor(72 * prog)
    local w = math.floor(80 * prog)
    love.graphics.rectangle("fill", 0, 72 - h, 160, h * 2)
    love.graphics.rectangle("fill", 80 - w, 0, w * 2, 144)
  end

  if prog >= 1 then
    love.graphics.rectangle("fill", 0, 0, 160, 144)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return BattleTransition
