-- tools/walker_radar_check: the Poke Radar's wider pools (WalkerRadarPools)
--   "/c/Program Files/LOVE/lovec.exe" tools/walker_radar_check
-- DATA=<install> (default G:/Gen2Recomped) for the imported games' encounter
-- tables; INBOX_GAME=crystal (default) for the trip-home check. A scratch
-- identity and scratch slots only.
io.stdout:setvbuf("line")
local ffi = require("ffi")
pcall(ffi.cdef, "int PHYSFS_mount(const char *newDir, const char *mountPoint, int appendToPath);")
local PHYS
do
  local root = (os.getenv("ROOT") or love.filesystem.getWorkingDirectory()):gsub("\\", "/")
  for _, lib in ipairs({ function() return ffi.C end, function() return ffi.load("love") end }) do
    local ok, l = pcall(lib)
    if ok and l then
      local okf, fn = pcall(function() return l.PHYSFS_mount end)
      if okf and fn and fn(root, "", 1) ~= 0 then PHYS = l break end
    end
  end
end

function love.load()
  local ok, err = xpcall(function()
  local W = require("src.pokewalker.Walker")
  local R = require("src.pokewalker.WalkerRadarPools")
  local Courses = require("src.pokewalker.WalkerCourses")
  local SaveData = require("src.core.SaveData")
  local Ser = require("src.core.SaveSerializer")
  local pass, fail = 0, 0
  local function check(name, okc, extra)
    if okc then pass = pass + 1 else fail = fail + 1 end
    print((okc and "ok   " or "FAIL ") .. name .. (extra ~= nil and ("  " .. tostring(extra)) or ""))
  end
  W.save = function() end
  local DATA = os.getenv("DATA") or "G:/Gen2Recomped"

  local VERSIONS = { "red", "blue", "yellow", "gold", "silver", "crystal", "ruby", "sapphire", "emerald", "firered", "leafgreen",
                     "diamond", "pearl", "platinum", "heartgold", "soulsilver", "black", "white" }
  for _, v in ipairs(VERSIONS) do love.filesystem.remove(R.CACHE:format(v)) end
  local GEN = { red = 1, blue = 1, yellow = 1, gold = 2, silver = 2, crystal = 2, ruby = 3, sapphire = 3, emerald = 3,
                firered = 3, leafgreen = 3, diamond = 4, pearl = 4, platinum = 4, heartgold = 4, soulsilver = 4, black = 5, white = 5 }
  local function maxFor(v) return Courses.MAX_DEX[GEN[v]] end

  -- 1. the curated tables alone: every species in its game's dex
  local CAP = { kanto = 151, johto = 251, hoenn = 386, frlg = 386, sinnoh = 493, hgss = 493, unova = 649 }
  for fam, list in pairs(R.CURATED) do
    local bad = {}
    local cap = CAP[fam]
    for _, e in ipairs(list) do
      if e[1] < 1 or e[1] > cap or R.LEGEND_DEX[e[1]] then bad[#bad + 1] = e[2] end
    end
    check(("curated %s: %d species within dex %d, no legendaries"):format(fam, #list, cap), #bad == 0 and #list >= 40, table.concat(bad, ","))
    local lb = {}
    for _, l in ipairs(R.LEGENDS[fam]) do if l[1] > cap or l[3] < 5 or l[3] > 100 then lb[#lb + 1] = l[2] end end
    check(("legends %s: %d within dex %d"):format(fam, #R.LEGENDS[fam], cap), #lb == 0 and #R.LEGENDS[fam] >= 5, table.concat(lb, ","))
  end

  -- 2. per game, imported where it can be (DATA), curated otherwise
  local report = {}
  local function poolsFor(tag)
    for _, v in ipairs(VERSIONS) do
      R._reset()
      local pool, src = R.pool(v)
      local legends = R.legends(v)
      local max = maxFor(v)
      local bad = {}
      for _, e in ipairs(pool) do
        if e.species < 1 or e.species > max or R.LEGEND_DEX[e.species] or e.minLevel < 1 or e.minLevel > 100 then bad[#bad + 1] = e.species end
      end
      for _, l in ipairs(legends) do if l.species > max then bad[#bad + 1] = "L" .. l.species end end
      local names = {}
      for _, l in ipairs(legends) do names[#names + 1] = l.name end
      check(("%s %s: %d wild (%s), %d legendaries, all within dex %d"):format(tag, v, #pool, src, #legends, max),
            #bad == 0 and #pool >= 30 and #legends >= 3, table.concat(bad, ","))
      if tag == "data" then report[#report + 1] = ("  %-10s %-8s wild=%3d legends=%2d: %s"):format(v, src, #pool, #legends, table.concat(names, ", ")) end
    end
  end
  -- the curated stand-ins, as a game with no import sees them
  local realImported = R.imported
  R.imported = function() return nil end
  poolsFor("curated")
  R.imported = realImported
  SaveData.setDataDir(DATA)
  love.filesystem.remove(Courses.INDEX_FILE)
  poolsFor("data")
  for _, line in ipairs(report) do print(line) end
  -- version-only legendaries follow the version
  local function has(v, dex) for _, l in ipairs(R.legends(v)) do if l.species == dex then return true end end return false end
  check("Reshiram in Black only, Zekrom in White only", has("black", 643) and not has("black", 644) and has("white", 644) and not has("white", 643))
  check("Groudon in HeartGold, Kyogre in SoulSilver", has("heartgold", 383) and not has("heartgold", 382) and has("soulsilver", 382))
  check("Gen 1 never offers Johto's", not has("red", 249) and not has("yellow", 243))

  -- a walk from a game, on a course, at some progress
  local routes = Courses.routes()
  local function walkFrom(v, steps, course)
    local st = W.newState()
    local entries = Courses.forGame(course or 0, v)
    W.send(st, course or 0, { species = 25, name = "PIKACHU", level = 10, types = { "ELECTRIC" }, friendship = 70,
                              source = { version = v, slot = "slot1" } }, entries, routes[course or 0])
    st.walking.steps = steps
    return st
  end

  -- 3. gating: more progress, more of the pool
  local st0, st5, st20 = walkFrom("heartgold", 0), walkFrom("heartgold", 5000), walkFrom("heartgold", 20000)
  local u0, u5, u20 = #R.unlocked(st0), #R.unlocked(st5), #R.unlocked(st20)
  check(("gating: %d species at 0 steps < %d at 5000 < %d at 20000"):format(u0, u5, u20), u0 < u5 and u5 < u20 and u0 >= R.MIN_POOL)
  local reach0 = R.reach(st0)
  local over = 0
  for i, e in ipairs(R.unlocked(st0)) do if e.minLevel > reach0 and i > R.MIN_POOL then over = over + 1 end end
  check("gating: a fresh walk reaches only low levels (reach " .. reach0 .. ")", reach0 <= 10 and over == 0)
  st0.walking.bonusSteps = 5000
  check("gating: non-step watts' bonus steps count", #R.unlocked(st0) == u5, #R.unlocked(st0))
  st0.walking.bonusSteps = nil
  check("no legendaries before " .. R.LEGEND_MIN_STEPS .. " steps", R.legendChance(st0) == 0)

  -- 4. the legendary rate (seeded): about 1.2% at 1000 steps, never past 2.2%
  local function rate(v, steps, n)
    love.math.setRandomSeed(12345)
    local st = walkFrom(v, steps)
    local legends, kinds, badDex, courseOwn, levelsOk = 0, {}, 0, 0, true
    local max = Courses.maxDexFor(v)
    for _ = 1, n do
      st.watts = 100
      local r = W.radarStart(st)
      if r then
        local e = r.encounter
        if r.legendary then legends = legends + 1 end
        if e.species < 1 or e.species > max then badDex = badDex + 1 end
        if not e.radar then courseOwn = courseOwn + 1 end
        kinds[e.species] = true
        if e.radar and not r.legendary and (e.level or 0) > math.max(R.reach(st), 0) then
          -- a MIN_POOL filler may sit above the reach; its level is its own lowest
          local fine = false
          for _, p in ipairs(R.pool(v)) do if p.species == e.species and e.level <= p.maxLevel then fine = p.minLevel > R.reach(st) end end
          if not fine then levelsOk = false end
        end
      end
    end
    local k = 0 for _ in pairs(kinds) do k = k + 1 end
    return legends / n, k, badDex, courseOwn / n, levelsOk
  end
  local r0 = rate("heartgold", 0, 4000)
  check("0 steps: no legendary in 4000 searches", r0 == 0, r0)
  local r1, k1, _, own1, lv1 = rate("heartgold", 1000, 20000)
  check(("1000 steps: legendary rate %.2f%% (1.2%% expected)"):format(r1 * 100), r1 >= 0.008 and r1 <= 0.017)
  check(("1000 steps: %d different species, course's own %.0f%%"):format(k1, own1 * 100), k1 >= 15 and own1 > 0.25 and own1 < 0.6)
  check("radar levels never past the reach", lv1)
  local r2 = rate("heartgold", 30000, 20000)
  check(("30000 steps: legendary rate %.2f%% (2.2%% cap)"):format(r2 * 100), r2 > r1 and r2 <= 0.028)
  for _, v in ipairs({ "red", "crystal", "emerald", "firered", "platinum", "soulsilver", "black", "white" }) do
    local rv, kv, badv = rate(v, 8000, 3000)
    check(("%s: every radar find within dex %d (%d species, legendary %.1f%%)"):format(v, Courses.maxDexFor(v), kv, rv * 100), badv == 0 and kv >= 15 and rv < 0.04)
  end
  check("no shinies in Kanto", (function()
    love.math.setRandomSeed(7)
    local st = walkFrom("red", 8000)
    for _ = 1, 6000 do st.watts = 100; local r = W.radarStart(st); if r and r.encounter.shiny then return false end end
    return true end)())

  -- 5. a legendary battle: six bars, much harder to catch
  local function catchRate(enc, n)
    love.math.setRandomSeed(99)
    local st = walkFrom("heartgold", 1000)
    local got = 0
    for _ = 1, n do
      st.watts, st.caught = 100, {}
      local b = W.newBattle(enc)
      local turns = 0
      while not b.over and turns < 50 do W.battleTurn(st, b, "catch"); turns = turns + 1 end
      if b.over == "caught" then got = got + 1 end
    end
    return got / n
  end
  local lb = W.newBattle({ species = 250, name = "Ho-Oh", level = 45, legendary = true })
  check("legendary battle has 6 bars", lb.wild == 6 and lb.max == 6 and lb.legendary == true)
  local cn = catchRate({ species = 16, name = "Pidgey", level = 5 }, 4000)
  local cl = catchRate({ species = 250, name = "Ho-Oh", level = 45, legendary = true }, 4000)
  check(("ball-only catch: ordinary %.0f%%, legendary %.0f%%"):format(cn * 100, cl * 100), cl < cn * 0.6)
  local st = walkFrom("crystal", 2000)
  st.caught = {}
  love.math.setRandomSeed(3)
  local caughtL
  for _ = 1, 500 do
    local b = W.newBattle({ species = 250, name = "HO_OH", level = 45, legendary = true, shiny = true })
    while not b.over do W.battleTurn(st, b, "catch") end
    if b.over == "caught" then caughtL = st.caught[#st.caught] break end
  end
  check("a caught legendary is flagged legendary and shiny", caughtL and caughtL.legendary == true and caughtL.shiny == true)

  -- 6. home: the flag rides the save's inbox and reaches the made Pokemon
  local V = os.getenv("INBOX_GAME") or "crystal"
  for _, s in ipairs(SaveData.listSlots(V)) do SaveData.deleteSlot(V, s.id) end
  local slot = SaveData.createSlot(V)
  SaveData.writeSlot(V, slot, { player = { name = "GOLD", id = 12345 }, party = {}, boxes = { {} } })
  st.walking.source = { version = V, slot = slot }
  st.caught = { caughtL or { species = 250, name = "HO_OH", level = 45, legendary = true, shiny = true } }
  local Link = require("src.pokewalker.WalkerLink")
  local okS, why = Link.sendCaught(st, 1)
  check("sent the legendary home", okS, why)
  local f = io.open(SaveData.slotDiskPath(V, slot), "rb"); local saved = Ser.decode(f:read("*a")); f:close()
  local inMon = saved.walkerInbox and saved.walkerInbox.mons and saved.walkerInbox.mons[1]
  check("inbox keeps legendary + shiny", inMon and inMon.legendary == true and inMon.shiny == true and inMon.species == 250)
  -- unpack it with the game's own data (mounted the way walker_inbox_check does)
  require("src.core.GameVersion").set(V)
  local mounted = PHYS and PHYS.PHYSFS_mount(DATA .. "/" .. V, "", 0) ~= 0
  if mounted then
    local Data = require("src.core.Data")
    Data:load()
    local rep = require("src.pokewalker.WalkerInbox").apply(saved, Data)
    local made
    for _, b in ipairs(saved.boxes or {}) do for _, m in pairs(b.mons or b) do if type(m) == "table" and m.species then made = m end end end
    local Pokemon = require("src.pokemon.Pokemon")
    check("unpacked into the PC", rep and rep.caught == 1 and made ~= nil, rep and rep.caught)
    check("made Pokemon is marked legendary", made and made.walkerLegendary == true)
    check("made Pokemon is shiny (" .. V .. ")", made and Pokemon.isShiny(made))
  else
    check("mount " .. DATA .. "/" .. V .. " for the inbox", false)
  end
  for _, s in ipairs(SaveData.listSlots(V)) do SaveData.deleteSlot(V, s.id) end
  print(("%d checks, %d failed"):format(pass + fail, fail))
  end, debug.traceback)
  if not ok then print("FAILED: " .. tostring(err)) end
  love.event.quit()
end
