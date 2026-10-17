-- CLOUD=<scratch folder> love tools/cloud_sync_check
-- Plays two devices against one sync folder by swapping cloud_sync.lua.
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
  local folder = assert(os.getenv("CLOUD"), "set CLOUD to a scratch folder")
  local C = require("src.import.CloudSync")
  local SaveData = require("src.core.SaveData")
  local Ser = require("src.core.SaveSerializer")
  local V = "red"
  local pass, fail = 0, 0
  local function check(name, ok, extra)
    if ok then pass = pass + 1 else fail = fail + 1 end
    print((ok and "ok   " or "FAIL ") .. name .. (extra and ("  " .. tostring(extra)) or ""))
  end
  -- a clean slate: no slots, no state
  for _, s in ipairs(SaveData.listSlots(V)) do SaveData.deleteSlot(V, s.id) end
  love.filesystem.remove(C.STATE_FILE)
  local function slots() return SaveData.listSlots(V) end
  local function saveWith(name) return { player = { name = name }, money = #name } end
  local function readSlot(id)
    local p = SaveData.slotDiskPath(V, id)
    local f = io.open(p, "rb"); local s = f and f:read("*a"); if f then f:close() end
    return s and Ser.decode(s)
  end

  -- DEVICE A: one save, first sync uploads it
  local a1 = SaveData.createSlot(V)
  SaveData.writeSlot(V, a1, saveWith("ASH"))
  local t = C.syncVersions(folder, { V })
  check("first sync uploads", t and t.uploaded == 1, C.describe(t))
  local stA = love.filesystem.read(C.STATE_FILE)

  -- DEVICE B: its own save in the same slot id, never synced -> nothing replaced
  for _, s in ipairs(slots()) do SaveData.deleteSlot(V, s.id) end
  love.filesystem.remove(C.STATE_FILE)
  local b1 = SaveData.createSlot(V)
  SaveData.writeSlot(V, b1, saveWith("GARY"))
  t = C.syncVersions(folder, { V })
  check("second device uploads its own and pulls A's as new", t and t.uploaded == 1 and t.new == 1, C.describe(t))
  local names = {}
  for _, s in ipairs(slots()) do local d = readSlot(s.id); names[#names + 1] = d and d.player.name end
  table.sort(names)
  check("both saves kept on B", table.concat(names, ",") == "ASH,GARY", table.concat(names, ","))
  check("B's own slot untouched", readSlot(b1).player.name == "GARY")
  -- B plays on A's save (the pulled slot) and syncs: uploaded
  local pulled
  for _, s in ipairs(slots()) do if s.id ~= b1 then pulled = s.id end end
  SaveData.writeSlot(V, pulled, saveWith("ASH2"))
  t = C.syncVersions(folder, { V })
  check("B's change to A's save goes up", t and t.uploaded == 1, C.describe(t))
  local stB = love.filesystem.read(C.STATE_FILE)

  -- BACK ON A: restore its local world (one slot, ASH) and state
  for _, s in ipairs(slots()) do SaveData.deleteSlot(V, s.id) end
  local a = SaveData.createSlot(V)
  check("A's slot id comes back the same", a == a1, a)
  SaveData.writeSlot(V, a, saveWith("ASH"))
  love.filesystem.write(C.STATE_FILE, stA)
  t = C.syncVersions(folder, { V })
  check("A takes the cloud's newer copy", t and t.downloaded == 1, C.describe(t))
  check("A now reads ASH2", readSlot(a).player.name == "ASH2")
  check("A's old copy backed up", love.filesystem.getInfo(("cloud_backups/%s/%s.1.lua"):format(V, a)) ~= nil)
  check("A also pulled B's own save", t.new == 1)

  -- BOTH CHANGE: A edits, then the cloud is edited behind its back
  SaveData.writeSlot(V, a, saveWith("ASH3"))
  local stNow = C.loadState()
  local cloudId = stNow.links[V][a].cloudId
  local p = folder .. "/" .. C.ROOT .. "/saves/" .. V .. "/" .. cloudId .. ".lua"
  local f = io.open(p, "wb"); f:write(Ser.encode(saveWith("ASH-B"))); f:close()
  local before = #slots()
  t = C.syncVersions(folder, { V })
  check("both changed keeps both", t and t["kept both"] == 1 and #slots() == before + 1, C.describe(t))
  check("A keeps its own ASH3", readSlot(a).player.name == "ASH3")
  local cloudNow = io.open(p, "rb"); local cs = Ser.decode(cloudNow:read("*a")); cloudNow:close()
  check("cloud now holds A's ASH3", cs.player.name == "ASH3")
  check("cloud backup of ASH-B kept", io.open(folder .. "/" .. C.ROOT .. "/backups/" .. V .. "/" .. cloudId .. ".1.lua", "rb") ~= nil)

  -- two backups only
  for i = 4, 7 do
    SaveData.writeSlot(V, a, saveWith("ASH" .. i))
    C.syncVersions(folder, { V })
  end
  local dir = folder .. "/" .. C.ROOT .. "/backups/" .. V
  check("never more than two cloud backups", io.open(dir .. "/" .. cloudId .. ".3.lua", "rb") == nil
        and io.open(dir .. "/" .. cloudId .. ".2.lua", "rb") ~= nil)
  print(("%d checks, %d failed"):format(pass + fail, fail))
  for _, s in ipairs(slots()) do SaveData.deleteSlot(V, s.id) end
  love.event.quit()
end
