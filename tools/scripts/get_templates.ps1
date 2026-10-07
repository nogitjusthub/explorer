# Скачивает шаблоны экспорта Godot, проверяет SHA512 и ставит только нужные (веб без потоков)
# в self-contained каталог редактора: tools/godot/editor_data/export_templates/<версия>.stable/
# Запуск (из корня репозитория): powershell -ExecutionPolicy Bypass -File tools\scripts\get_templates.ps1
param(
    [string]$Version = "4.7.2",
    [string[]]$Templates = @("web_nothreads_debug.zip", "web_nothreads_release.zip")
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"   # с прогресс-баром Invoke-WebRequest в PS 5.1 очень медленный
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.IO.Compression.FileSystem

$root = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$godotDir = Join-Path $root "tools\godot"
$base = "https://github.com/godotengine/godot-builds/releases/download/$Version-stable"
$tpzName = "Godot_v$Version-stable_export_templates.tpz"
$tpzPath = Join-Path $godotDir $tpzName
$sumsPath = Join-Path $godotDir "SHA512-SUMS.txt"
$dest = Join-Path $godotDir "editor_data\export_templates\$Version.stable"

if (-not (Test-Path $sumsPath)) {
    Invoke-WebRequest "$base/SHA512-SUMS.txt" -OutFile $sumsPath
}

Write-Host "Downloading $tpzName ..."
Invoke-WebRequest "$base/$tpzName" -OutFile $tpzPath

$line = Select-String -Path $sumsPath -Pattern ([regex]::Escape($tpzName) + '$') | Select-Object -First 1
if (-not $line) { throw "Checksum for $tpzName not found in SHA512-SUMS.txt" }
$expected = ($line.Line -split '\s+')[0].ToLower()
$actual = (Get-FileHash $tpzPath -Algorithm SHA512).Hash.ToLower()
if ($actual -ne $expected) { throw "SHA512 mismatch for $tpzName" }
Write-Host "SHA512 OK"

New-Item -ItemType Directory -Force $dest | Out-Null
$wanted = @("version.txt") + $Templates
$zip = [System.IO.Compression.ZipFile]::OpenRead($tpzPath)
try {
    foreach ($entry in $zip.Entries) {
        if ($wanted -contains $entry.Name) {
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, (Join-Path $dest $entry.Name), $true)
            Write-Host "  installed $($entry.Name)"
        }
    }
} finally {
    $zip.Dispose()
}
Remove-Item $tpzPath
Get-ChildItem $dest | Select-Object Name, Length
