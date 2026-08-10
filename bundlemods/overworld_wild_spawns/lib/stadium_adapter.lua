-- This adapter is no longer needed as stadium wilds functionality
-- has been moved to ADVANCED_SHAPE mod.
-- This file is kept for backwards compatibility but does nothing.

local V = ...

local StadiumAdapter = {}
StadiumAdapter.__index = StadiumAdapter

function StadiumAdapter.new(mod)
  local self = setmetatable({}, StadiumAdapter)
  self.mod = mod
  self.present = false
  return self
end

function StadiumAdapter:refreshPresence()
  return false
end

function StadiumAdapter:isPresent()
  return false
end

function StadiumAdapter:isModelAvailable(species)
  return false
end

function StadiumAdapter:speciesToDexNumber(species)
  return nil
end

function StadiumAdapter:getModel(species)
  return nil
end

function StadiumAdapter:keepModel(species)
  -- Do nothing
end

return StadiumAdapter