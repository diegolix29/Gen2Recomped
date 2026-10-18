# pack-windows.ps1
$ErrorActionPreference = "Stop"

# --- edit these if needed ---
$LoveDir    = "C:\Program Files\LOVE"
$ProjectDir = "G:\Github Desktop\0.7.0\Gen2Recomped"   # ← single source of truth
$ExeName    = "Gen2Recomped.exe"
$OutZip     = Join-Path $ProjectDir "Gen2Recomped-windows.zip"
# ----------------------------

Set-Location $ProjectDir

# =========================================================
# 1. Build game.love
# =========================================================
$stage = Join-Path $env:TEMP "g2love-pack"
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item $stage -ItemType Directory | Out-Null

Copy-Item main.lua, conf.lua $stage
# Keep local Windows packages consistent with CI/mobile payloads.
if (Test-Path -LiteralPath "cloud_clients.lua") {
    Copy-Item -LiteralPath "cloud_clients.lua" -Destination $stage
} else {
    Write-Warning "No cloud_clients.lua: cloud sign-in is unavailable in this package."
}
Copy-Item -Recurse src, data, assets $stage

# Strip generated ROM caches
Remove-Item "$stage\data\generated" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "$stage\assets\generated" -Recurse -Force -ErrorAction SilentlyContinue

# Tools needed at runtime
New-Item "$stage\tools" -ItemType Directory | Out-Null
Copy-Item -Recurse tools\save-editor "$stage\tools\"

Copy-Item -Recurse tools\map-editor "$stage\tools\"

# Every ROM manifest in the tree (one per cartridge, Gen 1 to Gen 5), not a
# hand-written list that stopped at Crystal
$manifests = Get-ChildItem tools -Filter "rom_manifest*.json"
if (-not $manifests) { throw "No tools\rom_manifest*.json found" }
foreach ($m in $manifests) { Copy-Item $m.FullName "$stage\tools\" }

# THE BUNDLED MODS (scripts\bundled_mods.txt) -- DRAMATIC SHAPES ships with
# every release -- without their development material
New-Item "$stage\mods" -ItemType Directory | Out-Null
$bundled = Get-Content "scripts\bundled_mods.txt" |
    ForEach-Object { ($_ -replace '#.*$', '').Trim() } | Where-Object { $_ }
foreach ($mod in $bundled) {
    $src = Join-Path "mods" $mod
    if (-not (Test-Path (Join-Path $src "manifest.json"))) { throw "Missing bundled mod $src" }
    $dst = Join-Path "$stage\mods" $mod
    Copy-Item -Recurse $src $dst
    foreach ($dev in @("tests", "tools", "oxr", ".git")) {
        Remove-Item (Join-Path $dst $dev) -Recurse -Force -ErrorAction SilentlyContinue
    }
    Get-ChildItem $dst -Recurse -File -Force |
        Where-Object { $_.Extension -eq ".zip" -or $_.Name -eq "CHANGELOG.md" -or $_.Name -like "*_PLAN.md" -or $_.Name -like ".git*" } |
        Remove-Item -Force
    Get-ChildItem $dst -Recurse -Directory -Filter "generated" | Remove-Item -Recurse -Force
}

$love = Join-Path $ProjectDir "game.love"
if (Test-Path $love) { Remove-Item $love -Force }

Compress-Archive -Path "$stage\*" -DestinationPath "$love.zip" -Force
Rename-Item "$love.zip" $love
Remove-Item $stage -Recurse -Force

Write-Host "Built: $love  ($((Get-Item $love).Length) bytes)"

# =========================================================
# 2. Fuse love.exe + game.love → Gen2Recomped.exe
# =========================================================
$LoveExe = Join-Path $LoveDir "love.exe"
$ExePath = Join-Path $ProjectDir $ExeName

if (-not (Test-Path $LoveExe)) { throw "love.exe not found: $LoveExe" }
if (-not (Test-Path $love))    { throw "game.love not found: $love" }

cmd /c "copy /b `"$LoveExe`" + `"$love`" `"$ExePath`""

if (-not (Test-Path $ExePath)) { throw "Fusion failed" }
Write-Host "Fused: $ExePath  ($((Get-Item $ExePath).Length) bytes)"

# =========================================================
# 3. Package with DLLs
# =========================================================
$packStage = Join-Path $env:TEMP "gen2recomp-win-pack"
if (Test-Path $packStage) { Remove-Item $packStage -Recurse -Force }
New-Item -ItemType Directory -Path $packStage | Out-Null

Copy-Item $ExePath -Destination (Join-Path $packStage $ExeName)
Copy-Item (Join-Path $LoveDir "*.dll") -Destination $packStage -Force

$license = Join-Path $LoveDir "license.txt"
if (Test-Path $license) {
    Copy-Item $license -Destination $packStage
}

if (Test-Path $OutZip) { Remove-Item $OutZip -Force }
Compress-Archive -Path (Join-Path $packStage "*") -DestinationPath $OutZip -Force
Remove-Item $packStage -Recurse -Force

Write-Host "OK: $OutZip"
Write-Host "Contents:"
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::OpenRead($OutZip).Entries | ForEach-Object { $_.FullName }