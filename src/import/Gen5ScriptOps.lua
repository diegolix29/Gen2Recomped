-- BLACK AND WHITE'S SCRIPT COMMAND WIDTHS, DERIVED FROM THE CARTRIDGE'S CODE.
--
-- There is no decompilation of Gen 5's script engine to transcribe a table
-- from, and no published one. So the widths are READ OUT OF THE HANDLERS, the
-- way Gen4ScriptOps' were read out of pokeplatinum's C -- here from the Thumb
-- code itself:
--
--   1. THE TABLE. A run of handler pointers (Thumb, odd addresses, a few null
--      slots for unused commands) in overlay 10: 624 slots, the handlers in
--      overlays 10, 18, 20 and 21.
--   2. THE READERS. A handler takes its operands with small helpers that load
--      the context's script pointer (offset 0x14), read bytes from it and
--      store it back: one reads a halfword (two ldrb), one a word (four).
--      Found by that shape, not by address.
--   3. A COMMAND'S WIDTH is what its handler reads: bytes read inline from the
--      script pointer, plus the width of every function it calls (helpers
--      that wrap a reader -- "a var or a value" -- count through). ONE call
--      deep: 0x1C (run common script <u16>, 0x021595CC in Black) reads one
--      halfword, but the loader it calls reads a script header through a
--      pointer of the same shape, and following it made 0x1C six bytes wide
--      -- swallowing the `pop var` after every common-script call. Stopping
--      at the handler's own callees fixes 0x1B, 0x1C and 0x1D3 and changes
--      no other width (3,233 clean entries against 3,228; 3,349 once tail-jump
--      stubs are followed, 3,360 once a stub's jump may come second -- see
--      `resolve`).
--   4. THE ALIGNMENT. The table's first slot is not opcode 0: decoding every
--      script in /a/0/5/7 at each candidate offset, one offset ends 3,360 of
--      3,383 entry points cleanly (Black) and the next best a third of that.
--      The cartridge's own scripts pick it.
--
-- Checked by tools/gen5_import_check.lua, which also pins the control flow
-- the scripts themselves show: End 0x02 and Return 0x05 take nothing, Call
-- 0x04 and Jump 0x1E a u32, the conditional jump 0x1F a u8 and a u32.

local Ops = {}

Ops.TERMINATORS = { [0x02] = true, [0x05] = true, [0x1E] = true }
Ops.JUMPS = { [0x04] = "call", [0x1E] = "jump", [0x1F] = "if" }

local function u16(s, o) return s:byte(o + 1) + s:byte(o + 2) * 256 end
local function u32(s, o) return u16(s, o) + u16(s, o + 2) * 65536 end

