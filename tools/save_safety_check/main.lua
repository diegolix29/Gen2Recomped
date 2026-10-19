-- tools/save_safety_check (see conf.lua for how to run it).
--
-- Simulates every save-loss path from docs/save-safety.md and checks that no
-- save is lost: a crash mid-write (truncated / empty main file, a .tmp left
-- before or after the swap), an undecodable main file, a missing main file
-- with only backups, the slot registry (options.lua) lost, backup rotation
-- over a bad main file, a New Game over an existing save, the Pokewalker
-- writing while a game has the slot open, a cloud pull of an older / empty
-- copy, a deleted slot, the restore tool, the walker's own state file, and a
-- save in another storage location.  Exit code 1 on any failure.
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

local pass, fail = 0, 0
local function check(name, ok, extra)
  if ok then pass = pass + 1 else fail = fail + 1 end
  print((ok and "ok   " or "FAIL ") .. name .. (extra ~= nil and ("  " .. tostring(extra)) or ""))
end

function love.load()
  local saveDir = love.filesystem.getSaveDirectory()
  -- the guard this whole tool rests on: never the player's real folders
  assert(saveDir:find("savesafetycheck", 1, true), "refusing to run outside the check identity: " .. saveDir)
  print("save dir: " .. saveDir)

  local SaveData = require("src.core.SaveData")
  local Safety = require("src.core.SaveSafety")
  local Ser = require("src.core.SaveSerializer")
  local GameVersion = require("src.core.GameVersion")
  local lfs = love.filesystem
  local V = "red"
  GameVersion.set(V)
  -- no other storage locations unless a scenario adds one
  SaveData._setOtherLocations({})

  -- only ever inside this identity's save directory (PhysFS removes from the
  -- write directory alone; the repo mounted for require is never touched)
  local function wipe(dir)
    for _, item in ipairs(lfs.getDirectoryItems(dir)) do
      local p = dir .. "/" .. item
      if lfs.getInfo(p, "directory") then wipe(p) end
      lfs.remove(p)
    end
    lfs.remove(dir)
  end
  local TOP = { "saves", "pokewalker_backups", "cloud_backups", "elsewhere_root" }
  local FILES = { "options.lua", "pokewalker.lua", "cloud_sync_mem.lua" }
  local function fresh()
    for _, d in ipairs(TOP) do if lfs.getInfo(d, "directory") then wipe(d) end end
    for _, f in ipairs(FILES) do
      for _, sfx in ipairs({ "", ".tmp", ".bak" }) do lfs.remove(f .. sfx) end
    end
    for _, item in ipairs(lfs.getDirectoryItems("")) do
      if item:match("^options%.lua") or item:match("^pokewalker%.lua") then lfs.remove(item) end
    end
    SaveData.resetSlotState()
    SaveData._resetSafetyState()
    SaveData._setOtherLocations({})
  end
  local function game(name, secs, extra)
    local t = { version = V, player = { name = name, id = 1234, map = "PALLET_TOWN", x = 1, y = 1 },
                party = { { species = "PIDGEY", level = 3 } }, boxes = { {} }, playTime = secs or 100,
                flags = {}, money = 3000 }
    for k, v in pairs(extra or {}) do t[k] = v end
    return t
  end
  local function slotFile(id) return ("saves/%s/%s.lua"):format(V, id) end
  local function newActiveSlot()
    local id = SaveData.createSlot(V)
    SaveData.setActiveSlot(V, id)
    return id
  end
  local function relaunch()
    SaveData.resetSlotState()
    SaveData._resetSafetyState()
  end

  -- 1. CRASH MID-WRITE: main truncated to half
  fresh()
  local id = newActiveSlot()
  check("save writes", SaveData.save(game("ETHAN", 100)))
  check("second save writes", SaveData.save(game("ETHAN", 200)))
  local full = lfs.read(slotFile(id))
  lfs.write(slotFile(id), full:sub(1, math.floor(#full / 2)))
  relaunch()
  local s, from = SaveData.load(V)
  check("truncated main: save recovered", s and s.player.name == "ETHAN", from)
  check("truncated main: recovery reported", from ~= nil, from)
  check("truncated main: main file put back", Safety.decodeSave(lfs.read(slotFile(id))) ~= nil)
  local corrupt = false
  for _, it in ipairs(lfs.getDirectoryItems("saves/" .. V)) do
    if it:find(id .. ".lua.corrupt-", 1, true) then corrupt = true end
  end
  check("truncated main: the cut-short file is kept aside", corrupt)

  -- 2. EMPTY main (killed between truncate and write) with .bak
  relaunch()
  lfs.write(slotFile(id), "")
  s, from = SaveData.load(V)
  check("empty main: save recovered", s and s.player.name == "ETHAN", from)

  -- 3. .tmp written and verified, swap never happened: the newer one wins
  relaunch()
  SaveData.save(game("ETHAN", 300))
  lfs.write(slotFile(id) .. ".tmp", Ser.encode(game("ETHAN", 400)))
  relaunch()
  s = SaveData.load(V)
  check("staged .tmp newer than main is used", s and s.playTime == 400, s and s.playTime)

  -- 4. main removed (Windows rename window), .tmp holds the save
  relaunch()
  lfs.write(slotFile(id) .. ".tmp", lfs.read(slotFile(id)))
  lfs.remove(slotFile(id))
  s = SaveData.load(V)
  check("missing main, .tmp present: recovered", s and s.player.name == "ETHAN")

  -- 5. BACKUP ROTATION over a bad main: the good .bak must survive a save
  fresh()
  id = newActiveSlot()
  SaveData.save(game("LYRA", 100))
  SaveData.save(game("LYRA", 200))
  local goodBak = lfs.read(slotFile(id) .. ".bak")
  lfs.write(slotFile(id), "return { player = ")      -- cut short
  relaunch()
  -- the game (which could not load) starts over and saves: nothing may go
  SaveData.save(game("NEWKID", 1, { player = { name = "NEWKID", id = 999 } }))
  check("bad main never rotated into .bak", lfs.read(slotFile(id) .. ".bak") == goodBak)
  local rows = SaveData.slotBackups(V, id)
  local hasLyra = false
  for _, r in ipairs(rows) do if r.ok and r.name == "LYRA" then hasLyra = true end end
  check("old playthrough still listed by the restore tool", hasLyra)

  -- 6. NEW GAME over an existing save keeps a 'replaced' snapshot
  fresh()
  id = newActiveSlot()
  SaveData.save(game("KRIS", 5000))
  relaunch()
  SaveData.save(game("SOMEONE", 1, { player = { name = "SOMEONE", id = 4321 } }))
  SaveData.save(game("SOMEONE", 2, { player = { name = "SOMEONE", id = 4321 } }))
  SaveData.save(game("SOMEONE", 3, { player = { name = "SOMEONE", id = 4321 } }))
  local replaced
  for _, e in ipairs(Safety.listBackups(lfs, slotFile(id))) do
    if e.tag == "replaced" then replaced = Safety.decodeSave(lfs.read(e.file)) end
  end
  check("new game over a save: old one kept as a 'replaced' snapshot", replaced and replaced.player.name == "KRIS")

  -- 7. MISSING main with only stamped backups: CONTINUE gate sees a save
  fresh()
  id = newActiveSlot()
  SaveData.save(game("SILVER", 100))
  SaveData.save(game("SILVER", 200))   -- rolling snapshot of the first
  lfs.remove(slotFile(id))
  lfs.remove(slotFile(id) .. ".bak")
  relaunch()
  local slots = SaveData.listSlots(V)
  check("missing main + backups: slot still listed with its save", slots[1] and slots[1].exists, slots[1] and slots[1].recoveredFrom)
  SaveData.saveFilename(V)                    -- what every CONTINUE gate calls
  check("missing main + backups: main put back before the title asks", lfs.getInfo(slotFile(id)) ~= nil)
  s, from = SaveData.load(V)
  check("missing main + backups: loads and says so", s and s.player.name == "SILVER" and from ~= nil, from)

  -- 8. UNDECODABLE everything: the slot is shown as unreadable, not empty
  fresh()
  id = newActiveSlot()
  lfs.createDirectory("saves/" .. V)
  lfs.write(slotFile(id), "garbage")
  relaunch()
  slots = SaveData.listSlots(V)
  check("undecodable slot is listed as unreadable", slots[1] and slots[1].unreadable == true)
  check("undecodable slot load returns nil (no crash)", SaveData.load(V) == nil)

  -- 9. THE REGISTRY LOST: options.lua truncated, then gone entirely
  fresh()
  local a = newActiveSlot(); SaveData.save(game("GOLD", 100))
  local b = SaveData.createSlot(V); SaveData.writeSlot(V, b, game("GOLD2", 50))
  SaveData.saveOptions(SaveData.loadOptions())   -- leaves options.lua.bak
  lfs.write("options.lua", lfs.read("options.lua"):sub(1, 20))
  relaunch()
  check("cut-short options.lua: slots come back from its .bak", #SaveData.listSlots(V) == 2, #SaveData.listSlots(V))
  lfs.remove("options.lua"); lfs.remove("options.lua.bak"); lfs.remove("options.lua.tmp")
  relaunch()
  slots = SaveData.listSlots(V)
  check("options.lua gone: orphaned slot files re-registered", #slots == 2, #slots)
  local c = SaveData.createSlot(V)
  check("a new slot never reuses an orphan's id", c ~= a and c ~= b, c)

  -- 10. WALKER WRITE WHILE THE GAME HAS THE SLOT OPEN
  fresh()
  id = newActiveSlot()
  SaveData.save(game("HIKER", 100, { boxes = { { { species = "ONIX", level = 9 } } } }))
  relaunch()
  local live = SaveData.load(V)              -- the game has it open
  -- another process's marker: the walker refuses
  lfs.write(slotFile(id) .. ".open", Ser.encode({ session = "other-process", t = os.time() }))
  local Link = require("src.pokewalker.WalkerLink")
  local okW, whyW = Link.deliverTo(V, id, { items = { { name = "POTION", count = 1 } } })
  check("walker refuses a slot open in another game window", not okW, whyW)
  -- ...and if it wrote anyway (an old build), the game's save keeps it
  local disk = Safety.decodeSave(lfs.read(slotFile(id)))
  disk.boxes[1][2] = { species = "PIKACHU", level = 12 }
  disk.walkerInbox = { returning = { { placed = { box = 1, index = 2 }, species = "PIKACHU", steps = 500 } },
                       mons = { { species = 16, level = 5 } }, items = { { name = "POTION", count = 1 } } }
  lfs.write(slotFile(id), Ser.encode(disk))
  live.playTime = 999
  SaveData.save(live)
  local after = Safety.decodeSave(lfs.read(slotFile(id)))
  local ret = after.walkerInbox and after.walkerInbox.returning and after.walkerInbox.returning[1]
  check("walked Pokemon survives the game's save", ret and ret.raw and ret.raw.species == "PIKACHU")
  check("walker catches and items survive", after.walkerInbox and #after.walkerInbox.mons == 1 and #after.walkerInbox.items == 1)
  check("game progress kept too", after.playTime == 999)
  local ext = false
  for _, e in ipairs(Safety.listBackups(lfs, slotFile(id))) do if e.tag == "external" then ext = true end end
  check("the externally-written file kept as a snapshot", ext)
  live.playTime = 1000
  SaveData.save(live)
  after = Safety.decodeSave(lfs.read(slotFile(id)))
  check("no duplicate deliveries on the next save", #after.walkerInbox.returning == 1 and #after.walkerInbox.mons == 1)
  lfs.remove(slotFile(id) .. ".open")
  SaveData.closeOpen()

  -- 11. CLOUD: an older, an empty and an undecodable copy
  fresh()
  local cloud = os.getenv("CLOUD") or (saveDir .. "/cloudfolder")
  local C = require("src.import.CloudSync")
  local store, files = nil, {}
  store = { kind = "mem", label = "mem",
    read = function(rel) return files[rel] end,
    write = function(rel, data) files[rel] = data; return true end,
    list = function(dir)
      local out = {}
      for rel in pairs(files) do
        local name = rel:match("^" .. dir:gsub("%p", "%%%0") .. "/([^/]+)$")
        if name then out[#out + 1] = name end
      end
      return out
    end }
  id = SaveData.createSlot(V)
  SaveData.writeSlot(V, id, game("BLUE", 5000))
  local st = C.loadState("mem")
  check("cloud: first sync uploads", C.syncSlot(store, st, V, id) == "uploaded")
  local link = st.links[V][id]
  local rel = ("saves/%s/%s.lua"):format(V, link.cloudId)
  files[rel] = Ser.encode(game("BLUE", 60))         -- an older branch from another device
  local what = C.syncSlot(store, st, V, id)
  local mine = Safety.decodeSave(Safety.read(lfs, slotFile(id)))
  check("cloud: older copy never replaces the local save", mine.playTime == 5000, what)
  check("cloud: the older copy kept as its own slot", #SaveData.listSlots(V) == 2, what)
  files[rel] = ""                                    -- an empty remote
  what = C.syncSlot(store, st, V, id)
  mine = Safety.decodeSave(Safety.read(lfs, slotFile(id)))
  check("cloud: empty remote never replaces the local save", mine and mine.playTime == 5000, what)
  check("cloud: empty remote gets the local save back", Safety.decodeSave(files[rel]) ~= nil)
  local cloudBefore = files[rel]
  lfs.write(slotFile(id), "return {")                -- local file cut short
  what = C.syncSlot(store, st, V, id)
  check("cloud: an unreadable local file is never uploaded", files[rel] == cloudBefore, what)

  -- 12. DELETE is not erase
  fresh()
  id = newActiveSlot()
  SaveData.save(game("CRYS", 700))
  SaveData.deleteSlot(V, id)
  local del = SaveData.deletedSlots(V)
  check("deleted slot listed for undelete", del[1] and del[1].ok and del[1].name == "CRYS")
  local back = SaveData.restoreAsNewSlot(V, del[1], "CRYS (restored)")
  check("deleted slot comes back as a new slot", back and Safety.decodeSave(lfs.read(slotFile(back))).player.name == "CRYS")

  -- 13. RESTORE TOOL: pick an older copy; the restore itself is undoable
  fresh()
  id = newActiveSlot()
  SaveData.save(game("HEART", 100))
  SaveData.save(game("HEART", 200))
  rows = SaveData.slotBackups(V, id)
  local older
  for _, r in ipairs(rows) do if r.ok and not r.current then older = r end end
  check("restore tool lists the previous copy", older ~= nil, #rows)
  check("restore succeeds", older and SaveData.restoreBackup(V, id, older))
  check("restored copy is the slot's save now", Safety.decodeSave(lfs.read(slotFile(id))).playTime == 100)
  local pre = false
  for _, e in ipairs(Safety.listBackups(lfs, slotFile(id))) do if e.tag == "prerestore" then pre = true end end
  check("the replaced current file is kept (prerestore)", pre)

  -- 14. THE WALKER'S OWN STATE FILE cut short: the walking Pokemon survives
  fresh()
  local W = require("src.pokewalker.Walker")
  W.live = nil
  local wst = W.load()
  wst.walking = { name = "TOGEPI", steps = 1234 }
  W.save(wst)
  wst.walking.steps = 2000
  W.save(wst)
  lfs.write(W.FILE, lfs.read(W.FILE):sub(1, 30))
  W.live = nil
  local back2 = W.load()
  check("walker state cut short: the walking Pokemon is still there", back2.walking and back2.walking.name == "TOGEPI")

  -- 15. A SAVE IN ANOTHER STORAGE LOCATION (Android volume change, portable
  --     switch, old identity): found read-only, copied in on load
  fresh()
  local elsewhere = saveDir .. "/elsewhere_root"
  lfs.createDirectory("elsewhere_root/saves/" .. V)
  id = newActiveSlot()
  lfs.write("elsewhere_root/" .. slotFile(id), Ser.encode(game("FARAWAY", 3000)))
  SaveData._setOtherLocations({ elsewhere })
  relaunch(); SaveData._setOtherLocations({ elsewhere })
  s, from = SaveData.load(V)
  check("save in another location is found", s and s.player.name == "FARAWAY", from)
  check("...and copied into this location", lfs.getInfo(slotFile(id)) ~= nil)
  check("...without touching the other copy", lfs.getInfo("elsewhere_root/" .. slotFile(id)) ~= nil)
  -- the whole save directory moved: no registry, no files here at all
  lfs.remove(slotFile(id)); lfs.remove(slotFile(id) .. ".bak"); lfs.remove(slotFile(id) .. ".backups")
  for _, it in ipairs(lfs.getDirectoryItems("saves/" .. V)) do lfs.remove("saves/" .. V .. "/" .. it) end
  for _, f in ipairs({ "options.lua", "options.lua.bak", "options.lua.tmp" }) do lfs.remove(f) end
  relaunch(); SaveData._setOtherLocations({ elsewhere })
  local moved = SaveData.listSlots(V)
  check("empty location: slots from the other location are listed", moved[1] and moved[1].exists, #moved)
  s = SaveData.load(V)
  check("empty location: the save loads", s and s.player.name == "FARAWAY")

  -- 16. ATOMIC WRITE on a disk that cuts writes short: main untouched
  local mem = {}
  local badFs = {
    getInfo = function(n) return mem[n] and { type = "file" } or nil end,
    read = function(n) return mem[n] end,
    write = function(n, d) mem[n] = d:sub(1, 5); return true end,
    remove = function(n) mem[n] = nil end,
  }
  mem["x.lua"] = Ser.encode(game("SAFE", 1))
  local okA = Safety.atomicWrite(badFs, "x.lua", Ser.encode(game("NEW", 2)), { bak = "x.lua.bak", decode = Safety.decodeSave })
  check("full disk: the write reports failure", not okA)
  check("full disk: the old save is untouched", Safety.decodeSave(mem["x.lua"]) ~= nil)

  -- 17. A non-save table is never written
  check("a save with no player table is refused", SaveData.save({ version = V }) == false)

  fresh()
  print(("%d checks, %d failed"):format(pass + fail, fail))
  love.event.quit(fail > 0 and 1 or 0)
end
