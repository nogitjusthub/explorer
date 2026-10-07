# Собирает веб-версию (однопоточную) в build/web. С ключом -Serve поднимает локальный сервер
# (tools/scripts/web_server.py): откройте http://127.0.0.1:8000 в браузере.
# Однопоточной сборке спец-заголовки сервера не нужны.
# Запуск: powershell -ExecutionPolicy Bypass -File tools\scripts\export_web.ps1 [-Debug] [-Serve]
param(
    [switch]$Debug,
    [switch]$Serve,
    [int]$Port = 8000
)

$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$godot = Join-Path $root "tools\godot\Godot_v4.7.2-stable_win64_console.exe"
if (-not (Test-Path $godot)) {
    Write-Host "Godot not found. Run tools\scripts\get_godot.ps1 first."
    exit 1
}
# В Windows PowerShell 5.1 stderr нативной программы не должен превращаться в прерывающую ошибку.
$ErrorActionPreference = "Continue"

$out = Join-Path $root "build\web"
New-Item -ItemType Directory -Force $out | Out-Null
& $godot --headless --path $root --import 2>&1 | Out-Null
$mode = if ($Debug) { "--export-debug" } else { "--export-release" }
& $godot --headless --path $root $mode "Web" (Join-Path $out "index.html") 2>&1 | ForEach-Object { "$_" }
if ($LASTEXITCODE -ne 0 -or -not (Test-Path (Join-Path $out "index.html"))) {
    Write-Host "Export failed"
    exit 1
}
Get-ChildItem $out | Select-Object Name, Length | Format-Table -AutoSize

if ($Serve) {
    python (Join-Path $root "tools\scripts\web_server.py") $Port
}
