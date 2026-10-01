-- Move IDs and badge IDs from Platinum's FieldMoves_Check* functions.
local F = {}
F.ids = {CUT=15,FLY=19,SURF=57,STRENGTH=70,FLASH=148,ROCK_SMASH=249,
  WATERFALL=127,ROCK_CLIMB=431,DEFOG=432,DIG=91,TELEPORT=100,SWEET_SCENT=230}
-- Badge-list positions follow TrainerInfo's IDs, not Platinum's gym visit order.
F.badges = {CUT=2,FLY=3,SURF=4,STRENGTH=6,DEFOG=5,ROCK_SMASH=1,WATERFALL=8,ROCK_CLIMB=7}
function F.knows(mon, name)
  if not mon or mon.egg or mon.isEgg then return false end
  local id = F.ids[name] or name
  for _, move in ipairs(mon.moves or {}) do
    local value = type(move)=='table' and move.id or move
    if value==id or value==name then return true end
  end
  return false
end
function F.badgeHeld(data, save, name)
  local position=F.badges[name]
  if not position then return true end
  local B=require('src.inventory.Badges');local entry=B.list(data)[position]
  if not entry then return false end
  return (save.badges and save.badges[entry.id]) or B.has(save,entry) or false
end
function F.partyMember(data, save, name)
  if not F.badgeHeld(data,save,name) then return end
  for _, mon in ipairs(save.party or {}) do if F.knows(mon,name) then return mon end end
end
function F.recordsEscape(from,dest)
  return from and dest and from.allowFly==true and dest.allowEscapeRope==true or false
end
return F
