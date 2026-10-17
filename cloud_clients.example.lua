-- Copy to cloud_clients.lua (git-ignored) and fill in. Release builds write
-- the same file from repository secrets (see docs/cloud-saves.md).
return {
  google = {
    -- "Desktop app" OAuth client: sign-in through the browser (PC / Mac / Linux)
    desktop = { id = "", secret = "" },
    -- "TVs and Limited Input devices" OAuth client: sign-in with a code (Android)
    device = { id = "", secret = "" },
  },
  microsoft = {
    -- Azure app registration (public client): the Application (client) ID
    id = "",
  },
}
