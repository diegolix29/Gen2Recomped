-- WalkerArt checks.
--   FIX=<dir>  a folder holding only_<version>/<version> junctions (or copies)
--              of imported caches -- default G:/Gen2Recomped/scratch_claude/
--              walker_art_fixture (see docs/pokewalker.md "Art").
-- `love tools/walker_art_check`
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
  local A = require("src.pokewalker.WalkerArt")
  local pass, fail = 0, 0
  local function check(name, ok, extra)
    if ok then pass = pass + 1 else fail = fail + 1 end
    print((ok and "ok   " or "FAIL ") .. name .. (extra ~= nil and ("  " .. tostring(extra)) or ""))
  end
  local FIX = (os.getenv("FIX") or "G:/Gen2Recomped/scratch_claude/walker_art_fixture"):gsub("\\", "/")
  local function only(...)
    local t = {}
    for _, v in ipairs({ ... }) do t[#t + 1] = FIX .. "/only_" .. v end
    return t
  end
  local function use(list) A._roots = list; A.forget() end
  local function from(fn, ...)
    local r = { fn(...) }
    return r[1] ~= nil, r[#r]
  end

  -- 1. THE ANDROID / FUSED DEFAULT: no game-data folder chosen, no portable
  --    folder -> the cache is in the save directory and nowhere else.  The
  --    old code read SaveData.dataDir() only, which is nil here.
  A._roots = nil; A.forget()
  local SaveData = require("src.core.SaveData")
  check("no data folder in this identity (the Android default)", SaveData.dataDir() == nil)
  local saveDir = love.filesystem.getSaveDirectory():gsub("[/\\]+$", "")
  local found = false
  for _, r in ipairs(A._rootList()) do if r == saveDir then found = true end end
  check("the save directory is searched", found, saveDir)
  -- a tiny Gen 2 cache written into the save directory only
  local png = love.image.newImageData(16, 32)
  png:mapPixel(function(x, y) return 1, (y < 16) and 0.5 or 0.2, 0, 1 end)
  local front = love.image.newImageData(40, 40)
  front:mapPixel(function(x, y) return (x > 4 and x < 36) and 1 or 0, 0, 0, (x > 4 and x < 36) and 1 or 0 end)
  love.filesystem.createDirectory("crystal/data/generated")
  love.filesystem.createDirectory("crystal/assets/generated/icons")
  love.filesystem.createDirectory("crystal/assets/generated/battle/front")
  love.filesystem.write("crystal/data/generated/pokemon.lua",
    'return { SPECIES_025 = { dex = 25, id = "SPECIES_025", spriteFront = "assets/generated/battle/front/pikachu.png" } }')
  love.filesystem.write("crystal/data/generated/icons.lua",
    'return { bySpecies = { SPECIES_025 = { image = "assets/generated/icons/species_025.png" } } }')
  love.filesystem.write("crystal/assets/generated/icons/species_025.png", png:encode("png"):getString())
  love.filesystem.write("crystal/assets/generated/battle/front/pikachu.png", front:encode("png"):getString())
  local img, fw, fh, facings, v = A.walk(25)
  check("save-dir cache: walking sprite found", img ~= nil and v == "crystal" and fw == 16 and fh == 16, v)
  check("save-dir cache: two-frame bounce for every facing", facings and #facings.right == 2)
  local fimg, fv = A.front(25)
  check("save-dir cache: front found", fimg ~= nil and fv == "crystal", fv)
  local b = fimg and A.bounds(fimg)
  check("front trimmed to its opaque bounds", b and b.x == 5 and b.w == 31, b and (b.x .. "," .. b.w))
  for _, p in ipairs({ "crystal/assets/generated/battle/front/pikachu.png", "crystal/assets/generated/battle/front",
                       "crystal/assets/generated/icons/species_025.png", "crystal/assets/generated/icons",
                       "crystal/assets/generated/battle", "crystal/assets/generated", "crystal/assets",
                       "crystal/data/generated/pokemon.lua", "crystal/data/generated/icons.lua",
                       "crystal/data/generated", "crystal/data", "crystal" }) do
    love.filesystem.remove(p)
  end

  -- 2. HIGHEST GENERATION FIRST, against the real imported caches
  if not love.filesystem.getInfo or not io.open(FIX .. "/only_crystal/crystal/data/generated/pokemon.lua", "rb") then
    print("skip: no fixture at " .. FIX)
  else
    use(only("crystal"))
    local ok, v = from(A.walk, 25);  check("Crystal only: walks with Crystal's sprite", ok and v == "crystal", v)
    ok, v = from(A.front, 25);      check("Crystal only: Crystal's front", ok and v == "crystal", v)
    ok = A.front(251) ~= nil;        check("Crystal only: Celebi has a front", ok)
    check("Crystal only: no Gen 3 species", A.front(252) == nil)
    use(only("crystal", "emerald"))
    ok, v = from(A.walk, 25);  check("+Emerald: walks with Emerald's sprite", ok and v == "emerald", v)
    ok, v = from(A.front, 25); check("+Emerald: Emerald's front", ok and v == "emerald", v)
    ok, v = from(A.front, 252); check("+Emerald: Treecko from Emerald", ok and v == "emerald", v)
    use(only("crystal", "emerald", "heartgold"))
    local img, fw, fh, facings, wv = A.walk(25)
    check("+HGSS: walks with the HGSS follower sheet", img and wv == "heartgold" and fw == 32 and facings and #facings.down == 3, wv)
    ok, v = from(A.front, 25); check("+HGSS: HGSS's front", ok and v == "heartgold", v)
    use(only("black", "crystal", "emerald", "heartgold"))
    ok, v = from(A.walk, 25);  check("+Black: still walks with HGSS (B/W has no follower)", ok and v == "heartgold", v)
    ok, v = from(A.front, 25); check("+Black: Black's front", ok and v == "black", v)
    ok, v = from(A.front, 649); check("+Black: Genesect from Black", ok and v == "black", v)
    use(only("black"))
    check("Black only: no walking sprite (the screen bobs the front)", A.walk(25) == nil)
    ok, v = from(A.front, 25); check("Black only: Black's front", ok and v == "black", v)
    use({ FIX .. "/nowhere" })
    check("nothing imported: nil, no error", A.walk(25) == nil and A.front(25) == nil)
  end
  A._roots = nil; A.forget()
  print(("%d checks, %d failed"):format(pass + fail, fail))
  love.event.quit(fail == 0 and 0 or 1)
end
