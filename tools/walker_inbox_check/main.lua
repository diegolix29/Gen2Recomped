-- tools/walker_inbox_check: unpack a save's Pokewalker inbox the way
-- Game:restoreSave does, WITHOUT the pcall, so a failure shows.
--   GAME=crystal SAVE=<copy of saves/crystal/slot1.lua> ROOT=G:/Gen2Recomped lovec tools/walker_inbox_check
io.stdout:setvbuf("line")
package.path = "./?.lua;./?/init.lua;" .. package.path
local ffi = require("ffi")
pcall(ffi.cdef, "int PHYSFS_mount(const char *newDir, const char *mountPoint, int appendToPath);")
local C = (pcall(function() return ffi.C.PHYSFS_mount end) and ffi.C) or ffi.load("love")
function love.load()
  local ok, err = xpcall(function()
    local v = os.getenv("GAME") or "crystal"
    require("src.core.GameVersion").set(v)
    assert(C.PHYSFS_mount((os.getenv("ROOT") or "G:/Gen2Recomped") .. "/" .. v, "", 0) ~= 0)
    local Data = require("src.core.Data")
    Data:load()
    if os.getenv("WALK") then
      -- the walker's own flow on the staged save: send the first box Pokemon,
      -- walk, bring it home, then read the save back off disk
      local L = require("src.pokewalker.WalkerLink")
      local W = require("src.pokewalker.Walker")
      local Ser = require("src.core.SaveSerializer")
      local SaveData = require("src.core.SaveData")
      local function disk()
        local f = assert(io.open(SaveData.slotDiskPath(v, "slot1"), "rb")); local b = f:read("*a"); f:close()
        return Ser.decode(b)
      end
      local function count(s) local n = 0 for _, b in ipairs(s.boxes or {}) do for _ in pairs(b.mons or b) do n = n + 1 end end return n end
      print("WALK before: box mons", count(disk()))
      local list = L.boxMons(v, "slot1")
      print("WALK boxMons", #list, list[1] and list[1].name)
      local st = W.newState()
      print("WALK send", L.send(st, list[1], 1))
      print("WALK after send: box mons", count(disk()))
      W.addSteps(st, 500)
      print("WALK home", L.bringHome(st, false))
      local after = disk()
      local r = after.walkerInbox and after.walkerInbox.returning and after.walkerInbox.returning[1]
      print("WALK after home: box mons", count(after), "inbox placed", r and r.placed and (r.placed.box .. "/" .. r.placed.index), "raw kept", tostring(r and r.raw ~= nil))
      print("WALK boxMons after home", #L.boxMons(v, "slot1"))
    end
    local f = assert(io.open(assert(os.getenv("SAVE")), "rb")); local bytes = f:read("*a"); f:close()
    local save = require("src.core.SaveSerializer").decode(bytes)
    local inbox = save.walkerInbox
    print("inbox returning", #(inbox.returning or {}), "mons", #(inbox.mons or {}), "items", #(inbox.items or {}))
    for _, r in ipairs(inbox.returning or {}) do
      print("  returning species", r.raw and r.raw.species, "level", r.raw and r.raw.level, "steps", r.steps)
    end
    local function boxCount(s) local n = 0 for _, b in ipairs(s.boxes or {}) do for _ in pairs(b) do n = n + 1 end end return n end
    print("boxes before", boxCount(save), "currentBox", tostring(save.currentBox), "boxes table", type(save.boxes), "box", type(save.box))
    if os.getenv("FULL") then
      -- the real path: Game:load, then the title's CONTINUE (SaveData.load -> restoreSave)
      local SaveData = require("src.core.SaveData")
      local Game = require("src.core.Game")
      Game:load()
      SaveData.setActiveSlot(os.getenv("GAME") or "crystal", "slot1")
      local loaded, recovered = SaveData.load()
      print("SaveData.load:", type(loaded), "inbox in loaded", tostring(type(loaded) == "table" and loaded.walkerInbox ~= nil))
      if loaded then Game:restoreSave(loaded, recovered) end
      print("Game.save boxes", boxCount(Game.save), "inbox left", tostring(Game.save.walkerInbox ~= nil))
    else
      local report = require("src.pokewalker.WalkerInbox").apply(save, Data)
      print("report", report and (report.mons .. " walked, " .. report.caught .. " caught, " .. report.items .. " items") or "nil")
      print("boxes after", boxCount(save), "inbox left", tostring(save.walkerInbox ~= nil))
    end
  end, debug.traceback)
  if not ok then print("FAILED: " .. tostring(err)) end
  love.event.quit()
end
