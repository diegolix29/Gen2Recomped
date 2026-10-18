#!/usr/bin/env bash
# Writes cloud_clients.lua (git-ignored) from the environment, for release
# builds: the cloud-save sign-in credentials (src/cloud/CloudClients.lua).
# Local builds preserve existing configuration when no environment is supplied.
# CI must supply at least one provider; never silently publish a blank config.
#
#   GOOGLE_DESKTOP_CLIENT_ID / GOOGLE_DESKTOP_CLIENT_SECRET   "Desktop app" client
#   GOOGLE_DEVICE_CLIENT_ID  / GOOGLE_DEVICE_CLIENT_SECRET    "TVs and Limited Input" client
#   MICROSOFT_CLIENT_ID                                       Azure application id
set -euo pipefail
out="${1:-cloud_clients.lua}"
if [ -z "${GOOGLE_DESKTOP_CLIENT_ID:-}${GOOGLE_DEVICE_CLIENT_ID:-}${MICROSOFT_CLIENT_ID:-}" ]; then
  if [ "${CI:-false}" = "true" ]; then
    echo "Cloud sign-in configuration missing: set GOOGLE_DEVICE_CLIENT_ID / GOOGLE_DEVICE_CLIENT_SECRET or MICROSOFT_CLIENT_ID in repository secrets." >&2
    exit 1
  fi
  if [ -f "$out" ]; then
    echo "Keeping existing cloud sign-in configuration (no environment supplied)."
    exit 0
  fi
  echo "No cloud sign-in credentials supplied; configuration was not written." >&2
  exit 1
fi
for name in GOOGLE_DESKTOP_CLIENT_ID GOOGLE_DESKTOP_CLIENT_SECRET GOOGLE_DEVICE_CLIENT_ID GOOGLE_DEVICE_CLIENT_SECRET MICROSOFT_CLIENT_ID; do
  value="${!name:-}"
  case "$value" in
    *$'\n'*|*$'\r'*) echo "Invalid newline in $name" >&2; exit 1 ;;
  esac
done
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
