-- Named attachment points for ORAS models (lib/ORASActorCache.lua).
--
-- Colosseum species carry a PKX body map (slot name -> bone index) that move
-- effects use to start at the mouth, hands, tail...  ORAS models have none,
-- but their skeletons use one naming scheme across all 721 species (Origin,
-- Waist, Spine1.., Neck, Head, EndHead, Jaw, EndJaw, LHand, RHand, Tail1..,
-- LFoot...), so the same map is built from the cached boneNames.
--
-- An entry is a bone index (0-based, as Actor:jointPosition wants) or a pair
-- {a, b}: the midpoint of two joints (the mouth sits between Jaw and EndJaw,
-- not on either pivot).  A slot with no fitting bone is -1; effects then fall
-- back to the chest (CurrentSpriteModels.moveFxWorldPoint).

local M = {}

M.SLOTS = {
  "origin", "mouth", "chest", "tail", "eye_left", "eye_right", "hand_left", "hand_right",
  "additional_1", "additional_2", "additional_3", "additional_4",
  "foot_left", "foot_right", "center", "additional_5",
}

-- boneNames: {[1] = "pm0006_00", [2] = "Origin", ...} (1-based, as cached)
function M.build(boneNames)
  if type(boneNames) ~= "table" then return nil end
  local index = {}
  for i, name in pairs(boneNames) do
    if type(i) == "number" and type(name) == "string" and index[name] == nil then
      index[name] = i - 1
    end
  end
  local function bone(...)
    for i = 1, select("#", ...) do
      local b = index[(select(i, ...))]
      if b then return b end
    end
    return nil
  end
  -- the highest-numbered bone of a plain chain ("Spine", "Spine1".."Spine5")
  local function chainEnd(stem)
    local best, bestN = index[stem], 0
    for name, b in pairs(index) do
      local n = name:match("^" .. stem .. "(%d+)$")
      n = tonumber(n)
      if n and n > bestN then best, bestN = b, n end
    end
    return best, bestN
  end
  local function pair(a, b)
    if a and b and a ~= b then return { a, b } end
    return a or b
  end

  local map = {}
  local origin = bone("Origin")
  local waist = bone("Waist", "Hips", "Spine1", "Spine", "SpineA1")
  local chest = chainEnd("Spine")
  if not chest then chest = bone("SpineA1", "SpineB1") end
  if not chest then chest = bone("Neck1", "Neck") end
  chest = chest or waist or origin

  local head = bone("Head", "HeadA", "Head1")
  local headTop = bone("EndHead", "EndHeadA", "EndHead1")
  local mouth = pair(bone("Jaw", "Jaw1"), bone("EndJaw", "EndJaw1"))
  if type(mouth) ~= "table" then
    local beak = pair(bone("UpperBeak"), bone("LowerBeak"))
    if type(beak) == "table" then mouth = beak end
  end
  if type(mouth) ~= "table" then
    local nose = pair(bone("Nose"), bone("EndNose"))
    if type(nose) == "table" and not head then mouth = nose end
  end
  if type(mouth) ~= "table" then mouth = pair(head, headTop) or mouth end
  mouth = mouth or chest

  -- tail tip: end of the main chain, else of a lettered one (TailA..), else
  -- a side tail (LTail..)
  local tail
  local endTail = chainEnd("EndTail")
  local lastTail = chainEnd("Tail")
  tail = endTail or lastTail
  if not tail then tail = chainEnd("EndTailA") or chainEnd("TailA") end
  if not tail then tail = chainEnd("LTail") end

  local eyes = pair(head, headTop) or mouth

  map.origin = origin or -1
  map.mouth = mouth or -1
  map.chest = chest or -1
  map.tail = tail or -1
  map.eye_left = eyes or -1
  map.eye_right = eyes or -1
  map.hand_left = bone("LHand", "LHand1", "LForeArm", "LArm", "LArm1") or -1
  map.hand_right = bone("RHand", "RHand1", "RForeArm", "RArm", "RArm1") or -1
  map.foot_left = bone("LFoot", "LToe", "LLeg", "LThigh") or -1
  map.foot_right = bone("RFoot", "RToe", "RLeg", "RThigh") or -1
  map.center = pair(waist, chest ~= waist and chest or nil) or -1
  map.additional_1, map.additional_2, map.additional_3 = -1, -1, -1
  map.additional_4, map.additional_5 = -1, -1
  return map
end

return M
