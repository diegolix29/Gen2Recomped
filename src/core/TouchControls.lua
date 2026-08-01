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
-- fractions.  The launcher editor (src/ui/TouchControlsEditor.lua) writes
-- those; applyOptions reads them at boot and whenever options change.
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

-- neutral zone at a d-pad/stick center, as a fraction of its width;
-- inside it no direction is held (keeps a resting thumb from jittering)
local DPAD_DEAD = 0.16

-- how far the stick art drifts toward the held direction, as a fraction
-- of the stick's width -- purely cosmetic, the input itself is 4-way
-- digital like the d-pad, not a continuous drag
local STICK_DRIFT = 0.28

-- hit slop: how far past the visible edge a press still counts, as a
-- multiplier on the control's half-width.  START/SELECT get more because
-- the glyphs are small.
local SLOP = { a = 1.3, b = 1.3, start = 1.4, select = 1.4 }
-- same idea for the shoulder/trigger/hotkey row: small targets, generous
-- slop so a thumb near the top edge of the screen still lands cleanly
local HOTKEY_SLOP = 1.35

local BUTTONS = { "a", "b", "start", "select" }
local CONTROLS = { "dpad", "a", "b", "start", "select" }

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

local function wantsOverlay()
  local env = os.getenv("POKEPORT_TOUCH")
  if env == "1" then return true end
  if env == "0" then return false end
  local osName = love.system and love.system.getOS and love.system.getOS()
  return osName == "Android" or osName == "iOS"
end

-- Normalize a persisted touchControls table into {enabled, positions}.
-- Unknown / garbage keys are dropped so a bad options.lua cannot brick
-- the overlay.
function TouchControls.normalizeConfig(tc)
  local out = { enabled = true, positions = nil }
  if type(tc) ~= "table" then return out end
  if tc.enabled == false then out.enabled = false end
  if type(tc.positions) == "table" then
    local pos = {}
    for _, name in ipairs(CONTROLS) do
      local p = tc.positions[name]
      if type(p) == "table" and type(p.x) == "number" and type(p.y) == "number" then
        pos[name] = { x = clamp01(p.x), y = clamp01(p.y) }
      end
    end
    if next(pos) then out.positions = pos end
  end
  return out
end

