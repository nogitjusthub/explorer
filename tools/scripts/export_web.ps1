# Собирает веб-версию (однопоточную) в build/web. С ключом -Serve поднимает локальный сервер
# (tools/scripts/web_server.py): откройте http://127.0.0.1:8000 в браузере.
# Однопоточной сборке спец-заголовки сервера не нужны. Release собирается на своём урезанном шаблоне
# (tools/godot/templates/web_nothreads_release.zip из build_web_template.ps1), без него — на официальном.
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
# Импорт ресурсов перед экспортом — до трёх попыток; не вышло — экспорт не запускаем: он собрал бы
# сборку на устаревших или неполных ресурсах. Headless Godot часто падает уже при выходе, после
# законченного импорта (access violation, 0xC0000005): это не ошибка импорта, если в выводе нет ERROR.
$imported = $false
for ($try = 1; $try -le 3 -and -not $imported; $try++) {
    $importLog = & $godot --headless --path $root --import 2>&1 | ForEach-Object { "$_" }
    $code = $LASTEXITCODE
    $errors = @($importLog | Where-Object { $_ -match '(^|\s)(SCRIPT )?ERROR:' })
    $crashOnExit = ($code -eq -1073741819) -and ($errors.Count -eq 0)
    $imported = ($code -eq 0) -or $crashOnExit
    if ($crashOnExit) { Write-Host "Import done (Godot crashed on exit, ignored)" }
    if (-not $imported) {
        Write-Host "Import failed (exit code $code), attempt $try of 3"
        $errors | Select-Object -First 5 | ForEach-Object { Write-Host "  $_" }
    }
}
if (-not $imported) {
    Write-Host "Import failed - export aborted"
    exit 1
}

# Release-экспорт идёт на своём урезанном шаблоне: custom_template/release в export_presets.cfg,
# собирает его tools\scripts\build_web_template.ps1. Если файла нет (свежий клон) — на время экспорта
# путь в пресете очищается и берётся официальный шаблон. Debug-экспорт всегда на официальном.
$presets = Join-Path $root "export_presets.cfg"
$presetText = [IO.File]::ReadAllText($presets)
$custom = [regex]::Match($presetText, '(?m)^custom_template/release="res://([^"]+)"').Groups[1].Value
$restorePresets = $false
if (-not $Debug -and $custom) {
    if (Test-Path (Join-Path $root $custom)) {
        Write-Host "Web template: custom ($custom)"
    } else {
        Write-Host "Custom web template $custom not found - exporting with the official template (bigger .wasm)."
        Write-Host "To build it: powershell -ExecutionPolicy Bypass -File tools\scripts\build_web_template.ps1"
        $noCustom = $presetText -replace '(?m)^custom_template/release=".*"', 'custom_template/release=""'
        [IO.File]::WriteAllText($presets, $noCustom, (New-Object Text.UTF8Encoding $false))
        $restorePresets = $true
    }
}
$mode = if ($Debug) { "--export-debug" } else { "--export-release" }
try {
    & $godot --headless --path $root $mode "Web" (Join-Path $out "index.html") 2>&1 | ForEach-Object { "$_" }
    $exportCode = $LASTEXITCODE
} finally {
    if ($restorePresets) { [IO.File]::WriteAllText($presets, $presetText, (New-Object Text.UTF8Encoding $false)) }
}
if ($exportCode -ne 0 -or -not (Test-Path (Join-Path $out "index.html"))) {
    Write-Host "Export failed"
    exit 1
}
Get-ChildItem $out | Select-Object Name, Length | Format-Table -AutoSize

if ($Serve) {
    python (Join-Path $root "tools\scripts\web_server.py") $Port
}
