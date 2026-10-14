-- HEARTGOLD AND SOULSILVER'S SCRIPT COMMANDS: 853 of them, NOT Platinum's 840
-- renumbered by a constant -- the two games diverge early (HGSS's 0x0E1 is
-- GoToIfTrainerDefeated) and never line up again, so a Platinum table fed an
-- HGSS script misreads its first unusual command and sails on.
--
-- The same interface as Gen4ScriptOps, so Gen4Script decodes with either.
-- The widths are generated (src/import/Gen4HgssScriptTable.lua, from
-- pokeheartgold's asm/macros/script.inc -- what the scripts were assembled
-- with); this file is the five commands whose macros branch, each rule copied
-- from its macro:
--
--   StrengthFlagAction / FlashAction / DefogAction (400-402):
--     .byte action, then .short var only when action == 2 -- Platinum's rule
--   ScrCmd_465: .short arg0, then two shorts when arg0 <= 3, none when it is
--     6, one otherwise
--   MysteryGift (489): .short arg0, one short for 1..3, two for 5 and 6

local T = require("src.import.Gen4HgssScriptTable")

local Ops = {}
Ops.FAMILY = "hgss"
Ops.OPCODE_BYTES = 2
Ops.OPCODE_COUNT = T.count

-- { name, spec } as Gen4ScriptOps has them; the name lowercased, which is the
-- spelling Platinum's table uses for the commands the two share
-- ("lockall", "faceplayer", "end")
Ops.COMMANDS = {}
Ops.MACRO_NAMES = {}
for op, entry in pairs(T.commands) do
  Ops.COMMANDS[op] = { entry[1]:lower(), entry[2] }
  Ops.MACRO_NAMES[op] = entry[1]
end

Ops.VARIABLE_LENGTH = {}
for op, entry in pairs(T.commands) do
  if entry[2] == "*" then Ops.VARIABLE_LENGTH[op] = entry[1]:lower() end
end

Ops.TERMINATORS = { [0x002] = true, [0x01B] = true }   -- End, Return

-- The code jumps (Gen4Script resolves their targets). ApplyMovement's
-- relative operand points at movement data, and is resolved apart.
Ops.JUMPS = {}
for op in pairs(T.relative) do
  if op ~= 0x05E then Ops.JUMPS[op] = Ops.COMMANDS[op][1] end
end
Ops.MOVEMENT = { [0x05E] = true }

function Ops.name(op)
  local entry = Ops.COMMANDS[op]
  return entry and entry[1] or ("unknown_%03X"):format(op or -1)
end

local function specWidth(spec)
  local n = 0
  for i = 1, #spec do
    local c = spec:sub(i, i)
    n = n + (c == "b" and 1 or c == "w" and 2 or c == "d" and 4 or 0)
  end
  return n
end
Ops.specWidth = specWidth

function Ops.size(op)
  local entry = Ops.COMMANDS[op]
  if not entry or entry[2]:find("*", 1, true) then return nil end
  return Ops.OPCODE_BYTES + specWidth(entry[2])
end

local function u16At(data, at)
  local lo, hi = data:byte(at, at + 1)
  return lo and hi and lo + hi * 256
end

local function fieldMove(data, pc)
  local action = data:byte(pc + Ops.OPCODE_BYTES)
  if action == 2 then return "bw" end
  if action == 0 or action == 1 then return "b" end
  return nil
end

Ops.VARIABLE_SPEC = {
  [0x190] = fieldMove, [0x191] = fieldMove, [0x192] = fieldMove,
  [0x1D1] = function(data, pc)
    local a = u16At(data, pc + Ops.OPCODE_BYTES)
    if not a then return nil end
    if a <= 3 then return "www" end
    if a == 6 then return "w" end
    return "ww"
  end,
  [0x1E9] = function(data, pc)
    local a = u16At(data, pc + Ops.OPCODE_BYTES)
    if not a then return nil end
    if a >= 1 and a <= 3 then return "ww" end
    if a == 5 or a == 6 then return "www" end
    return "w"
  end,
}

function Ops.specAt(op, data, pc)
  local entry = Ops.COMMANDS[op]
  if not entry then return nil end
  local spec = entry[2]
  if not spec:find("*", 1, true) then return spec end
  local rule = Ops.VARIABLE_SPEC[op]
  if not rule or type(data) ~= "string" or type(pc) ~= "number" then return nil end
  return rule(data, pc)
end

function Ops.sizeAt(op, data, pc)
  local spec = Ops.specAt(op, data, pc)
  if not spec then return nil end
  return Ops.OPCODE_BYTES + specWidth(spec)
end

return Ops
