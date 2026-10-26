-- HEARTGOLD / SOULSILVER POKeATHLON DATA.
--
-- gen4_hgss_performance: /a/1/6/9 (poketool/personal/performance.narc), one
-- 20-byte PokeathlonBasePerformance per member -- base[5], 4 unused,
-- minmax[5][2], 1 unused, ARCPERF order -- kept as its bytes, indexed from 0
-- by member (src/pokemon/HgssPokeathlonPerformance.lua reads them).
--
-- gen4_hgss_pokeathlon: the course app's tables out of overlay 96 (found by
-- the Speed Course's row, which is unique there):
--   courses[0..9]   ov96_0221A934, four event ids a course (10 = none): the
--                   five single courses (Speed, Power, Skill, Stamina, Jump,
--                   three events each) then the five link courses
--   master[0..9]    ov96_0221A95C, the Master Course's ten lineups
--   opponents[1..100]  the computer teams (/a/2/5/8): species x3, name (bank
--                   310), group; a single course c picks three of 5c+1..5c+5
--                   (the Master Course 26-50, the Supreme Cup +50)
-- Event ids are bank 313's order from #20: 0 Hurdle Dash, 1 Pennant Capture,
-- 2 Circle Push, 3 Block Smash, 4 Disc Catch, 5 Lamp Jump, 6 Relay Run,
-- 7 Ring Drop, 8 Snow Throw, 9 Goal Roll.

local M = {}

M.PATH = "/a/1/6/9"

function M.performance(rom)
  local raw = rom and rom:read(M.PATH)
  local narc = raw and require("src.import.NarcArchive").parse(raw)
  if not narc then return nil end
  local out = {}
  for i = 0, narc.count - 1 do
    local b = narc:get(i)
    if b and #b >= 20 then
      local row = {}
      for k = 1, 20 do row[k] = b:byte(k) end
      out[i] = row
    end
  end
  return out
end

M.COURSE_SIG = string.char(0, 1, 6, 10, 3, 2, 9, 10, 8, 9, 1, 10, 7, 6, 3, 10, 5, 4, 0, 10)

function M.courses(rom)
  local ov = rom and rom.overlay and rom:overlay(96)
  local at = ov and ov:find(M.COURSE_SIG, 1, true)
  if not at or ov:find(M.COURSE_SIG, at + 1, true) then return nil end
  local function sets(base)
    local out = {}
    for c = 0, 9 do
      local row = {}
      for e = 0, 3 do
        local id = ov:byte(base + c * 4 + e)
        if id ~= 10 then row[#row + 1] = id end
      end
      out[c] = row
    end
    return out
  end
  local out = { courses = sets(at), master = sets(at + 40) }
  out.opponents = M.opponents(rom)
  return out
end

-- the computer teams (ov96_021E8484): NARC 260 = /a/2/5/8, 100 x 8 bytes --
-- three species (u16), the name (bank 310 entry), a group byte -- `[1..100]`
function M.opponents(rom)
  local raw = rom and rom:read("/a/2/5/8")
  local narc = raw and require("src.import.NarcArchive").parse(raw)
  if not narc then return nil end
  local out = {}
  for i = 0, narc.count - 1 do
    local b = narc:get(i)
    if b and #b >= 8 then
      out[i + 1] = { species = { b:byte(1) + b:byte(2) * 256, b:byte(3) + b:byte(4) * 256, b:byte(5) + b:byte(6) * 256 },
                     name = b:byte(7), group = b:byte(8) }
    end
  end
  return out
end

function M.build(x)
  return M.performance(x.rom)
end

-- the course tables (a second module: gen4_hgss_pokeathlon)
function M.buildCourses(x)
  return M.courses(x.rom)
end

return M
