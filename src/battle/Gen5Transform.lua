-- BLACK AND WHITE'S TRANSFORM, drawn.
--
-- A Black / White battler is drawn from its LIVE multi-cell animation
-- (`picAnim`, Gen5MonAnimPlayer), so the Game Boy rule MoveEffects applies
-- (swap `sprite`) never showed: the user kept its own look. `apply` swaps
-- the picture as the cartridge's MCSS_COPY does (effect VM op 66,
-- 0x02200140: the defender's sprite resources onto the attacker) -- the
-- target's live animation and still, on the user's side, and the species the
-- feet are measured from.
--
-- WHEN. Transform's own effect program (/a/0/6/6 member 144) starts with END:
-- its mosaic-up / op 66 / mosaic-down body after it is never reached, so on
-- the cartridge the copy is not timed by the effect VM. MoveEffects therefore
-- calls `apply` with the move's effect; the op 66 seam (`hook`) is kept for
-- the dead body, should any program ever reach it.

local T = {}

local function isGen5(battle)
  local data = battle and battle.data
  return data and data.gen5_move_anims ~= nil
end

-- apply(battle, user, target): the user now LOOKS like the target
function T.apply(battle, user, target)
  if not (isGen5(battle) and user and target and target.mon) then return false end
  local species = target.mon.species
  local side = user.isPlayer and "back" or "front"
  if battle.speciesSprite then
    user.sprite = battle:speciesSprite(species, user.isPlayer) or user.sprite
  end
  user.species = species
  local okA, PicAnim = pcall(require, "src.pokemon.PicAnim")
  local anim = okA and PicAnim.new(battle.data, species, target.mon, side) or nil
  if anim then
    anim.mon = target.mon
    if anim.start then pcall(anim.start, anim) end
  end
  user.picAnim = anim
  user.gen5Transformed = true
  return true
end

-- hook(battle): the move-animation player's op 66 lands here
function T.hook(battle)
  local player = battle and battle.gen4Anim
  if not (player and player.gen5) then return end
  player.onTransform = function(attackerIsPlayer, layout)
    local user, target
    if layout and layout.attacker and layout.defender and battle.battlerAt then
      user = battle:battlerAt(layout.attacker - 2)
      target = battle:battlerAt(layout.defender - 2)
    else
      user = attackerIsPlayer and battle.player or battle.enemy
      target = attackerIsPlayer and battle.enemy or battle.player
    end
    T.apply(battle, user, target)
  end
end

return T
