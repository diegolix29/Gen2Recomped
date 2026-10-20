-- src/script/Gen5MartCommands.lua -- BLACK / WHITE'S POKE MART COUNTER.
--
-- Every Center's clerk runs shared script 871 (Black /a/0/5/7): its own
-- BUY / SELL / SEE YA menu (bank 424), then
--
--   0x149 <var shop, var result>   BUY: the counter's list. The clerk's
--        script sets 0x8000 = 255 for the regular counter (stock by badges)
--        or the second clerk's specialty id; 871 copies it to 0x8021.
--   0x14E <u16, var, var>          SELL: the Bag in sell mode, bracketed by
--        0x14B / 0x14A and the 0x1AE / 0x1B1 / 0x1AD fades
--
-- Both used to lower to nothing ("bw_149" unimplemented, 0x14E unaliased),
-- so BUY and SELL fell straight back to the menu. The stock is read out of
-- overlay 21 at import (src/import/Gen5Marts.lua, constants.gen5Marts).
--
-- Loaded by Gen4ScriptVM (`install` with the lowering table).

local okCommands, Commands = pcall(require, "src.script.Commands")
if not okCommands then Commands = {} end

local M = {}

local function G4() return require("src.script.Gen4Commands") end
local function valueOf(ctx, v) return tonumber(G4().valueOf(ctx, v)) or 0 end

local function badges(save)
  local n = 0
  local held = save and (save.badges or (save.player and save.player.badges))
  if type(held) == "table" then for _, has in pairs(held) do if has then n = n + 1 end end
  elseif tonumber(held) then n = tonumber(held) end
  return n
end

-- the counter's stock for a 0x149 shop value: a list of item ids the cache has
function M.stock(game, shop)
  local data = game and game.data
  local marts = data and data.constants and data.constants.gen5Marts
  local list = require("src.import.Gen5Marts").stock(marts, shop, badges(game and game.save))
  local out = {}
  for _, id in ipairs(list or {}) do
    if data.items and data.items[id] then out[#out + 1] = id end
  end
  return out
end

local function setResult(ctx, dest, value)
  if dest and ctx.save then G4().setVar(ctx.save, dest, value) end
end

function Commands.g4_bw_mart(ctx, shopVar, dest, sell)
  local game = ctx.game
  if not game then return end
  local runner = ctx.runner
  local Screens = require("src.ui.Screens")
  local stock = {}
  if not sell then
    stock = M.stock(game, valueOf(ctx, shopVar))
    if not stock[1] then
      require("src.core.Logger").warn("bw shop: no stock for shop %s -- re-import the ROM",
        tostring(valueOf(ctx, shopVar)))
      setResult(ctx, dest, 0)
      return
    end
  end
  Screens.push(game, "ShopMenu", stock, function()
    setResult(ctx, dest, 0)
    if runner then runner:resume() end
  end, nil, { direct = true, sell = sell or nil })
  if sell then
    local top = game.stack and game.stack:top()
    if top and top.openBag and top.mode == "sell" then top:openBag() end
  end
  if runner then runner:yield() end
end
Commands.meta = Commands.meta or {}
Commands.meta.g4_bw_mart = { foreground = true, blocking = true }

function M.install(L)
  local function emit(s, row) s.out[#s.out + 1] = row end
  L.bwpokemart = function(ins, s) emit(s, { "g4_bw_mart", ins.args[1], ins.args[2] }) end
  L.bwmartsell = function(ins, s) emit(s, { "g4_bw_mart", nil, ins.args[2], true }) end
  -- the Center's PC, 0x14F <var, mode>: Platinum's box modes 0..3 are the
  -- same; Black / White's 4 is the Battle Box, which this port opens as MOVE
  -- (Platinum's 4 is COMPARE)
  L.bwopenstorage = function(ins, s)
    local mode = tonumber(ins.args[2])
    if mode == 4 then mode = 2 end
    emit(s, { "g4_storage", mode or ins.args[2] })
  end
  -- the Xtransceiver's story calls (0x155)
  require("src.script.Gen5XtransceiverCommands").install(L)
  -- a question's YES / NO beside the question (0x34 then 0x47)
  require("src.script.Gen5MessageCommands").install(L)
end

return M
