-- ONE COPY OF EACH MOD, CHOSEN ON PURPOSE.
--
-- A mod can be on disk more than once, and players get there without trying:
--
--   * love.filesystem reads `mods/` out of TWO homes at once -- the save
--     directory first, then the game folder (the source of a `love <dir>` run,
--     the folder beside the executable of a portable install, or a chosen
--     game-data folder).  A copy installed by the launcher (save directory)
--     and a copy unzipped beside the game are both visible;
--   * a zip unzipped into a folder named after the zip rather than the mod
--     (`mods/Terrarium.Advance.Mod.1.8.7/`) sits beside the folder an earlier
--     install made (`mods/DRAMATIC_SHAPE-2/`) -- same id, two folders;
--   * the SAME folder name in both homes is worse: PhysFS merges them file by
--     file, so the manifest and main.lua come from the save directory and any
--     file only the other copy has comes from there -- one mod assembled from
--     two versions;
--   * a release zip dropped into `mods/` is not a mod the loader can see at
--     all, so the player unzips it as well and now has both.
--
-- The loader used to keep whichever copy getDirectoryItems happened to list
-- first and file the rest as "duplicate mod id" errors.  This module decides
-- instead, with one rule the launcher and the loader share:
--
--   1. the HIGHER manifest version wins (Semver; an unparsable version loses
--      to a parsable one);
--   2. at the same version, the SAVE DIRECTORY copy wins over the game
--      folder's -- it is where the launcher installs and updates, and it is
--      what love.filesystem itself answers first;
--   3. then a folder named exactly after the id, then the path, so the answer
--      never depends on directory order.
--
-- A zip is never loaded (the loader reads folders); a zip in `mods/` is
-- reported as ignored, with whether the installed copy is newer, the same or
-- older -- the last one is the one a player needs to hear about.
--
-- MODS THAT ARE THE SAME MOD UNDER ANOTHER ID share a SLOT (ModCopies.slotOf):
-- a launcher copy (`install_source_id`), an id a manifest says it used to have
-- (`previous_ids`), and the built-in ALIASES below.  Only one ENABLED member of
-- a slot loads (supersede); the rest are reported, not failed.

local Semver = require("src.mods.Semver")

local ModCopies = {}

-- Ids the engine knows are the same mod under an older name.
--
-- The bundled voxel mod was published as `DRAMATIC_SHAPE` (its own checkout's
-- first commit, v1.6.0) and now declares `Gen2Recomped-DramaticShapes`.  Forks
-- of it -- Terrarium / "Advanced Terrarium Voxel Mod" -- still declare
-- `DRAMATIC_SHAPE` and say in their own main.lua that they ship "under
-- ADVANCED_SHAPE's own manifest id" as "the only voxel pipeline installed".
-- With the rename both loaded, both registered the `voxel` render pipeline,
-- and whichever came second failed half-way through its entry chunk with
-- "render_pipelines already registered: voxel".
ModCopies.ALIASES = {
  DRAMATIC_SHAPE = "Gen2Recomped-DramaticShapes",
}

local HOME_RANK = { save = 1, game = 2, other = 3 }
ModCopies.HOME_RANK = HOME_RANK

local function versionCompare(a, b)
  local c = Semver.compare(a, b)
  if c then return c end
  local pa, pb = Semver.parse(a) ~= nil, Semver.parse(b) ~= nil
  if pa ~= pb then return pa and 1 or -1 end
  return 0
end

-- better(a, b) -> true when copy a should be the one loaded.  Copies are
-- { id, version, home, folder, path }.
function ModCopies.better(a, b)
  local c = versionCompare(a.version, b.version)
  if c ~= 0 then return c > 0 end
  local ra, rb = HOME_RANK[a.home] or 9, HOME_RANK[b.home] or 9
  if ra ~= rb then return ra < rb end
  local na, nb = a.folder == a.id, b.folder == b.id
  if na ~= nb then return na end
  return tostring(a.path) < tostring(b.path)
end

-- why `loser` lost to `winner`, in words for a log line and a launcher row
function ModCopies.reason(loser, winner)
  local c = versionCompare(winner.version, loser.version)
  if c > 0 then
    return ("older (%s) than %s at %s"):format(tostring(loser.version),
      tostring(winner.version), tostring(winner.where or winner.path))
  end
  return ("same version as %s, which takes precedence (%s)"):format(
    tostring(winner.where or winner.path), tostring(winner.home))
end

