-- HD animated battle Pokémon sheets (National Dex 1-493).
--
-- Port of Kanto in Motion's Pokémon atlas player only: front/back, normal/
-- shiny, optional male/female frames. No KIM UI, move animations, or HUD.
-- Used when Stadium / Colosseum 3D models are missing (no ROM, or Gen 4).
--
-- Sheets live at assets/battle/hd-pokemon/{front|back}/{normal|shiny}/NNN.png
-- (optional -m / -f). Import Reloded GIFs with tools/import_hd_pokemon.py
-- --max-dex 493. Optional data/hd_pokemon.lua supplies atlas metadata; without
-- it a present PNG is treated as a single frame.
local V = ...
local M = { DEX_MIN = 1, DEX_MAX = 493 }

local byDex = nil
local atlasCache = {}
local canvasCache = {}
local timingCache = setmetatable({}, { __mode = "k" })
local picHooked = false
local capabilityInstalled = false

local function mod()
  return V.mod
end

function M.dex(value)
  local n = tonumber(value)
  if n then
    n = math.floor(n)
    if n >= M.DEX_MIN and n <= M.DEX_MAX then return n end
  end
  return nil
end

local function loadLua(relative)
  local handle = mod()
  if not (handle and type(handle.read) == "function") then return nil end
  local ok, src = pcall(handle.read, handle, relative)
  if not (ok and type(src) == "string" and src ~= "") then return nil end
  local chunk, err = load(src, "@" .. relative)
  if not chunk then return nil, err end
  local okRun, value = pcall(chunk)
  if okRun and type(value) == "table" then return value end
  return nil
end

local function mergeRow(dex, row)
  if not (dex and type(row) == "table") then return end
  local dest = byDex[dex]
  if not dest then
    byDex[dex] = row
    row.dex = dex
    return
  end
  for side, sideData in pairs(row) do
    if type(sideData) == "table" and (side == "front" or side == "back") then
      dest[side] = dest[side] or {}
      for color, colorData in pairs(sideData) do
        if type(colorData) == "table" then
          dest[side][color] = dest[side][color] or {}
          for gender, rec in pairs(colorData) do
            if type(rec) == "table" then dest[side][color][gender] = rec end
          end
        end
      end
    end
  end
end

local function ingestTable(tbl)
  if type(tbl) ~= "table" then return end
  for key, row in pairs(tbl) do
    if type(row) == "table" then
      mergeRow(M.dex(row.dex or key), row)
    end
  end
end

local function loadCacheLua()
  local handle = mod()
  local function run(src, name)
    if type(src) ~= "string" or src == "" then return nil end
    local chunk = load(src, name)
    if not chunk then return nil end
    local okRun, value = pcall(chunk)
    if okRun and type(value) == "table" then return value end
    return nil
  end
  local merged = {}
  local function take(src, name)
    local value = run(src, name)
    if type(value) ~= "table" then return end
    for key, row in pairs(value) do merged[key] = row end
  end
  if handle and handle.cache and type(handle.cache.read) == "function" then
    local ok, src = pcall(handle.cache.read, handle.cache, "hd_pokemon/data/hd_pokemon.lua")
    if ok then take(src, "@cache/hd_pokemon.lua") end
  end
  local Compat = V.EngineCompat or (V.require and V.require("EngineCompat"))
  local f = Compat and Compat.fs and Compat.fs()
  if f and type(f.read) == "function" then
    local ok, src = pcall(f.read, "hd_pokemon/data/hd_pokemon.lua")
    if ok then take(src, "@save/hd_pokemon.lua") end
  end
  return next(merged) and merged or nil
end

local function loadMetadata()
  if byDex then return byDex end
  byDex = {}
  ingestTable(loadLua("data/hd_pokemon.lua"))
  local kim
  if mod() and type(mod().find) == "function" then
    local ok, handle = pcall(mod().find, "animated_menu_pokemon")
    if ok then kim = handle end
  end
  if kim and type(kim.read) == "function" then
    local function kimLua(rel)
      local ok, src = pcall(kim.read, kim, rel)
      if not (ok and type(src) == "string") then return nil end
      local chunk = load(src, "@kim/" .. rel)
      if not chunk then return nil end
      local okRun, value = pcall(chunk)
      return okRun and value or nil
    end
    ingestTable(kimLua("data/hd_pokemon_sprites.lua"))
    ingestTable(kimLua("data/hd_pokemon_national.lua"))
  end
  ingestTable(loadCacheLua())
  return byDex
