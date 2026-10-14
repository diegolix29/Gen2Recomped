-- THE FRONTIER ENGINE'S OWN ROWS (see src/script/Gen4FrontierVM.lua):
-- variables by the frontier's rule, the scene's objects and pictures, the
-- scene changes, and the system variables the field shares with it.

local Commands = require("src.script.Commands")
local G4 = require("src.script.Gen4Commands")
local Logger = require("src.core.Logger")

local M = {}

-- a frontier operand: 0x8000 and up is a variable, anything below a literal
function M.value(ctx, n)
  n = tonumber(n) or 0
  if n >= 0x8000 then return math.floor(tonumber(G4.getVar(ctx.save, n)) or 0) end
  return n
end
function M.store(ctx, var, v)
  var = tonumber(var)
  if var and var >= 0x8000 then G4.setVar(ctx.save, var, math.floor(tonumber(v) or 0) % 65536) end
end
local value, store = M.value, M.store
local function scene(ctx) return ctx.frontierScene end

-- ------------------------------------------------------------- the script --

function Commands.fr_stop(ctx) end

-- FrontierScrCmd_ExitFrontier: the scene ends, the field carries on
function Commands.fr_exit(ctx)
  local sc = scene(ctx)
  if sc then sc.exitPending = true end
end

-- ChangeSceneWithinScript: the backdrop and the people go, the script goes on
function Commands.fr_change_scene(ctx, id)
  local sc = scene(ctx)
  if not sc then return end
  sc.objects, sc.order, sc.monPics = {}, {}, {}
  sc:setScene(value(ctx, id))
end

-- ChangeScript: the new scene's own entry point (offset id `entry`)
function Commands.fr_change_script(ctx, id, entry)
  local sc = scene(ctx)
  if not sc then return end
  local VM = require("src.script.Gen4FrontierVM")
  local sid = value(ctx, id)
  sc.objects, sc.order, sc.monPics = {}, {}, {}
  sc:setScene(sid)
  local spec = sc.spec
  local label = spec.member and VM.entryLabel(ctx.game.data, spec.member, value(ctx, entry))
  local rows = label and VM.compile(ctx.game.data, spec.member, label, spec.bank)
  if rows then
    sc.pendingRows = rows
  else
    sc.exitPending = true
  end
end

function Commands.fr_set(ctx, dest, v) store(ctx, dest, value(ctx, v)) end
function Commands.fr_add(ctx, dest, v, sign)
  store(ctx, dest, value(ctx, dest) + (tonumber(sign) or 1) * value(ctx, v))
end
function Commands.fr_compare(ctx, a, b)
  ctx.g4Compare = G4.compare(value(ctx, a), value(ctx, b))
end

-- GetSystemVar / SetSystemVar: the field's own variable, by number
function Commands.fr_get_system_var(ctx, sysVar, dest)
  store(ctx, dest, tonumber(G4.getVar(ctx.save, tonumber(sysVar))) or 0)
end
function Commands.fr_set_system_var(ctx, sysVar, v)
  G4.setVar(ctx.save, tonumber(sysVar), value(ctx, v))
end

-- OBJ_EVENT_GFX_PLAYER_M (0) / _F (97)
function Commands.fr_player_gfx(ctx, dest)
  local p = ctx.save and ctx.save.player or {}
  local female = (p.gender == 1 or p.gender == "female" or p.gender == "girl")
  store(ctx, dest, female and 97 or 0)
end

function Commands.fr_wait(ctx, frames)
  ctx.runner.waitingFrames = math.max(1, tonumber(frames) or 1)
  ctx.runner:yield()
end

function Commands.fr_buffer_species(ctx, slot, var)
  return Commands.g4_buffer(ctx, slot, "species", value(ctx, var))
end
-- BufferMoveName / BufferTypeName: the operand by the frontier's rule
function Commands.fr_buffer_kind(ctx, slot, kind, var)
  return Commands.g4_buffer(ctx, slot, kind, value(ctx, var))
end
function Commands.fr_random(ctx, dest, bound)
  local n = math.max(1, value(ctx, bound))
  store(ctx, dest, love.math.random(0, 65535) % n)
end

-- IncrementRecordValue <record> / AddToRecordValue <record> <operand>
function Commands.fr_record(ctx, record, amount)
  local R = require("src.pokemon.Gen4GameRecords")
  local id = tonumber(record)
  if not id then return end
  if amount ~= nil then R.add(ctx.save, id, value(ctx, amount)) else R.increment(ctx.save, id) end
end

-- SaveData_SaveStateInit: the save, and whether it went
function Commands.fr_save(ctx, dest)
  local okSave = pcall(function()
    if ctx.game.saveGame then ctx.game:saveGame() end
  end)
  store(ctx, dest, okSave and 1 or 0)
