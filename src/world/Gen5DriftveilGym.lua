-- DRIFTVEIL GYM'S LIFTS (Black / White, zone 97): Clay's mine.
--
-- Three levels of walkways stacked on the same tiles -- heights 50, 40 and 30
-- in tiles -- over Clay's own floor at -59, which is what the map's permission
-- grid describes. The gym's overlay (43 in Black) holds the walkways and six
-- lifts, each moving between two heights (Gen5Field reads them into
-- `def.gen5Lifts`). The lift's flag 0x0A + n is SET while it is at its lower
-- height and CLEAR at its upper: the panels' scripts say so -- the "up" panel
-- moves a lift only when its flag is set ("This elevator can't go any
-- higher!" otherwise) and clears it, the "down" panel the reverse.
--
-- So the player has a LEVEL (50 on the lobby lift's arrival), and on it:
--   * a walkway of that level, or a lift standing at it, is ground; every
--     other cell is wall -- the grid below is another floor (on Clay's floor,
--     the grid's own rule applies);
--   * people and panels of other levels are not there (objects' level is the
--     NPC record's +34, signs' their +16 height -- Gen5Events);
--   * the floor is drawn at the level's height (`gen4HeightEdits`).
-- 0x190 <n> (a panel) moves lift n; a player standing on it rides along.
--
-- A CONTINUE IS NOT AN ARRIVAL. The flags are local ones (0..0x63), which the
-- zone change wipes (ov10 0x21589F4) and the gym block with them (ov20
-- 0x2185B9C), so a walk in finds the lifts as the arrival run leaves them. A
-- continue does neither, and the overlay's init (0x21F36C0) stands each lift
-- at the height its saved state says; the player's own height is part of the
-- saved position. Re-applying the arrival run on a continue put every lift
-- back and the player on the lobby level, wherever they had saved -- so the
-- level is kept in the save (`save.bwClayLevel`, this port's) and a continue
-- leaves the flags alone.

local G = {}

local function flagSet(save, flag)
  local Flags = require("src.script.Flags")
  return Flags.get(save, ("FLAG_G4_%04X"):format(flag)) and true or false
end

function G.liftHeight(save, lift)
  local lo, hi = math.min(lift.a, lift.b), math.max(lift.a, lift.b)
  return flagSet(save, lift.flag) and lo or hi
end

local function inside(r, x, z) return x >= r.x and x < r.x + r.w and z >= r.z and z < r.z + r.h end

local function levels(gl)
  local set, bottom = {}, nil
  for _, s in ipairs(gl.strips or {}) do set[s.level] = true end
  for _, l in ipairs(gl.lifts or {}) do
    for _, h in ipairs({ l.a, l.b }) do if not set[h] and (not bottom or h < bottom) then bottom = h end end
  end
  return set, bottom
end

-- true blocks, false is ground, nil asks the map's own grid
function G.collides(run, save, x, z)
  local gl, L = run.gl, run.level
  if not run.levelSet[L] then return nil end
  for _, s in ipairs(gl.strips) do if s.level == L and inside(s, x, z) then return false end end
  for _, l in ipairs(gl.lifts) do if G.liftHeight(save, l) == L and inside(l, x, z) then return false end end
  return true
end

local function publish(ow, run, save)
  local map, def = ow.map, ow.map and ow.map.def
  if not def then return end
  map.gen5Level = run.level
  -- the floor at the level's height, 16 world units to a tile
  local edits, h = {}, run.level * 16
  if run.levelSet[run.level] then
    for _, s in ipairs(run.gl.strips) do
      if s.level == run.level then
        for zz = s.z, s.z + s.h - 1 do for xx = s.x, s.x + s.w - 1 do edits[xx .. "," .. zz] = h end end
      end
    end
    for _, l in ipairs(run.gl.lifts) do
      if G.liftHeight(save, l) == run.level then
        for zz = l.z, l.z + l.h - 1 do for xx = l.x, l.x + l.w - 1 do edits[xx .. "," .. zz] = h end end
      end
    end
  else
    for zz = 0, (def.height or 32) - 1 do
      for xx = 0, (def.width or 32) - 1 do
        if map.isWalkableCell and map:isWalkableCell(xx, zz) then edits[xx .. "," .. zz] = h end
      end
    end
  end
  def.gen4HeightEdits = edits
  -- people of other levels are not on this one
  run.hidden = run.hidden or {}
  for _, npc in ipairs(ow.npcs or {}) do
    local lvl = npc.def and npc.def.gen5Level
    if lvl then
      if not run.levelSet[lvl] then lvl = run.bottom end
      -- (passable as well as hidden: the lifts' rail blockers are BURIED,
      -- which keeps a hidden object in the way -- Collision.entityAbsent)
      if lvl ~= run.level then
        if not npc.hidden or not npc.passable then
          npc.hidden, npc.passable = true, true
          run.hidden[npc] = true
        end
      elseif run.hidden[npc] then
        npc.hidden, npc.passable = nil, nil
        run.hidden[npc] = nil
      end
    end
  end
end

function G.attach(ow, save, continuing)
  local def = ow and ow.map and ow.map.def
  local gl = def and def.gen5Lifts
  if not (gl and save) then return nil end
  local set, bottom = levels(gl)
  local level = continuing and tonumber(save.bwClayLevel) or gl.start or 50
  local run = { gl = gl, level = level, levelSet = set, bottom = bottom or -59 }
  -- the lifts' places on arrival (the entry script the overlay runs:
  -- Gen5Field reads its set / clear run into `initial`) -- not on a continue
  local Flags = require("src.script.Flags")
  for flag, on in pairs((not continuing) and gl.initial or {}) do
    local name = ("FLAG_G4_%04X"):format(tonumber(flag) or 0)
    if on then Flags.set(save, name) elseif Flags.clear then Flags.clear(save, name) end
  end
  save.bwClayLevel = run.level
  ow.gen5LiftRun = run
  def.gen4CollisionHook = function(_, x, z) return G.collides(run, save, x, z) end
  def.gen4PropFollow = function(o) publish(o, run, save) end
  publish(ow, run, save)
  return run
end

-- 0x190 <n>: the flag still says where the lift is (the script flips it
-- after), so the player aboard goes to the other height
function G.move(ow, save, n)
  local run = ow.gen5LiftRun or G.attach(ow, save)
  local lift = run and run.gl.lifts[n + 1]
  if not lift then return end
  local from = G.liftHeight(save, lift)
  local to = (from == lift.a) and lift.b or lift.a
  local p = ow.player
  if p and run.level == from and inside(lift, p.cellX, p.cellY) then
    run.level = to
    save.bwClayLevel = to
  end
end

return G
