-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- CLOUD SAVES THROUGH A SYNC FOLDER: OneDrive, Google Drive for desktop,
-- Dropbox, iCloud Drive -- or any folder the player picks. The launcher only
-- copies files into and out of that folder; the provider's own app does the
-- uploading. No accounts, keys or sign-in here. (Direct sign-in to the
-- services' APIs is a second transport, added when the app has client ids.)
--
-- THE LAYOUT, under <folder>/Gen2Recomp/:
--   saves/<version>/<cloudId>.lua          the save, as the slot file holds it
--   saves/<version>/<cloudId>.info.lua     { label, device, updated, hash }
--   backups/<version>/<cloudId>.1.lua / .2.lua   the cloud side's last two
-- and locally, in the save directory:
--   cloud_sync.lua                         { device, links[version][slot] }
--   cloud_backups/<version>/<slot>.1.lua / .2.lua  the local side's last two
--
-- A cloudId is "<device>-<slot>", so two machines never write the same file
-- unless they have been linked to it by a sync.
--
-- THE RULES, per slot:
--   * NEVER SYNCED BEFORE (no link): nothing is replaced. The local save goes
--     up as a new cloud entry; every cloud entry no local slot is linked to
--     comes down as a NEW local slot.
--   * linked, only the local side changed since the last sync: the cloud copy
--     is backed up (two kept) and replaced;
--   * only the cloud side changed: the local slot is backed up (two kept) and
--     replaced;
--   * both changed: the cloud copy comes down as a new local slot labelled
--     "(cloud)", then the local save goes up -- nothing is lost either way.

local SaveData = require("src.core.SaveData")
local SaveSerializer = require("src.core.SaveSerializer")

local C = {}

C.ROOT = "Gen2Recomp"
C.STATE_FILE = "cloud_sync.lua"
C.BACKUPS = 2

local SEP = package.config:sub(1, 1)
local WINDOWS = SEP == "\\"

local function join(...)
  local parts = { ... }
  return table.concat(parts, SEP)
end

local function exists(path)
  local f = io.open(path, "rb")
  if f then f:close() return true end
  return false
end

local function readAll(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local function mkdirs(path)
  local okC, CacheFs = pcall(require, "src.import.CacheFs")
  local cur = ""
  for part in path:gmatch("[^\\/]+") do
    cur = (cur == "" and (path:sub(1, 1) == "/" and "/" or "") or (cur .. SEP)) .. part
    if not cur:match("^%a:$") then
      if okC and CacheFs.mkdirReal then pcall(CacheFs.mkdirReal, cur) end
    end
  end
end

-- write through a temp file, so a sync interrupted halfway leaves the old
-- file whole
local function writeAll(path, data)
  mkdirs(path:match("^(.*)[\\/][^\\/]+$") or path)
  local tmp = path .. ".tmp"
  local f = io.open(tmp, "wb")
  if not f then return false, "cannot write " .. tmp end
  f:write(data)
  f:close()
  os.remove(path)
  local ok, err = os.rename(tmp, path)
  if not ok then return false, tostring(err) end
  return true
end

local function listDir(path)
  local out = {}
  local HostShell = require("src.core.HostShell")
  local cmd = WINDOWS and ('dir /b "' .. path .. '" 2>nul') or ("ls -1 " .. HostShell.quote(path) .. " 2>/dev/null")
  local pipe = HostShell.popen(cmd)
  if not pipe then return out end
  for line in pipe:lines() do
    line = line:gsub("\r", "")
    if line ~= "" then out[#out + 1] = line end
  end
  pipe:close()
  return out
end
C._listDir = listDir

function C.hash(s)
  s = s or ""
  if love and love.data and love.data.hash then
    local ok, raw = pcall(love.data.hash, "md5", s)
    if ok and raw then
      local okE, hex = pcall(love.data.encode, "string", "hex", raw)
      if okE and hex then return hex end
    end
  end
  local h = 5381
  for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
  return ("%08x%d"):format(h, #s)
end

-- ----------------------------------------------------------------- folders

-- the sync folders this machine has, as { name, path }
function C.detectFolders()
  local found, seen = {}, {}
  local function add(name, path)
    if type(path) ~= "string" or path == "" then return end
    path = path:gsub("[\\/]+$", "")
    local key = path:lower()
    if seen[key] then return end
    -- a sync folder is one a probe file can be written into (no shell, so
    -- asking every candidate costs nothing)
    local probe = join(path, ".gen2recomp_probe")
    local f = io.open(probe, "wb")
    if not f then return end
    f:close(); os.remove(probe)
    seen[key] = true
    found[#found + 1] = { name = name, path = path }
  end
  local home = os.getenv("USERPROFILE") or os.getenv("HOME") or ""
  add("OneDrive", os.getenv("OneDriveConsumer"))
  add("OneDrive", os.getenv("OneDrive"))
  add("OneDrive (work)", os.getenv("OneDriveCommercial"))
  add("OneDrive", join(home, "OneDrive"))
  add("Dropbox", join(home, "Dropbox"))
  add("iCloud Drive", join(home, "iCloudDrive"))
  add("Google Drive", join(home, "Google Drive"))
  add("Google Drive", join(home, "My Drive"))
  if WINDOWS then
    -- Google Drive for desktop mounts a drive letter with "My Drive" in it
    for code = string.byte("D"), string.byte("Z") do
      local root = string.char(code) .. ":"
      add("Google Drive", root .. "\\My Drive")
    end
  else
    local cs = join(home, "Library", "CloudStorage")
    for _, name in ipairs(listDir(cs)) do
      local label = name:match("^GoogleDrive") and "Google Drive"
        or name:match("^OneDrive") and "OneDrive"
        or name:match("^Dropbox") and "Dropbox" or name
      local p = join(cs, name)
      if label == "Google Drive" and #listDir(join(p, "My Drive")) > 0 then p = join(p, "My Drive") end
      add(label, p)
    end
    add("iCloud Drive", join(home, "Library", "Mobile Documents", "com~apple~CloudDocs"))
  end
  return found
end

-- --------------------------------------------------------------- the state
-- One state per service (links made against a folder mean nothing on Drive):
-- cloud_sync.lua for the sync folder, cloud_sync_<kind>.lua for the others.

local function stateFile(kind)
  if not kind or kind == "folder" then return C.STATE_FILE end
  return ("cloud_sync_%s.lua"):format(kind)
end

function C.loadState(kind)
  local st
  local file = stateFile(kind)
  if love and love.filesystem and love.filesystem.getInfo(file) then
    local ok, t = pcall(SaveSerializer.decode, love.filesystem.read(file) or "")
    if ok and type(t) == "table" then st = t end
  end
  st = st or {}
  st.links = st.links or {}
  if not st.device then
    -- the same device id for every service, so names stay recognisable
    local other = kind and kind ~= "folder" and C.loadState("folder")
    if other and other.device then st.device = other.device
    else
      local r = love and love.math and love.math.random or math.random
      st.device = ("%04x%04x"):format(r(0, 0xFFFF), r(0, 0xFFFF))
    end
  end
  return st
end

function C.saveState(st, kind)
  if love and love.filesystem then
    love.filesystem.write(stateFile(kind), SaveSerializer.encode(st))
  end
end

-- ------------------------------------------------------------- the stores
-- A store is { kind, label, read(rel) -> text|nil, write(rel, text) -> ok,
-- why, list(relDir) -> names }. Paths are relative and use "/":
-- saves/<version>/<cloudId>.lua, its .info.lua, backups/<version>/<cloudId>.n.lua

function C.folderStore(folder)
  local root = join(folder, C.ROOT)
  local function abs(rel) return join(root, (rel:gsub("/", SEP))) end
  return {
    kind = "folder", label = folder,
    read = function(rel) return readAll(abs(rel)) end,
    write = function(rel, data) return writeAll(abs(rel), data) end,
    list = function(relDir) return listDir(abs(relDir)) end,
  }
end

local function asStore(target)
  if type(target) == "table" then return target end
  if type(target) == "string" and target ~= "" then return C.folderStore(target) end
  return nil
end

-- ------------------------------------------------------------- the copies

local function cloudRel(version, cloudId) return ("saves/%s/%s.lua"):format(version, cloudId) end
local function infoRel(version, cloudId) return ("saves/%s/%s.info.lua"):format(version, cloudId) end

local function readInfo(store, version, cloudId)
  local s = store.read(infoRel(version, cloudId))
  if not s then return {} end
  local ok, t = pcall(SaveSerializer.decode, s)
  return (ok and type(t) == "table") and t or {}
end

-- the newest copy goes in .1, the one before it in .2
local function rotateCloud(store, version, cloudId)
  local cur = store.read(cloudRel(version, cloudId))
  if not cur then return end
  local dir = ("backups/%s/"):format(version)
  for i = C.BACKUPS, 2, -1 do
    local older = store.read(dir .. ("%s.%d.lua"):format(cloudId, i - 1))
    if older then store.write(dir .. ("%s.%d.lua"):format(cloudId, i), older) end
  end
  store.write(dir .. cloudId .. ".1.lua", cur)
end

local function localBytes(version, slotId)
  local path = SaveData.slotDiskPath(version, slotId)
  return path and readAll(path) or nil
end

local function rotateLocal(version, slotId)
  local cur = localBytes(version, slotId)
  if not (cur and love and love.filesystem) then return end
  local dir = ("cloud_backups/%s"):format(version)
  love.filesystem.createDirectory(dir)
  for i = C.BACKUPS, 2, -1 do
    local older = love.filesystem.read(("%s/%s.%d.lua"):format(dir, slotId, i - 1))
    if older then love.filesystem.write(("%s/%s.%d.lua"):format(dir, slotId, i), older) end
  end
  love.filesystem.write(("%s/%s.1.lua"):format(dir, slotId), cur)
end

local function upload(store, st, version, slotId, cloudId, bytes, label)
  local ok, err = store.write(cloudRel(version, cloudId), bytes)
  if not ok then return false, err end
  local h = C.hash(bytes)
  store.write(infoRel(version, cloudId), SaveSerializer.encode({
    label = label, device = st.device, updated = os.time(), hash = h, slot = slotId,
  }))
  return true, h
end

local function writeLocal(version, slotId, bytes)
  local ok, t = pcall(SaveSerializer.decode, bytes)
  if not (ok and type(t) == "table") then return false, "the cloud copy does not read as a save" end
  return SaveData.writeSlot(version, slotId, t)
end

local function newLocalSlot(version, bytes, label)
  local id = SaveData.createSlot(version)
  if not id then return nil, "could not make a slot" end
  local ok, err = writeLocal(version, id, bytes)
  if not ok then return nil, err end
  if label then pcall(SaveData.renameSlot, version, id, label) end
  return id
end

local function slotLabel(version, slotId)
  for _, s in ipairs(SaveData.listSlots(version) or {}) do
    if s.id == slotId then return s.label or s.name end
  end
end

-- one slot; returns a short word for what happened, or nil + why
function C.syncSlot(target, st, version, slotId)
  local store = asStore(target)
  st.links[version] = st.links[version] or {}
  local link = st.links[version][slotId]
  local bytes = localBytes(version, slotId)
  if not link then
    if not bytes then return "empty" end
    local cloudId = st.device .. "-" .. slotId
    local ok, h = upload(store, st, version, slotId, cloudId, bytes, slotLabel(version, slotId))
    if not ok then return nil, h end
    st.links[version][slotId] = { cloudId = cloudId, hash = h }
    return "uploaded"
  end
  local cloudBytes = store.read(cloudRel(version, link.cloudId))
  local localH = bytes and C.hash(bytes) or nil
  local cloudH = cloudBytes and C.hash(cloudBytes) or nil
  local localChanged = localH ~= nil and localH ~= link.hash
  local cloudChanged = cloudH ~= nil and cloudH ~= link.hash
  if cloudH == nil and bytes then
    -- the cloud copy went missing: put it back
    local ok, h = upload(store, st, version, slotId, link.cloudId, bytes, slotLabel(version, slotId))
    if not ok then return nil, h end
    link.hash = h
    return "uploaded"
  end
  if not localChanged and not cloudChanged then return "same" end
  if localChanged and not cloudChanged then
    rotateCloud(store, version, link.cloudId)
    local ok, h = upload(store, st, version, slotId, link.cloudId, bytes, slotLabel(version, slotId))
    if not ok then return nil, h end
    link.hash = h
    return "uploaded"
  end
  if cloudChanged and not localChanged then
    rotateLocal(version, slotId)
    local ok, err = writeLocal(version, slotId, cloudBytes)
    if not ok then return nil, err end
    link.hash = cloudH
    return "downloaded"
  end
  -- both sides moved: keep both
  local label = (slotLabel(version, slotId) or slotId) .. " (cloud)"
  local newId, err = newLocalSlot(version, cloudBytes, label)
  if not newId then return nil, err end
  st.links[version][newId] = nil   -- the copy stays local until its own first sync
  rotateCloud(store, version, link.cloudId)
  local ok, h = upload(store, st, version, slotId, link.cloudId, bytes, slotLabel(version, slotId))
  if not ok then return nil, h end
  link.hash = h
  return "kept both"
end

-- cloud entries no local slot is linked to come down as new slots
function C.pullNew(target, st, version)
  local store = asStore(target)
  st.links[version] = st.links[version] or {}
  local linked = {}
  for _, link in pairs(st.links[version]) do linked[link.cloudId] = true end
  local got = 0
  for _, name in ipairs(store.list("saves/" .. version)) do
    local cloudId = name:match("^(.-)%.lua$")
    if cloudId and not cloudId:match("%.info$") and not linked[cloudId] then
      local bytes = store.read(cloudRel(version, cloudId))
      if bytes then
        local info = readInfo(store, version, cloudId)
        local label = info.label and (info.label .. " (cloud)") or ("Cloud " .. cloudId)
        local id = newLocalSlot(version, bytes, label)
        if id then
          st.links[version][id] = { cloudId = cloudId, hash = C.hash(bytes) }
          got = got + 1
        end
      end
    end
  end
  return got
end

-- every slot of these versions, then whatever is new in the cloud; a summary.
-- `target` is a sync folder's path or an open store (GoogleDrive.open())
function C.syncVersions(target, versions)
  local store = asStore(target)
  if not store then return nil, "no sync folder chosen" end
  local st = C.loadState(store.kind)
  local tally = { uploaded = 0, downloaded = 0, ["kept both"] = 0, new = 0, failed = 0 }
  for _, v in ipairs(versions) do
    for _, s in ipairs(SaveData.listSlots(v) or {}) do
      local what = C.syncSlot(store, st, v, s.id)
      if what and tally[what] then tally[what] = tally[what] + 1
      elseif not what then tally.failed = tally.failed + 1 end
    end
    tally.new = tally.new + C.pullNew(store, st, v)
  end
  C.saveState(st, store.kind)
  return tally
end

function C.syncOne(target, version, slotId)
  local store = asStore(target)
  if not store then return nil, "no sync folder chosen" end
  local st = C.loadState(store.kind)
  local what, why = C.syncSlot(store, st, version, slotId)
  C.saveState(st, store.kind)
  return what, why
end

function C.describe(t)
  if not t then return "nothing synced" end
  local parts = {}
  for _, k in ipairs({ "uploaded", "downloaded", "new", "kept both", "failed" }) do
    if (t[k] or 0) > 0 then parts[#parts + 1] = ("%d %s"):format(t[k], k == "new" and "new from the cloud" or k) end
  end
  return #parts > 0 and table.concat(parts, ", ") or "everything already in sync"
end

return C
