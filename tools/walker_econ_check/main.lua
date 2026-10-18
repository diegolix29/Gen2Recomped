-- The Monster Walker's economy: passive watts and their cap, the login
-- streak, the rewards API the minigames call, achievements, leaderboards and
-- the Watt Shop's delivery into a scratch save's walkerInbox.
--   `lovec tools/walker_econ_check`   (DATA=<install> for species facts,
--   default G:/Gen2Recomped; OUT=<file> also writes the log there)
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
  local E = require("src.pokewalker.WalkerEconomy")
  local Shop = require("src.pokewalker.WalkerShop")
  local Link = require("src.pokewalker.WalkerLink")
  local SaveData = require("src.core.SaveData")
  local Ser = require("src.core.SaveSerializer")
  local log = {}
  local pass, fail = 0, 0
  local function check(name, ok, extra)
    if ok then pass = pass + 1 else fail = fail + 1 end
    local line = (ok and "ok   " or "FAIL ") .. name .. (extra ~= nil and ("  " .. tostring(extra)) or "")
    print(line); log[#log + 1] = line
  end
  love.filesystem.remove(W.FILE)
  W.live = nil
  SaveData.setDataDir(os.getenv("DATA") or "G:/Gen2Recomped")
  local realClock = os.time
  local now = os.time({ year = 2026, month = 10, day = 17, hour = 9 })
  E.clock = function() return now end

  -- ------------------------------------------------------- passive watts
  local st = W.newState()
  local n = E.creditSeconds(st, 3600, now)
  check("one hour open = 5 W", n == 5 and st.watts == 5, st.watts)
  E.creditSeconds(st, 700, now)
  check("partial progress kept (700 s)", st.econ.passive.secs == 700 and st.watts == 5, st.econ.passive.secs)
  E.creditSeconds(st, 20, now)
  check("720 s more = 1 W", st.watts == 6, st.watts)
  E.creditSeconds(st, 20 * 3600, now)
  check("capped at 50 W a day", st.econ.passive.watts == 50 and st.watts == 50, st.watts)
  local before = st.watts
  E.creditSeconds(st, 3600, now)
  check("nothing past the cap", st.watts == before)
  E.creditSeconds(st, 3600, now + 86400)
  check("a new day, a new 50", st.econ.passive.watts == 5, st.econ.passive.watts)
  check("lifetime watts count passive", (st.econ.earned.passive or 0) == 55, st.econ.earned.passive)

  -- the process tally: frames + a backgrounded gap (Android pauses frames)
  local st2 = W.newState()
  W.live = st2
  W.save(st2)
  E._run.pending, E._run.ticked, E._run.unsaved = 0, 0, 0
  for _ = 1, 600 do E.tick(1) end           -- ten minutes of frames
  E.tick(1000)                              -- one stall: clamped to E.MAX_FRAME
  E.flush(true)
  check("frames accrue (605 s: no watt yet)", st2.econ.passive.secs == 605 and st2.watts == 0, st2.econ.passive.secs)
  E.focus(false)
  now = now + 3600                          -- an hour away, no frames
  E.focus(true)
  check("background gap credited (+5 W)", st2.watts == 5, st2.watts)
  E.focus(false)
  for _ = 1, 100 do E.tick(1) end           -- desktop: frames kept running while unfocused
  now = now + 100
  E.focus(true)
  check("no double count when frames ran", math.abs(st2.econ.passive.secs - (605 + 3600 - 3600 + 100)) < 0.01, st2.econ.passive.secs)
  local disk = Ser.decode(love.filesystem.read(W.FILE))
  check("partial progress persisted", disk.econ and disk.econ.passive and disk.econ.passive.secs == st2.econ.passive.secs)
  W.live = nil
  check("W.load shares one state", W.load() == W.load())
  W.live = nil

  -- ------------------------------------------------------- daily streak
  now = os.time({ year = 2026, month = 10, day = 17, hour = 9 })
  local s = W.newState()
  local b1 = E.dailyLogin(s)
  check("day 1 login: 5 W", b1 == 5 and s.watts == 5, b1)
  check("second open same day: nothing", E.dailyLogin(s) == nil)
  local bonuses = {}
  for d = 1, 7 do now = now + 86400; bonuses[#bonuses + 1] = E.dailyLogin(s) end
  check("streak grows 10..30, capped", table.concat(bonuses, ",") == "10,15,20,25,30,30,30", table.concat(bonuses, ","))
  check("streak 8, best 8", s.econ.login.streak == 8 and s.econ.login.best == 8)
  now = now + 2 * 86400
  check("a missed day resets", E.dailyLogin(s) == 5 and s.econ.login.streak == 1 and s.econ.login.best == 8)
  local diary = false
  for _, l in ipairs(s.log) do if l.text:find("streak") then diary = true end end
  check("streak in the diary", diary)
  check("streak achievements awarded", s.econ.done.streak3 and s.econ.done.streak7 and not s.econ.done.streak30)

  -- ------------------------------------------------------- rewards API
  local a = W.newState()
  check("earn adds, no cap", E.earn(a, 500, "test_game") == 500 and a.watts >= 500)
  check("earn records the source", a.econ.earned.test_game == 500)
  check("watts achievements (100, not 1000)", a.econ.done.watts100 and not a.econ.done.watts1k)
  check("earn ignores junk", E.earn(a, -5, "x") == 0 and E.earn(a, "abc", "x") == 0)
  check("grantItem", E.grantItem(a, "Rare Candy", 2, "test") == true and a.items[1].count == 2)
  E.grantItem(a, "Rare Candy", 3, "test")
  check("grantItem stacks", #a.items == 1 and a.items[1].count == 5)
  local ent = E.grantPokemon(a, 25, 12, "test")
  check("grantPokemon (radar shape)", ent and a.caught[1].species == 25 and a.caught[1].level == 12 and a.caught[1].name, a.caught[1] and a.caught[1].name)
  check("grantPokemon rejects bad dex", E.grantPokemon(a, 9999, 5) == false)
  -- granted things do not take the original's three places
  a.items[#a.items + 1] = { name = "Potion" }
  check("granted items don't fill the 3 found slots", W.heldCount(a.items) == 1)
  check("ranks", E.recordScore(a, "slots", 100) == 1 and E.recordScore(a, "slots", 50) == 2
    and E.recordScore(a, "slots", 200) == 1 and E.recordScore(a, "slots", 100) == 3)
  for i = 1, 10 do E.recordScore(a, "slots", 300 + i) end
  check("top 10 kept", #a.econ.scores.slots == 10 and a.econ.scores.slots[1].score == 310)
  check("not placed = nil", E.recordScore(a, "slots", 1) == nil)
  check("board has dates", type(a.econ.scores.slots[1].t) == "number")
  check("high score achievements", a.econ.done.play1 and a.econ.done.best1 and a.econ.done.best10)
  E.recordScore(a, "memory", 1); E.recordScore(a, "race", 1)
  check("all-rounder (3 boards)", a.econ.done.boards3)
  local got = E.achievement(a, "catch", 1)
  check("achievement() feeds counters", #got == 1 and got[1].id == "catch1")
  check("each awards once", #E.achievement(a, "catch", 1) == 0)
  check("friendship needs a walker", E.friendship(a, 5) == false)
  a.walking = { species = 25, name = "PIKACHU", level = 10, friendship = 250, steps = 100,
                source = { version = "platinum", slot = "x", box = 1, index = 1 } }
  check("friendship capped at 255", E.friendship(a, 20) == 255 and a.walking.bonusExp == 200)
  check("best friends achievement", a.econ.done.friend255)

  -- ------------------------------------------------------- the shop
  check("gen 1 shelf has no held items", (function()
    for _, it in ipairs(Shop.items(1)) do if it.cat == "Held items" then return false end end return true end)())
  check("gen 4 shelf has Dusk Stone", (function()
    for _, it in ipairs(Shop.items(4)) do if it.name == "Dusk Stone" then return true end end end)())
  -- every shelf item exists in the games of its generation (by name)
  local function norm(x) return Shop.norm(x) end
  for _, v in ipairs({ "crystal", "emerald", "platinum", "heartgold", "black" }) do
    local ok, items = pcall(dofile, (os.getenv("DATA") or "G:/Gen2Recomped") .. "/" .. v .. "/data/generated/items.lua")
    if ok and type(items) == "table" then
      local have = {}
      for _, d in pairs(items) do if type(d) == "table" and d.name then have[norm(d.name)] = true end end
      local miss = {}
      for _, it in ipairs(Shop.items(Shop.genOf(v))) do if not have[norm(it.name)] then miss[#miss + 1] = it.name end end
      for _, gft in ipairs(Shop.GIFTS) do
        if gft.kind == "item" and Shop.genOf(v) >= gft.gen and not have[norm(gft.name)] then miss[#miss + 1] = gft.name end
      end
      check(v .. ": every shelf item exists", #miss == 0, table.concat(miss, ", "))
    end
  end
  local stock = Shop.stock("crystal", 20000)
  local inRange = #stock == 6
  for _, o in ipairs(stock) do if o.dex > 251 then inRange = false end end
  check("crystal stock: 6, all within 251", inRange, #stock)
  check("stock is stable for a day", Shop.stock("crystal", 20000)[1].dex == stock[1].dex)
  check("stock rotates", Shop.stock("crystal", 20001)[1].dex ~= stock[1].dex or Shop.stock("crystal", 20001)[2].dex ~= stock[2].dex)
  local gifts = Shop.gifts(100)
  check("4 gifts a week, 2 Pokemon + 2 items", #gifts == 4 and gifts[1].kind == "mon" and gifts[2].kind == "item")

  -- delivery into a scratch save
  local V = "platinum"
  for _, sl in ipairs(SaveData.listSlots(V)) do SaveData.deleteSlot(V, sl.id) end
  local slot = SaveData.createSlot(V)
  SaveData.writeSlot(V, slot, { player = { name = "LUCAS" }, party = {}, boxes = { {} } })
  local target = { version = V, slot = slot }
  local buyer = W.newState()
  buyer.watts = 100
  local potion
  for _, it in ipairs(Shop.items(4)) do if it.name == "Potion" then potion = it end end
  local rare
  for _, it in ipairs(Shop.items(4)) do if it.name == "Rare Candy" then rare = it end end
  local okB, why = E.buyItem(buyer, rare, target)
  check("can't buy without the watts", okB == false and buyer.watts == 100, why)
  okB, why = E.buyItem(buyer, potion, target)
  check("bought Potion x5 (100 - 40 + 10 First purchase)", okB and buyer.watts == 70, buyer.watts)
  local f = io.open(SaveData.slotDiskPath(V, slot), "rb"); local saved = Ser.decode(f:read("*a")); f:close()
  local inbox = saved.walkerInbox
  check("inbox holds the stack", inbox and inbox.items[1] and inbox.items[1].name == "Potion" and inbox.items[1].count == 5)
  buyer.watts = 5000
  local offer = Shop.stock(V, E.day())[1]
  okB, why = E.buyPokemon(buyer, offer, target)
  check("bought a Pokemon", okB, why)
  check("sold out after", E.buyPokemon(buyer, offer, target) == false)
  local gift
  for _, gg in ipairs(Shop.gifts(E.week())) do if gg.kind == "mon" and gg.gen <= 4 then gift = gg end end
  if gift then
    okB, why = E.buyGift(buyer, gift, target)
    check("claimed a Mystery Gift", okB, why)
    check("once a week", E.buyGift(buyer, gift, target) == false)
  end
  f = io.open(SaveData.slotDiskPath(V, slot), "rb"); saved = Ser.decode(f:read("*a")); f:close()
  check("inbox holds the Pokemon", #saved.walkerInbox.mons >= 1 and saved.walkerInbox.mons[1].species == offer.dex, #saved.walkerInbox.mons)
  check("purchases counted", buyer.econ.counters.purchases == (gift and 3 or 2) and buyer.econ.done.buy1)
  okB = E.buyCosmetic(buyer, "theme", "night")
  check("cosmetic bought and in use", okB and E.using(buyer, "theme") == "night")
  check("free cosmetics owned", E.owns(buyer, "shell", "classic") and E.using(buyer, "shell") == "classic")
  okB = E.buyCosmetic(buyer, "course", 20)
  check("event course unlocked", okB and buyer.events[20] == true)
  local routes = require("src.pokewalker.WalkerCourses").routes()
  local open20 = false
  for _, id in ipairs(W.unlocked(buyer, routes, true)) do if id == 20 then open20 = true end end
  check("...and walkable", open20)
  check("can't target a missing save", E.buyItem(buyer, potion, { version = V, slot = "nope" }) == false)

  -- the walk home carries the minigames' EXP
  local wst = W.newState()
  SaveData.writeSlot(V, slot, { player = { name = "LUCAS" }, party = {}, boxes = { { { species = 25, level = 10, happiness = 90 } } } })
  local mons = Link.boxMons(V, slot)
  Link.send(wst, mons[1], 0)
  E.friendship(wst, 10)
  E.grantItem(wst, "Ultra Ball", 3, "test")
  Link.bringHome(wst, false)
  f = io.open(SaveData.slotDiskPath(V, slot), "rb"); saved = Ser.decode(f:read("*a")); f:close()
  local r = saved.walkerInbox.returning[1]
  check("returning carries bonus EXP and friendship", r and r.bonusExp == 100 and r.friendship == 100, r and r.bonusExp)
  check("granted stack goes home", saved.walkerInbox.items[#saved.walkerInbox.items].count == 3)

  -- WalkerInbox: stacks keep their count; "POKé BALL" now matches
  local okI, items = pcall(dofile, (os.getenv("DATA") or "G:/Gen2Recomped") .. "/crystal/data/generated/items.lua")
  if okI then
    require("src.core.GameVersion").set("crystal")
    local save = { inventory = {}, walkerInbox = { mons = {}, returning = {},
      items = { { name = "Poke Ball", count = 10 }, { name = "Rare Candy", count = 2 } } } }
    local okA, rep = pcall(require("src.pokewalker.WalkerInbox").apply, save, { items = items })
    local ball, candy
    for id, d in pairs(items) do
      if type(d) == "table" and Shop.norm(d.name) == "POKEBALL" then ball = id end
      if type(d) == "table" and Shop.norm(d.name) == "RARECANDY" then candy = id end
    end
    check("inbox: Poke Ball x10 is a Poke Ball", okA and ball and save.inventory[ball] == 10, okA and tostring(save.inventory[ball]) or rep)
    check("inbox: Rare Candy x2", okA and candy and save.inventory[candy] == 2)
  end

  for _, sl in ipairs(SaveData.listSlots(V)) do SaveData.deleteSlot(V, sl.id) end
  love.filesystem.remove(W.FILE)
  E.clock = realClock
  local summary = ("%d checks, %d failed"):format(pass + fail, fail)
  print(summary); log[#log + 1] = summary
  if os.getenv("OUT") then
    local o = io.open(os.getenv("OUT"), "wb"); if o then o:write(table.concat(log, "\n") .. "\n"); o:close() end
  end
  love.event.quit()
end
