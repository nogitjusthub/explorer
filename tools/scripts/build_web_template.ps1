# Собирает свой, урезанный по размеру шаблон веб-экспорта Godot (release, без потоков, без GDExtension)
# и кладёт его в tools/godot/templates/web_nothreads_release.zip — его подхватывает export_web.ps1.
# Исходники Godot, emsdk и объектные файлы живут ВНЕ репозитория (по умолчанию — папка godot-web-build
# рядом с ним). Нужны git и Python 3 (SCons ставится через pip --user). Компиляция идёт на половине ядер.
# Запуск (из корня репозитория): powershell -ExecutionPolicy Bypass -File tools\scripts\build_web_template.ps1
# Ниже отключено всё, чем игра не пользуется. Если в игре появится что-то из этого (ogg/mp3, RegEx,
# физические тела, сеть, SVG, JPG, GLTF, RichTextLabel, Line2D…), включите модуль обратно (или уберите
# класс из build_web_template.gdbuild) и пересоберите шаблон — иначе в вебе этого класса просто не будет.
param(
    [string]$Version = "4.7.2",
    [string]$EmsdkVersion = "4.0.20",   # ею собран официальный шаблон 4.7.2 (см. «Build configuration» в консоли браузера)
    [string]$WorkDir = "",              # по умолчанию <папка рядом с репозиторием>\godot-web-build
    [int]$Jobs = 0,                     # 0 — половина логических ядер
    [string]$Python = "",               # путь к python.exe, если он не находится сам
    [switch]$FallbackText,              # см. ниже, у списка флагов
    [switch]$NoClassProfile             # собрать без списка отключённых классов (build_web_template.gdbuild)
)

$ErrorActionPreference = "Stop"
# Сборка долгая — пониженный приоритет, чтобы не мешать игре и бенчмаркам (компилятор его наследует).
try { (Get-Process -Id $PID).PriorityClass = "BelowNormal" } catch { }
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
if (-not $WorkDir) { $WorkDir = Join-Path (Split-Path $root -Parent) "godot-web-build" }
if ($Jobs -le 0) { $Jobs = [Math]::Max(1, [int][Math]::Floor([Environment]::ProcessorCount / 2)) }
$src = Join-Path $WorkDir "godot"
$emsdk = Join-Path $WorkDir "emsdk"
$out = Join-Path $root "tools\godot\templates\web_nothreads_release.zip"
$tag = "$Version-stable"

# Флаги сборки. Обоснования — в docs/ARCHITECTURE.md, §12 («Свой шаблон веб-экспорта»).
$flags = @(
    "platform=web", "target=template_release", "threads=no", "dlink_enabled=no",
    "production=yes", "optimize=size", "lto=full", "debug_symbols=no",
    # Физики, навигации и XR в игре нет: движение и столкновения считаются своим кодом.
    # _physics_process, Engine.get_physics_frames() и physics interpolation от этого не зависят.
    "disable_physics_2d=yes", "disable_physics_3d=yes",
    "disable_navigation_2d=yes", "disable_navigation_3d=yes", "disable_xr=yes",
    # Текст: штатный Advanced-сервер (HarfBuzz + ICU) — вывод пиксель в пиксель как у официального шаблона.
    "module_msdfgen_enabled=no",          # MSDF-шрифтов нет — только встроенный шрифт темы
    "module_svg_enabled=no",              # SVG не грузим; иконки стандартной темы (CheckBox, OptionButton…) будут пустыми
    # Картинки: нужны только PNG (в ядре) и WebP — lossless-текстуры в .ctex хранятся как WebP.
    "module_jpg_enabled=no", "module_bmp_enabled=no", "module_tga_enabled=no", "module_hdr_enabled=no",
    "module_dds_enabled=no", "module_ktx_enabled=no", "module_tinyexr_enabled=no",
    "module_basis_universal_enabled=no", "module_astcenc_enabled=no", "module_etcpak_enabled=no",
    # Звук синтезируется в AudioStreamWAV/Generator на лету; ogg/mp3 и видео нет.
    "module_ogg_enabled=no", "module_vorbis_enabled=no", "module_mp3_enabled=no",
    "module_theora_enabled=no", "module_interactive_music_enabled=no",
    # Сеть и криптография не используются.
    "module_multiplayer_enabled=no", "module_enet_enabled=no", "module_webrtc_enabled=no",
    "module_websocket_enabled=no", "module_jsonrpc_enabled=no", "module_upnp_enabled=no",
    "module_mbedtls_enabled=no",
    # Импорт 3D-сцен и узлы, которых нет в игре (меши строятся SurfaceTool без LOD/simplify).
    "module_gltf_enabled=no", "module_fbx_enabled=no", "module_csg_enabled=no",
    "module_gridmap_enabled=no", "module_meshoptimizer_enabled=no",
    # Прочее: RegEx, VisualShader (шейдеры — только .gdshader), ZIPReader/ZIPPacker.
    "module_regex_enabled=no", "module_visual_shader_enabled=no", "module_zip_enabled=no"
)
# -FallbackText: Fallback-сервер вместо HarfBuzz + ICU — ещё −0,5 МБ gzip, кириллица работает, но глифы
# мелкого шрифта встают на другие доли пикселя (иначе выглядят скобки «[A]», чуть другие пробелы).
if ($FallbackText) { $flags += @("module_text_server_adv_enabled=no", "module_text_server_fb_enabled=yes") }
# Классы, которых нет ни в скриптах, ни в сценах и ресурсах игры (лишние GUI-контролы, AnimationTree,
# TileMap, 2D-узлы, GPU-частицы, Decal/VoxelGI/Lightmap, небо, аудиоэффекты…) — список в
# build_web_template.gdbuild. Godot их не регистрирует, LTO выкидывает код: ещё около −1 МБ gzip.
# Понадобился такой класс — уберите его из списка и пересоберите (-NoClassProfile — собрать без списка).
if (-not $NoClassProfile) { $flags += "build_profile=" + (Join-Path $PSScriptRoot "build_web_template.gdbuild") }

