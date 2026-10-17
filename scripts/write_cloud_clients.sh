#!/usr/bin/env bash
# Writes cloud_clients.lua (git-ignored) from the environment, for release
# builds: the cloud-save sign-in credentials (src/cloud/CloudClients.lua).
# Missing values are left empty; that service then reports "not set up".
#
#   GOOGLE_DESKTOP_CLIENT_ID / GOOGLE_DESKTOP_CLIENT_SECRET   "Desktop app" client
#   GOOGLE_DEVICE_CLIENT_ID  / GOOGLE_DEVICE_CLIENT_SECRET    "TVs and Limited Input" client
#   MICROSOFT_CLIENT_ID                                       Azure application id
set -euo pipefail
out="${1:-cloud_clients.lua}"
q() { printf '%s' "${1:-}" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
cat > "$out" <<EOF
-- Written by scripts/write_cloud_clients.sh for this build.
return {
  google = {
    desktop = { id = "$(q "${GOOGLE_DESKTOP_CLIENT_ID:-}")", secret = "$(q "${GOOGLE_DESKTOP_CLIENT_SECRET:-}")" },
    device = { id = "$(q "${GOOGLE_DEVICE_CLIENT_ID:-}")", secret = "$(q "${GOOGLE_DEVICE_CLIENT_SECRET:-}")" },
  },
  microsoft = { id = "$(q "${MICROSOFT_CLIENT_ID:-}")" },
}
EOF
echo "wrote $out"
