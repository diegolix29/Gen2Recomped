-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ONEDRIVE AS A CLOUD-SAVE STORE (CloudSync's read / write / list), in the
-- app's own folder (Microsoft Graph's special "approot": Apps/<app name> in
-- the player's OneDrive). Graph addresses files by path, so a store path is
-- used as it is; writing a file makes its folders.

local Http = require("src.cloud.Http")
local Auth = require("src.cloud.MicrosoftAuth")

local O = {}
O.ROOT = "https://graph.microsoft.com/v1.0/me/drive/special/approot"

local function enc(rel)
  local parts = {}
  for p in rel:gmatch("[^/]+") do parts[#parts + 1] = Http.escape(p) end
  return table.concat(parts, "/")
end

function O.open()
  local token, why = Auth.accessToken()
  if not token then return nil, why end
  local auth = { Authorization = "Bearer " .. token }
  -- one call first, so "signed in but offline" fails here and not mid-sync
  local status = Http.request("GET", O.ROOT .. "?$select=id", { headers = auth })
  if status ~= 200 then return nil, ("OneDrive is not reachable (%s)"):format(tostring(status)) end
  local store = { kind = "onedrive", label = "OneDrive" }

  function store.read(rel)
    local s, body = Http.request("GET", O.ROOT .. ":/" .. enc(rel) .. ":/content", { headers = auth })
    if s == 200 then return body end
    return nil
  end

  function store.write(rel, data)
    local s = Http.request("PUT", O.ROOT .. ":/" .. enc(rel) .. ":/content", {
      headers = { Authorization = auth.Authorization, ["Content-Type"] = "text/plain" }, body = data })
    if s == 200 or s == 201 then return true end
    return false, ("OneDrive upload failed (%s)"):format(tostring(s))
  end

  function store.list(relDir)
    local out = {}
    local url = O.ROOT .. ":/" .. enc(relDir) .. ":/children?$select=name&$top=999"
    while url do
      local s, doc = Http.json(Http.request("GET", url, { headers = auth }))
      if s ~= 200 or not doc then break end
      for _, item in ipairs(doc.value or {}) do out[#out + 1] = item.name end
      url = doc["@odata.nextLink"]
    end
    table.sort(out)
    return out
  end

  return store
end

return O
