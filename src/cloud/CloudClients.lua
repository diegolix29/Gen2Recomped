-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- The cloud services' app credentials: cloud_clients.lua at the game's root
-- (git-ignored; cloud_clients.example.lua shows the shape; release builds
-- write it from repository secrets). Missing or empty means "not set up" and
-- the launcher says so rather than offering a sign-in that cannot work.

local C = {}
local cached

function C.get()
  if cached ~= nil then return cached or nil end
  cached = false
  if love and love.filesystem and love.filesystem.getInfo("cloud_clients.lua") then
    local ok, chunk = pcall(love.filesystem.load, "cloud_clients.lua")
    if ok and chunk then
      local okR, t = pcall(chunk)
      if okR and type(t) == "table" then cached = t end
    end
  end
  return cached or nil
end

local function filled(c) return type(c) == "table" and type(c.id) == "string" and c.id ~= "" end

function C.googleDesktop() local t = C.get(); local g = t and t.google; return g and filled(g.desktop) and g.desktop or nil end
function C.googleDevice() local t = C.get(); local g = t and t.google; return g and filled(g.device) and g.device or nil end
function C.microsoft() local t = C.get(); return t and filled(t.microsoft) and t.microsoft or nil end

return C
