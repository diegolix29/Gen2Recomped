-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE POKEWALKER'S POKEMON PICTURES: the best the player has imported,
-- searched game by game, HIGHEST GENERATION FIRST.
--   * walking (an overworld sprite): HeartGold / SoulSilver's following-
--     Pokemon sheets (gen4_follow_mon -- eight 32x32 frames, a step cycle per
--     facing); else Emerald / FireRed's, then the Gen 2 games', two-frame
--     menu sprites (in Gen 2 those ARE the overworld Pokemon sprites).
--     Black / White have no overworld Pokemon, so they are skipped here.
--   * portraits: the battle front sprite of the highest generation that has
--     the species -- Black / White (649 species), HGSS, Platinum, then the
--     Gen 3, Gen 2 and Gen 1 games' fronts (pokemon.lua spriteFront).
--
-- WHERE THE BYTES COME FROM.  Every imported game keeps its cache under
-- <cache root>/<cachePrefix>{data,assets}/generated (Red's prefix is "").
-- The cache root is NOT one place:
--   * CacheFs.root() -- the portable folder (fused desktop builds next to the
--     .exe) or the player's chosen game-data folder (desktop or Android SD);
--   * otherwise LOVE's save directory (Android's default, and every install
--     that never picked a folder).
-- This module used to open SaveData.dataDir() .. "/<version>/..." only, which
-- is nil in BOTH of those common cases (portable mode returns nil on purpose,
-- and Android rarely has a folder chosen), so the pictures only ever appeared
-- on a desktop source run with a custom folder set.  It now asks every root
-- in turn with io.open (real paths -- no mount needed, and the launcher's
-- background may hold the one mount there is), then love.filesystem as a last
-- resort for a folder only the Android JNI bridge put on the read path.

local A = {}

