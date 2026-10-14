-- BATTLE ARENA RULES (pokeemerald battle_arena.c, battle_main.c's
-- arenaTurnCounter, battle_util.c's end-of-turn judgment and
-- data/battle_scripts_1.s's BattleScript_ArenaDoJudgment).
--
-- One Pokemon against one, three turns.  If neither has fainted by the end
-- of the third turn the REFEREE judges, and the loser is counted as fainted:
--   MIND  -- what each one tried: every move with power scores 1, except
--            Counter, Mirror Coat and Bide (0) and Fake Out (-1); every move
--            without power scores 0, except Protect, Detect and Endure (-1).
--            Scored when the move is chosen to be used, even if it then
--            fails to happen.
--   SKILL -- how it went: super effective +2, ordinary +1, not very
--            effective -1, missed / no effect / failed -2 (but nothing for
--            a move a Protect stopped, or for the user's own Protect).
--   BODY  -- HP left, as a percentage of the HP each had when the pair met.
-- Each category: the better one scores 2, a tie scores 1 each.  Higher
-- total wins; 3 to 3 is a draw, and both go down.
--
-- Nobody switches: the player's party menu refuses, the trainer's AI never
-- tries, and a fainted Pokemon is replaced by the next in the party, unasked.
-- Each new pair hears "REFEREE: X VS Y! Commence battling!", and its points
-- and turn count start from nothing.
--
-- The Battle Frontier's Battle Arena and Fallarbor's Battle Tent fight under
-- these rules.
--
-- WHAT IS NOT THE CARTRIDGE'S:
--   * the judgment window's circle / triangle / cross marks are not drawn --
--     each category's line is followed by who took it, in words;
--   * BattleArena_DeductSkillPoints' -3 for an ability or item that speaks
--     against a move (Volt Absorb, Own Tempo, Lum Berry ...) is taken only
--     for the commonest case, an ability that makes a move do nothing.

local Strings = require("src.core.Strings")

local Arena = {}

Arena.TEXT = {
  commence = "TEXT_5CD1A1", thatsIt = "TEXT_5CCF54",
  mind = "TEXT_5CCF9B", skill = "TEXT_5CCFE2", body = "TEXT_5CD029",
  draw = "TEXT_5CD0DB", defeated = "TEXT_5CD107", lost = "TEXT_5CD13C",
  tied = "TEXT_5CD170", forfeitAsk = "TEXT_5CD1EC", forfeited = "TEXT_5CD221",
}
Arena.FALLBACK = {
  commence = "REFEREE: {KUN} VS {RIVAL}!\nCommence battling!",
  thatsIt = "REFEREE: That's it! We will now go to\njudging to determine the winner!",
  mind = "REFEREE: Judging category 1, Mind!\nThe POKéMON showing the most guts!",
  skill = "REFEREE: Judging category 2, Skill!\nThe POKéMON using moves the best!",
  body = "REFEREE: Judging category 3, Body!\nThe POKéMON with the most vitality!",
  draw = "REFEREE: Judgment: 3 to 3!\nWe have a draw!",
  defeated = "{KUN} defeated the opponent\n{RIVAL} in a REFEREE's decision!",
  lost = "{KUN} lost to the opponent\n{RIVAL} in a REFEREE's decision!",
  tied = "{KUN} tied the opponent\n{RIVAL} in a REFEREE's decision!",
  forfeitAsk = "Would you like to forfeit the match\nand quit now?",
  forfeited = "forfeited the match!",
}

local function nameOf(b)
  return (b and (b.name or (b.mon and b.mon.nickname))) or "?"
end

-- a referee line out of the ROM's text, with the battle string codes the
-- extractor left as {KUN} (B_PLAYER_MON1_NAME) and {RIVAL}
-- (B_OPPONENT_MON1_NAME) filled in
function Arena.line(battle, key)
  local text = battle.data and battle.data.text and battle.data.text[Arena.TEXT[key]]
  text = text or Arena.FALLBACK[key]
  text = text:gsub("\012$", ""):gsub("\012", "\n")
  text = text:gsub("{KUN}", function() return nameOf(battle.player) end)
  text = text:gsub("{RIVAL}", function() return nameOf(battle.enemy) end)
  return text
end

-- sMindRatings, by the rule its own comment states (checked against all 354
-- rows of the table by tools/emerald_battle_arena_check.lua)
Arena.MIND_ZERO = { COUNTER = true, MIRROR_COAT = true, BIDE = true }
Arena.MIND_MINUS = { FAKE_OUT = true, PROTECT = true, DETECT = true, ENDURE = true }
function Arena.mindFor(data, moveId)
  if Arena.MIND_MINUS[moveId] then return -1 end
  if Arena.MIND_ZERO[moveId] then return 0 end
  local def = data and data.moves and data.moves[moveId]
  return ((tonumber(def and def.power) or 0) ~= 0) and 1 or 0
end

-- BattleArena_AddSkillPoints, over what the move did (`out`):
-- { failed, protected, typeMult, ability, selfProtect }
function Arena.skillFor(out)
  if out.protected then return 0 end
  local pts = 0
  if out.failed or out.typeMult == 0 then
    pts = -2
  elseif out.typeMult and out.typeMult > 10 then
    pts = 2
  elseif out.typeMult and out.typeMult < 10 then
    pts = -1
  elseif not out.selfProtect then
    pts = 1
  end
  if out.ability then pts = pts - 3 end
  return pts
end

-- 1 for the player's side, 2 for the trainer's
local function side(battle, b) return (b == battle.player or (b and b.isPlayer)) and 1 or 2 end

-- BattleArena_InitPoints, and arenaTurnCounter = 0xFF: a new pair
function Arena.reset(battle)
  local p, e = battle.player, battle.enemy
  battle.arenaState = {
    p = p, e = e, turn = -1, mind = { 0, 0 }, skill = { 0, 0 },
    startHp = { math.max(1, p and p.mon and p.mon.hp or 1), math.max(1, e and e.mon and e.mon.hp or 1) },
  }
  return battle.arenaState
end

-- at the menu: a pair that has not met yet hears the referee first
-- (BattleScript_ArenaTurnBeginning).  True when it queued the line.
function Arena.newPair(battle)
  local st = battle.arenaState
  local p, e = battle.player, battle.enemy
  if not (p and p.mon and p.mon.hp > 0 and e and e.mon and e.mon.hp > 0) then return false end
  if st and st.p == p and st.e == e then return false end
  Arena.reset(battle)
  battle.phase = "messages"
  battle.afterQueue = "menu"
  battle:say(Arena.line(battle, "commence"))
  return true
end

function Arena.turnStarted(battle)
  local st = battle.arenaState or Arena.reset(battle)
  st.turn = st.turn + 1
end

function Arena.addMind(battle, user, moveId)
  local st = battle.arenaState
  if not (st and user) then return end
  local s = side(battle, user)
  st.mind[s] = st.mind[s] + Arena.mindFor(battle.data, moveId)
end

-- the move's outcome, filled in as it resolves (BattleState wraps
-- performMove, cancelMoveAnim and markMissed; EffectRegistry reports the
-- type multiplier)
function Arena.beginMove(battle, user, target)
  battle.arenaOutcome = { user = user, targetProtecting = target and target.protecting or nil }
end
function Arena.endMove(battle, user)
  local st, out = battle.arenaState, battle.arenaOutcome
  battle.arenaOutcome = nil
  if not (st and out and user) then return end
  out.protected = out.failed and out.targetProtecting and true or nil
  out.selfProtect = user.protecting and true or nil
  local s = side(battle, user)
  st.skill[s] = st.skill[s] + Arena.skillFor(out)
end

-- ShowJudgmentSprite's three comparisons: { mind, skill, body } each
-- "player" / "opponent" / "tie", and the two totals
function Arena.judge(battle)
  local st = battle.arenaState
  local p, e = battle.player, battle.enemy
  local body1 = math.floor(p.mon.hp * 100 / st.startHp[1])
  local body2 = math.floor(e.mon.hp * 100 / st.startHp[2])
  local pairs3 = { { st.mind[1], st.mind[2] }, { st.skill[1], st.skill[2] }, { body1, body2 } }
  local calls, t1, t2 = {}, 0, 0
  for i, v in ipairs(pairs3) do
    if v[1] > v[2] then calls[i] = "player"; t1 = t1 + 2
    elseif v[1] < v[2] then calls[i] = "opponent"; t2 = t2 + 2
    else calls[i] = "tie"; t1 = t1 + 1; t2 = t2 + 1 end
  end
  local result = (t1 > t2) and "player" or (t1 < t2) and "opponent" or "tie"
  return result, t1, t2, calls
end

-- HandleWishPerishSongOnTurnEnd's arena arm: the third turn is over and both
-- are standing.  Queued with sayNext, after the turn's own residual lines.
function Arena.endOfTurn(battle)
  local st = battle.arenaState
  local p, e = battle.player, battle.enemy
  if not (st and st.turn >= 2 and st.p == p and st.e == e) then return end
  if not (p and p.mon and p.mon.hp > 0 and e and e.mon and e.mon.hp > 0) then return end
  -- CancelMultiTurnMoves for both
  for _, b in ipairs({ p, e }) do
    b.charging, b.chargeReady, b.invulnerable, b.hiddenAs = nil, nil, nil, nil
    b.rampMove, b.rampTurns, b.bideTurns, b.bideDamage = nil, nil, nil, nil
    b.rolloutTurns, b.uproarTurns = nil, nil
  end
  local result, t1, t2, calls = Arena.judge(battle)
  local you, them = nameOf(p), nameOf(e)
  local who = { player = you, opponent = them }
  battle:sayNext(Arena.line(battle, "thatsIt"))
  for i, key in ipairs({ "mind", "skill", "body" }) do
    battle:sayNext(Arena.line(battle, key))
    local c = calls[i]
    battle:sayNext(c == "tie" and Strings("It's even!") or Strings("%s takes it!", who[c]))
  end
  local trainer = battle.trainer and battle.trainer.name or "?"
  local player = battle.game and battle.game.save and battle.game.save.player
                 and battle.game.save.player.name or "?"
  local losers = {}
  if result == "player" then
    battle:sayNext(Strings("REFEREE: Judgment: %d to %d!\nThe winner is %s's %s!", t1, t2, player, you))
    battle:sayNext(Arena.line(battle, "defeated"))
    losers = { e }
  elseif result == "opponent" then
    battle:sayNext(Strings("REFEREE: Judgment: %d to %d!\nThe winner is %s's %s!", t1, t2, trainer, them))
    battle:sayNext(Arena.line(battle, "lost"))
    losers = { p }
  else
    battle:sayNext(Arena.line(battle, "draw"))
    battle:sayNext(Arena.line(battle, "tied"))
    losers = { p, e }
  end
  st.judged = result
  for _, b in ipairs(losers) do
    b.mon.hp = 0
    battle:drainNext(b, 0)
    battle:onFaint(b)
  end
end

-- the battle's own instance of the three move-resolution seams
function Arena.install(battle)
  battle.arena = true
  local performMove = battle.performMove
  local cancelMoveAnim = battle.cancelMoveAnim
  local markMissed = battle.markMissed
  local depth = 0
  battle.performMove = function(self, user, target, moveInst, isCalled, suppress)
    depth = depth + 1
    -- a called move (Metronome, Mirror Move, Sleep Talk) is what is judged
    Arena.beginMove(self, user, target)
    performMove(self, user, target, moveInst, isCalled, suppress)
    depth = depth - 1
    if depth == 0 then Arena.endMove(self, user) end
  end
  battle.cancelMoveAnim = function(self, ...)
    if self.arenaOutcome then self.arenaOutcome.failed = true end
    return cancelMoveAnim(self, ...)
  end
  battle.markMissed = function(self, ...)
    if self.arenaOutcome then self.arenaOutcome.failed = true end
    return markMissed(self, ...)
  end
end

return Arena
