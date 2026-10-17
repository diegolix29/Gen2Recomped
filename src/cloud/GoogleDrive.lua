-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- GOOGLE DRIVE AS A CLOUD-SAVE STORE (src/import/CloudSync.lua's store
-- interface: read(rel), write(rel, data), list(relDir)).
--
-- Everything lives in one Drive folder, "RetroRecomped", which the app made
-- itself (drive.file sees nothing else). Drive has no paths, so a store path
-- "saves/red/ab12cd34-slot1.lua" is the file name "saves__red__ab12cd34-slot1.lua".
-- A sync opens the store once: the folder's listing (name -> file id) is read
-- up front and kept current as files are written.

local Http = require("src.cloud.Http")
local Auth = require("src.cloud.GoogleAuth")

local D = {}

D.FOLDER = "RetroRecomped"
D.API = "https://www.googleapis.com/drive/v3/files"
D.UPLOAD = "https://www.googleapis.com/upload/drive/v3/files"

local function nameOf(rel) return (rel:gsub("/", "__")) end

local function call(token, method, url, opts)
  opts = opts or {}
  opts.headers = opts.headers or {}
  opts.headers.Authorization = "Bearer " .. token
  return Http.request(method, url, opts)
end

local function q(s) return Http.escape(s) end

-- the app's folder id, made on first use
local function folderId(token)
  local query = ("name='%s' and mimeType='application/vnd.google-apps.folder' and trashed=false"):format(D.FOLDER)
  local status, doc = Http.json(call(token, "GET", D.API .. "?q=" .. q(query) .. "&fields=" .. q("files(id)") .. "&spaces=drive"))
  if status ~= 200 then return nil, ("Drive listing failed (%s)"):format(tostring(status)) end
  if doc and doc.files and doc.files[1] then return doc.files[1].id end
  local Json = require("src.link.Json")
  status, doc = Http.json(call(token, "POST", D.API .. "?fields=id", {
    headers = { ["Content-Type"] = "application/json" },
    body = Json.encode({ name = D.FOLDER, mimeType = "application/vnd.google-apps.folder" }),
  }))
  if status ~= 200 or not (doc and doc.id) then return nil, ("could not make the Drive folder (%s)"):format(tostring(status)) end
  return doc.id
end

local function listing(token, folder)
  local ids, pageToken = {}, nil
  repeat
    local url = D.API .. "?q=" .. q(("'%s' in parents and trashed=false"):format(folder))
      .. "&fields=" .. q("nextPageToken,files(id,name)") .. "&pageSize=1000&spaces=drive"
      .. (pageToken and ("&pageToken=" .. q(pageToken)) or "")
    local status, doc = Http.json(call(token, "GET", url))
    if status ~= 200 then return nil, ("Drive listing failed (%s)"):format(tostring(status)) end
    for _, f in ipairs((doc and doc.files) or {}) do ids[f.name] = f.id end
    pageToken = doc and doc.nextPageToken
  until not pageToken
  return ids
end

-- open the store for one sync; nil + why when signed out or offline
function D.open()
  local token, why = Auth.accessToken()
  if not token then return nil, why end
  local folder, err = folderId(token)
  if not folder then return nil, err end
  local ids, err2 = listing(token, folder)
  if not ids then return nil, err2 end
  local store = { kind = "google", label = "Google Drive" }

  function store.read(rel)
    local id = ids[nameOf(rel)]
    if not id then return nil end
    local status, body = call(token, "GET", D.API .. "/" .. id .. "?alt=media")
    if status == 200 then return body end
    return nil
  end

  function store.write(rel, data)
    local name = nameOf(rel)
    local id = ids[name]
    if id then
      local status = call(token, "PATCH", D.UPLOAD .. "/" .. id .. "?uploadType=media",
        { headers = { ["Content-Type"] = "text/plain" }, body = data })
      if status == 200 then return true end
      return false, ("Drive update failed (%s)"):format(tostring(status))
    end
    local boundary = "rrboundary" .. love.math.random(100000, 999999)
    local Json = require("src.link.Json")
    local body = table.concat({
      "--" .. boundary,
      "Content-Type: application/json; charset=UTF-8",
      "",
      Json.encode({ name = name, parents = { folder } }),
      "--" .. boundary,
      "Content-Type: text/plain",
      "",
      data,
      "--" .. boundary .. "--",
      "",
    }, "\r\n")
    local status, doc = Http.json(call(token, "POST", D.UPLOAD .. "?uploadType=multipart&fields=id",
      { headers = { ["Content-Type"] = "multipart/related; boundary=" .. boundary }, body = body }))
    if status == 200 and doc and doc.id then ids[name] = doc.id; return true end
    return false, ("Drive upload failed (%s)"):format(tostring(status))
  end

  -- the names directly under relDir (like a folder listing)
  function store.list(relDir)
    local prefix = nameOf(relDir) .. "__"
    local out = {}
    for name in pairs(ids) do
      if name:sub(1, #prefix) == prefix then
        local rest = name:sub(#prefix + 1)
        if not rest:find("__", 1, true) then out[#out + 1] = rest end
      end
    end
    table.sort(out)
    return out
  end

  return store
end

return D
