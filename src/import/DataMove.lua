-- MOVING WHAT IS ALREADY INSTALLED INTO THE CHOSEN GAME-DATA FOLDER.
--
-- Changing the folder points every FUTURE write at it.  What was already on
-- disk stayed where it was, and love.filesystem shows every home at once, so
-- the launcher went on listing those mods and looked like the setting had done
-- nothing -- while new installs landed on the other drive.  Two homes, one
-- list.  Reported as "all of my mods are showing in the launcher but theyre
-- not in my new location".
--
-- Worse than cosmetic: a mod installed in the old home and re-installed after
-- the switch is two installs of one mod, and if it declares a base file that
-- is two copies of a 1.4 GB disc.
--
-- So the setting gets a way to converge on ONE home.  Deliberately an explicit
-- action rather than something the switch does for you: it can be gigabytes,
-- it is the kind of work that should happen when somebody asked for it, and a
-- launcher that silently relocates 40 GB the moment you touch a dropdown is
-- not a launcher anybody trusts twice.
--
-- WHAT MOVES: the three trees that grow -- installed mods, per-mod storage and
-- the shared base-file bank.  Saves and settings stay in the save directory on
-- purpose (see the launcher's own note): they are kilobytes and they are what
-- you want to still have when this folder is not plugged in.
--
-- HOW IT MOVES: a file at a time, streamed a megabyte at a time, as a
-- coroutine the launcher steps inside its frame budget.  Reading a 1.4 GB disc
-- into a string to write it back out would be the same bug the streaming
-- installer exists to avoid, and doing the whole tree in one call would freeze
-- the window for minutes with nothing on screen to say why.
--
-- COPY, VERIFY, THEN REMOVE -- in that order, per file.  A move that deletes
-- first and fails second is how somebody loses a mod folder, and this runs
-- against removable drives by definition.

local DataMove = {}

DataMove.TREES = { "mods", "modstorage", "imports/base" }
DataMove.CHUNK = 1024 * 1024

local function fsLove()
  return love and love.filesystem
end

local function cacheFs()
  local ok, CacheFs = pcall(require, "src.import.CacheFs")
  if ok then return CacheFs end
  return nil
end

-- Every file under `dir`, depth-first, as love.filesystem paths.  The listing
-- is the UNION of every home, which is what we want: a file that is already at
-- the destination is discovered here and skipped below rather than being
-- invisible until it collides.
function DataMove.files(dir, out, depth)
  out = out or {}
  depth = (depth or 0) + 1
  if depth > 12 then return out end          -- a symlink loop is not a tree
  local f = fsLove()
  if not (f and f.getInfo(dir)) then return out end
  for _, name in ipairs(f.getDirectoryItems(dir) or {}) do
    local path = dir .. "/" .. name
    local info = f.getInfo(path)
    if info and info.type == "directory" then
      DataMove.files(path, out, depth)
    elseif info then
      out[#out + 1] = { path = path, size = info.size or 0 }
    end
  end
  return out
end

-- Everything the three trees hold, plus a byte total for the progress line.
function DataMove.plan()
  local files, bytes = {}, 0
  for _, tree in ipairs(DataMove.TREES) do
    for _, row in ipairs(DataMove.files(tree)) do
      files[#files + 1] = row
      bytes = bytes + (row.size or 0)
    end
  end
  return files, bytes
end

-- Is this file already sitting at the destination, the right length?  Checked
-- with io.* against the real path rather than through love.filesystem, which
-- cannot tell the two homes apart -- that inability is the whole problem.
function DataMove.alreadyThere(root, path, size)
  local CacheFs = cacheFs()
  if not (CacheFs and root) then return false end
  local real = root .. CacheFs.SEP .. path:gsub("/", CacheFs.SEP)
  local handle = io.open(real, "rb")
  if not handle then return false end
  local have = handle:seek("end")
  handle:close()
  return have == size
end

-- Copy one file into the root, a megabyte at a time.  Returns true, or nil
-- plus a reason -- and removes a partial write, because a half-copied mod file
-- that LOOKS present is worse than one that is missing.
function DataMove.copyOne(root, path)
  local CacheFs = cacheFs()
  local f = fsLove()
  if not (CacheFs and f and root) then return nil, "no filesystem" end
  local real = root .. CacheFs.SEP .. path:gsub("/", CacheFs.SEP)
  local dir = path:match("^(.*)/[^/]*$")
  if dir then CacheFs.rawCreateDirectory(dir) end
  local input = f.newFile(path)
  if not (input and input:open("r")) then
    return nil, "could not read " .. path
  end
  local out, err = io.open(real, "wb")
  if not out then
    pcall(input.close, input)
    return nil, ("could not write %s (%s)"):format(path, tostring(err))
  end
  local ok = true
  while true do
    local chunk = input:read(DataMove.CHUNK)
    if not chunk or #chunk == 0 then break end
    local wrote = out:write(chunk)
    if wrote == nil then ok = false break end
    coroutine.yield()
  end
  out:close()
  pcall(input.close, input)
  if not ok then
    os.remove(real)
    return nil, "ran out of room writing " .. path
  end
  return true
end

-- The coroutine body.  `report(done, total, label)` is called as it goes; the
-- launcher turns that into a line and a bar.
--
-- love.filesystem.remove only ever reaches the SAVE DIRECTORY, which is
-- exactly the delete this wants: the copy at the destination is untouchable by
-- it, so "remove the old one" cannot become "remove the one I just made".
function DataMove.run(report)
  local CacheFs = cacheFs()
  local f = fsLove()
  if not (CacheFs and f) then return nil, "no filesystem" end
  local root = CacheFs.root()
  if not root then
    return nil, "there is no game-data folder to move into"
  end
  local files, bytes = DataMove.plan()
  local moved, skipped, failed, doneBytes = 0, 0, 0, 0
  for _, row in ipairs(files) do
    if report then report(doneBytes, bytes, row.path) end
    if DataMove.alreadyThere(root, row.path, row.size) then
      skipped = skipped + 1
    else
      local ok, why = DataMove.copyOne(root, row.path)
      if ok then
        moved = moved + 1
      else
        failed = failed + 1
        if report then report(doneBytes, bytes, tostring(why)) end
      end
    end
    -- Removed only once there is something at the other end, and only from the
    -- save directory.  A file that failed to copy keeps its original.
    if DataMove.alreadyThere(root, row.path, row.size) then
      f.remove(row.path)
    end
    doneBytes = doneBytes + (row.size or 0)
    coroutine.yield()
  end
  -- The now-empty directory shells, deepest first: love.filesystem.remove
  -- refuses a directory with anything left in it, which makes this safe to
  -- attempt blindly -- a folder that still holds a file it could not move
  -- simply stays.
  local dirs = {}
  local function walk(dir, depth)
    if (depth or 0) > 12 then return end
    if not f.getInfo(dir) then return end
    for _, name in ipairs(f.getDirectoryItems(dir) or {}) do
      local path = dir .. "/" .. name
      local info = f.getInfo(path)
      if info and info.type == "directory" then
        walk(path, (depth or 0) + 1)
        dirs[#dirs + 1] = path
      end
    end
  end
  for _, tree in ipairs(DataMove.TREES) do walk(tree, 0) end
  for i = #dirs, 1, -1 do pcall(f.remove, dirs[i]) end
  return { moved = moved, skipped = skipped, failed = failed, bytes = bytes }
end

function DataMove.summarize(result)
  if type(result) ~= "table" then return "Nothing to move." end
  local parts = {}
  if result.moved > 0 then
    parts[#parts + 1] = ("%d file(s) moved"):format(result.moved)
  end
  if result.skipped > 0 then
    parts[#parts + 1] = ("%d already there"):format(result.skipped)
  end
  if result.failed > 0 then
    parts[#parts + 1] = ("%d could not be moved"):format(result.failed)
  end
  if #parts == 0 then return "Nothing to move." end
  return table.concat(parts, ", ") .. "."
end

return DataMove
