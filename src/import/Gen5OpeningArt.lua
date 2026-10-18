-- BLACK AND WHITE'S OPENING MOVIES, written as `gen5_opening`.
--
-- WHAT RUNS, FROM THE CARTRIDGE. The boot state machine in the ARM9
-- (0x0202F9F8, Black) is five states:
--
--   0  overlay 88's boot cards (proc 0x021BD8E8)
--   1  overlay 179 in mode 0                      -- the Game Freak logo
--   2  overlay 179 in mode 1, unless the logo was skipped -- the coronation
--   3  overlay 179 in mode 2                      -- "Hopes! Dreams! ..."
--   4  overlay 88's title (proc 0x021BD574)
--
-- Overlay 179 is `cdemo_main.c` (its one string). Each mode runs a small
-- command script and plays a MOVIE: one LZ11 member per frame, a 256-wide
-- RGB555 bitmap (the DS's 15-bit colour, bit 15 opaque), shown at 15 frames a
-- second (the tick sum against 0x1046B = 66,667 microseconds). Per mode, a
-- 12-byte record: u16 archive, u16 frame count, u32 bytes copied, u32 VRAM
-- offset -- so the coronation is 256 x 170 placed 11 lines down (letterboxed)
-- and the other two fill the 192 lines.
--
--   mode 0  /a/2/2/5  151 frames   SEQ_BGM_GF_LOGO (1173)
--   mode 1  /a/1/3/4  670 frames   SEQ_BGM_TITLE   (1003), 80 frames first
--   mode 2  /a/2/2/6  174 frames   SEQ_BGM_TITLE01 (1004)
--
-- The scripts are read from the overlay rather than written here: ops of a
-- size given by the overlay's own table -- 0 wait n, 1 / 2 fade in / out,
-- 5 wait for the fade, 14 play a sequence, 18 play the movie to its end,
-- 20 end (19 is a marker that does nothing).
--
-- The archives are copied into the cache whole (about 26 MB) and decoded a
-- frame at a time as they play (src/ui/Gen5Opening.lua).

local A = {}

A.FPS = 15

local function u16(s, at) local a, b = s:byte(at + 1, at + 2); return b and a + b * 256 end
local function u32(s, at)
  local a, b, c, d = s:byte(at + 1, at + 4)
  return d and a + b * 256 + c * 65536 + d * 16777216
end

-- the overlay whose text says it is cdemo_main.c
function A.findOverlay(rom)
  for id = 0, 400 do
    local ok, ov = pcall(rom.overlay, rom, id)
    if ok and type(ov) == "string" and ov:find("cdemo_main.c", 1, true) then return ov, id end
  end
end

-- parse(ov) -> { records = { [mode] = {archive, frames, bytes, offset} },
--               scripts = { [mode] = { {op, args...}, ... } } }
function A.parse(ov)
  if type(ov) ~= "string" then return nil, "no overlay" end
  local out = { records = {}, scripts = {} }
  -- THE MOVIE RECORDS: three in a row, each a plausible archive and frame
  -- count, then one of the two copy sizes a 256-wide RGB555 picture can have
  for at = 0, #ov - 36, 4 do
    local ok = true
    for m = 0, 2 do
      local arcId, frames, bytes = u16(ov, at + m * 12), u16(ov, at + m * 12 + 2), u32(ov, at + m * 12 + 4)
      if not (arcId and arcId > 0 and arcId < 300 and frames and frames > 0 and frames < 2000
              and bytes and bytes > 0 and bytes <= 0x18000 and bytes % 512 == 0) then ok = false break end
    end
    if ok then
      for m = 0, 2 do
        out.records[m] = {
          archive = u16(ov, at + m * 12), frames = u16(ov, at + m * 12 + 2),
          bytes = u32(ov, at + m * 12 + 4), offset = u32(ov, at + m * 12 + 8),
        }
      end
      break
    end
  end
  -- THE OP SIZES: 21 u32 words (ops 0..20) starting "2, 3, 3, 3" -- op 0 is
  -- `wait n`, two words; ops 1..4 are the fades, three
  local sizeAt = ov:find(string.char(2,0,0,0, 3,0,0,0, 3,0,0,0, 3,0,0,0), 1, true)
  local sizes = {}
  if sizeAt then for op = 0, 20 do sizes[op] = u32(ov, sizeAt - 1 + op * 4) end end
  -- THE SCRIPTS: each opens `1, 1, 1, 5` (fade in, wait) and plays a
  -- sequence (14, n); found in file order and matched to modes by the table of
  -- pointers that names them
  local opener = string.char(1,0,0,0, 1,0,0,0, 1,0,0,0, 5,0,0,0, 14,0,0,0)
  local starts, p = {}, 1
  while true do
    local s = ov:find(opener, p, true)
    if not s then break end
    starts[#starts + 1] = s - 1
    p = s + 4
  end
  local function script(at)
    local list, guard = {}, 0
    while guard < 64 do
      guard = guard + 1
      local op = u32(ov, at)
      if not op then break end
      local size = sizes[op] or 1
      local row = { op = op }
      for k = 1, size - 1 do row[k] = u32(ov, at + k * 4) end
      list[#list + 1] = row
      if op == 20 then break end
      at = at + size * 4
    end
    return list
  end
  -- the pointer table: three words, each the overlay's load address plus one
  -- of the script offsets; the load address is whatever makes all three fit
  for at = 0, #ov - 12, 4 do
    local a, b, c = u32(ov, at), u32(ov, at + 4), u32(ov, at + 8)
    for _, s0 in ipairs(starts) do
      local base = a - s0
      if base > 0x2000000 and base < 0x2400000 then
        local function isStart(v) for _, s in ipairs(starts) do if v - base == s then return true end end end
        if isStart(b) and isStart(c) then
          out.scripts[0], out.scripts[1], out.scripts[2] = script(a - base), script(b - base), script(c - base)
          out.loadAddress = base
          break
        end
      end
    end
    if out.scripts[0] then break end
  end
  out.sizes = sizes
  return out
end

function A.build(x)
  local ov = A.findOverlay(x.rom)
  local parsed, why = A.parse(ov)
  if not (parsed and parsed.records[0]) then return nil, why or "movie records not found" end
  local out = { source = "ROM: overlay 179 (cdemo_main.c) + its movie archives", fps = A.FPS, modes = {} }
  for mode = 0, 2 do
    local r = parsed.records[mode]
    local path = ("/a/%d/%d/%d"):format(math.floor(r.archive / 100), math.floor(r.archive / 10) % 10, r.archive % 10)
    local raw = x.rom:read(path)
    out.modes[mode] = {
      archive = r.archive, frames = r.frames,
      lines = math.floor(r.bytes / 512), top = math.floor(r.offset / 512),
      movie = raw and x:saveBinary(("bw_opening/movie_%d.narc"):format(mode), raw) or nil,
      script = parsed.scripts[mode],
    }
  end
  return out
end

return A
