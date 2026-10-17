-- tools/gen4_hgss_overworld_harness/main.lua
--
-- tools/gen4_overworld_harness, standing on an INSTALLED version folder.
--
--   INSTALL=G:/Gen2Recomped/heartgold VERSION=heartgold MAP=T20 X=14 Y=14 \
--     love tools/gen4_hgss_overworld_harness
--
-- The overworld harness reads data through POKEPORT_DATA_DIR and pictures
-- through POKEPORT_ASSET_ROOT, but the 3D ground opens its packed geometry
-- (`terrain/chunks.bin`) with love.filesystem, which only sees what is
-- mounted -- the launcher mounts a version's cache (CacheFs.mountVersion) and
-- a bare harness does not. So this mounts INSTALL at the root, read-only,
-- with the same PHYSFS_mount CacheFs uses, sets the two variables from it, and
-- hands over to the overworld harness unchanged. Pictures land in this
-- harness's own save folder (identity hgss_ow).

local install = assert(os.getenv("INSTALL"), "set INSTALL to the version's folder")

local ffi = require("ffi")
pcall(ffi.cdef, "int PHYSFS_mount(const char *newDir, const char *mountPoint, int appendToPath);")
local mounted = false
for _, lib in ipairs({ function() return ffi.C end, function() return ffi.load("love") end }) do
  local ok, l = pcall(lib)
  if ok and l then
    local okf, fn = pcall(function() return l.PHYSFS_mount end)
    if okf and fn and fn(install, "", 1) ~= 0 then mounted = true break end
  end
end
print(("mounted %s: %s"):format(install, tostring(mounted)))

-- OUT_DIR: write the harness's PNGs there (plain io) instead of LÖVE's save
-- folder -- for a machine whose system drive has no room
local outDir = os.getenv("OUT_DIR")
if outDir then
  local probe = love.image.newImageData(1, 1)
  local mt = getmetatable(probe)
  local index = mt and mt.__index
  local encode = index and index.encode
  if encode then
    index.encode = function(self, format, filename)
      local data = encode(self, format)
      if filename then
        local f = assert(io.open(outDir .. "/" .. filename, "wb"))
        f:write(data:getString()); f:close()
        return data
      end
      return data
    end
  end
end

-- the overworld harness reads these two at load time
local env = { POKEPORT_DATA_DIR = install .. "/data/generated", POKEPORT_ASSET_ROOT = install }
local getenv = os.getenv
os.getenv = function(k) return env[k] or getenv(k) end

