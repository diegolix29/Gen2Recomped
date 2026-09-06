-- Battle Cinematics v0.7.2 TEST2 — Gen1Recomp 0.2.53 compatibility port
-- Clean companion mod. It never modifies a renderer's files.
--
-- Compatible backends currently mapped:
--   DRAMATIC_SHAPE          upstream Dramatic Shape, including the 1.68
--                           Battle Art replacement (same manifest id)
--   BATTLE_ART_VOXEL_FORK   parallel Battle Art fork
--
-- Both are optional at manifest level so either implementation can satisfy
-- Battle Cinematics. Optional dependencies still guarantee load ordering in
-- Gen1Recomp; the runtime check below enforces that at least one compatible
-- camera backend actually survived loading.
local mod = ...

local BACKEND_IDS = { "DRAMATIC_SHAPE", "BATTLE_ART_VOXEL_FORK" }
local backends = {}

local function discoverBackend(id)
  local handle = mod.find(id)
  if not handle then return nil end
  local exports = handle.exports or {}
  local V = exports.lib
  if type(V) ~= "table" or type(V.require) ~= "function" then
    mod.log:warn("backend %s has no compatible library loader", id)
    return nil
  end
  local okCam, BattleCam = pcall(V.require, "BattleCam")
  if not okCam or type(BattleCam) ~= "table"
     or type(BattleCam.rig) ~= "function"
     or type(BattleCam.rigFor) ~= "function" then
    mod.log:warn("backend %s has no compatible BattleCam", id)
    return nil
  end
  local okBattle, OverworldBattle = pcall(V.require, "OverworldBattle")
  return {
    id=id, version=handle.version, V=V, BattleCam=BattleCam,
    OverworldBattle=(okBattle and type(OverworldBattle)=="table") and OverworldBattle or nil,
  }
end

