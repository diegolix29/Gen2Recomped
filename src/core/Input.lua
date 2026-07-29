-- Input abstraction: maps keyboard to Game Boy buttons.
-- `down` = held this frame; `pressed` = edge, consumed per fixed step.

local Input = {}

local DEFAULT_BINDINGS = {
  up = "up", w = "up",
  down = "down", s = "down",
  left = "left", a = "left",
  right = "right", d = "right",
  z = "a", ["return"] = "a", space = "a",
  x = "b", backspace = "b",
  ["kpenter"] = "start", escape = "start",
  -- Select: fight-menu move reorder + bag item reorder. Tab is the
  -- discoverable default (shown in CONTROLS); both shifts stay as
  -- aliases so Right-Shift muscle memory from older builds still works.
  tab = "select",
  rshift = "select",
  lshift = "select",
}

-- keys that map to "start" but also to "a" would conflict; keep Enter = a,
-- Escape = start for desktop friendliness.

-- LÖVE's standard gamepad mapping (SDL game controller DB), consistent
-- across Xbox/PlayStation/generic controllers on desktop and mobile. Some
-- third-party pads report their own SDL mapping for a given physical
-- button (e.g. Select/Back/View on off-brand XInput pads), which is what
-- src/ui/BindingsMenu.lua's rebinding is for -- see applyBindings below.
local DEFAULT_GAMEPAD_BINDINGS = {
  dpup = "up", dpdown = "down", dpleft = "left", dpright = "right",
  a = "a", b = "b",
  start = "start", back = "select",
}

-- left-stick deadzones: press past STICK_ON, release once back under
-- STICK_OFF. The gap (hysteresis) stops the direction from flickering
-- while the stick sits near the threshold.
local STICK_ON = 0.5
local STICK_OFF = 0.3

-- trigger threshold: press past TRIGGER_ON, release once back under
-- TRIGGER_OFF. Same hysteresis pattern as the stick.
local TRIGGER_ON = 0.5
local TRIGGER_OFF = 0.3

-- Display "hotkeys" (COLORS/TILT/ZOOM/GBC FX + zoom step) are one-shot
-- actions fired straight from Game:keypressed/gamepadpressed -- they are
-- not Game Boy buttons, so they get their own binding table instead of
-- sharing keyBindings/padBindings above. That keeps a hotkey rebind from
-- ever colliding with (or being overwritten by) a d-pad/A/B/Start/Select
-- rebind, and vice versa. See Game:fireHotkey and src/ui/HotkeyBindingsMenu.lua.
local DEFAULT_HOTKEY_KEY_BINDINGS = {
  ["2"] = "colors",
  ["3"] = "tilt",
  ["4"] = "fastForward",
  ["5"] = "gbcfx",
  ["-"] = "zoomOut",
  ["="] = "zoomIn",
  ["9"] = "quit",
  ["0"] = "softReset",
  ["f1"] = "saveGame",
  ["f2"] = "loadGame",
  ["f10"] = "toggleModMenu",
  -- vortex hotkey for mods (e.g., Dramatic Shape voxel mode)
  ["6"] = "vortex",
  -- camera rotation
  ["["] = "cameraRotateLeft",
  ["]"] = "cameraRotateRight",
  -- mod reload
  ["f5"] = "reloadMods",
}

-- No default pad buttons: every physical button LÖVE exposes on a
-- standard gamepad is either already claimed by a Game Boy button above
-- or left free, and guessing a mapping risks colliding with a shoulder
-- button some pad already uses for something else. A player opts in
-- through HotkeyBindingsMenu's "PRESS A BUTTON" capture instead.
-- Directional stick movements and triggers are available for binding.
local DEFAULT_HOTKEY_PAD_BINDINGS = {
  ["stickup"] = nil,
  ["stickdown"] = nil,
  ["stickleft"] = nil,
  ["stickright"] = nil,
  ["rightstickup"] = nil,
  ["rightstickdown"] = nil,
  ["rightstickleft"] = nil,
  ["rightstickright"] = nil,
  ["lefttrigger"] = nil,
  ["righttrigger"] = nil,
}

function Input:init()
  self:applyBindings(nil)
  self:applyHotkeyBindings(nil)
  self:reset()
end

-- Layers a player's rebind choices (save.options.bindings, written by
-- src/ui/BindingsMenu.lua) on top of the defaults above. A rebind adds an
-- extra way to trigger that action instead of replacing the default key,
-- so e.g. Z/Enter/Space all still press A even after binding a 4th key to
-- it. Call whenever options load or change (see Game:applyOptions and
-- BindingsMenu:storeBinding) -- without this the menu records a choice
-- that never actually reaches gameplay.
function Input:applyBindings(overlay)
  local keys, pads = {}, {}
  for key, action in pairs(DEFAULT_BINDINGS) do keys[key] = action end
  for button, action in pairs(DEFAULT_GAMEPAD_BINDINGS) do pads[button] = action end
  for actionId, binding in pairs(overlay or {}) do
    if type(binding) == "table" then
      if binding.key then keys[binding.key] = actionId end
      if binding.pad then pads[binding.pad] = actionId end
    elseif type(binding) == "string" then
      keys[binding] = actionId
    end
  end
  self.keyBindings = keys
  self.padBindings = pads
