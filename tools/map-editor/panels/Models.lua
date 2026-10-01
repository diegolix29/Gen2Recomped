local M={fillsBody=true}
local Edits=require('tools.map-editor.MapEdits')
local Loader=require('src.world.MapLoader')
local function context(S)
 local map=Loader.load(S.data,S.mapId)
 local ground=map.renderer.gen4Ground
 if not ground then return end
 local cell=S.pvCell or {cx=math.floor(map.widthCells/2),cy=math.floor(map.heightCells/2)}
 local cx=math.floor(((S.data.maps[S.mapId].originX or 0)+cell.cx)/32)
 local cy=math.floor(((S.data.maps[S.mapId].originY or 0)+cell.cy)/32)
 local land=ground.grid.land[cy*ground.grid.width+cx+1]
 if land==nil then return end
 local def=map.def
 def.gen4ModelEdits=def.gen4ModelEdits or {}
 local list=def.gen4ModelEdits[tostring(land)]
 if not list then
  local record=ground.terrain.chunks[land]
  if not record then return end
  list={};for i,obj in ipairs(record.objects or {}) do
   local copy={};for k,v in pairs(obj) do copy[k]=v end;list[i]=copy
  end
 end
 return map,ground,land,list,cell
end
function M.commit(S,land,list)
 local def=S.data.maps[S.mapId]
 def.gen4ModelEdits=def.gen4ModelEdits or {};def.gen4ModelEdits[tostring(land)]=list
 S.mapEdits=S.mapEdits or Edits.load()
 Edits.setMapField(S.mapEdits,S.version,S.mapId,'gen4ModelEdits',def.gen4ModelEdits)
 S.mapEditsDirty=true;S.mapEditsStamp=(S.mapEditsStamp or 0)+1
 Loader.evict(S.mapId)
end
function M.draw(S,Kit,x,y,w,h)
 local map,ground,land,list,cell=context(S)
 if not map then Kit.emptyBox(x,y,w,h,'Select a cell on a rendered Platinum map.');return end
 local s=Kit.scale;local row=30*s
 Kit.caption(x,y,'PLATINUM 3D MODELS');y=y+row
 Kit.text('small','Select a map cell to edit its chunk props.',x,y);y=y+row
 S.modelPick=math.max(1,math.min(S.modelPick or 1,math.max(1,#list)))
 if Kit.stepper(x,y,32*s,row,'<') then S.modelPick=math.max(1,S.modelPick-1) end
 Kit.text('small',('Chunk %d · prop %d / %d'):format(land,S.modelPick,#list),x+40*s,y+6*s)
 if Kit.stepper(x+w-32*s,y,32*s,row,'>') then S.modelPick=math.min(#list,S.modelPick+1) end
 y=y+row+6*s
 if Kit.button(x,y,w/2-4*s,row,'Add model at cell') then
  list[#list+1]={model=0,x=(((map.def.originX or 0)+cell.cx)%32+.5)*16-256,z=(((map.def.originY or 0)+cell.cy)%32+.5)*16-256,y=0,scaleX=1,scaleY=1,scaleZ=1}
  S.modelPick=#list;M.commit(S,land,list)
 end
 if Kit.button(x+w/2+4*s,y,w/2-4*s,row,'Remove prop') and list[S.modelPick] then table.remove(list,S.modelPick);M.commit(S,land,list) end
 y=y+row+8*s
 local obj=list[S.modelPick]
 if not obj then return end
 for _,field in ipairs({'model','x','y','z','scaleX','scaleY','scaleZ'}) do
  local value=obj[field] or 0;local step=field:find('scale') and .1 or field=='model' and 1 or 8
  Kit.text('small',field..': '..string.format('%.2f',value),x,y+6*s)
  for i,sign in ipairs({-1,1}) do
   if Kit.stepper(x+w-(3-i)*36*s,y,32*s,row,sign<0 and '-' or '+') then
    local nextValue=value+step*sign
    if field=='model' then
     local maximum=0
     for _,rec in ipairs(ground.buildingSet and ground.buildingSet.models or {}) do maximum=math.max(maximum,rec.member or rec.index or 0) end
     nextValue=math.max(0,math.min(maximum,nextValue))
    end
    if field:find('scale') then nextValue=math.max(.1,nextValue) end
    obj[field]=nextValue;M.commit(S,land,list)
   end
  end
  y=y+row+4*s
 end
end
return M
