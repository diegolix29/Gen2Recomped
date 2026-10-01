-- Marking Map route locations, stored as {u16 mapHeader,u8 x,u8 y} in the ROM.
local M={}
function M.routes(rom)
  local anchor='\86\1\47\150\87\1\56\144\88\1\65\132\89\1\50\126'
  local found,hits=nil,0
  local function scan(bytes)
    local at=bytes and bytes:find(anchor,1,true)
    if not at then return end
    local out={}
    for i=0,28 do
      local lo,hi,x,y=bytes:byte(at+i*4,at+i*4+3)
      if not y or x<16 or x>208 or y<16 or y>176 then return end
      local header=lo+hi*256
      if header>=593 or out[header] then return end
      out[header]={x=x,y=y}
    end
    if not out[200] or not out[204] or not out[467] then return end
    found,hits=out,hits+1
  end
  scan(rom:arm9())
  for id=0,rom:header().overlays9-1 do scan(rom:overlay(id)) end
  return hits==1 and found or nil
end
function M.roamers(game)
  local routes=(game.data.constants or {}).gen4PoketchRoutes or {}
  local R=require('src.world.Gen4Roamers')
  local found={}
  for slot,roamer in pairs(game.save.gen4Roamers or {}) do
    if roamer.active then
      local route=R.ROUTES[roamer.route]
      -- Saves also retain the map name; use it when an older record has no route index.
      if not route then
        for _,candidate in pairs(R.ROUTES) do
          if candidate.map==roamer.map then route=candidate; break end
        end
      end
      local at=route and routes[route.header]
      if at then found[#found+1]={x=at.x,y=at.y,slot=slot} end
    end
  end
  return found
end
return M
