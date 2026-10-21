-- Stable National-Dex identity and persistence classification for the
-- production ColosseumDex compatibility layer. No runtime/save hooks are
-- installed here; callers must route nonnative persistence through sidecars.
local I={}

function I.originGeneration(dex)
  dex=tonumber(dex)
  local maxDex=386
  local okHD,HD=pccall(require,"HDPokemonSheets")
  if okHD and HD and type(HD.MAX_DEX)=="number" then maxDex=HD.MAX_DEX end
  if not dex or dex<1 or dex>maxDex or dex%1~=0 then return nil end
  if dex<=151 then return 1 end
  if dex<=251 then return 2 end
  if dex<=386 then return 3 end
  if dex<=493 then return 4 end
  return 5
end

function I.nativeDexLimit(hostGeneration)
  hostGeneration=tonumber(hostGeneration)
  if hostGeneration==1 then return 151 end
  if hostGeneration==2 then return 251 end
  if hostGeneration==3 then return 386 end
  if hostGeneration==4 then return 493 end
  if hostGeneration==5 then return 649 end
  return nil
end

function I.stableId(dex,name)
  dex=assert(tonumber(dex),"dex required")
  local suffix=tostring(name or ("DEX_"..dex)):upper():gsub("[^A-Z0-9_]","_")
  return ("NDEX_%03d_%s"):format(dex,suffix)
end

-- Native Gen1/Gen2 save structs store species in their original one-byte id
-- spaces.  Extra National-Dex species can exist safely as runtime battle/data
-- records, but permanent capture/party/PC ownership requires an extended
-- sidecar serializer rather than pretending the original save byte can hold
-- National Dex 252-386 (or Johto in a Gen1 save).
function I.storageClass(hostGeneration,dex)
  local origin=I.originGeneration(dex)
  if not origin then return nil,"invalid dex" end
  local limit=I.nativeDexLimit(hostGeneration)
  if not limit then return nil,"invalid host generation" end
  if dex<=limit then return "native" end
  return "extended"
end

function I.sidecarKey(dex,uid)
  return ("national-dex:%03d:%s"):format(assert(tonumber(dex)),tostring(uid or "unassigned"))
end

return I
