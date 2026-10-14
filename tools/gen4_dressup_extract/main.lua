-- tools/gen4_dressup_extract/main.lua
--
-- Writes the dress-up art (src/import/Gen4DressUp.lua) into an EXISTING
-- Platinum cache: the pictures to <asset root>/assets/generated/gen4/dressup/
-- and their index to <cache dir>/gen4_dressup.lua.
--
--   love tools/gen4_dressup_extract <platinum .nds> <asset root> <cache dir>

function love.load(args)
  local ok, err = xpcall(function()
    local romPath, assetRoot, cacheDir = args[1], args[2], args[3]
    assert(romPath and assetRoot and cacheDir, "usage: love tools/gen4_dressup_extract <rom> <asset root> <cache dir>")
    assetRoot, cacheDir = assetRoot:gsub("[/\\]$", ""), cacheDir:gsub("[/\\]$", "")
    local rom = assert(require("src.import.NdsRom").open(romPath))
    local images, record = require("src.import.Gen4DressUp").images(rom)
    assert(images, record)
    require("src.import.CacheFs").mkdirReal(assetRoot .. "/assets/generated/gen4/dressup")
    local paths, n = {}, 0
    for key, pic in pairs(images) do
      local rel = "assets/generated/gen4/dressup/" .. key .. ".png"
      local data = love.image.newImageData(pic.width, pic.height, "rgba8", pic.rgba)
      local f = assert(io.open(assetRoot .. "/" .. rel, "wb"))
      f:write(data:encode("png"):getString())
      f:close()
      paths[key] = rel
      n = n + 1
    end
    for _, acc in pairs(record.accessories) do acc.path = paths[acc.key] end
    if record.room then record.room = { path = paths.room } end
    local f = assert(io.open(cacheDir .. "/gen4_dressup.lua", "wb"))
    f:write(require("src.import.LuaWriter").encode(record))
    f:close()
    print(("wrote %d dress-up pictures and %s/gen4_dressup.lua"):format(n, cacheDir))
  end, debug.traceback)
  if not ok then print(err) end
  love.event.quit()
end
