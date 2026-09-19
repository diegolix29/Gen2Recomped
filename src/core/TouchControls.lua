-- On-screen touch controls: a visible d-pad, A, B, START, SELECT, L1/R1/
-- L2/R2, H1-H4 hotkey buttons, and dual analog sticks, drawn over the
-- finished frame (art: Xelu's CC0 controller prompts, see
-- assets/touch/README.md).  Replaces the old touch gesture recognizer:
-- every control is a real button under the thumb, so there is no
-- tap-vs-swipe classification, no deferred-A double-tap window, and no
-- added latency.
--
-- Mobile only, and only while no controller is being used: the overlay
-- shows on Android/iOS, disappears the moment a gamepad button or stick
-- is used, and comes back on the next screen touch (Game routes both
-- events here).  POKEPORT_TOUCH=1 forces it on for desktop testing
-- (main.lua then drives it with the mouse); POKEPORT_TOUCH=0 forces it
-- off everywhere.
--
-- Player preferences (options.touchControls) can permanently disable the
-- overlay and/or override per-control positions as normalized window
-- fractions.  Positions and a size multiplier are stored per orientation
-- (#633): options.touchControls.layouts.portrait / .landscape, picked from
-- the safe rect's aspect, so laying the pad out in landscape never moves
-- the portrait one.  The launcher editor (src/ui/TouchControlsEditor.lua)
-- writes those; applyOptions reads them at boot and whenever options
-- change.
--
-- Controls press GB buttons through Input:overlayPressed/Released -- their
-- own input source, not a keyboard alias -- so a held overlay direction
-- merges cleanly with a keyboard key or stick holding the same button,
-- and a player rebind can never detach the overlay.
--
-- L1/R1/L2/R2 and H1-H4 are not Game Boy buttons: like a physical pad's
-- shoulders/triggers, they only do anything once a "display hotkey"
-- action (COLORS/TILT/ZOOM/... or a mod's) is bound to them in
-- HotkeyBindingsMenu (src/ui/HotkeyBindingsMenu.lua), and they fire that
-- action once per tap through the exact same Input:hotkeyForPad lookup
-- Game:gamepadpressed uses -- so a binding made on a real controller's
-- L1 fires from the touch L1 too, for free. HotkeyBindingsMenu also lets
-- a player tap one of these buttons *during* a "PRESS A BUTTON" capture
-- to bind it in the first place (see TouchControls.captureTarget below);
-- H1-H4 have no physical-pad equivalent, so that touch capture is the
-- only way to ever bind them.
--
-- The left stick presses the same GB directions as the d-pad (an
-- alternate thumb position, not a distinct input). The right stick
-- mirrors Input:gamepadaxis's real-stick behavior: it presses GB
-- directions when "right stick moves the player" is on in Options, and
-- otherwise fires a bound rightstick<dir> hotkey instead, edge-triggered
-- exactly like a real right stick crossing the deadzone.

local Input = require("src.core.Input")
local SafeArea = require("src.core.SafeArea")

local TouchControls = {}

-- idle vs pressed overlay opacity
local ALPHA = 0.65
local ALPHA_PRESSED = 0.95
-- translucent backing disc behind each control: the prompt art is dark
-- gray, so without it the controls melt into dark map areas
local BACK = 0.24
local BACK_PRESSED = 0.38

-- neutral zone at the d-pad center, as a fraction of the d-pad width;
-- inside it no direction is held (keeps a resting thumb from jittering)
local DPAD_DEAD = 0.16

-- how far the stick art nudges off-center when held in a direction
local STICK_DRIFT = 0.15

-- hit slop: how far past the visible edge a press still counts, as a
-- multiplier on the control's half-width.  START/SELECT get more because
-- the glyphs are small.
local SLOP = { a = 1.3, b = 1.3, start = 1.4, select = 1.4 }
-- same idea for the shoulder/trigger/hotkey row: small targets, generous
-- slop so a thumb near the top edge of the screen still lands cleanly
local HOTKEY_SLOP = 1.35

local BUTTONS = { "a", "b", "start", "select" }
local CONTROLS = { "dpad", "a", "b", "start", "select", "l1", "l2", "r1", "r2", "h1", "h2", "h3", "h4", "leftstick", "rightstick" }

-- touch-zone name -> Input:hotkeyForPad name. L1/R1/L2/R2 reuse the exact
-- names a real controller reports (see src/core/Input.lua's
-- DEFAULT_HOTKEY_PAD_BINDINGS and HotkeyBindingsMenu's padLabel), so
-- their bindings are shared with a physical pad automatically. H1-H4 are
-- synthetic names that only ever exist as touch buttons.
local HOTKEY_BUTTONS = {
  h1 = "h1", h2 = "h2", h3 = "h3", h4 = "h4",
  l1 = "leftshoulder", r1 = "rightshoulder",
  l2 = "lefttrigger", r2 = "righttrigger",
}
local HOTKEY_ORDER = { "l2", "l1", "h1", "h2", "h3", "h4", "r1", "r2" }

local DIR_VEC = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }

-- Per-orientation layout buckets (#633).  Orientation comes from the safe
-- rect, not the device: sw > sh is landscape, so a resized desktop window
-- under POKEPORT_TOUCH exercises the same path a phone rotation does.
local ORIENTATIONS = { "portrait", "landscape" }

-- Control size multiplier bounds for the editor's -/+ (#633).  1.0 is the
-- historical size, so an install that never touches it draws as before.
local SCALE_MIN, SCALE_MAX, SCALE_STEP = 0.6, 1.6, 0.1

local IMAGES = {
  dpad = "assets/touch/dpad.png",
  dpad_up = "assets/touch/dpad_up.png",
  dpad_down = "assets/touch/dpad_down.png",
  dpad_left = "assets/touch/dpad_left.png",
  dpad_right = "assets/touch/dpad_right.png",
  a = "assets/touch/a.png",
  b = "assets/touch/b.png",
  start = "assets/touch/start.png",
  select = "assets/touch/select.png",
  h1 = "assets/touch/hotkey1.png",
  h2 = "assets/touch/hotkey2.png",
  h3 = "assets/touch/hotkey3.png",
  h4 = "assets/touch/hotkey4.png",
  l1 = "assets/touch/l1.png",
  r1 = "assets/touch/r1.png",
  l2 = "assets/touch/l2.png",
  r2 = "assets/touch/r2.png",
  leftstick = "assets/touch/leftstick.png",
  rightstick = "assets/touch/rightstick.png",
}

local function clamp01(v)
  if v < 0 then return 0 end
  if v > 1 then return 1 end
  return v
end

local function clampScale(v)
  if type(v) ~= "number" or v ~= v then return 1 end
  if v < SCALE_MIN then return SCALE_MIN end
  if v > SCALE_MAX then return SCALE_MAX end
  return v
end

-- Haptic feedback (#806): a short vibration the instant a control takes a GB
-- button, the way every mobile emulator front-end does it -- the pad has no
-- edges under a thumb, so the buzz is the only confirmation a press landed.
-- Persisted as options.haptics (src/core/SaveData.lua defaultOptions), NOT
-- under options.touchControls: TouchControls:config() is the launcher
-- editor's save snapshot and only emits enabled + layouts, so a nested key
-- would be dropped on every editor save.
-- love.system.vibrate takes a duration and nothing else, so "intensity" is a
-- duration preset: Android runs the platform vibrator for exactly that long,
-- while iOS ignores the duration and fires the fixed system vibration, so
-- there the three levels all read as simply on.
TouchControls.HAPTICS = { "off", "light", "medium", "heavy" }
TouchControls.HAPTIC_DEFAULT = "light"

local HAPTIC_SECONDS = { off = 0, light = 0.012, medium = 0.025, heavy = 0.045 }
local HAPTIC_LABELS = {
  off = "OFF", light = "LIGHT", medium = "MEDIUM", heavy = "HEAVY",
}

function TouchControls.normalizeHaptics(level)
  if HAPTIC_SECONDS[level] then return level end
  return TouchControls.HAPTIC_DEFAULT
end

function TouchControls.hapticLabel(level)
  return HAPTIC_LABELS[TouchControls.normalizeHaptics(level)]
end

function TouchControls.cycleHaptics(level, dir)
  local cur, idx = TouchControls.normalizeHaptics(level), 1
  for i, m in ipairs(TouchControls.HAPTICS) do
    if m == cur then idx = i break end
  end
  local n = #TouchControls.HAPTICS
  return TouchControls.HAPTICS[(idx - 1 + (dir or 1)) % n + 1]
end

-- One pulse at the given level.  Feature-guarded rather than platform-gated:
-- love.system.vibrate is a no-op on desktop and absent from the headless love
-- stubs, so the press path below stays identical everywhere and the tests
-- never reach a vibrator.
function TouchControls.buzz(level)
  local secs = HAPTIC_SECONDS[TouchControls.normalizeHaptics(level)]
  if not secs or secs <= 0 then return false end
  if not (love and love.system and love.system.vibrate) then return false end
  pcall(love.system.vibrate, secs)
  return true
end

-- Copy a persisted positions table, dropping unknown / non-numeric entries.
-- Always a fresh table: two orientations seeded from the same pre-#633
-- layout must not alias, or dragging one would still move the other.
local function normalizePositions(src)
  if type(src) ~= "table" then return nil end
  local pos = {}
  for _, name in ipairs(CONTROLS) do
    local p = src[name]
    if type(p) == "table" and type(p.x) == "number" and type(p.y) == "number" then
      pos[name] = { x = clamp01(p.x), y = clamp01(p.y) }
    end
  end
  if not next(pos) then return nil end
  return pos
end

local function orientationFor(sw, sh)
  return (sw or 0) > (sh or 0) and "landscape" or "portrait"
end

local function wantsOverlay()
  local env = os.getenv("POKEPORT_TOUCH")
  if env == "1" then return true end
  if env == "0" then return false end
  local osName = love.system and love.system.getOS and love.system.getOS()
  return osName == "Android" or osName == "iOS"
end

-- Normalize a persisted touchControls table into
-- {enabled, layouts = {portrait = {positions, scale}, landscape = {...}}}.
-- Unknown / garbage keys are dropped so a bad options.lua cannot brick
-- the overlay.  Pre-#633 files stored one top-level positions table and no
-- scale; that layout seeds both orientations, so an upgrading player keeps
-- what they had until they edit one of them.
function TouchControls.normalizeConfig(tc)
  local out = { enabled = true, layouts = { portrait = {}, landscape = {} } }
  -- a nil / garbage table still yields full buckets (scale defaulted), so
  -- no caller ever has to nil-check a bucket's scale
  if type(tc) ~= "table" then tc = {} end
  if tc.enabled == false then out.enabled = false end
  local saved = type(tc.layouts) == "table" and tc.layouts or nil
  for _, o in ipairs(ORIENTATIONS) do
    local b = saved and saved[o]
    if type(b) ~= "table" then b = { positions = tc.positions, scale = tc.scale } end
    out.layouts[o] = {
      positions = normalizePositions(b.positions),
      scale = clampScale(b.scale),
    }
  end
  return out
end

-- Pure default layout in LOVE units for a usable rect of size ww x wh at
-- origin (ox, oy).  Shared by layout() and the editor's Reset path so
-- defaults stay in one place.  ox/oy default to 0 for the headless tests
-- and for callers that already pass a full-window size.  scale (#633) is
-- the orientation's size multiplier: every width and the margin derive
-- from dpadW, so scaling it moves the default centers with the art
-- instead of letting bigger buttons hang off the edge.
function TouchControls.defaultLayout(ww, wh, ox, oy, scale)
  ox, oy = ox or 0, oy or 0
  local short = math.min(ww, wh)
  local dpadW = math.min(180, short * 0.34) * clampScale(scale)
  local abW = dpadW * 0.46
  local ssW = dpadW * 0.30
  local margin = dpadW * 0.12
  local shoulderW = math.min(56, short * 0.16)
  local hotkeyW = math.min(40, short * 0.10)
  local stickW = math.min(150, short * 0.32)
  local topMargin = margin + shoulderW * 0.18
  local hGap = hotkeyW * 1.25
  local hCenterX = ww / 2
  
  return {
    dpad = { cx = ox + margin + dpadW / 2, cy = oy + wh - margin - dpadW / 2, w = dpadW },
    a = { cx = ox + ww - margin - abW * 0.55, cy = oy + wh - margin - abW * 1.75, w = abW },
    b = { cx = ox + ww - margin - abW * 1.60, cy = oy + wh - margin - abW * 0.55, w = abW },
    start = { cx = ox + ww / 2 + ssW * 0.60, cy = oy + wh - margin - ssW * 0.95, w = ssW },
    select = { cx = ox + ww / 2 - ssW * 0.60, cy = oy + wh - margin - ssW * 0.95, w = ssW },
    l2 = { cx = ox + margin + shoulderW / 2, cy = oy + topMargin + shoulderW / 2, w = shoulderW },
    l1 = { cx = ox + margin + shoulderW / 2, cy = oy + topMargin + shoulderW * 1.75, w = shoulderW },
    r2 = { cx = ox + ww - margin - shoulderW / 2, cy = oy + topMargin + shoulderW / 2, w = shoulderW },
    r1 = { cx = ox + ww - margin - shoulderW / 2, cy = oy + topMargin + shoulderW * 1.75, w = shoulderW },
    h1 = { cx = ox + hCenterX - hGap * 1.5, cy = oy + topMargin + hotkeyW / 2, w = hotkeyW },
    h2 = { cx = ox + hCenterX - hGap * 0.5, cy = oy + topMargin + hotkeyW / 2, w = hotkeyW },
    h3 = { cx = ox + hCenterX + hGap * 0.5, cy = oy + topMargin + hotkeyW / 2, w = hotkeyW },
    h4 = { cx = ox + hCenterX + hGap * 1.5, cy = oy + topMargin + hotkeyW / 2, w = hotkeyW },
    leftstick = { cx = ox + margin + stickW / 2, cy = oy + wh * 0.42, w = stickW },
    rightstick = { cx = ox + ww - margin - stickW / 2, cy = oy + wh * 0.42, w = stickW },
  }
end

local function loadImages()
  local img = {}
  for name, path in pairs(IMAGES) do
    local ok, im = pcall(love.graphics.newImage, path)
    if not ok then return nil end
    im:setFilter("linear", "linear")
    img[name] = im
  end
  return img
end

function TouchControls:init(game)
  self.game = game
  self.active = wantsOverlay()
  self.enabled = true
  -- per-orientation buckets (#633); self.positions / self.scale mirror the
  -- one currently on screen so layout(), the editor and the tests keep a
  -- single lookup
  self.layouts = { portrait = {}, landscape = {} }
  self.orientation = nil
  self.positions = nil
  self.scale = 1
  self.preview = false
  self.controllerHidden = false
  self.touches = {}
  -- per-GB-button owner count: two fingers on A must not double-press it,
  -- and lifting one of them must not release the other's hold
  self.held = {}
  self.tapped = {}
  self.dpadTouch = nil
  self.leftStickTouch = nil
  self.rightStickTouch = nil
  self.layoutW, self.layoutH = nil, nil
  self.img = nil
  -- vibration level for presses (#806); applyOptions overwrites it from
  -- options.haptics, this is the value a harness that never applies options
  -- runs with
  self.haptics = TouchControls.HAPTIC_DEFAULT
  -- Images load whenever the platform wants the overlay OR the launcher
  -- editor forces a preview (desktop testing of the editor).
  if self.active then
    self.img = loadImages()
  end
end

-- Ensure art is loaded for the launcher editor even when wantsOverlay()
-- is false (desktop without POKEPORT_TOUCH).
function TouchControls:ensureImages()
  if self.img then return true end
  self.img = loadImages()
  return self.img ~= nil
end

-- Apply options.touchControls.  Called from Game:applyOptions and from
-- the launcher editor after a save.
function TouchControls:applyOptions(opts)
  local cfg = TouchControls.normalizeConfig(opts and opts.touchControls)
  self.enabled = cfg.enabled
  self.layouts = cfg.layouts
  self.layoutW, self.layoutH = nil, nil
  self.layoutOx, self.layoutOy = nil, nil
  -- prime positions/scale for the orientation on screen so callers that
  -- read them before the next layout() (editor chrome, tests) see the file
  self:currentBucket()
  if not self.enabled then
    self.controllerHidden = false
    self:reset()
  end
end

-- Snapshot for the editor's save path: enabled plus both orientation
-- buckets, matching what options.lua stores (#633).
function TouchControls:config()
  local out = { enabled = self.enabled ~= false, layouts = {} }
  for _, o in ipairs(ORIENTATIONS) do
    local b = self.layouts and self.layouts[o] or nil
    out.layouts[o] = {
      positions = b and b.positions or nil,
      scale = clampScale(b and b.scale),
    }
  end
  return out
end

-- Preview mode: force-draw the overlay for the layout editor, ignoring
-- platform / enabled / gamepad gates.  Gameplay input still respects
-- enabled via touchpressed.
function TouchControls:setPreview(on)
  self.preview = on and true or false
  if on then
    self:ensureImages()
    self.controllerHidden = false
  end
end

function TouchControls:visible()
  if self.preview then return self.img ~= nil end
  return self.active and self.enabled ~= false and self.img ~= nil
     and not self.controllerHidden
end

-- Keep a control fully inside the usable rect [x0,y0]..[x1,y1].
local function clampZone(zone, x0, y0, x1, y1)
  local half = zone.w * 0.5
  zone.cx = math.max(x0 + half, math.min(x1 - half, zone.cx))
  zone.cy = math.max(y0 + half, math.min(y1 - half, zone.cy))
end

-- The bucket for the orientation currently on screen (#633), created on
-- demand.  Mirrors it into self.orientation / self.positions / self.scale,
-- which layout(), the editor chrome and the tests read.
function TouchControls:currentBucket()
  local _, _, sw, sh = SafeArea.rect()
  local o = orientationFor(sw, sh)
  self.layouts = self.layouts or { portrait = {}, landscape = {} }
  local b = self.layouts[o]
  if type(b) ~= "table" then
    b = {}
    self.layouts[o] = b
  end
  b.scale = clampScale(b.scale)
  self.orientation = o
  self.positions = b.positions
  self.scale = b.scale
  return b
end

-- Layout in LOVE units (density-independent on mobile), recomputed when
-- the window or safe area changes (rotation, resize, notch insets).
-- Default: d-pad bottom-left, B/A bottom-right with A above B (the Game Boy
-- diagonal), START/SELECT flanking the bottom center -- all inside the
-- device safe area so thumbs clear the home indicator / cutouts.
-- Custom positions (normalized 0..1 within the safe rect) override centers
-- while sizes stay derived from the short edge, times the orientation's
-- size setting (#633).
function TouchControls:layout()
  local ox, oy, sw, sh = SafeArea.rect()
  if self.layoutW == sw and self.layoutH == sh
     and self.layoutOx == ox and self.layoutOy == oy and self.L then
    return self.L
  end
  self.layoutW, self.layoutH = sw, sh
  self.layoutOx, self.layoutOy = ox, oy
  -- orientation picks which saved layout applies; rotating swaps buckets
  -- because sw/sh swapped, which is already the cache key above (#633)
  local bucket = self:currentBucket()
  self.L = TouchControls.defaultLayout(sw, sh, ox, oy, bucket.scale)
  if bucket.positions then
    for _, name in ipairs(CONTROLS) do
      local p = bucket.positions[name]
      local zone = self.L[name]
      if p and zone then
        zone.cx = ox + p.x * sw
        zone.cy = oy + p.y * sh
        clampZone(zone, ox, oy, ox + sw, oy + sh)
      end
    end
  end
  local ssW = self.L.start.w
  local fontSize = math.max(8, math.floor(ssW * 0.26))
  if not self.labelFont or self.fontSize ~= fontSize then
    self.fontSize = fontSize
    self.labelFont = love.graphics.newFont(fontSize)
  end
  return self.L
end

-- Move one control to a screen-space point and persist its normalized
-- position within the safe rect.  Used by the layout editor while dragging.
function TouchControls:setControlCenter(name, cx, cy)
  local ox, oy, sw, sh = SafeArea.rect()
  local L = self:layout()
  local zone = L[name]
  if not zone then return end
  zone.cx, zone.cy = cx, cy
  clampZone(zone, ox, oy, ox + sw, oy + sh)
  -- writes land in the orientation on screen only (#633)
  local bucket = self:currentBucket()
  bucket.positions = bucket.positions or {}
  self.positions = bucket.positions
  bucket.positions[name] = {
    x = sw > 0 and (zone.cx - ox) / sw or 0,
    y = sh > 0 and (zone.cy - oy) / sh or 0,
  }
end

-- Editor Reset: defaults for the orientation on screen only (#633), so
-- resetting landscape never throws away the portrait layout.
function TouchControls:clearPositions()
  local bucket = self:currentBucket()
  bucket.positions = nil
  bucket.scale = 1
  self.positions = nil
  self.scale = 1
  self.layoutW, self.layoutH = nil, nil
  self.layoutOx, self.layoutOy = nil, nil
end

-- Control size multiplier for the orientation on screen (#633).  Widths and
-- the default centers both derive from it in defaultLayout; custom centers
-- keep their normalized spot and re-clamp inside the safe rect on the next
-- layout().
function TouchControls:setScale(scale)
  local bucket = self:currentBucket()
  bucket.scale = clampScale(scale)
  self.scale = bucket.scale
  self.layoutW, self.layoutH = nil, nil
  self.layoutOx, self.layoutOy = nil, nil
  return self.scale
end

function TouchControls:nudgeScale(delta)
  return self:setScale((self.scale or 1) + delta)
end

local function inCircle(zone, x, y, slop)
  local r = zone.w * 0.5 * slop
  local dx, dy = x - zone.cx, y - zone.cy
  return dx * dx + dy * dy <= r * r
end

-- Which control (if any) contains (x, y).  Prefer face buttons over the
-- d-pad when they overlap, matching touchpressed's order.
function TouchControls:hitTest(x, y)
  local L = self:layout()
  for _, btn in ipairs(BUTTONS) do
    if inCircle(L[btn], x, y, SLOP[btn]) then return btn end
  end
  local dz = L.dpad
  local half = dz.w * 0.65
  if math.abs(x - dz.cx) <= half and math.abs(y - dz.cy) <= half then
    return "dpad"
  end
  -- Check hotkey buttons, shoulder buttons, and sticks
  for _, name in ipairs({"l1", "l2", "r1", "r2", "h1", "h2", "h3", "h4", "leftstick", "rightstick"}) do
    if L[name] and inCircle(L[name], x, y, HOTKEY_SLOP) then return name end
  end
  return nil
end

local function dpadDir(zone, x, y)
  local dx, dy = x - zone.cx, y - zone.cy
  local dead = zone.w * DPAD_DEAD
  if math.abs(dx) < dead and math.abs(dy) < dead then return nil end
  if math.abs(dx) >= math.abs(dy) then
    return dx > 0 and "right" or "left"
  end
  return dy > 0 and "down" or "up"
end

local function pressBtn(self, btn)
  local n = (self.held[btn] or 0) + 1
  self.held[btn] = n
  -- Buzz only on the 0 -> 1 edge, the same edge that presses the GB button:
  -- a second finger landing on a button that is already held, and a d-pad
  -- finger resting inside one direction, must not retrigger it.  Sliding the
  -- d-pad to a new direction does, which is the point (#806).
  if n == 1 then
    Input:overlayPressed(btn)
    TouchControls.buzz(self.haptics)
  end
end

local function releaseBtn(self, btn)
  local n = self.held[btn]
  if not n then return end
  if n > 1 then
    self.held[btn] = n - 1
  else
    self.held[btn] = nil
    Input:overlayReleased(btn)
  end
end

-- Helper functions for stick mode checking (must be defined before setDpad)
local function rightStickMovementEnabled(self)
  local g = self.game
  return (g and g.save and g.save.options and g.save.options.rightStickMovement) or false
end

local function leftStickCameraEnabled(self)
  local g = self.game
  return (g and g.save and g.save.options and g.save.options.leftStickCamera) or false
end

-- looks up a bound "display hotkey" action for a touch shoulder/trigger/
-- H1-H4 button and fires it exactly once, the same path a physical pad
-- button takes through Game:gamepadpressed -> Input:hotkeyForPad ->
-- Game:fireHotkey. A no-op until the player binds something to it.
local function fireHotkeyPad(self, padName)
  local g = self.game
  if not g or not g.fireHotkey then return end
  local hotkey = Input:hotkeyForPad(padName)
  if hotkey then g:fireHotkey(hotkey) end
end

-- the d-pad's held direction changed (or ended): swap the GB hold.
local function setDpad(self, touch, dir)
  if touch.dir == dir then return end
  if touch.dir then 
    -- Release previous direction
    if touch.pressedAsMovement then
      releaseBtn(self, touch.dir)
    end
  end
  touch.dir = dir
  if dir then
    -- Check if in capture mode for binding
    if self.captureTarget then
      local padName = "dpad" .. dir
      self.captureTarget:capturePad(padName)
      touch.pressedAsMovement = false
    else
      -- Check if a hotkey is bound to this direction
      local padName = "dpad" .. dir
      local hotkey = Input:hotkeyForPad(padName)
      local g = self.game
      
      if hotkey and g and g.fireHotkey then
        -- Fire the bound hotkey once (edge-triggered)
        g:fireHotkey(hotkey)
        touch.pressedAsMovement = false
      else
        -- No hotkey bound: normal movement mode
        pressBtn(self, dir)
        touch.pressedAsMovement = true
      end
    end
  else
    touch.pressedAsMovement = nil
  end
end

-- the left stick's held direction changed (or ended): swap the GB hold.
-- Similar to d-pad but with camera mode support.
local function setLeftStick(self, touch, dir)
  if touch.dir == dir then return end
  if touch.dir then 
    -- Release previous direction
    if touch.pressedAsMovement then
      releaseBtn(self, touch.dir)
    end
  end
  touch.dir = dir
  if dir then
    -- Check if in capture mode for binding
    if self.captureTarget then
      local padName = "stick" .. dir
      self.captureTarget:capturePad(padName)
      touch.pressedAsMovement = false
    else
      -- Check if camera mode is enabled
      local cameraEnabled = leftStickCameraEnabled(self)
      
      if cameraEnabled then
        -- In camera mode, left stick left/right controls camera rotation
        touch.pressedAsMovement = false
        if dir == "left" then
          local g = self.game
          if g and g.fireHotkey then g:fireHotkey("cameraRotateLeft") end
        elseif dir == "right" then
          local g = self.game
          if g and g.fireHotkey then g:fireHotkey("cameraRotateRight") end
        else
          -- Up/down still control movement
          pressBtn(self, dir)
          touch.pressedAsMovement = true
        end
      else
        -- Check if a hotkey is bound to this direction
        local padName = "stick" .. dir
        local hotkey = Input:hotkeyForPad(padName)
        local g = self.game
        
        if hotkey and g and g.fireHotkey then
          -- Fire the bound hotkey once (edge-triggered)
          g:fireHotkey(hotkey)
          touch.pressedAsMovement = false
        else
          -- No hotkey bound: normal movement mode
          pressBtn(self, dir)
          touch.pressedAsMovement = true
        end
      end
    end
  else
    touch.pressedAsMovement = nil
  end
end

-- Right stick direction changed (or ended). Mirrors Input:gamepadaxis's
-- real-stick branch: presses GB directions when right-stick movement is
-- on, otherwise fires a bound rightstick<dir> hotkey once per direction
-- change. Whether a release also needs to let go of a GB button is
-- decided by how the press itself was made (touch.pressedAsMovement),
-- not by re-reading the option -- so flipping the option mid-drag can't
-- strand a held direction.
local function setRightStickDir(self, touch, dir)
  if touch.dir == dir then return end
  if touch.dir and touch.pressedAsMovement then
    releaseBtn(self, touch.dir)
  end
  touch.dir = dir
  if dir then
    -- Check if in capture mode for binding
    if self.captureTarget then
      self.captureTarget:capturePad("rightstick" .. dir)
      touch.pressedAsMovement = false
    else
      local enabled = rightStickMovementEnabled(self)
      touch.pressedAsMovement = enabled
      if enabled then
        pressBtn(self, dir)
      else
        fireHotkeyPad(self, "rightstick" .. dir)
      end
    end
  else
    touch.pressedAsMovement = nil
  end
end

function TouchControls:touchpressed(id, x, y)
  -- preview mode is layout-edit only: never press GB buttons
  if self.preview then return end
  if not (self.active and self.enabled ~= false and self.img) then return end
  -- a controller hid the overlay; the first touch only brings it back
  -- (uncaptured: it began on no control, so mods may still see it)
  if self.controllerHidden then
    self.controllerHidden = false
    return
  end
  local L = self:layout()
  
  for _, btn in ipairs(BUTTONS) do
    if inCircle(L[btn], x, y, SLOP[btn]) then
      self.touches[id] = { control = btn }
      pressBtn(self, btn)
      return true
    end
  end
  for _, name in ipairs(HOTKEY_ORDER) do
    if inCircle(L[name], x, y, HOTKEY_SLOP) then
      self.touches[id] = { control = name }
      self.tapped[name] = true
      -- HotkeyBindingsMenu arms this while its "PRESS A BUTTON" capture
      -- is open, so a mobile player with no controller can still bind
      -- these buttons instead of only firing whatever's already bound
      if self.captureTarget then
        self.captureTarget:capturePad(HOTKEY_BUTTONS[name])
      else
        fireHotkeyPad(self, HOTKEY_BUTTONS[name])
      end
      return
    end
  end
  -- square hit zone a bit past the cross art; one owning finger at a time
  local dz = L.dpad
  local half = dz.w * 0.65
  if not self.dpadTouch
     and math.abs(x - dz.cx) <= half and math.abs(y - dz.cy) <= half then
    self.dpadTouch = id
    local touch = { control = "dpad", dir = nil }
    self.touches[id] = touch
    setDpad(self, touch, dpadDir(dz, x, y))
    return
  end
  local lz = L.leftstick
  local lHalf = lz.w * 0.65
  if not self.leftStickTouch
     and math.abs(x - lz.cx) <= lHalf and math.abs(y - lz.cy) <= lHalf then
    self.leftStickTouch = id
    local touch = { control = "leftstick", dir = nil }
    self.touches[id] = touch
    setLeftStick(self, touch, dpadDir(lz, x, y))
    return
  end
  local rz = L.rightstick
  local rHalf = rz.w * 0.65
  if not self.rightStickTouch
     and math.abs(x - rz.cx) <= rHalf and math.abs(y - rz.cy) <= rHalf then
    self.rightStickTouch = id
    local touch = { control = "rightstick", dir = nil }
    self.touches[id] = touch
    setRightStickDir(self, touch, dpadDir(rz, x, y))
    return
  end
end

function TouchControls:touchmoved(id, x, y)
  if self.preview then return end
  local touch = self.touches[id]
  if not touch then return end
  
  -- the d-pad and left stick both track movement (slide between
  -- directions without lifting); buttons hold until release wherever the
  -- finger wanders, and the right stick has its own hotkey-vs-movement
  -- branch
  if touch.control == "dpad" then
    setDpad(self, touch, dpadDir(self:layout()[touch.control], x, y))
  elseif touch.control == "leftstick" then
    setLeftStick(self, touch, dpadDir(self:layout()[touch.control], x, y))
  elseif touch.control == "rightstick" then
    setRightStickDir(self, touch, dpadDir(self:layout().rightstick, x, y))
  end
end

function TouchControls:touchreleased(id, x, y)
  if self.preview then return end
  local touch = self.touches[id]
  if not touch then return end
  self.touches[id] = nil
  
  if touch.control == "dpad" then
    setDpad(self, touch, nil)
    self.dpadTouch = nil
  elseif touch.control == "leftstick" then
    setLeftStick(self, touch, nil)
    self.leftStickTouch = nil
  elseif touch.control == "rightstick" then
    setRightStickDir(self, touch, nil)
    self.rightStickTouch = nil
  elseif HOTKEY_BUTTONS[touch.control] then
    self.tapped[touch.control] = nil
  else
    releaseBtn(self, touch.control)
  end
end

-- LÖVE has no touchcancelled: a touch interrupted by the OS (app
-- backgrounded, a system gesture stealing the finger) never fires
-- touchreleased and would strand its button held forever.  Called from
-- Game alongside Input:reset() on focus/visibility loss.
function TouchControls:reset()
  for btn in pairs(self.held or {}) do
    Input:overlayReleased(btn)
  end
  self.held = {}
  self.tapped = {}
  self.touches = {}
  self.dpadTouch = nil
  self.leftStickTouch = nil
  self.rightStickTouch = nil
end

-- a gamepad is being used: hide the overlay (dropping anything it held)
-- until the next screen touch asks for it back.  No-op when the player
-- permanently disabled the overlay -- there is nothing to hide, and a
-- later accidental touch must not resurrect it.
function TouchControls:noteGamepad()
  if not self.active or self.enabled == false or self.controllerHidden then
    return
  end
  self.controllerHidden = true
  self:reset()
end

-- last controller unplugged: show the overlay again immediately instead
-- of requiring a blind first tap
function TouchControls:joystickremoved()
  self:reset()
  if love.joystick and love.joystick.getJoystickCount
     and love.joystick.getJoystickCount() == 0 then
    self.controllerHidden = false
  end
end

local function drawIcon(img, zone, pressed, alphaMul)
  alphaMul = alphaMul or 1
  love.graphics.setColor(1, 1, 1, (pressed and BACK_PRESSED or BACK) * alphaMul)
  love.graphics.circle("fill", zone.cx, zone.cy, zone.w * 0.58)
  local scale = zone.w / img:getWidth()
  love.graphics.setColor(1, 1, 1, (pressed and ALPHA_PRESSED or ALPHA) * alphaMul)
  love.graphics.draw(img, zone.cx - zone.w / 2,
                     zone.cy - img:getHeight() * scale / 2, 0, scale, scale)
end

-- the stick art itself doesn't have per-direction frames like the d-pad
-- does, so held direction is shown by nudging it off-center instead
local function drawStick(img, zone, dir)
  love.graphics.setColor(1, 1, 1, dir and BACK_PRESSED or BACK)
  love.graphics.circle("fill", zone.cx, zone.cy, zone.w * 0.5)
  local ox, oy = 0, 0
  if dir and DIR_VEC[dir] then
    local v = DIR_VEC[dir]
    ox, oy = v[1] * zone.w * STICK_DRIFT, v[2] * zone.w * STICK_DRIFT
  end
  local scale = zone.w * 0.62 / img:getWidth()
  love.graphics.setColor(1, 1, 1, dir and ALPHA_PRESSED or ALPHA)
  love.graphics.draw(img, zone.cx + ox - img:getWidth() * scale / 2,
                     zone.cy + oy - img:getHeight() * scale / 2, 0, scale, scale)
end

-- Screen-space, called by Game:draw after Renderer:endFrame so the
-- overlay rides on top of everything (world, UI, CRT/GBC FX included).
-- Also used by the launcher layout editor under preview mode.
function TouchControls:draw()
  if not self:visible() then return end
  local L = self:layout()
  -- when the player disabled the overlay but the editor is previewing,
  -- draw dimmed so the layout is still editable
  local alphaMul = (self.preview and self.enabled == false) and 0.45 or 1
  love.graphics.push("all")
  love.graphics.origin()

  local dpadTouch = self.dpadTouch and self.touches[self.dpadTouch]
  local dir = dpadTouch and dpadTouch.dir
  drawIcon(dir and self.img["dpad_" .. dir] or self.img.dpad, L.dpad,
           dir ~= nil, alphaMul)
  for _, btn in ipairs(BUTTONS) do
    drawIcon(self.img[btn], L[btn], self.held[btn] ~= nil, alphaMul)
  end
  for _, name in ipairs(HOTKEY_ORDER) do
    drawIcon(self.img[name], L[name], self.tapped[name], alphaMul)
  end

  local leftTouch = self.leftStickTouch and self.touches[self.leftStickTouch]
  drawStick(self.img.leftstick, L.leftstick, leftTouch and leftTouch.dir)
  
  local rightTouch = self.rightStickTouch and self.touches[self.rightStickTouch]
  drawStick(self.img.rightstick, L.rightstick, rightTouch and rightTouch.dir)

  -- the +/- glyphs alone don't say which is which; shadowed so the text
  -- reads on both the black letterbox and battle's white one.  Each label
  -- tracks its own control's cy/w so dragging START cannot move SELECT.
  love.graphics.setFont(self.labelFont)
  local function label(text, zone)
    local ly = zone.cy + zone.w * 0.66
    local w = self.labelFont:getWidth(text)
    love.graphics.setColor(0, 0, 0, 0.6 * alphaMul)
    love.graphics.print(text, zone.cx - w / 2 + 1, ly + 1)
    love.graphics.setColor(1, 1, 1, (ALPHA + 0.2) * alphaMul)
    love.graphics.print(text, zone.cx - w / 2, ly)
  end
  label("START", L.start)
  label("SELECT", L.select)

  love.graphics.pop()
end

TouchControls.CONTROLS = CONTROLS
TouchControls.ORIENTATIONS = ORIENTATIONS
TouchControls.SCALE_MIN, TouchControls.SCALE_MAX = SCALE_MIN, SCALE_MAX
TouchControls.SCALE_STEP = SCALE_STEP

return TouchControls
