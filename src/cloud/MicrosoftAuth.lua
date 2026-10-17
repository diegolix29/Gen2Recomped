-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- SIGNING IN TO MICROSOFT (OneDrive), for cloud saves: the device-code flow
-- on every platform -- the launcher shows a short code and
-- microsoft.com/devicelogin, the player enters it in any browser, the
-- launcher polls. A public client: no secret. Permissions:
-- Files.ReadWrite.AppFolder (the app's own folder only), offline_access,
-- User.Read. Tokens stay on this device (cloud_microsoft.lua).

local Http = require("src.cloud.Http")
local Clients = require("src.cloud.CloudClients")

local M = {}

M.AUTHORITY = "https://login.microsoftonline.com/common/oauth2/v2.0"
M.SCOPE = "Files.ReadWrite.AppFolder offline_access User.Read"
M.FILE = "cloud_microsoft.lua"

function M.client()
  local c = Clients.microsoft()
  if c then return c end
  return nil, "OneDrive sign-in is not set up in this build (cloud_clients.lua)"
end

local function load()
  if love.filesystem.getInfo(M.FILE) then
    local ok, t = pcall(require("src.core.SaveSerializer").decode, love.filesystem.read(M.FILE) or "")
    if ok and type(t) == "table" then return t end
  end
  return nil
end
local function store(t) love.filesystem.write(M.FILE, require("src.core.SaveSerializer").encode(t)) end

function M.signedIn() local t = load(); return t ~= nil and t.refresh ~= nil end
function M.account() local t = load(); return t and t.email or nil end

local function took(t, doc)
  t = t or {}
  t.access = doc.access_token
  t.expires = os.time() + (tonumber(doc.expires_in) or 3600) - 60
  if doc.refresh_token then t.refresh = doc.refresh_token end
  store(t)
  return t
end

local function post(path, form)
  return Http.json(Http.request("POST", M.AUTHORITY .. path, {
    headers = { ["Content-Type"] = "application/x-www-form-urlencoded" }, body = Http.form(form) }))
end

function M.accessToken()
  local t = load()
  if not (t and t.refresh) then return nil, "not signed in to OneDrive" end
  if t.access and (t.expires or 0) > os.time() then return t.access end
  local client = M.client()
  if not client then return nil, "OneDrive sign-in is not set up" end
  local status, doc = post("/token", { client_id = client.id, grant_type = "refresh_token",
                                        refresh_token = t.refresh, scope = M.SCOPE })
  if status == 200 and doc and doc.access_token then return took(t, doc).access end
  if doc and doc.error == "invalid_grant" then
    love.filesystem.remove(M.FILE)
    return nil, "OneDrive sign-in expired -- sign in again"
  end
  return nil, ("could not refresh the OneDrive sign-in (%s)"):format(tostring(doc and doc.error or status))
end

-- Microsoft keeps no revocation endpoint for this flow: signing out forgets
-- the tokens here (and the player can remove the app from their account)
function M.signOut() love.filesystem.remove(M.FILE) end

function M.fetchAccount()
  local token = M.accessToken()
  if not token then return nil end
  local status, doc = Http.json(Http.request("GET",
    "https://graph.microsoft.com/v1.0/me?$select=userPrincipalName,mail,displayName",
    { headers = { Authorization = "Bearer " .. token } }))
  local who = status == 200 and doc and (doc.mail or doc.userPrincipalName or doc.displayName)
  if who then local t = load(); if t then t.email = who; store(t) end end
  return who
end

-- start: { kind = "device", code, url } to show the player, or nil + why
function M.begin()
  local client, why = M.client()
  if not client then return nil, why end
  local status, doc = post("/devicecode", { client_id = client.id, scope = M.SCOPE })
  if status ~= 200 or not (doc and doc.device_code) then
    return nil, ("Microsoft refused the sign-in request (%s)"):format(tostring(doc and (doc.error_description or doc.error) or status))
  end
  return {
    kind = "device", client = client, deviceCode = doc.device_code, code = doc.user_code,
    url = doc.verification_uri or "https://microsoft.com/devicelogin",
    interval = tonumber(doc.interval) or 5, expires = os.time() + (tonumber(doc.expires_in) or 900),
    nextPoll = os.time() + (tonumber(doc.interval) or 5),
  }
end

function M.poll(flow)
  if not flow then return "failed", "no sign-in in progress" end
  if os.time() > flow.expires then return "failed", "the sign-in timed out" end
  if os.time() < flow.nextPoll then return "waiting" end
  flow.nextPoll = os.time() + flow.interval
  local status, doc = post("/token", { client_id = flow.client.id, device_code = flow.deviceCode,
    grant_type = "urn:ietf:params:oauth:grant-type:device_code" })
  if status == 200 and doc and doc.access_token then
    took({}, doc)
    pcall(M.fetchAccount)
    return "done"
  end
  local err = doc and doc.error
  if err == "authorization_pending" then return "waiting" end
  if err == "slow_down" then flow.interval = flow.interval + 5; return "waiting" end
  return "failed", ("OneDrive sign-in failed (%s)"):format(tostring(doc and (doc.error_description or err) or status))
end

function M.cancel() end

return M
