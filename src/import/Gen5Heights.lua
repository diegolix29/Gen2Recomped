-- src/import/Gen5Heights.lua -- WHAT A BLACK / WHITE TILE'S HEIGHT FIELD MEANS.
--
-- A WB / GC chunk's permission tile is 8 bytes; on a flat tile bytes 0-1 are
-- 0 and bytes 2-3 hold a u16 that Gen5Field read as the height in world
-- units. IT IS NOT A HEIGHT: it indexes the field overlay's table of plane
-- distances. OVERLAY 21 carries it (Black 0x54258, White 0x54250 into the
-- overlay; found by its own entries, not by address): s32 `d` per index, the
-- flat plane y * ny + d = 0 with ny = 4095 (the normal's fx 0.9998), so the
-- height is -d / 4095 -- 120 is -32759, 8 units (the bedroom's table and TV
-- stand, Z391: read as 120 units the gift box stood seven and a half tiles
-- over the table); 463 is 48, 14 is 16, 464 is -80.
-- Checked against the people standing on them (an NPC record's fx32 at +32,
-- Gen5Events): every one of the 31 values people stand on agrees.
--
-- `derive` is the fallback for a cartridge whose overlay does not carry the
-- table where it is looked for: the same answers read back out of the people
-- (exact) and the chunk models' surfaces (approximate -- 22 of 60 values came
-- out wrong this way, so it is only a fallback).
--
-- build(rom) -> { [value] = height in world units }, report
-- (sloped tiles -- bytes 0-1 non-zero, a normal's index -- are not read yet;
-- they take their neighbours' height in Gen4Ground.heightAt)

local H = {}

H.PATH = { zones = "/a/0/1/2", matrices = "/a/0/0/9", chunks = "/a/0/0/8", events = "/a/1/2/5" }

local function u16(s, o) return (s:byte(o + 1) or 0) + (s:byte(o + 2) or 0) * 256 end

-- the flat value of tile t (0..1023) of a raw permission section, or nil
function H.valueAt(raw, t)
  local at = 4 + t * 8
  if #raw < at + 8 then return nil end
  if raw:byte(at + 1) ~= 0 or raw:byte(at + 2) ~= 0 then return nil end
  return u16(raw, at + 2), raw:byte(at + 7) % 2 == 1
end

-- a SLOPED tile: bytes 0-1 name a normal (non-zero), so it has no flat value
function H.isSlope(raw, t)
  local at = 4 + t * 8
  if #raw < at + 8 then return false end
  return raw:byte(at + 1) ~= 0 or raw:byte(at + 2) ~= 0
end

local function mode(counts)
  local best, n = nil, 0
  for v, c in pairs(counts) do
    if c > n or (c == n and best and v < best) then best, n = v, c end
  end
  return best, n
end

function H.derive(rom)
  local Narc = require("src.import.NarcArchive")
  local M = require("src.import.Gen5Maps")
  local function arc(p) local b = rom:read(p); return b and Narc.parse(b) end
  local zoneArc, mxArc, cArc, evArc = arc(H.PATH.zones), arc(H.PATH.matrices), arc(H.PATH.chunks), arc(H.PATH.events)
  if not (zoneArc and mxArc and cArc and evArc) then return nil, "archives missing" end
  local zones = M.zones(zoneArc:get(0))
  local perms, models = {}, {}
  local function chunk(c)
    if perms[c] == nil then
      local ok, ch = pcall(M.chunk, cArc:get(c))
      perms[c] = ok and ch and ch.permissions and #ch.permissions >= 4 + 1024 * 8 and ch.permissions or false
      if ok and ch and ch.kind == "GC" and ch.layer2 and perms[c] then
        perms[c] = require("src.import.Gen5Field").mergeLayers(perms[c], ch.layer2)
      end
      models[c] = ok and ch and ch.model or false
    end
    return perms[c] or nil
  end

  -- 1. the people
  local people = {}
  for _, z in pairs(zones) do
    local mx = M.matrix(mxArc:get(z.matrix))
    local d = evArc:get(z.events)
    if mx and d and #d > 8 then
      local nf, nn = d:byte(5), d:byte(6)
      local at = 8 + nf * 20
      for i = 0, nn - 1 do
        local o = at + i * 36
        if u16(d, o + 24) ~= 1 then
          local x, y = u16(d, o + 28), u16(d, o + 30)
          local fy = u16(d, o + 32) + u16(d, o + 34) * 65536
          if fy >= 2 ^ 31 then fy = fy - 2 ^ 32 end
          local cx, cy = math.floor(x / 32), math.floor(y / 32)
          local c = cx < mx.width and cy < mx.height and mx.chunks[cy * mx.width + cx + 1]
          local raw = c and chunk(c)
          if raw then
            local v, blocked = H.valueAt(raw, (y % 32) * 32 + (x % 32))
            if v and not blocked then
              people[v] = people[v] or {}
              local h = fy / 4096
              people[v][h] = (people[v][h] or 0) + 1
            end
          end
        end
      end
    end
  end

  -- 2. the ground: every chunk model's surfaces at its tiles' centres
  local ground = {}
  local Nsbmd = require("src.import.Gen4Nsbmd")
  for c = 0, cArc.count - 1 do
    local raw = chunk(c)
    local okp, set = false, nil
    if raw and models[c] then okp, set = pcall(Nsbmd.parse, models[c]) end
    local model = okp and set and set.models and set.models[1]
    if model then
      local s = model.posScale or 1
      local vals = {}
      for t = 0, 1023 do vals[t] = (H.valueAt(raw, t)) end
      local seen, here = {}, {}
      for _, sh in ipairs(model.shapes or {}) do
        local V = sh.vertices
        for _, tr in ipairs(sh.triangles or {}) do
          local a, b, e = V[tr[1]], V[tr[2]], V[tr[3]]
          local ax, az, ay = a.x * s + 256, a.z * s + 256, a.y * s
          local bx, bz, by = b.x * s + 256, b.z * s + 256, b.y * s
          local ex, ez, ey = e.x * s + 256, e.z * s + 256, e.y * s
          local den = (bz - ez) * (ax - ex) + (ex - bx) * (az - ez)
          if math.abs(den) > 1e-6 then
            local x0 = math.max(0, math.floor((math.min(ax, bx, ex) - 8) / 16))
            local x1 = math.min(31, math.floor((math.max(ax, bx, ex) - 8) / 16) + 1)
            local z0 = math.max(0, math.floor((math.min(az, bz, ez) - 8) / 16))
            local z1 = math.min(31, math.floor((math.max(az, bz, ez) - 8) / 16) + 1)
            for tz = z0, z1 do
              for tx = x0, x1 do
                local t = tz * 32 + tx
                local v = vals[t]
                if v then
                  local px, pz = tx * 16 + 8, tz * 16 + 8
                  local l1 = ((bz - ez) * (px - ex) + (ex - bx) * (pz - ez)) / den
                  local l2 = ((ez - az) * (px - ex) + (ax - ex) * (pz - ez)) / den
                  local l3 = 1 - l1 - l2
                  if l1 >= -1e-4 and l2 >= -1e-4 and l3 >= -1e-4 then
                    local hy = math.floor((l1 * ay + l2 * by + l3 * ey) / 8 + 0.5) * 8
                    local key = t * 65536 + hy
                    if not seen[key] then
                      seen[key] = true
                      here[v] = here[v] or {}
                      here[v][hy] = (here[v][hy] or 0) + 1
                    end
                  end
                end
              end
            end
          end
        end
      end
      -- THE MODEL'S OWN FRAME can sit off the tiles' (a few chunks' models
      -- are drawn a constant height off): where this chunk carries values the
      -- people already pin, the commonest difference is its offset
      local diffs = {}
      for v, ys in pairs(here) do
        -- (not value 0: people stand on it at 0 and at 32 .. 80 alike)
        local p = v ~= 0 and people[v] and mode(people[v])
        if p then for hy, n in pairs(ys) do diffs[p - hy] = (diffs[p - hy] or 0) + n end end
      end
      local offset = mode(diffs) or 0
      for v, ys in pairs(here) do
        ground[v] = ground[v] or {}
        for hy, n in pairs(ys) do ground[v][hy + offset] = (ground[v][hy + offset] or 0) + n end
      end
    end
  end

  local out, report = {}, { people = 0, ground = 0, agree = 0, disagree = 0 }
  local values = {}
  for v in pairs(people) do values[v] = true end
  for v in pairs(ground) do values[v] = true end
  for v in pairs(values) do
    local p = people[v] and mode(people[v])
    local g = ground[v] and mode(ground[v])
    if p and g then
      if p == g then report.agree = report.agree + 1 else report.disagree = report.disagree + 1 end
    end
    if p then out[v] = p; report.people = report.people + 1
    elseif g then out[v] = g; report.ground = report.ground + 1 end
  end
  -- 0 is the floor everywhere it was ever read
  out[0] = 0
  return out, report
end

H.NY = 4095
-- the plane-distance table's signature: index 0 is 0, 14 is 16 units, 120 is
-- 8 and 463 is 48 (exact s32s; see the header)
H.SIGNATURE = { [0] = 0, [14] = -65519, [120] = -32759, [463] = -196559 }
H.OVERLAY = 21

function H.romTable(rom)
  local ok, b = pcall(function() return rom:overlay(H.OVERLAY) end)
  if not ok or type(b) ~= "string" then return nil end
  local function s32(o)
    local a, c, d, e = b:byte(o + 1, o + 4)
    if not e then return nil end
    local v = a + c * 256 + d * 65536 + e * 16777216
    return v >= 2 ^ 31 and v - 2 ^ 32 or v
  end
  for o = 0, #b - 1300 * 4, 4 do
    if s32(o + 14 * 4) == H.SIGNATURE[14] and s32(o) == 0 and s32(o + 120 * 4) == H.SIGNATURE[120]
       and s32(o + 463 * 4) == H.SIGNATURE[463] then
      local out, n = {}, 0
      for i = 0, math.floor((#b - o) / 4) - 1 do
        local d = s32(o + i * 4)
        if d == nil then break end
        out[i] = math.floor(-d / H.NY + 0.5)
        n = n + 1
      end
      return out, { source = ("overlay %d +0x%X"):format(H.OVERLAY, o), entries = n }
    end
  end
  return nil
end

function H.build(rom)
  local t, report = H.romTable(rom)
  if t then return t, report end
  return H.derive(rom)
end

return H
