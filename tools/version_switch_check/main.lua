-- tools/version_switch_check: boot several games ONE AFTER ANOTHER in one
-- process, the way the launcher does after "return to launcher", and say what
-- each one resolves. Catches the previous game's data / menus leaking into the
-- next (reported: Crystal after Emerald showed Emerald's main menu, Gen 2
-- opened Gen 4's start menu, after exiting through the main menu).
--
--   GAMES=heartgold,crystal,emerald,crystal ROOT=G:/Gen2Recomped \
--     "/c/Program Files/LOVE/lovec.exe" tools/version_switch_check
io.stdout:setvbuf("line")
package.path = "./?.lua;./?/init.lua;" .. package.path
local ffi = require("ffi")
pcall(ffi.cdef, [[int PHYSFS_mount(const char *newDir, const char *mountPoint, int appendToPath);
int PHYSFS_unmount(const char *oldDir);]])
local C = (pcall(function() return ffi.C.PHYSFS_mount end) and ffi.C) or ffi.load("love")
local root = os.getenv("ROOT") or "G:/Gen2Recomped"

function love.load()
  local games = {}
  for g in (os.getenv("GAMES") or "heartgold,crystal"):gmatch("[^,]+") do games[#games + 1] = g end
  local prev
  local bad = 0
  for i, v in ipairs(games) do
    local ok, err = xpcall(function()
      local GameVersion = require("src.core.GameVersion")
      GameVersion.set(v)
      -- what main.lua's bootGame does on the way back IN
      pcall(function() require("src.core.Data"):unloadGenerated() end)
      if prev then C.PHYSFS_unmount(root .. "/" .. prev) end
      local dir = root .. "/" .. v
      assert(C.PHYSFS_mount(dir, "", 0) ~= 0, "mount " .. dir)
      pcall(function() require("src.render.Assets").invalidate() end)
      local Game = require("src.core.Game")
      Game:load()
      local D = Game.data
      local Screens = require("src.ui.Screens")
      local function res(id) local okR, r = pcall(Screens.resolveId, Game, id) return okR and r or ("ERR " .. tostring(r)) end
      local scr = (D.field and D.field.boot and D.field.boot.screens) or {}
      local gen = GameVersion.generation and GameVersion.generation(v)
      local foreign = {}
      for k in pairs(D) do
        k = tostring(k)
        local g = k:match("^gen(%d)_")
        if g and tonumber(g) ~= gen and not (gen == 5 and g == "4") then foreign[#foreign + 1] = k end
      end
      table.sort(foreign)
      local top = Game.stack and Game.stack:top()
      print(("== %d %s (gen %s): version=%s gen3Cache=%s gen4Cache=%s"):format(i, v, tostring(gen),
        GameVersion.get(), tostring(D.isGen3Cache), tostring(D.isGen4Cache)))
      print(("   boot.screens title=%s newGame=%s startMenu=%s bag=%s party=%s"):format(
        tostring(scr.title), tostring(scr.newGame), tostring(scr.startMenu), tostring(scr.bag), tostring(scr.party)))
      print(("   resolve StartMenu=%s MainMenu=%s TitleState=%s BagMenu=%s PartyMenu=%s"):format(
        res(scr.startMenu or "StartMenu"), res("MainMenu"), res(scr.title or "TitleState"), res(scr.bag or "BagMenu"), res(scr.party or "PartyMenu")))
      print(("   first state: %s"):format(tostring(top and (top.__name or top.name or (getmetatable(top) or {}).__name) or top)))
      print(("   other-generation data left on Data: %s"):format(#foreign > 0 and table.concat(foreign, " ") or "none"))
      if #foreign > 0 then bad = bad + 1 end
      prev = v
    end, debug.traceback)
    if not ok then print("FAILED " .. v .. ": " .. tostring(err)) bad = bad + 1 end
  end
  print(bad == 0 and "version switch: clean" or ("version switch: " .. bad .. " game(s) carried another's data"))
  love.event.quit()
end
