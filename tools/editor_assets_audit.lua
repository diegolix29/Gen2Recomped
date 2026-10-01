for _,v in ipairs({'emerald','platinum'}) do
 local base='G:/Gen2Recomped/'..v..'/data/generated/'
 local maps=assert(loadfile(base..'maps.lua'))()
 local id=next(maps);local map=maps[id]
 print(v,id)
 for k,value in pairs(map) do if type(value)~='table' and k~='blocks' and k~='behaviorCells' then print(k,value) end end
 local sets=assert(loadfile(base..'tilesets.lua'))();local ts=sets[map.tileset]
 for k,value in pairs(ts) do print('tileset',k,type(value)=='table' and #value or value) end
end
