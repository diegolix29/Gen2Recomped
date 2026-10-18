-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- EVERY GEN 4 MOVE ANIMATION, AGAINST WHAT THE PLAYER CAN RUN.
--
-- For each move id 1..MOVES (467 in Platinum and HGSS) this runs the move's
-- program through `Gen4MoveAnimPlayer` twice (attacker on each side) as a dry
-- pass, and collects:
--   * moves with NO program (fall back to nothing),
--   * every command / callfunc / emitter callback / sprite callback the player
--     reported through `missing()`, by frequency and by how many moves need it,
--   * moves whose particle systems are not in the cache,
--   * moves that end with no visible layer at all (no battler motion, no
--     particles, no 2D sprite, no BG effect) -- the "generic or nothing" set.
--
-- Usage (LuaJIT, no LOVE needed):
--   python tools/run_lua_check.py tools/gen4_move_anim_audit.lua \
--       G:/Gen2Recomped/heartgold/data/generated [moves=467] [verbose]
--
-- Reads the install's cache READ-ONLY.

local root = (arg[0] or ""):gsub("[^/\\]*$", "")
if root ~= "" then package.path = root .. "../?.lua;" .. package.path end
package.path = "./?.lua;" .. package.path

local dir = arg[1] or "G:/Gen2Recomped/platinum/data/generated"
local MOVES = tonumber(arg[2]) or 467
local verbose = arg[3] == "verbose"
-- arg[4]: a ROM path. When given, the PROGRAMS are decoded from the cartridge
-- in memory (with the current decoder) instead of read from the cache, so a
-- decoder fix can be measured without re-importing. HGSS's we.arc is
-- /a/0/1/0, Platinum's /wazaeffect/we.arc.
local romPath = arg[4]

local function load(name)
  local f = loadfile(dir .. "/" .. name .. ".lua")
  if not f then return nil end
  local ok, v = pcall(f)
  return ok and v or nil
end

local data = {
  gen4_move_anims = load("gen4_move_anims"),
  gen4_particles = load("gen4_particles"),
  gen4_cellactors = load("gen4_cellactors"),
}
local moves = load("moves") or {}

if romPath then
  local NdsRom = require("src.import.NdsRom")
  local Narc = require("src.import.NarcArchive")
  local Anim = require("src.import.Gen4MoveAnim")
  local rom = assert(NdsRom.open(romPath))
  local bytes = rom:read("/wazaeffect/we.arc") or rom:read("/a/0/1/0")
  local arc = assert(Narc.parse(assert(bytes, "no we.arc")))
  local programs, skipped = {}, 0
  for index = 0, arc.count - 1 do
    local decoded = Anim.decode(arc:get(index))
    if decoded then
      local code, wordAt = {}, {}
      for i, row in ipairs(decoded) do
        local ins = { row.op }
        for j = 1, #row.args do ins[j + 1] = row.args[j] end
        code[i], wordAt[i] = ins, row.at
      end
      programs[index] = { code = code, wordAt = wordAt }
    else
      skipped = skipped + 1
    end
  end
  data.gen4_move_anims = { programs = programs, count = arc.count, skipped = skipped }
  print(("decoded %d programs from %s (%d did not decode)"):format(arc.count, romPath, skipped))
end

local Player = require("src.battle.Gen4MoveAnimPlayer")
local p = Player.new(data)
if not p then
  print("no gen4_move_anims in " .. dir)
  os.exit(1)
end
-- The battle answers this in game (BattleState wires `cryPlaying`); the audit
-- has no audio, so no cry is ever still playing.
p.cryPlaying = function() return false end

local byWhat, movesWhat = {}, {}
local noProgram, empty, budget = {}, {}, {}
local perMove = {}
local okMoves = 0

local function nameOf(id)
  local m = moves[id]
  return (m and (m.name or m.displayName)) or ("#" .. id)
end

