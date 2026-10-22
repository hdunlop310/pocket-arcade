# Runs the headless test suites. Usage: powershell -File scripts/run_tests.ps1 [-Balance] [-Shots]
# Finds Godot via $env:GODOT, then PATH, then ~/Downloads. Exits 1 if any suite fails.
param([switch]$Balance, [switch]$Shots)
$ErrorActionPreference = "Continue"
$project = Split-Path -Parent $PSScriptRoot
$godot = $env:GODOT
if (-not $godot) { $godot = (Get-Command godot -ErrorAction SilentlyContinue).Source }
if (-not $godot) {
    $godot = Get-ChildItem "$env:USERPROFILE\Downloads" -Filter "Godot_v4*_console.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $godot) { Write-Error "Godot not found. Set `$env:GODOT to the console exe."; exit 2 }
Write-Host "Using $godot"
& $godot --headless --import --path $project | Out-Null
$failed = $false
foreach ($t in @("test_game", "test_hub")) {
    $out = & $godot --headless --path $project "res://tests/$t.tscn" 2>&1
    $out | Where-Object { $_ -cmatch "FAIL |failures=|SCRIPT ERROR|Parse Error" } | ForEach-Object { Write-Host $_ }
    if (-not ($out -match "failures=0")) { $failed = $true; Write-Host "$t FAILED" -ForegroundColor Red }
}
if ($Balance) { & $godot --headless --path $project res://tests/sim_balance.tscn 2>&1 | Where-Object { $_ -match "ROSTER" } }
if ($Shots) {
    $env:SHOT_DIR = Join-Path $project "shots"
    New-Item -ItemType Directory -Force $env:SHOT_DIR | Out-Null
    & $godot --path $project res://tests/screenshots.tscn 2>&1 | Where-Object { $_ -match "SHOT" }
}
if ($failed) { exit 1 }
Write-Host "All suites passed." -ForegroundColor Green