-- segments: every overlay and the ARM9, by RAM address
local function segments(rom)
  local segs = { { b = rom:arm9(), ram = rom:header().arm9.ram, name = "arm9" } }
  for o = 0, 200 do
    local ok, b, info = pcall(function() return rom:overlay(o) end)
    if not ok or not b then if o > 160 then break end else
      segs[#segs + 1] = { b = b, ram = info.ram, name = "ov" .. o, overlay = o }
    end
  end
  return segs
end

-- find the handler table: the longest run of Thumb pointers (nulls allowed)
local function findTable(segs)
  local function isCode(v)
    if v % 2 == 0 then return false end
    for _, s in ipairs(segs) do if v - 1 >= s.ram and v - 1 < s.ram + #s.b then return true end end
    return false
  end
  local best
  for _, s in ipairs(segs) do
    if s.overlay then
      local b, at = s.b, 0
      while at + 4 <= #b do
        local n, good, run = 0, 0, 0
        while at + (n + 1) * 4 <= #b do
          local v = u32(b, at + n * 4)
          if isCode(v) then good = good + 1; run = 0
          elseif v == 0 then run = run + 1; if run > 3 then break end
          else break end
          n = n + 1
        end
        if good >= 250 and good / math.max(n, 1) > 0.9 and (not best or good > best.good) then
          best = { seg = s, at = at, n = n, good = good }
        end
        at = at + (n > 0 and n * 4 or 4)
      end
    end
  end
  return best
end

-- the handler's code. OVERLAYS SHARE ADDRESSES, so the segments are tried in
-- the order `rank` sets: the overlays most of the table's handlers start a
-- function in (10, 21, 20, 18 in Black) ahead of the rest, the ARM9 last --
-- the first match that starts with a push wins.
local function rank(segs, handlers)
  for _, s in ipairs(segs) do
    s.hits = 0
    for _, h in pairs(handlers) do
      local a = h - 1 - s.ram
      if a >= 0 and a + 2 <= #s.b then
        local ins = u16(s.b, a)
        if math.floor(ins / 256) == 0xB5 or math.floor(ins / 256) == 0xB4 then s.hits = s.hits + 1 end
      end
    end
    if not s.overlay then s.hits = -1 end
  end
  table.sort(segs, function(a, b) return a.hits > b.hits end)
end

local function codeAt(segs, addr)
  local fallback
  for _, s in ipairs(segs) do
    local a = addr - s.ram
    if a >= 0 and a + 2 <= #s.b then
      local ins = u16(s.b, a)
      if math.floor(ins / 256) == 0xB5 or math.floor(ins / 256) == 0xB4 then return s.b, a end
      fallback = fallback or { s.b, a }
    end
  end
  if fallback then return fallback[1], fallback[2] end
end

local function isEnd(ins) return ins == 0x4770 or math.floor(ins / 256) == 0xBD end
local function ldrPtr(ins) return math.floor(ins / 2048) == 0x0D and math.floor(ins / 64) % 32 == 5 end
local function strPtr(ins) return math.floor(ins / 2048) == 0x0C and math.floor(ins / 64) % 32 == 5 end
local function ldrb(ins) return math.floor(ins / 2048) == 0x0F end

local function calls(segs, addr)
  local b, a = codeAt(segs, addr)
  local out = {}
  if not b then return out end
  for i = 0, 80 do
    if a + i * 2 + 4 > #b then break end
    local ins = u16(b, a + i * 2)
    if isEnd(ins) then break end
    if math.floor(ins / 2048) == 0x1E then
      local nxt = u16(b, a + i * 2 + 2)
      if math.floor(nxt / 2048) == 0x1F or math.floor(nxt / 2048) == 0x1D then
        local hi = ins % 2048; if hi >= 1024 then hi = hi - 2048 end
        out[#out + 1] = addr + i * 2 + 4 + hi * 4096 + (nxt % 2048) * 2
      end
    end
  end
  return out
end

-- bytes a function reads straight from the script pointer: a handler's own
-- inline reads (the bytes read between loading the pointer and storing it
-- back), and -- for a READER, a function that loads, reads and stores the
-- pointer -- every byte it reads (the word reader stores the pointer back
-- after each byte, so a window would see one of four)
local function inlineBytes(segs, addr, asReader)
  local b, a = codeAt(segs, addr)
  if not b then return 0, false end
  local open, windowed, all, loads, stores = false, 0, 0, 0, 0
  for i = 0, 80 do
    if a + i * 2 + 2 > #b then break end
    local ins = u16(b, a + i * 2)
    if isEnd(ins) then break end
    if ldrPtr(ins) then open = true; loads = loads + 1 end
    if ldrb(ins) then all = all + 1; if open then windowed = windowed + 1 end end
    if strPtr(ins) then open = false; stores = stores + 1 end
  end
  local reader = loads > 0 and stores > 0 and all > 0
  if asReader then return reader and all or 0, reader end
  return windowed, reader
end

-- derive(rom, scripts) -> { widths = { [op] = bytes }, offset, table, report }
function Ops.derive(rom, scriptArchive)
  local segs = segments(rom)
  local tbl = findTable(segs)
  if not tbl then return nil, "no command table" end
  local handlers = {}
  for i = 0, tbl.n - 1 do
    local h = u32(tbl.seg.b, tbl.at + i * 4)
    if h ~= 0 then handlers[i] = h end
  end
  rank(segs, handlers)
  local memo = {}
  local function width(addr, depth)
    if memo[addr] ~= nil then return memo[addr] end
    if depth > 1 then return 0 end
    memo[addr] = 0
    local own, reader = inlineBytes(segs, addr, true)
    local w = own
    if not reader then for _, c in ipairs(calls(segs, addr)) do w = w + width(c, depth + 1) end end
    memo[addr] = w
    return w
  end
  -- A TAIL-JUMP STUB is a handler too: 0x38 and 0x39 are each
  -- `ldr r3, =routine; movs r2, #0 / #1; bx r3` into one message routine that
  -- reads a var-or-value and an inline byte. Without following the jump they
  -- measured 0 bytes and every script using them decoded askew after them
  -- (`38 0025 02, 32, 39` read as `38, 25 0232 0039`).
  local function resolve(addr)
    for _ = 1, 3 do
      local b, a = codeAt(segs, addr)
      if not b then return addr end
      -- the pc-relative load whose register the bx takes: the first
      -- instruction (0x38's `ldr r3; movs r2; bx r3`) or the second -- 0x4D,
      -- 0x4F and 0x50 are `ldr r2, =constant; ldr r3, =routine; bx r3`, and
      -- missing them read 0x4D as six bytes wide and Striaton's Gym's TM
      -- gift decoded askew (`4D 00 019A 0150 01` for 4D/50 and a message)
      local rd, imm, at
      for j = 0, 1 do
        local ij = u16(b, a + j * 2)
        if math.floor(ij / 2048) == 0x09 then                    -- ldr rD, [pc, #imm]
          local r = math.floor(ij / 256) % 8
          for k = j + 1, j + 2 do
            if u16(b, a + k * 2) == 0x4700 + r * 8 then           -- bx rD
              rd, imm, at = r, ij % 256, addr + j * 2
            end
          end
        end
        if rd then break end
      end
      if not rd then return addr end
      local lit = (at + 4) - (at + 4) % 4 + imm * 4
      local lb, la = codeAt(segs, lit)
      if not lb then return addr end
      local target = u32(lb, la)
      if target % 2 == 0 then return addr end
      addr = target - 1
    end
    return addr
  end
  local slots = {}
  for i = 0, tbl.n - 1 do
    local h = u32(tbl.seg.b, tbl.at + i * 4)
    if h ~= 0 then
      local entry = resolve(h - 1)
      local w = inlineBytes(segs, entry)
      for _, c in ipairs(calls(segs, entry)) do w = w + width(c, 1) end
      slots[i] = w
    end
  end
  -- the alignment the scripts themselves choose
  local Script = require("src.import.Gen4Script")
  local files = {}
  for m = 0, scriptArchive.count - 1 do
    local d = scriptArchive:get(m)
    files[#files + 1] = { d = d, e = Script.entries(d) }
  end
  local function score(k)
    local ends, total = 0, 0
    for _, f in ipairs(files) do
      for _, at in ipairs(f.e) do
        total = total + 1
        local pc = at
        for _ = 1, 400 do
          if pc + 1 > #f.d then break end
          local op = f.d:byte(pc) + f.d:byte(pc + 1) * 256
          local w = slots[op + k]
          if not w then break end
          pc = pc + 2 + w
          if Ops.TERMINATORS[op] then ends = ends + 1 break end
        end
      end
    end
    return ends, total
  end
  local bestK, bestS, total, second = 0, -1, 0, -1
  for k = 0, 64 do
    local s, t = score(k)
    total = t
    if s > bestS then second = bestS; bestK, bestS = k, s elseif s > second then second = s end
  end
  local widths = {}
  for i, w in pairs(slots) do if i - bestK >= 0 then widths[i - bestK] = w end end
  -- MEASURED BY HAND where the rule above cannot see: 0xB2 (the menu
  -- opener -- Castelia's elevators, `B2 1F 01 0000 01 8010`) loads and
  -- stores the script pointer itself, so it is taken for a READER and its
  -- two calls are never followed: two u8s, a var-or-value through
  -- 0x2159B10, a u8, and the result var through 0x2011330 -- seven bytes,
  -- not the six its own loads add up to. Six read the elevator askew from
  -- the next op on (`80 CC` for 0x1CC).
  local HAND = { [0xB2] = 7 }
  for op, w in pairs(HAND) do widths[op] = w end
  return { widths = widths, offset = bestK,
           table = { segment = tbl.seg.name, at = tbl.at, slots = tbl.n },
           report = { clean = bestS, entries = total, secondBest = second } }
end

-- handlerTable(rom, derived, op, count) -> { u16 x count } or nil: the
-- table a command's handler indexes through its first pc-relative literal.
-- 0x232 <index, dest> is `dest = TABLE[index]` (`ldr r1, =table; lsls r2,
-- r4, #1; ldrh r1, [r1, r2]`), and the table is the sixteen sprites of
-- Nimbasa's park visitor by season and badges -- read from the handler so
-- White's copy is found the same way as Black's.
function Ops.handlerTable(rom, derived, op, count)
  if not (derived and derived.table) then return nil end
  local segs = segments(rom)
  local tseg
  for _, s in ipairs(segs) do if s.name == derived.table.segment then tseg = s end end
  if not tseg then return nil end
  local h = u32(tseg.b, derived.table.at + (op + derived.offset) * 4)
  if not h or h == 0 then return nil end
  local addr = h - 1
  -- the handler's own segment: try the table's first, then any that holds it
  local order = { tseg }
  for _, s in ipairs(segs) do if s ~= tseg then order[#order + 1] = s end end
  for _, s in ipairs(order) do
    local a = addr - s.ram
    if a >= 0 and a + 64 <= #s.b and math.floor(u16(s.b, a) / 256) == 0xB5 then
      for i = 0, 30 do
        local ins = u16(s.b, a + i * 2)
        if math.floor(ins / 2048) == 0x09 then
          local pc = addr + i * 2
          local lit = (math.floor((pc + 4) / 4) * 4) + (ins % 256) * 4
          local at = u32(s.b, lit - s.ram)
          local off = at and at - s.ram
          if not off or off < 0 or off + count * 2 > #s.b then return nil end
          local out = {}
          for k = 0, count - 1 do out[k] = u16(s.b, off + k * 2) end
          return out
        end
      end
    end
  end
  return nil
end

-- decode(data, at, widths) -> instructions, why it stopped
function Ops.decode(data, at, widths)
  local out, pc = {}, at
  for _ = 1, 2000 do
    if pc + 1 > #data then return out, "overrun" end
    local op = data:byte(pc) + data:byte(pc + 1) * 256
    local w = widths[op]
    if not w then return out, "unknown" end
    local ins = { at = pc, op = op, width = w, operands = data:sub(pc + 2, pc + 1 + w) }
    if Ops.JUMPS[op] and w >= 4 then
      local rel = u32(data, pc + 1 + w - 4)
      if rel >= 2147483648 then rel = rel - 4294967296 end
      ins.target = pc + 2 + w + rel
    end
    out[#out + 1] = ins
    pc = pc + 2 + w
    if Ops.TERMINATORS[op] then return out, "end" end
  end
  return out, "long"
end

return Ops
