-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE "!" WHERE HEARTGOLD / SOULSILVER PUT IT, over anyone -- the player
-- included -- under every camera.
--
-- THE CARTRIDGE (pokeheartgold asm/overlay_01_022001E4.s):
--
--   ov01_02200540 starts the effect on a map object; every frame
--   ov01_02200614 asks for the object's DRAW position (ov01_021F93AC, so a
--   jump or sprite offset comes along) and adds (0, +32, +1) units -- the top
--   of a 32-unit character and one unit toward the camera. The bubble is
--   model 118 ("!") / 125 ("!!") of /a/1/0/3, a billboard whose plane spans
--   0..16 units up from that anchor, and its rise is world-vertical too:
--   velocity 6 less 2 a frame until it lands back on 0, then 0x1E frames held.
--   Its textures are byte for byte Platinum's fldeff 85 / 108 (measured).
--
-- WHAT THAT MEANS ON A SCREEN. The characters are full billboards 32 units
-- tall standing on their feet, so on screen a sprite is 32 pixels high at any
-- pitch; the bubble's anchor is 32 WORLD units up, which the camera leans by
-- cos(pitch) like every other height. At HGSS's own 48.68 degrees that is 21
-- pixels: the bubble's tail sits on the head, eleven rows inside the 32-pixel
-- frame, where the DS draws it -- not on the frame's empty top edge, ten
-- pixels clear of the hair, where the sprite-top rule put it.
--
-- So the anchor goes through the camera now drawing:
--
--   cartridge / tilt rungs   feet - (32 + rise) x heightScale + 1 x groundScale,
--                            in the flat screen space the sprite is drawn in
--   third / first person     Gen4Ground:freeEntity with the anchor as a pose
--                            lift -- the same projection the sprite gets --
--                            depth-tested at the bubble's middle
--   first person, the player there is no body to stand it on (the player is
--                            the eye), so it is shown at the top of the view
--                            for its usual life rather than not at all
--
-- Platinum keeps its sprite-top placement and timing, unchanged by request:
-- `FAMILIES` is the switch.

local Gen4Emotes = require("src.import.Gen4Emotes")

local D = {}

-- Platinum too: its cartridge anchors the bubble the same 32 units above the
-- owner, and the old flat placement sat it ~10 px high there as well (users
-- reported the "!" not sitting over the player under tilted / free cameras).
-- A Platinum map names no camera family, so an unnamed Gen 4 map is it.
D.FAMILIES = { hgss = true, platinum = true, bw = true }
-- BLACK / WHITE (ov21 0x21BB808, src/import/Gen5FieldEffects.lua): the
-- anchor is the owner's drawn position + (0, 22 + bounce, 0) turned by the
-- CAMERA, so the lift runs straight up the screen at one pixel a unit, under
-- any pitch -- not up the world as Sinnoh's and Johto's 32 do
D.BW_LIFT = 22
D.LIFT = Gen4Emotes.LIFT     -- 32
D.TOWARD = 1                 -- +1 z (0x1000), toward the camera
D.FEET_X, D.FEET_Y = 8, 12   -- Gen4Ground.FEET_X / FEET_Y

function D.applies(map)
  local def = map and map.def
  if not def then return false end
  local family = def.cameraFamily
  if def.gen5 then family = "bw" end
  if family == nil and def.generation == 4 and not def.gen5 then family = "platinum" end
  return family and D.FAMILIES[family] or false
end

-- The bounce in world units at `age` engine ticks, at the field's rate.
function D.rise(def, age)
  local ticks = Gen4Emotes.ticksFor(def)
  return Gen4Emotes.bounce(math.floor((tonumber(age) or 0) / ticks))
end

-- The owner where it is DRAWN: its pose when it has one (a hop, a sprite
-- offset), else its position. `pose` is what the sprite's own draw reads.
local function drawnAt(npc)
  local sprite, px, py = npc.sprite, npc.px or 0, npc.py or 0
  if npc.pose then
    local ok, s2, ppx, ppy = pcall(npc.pose, npc)
    if ok and s2 then sprite, px, py = s2, ppx or px, ppy or py end
  end
  return sprite, px, py
end

-- The terrain rise the owner's sprite is drawn with -- OverworldController's
-- `riseOf`, sprite offset included, so the bubble rides a surf mount with them.
local function riseOf(ground, npc, cam)
  local rise = ground:rise((npc.px or 0) + (npc.shiftPx or 0) + 8, (npc.py or 0) + 8) or 0
  local so = npc.spriteOffset
  if so and (so.lift or so.oz) then
    rise = rise + (so.lift or 0) * (ground.heightScale or 0)
              - (so.oz or 0) * (ground.groundScale or 1)
  end
  local sinP = ground.groundScale or 1
  if sinP < 1 then rise = ((npc.py or 0) - cam.y) * (1 - sinP) + rise end
  return rise
