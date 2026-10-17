-- intro_movie_scene_3.c, animation durations without application dispatch
-- overhead. Coordinates are DS pixels; each background retains its own window.
local M={LENGTH=894,CITIES_END=211,RIVAL=219,BEASTS=365,NARROW=422,SPRITES=425,ROCKETS=640}
local function clamp(x) return math.max(0,math.min(1,x)) end
local function progress(t,start,duration) return clamp((t-start)/duration) end
M.progress=progress
function M.at(t)
  local s={scene='montage',tick=t,bottom=t>=M.CITIES_END}
  if t<49 then s.city='op_wakaba';s.cityFrame=t;s.reveal=progress(t,0,8);s.cover=progress(t,41,8);s.colour={1,1,1}
  elseif t<104 then s.city='op_kogane';s.cityFrame=t-49;s.reveal=progress(t,49,8);s.cover=progress(t,96,8)
  elseif t<211 then s.city='op_enju';s.cityFrame=t-104;s.reveal=progress(t,104,8);s.cover=progress(t,203,8) end
  if t<211 then return s end
  s.rivalReveal=progress(t,211,8)
  s.section=t<275 and 42 or t<292 and 43 or t<311 and 44 or t<321 and 45 or nil
  s.silhouette=t<311
  s.letterbox=64*progress(t,326,5)
  s.suicune=progress(t,365,7)
  s.entei=progress(t,372,7)
  s.raikou=progress(t,379,1)
  s.narrow=progress(t,422,3)
  s.eusine=t>=481 and t-481 or nil
  s.unown1=t>=570 and t-570 or nil
  s.unown2=t>=580 and t-580 or nil
  s.unown3=t>=600 and t-600 or nil
  s.enteiExit=progress(t,570,10)
  s.raikouExit=progress(t,590,10)
  s.suicuneExit=progress(t,630,10)
  s.rockets=t>=600
  s.expand=progress(t,640,253)
  s.rocketScroll=progress(t,640,254)
  return s
end
return M
