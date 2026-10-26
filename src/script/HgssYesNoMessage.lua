-- src/script/HgssYesNoMessage.lua -- HEARTGOLD / SOULSILVER'S QUESTION STAYS UP.
--
-- An HGSS question is a message whose last code is {YESNO 0} ("Will you
-- press it? {YESNO 0}", Mahogany hideout B1F's secret switch) and then
-- GetMenuChoice (lowered as Platinum's showyesnomenu -> a bare `ask`), often
-- with TouchscreenMenuHide between them. The printer stops at the code
-- without waiting for A and the YES / NO window opens beside the question.
-- Lowered as two rows, the message waited for A and closed its box, and
-- `ask` opened an EMPTY box under the choice: the question was gone the
-- moment YES / NO appeared.
--
-- So a message whose text carries {YESNO, when the script's next row
-- (through no-ops, labels and jumps -- Gen5MessageCommands.nextRow) is that
-- bare ask, prints with the choice riding it (Commands.g4_bw_ask) and the
-- ask row is passed over (ctx.bwAnswered, as Black / White's question does).
-- Loaded by Gen4ScriptVM; wraps g4_message / g4_message_bank at runtime.

local okCommands, Commands = pcall(require, "src.script.Commands")
if not okCommands then Commands = {} end
local okMsg, Gen5Msg = pcall(require, "src.script.Gen5MessageCommands")

local M = {}

local function textOf(ctx, label)
  local data = ctx and ctx.game and ctx.game.data
  return type(label) == "string" and data and data.text and data.text[label] or nil
end

-- the label a message row prints, the way the row itself resolves it
local function labelFor(ctx, row, a, b)
  local okG, G4 = pcall(require, "src.script.Gen4Commands")
  if row == "g4_message" then
    return okG and G4.lineFor and G4.lineFor(ctx, a) or nil
  end
  if row == "g4_message_bank" then
    local valueOf = okG and G4.valueOf
    local bank, entry = tonumber(a), tonumber(b)
    if type(valueOf) == "function" then bank, entry = valueOf(ctx, a), valueOf(ctx, b) end
    return require("src.import.Gen4Text").label(bank or 0, entry or 0)
  end
  return nil
end

local function wrap(row)
  local plain = Commands[row]
  if type(plain) ~= "function" or not (okMsg and Gen5Msg.nextRow and Commands.g4_bw_ask) then return end
  Commands[row] = function(ctx, a, b, ...)
    local text = textOf(ctx, labelFor(ctx, row, a, b))
    if type(text) == "string" and text:find("{YESNO", 1, true) then
      local nxt = Gen5Msg.nextRow(ctx)
      if nxt and nxt[1] == "ask" and nxt[2] == nil then
        ctx.bwAnswered = true
        Commands[row] = plain
        local ok, err = pcall(Commands.g4_bw_ask, ctx, row, a, b)
        Commands[row] = M.wrapped[row]
        if not ok then error(err, 0) end
        return
      end
    end
    return plain(ctx, a, b, ...)
  end
  M.wrapped[row] = Commands[row]
end

M.wrapped = {}
function M.install()
  if M.installed then return end
  M.installed = true
  -- the rows are Gen4Commands' (it never requires the VM, so no loop)
  pcall(require, "src.script.Gen4Commands")
  wrap("g4_message")
  wrap("g4_message_bank")
end

return M