end

-- flatSpot(ground, npc, cam, w, h, rise) -> left, top of the bubble in the
-- flat (cartridge / tilt) screen space
function D.flatSpot(ground, npc, cam, w, h, up)
  local sprite, px, py = drawnAt(npc)
  local camY = cam.y + riseOf(ground, npc, cam)
  -- the sprite's own horizontal centre (SpriteRenderer:draw)
  local sw = (sprite and sprite.tileW) or 16
  local cx = math.floor(px - cam.x) - ((sprite and sprite.offsetX) or 0) + sw / 2
  -- the feet: SpriteRenderer's bottom edge, `py - camY + 12` for any size
  local feet = math.floor(py - camY) + ((sprite and sprite.cellYBias) or -4) + 16
  local bottom = feet - (D.LIFT + (up or 0)) * (ground.heightScale or 1)
                 + D.TOWARD * (ground.groundScale or 1)
  if D.screenUp then bottom = feet - (D.BW_LIFT + (up or 0)) end
  return math.floor(cx - w / 2 + 0.5), math.floor(bottom - h + 0.5)
end

-- groundSpot(ground, px, py, cam) -> the screen x of a tile's centre and the
-- screen y of its ground, in the same flat space (a field effect standing on
-- the cell whose map pixel corner is px, py: Gen5Phenomena, the rod's lure)
function D.groundSpot(ground, px, py, cam)
  local fake = { px = px, py = py }
  local camY = cam.y + riseOf(ground, fake, cam)
  return math.floor(px - cam.x) + 8, math.floor(py - camY) + 12
end

-- draw(ow, ground, npc, cam, record, img, age) -- one bubble
function D.draw(ow, ground, npc, cam, record, img, age)
  local g = love.graphics
  local w, h = record.width or img:getWidth(), record.height or img:getHeight()
  local def = ow.map and ow.map.def
  local up = D.rise(def, age)
  D.screenUp = def and def.gen5 and true or false
  local free = ground.freeMode and ground:freeMode()

  if free == "first" and npc == ow.player then
    -- the eye is the player: the top of the view, at the view's own scale
    local vw, vh = ground.freeW, ground.freeH
    if not (vw and vh) then return end
    local s = vh / 192
    g.push("all")
    if g.setDepthMode then pcall(g.setDepthMode, "always", false) end
    g.setShader()
    g.setColor(1, 1, 1, 1)
    g.draw(img, math.floor(vw / 2 - w * s / 2), math.floor(vh * 0.16 - (h + up) * s), 0, s, s)
    g.pop()
    return
  end

  if free then
    -- the anchor as a lift on the owner's own pose, so freeEntity projects
    -- it exactly as it projects their feet; the drawing then hangs the
    -- bubble's bottom-centre on the point that projection lands on
    local base = require("src.world.Gen4SurfMount").poseFor(npc,
      npc == ow.player and ow.dwPose or nil)
    local pose = {}
    for k, v in pairs(base or {}) do pose[k] = v end
    local _, ppx, ppy = drawnAt(npc)
    -- a hop is drawn as a flat shift inside the sprite's own draw; the
    -- bubble takes the same shift
    local dx, dy = ppx - (npc.px or 0), ppy - (npc.py or 0)
    -- Black / White: the lift is up the billboard (the camera), so it is
    -- drawn inside the owner's own plane rather than as a world lift
    local screenUp = D.screenUp and (D.BW_LIFT + up) or 0
    if not D.screenUp then
      pose.lift = (pose.lift or 0) + D.LIFT + up
      pose.oz = (pose.oz or 0) + D.TOWARD
    end
    pose.entity = nil
    local gx = (npc.px or 0) + D.FEET_X + (pose.ox or 0)
    local fy = (npc.py or 0) + D.FEET_Y
    ground:freeEntity(npc.px or 0, npc.py or 0, cam.x, cam.y, 0, function()
      g.setColor(1, 1, 1, 1)
      g.draw(img, math.floor(gx - cam.x - w / 2 + dx), math.floor(fy - cam.y - h + dy - screenUp))
    end, h / 2, pose)
    return
  end

  local bx, by = D.flatSpot(ground, npc, cam, w, h, up)
  g.setColor(1, 1, 1, 1)
  g.draw(img, bx, by)
end

return D
