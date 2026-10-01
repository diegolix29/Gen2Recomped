local S={}
function S.coin(archive)
  local A=require('src.import.Gen4Archives')
  local G=require('src.import.Gen4Graphics')
  local Anim=require('src.import.Gen4CellAnim')
  local id=A.find('/graphic/poketch.narc','coin_toss_anim.NANR.lz')
  local bytes=id and archive:get(id)
  if not bytes then return nil end
  if G.isCompressed(bytes) then bytes=G.decompress(bytes) end
  local bank=Anim.parse(bytes,G)
  if not bank then return nil end
  local spin,heads,tails=Anim.frames(bank,0),Anim.frames(bank,1),Anim.frames(bank,2)
  if not (spin and heads and heads[1] and tails and tails[1]) then return nil end
  return {spin=spin,heads=heads[1].cell,tails=tails[1].cell}
end
function S.spinCell(frames,ticks)
  local total=0
  for _,frame in ipairs(frames or {}) do total=total+(frame.duration or 0) end
  if total<=0 then return nil end
  ticks=math.floor(ticks or 0)%total
  for _,frame in ipairs(frames) do
    if ticks<frame.duration then return frame.cell end
    ticks=ticks-frame.duration
  end
end
return S
