do
  local root = (os.getenv("ROOT") or love.filesystem.getWorkingDirectory()):gsub("\\", "/")
  local ffi = require("ffi")
  pcall(ffi.cdef, "int PHYSFS_mount(const char *newDir, const char *mountPoint, int appendToPath);")
  for _, lib in ipairs({ function() return ffi.C end, function() return ffi.load("love") end }) do
    local ok, l = pcall(lib)
    if ok and l then
      local okf, fn = pcall(function() return l.PHYSFS_mount end)
      if okf and fn and fn(root, "", 1) ~= 0 then break end
    end
  end
end

function love.load()
  local W = require("src.pokewalker.Walker")
  local Link = require("src.pokewalker.WalkerLink")
  local Courses = require("src.pokewalker.WalkerCourses")
  local SaveData = require("src.core.SaveData")
  local Ser = require("src.core.SaveSerializer")
  local pass, fail = 0, 0
  local function check(name, ok, extra)
    if ok then pass = pass + 1 else fail = fail + 1 end
    print((ok and "ok   " or "FAIL ") .. name .. (extra ~= nil and ("  " .. tostring(extra)) or ""))
  end
  love.filesystem.remove(W.FILE)
  love.filesystem.remove(Courses.INDEX_FILE)
  -- species facts come from the imported games (DATA, default the install)
  SaveData.setDataDir(os.getenv("DATA") or "G:/Gen2Recomped")
  local routes = Courses.routes()
  check("27 courses", routes[0] and routes[26] and true, routes[26] and routes[26].name)

  -- courses for each generation stay inside that game's dex
  for _, v in ipairs({ "red", "crystal", "emerald", "platinum", "black" }) do
    local entries = Courses.forGame(15, v)  -- Big Forest
    local max = Courses.maxDexFor(v)
    local okAll, seen, dup = true, {}, false
    for _, e in ipairs(entries) do
      if e.species > max or e.species < 1 then okAll = false end
      if seen[e.species] then dup = true end
      seen[e.species] = true
    end
    check(v .. ": Big Forest within dex " .. max .. ", no repeats", okAll and not dup and #entries == 6,
          (function() local t = {} for _, e in ipairs(entries) do t[#t + 1] = e.name end return table.concat(t, ",") end)())
  end

  -- steps and watts
  local st = W.newState()
  W.addSteps(st, 1000, routes)
  check("1000 steps = 50 W", st.watts == 50, st.watts)
  check("Rugged Road unlocked at 50 W", #W.unlocked(st, routes, false) == 3, #W.unlocked(st, routes, false))
  check("Hoenn Field needs the National Dex", (function()
    st.lifetimeWatts = 6000
    local a, b = #W.unlocked(st, routes, false), #W.unlocked(st, routes, true)
    st.lifetimeWatts = 50
    return b == a + 1 end)())

  -- send from a save's box
  local V = "platinum"
  for _, s in ipairs(SaveData.listSlots(V)) do SaveData.deleteSlot(V, s.id) end
  local slot = SaveData.createSlot(V)
  SaveData.writeSlot(V, slot, { player = { name = "LUCAS" }, party = {}, boxes = { { { species = 25, level = 10, happiness = 90, exp = 1000 } } } })
  local mons = Link.boxMons(V, slot)
  check("box Pokemon listed", mons and #mons == 1 and mons[1].species == 25, mons and #mons)
  local ok, why = Link.send(st, mons[1], 0)
  check("sent", ok, why)
  local f = io.open(SaveData.slotDiskPath(V, slot), "rb"); local saved = Ser.decode(f:read("*a")); f:close()
  check("left the box", #saved.boxes[1] == 0)
  check("three encounters drawn", #st.walking.encounters == 3)
  check("Pikachu has no Refreshing Field advantage", st.walking.advantage == false)
  -- the phone's milestones: the next course is exact, nearest first
  local Notify = require("src.pokewalker.WalkerNotify")
  local ms = Notify.milestones(st, routes)
  local course
  for _, m in ipairs(ms) do if m.title == "New course unlocked!" then course = m end end
  check("next course milestone (Beautiful Beach at 200 W)", course and course.at == (200 - st.lifetimeWatts) * 20 - st.stepRemainder, course and course.at)
  local sorted = true
  for i = 2, #ms do if ms[i].at < ms[i - 1].at then sorted = false end end
  check("milestones nearest first", sorted and #ms >= 4, #ms)
  check("no notifier off Android", Notify.available() == false and Notify.watch(st, routes) == false)
  W.addSteps(st, 4000, routes)
  check("walk steps counted", st.walking.steps == 4000)
  check("friendship grew", st.walking.friendship >= 98, st.walking.friendship)
  -- radar until a catch (watts topped up)
  local caught = false
  for _ = 1, 200 do
    st.watts = 100
    local r = W.radarStart(st)
    if r then
      local b = W.newBattle(r.encounter)
      while not b.over do W.battleTurn(st, b, "catch") end
      if b.over == "caught" then caught = true break end
    end
  end
  check("radar catches", caught and #st.caught == 1, #st.caught)
  -- dowsing until an item
  local found = false
  for _ = 1, 50 do
    st.watts = 100
    local d = W.dowseStart(st, routes[0])
    if d then
      for i = 1, 6 do local res = W.dowseTry(st, d, i); if res == "found" then found = true break end; if d.done then break end end
    end
    if found then break end
  end
  check("dowsing finds", found and #st.items >= 1, #st.items)
  check("never more than three items", #st.items <= 3)
  -- home
  ok, why = Link.bringHome(st, false)
  check("brought home", ok, why)
  f = io.open(SaveData.slotDiskPath(V, slot), "rb"); saved = Ser.decode(f:read("*a")); f:close()
  local inbox = saved.walkerInbox
  check("inbox holds the walker", inbox and #inbox.returning == 1 and inbox.returning[1].steps == 4000)
  check("inbox holds the catch", inbox and #inbox.mons == 1)
  check("inbox holds the items", inbox and #inbox.items >= 1)
  check("walker empty", st.walking == nil and #st.caught == 0)
  check("a backup was kept", #love.filesystem.getDirectoryItems("pokewalker_backups/" .. V) >= 2)
  print(("%d checks, %d failed"):format(pass + fail, fail))
  for _, s in ipairs(SaveData.listSlots(V)) do SaveData.deleteSlot(V, s.id) end
  love.event.quit()
end
