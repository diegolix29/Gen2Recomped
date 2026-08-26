#!/usr/bin/env bash
# Packages the LÖVE2D Pokémon Red port into an Android APK via love-android 11.5a.
#
# Usage: scripts/build_android.sh [--version X.Y.Z] [--package-only]
#
#   --version X.Y.Z  set app.version_name / app.version_code (else left as-is)
#   --package-only   zip game.love + apply branding; skip gradle
#
# Prerequisites:
#   - mobile/android vendored love-android tree at tag 11.5a (in-repo; see mobile/ANDROID.md)
#   - Android SDK + NDK (SDK API 34, NDK 25.2.9519653)
#   - JDK 17
#
# Output (after gradle):
#   dist/android/debug/*.apk (convenience copy)
#   mobile/android/app/build/outputs/apk/embedNoRecord/debug/*.apk

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ANDROID_DIR="$ROOT/mobile/android"
EMBED_ASSETS="$ANDROID_DIR/app/src/embed/assets"
LOVE_FILE="$EMBED_ASSETS/game.love"
DIST="$ROOT/dist/android"
APP_NAME="gen2recomp"
# Distinct from the Gen 1 port's application id so the two can sit side by
# side on one device; see mobile/ANDROID.md.
APPLICATION_ID="com.underdecodedhd.gen2recomp"
LOVE_ANDROID_VERSION="11.5a"
NDK_VERSION="25.2.9519653"
MANIFEST_BASE_URL="${MANIFEST_BASE_URL:-https://raw.githubusercontent.com/UNDERdecoded/Gen2Recomped/main}"
MANIFESTS=""
GEN2_SOURCES=""
# RomExtractorGen2:readSourceTable falls back to data/generated_gen2_<version>/
# for the tables the Python tooling produces but the ROM walk does not.
GEN2_SOURCE_TABLES="constants charmap items maps moves text text_pointers trainer_headers"

# Convert Git Bash path to Windows path for PowerShell
git_bash_to_windows_path() {
  local path="$1"
  # Convert /c/ to C:/, /f/ to F:/, etc.
  if [[ "$path" =~ ^/([a-z])/(.*)$ ]]; then
    local drive="${BASH_REMATCH[1]}"
    local rest="${BASH_REMATCH[2]}"
    echo "${drive^^}:/${rest}"
  else
    echo "$path"
  fi
}

# Convert key paths to Windows format
WIN_ROOT="$(git_bash_to_windows_path "$ROOT")"
WIN_LOVE_FILE="$(git_bash_to_windows_path "$LOVE_FILE")"
WIN_EMBED_ASSETS="$(git_bash_to_windows_path "$EMBED_ASSETS")"

VERSION=""
PACKAGE_ONLY=false

say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2; }
fail() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --version) VERSION="$2"; shift ;;
    --package-only) PACKAGE_ONLY=true ;;
    -h|--help)
      sed -n '2,20p' "$0"
      exit 0
      ;;
    *) fail "unknown argument: $1 (try --version X.Y.Z or --package-only)" ;;
  esac
  shift
done

VERSION_CODE=""
if [ -n "$VERSION" ]; then
  if ! printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    fail "invalid --version '$VERSION' (expected X.Y.Z)"
  fi
  major="${VERSION%%.*}"
  rest="${VERSION#*.}"
  minor="${rest%%.*}"
  patch="${rest##*.}"
  VERSION_CODE=$((major * 10000 + minor * 100 + patch))
fi

# --------------------------------------------------------------- preconditions
if [ ! -f "$ANDROID_DIR/settings.gradle" ] || [ ! -f "$ANDROID_DIR/gradlew" ]; then
  fail "love-android not found at mobile/android/.
  The love-android $LOVE_ANDROID_VERSION tree is vendored in this repo,  your checkout
  looks incomplete. Re-clone or 'git checkout -- mobile/android'. See mobile/ANDROID.md."
fi

if [ ! -d "$ANDROID_DIR/love/src/jni/love/src" ]; then
  fail "liblove sources missing under mobile/android/love/src/jni/love/.
  They are vendored in this repo,  your checkout looks incomplete.
  Re-clone or 'git checkout -- mobile/android'. See mobile/ANDROID.md."