end

-- Same layering as applyBindings above, but for the hotkey action table
-- (save.options.hotkeyBindings, written by src/ui/HotkeyBindingsMenu.lua).
-- A rebind here adds an extra trigger for that action rather than
-- replacing the default, exactly like applyBindings.
function Input:applyHotkeyBindings(overlay)
  local keys, pads = {}, {}
  for key, action in pairs(DEFAULT_HOTKEY_KEY_BINDINGS) do keys[key] = action end
  for button, action in pairs(DEFAULT_HOTKEY_PAD_BINDINGS) do pads[button] = action end
  for actionId, binding in pairs(overlay or {}) do
    if type(binding) == "table" then
      if binding.key then keys[binding.key] = actionId end
      if binding.pad then pads[binding.pad] = actionId end
    elseif type(binding) == "string" then
      keys[binding] = actionId
    end
  end
  self.hotkeyKeyBindings = keys
  self.hotkeyPadBindings = pads
end

-- Returns the hotkey action id (e.g. "tilt") bound to a keyboard key or
-- gamepad button, or nil. These are looked up straight from
-- Game:keypressed/gamepadpressed -- they never touch state/pressQueue,
-- since a hotkey fires once and has no held/isDown concept.
function Input:hotkeyForKey(key)
  return self.hotkeyKeyBindings and self.hotkeyKeyBindings[key]
end

function Input:hotkeyForPad(button)
  return self.hotkeyPadBindings and self.hotkeyPadBindings[button]
end

-- Purely event-driven state (press sets true, release sets false) has no
-- fallback if a release event never arrives -- focus loss, a minimized
-- window, or a disconnected gamepad can all swallow the key-up/button-up
-- that would have cleared a held direction. Called from Game on those
-- transitions so a stuck flag can't outlive them.
function Input:reset()
  self.state = {}
  self.pressQueue = {}
  self.pressed = {}
  self.sources = {}
  self.stickAxis = { x = 0, y = 0 }
  self.stickDir = nil
  self.rightStickAxis = { x = 0, y = 0 }
  self.rightStickDir = nil
  self.triggerAxis = { left = 0, right = 0 }
  self.triggerPressed = { left = false, right = false }
  self.pendingStickHotkey = nil
  self.pendingRightStickHotkey = nil
  self.pendingTriggerHotkey = nil
end

-- Multiple physical sources (W + Up, d-pad + stick, etc.) can claim the
-- same GB button. Track them individually so releasing one doesn't clear
-- a hold another source still owns, and so a press+release that both land
-- before the next FixedStep can't be revived when step() drains the queue.
local function press(self, btn, source)
  local sources = self.sources[btn]
  if not sources then
    sources = {}
    self.sources[btn] = sources
  end
  if not sources[source] then
    sources[source] = true
    table.insert(self.pressQueue, btn)
  end
  self.state[btn] = true
end

local function release(self, btn, source)
  local sources = self.sources[btn]
  if sources then
    sources[source] = nil
    if next(sources) == nil then
      -- Leave an empty table (not nil) so step() can tell a real
      -- source was released before the queue drained, versus a
      -- synthetic pressQueue inject that never had sources at all.
      self.state[btn] = false
    end
  else
    self.state[btn] = false
  end
end

function Input:keypressed(key)
  local btn = self.keyBindings[key]
  if btn then
    press(self, btn, "key:" .. key)
  end
end

function Input:keyreleased(key)
  local btn = self.keyBindings[key]
  if btn then
    release(self, btn, "key:" .. key)
  end
end

-- Called once per fixed step: promote queued presses to this step's edges.
-- Hold state is owned by live sources (updated in press/release), not
-- re-asserted here -- otherwise a same-frame press→release leaves the
-- button stuck on after the queue drains.
-- Synthetic injects (tests/drivers writing pressQueue directly, with no
-- source entry) still set state so scripted holds keep working.
function Input:step()
  self.pressed = {}
  for _, btn in ipairs(self.pressQueue) do
    self.pressed[btn] = true
    local sources = self.sources[btn]
    if sources == nil then
      -- synthetic pressQueue inject (tests/drivers): no live source map
      self.state[btn] = true
    elseif next(sources) ~= nil then
      self.state[btn] = true
    end
    -- sources == {}: real press fully released before this step -- keep up
  end
  for btn, sources in pairs(self.sources) do
    if next(sources) == nil then
      self.sources[btn] = nil
    end
  end
  self.pressQueue = {}
end

-- The on-screen touch overlay (src/core/TouchControls.lua) presses GB
-- buttons directly by name -- not through a keyboard alias -- so a player
-- rebind can never detach or shadow the overlay.
function Input:overlayPressed(btn)
  press(self, btn, "touch:" .. btn)
