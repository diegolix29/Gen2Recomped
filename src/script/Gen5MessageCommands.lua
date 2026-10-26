-- src/script/Gen5MessageCommands.lua -- BLACK / WHITE'S QUESTION AND ITS YES / NO.
--
-- A BW question is two commands: 0x34 <message> prints it and returns as soon
-- as it has printed, and 0x47 <var> opens the YES / NO window beside it --
-- the question stays on screen under the choice ("Shall I heal your
-- Pokemon?" / YES NO). Lowered as Platinum's pair, the message row waited for
-- A and closed its box, and `ask` then opened an EMPTY box with the choice:
-- the nurse's question vanished the moment YES / NO appeared.
--
-- So when 0x47 follows a message row directly, that row becomes one that
-- prints the same text with the YES / NO riding it (TextBox opts.choice,
-- which is what `ask` does). Black / White only; installed through
-- Gen5MartCommands.install.

local okCommands, Commands = pcall(require, "src.script.Commands")
if not okCommands then Commands = {} end

local M = {}

M.MESSAGE_ROWS = { g4_message = true, g4_message_bank = true }
-- Black / White's opcodes: the messages 0x34 / 0x3C / 0x3D and the YES / NO
-- 0x47 (Gen5ScriptLink's aliases). The lowering can run before the game
-- version is known, so the instruction's own op says whose it is --
-- Platinum's `message` is 0x2C and its `showyesnomenu` 0x3E.
M.BW_MESSAGE_OPS = { [0x34] = true, [0x3C] = true, [0x3D] = true }
M.BW_YESNO_OP = 0x47
-- rows the look-ahead steps over: they change nothing on screen, and still
-- run in their turn after the answer
M.PASS = { g4_set_var = true, g4_copy_var = true, g4_noop = true }

-- the message row's own command, with show_text answering through a choice
function Commands.g4_bw_ask(ctx, row, a, b)
  local runner = ctx.runner
  local show = Commands.show_text
  Commands.show_text = function(c, text, subs, extra)
    Commands.show_text = show
    local opts = {}
    for k, v in pairs(extra or {}) do opts[k] = v end
    opts.choice = function(yes)
      c.lastCheck = yes
      if runner then runner:resume() end
    end
    return show(c, text, subs, opts)
  end
  local ok, err = pcall(Commands[row], ctx, a, b)
  Commands.show_text = show
  if not ok then error(err, 0) end
end
Commands.meta = Commands.meta or {}
Commands.meta.g4_bw_ask = { foreground = true, blocking = true }

-- the next row the script will run after `pc`, through labels and plain
-- jumps (a question is often printed, then jumped to its 0x47)
local function nextRow(ctx)
  local script, pc = ctx.script, ctx.pc
  if type(script) ~= "table" or not pc then return nil end
  local labels = require("src.script.ScriptRunner").scanLabels(script)
  -- a copy of the common-script return stack (0x1C is inlined as g4_call /
  -- jump / g4_return), so a question printed at the end of a shared script
  -- finds the YES / NO its caller asks next
  local stack = {}
  for k, v in ipairs(ctx.g4Stack or {}) do stack[k] = v end
  local i, hops = pc + 1, 0
  while i <= #script and hops < 8 do
    local row = script[i]
    if type(row) ~= "table" then return nil end
    local name = row[1]
    if name == "label" or M.PASS[name] then i = i + 1
    elseif name == "jump" and type(row[2]) == "string" and labels[row[2]] then
      i, hops = labels[row[2]], hops + 1
    elseif name == "g4_return" and #stack > 0 and labels[stack[#stack]] then
      i, hops = labels[table.remove(stack)], hops + 1
    else return row end
  end
  return nil
end

M.nextRow = nextRow   -- (HgssYesNoMessage looks ahead the same way)

-- a Black / White message: when the script's next row is the bare YES / NO,
-- the choice rides this box and that row is passed over
function Commands.g4_bw_message(ctx, row, a, b)
  local nxt = nextRow(ctx)
  if nxt and nxt[1] == "ask" and nxt[2] == nil then
    ctx.bwAnswered = true
    return Commands.g4_bw_ask(ctx, row, a, b)
  end
  return Commands[row](ctx, a, b)
end
Commands.meta.g4_bw_message = { foreground = true, blocking = true }

local plainAsk = Commands.ask
Commands.ask = function(ctx, textId, ...)
  if ctx and ctx.bwAnswered and textId == nil then
    ctx.bwAnswered = nil
    return
  end
  return plainAsk(ctx, textId, ...)
end

function M.install(L)
  local plainMessage = L.message
  local function bwMessage(ins, s)
    plainMessage(ins, s)
    local last = s.out[#s.out]
    if M.BW_MESSAGE_OPS[tonumber(ins.op)] and type(last) == "table" and M.MESSAGE_ROWS[last[1]] then
      s.out[#s.out] = { "g4_bw_message", last[1], last[2], last[3] }
    end
  end
  for _, name in ipairs({ "message", "messageinstant", "messagenoskip", "messagesynchronized" }) do
    if L[name] == plainMessage then L[name] = bwMessage end
  end
  local plain = L.showyesnomenu
  L.showyesnomenu = function(ins, s)
    local last = s.out[#s.out]
    if tonumber(ins.op) == M.BW_YESNO_OP and type(last) == "table" and last[1] == "g4_bw_message" then
      s.out[#s.out] = { "g4_bw_ask", last[2], last[3], last[4] }
      s.out[#s.out + 1] = { "g4_from_yesno", ins.args[1] }
      return
    end
    return plain(ins, s)
  end
end

return M