-- pick(copies) -> winners (id -> copy), ignored ({ copy, winner, reason })
function ModCopies.pick(copies)
  local byId = {}
  for _, c in ipairs(copies) do
    local list = byId[c.id]
    if not list then list = {}; byId[c.id] = list end
    list[#list + 1] = c
  end
  local winners, ignored = {}, {}
  local ids = {}
  for id in pairs(byId) do ids[#ids + 1] = id end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local list = byId[id]
    table.sort(list, function(a, b) return ModCopies.better(a, b) end)
    winners[id] = list[1]
    for i = 2, #list do
      ignored[#ignored + 1] = { copy = list[i], winner = list[1],
                                reason = ModCopies.reason(list[i], list[1]) }
    end
  end
  return winners, ignored
end

-- ------- slots: the same mod under more than one id

-- slots(manifests) -> id -> slot key.  manifests: id -> manifest (or a list).
-- Union of: the built-in aliases, a launcher copy's install_source_id, and
-- every previous_ids a manifest declares.
function ModCopies.slots(manifests)
  local parent = {}
  local function find(x)
    while parent[x] and parent[x] ~= x do x = parent[x] end
    return x
  end
  local function union(a, b)
    parent[a] = parent[a] or a
    parent[b] = parent[b] or b
    local ra, rb = find(a), find(b)
    if ra ~= rb then
      -- keep the lexically smaller root so the key is stable
      if rb < ra then ra, rb = rb, ra end
      parent[rb] = ra
    end
  end
  local list = {}
  for key, m in pairs(manifests or {}) do
    local man = type(m) == "table" and (m.manifest or m) or nil
    if type(man) == "table" and type(man.id) == "string" then list[#list + 1] = man end
  end
  for _, m in ipairs(list) do
    parent[m.id] = parent[m.id] or m.id
    local alias = ModCopies.ALIASES[m.id]
    if alias then union(m.id, alias) end
    local raw = m.raw or {}
    local src = raw.install_source_id
    if type(src) == "string" and src ~= "" then
      union(m.id, src)
      if ModCopies.ALIASES[src] then union(src, ModCopies.ALIASES[src]) end
    end
    for _, old in ipairs(m.previousIds or {}) do union(m.id, old) end
  end
  local out = {}
  for _, m in ipairs(list) do out[m.id] = find(m.id) end
  return out
end

-- supersede(mods, isEnabled) -> { { id, winner, reason } } for every enabled
-- mod that shares a slot with a better enabled one.  mods: id -> { manifest,
-- path, home }.
function ModCopies.supersede(mods, isEnabled)
  local slots = ModCopies.slots(mods)
  local groups = {}
  for id, mod in pairs(mods) do
    if isEnabled(id, mod) then
      local key = slots[id] or id
      groups[key] = groups[key] or {}
      local g = groups[key]
      g[#g + 1] = { id = id, version = mod.manifest.version, home = mod.home or "other",
                    folder = (mod.path or ""):match("([^/]+)$"), path = mod.path,
                    where = mod.where }
    end
  end
  local out = {}
  for _, g in pairs(groups) do
    if #g > 1 then
      table.sort(g, function(a, b) return ModCopies.better(a, b) end)
      for i = 2, #g do
        out[#out + 1] = { id = g[i].id, winner = g[1].id,
          reason = ("%s %s is the same mod and is %s"):format(g[1].id,
            tostring(g[1].version),
            versionCompare(g[1].version, g[i].version) > 0 and "newer"
              or "preferred at this version") }
      end
    end
  end
  table.sort(out, function(a, b) return a.id < b.id end)
  return out
end

-- ------- where a copy lives

local ffiSearchPath = nil
-- every directory on the PhysFS read path, in search order (nil when it
-- cannot be asked: no ffi, or a build that does not export the symbol)
function ModCopies.searchPath()
  if ffiSearchPath == false then return nil end
  local ok, list = pcall(function()
    local ffi = require("ffi")
    pcall(ffi.cdef, "char **PHYSFS_getSearchPath(void);")
    pcall(ffi.cdef, "void PHYSFS_freeList(void *listVar);")
    pcall(ffi.cdef, "const char *PHYSFS_getMountPoint(const char *dir);")
    local libs = { function() return ffi.C end, function() return ffi.load("love") end,
                   function() return ffi.load("liblove.so") end }
    for _, get in ipairs(libs) do
      local okL, lib = pcall(get)
      if okL and lib then
        local okF, fn = pcall(function() return lib.PHYSFS_getSearchPath end)
        if okF and fn then
          local raw = fn()
          if raw ~= nil then
            local out, i = {}, 0
            while raw[i] ~= nil do
              local dir = ffi.string(raw[i])
              -- only what is mounted at the root can hold a `mods/` of its
              -- own; a private mount (modcopies/1, a version cache's
              -- data/generated) is somewhere else in the tree
              local point = "/"
              pcall(function()
                local mp = lib.PHYSFS_getMountPoint(dir)
                if mp ~= nil then point = ffi.string(mp) end
              end)
              if point == "/" or point == "" then
                out[#out + 1] = (dir:gsub("\\", "/"))
              end
              i = i + 1
            end
            pcall(function() lib.PHYSFS_freeList(raw) end)
            return out
          end
        end
      end
    end
    return nil
  end)
  if ok and list then return list end
  ffiSearchPath = false
  return nil
end

local function norm(p) return (tostring(p or ""):gsub("\\", "/"):gsub("/+$", "")) end

-- "save" | "game" | "other" for the real directory a file was read from
function ModCopies.homeOfRealDir(fs, realDir)
  if not realDir then return "other" end
  local r = norm(realDir)
  local save = fs.getSaveDirectory and norm(fs.getSaveDirectory())
  if save and save ~= "" and r == save then return "save" end
  return "game"
end

local function readReal(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  return data
end
ModCopies.readReal = readReal

-- ------- the private mount a chosen copy is read through
--
-- When one folder name exists in two homes with different contents, the
-- merged view is neither copy.  The chosen one is mounted on its own at
-- `modcopies/<n>` and the mod is loaded from there, so every file it reads is
-- from the copy that was chosen.  Kept for the life of the process: a mod
-- reads its files long after it loads.
local mounted = {}   -- real dir -> mount point
local mountCount = 0

local function physMount(dir, point)
  local ok, res = pcall(function()
    local ffi = require("ffi")
    pcall(ffi.cdef, "int PHYSFS_mount(const char *newDir, const char *mountPoint, int appendToPath);")
    for _, get in ipairs({ function() return ffi.C end, function() return ffi.load("love") end,
                           function() return ffi.load("liblove.so") end }) do
      local okL, lib = pcall(get)
      if okL and lib then
        local okF, fn = pcall(function() return lib.PHYSFS_mount end)
        if okF and fn and fn(dir, point, 1) ~= 0 then return true end
      end
    end
    return false
  end)
  return ok and res
end

function ModCopies.mountPrivate(realDir)
  if mounted[realDir] then return mounted[realDir] end
  mountCount = mountCount + 1
  local point = ("modcopies/%d"):format(mountCount)
  if physMount(realDir, point) then
    mounted[realDir] = point
    return point
  end
  return nil
end

-- The manifest inside a zip sitting in mods/, without installing it: the zip
-- is mounted at a private point for the length of the read and dropped again
-- (CacheFs.withMounted).  Flat zips (manifest.json at the root, Terrarium's
-- layout) and one-folder zips both answer.  nil when it cannot be looked at.
function ModCopies.peekZip(fs, path, decode)
  if not (fs and fs.getRealDirectory and decode) then return nil end
  local okR, realDir = pcall(fs.getRealDirectory, path)
  if not (okR and realDir) then return nil end
  local okC, CacheFs = pcall(require, "src.import.CacheFs")
  if not (okC and CacheFs.withMounted) then return nil end
  local point = "modzip_peek"
  local okW, man = pcall(CacheFs.withMounted, norm(realDir) .. "/" .. path, point, function()
    local raw = fs.read(point .. "/manifest.json")
    if not raw then
      local dirs = {}
      for _, n in ipairs(fs.getDirectoryItems(point) or {}) do
        local i = fs.getInfo(point .. "/" .. n)
        if i and i.type == "directory" then dirs[#dirs + 1] = n end
      end
      if #dirs == 1 then raw = fs.read(point .. "/" .. dirs[1] .. "/manifest.json") end
    end
    if not raw then return nil end
    return (decode(raw, path))
  end)
  return okW and man or nil
end

-- The custom game-data folder confinement as a per-home test: a copy counts
-- when it lives in the chosen folder or in the game's own source (the bundled
-- mods, which are in every home -- LauncherMods.underRoot says why).
function ModCopies.confinedTo(confine)
  -- compared without case: Windows paths come back with either drive case
  local source = love and love.filesystem and love.filesystem.getSource
    and norm(love.filesystem.getSource()):lower() or nil
  local root = norm(confine):lower()
  return function(realDir)
    if not realDir then return false end
    local d = norm(realDir):lower()
    return d == root or (source ~= nil and d == source)
  end
end

-- ------- the scan

-- scan(fs, opts) -> {
--   winners = id -> copy, ignored = { {copy, winner, reason} },
--   zips = { {name, id, version, path, status, note} }, notes = { string },
-- }
-- copy = { id, version, manifest, path, folder, home, where, realDir }.
-- opts.decode(raw, path) -> manifest | nil, err (Manifest.validate wrapped)
-- opts.allow(path) -> false to skip a folder
-- opts.allowReal(realDir) -> false for a home that does not count (the
--   custom game-data folder confinement: only it and the game's own source)
-- opts.root (default "mods")
function ModCopies.scan(fs, opts)
  opts = opts or {}
  local root = opts.root or "mods"
  local out = { winners = {}, ignored = {}, zips = {}, notes = {}, invalid = {} }
  if not (fs and fs.getInfo and fs.getDirectoryItems and fs.getInfo(root)) then
    return out
  end
  local decode = assert(opts.decode, "ModCopies.scan needs opts.decode")
  local copies = {}
  local searchPath = (fs.getRealDirectory and ModCopies.searchPath()) or nil
  local items = fs.getDirectoryItems(root) or {}
  table.sort(items)
  for _, name in ipairs(items) do
    local path = root .. "/" .. name
    local info = fs.getInfo(path)
    if info and opts.allow and not opts.allow(path) then info = nil end
    if info and (info.type == "directory" or info.type == "symlink") then
      local raw = fs.read(path .. "/manifest.json")
      local manifest, err
      if raw then manifest, err = decode(raw, path) else err = "no manifest.json" end
      if manifest then
        local realDir = nil
        if fs.getRealDirectory then
          local okR, r = pcall(fs.getRealDirectory, path .. "/manifest.json")
          if okR then realDir = r end
        end
        local copy = {
          id = manifest.id, version = manifest.version, manifest = manifest,
          path = path, folder = name, realDir = realDir,
          home = fs.getRealDirectory and ModCopies.homeOfRealDir(fs, realDir) or "other",
        }
        copy.where = realDir and (norm(realDir) .. "/" .. path) or path
        -- THE SAME FOLDER NAME IN ANOTHER HOME, merged into this one
        local allowReal = opts.allowReal
        local visibleOk = not allowReal or allowReal(realDir)
        local twins = {}
        for _, dir in ipairs(searchPath or {}) do
          if norm(dir) ~= norm(realDir) and (not allowReal or allowReal(dir)) then
            local twinManifest = readReal(dir .. "/" .. path .. "/manifest.json")
            if twinManifest then
              local tm = decode(twinManifest, path)
              if tm and tm.id == manifest.id then
                local mineMain = readReal(norm(realDir) .. "/" .. path .. "/" .. (manifest.entry or "main.lua"))
                local theirMain = readReal(dir .. "/" .. path .. "/" .. (tm.entry or "main.lua"))
                -- an identical twin changes nothing about what is read
                -- unless the visible copy is not allowed to count
                if not visibleOk or twinManifest ~= raw or mineMain ~= theirMain then
                  twins[#twins + 1] = {
                    id = tm.id, version = tm.version, manifest = tm, path = path,
                    folder = name, realDir = dir,
                    home = ModCopies.homeOfRealDir(fs, dir),
                    where = norm(dir) .. "/" .. path, merged = true,
                  }
                end
              end
            end
          end
        end
        if #twins == 0 then
          if visibleOk then copies[#copies + 1] = copy end
        else
          -- choose among the merged copies, then read the chosen one alone
          local group = {}
          if visibleOk then group[1] = copy end
          for _, t in ipairs(twins) do group[#group + 1] = t end
          table.sort(group, function(a, b) return ModCopies.better(a, b) end)
          local best = group[1]
          local point = best.realDir and ModCopies.mountPrivate(norm(best.realDir) .. "/" .. path)
          if point then
            best.logicalPath = path
            best.path = point
            -- manifest.path is what imports and storage resolve against; it
            -- stays the logical folder so a base file the player imported
            -- into mods/<folder> is still found
            copies[#copies + 1] = best
            for i = 2, #group do
              out.ignored[#out.ignored + 1] = { copy = group[i], winner = best,
                reason = ModCopies.reason(group[i], best)
                  .. " (same folder name in two homes; the chosen copy is read on its own)" }
            end
          elseif visibleOk then
            -- no way to read one copy alone on this build: the merged view
            -- stands, and the player is told which files they are getting
            copies[#copies + 1] = copy
            out.notes[#out.notes + 1] = ("mods/%s exists in two places with "
              .. "different contents and this build cannot read them apart: "
              .. "the copy at %s (%s) is the one being loaded, the one at %s "
              .. "(%s) fills in only the files the first lacks -- remove one")
              :format(name, copy.where, tostring(copy.version),
                twins[1].where, tostring(twins[1].version))
          end
        end
      else
        out.invalid[#out.invalid + 1] = { path = path, err = err }
      end
    elseif info and info.type == "file" and name:lower():match("%.zip$") then
      out.zips[#out.zips + 1] = { name = name, path = path }
    end
  end
  out.winners, out.copiesIgnored = ModCopies.pick(copies)
  for _, row in ipairs(out.copiesIgnored) do out.ignored[#out.ignored + 1] = row end
  out.copiesIgnored = nil
  -- zips: say what each one is relative to what is installed
  for _, z in ipairs(out.zips) do
    local man
    if opts.peekZip then man = opts.peekZip(z.path)
    elseif opts.peekZip ~= false then man = ModCopies.peekZip(fs, z.path, decode) end
    if man then
      z.id, z.version = man.id, man.version
      local have = out.winners[man.id]
      if not have then
        z.status = "not_installed"
        z.note = ("%s (%s %s) is a zip in mods/ -- zips are not loaded; install "
          .. "it from the launcher (MODS > IMPORT MOD .ZIP) or unzip it into its "
          .. "own folder"):format(z.name, tostring(man.id), tostring(man.version))
      else
        local c = versionCompare(man.version, have.version)
        if c > 0 then
          z.status = "newer"
          z.note = ("%s holds %s %s, NEWER than the installed %s at %s -- the "
            .. "zip is not loaded; import it to update"):format(z.name, man.id,
            tostring(man.version), tostring(have.version), have.where or have.path)
        else
          z.status = c == 0 and "same" or "older"
          z.note = ("%s (%s %s) ignored: %s %s is installed at %s"):format(z.name,
            man.id, tostring(man.version), man.id, tostring(have.version),
            have.where or have.path)
        end
      end
    else
      z.status = "unreadable"
      z.note = ("%s is a zip in mods/ -- zips are not loaded, and this one has "
        .. "no readable manifest.json"):format(z.name)
    end
  end
  return out
end

-- ------- one module table per mod file, whatever name it is required by
--
-- `require("mods.<X>.lib.Y")` goes through love.filesystem, which knows
-- nothing about which copy of a mod was chosen: it resolves `mods/<X>/...` in
-- the merged view, so it reads a FOLDER called X (not the mod whose id is X),
-- reads the save directory's stale copy of a file before the chosen one, and
-- caches the result under whatever spelling was used -- the same file loaded
-- as `mods.DRAMATIC_SHAPE.lib.Y` and again under the folder's own name is two
-- module tables with two sets of state.
--
-- This searcher answers first for `mods.<id or folder>.<rest>` when <id or
-- folder> is a mod the loader chose: it reads the file from THAT copy, and
-- keeps it under one canonical name, `mods.<id>.<rest>`, which every other
-- spelling then shares.  Anything else falls through to the usual searchers.
local active = { byId = {}, byFolder = {} }

function ModCopies.setActive(mods)
  active = { byId = {}, byFolder = {} }
  for id, mod in pairs(mods or {}) do
    if mod.path and not mod.superseded and mod.enabled ~= false then
      active.byId[id] = mod.path
      local folder = (mod.manifest and mod.manifest.path or mod.path):match("([^/]+)$")
      if folder then active.byFolder[folder] = active.byFolder[folder] or id end
    end
  end
end

local searcherInstalled = false
function ModCopies.installSearcher()
  if searcherInstalled then return end
  local loaders = package.loaders or package.searchers
  if type(loaders) ~= "table" then return end
  searcherInstalled = true
  local function searcher(name)
    if type(name) ~= "string" then return nil end
    local key, rest = name:match("^mods%.([^%.]+)%.(.+)$")
    if not key then return nil end
    local id = active.byId[key] and key or active.byFolder[key]
    local root = id and active.byId[id]
    if not root then return nil end
    local canonical = "mods." .. id .. "." .. rest
    local cached = package.loaded[canonical]
    if cached ~= nil then
      return function() return cached end
    end
    local fs = love and love.filesystem
    if not (fs and fs.getInfo and fs.load) then return nil end
    local base = root .. "/" .. rest:gsub("%.", "/")
    for _, file in ipairs({ base .. ".lua", base .. "/init.lua" }) do
      if fs.getInfo(file) then
        local chunk, err = fs.load(file)
        if not chunk then error(err, 0) end
        return function(...)
          local value = chunk(...)
          if value == nil then value = true end
          package.loaded[canonical] = value
          return value
        end
      end
    end
    return ("\n\tno file '%s.lua' in the loaded copy of %s"):format(base, id)
  end
  table.insert(loaders, 2, searcher)
end

return ModCopies
