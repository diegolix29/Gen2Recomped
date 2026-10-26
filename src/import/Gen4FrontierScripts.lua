-- PLATINUM'S BATTLE FRONTIER SCENE SCRIPTS (/frontier/script/fr_script.narc,
-- run by overlay104's own script engine -- FrontierScriptContext and the 204
-- FrontierScrCmd_* in frscrcmd.c -- not the field engine).
--
-- Eleven members, in res/field/frontier_scripts/fr_script.order:
--   0 Battle Castle   1 Battle Factory   2 Battle Arcade   3 Battle Hall
--   4, 5 unused       6 Tower corridor   7 Tower multi corridor
--   8 Tower battle room   9 Tower multi battle room   10 Wi-Fi selector
--
-- A member opens with its entry points -- u32 `name - 4`, absolute offsets
-- once 4 is added back -- closed by u16 0xFD13. The byte code is a u16
-- opcode and the operands Gen4FrontierCommands names. Decoded the way the
-- field scripts are: from every entry point and every jump target, each
-- block running to its end, goto, return, changescript or exitfrontier.
--
-- Four commands point at DATA rather than code, and that is decoded too,
-- since a scene cannot be set up without it:
--   22  sprite resources to load   { u16 gfx, u8 }                ... FD13
--   24  the scene's objects        { u16 id, u16 gfx, u8 dir, u16 x, u16 y,
--                                    u8, u8 [, u8 netID if gfx == EEEF] } ... FD13
--   2A  frontier_obj sprites        { u16 id }                     ... FD13
--   2C  their placement             { u16 id, u16 x, u16 y, u16 draw, u8, u8 } ... FD13
-- and ApplyMovement's lists are { u16 code, u16 count } up to END_MOVEMENT.
--
-- Written to the cache as `gen4_frontier_scripts`:
--   { members = { [m] = { entries = { offsets }, blocks = { [label] =
--     { at, instructions = { { name, args = {...}, at } } } },
--     movements = { [label] = { {code, count} } },
--     data = { [label] = { kind, rows = {...} } } } } }
-- with labels "F<member>/<offset hex>".

local C = require("src.import.Gen4FrontierCommands")

local M = {}

M.NARC = "/frontier/script/fr_script.narc"
M.MEMBERS = { [0] = "battle_castle", "battle_factory", "battle_arcade", "battle_hall", "unused_04",
              "unused_05", "battle_tower_corridor", "battle_tower_corridor_multi",
              "battle_tower_battle_room", "battle_tower_multi_battle_room", "wfc_facility_selector" }
M.END_OPS = { ["end"] = true, exitfrontier = true, changescript = true, ["goto"] = true, ["return"] = true }

local END_MOVEMENT
for code, name in pairs(C.movements) do if name == "end_movement" then END_MOVEMENT = code end end
M.END_MOVEMENT = END_MOVEMENT

function M.label(member, at) return ("F%d/%04X"):format(member, at) end

local function u8(b, at) return b:byte(at + 1) end
local function u16(b, at) return b:byte(at + 1) + b:byte(at + 2) * 256 end
local function u32(b, at) return u16(b, at) + u16(b, at + 2) * 65536 end
local function s32(b, at)
  local v = u32(b, at)
  if v >= 0x80000000 then v = v - 0x100000000 end
  return v
end

