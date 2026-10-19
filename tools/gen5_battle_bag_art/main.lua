-- tools/gen5_battle_bag_art/main.lua
--
-- BLACK AND WHITE'S BATTLE BAG ART INTO AN EXISTING INSTALL, without a full
-- re-import: src/import/Gen5BattleBagArt.lua run against the ROM, its PNGs
-- written under INSTALL/assets/generated/gen4/battle5/ and its record as
-- INSTALL/data/generated/gen5_battle_bag.lua (the importer writes the same
-- two things on a fresh import).
--
--   INSTALL=G:/Gen2Recomped/black ROM="./Pokemon - Black Version (USA, Europe) (NDSi Enhanced).nds" \
--     lovec tools/gen5_battle_bag_art

local function env(k, d) local v = os.getenv(k) if v == nil or v == "" then return d end return v end

local function mkdirs(path)
  local acc = ""
  for part in path:gmatch("[^/]+") do
    acc = acc == "" and part or (acc .. "/" .. part)
    if not acc:match("^%a:$") then os.execute(('mkdir "%s" 2>nul'):format(acc:gsub("/", "\\"))) end
  end
end

function love.load()
  local ok, err = xpcall(function()
    local install = assert(env("INSTALL"), "INSTALL=<install root> is required")
    local romPath = env("ROM", "./Pokemon - Black Version (USA, Europe) (NDSi Enhanced).nds")
    local rom = assert(require("src.import.NdsRom").open(romPath))
    local ImageWriter = require("src.import.ImageWriter")
    mkdirs(install .. "/assets/generated/gen4/battle5")
    local x = { rom = rom }
    function x:saveImage(relative, image, extra)
      local data = ImageWriter.fromRGBA8(image.width, image.height, image.rgba)
      if not data then return nil end
      local path = "assets/generated/gen4/" .. relative .. ".png"
      local bytes = data:encode("png"):getString()
      local f = assert(io.open(install .. "/" .. path, "wb"))
      f:write(bytes); f:close()
      local entry = { path = path, width = image.width, height = image.height }
      for k, v in pairs(extra or {}) do entry[k] = v end
      return entry
    end
    local rec = assert(require("src.import.Gen5BattleBagArt").build(x), "no /a/0/9/9 in this ROM")
    local text = require("src.import.LuaWriter").encode(rec)
    local f = assert(io.open(install .. "/data/generated/gen5_battle_bag.lua", "wb"))
    f:write(text); f:close()
    local n = 0
    for _ in pairs(rec.images) do n = n + 1 end
    print(("[bag art] %d pictures, record written to %s/data/generated/gen5_battle_bag.lua"):format(n, install))
    if rom.close then rom:close() end
  end, debug.traceback)
  if not ok then print("FAILED:\n" .. tostring(err)) end
  love.event.quit(ok and 0 or 1)
end
