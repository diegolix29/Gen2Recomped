-- HEARTGOLD / SOULSILVER: HOW A MAP OBJECT IS DRAWN, where that is not "its
-- billboard, unless the object is hidden".
--
-- 1. THE MODEL OBJECTS. pret's sprite table (asm/overlay_01_sprite_data.s,
-- ov01_022074A8) gives twelve sprites the MMODEL_BABYBOY1 texture with render
-- bits 0x1E4 / 0x1E2 and no animation (63 << 10): the Goldenrod Tunnel's gates
-- (SPRITE_GATE_LEFT / RIGHT / TOP / BOTTOM), the Department Store warehouse's
-- containers (SPRITE_BABYBOY1_5), the Basement door (SPRITE_BABYBOY1_8) and
-- the rest of the BABYBOY1_n family. Their renderer (ov01_021F8CFC) never
-- draws that texture: it looks the sprite up in ov01_022073D8 and hangs a
-- field-effect model on the object (ov01_021FD2EC), so the object -- its
-- position, its scripted walks, its visibility -- carries a model from
-- fldeff.narc. Read as an ordinary sprite here, every one of them was a baby
-- boy: the B2F switch puzzle showed two toddlers flanking each barrier.
--
-- WHICH MODEL: ov01_022073D8 lists the sprites in the order the field-effect
-- archive stores their models, members 106 on -- 0xFD (the container) is the
-- 4th row and member 109 is `box`, the four gates are rows 5..8 and members
-- 110..113 are `rshutter`, `lshutter`, `ushutter`, `dshutter`, and the
-- Basement door (row 2) is `door3`, the shutter with the key slot.
--
-- So each such object keeps its billboard switched off and drives a LIVE
-- runtime prop (Gen4Ground:runtimePropsFor) that follows it a frame at a
-- time; the prop is dropped while the object is hidden or invisible.
--
-- 2. INVISIBLE BUT THERE. MapObject_SetVisible(TRUE) -- the script commands
-- MakeObjectVisible and ScrCmd_374 (see Gen4ScriptVM) -- sets bit 9, which
-- only stops the object being DRAWN: it still blocks, can still be talked to
-- and walked, and its event flag is untouched. The SPRITE_STOP blockers of
-- the tunnel's gates and Vermilion Gym are the main users. It belongs to the
-- live object, so a map load (which builds the objects afresh on the
-- cartridge) clears it: here it is remembered against the map instance it
-- was set on, and the pooled NPC that comes back on a later visit is drawn.

local M = {}

-- sprite id -> fldeff member (ov01_022073D8 row i is member 106 + i)
M.MEMBER = {
  [0x0B7] = 106, -- SPRITE_BABYBOY1_2   dun_spot
  [0x100] = 107, -- SPRITE_BABYBOY1_8   door3 (Goldenrod Tunnel's Basement door)
  [0x101] = 108, -- SPRITE_BABYBOY1_9   door4
  [0x0FD] = 109, -- SPRITE_BABYBOY1_5   box (the Dept. Store warehouse's containers)
  [0x0FB] = 110, -- SPRITE_GATE_RIGHT   rshutter
  [0x0FC] = 111, -- SPRITE_GATE_LEFT    lshutter
  [0x0FE] = 112, -- SPRITE_GATE_TOP     ushutter
  [0x0FF] = 113, -- SPRITE_GATE_BOTTOM  dshutter
  [0x120] = 114, -- SPRITE_BABYBOY1_10  m_present01
  [0x123] = 115, -- SPRITE_BABYBOY1_12  alfu_hole
  [0x124] = 116, -- SPRITE_BABYBOY1_13  alfu_door
  [0x121] = 117, -- SPRITE_BABYBOY1_11  leag_door1
}

local function isHgss(game)
  local v = game and game.data and game.data.gen4_version
  return v and v.family == "hgss"
end

local function noDraw() end

-- is this entity invisible on this visit?
function M.invisible(ow, e)
  return e and e.gen4Invisible and e.gen4InvisibleMap == (ow and ow.map) or false
end

-- MakeObjectVisible (on = true) / ScrCmd_374 (on = false)
function M.setInvisible(ow, e, on)
  if not e then return end
  e.gen4Invisible = on and true or nil
  e.gen4InvisibleMap = on and ow and ow.map or nil
  M.applyDraw(ow, e)
end

-- the entity's draw: off while it is a model object or invisible, its class's
-- own otherwise (an instance field shadows the class method)
function M.applyDraw(ow, e)
  if e.hgssModelLive or M.invisible(ow, e) then
    e.draw = noDraw
  elseif e.draw == noDraw then
    e.draw = nil
  end
end

-- once a frame from OverworldState:update
function M.update(game, ow)
  if not (ow and ow.map and ow.map.def and isHgss(game)) then return end
  local def = ow.map.def
  local list
  for _, npc in ipairs(ow.npcs or {}) do
    local member = npc.def and M.MEMBER[tonumber(npc.def.graphicsId) or -1]
    if member and not npc.gen4Follower then
      list = list or {}
      list[#list + 1] = npc
    end
  end
  local key = ow.hgssModelObjects
  local same = key and key.def == def and #key.npcs == #(list or {})
  if same then
    for i, npc in ipairs(list or {}) do if key.npcs[i] ~= npc then same = false break end end
  end
  if not same then
    -- a fresh props table, so the ground re-splits it by chunk; another
    -- system's props on this map are kept, this module's old ones dropped
    local props = {}
    for _, p in ipairs(def.gen4RuntimeProps or {}) do
      if not p.hgssModelObject then props[#props + 1] = p end
    end
    for _, npc in ipairs(list or {}) do
      local live = { px0 = npc.px or 0, py0 = npc.py or 0 }
      npc.hgssModelLive = live
      local ground = ow.map.renderer and ow.map.renderer.gen4Ground
      local y = ground and ground.heightAt and ground:heightAt(npc.cellX or 0, npc.cellY or 0) or 0
      props[#props + 1] = { model = M.MEMBER[tonumber(npc.def.graphicsId)], archive = "fldeff",
        hgssModelObject = true, live = live,
        x = (npc.px or 0) + 8, y = tonumber(y) or 0, z = (npc.py or 0) + 8 }
    end
    def.gen4RuntimeProps = props
    ow.hgssModelObjects = { def = def, npcs = list or {} }
  end
  for _, npc in ipairs(list or {}) do
    local live = npc.hgssModelLive
    if live then
      local dx, dz = (npc.px or 0) - live.px0, (npc.py or 0) - live.py0
      live.dx = dx ~= 0 and dx or nil
      live.dz = dz ~= 0 and dz or nil
      live.hidden = (npc.hidden or M.invisible(ow, npc)) and true or nil
    end
  end
  for _, npc in ipairs(ow.npcs or {}) do
    if npc.gen4Invisible or npc.hgssModelLive or npc.draw == noDraw then M.applyDraw(ow, npc) end
  end
  if ow.player and (ow.player.gen4Invisible or ow.player.draw == noDraw) then M.applyDraw(ow, ow.player) end
end

return M
