-- Overworld tilt mode: a cycleable, purely presentational perspective
-- tilt for the free-roam overworld.  The flat world canvas is treated as
-- a ground plane, rotated about the horizontal axis through the viewport
-- centre and viewed through a perspective camera, so rows above centre
-- recede/shrink and rows below come closer (the HD-2D "diorama" look).
-- Like survey zoom this lives entirely in the draw path -- zero effect
-- on collision, movement, triggers, scripts -- and is persisted via
-- save.options.tilt (OFF / 15 / 35 / 50).
--
-- Spec: docs/new-features.md (tilt mode)

local Zoom = require("src.render.Zoom")
local love = love

local Tilt = {}

-- Sky image for tilt mode (nil = black sky)
Tilt.skyImage = nil
Tilt.skyImagePath = nil
-- Store options for sky enabled check
Tilt.options = nil
-- Sky rotation tracking (in radians)
Tilt.skyRotation = 0
Tilt.skyTargetRotation = 0
Tilt.skyBounceOffset = 0

-- Discrete tilt angles in degrees (index 0 is off).  Cycle: off→15→35→50→off.
Tilt.ANGLES_DEG = { 0, 15, 35, 50 }
Tilt.ANGLE_LABELS = { "OFF", "15", "35", "50" }

-- Runtime state.  `level` is the discrete option (0=off .. 3=50°);
-- `angle` is the live tweened tilt in radians; `from`/`goal`/`t` drive
-- the ease between any two levels (including off).
Tilt.level = 0
Tilt.angle = 0
Tilt.from = 0
Tilt.goal = 0
Tilt.t = 1
-- Compatibility: TARGET_ANGLE is the current goal; enabled mirrors level > 0.
Tilt.TARGET_ANGLE = 0
Tilt.enabled = false

Tilt.TWEEN_TIME = 0.25
Tilt.FOCAL = 1.0
Tilt.VIEW_MARGIN = 0.35

local function ease(t)
  return t * t * (3 - 2 * t)
end

local function goalFor(level)
  return math.rad(Tilt.ANGLES_DEG[level + 1] or 0)
end

function Tilt.setLevel(level)
  level = math.floor(tonumber(level) or 0)
  if level < 0 then level = 0 end
  if level > 3 then level = 3 end
  local goal = goalFor(level)
  if goal ~= Tilt.goal or level ~= Tilt.level then
    Tilt.from = Tilt.angle
    Tilt.goal = goal
    Tilt.t = 0
  end
  Tilt.level = level
  Tilt.TARGET_ANGLE = goal
  Tilt.enabled = level > 0
end

-- Advance OFF → 15 → 35 → 50 → OFF.  Returns the new level.
function Tilt.cycle()
  Tilt.setLevel((Tilt.level + 1) % 4)
  return Tilt.level
end

-- Legacy name: one cycle step (same as cycle).
function Tilt.toggle()
  return Tilt.cycle()
end

function Tilt.reset()
  Tilt.level = 0
  Tilt.angle = 0
  Tilt.from = 0
  Tilt.goal = 0
  Tilt.t = 1
  Tilt.TARGET_ANGLE = 0
  Tilt.enabled = false
end

function Tilt.applyOptions(opts)
  local level = math.floor(tonumber(opts and opts.tilt) or 0)
  if level < 0 then level = 0 end
  if level > 3 then level = 3 end
  Tilt.level = level
  Tilt.goal = goalFor(level)
  Tilt.from = Tilt.goal
  Tilt.angle = Tilt.goal
  Tilt.t = 1
  Tilt.TARGET_ANGLE = Tilt.goal
  Tilt.enabled = level > 0
  
  -- Store options for sky enabled check
  Tilt.options = opts
  
  -- Load sky image from save directory if enabled and not already loaded
  if opts and opts.skyImageEnabled and not Tilt.skyImage then
    local savePath = "sky_image.png"
    if love.filesystem.getInfo(savePath) then
      local success, err = pcall(function()
        Tilt.skyImage = love.graphics.newImage(savePath)
      end)
      if not success then
        print("Failed to load sky image from save directory: " .. tostring(err))
      else
        print("Sky image loaded from save directory")
      end
    end
  end
end

-- Check if sky image should be rendered (enabled and image loaded)
function Tilt:isSkyEnabled()
  return Tilt.options and Tilt.options.skyImageEnabled and Tilt.skyImage ~= nil
end

function Tilt.levelLabel(level)
  return Tilt.ANGLE_LABELS[(level or Tilt.level) + 1] or "OFF"
end

