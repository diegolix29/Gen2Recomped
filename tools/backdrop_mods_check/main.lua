-- tools/backdrop_mods_check: the launcher backdrop's load must bring up no
-- mods, and the Play load after it in the same process must bring them all.
--   GAME=crystal ROOT=G:/Gen2Recomped lovec tools/backdrop_mods_check
io.stdout:setvbuf("line")
package.path = "./?.lua;./?/init.lua;" .. package.path
local ffi = require("ffi")
pcall(ffi.cdef, "int PHYSFS_mount(const char *newDir, const char *mountPoint, int appendToPath);")
local C = (pcall(function() return ffi.C.PHYSFS_mount end) and ffi.C) or ffi.load("love")
function love.load()
  local ok, err = xpcall(function()
    local root = os.getenv("ROOT") or "G:/Gen2Recomped"
    local v = os.getenv("GAME") or "crystal"
    require("src.core.GameVersion").set(v)
    assert(C.PHYSFS_mount(root .. "/" .. v, "", 0) ~= 0)
    assert(C.PHYSFS_mount(root, "", 1) ~= 0)   -- the mods folder beside the caches
    local Game = require("src.core.Game")
    Game.loadWithoutMods = true
    Game:load()
    Game.loadWithoutMods = nil
    local first = #(Game.modStatus.loaded or {})
    print(("backdrop load: %d mod(s) loaded, %d available"):format(first, #(Game.modStatus.available or {})))
    pcall(function() require("src.core.Data"):unloadGenerated() end)
    Game:load()
    local ids = {}
    for _, m in ipairs(Game.modStatus.loaded or {}) do ids[#ids + 1] = m.id end
    print(("play load: %d mod(s) loaded: %s"):format(#ids, table.concat(ids, ", ")))
    print(first == 0 and #ids > 0 and "backdrop mods: OK" or "backdrop mods: CHECK")
  end, debug.traceback)
  if not ok then print("FAILED: " .. tostring(err)) end
  love.event.quit()
end
