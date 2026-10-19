-- BLACK AND WHITE'S BATTLE LAYOUT BEYOND SINGLES: where each battler stands
-- and where its healthbox sits in a double (and the tables for triples and
-- rotation, which this engine does not field yet).
--
-- Both come out of overlay 94 (Black; research in
-- G:/Gen2Recomped/scratch_claude/bwanim/ and scratch_claude/bw_battle2/):
--
--   MCSS home positions (world units; the player is +z, the foe -z)
--     0x0220A050 singles 0..1, 0x0220A080 doubles 2..5,
--     0x0220A158 triples 2..7, 0x0220A1A0 rotation 2..7
--   the HP gauges (screen pixels, s16 x / y per BtlvMcssPos)
--     0x0220AADC doubles 0..5, 0x0220AB0C triples 0..7, 0x0220AB2C rotation
--
-- BtlvMcssPos is the cartridge's numbering: 0 / 1 are the singles pair, and
-- a double puts BattleState position p (0 player left, 1 foe left, 2 player
-- right, 3 foe right) on p + 2 -- A, B, C, D -- the same order Platinum's
-- battler types use, so Gen4Battle's `slot = p + 2` rows map one to one.
--
-- WHERE A DOUBLES BATTLER STANDS ON THE PORT'S SCREEN. The port draws BW's
-- field under a camera set by eye (src/render/Gen5BattleSceneView.lua), with
-- the singles pair on its two platforms; the move-animation player carries
-- the cartridge's view onto that screen through a map that is exact at those
-- two battlers (Gen5MoveAnimPlayer.anchorsFor / toScreen). A doubles slot's
-- home is projected through the CARTRIDGE's default camera and carried
-- across by the same map, so a battler stands exactly where a move aimed at
-- its slot lands, and is drawn at the size the cartridge's perspective gives
-- that depth (the foe's singles spot being native size).
--
-- WHERE A DOUBLES HEALTHBOX SITS. The gauge table's points are not the box
-- cells' centres this HUD was measured with (Gen5BattleHud.ENEMY / PLAYER),
-- but they differ from them by one offset a side in singles (foe +20, -2;
-- player -24, -2), and that offset is carried to the doubles rows.

local L = {}

L.HOME = {
  single = { [0] = { 0.5, 0.4, 7.0 }, [1] = { 0.3, 0.4, -10.0 } },
  double = { [2] = { -1.6875, 0.4, 6.375 }, [3] = { 2.425, 0.4, -10.375 },
             [4] = { 2.5, 0.4, 7.625 }, [5] = { -2.2, 0.4, -11.5625 } },
  triple = { [2] = { -4.0, 0.4, 7.0 }, [3] = { 4.5, 0.4, -12.0 }, [4] = { 0.75, 0.4, 4.75 },
             [5] = { 0.738, 0.4, -9.0 }, [6] = { 5.1875, 0.4, 6.1875 }, [7] = { -4.387, 0.4, -12.0 } },
  rotation = { [2] = { 0.0, 0.4, 7.0 }, [3] = { 0.0, 0.4, -8.0 }, [4] = { -4.331, 0.4, 14.5 },
               [5] = { 4.331, 0.4, -15.5 }, [6] = { 4.331, 0.4, 14.5 }, [7] = { -4.331, 0.4, -15.5 } },
}

L.GAUGE = {
  double = { [0] = { 216, 120 }, [1] = { 44, 40 }, [2] = { 216, 98 }, [3] = { 48, 28 },
             [4] = { 220, 128 }, [5] = { 44, 54 } },
  triple = { [0] = { 216, 120 }, [1] = { 44, 40 }, [2] = { 216, 95 }, [3] = { 48, 19 },
             [4] = { 220, 116 }, [5] = { 44, 40 }, [6] = { 224, 137 }, [7] = { 40, 61 } },
  rotation = { [0] = { 216, 120 }, [1] = { 44, 40 }, [2] = { 220, 116 }, [3] = { 44, 40 },
               [4] = { 216, 95 }, [5] = { 48, 19 }, [6] = { 224, 137 }, [7] = { 40, 61 } },
}

-- the battle's rule: "single" or "double" (the engine fields nothing else)
function L.rule(battle)
  if battle and battle.isDouble and battle.battlerAt then
    local ok, d = pcall(battle.isDouble, battle)
    if ok and d then return "double" end
  end
  return "single"
end

-- BattleState position -> BtlvMcssPos under the battle's rule
function L.mcssPos(battle, position)
  local p = tonumber(position) or 0
  if L.rule(battle) == "double" then return p + 2 end
  return p % 2
end

-- the world home of a BtlvMcssPos under a rule
function L.home(rule, slot)
  if slot == 0 or slot == 1 then return L.HOME.single[slot] end
  local t = L.HOME[rule or "double"] or L.HOME.double
  return t[slot] or L.HOME.single[slot % 2]
end

local function view(battle)
  local okV, V = pcall(require, "src.render.Gen5BattleSceneView")
  if okV and V and V.available and V.available(battle) then return V end
  return nil
end

function L.active(battle)
  return view(battle) ~= nil
end

-- stand(battle, slot) -> feet x, feet y, scale on the port's screen, or nil
-- (slot is a BtlvMcssPos / Gen4Battle battler type)
function L.stand(battle, slot)
  local V = view(battle)
  if not V then return nil end
  slot = tonumber(slot)
  if slot == 0 or slot == 1 then
    local side = slot == 0 and "player" or "enemy"
    local sx, sy = V.standPoint(side)
    if not sx then return nil end
    return sx, sy, V.depthScale(side)
  end
  local home = slot and L.HOME.double[slot]
  if not home then return nil end
  local okP, P = pcall(require, "src.battle.Gen5MoveAnimPlayer")
  if not (okP and P and P.anchorsFor) then return nil end
  local A = P.anchorsFor(battle)
  local rx, ry, d = P.project(P.DEFAULT_CAM, home)
  local x, y, s = P.toScreen(A, rx, ry)
  local _, _, dF = P.project(P.DEFAULT_CAM, P.HOME[1])
  return x, y, s * P.pixelsPerUnit(d) / P.pixelsPerUnit(dF)
end

-- the healthbox cell centre for a slot, from the HUD's singles centres
function L.healthbox(slot, enemyCentre, playerCentre)
  local g = L.GAUGE.double[slot]
  if not g then return nil end
  local foe = slot % 2 == 1
  local ref = foe and enemyCentre or playerCentre
  local base = L.GAUGE.double[foe and 1 or 0]
  return ref.x + (g[1] - base[1]), ref.y + (g[2] - base[2])
end

return L