for _,id in ipairs(BACKEND_IDS) do
  local backend=discoverBackend(id)
  if backend then backends[#backends+1]=backend end
end
if #backends==0 then
  error("BATTLE_CINEMATICS: compatible Dramatic Shape battle camera required", 0)
end

local SPEEDS = {
  { value="slowest", label="SLOWEST", scale=1.75 },
  { value="slow",    label="SLOW",    scale=1.35 },
  { value="medium",  label="MEDIUM",  scale=1.00 },
  { value="fast",    label="FAST",    scale=0.78 },
}
local DELAYS = { immediate=0.0, quick_2=2.0, quick_4=4.0, short=6.0, standard=9.0, long=12.0, extra_long=15.0 }

-- A genuine mod-owned settings page. Nothing is injected into the game's
-- global Options list or Dramatic Shape's menu.
mod.options:define({
  { key="enabled", label="ENABLED", type="choice", default="on",
    choices={{"ON","on"},{"OFF","off"}} },
  { key="preset", label="PRESET", type="choice", default="dw3",
    choices={{"DW3 CLASSIC","dw3"},{"HERO PORTRAIT","portrait_test"}} },
  { key="dynamicIntro", label="DYNAMIC INTRO", type="choice", default="on",
    choices={{"ON","on"},{"OFF","off"}} },

  -- Preset-owned values. The Mod Manager wrapper below hides these rows from
  -- the main Battle Cinematics page and exposes them through CONFIGURE PRESET.
  -- They remain normal mod options underneath, so values are persisted by the
  -- launcher and survive preset switching / restarts.
  { key="dw3Framing", label="FRAMING", type="choice", default="standard",
    choices={{"STANDARD","standard"},{"NEAR","near"},{"CLOSE","close"}} },
  { key="circleSpeed", label="ORBIT SPEED", type="choice", default="medium",
    choices={{"SLOWEST","slowest"},{"SLOW","slow"},{"MEDIUM","medium"},{"FAST","fast"}} },
  { key="dw3Height", label="HEIGHT", type="choice", default="standard",
    choices={{"LOW","low"},{"STANDARD","standard"},{"HIGH","high"}} },
  { key="dw3Angle", label="ANGLE", type="choice", default="standard",
    choices={{"SHALLOW","shallow"},{"STANDARD","standard"},{"STRONG","strong"}} },

  { key="introSpeed", label="INTRO SPEED", type="choice", default="fast",
    choices={{"SLOW","slow"},{"NORMAL","normal"},{"FAST","fast"}} },
  { key="introReset", label="INTRO RESET CAM", type="choice", default="off",
    choices={{"OFF","off"},{"ON MOVE/ITEM","confirmed"},{"ANY INPUT","any"}} },
  { key="initialDelay", label="INITIAL DELAY", type="choice", default="standard",
    choices={{"IMMEDIATE (0s)","immediate"},{"2 SECONDS","quick_2"},
             {"4 SECONDS","quick_4"},{"SHORT (6s)","short"},
             {"STANDARD (9s)","standard"},{"LONG (12s)","long"},
             {"EXTRA LONG (15s)","extra_long"}} },
  { key="inputReturn", label="RESET CAMERA", type="choice", default="confirmed",
    choices={{"ON MOVE/ITEM","confirmed"},{"ANY INPUT","any"},{"OFF","off"}} },
  { key="diagnostics", label="DIAGNOSTICS", type="choice", default="off",
    choices={{"OFF","off"},{"ON","on"}} },
})

local state = {
  rigSeen=false, sinceRig=0, noRig=0,
  idle=0, time=0, active=false, blend=0,
  directorPlan=1, directorBattle=0,
  battle=nil,
  intro={ active=false, side=nil, time=0, pendingEnemy=false, pendingPlayer=false,
          initial=true, enemyWasSending=false, playerWasSending=false },
}
local BLEND_TIME=0.70

local function enabled()
  return mod.options:get("enabled") ~= "off"
end
local function idleDelay()
  return DELAYS[mod.options:get("initialDelay")] or DELAYS.standard
end
local function speedScale()
  local value=mod.options:get("circleSpeed") or "medium"
  for _,e in ipairs(SPEEDS) do if e.value==value then return e.scale end end
  return 1.0
end
local function diagnosticsOn()
  return mod.options:get("diagnostics") == "on"
end
local function logDiagnostic(message)
  if diagnosticsOn() then mod.log:info("[diagnostics] " .. message) end
end

local INTRO_DURATION=9.4
local function dynamicIntroOn()
  return mod.options:get("dynamicIntro") == "on"
end
local function introSpeedScale()
  local value=mod.options:get("introSpeed") or "fast"
  if value=="fast" then return 2.0 end      -- established v0.7.1 default
  if value=="slow" then return 0.75 end     -- gentler presentation
  return 1.0                                -- normal / legacy normal
end
local function introResetMode()
  return mod.options:get("introReset") or "off"
end
local function clearIntro()
  state.intro.active=false
  state.intro.side=nil
  state.intro.time=0
end
local function queueIntro(side)
  if not dynamicIntroOn() then return end
  if side=="enemy" then state.intro.pendingEnemy=true
  elseif side=="player" then state.intro.pendingPlayer=true end
end
local function startIntro(side)
  state.intro.active=true
  state.intro.side=side
  state.intro.time=0
  if side=="enemy" then state.intro.pendingEnemy=false else state.intro.pendingPlayer=false end
  state.active=false
  state.idle=0
  state.blend=0
  logDiagnostic("dynamic intro: "..side)
end

local function activity()
  state.idle=0
  state.active=false
end
local function resetBattle()
  rigCache=setmetatable({},{__mode="k"})
  state.idle,state.time,state.active,state.blend=0,0,false,0
  state.directorBattle=(state.directorBattle or 0)+1
  state.directorPlan=((state.directorBattle-1)%3)+1
  clearIntro()
end
local function chase(now,goal,dt,time)
  if now==goal then return goal end
  local v=now+(goal-now)*math.min(1,(dt or 0)/math.max(1e-4,time))
  return (math.abs(goal-v)<1e-4) and goal or v
end
local function smoothstep(q) return q*q*(3-2*q) end
local function smootherstep(q) return q*q*q*(q*(q*6-15)+10) end
local function mix(a,b,w) return a+(b-a)*w end
local function mixCamera(base,cine,w)
  if not cine or w<=0 then return base end
  return {
    eye={mix(base.eye[1],cine.eye[1],w),mix(base.eye[2],cine.eye[2],w),mix(base.eye[3],cine.eye[3],w)},
    focus={mix(base.focus[1],cine.focus[1],w),mix(base.focus[2],cine.focus[2],w),mix(base.focus[3],cine.focus[3],w)},
    fov=mix(base.fov,cine.fov,w), curve=0,
  }
end

local PLANS={
  {
    {kind="orbit",duration=13.5,turns=1.00,direction=1},
    {kind="enemy",duration=6.0,approach=0.30,hold=0.40},
    {kind="player",duration=6.0,approach=0.30,hold=0.40},
  },
  {
    {kind="orbit",duration=10.5,turns=0.78,direction=-1},
    {kind="enemy",duration=7.4,approach=0.27,hold=0.48},
    {kind="player",duration=6.2,approach=0.30,hold=0.40},
  },
  {
    {kind="player",duration=6.4,approach=0.29,hold=0.42},
    {kind="orbit",duration=12.0,turns=0.88,direction=1},
    {kind="enemy",duration=8.0,approach=0.26,hold=0.52},
  },
}
local function shots() return PLANS[state.directorPlan or 1] or PLANS[1] end
local function shotDuration(shot,scale)
  scale=scale or speedScale()
  return shot.kind=="orbit" and shot.duration*scale or shot.duration
end

local cycleCache={}
local function shotCycle(list,plan,scale)
  local key=tostring(plan or 1)..":"..string.format("%.3f",scale or 1)
  local cached=cycleCache[key]
  if cached then return cached end
  local cycle=0
  for _,s in ipairs(list) do cycle=cycle+shotDuration(s,scale) end
  cycleCache[key]=cycle
  return cycle
end

local function selectedPreset()
  return mod.options:get("preset") or "dw3"
end

-- PERFORMANCE TEST1 -----------------------------------------------------
-- BattleCam.rigFor() is stable for a given arena geometry, but the stock
-- camera code asks for it repeatedly while composing every cinematic frame.
-- Cache the result and invalidate automatically if arena geometry changes.
local rigCache=setmetatable({},{__mode="k"})
local function rigForCached(camera,arena)
  if not (camera and type(camera.rigFor)=="function" and arena) then
    return camera.rigFor(arena)
  end
  local p,e=arena.player,arena.enemy
  local sig=table.concat({
    tostring(arena.cam or ""),
    tostring(p and p[1] or ""),tostring(p and p[2] or ""),
    tostring(e and e[1] or ""),tostring(e and e[2] or ""),
  },":")
  local c=rigCache[arena]
  if c and c.camera==camera and c.sig==sig then return c.rig end
  local rig=camera.rigFor(arena)
  rigCache[arena]={camera=camera,sig=sig,rig=rig}
  return rig
end

-- First Configure Preset proof: a DW3-owned framing profile.  This is saved
-- independently of the selected preset, so switching to Hero Portrait and
-- back restores the user's DW3 choice.  Framing is optical rather than a
-- positional push: the camera path remains inside the already-proven safe
-- volume while the field of view provides increasing degrees of closeness.
local function dw3FramingScale()
  local value=mod.options:get("dw3Framing") or "standard"
  if value=="near" then return 0.86 end
  if value=="close" then return 0.72 end
  return 1.00
end

-- Safe preset-direction controls. These deliberately expose artistic levels,
-- not raw coordinates. Height nudges the entire DW3 rig vertically within a
-- conservative range; Angle changes the lateral strength of the close-up /
-- shoulder compositions. Standard is exactly the v0.7.1 camera.
local function dw3HeightOffset()
  local value=mod.options:get("dw3Height") or "standard"
  if value=="low" then return math.rad(-4.0) end
  if value=="high" then return math.rad(4.0) end
  return 0
end
local function dw3AngleScale()
  local value=mod.options:get("dw3Angle") or "standard"
  if value=="shallow" then return 0.72 end
  if value=="strong" then return 1.30 end
  return 1.00
end

-- Passive opponent-side portrait proof. The camera remains safely on the
-- opponent's half of the Stadium volume, moves laterally out of the battle
-- lane, and looks back toward the player's Pokémon for an unobstructed hero
-- portrait. It never crosses onto the player's side of midfield.
local function portraitTestPose(arena,groundY,camera)
  if not arena or not arena.player or not arena.enemy then return nil,nil,0 end
  local R=rigForCached(camera,arena)

  -- Hero Portrait is a complete mirrored two-subject sequence:
  -- player portrait -> brief neutral pause -> opponent portrait -> pause.
  -- Each side uses the exact V5 lens, safe-distance geometry and subtle rise.
  local cycle=20.4
  local t=state.time%cycle
  local target,other,mirror,localT
  if t<9.4 then
    target,other,mirror,localT=arena.player,arena.enemy,1,t
  elseif t<10.2 then
    return nil,nil,0
  elseif t<19.6 then
    target,other,mirror,localT=arena.enemy,arena.player,-1,t-10.2
  else
    return nil,nil,0
  end

  local tx,tz=target[1],target[2]
  local ox,oz=other[1],other[2]
  local fx,fz=ox-tx,oz-tz
  local len=math.sqrt(fx*fx+fz*fz)
  if len<1e-4 then return nil,nil,0 end
  fx,fz=fx/len,fz/len
  local rx,rz=-fz,fx

  local w
  if localT<2.6 then
    w=smootherstep(localT/2.6)
  elseif localT<6.8 then
    w=1.0
  else
    w=1.0-smootherstep((localT-6.8)/2.6)
  end

  local holdT=math.max(0,math.min(1,(localT-2.6)/4.2))
  local micro=math.sin(holdT*math.pi*2)*math.rad(0.35)

  -- V5 breathing drift, restarted identically for each subject.
  local tiltT=math.max(0,math.min(1,(localT-2.9)/2.75))
  local tiltEase=smootherstep(tiltT)

  local baseRadius=math.sqrt(R.side*R.side+R.back*R.back)
  local radius=baseRadius*0.80
  local elevation=math.rad(12.0)

  -- Mirror the successful V5 side offset across the arena. Swapping target
  -- and opponent reverses the forward axis; mirror reverses the lateral arc.
  local arc=mirror*(math.rad(24.0)+micro)
  local ca,sa=math.cos(arc),math.sin(arc)
  local dx,dz=fx*ca+rx*sa,fz*ca+rz*sa
  local flat=radius*math.cos(elevation)

  local baseFocusY=(groundY or 0)+R.lookY+4.9
  local eye={
    tx+dx*flat,
    baseFocusY+radius*math.sin(elevation),
    tz+dz*flat,
  }

  local horizontalDistance=math.max(1,flat)
  local focusRise=horizontalDistance*math.tan(math.rad(2.25))*tiltEase
  local focus={
    tx+rx*(len*0.010)*mirror,
    baseFocusY+focusRise,
    tz+rz*(len*0.010)*mirror,
  }

  local cameraDistance=math.sqrt((eye[1]-focus[1])^2+(eye[3]-focus[3])^2)
  local frame=R.frameH*0.46
  local fov=2*math.atan((frame/2)/math.max(1,cameraDistance))
  local pitch=math.atan2(cameraDistance,math.max(1e-3,eye[2]-focus[2]))
  return {eye=eye,focus=focus,fov=fov,curve=0},pitch,w
end

local function dynamicIntroPose(arena,groundY,camera)
  if not arena or not arena.player or not arena.enemy or not state.intro.active then return nil,nil,0 end
  local R=rigForCached(camera,arena)
  local side=state.intro.side
  local target,other,mirror
  if side=="player" then target,other,mirror=arena.player,arena.enemy,1
  else target,other,mirror=arena.enemy,arena.player,-1 end
  local localT=state.intro.time
  local tx,tz=target[1],target[2]
  local ox,oz=other[1],other[2]
  local fx,fz=ox-tx,oz-tz
  local len=math.sqrt(fx*fx+fz*fz)
  if len<1e-4 then return nil,nil,0 end
  fx,fz=fx/len,fz/len
  local rx,rz=-fz,fx
  local w
  if localT<2.6 then w=smootherstep(localT/2.6)
  elseif localT<6.8 then w=1.0
  else w=1.0-smootherstep((localT-6.8)/2.6) end
  local holdT=math.max(0,math.min(1,(localT-2.6)/4.2))
  local micro=math.sin(holdT*math.pi*2)*math.rad(0.35)
  local tiltT=math.max(0,math.min(1,(localT-2.9)/2.75))
  local tiltEase=smootherstep(tiltT)
  local baseFocusY=(groundY or 0)+R.lookY+4.9

  -- Hard Dynamic Intro fallback. Do not attempt to rescue the target-relative
  -- front-axis trajectory on extreme rigs. The successful DW3 shoulder fix
  -- taught us that these maps need a different construction method entirely.
  -- For Dramatic Shape's known problem rig, or when battlers are spread much
  -- farther apart than the normal ~48 world pixels, construct the camera from
  -- the arena midpoint and a strong perpendicular offset. This guarantees the
  -- eye never travels down the line through either Pokemon.
  local extreme = (arena.cam=="wide") or (len>56.0)
  if extreme then
    local mx,mz=(arena.mid and arena.mid[1]) or ((tx+ox)*0.5),
                (arena.mid and arena.mid[2]) or ((tz+oz)*0.5)
    -- Stay predominantly beside the battle line. A small axial component keeps
    -- the portrait three-quarter rather than pure profile, while remaining far
    -- away from the dangerous front/back axis.
    local lateral=math.min(30.0,math.max(22.0,len*0.42))
    local axial=math.min(10.0,math.max(6.0,len*0.12))
    local microOffset=math.sin(holdT*math.pi*2)*0.35
    local eye={
      mx + rx*(mirror*(lateral+microOffset)) - fx*axial,
      baseFocusY + 10.5,
      mz + rz*(mirror*(lateral+microOffset)) - fz*axial,
    }
    local cameraDistance=math.sqrt((eye[1]-tx)^2+(eye[3]-tz)^2)
    local focusRise=cameraDistance*math.tan(math.rad(2.25))*tiltEase
    local focus={tx,baseFocusY+focusRise,tz}
    -- Recover intimacy optically rather than by moving the eye closer.
    local frame=R.frameH*0.43
    local fov=2*math.atan((frame/2)/math.max(1,cameraDistance))
    local pitch=math.atan2(cameraDistance,math.max(1e-3,eye[2]-focus[2]))
    if diagnosticsOn() then
      logDiagnostic(string.format("dynamic intro midpoint fallback: cam=%s spacing=%.1f",tostring(arena.cam),len))
    end
    return {eye=eye,focus=focus,fov=fov,curve=0},pitch,w
  end

  -- Established Hero Portrait intro for normal arenas.
  local baseRadius=math.sqrt(R.side*R.side+R.back*R.back)
  local radius=baseRadius*0.80
  local elevation=math.rad(12.0)
  local arc=mirror*(math.rad(24.0)+micro)
  local ca,sa=math.cos(arc),math.sin(arc)
  local dx,dz=fx*ca+rx*sa,fz*ca+rz*sa
  local flat=radius*math.cos(elevation)
  local eye={tx+dx*flat,baseFocusY+radius*math.sin(elevation),tz+dz*flat}
  local horizontalDistance=math.max(1,flat)
  local focusRise=horizontalDistance*math.tan(math.rad(2.25))*tiltEase
  local focus={tx+rx*(len*0.010)*mirror,baseFocusY+focusRise,tz+rz*(len*0.010)*mirror}
  local cameraDistance=math.sqrt((eye[1]-focus[1])^2+(eye[3]-focus[3])^2)
  local frame=R.frameH*0.46
  local fov=2*math.atan((frame/2)/math.max(1,cameraDistance))
  local pitch=math.atan2(cameraDistance,math.max(1e-3,eye[2]-focus[2]))
  return {eye=eye,focus=focus,fov=fov,curve=0},pitch,w
end

local function cinematicPose(arena,groundY,camera)
  local t=state.time
  local list=shots()
  local orbitScale=speedScale()
  local cycle=shotCycle(list,state.directorPlan,orbitScale)
  if cycle<=0 then return nil end
  t=t%cycle
  local shot,localT
  for _,candidate in ipairs(list) do
    local d=shotDuration(candidate,orbitScale)
    if t<d then shot,localT=candidate,t/d break end
    t=t-d
  end
  if not shot then return nil end

  local R=rigForCached(camera,arena)
  -- Dramatic Shape marks cramped indoor arenas with the wide rig. Those are
  -- exactly the maps where the target-relative shoulder trajectory can be
  -- redirected through both battlers by surrounding voxels. On those maps,
  -- use a conservative midpoint-based shoulder fallback: it preserves the
  -- subject bias and timing, but never travels down the line between mons.
  local cramped = arena and arena.cam == "wide"
  local mx,mz=arena.mid[1],arena.mid[2]
  local baseRadius=math.sqrt(R.side*R.side+R.back*R.back)
  local yaw0=math.atan2(R.side,R.back)
  local yaw,radius,elevation,focusBias,frameScale
  local portraitEyeX,portraitEyeZ

  if shot.kind=="orbit" then
    local q=localT; local u=smootherstep(q)
    yaw=yaw0+u*math.pi*2*(shot.turns or 1)*(shot.direction or 1)
    radius=baseRadius*(1.15+0.025*math.sin(q*math.pi*2)+0.012*math.sin(q*math.pi*4+0.7))
    elevation=math.rad(41.5+1.4*math.sin(q*math.pi*2-0.4)+0.6*math.sin(q*math.pi*6))+dw3HeightOffset()
    focusBias=0.025*math.sin(q*math.pi*2+0.8)
    frameScale=1.22+0.018*math.sin(q*math.pi*2+1.2)
  else
    local side=(shot.kind=="enemy") and 1 or -1
    local approach,holdPhase=0,0
    local approachEnd=shot.approach or 0.30
    local holdLength=shot.hold or 0.40
    local holdEnd=approachEnd+holdLength
    local departLength=math.max(1e-4,1-holdEnd)
    if localT<approachEnd then approach=smoothstep(localT/approachEnd)
    elseif localT<=holdEnd then approach=1; holdPhase=(localT-approachEnd)/math.max(1e-4,holdLength)
    else approach=1-smoothstep((localT-holdEnd)/departLength) end
    local travel=math.sin(math.pi*math.min(1,localT/approachEnd))
    if localT>holdEnd then travel=math.sin(math.pi*math.min(1,(1-localT)/departLength))
    elseif localT>=approachEnd then travel=0 end
    local micro=(holdPhase>0) and math.sin(holdPhase*math.pi*2) or 0
    if cramped then
      -- Safe fallback for narrow voxel arenas. Keep the camera farther back,
      -- reduce the inward travel, and avoid constructing an eye point from
      -- the target-to-opponent axis (the path that can be shoved through both
      -- models by geometry correction).
      radius=baseRadius*(1.14-0.10*approach+0.004*micro)
      elevation=math.rad(20.0-3.5*approach+1.2*travel+0.12*micro)+dw3HeightOffset()
      focusBias=side*(0.12+0.40*approach)
      frameScale=1.18-0.08*approach+0.002*micro
    else
      radius=baseRadius*(1.07-0.31*approach+0.006*micro)
      elevation=math.rad(18.0-10.0*approach+3.5*travel+0.18*micro)+dw3HeightOffset()
      focusBias=side*(0.18+0.68*approach)
      frameScale=1.10-0.27*approach+0.003*micro
    end
    if (not cramped) and arena.player and arena.enemy then
      local px,pz=arena.player[1],arena.player[2]
      local ex,ez=arena.enemy[1],arena.enemy[2]
      local tx,tz,ox,oz
      if shot.kind=="enemy" then tx,tz,ox,oz=ex,ez,px,pz else tx,tz,ox,oz=px,pz,ex,ez end
      local fx,fz=ox-tx,oz-tz; local fl=math.sqrt(fx*fx+fz*fz)
      if fl>1e-4 then
        fx,fz=fx/fl,fz/fl
        local rx,rz=-fz,fx
        local arc=side*(math.sin(localT*math.pi)*math.rad(5.0)+micro*math.rad(0.55))*dw3AngleScale()
        local ca,sa=math.cos(arc),math.sin(arc)
        local dx,dz=fx*ca+rx*sa,fz*ca+rz*sa
        local flatPortrait=radius*math.cos(elevation)
        portraitEyeX,portraitEyeZ=tx+dx*flatPortrait,tz+dz*flatPortrait
      end
    end
    yaw=yaw0+side*math.rad(12)*dw3AngleScale()
  end

  local focusX,focusZ=mx+R.lookX,mz
  local focusY=(groundY or 0)+R.lookY
  if shot.kind~="orbit" then focusY=focusY+3.6 end
  if focusBias~=0 and arena.player and arena.enemy then
    local px,pz=arena.player[1],arena.player[2]
    local ex,ez=arena.enemy[1],arena.enemy[2]
    local tx=(px+ex)*0.5+(ex-px)*0.5*focusBias
    local tz=(pz+ez)*0.5+(ez-pz)*0.5*focusBias
    focusX,focusZ=focusX+(tx-mx),focusZ+(tz-mz)
  end
  local flat=radius*math.cos(elevation)
  local eye={portraitEyeX or (focusX+math.sin(yaw)*flat),focusY+radius*math.sin(elevation),portraitEyeZ or (focusZ+math.cos(yaw)*flat)}
  local focus={focusX,focusY,focusZ}
  local dist=math.max(1,radius)
  -- Apply the user's DW3 framing only at the final optical stage.  Standard
  -- is bit-for-bit the existing composition; Near and Close narrow the lens
  -- without moving the eye closer to either battler or changing the safe
  -- narrow-arena fallback trajectory.
  local opticalFrameScale=frameScale*dw3FramingScale()
  return {eye=eye,focus=focus,fov=2*math.atan(((R.frameH*opticalFrameScale)/2)/dist),curve=0},
         math.atan2(flat,math.max(1e-3,eye[2]-focusY)),1
end

-- Configure Preset --------------------------------------------------------
-- Gen1Recomp's stock mod-options schema is intentionally flat. Battle
-- Cinematics already has engine_internals permission, so we add one narrowly
-- scoped ManagerState row that opens a second options-style screen. Nothing is
-- written into Gen1Recomp's files: this is a runtime wrapper for this mod only.
local MOD_ID="BATTLE_CINEMATICS"
local PRESET_KEYS={ dw3Framing=true, circleSpeed=true, dw3Height=true, dw3Angle=true }

local function schemaRow(manager,key)
  local loader=manager and manager.game and manager.game.mods
  local schema=loader and loader.optionSchemas and loader.optionSchemas[MOD_ID]
  for _,row in ipairs(schema or {}) do
    if row.key==key then return row end
  end
end

local function choiceLabel(manager,row)
  if not row then return "----" end
  local cur=manager:optionValue(MOD_ID,row)
  for _,choice in ipairs(row.choices or {}) do
    if choice[2]==cur then return choice[1] end
  end
  return ((row.choices or {})[1] or {})[1] or "----"
end

local function stepChoice(manager,row,dir)
  if not row then return end
  local choices=row.choices or {}
  if #choices==0 then return end
  local cur=manager:optionValue(MOD_ID,row)
  local index=1
  for i,choice in ipairs(choices) do
    if choice[2]==cur then index=i break end
  end
  index=((index-1+(dir or 1))%#choices)+1
  manager:setOption(MOD_ID,row.key,choices[index][2])
end

local okRows,OptionRows=pcall(require,"src.ui.OptionRows")
local okFont,Font=pcall(require,"src.render.Font")
local okTheme,Theme=pcall(require,"src.ui.Theme")
local PresetConfigState={}
PresetConfigState.__index=PresetConfigState
PresetConfigState.isOpaque=true
PresetConfigState.screenId="BattleCinematicsPresetConfig"

function PresetConfigState.new(manager,preset)
  local self=setmetatable({},PresetConfigState)
  self.manager=manager
  self.game=manager.game
  self.preset=preset or "dw3"
  self.cursor=1
  self.scroll=0
  self.rows={}

  if self.preset=="dw3" then
    local keys={"dw3Framing","circleSpeed","dw3Height","dw3Angle"}
    for _,key in ipairs(keys) do
      local def=schemaRow(manager,key)
      self.rows[#self.rows+1]={
        id=key,
        label=def and def.label or key,
        value=function() return choiceLabel(manager,def) end,
        step=function(_,dir) stepChoice(manager,def,dir); return true end,
      }
    end
    self.rows[#self.rows+1]={
      id="__preset_reset", label="RESET TO DEFAULT", value=function() return "" end,
      activate=function()
        for _,key in ipairs(keys) do
          local def=schemaRow(manager,key)
          if def then manager:setOption(MOD_ID,key,def.default) end
        end
        if manager.notify then manager:notify("DW3 DEFAULTS RESTORED") end
      end,
    }
  else
    -- Contextual second page is live now; Hero-specific controls can be added
    -- without growing the main options list when that preset is tuned next.
    self.rows[#self.rows+1]={
      id="__hero_future", label="HERO PORTRAIT", value=function() return "NO OPTIONS YET" end,
    }
  end
  return self
end

function PresetConfigState:update(dt)
  local input=self.game.input
  local n=#self.rows
  if input:wasPressed("b") then self.game.stack:pop(); return end
  if n==0 then return end
  if input:wasPressed("up") then
    self.cursor=((self.cursor-2)%n)+1
  elseif input:wasPressed("down") then
    self.cursor=(self.cursor%n)+1
  elseif input:wasPressed("left") or input:wasPressed("right") or input:wasPressed("a") then
    local row=self.rows[self.cursor]
    local dir=input:wasPressed("left") and -1 or 1
    if row.activate and input:wasPressed("a") then row.activate()
    elseif row.step then row.step(self.game,dir) end
  end
  if okRows and OptionRows then
    self.scroll=OptionRows.clampScroll(self.cursor,self.scroll or 0,n,nil)
  end
end

function PresetConfigState:draw()
  if okRows and OptionRows then
    OptionRows.draw(self.game,self.rows,self.cursor,self.scroll or 0)
    if okFont and Font then
      love.graphics.setColor(0,0,0,1)
      Font.draw(self.preset=="dw3" and "DW3 SETTINGS B:DONE" or "HERO SETTINGS B:DONE",8,136)
      love.graphics.setColor(1,1,1,1)
    end
    return
  end
end

local okManager,ManagerState=pcall(require,"src.mods.ManagerState")
if okManager and ManagerState then
  -- Provider is refreshed on hot reload; wrapper itself is installed once.
  ManagerState.__bcPresetConfigProvider=function(manager)
    local preset=mod.options:get("preset") or "dw3"
    manager.game.stack:push(PresetConfigState.new(manager,preset))
  end
  if not ManagerState.__bcPresetConfigWrapped then
    local originalBuildOptionRows=ManagerState.buildOptionRows
    ManagerState.buildOptionRows=function(self,m,schema)
      local rows=originalBuildOptionRows(self,m,schema)
      if not m or m.id~=MOD_ID then return rows end

      local filtered={}
      for _,row in ipairs(rows) do
        if not PRESET_KEYS[row.id] then
          filtered[#filtered+1]=row
        end
      end

      local insertAt=#filtered
      for i,row in ipairs(filtered) do
        if row.id=="preset" then insertAt=i+1 break end
      end
      local configure={
        id="__bc_configure_preset",
        label="CONFIGURE PRESET",
        value=function()
          return (mod.options:get("preset") or "dw3")=="dw3" and "DW3 CLASSIC" or "HERO PORTRAIT"
        end,
        activate=function()
          local provider=ManagerState.__bcPresetConfigProvider
          if provider then provider(self) end
        end,
      }
      table.insert(filtered,insertAt,configure)
      return filtered
    end
    ManagerState.__bcPresetConfigWrapped=true
  end
else
  mod.log:warn("Configure Preset menu unavailable on this Gen1Recomp build")
end

local Game=require("src.core.Game")

-- Install the same cinematic wrapper into every compatible camera backend.
-- This is the key compatibility seam: we no longer assume that the battle
-- renderer carrying the active BattleCam table must have the DRAMATIC_SHAPE
-- manifest id. Whichever backend actually asks for a rig receives the same
-- Battle Cinematics choreography, using that backend's own rig constants.
local function installBackendCamera(backend)
  local BattleCam=backend.BattleCam
  if BattleCam.__bcStandaloneDW3Wrapped then return end
  local originalRig=BattleCam.rig
  BattleCam.rig=function(arena,groundY,canonical)
    local base,pitch=originalRig(arena,groundY,canonical)
    if not canonical then
      state.rigSeen=true; state.noRig=0
      state.backendId=backend.id
    end
    if canonical or state.blend<=0 or type(base)~="table" then return base,pitch end
    local cine,cinePitch,shotWeight
    if state.intro.active then
      cine,cinePitch,shotWeight=dynamicIntroPose(arena,groundY,BattleCam)
    elseif selectedPreset()=="portrait_test" then
      cine,cinePitch,shotWeight=portraitTestPose(arena,groundY,BattleCam)
    else
      cine,cinePitch,shotWeight=cinematicPose(arena,groundY,BattleCam)
    end
    if not cine then return base,pitch end
    local w=state.blend*(shotWeight or 1)

    -- Dynamic Intro hard fallback: on the known problem rig / extreme spacing,
    -- NEVER interpolate the camera eye from the engine base rig toward the
    -- cinematic eye. That positional interpolation was the remaining crane-in
    -- through the sprite deadzone even when the destination itself was safe.
    -- Keep the engine-resolved eye completely fixed and create the close-up
    -- optically (focus + FOV) only. Normal arenas retain the established path.
    -- Zero-travel portrait safety. Dynamic Intro and Hero Portrait share the
    -- same close-up language, so on the known problem rig / extreme spacing
    -- both must avoid positional interpolation through the 2D sprite deadzone.
    -- Lock the eye to the backend's safe base rig; animate only focus/FOV.
    if (state.intro.active or selectedPreset()=="portrait_test") and arena and arena.player and arena.enemy then
      local dx=arena.enemy[1]-arena.player[1]
      local dz=arena.enemy[2]-arena.player[2]
      local spacing=math.sqrt(dx*dx+dz*dz)
      if arena.cam=="wide" or spacing>56.0 then
        local locked={
          eye={base.eye[1],base.eye[2],base.eye[3]},
          focus={mix(base.focus[1],cine.focus[1],w),mix(base.focus[2],cine.focus[2],w),mix(base.focus[3],cine.focus[3],w)},
          fov=mix(base.fov,cine.fov,w), curve=0,
        }
        return locked,mix(pitch,cinePitch,w)
      end
    end

    return mixCamera(base,cine,w),mix(pitch,cinePitch,w)
  end
  BattleCam.__bcStandaloneDW3Wrapped=true
  mod.log:info("camera backend connected: %s %s",backend.id,tostring(backend.version or ""))
end

for _,backend in ipairs(backends) do installBackendCamera(backend) end

mod.hooks:wrap("input.step",function(nextFn,game,dt)
  local result=nextFn(game,dt); dt=tonumber(dt) or 0
  state.noRig=state.noRig+dt
  if state.noRig>0.75 and state.rigSeen then
    state.rigSeen=false; resetBattle()
  end

  local battle=state.battle
  if battle and dynamicIntroOn() and state.rigSeen then
    local enemySending=not not battle.enemySendingOut
    local playerSending=not not battle.sendingOut

    -- A queued intro starts only once that side's 3D model is actually
    -- visible. This handles wild encounters, trainer send-outs and switches.
    if state.intro.pendingEnemy and not battle.showEnemyTrainer and not enemySending then
      startIntro("enemy")
    elseif state.intro.pendingPlayer and not playerSending and battle.player and not battle.showPlayerBack then
      startIntro("player")
    end
    state.intro.enemyWasSending=enemySending
    state.intro.playerWasSending=playerSending
  end

  if state.intro.active then
    local introScale=introSpeedScale()
    state.intro.time=state.intro.time+dt*introScale
    state.blend=chase(state.blend,1,dt,BLEND_TIME/introScale)
    if state.intro.time>=INTRO_DURATION then
      local completed=state.intro.side
      clearIntro()
      state.blend=0
      state.idle=0
      state.active=false
      logDiagnostic("dynamic intro complete: "..tostring(completed))
    end
    return result
  end

  -- During the initial battle introduction the selected idle preset waits
  -- until both queued portraits have completed. During later switches it
  -- restarts its normal delay after the single portrait completes.
  local introWaiting=dynamicIntroOn() and (state.intro.pendingEnemy or state.intro.pendingPlayer)
  if state.rigSeen and enabled() and not introWaiting then
    if not state.active then
      state.idle=state.idle+dt
      if state.idle>=idleDelay() then
        state.active=true; state.time=0
        logDiagnostic("cinematic active")
      end
    else state.time=state.time+dt end
  elseif not enabled() or introWaiting then
    state.active=false; state.idle=0
  end
  state.blend=chase(state.blend,(enabled() and state.active) and 1 or 0,dt,BLEND_TIME)
  return result
end,25,"BATTLE_CINEMATICS")

-- Input policy ------------------------------------------------------------
-- RESET CAMERA controls the selected idle preset. INTRO RESET CAM controls
-- Dynamic Intro independently, allowing intros to remain uninterruptible,
-- dismiss only on a committed move/item, or dismiss on any input.
local function resetMode()
  return mod.options:get("inputReturn") or "confirmed"
end
local function cancelActiveIntro(reason)
  if not state.intro.active then return false end
  local side=state.intro.side
  clearIntro()
  state.blend=0
  state.idle=0
  state.active=false
  logDiagnostic("dynamic intro reset ("..tostring(reason).."): "..tostring(side))
  return true
end
local function confirmedAction()
  if state.intro.active then
    if introResetMode()=="confirmed" then cancelActiveIntro("move/item") end
    return
  end
  if resetMode() ~= "off" then
    activity()
    logDiagnostic("move/item returned camera")
  end
end
local function rawActivity()
  if state.intro.active then
    if introResetMode()=="any" then cancelActiveIntro("any input") end
    return
  end
  if resetMode()=="any" then activity() end
end

local function wrapMethod(tbl,name,handler)
  local inner=tbl and tbl[name]
  if type(inner)~="function" or tbl["__bc_"..name] then return end
  tbl[name]=function(self,...)
    handler()
    return inner(self,...)
  end
  tbl["__bc_"..name]=true
end
wrapMethod(Game,"keypressed",rawActivity)
wrapMethod(Game,"gamepadpressed",rawActivity)
wrapMethod(Game,"touchpressed",rawActivity)
wrapMethod(Game,"mousepressed",rawActivity)

-- Mod API 2 content sandboxes in Gen1Recomp 0.1.87+ reject writes to global
-- LÖVE callbacks. Older Battle Cinematics builds replaced love.touchpressed
-- and love.mousepressed here, which aborts the entire mod during loading on
-- current builds. Game's key/gamepad/touch/mouse methods above are the
-- supported input seam and receive Android input on 0.2.53.

-- Sanctioned battle commitments. These wrappers do not alter the action;
-- they only apply the selected reset policy before the action is rendered.
local okBattle,BattleState=pcall(require,"src.battle.BattleState")
if okBattle and BattleState then
  wrapMethod(BattleState,"resolveTurn",confirmedAction)
  wrapMethod(BattleState,"tryRun",confirmedAction)
  wrapMethod(BattleState,"openItems",confirmedAction)
  wrapMethod(BattleState,"openParty",confirmedAction)
else
  mod.log:warn("move/item hooks unavailable; ANY INPUT remains supported")
end

-- Dynamic Intro lifecycle -------------------------------------------------
mod.events:on("battle.started",function(ev)
  state.battle=ev and ev.battle or nil
  state.intro.initial=true
  clearIntro()
  state.intro.pendingEnemy=dynamicIntroOn()
  state.intro.pendingPlayer=dynamicIntroOn()
  state.idle,state.time,state.active,state.blend=0,0,false,0
  logDiagnostic("battle started; dynamic introductions queued")
end)

mod.events:on("battle.battler_switched",function(ev)
  if not dynamicIntroOn() or not ev then return end
  state.battle=ev.battle or state.battle
  local side=ev.side and ev.side.index
  if side==1 then queueIntro("player")
  elseif side==2 then queueIntro("enemy") end
  state.idle,state.time,state.active,state.blend=0,0,false,0
end)

mod.events:on("battle.ended",function()
  state.battle=nil
  state.intro.pendingEnemy=false
  state.intro.pendingPlayer=false
  clearIntro()
end)

mod.exports.version="0.7.2-perf2-compat253"
mod.exports.activity=activity
mod.log:info("Battle Cinematics v0.7.2 TEST2 (0.2.53 compatibility) connected (%d camera backend%s)",#backends,#backends==1 and "" or "s")
