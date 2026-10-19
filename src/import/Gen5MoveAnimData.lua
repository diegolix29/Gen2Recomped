-- BLACK AND WHITE'S MOVE ANIMATIONS: the programs, their particles and their
-- effect backgrounds, out of the cartridge.
--
-- WHERE (verified against Black (USA/EUR); research notes in
-- G:/Gen2Recomped/scratch_claude/bwanim/FINDINGS*.txt):
--   /a/0/6/6  601 members; member N is effect N, and effect N < 561 is move N
--             (560..600 are padding copies of member 1)
--   /a/0/6/7  98 shared effects, effect id 561 + i (stat changes, status,
--             the Substitute swap ...), reached by CALL_EFFECT / GOTO_EFFECT
--   /a/0/0/6  733 SPA particle files, the same ' APS' "12_1" format as
--             Platinum's -- so Gen4Particle reads them unchanged
--   /a/0/9/5  the effect backgrounds: 43 (NSCR, NCGR, NCLR) triples from 0,
--             BG_LOAD naming the NSCR member
--
-- ONE MEMBER: u32 seqCount; u32 offset[seqCount][14] (one per MCSS position,
-- all fourteen equal in every sequence the cartridge ships); then bytecode,
-- 2-byte aligned: u16 opcode and WIDTHS[opcode] u32 operands. The VM is the
-- GFL VMCMD in arm9 with the opcode table in overlay 94 (btlv_effvm.c).
-- Every one of the 741 sequences walks exactly to the next one with these
-- widths, which is what fixes them (the closure check in the research).
--
-- The programs are stored decoded -- one array per instruction, `{op, a1,
-- a2, ...}` -- with each relative jump resolved to the INDEX of the
-- instruction it lands on (`to`), because a byte offset means nothing once
-- the bytes are gone.

local Narc = require("src.import.NarcArchive")

local M = {}

M.PROGRAMS = "/a/0/6/6"
M.SHARED = "/a/0/6/7"
M.PARTICLES = "/a/0/0/6"
M.BACKGROUNDS = "/a/0/9/5"
M.SHARED_BASE = 0x231          -- 561: effect ids from here load /a/0/6/7
M.MOVE_LAST = 559
M.BG_TRIPLES = 43

M.WIDTHS = { [0] =
  5, 10, 6, 6, 2, 0, 1, 11, 15, 11,
  10, 1, 11, 13, 11, 13, 10, 10, 7, 9,
  6, 7, 6, 6, 6, 4, 2, 5, 2, 2,
  7, 1, 5, 8, 2, 1, 1, 6, 4, 5,
  1, 6, 5, 2, 7, 7, 7, 7, 2, 5,
  1, 2, 9, 1, 8, 9, 1, 1, 1, 4,
  4, 3, 1, 1, 2, 3, 0, 7, 1, 6,
  3, 0, 1, 0, 1, 1, 1, 0,
}
-- which operand of a jump is the byte offset (from the END of the instruction)
M.RELJUMP = { [59] = 4, [60] = 4, [61] = 3, [72] = 1 }
M.TERMINATOR = { [71] = true, [72] = true, [74] = true, [77] = true }

local byte = string.byte
local function u16(s, at) local a, b = byte(s, at + 1, at + 2); return (a or 0) + (b or 0) * 256 end
local function u32(s, at)
  local a, b, c, d = byte(s, at + 1, at + 4)
  return (a or 0) + (b or 0) * 256 + (c or 0) * 65536 + (d or 0) * 16777216
end
local function s32(v) if v >= 0x80000000 then return v - 0x100000000 end return v end

