-- BLACK AND WHITE'S MAP EVENTS (/a/1/2/5, one file per zone, 428).
--
--   u32 size of what follows the counts, then u8 counts: interactables, NPCs,
--   warps, triggers -- and the records in that order, 20 / 36 / 20 / 22 bytes.
--   427 of the 428 files add up to the byte with those sizes.
--
-- Positions are ABSOLUTE tiles on the zone's matrix (Striaton's NPCs stand at
-- x 740..795 on a map whose corner is 736), so every one is taken back to
-- the map by its origin. Field by field, read from Striaton (zone 6):
--
--   interactable  u16 script, u16 kind, u16, u16, u32 x, u32 y, ...
--   NPC           u16 id, u16 sprite, u16 movement, u16 type, u16 flag,
--                 u16 script, u16 facing (0 up 1 down 2 left 3 right), ...
--                 u16 x @28, u16 y @30, and a PAIR at @14 / @16 whose
--                 meaning is the object's: sprite 185 (no picture -- 54
--                 objects) is an invisible blocker that wide and tall
--                 (Striaton's gym curtains are 7 x 1 at (9, 34/24/14)); a
--                 trainer's @14 is its sight range (the gym's two: 6); on
--                 anyone else the pair is the wander range
--   warp          u16 destination zone, u16 destination warp, ...,
--                 u16 x @8 and u16 y @12 in pixels (tile * 16 + 8)
--   trigger       u16 script, u16 value, u16 var, u16 (0 in every one
--                 read), u16, u16 x, u16 y, u16 width, u16 height -- the
--                 VALUE is the second halfword: Accumula's Plasma speech fires
--                 at var 0x407A == 2, after Juniper's Pokemon Center tour sets
--                 2, and Route 1's exit at 0x407C == 1, after her demonstration
--
-- Written in the shape Platinum's map defs carry (objects, warps, signs,
-- coordEvents), so the Gen 4 overworld places them.

local E = {}

local function u8(s, o) return s:byte(o + 1) or 0 end
local function u16(s, o) return u8(s, o) + u8(s, o + 1) * 256 end
local function u32(s, o) return u16(s, o) + u16(s, o + 2) * 65536 end
local function s16(s, o) local v = u16(s, o) return v >= 0x8000 and v - 0x10000 or v end

-- RAIL POSITIONS. On a rail map (Castelia, Skyarrow ...) a record whose flag
-- halfword is 1 is placed not by tile but by <line, along, across>: the rail
-- line's index, the step along it from its first point (a line's own step
-- count is its record's sixth word), and the tiles to its side. Every kind
-- carries the same three, only at its own offset -- a warp's flag at +6, a
-- sign's at +6, a trigger's at +8, each followed by the three; an NPC's flag
-- at +24 and the three at +28 (where its tile x / y otherwise sit).
-- Gen5Field turns them into tiles once the rails are read (E.placeOnRails).
local function railAt(d, o, flag, at)
  if u16(d, o + flag) ~= 1 then return nil end
  at = o + (at or flag + 2)
  return { line = u16(d, at), along = u16(d, at + 2), across = s16(d, at + 4) }
end

