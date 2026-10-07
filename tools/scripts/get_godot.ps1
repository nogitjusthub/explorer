# Скачивает портативный редактор Godot в tools/godot и проверяет SHA512.
# Запуск (из корня репозитория): powershell -ExecutionPolicy Bypass -File tools\scripts\get_godot.ps1
param(
    [string]$Version = "4.7.2"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"   # с прогресс-баром Invoke-WebRequest в PS 5.1 очень медленный
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$root = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$dest = Join-Path $root "tools\godot"
$base = "https://github.com/godotengine/godot-builds/releases/download/$Version-stable"
$zipName = "Godot_v$Version-stable_win64.exe.zip"
$zipPath = Join-Path $dest $zipName
$sumsPath = Join-Path $dest "SHA512-SUMS.txt"
$console = Join-Path $dest "Godot_v$Version-stable_win64_console.exe"

New-Item -ItemType Directory -Force $dest | Out-Null

Write-Host "Downloading $zipName ..."
Invoke-WebRequest "$base/$zipName" -OutFile $zipPath
Invoke-WebRequest "$base/SHA512-SUMS.txt" -OutFile $sumsPath

$line = Select-String -Path $sumsPath -Pattern ([regex]::Escape($zipName) + '$') | Select-Object -First 1
if (-not $line) { throw "Checksum for $zipName not found in SHA512-SUMS.txt" }
$expected = ($line.Line -split '\s+')[0].ToLower()
$actual = (Get-FileHash $zipPath -Algorithm SHA512).Hash.ToLower()
if ($actual -ne $expected) { throw "SHA512 mismatch for $zipName (expected $expected, got $actual)" }
Write-Host "SHA512 OK"

Expand-Archive $zipPath $dest -Force
Remove-Item $zipPath
# Self-contained режим: настройки редактора и шаблоны экспорта остаются внутри tools/godot.
New-Item -ItemType File -Force (Join-Path $dest "._sc_") | Out-Null

& $console --version