-- decode(bytes) -> { code = { {op, ...} }, to = { [i] = target index },
--                    seq = { [s] = first instruction index } } or nil, why
function M.decode(data)
  if type(data) ~= "string" or #data < 4 then return nil, "too short" end
  local n = u32(data, 0)
  if n < 1 or n > 16 or 4 + n * 56 > #data then return nil, "bad sequence count" end
  local starts, sorted, seen = {}, {}, {}
  for s = 0, n - 1 do
    local st = u32(data, 4 + s * 56)
    starts[s] = st
    if not seen[st] then seen[st] = true; sorted[#sorted + 1] = st end
  end
  table.sort(sorted)
  local code, at, index, ends = {}, {}, {}, {}
  for k, st in ipairs(sorted) do
    local stop = sorted[k + 1] or #data
    local p = st
    while p + 2 <= stop do
      local op = u16(data, p)
      local w = M.WIDTHS[op]
      if not w then break end
      if p + 2 + 4 * w > stop then break end
      local ins = { op }
      for j = 1, w do ins[j + 1] = s32(u32(data, p + 2 + 4 * (j - 1))) end
      code[#code + 1] = ins
      at[#code] = p
      index[p] = #code
      p = p + 2 + 4 * w
      ends[#code] = p
      if M.TERMINATOR[op] and (stop - p) < 4 then break end
    end
  end
  local to = {}
  for i, ins in ipairs(code) do
    local k = M.RELJUMP[ins[1]]
    if k then
      local target = ends[i] + (ins[k + 1] or 0)
      to[i] = index[target] or (#code + 1)
    end
  end
  local seq = {}
  for s = 0, n - 1 do seq[s] = index[starts[s]] or 1 end
  return { code = code, to = to, seq = seq, count = n }
end

local function members(rom, path)
  local raw = rom and rom:read(path)
  return raw and Narc.parse(raw) or nil
end

-- programs(rom) -> { [effectId] = decoded }, count
function M.programs(rom)
  local out, n = {}, 0
  local a = members(rom, M.PROGRAMS)
  if a then
    for i = 0, math.min(M.MOVE_LAST, a.count - 1) do
      local d = M.decode(a:get(i))
      if d then out[i] = d; n = n + 1 end
    end
  end
  local b = members(rom, M.SHARED)
  if b then
    for i = 0, b.count - 1 do
      local d = M.decode(b:get(i))
      if d then out[M.SHARED_BASE + i] = d; n = n + 1 end
    end
  end
  return out, n
end

-- Every SPA a program names, plus the type-remapped neighbours of the six ids
-- PARTICLE_LOAD offsets by a type (3, 29, 46-49 + 1..25; 0x021FE38C).
function M.particleIds(programs, spaCount)
  local want = {}
  for _, prog in pairs(programs) do
    for _, ins in ipairs(prog.code) do
      if ins[1] == 6 then want[ins[2]] = true end
    end
  end
  for _, base in ipairs({ 3, 29, 46, 47, 48, 49 }) do
    for k = 0, 25 do want[base + k] = true end
  end
  local list = {}
  for id in pairs(want) do
    if id >= 0 and id < (spaCount or 733) then list[#list + 1] = id end
  end
  table.sort(list)
  return list
end

function M.backgroundIds(programs)
  local want, list = {}, {}
  for _, prog in pairs(programs) do
    for _, ins in ipairs(prog.code) do
      if ins[1] == 36 then want[ins[2]] = true end
    end
  end
  for id in pairs(want) do list[#list + 1] = id end
  table.sort(list)
  return list
end

-- compose one effect background: NSCR id, NCGR id + 1, NCLR id + 2. A
-- sixteen-colour palette lands in the sub-palette the tilemap's cells name.
function M.composeBackground(arc, id)
  local G = require("src.import.Gen4Graphics")
  local function member(i)
    local b = arc:get(i)
    if b and G.isCompressed(b) then b = G.decompress(b) end
    return b
  end
  local map = G.tilemap(member(id))
  local sheet = G.tiles(member(id + 1))
  local palette = G.palette(member(id + 2))
  if not (map and sheet and palette) then return nil end
  if #palette <= 16 then
    local slot = 0
    for _, c in ipairs(map.cells or {}) do
      if c.palette and c.palette > 0 then slot = c.palette; break end
    end
    if slot > 0 then palette = G.paletteAtSlot(palette, slot) end
  end
  return G.compose(map, sheet, palette)
end

-- The work both routes share. `save(name, image, extra)` -> entry or nil.
local function collect(rom, save, progress)
  local programs, count = M.programs(rom)
  local P = require("src.import.Gen4Particle")
  local fx = { effects = {}, skipped = {}, textures = 0 }
  local spa = members(rom, M.PARTICLES)
  if spa then
    local ids = M.particleIds(programs, spa.count)
    for k, id in ipairs(ids) do
      local data = spa:get(id)
      local list = data and P.textures(data)
      local emitters = data and P.emitters(data)
      if list or emitters then
        local entry = { textures = {}, emitters = emitters or nil }
        for i, texture in ipairs(list or {}) do
          local img = P.rgba(texture)
          local saved = img and save(("particle5/spa_%03d_%d"):format(id, i - 1), img, {
            flipS = texture.flipS or nil, flipT = texture.flipT or nil,
          })
          if saved then
            entry.textures[#entry.textures + 1] = saved
            fx.textures = fx.textures + 1
          end
        end
        fx.effects["spa_" .. id] = entry
      else
        fx.skipped[#fx.skipped + 1] = id
      end
      if progress then progress(k, #ids) end
    end
  end
  local bgs = {}
  local bgArc = members(rom, M.BACKGROUNDS)
  if bgArc then
    for _, id in ipairs(M.backgroundIds(programs)) do
      local ok, img = pcall(M.composeBackground, bgArc, id)
      local saved = ok and img and save(("battle5/effect_bg_%03d"):format(id), img, {})
      if saved then bgs[id] = saved end
    end
  end
  return {
    programs = programs, count = count, backgrounds = bgs,
    source = "ROM:" .. M.PROGRAMS .. " + " .. M.SHARED .. " (BW effect VM)",
  }, fx
end

-- build(x) -> anims, particles  (the import stage; x is RomExtractorGen5)
function M.build(x)
  return collect(x.rom, function(name, image, extra) return x:saveImage(name, image, extra) end)
end

-- runtime(rom) -> the `gen5_move_anims` record with in-memory images, for a
-- harness holding the cartridge (no cache write). Images ride as `image`.
function M.runtime(rom)
  local anims, fx = collect(rom, function(_, image, extra)
    local okD, data = pcall(love.image.newImageData, image.width, image.height, "rgba8", image.rgba)
    if not okD then return nil end
    local img = love.graphics.newImage(data)
    img:setFilter("nearest", "nearest")
    local entry = { image = img, width = image.width, height = image.height }
    for k, v in pairs(extra or {}) do entry[k] = v end
    return entry
  end)
  anims.particles = fx
  return anims
end

return M