-- Pure default layout in LOVE units for a usable rect of size ww x wh at
-- origin (ox, oy).  Shared by layout() and the editor's Reset path so
-- defaults stay in one place.  ox/oy default to 0 for the headless tests
-- and for callers that already pass a full-window size.
function TouchControls.defaultLayout(ww, wh, ox, oy)
  ox, oy = ox or 0, oy or 0
  local short = math.min(ww, wh)
  local dpadW = math.min(180, short * 0.34)
  local abW = dpadW * 0.46
  local ssW = dpadW * 0.30
  local margin = dpadW * 0.12
  return {
    dpad = { cx = ox + margin + dpadW / 2, cy = oy + wh - margin - dpadW / 2, w = dpadW },
    a = { cx = ox + ww - margin - abW * 0.55, cy = oy + wh - margin - abW * 1.75, w = abW },
    b = { cx = ox + ww - margin - abW * 1.60, cy = oy + wh - margin - abW * 0.55, w = abW },
    start = { cx = ox + ww / 2 + ssW * 0.60, cy = oy + wh - margin - ssW * 0.95, w = ssW },
    select = { cx = ox + ww / 2 - ssW * 0.60, cy = oy + wh - margin - ssW * 0.95, w = ssW },
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

function TouchControls:init()
  self.active = wantsOverlay()
  self.enabled = true
  self.positions = nil
  self.preview = false
  self.controllerHidden = false
  self.touches = {}
  -- per-GB-button owner count: two fingers on A must not double-press it,
  -- and lifting one of them must not release the other's hold
  self.held = {}
  -- per-hotkey-button pressed-visual flag; these aren't held GB state,
  -- just "is a finger currently on this button" for the art
  self.tapped = {}
  self.dpadTouch = nil
  self.leftStickTouch = nil
  self.rightStickTouch = nil
  self.layoutW, self.layoutH = nil, nil
  self.img = nil
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
  -- Edit mode for customizing button positions
  self.editMode = false
  self.editingButton = nil
  self.editOffset = { x = 0, y = 0 }
  if not self.active then return end
  -- soft-fail: a missing/corrupt PNG must never block boot; the overlay
  -- stays off and keyboard/controller play still works. Every name in
  -- IMAGES must resolve, so the four new button sets ship together --
  -- add all ten new PNGs (hotkey1-4, l1, r1, l2, r2, leftstick,
  -- rightstick) to assets/touch or the whole overlay disables itself.
  local img = {}
  for name, path in pairs(IMAGES) do
    local ok, im = pcall(love.graphics.newImage, path)
    if not ok then
      img = nil
      break
    end
    -- smooth UI icons; the global default filter is nearest for GB pixels
    im:setFilter("linear", "linear")
    img[name] = im
  end
  self.img = img
end

-- Apply options.touchControls.  Called from Game:applyOptions and from
-- the launcher editor after a save.
function TouchControls:applyOptions(opts)
  local cfg = TouchControls.normalizeConfig(opts and opts.touchControls)
  self.enabled = cfg.enabled
  self.positions = cfg.positions
  self.layoutW, self.layoutH = nil, nil
  self.layoutOx, self.layoutOy = nil, nil
  if not self.enabled then
    self.controllerHidden = false
    self:reset()
  end
end

function TouchControls:config()
  return {
    enabled = self.enabled ~= false,
    positions = self.positions,
  }
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

-- Toggle edit mode for customizing button positions
function TouchControls:toggleEditMode()
  self.editMode = not self.editMode
  if not self.editMode then
    self.editingButton = nil
  end
  return self.editMode
end

-- Check if edit mode is active
function TouchControls:isEditMode()
  return self.editMode
end

-- Layout in LOVE units (density-independent on mobile), recomputed when
-- the window size changes (rotation, resize).  D-pad bottom-left, B/A
-- bottom-right with A above B (the Game Boy diagonal), START/SELECT
-- flanking the bottom center, L2/L1 and R2/R1 stacked in the top
-- corners, H1-H4 centered along the top edge, and the two sticks resting
-- mid-height on either side, clear of both rows.
function TouchControls:layout()
  local ww, wh = love.graphics.getDimensions()
  if self.layoutW == ww and self.layoutH == wh then return self.L end
  self.layoutW, self.layoutH = ww, wh
  local short = math.min(ww, wh)
  -- ~a third of the short edge, capped so tablets don't get a dinner plate
  local dpadW = math.min(180, short * 0.34)
  local abW = dpadW * 0.46
  local ssW = dpadW * 0.30
  local margin = dpadW * 0.12
  local shoulderW = math.min(56, short * 0.16)
  local hotkeyW = math.min(40, short * 0.10)
  local stickW = math.min(150, short * 0.32)
  local topMargin = margin + shoulderW * 0.18
  local hGap = hotkeyW * 1.25
  local hCenterX = ww / 2
  
  -- Default layout
  local defaultLayout = {
    dpad = { cx = margin + dpadW / 2, cy = wh - margin - dpadW / 2, w = dpadW },
    a = { cx = ww - margin - abW * 0.55, cy = wh - margin - abW * 1.75, w = abW },
    b = { cx = ww - margin - abW * 1.60, cy = wh - margin - abW * 0.55, w = abW },
    start = { cx = ww / 2 + ssW * 0.60, cy = wh - margin - ssW * 0.95, w = ssW },
    select = { cx = ww / 2 - ssW * 0.60, cy = wh - margin - ssW * 0.95, w = ssW },
    l2 = { cx = margin + shoulderW / 2, cy = topMargin + shoulderW / 2, w = shoulderW },
    l1 = { cx = margin + shoulderW / 2, cy = topMargin + shoulderW * 1.75, w = shoulderW },
    r2 = { cx = ww - margin - shoulderW / 2, cy = topMargin + shoulderW / 2, w = shoulderW },
    r1 = { cx = ww - margin - shoulderW / 2, cy = topMargin + shoulderW * 1.75, w = shoulderW },
    h1 = { cx = hCenterX - hGap * 1.5, cy = topMargin + hotkeyW / 2, w = hotkeyW },
    h2 = { cx = hCenterX - hGap * 0.5, cy = topMargin + hotkeyW / 2, w = hotkeyW },
    h3 = { cx = hCenterX + hGap * 0.5, cy = topMargin + hotkeyW / 2, w = hotkeyW },
    h4 = { cx = hCenterX + hGap * 1.5, cy = topMargin + hotkeyW / 2, w = hotkeyW },
    leftstick = { cx = margin + stickW / 2, cy = wh * 0.42, w = stickW },
    rightstick = { cx = ww - margin - stickW / 2, cy = wh * 0.42, w = stickW },
  }
  
  -- Apply custom positions from save if they exist
  local customPositions = self.game and self.game.save and self.game.save.options and 
                          self.game.save.options.touchButtonPositions or {}
  
  self.L = {}
  for buttonName, defaultPos in pairs(defaultLayout) do
    if customPositions[buttonName] then
      -- Use custom position but keep default width if not specified
      local custom = customPositions[buttonName]
      self.L[buttonName] = {
        cx = custom.cx or defaultPos.cx,
        cy = custom.cy or defaultPos.cy,
        w = custom.w or defaultPos.w
      }
    else
      self.L[buttonName] = defaultPos
    end
  end
  
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
  self.positions = self.positions or {}
  self.positions[name] = {
    x = sw > 0 and (zone.cx - ox) / sw or 0,
    y = sh > 0 and (zone.cy - oy) / sh or 0,
  }
end

function TouchControls:clearPositions()
  self.positions = nil
  self.layoutW, self.layoutH = nil, nil
  self.layoutOx, self.layoutOy = nil, nil
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
  if n == 1 then Input:overlayPressed(btn) end
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

-- the d-pad/left-stick touch's held direction changed (or ended): swap
-- the GB hold. Shared by the d-pad and the left stick -- they're two
-- thumb positions for the same four directions, tracked as independent
-- touches so one lifting doesn't drop the other's hold.
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
      -- Check if this is left stick and camera mode is enabled
      local isLeftStick = touch.control == "leftstick"
      local cameraEnabled = isLeftStick and leftStickCameraEnabled(self)
      
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
        -- Normal movement mode
        pressBtn(self, dir)
        touch.pressedAsMovement = true
      end
    end
  else
    touch.pressedAsMovement = nil
  end
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
  if self.controllerHidden then
    self.controllerHidden = false
    return
  end
  local L = self:layout()
  
  -- Edit mode: check if touching a button to start dragging
  if self.editMode then
    -- Check if Done button was pressed
    if self.doneButton and x >= self.doneButton.x and x <= self.doneButton.x + self.doneButton.w and
       y >= self.doneButton.y and y <= self.doneButton.y + self.doneButton.h then
      self:toggleEditMode()
      return
    end
    
    for buttonName, zone in pairs(L) do
      if inCircle(zone, x, y, 1.5) then -- More generous hit area for editing
        self.editingButton = buttonName
        self.editOffset = { x = x - zone.cx, y = y - zone.cy }
        self.touches[id] = { control = buttonName, isEdit = true }
        return
      end
    end
    return -- In edit mode, only allow button dragging
  end
  
  for _, btn in ipairs(BUTTONS) do
    if inCircle(L[btn], x, y, SLOP[btn]) then
      self.touches[id] = { control = btn }
      pressBtn(self, btn)
      return
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
    setDpad(self, touch, dpadDir(lz, x, y))
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
  
  -- Edit mode: drag the button being edited
  if touch.isEdit and self.editingButton then
    local L = self:layout()
    local zone = L[self.editingButton]
    if zone then
      zone.cx = x - self.editOffset.x
      zone.cy = y - self.editOffset.y
    end
    return
  end
  
  -- the d-pad and left stick both track movement (slide between
  -- directions without lifting); buttons hold until release wherever the
  -- finger wanders, and the right stick has its own hotkey-vs-movement
  -- branch
  if touch.control == "dpad" or touch.control == "leftstick" then
    setDpad(self, touch, dpadDir(self:layout()[touch.control], x, y))
  elseif touch.control == "rightstick" then
    setRightStickDir(self, touch, dpadDir(self:layout().rightstick, x, y))
  end
end

function TouchControls:touchreleased(id, x, y)
  if self.preview then return end
  local touch = self.touches[id]
  if not touch then return end
  self.touches[id] = nil
  
  -- Edit mode: save the new position
  if touch.isEdit and self.editingButton then
    local L = self:layout()
    local zone = L[self.editingButton]
    if zone and self.game and self.game.save and self.game.save.options then
      if not self.game.save.options.touchButtonPositions then
        self.game.save.options.touchButtonPositions = {}
      end
      self.game.save.options.touchButtonPositions[self.editingButton] = {
        cx = zone.cx,
        cy = zone.cy,
        w = zone.w
      }
      -- Save the options
      local SaveData = require("src.core.SaveData")
      SaveData.saveOptions(self.game.save.options)
    end
    self.editingButton = nil
    return
  end
  
  if touch.control == "dpad" then
    setDpad(self, touch, nil)
    self.dpadTouch = nil
  elseif touch.control == "leftstick" then
    setDpad(self, touch, nil)
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
  if not self.active or not self.controllerHidden then return end
  self.controllerHidden = false
end

-- Mouse support for desktop testing
function TouchControls:mousepressed(x, y, button)
  if button == 1 then -- Left click only
    self:touchpressed("mouse", x, y)
  end
end

function TouchControls:mousemoved(x, y, dx, dy)
  self:touchmoved("mouse", x, y)
end

function TouchControls:mousereleased(x, y, button)
  if button == 1 then
    self:touchreleased("mouse", x, y)
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

  -- Edit mode visual feedback
  if self.editMode then
    love.graphics.setColor(1, 0.5, 0, 0.3) -- Orange tint for edit mode
    love.graphics.rectangle("fill", 0, 0, love.graphics.getDimensions())
    
    -- Draw edit mode indicator
    love.graphics.setFont(self.labelFont)
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.print("EDIT MODE - Drag buttons to reposition", 20, 20)
    
    -- Draw Done button in top right corner
    local ww, wh = love.graphics.getDimensions()
    local doneButton = { x = ww - 120, y = 10, w = 100, h = 40 }
    love.graphics.setColor(0.2, 0.8, 0.2, 0.8) -- Green
    love.graphics.rectangle("fill", doneButton.x, doneButton.y, doneButton.w, doneButton.h, 8)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf("DONE", doneButton.x, doneButton.y + 12, doneButton.w, "center")
    
    -- Store done button bounds for touch handling
    self.doneButton = doneButton
  end

  local dpadTouch = self.dpadTouch and self.touches[self.dpadTouch]
  local dir = dpadTouch and dpadTouch.dir
  drawIcon(dir and self.img["dpad_" .. dir] or self.img.dpad, L.dpad,
           dir ~= nil, alphaMul)
  for _, btn in ipairs(BUTTONS) do
    local isEditing = self.editMode and self.editingButton == btn
    drawIcon(self.img[btn], L[btn], self.held[btn] ~= nil or isEditing)
    if isEditing then
      -- Highlight the button being edited
      love.graphics.setColor(1, 1, 0, 0.5)
      love.graphics.circle("line", L[btn].cx, L[btn].cy, L[btn].w * 0.6)
    end
  end
  for _, name in ipairs(HOTKEY_ORDER) do
    local isEditing = self.editMode and self.editingButton == name
    drawIcon(self.img[name], L[name], self.tapped[name] or isEditing)
    if isEditing then
      -- Highlight the button being edited
      love.graphics.setColor(1, 1, 0, 0.5)
      love.graphics.circle("line", L[name].cx, L[name].cy, L[name].w * 0.6)
    end
  end

  local leftTouch = self.leftStickTouch and self.touches[self.leftStickTouch]
  local isEditingLeft = self.editMode and self.editingButton == "leftstick"
  drawStick(self.img.leftstick, L.leftstick, leftTouch and leftTouch.dir)
  if isEditingLeft then
    love.graphics.setColor(1, 1, 0, 0.5)
    love.graphics.circle("line", L.leftstick.cx, L.leftstick.cy, L.leftstick.w * 0.5)
  end
  
  local rightTouch = self.rightStickTouch and self.touches[self.rightStickTouch]
  local isEditingRight = self.editMode and self.editingButton == "rightstick"
  drawStick(self.img.rightstick, L.rightstick, rightTouch and rightTouch.dir)
  if isEditingRight then
    love.graphics.setColor(1, 1, 0, 0.5)
    love.graphics.circle("line", L.rightstick.cx, L.rightstick.cy, L.rightstick.w * 0.5)
  end

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

return TouchControls
