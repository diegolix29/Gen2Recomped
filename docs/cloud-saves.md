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
- **In CI builds:** `release.yml` (every platform job), `ios.yml` and `build-ios.yml` write it with `scripts/write_cloud_clients.sh` from these repository secrets:
  - `GOOGLE_DESKTOP_CLIENT_ID`, `GOOGLE_DESKTOP_CLIENT_SECRET`
  - `GOOGLE_DEVICE_CLIENT_ID`, `GOOGLE_DEVICE_CLIENT_SECRET`
  - `MICROSOFT_CLIENT_ID`
- `scripts/pack_love.sh` packs the file when it is present.

A Google "installed app" secret is not confidential (Google says so), but GitHub's secret scanning flags it. That is why it lives outside the source tree.

## Earlier phone configuration and transport fixes (2026-10-17)

On Android and iOS, pressing SIGN IN for Google Drive or OneDrive showed only a one-line notice and never the code popup. The initial fixes covered configuration and transport; the additional layout and blocking-request faults are documented below. It draws and takes taps through the same `RomImporter:draw` / `mousepressed` path that `main.lua` forwards touches into. It opens only once `Auth.begin()` returns a device flow, and on phones `begin()` never got that far:

- **Credentials were never packed for phones.** `scripts/build_android.sh` and `scripts/build_ios.sh` each zip their own `game.love`. The `Write cloud-save credentials` step ran only in the `payload` job, so the APK and IPA had no `cloud_clients.lua`, and every sign-in stopped at "not set up". The fix:
  - the `android` and `ios` jobs in `release.yml` now write the file too;
  - both build scripts pack it when it is present (and warn when it is not).
- **iOS took the desktop flow.** `GoogleAuth.client()` gave iOS the loopback browser flow, which cannot work there (Safari suspends the app), and that flow has no code to show. iOS now uses the device-code flow, as Android does.
- **iOS had no HTTP transport.** It has no `httpRequest` bridge and no curl. `src/cloud/Http.lua` now uses LÖVE 12's built-in `require("https")` (lua-https) on iOS, and anywhere curl cannot run.
- A network failure now reads "could not reach Google/Microsoft: <why>" instead of "refused the sign-in request (nil)".

Popup changes:

- The popup is laid out inside `SafeArea.rect()`, clear of notches and the home indicator.
- CANCEL now always closes it, even when the SERVICE row has changed underneath it.
- COPY calls `love.system.setClipboardText`. OPEN WEBSITE calls `love.system.openURL`.

Verified with a phone-sized probe that fakes `getOS()` as Android or iOS: 1080x2340 and 2340x1080, plus 1170x2532 for iOS. Taps are routed exactly the way `main.lua` routes them, and COPY, OPEN WEBSITE and CANCEL each call the right function. Two things need a real device: the lua-https transport (desktop LÖVE here is 11.5) and a real sign-in round trip.

## Popup freezes and missing desktop configuration (2026-10-17)

The code font fit loop used line height as the next requested font size. With fonts whose line height exceeds their point size, a narrow code box caused the loop to increase font sizes indefinitely. It now shrinks an explicit point size with a fixed iteration limit. The card also scales to the safe area in portrait and landscape.

`src/cloud/Task.lua` runs auth control flow in a main-state coroutine and yields HTTP requests to `src/cloud/http_worker.lua`. Starting sign-in, polling tokens, fetching the account, and revoking a sign-in no longer block launcher rendering. A pending popup appears immediately and remains cancellable. Workers have a 30-second UI deadline; cancelled or timed-out responses cannot resume auth code. In-flight workers are retained until they exit so garbage collection cannot block Cancel by joining them. Browsers, token persistence, and callbacks stay on the main state. Ordinary cloud file synchronization still uses its existing transport path.

The local Windows packer omitted `cloud_clients.lua`; the existing local `game.love` also lacked it. `scripts/build-windows-exe-script.ps1` now includes the file. The credentials writer preserves existing local configuration when no environment is supplied, and fails CI with an explicit setup error rather than silently generating an entirely blank configuration. CI secrets remain required for the providers you publish; no credentials are committed.

Validation: `tools/cloud_signin_check/tests.lua` covers asynchronous completion, cancellation, deadlines, worker errors, font metrics that previously caused the infinite loop, modal input isolation, and controls in four viewport sizes (47 checks). `tools/cloud_signin_check/build_tests.py` covers missing CI credentials, preservation of local configuration, generation, and invalid multiline values (4 checks). `tools/cloud_signin_check` verifies a real LOVE worker against a delayed local HTTP server and checks render-thread poll duration. `tools/launcher_shot` supports `CLOUD_CODE` and `CLOUD_PENDING` for isolated screenshots. Real Android/iOS sign-in and provider authorization still require device testing.
