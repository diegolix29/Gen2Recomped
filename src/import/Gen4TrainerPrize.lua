-- PLATINUM'S PRIZE MONEY (pokeplatinum src/battle/battle_script.c,
-- BattleScript_CalcPrizeMoney, and include/data/trainer_class_prize_mul.h).
--
-- `sTrainerClassPrizeMul` is one byte per trainer class (105), compiled into
-- the battle overlay (16) and found by content: the two player classes at 0,
-- then Youngster 4, Lass 4, Camper 4, Picnicker 4, Bug Catcher 4, Aroma Lady 8,
-- Twins 4, Hiker 8 ...
--
--   prize = the trainer's LAST party member's level x 4 x prizeMoneyMul x
--           the class's byte, x2 more in a double battle (not a tag battle)
--
-- prizeMoneyMul is 2 when any battler that came onto the field held an Amulet
-- Coin (HOLD_EFFECT_MONEY_UP, battle_lib.c SWITCH_IN_CHECK_STATE_AMULET_COIN
-- walks every battler), else 1.
--
-- Written to the cache module `gen4_trainer_prize` as { byClass = {...} }.

local Gen4TrainerPrize = {}

Gen4TrainerPrize.OVERLAY = 16
Gen4TrainerPrize.CLASSES = 105
Gen4TrainerPrize.SIGNATURE = string.char(0, 0, 4, 4, 4, 4, 4, 8, 4, 8, 4, 8, 8, 8, 6, 12, 12, 12, 4, 8, 16, 16, 2, 16, 15, 15)

function Gen4TrainerPrize.parse(ov)
  if type(ov) ~= "string" then return nil, "no overlay" end
  local at = ov:find(Gen4TrainerPrize.SIGNATURE, 1, true)
  if not at then return nil, "sTrainerClassPrizeMul not found in overlay 16" end
  local byClass = {}
  for c = 0, Gen4TrainerPrize.CLASSES - 1 do byClass[c] = ov:byte(at + c) end
  return { byClass = byClass }
end

-- HEARTGOLD / SOULSILVER (pokeheartgold asm/overlay_12_battle_command.s,
-- sPrizeMoneyTbl): 0x81 rows of u16 { class, multiplier } in overlay 12, found
-- by its first eight (Ethan 0, Lyra 0, Youngster 4, Lass 4, Camper 4,
-- Picnicker 4, Bug Catcher 4, Aroma Lady 8). CalcPrizeMoney is Platinum's
-- formula; a class not listed falls back to row 2 (Youngster).
Gen4TrainerPrize.HGSS_OVERLAY = 12
Gen4TrainerPrize.HGSS_ROWS = 0x81
function Gen4TrainerPrize.parseHgss(ov)
  if type(ov) ~= "string" then return nil, "no overlay" end
  local sig = {}
  for c, m in ipairs({ 0, 0, 4, 4, 4, 4, 4, 8 }) do
    sig[#sig + 1] = string.char(c - 1, 0, m, 0)
  end
  local at = ov:find(table.concat(sig), 1, true)
  if not at then return nil, "sPrizeMoneyTbl not found in overlay 12" end
  local byClass = {}
  for r = 0, Gen4TrainerPrize.HGSS_ROWS - 1 do
    local o = at + r * 4
    local c1, c2, m1, m2 = ov:byte(o, o + 3)
    if not m2 then break end
    local class = c1 + c2 * 256
    if byClass[class] == nil then byClass[class] = m1 + m2 * 256 end
  end
  return { byClass = byClass, default = byClass[2] }
end

function Gen4TrainerPrize.extract(rom)
  return Gen4TrainerPrize.parse(rom and rom:overlay(Gen4TrainerPrize.OVERLAY))
end

-- BattleScript_CalcPrizeMoney for one trainer record.
function Gen4TrainerPrize.prize(data, trainer, opts)
  opts = opts or {}
  local rec = data and data.gen4_trainer_prize
  local mul = rec and rec.byClass and rec.byClass[tonumber(trainer and trainer.class)]
    or (rec and rec.default) or tonumber(trainer and trainer.moneyRate) or 0
  local party = trainer and (trainer.party or (trainer.parties and trainer.parties[1])) or {}
  local last = party[#party]
  local level = tonumber(last and last.level) or 0
  local prize = level * 4 * (opts.amuletCoin and 2 or 1) * mul
  if opts.double and not opts.tag then prize = prize * 2 end
  return prize
end

return Gen4TrainerPrize
