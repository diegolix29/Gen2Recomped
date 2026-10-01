-- Run from the mod root:  texlua tests/hd_sheets_test.lua   (or luajit/lua5.1)
-- Mocks LOVE + the mod API; exercises the real ported data/hd_sheet_meta.lua.
local fails, passes = 0, 0
local function ok(cond, name)
  if cond then passes = passes + 1 else fails = fails + 1; print("FAIL: " .. name) end
end
local function eq(a, b, name)
  if a == b then passes = passes + 1 else fails = fails + 1
    print(("FAIL: %s (got %s, want %s)"):format(name, tostring(a), tostring(b))) end
end

-- ---- mocks ----
local now = 0
local files = {}      -- mod-package files: rel -> "IMG:WxH" (data/*.lua read from disk)
local cacheFiles = {} -- mod.cache files
local created = { images = 0, released = 0 }
local pastes = {}
local function imgdata(w, h)
  local o = { w = w, h = h }
  function o:getDimensions() return self.w, self.h end
  function o:paste(src, dx, dy, sx, sy, sw, sh) pastes[#pastes + 1] = { dx, dy, sx, sy, sw, sh } end
  function o:release() end
  return o
end
love = {
  timer = { getTime = function() return now end },
  filesystem = { newFileData = function(bytes) return { bytes = bytes } end },
  image = { newImageData = function(a, b)
    if type(a) == "table" then
      local w, h = a.bytes:match("^IMG:(%d+)x(%d+)$")
      if not w then error("bad image") end
      return imgdata(tonumber(w), tonumber(h))
    end
    return imgdata(a, b)
  end },
  graphics = { newImage = function(d)
    created.images = created.images + 1
    local o = { w = d.w, h = d.h }
    function o:getDimensions() return self.w, self.h end
    function o:setFilter() end
    function o:release() created.released = created.released + 1 end
    return o
  end },
}
local function readDisk(rel)
  local f = io.open(rel, "rb"); if not f then return nil end
  local s = f:read("*a"); f:close(); return s
end
local mod = {}
function mod.read(self, rel)
  if files[rel] then return files[rel] end
  if rel:match("^data/") then return readDisk(rel) end
  return nil
end
function mod.info(self, rel)
  if files[rel] then return { type = "file", size = #files[rel] } end
  return nil
end
mod.cache = {
  info = function(self, k) local v = cacheFiles[k]; return v and { size = #v } or nil end,
  read = function(self, k) return cacheFiles[k] end,
}
local function fresh()
  files, cacheFiles = {}, {}
  now = 0; created.images = 0; created.released = 0; pastes = {}
  local chunk = assert(loadfile("lib/HDPokemonSheets.lua"))
  return chunk({ mod = mod })
end
local function put(rel, w, h) cacheFiles["hd_sheets/" .. rel] = ("IMG:%dx%d"):format(w, h) end
local function putPkg(rel, w, h) files["assets/hd-pokemon/" .. rel] = ("IMG:%dx%d"):format(w, h) end

-- ---- names / cap ----
local M = fresh()
M.status()  -- forces meta load
ok(M.identify({ pokemon = { X = { dex = 1 } } }, { mon = { species = "X" } }) ~= nil, "identify smoke")
eq(M.identify({}, { mon = { species = "ARCEUS" } }).dex, 493, "ARCEUS -> 493")
eq(M.identify({}, { mon = { species = "Porygon-Z" } }).dex, 474, "Porygon-Z -> 474")
eq(M.identify({}, { mon = { species = "MIME_JR" } }).dex, 439, "MIME_JR -> 439")
eq(M._g4NameCount, 107, "107 Gen 4 names (387..493)")
eq(M.identify({}, { mon = { species = "X", dex = 494 } }), nil, "494 rejected")
eq(M.identify({}, { mon = { species = "X", dex = 0 } }), nil, "0 rejected")
eq(M.supported(493), true, "493 supported"); eq(M.supported(494), false, "494 unsupported")
eq(M.status().metaRows.kim, 1796, "all 1796 KIM rows loaded")

-- ---- identity ----
local data = { pokemon = { PIKACHU = { dex = 25 }, GIRATINA = { dex = 487 }, UNOWN = { dex = 201 },
                           GARCHOMP = { nationalDex = 445, dex = 999 } } }
eq(M.identify(data, { mon = { species = "GARCHOMP" } }).dex, 445, "nationalDex wins over dex")
local id = M.identify(data, { mon = { species = "PIKACHU", shiny = true, gender = "FEMALE" } })
ok(id.shiny and id.gender == "f", "shiny + gender parsed")
eq(M.identify(data, { mon = { species = "PIKACHU", gender = 0 } }).gender, "m", "numeric gender 0 = m")
eq(M.identify(data, { mon = { species = "GIRATINA", form = "Origin" } }).form, "origin", "origin form key")
eq(M.identify(data, { mon = { species = "GIRATINA", form = "altered" } }).form, nil, "altered = default")
eq(M.identify(data, { mon = { species = "GIRATINA", form = 0 } }).form, nil, "form 0 = default")
eq(M.identify(data, { mon = { species = "UNOWN", form = "b" } }).form, nil, "unown ignores form")

-- ---- existence-based resolution ----
M = fresh()
eq(M.available(25, "front", false), false, "nothing installed -> unavailable")
put("front/normal/025.png", 170, 186)
M.rescan()
eq(M.available(25, "front", false), true, "cache file found")
eq(M.available(25, "back", false), false, "back still missing")
eq(M.available(25, "front", true), false, "shiny missing")
putPkg("back/normal/025.png", 221, 246)
M.rescan()
eq(M.available(25, "back", false), true, "package file found")
eq(M.available(494, "front", false), false, "494 never available")

-- gender preference order
M = fresh()
put("front/normal/154-m.png", 131, 186); put("front/normal/154-f.png", 122, 186)
local _, info = M.frame({ dex = 154, facing = "front", gender = "f" })
eq(info.stem, "154-f", "female picks -f")
_, info = M.frame({ dex = 154, facing = "front" })
eq(info.stem, "154-m", "no gender falls back to -m")

-- form: missing file stays native
M = fresh()
put("front/normal/487.png", 100, 100)
eq(M.frame({ dex = 487, facing = "front", form = "origin" }), nil, "Giratina-Origin without file -> nil (native)")
ok(M.frame({ dex = 487, facing = "front" }) ~= nil, "Giratina-Altered uses base file")
put("front/normal/487-origin.png", 100, 100); M.rescan()
_, info = M.frame({ dex = 487, facing = "front", form = "origin" })
eq(info and info.stem, "487-origin", "origin file used when present")

-- ---- geometry / animation (real KIM row: 001 front = 170x186, 6 cols, 26 frames) ----
M = fresh()
put("front/normal/001.png", 170 * 6, 186 * 5)   -- 6 cols x 5 rows
local img, inf = M.frame({ dex = 1, facing = "front", key = "a" })
eq(inf.frame, 1, "starts on frame 1"); eq(img.w, 170, "frame width"); eq(img.h, 186, "frame height")
eq(inf.frames, 26, "26 frames"); ok(math.abs(inf.scale - 0.234946) < 1e-6, "KIM displayScale carried")
now = 0.05;  _, inf = M.frame({ dex = 1, facing = "front", key = "a" }); eq(inf.frame, 2, "frame 2 after 50ms")
now = 1.30;  _, inf = M.frame({ dex = 1, facing = "front", key = "a" }); eq(inf.frame, 1, "loops at 26*50ms")
now = 0.05 + 0.3; _, inf = M.frame({ dex = 1, facing = "front", key = "a" })
ok(inf.frame >= 1 and inf.frame <= 26, "frame in range")
-- frame 8 (index 8) -> col 1,row 1 of 6 cols
pastes = {}; M.rescan(); now = 0; put("front/normal/001.png", 170 * 6, 186 * 5)
now = 0; M.frame({ dex = 1, facing = "front", key = "b" })
now = 0.35; M.frame({ dex = 1, facing = "front", key = "b" })
local p = pastes[#pastes]
eq(p[3], 170, "frame 8 source x"); eq(p[4], 186, "frame 8 source y")

-- ---- static fallback + adjusted layout ----
M = fresh()
put("front/normal/400.png", 200, 300)          -- Bibarel: no meta row
img, inf = M.frame({ dex = 400, facing = "front" })
eq(inf.frames, 1, "no meta -> static"); eq(img.w, 200, "static width = image"); eq(inf.scale, 0.33, "default front scale")
M = fresh()
put("front/normal/001.png", 600, 200)          -- wrong size for the 6x5 grid
img, inf = M.frame({ dex = 1, facing = "front" })
ok(img ~= nil and M._stats.adjusted == 1, "mismatched sheet is re-derived, not read out of bounds")
eq(inf.w, 100, "adjusted cell width"); eq(inf.h, 40, "adjusted cell height = 200/5")
put("front/normal/002.png", 10, 10); M.rescan()
put("front/normal/002.png", 0, 0)
cacheFiles["hd_sheets/front/normal/003.png"] = "garbage"
eq(M.frame({ dex = 3, facing = "front" }), nil, "undecodable bytes -> nil"); eq(M._stats.decodeFailed, 1, "decode failure counted")

-- ---- billboard descriptor ----
M = fresh()
put("front/normal/001.png", 170 * 6, 186 * 5); put("back/normal/001.png", 221 * 6, 246 * 5)
data.pokemon.BULBASAUR = { dex = 1 }
local battle = { data = data, enemy = { mon = { species = "BULBASAUR" } }, player = { mon = { species = "BULBASAUR" } } }
local native = { canvas = "native", ax = 80, ay = 60, cw = 160, ch = 144, trainer = false }
local d = M.textureFor(battle, "enemy", native)
ok(d and d.hd, "enemy descriptor swapped")
local KIM = (loadfile("data/hd_sheet_meta.lua"))()
local rec = KIM.front.normal["001"]
ok(math.abs(d.cw - rec[1] * rec[5]) < 1e-6, "cw = frameW * displayScale")
ok(math.abs(d.ch - rec[2] * rec[5]) < 1e-6, "ch = frameH * displayScale")
ok(math.abs(d.ay - d.ch) < 1e-9 and math.abs(d.ax - d.cw / 2) < 1e-9, "feet-centred anchor")
eq(M.textureFor(battle, "enemy", { trainer = true }), nil, "trainer descriptors untouched")
local out = { enemy = native, player = { canvas = "n2", trainer = false, cw = 160, ch = 144, ax = 80, ay = 60 } }
eq(M.applyToTextures(battle, out), true, "applyToTextures changed something")
ok(out.enemy.hd and out.player.hd, "both sides swapped")
local before = out.enemy
M.applyToTextures(battle, out); eq(out.enemy, before, "already-swapped descriptor not re-swapped")
battle.game = { save = { terrariumBattle = { hdSheetsEnabled = false } } }
eq(M.textureFor(battle, "enemy", native), nil, "toggle OFF -> native")
battle.game = nil
eq(M.textureFor({ data = data, enemy = { mon = { species = "GIRATINA", form = "origin" } } }, "enemy", native), nil,
  "no form file -> native")
eq(M.textureFor({ data = data, enemy = { mon = { species = "NOPE" } } }, "enemy", native), nil, "unknown species -> native")

-- ---- CSM provider: padding keeps KIM sizing ----
M = fresh()
put("front/normal/001.png", 170 * 6, 186 * 5)           -- scale .2349 -> want ceil(90/.2349)
local ctx = { game = { data = data }, battle = {} }
local r = M.spriteApi.resolve(ctx, "enemy", { mon = { species = "BULBASAUR" } }, "native")
eq(r.h, math.ceil(90 / 0.234946), "small-scale species padded on top to keep KIM ratio"); eq(r.w, 170, "width untouched")
local last = pastes[#pastes]; eq(last[2], r.h - 186, "cell pasted at bottom (dy = pad)")
-- a species whose KIM scale is above slot/cellH must not be padded or cropped
local bigStem, bigRec
for stem, rc in pairs(KIM.front.normal) do
  if rc[5] > 90 / rc[2] + 0.01 and stem:match("^%d%d%d$") then bigStem, bigRec = stem, rc; break end
end
ok(bigStem ~= nil, "found a large-scale KIM species to test")
M = fresh(); put("front/normal/" .. bigStem .. ".png", bigRec[1] * bigRec[3], bigRec[2] * math.ceil(bigRec[4] / bigRec[3]))
data.pokemon.BIG = { dex = tonumber(bigStem) }
r = M.spriteApi.resolve(ctx, "enemy", { mon = { species = "BIG" } }, "native")
eq(r.h, bigRec[2], "large species drawn at cell height (capped at slot, never cropped)")
eq(M.spriteApi.resolve(ctx, "enemy", { mon = { species = "NOPE" } }, "native"), nil, "unknown species -> nil")
eq(M.spriteApi.version, 1, "battleSprites v1")
eq(M.spriteApi.selected(ctx), true, "selected by default")

-- ---- ownsSide: only dex > 386 with BOTH sheets ----
M = fresh()
data.pokemon.BIBAREL = { dex = 400 }
local b = { mon = { species = "BIBAREL" } }
eq(M.ownsSide(ctx, b), false, "no sheets -> CSM keeps native")
put("front/normal/400.png", 100, 100); M.rescan()
eq(M.ownsSide(ctx, b), false, "front only -> not owned")
put("back/normal/400.png", 100, 100); M.rescan()
eq(M.ownsSide(ctx, b), true, "front+back -> owned")
put("front/normal/025.png", 100, 100); put("back/normal/025.png", 100, 100); M.rescan()
eq(M.ownsSide(ctx, { mon = { species = "PIKACHU" } }), false, "dex <= 386 never lifts CBE's 2D block")

-- ---- LRU eviction ----
M = fresh(); M.config.maxSheets = 2
for _, n in ipairs({ 1, 2, 3, 4 }) do put(("front/normal/%03d.png"):format(n), 100, 100) end
for i, n in ipairs({ 1, 2, 3, 4 }) do now = i; M.frame({ dex = n, facing = "front" }) end
eq(M.status().residentSheets, 2, "resident sheets capped")
ok(created.released > 0 or M._stats.evicted >= 2, "evicted sheets released")
now = 4.1; ok(M.frame({ dex = 1, facing = "front" }) ~= nil, "evicted sheet reloads on demand")

print(("hd_sheets_test: %d passed, %d failed"):format(passes, fails))
os.exit(fails == 0 and 0 or 1)
