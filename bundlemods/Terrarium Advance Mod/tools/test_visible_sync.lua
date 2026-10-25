-- StandaloneHost visible-boundary sync (Gen 4/5): headless test.
--   lua tools/test_visible_sync.lua [lib/StandaloneHost.lua]   (run from the mod root)
--
-- Loads the real StandaloneHost with stubbed providers and drives a fake
-- BattleState queue shaped like one Gen 4 turn as BattleState builds it:
--   "X used Y!" text -> anim row (3-frame pre-delay + 40-frame hold) ->
--   HP drain row (20 frames) -> "It's super effective!" text
-- Both semantic events are emitted on the frame the queue is BUILT, exactly
-- as performMove / EffectRegistry do. The test records the frame on which the
-- CBE consumer (CurrentSpriteModels stand-in) receives each event, and checks
-- it against the frame the engine starts showing that row.
local path = arg and arg[1] or "lib/StandaloneHost.lua"

local function loadMod(p, V)
  local f = assert(io.open(p, "rb")); local src = f:read("*a"); f:close()
  return assert((loadstring or _G.load)(src, "@" .. p))(V)
end

local frame = 0
local received = {}
local consumer = { event = function(_, _, name, payload) received[#received + 1] = { name = name, frame = frame } end }
consumer.update = function() end
-- any read of an undefined global inside the host is a crash in the game
-- (a forward-referenced local reads as a nil global): make it loud here
local strict = { __index = function(_, k) error("undefined global read: " .. tostring(k), 2) end }
local director = { seen = {}, event = function(self, _, name) self.seen[#self.seen + 1] = { name = name, frame = frame } end }

local function run(gen4, label)
  frame = 0; received = {}; director.seen = {}
  local V = { mod = { log = { info = function() end, warn = function() end, error = function() end } },
              CurrentSpriteModels = consumer, BattleDirector = director }
  local H = loadMod(path, V)
  local battle = { queue = {}, nextInsert = 0, phase = "messages", __cbePresentationQueueSync = true,
                   gen4Layout = function() return gen4 end }
  H.session = { battle = battle, started = true, presented = true,
                context = { battle = battle, sides = { player = {}, enemy = {} } },
                pendingSemantics = { move = { player = {}, enemy = {} }, damage = { player = {}, enemy = {} },
                                     faint = { player = {}, enemy = {} } } }
  local target = { isPlayer = false }

  -- the engine builds the turn (one logic step)
  local text = { text = "PIPLUP used BUBBLE!" }
  local anim = { anim = "BUBBLE" }
  local drain = { drain = true, battler = target }
  local eff = { text = "It's super effective!" }
  battle.queue = { text, anim, drain, eff }
  battle.moveAnimRow = anim
  battle.nextInsert = 2
  H.event("battle.move_used", { battle = battle, user = {}, target = target })
  battle.nextInsert = 3
  H.event("battle.damage_dealt", { battle = battle, user = {}, target = target, damage = 12 })

  -- a minimal updateQueue: the same row semantics as BattleState's
  local shown = {}
  local textLeft = 0
  local function updateQueue(b)
    if (b.waitFrames or 0) > 0 then b.waitFrames = b.waitFrames - 1; return true end
    if b.draining then b.drainLeft = b.drainLeft - 1; if b.drainLeft > 0 then return true end; b.draining = nil end
    if textLeft > 0 then textLeft = textLeft - 1; if textLeft > 0 then return true end end
    local item = table.remove(b.queue, 1)
    if not item then return false end
    if item.anim then
      if not item.animDelayed then
        item.animDelayed = true; table.insert(b.queue, 1, item); b.waitFrames = 3; return true
      end
      shown.anim = frame; b.waitFrames = 40; return true
    end
    if item.drain then shown.drain = frame; b.draining = true; b.drainLeft = 20; return true end
    if item.text then shown[item.text] = frame; textLeft = 30; return true end
    return true
  end
  -- what StandaloneHost's updateQueue wrapper does around the engine call
  for _ = 1, 400 do
    frame = frame + 1
    -- the logic step's host update (StandaloneHost.update), exactly as the
    -- input.step hook calls it every step
    setmetatable(_G, strict)
    local okU, errU = pcall(H.update, 1 / 60)
    setmetatable(_G, nil)
    if not okU then error("H.update failed: " .. tostring(errU)) end
    local held = H.session.visibleHolds and #H.session.visibleHolds > 0
    if held then H.releaseVisible(battle, false, true) end
    local more = updateQueue(battle)
    if held then H.releaseVisible(battle, false, false) end
    if not more then break end
  end

  local at = {}
  for _, r in ipairs(received) do at[r.name] = at[r.name] or r.frame end
  local dir = {}
  for _, r in ipairs(director.seen) do dir[r.name] = dir[r.name] or r.frame end
  print(string.format("%-28s text@%-3s anim@%-3s drain@%-3s | CBE move@%-3s damage@%-3s | director move@%-3s damage@%-3s",
    label, tostring(shown["PIPLUP used BUBBLE!"]), tostring(shown.anim), tostring(shown.drain),
    tostring(at["battle.move_used"]), tostring(at["battle.damage_dealt"]),
    tostring(dir["battle.move_used"]), tostring(dir["battle.damage_dealt"])))
  return shown, at, dir
end

local fails = 0
local function check(cond, msg) if not cond then print("FAIL: " .. msg); fails = fails + 1 end end

local shown, at, dir = run(true, "Gen 4/5 (sync on)")
check(at["battle.move_used"] == shown.anim, "move must reach CBE on the anim-start frame")
check(at["battle.damage_dealt"] == shown.drain, "damage must reach CBE on the drain-start frame")
check(dir["battle.move_used"] == shown.anim, "director must see the move at the same frame")

local _, at2 = run(false, "Gen 1-3 (unchanged)")
check(at2["battle.move_used"] == 0 and at2["battle.damage_dealt"] == 0,
      "Gen 1-3 must still receive both events on the build frame (old behaviour)")

print(fails == 0 and "PASS" or ("FAILED " .. fails))
_G.__exitCode = fails > 0 and 1 or 0
if not _G.__runnerHost and fails > 0 then os.exit(1) end