for id = 1, MOVES do
  local prog = data.gen4_move_anims.programs[id]
  if not (prog and prog.code and #prog.code > 0) then
    noProgram[#noProgram + 1] = id
  else
    local gaps, seen = {}, {}
    local visible = false
    for _, side in ipairs({ true, false }) do
      p:start(id, side)
      p.quiet = true
      local frames = 0
      while p:update() do
        frames = frames + 1
        local st = p.state
        if (st[true].dx ~= 0 or st[true].dy ~= 0 or st[false].dx ~= 0
            or st[false].dy ~= 0 or st[true].sx ~= 1 or st[false].sx ~= 1
            or st[true].sy ~= 1 or st[false].sy ~= 1
            or st[true].hidden or st[false].hidden
            or st[true].tint or st[false].tint)
          or (p.emitters and #p.emitters > 0)
          or (p.sprites and #p.sprites > 0)
          or p.bgLayer or next(p.groups or {}) or p.grayscale
          or st[true].ghosts or st[false].ghosts or p.screenFlash or p.bgScroll
          or (st[true].rot or 0) ~= 0 or (st[false].rot or 0) ~= 0
          or (st[true].alpha or 1) < 1 or (st[false].alpha or 1) < 1 then
          visible = true
        end
        if frames > (Player.Player.FRAME_BUDGET or 2000) + 10 then
          budget[#budget + 1] = id
          break
        end
      end
      for _, row in ipairs(p:missing()) do
        if not seen[row.what] then
          seen[row.what] = true
          gaps[#gaps + 1] = row.what
          movesWhat[row.what] = (movesWhat[row.what] or 0) + 1
        end
        byWhat[row.what] = (byWhat[row.what] or 0) + row.count
      end
    end
    if not visible then empty[#empty + 1] = id end
    if #gaps == 0 then okMoves = okMoves + 1 end
    perMove[id] = gaps
  end
end

print(("== %s"):format(dir))
print(("moves 1..%d: %d with a program, %d without; %d fully supported (no gap on either side)")
  :format(MOVES, MOVES - #noProgram, #noProgram, okMoves))

local rows = {}
for what, n in pairs(byWhat) do rows[#rows + 1] = { what, n, movesWhat[what] } end
table.sort(rows, function(a, b)
  if a[3] ~= b[3] then return a[3] > b[3] end
  return a[1] < b[1]
end)
print(("\nunsupported (by moves affected) -- %d kinds"):format(#rows))
print(("  %-48s %8s %6s"):format("what", "uses", "moves"))
for _, r in ipairs(rows) do
  print(("  %-48s %8d %6d"):format(r[1], r[2], r[3]))
end

local function list(t)
  local out = {}
  for _, id in ipairs(t) do out[#out + 1] = ("%d %s"):format(id, nameOf(id)) end
  return table.concat(out, ", ")
end
print(("\nno program (%d): %s"):format(#noProgram, list(noProgram)))
print(("\nnothing visible on either side (%d): %s"):format(#empty, list(empty)))
print(("\nhit the frame budget (%d): %s"):format(#budget, list(budget)))

-- STATIC: every callfunc / sprite callback named anywhere in a move's
-- program (both arms of every branch), against what the player has.
do
  local P = Player.Player
  local Extras = require("src.battle.Gen4MoveAnimExtras").load()
  local builtin = {}
  for _, id in pairs(P.FUNC) do builtin[id] = true end
  local missF, missS = {}, {}
  for id = 1, MOVES do
    local prog = data.gen4_move_anims.programs[id]
    for _, row in ipairs(prog and prog.code or {}) do
      if row[1] == 45 then
        local f = row[2]
        if not builtin[f] and not Extras.FUNCS[f] then
          missF[f] = missF[f] or {}
          missF[f][#missF[f] + 1] = id
        end
      elseif row[1] == 78 then
        local f = row[3]
        if f and not P.SPRITE_MOTION[f] and not rawget(Extras.SPRITES, f) then
          missS[f] = missS[f] or {}
          missS[f][#missS[f] + 1] = id
        end
      end
    end
  end
  local function dump(t, label, names)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys)
    print(("\nstatic: %s with no port (%d)"):format(label, #keys))
    for _, k in ipairs(keys) do
      print(("  %3d %-24s moves %s"):format(k, names and names[k] or "", table.concat(t[k], ",")))
    end
  end
  dump(missF, "callfunc ids")
  dump(missS, "sprite callbacks", P.SPRITE_FUNCS)
end

if verbose then
  print("\nper move gaps:")
  for id = 1, MOVES do
    if perMove[id] and #perMove[id] > 0 then
      print(("  %3d %-16s %s"):format(id, nameOf(id), table.concat(perMove[id], ", ")))
    end
  end
end
