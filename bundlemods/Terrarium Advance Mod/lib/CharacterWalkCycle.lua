-- lib/CharacterWalkCycle.lua
--
-- A procedural, per-vertex walk cycle for the overworld Colosseum
-- trainer/character player models (see PlayerModel.loadColosseumCharacter).
--
-- WHY THIS EXISTS, AND WHY IT ISN'T THE SAME TRICK RED_3D_PLAYER USES:
-- red_3d_player's humanoids (lib/HumanoidRigger.lua, lib/DonorRigCloner.lua)
-- are real bone-rigged skeletons -- every vertex has joint weights, so a
-- walk cycle is just rotating named bones (thigh, knee, shoulder, ...) and
-- the skin follows cleanly. The Colosseum trainer cache this mod loads is a
-- different shape entirely: it comes from Pokemon Colosseum's BATTLE actor
-- data (extract/TrainerExtractor.lua), which only ever needed to stand
-- still and gesture at a wild/trainer opponent -- a battle never moves a
-- trainer around, so nothing in the source game ever authored a walk clip
-- for these models to begin with. What TrainerExtractor bakes out per
-- vertex is a rest pose plus twelve named MORPH TARGETS (gesture1-5,
-- reaction1-5, breath, look -- see lib/TrainerRig.lua's R.mixJointPoint)
-- and a few labelled joint LANDMARK POINTS used only to place a thrown
-- Poke Ball (TrainerRig.lua's R.status(): "proceduralDeformation=false",
-- "purpose=trainer throw/release anchoring"). There is no per-vertex skin
-- weight anywhere in that cache, so there are no bones here to rotate.
--
-- Native locomotion tracks were tried: they dropped feet and corrupted other
-- clips' lower body, so they stay unextracted. Overworld walking instead
-- overlays this gait on the live idle/victory pose PlayerModel samples each
-- frame (see CharacterNativeAnim.sample / copyPositions), so Wes keeps his
-- victory body language while only arms/hands and legs/feet stride. Vertex
-- membership comes from the rest HSD skeleton in model_cache.lua
-- (jointPositions + jointParents) -- the same joint coordinates each native_v1
-- index.lua clip stores per frame, which is why those constructed clips do not
-- pull hair, back, torso, or hip. Height/side buckets are only a fallback
-- when that skeleton is missing. The overlay itself is still a coarse
-- two-joint (hip+knee) leg and one-joint (shoulder) arm swing, not a real
-- skin: retune HIP_FRACTION_OF_SHOULDER/KNEE_FRACTION_OF_HIP/SEAM_SOFTEN
-- or LOCK_BIAS below rather than the FK math if a character's proportions
-- look off.

local V = ...
local TrainerRig = V.require("TrainerRig")

local M = { version = 3 }

-- ------- tuning constants (generic human-ish proportions + gait feel)

-- Hip height as a fraction of the character's own shoulder height
-- (TrainerRig.profile already gives per-character shoulder height as a
-- fraction of total height -- see lib/TrainerRig.lua's PROFILES table).
-- ~0.62 is the ordinary hip/shoulder height ratio for a standing human;
-- it holds up fine even for Terrarium's stockier Cipher-admin models.
local HIP_FRACTION_OF_SHOULDER = 0.62

-- Knee height as a fraction of the way from the ground up to the hip.
local KNEE_FRACTION_OF_HIP = 0.50

-- How far out (as a fraction of the model's own half-width) a vertex has
-- to sit from the centerline before it counts as fully "leg" or "arm"
-- rather than "torso/spine". Vertices between 0 and this fraction fade in
-- smoothly (see smooth01 below) instead of snapping straight to full
-- weight, which is what keeps the crotch and spine from visibly tearing
-- when the two legs/arms swing apart.
local SEAM_SOFTEN = 0.22

-- Gait half-width fractions. Spine/ribs stay idle; feet sit closer to the
-- centerline than sleeves, so they use a much smaller floor than arms.
local ARM_LATERAL_CUTOFF = 0.30
local LEG_LATERAL_CUTOFF = 0.12
local FOOT_LATERAL_CUTOFF = 0.03

-- Height (as a fraction of the hip) above which a "leg" vertex is treated
-- as pelvis/hip mesh and left on the idle pose. Long coats and hanging
-- hair that dip into the thigh band are rejected separately as "back".
local HIP_LOCK_FRACTION = 0.86

-- Prefer a torso/head/hip joint over a limb joint unless the limb is
-- clearly closer. Only used to pick thigh vs shin vs arm, not to drop a
-- limb the geometry already accepted (that froze the trailing leg/arm).
local LOCK_BIAS = 1.18

-- Stop walking up a foot's parent chain once the joint is this high
-- (fraction of model height). Keeps the pelvis/spine out of the leg set.
local LEG_CHAIN_MAX_NY = 0.46

-- Stop walking up a hand's parent chain once the joint is this close to
-- the centerline (fraction of model height). Keeps clavicle/chest idle.
local ARM_CHAIN_MIN_LAT = 0.11

-- Which local axis is "forward" for a step (the other horizontal axis is
-- left the vertex's untouched "side" coordinate). TrainerExtractor centers
-- every model on both X and Z, so a forward/back stride is a rotation in
-- the (up, forward) plane around a pivot on the vertical centerline.
-- extract/TrainerExtractor.lua's normalize keeps X as the left/right split
-- (see PROFILES' halfWidth, which is measured off X) and these battle
-- actors are conventionally built facing along Z, so FORWARD_INDEX=3 (Z)
-- is the expected default. If a character's legs swing side-to-side on
-- screen instead of front-to-back once you test this in-game, that
-- character's source mesh is built facing X instead -- flip this one
-- constant to 1 rather than touching the rotation code below.
local FORWARD_INDEX = 3
local SIDE_INDEX = (FORWARD_INDEX == 3) and 1 or 3

-- Swing amplitudes, in radians. Keep these modest -- the overlay sits on
-- an already-posed idle/victory clip, so a full red_3d_player stride reads
-- as the legs ripping around. Smoothstep weights on the seam also keep
-- the motion from snapping at the hip/shoulder.
local HIP_SWING = 0.28
local KNEE_BEND = 0.38
local ARM_SWING = 0.26
local KNEE_LAG = 0.12 -- fraction of a full stride the knee-bend peak lags the hip

-- A small torso bob riding on top of the leg motion, the way a real walk
-- bobs down-and-up once per FOOTFALL (twice per full left/right cycle) --
-- see red_3d_player's own `bounce=0.5-0.5*math.cos(phase*2)` for the same
-- idea applied to its bone rig.
local BOB_AMOUNT = 0.025

-- ------- jump pose tuning (see M.applyJump below)
--
-- A manual hop (main.lua's JUMP key, thrown when it isn't crossing a real
-- ledge) is one clean up/down arc rather than a repeating stride, so it
-- doesn't have a "phase" to loop the way HIP_SWING/KNEE_BEND above do --
-- just a single 0 (takeoff) .. 1 (landing) progress. JUMP_HIP_MAX/
-- JUMP_KNEE_MAX/JUMP_ARM_MAX are the pose at full airborne tuck (progress
-- 0.5); JUMP_LOAD_FRAC/JUMP_SETTLE_FRAC are how much of the jump, at each
-- end, is spent easing into/out of a shallower JUMP_CROUCH_FRAC anticipation
-- crouch before the legs pull all the way up. Same "retune the constant,
-- not the FK math" note as HIP_FRACTION_OF_SHOULDER etc. above applies here.
local JUMP_LOAD_FRAC = 0.18    -- fraction of the jump spent easing into the windup crouch
local JUMP_SETTLE_FRAC = 0.18  -- fraction spent easing out of the landing crouch
local JUMP_CROUCH_FRAC = 0.30  -- windup/landing crouch depth, as a fraction of full tuck
local JUMP_HIP_MAX = 0.35      -- hip flexion (radians) at full airborne tuck
local JUMP_KNEE_MAX = 1.10     -- knee bend (radians) at full airborne tuck -- deeper than
                                -- KNEE_BEND since a hop tucks both feet up, not one recovering leg
local JUMP_ARM_MAX = 0.50      -- arm swing (radians), back and away from the tucked legs

local function clamp(v, a, b) if v < a then return a elseif v > b then return b else return v end end
local function smooth01(t) t = clamp(t, 0, 1); return t * t * (3 - 2 * t) end

-- Rotate a (up, forward) pair around a pivot expressed in the same two
-- coordinates. Both legs and the arm use this -- the leg additionally
-- chains a second rotation around the knee's own post-hip-rotation
-- position (see apply() below), which is what keeps the thigh and shin
-- joined instead of the shin rotating around its ORIGINAL, pre-swing spot.
local function rotate2(up, fwd, pivotUp, pivotFwd, angle)
  if angle == 0 then return up, fwd end
  local c, s = math.cos(angle), math.sin(angle)
  local du, df = up - pivotUp, fwd - pivotFwd
  return pivotUp + du * c - df * s, pivotFwd + du * s + df * c
end

local function dist2(ax, ay, az, p)
  local dx = ax - (p[1] or 0)
  local dy = ay - (p[2] or 0)
  local dz = az - (p[3] or 0)
  return dx * dx + dy * dy + dz * dz
end

-- Which way the rest pose faces, from the feet vs the body center. Coat
-- tails and hanging hair sit on the opposite side of that axis and must
-- not inherit the leg swing just because they overlap the thigh height band.
local function facingSign(groups, bounds, minY, height, centerFwd)
  local footSum, footN = 0, 0
  local limit = minY + height * 0.10
  for _, g in ipairs(groups or {}) do
    local base = g.baseVertices
    if base then
      for i = 1, #base do
        local v = base[i]
        if (v[2] or 0) <= limit then
          footSum = footSum + (v[FORWARD_INDEX] or 0)
          footN = footN + 1
        end
      end
    end
  end
  if footN == 0 then return 1, centerFwd end
  local footFwd = footSum / footN
  local sign = (footFwd >= centerFwd) and 1 or -1
  return sign, footFwd
end

-- Label rest-pose HSD joints (model_cache.jointPositions / native_v1 index
-- roles[role].joints[1]) as arm, thigh, shin, or lock. Parent-chain walk
-- from the lowest joint per side (foot) and the most lateral upper-body
-- joint per side (hand) so pelvis, spine, chest, neck, and hair joints
-- stay locked. Constructed native clips already move the right vertices;
-- this is only a membership mask for the procedural overlay.
local function classifyJoints(positions, parents, bounds, minY, height, centerX)
  local n = type(positions) == "table" and #positions or 0
  if n < 4 then return nil end
  parents = type(parents) == "table" and parents or {}
  local children = {}
  for i = 1, n do children[i] = {} end
  for i = 1, n do
    local p = math.floor(tonumber(parents[i]) or 0)
    if p >= 1 and p <= n then
      children[p][#children[p] + 1] = i
    end
  end

  local function ny(i)
    local p = positions[i]
    return (((p and p[2]) or 0) - minY) / height
  end
  local function lat(i)
    local p = positions[i]
    return math.abs(((p and p[1]) or 0) - centerX) / height
  end
  local function sideOf(i)
    local p = positions[i]
    return (((p and p[1]) or 0) >= centerX) and 1 or -1
  end

  local foot, footY = { [-1] = nil, [1] = nil }, { [-1] = math.huge, [1] = math.huge }
  local hand, handScore = { [-1] = nil, [1] = nil }, { [-1] = -1, [1] = -1 }
  for i = 1, n do
    if type(positions[i]) == "table" then
      local s = sideOf(i)
      local y = positions[i][2] or 0
      if y < footY[s] then footY[s] = y; foot[s] = i end
      local h = ny(i)
      if h > 0.50 and h < 0.94 then
        local sc = lat(i) * 2.2 + (1 - math.abs(h - 0.72)) * 0.25
        if sc > handScore[s] then handScore[s] = sc; hand[s] = i end
      end
    end
  end

  local kind = {}
  for i = 1, n do kind[i] = "lock" end
  local parentCount = 0
  for i = 1, n do
    if (tonumber(parents[i]) or 0) > 0 then parentCount = parentCount + 1 end
  end

  -- Mark only the parent chain first. Never tag the root/pelvis/spine:
  -- those sit on the centerline (or branch to both legs AND the torso).
  -- Flooding from a ground-level root painted the whole actor as a leg,
  -- so the idle torso/head split into opposite gait phases.
  local kneeNy = LEG_CHAIN_MAX_NY * KNEE_FRACTION_OF_HIP
  local function isSpine(j)
    -- Centerline only. A thigh JOBJ with extra helper children is still a
    -- leg -- treating "3 children" as spine froze one side's chain.
    return lat(j) < 0.07
  end
  for _, s in ipairs({ -1, 1 }) do
    local j, guard = foot[s], 0
    while j and j >= 1 and j <= n and guard < 64 do
      guard = guard + 1
      if ny(j) >= LEG_CHAIN_MAX_NY or isSpine(j) then break end
      kind[j] = (ny(j) < kneeNy) and "shin" or "thigh"
      j = math.floor(tonumber(parents[j]) or 0)
    end
    j, guard = hand[s], 0
    while j and j >= 1 and j <= n and guard < 64 do
      guard = guard + 1
      if lat(j) < ARM_CHAIN_MIN_LAT or ny(j) < 0.44 or isSpine(j) then break end
      kind[j] = "arm"
      j = math.floor(tonumber(parents[j]) or 0)
    end
  end

  local function flood(j, label, guard)
    local kids = children[j]
    if not kids or guard > 48 then return end
    for k = 1, #kids do
      local c = kids[k]
      if kind[c] == "lock" and not isSpine(c) then
        kind[c] = label
        flood(c, label, guard + 1)
      end
    end
  end
  for i = 1, n do
    if kind[i] ~= "lock" then flood(i, kind[i], 0) end
  end

  -- Caches without jointParents: classify each joint by rest pose alone.
  if parentCount < n * 0.5 then
    for i = 1, n do
      if type(positions[i]) == "table" then
        local h, l = ny(i), lat(i)
        if h < LEG_CHAIN_MAX_NY and l > 0.05 then
          kind[i] = (h < kneeNy) and "shin" or "thigh"
        elseif h > 0.50 and h < 0.94 and l > ARM_CHAIN_MIN_LAT then
          kind[i] = "arm"
        else
          kind[i] = "lock"
        end
      end
    end
  end

  local limb, lock = {}, {}
  local hipSum, hipN, kneeSum, kneeN, shSum, shN = 0, 0, 0, 0, 0, 0
  for i = 1, n do
    local p = positions[i]
    if type(p) == "table" then
      local row = { p = p, k = kind[i], side = sideOf(i) }
      if kind[i] == "lock" then
        lock[#lock + 1] = row
      else
        limb[#limb + 1] = row
        local y = p[2] or 0
        if kind[i] == "thigh" then hipSum = hipSum + y; hipN = hipN + 1
        elseif kind[i] == "shin" then kneeSum = kneeSum + y; kneeN = kneeN + 1
        else shSum = shSum + y; shN = shN + 1 end
      end
    end
  end
  if #limb == 0 then return nil end
  return {
    limb = limb, lock = lock,
    hipY = hipN > 0 and (hipSum / hipN) or nil,
    kneeY = kneeN > 0 and (kneeSum / kneeN) or nil,
    shoulderY = shN > 0 and (shSum / shN) or nil,
  }
end

local function bindNearest(vx, vy, vz, classified)
  local bestLimb, bestLimbD, bestLockD = nil, math.huge, math.huge
  local limb, lock = classified.limb, classified.lock
  for i = 1, #limb do
    local d = dist2(vx, vy, vz, limb[i].p)
    if d < bestLimbD then bestLimbD = d; bestLimb = limb[i] end
  end
  for i = 1, #lock do
    local d = dist2(vx, vy, vz, lock[i].p)
    if d < bestLockD then bestLockD = d end
  end
  if not bestLimb then return "torso", 0, 1 end
  -- Hair, back, and hip verts sit closer to lock joints than to a wrist
  -- or ankle. Bias lock so a tie (armpit, inner thigh, scalp) stays idle.
  if bestLockD <= bestLimbD * LOCK_BIAS then
    return "torso", 0, bestLimb.side
  end
  local ratio = math.sqrt(bestLockD) / (math.sqrt(bestLimbD) + 1e-8)
  local weight = smooth01((ratio - LOCK_BIAS) / 0.70)
  return bestLimb.k, weight, bestLimb.side
end

-- Height/side membership. Spine/head/coat stay idle; both shoes and both
-- sleeves must still qualify even when the rest pose is a bit off-center
-- (tucked arm, trailing leg, inner sole).
local function geometricBucket(up, sideCoord, fwd, hipY, kneeY, shoulderY, minY, height, centerSide, halfWidth, softenSide, faceSign, centerFwd)
  local side = (sideCoord >= centerSide) and 1 or -1
  local lateralAbs = math.abs(sideCoord - centerSide)
  local sideFrac = lateralAbs / halfWidth
  local seam = smooth01(lateralAbs / math.max(softenSide, 0.0001))
  local behind = ((fwd - centerFwd) * faceSign) < -(halfWidth * 0.12)
  local footTop = minY + height * 0.16

  -- Head, neck, scalp: never a limb. Rest-pose hands sit lower and wider.
  if up >= shoulderY * 0.90 then
    return "torso", 0, side
  end
  -- Coat / hair / backpack on the BACK OF THE TORSO only -- a trailing
  -- stance leg is also "behind" and must still walk.
  if behind and up >= hipY then
    return "torso", 0, side
  end
  -- Shoes: keep the inner sole. One leftover sole vert was the old
  -- LEG_LATERAL_CUTOFF rejecting the medial bottom of the foot.
  if up <= footTop or up < kneeY * 0.42 then
    if sideFrac < FOOT_LATERAL_CUTOFF then
      return "torso", 0, side
    end
    return "shin", math.max(0.85, seam), side
  end
  -- Spine / chest / belly -- not the legs under it.
  if up >= hipY and sideFrac < LEG_LATERAL_CUTOFF then
    return "torso", 0, side
  end
  if up < hipY then
    if up >= hipY * HIP_LOCK_FRACTION and sideFrac < 0.32 then
      return "torso", 0, side
    end
    if sideFrac < LEG_LATERAL_CUTOFF then
      return "torso", 0, side
    end
    local w = smooth01((sideFrac - LEG_LATERAL_CUTOFF) / 0.20)
    return (up < kneeY) and "shin" or "thigh", math.min(1, math.max(seam, w)), side
  end
  -- Arms: out from the ribs, between hip and shoulder. A tucked rest pose
  -- (Wes's left) is still an arm; 0.30 of half-width is the sleeve, not
  -- the far reach of the throwing hand.
  if up > hipY * 1.02 and up <= shoulderY * 1.06 and sideFrac > ARM_LATERAL_CUTOFF then
    local w = smooth01((sideFrac - ARM_LATERAL_CUTOFF) / 0.22)
    return "arm", math.max(w, 0.45), side
  end
  return "torso", 0, side
end

-- Any sole vert that sat just inside the cutoff still inherits the nearest
-- swinging shoe instead of stretching off the mesh.
local function stitchFeet(groups, rig, kneeY, minY, height, halfWidth)
  local radius = halfWidth * 0.38
  local r2 = radius * radius
  local footTop = minY + height * 0.18
  for gi, g in ipairs(groups or {}) do
    local base = g.baseVertices
    local buckets = rig.groups[gi]
    if base and buckets then
      local seeds = {}
      for vi = 1, #base do
        local b = buckets[vi]
        if b and (b.bucket == "shin" or b.bucket == "thigh") and (b.weight or 0) > 0.4 then
          local v = base[vi]
          if (v[2] or 0) <= footTop then
            seeds[#seeds + 1] = { v[1] or 0, v[2] or 0, v[3] or 0, b.side, b.bucket }
          end
        end
      end
      if #seeds > 0 then
        for vi = 1, #base do
          local b = buckets[vi]
          local v = base[vi]
          local up = v[2] or 0
          if b and (not b.weight or b.weight <= 0 or b.bucket == "torso") and up <= footTop then
            local bx, by, bz = v[1] or 0, up, v[3] or 0
            local best, bestD = nil, r2
            for s = 1, #seeds do
              local p = seeds[s]
              local dx, dy, dz = bx - p[1], by - p[2], bz - p[3]
              local d = dx * dx + dy * dy + dz * dz
              if d < bestD then bestD = d; best = p end
            end
            if best then
              buckets[vi] = { bucket = "shin", side = best[4], weight = 1 }
            end
          end
        end
      end
    end
  end
end

-- Split left/right from the actual shoes so a slightly off-center rest
-- pose does not dump one whole leg on the spine side of centerX.
local function footSplitX(groups, minY, height, fallback)
  local acc = { [-1] = 0, [1] = 0 }
  local n = { [-1] = 0, [1] = 0 }
  local limit = minY + height * 0.12
  for _, g in ipairs(groups or {}) do
    local base = g.baseVertices
    if base then
      for i = 1, #base do
        local v = base[i]
        if (v[2] or 0) <= limit then
          local x = v[SIDE_INDEX] or 0
          local s = (x >= fallback) and 1 or -1
          acc[s] = acc[s] + x
          n[s] = n[s] + 1
        end
      end
    end
  end
  if n[-1] > 0 and n[1] > 0 then
    return 0.5 * (acc[-1] / n[-1] + acc[1] / n[1])
  end
  return fallback
end

-- Build (once, when a character model loads -- see PlayerModel.loadColosseumCharacter)
-- the per-vertex bucket assignment for one character's mesh groups: which
-- limb each vertex belongs to, which side, and how much weight it gets.
-- Cheap and one-shot -- O(total vertex count), never called per frame.
--
-- `groups` is PlayerModel's array of {mesh=, texture=, baseVertices=, baseUVs=}.
-- `bounds` is the trainer cache's own cache.bounds (min/max/center), the
-- same table TrainerRig.profile already reads for the throw-anchor system.
-- `skeleton`, when given, is { jointPositions=, jointParents= } from
-- model_cache.lua (rest pose). native_v1/index.lua stores the same joint
-- coordinates per clip frame under roles[role].joints -- those authored
-- tracks already skin arms/legs correctly; we only use rest joints here
-- so the walk overlay does not swing torso, hip, back, or hair verts.
function M.build(id, groups, bounds, skeleton)
  local prof = TrainerRig.profile(id, bounds)
  local minY = prof.minY
  local hipY = minY + prof.height * prof.shoulder * HIP_FRACTION_OF_SHOULDER
  local shoulderY = minY + prof.height * prof.shoulder
  local kneeY = minY + (hipY - minY) * KNEE_FRACTION_OF_HIP
  local centerSide = (SIDE_INDEX == 1) and prof.centerX or prof.centerZ
  local centerFwd = (FORWARD_INDEX == 3) and prof.centerZ or prof.centerX
  if SIDE_INDEX == 1 then
    centerSide = footSplitX(groups, minY, prof.height, centerSide)
  end
  local halfWidth = math.max(prof.halfWidth, 0.001)
  local softenSide = halfWidth * SEAM_SOFTEN
  local faceSign = facingSign(groups, bounds, minY, prof.height, centerFwd)

  local classified = nil
  local joints = skeleton and skeleton.jointPositions
  if (not joints or #joints == 0) and skeleton and skeleton.joints then
    joints = skeleton.joints
  end
  if type(joints) == "table" and #joints > 0 then
    classified = classifyJoints(joints, skeleton.jointParents, bounds, minY, prof.height, centerSide)
  end
  -- Pivots stay on the authored shoulder/hip profile. Joint averages were
  -- pulled toward the spine when a root joint got tagged as a leg.
  local rig = {
    hipY = hipY, kneeY = kneeY, shoulderY = shoulderY,
    centerSide = centerSide, version = M.version, groups = {},
  }

  for gi, g in ipairs(groups) do
    local buckets = {}
    local base = g.baseVertices
    if base then
      for vi, v in ipairs(base) do
        local up = v[2] or 0
        local vx, vz = v[1] or 0, v[3] or 0
        local sideCoord = v[SIDE_INDEX] or 0
        local fwd = v[FORWARD_INDEX] or 0
        local bucket, weight, side = geometricBucket(
          up, sideCoord, fwd, hipY, kneeY, shoulderY, minY, prof.height,
          centerSide, halfWidth, softenSide, faceSign, centerFwd
        )
        -- Joints may refine thigh/shin/arm, but must not freeze a limb
        -- the rest-pose silhouette already accepted.
        if classified and weight > 0 then
          local jBucket, jWeight, jSide = bindNearest(vx, up, vz, classified)
          if jBucket == "thigh" or jBucket == "shin" or jBucket == "arm" then
            if (jBucket == "arm") == (bucket == "arm") then
              bucket = jBucket
            end
            if jSide then side = jSide end
            if jWeight and jWeight > 0 then
              weight = math.max(weight, jWeight)
            end
          end
        end
        buckets[vi] = { bucket = bucket, side = side, weight = weight or 0 }
      end
    end
    rig.groups[gi] = buckets
  end
  stitchFeet(groups, rig, kneeY, minY, prof.height, halfWidth)

  return rig
end

-- Apply manual vertex overrides exported from the Python editor.
-- `overridesPath` is the path to a Lua file like {char_id}_walk_overrides.lua
-- that contains: return { [1]={{ [1]={bucket="arm",weight=1.0}, ... }}, ... }
-- where the outer keys are 1-based group indices and inner keys are 1-based vertex indices.
function M.applyOverrides(rig, overridesPath)
  local ok, overrides = pcall(dofile, overridesPath)
  if not ok or type(overrides) ~= "table" then
    print("CharacterWalkCycle: failed to load overrides from " .. tostring(overridesPath))
    return
  end
  
  local appliedCount = 0
  for groupIdx, groupOverrides in pairs(overrides) do
    if rig.groups[groupIdx] then
      for vertexIdx, override in pairs(groupOverrides) do
        local bucket = rig.groups[groupIdx][vertexIdx]
        if bucket then
          if override.bucket then
            bucket.bucket = override.bucket
          end
          if override.weight then
            bucket.weight = override.weight
          end
          appliedCount = appliedCount + 1
        end
      end
    end
  end
  
  print("CharacterWalkCycle: applied " .. appliedCount .. " manual overrides from " .. tostring(overridesPath))
end

-- Advance/decay a smooth 0..1 blend toward `movingNow`, so starting or
-- stopping eases the swing in/out over a few frames instead of snapping --
-- same idea as red_3d_player's startBlendRate/stopBlendRate.
function M.updateBlend(current, movingNow, dt, riseRate, fallRate)
  current = current or 0
  local target = movingNow and 1 or 0
  local rate = movingNow and (riseRate or 10) or (fallRate or 6)
  if current < target then
    current = math.min(target, current + rate * dt)
  elseif current > target then
    current = math.max(target, current - rate * dt)
  end
  return current
end

-- Produce a fresh vertexData array (in Voxel3D.FORMAT order: pos3, uv2,
-- shade1, water1) for one mesh group, at gait `phase` (radians, one full
-- lap = one full left-right-left stride) and swing `blend` (0..1). Written
-- to `out` in place when given, so callers can reuse the same table every
-- frame instead of allocating one per vertex per frame.
-- `posedVertices`, when given, is the live idle/victory pose for this group
-- (CharacterNativeAnim.copyPositions). The gait then swings those posed verts
-- instead of the rest-pose mesh, so walking keeps the character's authored
-- idle body language. Buckets/pivots still come from the rest-pose rig.
function M.apply(rig, groupIndex, group, phase, blend, out, posedVertices)
  out = out or {}
  local buckets = rig.groups[groupIndex]
  local base, uv = group.baseVertices, group.baseUVs
  if not buckets or not base then return out end

  local hipY, kneeY, shoulderY = rig.hipY, rig.kneeY, rig.shoulderY

  -- Both legs' hip-phase and knee-phase sines only ever take one of two
  -- values per frame (the left leg is always exactly half a cycle behind
  -- the right), so compute each pair once here instead of per vertex.
  local hipSinR = math.sin(phase)
  local kneeSinR = math.sin(phase - KNEE_LAG * math.pi * 2)
  local bob = blend * BOB_AMOUNT * (0.5 - 0.5 * math.cos(phase * 2))

  for vi = 1, #base do
    local v = (posedVertices and posedVertices[vi]) or base[vi]
    local side = v[SIDE_INDEX]
    local up = v[2] + bob
    local fwd = v[FORWARD_INDEX]

    local b = buckets[vi]
    if b and b.weight > 0 and blend > 0 then
      local hipSin = (b.side < 0) and -hipSinR or hipSinR
      local hipAngle = HIP_SWING * hipSin * b.weight * blend

      if b.bucket == "arm" then
        -- The arm swings opposite its own side's leg, which is the same
        -- as just negating this side's own hip sine.
        local armAngle = -ARM_SWING * hipSin * b.weight * blend
        up, fwd = rotate2(up, fwd, shoulderY, 0, armAngle)
      elseif b.bucket == "thigh" then
        up, fwd = rotate2(up, fwd, hipY, 0, hipAngle)
      elseif b.bucket == "shin" then
        -- Forward-kinematics chain: rotate the whole leg (this vertex AND
        -- the knee pivot itself) around the hip first, then bend further
        -- around the knee's NEW (already-swung) position -- not its rest
        -- position -- so the shin stays joined to the thigh instead of
        -- rotating around a point the thigh has already left behind.
        local kneeSin = (b.side < 0) and -kneeSinR or kneeSinR
        local kneeAngle = KNEE_BEND * math.max(0, kneeSin) * b.weight * blend
        local kneeUpNow, kneeFwdNow = rotate2(kneeY, 0, hipY, 0, hipAngle)
        up, fwd = rotate2(up, fwd, hipY, 0, hipAngle)
        up, fwd = rotate2(up, fwd, kneeUpNow, kneeFwdNow, kneeAngle)
      end
    end

    -- Reassemble (side, up, fwd) back into (x, y, z) using whichever axis
    -- FORWARD_INDEX/SIDE_INDEX picked -- these are fixed module constants,
    -- not per-vertex, so this is just undoing the split above.
    local ox, oy, oz
    oy = up
    if FORWARD_INDEX == 3 then ox, oz = side, fwd else ox, oz = fwd, side end

    local slot = out[vi]
    local uvv = uv[vi]
    if slot then
      slot[1], slot[2], slot[3] = ox, oy, oz
      slot[4], slot[5] = uvv[1] or 0, uvv[2] or 0
      slot[6], slot[7] = 1.0, 0.0
    else
      out[vi] = { ox, oy, oz, uvv[1] or 0, uvv[2] or 0, 1.0, 0.0 }
    end
  end

  return out
end

-- Single 0..1 "how bent right now" curve for a manual hop: rises from 0
-- (standing) through a shallow JUMP_CROUCH_FRAC windup crouch at
-- JUMP_LOAD_FRAC, on up to a full 1.0 tuck at the midpoint (progress 0.5,
-- the top of the hop), back down through a shallow landing crouch at
-- 1 - JUMP_SETTLE_FRAC, and down to 0 again by progress 1 (feet planted).
-- Every limb in M.applyJump below reads this same curve, just scaled by
-- its own JUMP_*_MAX, rather than each keeping its own separate timing --
-- one shared curve is what keeps the hip/knee/arm moving as one motion
-- instead of three animations that happen to overlap.
local function jumpEnvelope(p)
  local L, S = JUMP_LOAD_FRAC, JUMP_SETTLE_FRAC
  if p <= L then
    return JUMP_CROUCH_FRAC * smooth01(p / L)
  elseif p <= 0.5 then
    return JUMP_CROUCH_FRAC + (1 - JUMP_CROUCH_FRAC) * smooth01((p - L) / (0.5 - L))
  elseif p <= 1 - S then
    return 1 - (1 - JUMP_CROUCH_FRAC) * smooth01((p - 0.5) / (0.5 - S))
  else
    return JUMP_CROUCH_FRAC * (1 - smooth01((p - (1 - S)) / S))
  end
end

-- Produce a fresh vertexData array for one mesh group during a manual
-- (cosmetic, in-place) hop -- see PlayerModel.draw for where `progress`
-- (0 at takeoff, 1 at landing) comes from. Same output shape and same
-- `out`-reuse convention as M.apply, and callers should use ONE or the
-- OTHER per frame, never both: a hop and a stride are different motions
-- of the same buckets, not two things to blend together.
--
-- Unlike M.apply, there is no left/right alternation here -- both feet
-- leave the ground together on a hop, so every bucket gets the same
-- magnitude regardless of `b.side` -- and no torso bob, since the actual
-- vertical travel of the whole model is the engine's own jump arc,
-- already baked into the `y` PlayerModel.draw is called with.
function M.applyJump(rig, groupIndex, group, progress, out, posedVertices)
  out = out or {}
  local buckets = rig.groups[groupIndex]
  local base, uv = group.baseVertices, group.baseUVs
  if not buckets or not base then return out end

  local hipY, kneeY, shoulderY = rig.hipY, rig.kneeY, rig.shoulderY
  local e = jumpEnvelope(clamp(progress or 0, 0, 1))
  local hipAngle = JUMP_HIP_MAX * e
  local kneeAngle = JUMP_KNEE_MAX * e
  local armAngle = JUMP_ARM_MAX * e

  for vi = 1, #base do
    local v = (posedVertices and posedVertices[vi]) or base[vi]
    local side = v[SIDE_INDEX]
    local up = v[2]
    local fwd = v[FORWARD_INDEX]

    local b = buckets[vi]
    if b and b.weight > 0 and e > 0 then
      if b.bucket == "arm" then
        -- Both arms swing back together, away from the tucked legs, same
        -- "negative = backward" sign M.apply's own arm swing uses.
        up, fwd = rotate2(up, fwd, shoulderY, 0, -armAngle * b.weight)
      elseif b.bucket == "thigh" then
        up, fwd = rotate2(up, fwd, hipY, 0, hipAngle * b.weight)
      elseif b.bucket == "shin" then
        -- Same hip-then-knee FK chain as M.apply: swing the whole leg
        -- (including the knee pivot) around the hip first, then fold the
        -- shin further around the knee's already-swung position.
        local kneeUpNow, kneeFwdNow = rotate2(kneeY, 0, hipY, 0, hipAngle * b.weight)
        up, fwd = rotate2(up, fwd, hipY, 0, hipAngle * b.weight)
        up, fwd = rotate2(up, fwd, kneeUpNow, kneeFwdNow, kneeAngle * b.weight)
      end
    end

    local ox, oy, oz
    oy = up
    if FORWARD_INDEX == 3 then ox, oz = side, fwd else ox, oz = fwd, side end

    local slot = out[vi]
    local uvv = uv[vi]
    if slot then
      slot[1], slot[2], slot[3] = ox, oy, oz
      slot[4], slot[5] = uvv[1] or 0, uvv[2] or 0
      slot[6], slot[7] = 1.0, 0.0
    else
      out[vi] = { ox, oy, oz, uvv[1] or 0, uvv[2] or 0, 1.0, 0.0 }
    end
  end

  return out
end

return M
