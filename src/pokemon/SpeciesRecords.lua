-- Shared adaptation of extracted DS records to runtime Pokemon definitions.
-- Used by normal game loads and isolated launcher deliveries.
local M={}
function M.species(pokemon)
    local EXP_RATE_NAME = {
      [0] = "MEDIUM_FAST", [1] = "ERRATIC", [2] = "FLUCTUATING",
      [3] = "MEDIUM_SLOW", [4] = "FAST", [5] = "SLOW",
    }
    local speciesFixed = 0
    for _, def in pairs(pokemon or {}) do
      if type(def) == "table" then
        local changed = false
        local bs = def.baseStats
        if type(bs) == "table" and bs.spatk == nil and bs.spAttack ~= nil then
          bs.spatk, bs.spdef = bs.spAttack, bs.spDefense
          bs.special = bs.special or bs.spAttack
          changed = true
        end
        if def.evYield == nil and type(def.evYields) == "table" then
          local y = def.evYields
          y.spatk = y.spatk or y.spAttack
          y.spdef = y.spdef or y.spDefense
          def.evYield = y
          changed = true
        end
        if def.growthRate == nil and def.expRate ~= nil then
          def.growthRate = EXP_RATE_NAME[tonumber(def.expRate)] or "MEDIUM_FAST"
          changed = true
        end
        if def.level1Moves == nil then
          local first = {}
          for _, row in ipairs(def.learnset or {}) do
            if row.move and (tonumber(row.level) or 0) <= 1 then
              first[#first + 1] = row.move
            end
          end
          def.level1Moves = first
          changed = true
        end
        if changed then speciesFixed = speciesFixed + 1 end
      end
    end
  return speciesFixed
end
function M.constants(constants)
 constants=constants or {}
 local names,order=constants.natures,constants.natureOrder
 if type(names)=="table" and type(names[1])=="string" then
  if type(order)=="table" and type(order[1])=="number" then
   local named={};for i=1,25 do named[i]=names[i] or order[i] end;constants.natureOrder=named
  end
  -- Native index rule: raised stat = floor(index/5), lowered = index%5.
  local stats={"attack","defense","speed","spatk","spdef"};local byName={}
  for i=1,25 do
   local name=names[i]
   if type(name)=="string" and name~="" then
    local n=i-1;local up,down=stats[math.floor(n/5)+1],stats[n%5+1]
    local modifiers={};for _,stat in ipairs(stats)do modifiers[stat]=100 end
    if up~=down then modifiers[up]=110;modifiers[down]=90 end
    byName[name]={name=name,index=n,modifiers=modifiers,raises=up~=down and up or nil,lowers=up~=down and down or nil}
   end
  end
  if next(byName) then constants.natures=byName;return true end
 end
 return false
end
return M