-- version id, generation, cache prefix (nil = GameVersion's, else this)
local FRONTS = {
  { "black", 5 }, { "white", 5 },
  { "heartgold", 4 }, { "soulsilver", 4 }, { "platinum", 4 },
  { "emerald", 3 }, { "firered", 3 },
  { "crystal", 2 }, { "polishedcrystal", 2 }, { "prism", 2 }, { "gold", 2 }, { "silver", 2 },
  { "yellow", 1 }, { "blue", 1 }, { "red", 1, "" },
}
local WALKS = {
  { "heartgold", 4 }, { "soulsilver", 4 },
  { "emerald", 3 }, { "firered", 3 },
  { "crystal", 2 }, { "polishedcrystal", 2 }, { "prism", 2 }, { "gold", 2 }, { "silver", 2 },
}
A.FRONT_ORDER, A.WALK_ORDER = FRONTS, WALKS

local cache

function A.forget()
  cache = { images = {}, boxes = {}, data = {}, dex = {} }
end
A.forget()

local function prefixOf(entry)
  if entry[3] then return entry[3] end
  local ok, p = pcall(function() return require("src.core.GameVersion").cachePrefix(entry[1]) end)
  if ok and type(p) == "string" then return p end
  return entry[1] .. "/"
end

-- every real folder a cache can live in, most specific first.  Tests set
-- A._roots to a list to point it at a fixture tree.
local function roots()
  if A._roots then return A._roots end
  if cache.roots then return cache.roots end
  local list, seen = {}, {}
  local function add(r)
    if type(r) ~= "string" or r == "" then return end
    r = r:gsub("[/\\]+$", "")
    if r ~= "" and not seen[r] then seen[r] = true; list[#list + 1] = r end
  end
  pcall(function() add(require("src.import.CacheFs").root()) end)
  pcall(function() add(require("src.core.SaveData").dataDir()) end)
  pcall(function() add(require("src.core.SaveData").portableBaseDir()) end)
  pcall(function() add(love.filesystem.getSaveDirectory()) end)
  cache.roots = list
  return list
end
A._rootList = roots

-- the bytes of <prefix><rel> from the first root that has them
local function readCache(prefix, rel)
  local path = prefix .. rel
  for _, r in ipairs(roots()) do
    local f = io.open(r .. "/" .. path, "rb")
    if f then
      local s = f:read("*a"); f:close()
      if s and #s > 0 then return s end
    end
  end
  -- Red's un-prefixed paths are skipped: the version overlays answer those
  -- for whichever game is active, which may not be Red.
  if prefix ~= "" and not A._roots and love and love.filesystem and love.filesystem.read then
    local ok, s = pcall(love.filesystem.read, path)
    if ok and type(s) == "string" and #s > 0 then return s end
  end
  return nil
end
A._read = readCache

local function loadData(entry, module)
  local key = entry[1] .. ":" .. module
  local hit = cache.data[key]
  if hit ~= nil then return hit or nil end
  hit = false
  local src = readCache(prefixOf(entry), "data/generated/" .. module .. ".lua")
  if src then
    local chunk = (loadstring or load)(src, "=" .. entry[1] .. "/" .. module)
    local ok, t = pcall(chunk or error)
    if ok and type(t) == "table" then hit = t end
  end
  cache.data[key] = hit
  return hit or nil
end

local function image(entry, rel)
  if not (entry and rel) then return nil end
  local key = entry[1] .. "/" .. rel
  local hit = cache.images[key]
  if hit ~= nil then return hit or nil end
  hit = false
  local bytes = readCache(prefixOf(entry), rel)
  if bytes then
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
    if ok and img then
      img:setFilter("nearest", "nearest")
      hit = img
      cache.boxes[img] = box
    end
  end
  cache.images[key] = hit
  return hit or nil
end

-- Gen 1-3: national dex -> { front, shiny, icon, frameHeight } from the
-- game's pokemon.lua, joined with icons.lua by species id
local function speciesByDex(entry)
  local hit = cache.dex[entry[1]]
  if hit ~= nil then return hit or nil end
  hit = false
  local mons = loadData(entry, "pokemon")
  if mons then
    local icons = loadData(entry, "icons")
    local byId = icons and icons.bySpecies or {}
    hit = {}
    for id, rec in pairs(mons) do
      local dex = type(rec) == "table" and tonumber(rec.dex)
      if dex and dex > 0 and not hit[dex] then
        local ic = byId[rec.id or id]
        local icon = ic and ic.image
        if not icon and type(rec.icon) == "string" and not rec.icon:find("placeholder", 1, true) then
          icon = rec.icon
        end
        hit[dex] = { front = rec.spriteFront, shiny = rec.spriteShiny, icon = icon,
                     frameHeight = ic and ic.frameHeight }
      end
    end
  end
  cache.dex[entry[1]] = hit
  return hit or nil
end

-- two frames stacked: the same bounce for every facing
local BOUNCE = { down = { 0, 1 }, up = { 0, 1 }, left = { 0, 1 }, right = { 0, 1 } }

-- the walking sheet: image, frame w, frame h, facings ({ down = {2,3,2}, ... }),
-- and the version it came from
function A.walk(dex, shiny)
  if not dex then return nil end
  for _, entry in ipairs(WALKS) do
    if entry[2] == 4 then
      local d = loadData(entry, "gen4_follow_mon")
      local idx = d and d.sheets and d.lut and d.lut[dex]
      local sheet = idx and d.sheets[idx]
      if sheet then
        local img = image(entry, shiny and sheet.shiny or sheet.normal)
                 or (shiny and image(entry, sheet.normal))
        if img then
          return img, sheet.frameWidth or 32, sheet.frameHeight or 32, d.facings, entry[1]
        end
      end
    else
      local by = speciesByDex(entry)
      local rec = by and by[dex]
      local img = rec and rec.icon and image(entry, rec.icon)
      if img then
        local iw = img:getWidth()
        return img, iw, rec.frameHeight or iw, BOUNCE, entry[1]
      end
    end
  end
  return nil
end

-- the front portrait of the highest generation that has it (+ its version)
function A.front(dex, shiny)
  if not dex then return nil end
  for _, entry in ipairs(FRONTS) do
    if entry[2] >= 4 then
      local d = loadData(entry, "gen4_species_sprites")
      local rec = d and d.species and d.species[dex]
      if rec then
        local img = image(entry, shiny and rec.shiny_front or rec.front)
                 or (shiny and image(entry, rec.front))
        if img then return img, entry[1] end
      end
    else
      local by = speciesByDex(entry)
      local rec = by and by[dex]
      if rec then
        local img = image(entry, shiny and rec.shiny or rec.front) or (shiny and image(entry, rec.front))
        if img then return img, entry[1] end
      end
    end
  end
  return nil
end

-- the opaque part of a picture this module loaded: { x, y, w, h } or nil
function A.bounds(img) return cache.boxes[img] end

-- the menu icon (two frames stacked in one image) and its frame height
function A.icon(dex)
  if not dex then return nil end
  for _, entry in ipairs(FRONTS) do
    if entry[2] >= 4 then
      local d = loadData(entry, "gen4_species_sprites")
      local icons = d and d.icons and d.icons.bySpecies
      local rec = icons and icons[dex]
      local img = rec and image(entry, rec.image)
      if img then return img, rec.frameHeight or 32 end
    else
      local by = speciesByDex(entry)
      local rec = by and by[dex]
      local img = rec and rec.icon and image(entry, rec.icon)
      if img then return img, rec.frameHeight or img:getWidth() end
    end
  end
  return nil
end

return A