-- PARTY_DETAIL=1: with the overworld harness's "party after" line, each
-- member's species and friendship (what a script's friendship row changed)
if os.getenv("PARTY_DETAIL") then
  local print0 = print
  print = function(first, ...)
    print0(first, ...)
    if type(first) == "string" and first:match("^party after") then
      local G = package.loaded["src.core.Game"]
      local beaten = {}
      for id, yes in pairs((G and G.save and G.save.gen4TrainerFlags) or {}) do
        if yes then beaten[#beaten + 1] = tostring(id) end
      end
      table.sort(beaten)
      print0("  trainers beaten: " .. (#beaten > 0 and table.concat(beaten, ",") or "none"))
      local badges = {}
      for id, yes in pairs((G and G.save and G.save.badges) or {}) do if yes then badges[#badges + 1] = tostring(id) end end
      table.sort(badges)
      print0("  badges: " .. (#badges > 0 and table.concat(badges, ",") or "none"))
      -- SHOW_FLAGS="0x169,0x1D0": whether each is set at the end
      for id in tostring(os.getenv("SHOW_FLAGS") or ""):gmatch("%w+") do
        local C = require("src.script.Commands")
        local c = { save = G.save, game = G }
        C.check_flag(c, ("FLAG_G4_%04X"):format(tonumber(id)))
        print0(("  flag %s %s"):format(id, c.lastCheck and "set" or "clear"))
      end
      -- SHOW_SAVE="gen4SpecialLocation,hgssGymmick.candles": a save field (dotted), one level shown
      for key in tostring(os.getenv("SHOW_SAVE") or ""):gmatch("[%w_%.]+") do
        local v = G.save
        for part in key:gmatch("[^%.]+") do v = type(v) == "table" and v[part] or nil end
        local parts = {}
        if type(v) == "table" then
          for k, x in pairs(v) do parts[#parts + 1] = tostring(k) .. "=" .. tostring(x) end
          table.sort(parts)
        end
        print0(("  save.%s = %s"):format(key, type(v) == "table" and "{" .. table.concat(parts, ", ") .. "}" or tostring(v)))
      end
      -- SHOW_MAPS="R32,R_32": a loaded map def's header, generation and source
      for id in tostring(os.getenv("SHOW_MAPS") or ""):gmatch("[%w_]+") do
        local d = G.data and G.data.maps and G.data.maps[id]
        print0(("  map %s: %s"):format(id, d and ("id=%s same=%s header=%s generation=%s label=%s width=%s"):format(tostring(d.id), tostring(d == (G.data.maps[(id:gsub("_", ""))])),
          tostring(d.header), tostring(d.generation), tostring(d.label), tostring(d.width)) or "absent"))
      end
      -- SHOW_LOCAL=0: every live entity answering to that local id
      if os.getenv("SHOW_LOCAL") then
        local want = tonumber(os.getenv("SHOW_LOCAL"))
        local OWs = G.stack and G.stack.states or {}
        for _, st in ipairs(OWs) do
          for i, e in ipairs(st.entities or {}) do
            local lid = e.localId or (e.def and e.def.localId)
            if lid == want then
              print0(("  entity %d: localId %s index %s sprite %s at (%s,%s) player=%s"):format(i, tostring(lid),
                tostring(e.def and e.def.index), tostring(e.def and (e.def.spriteName or e.def.sprite)),
                tostring(e.cellX), tostring(e.cellY), tostring(e == st.player)))
            end
          end
        end
      end
      -- SHOW_BUILDINGS=1: the ground's building set and, per placement in
      -- view, whether its model resolves
      if os.getenv("SHOW_BUILDINGS") then
        for _, st in ipairs((G.stack and G.stack.states) or {}) do
          local ground = st.map and st.map.renderer and st.map.renderer.gen4Ground
          if ground then
            local set = ground.buildingSet
            print0(("  building set %s (%s models)"):format(tostring(set and set.label),
              tostring(set and set.models and #set.models)))
            local where = {}
            local grid = ground.grid
            for i, l in ipairs((grid and grid.land) or {}) do
              where[l] = where[l] or { (i - 1) % grid.width, math.floor((i - 1) / grid.width) }
            end
            for land, rec in pairs((ground.terrain and ground.terrain.chunks) or {}) do
              local ok, objs = pcall(ground.objectsFor, ground, land, rec)
              local cw = where[land]
              if cw then print0(("  land %s at chunk (%d,%d), map offset (%s,%s)"):format(tostring(land), cw[1], cw[2],
                tostring(ground.offsetX), tostring(ground.offsetY))) end
              if ok and objs and #objs > 0 and (not os.getenv("LAND") or tonumber(os.getenv("LAND")) == land) then
                local parts = {}
                for _, o in ipairs(objs) do
                  local b = ground:building(o.model, o.archive)
                  parts[#parts + 1] = ("%s%s@%.0f,%.0f,%.0f"):format(tostring(o.model), b and "" or "!", o.x or 0, o.y or 0, o.z or 0)
                end
                print0(("  land %s: %s"):format(tostring(land), table.concat(parts, " ")))
              end
            end
          end
        end
      end
      -- SHOW_PLAYER=1: the player's position and state fields
      if os.getenv("SHOW_PLAYER") then
        for _, st in ipairs((G.stack and G.stack.states) or {}) do
          local p = st.player
          if p then
            print0(("  player cell (%s,%s) px (%s,%s) moving %s hidden %s locked %s elevation %s"):format(
              tostring(p.cellX), tostring(p.cellY), tostring(p.px), tostring(p.py), tostring(p.moving),
              tostring(p.hidden or p.invisible), tostring(p.inputLocked), tostring(p.elevation)))
          end
        end
      end
      -- SHOW_HEIGHTS="13,80;13,75": the ground's heights (world units) there
      if os.getenv("SHOW_HEIGHTS") then
        for _, st in ipairs((G.stack and G.stack.states) or {}) do
          local ground = st.map and st.map.renderer and st.map.renderer.gen4Ground
          if ground then
            for x, z in tostring(os.getenv("SHOW_HEIGHTS")):gmatch("(%d+),(%d+)") do
              local list = ground.heightsAt and ground:heightsAt(tonumber(x), tonumber(z)) or {}
              local over = ground.heightOverride and ground:heightOverride(tonumber(x), tonumber(z))
              print0(("  height %s,%s: %s (override %s)"):format(x, z, table.concat(list, "/"), tostring(over)))
            end
          end
        end
      end
      local ap = G and G.save and G.save.hgssApricorns
      if ap then
        local picked = {}
        for k in pairs(ap.picked or {}) do picked[#picked + 1] = k end
        print0(("  apricorns: box %s, Kurt %d of colour %d, trees picked %s"):format(
          table.concat(ap.box, ","), ap.kurtQuantity or 0, ap.kurtColour or 0, table.concat(picked, ",")))
      end
      local inv = G and G.save and G.save.inventory or {}
      for _, id in ipairs({ 492, 493, 494, 495, 496, 497, 498 }) do
        local k = ("ITEM_%03d"):format(id)
        if inv[k] then print0(("  item %d x%s"):format(id, tostring(inv[k]))) end
      end
      for i, mon in ipairs((G and G.save and G.save.party) or {}) do
        local moves = {}
        for _, mv in ipairs(mon.moves or {}) do moves[#moves + 1] = tostring(mv.id) end
        print0(("  party %d: species %s level %s shiny %s fateful %s friendship %s egg %s moves %s"):format(i, tostring(mon.species), tostring(mon.level), tostring(require("src.pokemon.Pokemon").isShiny(mon)), tostring(mon.fatefulEncounter),
          tostring(mon.happiness or mon.friendship), tostring(mon.isEgg or mon.egg or false),
          table.concat(moves, ",")))
      end
    end
  end
end

-- CMD_TRACE="ecruteak|battle": print each script command whose name matches
-- one of the |-separated patterns, with its operands, as it runs
if os.getenv("CMD_TRACE") then
  local Commands = require("src.script.Commands")
  require("src.script.Gen4Commands")
  local pats = {}
  for p in tostring(os.getenv("CMD_TRACE")):gmatch("[^|]+") do pats[#pats + 1] = p end
  for name, fn in pairs(Commands) do
    if type(fn) == "function" then
      for _, p in ipairs(pats) do
        if name:find(p) then
          Commands[name] = function(ctx, ...)
            local a = {}
            for i = 1, select("#", ...) do a[i] = tostring((select(i, ...))) end
            print(("[cmd] %s(%s) npc=%s"):format(name, table.concat(a, ","),
              tostring(ctx and ctx.npc and ctx.npc.def and ctx.npc.def.localId)))
            return fn(ctx, ...)
          end
          break
        end
      end
    end
  end
end

-- FOG_OFF=1: a map script's fog (Morty's gym) is dropped again at once, to
-- see what is under it
if os.getenv("FOG_OFF") then
  local Commands = require("src.script.Commands")
  require("src.script.Gen4Commands")
  local init = Commands.g4_ecruteak_gym_init
  Commands.g4_ecruteak_gym_init = function(ctx, ...)
    init(ctx, ...)
    local def = ctx.overworld and ctx.overworld.map and ctx.overworld.map.def
    if def then def.gen4Fog = nil end
    local list = def and def.gen4RuntimeProps or {}
    for _, p in ipairs(list) do print(("[fog off] prop %s at %s,%s,%s"):format(p.model, p.x, p.y, p.z)) end
  end
end

-- AUTO_BATTLE=win|lose: a script's battle ends at once with that result, so
-- the branch the script takes after it can be watched without fighting
if os.getenv("AUTO_BATTLE") then
  local Commands = require("src.script.Commands")
  Commands.start_battle = function(ctx, kind, id)
    -- AUTO_BATTLE_WILD=caught: a different result for a wild battle
    ctx.lastBattleResult = (kind == "wild" and os.getenv("AUTO_BATTLE_WILD")) or os.getenv("AUTO_BATTLE")
    print(("[auto battle] %s %s -> %s"):format(tostring(kind), tostring(id), ctx.lastBattleResult))
  end
end

-- HARNESS picks another Gen 4 harness to run on the same mounted install
-- (gen4_battle_harness, ...); the overworld one by default
local harness = os.getenv("HARNESS") or "gen4_overworld_harness"
assert(harness:match("^gen4_[%w_]+_harness$"), "HARNESS names a tools/gen4_*_harness folder")
dofile(("tools/%s/main.lua"):format(harness))

-- CAM_TILT=cartridge|third|first|<degrees>: the options menu's CAM TILT row,
-- chosen before the first frame -- Platinum's camera modes on this install
local camTilt = os.getenv("CAM_TILT")
if camTilt then
  local load = love.load
  love.load = function(...)
    local r = { load(...) }
    local Gen4Camera = require("src.render.Gen4Camera")
    local G = package.loaded["src.core.Game"]
    local at
    for i, t in ipairs(Gen4Camera.TILTS) do
      if tostring(t) == camTilt or (tonumber(camTilt) and tonumber(t) and math.abs(tonumber(t) - tonumber(camTilt)) < 0.5) then at = i end
    end
    assert(at, "CAM_TILT is one of: " .. table.concat((function()
      local l = {} for _, t in ipairs(Gen4Camera.TILTS) do l[#l + 1] = tostring(t) end return l end)(), ", "))
    if G and G.save then G.save.options = G.save.options or {}; G.save.options.gen4CameraTilt = at end
    Gen4Camera.setTilt(at)
    print(("[cam] tilt %s (row %d)"):format(tostring(Gen4Camera.TILTS[at]), at))
    return (table.unpack or unpack)(r)
  end
end

-- SET_VARS="0x4108=1,0x4030=152", SET_FLAGS / CLEAR_FLAGS="0x6A,0x73", APRICORNS: story state
-- before the first frame, through the engine's own setters, so a later
-- scene can be tested without playing up to it
if os.getenv("SET_VARS") or os.getenv("SET_FLAGS") or os.getenv("CLEAR_FLAGS") or os.getenv("APRICORNS") or os.getenv("KURT") or os.getenv("BADGES") or os.getenv("STRENGTH") then
  -- applied as the overworld is pushed: that is after the new save exists
  -- and before the first tick (this harness ticks inside love.load)
  local StateStack = require("src.core.StateStack")
  local push, applied = StateStack.push, false
  StateStack.push = function(self, state, ...)
    if not applied and state == require("src.world.OverworldController") then
      applied = true
      local G = package.loaded["src.core.Game"]
      local G4 = require("src.script.Gen4Commands")
      local Commands = require("src.script.Commands")
      local ctx = { save = G and G.save, game = G }
      -- STRENGTH=1: Strength already active, as the field-move script leaves it
      if os.getenv("STRENGTH") and ctx.save then
        ctx.save.gen4FieldMoveFlags = ctx.save.gen4FieldMoveFlags or {}
        ctx.save.gen4FieldMoveFlags.strength = true
        _G.__harnessStrength = true
      end
      -- BADGES=all (or a count): field-move tests need the badge checks to pass
      if os.getenv("BADGES") and ctx.save then
        local Badges = require("src.inventory.Badges")
        local list = Badges.list(G and G.data) or {}
        local n = tonumber(os.getenv("BADGES")) or #list
        for i = 1, math.min(n, #list) do Badges.set(ctx.save, list[i], true) end
        print(("[state] %d badge(s) given"):format(math.min(n, #list)))
      end
      for id, value in tostring(os.getenv("SET_VARS") or ""):gmatch("(%w+)=(%w+)") do
        G4.setVar(ctx.save, tonumber(id), tonumber(value))
        print(("[state] var %s = %s"):format(id, value))
      end
      for id in tostring(os.getenv("SET_FLAGS") or ""):gmatch("%w+") do
        Commands.set_flag(ctx, ("FLAG_G4_%04X"):format(tonumber(id)))
        print(("[state] flag %s set"):format(id))
      end
      for id in tostring(os.getenv("CLEAR_FLAGS") or ""):gmatch("%w+") do
        Commands.clear_flag(ctx, ("FLAG_G4_%04X"):format(tonumber(id)))
        print(("[state] flag %s clear"):format(id))
      end
      -- APRICORNS="3=5,0=2": colour (0 red .. 6 black) = how many in the box
      for colour, n in tostring(os.getenv("APRICORNS") or ""):gmatch("(%d+)=(%d+)") do
        require("src.world.HgssApricorns").give(ctx.save, tonumber(colour), tonumber(n))
        print(("[state] apricorn %s x%s"):format(colour, n))
      end
      -- KURT="2=3": Kurt already holds 3 of colour 2 (a day has passed)
      for colour, n in tostring(os.getenv("KURT") or ""):gmatch("(%d+)=(%d+)") do
        local A = require("src.world.HgssApricorns")
        A.give(ctx.save, tonumber(colour), tonumber(n))
        A.setKurt(ctx.save, tonumber(colour), tonumber(n))
        print(("[state] Kurt holds %s of colour %s"):format(n, colour))
      end
    end
    return push(self, state, ...)
  end
end

-- ENC_FORCE=1: every step's rate check passes, so a short walk tests the
-- rest of the encounter path (table, slot, battle) instead of luck
if os.getenv("ENC_FORCE") then
  local Encounter = require("src.world.Encounter")
  Encounter.gen4StepAllowed = function() return true end
end

-- ENC_DEBUG=1: every encounter roll and every grass-cell answer, logged
if os.getenv("ENC_DEBUG") then
  local OW = require("src.world.OverworldController")
  local roll = OW.rollEncounter
  OW.rollEncounter = function(self, encDef, terrain)
    local enc = roll(self, encDef, terrain)
    print(("[enc] roll %s table=%s -> %s"):format(tostring(terrain),
      tostring(encDef and encDef.grass and #encDef.grass or nil), enc and tostring(enc.species) or "none"))
    return enc
  end
  local Map = require("src.world.Map")
  local isEnc = Map.isEncounterCell
  Map.isEncounterCell = function(self, cx, cy)
    local yes = isEnc(self, cx, cy)
    print(("[enc] cell %d,%d grass=%s"):format(cx, cy, tostring(yes)))
    return yes
  end
end

-- PROBE_CELL=x,y: after load, say which chunk the loaded terrain has there
local probe = os.getenv("PROBE_CELL")
if probe then
  local load = love.load
  love.load = function(...)
    local r = { load(...) }
    local x, y = probe:match("(%d+),(%d+)")
    local G = rawget(_G, "Game")
    local data = G and G.data or package.loaded["src.core.Data"]
    local t = data and data.gen4_terrain
    local g = t and t.matrices and t.matrices[0]
    print(("PROBE terrain source=%s grid=%sx%s land=%s"):format(tostring(t and t.source),
      tostring(g and g.width), tostring(g and g.height),
      tostring(g and g.land[tonumber(y) * g.width + tonumber(x) + 1])))
    return table.unpack and table.unpack(r) or unpack(r)
  end
end