fi

# ------------------------------------------------------- import metadata
# Android packages game.love itself rather than reusing scripts/build.sh's
# archive. Keep a partial source export from silently shipping an APK that can
# list a version but cannot import it. Resolve the manifest list from
# src/core/GameVersion.lua so newly added versions are included automatically.
manifest_paths() {
  python3 - "$ROOT/src/core/GameVersion.lua" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
print(" ".join(dict.fromkeys(re.findall(r'manifest\s*=\s*"([^"]+)"', src))))
PY
}

# Gen2 versions declared in GameVersion.lua, so a newly added cart is covered
# without touching this script.
gen2_version_ids() {
  python3 - "$ROOT/src/core/GameVersion.lua" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
ids = [i for i, gen in re.findall(r'id\s*=\s*"([^"]+)"[^}]*?generation\s*=\s*(\d+)', src, re.S)
       if gen == "2"]
print(" ".join(dict.fromkeys(ids)))
PY
}

# The Gen2 extractor cannot run off the ROM alone: without these the APK lists
# Gold/Silver and then dies partway through the import.
ensure_gen2_sources() {
  GEN2_SOURCES=""
  local version table rel
  for version in $(gen2_version_ids); do
    for table in $GEN2_SOURCE_TABLES; do
      rel="data/generated_gen2_$version/$table.lua"
      [ -s "$ROOT/$rel" ] || fail "$rel is missing or empty.
  Regenerate the Gen2 source tables before packaging:
    powershell -ExecutionPolicy Bypass -File scripts/setup_gen2_symbols.ps1
  (see mobile/ANDROID.md, \"Gold/Silver mobile prep checklist\")"
      GEN2_SOURCES="$GEN2_SOURCES $rel"
    done
  done
  say "gen2 source tables:$(printf ' %s' $(gen2_version_ids))"
}

manifest_is_valid() {
  local path="$1"
  python3 - "$path" <<'PY'
import json, pathlib, sys

try:
    manifest = json.loads(pathlib.Path(sys.argv[1]).read_text())
except (OSError, ValueError):
    raise SystemExit(1)

sha = manifest.get("romSha1")
raise SystemExit(0 if isinstance(sha, str) and len(sha) == 40 else 1)
PY
}

ensure_manifests() {
  MANIFESTS="$(manifest_paths)"
  [ -n "$MANIFESTS" ] \
    || fail "could not read any manifest path out of src/core/GameVersion.lua"
  local rel staged
  for rel in $MANIFESTS; do
    if manifest_is_valid "$ROOT/$rel"; then continue; fi
    warn "$rel is missing or invalid; recovering it before packaging"
    staged="$(mktemp)"
    if git -C "$ROOT" show "HEAD:$rel" > "$staged" 2>/dev/null \
        && manifest_is_valid "$staged"; then
      mkdir -p "$ROOT/$(dirname "$rel")"
      mv "$staged" "$ROOT/$rel"
      say "restored $rel from this checkout's Git data"
      continue
    fi

    if command -v curl >/dev/null 2>&1 \
        && curl --fail --location --retry 2 --connect-timeout 15 \
            --output "$staged" "$MANIFEST_BASE_URL/$rel" \
        && manifest_is_valid "$staged"; then
      mkdir -p "$ROOT/$(dirname "$rel")"
      mv "$staged" "$ROOT/$rel"
      say "downloaded $rel from the project repository"
      continue
    fi

    rm -f "$staged"
    fail "$rel is unavailable: Git recovery failed and $MANIFEST_BASE_URL/$rel could not be downloaded"
  done
  say "import manifests: $MANIFESTS"
}

archive_list() {
  local archive="$1"
  if command -v unzip >/dev/null 2>&1; then
    unzip -Z1 "$archive"
    return
  fi
  python3 - "$archive" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], "r") as zf:
    for name in zf.namelist():
        print(name)
PY
}

archive_read_entry() {
  local archive="$1"
  local entry="$2"
  if command -v unzip >/dev/null 2>&1; then
    unzip -p "$archive" "$entry"
    return
  fi
  python3 - "$archive" "$entry" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], "r") as zf:
    sys.stdout.buffer.write(zf.read(sys.argv[2]))
