-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- PLATINUM LIGHTS ITS WORLD, AND THIS PORT WAS DRAWING IT UNLIT.
--
-- Reported from play as "still seems to be flat 2d", with a side-by-side against
-- the cartridge. The geometry was not the whole story: the port's Twinleaf is a
-- BRIGHT SATURATED GREEN with a YELLOW path and the cartridge's is a muted olive
-- with a warm ORANGE-BROWN one. Same textures, different light -- and the port
-- was applying none.
--
-- `/data/arealight.narc` holds FOUR members, and `AREA_LIGHT_FILE_COUNT` is 4:
-- the member is chosen by the map header's own `lighting` byte, which
-- `Gen4MapHeaders` has parsed and `gen4_terrain`'s `maps` table has carried on
-- all 593 maps since the terrain stage was written. Nothing has ever read it.
--
-- IT IS A TEXT FILE. `AreaLightTemplate_New` walks it with
-- `Ascii_CopyToTerminator(iter, buf, '\r')` and `Ascii_ConvertToInt`, so every
-- value is decimal ASCII and every line ends in a bare CR. Ten lines per
-- template, and the tenth is blank:
--
--     <endTime>,
--     <valid>,<r>,<g>,<b>,<vx>,<vy>,<vz>,      light 0
--     <valid>,<r>,<g>,<b>,<vx>,<vy>,<vz>,      light 1
--     <valid>,<r>,<g>,<b>,<vx>,<vy>,<vz>,      light 2
--     <valid>,<r>,<g>,<b>,<vx>,<vy>,<vz>,      light 3
--     <r>,<g>,<b>,                             diffuse reflection
--     <r>,<g>,<b>,                             ambient reflection
--     <r>,<g>,<b>,                             specular reflection
--     <r>,<g>,<b>,                             emission
--     (blank)
--
-- and the file ends with a line beginning `EOF`. GX_LIGHTS_COUNT is 4, which is
-- why there are exactly four light lines; a light whose first field is 0 is OFF
-- and the cartridge zeroes its colour and vector rather than leaving them.
--
-- `endTime` IS SECONDS SINCE MIDNIGHT OVER TWO, not a frame count or an index:
-- `GetSecondsSinceMidnight() / 2` is what it is compared against. So the 0, 7200,
-- 8100, 9000, 14400, 20700, 21600 in member 0 are midnight, 4:00, 4:30, 5:00,
-- 8:00, 11:30 and 12:00 -- the cartridge's own dawn ramp. The ACTIVE template is
-- the first whose endTime is past the current time, and the manager re-checks it
-- as the clock moves.
--
-- COLOUR CHANNELS ARE 0..31, the DS's five bits, and `GX_RGB` packs them. The
-- REFLECTION rows are the same five-bit scale. Member 0's first template lights
-- the world at 11,11,16 of 31 with an ambient of 10,10,10 -- ABOUT A THIRD
-- BRIGHTNESS, and slightly blue. That single row is most of the difference
-- between the two screenshots.
--
-- VECTORS ARE fx16, clamped to +-FX16_ONE (4096) by the cartridge on each axis.
-- Kept raw AND as a unit triple, because a renderer wants the direction and a
-- check wants the number that was in the file.

local Gen4AreaLight = {}

local floor = math.floor

Gen4AreaLight.PATH = "/data/arealight.narc"
-- AREA_LIGHT_FILE_COUNT, and the range the `lighting` byte is asserted against.
Gen4AreaLight.FILE_COUNT = 4
-- GX_LIGHTS_COUNT.
Gen4AreaLight.LIGHTS = 4
-- FX16_ONE, the clamp on every vector axis.
Gen4AreaLight.FX16_ONE = 4096
-- The five-bit channel the cartridge's colours are on.
Gen4AreaLight.CHANNEL_MAX = 31
-- `endTime` is halved seconds, so a day is 86400/2.
Gen4AreaLight.DAY_TICKS = 43200

