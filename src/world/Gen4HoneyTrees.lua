-- Platinum Honey Tree save state and native encounter-table selection.
local H={}
H.headers={347,349,350,353,354,356,362,363,366,367,371,373,380,382,388,392,395,200,202,204,256}
function H.treeId(header)
 for i,id in ipairs(H.headers) do if id==header then return i-1 end end
end
function H.tables(rom)
 local bytes=rom:read('/arc/encdata_ex.narc');local arc=bytes and require('src.import.NarcArchive').parse(bytes)
 if not arc then return end
 local out={}
 for group=1,3 do
  local b=arc:get(group+1);if not b or #b<24 then return end
  out[group]={}
  for slot=1,6 do local a,c,d,e=b:byte((slot-1)*4+1,(slot-1)*4+4);out[group][slot]=a+c*256+d*65536+e*16777216 end
 end
 return out
end
function H.rareTrees(id)
 local out={};id=tonumber(id) or 0
 for i=1,4 do out[i]=math.floor(id/256^(4-i))%256%21 end
 for i=2,4 do for j=1,i-1 do if out[j]==out[i] then out[i]=(out[i]+1)%21 end end end
 return out
end
local function state(save)
 save.gen4HoneyTrees=save.gen4HoneyTrees or {trees={}}
 return save.gen4HoneyTrees
end
function H.status(save,id,now)
 local tree=state(save).trees[id];if not tree or not tree.at then return 1 end
 local minutes=math.max(0,math.floor(((now or os.time())-tree.at)/60))
 if minutes>=1440 or tree.empty then return 1 end
 return minutes>=360 and 3 or 2
end
function H.slather(save,id,rng,now)
 if id==nil then return end
 rng=rng or math.random;local s=state(save);local tree=s.trees[id] or {}
 local group=tree.group
 local reuse=s.last==id and group~=nil and rng(0,99)<90
 if not reuse then
  local player=save.player or {};local ot=tonumber(player.id) or 0
  if ot<65536 then ot=ot+(tonumber(player.secretId or player.sid) or 0)*65536 end
  local rare=false;for _,candidate in ipairs(H.rareTrees(ot)) do if candidate==id then rare=true end end
  local roll=rng(0,99)
  if rare then group=roll<1 and 3 or roll<10 and 0 or roll<30 and 1 or 2
  else group=roll<10 and 0 or roll<30 and 2 or 1 end
 end
 local roll=rng(0,99)
 local slot=roll<5 and 6 or roll<10 and 5 or roll<20 and 4 or roll<40 and 3 or roll<60 and 2 or 1
 local shake=rng(0,99)
 local thresholds=group==3 and {5,6,7} or group==2 and {75,95,96} or group==1 and {19,79,99} or {1,19,99}
 tree.group,tree.slot,tree.at=group,slot,now or os.time()
 tree.shakes=shake<thresholds[1] and 2 or shake<thresholds[2] and 1 or shake<thresholds[3] and 0 or 3
 tree.empty=group==0 and not reuse
 s.trees[id]=tree;if not reuse then s.last=id end
 return tree
end
function H.consume(data,save,id,rng,now)
 if id==nil or H.status(save,id,now)~=3 then return end
 local tree=state(save).trees[id]
 local tables=(data.constants or {}).gen4HoneyEncounters
 local slots=tables and tables[math.max(1,tree.group)]
 local species=slots and slots[tree.slot];if not species or species==0 then return end
 tree.at=nil;tree.shakes=0;tree.empty=true
 local level=(rng or math.random)(5,15)
 local lead=(save.party or {})[1]
 local ability=lead and require('src.battle.Abilities').of({mon=lead,def=(data.pokemon or {})[lead.species]})
 if lead and not (lead.egg or lead.isEgg) and (ability=='HUSTLE' or ability=='VITAL_SPIRIT' or ability=='PRESSURE') then
  if (rng or math.random)(0,1)==1 then level=15 end
 end
 return species,level
end
function H.facingTree(ground,fx,fy)
 if not ground or not ground.grid or not ground.terrain then return false end
 local x,z=fx*16+8+(ground.offsetX or 0),fy*16+8+(ground.offsetY or 0)
 local cx,cy=math.floor(x/512),math.floor(z/512)
 local land=ground.grid.land[cy*ground.grid.width+cx+1]
 local record=ground.terrain.chunks[land]
 for _,object in ipairs(record and record.objects or {}) do
  if object.model==26 and not object.archive and math.abs(x-(cx*512+256+object.x))<=16
      and math.abs(z-(cy*512+256+object.z))<=16 then return true end
 end
 return false
end
return H
