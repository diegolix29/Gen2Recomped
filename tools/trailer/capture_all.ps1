# tools/trailer/capture_all.ps1 -- record every trailer shot for every game.
#
#   powershell -ExecutionPolicy Bypass -File tools/trailer/capture_all.ps1 -Out G:\trailer-footage
#
# Each game is one LOVE run of tools/trailer/capture.lua (see its header). The
# voxel mod must be installed in the identity's data folder and enabled; every
# shot is recorded with it on. Output: <Out>\<version>_<shot>.mp4, streamed
# straight into ffmpeg (-Format png writes image sequences instead).
param(
  [string]$Out = "G:\Gen2Recomped\trailer_footage",
  [string]$Identity = "trailer_cap",
  [string]$Love = "C:\Program Files\LOVE\love.exe",
  [string[]]$Versions = @("crystal", "firered", "emerald", "platinum"),
  [int]$Voxel = 4,
  [string]$Only = "",
  [string]$Ffmpeg = "G:\Tools\ffmpeg-9.0.2-essentials_build\bin\ffmpeg.exe",
  [string]$Format = "mp4"
)
$ErrorActionPreference = "Stop"
$repo = Resolve-Path (Join-Path $PSScriptRoot "..\..")
New-Item -ItemType Directory -Force $Out | Out-Null

foreach ($v in $Versions) {
  Write-Host "=== $v ==="
  $env:OUT = $Out.Replace("\", "/")
  $env:VOXEL = "$Voxel"
  $env:ONLY = $Only
  $env:FFMPEG = $Ffmpeg
  $env:FORMAT = $Format
  $env:POKEPORT_IDENTITY = $Identity
  $env:POKEPORT_VERSION = $v
  $env:POKEPORT_DRIVER = "tools/trailer/capture.lua"
  Remove-Item Env:POKEPORT_NO_MODS -ErrorAction SilentlyContinue
  $log = Join-Path $Out "$v.log"
  Push-Location $repo
  try {
    # love.exe is a GUI-subsystem program: `&` would not wait for it
    Start-Process -FilePath $Love -ArgumentList "." -WorkingDirectory $repo -Wait -NoNewWindow `
      -RedirectStandardOutput $log -RedirectStandardError "$log.err"
  } finally {
    Pop-Location
  }
  Select-String -Path $log -Pattern "\[driver\]" | ForEach-Object { $_.Line }
}
Write-Host "footage in $Out"