end

-- ------------------------------------------------------------- the scene --

local function member(ctx)
  local sc = scene(ctx)
  local VM = require("src.script.Gen4FrontierVM")
  return sc and sc.spec and VM.member(ctx.game.data, sc.spec.member)
end

-- FrontierScrCmd_24: the people, from the list the operand names
function Commands.fr_objects(ctx, label)
  local sc, m = scene(ctx), member(ctx)
  local list = m and m.data[label]
  if not (sc and list) then return end
  for _, row in ipairs(list.rows) do
    local id = value(ctx, row.id)
    local gfx = row.gfx
    local isPlayer = false
    if gfx == 0xEEEE then
      local female = (ctx.save.player or {}).gender
      gfx = (female == 1 or female == "female" or female == "girl") and 97 or 0
      isPlayer = true
    elseif gfx == 0xEEEF then
      -- a link partner: alone, the multi partner's own sprite stands in
      gfx = value(ctx, 0x800A)
    else
      gfx = value(ctx, gfx)
    end
    -- THE 0xEEEE OBJECT IS THE CAMERA'S, not a second player: the cartridge
    -- puts it in the reserved slot 31, never walks it in either Hall scene,
    -- and the player everyone sees is the 0x800A object beside it (whose
    -- sprite GetPlayerObjEventGfx chose -- in a multi challenge, each player's
    -- own). It is placed, followed, and not drawn.
    local o = sc:addObject({ id = id, x = row.x, y = row.y, dir = row.dir, b = row.b, anchor = isPlayer }, gfx)
    o.isPlayer = isPlayer
  end
end

function Commands.fr_remove_object(ctx, id)
  local sc = scene(ctx)
  if sc then sc:removeObject(value(ctx, id)) end
end

-- FrontierScrCmd_26: an object's visibility flag
function Commands.fr_object_flag(ctx, id, flag)
  local sc = scene(ctx)
  local o = sc and sc.objects[value(ctx, id)]
  if o then o.hidden = (tonumber(flag) or 0) ~= 0 end
end

function Commands.fr_move(ctx, id, label)
  local sc, m = scene(ctx), member(ctx)
  if not sc then return end
  sc:move(value(ctx, id), m and m.movements[label])
end

function Commands.fr_wait_move(ctx)
  local sc = scene(ctx)
  if not (sc and sc:moving()) then return end
  ctx.runner.waitingCheck = function() return not sc:moving() end
  ctx.runner:yield()
end

-- FrontierScrCmd_45: a party Pokemon's front picture at (x, y)
function Commands.fr_show_mon(ctx, slot, x, y)
  local sc = scene(ctx)
  local mon = sc and ctx.save.party and ctx.save.party[value(ctx, slot) + 1]
  if not mon then return end
  local img
  local ok = pcall(function()
    local Sprites = require("src.pokemon.Sprites")
    local path = Sprites.path(ctx.game.data, mon.species, "front", mon)
    img = path and require("src.render.Assets").image(path)
  end)
  sc.monPics[value(ctx, slot)] = { image = ok and img or nil, x = value(ctx, x), y = value(ctx, y) }
end
function Commands.fr_hide_mon(ctx, slot)
  local sc = scene(ctx)
  if sc then sc.monPics = {} end
  local _ = slot
end

-- FadeScreen: even types fade to black, odd ones back from it (the field's rule)
function Commands.fr_fade(ctx, fadeType, steps, framesPerStep)
  local sc = scene(ctx)
  if not sc then return end
  local t = math.floor(tonumber(fadeType) or 0)
  local n = math.max(1, math.floor(tonumber(steps) or 6) * math.max(1, math.floor(tonumber(framesPerStep) or 1)))
  sc.fadeTarget = (t % 2 == 0) and 1 or 0
  sc.fadeStep = 1 / n
  sc.fade = sc.fade or 0
end
function Commands.fr_wait_fade(ctx)
  local sc = scene(ctx)
  if not (sc and sc.fadeTarget and sc.fade ~= sc.fadeTarget) then return end
  ctx.runner.waitingCheck = function() return sc.fade == sc.fadeTarget end
  ctx.runner:yield()
end

-- FrontierScrCmd_3F: the battle transition (the battle itself is the
-- facility's StartBattle); a beat of black
function Commands.fr_battle_transition(ctx)
  local sc = scene(ctx)
  if not sc then return end
  sc.fade = 1
  ctx.runner.waitingFrames = 20
  ctx.runner:yield()
  sc.fade = 0
end

Logger.debug("gen4 frontier: engine rows registered")
return M