end

function Input:overlayReleased(btn)
  release(self, btn, "touch:" .. btn)
end

function Input:gamepadpressed(joystick, button)
  local btn = self.padBindings[button]
  if btn then
    press(self, btn, "pad:" .. button)
  end
end

function Input:gamepadreleased(joystick, button)
  local btn = self.padBindings[button]
  if btn then
    release(self, btn, "pad:" .. button)
  end
end

-- left stick treated as a continuous held direction, same 4-way rule as
-- the touch swipe d-pad: whichever axis has the larger magnitude wins.
function Input:gamepadaxis(joystick, axis, value)
  if axis == "leftx" then
    self.stickAxis.x = value
  elseif axis == "lefty" then
    self.stickAxis.y = value
  elseif axis == "rightx" then
    self.rightStickAxis.x = value
  elseif axis == "righty" then
    self.rightStickAxis.y = value
  elseif axis == "triggerleft" then
    self:handleTrigger("left", value)
  elseif axis == "triggerright" then
    self:handleTrigger("right", value)
  else
    return
  end

  if axis == "leftx" or axis == "lefty" then
    local x, y = self.stickAxis.x, self.stickAxis.y
    local ax, ay = math.abs(x), math.abs(y)
    local newDir = self.stickDir
    if ax > STICK_ON or ay > STICK_ON then
      if ax >= ay then
        newDir = x > 0 and "right" or "left"
      else
        newDir = y > 0 and "down" or "up"
      end
    elseif ax < STICK_OFF and ay < STICK_OFF then
      newDir = nil
    end

    if newDir ~= self.stickDir then
      if self.stickDir then
        release(self, self.stickDir, "stick")
      end
      if newDir then
        press(self, newDir, "stick")
        -- Fire hotkey for stick direction
        local stickButton = "stick" .. newDir
        local hotkey = self:hotkeyForPad(stickButton)
        if hotkey then
          self.pendingStickHotkey = hotkey
        end
      end
      self.stickDir = newDir
    end
  elseif axis == "rightx" or axis == "righty" then
    local x, y = self.rightStickAxis.x, self.rightStickAxis.y
    local ax, ay = math.abs(x), math.abs(y)
    local newDir = self.rightStickDir
    
    -- Check if right stick movement is enabled in options
    local rightStickMovementEnabled = false
    local ok, Game = pcall(require, "src.core.Game")
    if ok and Game and Game.save and Game.save.options then
      rightStickMovementEnabled = Game.save.options.rightStickMovement or false
    end
    
    if ax > STICK_ON or ay > STICK_ON then
      if ax >= ay then
        newDir = x > 0 and "right" or "left"
      else
        newDir = y > 0 and "down" or "up"
      end
    elseif ax < STICK_OFF and ay < STICK_OFF then
      newDir = nil
    end

    if newDir ~= self.rightStickDir then
      if self.rightStickDir then
        release(self, self.rightStickDir, "rightstick")
      end
      if newDir then
        -- When movement is enabled: press for game movement only (no hotkeys)
        if rightStickMovementEnabled then
          press(self, newDir, "rightstick")
        else
          -- When movement is disabled: fire hotkey only (no movement)
          local stickButton = "rightstick" .. newDir
          local hotkey = self:hotkeyForPad(stickButton)
          if hotkey then
            self.pendingRightStickHotkey = hotkey
          end
        end
      end
      self.rightStickDir = newDir
    end
  end
end

-- Handle analog triggers (ZL/ZR) with threshold detection
function Input:handleTrigger(side, value)
  local buttonName = side == "left" and "lefttrigger" or "righttrigger"
  self.triggerAxis[side] = value
  
  local wasPressed = self.triggerPressed[side]
  local isPressed = value > TRIGGER_ON
  
  if isPressed and not wasPressed then
    -- Trigger just crossed threshold - fire hotkey if bound
    local hotkey = self:hotkeyForPad(buttonName)
    if hotkey then
      -- Store for Game to fire in gamepadpressed
      self.pendingTriggerHotkey = hotkey
    end
  end
  
  self.triggerPressed[side] = isPressed
end

-- Check for pending trigger hotkey to fire
function Input:consumeTriggerHotkey()
  local hotkey = self.pendingTriggerHotkey
  self.pendingTriggerHotkey = nil
  return hotkey
end

-- Check for pending stick hotkey to fire
function Input:consumeStickHotkey()
  local hotkey = self.pendingStickHotkey
  self.pendingStickHotkey = nil
  return hotkey
end

-- Check for pending right stick hotkey to fire
function Input:consumeRightStickHotkey()
  local hotkey = self.pendingRightStickHotkey
  self.pendingRightStickHotkey = nil
  return hotkey
end

function Input:isDown(btn)
  return self.state[btn] or false
end

function Input:wasPressed(btn)
  return self.pressed[btn] or false
end

return Input
