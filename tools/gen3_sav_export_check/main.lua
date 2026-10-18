-- tools/gen3_sav_export_check: export a port save as a cartridge .sav and
-- check what PKHeX keys on -- SaveBlock2 + 0xAC: 0 = Ruby/Sapphire,
-- 1 = FireRed/LeafGreen, anything else = Emerald -- and that money and the
-- bag read back the same after export -> import.
--   GAME=emerald SAVE=<port save .lua> ROOT=G:/Gen2Recomped lovec tools/gen3_sav_export_check
io.stdout:setvbuf("line")
package.path = "./?.lua;./?/init.lua;" .. package.path
local ffi = require("ffi")
pcall(ffi.cdef, "int PHYSFS_mount(const char *newDir, const char *mountPoint, int appendToPath);")
local C = (pcall(function() return ffi.C.PHYSFS_mount end) and ffi.C) or ffi.load("love")
function love.load()
  local ok, err = xpcall(function()
    local v = os.getenv("GAME") or "emerald"
    require("src.core.GameVersion").set(v)
    assert(C.PHYSFS_mount((os.getenv("ROOT") or "G:/Gen2Recomped") .. "/" .. v, "", 0) ~= 0)
    local f = assert(io.open(assert(os.getenv("SAVE")), "rb")); local bytes = f:read("*a"); f:close()
    local save = require("src.core.SaveSerializer").decode(bytes)
    local SC = require("src.save_convert.SaveConvert")
    local sav, why = SC.exportSav(save, v)
    assert(sav, why)
    if os.getenv("DS") then
      local function u32(b, o) local a, c, d, e = b:byte(o + 1, o + 4) return a + c * 256 + d * 65536 + e * 16777216 end
      print(("export %s: %d bytes"):format(v, #sav))
      for _, size in ipairs({ 0xC100, 0xCF2C, 0xF628 }) do
        for _, back in ipairs({ 0x14, 0x10, 0xC }) do
          print(("  general %05X: u32 at size-0x%X = 0x%X%s"):format(size, back, u32(sav, size - back),
            u32(sav, size - back) == size and "  <-- matches" or ""))
        end
      end
      if os.getenv("OUT") then local o = assert(io.open(os.getenv("OUT"), "wb")); o:write(sav); o:close() end
      return
    end
    local G3 = require("src.save_convert.Gen3Save")
    local blocks = G3.readBlocks(sav)
    local b2 = blocks.block2
    local function u32(b, o) local a, c, d, e = b:byte(o + 1, o + 4) return a + c * 256 + d * 65536 + e * 16777216 end
    local mark = u32(b2, 0xAC)
    print(("export %s: %d bytes, SaveBlock2+0xAC = 0x%08X -> PKHeX reads %s"):format(v, #sav, mark,
      mark == 0 and "RUBY/SAPPHIRE" or mark == 1 and "FIRERED/LEAFGREEN" or "EMERALD"))
    local back = SC.importSav(sav, nil, v)
    print(("money %s -> %s"):format(tostring(save.money), tostring(back and back.money)))
    local function bagSum(s) local n = 0 for _, e in pairs(s.inventory or {}) do n = n + (tonumber(type(e) == "table" and e.count or e) or 0) end return n end
    print(("bag count total %s -> %s"):format(bagSum(save), back and bagSum(back) or "?"))
    if os.getenv("OUT") then local o = assert(io.open(os.getenv("OUT"), "wb")); o:write(sav); o:close() end
  end, debug.traceback)
  if not ok then print("FAILED: " .. tostring(err)) end
  love.event.quit()
end
