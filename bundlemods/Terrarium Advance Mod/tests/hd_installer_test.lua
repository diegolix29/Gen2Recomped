-- texlua tests/hd_installer_test.lua  (expects /tmp/hdz/*.zip from the Python builder)
local passes, fails = 0, 0
local function eq(a, b, name) if a == b then passes = passes + 1 else fails = fails + 1
  print(("FAIL: %s (got %s, want %s)"):format(name, tostring(a), tostring(b))) end end
local function ok(c, name) eq(c and true or false, true, name) end
local function slurp(p) local f = assert(io.open(p, "rb")); local s = f:read("*a"); f:close(); return s end

-- ---- engine mocks ----
local clock = 0
love = { timer = { getTime = function() clock = clock + 0.011; return clock end },
  data = { decompress = function(_, _, packed)
    local tmp = os.tmpname(); local f = io.open(tmp, "wb"); f:write(packed); f:close()
    local p = io.popen("python3 /tmp/hdz/inflate.py " .. tmp, "r"); local out = p:read("*a"); p:close(); os.remove(tmp); return out end } }
local disk = {}                       -- save-dir files
local scenario                        -- current test knobs
local function newFile(name)
  local f = { pos = 0 }
  function f:open() self.data = disk[name]; return self.data ~= nil end
  function f:getSize() return #self.data end
  function f:seek(p) self.pos = p; return true end
  function f:read(n) return self.data:sub(self.pos + 1, self.pos + n) end
  function f:close() end
  return f
end
local fs = { newFile = newFile,
  getInfo = function(name) return disk[name] and { size = #disk[name], type = "file" } or nil end,
  remove = function(name) disk[name] = nil; return true end }
package.preload["src.core.SaveData"] = function() return { persistenceFs = function() return fs end } end
local F = { cancelled = 0, released = 0 }
package.preload["src.net.Fetch"] = function()
  function F.download(url, temp, opts)
    scenario.lastDownload = { url = url, temp = temp, opts = opts }
    return { ticks = 0, temp = temp }
  end
  function F.poll(job)
    job.ticks = job.ticks + 1
    if job.ticks < 3 then return { status = "pending", progress = job.ticks / 3 } end
    if scenario.fetchError then return { status = "error", err = scenario.fetchError } end
    disk[job.temp] = slurp(scenario.zip); return { status = "ok" }
  end
  function F.cancel(job) F.cancelled = F.cancelled + 1 end
  function F.release(job) F.released = F.released + 1 end
  return F
end
package.preload["src.mods.ModUpdate"] = function()
  return {
    beginFetchReleases = function(repo, _, o) scenario.repo = repo; return { n = 0 } end,
    pumpFetchReleases = function(h) h.n = h.n + 1; if h.n < 2 then return false end
      local z = slurp(scenario.zip)
      return true, { { version = scenario.releaseVersion or "1.0.0", zip = { url = "https://example/x.zip", size = scenario.size or #z } } } end,
  }
end

-- ---- mod / V ----
local cacheStore = {}
local logs = {}
local mod = { cache = {
  read = function(_, k) return cacheStore[k] end,
  write = function(_, k, v) if scenario.cacheFull then return false, "disk full" end cacheStore[k] = v; return true end,
  info = function(_, k) return cacheStore[k] and { size = #cacheStore[k] } or nil end },
  log = setmetatable({}, { __index = function(_, lvl) return function(_, fmt, ...) logs[#logs + 1] = lvl .. ": " .. fmt:format(...) end end }) }
function mod.read(self, rel) local f = io.open(rel, "rb"); if not f then return nil end local s = f:read("*a"); f:close(); return s end
function mod.info(self, rel) return nil end
local V = { mod = mod }; local loaded = {}
function V.require(name)
  if loaded[name] then return loaded[name] end
  loaded[name] = assert(loadfile("lib/" .. name .. ".lua"))(V); return loaded[name]
end

local function fresh(zip, extra)
  cacheStore, disk, logs, clock = {}, {}, {}, 0
  scenario = { zip = "/tmp/hdz/" .. zip }
  for k, v in pairs(extra or {}) do scenario[k] = v end
  loaded = {}; F.cancelled, F.released = 0, 0; scenario.Fetch = F
  return V.require("HDSheetInstaller")
end
local function run(I, limit)
  local frames = 0
  repeat I.update(); frames = frames + 1 until not I.active() or frames > (limit or 2000)
  return frames
end

-- ---- sheetOf ----
local I = fresh("good.zip")
local rel, dex = I._sheetOf("assets/battle/hd-pokemon/front/normal/154-m.png", "assets/battle/hd-pokemon/")
eq(rel, "front/normal/154-m.png", "sheetOf keeps gender stem"); eq(dex, 154, "sheetOf dex")
eq(I._sheetOf("assets/battle/backgrounds/bg.png", "assets/battle/hd-pokemon/"), nil, "non-sheet ignored")
eq(I._sheetOf("assets/battle/hd-pokemon/front/weird/001.png", "assets/battle/hd-pokemon/"), nil, "bad colour dir ignored")
eq(select(2, I._sheetOf("assets/battle/hd-pokemon/back/shiny/487-origin.png", "assets/battle/hd-pokemon/")), 487, "form stem parsed")

-- ---- happy path ----
I = fresh("good.zip")
eq(I.statusText(), "GET SHEETS", "idle with nothing installed")
ok(I.start(), "start ok"); eq(I.statusText(), "CHECKING", "checking")
eq(scenario.repo, "HaseoSora/Kanto-in-Motion-Assets", "uses KIM asset repo")
local sawDownload, sawUnpack
for _ = 1, 2000 do I.update(); local t = I.statusText()
  if t:match("^DOWNLOAD") then sawDownload = true end
  if t:match("^UNPACK") then sawUnpack = true end
  if not I.active() then break end end
ok(sawDownload, "progress shown while downloading"); ok(sawUnpack, "progress shown while unpacking")
eq(I.status().state, "done", "finished: " .. tostring(I.lastError()))
eq(scenario.lastDownload.opts.maxSeconds, 900, "15-minute download limit"); eq(scenario.lastDownload.temp, "terrarium_hd_sheets.tmp.zip", "temp name")
eq(cacheStore["hd_sheets/front/normal/001.png"], ("PNGDATA-front/normal/001.png"):rep(3), "stored entry extracted intact")
eq(cacheStore["hd_sheets/back/shiny/154-m.png"], ("DEFLATEME-"):rep(500), "DEFLATE entry inflated intact")
ok(cacheStore["hd_sheets/front/normal/400.png"] ~= nil, "Gen 4 (dex 400) sheet installed")
eq(cacheStore["hd_sheets/front/normal/494.png"], nil, "dex 494 NOT installed (cap)")
eq(cacheStore["hd_sheets/front/normal/700.png"], nil, "dex 700 NOT installed (cap)")
eq(cacheStore["hd_sheets/front/weird/001.png"], nil, "bad colour dir NOT installed")
local n = 0; for k in pairs(cacheStore) do n = n + 1 end; eq(n, 5, "exactly 5 in-cap sheets written, nothing else")
local c = I.status().counts
eq(c.written, 5, "written"); eq(c.low, 3, "<=386 count"); eq(c.high, 2, "387-493 count"); eq(c.over, 2, "above-cap skipped")
ok(c.other >= 3, "non-sheet entries counted, not installed")
eq(I.coverage().low, 1, "dex 1 has front+back"); eq(I.coverage().high, 1, "dex 400 has front+back (Gen 4 counted)")
eq(I.statusText(), "2/493", "row shows coverage of 493")
ok(logs[#logs]:find("387%-493 1/107"), "log reports the 387-493 band: " .. tostring(logs[#logs]))
eq(disk["terrarium_hd_sheets.tmp.zip"], nil, "temp ZIP removed")
eq(scenario.Fetch.released, 1, "fetch job released")
-- loader sees it without a restart
local HD = V.require("HDPokemonSheets")
ok(HD.available(400, "front", false), "HDPokemonSheets.available(400) after install")
eq(HD.available(494, "front", false), false, "494 still unavailable")

-- ---- re-run skips identical files ----
local before = cacheStore["hd_sheets/front/normal/001.png"]
ok(I.start(), "restart ok"); run(I)
c = I.status().counts
eq(c.written, 0, "second run writes nothing"); eq(c.existing, 5, "second run skips 5 existing")
eq(I.status().state, "done", "second run done")

-- ---- failures ----
I = fresh("good.zip", { releaseVersion = "2.0.0" }); I.start(); run(I)
eq(I.status().state, "error", "missing release version -> error"); ok(I.lastError():find("not found"), "says not found")
eq(I.statusText(), "ERROR RETRY", "error row text")
I = fresh("good.zip", { fetchError = "HTTP 404" }); I.start(); run(I)
eq(I.status().state, "error", "fetch error -> error"); eq(I.lastError(), "HTTP 404", "surfaces Fetch error")
I = fresh("badver.zip"); I.start(); run(I); ok(I.lastError() and I.lastError():find("version mismatch"), "pack version mismatch rejected")
I = fresh("badid.zip"); I.start(); run(I); ok(I.lastError() and I.lastError():find("not the expected"), "wrong pack id rejected")
I = fresh("nometa.zip"); I.start(); run(I); ok(I.lastError() and I.lastError():find("asset%-pack.json"), "missing asset-pack.json rejected")
I = fresh("good.zip", { size = 123456 }); I.start(); run(I); ok(I.lastError() and I.lastError():find("incomplete"), "size mismatch -> incomplete")
I = fresh("good.zip", { cacheFull = true }); I.start(); run(I); ok(I.lastError() and I.lastError():find("disk full"), "cache write failure surfaced")
eq(next(cacheStore), nil, "nothing half-written on failure")
-- not a zip at all
cacheStore, disk = {}, {}; scenario = { zip = "/tmp/hdz/inflate.py" }; loaded = {}; I = V.require("HDSheetInstaller"); I.start(); run(I)
eq(I.status().state, "error", "garbage download -> error, no crash")

-- ---- cancel ----
I = fresh("good.zip"); I.start(); I.update(); I.update()
eq(I.status().state, "downloading", "downloading before cancel"); ok(I.cancel(), "cancel accepted")
eq(I.status().state, "idle", "idle after cancel"); eq(scenario.Fetch.cancelled, 1, "fetch cancelled"); eq(disk["terrarium_hd_sheets.tmp.zip"], nil, "temp removed on cancel")

-- ---- two sources in one run (e.g. KIM + a Gen 4 pack) ----
I = fresh("good.zip")
I.config.sources[2] = { name = "second", repo = "x/y", version = "1.0.0", packId = "kanto_in_motion_assets", prefix = "assets/battle/hd-pokemon/" }
I.start(); run(I, 4000)
eq(I.status().state, "done", "two sources complete"); eq(I.status().counts.written, 5, "second source adds nothing new")
eq(I.status().counts.existing, 5, "second source skipped existing")

-- ---- row ----
local row = I.row(); eq(row.id, "hd_sheets_install", "row id"); eq(type(row.value()), "string", "row value is live text")
ok(row.step() == true, "row step returns true")
print(("hd_installer_test: %d passed, %d failed"):format(passes, fails)); os.exit(fails == 0 and 0 or 1)
