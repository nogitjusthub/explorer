# Импортирует проект и запускает headless юнит-тесты.
# Запуск (из любого места): powershell -ExecutionPolicy Bypass -File tools\scripts\test.ps1 [-Filter <substring>]
param(
    [string]$Filter = ""
)

$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$godot = Join-Path $root "tools\godot\Godot_v4.7.2-stable_win64_console.exe"
if (-not (Test-Path $godot)) {
    Write-Host "Godot not found. Run tools\scripts\get_godot.ps1 first."
    exit 1
}

# В Windows PowerShell 5.1 stderr нативной программы не должен превращаться в прерывающую ошибку.
$ErrorActionPreference = "Continue"

$importLog = & $godot --headless --path $root --import 2>&1 | ForEach-Object { "$_" }
if ($LASTEXITCODE -ne 0) {
    $importLog | Write-Host
    Write-Host "Import failed (exit code $LASTEXITCODE)"
    exit 1
}

$godotArgs = @("--headless", "--path", $root, "--script", "res://tests/run_tests.gd")
if ($Filter) { $godotArgs += @("--", "--filter=$Filter") }
$output = & $godot @godotArgs 2>&1 | ForEach-Object { "$_" }
$code = $LASTEXITCODE
$output | Write-Host

if ($code -ne 0) { exit $code }
if ($output -match "SCRIPT ERROR") {
    Write-Host "Script errors detected"
    exit 1
}
exit 0
