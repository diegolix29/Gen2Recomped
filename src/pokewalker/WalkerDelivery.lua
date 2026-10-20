-- Materialize walker parcels using only their destination ROM's extracted
-- records. No mounts, Data:load or preview-game resets are involved.
local D={}
function D.dataset(version)
 local Art=require("src.pokewalker.WalkerArt")
 local prefix=require("src.core.GameVersion").cachePrefix(version)
 local data={}
 for _,name in ipairs({"pokemon","items","moves","constants","save_layout","growth_rates"})do
  local src=Art._read(prefix,"data/generated/"..name..".lua")
  if src then
   local chunk,err=(loadstring or load)(src,"="..version.."/"..name)
   if not chunk then return nil,err end
   local ok,record=pcall(chunk)
   if not ok or type(record)~="table" then return nil,"cannot read "..version.."/"..name end
   data[name]=record
  end
 end
 if not (data.pokemon and data.items and data.moves) then return nil,"import the destination ROM before sending presents" end
 -- Match the runtime's DS bag aliases; save keys must be string ids.
 local aliases={}
 for id,def in pairs(data.items)do if type(id)=="number" then aliases[("ITEM_%03d"):format(id)]=def end end
 for id,def in pairs(aliases)do data.items[id]=def end
 data.constants=data.constants or {}
 if require("src.core.GameVersion").generation(version)>=4 then
  local Records=require("src.pokemon.SpeciesRecords")
  Records.species(data.pokemon);Records.constants(data.constants)
 end
 return data
end
function D.apply(save,version,data)
 local GV=require("src.core.GameVersion")
 local previous=GV.get()
 GV.set(version)
 local ok,result=pcall(function()
  return require("src.pokemon.Boxes").withData(data,function()
   return require("src.pokemon.Growth").withTables(data.constants and data.constants.experienceTables,function()
    return require("src.pokemon.Stats").withNatures(data.constants and data.constants.natures,function()
     return require("src.pokewalker.WalkerInbox").apply(save,data,{skipEvents=true})
    end)
   end)
  end)
 end)
 GV.set(previous)
 if not ok then return false,tostring(result) end
 return true,result
end
return D
