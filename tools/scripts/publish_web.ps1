# Публикует веб-версию на GitHub Pages: собирает build/web (export_web.ps1), кладёт её в ветку gh-pages
# (отдельный worktree в build/gh-pages) и отправляет на GitHub. Страница: https://<логин>.github.io/<репозиторий>/
# Запуск (из корня репозитория, remote origin уже настроен):
#   powershell -ExecutionPolicy Bypass -File tools\scripts\publish_web.ps1
#   (в PowerShell 7: pwsh -File tools\scripts\publish_web.ps1)
param(
    [switch]$NoPush
)

$ErrorActionPreference = "Continue"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$pages = Join-Path $root "build\gh-pages"
Set-Location $root

& (Join-Path $PSScriptRoot "export_web.ps1")
if ($LASTEXITCODE -ne 0) { Write-Host "Export failed"; exit 1 }

# Ветка gh-pages живёт в отдельном worktree; первый раз — создаём (если на GitHub уже есть — берём её).
if (-not (Test-Path (Join-Path $pages ".git"))) {
    git fetch origin gh-pages 2>$null
    git show-ref --verify --quiet refs/heads/gh-pages
    if ($LASTEXITCODE -ne 0) {
        git show-ref --verify --quiet refs/remotes/origin/gh-pages
        if ($LASTEXITCODE -eq 0) { git branch gh-pages origin/gh-pages | Out-Null }
    }
    git show-ref --verify --quiet refs/heads/gh-pages
    if ($LASTEXITCODE -eq 0) { git worktree add $pages gh-pages } else { git worktree add --orphan -b gh-pages $pages }
}

# Содержимое страницы — ровно свежая сборка (.nojekyll — чтобы GitHub отдавал файлы как есть).
Get-ChildItem $pages -Force | Where-Object { $_.Name -ne ".git" } | Remove-Item -Recurse -Force
Copy-Item (Join-Path $root "build\web\*") $pages -Recurse
New-Item -ItemType File -Force (Join-Path $pages ".nojekyll") | Out-Null

$rev = git rev-parse --short HEAD
git -C $pages add -A
git -C $pages commit -q -m "Веб-версия игры ($rev)"
if ($LASTEXITCODE -ne 0) { Write-Host "Nothing changed" }
if (-not $NoPush) {
    git -C $pages push -u origin gh-pages
}