function E.parse(d)
  if type(d) ~= "string" or #d < 8 then return nil end
  local nf, nn, nw, nt = u8(d, 4), u8(d, 5), u8(d, 6), u8(d, 7)
  if 4 + nf * 20 + nn * 36 + nw * 20 + nt * 22 ~= u32(d, 0) then return nil, "sizes do not add up" end
  local out = { signs = {}, npcs = {}, warps = {}, triggers = {} }
  local at = 8
  for i = 0, nf - 1 do
    local o = at + i * 20
    out.signs[i + 1] = { index = i, script = u16(d, o), kind = u16(d, o + 2), x = u32(d, o + 8), y = u32(d, o + 12),
      rail = railAt(d, o, 6), height = s16(d, o + 16) }
  end
  at = at + nf * 20
  for i = 0, nn - 1 do
    local o = at + i * 36
    out.npcs[i + 1] = { index = i, localId = u16(d, o), sprite = u16(d, o + 2), movementType = u16(d, o + 4),
      trainerType = u16(d, o + 6), flag = u16(d, o + 8), script = u16(d, o + 10), direction = u16(d, o + 12),
      x = u16(d, o + 28), y = u16(d, o + 30), paramA = u16(d, o + 14), paramB = u16(d, o + 16),
      level = s16(d, o + 34),
      rail = railAt(d, o, 24, 28) }
  end
  at = at + nn * 36
  for i = 0, nw - 1 do
    local o = at + i * 20
    -- +4 `kind` is the CONTACT DIRECTION (ov10 0x21626B8 against the
    -- facing: 2 up, 1 down, 4 left, 3 right, 0 none) and +5 the TRANSITION
    -- type (ov10 0x21626E8). Types 0, 5 and 6 are taken by STEPPING ONTO the
    -- cell once a step ends (ov21 0x218AEAC, mask 0x61, run from 0x218ACD0
    -- after the coord events); every other type by a press that matches
    -- the contact direction (0x218AED4).
    out.warps[i + 1] = { index = i, destZone = u16(d, o), destWarp = u16(d, o + 2),
      kind = d:byte(o + 5), transition = d:byte(o + 6),
      x = math.floor(u16(d, o + 8) / 16), y = math.floor(u16(d, o + 12) / 16),
      width = math.max(u16(d, o + 14), 1), height = math.max(u16(d, o + 16), 1), rail = railAt(d, o, 6) }
  end
  at = at + nw * 20
  for i = 0, nt - 1 do
    local o = at + i * 22
    out.triggers[i + 1] = { index = i, script = u16(d, o), var = u16(d, o + 4), value = u16(d, o + 2),
      x = u16(d, o + 10), y = u16(d, o + 12), width = u16(d, o + 14), height = u16(d, o + 16) }
    -- THE RAIL SHAPE: halfword +8 is 1 on nine triggers (Castelia's, Route
    -- 4's ...), and then a rail position <line, along, across> sits before
    -- the extent. Read as the first shape, Castelia's 1 x 8 strip on line
    -- 4 was 65531 tiles wide.
    if u16(d, o + 8) == 1 then
      local t = out.triggers[i + 1]
      t.rail = railAt(d, o, 8)
      t.width, t.height = u16(d, o + 16), u16(d, o + 18)
    end
  end
  return out
end

-- attach(def, events, spriteFor) -- fills a Gen 4-shaped map def's lists
E.BLOCKER_SPRITE = 185
function E.attach(def, ev, spriteFor)
  if not (def and ev) then return end
  local ox, oy = def.originX or 0, def.originY or 0
  def.objects, def.warps, def.signs, def.coordEvents = {}, {}, {}, {}
  for _, n in ipairs(ev.npcs) do
    local sprite, name = spriteFor(n.sprite)
    def.objects[#def.objects + 1] = { index = n.index + 1, localId = n.localId, graphicsId = n.sprite,
      sprite = sprite, spriteName = name, x = n.x - ox, y = n.y - oy, direction = n.direction,
      movementType = n.movementType, movementRangeX = 0, movementRangeY = 0, trainerType = n.trainerType,
      -- the same flag namespace the script engine's setflag/clearflag write
      -- (Gen4ScriptVM.flagName), so a script hiding an NPC hides THIS one
      flag = n.flag, eventFlag = n.flag ~= 0 and ("FLAG_G4_%04X"):format(n.flag) or nil,
      script = n.script, elevation = 0, gen5 = true, rail = n.rail, gen5Level = n.level }
    local obj = def.objects[#def.objects]
    if n.sprite == 0 then
      -- SPRITE 0 IS A GYM GIMMICK, drawn by the gym's own overlay rather
      -- than as a character: Castelia's seven honey walls, Driftveil's
      -- lifts, Icirrus's and Dragonspiral's pieces (24 objects on 6 maps).
      -- Their picture is the overlay's model, not a sprite sheet -- member 0
      -- drew a placeholder box -- so they are BURIED: not drawn, still there
      obj.gen5Gimmick, obj.buried = true, true
    end
    if n.sprite == E.BLOCKER_SPRITE then
      -- never drawn, always in the way: the state `buried` already means
      -- (OverworldController seeds it from the def). Striaton's gym curtains
      -- are three of these, walked aside by the right doorway's script.
      obj.gen5Blocker, obj.buried = true, true
      obj.footprintW, obj.footprintH = math.max(n.paramA or 1, 1), math.max(n.paramB or 1, 1)
    elseif n.script >= 3000 and n.script < 7000 then
      -- A TRAINER, by its script's band exactly as on Gen 4: 3000.. single,
      -- 5000.. double, the remainder the trainer id (Striaton's gym runs
      -- 3009 / 3010 -- Waiter Maxwell and Waitress Tia, the waiters standing
      -- there). The sight range is the pair's first half; which ways it looks
      -- is Gen 4's rule on the trainer type (2 all round, 1 its facing).
      local double = n.script >= 5000
      obj.trainer = { id = n.script - (double and 5000 or 3000), battler = double and 1 or 0 }
      obj.sightRange = n.paramA
      local ty = n.trainerType or 0
      obj.sightWays = ty == 2 and 4 or ((ty == 1 or (ty >= 4 and ty <= 8)) and 1 or 0)
    else
      obj.movementRangeX, obj.movementRangeY = n.paramA or 0, n.paramB or 0
    end
  end
  for _, w in ipairs(ev.warps) do
    def.warps[#def.warps + 1] = { index = w.index + 1, x = w.x - ox, y = w.y - oy,
      destMap = ("Z%03d"):format(w.destZone), destHeader = w.destZone, destWarp = w.destWarp + 1,
      kind = w.kind, transition = w.transition, width = w.width, height = w.height, rail = w.rail }
  end
  -- (`destWarp` is 1-based, as the engine indexes `warps[destWarp]` and the
  -- Gen 4 importer writes it; the cartridge's number is 0-based.)
  -- A WARP COVERS A RECTANGLE: halfwords +14 / +16 are its width and height
  -- (a gym's exit mat 3 x 1, Route 2's gate edge 1 x 3, the Dreamyard's 1 x
  -- 4). The extra cells go AFTER every real warp, so a destination's
  -- `destWarp` still indexes the list as the cartridge numbers it.
  for _, w in ipairs(ev.warps) do
    for dy = 0, (w.height or 1) - 1 do
      for dx = 0, (w.width or 1) - 1 do
        if dx > 0 or dy > 0 then
          def.warps[#def.warps + 1] = { index = #def.warps + 1, extentOf = w.index + 1,
            x = w.x - ox + dx, y = w.y - oy + dy, destMap = ("Z%03d"):format(w.destZone),
            destHeader = w.destZone, destWarp = w.destWarp + 1, kind = w.kind,
            transition = w.transition, rail = w.rail, railDX = dx, railDY = dy }
        end
      end
    end
  end
  for _, s in ipairs(ev.signs) do
    def.signs[#def.signs + 1] = { index = s.index + 1, x = s.x - ox, y = s.y - oy, script = s.script,
      kind = s.kind, elevation = 0, rail = s.rail,
      -- a sign's height is world units at +16 (Clay's lift panels stand at
      -- 800 / 640 / 480 / -944, i.e. levels 50 / 40 / 30 / -59 in tiles)
      gen5Level = s.height and math.floor(s.height / 16) or nil }
  end
  for _, t in ipairs(ev.triggers) do
    def.coordEvents[#def.coordEvents + 1] = { index = t.index + 1, x = t.x - ox, y = t.y - oy,
      width = t.width, height = t.height, script = t.script, var = t.var, value = t.value, elevation = 0,
      rail = t.rail }
  end
end

-- placeOnRails(def, toTile) -- gives every rail-placed entry its tile:
-- toTile(line, along, across) -> map tile x, y (or nil off the data).
-- A RAIL EXTENT IS IN THE RAIL'S AXES: width is steps ALONG the line,
-- height tiles ACROSS it -- Z030's exits are 1 x 8, a strip across the
-- street's whole width, and Castelia's gate to the bridge 1 x 4. So a
-- warp's extra cells are each placed through the rail (attach's dx is the
-- step along, dy the tile across), and a trigger's rectangle is the box of
-- its two far corners.
function E.placeOnRails(def, toTile)
  local placed = 0
  for _, list in ipairs({ def.objects or {}, def.warps or {}, def.signs or {} }) do
    for _, e in ipairs(list) do
      local r = e.rail
      if r then
        local x, y = toTile(r.line, r.along + (e.railDX or 0), r.across + (e.railDY or 0))
        if x then e.x, e.y = x, y; placed = placed + 1 end
      end
    end
  end
  for _, e in ipairs(def.coordEvents or {}) do
    local r = e.rail
    if r then
      local x0, y0 = toTile(r.line, r.along, r.across)
      local x1, y1 = toTile(r.line, r.along + math.max((e.width or 1) - 1, 0), r.across + math.max((e.height or 1) - 1, 0))
      if x0 and x1 then
        e.x, e.y = math.min(x0, x1), math.min(y0, y1)
        e.width, e.height = math.abs(x1 - x0) + 1, math.abs(y1 - y0) + 1
        placed = placed + 1
      end
    end
  end
  return placed
end

return E
