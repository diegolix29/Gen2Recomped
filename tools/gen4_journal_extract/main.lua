-- tools/gen4_journal_extract/main.lua
--
-- Writes the Journal's notebook (src/import/Gen4JournalArt.lua) into an
-- EXISTING Platinum cache: the pictures to
-- <asset root>/assets/generated/gen4/journal/ and their index to
-- <cache dir>/gen4_journal_art.lua.
--
--   love tools/gen4_journal_extract <platinum .nds> <asset root> <cache dir>

function love.load(args)
  local ok, err = xpcall(function()
    local romPath, assetRoot, cacheDir = args[1], args[2], args[3]
    assert(romPath and assetRoot and cacheDir, "usage: love tools/gen4_journal_extract <rom> <asset root> <cache dir>")
    assetRoot, cacheDir = assetRoot:gsub("[/\\]$", ""), cacheDir:gsub("[/\\]$", "")
    local rom = assert(require("src.import.NdsRom").open(romPath))
    local images, why = require("src.import.Gen4JournalArt").images(rom)
    assert(images, why)
    require("src.import.CacheFs").mkdirReal(assetRoot .. "/assets/generated/gen4/journal")
    local index, n = {}, 0
    for key, pic in pairs(images) do
      local rel = "assets/generated/gen4/journal/" .. key .. ".png"
      local data = love.image.newImageData(pic.width, pic.height, "rgba8", pic.rgba)
      local f = assert(io.open(assetRoot .. "/" .. rel, "wb"))
      f:write(data:encode("png"):getString())
      f:close()
      index[key] = { path = rel }
      n = n + 1
    end
    local f = assert(io.open(cacheDir .. "/gen4_journal_art.lua", "wb"))
    f:write(require("src.import.LuaWriter").encode(index))
    f:close()
    print(("wrote %d journal pages and %s/gen4_journal_art.lua"):format(n, cacheDir))
  end, debug.traceback)
  if not ok then print(err) end
  love.event.quit()
end