PY
}

archive_update_entry_from_file() {
  local archive="$1"
  local entry="$2"
  local src_file="$3"
  if command -v zip >/dev/null 2>&1; then
    local stage
    stage="$(mktemp -d)"
    mkdir -p "$stage/$(dirname "$entry")"
    cp "$src_file" "$stage/$entry"
    (cd "$stage" && zip -q "$archive" "$entry")
    rm -rf "$stage"
    return
  fi
  python3 - "$archive" "$entry" "$src_file" <<'PY'
import pathlib, sys, tempfile, zipfile
archive, entry, src = sys.argv[1], sys.argv[2], sys.argv[3]
data = pathlib.Path(src).read_bytes()
archive_path = pathlib.Path(archive)
tmp_fd, tmp_name = tempfile.mkstemp(suffix=".zip", dir=str(archive_path.parent))
pathlib.Path(tmp_name).unlink(missing_ok=True)

with zipfile.ZipFile(archive_path, "r") as src_zip, \
   zipfile.ZipFile(tmp_name, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as dst_zip:
  for info in src_zip.infolist():
    if info.filename == entry:
      continue
    dst_zip.writestr(info, src_zip.read(info.filename))
  dst_zip.writestr(entry, data)

pathlib.Path(tmp_name).replace(archive_path)
PY
}

pack_love_archive() {
  local archive="$1"
  local root="$2"
  local manifests="$3"

  if command -v zip >/dev/null 2>&1; then
    # shellcheck disable=SC2086  # manifests is a deliberate word list
    # NO mods/ here, deliberately.  Adding it shipped eleven bundled mods to
    # Android for the first time -- the launcher enables a bundled mod by
    # default, so the app booted, loaded a mod set that had never run on that
    # platform, and died about a second in with no Lua error reaching the
    # handler.  0.7.5 shipped no mods and boots; this restores that exactly.
    # Re-add only after the bundled mods are known to load on device, one at
    # a time (see mobile/ANDROID.md).
    # tools/map-editor RIDES WITH tools/save-editor, which is not obvious from
    # the names: the map editor is the save editor's shell (App.lua) plus a
    # directory of panels it requires by path. Shipping one without the other
    # gives Android a map editor whose every tool fails its pcall, so the rail
    # prunes itself empty and the editor opens with nothing in it. This list
    # was the only packer that had them apart -- scripts/pack_love.sh carries
    # both, and its own header records that the map editor was missed there
    # once already.
    (cd "$root" && zip -q -9 -r "$archive" \
      main.lua conf.lua src data assets tools/save-editor tools/map-editor \
      $manifests \
      -x '*.DS_Store' -x '*/.git/*' -x '*/.DS_Store' \
      -x 'data/generated/*' -x 'assets/generated/*')
    return
  fi

  python3 - "$root" "$archive" "$manifests" <<'PY'
import fnmatch
import os
import pathlib
import sys
import zipfile

root = pathlib.Path(sys.argv[1]).resolve()
archive = pathlib.Path(sys.argv[2])
manifest_words = [w for w in sys.argv[3].split() if w]
# mods/ intentionally absent -- see the note on the zip path above.
includes = ["main.lua", "conf.lua", "src", "data", "assets",
            "tools/save-editor", "tools/map-editor", *manifest_words]
excludes = ["*.DS_Store", "*/.DS_Store", "*/.git/*", "data/generated/*", "assets/generated/*"]

def excluded(rel: str) -> bool:
    rel = rel.replace("\\", "/")
    return any(fnmatch.fnmatch(rel, pat) for pat in excludes)

paths = []
for item in includes:
    path = (root / item).resolve()
    if not path.exists():
        continue
    if path.is_file():
        rel = path.relative_to(root).as_posix()
        if not excluded(rel):
            paths.append(rel)
        continue
    for base, dirs, files in os.walk(path):
        base_path = pathlib.Path(base)
        dirs[:] = [d for d in dirs if d != ".git"]
        for name in files:
            rel = (base_path / name).relative_to(root).as_posix()
            if not excluded(rel):
                paths.append(rel)

paths = sorted(dict.fromkeys(paths))
archive.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
    for rel in paths:
        zf.write(root / rel, rel)
PY
}

# --------------------------------------------------------------- branding
# love-android 11.5+ reads app id / name / orientation from gradle.properties.
# Manifest still gets permission trims. Re-applied every build so refreshing
# the vendored love-android tree does not lose project settings.
apply_android_branding() {
  local props="$ANDROID_DIR/gradle.properties"
  local manifest="$ANDROID_DIR/app/src/main/AndroidManifest.xml"
  [ -f "$props" ] || fail "missing $props"
  [ -f "$manifest" ] || fail "missing $manifest"

  say "applying Android branding (gradle.properties + permission trim)"

  # Detect if running on Windows (Git Bash) or Linux/macOS
  local is_windows=false
  if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
    is_windows=true
  fi

  if [ "$is_windows" = true ]; then
    local win_props
    local win_manifest
    win_props="$(git_bash_to_windows_path "$props")"
    win_manifest="$(git_bash_to_windows_path "$manifest")"

    py - "$win_props" "$APPLICATION_ID" "$APP_NAME" "$VERSION" "$VERSION_CODE" <<'PY'
import pathlib, re, sys
path = pathlib.Path(sys.argv[1])
app_id, name, version, version_code = sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
text = path.read_text()

def set_prop(text, key, value):
    pat = re.compile(rf"(?m)^{re.escape(key)}=.*$")
    line = f"{key}={value}"
    if pat.search(text):
        return pat.sub(line, text)
    return text.rstrip() + "\n" + line + "\n"

# Prefer plain app.name; clear byte-array form so it cannot win.
text = re.sub(r"(?m)^app\.name_byte_array=.*\n?", "", text)
text = set_prop(text, "app.name", name)
text = set_prop(text, "app.application_id", app_id)
text = set_prop(text, "app.orientation", "fullUser")
if version:
    text = set_prop(text, "app.version_name", version)
    text = set_prop(text, "app.version_code", version_code)
path.write_text(text)
PY

    py - "$win_manifest" <<'PY'
import pathlib, re, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()

# Drop mic / legacy storage, not needed by this game.
# Keep VIBRATE (love.system.vibrate), BLUETOOTH (optional gamepads) and
# INTERNET: link play is not offline-only any more, and stripping INTERNET
# made every LAN host and every relay connect fail with EPERM (issue #287).
# Orientation / label come from gradle.properties placeholders.
for perm in (
    "android.permission.RECORD_AUDIO",
    "android.permission.WRITE_EXTERNAL_STORAGE",
):
    text = re.sub(
        rf'\s*<uses-permission android:name="{re.escape(perm)}"[^/]*/>\s*',
        "\n",
        text,
    )
text = re.sub(r'\s*android:usesCleartextTraffic="true"', "", text)
path.write_text(text)
PY
  else
    # Linux/macOS - use native paths
    python3 - "$props" "$APPLICATION_ID" "$APP_NAME" "$VERSION" "$VERSION_CODE" <<'PY'
import pathlib, re, sys
path = pathlib.Path(sys.argv[1])
app_id, name, version, version_code = sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
text = path.read_text()

def set_prop(text, key, value):
    pat = re.compile(rf"(?m)^{re.escape(key)}=.*$")
    line = f"{key}={value}"
    if pat.search(text):
        return pat.sub(line, text)
    return text.rstrip() + "\n" + line + "\n"

# Prefer plain app.name; clear byte-array form so it cannot win.
text = re.sub(r"(?m)^app\.name_byte_array=.*\n?", "", text)
text = set_prop(text, "app.name", name)
text = set_prop(text, "app.application_id", app_id)
text = set_prop(text, "app.orientation", "fullUser")
if version:
    text = set_prop(text, "app.version_name", version)
    text = set_prop(text, "app.version_code", version_code)
path.write_text(text)
PY

    python3 - "$manifest" <<'PY'
import pathlib, re, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()

# Drop mic / legacy storage, not needed by this game.
# Keep VIBRATE (love.system.vibrate), BLUETOOTH (optional gamepads) and
# INTERNET: link play is not offline-only any more, and stripping INTERNET
# made every LAN host and every relay connect fail with EPERM (issue #287).
# Orientation / label come from gradle.properties placeholders.
for perm in (
    "android.permission.RECORD_AUDIO",
    "android.permission.WRITE_EXTERNAL_STORAGE",
):
    text = re.sub(
        rf'\s*<uses-permission android:name="{re.escape(perm)}"[^/]*/>\s*',
        "\n",
        text,
    )
text = re.sub(r'\s*android:usesCleartextTraffic="true"', "", text)
path.write_text(text)
PY
  fi
}

# --------------------------------------------------------------- game.love
pack_game_love() {
  say "packing game.love for love-android embed flavor"
  mkdir -p "$EMBED_ASSETS"
  rm -f "$LOVE_FILE"
  
  # Detect if running on Windows (Git Bash) or Linux/macOS
  local is_windows=false
  if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
    is_windows=true
  fi
  
  if [ "$is_windows" = true ]; then
    # Use PowerShell for compression since zip is not available on Windows
    powershell -Command "
      \$ProgressPreference = 'SilentlyContinue'
      Set-Location '$WIN_ROOT'
      \$files = @(
        'main.lua', 'conf.lua', 'src', 'data', 'assets', 'tools', 'bundlemods'
      )
      \$excludePatterns = @(
        '*.DS_Store', '*/.git/*', '*/.DS_Store', 'data/generated/*', 'assets/generated/*',
        '*/__pycache__/*', '*.pyc', '*/.pytest_cache/*'
      )
      
      # Get all files recursively with relative paths
      \$allFiles = @()
      foreach (\$file in \$files) {
        if (Test-Path \$file) {
          if (Test-Path \$file -PathType Leaf) {
            \$allFiles += @{ Path = \$file; Relative = \$file }
          } else {
            Get-ChildItem -Path \$file -Recurse -File | ForEach-Object {
              \$relative = \$_.FullName.Replace((Get-Location).Path + '\', '').Replace('\', '/')
              \$allFiles += @{ Path = \$_.FullName; Relative = \$relative }
            }
          }
        }
      }
      
      # Filter out excluded files
      \$filteredFiles = @()
      foreach (\$fileInfo in \$allFiles) {
        \$exclude = \$false
        \$relativePath = \$fileInfo.Relative
        foreach (\$pattern in \$excludePatterns) {
          if (\$relativePath -like \$pattern) {
            \$exclude = \$true
            break
          }
        }
        if (-not \$exclude) {
          \$filteredFiles += \$fileInfo
        }
      }
      
      # Create directory if it doesn't exist
      if (-not (Test-Path '$WIN_EMBED_ASSETS')) {
        New-Item -ItemType Directory -Path '$WIN_EMBED_ASSETS' -Force | Out-Null
      }
      
      # Create zip archive using .NET to preserve directory structure
      Add-Type -AssemblyName System.IO.Compression.FileSystem
      \$tempZip = '$WIN_LOVE_FILE.zip'
      if (Test-Path \$tempZip) { Remove-Item \$tempZip }
      \$zip = [System.IO.Compression.ZipFile]::Open(\$tempZip, 'Create')
      
      foreach (\$fileInfo in \$filteredFiles) {
        \$entry = \$zip.CreateEntry(\$fileInfo.Relative)
        \$fs = [System.IO.File]::OpenRead(\$fileInfo.Path)
        try {
          \$es = \$entry.Open()
          try {
            \$fs.CopyTo(\$es)
          } finally {
            \$es.Dispose()
          }
        } finally {
          \$fs.Dispose()
        }
      }
      \$zip.Dispose()
      
      # Rename to .love
      Move-Item -Force \$tempZip '$WIN_LOVE_FILE'
    "
  else
    # Linux/macOS - use standard zip command
    (cd "$ROOT" && zip -q -9 -r "$LOVE_FILE" \
      main.lua conf.lua src data assets tools bundlemods \
      -x '*.DS_Store' 'data/generated/*' 'assets/generated/*' '*/__pycache__/*' '*.pyc' '*/.pytest_cache/*')
  fi
  
  # Verify the archive was created
  if [ ! -f "$LOVE_FILE" ]; then
    fail "Failed to create game.love"
  fi
  
  # Verify contents
  if [ "$is_windows" = true ]; then
    # Windows - use PowerShell for verification
    powershell -Command "
      \$ProgressPreference = 'SilentlyContinue'
      Add-Type -AssemblyName System.IO.Compression.FileSystem
      \$zip = [System.IO.Compression.ZipFile]::OpenRead('$WIN_LOVE_FILE')
      \$entries = \$zip.Entries | ForEach-Object { \$_.FullName }
      
      # Check for generated files
      \$hasGenerated = \$false
      foreach (\$entry in \$entries) {
        if (\$entry -match '^(data|assets)/generated/') {
          \$hasGenerated = \$true
          break
        }
      }
      if (\$hasGenerated) {
        Write-Host 'ERROR: game.love unexpectedly contains generated ROM data'
        exit 1
      }
      
      # Check for tools folder
      \$hasTools = \$false
      foreach (\$entry in \$entries) {
        if (\$entry -like 'tools/*') {
          \$hasTools = \$true
          break
        }
      }
      if (-not \$hasTools) {
        Write-Host 'ERROR: game.love is missing the tools folder'
        exit 1
      }
      
      \$zip.Dispose()
      Write-Host 'OK'
    " || fail "game.love validation failed"
    
    # Get file size
    file_size=$(powershell -Command "(Get-Item '$WIN_LOVE_FILE').Length")
    file_size_mb=$(powershell -Command "('{0:N2}' -f ((Get-Item '$WIN_LOVE_FILE').Length / 1MB))")
  else
    # Linux/macOS - use standard unzip for verification
    if unzip -Z1 "$LOVE_FILE" \
      | grep -Eq '^(data|assets)/generated/[^/]+|^(data|assets)/generated/.+/'; then
      fail "game.love unexpectedly contains generated ROM data"
    fi
    
    # Check for tools folder
    if ! unzip -Z1 "$LOVE_FILE" | grep -q '^tools/'; then
      fail "game.love is missing the tools folder"
    fi
    
    # Get file size
    file_size=$(stat -f%z "$LOVE_FILE" 2>/dev/null || stat -c%s "$LOVE_FILE" 2>/dev/null)
    file_size_mb=$(echo "scale=2; $file_size / 1048576" | bc)
  fi
  
  say "game.love: ${file_size_mb}MB -> $LOVE_FILE"

  # This script packs its own game.love (it does not reuse build.sh's), so it
  # stamps the release version the same way: patch a copy of Version.lua
  # (engine set to $VERSION) under a throwaway staging dir and replace the
  # entry inside the archive in place -- never the source tree. VERSION is
  # already validated as X.Y.Z above; when it is empty the packaged game keeps
  # the "0.0.0-dev" default. The stamp is read back out and the build fails if
  # it did not take.
  if printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    say "stamping engine version $VERSION into game.love"
    local stamp_dir
    stamp_dir="$(mktemp -d)"
    mkdir -p "$stamp_dir/src/core"
    sed -E "s/(engine[[:space:]]*=[[:space:]]*\")[^\"]*(\")/\1$VERSION\2/" \
      "$ROOT/src/core/Version.lua" > "$stamp_dir/src/core/Version.lua"
    
    if [ "$is_windows" = true ]; then
      # Use PowerShell to add the version file to the archive
      local win_stamp_dir
      win_stamp_dir="$(git_bash_to_windows_path "$stamp_dir")"
      
      powershell -Command "
        \$ProgressPreference = 'SilentlyContinue'
        \$tempZip = '$WIN_LOVE_FILE.tmp.zip'
        Copy-Item '$WIN_LOVE_FILE' \$tempZip
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        \$zip = [System.IO.Compression.ZipFile]::Open(\$tempZip, 'Update')
        \$entry = \$zip.Entries | Where-Object { \$_.FullName -eq 'src/core/Version.lua' }
        if (\$entry) {
          \$entry.Delete()
        }
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(\$zip, '$win_stamp_dir/src/core/Version.lua', 'src/core/Version.lua') | Out-Null
        \$zip.Dispose()
        Move-Item -Force \$tempZip '$WIN_LOVE_FILE'
      "
      
      # Verify the version stamp
      powershell -Command "
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        \$zip = [System.IO.Compression.ZipFile]::OpenRead('$WIN_LOVE_FILE')
        \$entry = \$zip.Entries | Where-Object { \$_.FullName -eq 'src/core/Version.lua' }
        if (\$entry) {
          \$stream = \$entry.Open()
          \$reader = New-Object System.IO.StreamReader(\$stream)
          \$content = \$reader.ReadToEnd()
          \$reader.Close()
          \$stream.Close()
          if (\$content -match 'engine[[:space:]]*=[[:space:]]*\"$VERSION\"') {
            Write-Host 'OK'
          } else {
            Write-Host 'ERROR: version stamp failed'
            exit 1
          }
        } else {
          Write-Host 'ERROR: Version.lua not found in archive'
          exit 1
        }
        \$zip.Dispose()
      " || fail "version stamp failed: game.love does not report engine $VERSION"
    else
      # Linux/macOS - use standard zip to update the archive
      (cd "$stamp_dir" && zip -q "$LOVE_FILE" src/core/Version.lua)
      
      # Verify the version stamp
      version_re="$(printf '%s' "$VERSION" | sed 's/\./\\./g')"
      unzip -p "$LOVE_FILE" src/core/Version.lua \
        | grep -Eq "engine[[:space:]]*=[[:space:]]*\"$version_re\"" \
        || fail "version stamp failed: game.love does not report engine $VERSION"
    fi
    
    rm -rf "$stamp_dir"
    say "stamped engine version: $VERSION"
  else
    say "no X.Y.Z --version,  shipping default engine (no stamp)"
  fi
}

# --------------------------------------------------------------- SDK check
require_android_sdk() {
  local sdk="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
  
  # Check if running in CI environment (GitHub Actions, etc.)
  local is_ci=false
  if [ -n "${CI:-}" ] || [ -n "${GITHUB_ACTIONS:-}" ] || [ -n "${CONTINUOUS_INTEGRATION:-}" ]; then
    is_ci=true
  fi
  
  # For local builds, use hardcoded path
  if [ "$is_ci" = false ]; then
    sdk="C:/Android/android-sdk"
  fi
  
  if [ -z "$sdk" ]; then
    for candidate in \
      "$HOME/Library/Android/sdk" \
      "$HOME/Android/Sdk" \
      /usr/local/lib/android/sdk; do
      if [ -d "$candidate" ]; then
        sdk="$candidate"
        break
      fi
    done
  fi

  if [ -z "$sdk" ] || [ ! -d "$sdk" ]; then
    fail "Android SDK not found.
  Install Android Studio (or command-line tools), then either:
    export ANDROID_SDK_ROOT=\$HOME/Library/Android/sdk
  or create mobile/android/local.properties with:
    sdk.dir=/path/to/Android/sdk
  love-android $LOVE_ANDROID_VERSION expects SDK API 34 and NDK $NDK_VERSION
  (see mobile/ANDROID.md)."
  fi

  export ANDROID_SDK_ROOT="$sdk"
  export ANDROID_HOME="$sdk"

  local props="$ANDROID_DIR/local.properties"
  # Always rewrite so a leftover Docker sdk.dir=/opt/android-sdk cannot stick.
  printf 'sdk.dir=%s\n' "$sdk" > "$props"

  if ! command -v java >/dev/null 2>&1; then
    fail "java not found. Install JDK 17 (Android Studio's bundled JDK is fine)."
  fi

  if [ ! -d "$sdk/ndk/$NDK_VERSION" ]; then
    warn "NDK $NDK_VERSION not found under $sdk/ndk/"
    warn "Install via SDK Manager (Show Package Details → NDK $NDK_VERSION)."
  fi
}

# --------------------------------------------------------------- gradle
run_gradle() {
  local task="assembleEmbedNoRecordDebug"
  local build_dir="$ANDROID_DIR"

  # ndk-build is GNU make underneath and cannot cope with spaces anywhere in
  # the project path ("Your APP_BUILD_SCRIPT points to an unknown file").
  # When this checkout lives at a spaced path (e.g. "~/xCode Projects/..."),
  # shadow the android tree to a space-free location and build there; the
  # shadow persists across runs so gradle/ndk builds stay incremental.
  case "$ANDROID_DIR" in
    *" "*)
      build_dir="${TMPDIR:-/tmp}/Gen2Recomped-android-shadow"
      say "path contains spaces (ndk-build cannot handle them);"
      say "shadow-building in: $build_dir"
      mkdir -p "$build_dir"
      rsync -a --delete \
        --exclude=".gradle" --exclude="app/build" --exclude="love/build" \
        --exclude="local.properties" \
        "$ANDROID_DIR/" "$build_dir/"
      if [ -f "$ANDROID_DIR/local.properties" ]; then
        cp "$ANDROID_DIR/local.properties" "$build_dir/local.properties"
      fi
      ;;
  esac

  say "building APK ($task)"
  if [ -f "$build_dir/gradlew" ]; then
    # Windows checkouts can carry CRLF into gradlew and break under bash
    # with '/bin/sh^M: bad interpreter'. Normalize just before execution.
    sed -i 's/\r$//' "$build_dir/gradlew"
    # ...and they record no exec bit either, which a Linux CI runner turns
    # into './gradlew: Permission denied'.  chmod for anyone who runs the
    # wrapper by hand later; the invocation below does not rely on it.
    chmod +x "$build_dir/gradlew" 2>/dev/null || true

  # Detect if running on Windows (Git Bash) or Linux/macOS
  local is_windows=false
  if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
    is_windows=true
  fi

  if ! (
    cd "$build_dir"
    # `sh ./gradlew`, not `./gradlew`: the wrapper is a POSIX sh script (that
    # is its own shebang), so this is the identical execution and it cannot be
    # defeated by a missing mode bit at all.  The chmod above is best-effort
    # -- it is silenced because it legitimately fails on mounts that carry no
    # permission bits (Windows shares, some WSL setups) -- so the build must
    # not depend on it having worked.
    sh ./gradlew --no-daemon "$task"
  ); then
    fail "gradle $task failed.
  Packaging already wrote: $LOVE_FILE
  Common causes: missing SDK/NDK $NDK_VERSION, or JDK ≠ 17. See mobile/ANDROID.md.
  You can still iterate on the .love payload with: scripts/build_android.sh --package-only"
  fi

  local out_dir="$build_dir/app/build/outputs/apk/embedNoRecord/debug"
  if [ -d "$out_dir" ]; then
    say "APK output:"
    find "$out_dir" -name '*.apk' -exec ls -lh {} \;

    local dist_dir="$DIST/debug"
    rm -rf "$dist_dir"
    mkdir -p "$dist_dir"
    
    if [ "$is_windows" = true ]; then
      # Use PowerShell for copying to handle Windows paths
      local win_out_dir
      local win_dist_dir
      win_out_dir="$(git_bash_to_windows_path "$out_dir")"
      win_dist_dir="$(git_bash_to_windows_path "$dist_dir")"
      
      powershell -Command "
        \$ProgressPreference = 'SilentlyContinue'
        if (Test-Path '$win_out_dir') {
          Get-ChildItem -Path '$win_out_dir' -Filter '*.apk' | ForEach-Object {
            Copy-Item -Path \$_.FullName -Destination '$win_dist_dir' -Force
            Write-Host \"  \$((Get-Item \$_.FullName).Length / 1MB):MB  \$_.Name\"
          }
        }
      "
    else
      # Linux/macOS - use standard cp
      cp "$out_dir"/*.apk "$dist_dir/"
    fi
    say "copied to $dist_dir/"
  else
    warn "gradle finished but no APK dir at $out_dir,  check gradle logs above"
  fi
}

# --------------------------------------------------------------- main
apply_android_branding
pack_game_love

if $PACKAGE_ONLY; then
  say "package-only: skipping gradle (game.love + branding ready under mobile/android/)"
  exit 0
fi

require_android_sdk
run_gradle
say "done"