end

local function relPath(dex, side, shiny, gender)
  local color = shiny and "shiny" or "normal"
  local suffix = ""
  if gender == "male" then suffix = "-m"
  elseif gender == "female" then suffix = "-f" end
  return string.format("assets/battle/hd-pokemon/%s/%s/%03d%s.png",
    side, color, dex, suffix)
end

local function tryImage(relative)
  if type(relative) ~= "string" or relative == "" then return nil end
  local cached = atlasCache[relative]
  if cached then return cached end
  if cached == false then return nil end
  local handle = mod()
  local image
  if handle and handle.assets and type(handle.assets.image) == "function" then
    local ok, got = pcall(function() return handle.assets:image(relative) end)
    if ok and got then image = got end
  end
  if not image then
    local bytes
    local Compat = V.EngineCompat or (V.require and V.require("EngineCompat"))
    local f = Compat and Compat.fs and Compat.fs()
    if f and type(f.read) == "function" then
      local ok, got = pcall(f.read, "hd_pokemon/" .. relative)
      if ok then bytes = got end
    end
    if (type(bytes) ~= "string" or #bytes == 0)
        and handle and handle.cache and type(handle.cache.read) == "function" then
      local ok, got = pcall(function() return handle.cache:read("hd_pokemon/" .. relative) end)
      if ok then bytes = got end
    end
    if type(bytes) == "string" and #bytes > 0
        and love and love.filesystem and love.filesystem.newFileData then
      local okData, fileData = pcall(love.filesystem.newFileData, bytes, relative)
      if okData and fileData and love.graphics and love.graphics.newImage then
        local okImg, got = pcall(love.graphics.newImage, fileData)
        if okImg then image = got end
      end
    end
  end
  if not image and handle and type(handle.find) == "function" then
    local ok, kim = pcall(handle.find, "animated_menu_pokemon")
    if ok and kim then
      local provider = kim._kimAssetProvider
      if provider and type(provider.image) == "function" then
        local okImg, got = pcall(provider.image, relative)
        if okImg and got then image = got end
      end
      if not image and kim.assets and type(kim.assets.image) == "function" then
        local okImg, got = pcall(function() return kim.assets:image(relative) end)
        if okImg and got then image = got end
      end
    end
  end
  if image then
    if image.setFilter then pcall(image.setFilter, image, "nearest", "nearest") end
    atlasCache[relative] = image
    return image
  end
  atlasCache[relative] = false
  return nil
end

local function chooseVariant(colorData, gender)
  if type(colorData) ~= "table" then return nil end
  if gender and type(colorData[gender]) == "table" then return colorData[gender] end
  return colorData.default or colorData.male or colorData.female
end

local function syntheticRecord(dex, side, shiny, gender)
  local tries = {}
  if gender then tries[#tries + 1] = relPath(dex, side, shiny, gender) end
  tries[#tries + 1] = relPath(dex, side, shiny, nil)
  if shiny then
    if gender then tries[#tries + 1] = relPath(dex, side, false, gender) end
    tries[#tries + 1] = relPath(dex, side, false, nil)
  end
  for _, path in ipairs(tries) do
    local image = tryImage(path)
    if image then
      local iw, ih = image:getDimensions()
      return {
        image = path,
        width = iw,
        height = ih,
        columns = 1,
        frames = 1,
        durations = { 100 },
        displayScale = side == "back" and 0.315 or 0.33,
        _whole = true,
      }
    end
  end
  return nil
end

function M.reload()
  byDex = nil
  atlasCache = {}
  canvasCache = {}
  return loadMetadata()
end

function M.installedCount()
  local n = 0
  for key, row in pairs(loadMetadata()) do
    if type(row) == "table" and (row.front or row.back) then
      local dex = M.dex(row.dex or key)
      if dex then n = n + 1 end
    end
  end
  return n
end

function M.record(dex, side, shiny, gender)
  dex = M.dex(dex)
  side = side == "back" and "back" or "front"
  if not dex then return nil end
  loadMetadata()
  local row = byDex[dex]
  local rec
  if row then
    local sideData = row[side]
    local colorData = type(sideData) == "table" and sideData[shiny and "shiny" or "normal"]
    rec = chooseVariant(colorData, gender)
    if type(rec) ~= "table" and shiny then
      colorData = type(sideData) == "table" and sideData.normal
      rec = chooseVariant(colorData, gender)
    end
  end
  if type(rec) ~= "table" or type(rec.image) ~= "string" then
    rec = syntheticRecord(dex, side, shiny, gender)
  end
  if type(rec) ~= "table" or type(rec.image) ~= "string" then return nil end
  if not tryImage(rec.image) then return nil end
  return rec
end

function M.available(dex, side, shiny, gender)
  return M.record(dex, side, shiny, gender) ~= nil
end

local function timing(rec)
  local hit = timingCache[rec]
  if hit then return hit end
  local count = math.max(1, math.floor(tonumber(rec.frames) or 1))
  local src = type(rec.durations) == "table" and rec.durations or {}
  local cumulative, total = {}, 0
  for i = 1, count do
    local d = math.max(1, tonumber(src[i]) or 100)
    total = total + d
    cumulative[i] = total
  end
  hit = { count = count, cumulative = cumulative, total = math.max(1, total) }
  timingCache[rec] = hit
  return hit
end

local function frameFor(rec)
  local t = timing(rec)
  if t.count <= 1 then return 1 end
  local now = love and love.timer and love.timer.getTime and love.timer.getTime() or 0
  local ms = (now * 1000) % t.total
  for i = 1, t.count do
    if ms < t.cumulative[i] then return i end
  end
  return t.count
end

local function sourceQuad(image, rec, frame)
  if rec._whole or (tonumber(rec.frames) or 1) <= 1 then return nil end
  local width = math.max(1, math.floor(tonumber(rec.width) or 1))
  local height = math.max(1, math.floor(tonumber(rec.height) or 1))
  local columns = math.max(1, math.floor(tonumber(rec.columns) or 1))
  local iw, ih = image:getDimensions()
  frame = math.max(1, math.min(math.floor(tonumber(rec.frames) or 1), frame))
  local idx = frame - 1
  local col, row = idx % columns, math.floor(idx / columns)
  local ok, quad = pcall(love.graphics.newQuad,
    col * width, row * height, width, height, iw, ih)
  return ok and quad or nil
end

function M.frameImage(rec)
  if type(rec) ~= "table" then return nil end
  local image = tryImage(rec.image)
  if not image then return nil end
  local frame = frameFor(rec)
  if rec._whole or (tonumber(rec.frames) or 1) <= 1 then return image end
  local width = math.max(1, math.floor(tonumber(rec.width) or 1))
  local height = math.max(1, math.floor(tonumber(rec.height) or 1))
  local key = table.concat({ rec.image, tostring(frame), tostring(width), tostring(height) }, ":")
  local cached = canvasCache[key]
  if cached then return cached end
  if not (love and love.graphics and love.graphics.newCanvas) then return image end
  local ok, canvas = pcall(love.graphics.newCanvas, width, height)
  if not ok or not canvas then return image end
  if canvas.setFilter then pcall(canvas.setFilter, canvas, "nearest", "nearest") end
  local quad = sourceQuad(image, rec, frame)
  if not quad then return image end
  local previous = love.graphics.getCanvas and love.graphics.getCanvas() or nil
  love.graphics.push("all")
  love.graphics.setCanvas(canvas)
  love.graphics.origin()
  love.graphics.setShader()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.draw(image, quad, 0, 0)
  if previous then love.graphics.setCanvas(previous) else love.graphics.setCanvas() end
  love.graphics.pop()
  canvasCache[key] = canvas
  return canvas
end

local function battlerShiny(battler)
  local mon = battler and (battler.mon or battler)
  if not mon then return false end
  if mon.shiny == true or mon.isShiny == true then return true end
  local Shiny = V.ShinySupport
  if Shiny and type(Shiny.variant) == "function" then
    local ok, value = pcall(Shiny.variant, battler)
    if ok and value == "shiny" then return true end
  end
  return false
end

local function battlerGender(battler)
  local mon = battler and (battler.mon or battler)
  local g = mon and (mon.gender or mon.sex)
  if g == "F" or g == "female" or g == 1 then return "female" end
  if g == "M" or g == "male" or g == 0 then return "male" end
  return nil
end

local function battlerDex(battler, game)
  if not battler then return nil end
  local mon = battler.mon or battler
  local n = M.dex(mon and (mon.dex or mon.nationalDex or mon.speciesIndex or mon.index))
  if n then return n end
  local def = battler.def
  n = M.dex(def and (def.dex or def.index or def.number or def.nationalDex))
  if n then return n end
  local species = mon and mon.species or battler.species
  n = M.dex(species)
  if n then return n end
  if type(species) == "string" then
    local fromName = species:match("SPECIES_(%d+)")
    n = M.dex(fromName)
    if n then return n end
  end
  local data = game and game.data and game.data.pokemon
  if data and species and data[species] then
    return M.dex(data[species].dex or data[species].index)
  end
  return nil
end

function M.battleImage(battle, side, battler)
  local game = (battle and battle.game) or (mod() and mod().game)
  local dex = battlerDex(battler, game)
  if not dex then return nil end
  -- 3D battles: front sheet for every battler. Back sheets are for followers.
  local rec = M.record(dex, "front", battlerShiny(battler), battlerGender(battler))
  return rec and M.frameImage(rec) or nil
end

function M.replacePic(battle, img)
  if not (battle and img) then return nil end
  local player = battle.player
  local enemy = battle.enemy
  if img == battle.playerBackPic or (player and img == player.sprite) then
    return M.battleImage(battle, "player", player)
  end
  if img == battle.enemyPic or (enemy and img == enemy.sprite) then
    return M.battleImage(battle, "enemy", enemy)
  end
  return nil
end

function M.decoratePose(pose)
  local entity = pose and (pose.entity or pose)
  if type(entity) ~= "table" then return false end
  local dex = M.dex(entity._hdPokemonDex)
  if not dex then
    local Wilds = V.StadiumWilds
    if Wilds and type(Wilds.getEntitySpeciesDex) == "function" then
      dex = M.dex(Wilds.getEntitySpeciesDex(entity))
    end
  end
  if not dex then
    dex = battlerDex(entity, mod() and mod().game)
  end
  if not dex then return false end
  local rec = M.record(dex, "front", entity.shiny == true, nil)
  local image = rec and M.frameImage(rec)
  if not image then return false end
  local iw, ih = image:getDimensions()
  local fw = math.max(1, math.floor(tonumber(rec.width) or iw))
  local fh = math.max(1, math.floor(tonumber(rec.height) or ih))
  local scale = 16 / fh
  local sprite = pose.sprite or entity.sprite
  if type(sprite) ~= "table" then
    sprite = {}
    pose.sprite = sprite
  end
  local def = {}
  if type(sprite.def) == "table" then
    for key, value in pairs(sprite.def) do def[key] = value end
  end
  def.hdImage = image
  def.hdFrameW = fw
  def.hdFrameH = fh
  def.frames = 1
  def.trueColor = true
  def.walker = false
  def.scale = scale
  def.heightScale = scale
  sprite.def = def
  sprite.image = image
  sprite.frames = 1
  sprite.walker = false
  sprite.trueColor = true
  sprite.scale = scale
  return true
end

M.service = {
  version = 1,
  resolve = function(context, side, battler, current)
    local battle = context and context.battle
    local image = M.battleImage(battle, side, battler)
    return image or current
  end,
}

function M.installPicHook()
  if picHooked then return true end
  local ok, BattleState = pcall(require, "src.battle.BattleState")
  if not (ok and type(BattleState) == "table" and type(BattleState.picImage) == "function") then
    return false
  end
  if BattleState.__hdPokemonPicHook then
    picHooked = true
    return true
  end
  local inner = BattleState.picImage
  function BattleState:picImage(img)
    local out = inner(self, img)
    local hd = M.replacePic(self, img)
    return hd or out
  end
  BattleState.__hdPokemonPicHook = true
  picHooked = true
  return true
end

function M.installCapability(CurrentSpriteModels)
  if capabilityInstalled then return true end
  local CSM = CurrentSpriteModels or V.CurrentSpriteModels
  if not (CSM and type(CSM.registerCapability) == "function") then return false end
  local ok = pcall(CSM.registerCapability, "DRAMATIC_SHAPE/hd-pokemon", "battleSprites", M.service)
  capabilityInstalled = ok and true or false
  return capabilityInstalled
end

function M.install(CurrentSpriteModels)
  M.installPicHook()
  M.installCapability(CurrentSpriteModels)
  return true
end

return M
