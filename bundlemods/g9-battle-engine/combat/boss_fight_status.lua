-- Boss-fight "hardStatus"/"softStatus"/"antiDrain" protections (combat/
-- boss_fight.lua's own header owns the full flag list) -- grouped in one
-- file since none of these three has an existing primitive-owning file
-- of its own the way weather/terrain/type do (StatusRegistry/Battle:
-- applyStatus are raw ENGINE modules, not something this mod already
-- wraps anywhere; confusion has no shared primitive at all in this mod,
-- every site writes .confusedTurns/.confuseCount directly; drain-healing
-- is split across two native generic mechanisms plus one mod-custom
-- effect id, with no shared post-heal hook either).
--
-- HARD STATUS (poison/burn/paralyze/sleep/freeze): confirmed by direct
-- source read (not assumed) that every hostile hard-status application
-- in this engine -- native AND this mod's own -- funnels through exactly
-- one of two shared primitives depending on generation:
--   Gen 1: StatusRegistry.inflict(battle, target, status, opts)
--     (src/battle/StatusRegistry.lua) -- also the primitive Gen 1's own
--     native statusSide()/ctx.inflict facade route through, so gating it
--     here covers native Toxic/Thunder Wave/Sleep Powder/Will-O-Wisp too,
--     not just this mod's own secondary-chance handlers.
--   Gen 2: Battle:applyStatus(mon, status, source) (gen2/Battle.lua) --
--     same story, covers native Gen 2 status moves directly.
-- Neither primitive carries a hostile/self-inflicted flag of its own (the
-- caller's responsibility per their own contract) -- but REST bypasses
-- BOTH of them entirely on both generations (confirmed: Gen 1's HEAL_
-- EFFECT writes mon.status = "SLP" directly, src/battle/MoveEffects.lua
-- :206; Gen 2's Rest does the same, gen2/Battle.lua:2340) -- so gating
-- these two primitives unconditionally by target (battle.enemy -> block)
-- is safe: the one self-only case the user named ("only self induced are
-- allowed like rest") never reaches either gate in the first place, on
-- either engine.
--
-- SOFT STATUS (confusion + "similar bracket, like leechseed"):
--   Confusion has no shared primitive in this mod; confirmed by direct
--   source read that only TWO of the mod's own three infliction sites
--   are hostile-capable (the third, Outrage's post-rampage self-confuse
--   in modern_movepool_damage.lua, always targets its own user and is
--   deliberately left untouched). Of those two:
--     - main.lua's GALAR_CONFUSE_EFFECT_<chance> secondary-confuse-chance
--       handler (a damaging move's chance effect) is gated below via a
--       battle.damage_dealt listener, registered at an explicit LOW
--       priority (-100) -- confirmed by reading src/mods/Events.lua
--       directly that Events:emit sorts listeners by priority descending
--       and table.sort is NOT stable for equal priorities in Lua's
--       reference implementation, so "this file loads after main.lua" is
--       NOT enough on its own to guarantee this listener runs after that
--       handler's own roll; both default to priority 0 without an
--       explicit value, so an explicit low priority here is required, not
--       just tidy.
--     - modern_movepool_status.lua's confuseTarget (Flatter/Swagger) is a
--       power=0 STATUS move -- it never deals damage, so battle.
--       damage_dealt never fires for it at all, confirmed by this
--       engine's own damage-dealt emit sites (both only fire after a
--       landed, non-zero hit). Gated directly at that file's own call
--       site instead, not through this event at all.
--   LeechSeed: confirmed NOT implemented anywhere in this mod at all
--   (national_dex registers the move id with effectModeled=false, same
--   "registered, no real effect" shape) -- nothing currently applies it
--   to anything, so there is nothing to gate; an honest no-op today, not
--   silently pretended done. (MAGICROOM/WONDERROOM used to be named here
--   as the same shape; both now have real field effects -- see combat/
--   trick_room.lua.)
--
-- antiDrain: every drain-heal path found (native Gen 1 drainHalf, native
-- Gen 2's Effects.DRAIN check in Battle:useMove, and this mod's own
-- GALAR_DRAIN_EFFECT_75 for Draining Kiss) heals the ATTACKER, never
-- battle.enemy itself -- so there's no separate "who gets healed" gate
-- needed, only "did the player just drain off the boss." Implemented as
-- a battle.damage_dealt listener (the same real, confirmed event main
-- .lua's own flinch/confuse handler already uses, payload shape confirmed
-- directly: {battle,user,target,move,damage,...}) that recomputes the
-- same drain fraction the native/mod handler already applied and deals
-- it back to the attacker as self-harm -- net HP effect is the SAME as
-- "the heal never happened, dealt as self-harm instead" (explicit user
-- rule), even though the visible sequence is heal-then-immediate-
-- correction rather than a single substituted message, since none of the
-- three drain implementations expose a pre-heal interception point this
-- mod can reach without touching engine source.
--
-- healblock: ENFORCED (2026-09-10). The real enforcement lives in combat/
-- heal_block.lua -- the ONE gate every HP-recovery source routes through,
-- both generations. combat/boss_fight.lua's own flag list entry now points
-- there. (Historically this file carried a "RESERVED, no enforcement" note
-- here; the Heal Block move and this flag are both real now.)
return function(mod)
  local StatusRegistry = require("src.battle.StatusRegistry")
  local bossFightHas = mod.exports.bossFightHas
  assert(bossFightHas, "boss_fight_status: combat/boss_fight.lua must load first")
  local nationalDex = mod.find and mod.find("national_dex")
  assert(nationalDex and nationalDex.exports and nationalDex.exports.moveById,
    "boss_fight_status: national_dex must be loaded first")
  local moveById = nationalDex.exports.moveById

  -- Gen-2's Battle module is needed ONLY for the applyStatus wrap below. On a
  -- Gen 1 game that require is a hard cross-generation denial (the Loader
  -- refuses every src.*.gen2.* name), so it is guarded: hardStatus on Gen 1 is
  -- still fully enforced through StatusRegistry.inflict above, which is Gen
  -- 1's real status primitive.
  local gen2ok, Battle = pcall(require, "src.battle.gen2.Battle")

  -- "is this battler on the protected enemy side", uniformly across both
  -- generations. Gen 1's own BattleState:sideOf returns a side-record OBJECT
  -- (not a string), so it cannot be compared to "enemy" -- the battler
  -- wrapper's own isPlayer is the reliable Gen 1 signal, with identity
  -- against battle.player/enemy as the raw-mon fallback.
  local function sideIsEnemy(battle, who)
    if not (battle and who) then return false end
    local wrapper = who.mon and who or nil
    if wrapper and wrapper.isPlayer ~= nil then return not wrapper.isPlayer end
    local m = who.mon or who
    if m.multiSide then return m.multiSide == "enemy" end
    if m.isPlayer ~= nil then return not m.isPlayer end
    if m == (battle.player and (battle.player.mon or battle.player)) then return false end
    if m == (battle.enemy and (battle.enemy.mon or battle.enemy)) then return true end
    if Battle and battle.sideOf then
      local ok, s = pcall(battle.sideOf, battle, who)
      if ok and (s == "player" or s == "enemy") then return s == "enemy" end
    end
    return false
  end

  ------------------------------------------------------------------
  -- hardStatus
  ------------------------------------------------------------------
  -- Real N-way "is this the protected enemy side" check -- explicit user
  -- request (2026-08-28): object identity against `battle.enemy` only
  -- ever matched the FIRST enemy-side battler, silently leaving battler
  -- #2/#3 unprotected in a real multi-enemy boss encounter (an add, not
  -- just the boss itself). `battle:sideOf(mon) == "enemy"` uses the same
  -- real N-way primitive (combat/move_targeting.lua) every other fix in
  -- this pass now goes through -- generalizes "the boss is protected" to
  -- "the whole enemy side is protected," the natural reading of a boss
  -- fight that includes escorts, not a narrower one.
  local nativeStatusInflict = StatusRegistry.inflict
  StatusRegistry.inflict = function(battle, target, status, opts)
    if battle and target and sideIsEnemy(battle, target) and bossFightHas(battle, "hardStatus") then
      return {}
    end
    return nativeStatusInflict(battle, target, status, opts)
  end

  if gen2ok and type(Battle) == "table" then
    local nativeApplyStatus = Battle.applyStatus
    function Battle:applyStatus(mon, status, source)
      if mon and sideIsEnemy(self, mon) and bossFightHas(self, "hardStatus") then
        return
      end
      return nativeApplyStatus(self, mon, status, source)
    end
  end

  ------------------------------------------------------------------
  -- softStatus (confusion; LeechSeed is a documented no-op, see header)
  ------------------------------------------------------------------
  -- main.lua's installMovepoolEffects: the GALAR_CONFUSE_EFFECT_<chance>
  -- secondary-confuse-chance handler. Wrapping the roll itself isn't
  -- possible (it's a closure, not an export) -- instead this listens on
  -- the SAME battle.damage_dealt event at priority -100, GUARANTEED to
  -- run after that handler's own default-priority (0) roll (see this
  -- file's own header for why registration order alone isn't a safe
  -- assumption here), and clears whatever the roll just set if the
  -- target is boss-protected -- same net effect as preventing it, since
  -- nothing reads the field between those two steps within the same
  -- event dispatch.
  mod.events:on("battle.damage_dealt", function(ev)
    local battle = ev and ev.battle
    local target = ev and ev.target
    if not (battle and target and sideIsEnemy(battle, target)) then return end
    if bossFightHas(battle, "softStatus") then
      local gen2 = mod.exports.isGen2Battle and mod.exports.isGen2Battle(battle)
      if gen2 then
        battle:volatile(target).confuseCount = nil
      else
        target.confusedTurns = nil
      end
    end
  end, -100)

  ------------------------------------------------------------------
  -- antiDrain -- keyed off the move's own real, live `drain` field
  -- (national_dex), not a hardcoded effect-id table (migrated
  -- 2026-08-27 -- the id-table version stopped covering Draining Kiss
  -- the moment GALAR_DRAIN_EFFECT_75 was retired as dead/Gen-2-broken
  -- code, main.lua's own installGenericDrainRecoil work; reading the
  -- field directly means this covers every real drain move generically,
  -- natively-modeled ones included, not just whichever ids a list
  -- happened to name).
  ------------------------------------------------------------------
  mod.events:on("battle.damage_dealt", function(ev)
    local battle = ev and ev.battle
    local target = ev and ev.target
    local user = ev and ev.user
    local move = ev and ev.move
    local dealt = ev and ev.damage
    if not (battle and target and user and move and dealt and dealt > 0) then return end
    if not sideIsEnemy(battle, target) or not bossFightHas(battle, "antiDrain") then return end
    local ok, info = pcall(moveById, move.id)
    local drainPercent = ok and info and (info.drain or 0) > 0 and info.drain or nil
    if not drainPercent then return end
    local harm = math.max(1, math.floor(dealt * drainPercent / 100))
    local userMon = user.mon or user
    userMon.hp = math.max(0, (userMon.hp or 0) - harm)
    local displayNameFor = mod.exports.displayNameFor
    local name = (displayNameFor and displayNameFor(battle, user,
      mod.exports.isGen2Battle and mod.exports.isGen2Battle(battle)))
      or (userMon.name or "The Pokemon")
    battle:emit({ kind = "message",
      text = name .. " was hurt trying to drain the boss!" })
  end)

  mod.log:info("g9-battle-engine: boss_fight_status installed (hardStatus, softStatus, antiDrain)")
end
