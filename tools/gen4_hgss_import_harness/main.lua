-- tools/gen4_hgss_import_harness/main.lua
--
-- A HEADLESS HEARTGOLD / SOULSILVER IMPORT, into the version's OWN folder.
--
--   CACHE_ROOT=G:/Gen2Recomped VERSION=heartgold \
--     ROM="./Pokemon - HeartGold Version (USA).nds" love tools/gen4_hgss_import_harness
--
-- Writes under <CACHE_ROOT>/<version>/ -- GameVersion's cachePrefix, the same
-- place the launcher would -- so it never touches another version's cache.
-- It runs the stages Gen4Versions lists for the family and nothing else, and
-- prints the report (`gen4_version.notPorted` says what is still missing).
-- The ground, buildings and sprites it writes are what
-- tools/gen4_overworld_harness then draws (POKEPORT_DATA_DIR / ASSET_ROOT).

function love.load()
  local ok, err = xpcall(function()
    local version = os.getenv("VERSION") or "heartgold"
    local root = assert(os.getenv("CACHE_ROOT"), "set CACHE_ROOT to the install folder")
    local rom = assert(os.getenv("ROM"), "set ROM to the cartridge path")
    local GameVersion = require("src.core.GameVersion")
    GameVersion.set(version)
    local info = GameVersion.info and GameVersion.info(version) or {}
    local prefix = info.cachePrefix or (version .. "/")
    assert(prefix ~= "" and prefix:match("^[%w_]+/$"), "refusing an empty or odd cache prefix")

    local CacheFs = require("src.import.CacheFs")
    CacheFs.prefix = prefix
    CacheFs.root = function() return root end

    -- Black and White go through the Gen 5 extractor, into the same layout
    local X = require(GameVersion.generation(version) == 5 and "src.import.RomExtractorGen5"
                      or "src.import.RomExtractorGen4")
    local x = assert(X.new(rom, version))
    local t = os.clock()
    -- STAGE_ONLY=models,fonts: just those stages, into the existing install,
    -- leaving the version record (and every other stage's output) as it is
    local only = os.getenv("STAGE_ONLY")
    if only then
      local methods = X.STAGE_METHODS or {}
      for name in only:gmatch("[%w_]+") do
        local chained = X.STAGE_CHAIN and X.STAGE_CHAIN[name]
        if chained then chained(x)
        else
          local method = methods[name] or name
          assert(type(x[method]) == "function", "no stage " .. name)
          x[method](x)
        end
      end
    else
      x:run()
    end
    x:close()
    print(("imported %s into %s/%s in %.1fs"):format(version, root, prefix, os.clock() - t))
    for _, name in ipairs(x.wrote or {}) do io.write(name, " ") end
    print()
    print("not ported: " .. table.concat(x.notPorted or {}, ", "))
  end, debug.traceback)
  if not ok then print("IMPORT FAILED: " .. tostring(err)) end
  love.event.quit(ok and 0 or 1)
end