# Python: явный путь, потом py-лаунчер, потом python из PATH (заглушку Microsoft Store отсекаем проверкой).
function Find-Python {
    if ($Python) { return $Python }
    foreach ($cand in @("py -3", "python", "python3")) {
        try {
            $parts = $cand -split ' '
            $exe = $parts[0]; $rest = @($parts | Select-Object -Skip 1)   # всегда массив: строка «склеилась» бы по буквам
            $p = & $exe @rest -c "import sys; print(sys.executable)" 2>$null
            if ($LASTEXITCODE -eq 0 -and $p -and (Test-Path $p)) { return $p.Trim() }
        } catch { }
    }
    throw "Python 3 not found. Pass -Python <path to python.exe>."
}
$py = Find-Python
Write-Host "Python: $py"
Write-Host "Work dir: $WorkDir (jobs: $Jobs)"
New-Item -ItemType Directory -Force $WorkDir | Out-Null

# Нативные программы пишут прогресс в stderr — в PS 5.1 это не должно прерывать скрипт.
$ErrorActionPreference = "Continue"

# 1. Исходники Godot ровно на нужном теге.
if (-not (Test-Path (Join-Path $src ".git"))) {
    git clone --depth 1 --branch $tag https://github.com/godotengine/godot.git $src
    if ($LASTEXITCODE -ne 0) { throw "git clone failed" }
} else {
    $cur = git -C $src describe --tags --exact-match 2>$null
    if ($cur -ne $tag) {
        git -C $src fetch --depth 1 origin tag $tag
        git -C $src checkout -q $tag
        if ($LASTEXITCODE -ne 0) { throw "Cannot checkout $tag in $src" }
    }
}

# 2. Emscripten SDK нужной версии.
if (-not (Test-Path (Join-Path $emsdk ".git"))) {
    git clone https://github.com/emscripten-core/emsdk.git $emsdk
    if ($LASTEXITCODE -ne 0) { throw "git clone emsdk failed" }
} else {
    git -C $emsdk pull -q
}
& $py (Join-Path $emsdk "emsdk.py") install $EmsdkVersion
if ($LASTEXITCODE -ne 0) { throw "emsdk install $EmsdkVersion failed" }
& $py (Join-Path $emsdk "emsdk.py") activate $EmsdkVersion | Out-Null
if ($LASTEXITCODE -ne 0) { throw "emsdk activate $EmsdkVersion failed" }
& (Join-Path $emsdk "emsdk_env.ps1") | Out-Null   # emcc и прочее — в PATH этого процесса
Set-StrictMode -Off                               # emsdk_env.ps1 включает StrictMode
# emcc.bat, а не emcc.ps1; первый запуск после установки печатает ещё и «sanity checks» — ищем строку версии.
$emccVersion = (& emcc.bat --version 2>$null | Out-String) -split "`r?`n" | Where-Object { $_ -match '^emcc ' } | Select-Object -First 1
Write-Host "emcc: $emccVersion"
if ("$emccVersion" -notmatch [regex]::Escape($EmsdkVersion)) { throw "emcc $EmsdkVersion is not active" }

# 3. SCons.
& $py -m SCons --version 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    & $py -m pip install --user scons
    if ($LASTEXITCODE -ne 0) { throw "pip install scons failed" }
}

# 4. Сборка.
$sw = [Diagnostics.Stopwatch]::StartNew()
Push-Location $src
try {
    & $py -m SCons "-j$Jobs" @flags 2>&1 | ForEach-Object { "$_" }
    $code = $LASTEXITCODE
} finally {
    Pop-Location
}
$sw.Stop()
if ($code -ne 0) { throw "SCons failed (exit $code)" }
$zip = Get-ChildItem (Join-Path $src "bin") -Filter "godot.web.template_release.wasm32*.zip" |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $zip) { throw "Template zip not found in $src\bin" }

New-Item -ItemType Directory -Force (Split-Path $out -Parent) | Out-Null
Copy-Item $zip.FullName $out -Force
Write-Host ("Built {0} in {1:N0} min -> {2} ({3:N1} MB)" -f $zip.Name, $sw.Elapsed.TotalMinutes, $out, ((Get-Item $out).Length / 1MB))