-- the data a pointer names, by the command that names it
local function readData(b, at, op)
  local rows, guard = {}, 0
  while at + 1 < #b and guard < 64 do
    guard = guard + 1
    local first = u16(b, at)
    if first == C.SCRIPT_ENTRY_END then break end
    if op == "22" then
      rows[#rows + 1] = { gfx = first, b = u8(b, at + 2) }
      at = at + 3
    elseif op == "24" then
      local r = { id = first, gfx = u16(b, at + 2), dir = u8(b, at + 4), x = u16(b, at + 5),
                  y = u16(b, at + 7), b = u8(b, at + 9), c = u8(b, at + 10) }
      at = at + 11
      if r.gfx == 0xEEEF then r.netID = u8(b, at); at = at + 1 end
      rows[#rows + 1] = r
    elseif op == "2a" then
      rows[#rows + 1] = { id = first }
      at = at + 2
    elseif op == "2c" then
      rows[#rows + 1] = { id = first, x = u16(b, at + 2), y = u16(b, at + 4), draw = u16(b, at + 6),
                          b = u8(b, at + 8), c = u8(b, at + 9) }
      at = at + 10
    else
      break
    end
  end
  return { kind = op, rows = rows }
end

local function readMovement(b, at)
  local out, guard = {}, 0
  while at + 1 < #b and guard < 256 do
    guard = guard + 1
    local code = u16(b, at)
    if code == END_MOVEMENT then break end
    out[#out + 1] = { code = code, name = C.movements[code], count = u16(b, at + 2) }
    at = at + 4
  end
  return out
end

function M.decodeMember(b, member, ops)
  ops = ops or C.ops
  local out = { entries = {}, blocks = {}, movements = {}, data = {}, unknown = {} }
  local at = 0
  while at + 3 < #b do
    if u16(b, at) == C.SCRIPT_ENTRY_END then break end
    out.entries[#out.entries + 1] = u32(b, at) + 4
    at = at + 4
  end
  local queue, queued = {}, {}
  local function want(off)
    if off and off >= 0 and off < #b and not queued[off] then
      queued[off] = true
      queue[#queue + 1] = off
    end
  end
  for _, e in ipairs(out.entries) do want(e) end
  local qi = 1
  while qi <= #queue do
    local start = queue[qi]
    qi = qi + 1
    local pc, ins = start, {}
    local guard = 0
    while pc + 1 < #b and guard < 2000 do
      guard = guard + 1
      local op = u16(b, pc)
      local def = ops[op]
      if not def then
        out.unknown[#out.unknown + 1] = { at = pc, op = op }
        break
      end
      local name, operands = def[1], def[3]
      local here = pc
      pc = pc + 2
      local args = {}
      for i, kind in ipairs(operands) do
        if kind == "u8" then args[i] = u8(b, pc); pc = pc + 1
        elseif kind == "u16" then args[i] = u16(b, pc); pc = pc + 2
        elseif kind == "u32" then args[i] = u32(b, pc); pc = pc + 4
        else
          local target = pc + 4 + s32(b, pc)
          pc = pc + 4
          if name == "applymovement" then
            local lbl = M.label(member, target)
            out.movements[lbl] = out.movements[lbl] or readMovement(b, target)
            args[i] = lbl
          elseif name == "22" or name == "24" or name == "2a" or name == "2c" then
            local lbl = M.label(member, target)
            out.data[lbl] = out.data[lbl] or readData(b, target, name)
            args[i] = lbl
          else
            want(target)
            args[i] = M.label(member, target)
          end
        end
      end
      ins[#ins + 1] = { name = name, args = args, at = here }
      if M.END_OPS[name] then break end
      -- a block that runs into the next queued block's start continues there
      if queued[pc] and pc ~= start then
        ins[#ins + 1] = { name = "goto", args = { M.label(member, pc) }, at = pc, implicit = true }
        break
      end
    end
    out.blocks[M.label(member, start)] = { at = start, instructions = ins }
  end
  return out
end

-- HEARTGOLD / SOULSILVER: the same eleven members in /a/1/8/2 (overlay 80's
-- ov80_0222AA40 reads NARC 0xB6), and the same byte code -- Platinum's
-- opcodes 0-201 decode every live script -- with the menu origins at 206 /
-- 207 where Platinum has them at 202 / 203 (FrtCmd_206 / 207: one u8 each,
-- to the menu at +0x60)
M.HGSS_NARC = "/a/1/8/2"
function M.hgssOps()
  local ops = {}
  for k, v in pairs(C.ops) do if k < 202 then ops[k] = v end end
  ops[206] = C.ops[202]
  ops[207] = C.ops[203]
  return ops
end

function M.read(rom)
  local raw = rom:read(M.NARC)
  if not raw then
    raw = rom:read(M.HGSS_NARC)
    if not raw then return nil, "fr_script.narc missing" end
    local narc = require("src.import.NarcArchive").parse(raw)
    local ops = M.hgssOps()
    local out = { members = {}, names = M.MEMBERS, family = "hgss" }
    for i = 0, narc.count - 1 do
      local b = narc:get(i)
      if b and #b > 4 then out.members[i] = M.decodeMember(b, i, ops) end
    end
    return out
  end
  local narc = require("src.import.NarcArchive").parse(raw)
  local out = { members = {}, names = M.MEMBERS }
  for i = 0, narc.count - 1 do
    local b = narc:get(i)
    if b and #b > 4 then out.members[i] = M.decodeMember(b, i) end
  end
  return out
end

return M
