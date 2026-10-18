-- DATA=<game-data folder holding the imported caches> (default G:/Gen2Recomped)
-- OLD=<folder of this port's old .lua saves to import: <version>_*.lua>
-- `love tools/save_variants_check`
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
  local SaveData = require("src.core.SaveData")
  local SaveConvert = require("src.save_convert.SaveConvert")
  local SaveFileIO = require("src.import.SaveFileIO")
  local NdsSave = require("src.save_convert.NdsSave")
  local GameVersion = require("src.core.GameVersion")
  local pass, fail = 0, 0
  local function check(name, ok, extra)
    if ok then pass = pass + 1 else fail = fail + 1 end
    print((ok and "ok   " or "FAIL ") .. name .. (extra ~= nil and ("  " .. tostring(extra)) or ""))
  end
  SaveData.setDataDir(os.getenv("DATA") or "G:/Gen2Recomped")
  local function clear(v) for _, s in ipairs(SaveData.listSlots(v)) do SaveData.deleteSlot(v, s.id) end end

  local cases = {
    red = { { "+48 RTC", function(b) return b .. string.rep("\0", 48) end },
            { "+44 RTC", function(b) return b .. string.rep("\1", 44) end },
            { "64 KiB 0xFF pad", function(b) return b .. string.rep("\255", 32768) end } },
    crystal = { { "+48 RTC", function(b) return b .. string.rep("\7", 48) end },
                { "mirrored 64 KiB", function(b) return b .. b end } },
    emerald = { { "+16 mGBA RTC", function(b) return b .. string.rep("\3", 16) end },
                { "64 KiB flash", function(b) return b:sub(1, 65536) end },
                { "256 KiB pad", function(b) return b .. string.rep("\255", 131072) end } },
    platinum = { { ".dsv", function(b) return NdsSave.wrapDesmume(b) end },
                 { "1 MiB", function(b) return b .. string.rep("\255", NdsSave.SIZE) end } },
    heartgold = { { ".dsv", function(b) return NdsSave.wrapDesmume(b) end } },
    black = { { ".dsv", function(b) return NdsSave.wrapDesmume(b) end } },
  }
  for _, v in ipairs({ "red", "crystal", "emerald", "platinum", "heartgold", "black" }) do
    clear(v)
    local gen = GameVersion.generation(v)
    local base = SaveConvert.mergeDefaults({ player = { name = "TEST", id = 4321 }, party = {}, boxes = {} }, v, gen)
    local bytes, err = SaveConvert.exportSav(base, v)
    if not bytes then
      print("skip " .. v .. ": export failed (" .. tostring(err) .. ")")
    else
      local ok, slot = SaveFileIO.importToSlot(bytes, v)
      check(v .. ": raw " .. #bytes .. " bytes imports", ok, slot)
      if not ok then
        print("  (baseline does not import; variants skipped)")
      else
        for _, c in ipairs(cases[v]) do
          local variant = c[2](bytes)
          local ok2, res = SaveFileIO.importToSlot(variant, v)
          check(("%s: %s (%d bytes)"):format(v, c[1], #variant), ok2, res)
        end
        local ok3, res3 = SaveFileIO.importToSlot(bytes .. ("junk"):rep(2000), v)
        if gen >= 4 then
          -- NdsSave.unwrap's own rule: the first 512 KiB of a longer DS file
          check(v .. ": trailing bytes after a DS image are trimmed", ok3, res3)
        else
          check(v .. ": real data after the image is still refused", not ok3, res3)
        end
      end
    end
  end

  -- this port's own old saves (copies of real slot files; never the originals)
  local OLD = os.getenv("OLD") or "G:/Gen2Recomped/scratch_claude/save_variants/real"
  for _, name in ipairs({ "slot1.lua:red", "save_online.lua:red", "emerald_old_20260826.lua:emerald" }) do
    local file, v = name:match("^(.-):(.+)$")
    local path = OLD .. "/" .. file
    local f = io.open(path, "rb")
    if f then
      f:close()
      local ok, slot = SaveFileIO.importToSlot(path, v)
      check(("old port save %s -> %s"):format(file, v), ok, slot)
      if ok then
        local s = SaveData.load(v)
        check(("  %s loads back at the current format"):format(file),
          s and s.meta and s.meta.format == require("src.core.Version").saveFormat and s.version == v)
      end
      local okx, why = SaveFileIO.importToSlot(path, v == "red" and "crystal" or "red")
      check(("  %s refused on another game's page"):format(file), not okx, why)
    else
      print("skip old save " .. path)
    end
  end
  for _, v in ipairs({ "red", "crystal", "emerald", "platinum", "heartgold", "black" }) do clear(v) end
  print(("%d checks, %d failed"):format(pass + fail, fail))
  love.event.quit(fail == 0 and 0 or 1)
end
