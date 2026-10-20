local V=...
local B={}
local names
function B.forMap(S,map)
 if require("src.core.GameVersion").get()~="emerald" then return nil end
 names=names or V.data("gen3_maps").maps
 local own=names[map.id]
 if not (own and own.outdoor)then return nil end
 local list={}
 for _,w in ipairs(map.def.warps or {})do
  local dest=names[w.destMap]
  local kind=dest and (dest.name:find("PokemonCenter_1F",1,true) and "center"
    or dest.name:find("Pokecenter_1F",1,true) and "center"
    or dest.name:match("_Mart$") and "mart")
  if kind and (w.destWarp==nil or w.destWarp==1) then
   local tx,ty=(w.x-1)*2,(w.y-3)*2
   local tiles={}
   for y=0,7 do
    tiles[y+1]={}
    for x=0,7 do tiles[y+1][x+1]=S.tileAt[(ty+y+64)*4096+tx+x+64] end
   end
   if tiles[1][1] then
    list[#list+1]={name=kind,civic=kind,door={w.x*2,(w.y+1)*2},tiles=tiles,position={tx,ty},roofRows=32,
      roofBack=2,roofFront=8,roofCycle={8,23},slab=2,frontEave=2,depthPx=48}
   end
  end
 end
 return #list>0 and list or nil
end
function B.settle(S)
 for _,p in ipairs(S.civicPlacements or {})do
  local key=(p.door[2]+64)*4096+p.door[1]+64
  local shape=S.shapeAt[key]
  local base=(S.runs[key] and S.runs[key].h) or (shape and shape.h) or p.base
  local delta=base-p.base
  for i=p.first,p.last do for j=1,4 do S.objectQuads[i][j][2]=S.objectQuads[i][j][2]+delta end end
  -- Ground and model must share the doorstep datum. Earlier stamps may be
  -- shared by every footprint tile; give civic plots their settled floor
  -- explicitly so the foliage clump heuristic cannot lower it afterwards.
  S.civicFloor=S.civicFloor or {}
  for y=p.ty,p.ty+p.height-1 do for x=p.tx,p.tx+p.width-1 do
   local k=(y+64)*4096+x+64
   S.civicFloor[k]=base
  end end
  p.base=base
 end
end
return B
