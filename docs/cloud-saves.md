# Cloud saves

The top of Settings → **CLOUD SAVES** offers three services:

| Service | How it works |
| --- | --- |
| **Sync folder** | Copies saves into a OneDrive / Google Drive / Dropbox / iCloud folder on this computer. The provider's own app uploads them. |
| **Google Drive** | Signs in through Google and keeps saves in a `RetroRecomped` folder in the player's Drive. The `drive.file` permission means the app sees only files it created. |
| **OneDrive** | Signs in through Microsoft and keeps saves in the app's own folder (`Apps/<app name>`). The `Files.ReadWrite.AppFolder` permission is limited to that folder. |

The sync rules are the same for every service (`src/import/CloudSync.lua`):

- A save is never replaced on its first sync.
- After that, whichever side changed is copied to the other.
- If both sides changed, both copies are kept.
- Each side keeps two backups.

Each service keeps its own link state: `cloud_sync.lua` for the folder, and `cloud_sync_google.lua` / `cloud_sync_onedrive.lua` for the others.

## Modules

| Module | Role |
| --- | --- |
| `src/cloud/Http.lua` | Any HTTP method. Uses curl on desktop and `love.system.httpRequest` on Android (`GameActivity.httpRequest`, a new JNI bridge). |
| `src/cloud/GoogleAuth.lua` | Google sign-in (see "Sign-in flows"). Tokens are stored in `cloud_google.lua`, on the device only. |
| `src/cloud/GoogleDrive.lua` | The Drive store. Drive has no folders here, so a store path is flattened into a file name: `saves/red/x.lua` becomes `saves__red__x.lua`. |
| `src/cloud/MicrosoftAuth.lua` | Microsoft sign-in by device code. Tokens are stored in `cloud_microsoft.lua`. |
| `src/cloud/OneDrive.lua` | The OneDrive store: Graph's `special/approot`, addressed by path. |
| `src/cloud/CloudClients.lua` | Reads the app credentials (see "Credentials"). |

## Sign-in flows

- **Google, everywhere:** a short code that the player enters at google.com/device. This needs a "TVs and Limited Input devices" client, which is the project's client.
  - Its downloaded JSON says `"installed"`, the same as a Desktop client's, so it is easy to mistake for one.
  - Google rejects the browser-redirect flow for this type: `Localhost URI is not allowed for 'NATIVE_DEVICE' client type`.
- **Google with a Desktop client, if you ever add one:** the browser opens Google's page, which redirects to a one-shot listener on `127.0.0.1`, protected with PKCE. That client goes in the `desktop` slot.
- **Microsoft, everywhere:** a short code that the player enters at microsoft.com/devicelogin.

For both code flows, the launcher shows a popup over everything (`src/import/LauncherCloudCode.lua`). It has the steps, the code in large bold letters with a **COPY** button, **OPEN WEBSITE**, and **CANCEL**.

- The website does not open by itself, so the player can copy the code first.
- The popup closes when the sign-in succeeds or fails.
- Keys: Escape cancels, Ctrl+C copies, Enter opens the site.
- Harness: `CLOUD_CODE=ABCD-EFGH` in `tools/launcher_shot` shows the popup with a pretend sign-in.

## Credentials

`cloud_clients.lua` is git-ignored. `cloud_clients.example.lua` shows its shape.

- **Locally:** copy the example and fill it in.
- **In release builds:** `.github/workflows/release.yml` writes it with `scripts/write_cloud_clients.sh` from these repository secrets:
  - `GOOGLE_DESKTOP_CLIENT_ID`, `GOOGLE_DESKTOP_CLIENT_SECRET`
  - `GOOGLE_DEVICE_CLIENT_ID`, `GOOGLE_DEVICE_CLIENT_SECRET`
  - `MICROSOFT_CLIENT_ID`
- `scripts/pack_love.sh` packs the file when it is present.

A Google "installed app" secret is not confidential (Google says so), but GitHub's secret scanning flags it. That is why it lives outside the source tree.
