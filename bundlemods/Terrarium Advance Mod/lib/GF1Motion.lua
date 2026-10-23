-- GF1Motion: Game Freak's XY / Omega Ruby / Alpha Sapphire skeletal motion
-- packs -- part 0 of a Pokemon's battle-motion member in a/0/0/8 (see
-- lib/ORASActorCache.lua).  Layout per SPICA (SPICA/Formats/GFL:
-- GF1MotionPack, GF1MotBone, GF1Motion), checked against the player's dump:
-- every decoded motion ends on exactly the byte the next one starts at.
--
--   pack      u32 slot count, then u32 addresses (relative to the pack) per
--             slot; slot 0 is the skeleton, slot i >= 1 is motion i - 1 (0
--             = empty).  Battle slots: 0 idle (ba10_waitA), 1 idle B,
--             3-5 landing, 8 physical (ba20_buturi), 12 special
--             (ba21_tokusyu), 16 damage (ba30_damageS), 17 faint (ba41_down).
--   skeleton  u8 bone count, u8 (unused); per bone 1..n-1: parent u8, flags
--             u8, child count u8; then their NUL-terminated names; align 4;
--             then per bone 0..n-1: translation (3 floats) + quaternion (4).
--             Bone 0 is an implicit "Origin".
--   motion    u16 channel-code count, u16 frame count; 3-bit channel codes
--             packed eight to a 24-bit little-endian word; keyframe lists
--             (u8 frames, or u16 when frame count > 255, after a pad to even)
--             for every code 6/7, each implicitly opened by 0 and closed by
--             the frame count; align 4; then the values.  Codes from index 2
--             on walk channels nine per bone (translation xyz, rotation xyz
--             in radians, scale xyz): 0 zero, 1 skip three channels, 2 +pi/2,
--             3 pi, 4 -pi/2, 5 one constant float, 6 one float per key
--             (linear), 7 value + slope per key (Hermite, slope per 30
--             frames).

local V = ...
local BCH = V.require("BCH")

local M = {}

local f32 = BCH.f32
local function u16(s, p) local a, b = s:byte(p, p + 1); return a + b * 256 end
local function u32(s, p)
  local a, b, c, d = s:byte(p, p + 3)
  return a + b * 256 + c * 65536 + d * 16777216
end
local function F(s, at) return f32(u32(s, at + 1)) end
local function align4(n) return math.ceil(n / 4) * 4 end

-- `at` is a 0-based offset into `s`
function M.readSkeleton(s, at)
  local n = s:byte(at + 1)
  local p = at + 2
  local bones = { { name = "Origin", parent = -1, flags = 0 } }
  for i = 1, n - 1 do
    bones[i + 1] = { parent = s:byte(p + 1), flags = s:byte(p + 2) }
    p = p + 3
  end
  for i = 1, n - 1 do
    local stop = s:find("\0", p + 1, true)
    bones[i + 1].name = s:sub(p + 1, stop - 1)
    p = stop
  end
  p = align4(p)
  for i = 1, n do
    bones[i].translation = { F(s, p), F(s, p + 4), F(s, p + 8) }
    p = p + 28
  end
  return bones
end

-- curves[bone * 9 + channel] = { kind = "const"|"lin"|"herm", value | keys }
function M.readMotion(s, at)
  local p = at
  local count, frames = u16(s, p + 1), u16(s, p + 3)
  p = p + 4
  local codes, cur = {}, 0
  for i = 0, count - 1 do
    if i % 8 == 0 then
      cur = s:byte(p + 1) + s:byte(p + 2) * 256 + s:byte(p + 3) * 65536
      p = p + 3
    end
    codes[i] = cur % 8
    cur = math.floor(cur / 8)
  end
  local wide = frames > 0xFF
  local lists = {}
  local listCount = 0
  for i = 0, count - 1 do if codes[i] > 5 then listCount = listCount + 1 end end
  if wide and p % 2 == 1 then p = p + 1 end
  for k = 1, listCount do
    local n
    if wide then n = u16(s, p + 1); p = p + 2 else n = s:byte(p + 1); p = p + 1 end
    local keys = { 0 }
    for _ = 1, n do
      if wide then keys[#keys + 1] = u16(s, p + 1); p = p + 2
      else keys[#keys + 1] = s:byte(p + 1); p = p + 1 end
    end
    keys[#keys + 1] = frames
    lists[k] = keys
  end
  p = align4(p)

  local curves, elem, list = {}, 0, 0
  for i = 2, count - 1 do
    local c = codes[i]
    if c == 1 then
      elem = elem + 3
    else
      local key = elem
      if c == 0 then curves[key] = { kind = "const", value = 0 }
      elseif c == 2 then curves[key] = { kind = "const", value = math.pi / 2 }
      elseif c == 3 then curves[key] = { kind = "const", value = math.pi }
      elseif c == 4 then curves[key] = { kind = "const", value = -math.pi / 2 }
      elseif c == 5 then curves[key] = { kind = "const", value = F(s, p) }; p = p + 4
      else
        list = list + 1
        local keys, out = lists[list], {}
        for k, f in ipairs(keys) do
          if c == 6 then out[k] = { f, F(s, p) }; p = p + 4
          else out[k] = { f, F(s, p), F(s, p + 4) }; p = p + 8 end
        end
        curves[key] = { kind = c == 6 and "lin" or "herm", keys = out }
      end
      elem = elem + 1
    end
  end
  return { frames = frames, curves = curves, finish = p }
end

function M.sample(curve, f)
  if curve.kind == "const" then return curve.value end
  local keys = curve.keys
  if f <= keys[1][1] then return keys[1][2] end
  for k = 1, #keys - 1 do
    local a, b = keys[k], keys[k + 1]
    if f <= b[1] then
      local d = b[1] - a[1]
      if d <= 0 then return b[2] end
      local t = (f - a[1]) / d
      if curve.kind == "lin" then return a[2] + (b[2] - a[2]) * t end
      local t2, t3 = t * t, t * t * t
      return (2 * t3 - 3 * t2 + 1) * a[2] + (t3 - 2 * t2 + t) * d * a[3] / 30
           + (-2 * t3 + 3 * t2) * b[2] + (t3 - t2) * d * b[3] / 30
    end
  end
  return keys[#keys][2]
end

-- pack bytes -> skeleton, { [slot] = motion }
function M.readPack(s)
  local slots = u32(s, 1)
  local skeleton = M.readSkeleton(s, u32(s, 5))
  local motions = {}
  for i = 1, slots - 1 do
    local at = u32(s, 5 + i * 4)
    if at > 0 then motions[i - 1] = M.readMotion(s, at) end
  end
  return skeleton, motions
end

return M