-- Ease angle from `from` toward `goal` over TWEEN_TIME.
function Tilt.update(dt)
  if Tilt.t < 1 then
    Tilt.t = math.min(1, Tilt.t + dt / Tilt.TWEEN_TIME)
    local e = ease(Tilt.t)
    Tilt.angle = Tilt.from + (Tilt.goal - Tilt.from) * e
  else
    Tilt.angle = Tilt.goal
  end
  Tilt.TARGET_ANGLE = Tilt.goal
  Tilt.enabled = Tilt.level > 0
  -- Ease sky rotation toward target
  local rotDiff = Tilt.skyTargetRotation - Tilt.skyRotation
  if math.abs(rotDiff) > 0.001 then
    Tilt.skyRotation = Tilt.skyRotation + rotDiff * 5 * dt
  end
end

-- Update sky rotation based on player movement direction
-- dx: -1 (left), 0, 1 (right)
-- dy: -1 (up), 0, 1 (down)
function Tilt.updateSkyRotation(dx, dy)
  local rotationSpeed = 0.5 -- radians per second of movement
  local wiggleAmount = 0.1 -- radians for forward/back wiggle
  local bounceAmount = 0.05 -- radians for left/right bounce
  
  if dx ~= 0 then
    -- Rotate opposite to horizontal movement
    Tilt.skyTargetRotation = Tilt.skyTargetRotation + (-dx) * rotationSpeed
    -- Set bounce offset for left/right movement
    Tilt.skyBounceOffset = math.sin(love.timer.getTime() * 5) * bounceAmount
  elseif dy ~= 0 then
    -- Wiggle for forward/backward movement (affects target rotation directly)
    Tilt.skyTargetRotation = math.sin(love.timer.getTime() * 3) * wiggleAmount
    Tilt.skyBounceOffset = 0
  else
    -- No movement, reset bounce
    Tilt.skyBounceOffset = 0
  end
  -- Clamp rotation to reasonable range
  Tilt.skyTargetRotation = math.max(-math.pi/2, math.min(math.pi/2, Tilt.skyTargetRotation))
end

-- true while tilt is on *or* still tweening -- i.e. whenever the renderer
-- must take the perspective path rather than the flat blit
function Tilt.active()
  return Tilt.level > 0 or Tilt.angle > 0
end

function Tilt.gateOK(top, overworld)
  return Zoom.gateOK(top, overworld)
end

function Tilt.groundPoint(cx, cy, vw, vh)
  local a = Tilt.angle
  if a <= 0 then return cx, cy, 1 end
  local u = cx - vw * 0.5
  local w = cy - vh * 0.5
  local d = Tilt.FOCAL * vh
  local scale = d / (d - w * math.sin(a))
  local sx = vw * 0.5 + u * scale
  local sy = vh * 0.5 + w * math.cos(a) * scale
  return sx, sy, scale
end

function Tilt.viewGrowth()
  local a = Tilt.angle
  if a <= 0 then return 1 end
  local topScale = 1 / (1 + 0.5 * math.sin(a) / Tilt.FOCAL)
  local base = 1 / (math.cos(a) * topScale)
  return base + Tilt.VIEW_MARGIN * (base - 1)
end

function Tilt.meshCorners(vw, vh)
  local corners = {
    { 0, 0, 0, 0 },
    { vw, 0, 1, 0 },
    { vw, vh, 1, 1 },
    { 0, vh, 0, 1 },
  }
  local out = {}
  for i, c in ipairs(corners) do
    local sx, sy, scale = Tilt.groundPoint(c[1], c[2], vw, vh)
    out[i] = { sx, sy, c[3], c[4], scale }
  end
  return out
end

-- Set sky image from file path
function Tilt:setSkyImage(path)
  -- Ensure path is a string
  path = path and tostring(path) or nil
  
  -- Check if path has changed (avoid unnecessary copying)
  if path == Tilt.skyImagePath and Tilt.skyImage then
    -- Same image already loaded, do nothing
    return
  end
  
  Tilt.skyImagePath = path
  if Tilt.skyImage and Tilt.skyImage.release then
    Tilt.skyImage:release()
    Tilt.skyImage = nil
  end
  
  if path and path ~= "" then
    -- Copy image to save directory for LÖVE to access it
    local love = love
    local savePath = "sky_image.png"
    
    -- Try to read the source file and write to save directory
    local sourceFile = io.open(path, "rb")
    if sourceFile then
      local content = sourceFile:read("*a")
      sourceFile:close()
      if content then
        love.filesystem.write(savePath, content)
        print("Sky image copied to save directory: " .. savePath)
      end
    end
    
    -- Load from save directory
    local success, err = pcall(function()
      Tilt.skyImage = love.graphics.newImage(savePath)
    end)
    if not success then
      -- Log error but don't crash
      print("Failed to load sky image: " .. tostring(err))
      Tilt.skyImage = nil
    else
      print("Sky image loaded successfully from save directory")
    end
  end
end

-- Get current sky image
function Tilt:getSkyImage()
  return Tilt.skyImage
end

return Tilt
