-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE POKEWALKER'S POKEMON PICTURES: the best the player has imported.
--   * walking: HeartGold / SoulSilver's following-Pokemon sheets
--     (gen4_follow_mon -- eight 32x32 frames, a step cycle per facing), so
--     the walk on the screen is the cartridge's own walk; species 1..493.
--   * portraits: the battle front sprites at their largest -- Black / White's
--     (649 species, 96x96), else HeartGold / SoulSilver's or Platinum's.
-- Read straight from each imported game's cache folder (no mount -- the
-- launcher's background may hold the one mount there is).

local A = {}

local function root() return require("src.core.SaveData").dataDir() end

local function loadData(version, module)
  local r = root()
  if not r then return nil end
  local f = io.open(r .. "/" .. version .. "/data/generated/" .. module .. ".lua", "rb")
  if not f then return nil end
  local src = f:read("*a"); f:close()
  local chunk = (loadstring or load)(src)
  local ok, t = pcall(chunk)
  return ok and type(t) == "table" and t or nil
end

local cache = { images = {} }

local function image(version, rel)
  if not (version and rel) then return nil end
  local key = version .. "/" .. rel
  local hit = cache.images[key]
  if hit ~= nil then return hit or nil end
  hit = false
  local r = root()
  local f = r and io.open(r .. "/" .. version .. "/" .. rel, "rb")
  if f then
    local bytes = f:read("*a"); f:close()
    local ok, img, box = pcall(function()
      local data = love.image.newImageData(love.filesystem.newFileData(bytes, rel:match("[^/]+$")))
      -- the opaque bounds, so a sprite in a mostly empty frame can be shown
      -- at the size of the Pokemon rather than of the frame
      local w, h = data:getDimensions()
      local x0, y0, x1, y1 = w, h, -1, -1
      for yy = 0, h - 1 do
        for xx = 0, w - 1 do
          local _, _, _, a = data:getPixel(xx, yy)
          if a > 0 then
            if xx < x0 then x0 = xx end; if xx > x1 then x1 = xx end
            if yy < y0 then y0 = yy end; if yy > y1 then y1 = yy end
          end
        end
      end
      local i = love.graphics.newImage(data)
      return i, x1 >= 0 and { x = x0, y = y0, w = x1 - x0 + 1, h = y1 - y0 + 1 } or nil
    end)
    if ok and img then img:setFilter("nearest", "nearest"); hit = img; cache.boxes = cache.boxes or {}; cache.boxes[img] = box end
  end
  cache.images[key] = hit
  return hit or nil
end

local function follow()
  if cache.follow == nil then
    cache.follow = false
    for _, v in ipairs({ "heartgold", "soulsilver" }) do
      local d = loadData(v, "gen4_follow_mon")
      if d and d.sheets then cache.follow = { data = d, version = v } break end
    end
  end
  return cache.follow or nil
end

local function fronts()
  if cache.fronts == nil then
    cache.fronts = {}
    for _, v in ipairs({ "black", "white", "heartgold", "soulsilver", "platinum" }) do
      local d = loadData(v, "gen4_species_sprites")
      if d and d.species then cache.fronts[#cache.fronts + 1] = { data = d, version = v } end
    end
  end
  return cache.fronts
end

-- the walking sheet: image, frame w, frame h, facings ({ down = {2,3,2}, ... })
function A.walk(dex, shiny)
  local f = follow()
  if not (f and dex) then return nil end
  local idx = f.data.lut and f.data.lut[dex]
  local sheet = idx and f.data.sheets[idx]
  if not sheet then return nil end
  local img = image(f.version, shiny and sheet.shiny or sheet.normal)
  if not img then return nil end
  return img, sheet.frameWidth or 32, sheet.frameHeight or 32, f.data.facings
end

-- the largest front portrait
function A.front(dex, shiny)
  if not dex then return nil end
  for _, src in ipairs(fronts()) do
    local rec = src.data.species and src.data.species[dex]
    if rec then
      local img = image(src.version, shiny and rec.shiny_front or rec.front)
      if img then return img end
    end
  end
  return nil
end

-- the opaque part of a picture this module loaded: { x, y, w, h } or nil
function A.bounds(img) return cache.boxes and cache.boxes[img] end

-- the menu icon (32x32, two frames stacked in one image)
function A.icon(dex)
  for _, src in ipairs(fronts()) do
    local icons = src.data.icons and src.data.icons.bySpecies
    local rec = icons and icons[dex]
    if rec then
      local img = image(src.version, rec.image)
      if img then return img, rec.frameHeight or 32 end
    end
  end
  return nil
end

return A
