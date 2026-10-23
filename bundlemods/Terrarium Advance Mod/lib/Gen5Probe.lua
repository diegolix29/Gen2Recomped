-- Gen5Probe: what Black / White's terrain is MADE of, written to the mod log once
-- per map.
--
-- WHY THIS EXISTS
--
-- Gen4Trees, Gen4Rocks, Gen4Fence, Gen4Flowers, Gen4Bump, Gen4Lawn and Gen4Hide's
-- water test all find their shapes by the cartridge's own texture / material
-- names -- Platinum's (`imped`, `nhana`, `allpeak`, `ngrass`, `tree01`...). Black /
-- White name their textures differently, so on a B/W cartridge those passes find
-- nothing and stay out of the way. To teach them B/W's names someone has to read
-- the names off the real cache once; this does that, so nobody has to guess.
--
-- WHAT IT WRITES
--
-- On the first Gen 5 frame of every map (Gen4Bridge.gen5FrameStart calls scan) one
-- block of lines in the mod log, prefixed "Gen5Probe:":
--
--   map Z123 area 6 outdoors=true: 14 terrain shape name(s)
--     tex='<texture>'  mat='<material>'  shapes=<n>  tris=<n>  [water?] [tree?] ...
--   texture set (area 6, season 0): <comma separated texture names>
--
-- `[water?]`, `[tree?]` and `[grass?]` mark names the existing classifiers would
-- already take (Gen4Hide.classify, Gen4Trees.isTreeName, "Cards" grass shapes), so
-- the unmarked ones are exactly the names that still need teaching.
--
-- Switch off with Probe.enabled = false. It reads names only: no geometry, no
-- textures, a few hundred table reads once per map.

local V = ...

local Probe = {
  enabled = true,
  seen = {},        -- map id -> true once logged
  MAX_LINES = 80,   -- per map
}

local function log(fmt, ...)
  local l = V and V.mod and V.mod.log
  if l and l.info then
    local ok, msg = pcall(string.format, fmt, ...)
    pcall(l.info, l, "Gen5Probe: " .. (ok and msg or fmt))
  end
end

local function optional(name)
  local ok, m = pcall(V.require, name)
  return ok and type(m) == "table" and m or nil
end

local function lower(s) return tostring(s or ""):lower() end

function Probe.scan(ground)
  if not Probe.enabled then return end
  local def = ground and ground.def
  local id = def and (def.id or def.header)
  if id == nil or Probe.seen[id] then return end
  Probe.seen[id] = true

  local terrain = ground.terrain
  local chunks = terrain and terrain.chunks
  if type(chunks) ~= "table" then
    log("map %s: no terrain chunks to read", tostring(id))
    return
  end

  local Hide, Trees = optional("Gen4Hide"), optional("Gen4Trees")
  local byKey, order = {}, {}
  for _, record in pairs(chunks) do
    for _, s in ipairs(record and record.shapes or {}) do
      local key = lower(s.texture) .. "\0" .. lower(s.material)
      local e = byKey[key]
      if not e then
        e = { tex = tostring(s.texture), mat = tostring(s.material), shapes = 0, tris = 0, sample = s }
        byKey[key] = e
        order[#order + 1] = key
      end
      e.shapes = e.shapes + 1
      e.tris = e.tris + (tonumber(s.triangleCount) or tonumber(s.triCount) or 0)
    end
  end
  table.sort(order)

  local rec = terrain.maps and terrain.maps[id]
  log("map %s area %s outdoors=%s: %d distinct terrain texture/material pair(s)",
      tostring(id), tostring(rec and rec.area or "?"), tostring(ground.outdoors), #order)
  for i, key in ipairs(order) do
    if i > Probe.MAX_LINES then
      log("  ... %d more", #order - Probe.MAX_LINES)
      break
    end
    local e = byKey[key]
    local marks = {}
    if Hide and Hide.classify then
      local okC, why = pcall(Hide.classify, e.sample)
      if okC and why then marks[#marks + 1] = "[water?:" .. tostring(why) .. "]" end
    end
    if Trees and Trees.isTreeName then
      local okT, isTree = pcall(Trees.isTreeName, e.sample)
      if okT and isTree then marks[#marks + 1] = "[tree?]" end
    end
    if Hide and Hide.isGrassCards then
      local okG, isCards = pcall(Hide.isGrassCards, e.sample)
      if okG and isCards then marks[#marks + 1] = "[grass-cards]" end
    end
    log("  tex='%s' mat='%s' shapes=%d tris=%d %s", e.tex, e.mat, e.shapes, e.tris,
        table.concat(marks, " "))
  end

  -- the texture set this ground wears (season already applied by the engine)
  local set = ground.set
  local textures = set and set.textures
  if type(textures) == "table" then
    local names = {}
    for name in pairs(textures) do names[#names + 1] = tostring(name) end
    table.sort(names)
    if #names > 0 then
      log("  texture set (%d): %s", #names, table.concat(names, ", "))
    end
  end
end

function Probe.reset() Probe.seen = {} end
Probe.invalidate = Probe.reset

return Probe
