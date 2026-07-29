-- Camera centered on the player.  At the default 160x144 view this is
-- the original framing (player sprite at screen tile (8,8) -> pixel
-- (64, 60) after the -4px sprite offset); wider/taller world-pass views
-- (window-filling survey on phones, wheel zoom-out) keep the player at
-- the same relative center.

local Camera = {}
Camera.__index = Camera

-- Standard angles for each compass direction (using positive range 0 to 360)
Camera.STANDARD_ANGLES = {
  FRONT = 0,
  RIGHT = 90,
  BACK = 180,
  LEFT = 270
}

-- Tween settings for smooth rotation
Camera.TWEEN_TIME = 0.3 -- seconds to complete rotation

local function ease(t)
  return t * t * (3 - 2 * t) -- smooth ease-in-out
end

-- Normalize angle to 0 to 360 range
local function normalizeAngle(angle)
  while angle >= 360 do angle = angle - 360 end
  while angle < 0 do angle = angle + 360 end
  return angle
end

-- Get the closest standard angle for a given angle
local function getClosestStandardAngle(angle)
  local normalized = normalizeAngle(angle)
  local closest = Camera.STANDARD_ANGLES.FRONT
  local minDiff = math.abs(normalized - closest)
  
  for name, standardAngle in pairs(Camera.STANDARD_ANGLES) do
    local diff = math.abs(normalized - standardAngle)
    if diff < minDiff then
      minDiff = diff
      closest = standardAngle
    end
  end
  
  return closest
end

-- Get label for current angle
local function getAngleLabel(angle)
  local normalized = normalizeAngle(angle)
  for label, standardAngle in pairs(Camera.STANDARD_ANGLES) do
    if math.abs(normalized - standardAngle) < 45 then
      return label
    end
  end
  return "FRONT"
end

function Camera.new()
  return setmetatable({ 
    x = 0, 
    y = 0, 
    rotation = 0, 
    targetRotation = 0,
    rotationFrom = 0,
    rotationT = 1
  }, Camera)
end

function Camera:follow(px, py, viewW, viewH)
  viewW, viewH = viewW or 160, viewH or 144
  self.x = px - (viewW / 2 - 16)
  self.y = py - (viewH / 2 - 8)
  self.px = px -- Store player position for rotation pivot
  self.py = py
end

-- Rotate camera left (decrease rotation, compass movement)
function Camera:rotateLeft()
  -- Always move 90 degrees left from current target
  local currentTarget = normalizeAngle(self.targetRotation)
  local newTarget = currentTarget + 90  -- Fixed: +90 for left movement
  
  -- Find the next standard angle in compass direction
  local closest = getClosestStandardAngle(newTarget)
  
  if closest ~= self.targetRotation then
    self.rotationFrom = self.rotation
    self.targetRotation = closest
    self.rotationT = 0
  end
end

-- Rotate camera right (increase rotation, compass movement)
function Camera:rotateRight()
  -- Always move 90 degrees right from current target
  local currentTarget = normalizeAngle(self.targetRotation)
  local newTarget = currentTarget - 90  -- Fixed: -90 for right movement
  
  -- Find the next standard angle in compass direction
  local closest = getClosestStandardAngle(newTarget)
  
  if closest ~= self.targetRotation then
    self.rotationFrom = self.rotation
    self.targetRotation = closest
    self.rotationT = 0
  end
end

-- Reset camera to front view
function Camera:resetRotation()
  self.targetRotation = Camera.STANDARD_ANGLES.FRONT
  self.rotationFrom = self.rotation
  self.rotationT = 0
end

-- Update rotation tween
function Camera:update(dt)
  if self.rotationT < 1 then
    self.rotationT = math.min(1, self.rotationT + dt / Camera.TWEEN_TIME)
    local e = ease(self.rotationT)
    
    -- Handle wrapping for smooth interpolation in 0-360 range
    local from = self.rotationFrom
    local to = self.targetRotation
    local diff = to - from
    
    -- If the difference is more than 180, wrap the other way around 0/360
    if diff > 180 then
      from = from + 360
    elseif diff < -180 then
      from = from - 360
    end
    
    self.rotation = from + (to - from) * e
    
    -- Normalize to 0-360 range during interpolation to keep values consistent
    self.rotation = normalizeAngle(self.rotation)
  else
    self.rotation = self.targetRotation
  end
end

-- Get current rotation angle in degrees (interpolated during tween)
function Camera:getRotation()
  return self.rotation
end

-- Get current rotation label
function Camera:getRotationLabel()
  return getAngleLabel(self.rotation)
end

-- Get current rotation angle in radians (for voxel mod integration)
function Camera:angle()
  return math.rad(self.rotation)
end

return Camera