-- The lines of one member, with the trailing blank kept: the blank line is part
-- of a template's ten and dropping it renumbers everything after the first one.
--
-- THE FILE IS CRLF, NOT BARE CR, AND THAT COSTS A LINE IF YOU MISS IT.
-- `Ascii_CopyToTerminator` looks past the terminator it stopped on:
--
--     if (terminator == '\r' && src[i + 1] == '\n') return &src[i + 2];
--
-- so the cartridge swallows the LF and its line buffers never carry one. A split
-- on CR alone leaves that LF on the FRONT of every line after the first, which
-- `tonumber` happens to tolerate and the `EOF` test does NOT -- `("\nEOF"):sub(1,3)`
-- is not "EOF", so the terminator is read as a sixteenth template and the whole
-- member is rejected. That is exactly how members 1 and 3 failed to parse.
local function lines(text)
  local out = {}
  for piece in tostring(text or ""):gmatch("([^\r]*)\r") do
    out[#out + 1] = (piece:gsub("^\n", ""))
  end
  return out
end

-- `Ascii_ConvertToInt` on each comma-separated field. Trailing empties are
-- dropped because every line ends in a comma, which would otherwise add a field.
local function fields(line)
  local out = {}
  for piece in tostring(line or ""):gmatch("([^,]*),") do
    out[#out + 1] = tonumber(piece) or 0
  end
  return out
end

-- GX_RGB: five bits a channel, red low. The validity test is on this PACKED
-- value and not on the line's leading field, so it matters that GX_RGB(31,31,31)
-- is 0x7FFF -- a full-white light is VALID, and only bit 15 makes 0xFFFF.
function Gen4AreaLight.packRgb(r, g, b)
  return (r % 32) + (g % 32) * 32 + (b % 32) * 1024
end

-- INVALID_LIGHT_COLOR. `ParseLightAttrs` writes it into the colour when the
-- line's first field is not exactly 1, and the caller turns that into a cleared
-- `validLightsMask` bit plus a black colour.
Gen4AreaLight.INVALID_COLOUR = 0xFFFF

local function clampAxis(v)
  local one = Gen4AreaLight.FX16_ONE
  if v > one then return one end
  if v < -one then return -one end
  return v
end

-- parse(bytes) -> { templates }, or nil plus a reason.
function Gen4AreaLight.parse(bytes)
  if type(bytes) ~= "string" or #bytes == 0 then
    return nil, "area light member is empty"
  end
  local ls = lines(bytes)
  local out, at = {}, 1
  while at <= #ls do
    local head = ls[at]
    -- The cartridge's own stop condition, and it is a PREFIX test rather than an
    -- equality one: `lineBuffer[0]=='E' && [1]=='O' && [2]=='F'`.
    if head:sub(1, 3) == "EOF" then break end
    if at + 8 > #ls then
      return nil, ("template %d is short: %d lines left"):format(#out + 1, #ls - at)
    end
    local template = {
      endTime = fields(head)[1] or 0,
      lights = {},
      validMask = 0,
    }
    for i = 1, Gen4AreaLight.LIGHTS do
      local f = fields(ls[at + i])
      -- `if (lightValid == TRUE)`, and TRUE is 1: not "non-zero".
      if (f[1] or 0) == 1 then
        local x, y, z = clampAxis(f[5] or 0), clampAxis(f[6] or 0), clampAxis(f[7] or 0)
        template.lights[i] = {
          index = i - 1,
          colour = { f[2] or 0, f[3] or 0, f[4] or 0 },
          vector = { x, y, z },
          -- ...and the same direction as a unit triple, for a renderer that
          -- wants to dot it against a normal without knowing what fx16 is.
          unit = { x / Gen4AreaLight.FX16_ONE,
                   y / Gen4AreaLight.FX16_ONE,
                   z / Gen4AreaLight.FX16_ONE },
          packed = Gen4AreaLight.packRgb(f[2] or 0, f[3] or 0, f[4] or 0),
        }
        -- ...and the cartridge's own `validLightsMask`, so a check can assert the
        -- bitmask rather than the table's shape.
        template.validMask = template.validMask + 2 ^ (i - 1)
      end
    end
    -- THE FOUR REFLECTION ROWS, in the order `ApplyToModelAttributes` sets them.
    local function colourAt(n)
      local f = fields(ls[at + n])
      return { f[1] or 0, f[2] or 0, f[3] or 0 }
    end
    template.diffuse  = colourAt(5)
    template.ambient  = colourAt(6)
    template.specular = colourAt(7)
    template.emission = colourAt(8)
    out[#out + 1] = template
    at = at + 10
  end
  if #out == 0 then return nil, "no templates in this member" end
  return out
end

-- all(archive) -> { [member] = { templates } }, plus the count read.
function Gen4AreaLight.all(archive)
  local out, read = {}, 0
  for m = 0, (archive and archive.count or 0) - 1 do
    local parsed = Gen4AreaLight.parse(archive:get(m))
    if parsed then out[m] = parsed; read = read + 1 end
  end
  return out, read
end

-- WHICH TEMPLATE IS LIVE AT A GIVEN TIME.
--
-- `AreaLightManager_New` takes the FIRST template whose endTime is past the
-- clock, and falls back to index 0 when none is -- which is what makes the last
-- band wrap around midnight rather than leaving a gap.
function Gen4AreaLight.activeAt(templates, halfSeconds)
  if type(templates) ~= "table" or #templates == 0 then return nil end
  local t = tonumber(halfSeconds) or 0
  for i = 1, #templates do
    if templates[i].endTime > t then return templates[i], i end
  end
  return templates[1], 1
end

-- A WALL CLOCK IN THE UNITS `endTime` IS IN, which is half-seconds and nothing
-- else in this port speaks.
--
-- Public, and pulled out of `activeAtClock` rather than left inline, for the
-- reason `activeAtClock` itself gives about the band rule: `Gen4Shade.nightness`
-- needs this same number to walk the same table, and two spellings of it is how
-- the two drift.
function Gen4AreaLight.clockTime(hour, minute)
  local h = tonumber(hour) or 0
  local m = tonumber(minute) or 0
  return floor((h * 3600 + m * 60) / 2)
end

-- ...and the same question from a wall clock.
function Gen4AreaLight.activeAtClock(templates, hour, minute)
  return Gen4AreaLight.activeAt(templates, Gen4AreaLight.clockTime(hour, minute))
end

-- THE PER-LIGHT DIFFUSE WEIGHT, WHICH IS PURE GEOMETRY AND NOTHING ELSE.
--
-- `max(0, -N . L)` per enabled light. This is the one part of the DS's lighting
-- that follows from the extracted vectors alone, so it is the one part this file
-- will state. Returns a table keyed by the same 1..4 slot as `lights`.
--
-- N IS Y-UP. Light 0's vector is dominated by y = -3600 of 4096, a sun pointing
-- DOWN, and -N.L against (0,1,0) makes that +0.879 -- a strongly lit ground. Any
-- other axis convention leaves the cartridge's own sun lighting nothing, which is
-- how the convention was settled rather than assumed.
--
-- WHAT THIS FILE DELIBERATELY DOES NOT DO IS COMBINE THE TERMS.
-- The obvious next step is `diffuse * lightColour * lambert + ambient *
-- lightColour + emission`, and I wrote it, measured it, and took it back out:
-- summed over member 0 it pinned THIRTEEN OF FIFTEEN templates to exactly 1.000
-- on every channel, so it reported full brightness for almost the whole day and
-- could not have told a dawn from a noon. A measurement that cannot fail says
-- nothing, and a renderer tint that cannot vary is worse than none.
--
-- The reason it saturates is a real open question and not a coding slip: light 3
-- is full white 31,31,31 in every one of member 0's templates, the emission row
-- is another 0.45 of full on its own, and `AreaLight_UseGlobalModelAttributes`
-- switches the model onto GLOBAL diffuse/ambient/specular/emission
-- (`NNS_G3dMdlUseGlbDiff` and its three siblings), so how much of each row
-- actually reaches an area's ground is a property of the model resource rather
-- than of this file. Settling it needs a frame compared against the cartridge.
-- Until then the extractor's job is to land the cartridge's own numbers exactly,
-- and the lighting equation belongs to whoever owns the ground renderer.
function Gen4AreaLight.lambert(template, nx, ny, nz)
  local out = {}
  if type(template) ~= "table" then return out end
  nx, ny, nz = tonumber(nx) or 0, tonumber(ny) or 1, tonumber(nz) or 0
  for slot, light in pairs(template.lights or {}) do
    local u = light.unit
    local v = -(nx * u[1] + ny * u[2] + nz * u[3])
    if v < 0 then v = 0 end
    out[slot] = v
  end
  return out
end

return Gen4AreaLight
